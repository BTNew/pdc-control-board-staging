"""Compatibility re-export for staging tests.

Operational scripts must import :mod:`scripts.pdc_staging_runtime` directly.
"""
from scripts.pdc_staging_runtime import (  # noqa:F401
    ENV_PATH,
    EXPECTED_STAGING_REF,
    PRODUCTION_REF,
    assert_staging_target,
    load_local_env,
    required,
)
