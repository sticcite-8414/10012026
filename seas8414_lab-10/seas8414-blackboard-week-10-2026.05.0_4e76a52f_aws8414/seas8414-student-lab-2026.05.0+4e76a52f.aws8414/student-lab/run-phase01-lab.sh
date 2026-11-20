#!/usr/bin/env bash
# Download, start, scan, and write a Phase 1 HTML report for the public lab.

set -euo pipefail

COURSE_URL="${COURSE_URL:-https://8414.bwater.io}"
PACKAGE_NAME="seas8414-blackboard-week-01-2026.05.0_4e76a52f_aws8414.zip"
PACKAGE_URL="${SEAS8414_PACKAGE_URL:-${COURSE_URL%/}/downloads/labs/packages/${PACKAGE_NAME}}"
WORK_DIR="${SEAS8414_LAB_WORK_DIR:-$HOME/seas8414-labs/phase01}"
API_URL="${API_URL:-http://127.0.0.1:${BREAKWATER_LAB_API_PORT:-8100}}"
SCAN_TIMEOUT="${SCAN_TIMEOUT:-900}"
SCAN_DISCOVERY="${SCAN_DISCOVERY:-1}"
OPEN_REPORT=1
CLEANUP=0
DRY_RUN=0

usage() {
    cat <<'USAGE'
Usage: ./run-phase01-lab.sh [options]

Runs the public SEAS-8414 Phase 1 lab from download through HTML report generation.

Options:
  --work-dir DIR       Directory used when the weekly ZIP must be downloaded.
  --package-url URL    Weekly ZIP URL. Defaults to the public course site.
  --api-url URL        Breakwater API URL. Defaults to http://127.0.0.1:8100.
  --timeout SECONDS    Maximum scan wait time. Defaults to 900.
  --clean              Stop containers and remove volumes after report generation.
  --no-open            Do not open the final HTML report automatically.
  --dry-run            Validate download/extraction path and print the execution plan.
  -h, --help           Show this help.

Environment:
  SCAN_DISCOVERY=1     Default for Phase 1. Set to 0 to run the full pipeline.
USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --work-dir)
            [ "$#" -ge 2 ] || { echo "missing value for --work-dir" >&2; exit 2; }
            WORK_DIR="$2"
            shift 2
            ;;
        --package-url)
            [ "$#" -ge 2 ] || { echo "missing value for --package-url" >&2; exit 2; }
            PACKAGE_URL="$2"
            shift 2
            ;;
        --api-url)
            [ "$#" -ge 2 ] || { echo "missing value for --api-url" >&2; exit 2; }
            API_URL="$2"
            shift 2
            ;;
        --timeout)
            [ "$#" -ge 2 ] || { echo "missing value for --timeout" >&2; exit 2; }
            SCAN_TIMEOUT="$2"
            shift 2
            ;;
        --clean)
            CLEANUP=1
            shift
            ;;
        --no-open)
            OPEN_REPORT=0
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
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

log() {
    printf '[phase01] %s\n' "$*" >&2
}

find_student_lab_under() {
    find "$1" -maxdepth 7 -type f -name docker-compose.yml -path '*/student-lab/docker-compose.yml' \
        -exec dirname {} \; | sort | head -n 1
}

extract_runtime_if_present() {
    base="$1"
    runtime_zip="$(find "$base" -maxdepth 4 -type f -path '*/runtime/seas8414-student-lab-*.zip' | sort | head -n 1)"
    if [ -n "$runtime_zip" ]; then
        extract_dir="$(dirname "$runtime_zip")/extracted"
        mkdir -p "$extract_dir"
        log "Extracting nested runtime ZIP: $runtime_zip"
        unzip -q -o "$runtime_zip" -d "$extract_dir"
    fi
}

locate_student_lab() {
    if [ -f "$PWD/docker-compose.yml" ] && [ -f "$PWD/phase1-lab.md" ]; then
        pwd
        return 0
    fi

    found="$(find_student_lab_under "$PWD")"
    if [ -n "$found" ]; then
        printf '%s\n' "$found"
        return 0
    fi

    extract_runtime_if_present "$PWD"
    found="$(find_student_lab_under "$PWD")"
    if [ -n "$found" ]; then
        printf '%s\n' "$found"
        return 0
    fi

    return 1
}

download_and_locate_student_lab() {
    mkdir -p "$WORK_DIR/downloads" "$WORK_DIR/extracted"
    zip_path="$WORK_DIR/downloads/$PACKAGE_NAME"
    log "Downloading weekly package: $PACKAGE_URL"
    curl -fsSL "$PACKAGE_URL" -o "$zip_path"
    log "Extracting weekly package under: $WORK_DIR/extracted"
    unzip -q -o "$zip_path" -d "$WORK_DIR/extracted"
    extract_runtime_if_present "$WORK_DIR/extracted"
    found="$(find_student_lab_under "$WORK_DIR/extracted")"
    if [ -z "$found" ]; then
        echo "error: could not find nested student-lab directory after extraction" >&2
        exit 1
    fi
    printf '%s\n' "$found"
}

