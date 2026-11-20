# Breakwater IoT Simulation Lab

A self-contained Docker-based environment with 21 simulated IoT devices for learning network security scanning and vulnerability assessment.

## Prerequisites

- **Docker Desktop** (macOS/Windows) or **Docker Engine** (Linux)
- **Python 3.9+** (for the scan report CLI)
- **curl** and **Docker Compose v2** (used by the lab health scripts)
- ~4 GB free disk space (Docker images)

## Quick Start

### 1. Run Phase 1 end to end

For Phase 1, use the runner first. It starts the lab, waits for readiness, runs
the discovery-owned scan, exports the Breakwater HTML report, and writes a local
summary page under `reports/`.

```bash
cd student-lab
./run-phase01-lab.sh
```

Use `./run-phase01-lab.sh --clean` when you want the script to remove the lab
containers and volumes after the report is generated.

### 2. Manual startup from this directory

```bash
docker compose up -d
```

This starts 25 containers:
- 21 simulated IoT devices (cameras, NAS, smart home, etc.)
- 1 MQTT broker
- 1 Breakwater API server (the scanner)
- 1 Redis cache
- 1 PostgreSQL database

The API is bound to `127.0.0.1:8100` by default so it is reachable from the
student workstation but not published on the LAN.

### 3. Wait for readiness and validate the runtime

```bash
./wait-for-lab.sh
./check-lab.sh
```

`wait-for-lab.sh` waits for container health checks and `http://127.0.0.1:8100/health`.
`check-lab.sh` also verifies the compose syntax, localhost API binding, and container
privilege posture. If either script fails, inspect the current state with:

```bash
docker compose ps
docker compose logs --tail=100 api
```

### 4. Optional runtime configuration

For a public student release, keep the default localhost bind unless the lab is
running inside a controlled VM or classroom host. To change defaults, create a
`.env` file in `student-lab/` before running `docker compose up -d`:

```bash
BREAKWATER_LAB_API_PORT=8100
BREAKWATER_LAB_BIND_ADDR=127.0.0.1
BREAKWATER_LAB_DB_PASSWORD=replace-with-local-random-value
BREAKWATER_LAB_JWT_ACCESS_SECRET=replace-with-local-random-value
BREAKWATER_LAB_JWT_REFRESH_SECRET=replace-with-local-random-value
```

Generate local random values with `openssl rand -hex 32` when OpenSSL is available.
Do not set `BREAKWATER_LAB_BIND_ADDR=0.0.0.0` on a shared network unless the host
firewall and classroom access controls are already in place.

The public course package enables the advanced Phase 5-12 simulation endpoints
inside this local lab container. The account `student@example.com` is treated as
a local lab administrator so write-gated simulation exercises such as controlled
pentest campaigns, deception deployment, formal verification, and remediation
approval can be completed without a private Breakwater account. This permission
bootstrap applies only to the disposable student lab stack.

### 5. Install scan CLI dependencies

```bash
pip install -r requirements-scan.txt
```

### 6. Run a scan

```bash
python scan_report.py 172.30.0.0/24
```

The scan takes 10-15 minutes and runs through 7 phases:
1. **Discovery** - Find live hosts on the network
2. **Enrichment** - Probe each host for open ports, services, certificates
3. **Identification** - Classify device type (camera, NAS, router, etc.)
4. **CVE Assessment** - Look up known vulnerabilities (NVD database)
5. **OpenVAS** - (skipped in this lab)
6. **Nuclei** - Template-based vulnerability scanning
7. **Default Credentials** - Check for factory passwords

### 7. Read the results

The scan report shows a table with:
- **IP Address** - Device location on the network
- **Hostname / Device** - What the device is (with confidence %)
- **Ports** - Open network ports and services
- **Software** - Detected software versions, enrichment sources
- **Vulns** - Vulnerability counts by source (NVD CVEs, default credentials, Nuclei)
- **Risk** - Overall risk rating (CREDS! > CRITICAL > HIGH > MEDIUM)

## What's in the Lab?

### Simulated Devices

| IP | Device | Protocols | Default Creds |
|----|--------|-----------|---------------|
| 172.30.0.10 | Hikvision IP Camera | HTTP, RTSP, ONVIF | admin/12345 |
| 172.30.0.11 | Dahua NVR | HTTP, RTSP | admin/admin |
| 172.30.0.12 | Axis IP Camera | HTTP, RTSP | root/pass |
| 172.30.0.13 | Reolink Camera | HTTP, RTSP | admin/admin |
| 172.30.0.14 | Amcrest Camera | HTTP, RTSP | admin/admin |
| 172.30.0.15 | Nest Cam | HTTP, TLS | - |
| 172.30.0.20 | Chromecast | HTTP, mDNS, SSDP | - |
| 172.30.0.21 | Echo Dot | HTTP, SSDP | - |
| 172.30.0.22 | Philips Hue Bridge | HTTP, SSDP, mDNS | - |
| 172.30.0.23 | Sonos Speaker | HTTP, SSDP | - |
| 172.30.0.24 | Apple TV | HTTP, mDNS | - |
| 172.30.0.30 | Synology NAS | HTTP, HTTPS | admin/admin |
| 172.30.0.31 | QNAP NAS | HTTP, HTTPS | admin/admin |
| 172.30.0.32 | TP-Link Router | HTTP | admin/admin |
| 172.30.0.33 | Ubiquiti AP | HTTP, SSH | ubnt/ubnt |
| 172.30.0.40 | HP Printer | HTTP | - |
| 172.30.0.50 | MQTT Broker | MQTT (1883) | - |
| 172.30.0.51 | Raspberry Pi | SSH, HTTP | pi/raspberry |
| 172.30.0.52 | ESP32 Module | HTTP | admin/admin |
| 172.30.0.60 | Ring Doorbell | HTTP, SSDP | - |
| 172.30.0.61 | Samsung TV | HTTP, SSDP | - |
| 172.30.0.62 | Nest Thermostat | HTTP, mDNS | - |

### Expected Scan Results

| Metric | Expected |
|--------|----------|
| Devices discovered | ~20 |
| NVD CVEs found | ~225 |
| Critical vulnerabilities | ~60 |
| High vulnerabilities | ~74 |
| Default credentials found | ~20 |

