#!/usr/bin/env python3
"""Run a progressive scan and render results as a rich table report.

Usage:
    python scan_report.py [SUBNET]
    python scan_report.py 172.30.0.0/24
    python scan_report.py --lab-targets

Environment:
    API_URL           Base URL of the Breakwater API (default: http://localhost:8100)
    SCAN_EMAIL        Login email  (default: auto-register a throwaway user)
    SCAN_PASSWORD     Login password
    SCAN_TIMEOUT      Max wait seconds (default: 600)
    SCAN_DISCOVERY    Set to "1" for discovery-only (skip enrichment/ident/CVE)
"""

from __future__ import annotations

import argparse
import os
import sys
import time

import httpx
from rich.console import Console
from rich.live import Live
from rich.table import Table
from rich.text import Text

API_URL = os.getenv("API_URL", "http://localhost:8100").rstrip("/")
DISCOVERY_ONLY = os.getenv("SCAN_DISCOVERY", "0") in {"1", "true", "yes"}
POLL_INTERVAL = 2.0
LAB_SUBNET = "172.30.0.0/24"
LAB_TARGETS = [
    "172.30.0.10",
    "172.30.0.11",
    "172.30.0.12",
    "172.30.0.13",
    "172.30.0.14",
    "172.30.0.15",
    "172.30.0.20",
    "172.30.0.21",
    "172.30.0.22",
    "172.30.0.23",
    "172.30.0.24",
    "172.30.0.30",
    "172.30.0.31",
    "172.30.0.32",
    "172.30.0.33",
    "172.30.0.40",
    "172.30.0.50",
    "172.30.0.51",
    "172.30.0.52",
    "172.30.0.60",
    "172.30.0.61",
    "172.30.0.62",
]


def _compute_timeout(subnet: str) -> int:
    """Scale scan timeout by network prefix length.

    /24 → 900s, /20 → 1800s, /16 → 3600s.  Explicit SCAN_TIMEOUT env
    var overrides the dynamic calculation.  Each vuln-scanning phase
    (nuclei, openvas, default_creds) extends the deadline by +900s.
    """
    explicit = os.getenv("SCAN_TIMEOUT")
    if explicit:
        return int(explicit)
    try:
        prefix = int(subnet.split("/")[1]) if "/" in subnet else 24
    except (ValueError, IndexError):
        prefix = 24
    # Base 900s for /24, double every 4 prefix bits
    return int(900 * (2 ** ((24 - max(prefix, 16)) / 4)))

console = Console()


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _parse_args() -> argparse.Namespace:
    """Parse CLI arguments while preserving the existing positional subnet form."""
    parser = argparse.ArgumentParser(
        description="Run a progressive Breakwater scan and render a rich report.",
    )
    parser.add_argument(
        "subnet",
        nargs="?",
        help="CIDR subnet or single IP to scan. Omit to auto-detect.",
    )
    parser.add_argument(
        "--lab-targets",
        action="store_true",
        help="Scan the known IoT simulation devices instead of the whole lab /24.",
    )
    args = parser.parse_args()
    if args.lab_targets and args.subnet:
        parser.error("--lab-targets cannot be combined with a positional subnet")
    return args


# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------

def _get_token(client: httpx.Client) -> str:
    """Authenticate and return an access token."""
    email = os.getenv("SCAN_EMAIL", "")
    password = os.getenv("SCAN_PASSWORD", "")

    if email and password:
        r = client.post(f"{API_URL}/v1/auth/login", json={"email": email, "password": password})
        if r.status_code == 200:
            return r.json()["access_token"]
        console.print(f"[red]Login failed ({r.status_code}): {r.text}[/red]")
        sys.exit(1)

    # Auto-register a throwaway scan user
    ts = int(time.time())
    email = f"scan-{ts}@cli.breakwater.dev"
    password = f"ScanCLI!{ts}"
    r = client.post(
        f"{API_URL}/v1/auth/register",
        json={"email": email, "password": password, "full_name": "CLI Scanner"},
    )
    if r.status_code not in (200, 201):
        console.print(f"[red]Auto-register failed ({r.status_code}): {r.text}[/red]")
        sys.exit(1)
    return r.json()["access_token"]


# ---------------------------------------------------------------------------
# Network detection
# ---------------------------------------------------------------------------

