"""IoT Device Simulator — multi-protocol network fingerprint emulator.

Reads a device profile JSON and starts async protocol listeners that mimic
the network behavior of real IoT devices, allowing the Breakwater scanner
to discover and identify them.

Supported protocol types:
  http        — HTTP server with configurable <title>, Server header, auth, vuln endpoints
  tls         — HTTPS server with self-signed cert (configurable issuer)
  rtsp        — RTSP OPTIONS responder with Server header and auth
  ssh_server  — SSH server accepting password auth (via asyncssh)
  ssh_banner  — SSH-2.0 banner on TCP connect (legacy, no auth)
  ssdp        — UPnP/SSDP M-SEARCH responder + description.xml
  mdns        — Zeroconf service advertisement
  raw_tcp     — Accept-and-close TCP listener (port appears "open")
"""

from __future__ import annotations

import asyncio
import base64
import json
import logging
import os
import signal
import socket
import ssl
import struct
import sys

from aiohttp import web

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(name)s] %(message)s",
    datefmt="%H:%M:%S",
)
LOG = logging.getLogger("iotsim")

# Shared state for SSDP → HTTP description.xml serving
_ssdp_config: dict | None = None
_device_ip: str = ""


def _check_basic_auth(request_text: str, credentials: list[dict]) -> bool:
    """Check Basic auth header against credential list.

    Returns True if credentials match, False otherwise.
    """
    if not credentials:
        return False

    # Find Authorization header
    auth_header = ""
    for line in request_text.split("\r\n"):
        if line.lower().startswith("authorization:"):
            auth_header = line.split(":", 1)[1].strip()
            break

    if not auth_header or not auth_header.lower().startswith("basic "):
        return False

    try:
        decoded = base64.b64decode(auth_header.split(" ", 1)[1]).decode()
        user, passwd = decoded.split(":", 1)
    except Exception:
        return False

    for cred in credentials:
        if cred["username"] == user and cred["password"] == passwd:
            return True
    return False


def _check_aiohttp_basic_auth(request: web.Request, credentials: list[dict]) -> bool:
    """Check Basic auth from an aiohttp request."""
    if not credentials:
        return False
    auth_header = request.headers.get("Authorization", "")
    if not auth_header or not auth_header.lower().startswith("basic "):
        return False
    try:
        decoded = base64.b64decode(auth_header.split(" ", 1)[1]).decode()
        user, passwd = decoded.split(":", 1)
    except Exception:
        return False
    for cred in credentials:
        if cred["username"] == user and cred["password"] == passwd:
            return True
    return False


# ---------------------------------------------------------------------------
# Protocol handlers
# ---------------------------------------------------------------------------

async def _run_http_server(cfg: dict) -> None:
    """Start an HTTP server with configurable title, auth, and vuln endpoints."""
    port = cfg["port"]
    title = cfg.get("title", "IoT Device")
    server_header = cfg.get("server_header", "")
    realm = cfg.get("realm", "")
    credentials = cfg.get("credentials", [])
    vuln_endpoints = cfg.get("vuln_endpoints", [])

    html = (
        f"<html><head><title>{title}</title></head>"
        f"<body><h1>{title}</h1></body></html>"
    )

    # Build vuln endpoint lookup: path -> {response, content_type, status, auth_bypass}
    vuln_map: dict[str, dict] = {}
    for ep in vuln_endpoints:
        vuln_map[ep["path"]] = ep

    async def handle_description_xml(request: web.Request) -> web.Response:
        """Serve UPnP device description XML for SSDP."""
        if not _ssdp_config:
            return web.Response(status=404)
        xml = _build_upnp_xml(_ssdp_config)
        return web.Response(text=xml, content_type="text/xml")

    async def handle_request(request: web.Request) -> web.Response:
        headers: dict[str, str] = {}
        if server_header:
            headers["Server"] = server_header

        path = request.path

        # Check if this is a vulnerable endpoint
        if path in vuln_map:
            ep = vuln_map[path]
            # Some vuln endpoints bypass auth (the whole point of the vuln)
            if not ep.get("auth_required", False):
                return web.Response(
                    text=ep["response"],
                    content_type=ep.get("content_type", "text/html"),
                    status=ep.get("status", 200),
                    headers=headers,
                )
            # Auth-required vuln endpoint — check creds
            if credentials and _check_aiohttp_basic_auth(request, credentials):
                return web.Response(
                    text=ep["response"],
                    content_type=ep.get("content_type", "text/html"),
                    status=ep.get("status", 200),
                    headers=headers,
                )

        # Normal auth handling
        if realm and credentials:
            # Auth is required — check credentials
            if _check_aiohttp_basic_auth(request, credentials):
                # Authenticated — serve content
                return web.Response(
                    text=html, content_type="text/html",
                    status=200, headers=headers,
                )
            # Not authenticated — 401 (still serve branded HTML for scanner extraction)
            headers["WWW-Authenticate"] = f'Basic realm="{realm}"'
            return web.Response(
                text=html, content_type="text/html",
                status=401, headers=headers,
            )

        if realm:
            # Realm set but no credentials — always 401
            headers["WWW-Authenticate"] = f'Basic realm="{realm}"'
            return web.Response(
                text=html, content_type="text/html",
                status=401, headers=headers,
            )

        return web.Response(text=html, content_type="text/html", headers=headers)

    app = web.Application()
    app.router.add_get("/description.xml", handle_description_xml)
    app.router.add_route("*", "/{path:.*}", handle_request)

    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, "0.0.0.0", port)
    await site.start()
    LOG.info("HTTP listening on :%d (title=%r, creds=%d, vuln_endpoints=%d)",
             port, title, len(credentials), len(vuln_endpoints))
    # Keep running forever
    await asyncio.Event().wait()


