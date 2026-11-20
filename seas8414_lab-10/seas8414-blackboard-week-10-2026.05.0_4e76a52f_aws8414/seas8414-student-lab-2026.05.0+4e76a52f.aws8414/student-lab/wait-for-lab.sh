#!/usr/bin/env bash
# Wait until the student lab containers and API health endpoint are ready.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

API_URL="${API_URL:-http://127.0.0.1:${BREAKWATER_LAB_API_PORT:-8100}}"
TIMEOUT_SECONDS="${LAB_WAIT_TIMEOUT:-180}"
POLL_SECONDS="${LAB_WAIT_POLL:-5}"

usage() {
    cat <<'USAGE'
Usage: ./wait-for-lab.sh [--timeout SECONDS] [--api-url URL]

Environment:
  API_URL                  API health base URL. Default: http://127.0.0.1:8100
  LAB_WAIT_TIMEOUT         Maximum wait time in seconds. Default: 180
  LAB_WAIT_POLL            Poll interval in seconds. Default: 5
USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --timeout)
            [ "$#" -ge 2 ] || { echo "missing value for --timeout" >&2; exit 2; }
            TIMEOUT_SECONDS="$2"
            shift 2
            ;;
        --api-url)
            [ "$#" -ge 2 ] || { echo "missing value for --api-url" >&2; exit 2; }
            API_URL="$2"
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

if ! [[ "$TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] || [ "$TIMEOUT_SECONDS" -le 0 ]; then
    echo "error: --timeout must be a positive integer" >&2
    exit 2
fi

if ! [[ "$POLL_SECONDS" =~ ^[0-9]+$ ]] || [ "$POLL_SECONDS" -le 0 ]; then
    echo "error: LAB_WAIT_POLL must be a positive integer" >&2
    exit 2
fi

read_compose_state() {
    docker compose ps --format json 2>/dev/null | python3 -c '
import json
import sys

raw = sys.stdin.read().strip()
if not raw:
    print("no compose services are running")
    sys.exit(1)

try:
    data = json.loads(raw)
    rows = data if isinstance(data, list) else [data]
except json.JSONDecodeError:
    rows = [json.loads(line) for line in raw.splitlines() if line.strip()]

bad = []
for svc in rows:
    name = svc.get("Service") or svc.get("Name") or "unknown"
    state = (svc.get("State") or "").lower()
    health = (svc.get("Health") or "").lower()
    if state != "running":
        bad.append(f"{name}: state={state or 'unknown'}")
    elif health and health != "healthy":
        bad.append(f"{name}: health={health}")

if bad:
    print("; ".join(bad))
    sys.exit(1)

print(f"{len(rows)} services running with passing health checks")
'
}

deadline=$((SECONDS + TIMEOUT_SECONDS))
last_status=""

echo "[*] Waiting for lab services to become ready ..."
while true; do
    compose_status="$(read_compose_state 2>&1)" && compose_ready=true || compose_ready=false

    if curl -fsS "${API_URL%/}/health" >/dev/null 2>&1; then
        api_ready=true
    else
        api_ready=false
    fi

    if [ "$compose_ready" = true ] && [ "$api_ready" = true ]; then
        echo "[+] ${compose_status}"
        echo "[+] API health check passed at ${API_URL%/}/health"
        exit 0
    fi

    if [ "$api_ready" = true ]; then
        status="${compose_status}; api=healthy"
    else
        status="${compose_status}; api=waiting"
    fi

    if [ "$status" != "$last_status" ]; then
        echo "    ${status}"
        last_status="$status"
    fi

    if [ "$SECONDS" -ge "$deadline" ]; then
        echo "[!] Timed out after ${TIMEOUT_SECONDS}s waiting for the lab." >&2
        echo "    Inspect with: docker compose ps" >&2
        echo "    Logs:         docker compose logs --tail=100 api" >&2
        exit 1
    fi

    sleep "$POLL_SECONDS"
done