def _detect_subnet(client: httpx.Client, headers: dict) -> str:
    """Auto-detect local subnet via the API."""
    r = client.get(f"{API_URL}/v1/scanning/detect-range", headers=headers, timeout=10)
    if r.status_code != 200:
        console.print("[red]Failed to auto-detect network range[/red]")
        sys.exit(1)
    data = r.json()
    subnet = data.get("subnet", "")
    console.print(f"Auto-detected network: [cyan]{subnet}[/cyan]")
    return subnet


# ---------------------------------------------------------------------------
# Progress display
# ---------------------------------------------------------------------------

def _make_progress_table(progress: dict, subnet: str, scan_id: str) -> Table:
    """Build a compact progress table."""
    t = Table(title=f"Scan {scan_id[:8]}... — {subnet}", show_header=False, border_style="dim")
    t.add_column("Metric", style="bold")
    t.add_column("Value", justify="right")

    phase = progress.get("phase", "?")
    phase_colors = {
        "discovery": "blue",
        "enrichment": "yellow",
        "identification": "magenta",
        "vulnerability": "red",
        "openvas": "bright_red",
        "nuclei": "bright_magenta",
        "completed": "green",
    }
    color = phase_colors.get(phase, "white")
    t.add_row("Phase", f"[{color}]{phase}[/{color}]")
    t.add_row(
        "Batches",
        f"{progress.get('batches_done', 0)}/{progress.get('batches_total', '?')}",
    )
    t.add_row("Discovered", str(progress.get("discovered", 0)))
    t.add_row("Enriched", str(progress.get("enriched", 0)))
    t.add_row("Identified", str(progress.get("identified", 0)))
    t.add_row("CVE Assessed", str(progress.get("cve_assessed", 0)))
    openvas_count = progress.get("openvas_assessed", 0)
    if int(openvas_count) > 0 or phase == "openvas":
        t.add_row("OpenVAS", str(openvas_count))
    nuclei_count = progress.get("nuclei_assessed", 0)
    if int(nuclei_count) > 0 or phase == "nuclei":
        t.add_row("Nuclei", str(nuclei_count))
    creds_count = progress.get("default_creds_assessed", 0)
    if int(creds_count) > 0 or phase == "default_creds":
        t.add_row("Default Creds", str(creds_count))
    return t


# ---------------------------------------------------------------------------
# Result tables
# ---------------------------------------------------------------------------

def _severity_style(sev: str) -> str:
    sev = (sev or "").lower()
    if sev == "critical":
        return "bold red"
    if sev == "high":
        return "red"
    if sev == "medium":
        return "yellow"
    return "dim"


def _count_severity(cves: list[dict], level: str) -> int:
    """Count CVEs matching a severity level."""
    return sum(1 for c in cves if (c.get("severity") or "").upper() == level.upper())


def _enrichment_detail(enrichment: dict, prefix: str) -> str:
    """Extract a short summary string for an enrichment adapter."""
    vals = {k: v for k, v in enrichment.items() if k.startswith(prefix) and v}
    if not vals:
        return ""
    for suffix in ("_name", "_friendly_name", "_model", "_server", "_title", "_cn", "_hash", "_os"):
        key = prefix + suffix
        if key in vals:
            return str(vals[key])
    # Fallback: pick first scalar (string/number) value, skip lists/dicts
    for v in vals.values():
        if isinstance(v, (str, int, float)):
            return str(v)
    return ""


