"""Compatibility re-export for staging tests.

Operational scripts must import :mod:`scripts.pdc_staging_runtime` directly.
"""
from scripts.pdc_staging_runtime import get_conn  # noqa:F401
