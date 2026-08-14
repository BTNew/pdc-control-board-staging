"""Fail-closed staging environment and PostgreSQL connection helpers.

This module is operational support code. It deliberately has no test-fixture
imports, production fallback, password-file fallback, or hard-coded secret.
"""
from __future__ import annotations

import base64
import os
import re
import hashlib
import ssl
from pathlib import Path
from urllib.parse import unquote, urlsplit

EXPECTED_STAGING_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
ROOT = Path(__file__).resolve().parents[1]
ENV_PATH = ROOT / "_staging_test_tools" / ".env"
SSLROOTCERT_ENV = "PDC_STAGING_SSLROOTCERT"
SSLROOTCERT_SHA256_ENV = "PDC_STAGING_SSLROOTCERT_SHA256"


def _der_tlv(payload: bytes, offset: int = 0) -> tuple[int, bytes, int]:
    """Read one strict definite-length DER value."""
    if offset + 2 > len(payload):
        raise ValueError("truncated DER")
    tag, first = payload[offset], payload[offset + 1]
    offset += 2
    if first & 0x80:
        count = first & 0x7F
        if count == 0 or count > 4 or offset + count > len(payload):
            raise ValueError("invalid DER length")
        raw = payload[offset:offset + count]
        if raw[0] == 0:
            raise ValueError("non-minimal DER length")
        length = int.from_bytes(raw, "big")
        if length < 128:
            raise ValueError("non-minimal DER length")
        offset += count
    else:
        length = first
    end = offset + length
    if end > len(payload):
        raise ValueError("truncated DER value")
    return tag, payload[offset:end], end


def _der_children(payload: bytes) -> list[tuple[int, bytes]]:
    children, offset = [], 0
    while offset < len(payload):
        tag, value, offset = _der_tlv(payload, offset)
        children.append((tag, value))
    return children


def _assert_ca_certificate(der: bytes) -> None:
    """Require canonical DER plus CA:TRUE and keyCertSign when Key Usage is present."""
    tag, certificate, end = _der_tlv(der)
    if tag != 0x30 or end != len(der):
        raise ValueError("certificate is not one DER sequence")
    certificate_fields = _der_children(certificate)
    if not certificate_fields or certificate_fields[0][0] != 0x30:
        raise ValueError("certificate TBS sequence is missing")
    extension_wrappers = [value for tag, value in _der_children(certificate_fields[0][1]) if tag == 0xA3]
    if len(extension_wrappers) != 1:
        raise ValueError("certificate extensions are missing or ambiguous")
    wrapper_fields = _der_children(extension_wrappers[0])
    if len(wrapper_fields) != 1 or wrapper_fields[0][0] != 0x30:
        raise ValueError("certificate extensions are malformed")
    extensions: dict[bytes, bytes] = {}
    for tag, extension in _der_children(wrapper_fields[0][1]):
        if tag != 0x30:
            raise ValueError("certificate extension is malformed")
        fields = _der_children(extension)
        if len(fields) not in (2, 3) or fields[0][0] != 0x06 or fields[-1][0] != 0x04:
            raise ValueError("certificate extension fields are malformed")
        # Extension.critical is BOOLEAN DEFAULT FALSE.  Canonical DER omits
        # FALSE, so a present value must be the exact TRUE encoding 01 01 FF.
        if len(fields) == 3 and fields[1] != (0x01, b"\xff"):
            raise ValueError("certificate extension critical flag is malformed")
        oid = fields[0][1]
        if oid in extensions:
            raise ValueError("duplicate certificate extension")
        extensions[oid] = fields[-1][1]
    basic_constraints = extensions.get(b"\x55\x1d\x13")
    if basic_constraints is None:
        raise ValueError("Basic Constraints is missing")
    tag, constraints, end = _der_tlv(basic_constraints)
    fields = _der_children(constraints) if tag == 0x30 and end == len(basic_constraints) else []
    if len(fields) not in (1, 2) or fields[0] != (0x01, b"\xff"):
        raise ValueError("Basic Constraints does not authorize a CA")
    if len(fields) == 2:
        integer_tag, integer_value = fields[1]
        if (
            integer_tag != 0x02
            or not integer_value
            or integer_value[0] & 0x80
            or (len(integer_value) > 1 and integer_value[0] == 0 and integer_value[1] < 0x80)
        ):
            raise ValueError("Basic Constraints path length is not a canonical non-negative INTEGER")
    key_usage = extensions.get(b"\x55\x1d\x0f")
    if key_usage is not None:
        tag, bits, end = _der_tlv(key_usage)
        if (
            tag != 0x03
            or end != len(key_usage)
            or len(bits) < 2
            or bits[0] > 7
            or bits[-1] & ((1 << bits[0]) - 1)
            or not bits[1] & 0x04
        ):
            raise ValueError("Key Usage is non-canonical or does not authorize certificate signing")


def _assert_semantic_ca_bundle(payload: bytes) -> None:
    pattern = re.compile(br"-----BEGIN CERTIFICATE-----\s*(.*?)\s*-----END CERTIFICATE-----", re.DOTALL)
    matches = list(pattern.finditer(payload))
    if not matches:
        raise ValueError("certificate bundle is empty")
    residue = pattern.sub(b"", payload)
    if residue.strip():
        raise ValueError("certificate bundle contains non-certificate data")
    for match in matches:
        der = base64.b64decode(re.sub(br"\s+", b"", match.group(1)), validate=True)
        _assert_ca_certificate(der)


def load_local_env() -> None:
    """Load missing local staging values without overriding process values."""
    if not ENV_PATH.is_file():
        return
    for raw in ENV_PATH.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip())


