"""Fail-closed staging environment and PostgreSQL connection helpers.

This module is operational support code. It deliberately has no test-fixture
imports, production fallback, password-file fallback, or hard-coded secret.
"""
from __future__ import annotations

import os
from pathlib import Path
from urllib.parse import urlparse

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


def assert_staging_target(
    project_url: str | None = None,
    database_url: str | None = None,
) -> None:
    """Reject production and every endpoint not naming the approved staging ref."""
    values = [value for value in (project_url, database_url) if value]
    if not values:
        raise RuntimeError("No staging endpoint supplied to target guard")
    for value in values:
        lowered = value.lower()
        if PRODUCTION_REF in lowered:
            raise RuntimeError("Refusing to run staging operation against production")
        if EXPECTED_STAGING_REF not in lowered:
            host = urlparse(value).hostname or "unknown host"
            raise RuntimeError(
                f"Refusing non-staging target {host!r}; expected project "
                f"reference {EXPECTED_STAGING_REF}."
            )


def get_conn():
    """Connect only to the explicitly approved staging PostgreSQL endpoint."""
    database_url = required("PDC_STAGING_DATABASE_URL")
    assert_staging_target(database_url=database_url)
    return psycopg2.connect(database_url)
