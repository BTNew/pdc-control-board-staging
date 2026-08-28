from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REF = "cdsmnqxtyyoeoznmbidd"
MIGRATION = ROOT / "supabase/staging_only/20260829030000_737_email_monitor_requeue_receipt_table_binding_repair.sql"
BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRET = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")


def db_values():
    spec = importlib.util.spec_from_file_location("pdc_staging_bootstrap", BOOTSTRAP)
    if spec is None or spec.loader is None:
        raise RuntimeError("staging bootstrap loader unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    result = json.loads(module.unprotect(SECRET.read_bytes()).decode())
    module.validate(result)
    if result.get("PDC_STAGING_PROJECT_REF") != REF:
        raise RuntimeError("staging project mismatch")
    return result


def main():
    evidence = ROOT / "review-evidence" / "email-monitor-735" / "migration-737-apply.json"
    event = {"ok": False, "migration": MIGRATION.name, "migration_sha256": hashlib.sha256(MIGRATION.read_bytes()).hexdigest(), "production_touched": False, "mailbox_contacted": False, "task_enabled": False}
    try:
        import psycopg2
        v = db_values()
        with psycopg2.connect(v["PDC_STAGING_DATABASE_URL"], connect_timeout=15, application_name="pdc_email_monitor_737_migration", sslmode="verify-full", sslrootcert=v["PDC_STAGING_SSLROOTCERT"]) as conn:
            with conn.cursor() as cur:
                cur.execute("select current_user,session_user,to_regclass('public.pdc_production_environment_sentinel') is not null")
                if cur.fetchone() != ("postgres", "postgres", False):
                    raise RuntimeError("exact staging database custody required")
                cur.execute("select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref=%s", (REF,))
                if cur.fetchone()[0] != 1:
                    raise RuntimeError("staging sentinel mismatch")
                cur.execute("select max(version) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$'")
                if cur.fetchone()[0] != "20260829020000":
                    raise RuntimeError("exact 736 predecessor required")
                cur.execute(MIGRATION.read_text(encoding="utf-8"))
                conn.commit()
                cur.execute("select max(version),count(*) from supabase_migrations.schema_migrations where version='20260829030000'")
                head, count = cur.fetchone()
                if (head, count) != ("20260829030000", 1):
                    raise RuntimeError("737 ledger readback mismatch")
                cur.execute("select position('pdc_email_monitor_requeue_receipts_735' in pg_get_functiondef('public.admin_requeue_pdc_email_intake_735(uuid,text,text)'::regprocedure))>0")
                if not cur.fetchone()[0]:
                    raise RuntimeError("737 function binding readback mismatch")
                event["after"] = {"head": head, "ledger_count": count, "requeue_receipt_table_bound": True}
                event["ok"] = True
    except Exception as exc:
        event["error"] = str(exc)[:500]
    evidence.parent.mkdir(parents=True, exist_ok=True)
    evidence.write_text(json.dumps(event, sort_keys=True, separators=(",", ":")) + "\n")
    print(json.dumps(event, sort_keys=True, separators=(",", ":")))
    return 0 if event["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
