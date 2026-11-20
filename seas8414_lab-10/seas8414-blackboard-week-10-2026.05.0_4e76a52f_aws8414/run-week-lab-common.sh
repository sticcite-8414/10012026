#!/usr/bin/env bash
set -Eeuo pipefail

PHASE="${PHASE:?PHASE must be set by the week wrapper}"
WEEK="${WEEK:?WEEK must be set by the week wrapper}"
LAB_TITLE="${LAB_TITLE:-SEAS-8414 Lab}"

RELEASE_SLUG="${RELEASE_SLUG:-2026.05.0_4e76a52f_aws8414}"
RELEASE_ID="${RELEASE_ID:-2026.05.0+4e76a52f.aws8414}"
OUTER_ZIP="${OUTER_ZIP:-seas8414-blackboard-week-${WEEK}-${RELEASE_SLUG}.zip}"
OUTER_DIR="${OUTER_DIR:-seas8414-blackboard-week-${WEEK}-${RELEASE_SLUG}}"
RUNTIME_ZIP="${RUNTIME_ZIP:-runtime/seas8414-student-lab-${RELEASE_ID}.zip}"
RUNTIME_DIR="${RUNTIME_DIR:-seas8414-student-lab-${RELEASE_ID}}"
RESULTS_REL="${RESULTS_REL:-lab-results/week-${WEEK}}"
EVIDENCE_REL="$RESULTS_REL/evidence"
SUBNET="${SUBNET:-172.30.0.0/24}"
API_BASE="${API_BASE:-http://localhost:8100}"
EMAIL="${EMAIL:-student@example.com}"
PASSWORD="${PASSWORD:-SecurePass!2026}"
SCAN_INTERVAL="${SCAN_INTERVAL:-15}"
SCAN_POLLS="${SCAN_POLLS:-80}"
KEEP_LAB="${KEEP_LAB:-0}"
DRY_RUN="${DRY_RUN:-0}"
ALLOW_REMEDIATION_EXECUTE="${ALLOW_REMEDIATION_EXECUTE:-0}"

ROOT_DIR="$(pwd)"
LAB_DIR="$OUTER_DIR/$RUNTIME_DIR/student-lab"
TOKEN=""
SCAN_ID="${SCAN_ID:-}"
REPORT_TITLE="Week ${WEEK}: ${LAB_TITLE}"