## Exercises

### Exercise 1: Discovery Analysis
Run the scan and identify which discovery methods found each device. Look at the `discovery_method` field in the API results.

```bash
# Get raw JSON results for a specific scan
curl http://localhost:8100/v1/scanning/smart-scan/YOUR_SCAN_ID/results | python -m json.tool
```

### Exercise 2: Vulnerability Triage
Sort the scan results by risk level. Which devices are most critical to remediate first? Why?

### Exercise 3: Default Credential Impact
How many devices have default credentials? What attack scenarios could an attacker execute with these credentials?

### Exercise 4: CVE Research
Pick the top-3 critical CVEs from the scan results. Look them up on [nvd.nist.gov](https://nvd.nist.gov/) and summarize:
- What is the vulnerability?
- What software version is affected?
- Is there a patch available?

### Exercise 5: Network Segmentation
Based on the scan results, design a network segmentation policy. Which devices should be on the same VLAN? Which need isolation?

### Exercise 6: API Exploration

Use `curl` to explore the Breakwater API endpoints. Parse JSON results with `jq`.

First, register a user and obtain an access token:

```bash
# Register a user and capture the access token
TOKEN=$(curl -s -X POST http://localhost:8100/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"student@example.com","password":"SecurePass!2026"}' \
  | jq -r '.access_token')

echo "Token: $TOKEN"
```

Now explore the scanning API:

```bash
# Check the API health
curl -s http://localhost:8100/health | jq .

# View the interactive API documentation (open in browser)
# http://localhost:8100/docs

# Start a scan and capture the scan ID
SCAN_ID=$(curl -s -X POST http://localhost:8100/v1/scanning/smart-scan \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"subnet":"172.30.0.0/24"}' | jq -r '.scan_id')

echo "Scan ID: $SCAN_ID"

# Monitor scan progress (run repeatedly or watch with a loop)
curl -s http://localhost:8100/v1/scanning/smart-scan/$SCAN_ID/results \
  -H "Authorization: Bearer $TOKEN" | jq '.progress'

# Once completed, extract the list of discovered hosts
curl -s http://localhost:8100/v1/scanning/smart-scan/$SCAN_ID/results \
  -H "Authorization: Bearer $TOKEN" | jq '.hosts[] | {ip, hostname, device_type}'

# Search for CVEs by keyword
curl -s "http://localhost:8100/v1/cves/search?keyword=hikvision&limit=5" \
  -H "Authorization: Bearer $TOKEN" | jq '.[].cve_id'
```

**Questions:**
1. Which API endpoints require a Bearer token in the `Authorization` header? Which do not? (Hint: try calling `/health` vs. `/v1/scanning/smart-scan/history` without a token.)
2. What HTTP methods are used across the API (GET, POST, PUT, DELETE)? For each method, give one example endpoint and explain why that method is appropriate.
3. What HTTP status code do you receive when you call an authenticated endpoint without a token? What does this status code mean per RFC 9110?

### Exercise 7: Scheduled Scan Setup

Configure a recurring scan via the API and examine how the scheduling system works.

```bash
# Create a daily scan schedule that runs at 2 AM UTC
curl -s -X POST http://localhost:8100/v1/scanning/schedules \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"subnet":"172.30.0.0/24","cron_expression":"0 2 * * *","name":"Daily IoT Scan"}' \
  | jq .

# List all active schedules
curl -s http://localhost:8100/v1/scanning/schedules \
  -H "Authorization: Bearer $TOKEN" | jq '.data.schedules'

# Capture the schedule ID for later deletion
SCHEDULE_ID=$(curl -s http://localhost:8100/v1/scanning/schedules \
  -H "Authorization: Bearer $TOKEN" | jq -r '.data.schedules[0].scan_id')

# Delete (deactivate) a schedule
curl -s -X DELETE http://localhost:8100/v1/scanning/schedules/$SCHEDULE_ID \
  -H "Authorization: Bearer $TOKEN" | jq .
```

**Questions:**
1. Why would an organization schedule vulnerability scans at 2 AM rather than during business hours? Consider both technical and operational factors.
2. Write the cron expression for a scan that runs every Monday at 6:00 AM UTC. Explain each field.
3. A hospital network has maintenance windows on Sundays from 00:00-04:00. Write a cron expression that scans within this window. What additional constraints might apply in a healthcare environment (consider HIPAA, patient safety, and medical device availability)?
4. The API validates cron expressions server-side. What would happen if you submitted an invalid expression like `"99 99 * * *"`? Try it and document the response.

### Exercise 8: Report Generation

Download scan reports in multiple formats and compare the information density.

```bash
# Ensure you have a completed scan ID (from Exercise 6 or a previous run)
# Check the latest scan results
curl -s http://localhost:8100/v1/scanning/smart-scan/$SCAN_ID/results \
  -H "Authorization: Bearer $TOKEN" | jq '{status, host_count, vulnerability_summary}'

# Download a PDF report
curl -s http://localhost:8100/v1/reports/$SCAN_ID/pdf \
  -H "Authorization: Bearer $TOKEN" -o breakwater-report.pdf

# Download an HTML report
curl -s http://localhost:8100/v1/reports/$SCAN_ID/html \
  -H "Authorization: Bearer $TOKEN" -o breakwater-report.html

# Compare with raw JSON (save for analysis)
curl -s http://localhost:8100/v1/scanning/smart-scan/$SCAN_ID/results \
  -H "Authorization: Bearer $TOKEN" | jq . > breakwater-report.json

# Count hosts and vulnerabilities from the JSON
cat breakwater-report.json | jq '{
  total_hosts: .host_count,
  total_vulns: .vulnerability_summary.total_cves,
  critical: .vulnerability_summary.critical,
  high: .vulnerability_summary.high,
  default_creds: .vulnerability_summary.default_creds
}'
```

**Questions:**
1. Open the PDF and HTML reports. What information is present in the formatted reports that adds context beyond the raw JSON data (e.g., executive summary, risk visualizations, remediation guidance)?
2. Why might a CISO prefer a PDF report while a SOC analyst prefers raw JSON? Consider audience, automation, compliance, and decision-making context.
3. Design the table of contents for an ideal vulnerability assessment report aimed at a board of directors. How would it differ from one aimed at a penetration testing team?

### Exercise 9: Attack Path Analysis

Chain default credentials and CVE findings to map realistic attack paths through the IoT network.

**Scenario:** An external attacker has gained access to the lab network (172.30.0.0/24) through a compromised IoT device. Using your scan results, map the attacker's potential movements.

**Step 1: Identify initial access vectors**

```bash
# Extract all devices with default credentials
curl -s http://localhost:8100/v1/scanning/smart-scan/$SCAN_ID/results \
  -H "Authorization: Bearer $TOKEN" \
  | jq '.hosts[] | select(.default_creds != null and (.default_creds | length) > 0)
        | {ip, device_type, hostname, creds: [.default_creds[] | {protocol, username}]}'
```

**Step 2: Map lateral movement from compromised devices**

```bash
# For each device with default creds, list its known CVEs
curl -s http://localhost:8100/v1/scanning/smart-scan/$SCAN_ID/results \
  -H "Authorization: Bearer $TOKEN" \
  | jq '.hosts[] | select(.default_creds != null and (.default_creds | length) > 0)
        | {ip, device_type,
           cred_count: (.default_creds | length),
           cve_total: (.cve_summary.total // 0),
           critical_cves: (.cve_summary.critical // 0),
           open_ports: [.services[]? | select(.state == "open") | .port]}'
```

**Step 3: Identify high-value targets**

```bash
# Find devices with the most critical vulnerabilities (potential pivot points)
curl -s http://localhost:8100/v1/scanning/smart-scan/$SCAN_ID/results \
  -H "Authorization: Bearer $TOKEN" \
  | jq '[.hosts[] | {ip, device_type,
         total_vulns: ((.cve_summary.total // 0) + (.default_creds // [] | length)),
         has_creds: ((.default_creds // []) | length > 0),
         critical: (.cve_summary.critical // 0)}]
       | sort_by(-.total_vulns) | .[:5]'
```

**Attack path construction:**

Using the data gathered above, document the following attack chains:

1. **Camera-to-NVR pivot:** An attacker uses default credentials on a camera (e.g., Hikvision at 172.30.0.10, admin/12345) to access RTSP streams. From the camera's network position, they pivot to the Dahua NVR (172.30.0.11, admin/admin) which records all camera feeds.

2. **Infrastructure compromise:** From the NVR, trace paths to network infrastructure devices (TP-Link router at 172.30.0.32, Ubiquiti AP at 172.30.0.33). What credentials give access? What CVEs enable privilege escalation?

3. **Data exfiltration:** Map the path from compromised infrastructure to high-value data stores (Synology NAS at 172.30.0.30, QNAP NAS at 172.30.0.31). What data could be exfiltrated?

**Deliverable:** Draw a network attack path diagram showing:
- **Initial access** (which devices, which credentials)
- **Privilege escalation** (which CVEs enable elevated access)
- **Lateral movement** (network paths between compromised devices)
- **Data exfiltration** (what data is reachable, through which path)

Use MITRE ATT&CK technique IDs where applicable (e.g., T1078 Valid Accounts, T1021 Remote Services, T1557 Adversary-in-the-Middle).

### Exercise 10: Remediation Plan

Write a comprehensive remediation report with priority tiers based on your scan findings.

**Step 1: Gather your data**

```bash
# Full vulnerability summary
curl -s http://localhost:8100/v1/scanning/smart-scan/$SCAN_ID/results \
  -H "Authorization: Bearer $TOKEN" \
  | jq '{
      scan_summary: {
        total_hosts: .host_count,
        vulns: .vulnerability_summary
      },
      devices_with_creds: [.hosts[] | select((.default_creds // []) | length > 0)
                           | {ip, device_type, protocols: [.default_creds[].protocol]}],
      critical_cve_hosts: [.hosts[] | select((.cve_summary.critical // 0) > 0)
                           | {ip, device_type, critical: .cve_summary.critical, high: .cve_summary.high}]
    }'
```

**Step 2: Build your remediation plan**

Create a remediation report with the following structure and three priority tiers:

**Tier 1 -- Immediate (within 24 hours):**
- Change all default credentials identified by the scan. For each device, document the current default username, the protocol (HTTP, SSH, RTSP, ONVIF), and the action required (password change, account disable, or both).
- Isolate devices with critical CVEs that have known public exploits. Prioritize any CVE with a CVSS score above 9.0.
- Disable unnecessary services (e.g., RTSP on cameras that do not require remote viewing, SSH on devices where it is not operationally needed).

**Tier 2 -- Short-term (within 7 days):**
- Apply patches for all HIGH severity CVEs where vendor patches are available. Reference specific CVE IDs from your scan.
- Implement network access controls to restrict communication between device categories (cameras should not talk to NAS devices directly).
- Enable logging and monitoring on all network infrastructure devices (router, access point).
- Disable UPnP on all devices where it is not required (reference any UPnP vulnerabilities found in the scan).

**Tier 3 -- Medium-term (within 30 days):**
- Implement network segmentation using VLANs: separate cameras, smart home, NAS/infrastructure, and IoT protocols into distinct segments.
- Deploy firmware updates on all devices with outdated firmware versions.
- Establish a vulnerability management program with scheduled recurring scans (reference your Exercise 7 schedule configuration).
- Develop an IoT device procurement policy requiring security assessment before deployment.
- Plan for end-of-life device replacement where vendor support has ceased.

**Deliverable:** A 1-2 page remediation report suitable for a CISO audience. Include:
- An executive summary (2-3 sentences on overall risk posture)
- A risk matrix or summary table mapping device categories to risk levels
- Specific remediation actions with owner, timeline, and success criteria
- Cost/effort estimates where possible (e.g., "credential rotation: 2 hours, no cost" vs. "network segmentation: 2 weeks, requires managed switch upgrade")
- Metrics to track remediation progress (e.g., percentage of default credentials changed, mean time to patch)

### Exercise 11: Firmware Intelligence

Explore the firmware risk analysis pipeline. Breakwater Phase 2 discovers firmware versions from device management interfaces and scores them by age, end-of-life status, and known CVEs.

**Step 1: Get the fleet firmware summary**

```bash
# Overall firmware risk distribution
curl -s http://localhost:8100/v1/firmware/summary \
  -H "Authorization: Bearer $TOKEN" | jq .

# Risk counts only
curl -s http://localhost:8100/v1/firmware/summary \
  -H "Authorization: Bearer $TOKEN" \
  | jq '{critical: .critical_count, high: .high_count, medium: .medium_count,
         eol: .eol_count, avg_freshness}'
```

**Step 2: Find the most at-risk devices**

```bash
# Critical-risk firmware devices
curl -s "http://localhost:8100/v1/firmware/devices?risk_level=critical&limit=10" \
  -H "Authorization: Bearer $TOKEN" \
  | jq '.devices[] | {ip, vendor, model, version, risk_level, age_days, eol}'
```

**Step 3: Inspect a specific device**

```bash
# Pick a device IP from the previous output
DEVICE_IP="172.30.0.10"

curl -s http://localhost:8100/v1/devices/$DEVICE_IP/firmware \
  -H "Authorization: Bearer $TOKEN" | jq .
```

**Questions:**
1. How many devices have firmware classified as "critical" risk? What criteria do you think contribute to a critical rating (consider age, EOL status, and known CVEs)?
2. What is the average freshness score across all devices? A freshness score of 1.0 means current; 0.0 means severely outdated. What score threshold would you set as an organizational policy minimum?
3. Which vendor has the most devices in the fleet? Does vendor concentration increase or decrease supply chain risk?
4. Compare the `age_days` field for two devices with different risk levels. How does firmware age correlate with vulnerability exposure?

### Exercise 12: SBOM Analysis

Examine the Software Bill of Materials (SBOM) extracted from device firmware. An SBOM lists every software component inside a device — libraries, packages, and their versions.

```bash
# Get SBOM for a device
curl -s http://localhost:8100/v1/devices/$DEVICE_IP/sbom \
  -H "Authorization: Bearer $TOKEN" | jq .

# Count components
curl -s http://localhost:8100/v1/devices/$DEVICE_IP/sbom \
  -H "Authorization: Bearer $TOKEN" | jq '.components | length'

# List component names and versions
curl -s http://localhost:8100/v1/devices/$DEVICE_IP/sbom \
  -H "Authorization: Bearer $TOKEN" \
  | jq '.components[] | {name, version, purl}'

# Find components with known PURLs (Package URLs)
curl -s http://localhost:8100/v1/devices/$DEVICE_IP/sbom \
  -H "Authorization: Bearer $TOKEN" \
  | jq '[.components[] | select(.purl != null)] | length'

# Group by license
curl -s http://localhost:8100/v1/devices/$DEVICE_IP/sbom \
  -H "Authorization: Bearer $TOKEN" \
  | jq '[.components[].licenses[]?] | group_by(.) | map({license: .[0], count: length}) | sort_by(-.count)'
```

**Questions:**
1. How many software components does the device firmware contain? Were you surprised by the number?
2. What is a PURL (Package URL)? Why is it more useful than just a component name and version for vulnerability matching?
3. Find a component that uses a GPL license. What are the compliance implications for a commercial IoT device shipping GPL-licensed code?
4. The EU Cyber Resilience Act (CRA) requires manufacturers to provide SBOMs for connected devices. How does automated SBOM extraction help meet this requirement compared to manual documentation?

### Exercise 13: Component CVEs and Transitive Vulnerabilities

Discover vulnerabilities at the component level — not just the device level — and identify shared vulnerable components across multiple devices.

**Step 1: Component-level CVEs for a device**

```bash
# Get CVEs mapped to specific SBOM components
curl -s http://localhost:8100/v1/devices/$DEVICE_IP/component-cves \
  -H "Authorization: Bearer $TOKEN" | jq .

# Components with CVE counts
curl -s http://localhost:8100/v1/devices/$DEVICE_IP/component-cves \
  -H "Authorization: Bearer $TOKEN" \
  | jq '.components[] | {name, version, cve_count: (.cves | length)}'

# Critical component CVEs only
curl -s http://localhost:8100/v1/devices/$DEVICE_IP/component-cves \
  -H "Authorization: Bearer $TOKEN" \
  | jq '[.components[].cves[] | select(.severity == "CRITICAL")] | sort_by(-.cvss_score)'
```

**Step 2: Transitive vulnerabilities (shared across devices)**

```bash
# Find vulnerable components shared by 2+ devices
curl -s "http://localhost:8100/v1/firmware/transitive-vulns?min_devices=2" \
  -H "Authorization: Bearer $TOKEN" | jq .

# Summary: component, CVE, affected device count
curl -s "http://localhost:8100/v1/firmware/transitive-vulns?min_devices=2" \
  -H "Authorization: Bearer $TOKEN" \
  | jq '.vulnerabilities[] | {name, version, cve_id, severity, device_count}'
```

**Questions:**
1. What is the difference between a device-level CVE (from Phase 1 NVD lookup) and a component-level CVE (from SBOM analysis)? Which provides more actionable remediation guidance?
2. How many transitive vulnerabilities affect 2 or more devices? Why are transitive vulnerabilities particularly dangerous in an IoT fleet?
3. If a single library (e.g., OpenSSL) is vulnerable and appears in 5 devices, does patching one device fix the others? What does this imply for fleet-wide firmware update strategies?
4. A vulnerability in a deeply nested dependency (e.g., a compression library used by a TLS library used by a web server) is called a "transitive dependency vulnerability." Why are these harder to discover without SBOM analysis?

### Exercise 14: Integrity Detection

Explore the integrity checking system that detects anomalies such as MAC address spoofing, firmware hash mismatches, and banner inconsistencies.

```bash
# Get integrity alerts for a device
curl -s http://localhost:8100/v1/devices/$DEVICE_IP/integrity \
  -H "Authorization: Bearer $TOKEN" | jq .

# Alert types and severity
curl -s http://localhost:8100/v1/devices/$DEVICE_IP/integrity \
  -H "Authorization: Bearer $TOKEN" \
  | jq '.alerts[] | {check_type, severity, description}'

# Count alerts by severity
curl -s http://localhost:8100/v1/devices/$DEVICE_IP/integrity \
  -H "Authorization: Bearer $TOKEN" \
  | jq '[.alerts[].severity] | group_by(.) | map({severity: .[0], count: length})'
```

Try multiple device IPs to compare integrity results:

```bash
for IP in 172.30.0.10 172.30.0.11 172.30.0.30 172.30.0.32; do
  echo "--- $IP ---"
  curl -s http://localhost:8100/v1/devices/$IP/integrity \
    -H "Authorization: Bearer $TOKEN" | jq '.total'
done
```

**Questions:**
1. What types of integrity checks does Breakwater perform? List the `check_type` values you observe and explain what each one detects.
2. A "MAC OUI mismatch" alert means the device's MAC address vendor prefix does not match the identified device vendor. What could cause this? Consider both benign explanations (virtualization, NIC replacement) and malicious ones (device spoofing, man-in-the-middle).
3. How would you use firmware hash baselines to detect unauthorized firmware modifications? Design a workflow that includes: (a) establishing the baseline, (b) periodic re-verification, and (c) incident response when a mismatch is detected.
4. Banner inconsistency detection compares the HTTP Server header, TLS certificate CN, and SSDP device description against the identified device type. Why might an attacker modify these banners, and how does detection help?

### Exercise 15: Compliance Assessment

Use the compliance endpoints to assess vendor trustworthiness, supply chain risk, and generate CRA-compliant SBOM documents.

**Step 1: Vendor trust scores**

```bash
# Get vendor trust scorecards
curl -s http://localhost:8100/v1/compliance/vendor-trust \
  -H "Authorization: Bearer $TOKEN" | jq .

# Sorted by score (worst first)
curl -s http://localhost:8100/v1/compliance/vendor-trust \
  -H "Authorization: Bearer $TOKEN" \
  | jq '.vendors[] | {vendor, score, grade}'
```

**Step 2: Supply chain risk assessment**

```bash
# Aggregate supply chain risk
curl -s http://localhost:8100/v1/compliance/supply-chain-risk \
  -H "Authorization: Bearer $TOKEN" | jq .

# Risk factors breakdown
curl -s http://localhost:8100/v1/compliance/supply-chain-risk \
  -H "Authorization: Bearer $TOKEN" | jq '.risk_factors'
```

**Step 3: CRA SBOM document**

```bash
# Generate CRA-compliant SBOM (JSON)
curl -s http://localhost:8100/v1/compliance/$DEVICE_IP/sbom/cra \
  -H "Authorization: Bearer $TOKEN" | jq .

# Download as PDF
curl -s "http://localhost:8100/v1/compliance/$DEVICE_IP/sbom/cra?fmt=pdf" \
  -H "Authorization: Bearer $TOKEN" -o cra-sbom.pdf

ls -lh cra-sbom.pdf
```

**Questions:**
1. Which vendor has the lowest trust score? What factors contributed to this score? How would you use vendor trust data in a procurement decision?
2. The supply chain risk score aggregates vendor trust, firmware age, EOL status, and vulnerability density. What is the overall risk level? What single action would most reduce supply chain risk?
3. The EU Cyber Resilience Act (CRA) requires manufacturers to "identify and document vulnerabilities and components contained in the product." How does the CRA SBOM endpoint help demonstrate compliance? What additional information might a regulator require beyond what the SBOM provides?
4. Compare the vendor trust scores of two vendors. A vendor with a score of 80 ("B" grade) and another with 40 ("F" grade) both supply devices in your network. Draft a 2-sentence procurement policy recommendation based on this data.

### Exercise 16: Advanced — Binary Analysis and Fuzzing (Conceptual)

Phase 2 includes binary analysis (binwalk, Ghidra) and fuzzing (AFL++) capabilities that are computationally intensive and require additional tooling. This exercise explores the architecture conceptually.

**Discussion: Binary Analysis Pipeline**

The binary analysis phase performs:
1. **Firmware extraction** (binwalk) — unpacks firmware images into filesystem layers
2. **Endpoint discovery** — finds hardcoded URLs, IP addresses, and API endpoints in binary strings
3. **Secret detection** — identifies embedded credentials, API keys, and certificates
4. **Static analysis** (Ghidra) — decompiles binaries to find unsafe function calls (e.g., `strcpy`, `sprintf`)

```bash
# The analysis endpoint returns combined results from binary analysis
curl -s http://localhost:8100/v1/devices/$DEVICE_IP/analysis \
  -H "Authorization: Bearer $TOKEN" | jq .
```

**Discussion: Fuzzing Architecture**

The fuzzing phase uses AFL++ to discover zero-day vulnerabilities:
1. **Harness generation** — creates test harnesses for discovered network services
2. **Fuzzing execution** — generates mutated inputs targeting protocol parsers
3. **Crash triage** — classifies crashes by CWE (e.g., CWE-120 Buffer Overflow, CWE-416 Use After Free)
4. **Disclosure workflow** — manages responsible disclosure timeline (90-day policy)

**Questions:**
1. Why is binary analysis performed on firmware images rather than running devices? What are the advantages of static analysis vs. dynamic analysis (fuzzing) for IoT security?
2. A binwalk extraction reveals the firmware uses `busybox 1.28.0`. How would you determine if this version has known vulnerabilities? How does this complement the SBOM analysis from Exercise 12?
3. AFL++ discovered a crash in the RTSP parser of a camera firmware. The crash is classified as CWE-120 (Buffer Copy without Checking Size of Input). Outline the steps for responsible disclosure: who do you notify, what information do you include, and what timeline do you follow?
4. Hardcoded secrets found during binary analysis (e.g., an embedded AWS API key or a fixed SSH private key) affect every deployed unit of that device. Compare the risk profile of a hardcoded secret vs. a default password (Exercise 3). Which is harder to remediate at scale?

### Exercise 17: Protocol Transcript Analysis

Phase 3 introduces the Protocol Security Engine, which records full protocol transcripts during enrichment and then analyzes them for anomalies. The engine captures every request/response exchange (HTTP headers, RTSP handshakes, TLS negotiations) and runs passive anomaly detection to flag timing irregularities, information leakage, missing security headers, and session weaknesses -- all without sending any additional probes.

**Step 1: View protocol findings for a scan**

```bash
# List all protocol security findings from the scan
curl -s http://localhost:8100/v1/protocols/findings/$SCAN_ID \
  -H "Authorization: Bearer $TOKEN" | jq .

# Count findings by severity
curl -s http://localhost:8100/v1/protocols/findings/$SCAN_ID \
  -H "Authorization: Bearer $TOKEN" \
  | jq '[.data.findings[].severity] | group_by(.) | map({severity: .[0], count: length})'
```

**Step 2: Inspect findings for a specific host**

```bash
# Pick a device IP with known services (e.g., the Hikvision camera)
DEVICE_IP="172.30.0.10"

# View protocol findings for this host
curl -s http://localhost:8100/v1/protocols/findings/$SCAN_ID/$DEVICE_IP \
  -H "Authorization: Bearer $TOKEN" | jq .

# Filter for specific finding types: timing anomalies and info disclosure
curl -s http://localhost:8100/v1/protocols/findings/$SCAN_ID/$DEVICE_IP \
  -H "Authorization: Bearer $TOKEN" \
  | jq '.data.findings[] | select(.finding_type == "timing_anomaly" or .finding_type == "info_disclosure")
        | {finding_type, severity, title, protocol, port, evidence}'
```

**Step 3: Compare findings across two devices**

```bash
# Compare the Hikvision camera and the Dahua NVR
for IP in 172.30.0.10 172.30.0.11; do
  echo "--- $IP ---"
  curl -s http://localhost:8100/v1/protocols/findings/$SCAN_ID/$IP \
    -H "Authorization: Bearer $TOKEN" \
    | jq '{ip: .data.findings[0].ip // "'$IP'",
           count: .data.count,
           types: [.data.findings[].finding_type] | unique}'
done
```

**Questions:**
1. What types of passive anomalies were detected (e.g., `timing_anomaly`, `info_disclosure`, `missing_security_header`, `session_weakness`)? For each type, explain what the anomaly reveals about the device's security posture without requiring active exploitation.
2. Compare the findings for two different cameras. Do they share the same anomaly types? What does a device with more `info_disclosure` findings tell you about its firmware's approach to HTTP response headers?
3. Passive analysis detects anomalies by observing protocol exchanges that already occurred during enrichment. Why is this preferable to active probing in a production OT/ICS environment? What risks does even passive observation introduce?
4. The `evidence` field in each finding contains raw protocol data (e.g., response headers, timing measurements). How would you use this evidence to validate whether a finding is a true positive vs. an artifact of network latency?

### Exercise 18: Grammar Inference & RFC Conformance

The protocol engine infers state machines (grammars) from observed protocol exchanges using a technique called DynPRE (Dynamic Protocol Reverse Engineering). For each protocol on each device, it constructs a model of states, transitions, and message fields. It then checks these models against RFC specifications to compute a conformance score.

**Step 1: List all inferred grammars**

```bash
# List grammars inferred during this scan
curl -s "http://localhost:8100/v1/protocols/grammars?scan_id=$SCAN_ID" \
  -H "Authorization: Bearer $TOKEN" | jq .

# Summary: protocol, device IP, and state count
curl -s "http://localhost:8100/v1/protocols/grammars?scan_id=$SCAN_ID" \
  -H "Authorization: Bearer $TOKEN" \
  | jq '.data.grammars[] | {protocol, ip, port, states: (.states | length),
         transitions: (.transitions | length), device_fingerprint}'
```

**Step 2: Inspect a specific grammar**

```bash
# Get the grammar for a specific host and port (e.g., HTTP on the Hikvision camera)
curl -s "http://localhost:8100/v1/protocols/grammars/172.30.0.10/80?scan_id=$SCAN_ID" \
  -H "Authorization: Bearer $TOKEN" | jq .

# View the state machine: states and transitions
curl -s "http://localhost:8100/v1/protocols/grammars/172.30.0.10/80?scan_id=$SCAN_ID" \
  -H "Authorization: Bearer $TOKEN" \
  | jq '{states: [.data.states[] | {id, name, is_initial, is_terminal}],
         transitions: [.data.transitions[] | {from_state, to_state, method, description}],
         field_definitions: [.data.field_definitions[] | {name, field_type, semantic}]}'
```

**Step 3: Check RFC conformance scores**

```bash
# Get RFC conformance score for a device
curl -s http://localhost:8100/v1/protocols/rfc-conformance/$SCAN_ID/172.30.0.10 \
  -H "Authorization: Bearer $TOKEN" | jq .

# Compare conformance across multiple devices
for IP in 172.30.0.10 172.30.0.11 172.30.0.30 172.30.0.32; do
  echo "--- $IP ---"
  curl -s http://localhost:8100/v1/protocols/rfc-conformance/$SCAN_ID/$IP \
    -H "Authorization: Bearer $TOKEN" \
    | jq '{ip: .data.ip, score: .data.score, deviations: .data.deviation_count}'
done
```

**Questions:**
1. How many states does the HTTP grammar have for the Hikvision camera vs. the Synology NAS? Why might a more complex device (NAS) have a grammar with more states and transitions?
2. What is the RFC conformance score for each device you checked? A score of 100 means full conformance. What common deviations reduce the score (e.g., missing `Date` header per RFC 9110, non-standard status codes, improper `Content-Length` handling)?
3. DynPRE infers grammars from observed traffic rather than source code. What are the limitations of this approach? Can the inferred grammar ever be more complete than the actual protocol implementation? Less complete?
4. Two devices running the same protocol (HTTP) but from different vendors may have different grammars. How can grammar differences serve as a device fingerprint even when banners are stripped or spoofed?

### Exercise 19: Differential Analysis & Vulnerability Propagation

Differential analysis compares protocol responses across devices of the same type to detect outliers. If three Hikvision cameras all respond the same way but a fourth differs, that deviation may indicate a modified firmware, a backdoor, or a compromised device. The engine also propagates findings: if a vulnerability is confirmed on one device model, it flags other devices running the same firmware as potentially affected.

**Step 1: View differential analysis results**

```bash
# Get all differential anomalies for the scan
curl -s http://localhost:8100/v1/protocols/differential/$SCAN_ID \
  -H "Authorization: Bearer $TOKEN" | jq .

# Detail each anomaly: which device deviates, and from which peers
curl -s http://localhost:8100/v1/protocols/differential/$SCAN_ID \
  -H "Authorization: Bearer $TOKEN" \
  | jq '.data.anomalies[] | {device_group, anomalous_ip, peer_ips, anomaly_score, description}'
```

**Step 2: Examine propagated findings**

```bash
# Filter findings for propagated vulnerabilities
curl -s http://localhost:8100/v1/protocols/findings/$SCAN_ID \
  -H "Authorization: Bearer $TOKEN" \
  | jq '[.data.findings[] | select(.finding_type == "propagated_finding")]
        | map({ip, title, severity, propagated_from, confidence})'
```

**Step 3: Cross-reference with device identification**

```bash
# Compare: are the devices in the same differential group identified as the same type?
curl -s http://localhost:8100/v1/scanning/smart-scan/$SCAN_ID/results \
  -H "Authorization: Bearer $TOKEN" \
  | jq '.hosts[] | select(.ip == "172.30.0.10" or .ip == "172.30.0.12" or .ip == "172.30.0.13")
        | {ip, device_type, hostname}'
```

**Questions:**
1. How many differential anomalies were detected? For each, explain what the `anomaly_score` represents. A score of 0.0 means no deviation; a score approaching 1.0 means the device responded very differently from its peers.
2. Why is differential analysis particularly effective for detecting compromised or backdoored IoT devices? Consider a scenario where an attacker has modified the firmware of one camera in a fleet of identical units.
3. Propagated findings have a `confidence` field. Why might a propagated finding have lower confidence than a directly observed finding? What additional verification steps would you recommend before acting on a propagated finding?
4. A fleet of 50 identical IP cameras was deployed from the same vendor shipment. Differential analysis reveals that 3 cameras have a different HTTP response fingerprint. List three benign explanations and three malicious explanations for this deviation.

### Exercise 20: Protocol Fuzzing & Attack Chains

The protocol fuzzer generates mutated protocol messages guided by the inferred grammar and sends them to target devices, monitoring for crashes, hangs, and unexpected responses. A safety guard and circuit breaker prevent destructive testing. Attack chain planning combines multiple findings into multi-step exploitation scenarios with proof-of-concept scripts.

**Step 1: View fuzzer coverage metrics**

```bash
# Get fuzzer coverage for a specific device
curl -s http://localhost:8100/v1/protocols/fuzzer-coverage/$SCAN_ID/172.30.0.10 \
  -H "Authorization: Bearer $TOKEN" | jq .

# Compare fuzzing depth across devices
for IP in 172.30.0.10 172.30.0.11 172.30.0.30; do
  echo "--- $IP ---"
  curl -s http://localhost:8100/v1/protocols/fuzzer-coverage/$SCAN_ID/$IP \
    -H "Authorization: Bearer $TOKEN" \
    | jq '{ip: .data.ip, states_tested: .data.states_tested,
           total_states: .data.total_states, mutations_sent: .data.mutations_sent,
           anomalies_found: .data.anomalies_found, coverage_percent: .data.coverage_percent}'
done
```

**Step 2: Examine attack chain plans**

```bash
# Get attack chains for a target device
curl -s http://localhost:8100/v1/protocols/attack-chains/$SCAN_ID/172.30.0.10 \
  -H "Authorization: Bearer $TOKEN" | jq .

# View chain details: steps, severity, and feasibility
curl -s http://localhost:8100/v1/protocols/attack-chains/$SCAN_ID/172.30.0.10 \
  -H "Authorization: Bearer $TOKEN" \
  | jq '.data.chains[] | {description, total_severity, feasibility,
         validated_steps, steps: [.steps[] | {protocol, action, port}]}'
```

**Step 3: Identify the highest-severity exploit paths**

```bash
# Find findings that drive attack chains (auth bypass, command injection, buffer overflow)
curl -s http://localhost:8100/v1/protocols/findings/$SCAN_ID \
  -H "Authorization: Bearer $TOKEN" \
  | jq '[.data.findings[] | select(.finding_type == "auth_bypass"
         or .finding_type == "command_injection"
         or .finding_type == "buffer_overflow")]
        | sort_by(-.cvss_score)
        | map({ip, finding_type, severity, title, cwe_id, mitre_technique, cvss_score})'
```

**Questions:**
1. What is the `coverage_percent` for the fuzzed devices? A coverage of 100% means every grammar state was tested with mutations. Why is 100% coverage difficult to achieve in practice, and what does low coverage imply about undiscovered vulnerabilities?
2. The safety guard prevents fuzzing from causing permanent device damage. What mechanisms does a circuit breaker use to detect that a target device is becoming unstable (consider response latency spikes, connection resets, service unavailability)?
3. Examine an attack chain with multiple steps. What is the `feasibility` score? How does the planner estimate feasibility (consider: does each step's postconditions satisfy the next step's preconditions)?
4. Attack chain planning generates proof-of-concept scripts. In a real engagement, what ethical and legal constraints govern the use of PoC exploits against production IoT devices? How does a "lab environment" like this simulation change those constraints?

### Exercise 21: Hidden Endpoint & Debug Interface Discovery

The web endpoint scanner and debug interface detector probe for undocumented paths (e.g., `/cgi-bin/debug`, `/api/v1/admin/factory-reset`, `/dev/console`) and debug interfaces (JTAG, UART, telnet backdoors, factory test modes) that manufacturers leave enabled in production firmware. These findings map to CWE-912 (Hidden Functionality) and MITRE ICS technique T0886.

**Step 1: Filter for hidden endpoint and debug interface findings**

```bash
# Hidden endpoints discovered during the scan
curl -s http://localhost:8100/v1/protocols/findings/$SCAN_ID \
  -H "Authorization: Bearer $TOKEN" \
  | jq '[.data.findings[] | select(.finding_type == "hidden_endpoint")]
        | map({ip, port, title, severity, evidence, cwe_id})'

# Debug interfaces discovered
curl -s http://localhost:8100/v1/protocols/findings/$SCAN_ID \
  -H "Authorization: Bearer $TOKEN" \
  | jq '[.data.findings[] | select(.finding_type == "debug_interface")]
        | map({ip, port, title, severity, evidence, cwe_id})'
```

**Step 2: Examine finding details and remediation**

```bash
# Get full details including remediation guidance for hidden endpoint findings
curl -s http://localhost:8100/v1/protocols/findings/$SCAN_ID \
  -H "Authorization: Bearer $TOKEN" \
  | jq '.data.findings[] | select(.finding_type == "hidden_endpoint" or .finding_type == "debug_interface")
        | {ip, port, finding_type, severity, title, description, remediation, cwe_id, mitre_technique}'
```

**Step 3: Correlate with attack chains**

```bash
# Check if hidden endpoints feed into attack chains
DEVICE_IP="172.30.0.10"
curl -s http://localhost:8100/v1/protocols/attack-chains/$SCAN_ID/$DEVICE_IP \
  -H "Authorization: Bearer $TOKEN" \
  | jq '.data.chains[] | select(.steps[] | .action | test("hidden|debug"; "i"))
        | {description, feasibility, steps: [.steps[] | {action, protocol}]}'
```

**Questions:**
1. How many hidden endpoints and debug interfaces were discovered across all devices? Which device types (cameras, NAS, routers) tend to have the most hidden functionality? Why?
2. CWE-912 (Hidden Functionality) is the CWE assigned to hidden endpoints. Read the CWE description at [cwe.mitre.org/data/definitions/912.html](https://cwe.mitre.org/data/definitions/912.html). Why is hidden functionality classified as a vulnerability even when it was intentionally placed by the manufacturer?
3. A factory test mode endpoint (`/factory/test`) is discovered on an IP camera in production. The endpoint accepts unauthenticated POST requests that can reset the device to factory settings. Describe the attack scenario, the business impact, and three remediation options (consider firmware update, network ACL, and IDS rule).
4. JTAG and UART debug interfaces require physical access. Why does Breakwater still flag them as findings during a network-only scan? How could a network-based attacker leverage knowledge of debug interfaces without physical access (consider supply chain attacks, insider threats, and social engineering)?

### Exercise 22: Licensing & Feature Gating

Breakwater uses a tiered licensing model to control feature access, similar to commercial security platforms. The licensing API exposes the current tier, usage metering (scans per month, subnets, devices), and tier capabilities. Understanding licensing architecture is important because most enterprise security tools gate their most powerful features behind paid tiers.

**Step 1: Check the current license status**

```bash
# View current license tier and usage
curl -s http://localhost:8100/v1/licensing/status \
  -H "Authorization: Bearer $TOKEN" | jq .

# Extract key limits and usage
curl -s http://localhost:8100/v1/licensing/status \
  -H "Authorization: Bearer $TOKEN" \
  | jq '{tier: .data.license.tier, valid: .data.license.is_valid,
         max_subnets: .data.license.max_subnets,
         max_devices: .data.license.max_devices,
         max_scans_per_month: .data.license.max_scans_per_month,
         scans_used: .data.license.scans_used_this_month,
         features: .data.license.features}'
```

**Step 2: Compare all license tiers**

```bash
# List all available tiers and their capabilities
curl -s http://localhost:8100/v1/licensing/tiers \
  -H "Authorization: Bearer $TOKEN" | jq .

# Side-by-side comparison: features per tier
curl -s http://localhost:8100/v1/licensing/tiers \
  -H "Authorization: Bearer $TOKEN" \
  | jq '.data.tiers[] | {tier, max_subnets, max_devices, max_scans_per_month,
         unlimited_subnets, unlimited_devices, unlimited_scans,
         feature_count: (.features | length), features}'
```

**Step 3: View usage metering**

```bash
# Current billing period usage
curl -s http://localhost:8100/v1/licensing/usage \
  -H "Authorization: Bearer $TOKEN" | jq .
```

**Questions:**
1. The lab runs on the Community tier. Which features are available in Community, and which are locked behind Professional or Enterprise? Identify at least three features that require a paid tier, and explain why a vendor would gate those specific capabilities (consider: cost to operate, competitive differentiation, and customer segmentation).
2. The Community tier limits scans to 10 per month, 1 subnet, and 256 devices. The Enterprise tier has no limits. Design a pricing page for a hypothetical security platform with three tiers. For each tier, specify: target customer (e.g., home lab, SMB, enterprise SOC), monthly price, and the 5 most important features included. Justify your pricing strategy.
3. Usage metering tracks `scans_this_month`, `unique_subnets`, and `total_devices`. Why is metering important for a SaaS security platform beyond billing? Consider: capacity planning, abuse prevention, fair use enforcement, and customer success monitoring.
4. The MSSP (Managed Security Service Provider) tier includes `multi_tenant`, `white_label`, and `billing_api` features. Why would an MSSP need these features? Design a scenario where an MSSP manages 10 client networks using Breakwater and explain how multi-tenancy and white-labeling create business value.

## Cleanup

```bash
docker compose down -v    # Stop containers and remove data
```

## Troubleshooting

**Containers not starting?**
```bash
docker compose ps         # Check container status
docker compose logs api   # Check API logs
```

**Scan not finding devices?**
- Wait 30 seconds after `docker compose up -d` for all containers to start
- Run: `./wait-for-lab.sh`
- Check: `docker compose ps` - all containers should be "running" or "healthy"

**Scan timing out?**
- The full 7-phase scan takes 10-15 minutes
- Set a longer timeout: `SCAN_TIMEOUT=1800 python scan_report.py 172.30.0.0/24`

**Port 8100 already in use?**
- Set `BREAKWATER_LAB_API_PORT=8200` in `student-lab/.env`
- Restart: `docker compose up -d`
- Then: `API_URL=http://127.0.0.1:8200 python scan_report.py 172.30.0.0/24`