open_report() {
    report="$1"
    if [ "$OPEN_REPORT" -ne 1 ]; then
        return 0
    fi
    if command -v open >/dev/null 2>&1; then
        open "$report" >/dev/null 2>&1 || true
    elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$report" >/dev/null 2>&1 || true
    fi
}

require_command curl
require_command docker
require_command python3
require_command unzip

if ! docker compose version >/dev/null 2>&1; then
    echo "error: docker compose v2 is required" >&2
    exit 127
fi

if ! [[ "$SCAN_TIMEOUT" =~ ^[0-9]+$ ]] || [ "$SCAN_TIMEOUT" -le 0 ]; then
    echo "error: --timeout must be a positive integer" >&2
    exit 2
fi

if lab_dir="$(locate_student_lab 2>/dev/null)"; then
    log "Using existing student lab: $lab_dir"
else
    lab_dir="$(download_and_locate_student_lab)"
    log "Using downloaded student lab: $lab_dir"
fi

cd "$lab_dir"
report_dir="$lab_dir/reports/phase01-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$report_dir"

if [ "$DRY_RUN" -eq 1 ]; then
    log "Dry run complete."
    log "Student lab directory: $lab_dir"
    log "Report directory: $report_dir"
    log "Would run: ./check-lab.sh, docker compose up -d, ./wait-for-lab.sh, scan, HTML report export"
    exit 0
fi

if curl -fsS "${API_URL%/}/health" >/dev/null 2>&1; then
    log "API is already reachable at ${API_URL%/}; reusing the running lab."
else
    log "Running preflight checks ..."
    ./check-lab.sh

    log "Starting lab containers ..."
    docker compose up -d
fi

log "Waiting for API and simulation readiness ..."
./wait-for-lab.sh --timeout 300 --api-url "$API_URL"

log "Running Phase 1 scan and writing report artifacts ..."
python3 - "$API_URL" "$report_dir" "$SCAN_TIMEOUT" "$SCAN_DISCOVERY" <<'PY'
from __future__ import annotations

import html
import http.client
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

api_url = sys.argv[1].rstrip("/")
report_dir = Path(sys.argv[2])
timeout_seconds = int(sys.argv[3])
discovery_only = sys.argv[4].lower() not in {"0", "false", "no"}
email = "student@example.com"
password = "SecurePass!2026"
targets = [
    "172.30.0.10", "172.30.0.11", "172.30.0.12", "172.30.0.13",
    "172.30.0.14", "172.30.0.15", "172.30.0.20", "172.30.0.21",
    "172.30.0.22", "172.30.0.23", "172.30.0.24", "172.30.0.30",
    "172.30.0.31", "172.30.0.32", "172.30.0.33", "172.30.0.40",
    "172.30.0.50", "172.30.0.51", "172.30.0.52", "172.30.0.60",
    "172.30.0.61", "172.30.0.62",
]


def call(method: str, path: str, body: dict | None = None, token: str | None = None) -> tuple[int, bytes]:
    data = None if body is None else json.dumps(body).encode("utf-8")
    headers = {"Accept": "application/json"}
    if body is not None:
        headers["Content-Type"] = "application/json"
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(api_url + path, data=data, headers=headers, method=method)
    for attempt in range(1, 6):
        try:
            with urllib.request.urlopen(request, timeout=45) as response:
                return response.status, response.read()
        except urllib.error.HTTPError as exc:
            return exc.code, exc.read()
        except (
            TimeoutError,
            ConnectionResetError,
            http.client.RemoteDisconnected,
            urllib.error.URLError,
        ) as exc:
            if attempt == 5:
                raise RuntimeError(f"{method} {path} failed after retries: {exc}") from exc
            time.sleep(min(2 * attempt, 10))


def json_call(method: str, path: str, body: dict | None = None, token: str | None = None) -> dict:
    status, payload = call(method, path, body, token)
    if status < 200 or status >= 300:
        raise RuntimeError(f"{method} {path} failed with HTTP {status}: {payload.decode('utf-8', 'replace')[:600]}")
    return json.loads(payload.decode("utf-8"))


def get_token() -> str:
    body = {"email": email, "password": password, "full_name": "Lab Student"}
    status, payload = call("POST", "/v1/auth/register", body)
    if status in (200, 201):
        return json.loads(payload.decode("utf-8"))["access_token"]
    if status == 409:
        return json_call("POST", "/v1/auth/login", {"email": email, "password": password})["access_token"]
    raise RuntimeError(f"registration failed with HTTP {status}: {payload.decode('utf-8', 'replace')[:600]}")


def write_json(name: str, payload: dict) -> Path:
    path = report_dir / name
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return path


