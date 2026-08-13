"""Fail-closed staging environment and PostgreSQL connection helpers.

This module is operational support code. It deliberately has no test-fixture
imports, production fallback, password-file fallback, or hard-coded secret.
"""
from __future__ import annotations

import os
import re
from pathlib import Path
from urllib.parse import parse_qsl, urlparse

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


def required(name: str) -> str:
    load_local_env()
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(
            f"Missing required environment variable {name}. Configure the "
            "ignored _staging_test_tools/.env file or process environment; "
            "never commit credentials."
        )
    return value


def _reject_target(value: str, host: str) -> None:
    if PRODUCTION_REF in value.lower():
        raise RuntimeError("Refusing to run staging operation against production")
    raise RuntimeError(
        f"Refusing non-staging target {host!r}; expected project "
        f"reference {EXPECTED_STAGING_REF}."
    )


def _parsed_endpoint(value: str):
    try:
        parsed = urlparse(value)
        host = (parsed.hostname or "").lower().rstrip(".")
        port = parsed.port
    except (TypeError, ValueError):
        _reject_target(str(value), "invalid endpoint")
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
        if parsed.scheme.lower() != "https" or parsed.username is not None or parsed.password is not None or host != f"{EXPECTED_STAGING_REF}.supabase.co" or port not in (None, 443):
            _reject_target(project_url, host or "unknown host")
    if database_url:
        parsed, host, port = _parsed_endpoint(database_url)
        scheme = parsed.scheme.lower()
        direct = host == f"db.{EXPECTED_STAGING_REF}.supabase.co" and (parsed.username or "").lower() == "postgres" and port in (None, 5432)
        pooler = (
            bool(re.fullmatch(r"aws-[0-9]+-[a-z0-9-]+\.pooler\.supabase\.com", host))
            and (parsed.username or "").lower() == f"postgres.{EXPECTED_STAGING_REF}"
            and port in (5432, 6543)
        )
        query = parse_qsl(parsed.query, keep_blank_values=True)
        safe_query = len(query) <= 1 and all(key.lower() == "sslmode" and value.lower() in ("require", "verify-ca", "verify-full") for key, value in query)
        if scheme not in ("postgres", "postgresql") or parsed.path != "/postgres" or not safe_query or not (direct or pooler):
            _reject_target(database_url, host or "unknown host")


def get_conn():
    """Connect only to the explicitly approved staging PostgreSQL endpoint."""
    database_url = required("PDC_STAGING_DATABASE_URL")
    assert_staging_target(database_url=database_url)
    return psycopg2.connect(database_url)
