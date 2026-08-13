"""Fail-closed staging environment and PostgreSQL connection helpers.

This module is operational support code. It deliberately has no test-fixture
imports, production fallback, password-file fallback, or hard-coded secret.
"""
from __future__ import annotations

import os
import re
from pathlib import Path
from urllib.parse import unquote, urlsplit

import psycopg2

EXPECTED_STAGING_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
ROOT = Path(__file__).resolve().parents[1]
ENV_PATH = ROOT / "_staging_test_tools" / ".env"


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


def _parsed_endpoint(value: str):
    if type(value) is not str or not value or value != value.strip() or any(ord(char) <= 0x20 or ord(char) == 0x7F for char in value):
        _reject_target("", "invalid endpoint")
    if PRODUCTION_REF in value.lower() or PRODUCTION_REF in unquote(value).lower():
        _reject_target(value, "production marker")
    try:
        parsed = urlsplit(value)
        host = parsed.hostname or ""
        port = parsed.port
    except (TypeError, ValueError, UnicodeError):
        _reject_target("", "invalid endpoint")
    return parsed, host, port


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
    return psycopg2.connect(database_url, sslmode="require")