report_dir.mkdir(parents=True, exist_ok=True)
health = json_call("GET", "/health")
token = get_token()
scan = json_call(
    "POST",
    "/v1/scanning/multi-target-scan",
    {
        "targets": targets,
        "batch_concurrency": 4,
        "discovery_only": discovery_only,
        "scan_name": "SEAS-8414 Phase 1 Runner",
    },
    token,
)
scan_id = scan["scan_id"]
deadline = time.time() + timeout_seconds
last_status = ""

while True:
    results = json_call("GET", f"/v1/scanning/smart-scan/{scan_id}/results", token=token)
    status = str(results.get("status") or "unknown")
    progress = results.get("progress") or {}
    progress_text = f"{status}: discovered={progress.get('discovered', 0)} enriched={progress.get('enriched', 0)} identified={progress.get('identified', 0)}"
    if progress_text != last_status:
        print(progress_text, flush=True)
        last_status = progress_text
    if status in {"completed", "failed", "cancelled"}:
        break
    if time.time() >= deadline:
        raise TimeoutError(f"scan {scan_id} did not finish within {timeout_seconds} seconds")
    time.sleep(5)

write_json("phase01-scan-start.json", scan)
write_json("phase01-scan-results.json", results)

if status != "completed":
    raise RuntimeError(f"scan {scan_id} ended with status {status}")

report_status, report_payload = call("GET", f"/v1/reports/{scan_id}/html", token=token)
if report_status != 200 or len(report_payload) < 500:
    raise RuntimeError(f"HTML report export failed with HTTP {report_status}; bytes={len(report_payload)}")
api_report = report_dir / "phase01-api-scan-report.html"
api_report.write_bytes(report_payload)

hosts = results.get("hosts") or []
progress = results.get("progress") or {}
summary = {
    "scan_id": scan_id,
    "status": status,
    "host_count": len(hosts),
    "progress": progress,
    "health": health,
    "api_report": api_report.name,
    "discovery_only": discovery_only,
}
write_json("phase01-run-summary.json", summary)

rows = [
    ("API URL", api_url),
    ("Scan ID", scan_id),
    ("Status", status),
    ("Hosts returned", str(len(hosts))),
    ("Discovered", str(progress.get("discovered", ""))),
    ("Enriched", str(progress.get("enriched", ""))),
    ("Identified", str(progress.get("identified", ""))),
    ("API HTML report", api_report.name),
    ("Discovery-only mode", str(discovery_only)),
]
row_html = "\n".join(
    f"<tr><th>{html.escape(k)}</th><td>{html.escape(v)}</td></tr>" for k, v in rows
)
host_rows = "\n".join(
    "<tr>"
    f"<td>{html.escape(str(host.get('ip') or host.get('ip_address') or ''))}</td>"
    f"<td>{html.escape(str(host.get('hostname') or host.get('device_type') or ''))}</td>"
    f"<td>{html.escape(str(host.get('mac') or ''))}</td>"
    f"<td>{html.escape(', '.join(str(p) for p in (host.get('open_ports') or [])))}</td>"
    "</tr>"
    for host in hosts[:80]
)
summary_html = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>SEAS-8414 Phase 1 Lab Run Report</title>
  <style>
    body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 2rem; color: #111827; line-height: 1.5; }}
    h1, h2 {{ line-height: 1.2; }}
    table {{ border-collapse: collapse; width: 100%; margin: 1rem 0 2rem; }}
    th, td {{ border: 1px solid #d1d5db; padding: 0.45rem 0.6rem; text-align: left; vertical-align: top; }}
    th {{ width: 14rem; background: #f3f4f6; }}
    code {{ background: #f3f4f6; padding: 0.1rem 0.25rem; border-radius: 4px; }}
    .ok {{ color: #166534; font-weight: 700; }}
  </style>
</head>
<body>
  <h1>SEAS-8414 Phase 1 Lab Run Report</h1>
  <p class="ok">Completed: scan finished and the Breakwater API HTML report was generated.</p>
  <h2>Run Summary</h2>
  <table>{row_html}</table>
  <h2>Artifacts</h2>
  <ul>
    <li><a href="{html.escape(api_report.name)}">Breakwater API HTML report</a></li>
    <li><a href="phase01-scan-results.json">Raw scan results JSON</a></li>
    <li><a href="phase01-run-summary.json">Run summary JSON</a></li>
  </ul>
  <h2>Returned Hosts</h2>
  <table>
    <thead><tr><th>IP</th><th>Hostname or type</th><th>MAC</th><th>Open ports</th></tr></thead>
    <tbody>{host_rows}</tbody>
  </table>
</body>
</html>
"""
summary_path = report_dir / "index.html"
summary_path.write_text(summary_html, encoding="utf-8")
print(summary_path)
PY

summary_report="$report_dir/index.html"
if [ ! -s "$summary_report" ]; then
    echo "error: expected HTML summary was not created: $summary_report" >&2
    exit 1
fi

if [ "$CLEANUP" -eq 1 ]; then
    log "Cleaning up lab containers and volumes ..."
    docker compose down -v --remove-orphans
fi

log "Phase 1 HTML report: $summary_report"
open_report "$summary_report"