def _render_report_table(hosts: list[dict]) -> Table:
    """Unified scan report table — identity, software, and vulnerabilities.

    Columns: # | IP | Hostname/Device | MAC/Vendor | Ports | Software | Vulns | Risk
    """
    t = Table(
        title="Scan Report",
        show_lines=True,
        title_style="bold cyan",
        header_style="bold",
        pad_edge=False,
        expand=True,
    )
    t.add_column("#", style="dim", width=3, justify="right")
    t.add_column("IP Address", style="cyan", no_wrap=True, max_width=15)
    t.add_column("Hostname / Device", max_width=18)
    t.add_column("MAC / Vendor", max_width=18)
    t.add_column("Ports", max_width=18)
    t.add_column("Software", max_width=22)
    t.add_column("Vulns", justify="left", max_width=22)
    t.add_column("Risk", justify="center", width=9)

    no = "[dim]-[/dim]"

    # Enrichment adapter prefixes
    _ADAPTER_LABELS = [
        ("mdns_", "mDNS"),
        ("ssdp_", "SSDP"),
        ("tls_", "TLS"),
        ("http_", "HTTP"),
        ("rtsp_", "RTSP"),
        ("onvif_", "ONVIF"),
        ("jarm_", "JARM"),
    ]

    for i, h in enumerate(hosts, 1):
        ip = h.get("ip", "")
        hostname = h.get("hostname", "") or ""
        mac = h.get("mac", "") or ""
        vendor = h.get("vendor") or h.get("mac_vendor") or ""
        device_type = h.get("device_type") or ""
        confidence = h.get("confidence", 0)

        # --- Hostname / Device column ---
        name_parts: list[str] = []
        if hostname:
            name_parts.append(hostname)
        if device_type:
            conf_pct = round(confidence * 100) if confidence <= 1.0 else round(confidence)
            conf_color = "green" if conf_pct >= 80 else "yellow" if conf_pct >= 50 else "red"
            conf_tag = f" [{conf_color}]{conf_pct}%[/{conf_color}]" if conf_pct else ""
            name_parts.append(f"[magenta]{device_type}[/magenta]{conf_tag}")
        name_str = "\n".join(name_parts) if name_parts else no

        # --- MAC / Vendor column ---
        mac_parts: list[str] = []
        if mac:
            mac_parts.append(f"[dim]{mac}[/dim]")
        if vendor:
            mac_parts.append(vendor)
        mac_str = "\n".join(mac_parts) if mac_parts else no

        # --- Open Ports ---
        ports: list[str] = []
        for s in h.get("services", []):
            if s.get("state") == "open":
                port = str(s["port"])
                svc_name = s.get("name") or ""
                if svc_name and svc_name not in ("unknown", "tcpwrapped"):
                    port += f"/{svc_name}"
                ports.append(port)
        if not ports:
            ports = [str(p) for p in h.get("open_ports", [])]
        if len(ports) > 6:
            ports_str = ", ".join(ports[:6]) + f"\n(+{len(ports) - 6} more)"
        else:
            ports_str = ", ".join(ports) if ports else no

        # --- Software column (enrichment adapters + firmware + key versions) ---
        e = h.get("enrichment") or {}
        active_tags: list[str] = []
        best_detail = ""
        for prefix, label in _ADAPTER_LABELS:
            detail = _enrichment_detail(e, prefix)
            if detail:
                active_tags.append(f"[green]{label}[/green]")
                if not best_detail and detail:
                    if len(detail) > 20:
                        detail = detail[:18] + ".."
                    best_detail = detail

        cpes = h.get("cpes", [])
        sw_parts: list[str] = []
        if active_tags:
            sw_parts.append(" ".join(active_tags))
        if best_detail:
            sw_parts.append(f"[dim]{best_detail}[/dim]")
        # Show key software versions from nmap
        for svc in h.get("services", []):
            if svc.get("state") == "open" and svc.get("product") and svc.get("version"):
                prod = svc["product"]
                ver = svc["version"]
                sw_parts.append(f"[dim]{prod}/{ver}[/dim]")
                break  # Just show the first one
        if cpes:
            sw_parts.append(f"[dim]CPE x{len(cpes)}[/dim]")
        fw_ver = h.get("firmware_version")
        if fw_ver:
            fw_src = h.get("firmware_source", "")
            sw_parts.append(f"[cyan]FW:{fw_ver}[/cyan] [dim]({fw_src})[/dim]")

        sw_str = "\n".join(sw_parts) if sw_parts else no

        # --- Vulns column (compact: one line per source with severity counts) ---
        cve_summary = h.get("cve_summary") or {}
        cve_total = cve_summary.get("total", 0)
        cves_list = cve_summary.get("cves", [])
        openvas_vulns = h.get("openvas_vulns") or []
        nuclei_vulns = h.get("nuclei_vulns") or []
        default_creds = h.get("default_creds") or []
        upnp_vulns = h.get("upnp_vulns") or []
        firmware_cves = h.get("firmware_cves") or []

        vuln_parts: list[str] = []

        # Default credentials FIRST — most actionable finding
        if default_creds:
            for c in default_creds:
                proto = c.get("protocol", "?")
                user = c.get("username", "?")
                vuln_parts.append(f"[bold red on dark_red] {proto}:{user}/***** [/bold red on dark_red]")

        # NVD CVEs — compact severity breakdown
        if cve_total:
            n_crit = cve_summary.get("critical") or _count_severity(cves_list, "CRITICAL")
            n_high = cve_summary.get("high") or _count_severity(cves_list, "HIGH")
            sev_tags: list[str] = []
            if n_crit:
                sev_tags.append(f"[bold red]{n_crit}C[/bold red]")
            if n_high:
                sev_tags.append(f"[red]{n_high}H[/red]")
            sev_str = " ".join(sev_tags)
            nvd_line = f"[bold]{cve_total}[/bold] NVD"
            if sev_str:
                nvd_line += f" ({sev_str})"
            vuln_parts.append(nvd_line)
            # Top CVE ID
            if cves_list:
                top = cves_list[0]
                cve_id = top.get("cve_id", "")
                score = top.get("cvss_score")
                severity = (top.get("severity") or "").upper()
                style = _severity_style(severity)
                score_str = f" {score:.1f}" if score else ""
                vuln_parts.append(f"  [{style}]{cve_id}{score_str}[/{style}]")

        # OpenVAS
        if openvas_vulns:
            ov_crit = sum(1 for v in openvas_vulns if v.get("severity") == "CRITICAL")
            ov_high = sum(1 for v in openvas_vulns if v.get("severity") == "HIGH")
            sev_tags = []
            if ov_crit:
                sev_tags.append(f"[bold red]{ov_crit}C[/bold red]")
            if ov_high:
                sev_tags.append(f"[red]{ov_high}H[/red]")
            sev_str = " ".join(sev_tags)
            ov_line = f"[bold]{len(openvas_vulns)}[/bold] OpenVAS"
            if sev_str:
                ov_line += f" ({sev_str})"
            vuln_parts.append(ov_line)

        # Nuclei
        if nuclei_vulns:
            nuc_crit = sum(1 for v in nuclei_vulns if v.get("severity") == "CRITICAL")
            nuc_high = sum(1 for v in nuclei_vulns if v.get("severity") == "HIGH")
            sev_tags = []
            if nuc_crit:
                sev_tags.append(f"[bold red]{nuc_crit}C[/bold red]")
            if nuc_high:
                sev_tags.append(f"[red]{nuc_high}H[/red]")
            sev_str = " ".join(sev_tags)
            nuc_line = f"[bold]{len(nuclei_vulns)}[/bold] Nuclei"
            if sev_str:
                nuc_line += f" ({sev_str})"
            vuln_parts.append(nuc_line)

        # UPnP
        if upnp_vulns:
            upnp_high = sum(1 for v in upnp_vulns if v.get("severity") == "HIGH")
            upnp_crit = sum(1 for v in upnp_vulns if v.get("severity") == "CRITICAL")
            sev_tags = []
            if upnp_crit:
                sev_tags.append(f"[bold red]{upnp_crit}C[/bold red]")
            if upnp_high:
                sev_tags.append(f"[red]{upnp_high}H[/red]")
            sev_str = " ".join(sev_tags)
            upnp_line = f"[bold]{len(upnp_vulns)}[/bold] UPnP"
            if sev_str:
                upnp_line += f" ({sev_str})"
            vuln_parts.append(upnp_line)

        # Firmware CVEs
        if firmware_cves:
            vuln_parts.append(f"[red]{len(firmware_cves)} FW CVEs[/red]")

        vuln_str = "\n".join(vuln_parts) if vuln_parts else no

        # --- Risk badge ---
        cve_critical = cve_summary.get("critical", 0)
        cve_high = cve_summary.get("high", 0)
        ov_critical = sum(1 for v in openvas_vulns if v.get("severity") == "CRITICAL")
        ov_high = sum(1 for v in openvas_vulns if v.get("severity") == "HIGH")
        nuc_critical = sum(1 for v in nuclei_vulns if v.get("severity") == "CRITICAL")
        nuc_high = sum(1 for v in nuclei_vulns if v.get("severity") == "HIGH")
        upnp_critical = sum(1 for v in upnp_vulns if v.get("severity") == "CRITICAL")
        upnp_high_count = sum(1 for v in upnp_vulns if v.get("severity") == "HIGH")
        total_critical = cve_critical + ov_critical + nuc_critical + len(default_creds) + upnp_critical
        total_high = cve_high + ov_high + nuc_high + upnp_high_count + len(firmware_cves)
        total_vulns = (
            cve_total + len(openvas_vulns) + len(nuclei_vulns)
            + len(default_creds) + len(upnp_vulns) + len(firmware_cves)
        )
        if default_creds:
            risk = Text("CREDS!", style="bold red on dark_red")
        elif total_critical:
            risk = Text("CRITICAL", style="bold red")
        elif total_high:
            risk = Text("HIGH", style="red")
        elif total_vulns:
            risk = Text("MEDIUM", style="yellow")
        else:
            risk = Text("-", style="dim")

        t.add_row(
            str(i), ip, name_str, mac_str, ports_str,
            sw_str, vuln_str, risk,
        )

    return t


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def _check_prerequisites() -> None:
    """Verify that required services (API, Redis) are reachable."""
    api = API_URL
    try:
        r = httpx.get(f"{api}/health", timeout=5)
        if r.status_code == 200:
            return  # API is healthy
    except (httpx.ConnectError, httpx.ReadTimeout):
        pass

    console.print()
    console.print("[bold red]Cannot reach the Breakwater API[/bold red]")
    console.print(f"  Tried: {api}/health")
    console.print()
    console.print("[bold]Start the required services first:[/bold]")
    console.print("  [cyan]docker compose up -d[/cyan]       # Start the lab stack")
    console.print("  [cyan]docker compose ps[/cyan]          # Verify api/redis/postgres are up")
    console.print()
    console.print("[dim]If the API is still unreachable:[/dim]")
    console.print("  [cyan]docker compose logs api --tail=50[/cyan]")
    console.print()
    sys.exit(1)


