from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import re
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260830091000_sublet_auditor_read_ledger_volatility_repair.sql"
BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
EXPECTED_REF = "cdsmnqxtyyoeoznmbidd"
EXPECTED_PREDECESSOR = ("20260830090000", "sublet_auditor_read_ledger")
EXPECTED_VERSION = "20260830091000"
EXPECTED_NAME = "sublet_auditor_read_ledger_volatility_repair"


def main() -> None:
    digest = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
    if os.environ.get("PDC_APPROVE_STAGING_MIGRATION_901") != f"apply migration 901 source {digest}":
        raise RuntimeError("staging migration approval missing")
    spec = importlib.util.spec_from_file_location("pdc_staging_bootstrap", BOOTSTRAP)
    if spec is None or spec.loader is None:
        raise RuntimeError("staging bootstrap unavailable")
    bootstrap = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(bootstrap)
    values = json.loads(bootstrap.unprotect(SECRETS.read_bytes()).decode())
    bootstrap.validate(values)
    if values.get("PDC_STAGING_PROJECT_REF") != EXPECTED_REF:
        raise RuntimeError("staging project mismatch")
    parsed = urlsplit(values["PDC_STAGING_DATABASE_URL"])
    direct = parsed.hostname == f"db.{EXPECTED_REF}.supabase.co" and parsed.username == "postgres" and parsed.port == 5432
    pooler = bool(re.fullmatch(r"aws-[0-9]+-[a-z0-9]+(?:-[a-z0-9]+)*\.pooler\.supabase\.com", parsed.hostname or "")) and parsed.username == f"postgres.{EXPECTED_REF}" and parsed.port in (5432, 6543)
    if "vjdtsswhroyguxyfjdkt" in values["PDC_STAGING_DATABASE_URL"].lower() or not (direct or pooler):
        raise RuntimeError("refusing non-staging database endpoint")
    import psycopg2
    connection = psycopg2.connect(host=parsed.hostname, port=parsed.port or 5432, user=parsed.username, password=parsed.password, dbname="postgres", sslmode="verify-full", sslrootcert=values["PDC_STAGING_SSLROOTCERT"], connect_timeout=20, application_name="pdc-staging-sublet-read-901")
    connection.autocommit = True
    try:
        with connection.cursor() as cursor:
            cursor.execute("select version,name from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1")
            head = tuple(cursor.fetchone() or ())
            if head != EXPECTED_PREDECESSOR:
                raise RuntimeError(f"unexpected live predecessor: {head!r}")
            cursor.execute(MIGRATION.read_text(encoding="utf-8"))
            cursor.execute("select version,name from supabase_migrations.schema_migrations where version=%s and name=%s", (EXPECTED_VERSION, EXPECTED_NAME))
            applied = tuple(cursor.fetchone() or ())
            cursor.execute("select to_regprocedure('public.get_pdc_sublet_audit_ledgers(uuid,text,text)') is not null, (select p.provolatile='v' from pg_proc p where p.oid='public.get_pdc_sublet_audit_ledgers(uuid,text,text)'::regprocedure)")
            rpc_exists, volatile = cursor.fetchone()
            cursor.execute("select has_table_privilege('authenticated','public.pdc_sublet_booking_instances','select'), has_table_privilege('authenticated','public.pdc_sublet_booking_instance_history','select'), has_table_privilege('authenticated','public.pdc_sublet_email_update_receipts','select'), has_function_privilege('authenticated','public.get_pdc_sublet_audit_ledgers(uuid,text,text)','execute')")
            acl = tuple(cursor.fetchone())
            if applied != (EXPECTED_VERSION, EXPECTED_NAME) or not rpc_exists or not volatile or acl != (False, False, False, True):
                raise RuntimeError(f"post-apply proof failed: applied={applied!r} rpc_exists={rpc_exists!r} volatile={volatile!r} acl={acl!r}")
            print(json.dumps({"ok": True, "applied": applied, "migration_sha256": digest, "rpc_exists": bool(rpc_exists), "rpc_volatile": bool(volatile), "direct_table_select_authenticated": acl[:3], "rpc_execute_authenticated": acl[3], "production_contacted": False}, sort_keys=True))
    finally:
        connection.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(json.dumps({"ok": False, "error": str(error), "production_contacted": False}, sort_keys=True))
        raise SystemExit(1)
