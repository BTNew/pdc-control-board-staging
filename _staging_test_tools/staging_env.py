"""Safe environment loader and staging-target guard for review tests.

Real values belong in an ignored ``_staging_test_tools/.env`` file or the
process environment. Only ``.env.example`` is committed and exported.
"""
from __future__ import annotations

import os
from pathlib import Path
from urllib.parse import urlparse

EXPECTED_STAGING_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
ENV_PATH = Path(__file__).with_name(".env")


def load_local_env() -> None:
    """Load missing values from the ignored local .env without overriding
    values explicitly supplied by the reviewer or CI environment."""
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
            f"Missing required environment variable {name}. Copy "
            "_staging_test_tools/.env.example to .env, populate only "
            "staging values locally, and never commit that .env file."
        )
    return value


def assert_staging_target(project_url: str | None = None, database_url: str | None = None) -> None:
    """Fail closed unless every supplied endpoint names the approved staging
    project, and explicitly reject the production project reference."""
    values = [v for v in (project_url, database_url) if v]
    if not values:
        raise RuntimeError("No staging endpoint supplied to target guard")
    for value in values:
        lowered = value.lower()
        if PRODUCTION_REF in lowered:
            raise RuntimeError("Refusing to run staging tests against production")
        if EXPECTED_STAGING_REF not in lowered:
            host = urlparse(value).hostname or "unknown host"
            raise RuntimeError(
                f"Refusing non-staging target {host!r}; expected project "
                f"reference {EXPECTED_STAGING_REF}."
            )