def required(name: str, *, preserve_raw: bool = False) -> str:
    load_local_env()
    raw_value = os.environ.get(name, "")
    if not raw_value.strip():
        raise RuntimeError(
            f"Missing required environment variable {name}. Configure the "
            "ignored _staging_test_tools/.env file or process environment; "
            "never commit credentials."
        )
    return raw_value if preserve_raw else raw_value.strip()


def _reject_target(value: str, host: str) -> None:
    if PRODUCTION_REF in value.lower():
        raise RuntimeError("Refusing to run staging operation against production")
    raise RuntimeError(
        f"Refusing non-staging target {host!r}; expected project "
        f"reference {EXPECTED_STAGING_REF}."
    )


def _contains_production_marker(value: str) -> bool:
    decoded = value
    while True:
        if re.search(r'%(?![0-9A-Fa-f]{2})', decoded):
            raise RuntimeError('Refusing invalid percent-encoding in staging target')
        if PRODUCTION_REF in decoded.lower():
            return True
        next_decoded = unquote(decoded)
        if next_decoded == decoded:
            return False
        decoded = next_decoded


def _parsed_endpoint(value: str):
    if type(value) is not str or not value or value != value.strip() or any(ord(char) <= 0x20 or ord(char) == 0x7F for char in value):
        _reject_target("", "invalid endpoint")
    if _contains_production_marker(value):
        _reject_target(value, "production marker")
    try:
        parsed = urlsplit(value)
        host = parsed.hostname or ""
        port = parsed.port
    except (TypeError, ValueError, UnicodeError):
        _reject_target("", "invalid endpoint")
    return parsed, host, port


def trusted_sslrootcert() -> str:
    """Return an explicit trusted CA bundle for verify-full connections."""
    raw = required(SSLROOTCERT_ENV, preserve_raw=True)
    if (
        raw != raw.strip()
        or any(ord(char) <= 0x20 or ord(char) == 0x7F for char in raw)
    ):
        raise RuntimeError("Refusing invalid staging TLS CA path")
    path = Path(raw)
    if not path.is_absolute() or path.is_symlink() or not path.is_file():
        raise RuntimeError(
            "PDC_STAGING_SSLROOTCERT must name an absolute, regular, non-symlink CA bundle"
        )
    resolved = path.resolve(strict=True)
    if resolved != path.absolute():
        raise RuntimeError("Refusing non-canonical staging TLS CA path")
    try:
        payload = resolved.read_bytes()
    except OSError as exc:
        raise RuntimeError("Unable to read staging TLS CA bundle") from exc
    if (
        b"-----BEGIN CERTIFICATE-----" not in payload
        or b"-----END CERTIFICATE-----" not in payload
    ):
        raise RuntimeError("Staging TLS CA bundle does not contain a PEM certificate")
    try:
        tls_context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        tls_context.load_verify_locations(cafile=str(resolved))
        _assert_semantic_ca_bundle(payload)
    except (OSError, ssl.SSLError, ValueError) as exc:
        raise RuntimeError("Staging TLS CA bundle is not a parseable certificate bundle") from exc
    expected_sha256 = required(SSLROOTCERT_SHA256_ENV).lower()
    if not re.fullmatch(r"[0-9a-f]{64}", expected_sha256):
        raise RuntimeError("PDC_STAGING_SSLROOTCERT_SHA256 must be an exact SHA-256")
    actual_sha256 = hashlib.sha256(payload).hexdigest()
    if actual_sha256 != expected_sha256:
        raise RuntimeError("Staging TLS CA bundle SHA-256 mismatch")
    return str(resolved)


def staging_tls_kwargs() -> dict[str, str]:
    return {"sslmode": "verify-full", "sslrootcert": trusted_sslrootcert()}


def assert_staging_target(
    project_url: str | None = None,
    database_url: str | None = None,
) -> None:
    """Accept only the exact approved Supabase staging HTTPS/PostgreSQL hosts."""
    if not project_url and not database_url:
        raise RuntimeError("No staging endpoint supplied to target guard")
    if project_url:
        parsed, host, port = _parsed_endpoint(project_url)
        if (
            parsed.scheme != "https"
            or parsed.username is not None
            or parsed.password is not None
            or host != f"{EXPECTED_STAGING_REF}.supabase.co"
            or port is not None
            or parsed.path not in ("", "/")
            or parsed.query
            or parsed.fragment
        ):
            _reject_target(project_url, host or "unknown host")
    if database_url:
        parsed, host, port = _parsed_endpoint(database_url)
        direct = host == f"db.{EXPECTED_STAGING_REF}.supabase.co" and parsed.username == "postgres" and port == 5432
        pooler = (
            bool(re.fullmatch(r"aws-[0-9]+-[a-z0-9]+(?:-[a-z0-9]+)*\.pooler\.supabase\.com", host))
            and parsed.username == f"postgres.{EXPECTED_STAGING_REF}"
            and port in (5432, 6543)
        )
        if (
            parsed.scheme not in ("postgres", "postgresql")
            or parsed.path != "/postgres"
            or parsed.query
            or parsed.fragment
            or not parsed.password
            or not (direct or pooler)
        ):
            _reject_target(database_url, host or "unknown host")


def get_conn():
    """Connect only to the explicitly approved staging PostgreSQL endpoint."""
    database_url = required("PDC_STAGING_DATABASE_URL", preserve_raw=True)
    assert_staging_target(database_url=database_url)
    tls_kwargs = staging_tls_kwargs()
    import psycopg2
    return psycopg2.connect(database_url, **tls_kwargs)
