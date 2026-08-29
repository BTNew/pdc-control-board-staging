from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import re
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260830092000_sublet_auditor_read_ledger_uuid_text_cast_repair.sql"
BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
REF = "cdsmnqxtyyoeoznmbidd"
PREDECESSOR = ("20260830091000", "sublet_auditor_read_ledger_volatility_repair")
NEW = ("20260830092000", "sublet_auditor_read_ledger_uuid_text_cast_repair")


def main() -> None:
    digest = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
    if os.environ.get("PDC_APPROVE_STAGING_MIGRATION_902") != f"apply migration 902 source {digest}":
        raise RuntimeError("staging migration approval missing")
    spec = importlib.util.spec_from_file_location("pdc_staging_bootstrap", BOOTSTRAP)
    if spec is None or spec.loader is None:
        raise RuntimeError("staging bootstrap unavailable")
    bootstrap = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(bootstrap)
    values = json.loads(bootstrap.unprotect(SECRETS.read_bytes()).decode())
    bootstrap.validate(values)
    if values.get("PDC_STAGING_PROJECT_REF") != REF:
        raise RuntimeError("staging project mismatch")
    parsed = urlsplit(values["PDC_STAGING_DATABASE_URL"])
    direct = parsed.hostname == f"db.{REF}.supabase.co" and parsed.username == "postgres" and parsed.port == 5432
    pooler = bool(re.fullmatch(r"aws-[0-9]+-[a-z0-9]+(?:-[a-z0-9]+)*\.pooler\.supabase\.com", parsed.hostname or "")) and parsed.username == f"postgres.{REF}" and parsed.port in (5432, 6543)
    if "vjdtsswhroyguxyfjdkt" in values["PDC_STAGING_DATABASE_URL"].lower() or not (direct or pooler):
        raise RuntimeError("refusing non-staging database endpoint")
    import psycopg2
    connection = psycopg2.connect(host=parsed.hostname, port=parsed.port or 5432, user=parsed.username, password=parsed.password, dbname="postgres", sslmode="verify-full", sslrootcert=values["PDC_STAGING_SSLROOTCERT"], connect_timeout=20, application_name="pdc-staging-sublet-read-902")
    connection.autocommit = True
    try:
        with connection.cursor() as cursor:
            cursor.execute("select version,name from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1")
            head = tuple(cursor.fetchone() or ())
            if head != PREDECESSOR:
                raise RuntimeError(f"unexpected live predecessor: {head!r}")
            cursor.execute(MIGRATION.read_text(encoding="utf-8"))
            cursor.execute("select version,name from supabase_migrations.schema_migrations where version=%s and name=%s", NEW)
            applied = tuple(cursor.fetchone() or ())
            cursor.execute("select to_regprocedure('public.get_pdc_sublet_audit_ledgers(uuid,text,text)') is not null, (select p.provolatile='v' from pg_proc p where p.oid='public.get_pdc_sublet_audit_ledgers(uuid,text,text)'::regprocedure), (select position('r.id::text=v_vehicle.source_record_id' in pg_get_functiondef('public.get_pdc_sublet_audit_ledgers(uuid,text,text)'::regprocedure))>0)")
            rpc_exists, volatile, cast_repaired = cursor.fetchone()
            cursor.execute("select has_table_privilege('authenticated','public.pdc_sublet_booking_instances','select'), has_table_privilege('authenticated','public.pdc_sublet_booking_instance_history','select'), has_table_privilege('authenticated','public.pdc_sublet_email_update_receipts','select'), has_function_privilege('authenticated','public.get_pdc_sublet_audit_ledgers(uuid,text,text)','execute')")
            acl = tuple(cursor.fetchone())
            if applied != NEW or not rpc_exists or not volatile or not cast_repaired or acl != (False, False, False, True):
                raise RuntimeError(f"post-apply proof failed: applied={applied!r} rpc_exists={rpc_exists!r} volatile={volatile!r} cast_repaired={cast_repaired!r} acl={acl!r}")
            print(json.dumps({"ok": True, "applied": applied, "migration_sha256": digest, "rpc_exists": bool(rpc_exists), "rpc_volatile": bool(volatile), "uuid_text_cast_repaired": bool(cast_repaired), "direct_table_select_authenticated": acl[:3], "rpc_execute_authenticated": acl[3], "production_contacted": False}, sort_keys=True))
    finally:
        connection.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(json.dumps({"ok": False, "error": str(error), "production_contacted": False}, sort_keys=True))
        raise SystemExit(1)