def main() -> None:
    args = _parse_args()
    subnet = LAB_SUBNET if args.lab_targets else (args.subnet or "")

    console.rule("[bold cyan]Breakwater Scan Report[/bold cyan]")

    _check_prerequisites()

    client = httpx.Client(timeout=30)

    # Auth
    console.print("Authenticating...", style="dim")
    token = _get_token(client)
    headers = {"Authorization": f"Bearer {token}"}

    # Detect subnet if not provided
    if not subnet:
        subnet = _detect_subnet(client, headers)

    timeout = _compute_timeout(subnet)
    console.print(f"Target: [bold]{subnet}[/bold]  Timeout: {timeout}s")

    # Start scan
    console.print("Starting progressive scan...", style="dim")
    if args.lab_targets:
        r = client.post(
            f"{API_URL}/v1/scanning/multi-target-scan",
            headers=headers,
            json={
                "targets": LAB_TARGETS,
                "batch_concurrency": 4,
                "discovery_only": DISCOVERY_ONLY,
                "scan_name": "Student Lab Targets",
            },
            timeout=30,
        )
    else:
        r = client.post(
            f"{API_URL}/v1/scanning/smart-scan",
            headers=headers,
            json={
                "subnet": subnet,
                "batch_concurrency": 4,
                "discovery_only": DISCOVERY_ONLY,
            },
            timeout=30,
        )
    if r.status_code != 200:
        console.print(f"[red]Failed to start scan ({r.status_code}): {r.text}[/red]")
        sys.exit(1)

    scan_data = r.json()
    scan_id = scan_data["scan_id"]
    subnet = scan_data.get("subnet") or subnet
    results_url = f"{API_URL}/v1/scanning/smart-scan/{scan_id}/results"

    console.print(
        f"Scan ID: [bold]{scan_id}[/bold]  "
        f"Batches: {scan_data['total_batches']}  "
        f"Est. hosts: {scan_data['estimated_hosts']}"
    )

    # Poll with live progress
    start_time = time.time()
    extended_phases: set[str] = set()
    connection_errors = 0
    with Live(console=console, refresh_per_second=2) as live:
        while True:
            try:
                r = client.get(results_url, headers=headers, timeout=30)
            except (httpx.ConnectError, httpx.ReadTimeout, httpx.WriteTimeout) as exc:
                connection_errors += 1
                if connection_errors > 10:
                    console.print(f"[red]Lost connection to API: {exc}[/red]")
                    sys.exit(1)
                time.sleep(POLL_INTERVAL)
                continue
            connection_errors = 0  # Reset on success
            if r.status_code == 401:
                # Token expired during long scan — re-authenticate
                token = _get_token(client)
                headers = {"Authorization": f"Bearer {token}"}
                continue
            if r.status_code != 200:
                elapsed = time.time() - start_time
                if elapsed > timeout:
                    console.print("[red]Scan timed out[/red]")
                    break
                time.sleep(POLL_INTERVAL)
                continue

            data = r.json()
            progress = data.get("progress", {})
            status = data.get("status", "")

            # Extend deadline when vuln scanning phases start (they can be slow)
            phase = progress.get("phase", "")
            if phase in ("nuclei", "openvas", "default_creds") and phase not in extended_phases:
                timeout += 900
                extended_phases.add(phase)

            elapsed = time.time() - start_time
            if elapsed > timeout:
                console.print("[red]Scan timed out — showing partial results[/red]")
                break

            live.update(_make_progress_table(progress, subnet, scan_id))

            if status in ("completed", "failed", "cancelled"):
                break

            time.sleep(POLL_INTERVAL)

    elapsed = time.time() - start_time
    console.print()

    # Final results — re-authenticate in case the token expired during a long scan
    try:
        r = client.get(results_url, headers=headers, timeout=30)
        if r.status_code == 401:
            token = _get_token(client)
            headers = {"Authorization": f"Bearer {token}"}
            r = client.get(results_url, headers=headers, timeout=30)
        data = r.json()
    except Exception:
        # Last resort: try with a fresh token
        token = _get_token(client)
        headers = {"Authorization": f"Bearer {token}"}
        r = client.get(results_url, headers=headers, timeout=30)
        data = r.json()
    hosts = data.get("hosts", [])
    progress = data.get("progress", {})
    vuln_summary = data.get("vulnerability_summary", {})
    status = data.get("status", "unknown")

    # Status line
    if status == "completed":
        console.print(f"[bold green]Scan completed[/bold green] in {elapsed:.1f}s")
    elif status == "failed":
        console.print(f"[bold red]Scan failed[/bold red] after {elapsed:.1f}s")
    elif status == "cancelled":
        console.print(f"[bold yellow]Scan cancelled[/bold yellow] after {elapsed:.1f}s")
    else:
        console.print(f"[bold yellow]Scan still running ({status})[/bold yellow] — showing results after {elapsed:.1f}s")

    # Summary stats
    console.print()
    console.rule("[bold]Summary[/bold]")
    summary_line = (
        f"  Discovered: [cyan]{progress.get('discovered', 0)}[/cyan]  "
        f"Enriched: [yellow]{progress.get('enriched', 0)}[/yellow]  "
        f"Identified: [magenta]{progress.get('identified', 0)}[/magenta]  "
        f"CVE Assessed: [red]{progress.get('cve_assessed', 0)}[/red]"
    )
    openvas_count = int(progress.get("openvas_assessed", 0))
    if openvas_count:
        summary_line += f"  OpenVAS: [bright_red]{openvas_count}[/bright_red]"
    nuclei_count = int(progress.get("nuclei_assessed", 0))
    if nuclei_count:
        summary_line += f"  Nuclei: [bright_magenta]{nuclei_count}[/bright_magenta]"
    creds_count = int(progress.get("default_creds_assessed", 0))
    if creds_count:
        summary_line += f"  Default Creds: [bold red]{creds_count}[/bold red]"
    console.print(summary_line)
    if vuln_summary.get("total_cves", 0):
        vuln_line = (
            f"  Vulnerabilities: "
            f"[bold red]{vuln_summary.get('critical', 0)} critical[/bold red]  "
            f"[red]{vuln_summary.get('high', 0)} high[/red]  "
            f"Total: {vuln_summary['total_cves']}"
        )
        dc = vuln_summary.get("default_creds", 0)
        if dc:
            vuln_line += f"  [bold red]({dc} default creds)[/bold red]"
        console.print(vuln_line)
    console.print()

    if not hosts:
        console.print("[yellow]No hosts discovered.[/yellow]")
        return

    # Unified scan report table
    console.print(_render_report_table(hosts))
    console.print()

    console.rule(f"[dim]{len(hosts)} hosts — {subnet} — {elapsed:.1f}s[/dim]")


if __name__ == "__main__":
    main()