async def _run_tls_server(cfg: dict) -> None:
    """Start an HTTPS server with a self-signed cert."""
    from certs import generate_cert

    port = cfg["port"]
    issuer_org = cfg.get("issuer_org", "IoT Simulator")
    subject_cn = cfg.get("subject_cn", "localhost")
    title = cfg.get("title", issuer_org)
    server_header = cfg.get("server_header", "")

    cert_path, key_path = generate_cert(subject_cn, issuer_org)
    ssl_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ssl_ctx.load_cert_chain(cert_path, key_path)

    html = (
        f"<html><head><title>{title}</title></head>"
        f"<body><h1>{title}</h1></body></html>"
    )

    async def handle(request: web.Request) -> web.Response:
        headers = {}
        if server_header:
            headers["Server"] = server_header
        return web.Response(text=html, content_type="text/html", headers=headers)

    app = web.Application()
    app.router.add_route("*", "/{path:.*}", handle)

    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, "0.0.0.0", port, ssl_context=ssl_ctx)
    await site.start()
    LOG.info("TLS listening on :%d (issuer=%r)", port, issuer_org)
    await asyncio.Event().wait()


async def _run_rtsp_server(cfg: dict) -> None:
    """Minimal RTSP responder — answers OPTIONS with Server header and auth."""
    port = cfg["port"]
    server_header = cfg.get("server_header", "IoT-Sim RTSP")
    realm = cfg.get("realm", "")
    credentials = cfg.get("credentials", [])

    async def handle_client(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        try:
            data = await asyncio.wait_for(reader.read(4096), timeout=5.0)
        except (asyncio.TimeoutError, ConnectionError):
            writer.close()
            return

        text = data.decode(errors="replace")
        # Extract CSeq
        cseq = "1"
        for line in text.split("\r\n"):
            if line.lower().startswith("cseq:"):
                cseq = line.split(":", 1)[1].strip()
                break

        # Check auth if credentials configured
        if realm and credentials:
            if _check_basic_auth(text, credentials):
                # Authenticated — 200 OK
                response_lines = [
                    "RTSP/1.0 200 OK",
                    f"CSeq: {cseq}",
                    f"Server: {server_header}",
                    "Public: OPTIONS, DESCRIBE, SETUP, PLAY, TEARDOWN",
                    "",
                    "",
                ]
            else:
                # Not authenticated — 401
                response_lines = [
                    "RTSP/1.0 401 Unauthorized",
                    f"CSeq: {cseq}",
                    f"Server: {server_header}",
                    f'WWW-Authenticate: Basic realm="{realm}"',
                    "",
                    "",
                ]
        else:
            response_lines = [
                "RTSP/1.0 200 OK",
                f"CSeq: {cseq}",
                f"Server: {server_header}",
                "Public: OPTIONS, DESCRIBE, SETUP, PLAY, TEARDOWN",
            ]
            if realm:
                response_lines.append(f'WWW-Authenticate: Basic realm="{realm}"')
            response_lines.append("")
            response_lines.append("")

        writer.write("\r\n".join(response_lines).encode())
        await writer.drain()
        writer.close()

    server = await asyncio.start_server(handle_client, "0.0.0.0", port)
    LOG.info("RTSP listening on :%d (server=%r, creds=%d)", port, server_header, len(credentials))
    async with server:
        await server.serve_forever()


async def _run_ssh_server(cfg: dict) -> None:
    """SSH server accepting password authentication via asyncssh."""
    try:
        import asyncssh
    except ImportError:
        LOG.warning("asyncssh not installed, falling back to banner-only SSH")
        await _run_ssh_banner(cfg)
        return

    port = cfg["port"]
    banner = cfg.get("banner", "OpenSSH_8.4p1 Debian-5+deb11u3")
    credentials = cfg.get("credentials", [])

    class SimSSHServer(asyncssh.SSHServer):
        def connection_made(self, conn: asyncssh.SSHServerConnection) -> None:
            pass

        def begin_auth(self, username: str) -> bool:
            # Return True to require authentication
            return bool(credentials)

        def password_auth_supported(self) -> bool:
            return True

        def validate_password(self, username: str, password: str) -> bool:
            for cred in credentials:
                if cred["username"] == username and cred["password"] == password:
                    LOG.info("SSH auth success: %s@:%d", username, port)
                    return True
            return False

    # Generate a host key
    key = asyncssh.generate_private_key("ssh-rsa", 2048)

    try:
        await asyncssh.create_server(
            SimSSHServer,
            host="0.0.0.0",
            port=port,
            server_host_keys=[key],
            server_version=f"SSH-2.0-{banner}",
            process_factory=None,
        )
        LOG.info("SSH server on :%d (banner=%r, creds=%d)", port, banner, len(credentials))
        await asyncio.Event().wait()
    except Exception as e:
        LOG.error("SSH server failed on :%d: %s, falling back to banner", port, e)
        await _run_ssh_banner(cfg)


async def _run_ssh_banner(cfg: dict) -> None:
    """Send SSH version banner on connect — triggers nmap -sV detection."""
    port = cfg["port"]
    banner = cfg.get("banner", "OpenSSH_8.4p1 Debian-5+deb11u3")

    async def handle_client(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        writer.write(f"SSH-2.0-{banner}\r\n".encode())
        await writer.drain()
        # Wait briefly for client to read, then close
        try:
            await asyncio.wait_for(reader.read(1024), timeout=2.0)
        except (asyncio.TimeoutError, ConnectionError):
            pass
        writer.close()

    server = await asyncio.start_server(handle_client, "0.0.0.0", port)
    LOG.info("SSH banner on :%d (banner=%r)", port, banner)
    async with server:
        await server.serve_forever()


async def _run_ssdp_server(cfg: dict) -> None:
    """Respond to SSDP M-SEARCH unicast requests."""
    global _ssdp_config
    _ssdp_config = cfg

    # Find the HTTP port for LOCATION header
    http_port = cfg.get("http_port", 80)

    loop = asyncio.get_running_loop()

    class SsdpProtocol(asyncio.DatagramProtocol):
        def connection_made(self, transport: asyncio.DatagramTransport) -> None:
            self.transport = transport

        def datagram_received(self, data: bytes, addr: tuple[str, int]) -> None:
            text = data.decode(errors="replace")
            if "M-SEARCH" not in text:
                return

            ip = _device_ip or "0.0.0.0"
            response = (
                "HTTP/1.1 200 OK\r\n"
                f"LOCATION: http://{ip}:{http_port}/description.xml\r\n"
                "ST: upnp:rootdevice\r\n"
                f"USN: uuid:iotsim-{cfg.get('friendly_name', 'device')}::upnp:rootdevice\r\n"
                "CACHE-CONTROL: max-age=1800\r\n"
                f"SERVER: IoT-Sim UPnP/1.0\r\n"
                "\r\n"
            )
            self.transport.sendto(response.encode(), addr)

    transport, _ = await loop.create_datagram_endpoint(
        SsdpProtocol, local_addr=("0.0.0.0", 1900),
        family=socket.AF_INET,
    )
    LOG.info("SSDP listening on :1900 (manufacturer=%r)", cfg.get("manufacturer"))
    await asyncio.Event().wait()


def _build_upnp_xml(cfg: dict) -> str:
    """Build UPnP device description XML from SSDP config."""
    friendly = cfg.get("friendly_name", "IoT Device")
    manufacturer = cfg.get("manufacturer", "")
    model = cfg.get("model_name", "")
    device_type = cfg.get("device_type_urn", "urn:schemas-upnp-org:device:Basic:1")

    services_xml = ""
    for svc in cfg.get("upnp_services", []):
        svc_type = svc.get("type", "")
        ctrl_url = svc.get("control_url", "/ctrl")
        services_xml += f"""      <service>
        <serviceType>{svc_type}</serviceType>
        <controlURL>{ctrl_url}</controlURL>
      </service>
"""

    return f"""<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <specVersion><major>1</major><minor>0</minor></specVersion>
  <device>
    <deviceType>{device_type}</deviceType>
    <friendlyName>{friendly}</friendlyName>
    <manufacturer>{manufacturer}</manufacturer>
    <modelName>{model}</modelName>
    <serviceList>
{services_xml}    </serviceList>
  </device>
</root>"""


async def _run_mdns_advertiser(cfg: dict) -> None:
    """Register mDNS/Zeroconf services on the network."""
    try:
        from zeroconf import Zeroconf, ServiceInfo
    except ImportError:
        LOG.warning("zeroconf not installed, skipping mDNS")
        return

    ip = _device_ip
    if not ip or ip == "0.0.0.0":
        LOG.warning("No device IP for mDNS, skipping")
        return

    ip_bytes = socket.inet_aton(ip)
    zc = Zeroconf(interfaces=[ip])
    infos = []

    for svc in cfg.get("services", []):
        svc_type = svc["type"]
        svc_name = svc.get("name", f"iotsim.{svc_type}")
        svc_port = svc.get("port", 80)
        txt = svc.get("txt", {})

        info = ServiceInfo(
            svc_type,
            svc_name,
            addresses=[ip_bytes],
            port=svc_port,
            properties=txt,
        )
        zc.register_service(info)
        infos.append(info)
        LOG.info("mDNS registered: %s on %s:%d", svc_type, ip, svc_port)

    await asyncio.Event().wait()

    for info in infos:
        zc.unregister_service(info)
    zc.close()


async def _run_raw_tcp(cfg: dict) -> None:
    """Open TCP ports that accept and close — appear as 'open' to scanners."""
    ports = cfg.get("ports", [])
    servers = []
    for port in ports:
        async def handle(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, p: int = port) -> None:
            # Accept the connection, wait briefly, close
            try:
                await asyncio.wait_for(reader.read(1), timeout=1.0)
            except (asyncio.TimeoutError, ConnectionError):
                pass
            writer.close()

        server = await asyncio.start_server(handle, "0.0.0.0", port)
        servers.append(server)
        LOG.info("Raw TCP listening on :%d", port)

    await asyncio.Event().wait()


# ---------------------------------------------------------------------------
# Protocol dispatch
# ---------------------------------------------------------------------------

PROTOCOL_HANDLERS = {
    "http": _run_http_server,
    "tls": _run_tls_server,
    "rtsp": _run_rtsp_server,
    "ssh_server": _run_ssh_server,
    "ssh_banner": _run_ssh_banner,
    "ssdp": _run_ssdp_server,
    "mdns": _run_mdns_advertiser,
    "raw_tcp": _run_raw_tcp,
}


async def main() -> None:
    global _device_ip

    profile_path = os.environ.get("DEVICE_PROFILE")
    if not profile_path:
        LOG.error("DEVICE_PROFILE env var not set")
        sys.exit(1)

    with open(profile_path) as f:
        profile = json.load(f)

    name = profile.get("name", "unknown")
    _device_ip = os.environ.get("DEVICE_IP", "")

    # Auto-detect IP if not provided
    if not _device_ip:
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("172.30.0.1", 80))
            _device_ip = s.getsockname()[0]
            s.close()
        except OSError:
            _device_ip = "0.0.0.0"

    LOG.info("Starting IoT simulator: %s (IP: %s)", name, _device_ip)

    protocols = profile.get("protocols", [])
    if not protocols:
        LOG.info("No protocols configured — running as passive device (MAC-only)")
        # Keep container alive for MAC-based discovery
        await asyncio.Event().wait()
        return

    tasks = []
    for proto_cfg in protocols:
        proto_type = proto_cfg.get("type")
        handler = PROTOCOL_HANDLERS.get(proto_type)
        if not handler:
            LOG.warning("Unknown protocol type: %s", proto_type)
            continue
        tasks.append(asyncio.create_task(handler(proto_cfg)))

    # Wait forever (or until signal)
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, stop.set)

    await stop.wait()
    for t in tasks:
        t.cancel()


if __name__ == "__main__":
    asyncio.run(main())
