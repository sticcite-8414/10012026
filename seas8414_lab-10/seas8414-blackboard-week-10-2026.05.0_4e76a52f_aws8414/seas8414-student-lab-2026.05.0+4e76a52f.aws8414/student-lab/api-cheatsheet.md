# Breakwater API Cheatsheet

Quick reference for all Breakwater API endpoints. The API runs on `http://localhost:8100` in the student lab environment.

**Base URL:** `http://localhost:8100`
**API Documentation (Swagger UI):** `http://localhost:8100/docs`

---

## Table of Contents

- [Health Check](#health-check)
- [Authentication](#authentication)
- [Scanning](#scanning)
- [Scheduled Scans](#scheduled-scans)
- [Scan History](#scan-history)
- [Baselines](#baselines)
- [Reports](#reports)
- [CVEs](#cves)
- [Fingerprints](#fingerprints)
- [Agents](#agents)
- [Firmware Intelligence](#firmware-intelligence)
- [Compliance](#compliance)

---

## Health Check

No authentication required.

### Check API Health

```
GET /health
```

```bash
curl -s http://localhost:8100/health | jq .
```

```bash
# Extract just the status
curl -s http://localhost:8100/health | jq -r '.status'
```

---

## Authentication

### Register a New User

```
POST /v1/auth/register
```

```bash
curl -s -X POST http://localhost:8100/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "student@example.com",
    "password": "SecurePass!2026",
    "full_name": "Lab Student"
  }' | jq .
```

```bash
# Capture the access token into a variable for subsequent requests
TOKEN=$(curl -s -X POST http://localhost:8100/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"student@example.com","password":"SecurePass!2026"}' \
  | jq -r '.access_token')
```

### Login

```
POST /v1/auth/login
```

```bash
curl -s -X POST http://localhost:8100/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "student@example.com",
    "password": "SecurePass!2026"
  }' | jq .
```

```bash
# Capture token from login
TOKEN=$(curl -s -X POST http://localhost:8100/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"student@example.com","password":"SecurePass!2026"}' \
  | jq -r '.access_token')
```

### Refresh Token

```
POST /v1/auth/refresh
```

```bash
curl -s -X POST http://localhost:8100/v1/auth/refresh \
  -H "Content-Type: application/json" \
  -d "{\"refresh_token\": \"$REFRESH_TOKEN\"}" | jq .
```

### Get Current User Profile

```
GET /v1/auth/me
```

```bash
curl -s http://localhost:8100/v1/auth/me \
  -H "Authorization: Bearer $TOKEN" | jq .
```

```bash
# Extract just the email and roles
curl -s http://localhost:8100/v1/auth/me \
  -H "Authorization: Bearer $TOKEN" | jq '{email, roles}'
```

### Logout (Revoke All Refresh Tokens)

```
POST /v1/auth/logout
```

```bash
curl -s -X POST http://localhost:8100/v1/auth/logout \
  -H "Authorization: Bearer $TOKEN" -w "\nHTTP Status: %{http_code}\n"
```

---

## Scanning

All scanning endpoints require authentication (`Authorization: Bearer $TOKEN`).

### Start a Progressive Scan

```
POST /v1/scanning/smart-scan
```

```bash
curl -s -X POST http://localhost:8100/v1/scanning/smart-scan \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "subnet": "172.30.0.0/24",
    "batch_concurrency": 4,
    "discovery_only": false
  }' | jq .
```

```bash
# Capture the scan ID
SCAN_ID=$(curl -s -X POST http://localhost:8100/v1/scanning/smart-scan \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"subnet":"172.30.0.0/24"}' | jq -r '.scan_id')

echo "Scan started: $SCAN_ID"
```

### Check Scan Status and Results

```
GET /v1/scanning/smart-scan/{scan_id}/results
```

```bash
curl -s http://localhost:8100/v1/scanning/smart-scan/$SCAN_ID/results \
  -H "Authorization: Bearer $TOKEN" | jq .
```

```bash
# Check progress only
curl -s http://localhost:8100/v1/scanning/smart-scan/$SCAN_ID/results \
  -H "Authorization: Bearer $TOKEN" | jq '.progress'

# Get scan status
curl -s http://localhost:8100/v1/scanning/smart-scan/$SCAN_ID/results \
  -H "Authorization: Bearer $TOKEN" | jq -r '.status'

# List all discovered hosts (IP + device type)
curl -s http://localhost:8100/v1/scanning/smart-scan/$SCAN_ID/results \
  -H "Authorization: Bearer $TOKEN" \
  | jq '.hosts[] | {ip, hostname, device_type, confidence}'

# Get vulnerability summary
curl -s http://localhost:8100/v1/scanning/smart-scan/$SCAN_ID/results \
  -H "Authorization: Bearer $TOKEN" | jq '.vulnerability_summary'

# List only hosts with default credentials
curl -s http://localhost:8100/v1/scanning/smart-scan/$SCAN_ID/results \
  -H "Authorization: Bearer $TOKEN" \
  | jq '[.hosts[] | select((.default_creds // []) | length > 0)
         | {ip, device_type, creds: [.default_creds[] | "\(.protocol):\(.username)"]}]'

# List hosts sorted by CVE count (most vulnerable first)
curl -s http://localhost:8100/v1/scanning/smart-scan/$SCAN_ID/results \
  -H "Authorization: Bearer $TOKEN" \
  | jq '[.hosts[] | {ip, device_type, total_cves: (.cve_summary.total // 0),
         critical: (.cve_summary.critical // 0)}]
       | sort_by(-.total_cves)'
```

### Get Latest Scan Results

```
GET /v1/scanning/smart-scan/latest/results
```

```bash
curl -s http://localhost:8100/v1/scanning/smart-scan/latest/results \
  -H "Authorization: Bearer $TOKEN" | jq '.vulnerability_summary'
```

### Cancel a Running Scan

```
POST /v1/scanning/smart-scan/{scan_id}/cancel
```

```bash
curl -s -X POST http://localhost:8100/v1/scanning/smart-scan/$SCAN_ID/cancel \
  -H "Authorization: Bearer $TOKEN" | jq .
```

### Stream Scan Events (Server-Sent Events)

```
GET /v1/scanning/stream/{scan_id}
```

```bash
# Stream events in real time (press Ctrl+C to stop)
curl -N http://localhost:8100/v1/scanning/stream/$SCAN_ID \
  -H "Authorization: Bearer $TOKEN"
```

### Auto-Detect Network Range

```
GET /v1/scanning/detect-range
```

```bash
curl -s http://localhost:8100/v1/scanning/detect-range \
  -H "Authorization: Bearer $TOKEN" | jq .
```

---

## Scheduled Scans

### Create a Scheduled Scan

```
POST /v1/scanning/schedules
```

```bash
curl -s -X POST http://localhost:8100/v1/scanning/schedules \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "subnet": "172.30.0.0/24",
    "cron_expression": "0 2 * * *",
    "name": "Daily IoT Scan"
  }' | jq .
```

Common cron expressions:
- `0 2 * * *` -- Daily at 2:00 AM
- `0 6 * * 1` -- Every Monday at 6:00 AM
- `0 0 1 * *` -- First day of each month at midnight
- `0 */6 * * *` -- Every 6 hours

### List All Schedules

```
GET /v1/scanning/schedules
```

```bash
curl -s http://localhost:8100/v1/scanning/schedules \
  -H "Authorization: Bearer $TOKEN" | jq '.data.schedules'
```

```bash
# List only active schedules with their next run time
curl -s http://localhost:8100/v1/scanning/schedules \
  -H "Authorization: Bearer $TOKEN" \
  | jq '.data.schedules[] | select(.is_active) | {name, subnet, cron_expression, next_run_time}'
```

### Delete (Deactivate) a Schedule

```
DELETE /v1/scanning/schedules/{scan_id}
```

```bash
curl -s -X DELETE http://localhost:8100/v1/scanning/schedules/$SCHEDULE_ID \
  -H "Authorization: Bearer $TOKEN" | jq .
```

---

## Scan History

### List Recent Scans

```
GET /v1/scanning/smart-scan/history?limit=20
```

```bash
curl -s "http://localhost:8100/v1/scanning/smart-scan/history?limit=10" \
  -H "Authorization: Bearer $TOKEN" | jq '.scans'
```

```bash
# List completed scans with host counts
curl -s "http://localhost:8100/v1/scanning/smart-scan/history?limit=10" \
  -H "Authorization: Bearer $TOKEN" \
  | jq '.scans[] | select(.status == "completed")
       | {scan_id: .scan_id[:12], subnet, hosts_discovered, duration_seconds}'
```

---

## Baselines

Baselines allow you to save a scan snapshot and compare future scans against it to detect changes.

### Save a Baseline

```
POST /v1/scanning/baseline/save
```

```bash
# First get the hosts from a completed scan
HOSTS=$(curl -s http://localhost:8100/v1/scanning/smart-scan/$SCAN_ID/results \
  -H "Authorization: Bearer $TOKEN" | jq '.hosts')

# Save as baseline
curl -s -X POST http://localhost:8100/v1/scanning/baseline/save \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d "{\"subnet\":\"172.30.0.0/24\",\"hosts\":$HOSTS}" | jq .
```

### Load a Baseline

```
GET /v1/scanning/baseline/{subnet}
```

```bash
curl -s http://localhost:8100/v1/scanning/baseline/172.30.0.0%2F24 \
  -H "Authorization: Bearer $TOKEN" | jq .
```

### Compare Scan Against Baseline

```
POST /v1/scanning/baseline/compare
```

```bash
HOSTS=$(curl -s http://localhost:8100/v1/scanning/smart-scan/$SCAN_ID/results \
  -H "Authorization: Bearer $TOKEN" | jq '.hosts')

curl -s -X POST http://localhost:8100/v1/scanning/baseline/compare \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d "{\"subnet\":\"172.30.0.0/24\",\"hosts\":$HOSTS}" | jq .
```

### List All Baselines

```
GET /v1/scanning/baselines
```

```bash
curl -s http://localhost:8100/v1/scanning/baselines \
  -H "Authorization: Bearer $TOKEN" | jq .
```

### Delete a Baseline

```
DELETE /v1/scanning/baseline/{subnet}
```

```bash
curl -s -X DELETE http://localhost:8100/v1/scanning/baseline/172.30.0.0%2F24 \
  -H "Authorization: Bearer $TOKEN" | jq .
```

---

## Reports

### Download PDF Report

```
GET /v1/reports/{scan_id}/pdf
```

```bash
curl -s http://localhost:8100/v1/reports/$SCAN_ID/pdf \
  -H "Authorization: Bearer $TOKEN" -o report.pdf

# Check file size
ls -lh report.pdf
```

### Download HTML Report

```
GET /v1/reports/{scan_id}/html
```

```bash
curl -s http://localhost:8100/v1/reports/$SCAN_ID/html \
  -H "Authorization: Bearer $TOKEN" -o report.html

# Open in browser (macOS)
open report.html
```

---

## CVEs

### Search CVEs by Keyword

```
GET /v1/cves/search?keyword={keyword}&limit={limit}
```

```bash
curl -s "http://localhost:8100/v1/cves/search?keyword=hikvision&limit=10" \
  -H "Authorization: Bearer $TOKEN" | jq .
```

```bash
# Extract just CVE IDs and scores
curl -s "http://localhost:8100/v1/cves/search?keyword=qnap&limit=5" \
  -H "Authorization: Bearer $TOKEN" \
  | jq '.[] | {cve_id, severity, cvss_score}'
```

### Get CVE Details

```
GET /v1/cves/{cve_id}
```

```bash
curl -s http://localhost:8100/v1/cves/CVE-2021-36260 \
  -H "Authorization: Bearer $TOKEN" | jq .
```

```bash
# Get description and severity
curl -s http://localhost:8100/v1/cves/CVE-2021-36260 \
  -H "Authorization: Bearer $TOKEN" | jq '{cve_id, severity, cvss_score, description}'
```

### Batch CVE Lookup for Hosts

```
POST /v1/cves/lookup
```

```bash
curl -s -X POST http://localhost:8100/v1/cves/lookup \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "hosts": [
      {
        "ip": "172.30.0.10",
        "vendor": "Hikvision",
        "model": "DS-2CD2032",
        "services": [{"port": 80, "product": "Hikvision httpd", "state": "open"}]
      }
    ]
  }' | jq '.results[] | {ip, total_cves, critical_count}'
```

---

## Fingerprints

### List Fingerprints

```
GET /v1/fingerprints?vendor={vendor}&limit={limit}&offset={offset}
```

```bash
curl -s "http://localhost:8100/v1/fingerprints?limit=20" \
  -H "Authorization: Bearer $TOKEN" | jq '.[] | {id, vendor, device_type, model}'
```

```bash
# Filter by vendor
curl -s "http://localhost:8100/v1/fingerprints?vendor=Hikvision&limit=10" \
  -H "Authorization: Bearer $TOKEN" | jq .
```

### Get Fingerprint Database Stats

```
GET /v1/fingerprints/stats
```

```bash
curl -s http://localhost:8100/v1/fingerprints/stats \
  -H "Authorization: Bearer $TOKEN" | jq .
```

### Export All Fingerprints

```
GET /v1/fingerprints/export
```

```bash
curl -s http://localhost:8100/v1/fingerprints/export \
  -H "Authorization: Bearer $TOKEN" | jq . > fingerprints-export.json
```

### Identify Devices by Port Signature

```
POST /v1/fingerprints/identify
```

```bash
curl -s -X POST http://localhost:8100/v1/fingerprints/identify \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "hosts": [
      {"ip": "172.30.0.10", "open_ports": [80, 554, 8080]}
    ]
  }' | jq .
```

---

## Agents

Agents are used for distributed scanning across multiple network segments. The lab environment does not include remote agents, but the API endpoints are functional for exploration.

### List All Agents (Admin, JWT Auth)

```
GET /v1/agents/
```

```bash
curl -s http://localhost:8100/v1/agents/ \
  -H "Authorization: Bearer $TOKEN" | jq '.agents'
```

### Create an Agent Registration Token (Admin, JWT Auth)

```
POST /v1/agents/tokens
```

```bash
curl -s -X POST http://localhost:8100/v1/agents/tokens \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "agent_type": "explorer",
    "subnets": ["10.0.0.0/24"],
    "expires_in_hours": 24
  }' | jq .
```

```bash
# Capture the registration token
REG_TOKEN=$(curl -s -X POST http://localhost:8100/v1/agents/tokens \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"agent_type":"explorer","subnets":["10.0.0.0/24"]}' \
  | jq -r '.token')

echo "Registration token: $REG_TOKEN"
```

### Register an Agent (No Auth -- Uses Registration Token)

```
POST /v1/agents/register
```

```bash
curl -s -X POST http://localhost:8100/v1/agents/register \
  -H "Content-Type: application/json" \
  -d "{
    \"registration_token\": \"$REG_TOKEN\",
    \"name\": \"lab-agent-01\",
    \"subnets\": [\"10.0.0.0/24\"],
    \"capabilities\": [\"arp\", \"mdns\", \"ssdp\"]
  }" | jq .
```

```bash
# Capture the agent API token for subsequent agent calls
AGENT_TOKEN=$(curl -s -X POST http://localhost:8100/v1/agents/register \
  -H "Content-Type: application/json" \
  -d "{\"registration_token\":\"$REG_TOKEN\",\"name\":\"lab-agent-01\"}" \
  | jq -r '.api_token')
```

### Revoke an Agent (Admin, JWT Auth)

```
POST /v1/agents/{agent_id}/revoke
```

```bash
curl -s -X POST http://localhost:8100/v1/agents/$AGENT_ID/revoke \
  -H "Authorization: Bearer $TOKEN" | jq .
```

### Agent Heartbeat (Agent Token Auth)

```
POST /v1/agents/heartbeat
```

```bash
curl -s -X POST http://localhost:8100/v1/agents/heartbeat \
  -H "X-Agent-Token: $AGENT_TOKEN" | jq .
```

### Poll for Tasks (Agent Token Auth)

```
GET /v1/agents/tasks
```

```bash
curl -s http://localhost:8100/v1/agents/tasks \
  -H "X-Agent-Token: $AGENT_TOKEN" | jq '.tasks'
```

---

## Firmware Intelligence

Phase 2 endpoints for firmware risk analysis, SBOM inspection, component-level CVE matching, integrity detection, and transitive vulnerability discovery.

### Firmware Summary

```
GET /v1/firmware/summary
```

```bash
curl -s http://localhost:8100/v1/firmware/summary \
  -H "Authorization: Bearer $TOKEN" | jq .
```

```bash
# Risk breakdown only
curl -s http://localhost:8100/v1/firmware/summary \
  -H "Authorization: Bearer $TOKEN" \
  | jq '{critical: .critical_count, high: .high_count, medium: .medium_count,
         low: .low_count, current: .current_count, eol: .eol_count}'
```

### List Firmware Devices (Paginated)

```
GET /v1/firmware/devices?risk_level={level}&vendor={vendor}&eol={bool}&page={n}&limit={n}
```

```bash
curl -s "http://localhost:8100/v1/firmware/devices?limit=10" \
  -H "Authorization: Bearer $TOKEN" | jq '.devices[] | {ip, vendor, version, risk_level}'
```

```bash
# Critical-risk devices only
curl -s "http://localhost:8100/v1/firmware/devices?risk_level=critical&limit=10" \
  -H "Authorization: Bearer $TOKEN" | jq '.devices'
```

```bash
# EOL devices sorted by age
curl -s "http://localhost:8100/v1/firmware/devices?eol=true&sort_by=age_days&order=desc" \
  -H "Authorization: Bearer $TOKEN" | jq '.devices[] | {ip, vendor, age_days, eol}'
```

### Device Firmware Detail

```
GET /v1/devices/{ip}/firmware
```

```bash
curl -s http://localhost:8100/v1/devices/172.30.0.10/firmware \
  -H "Authorization: Bearer $TOKEN" | jq .
```

```bash
# Key fields: version, risk, age, EOL status
curl -s http://localhost:8100/v1/devices/172.30.0.10/firmware \
  -H "Authorization: Bearer $TOKEN" \
  | jq '{ip, version, vendor, risk_level, age_days, freshness_score, eol, firmware_cves}'
```

### Device SBOM (Software Bill of Materials)

```
GET /v1/devices/{ip}/sbom
```

```bash
curl -s http://localhost:8100/v1/devices/172.30.0.10/sbom \
  -H "Authorization: Bearer $TOKEN" | jq .
```

```bash
# Component names and versions
curl -s http://localhost:8100/v1/devices/172.30.0.10/sbom \
  -H "Authorization: Bearer $TOKEN" \
  | jq '.components[] | {name, version, purl, licenses}'
```

```bash
# Count components
curl -s http://localhost:8100/v1/devices/172.30.0.10/sbom \
  -H "Authorization: Bearer $TOKEN" | jq '.components | length'
```

### Component-Level CVEs

```
GET /v1/devices/{ip}/component-cves
```

```bash
curl -s http://localhost:8100/v1/devices/172.30.0.10/component-cves \
  -H "Authorization: Bearer $TOKEN" | jq .
```

```bash
# Components with CVEs (name, version, CVE count)
curl -s http://localhost:8100/v1/devices/172.30.0.10/component-cves \
  -H "Authorization: Bearer $TOKEN" \
  | jq '.components[] | {name, version, cve_count: (.cves | length)}'
```

```bash
# All critical CVEs across components
curl -s http://localhost:8100/v1/devices/172.30.0.10/component-cves \
  -H "Authorization: Bearer $TOKEN" \
  | jq '[.components[].cves[] | select(.severity == "CRITICAL")] | sort_by(-.cvss_score)'
```

### Transitive Vulnerabilities

```
GET /v1/firmware/transitive-vulns?min_devices={n}
```

```bash
curl -s "http://localhost:8100/v1/firmware/transitive-vulns?min_devices=2" \
  -H "Authorization: Bearer $TOKEN" | jq .
```

```bash
# Shared vulnerable components and affected device count
curl -s "http://localhost:8100/v1/firmware/transitive-vulns?min_devices=2" \
  -H "Authorization: Bearer $TOKEN" \
  | jq '.vulnerabilities[] | {name, version, cve_id, severity, device_count, affected_devices}'
```

### Device Integrity Alerts

```
GET /v1/devices/{ip}/integrity
```

```bash
curl -s http://localhost:8100/v1/devices/172.30.0.10/integrity \
  -H "Authorization: Bearer $TOKEN" | jq .
```

```bash
# Alert details with severity
curl -s http://localhost:8100/v1/devices/172.30.0.10/integrity \
  -H "Authorization: Bearer $TOKEN" \
  | jq '.alerts[] | {check_type, severity, description}'
```

---

## Compliance

Phase 2 endpoints for regulatory compliance assessment, vendor trust scoring, and supply chain risk analysis.

### CRA-Compliant SBOM

```
GET /v1/compliance/{ip}/sbom/cra?fmt=json|pdf
```

```bash
# JSON format (default)
curl -s http://localhost:8100/v1/compliance/172.30.0.10/sbom/cra \
  -H "Authorization: Bearer $TOKEN" | jq .
```

```bash
# Document metadata
curl -s http://localhost:8100/v1/compliance/172.30.0.10/sbom/cra \
  -H "Authorization: Bearer $TOKEN" \
  | jq '{document_name: .document.name, created: .document.created,
         vendor: .device.vendor, component_count: (.components | length)}'
```

```bash
# Download as PDF
curl -s "http://localhost:8100/v1/compliance/172.30.0.10/sbom/cra?fmt=pdf" \
  -H "Authorization: Bearer $TOKEN" -o cra-sbom.pdf
```

### Vendor Trust Scores

```
GET /v1/compliance/vendor-trust
```

```bash
curl -s http://localhost:8100/v1/compliance/vendor-trust \
  -H "Authorization: Bearer $TOKEN" | jq .
```

```bash
# Vendor scorecards sorted by score (lowest = worst)
curl -s http://localhost:8100/v1/compliance/vendor-trust \
  -H "Authorization: Bearer $TOKEN" \
  | jq '.vendors[] | {vendor, score, grade, factors}'
```

### Supply Chain Risk

```
GET /v1/compliance/supply-chain-risk
```

```bash
curl -s http://localhost:8100/v1/compliance/supply-chain-risk \
  -H "Authorization: Bearer $TOKEN" | jq .
```

```bash
# Overall risk score and contributing factors
curl -s http://localhost:8100/v1/compliance/supply-chain-risk \
  -H "Authorization: Bearer $TOKEN" \
  | jq '{overall_score, risk_level, risk_factors}'
```

---

## Quick Reference Table

| Endpoint | Method | Auth | Description |
|----------|--------|------|-------------|
| `/health` | GET | None | API health check |
| `/v1/auth/register` | POST | None | Register new user |
| `/v1/auth/login` | POST | None | Login, get tokens |
| `/v1/auth/refresh` | POST | None | Refresh access token |
| `/v1/auth/me` | GET | Bearer | Current user profile |
| `/v1/auth/logout` | POST | Bearer | Revoke refresh tokens |
| `/v1/scanning/smart-scan` | POST | Bearer | Start a scan |
| `/v1/scanning/smart-scan/{id}/results` | GET | Bearer | Scan results + progress |
| `/v1/scanning/smart-scan/{id}/cancel` | POST | Bearer | Cancel running scan |
| `/v1/scanning/smart-scan/latest/results` | GET | Bearer | Latest scan results |
| `/v1/scanning/smart-scan/history` | GET | Bearer | List recent scans |
| `/v1/scanning/stream/{id}` | GET | Bearer | SSE event stream |
| `/v1/scanning/detect-range` | GET | Bearer | Auto-detect subnet |
| `/v1/scanning/schedules` | POST | Bearer | Create scan schedule |
| `/v1/scanning/schedules` | GET | Bearer | List schedules |
| `/v1/scanning/schedules/{id}` | DELETE | Bearer | Deactivate schedule |
| `/v1/scanning/baseline/save` | POST | Bearer | Save scan baseline |
| `/v1/scanning/baseline/{subnet}` | GET | Bearer | Load baseline |
| `/v1/scanning/baseline/compare` | POST | Bearer | Compare vs baseline |
| `/v1/scanning/baselines` | GET | Bearer | List all baselines |
| `/v1/scanning/baseline/{subnet}` | DELETE | Bearer | Delete baseline |
| `/v1/reports/{id}/pdf` | GET | Bearer | Download PDF report |
| `/v1/reports/{id}/html` | GET | Bearer | Download HTML report |
| `/v1/cves/search` | GET | Bearer | Search CVEs by keyword |
| `/v1/cves/{cve_id}` | GET | Bearer | CVE detail |
| `/v1/cves/lookup` | POST | Bearer | Batch CVE lookup |
| `/v1/fingerprints` | GET | Bearer | List fingerprints |
| `/v1/fingerprints` | POST | Bearer | Create fingerprint |
| `/v1/fingerprints/stats` | GET | Bearer | Fingerprint DB stats |
| `/v1/fingerprints/export` | GET | Bearer | Export fingerprints |
| `/v1/fingerprints/identify` | POST | Bearer | Identify by ports |
| `/v1/agents/` | GET | Bearer | List agents |
| `/v1/agents/tokens` | POST | Bearer | Create registration token |
| `/v1/agents/{id}/revoke` | POST | Bearer | Revoke agent |
| `/v1/agents/register` | POST | None* | Register agent |
| `/v1/agents/tasks` | GET | Agent | Poll for tasks |
| `/v1/agents/heartbeat` | POST | Agent | Agent heartbeat |
| `/v1/firmware/summary` | GET | Bearer | Firmware risk summary |
| `/v1/firmware/devices` | GET | Bearer | Paginated firmware device list |
| `/v1/firmware/transitive-vulns` | GET | Bearer | Shared vulnerable components |
| `/v1/devices/{ip}/firmware` | GET | Bearer | Device firmware metadata |
| `/v1/devices/{ip}/sbom` | GET | Bearer | Device SBOM components |
| `/v1/devices/{ip}/component-cves` | GET | Bearer | Component-level CVEs |
| `/v1/devices/{ip}/integrity` | GET | Bearer | Device integrity alerts |
| `/v1/compliance/{ip}/sbom/cra` | GET | Bearer | CRA-compliant SBOM document |
| `/v1/compliance/vendor-trust` | GET | Bearer | Vendor trust scorecards |
| `/v1/compliance/supply-chain-risk` | GET | Bearer | Supply chain risk assessment |

**Auth types:**
- **None** -- No authentication required
- **Bearer** -- JWT access token via `Authorization: Bearer $TOKEN` header
- **Agent** -- Agent API token via `X-Agent-Token: $AGENT_TOKEN` header
- **None*** -- Uses a one-time registration token in the request body (not a header)

---

## Common jq Patterns

```bash
# Pretty-print any JSON response
curl -s ... | jq .

# Extract a single field
curl -s ... | jq -r '.scan_id'

# Filter array elements
curl -s ... | jq '.hosts[] | select(.device_type == "ip_camera")'

# Count array elements
curl -s ... | jq '.hosts | length'

# Sort by a numeric field (descending)
curl -s ... | jq '[.hosts[] | {ip, total: (.cve_summary.total // 0)}] | sort_by(-.total)'

# Create a CSV-like output
curl -s ... | jq -r '.hosts[] | [.ip, .device_type, (.cve_summary.total // 0)] | @csv'

# Group by device type
curl -s ... | jq '[.hosts[] | {device_type}] | group_by(.device_type) | map({type: .[0].device_type, count: length})'
```

---

## Workflow: Complete Scan Session

```bash
# 1. Authenticate
TOKEN=$(curl -s -X POST http://localhost:8100/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"student@example.com","password":"SecurePass!2026"}' \
  | jq -r '.access_token')

# 2. Start scan
SCAN_ID=$(curl -s -X POST http://localhost:8100/v1/scanning/smart-scan \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"subnet":"172.30.0.0/24"}' | jq -r '.scan_id')

echo "Scan started: $SCAN_ID"

# 3. Poll until complete (simple loop)
while true; do
  STATUS=$(curl -s http://localhost:8100/v1/scanning/smart-scan/$SCAN_ID/results \
    -H "Authorization: Bearer $TOKEN" | jq -r '.status')
  echo "Status: $STATUS"
  [ "$STATUS" = "completed" ] && break
  [ "$STATUS" = "failed" ] && echo "Scan failed!" && break
  sleep 10
done

# 4. View results
curl -s http://localhost:8100/v1/scanning/smart-scan/$SCAN_ID/results \
  -H "Authorization: Bearer $TOKEN" | jq '.vulnerability_summary'

# 5. Download report
curl -s http://localhost:8100/v1/reports/$SCAN_ID/pdf \
  -H "Authorization: Bearer $TOKEN" -o report.pdf
```