case "$ROOT_DIR" in
  /tmp/*|/private/tmp/*)
    if [ "$(uname -s)" = "Darwin" ]; then
      cat >&2 <<EOF
Do not run this Docker lab from /tmp on macOS.

Docker Desktop and Colima can reject bind mounts from temporary directories.
Create a normal working directory, then rerun:

  mkdir -p "\$HOME/seas8414-week${WEEK}"
  cd "\$HOME/seas8414-week${WEEK}"
  # Use the launcher supplied in the extracted Blackboard package.
  echo "Use the locally extracted Week ${WEEK} Blackboard package and run make week${WEEK}."
EOF
      exit 1
    fi
    ;;
esac

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

log() {
  printf '\n[%s] %s\n' "$(date -u +%H:%M:%SZ)" "$*"
}

json_escape() {
  python3 - "$1" <<'PY'
import json
import sys
print(json.dumps(sys.argv[1]))
PY
}

detect_layout() {
  if [ -f "$RUNTIME_ZIP" ] && [ -d "lab" ]; then
    OUTER_DIR="."
    LAB_DIR="$RUNTIME_DIR/student-lab"
  elif [ -f "docker-compose.yml" ] && [ -f "wait-for-lab.sh" ]; then
    OUTER_DIR="."
    LAB_DIR="."
  fi
}

download_and_extract() {
  need curl
  need unzip
  need jq
  need python3
  need docker

  if ! docker compose version >/dev/null 2>&1; then
    echo "Docker Compose v2 is required: docker compose version failed" >&2
    exit 1
  fi

  detect_layout

  if [ "$OUTER_DIR" = "." ] && [ "$LAB_DIR" = "." ]; then
    log "Using current student-lab directory"
  elif [ "$OUTER_DIR" = "." ]; then
    log "Using current Blackboard package directory"
  elif [ ! -f "$OUTER_ZIP" ]; then
    echo "ERROR: Local Blackboard ZIP not found: $OUTER_ZIP" >&2
    echo "Extract the complete Week ${WEEK} Blackboard package; no download will be attempted." >&2
    exit 1
  else
    log "Using existing $OUTER_ZIP"
  fi

  if [ "$OUTER_DIR" = "." ]; then
    :
  elif [ ! -d "$OUTER_DIR" ]; then
    log "Extracting Blackboard ZIP"
    unzip -q "$OUTER_ZIP"
  else
    log "Using existing $OUTER_DIR"
  fi

  if [ "$LAB_DIR" != "." ] && [ ! -d "$OUTER_DIR/$RUNTIME_DIR" ]; then
    log "Extracting nested student runtime ZIP"
    (cd "$OUTER_DIR" && unzip -q "$RUNTIME_ZIP")
  fi

  if [ ! -d "$LAB_DIR" ]; then
    echo "Expected lab directory not found: $LAB_DIR" >&2
    echo "Note: the package uses student-lab, not students-labs." >&2
    exit 1
  fi
  LAB_DIR="$(cd "$LAB_DIR" && pwd)"
}

cleanup() {
  local run_status=$?
  local cleanup_status=0
  if [ "$KEEP_LAB" = "1" ] || [ "$DRY_RUN" = "1" ]; then
    exit "$run_status"
  fi
  if [ -d "$LAB_DIR" ]; then
    log "Cleaning up Docker Compose lab stack"
    (cd "$LAB_DIR" && docker compose down -v --remove-orphans) >"$LAB_DIR/$EVIDENCE_REL/99-compose-down.txt" 2>&1 || cleanup_status=$?
    (
      cd "$LAB_DIR"
      python3 - "$run_status" "$cleanup_status" >"$EVIDENCE_REL/99-cleanup-status.json" <<'PY'
import json
import sys

run_status = int(sys.argv[1])
cleanup_status = int(sys.argv[2])
json.dump(
    {
        "workflow_exit_code": run_status,
        "cleanup_exit_code": cleanup_status,
        "cleanup_passed": cleanup_status == 0,
        "containers_decommissioned": cleanup_status == 0,
    },
    sys.stdout,
    indent=2,
)
sys.stdout.write("\n")
PY
      write_html_report || true
    )
  fi
  exit "$run_status"
}
trap cleanup EXIT

wait_for_api() {
  mkdir -p "$EVIDENCE_REL"
  log "Waiting for lab readiness"
  if [ -x "./wait-for-lab.sh" ]; then
    ./wait-for-lab.sh 2>&1 | tee "$EVIDENCE_REL/00-wait-for-lab.txt"
  else
    for _ in $(seq 1 60); do
      if curl -fsS "$API_BASE/health" >"$EVIDENCE_REL/00-health.json" 2>/dev/null; then
        break
      fi
      sleep 2
    done
  fi
  curl -fsS "$API_BASE/health" >"$EVIDENCE_REL/00-health.json"
  docker compose ps >"$EVIDENCE_REL/00-compose-ps-start.txt"
}

auth_token() {
  local register_json login_json token
  register_json="$(
    curl -s -X POST "$API_BASE/v1/auth/register" \
      -H "Content-Type: application/json" \
      -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"full_name\":\"Lab Student\"}" || true
  )"
  printf '%s\n' "$register_json" >"$EVIDENCE_REL/01-auth-register.json"
  token="$(printf '%s\n' "$register_json" | jq -r '.access_token // empty' 2>/dev/null || true)"

  if [ -z "$token" ] || [ "$token" = "null" ]; then
    login_json="$(
      curl -s -X POST "$API_BASE/v1/auth/login" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" || true
    )"
    printf '%s\n' "$login_json" >"$EVIDENCE_REL/01-auth-login.json"
    token="$(printf '%s\n' "$login_json" | jq -r '.access_token // empty' 2>/dev/null || true)"
  fi

  if [ -z "$token" ] || [ "$token" = "null" ]; then
    echo "Could not obtain API token" >&2
    exit 1
  fi

  TOKEN="$token"
  echo "Token acquired for $EMAIL" >"$EVIDENCE_REL/01-auth.txt"
}

api_get_required() {
  local path="$1"
  local output="$2"
  curl -fsS "$API_BASE$path" -H "Authorization: Bearer $TOKEN" >"$output"
}

api_get_optional() {
  local path="$1"
  local output="$2"
  local status
  status="$(curl -sS -w '%{http_code}' -o "$output" "$API_BASE$path" -H "Authorization: Bearer $TOKEN" || true)"
  echo "$status" >"${output}.status"
  if [ "$status" -lt 200 ] || [ "$status" -ge 300 ]; then
    printf '{"skipped":true,"http_status":%s,"path":%s}\n' "$status" "$(json_escape "$path")" >"$output"
    return 1
  fi
  return 0
}

api_post_json() {
  local path="$1"
  local body="$2"
  local output="$3"
  local status
  status="$(curl -sS -w '%{http_code}' -o "$output" -X POST "$API_BASE$path" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    -d "$body" || true)"
  echo "$status" >"${output}.status"
  if [ "$status" -lt 200 ] || [ "$status" -ge 300 ]; then
    return 1
  fi
  return 0
}

start_scan() {
  local output="$1"
  api_post_json "/v1/scanning/smart-scan" "{\"subnet\":\"$SUBNET\"}" "$output"
  jq -r '.scan_id // empty' "$output"
}

wait_scan() {
  local scan_id="$1"
  local label="$2"
  local status="queued"

  : >"$EVIDENCE_REL/${label}-poll.log"
  for ((i = 1; i <= SCAN_POLLS; i++)); do
    status="$(
      curl -sf "$API_BASE/v1/scanning/smart-scan/$scan_id/results" \
        -H "Authorization: Bearer $TOKEN" |
        jq -r '.status // .progress.phase // "queued"' 2>/dev/null || echo queued
    )"
    printf '%s poll %d: %s\n' "$label" "$i" "$status" | tee -a "$EVIDENCE_REL/${label}-poll.log"
    case "$status" in
      completed) return 0 ;;
      failed) return 1 ;;
    esac
    sleep "$SCAN_INTERVAL"
  done

  echo "$label timed out with status $status" >&2
  return 1
}

resolve_scan() {
  if [ -n "$SCAN_ID" ]; then
    echo "SCAN_ID=$SCAN_ID" >"$EVIDENCE_REL/02-selected-scan.txt"
    return 0
  fi

  if [ -f "lab-results/week-01/evidence/scan-ids.txt" ]; then
    SCAN_ID="$(grep '^SCAN_ID=' lab-results/week-01/evidence/scan-ids.txt | tail -1 | cut -d= -f2- || true)"
  fi

  if [ -z "$SCAN_ID" ]; then
    api_get_optional "/v1/scanning/smart-scan/history?limit=1" "$EVIDENCE_REL/02-scan-history.json" || true
    SCAN_ID="$(jq -r '.scans[0].scan_id // .data[0].scan_id // .[0].scan_id // empty' "$EVIDENCE_REL/02-scan-history.json" 2>/dev/null || true)"
  fi

  if [ -z "$SCAN_ID" ] || [ "$SCAN_ID" = "null" ]; then
    log "No reusable scan found; starting a full smart scan"
    SCAN_ID="$(start_scan "$EVIDENCE_REL/02-start-smart-scan.json")"
    if [ -z "$SCAN_ID" ] || [ "$SCAN_ID" = "null" ]; then
      echo "Could not start smart scan" >&2
      exit 1
    fi
    wait_scan "$SCAN_ID" "02-smart-scan"
  fi

  api_get_required "/v1/scanning/smart-scan/$SCAN_ID/results" "$EVIDENCE_REL/02-scan-results.json"
  echo "SCAN_ID=$SCAN_ID" >"$EVIDENCE_REL/02-selected-scan.txt"
  jq '{scan_id, status, hosts:(.hosts // [] | length), duration_seconds}' "$EVIDENCE_REL/02-scan-results.json" >"$EVIDENCE_REL/02-scan-summary.json" || true
}

write_summary_json() {
  local extra="${1:-{}}"
  python3 - "$WEEK" "$PHASE" "$LAB_TITLE" "$SCAN_ID" "$extra" >"$EVIDENCE_REL/summary.json" <<'PY'
import datetime
import json
import sys

week, phase, title, scan_id, extra_raw = sys.argv[1:6]
try:
    extra = json.loads(extra_raw)
except json.JSONDecodeError:
    extra = {"raw": extra_raw}

json.dump(
    {
        "week": week,
        "phase": int(phase),
        "title": title,
        "scan_id": scan_id,
        "generated_at": datetime.datetime.now(datetime.UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "extra": extra,
    },
    sys.stdout,
    indent=2,
)
sys.stdout.write("\n")
PY
}

write_run_metadata() {
  python3 - "$WEEK" "$PHASE" "$LAB_TITLE" "$API_BASE" "$SUBNET" "$OUTER_ZIP" "$RUNTIME_DIR" >"$EVIDENCE_REL/00-run-metadata.json" <<'PY'
import datetime
import json
import os
import platform
import sys

week, phase, title, api_base, subnet, outer_zip, runtime_dir = sys.argv[1:8]
json.dump(
    {
        "week": week,
        "phase": int(phase),
        "title": title,
        "api_base": api_base,
        "subnet": subnet,
        "outer_zip": outer_zip,
        "runtime_dir": runtime_dir,
        "generated_at": datetime.datetime.now(datetime.UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "host_platform": platform.platform(),
        "working_directory": os.getcwd(),
    },
    sys.stdout,
    indent=2,
)
sys.stdout.write("\n")
PY
}

write_command_plan() {
  cat >"$EVIDENCE_REL/00-command-plan.md" <<EOF
# Week ${WEEK} Command Plan

Runner invocation:

\`\`\`bash
make week${WEEK}
# or
./run-week${WEEK}-lab.sh
\`\`\`

Environment:

- API base: \`${API_BASE}\`
- Subnet: \`${SUBNET}\`
- Runtime directory: \`${RUNTIME_DIR}/student-lab\`

Core commands executed:

\`\`\`bash
docker compose up -d
./wait-for-lab.sh
curl ${API_BASE}/health
POST ${API_BASE}/v1/auth/register
POST ${API_BASE}/v1/auth/login
GET ${API_BASE}/v1/scanning/smart-scan/history?limit=1
POST ${API_BASE}/v1/scanning/smart-scan
GET ${API_BASE}/v1/scanning/smart-scan/\$SCAN_ID/results
docker compose down -v --remove-orphans
\`\`\`

Week-specific API and probe commands are recorded as JSON/text evidence files in this directory.
EOF
}

write_html_report() {
  local report="$RESULTS_REL/index.html"
  python3 - "$REPORT_TITLE" "$EVIDENCE_REL" "$report" <<'PY'
import html
import json
import os
import pathlib
import sys

title, evidence_rel, report = sys.argv[1:4]
evidence = pathlib.Path(evidence_rel)
files = sorted(p for p in evidence.glob("**/*") if p.is_file())

