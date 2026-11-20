"""Generate self-signed X.509 certificates with configurable issuer fields.

Used by the IoT simulator to present TLS certificates that trigger
the scanner's TLS issuer identification rules.
"""

from __future__ import annotations

import datetime
import tempfile

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID


def generate_cert(
    subject_cn: str,
    issuer_org: str,
    issuer_cn: str | None = None,
) -> tuple[str, str]:
    """Create a self-signed cert and return (cert_path, key_path)."""
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    subject = x509.Name([
        x509.NameAttribute(NameOID.COMMON_NAME, subject_cn),
    ])
    issuer = x509.Name([
        x509.NameAttribute(NameOID.ORGANIZATION_NAME, issuer_org),
        x509.NameAttribute(NameOID.COMMON_NAME, issuer_cn or subject_cn),
    ])
    now = datetime.datetime.utcnow()
    cert = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now)
        .not_valid_after(now + datetime.timedelta(days=3650))
        .sign(key, hashes.SHA256())
    )

    cert_path = tempfile.mktemp(suffix=".pem")
    key_path = tempfile.mktemp(suffix=".key")
    with open(cert_path, "wb") as f:
        f.write(cert.public_bytes(serialization.Encoding.PEM))
    with open(key_path, "wb") as f:
        f.write(key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.TraditionalOpenSSL,
            serialization.NoEncryption(),
        ))
    return cert_path, key_path
