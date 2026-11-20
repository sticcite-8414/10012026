#!/usr/bin/env bash
# Validate local prerequisites and release-safe compose defaults before startup.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

API_URL="${API_URL:-http://127.0.0.1:${BREAKWATER_LAB_API_PORT:-8100}}"

usage() {
    cat <<'USAGE'
Usage: ./check-lab.sh [--timeout SECONDS] [--api-url URL]

Runs prerequisite checks and compose policy checks before `docker compose up -d`.
Use `./wait-for-lab.sh` after startup for service health.
USAGE
}

wait_args=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --timeout)
            [ "$#" -ge 2 ] || { echo "missing value for --timeout" >&2; exit 2; }
            wait_args+=("--timeout" "$2")
            shift 2
            ;;
        --api-url)
            [ "$#" -ge 2 ] || { echo "missing value for --api-url" >&2; exit 2; }
            API_URL="$2"
            wait_args+=("--api-url" "$2")
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "error: required command not found: $1" >&2
        exit 127
    fi
}

require_command curl
require_command docker
require_command python3

if ! docker compose version >/dev/null 2>&1; then
    echo "error: docker compose v2 is required" >&2
    exit 127
fi

echo "[*] Checking compose syntax ..."
docker compose config -q

echo "[*] Checking student compose does not use default builds ..."
if docker compose config --format json | python3 -c '
import json
import sys

doc = json.load(sys.stdin)
for name, svc in (doc.get("services") or {}).items():
    if "build" in svc:
        print(f"service {name}: default build is not allowed", file=sys.stderr)
        sys.exit(1)
'; then
    echo "[+] Default compose uses prebuilt images only"
fi

echo "[*] Checking API loopback bind policy ..."
docker compose config --format json | python3 -c '
import json
import sys

doc = json.load(sys.stdin)
api = (doc.get("services") or {}).get("api") or {}
ports = api.get("ports") or []
for port in ports:
    host_ip = str(port.get("host_ip") or "") if isinstance(port, dict) else ""
    published = str(port.get("published") or "") if isinstance(port, dict) else str(port)
    if host_ip not in {"127.0.0.1", "::1", "localhost"}:
        print(f"api port {published} is not bound to loopback", file=sys.stderr)
        sys.exit(1)
print("api loopback binding verified")
'

echo "[*] Checking image references ..."
images="$(docker compose config --images | sort -u)"
printf '%s\n' "$images"
if printf '%s\n' "$images" | grep -Eq 'breakwater-lab-(api|simulator)@sha256:(0{64}|1{64})'; then
    echo "error: this package contains placeholder lab-owned image digests." >&2
    echo "       It is not ready for students until public image digests are published." >&2
    exit 1
fi

echo "[*] Checking API port availability ..."
python3 - <<'PY'
import os
import socket
import sys

host = os.environ.get("BREAKWATER_LAB_BIND_ADDR", "127.0.0.1")
port = int(os.environ.get("BREAKWATER_LAB_API_PORT", "8100"))
with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    if sock.connect_ex((host, port)) == 0:
        print(f"error: {host}:{port} is already in use", file=sys.stderr)
        sys.exit(1)
print(f"{host}:{port} is available")
PY

echo "[+] Preflight checks passed."