def read_json(name):
    path = evidence / name
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None

metadata = read_json("00-run-metadata.json") or {}
summary = read_json("summary.json") or {}
cleanup = read_json("99-cleanup-status.json") or {
    "cleanup_passed": False,
    "containers_decommissioned": False,
    "note": "Cleanup had not run when this report was first written.",
}

rows = []
for path in files:
    rel = path.relative_to(pathlib.Path(report).parent)
    label = path.relative_to(evidence)
    rows.append(
        f'<tr><td><a href="{html.escape(rel.as_posix())}">{html.escape(label.as_posix())}</a></td>'
        f'<td>{path.stat().st_size}</td></tr>'
    )

body = "\n".join(rows)
status = "PASS" if summary and cleanup.get("cleanup_passed") else "IN PROGRESS"
environment_rows = "\n".join(
    f"<tr><th>{html.escape(str(key))}</th><td>{html.escape(str(value))}</td></tr>"
    for key, value in {
        "Week": metadata.get("week", ""),
        "Phase": metadata.get("phase", ""),
        "Title": metadata.get("title", title),
        "API Base": metadata.get("api_base", ""),
        "Subnet": metadata.get("subnet", ""),
        "Working Directory": metadata.get("working_directory", ""),
        "Scan ID": summary.get("scan_id", ""),
    }.items()
)
pathlib.Path(report).write_text(f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>{html.escape(title)} Results</title>
  <style>
    body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 2rem; line-height: 1.45; }}
    table {{ border-collapse: collapse; width: 100%; }}
    th, td {{ border: 1px solid #ddd; padding: 0.45rem 0.6rem; text-align: left; }}
    th {{ background: #f6f7f8; }}
    code {{ background: #f6f7f8; padding: 0.1rem 0.25rem; }}
    .status {{ display: inline-block; padding: 0.2rem 0.55rem; border-radius: 0.35rem; background: #eef6ee; font-weight: 700; }}
  </style>
</head>
<body>
  <h1>{html.escape(title)} Results</h1>
  <p>Generated by the public SEAS-8414 lab runner. Evidence is stored under <code>{html.escape(evidence_rel)}</code>.</p>
  <h2>Run Status</h2>
  <p><span class="status">{html.escape(status)}</span></p>
  <ul>
    <li>Workflow exit code: {html.escape(str(cleanup.get("workflow_exit_code", "pending")))}</li>
    <li>Cleanup exit code: {html.escape(str(cleanup.get("cleanup_exit_code", "pending")))}</li>
    <li>Containers decommissioned: {html.escape(str(cleanup.get("containers_decommissioned", False)))}</li>
  </ul>
  <h2>Environment Summary</h2>
  <table><tbody>{environment_rows}</tbody></table>
  <h2>Commands Run</h2>
  <p>The exact runner command plan is captured in <a href="evidence/00-command-plan.md">00-command-plan.md</a>. Raw command output and API responses are linked below.</p>
  <h2>Evidence Links</h2>
  <table>
    <thead><tr><th>Evidence File</th><th>Bytes</th></tr></thead>
    <tbody>{body}</tbody>
  </table>
</body>
</html>
""", encoding="utf-8")
PY
}

docker_exec_capture() {
  local output="$1"
  shift
  docker compose exec -T api "$@" >"$output" 2>&1 || true
}

run_week02() {
  log "Collecting Week 02 service enrichment evidence"
  jq '[.hosts[]? | {ip, hostname, vendor, model, services, cpes, open_ports}]' "$EVIDENCE_REL/02-scan-results.json" >"$EVIDENCE_REL/week02-compact-hosts.json" || true
  jq '[.hosts[]? | keys] | add | unique' "$EVIDENCE_REL/02-scan-results.json" >"$EVIDENCE_REL/week02-host-schema-keys.json" || true
  jq '[.hosts[]? | select((.open_ports // []) | index(80) or index(443) or index(8080)) | {ip, hostname, vendor, open_ports, services}]' "$EVIDENCE_REL/02-scan-results.json" >"$EVIDENCE_REL/week02-web-hosts.json" || true
  jq '[.hosts[]? | select(((.open_ports // []) | index(554)) or ((.vendor // "") | test("hikvision|dahua|axis"; "i"))) | {ip, hostname, vendor, model, cpes, services}]' "$EVIDENCE_REL/02-scan-results.json" >"$EVIDENCE_REL/week02-camera-like-hosts.json" || true
  jq '[.hosts[]? | {ip, services, open_ports}]' "$EVIDENCE_REL/02-scan-results.json" >"$EVIDENCE_REL/week02-all-services.json" || true
  jq '.hosts[]? | select(.ip == "172.30.0.10") | {ip, hostname, vendor, model, cpes, services}' "$EVIDENCE_REL/02-scan-results.json" >"$EVIDENCE_REL/week02-hikvision-host-cpes.json" || true
  docker_exec_capture "$EVIDENCE_REL/week02-nmap-172.30.0.10.txt" nmap -sV -Pn -p 80,554,8000 172.30.0.10
  for ip in 172.30.0.10 172.30.0.11 172.30.0.12; do
    docker_exec_capture "$EVIDENCE_REL/week02-http-headers-${ip}.txt" curl -sI "http://${ip}/"
  done
  docker_exec_capture "$EVIDENCE_REL/week02-rtsp-probe.txt" python - <<'PY'
import socket
for ip in ["172.30.0.10", "172.30.0.11", "172.30.0.12"]:
    try:
        s = socket.create_connection((ip, 554), timeout=3)
        s.sendall(b"OPTIONS rtsp://%b/ RTSP/1.0\r\nCSeq: 1\r\n\r\n" % ip.encode())
        print(ip, s.recv(256).decode(errors="replace").strip())
        s.close()
    except Exception as exc:
        print(ip, type(exc).__name__, exc)
PY
  for container in hikvision-camera dahua-nvr axis-camera; do
    docker inspect "student-lab-${container}-1" --format '{{range .NetworkSettings.Networks}}{{.MacAddress}}{{end}}' >"$EVIDENCE_REL/week02-mac-${container}.txt" 2>&1 || true
  done
}

run_week03() {
  log "Collecting Week 03 vulnerability evidence"
  jq '[.hosts[]? | {ip, vendor, model, cpes, vulnerabilities, cve_summary, nuclei_findings, openvas_findings, default_creds}]' "$EVIDENCE_REL/02-scan-results.json" >"$EVIDENCE_REL/week03-vulnerability-host-view.json" || true
  api_post_json "/v1/cves/lookup" '{"vendor":"hikvision","product":"camera","limit":50}' "$EVIDENCE_REL/week03-cve-lookup-broad.json" || true
  api_post_json "/v1/cves/lookup" '{"cpe":"cpe:2.3:o:hikvision:ip_camera_firmware:*:*:*:*:*:*:*:*","limit":50}' "$EVIDENCE_REL/week03-cve-lookup-narrow.json" || true
  api_get_optional "/v1/cves/search?keyword=hikvision&limit=20" "$EVIDENCE_REL/week03-cve-search-hikvision.json" || true
  jq '[.hosts[]? | select(((.vendor // "") | test("hikvision"; "i")) or (.ip == "172.30.0.10")) | {ip, cpes, vulnerabilities, cve_summary}]' "$EVIDENCE_REL/02-scan-results.json" >"$EVIDENCE_REL/week03-hikvision-scan-cves.json" || true
  jq '{cve_summary:[.hosts[]?.cve_summary?] | length, nuclei:[.hosts[]?.nuclei_findings?] | length, openvas:[.hosts[]?.openvas_findings?] | length, default_creds:[.hosts[]?.default_creds?] | length}' "$EVIDENCE_REL/02-scan-results.json" >"$EVIDENCE_REL/week03-multi-tool-evidence.json" || true
  jq '[.hosts[]? | select(((.vulnerabilities // []) | length) == 0) | {ip, vendor, model}]' "$EVIDENCE_REL/02-scan-results.json" >"$EVIDENCE_REL/week03-zero-finding-hosts.json" || true
  jq '[.hosts[]? | select((.default_creds // []) | length > 0) | {ip, default_creds}]' "$EVIDENCE_REL/02-scan-results.json" >"$EVIDENCE_REL/week03-default-creds-from-scan.json" || true
  docker_exec_capture "$EVIDENCE_REL/week03-default-credential-probe.txt" curl -s -u admin:admin "http://172.30.0.10/"
  docker_exec_capture "$EVIDENCE_REL/week03-device-info-172.30.0.10.txt" curl -s "http://172.30.0.10/system/deviceInfo"
  docker_exec_capture "$EVIDENCE_REL/week03-nuclei-172.30.0.10.txt" sh -lc 'timeout 45 nuclei -u http://172.30.0.10 -severity high,critical -silent -j || true'
}

run_week04() {
  log "Collecting Week 04 attack graph analytics evidence"
  api_get_optional "/v1/analytics/graph/$SCAN_ID" "$EVIDENCE_REL/week04-graph.json" || true
  api_get_optional "/v1/analytics/attack-paths/$SCAN_ID" "$EVIDENCE_REL/week04-attack-paths.json" || true
  for ip in 172.30.0.30 172.30.0.11; do api_get_optional "/v1/analytics/attack-paths/$SCAN_ID?target_ip=$ip" "$EVIDENCE_REL/week04-attack-paths-${ip}.json" || true; done
  api_get_optional "/v1/analytics/brs/$SCAN_ID" "$EVIDENCE_REL/week04-brs.json" || true
  for ip in 172.30.0.10 172.30.0.30 172.30.0.32; do api_get_optional "/v1/analytics/brs/$SCAN_ID?ip=$ip" "$EVIDENCE_REL/week04-brs-${ip}.json" || true; done
  for ip in 172.30.0.10 172.30.0.32; do api_get_optional "/v1/analytics/blast-radius/$SCAN_ID?source_ip=$ip" "$EVIDENCE_REL/week04-blast-radius-${ip}.json" || true; done
  api_get_optional "/v1/analytics/segmentation/$SCAN_ID" "$EVIDENCE_REL/week04-segmentation.json" || true
  api_get_optional "/v1/analytics/mitre/$SCAN_ID" "$EVIDENCE_REL/week04-mitre.json" || true
  api_get_optional "/v1/analytics/mitre/$SCAN_ID/stix" "$EVIDENCE_REL/week04-stix-bundle.json" || true
  api_get_optional "/v1/analytics/behavioral/$SCAN_ID" "$EVIDENCE_REL/week04-behavioral.json" || true
  api_get_optional "/v1/analytics/threat-intel/$SCAN_ID" "$EVIDENCE_REL/week04-threat-intel.json" || true
  for ip in 172.30.0.10 172.30.0.30 172.30.0.22; do api_get_optional "/v1/analytics/timeline/$SCAN_ID?ip=$ip" "$EVIDENCE_REL/week04-timeline-${ip}.json" || true; done
}

run_week05() {
  log "Collecting Week 05 autonomous pentest evidence"
  api_post_json "/v1/pentest/run" "{\"scan_id\":\"$SCAN_ID\",\"mode\":\"simulation\",\"max_actions\":100,\"agent_type\":\"rule\"}" "$EVIDENCE_REL/week05-campaign-simulation-rule.json" || true
  api_post_json "/v1/pentest/run" "{\"scan_id\":\"$SCAN_ID\",\"mode\":\"shadow\",\"max_actions\":100,\"agent_type\":\"rule\"}" "$EVIDENCE_REL/week05-campaign-shadow-rule.json" || true
  api_post_json "/v1/pentest/run" "{\"scan_id\":\"$SCAN_ID\",\"mode\":\"controlled\",\"max_actions\":100,\"agent_type\":\"rule\",\"target_ips\":[\"172.30.0.10\",\"172.30.0.11\"]}" "$EVIDENCE_REL/week05-campaign-controlled-rule.json" || true
  api_get_optional "/v1/pentest/mitre-coverage/$SCAN_ID" "$EVIDENCE_REL/week05-mitre-coverage.json" || true
  for file in "$EVIDENCE_REL"/week05-campaign-*.json; do
    [ -f "$file" ] || continue
    campaign="$(jq -r '.data.campaign_id // .campaign_id // empty' "$file" 2>/dev/null || true)"
    [ -n "$campaign" ] || continue
    api_get_optional "/v1/pentest/$campaign/timeline" "$EVIDENCE_REL/week05-timeline-${campaign}.json" || true
    api_get_optional "/v1/pentest/$campaign/evidence" "$EVIDENCE_REL/week05-evidence-${campaign}.json" || true
    api_get_optional "/v1/pentest/$campaign/report" "$EVIDENCE_REL/week05-report-${campaign}.json" || true
  done
}

run_week06() {
  log "Collecting Week 06 digital twin evidence"
  api_post_json "/v1/twin/deploy/$SCAN_ID" '{"auto_scenario":false}' "$EVIDENCE_REL/week06-twin-deploy.json" || true
  twin="$(jq -r '.data.twin_id // .twin_id // empty' "$EVIDENCE_REL/week06-twin-deploy.json" 2>/dev/null || true)"
  if [ -z "$twin" ]; then
    echo '{"skipped":true,"reason":"twin deployment did not return a twin_id"}' >"$EVIDENCE_REL/week06-summary-skip.json"
    return
  fi
  api_get_optional "/v1/twin/$twin/status" "$EVIDENCE_REL/week06-twin-status.json" || true
  api_get_optional "/v1/twin/scan/$SCAN_ID" "$EVIDENCE_REL/week06-twin-scan.json" || true
  api_post_json "/v1/twin/$twin/scenario" '{"name":"credentialed_camera_attack","entry_ip":"172.30.0.10","target_ip":"172.30.0.30"}' "$EVIDENCE_REL/week06-scenario-1.json" || true
  api_post_json "/v1/twin/$twin/scenario" '{"name":"credentialed_camera_attack","entry_ip":"172.30.0.10","target_ip":"172.30.0.30"}' "$EVIDENCE_REL/week06-scenario-2.json" || true
  api_get_optional "/v1/twin/$twin/cascades" "$EVIDENCE_REL/week06-cascades.json" || true
  api_post_json "/v1/twin/$twin/replay-traffic" '{"protocol":"http","source_ip":"172.30.0.10","target_ip":"172.30.0.30"}' "$EVIDENCE_REL/week06-replay-http.json" || true
  api_post_json "/v1/twin/$twin/replay-traffic" '{"protocol":"rtsp","source_ip":"172.30.0.10","target_ip":"172.30.0.11"}' "$EVIDENCE_REL/week06-replay-rtsp.json" || true
  api_get_optional "/v1/twin/$twin/risk-comparison" "$EVIDENCE_REL/week06-risk-comparison.json" || true
}

run_week07() {
  log "Collecting Week 07 post-quantum readiness evidence"
  api_get_optional "/v1/quantum/$SCAN_ID" "$EVIDENCE_REL/week07-quantum-scorecard.json" || true
  api_get_optional "/v1/quantum/$SCAN_ID/hndl" "$EVIDENCE_REL/week07-hndl.json" || true
  api_get_optional "/v1/quantum/$SCAN_ID/certs" "$EVIDENCE_REL/week07-certs.json" || true
  api_get_optional "/v1/quantum/$SCAN_ID/migration" "$EVIDENCE_REL/week07-migration.json" || true
  api_get_optional "/v1/quantum/$SCAN_ID/hydra" "$EVIDENCE_REL/week07-hydra.json" || true
  api_get_optional "/v1/quantum/$SCAN_ID/hndl?ip=172.30.0.10" "$EVIDENCE_REL/week07-hndl-172.30.0.10.json" || true
  api_get_optional "/v1/quantum/$SCAN_ID/certs?ip=172.30.0.30" "$EVIDENCE_REL/week07-certs-172.30.0.30.json" || true
}

run_week08() {
  log "Collecting Week 08 federated threat intelligence evidence"
  api_get_optional "/v1/federated/$SCAN_ID/train" "$EVIDENCE_REL/week08-train.json" || true
  api_get_optional "/v1/federated/$SCAN_ID/signals" "$EVIDENCE_REL/week08-signals.json" || true
  api_get_optional "/v1/federated/$SCAN_ID/privacy" "$EVIDENCE_REL/week08-privacy.json" || true
  api_post_json "/v1/federated/aggregate" '{"min_sites":1}' "$EVIDENCE_REL/week08-aggregate.json" || true
  api_get_optional "/v1/federated/$SCAN_ID/model" "$EVIDENCE_REL/week08-model.json" || true
  api_get_optional "/v1/federated/$SCAN_ID/threats" "$EVIDENCE_REL/week08-threats.json" || true
}

run_week09() {
  log "Collecting Week 09 supply chain integrity evidence"
  api_get_optional "/v1/supply-chain/$SCAN_ID" "$EVIDENCE_REL/week09-supply-chain-summary.json" || true
  api_get_optional "/v1/supply-chain/$SCAN_ID/counterfeit" "$EVIDENCE_REL/week09-counterfeit.json" || true
  api_get_optional "/v1/supply-chain/$SCAN_ID/firmware" "$EVIDENCE_REL/week09-firmware.json" || true
  api_get_optional "/v1/supply-chain/$SCAN_ID/vendors" "$EVIDENCE_REL/week09-vendors.json" || true
  api_get_optional "/v1/supply-chain/$SCAN_ID/compliance" "$EVIDENCE_REL/week09-compliance.json" || true
  component="$(jq -r '.data.analyses[]?.sbom_data.components[]?.name // empty' "$EVIDENCE_REL/week09-supply-chain-summary.json" 2>/dev/null | head -1 || true)"
  if [ -n "$component" ]; then
    api_post_json "/v1/supply-chain/$SCAN_ID/simulate" "{\"target_component\":\"$component\",\"n_simulations\":1000,\"propagation_prob\":0.85}" "$EVIDENCE_REL/week09-simulate.json" || true
  else
    echo '{"skipped":true,"reason":"No SBOM component available for Monte Carlo simulation"}' >"$EVIDENCE_REL/week09-simulate-skipped.json"
  fi
}

run_week10() {
  log "Collecting Week 10 deception evidence"
  api_post_json "/v1/deception/$SCAN_ID/deploy" '{"max_honeypots":10,"protocols":["ssh","telnet","http"],"session_timeout":300}' "$EVIDENCE_REL/week10-deploy.json" || true
  api_get_optional "/v1/deception/$SCAN_ID" "$EVIDENCE_REL/week10-deception-summary.json" || true
  api_get_optional "/v1/deception/$SCAN_ID/deployments" "$EVIDENCE_REL/week10-deployments.json" || true
  api_get_optional "/v1/deception/$SCAN_ID/sessions" "$EVIDENCE_REL/week10-sessions.json" || true
  session="$(jq -r '.data.sessions[0].session_id // .sessions[0].session_id // empty' "$EVIDENCE_REL/week10-sessions.json" 2>/dev/null || true)"
  if [ -n "$session" ]; then
    api_get_optional "/v1/deception/$SCAN_ID/replay/$session" "$EVIDENCE_REL/week10-session-replay.json" || true
    api_get_optional "/v1/deception/$SCAN_ID/evidence/$session/export" "$EVIDENCE_REL/week10-session-evidence-export.json" || true
  else
    echo '{"skipped":true,"reason":"No deception session available for replay/export"}' >"$EVIDENCE_REL/week10-session-skipped.json"
  fi
  api_get_optional "/v1/deception/$SCAN_ID/analytics" "$EVIDENCE_REL/week10-analytics.json" || true
}

run_week11() {
  log "Collecting Week 11 formal verification evidence"
  api_get_optional "/v1/formal/$SCAN_ID" "$EVIDENCE_REL/week11-formal-summary.json" || true
  api_get_optional "/v1/formal/results?scan_id=$SCAN_ID" "$EVIDENCE_REL/week11-formal-results.json" || true
  device="$(jq -r '.data.results[0].device_ip // .results[0].device_ip // empty' "$EVIDENCE_REL/week11-formal-results.json" 2>/dev/null || true)"
  if [ -n "$device" ]; then
    api_get_optional "/v1/formal/$SCAN_ID/$device" "$EVIDENCE_REL/week11-formal-device.json" || true
    api_get_optional "/v1/formal/results/$device?scan_id=$SCAN_ID" "$EVIDENCE_REL/week11-formal-device-compat.json" || true
  else
    echo '{"skipped":true,"reason":"No device-level formal result available"}' >"$EVIDENCE_REL/week11-device-skipped.json"
  fi
  api_get_optional "/v1/formal/traces?scan_id=$SCAN_ID" "$EVIDENCE_REL/week11-formal-traces.json" || true
  api_get_optional "/v1/formal/conformance?scan_id=$SCAN_ID" "$EVIDENCE_REL/week11-formal-conformance.json" || true
}

run_week12() {
  log "Collecting Week 12 remediation evidence"
  api_post_json "/v1/remediation/$SCAN_ID/plan" '{"approval_mode":"manual","include_firmware":true,"include_credentials":true,"include_segmentation":true}' "$EVIDENCE_REL/week12-plan-create.json" || true
  plan="$(jq -r '.data.plan_id // .plan_id // empty' "$EVIDENCE_REL/week12-plan-create.json" 2>/dev/null || true)"
  api_get_optional "/v1/remediation/$SCAN_ID/plans" "$EVIDENCE_REL/week12-plans.json" || true
  if [ -n "$plan" ]; then
    api_get_optional "/v1/remediation/$SCAN_ID/plans/$plan" "$EVIDENCE_REL/week12-plan-detail.json" || true
    if [ "$ALLOW_REMEDIATION_EXECUTE" = "1" ]; then
      api_post_json "/v1/remediation/$SCAN_ID/plans/$plan/approve" "{\"approved_by\":\"$EMAIL\"}" "$EVIDENCE_REL/week12-approval.json" || true
      api_post_json "/v1/remediation/$SCAN_ID/plans/$plan/execute" '{}' "$EVIDENCE_REL/week12-execute.json" || true
      api_get_optional "/v1/remediation/$SCAN_ID/plans/$plan/status" "$EVIDENCE_REL/week12-status.json" || true
    else
      echo '{"skipped":true,"reason":"Set ALLOW_REMEDIATION_EXECUTE=1 to approve and execute the remediation plan"}' >"$EVIDENCE_REL/week12-execution-skipped.json"
    fi
  fi
  api_get_optional "/v1/remediation/$SCAN_ID/compliance" "$EVIDENCE_REL/week12-compliance.json" || true
  api_get_optional "/v1/remediation/$SCAN_ID/credentials" "$EVIDENCE_REL/week12-credentials.json" || true
  api_get_optional "/v1/remediation/$SCAN_ID/segmentation" "$EVIDENCE_REL/week12-segmentation.json" || true
  api_post_json "/v1/remediation/$SCAN_ID/export-policy" '{"format":"iptables"}' "$EVIDENCE_REL/week12-policy-iptables.json" || true
  api_post_json "/v1/remediation/$SCAN_ID/export-policy" '{"format":"cisco_acl"}' "$EVIDENCE_REL/week12-policy-cisco-acl.json" || true
}

run_phase() {
  case "$PHASE" in
    2) run_week02 ;;
    3) run_week03 ;;
    4) run_week04 ;;
    5) run_week05 ;;
    6) run_week06 ;;
    7) run_week07 ;;
    8) run_week08 ;;
    9) run_week09 ;;
    10) run_week10 ;;
    11) run_week11 ;;
    12) run_week12 ;;
    *) echo "Unsupported PHASE=$PHASE for shared runner" >&2; exit 1 ;;
  esac
}

main() {
  download_and_extract
  if [ "$DRY_RUN" = "1" ]; then
    log "Dry run passed for Week ${WEEK}; lab directory is $LAB_DIR"
    return 0
  fi

  mkdir -p "$LAB_DIR/$EVIDENCE_REL"
  cd "$LAB_DIR"
  write_run_metadata
  write_command_plan
  log "Starting Docker Compose lab stack"
  docker compose up -d --pull never --no-build 2>&1 | tee "$EVIDENCE_REL/00-compose-up.txt"
  wait_for_api
  auth_token
  resolve_scan
  run_phase
  write_summary_json '{}'
  write_html_report
  log "Report generated: $LAB_DIR/$RESULTS_REL/index.html"
}

main "$@"
