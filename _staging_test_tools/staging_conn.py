"""Staging-only PostgreSQL connection helper for independent review tests."""
import psycopg2

from staging_env import assert_staging_target, required


def get_conn():
    """Connect only to the explicitly approved staging Supabase pooler.

    The full connection string must come from the process environment or the
    ignored local ``_staging_test_tools/.env`` file. There is deliberately no
    password-file, hardcoded-host, or production fallback.
    """
    database_url = required("PDC_STAGING_DATABASE_URL")
    assert_staging_target(database_url=database_url)
    return psycopg2.connect(database_url)
