from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_REF = "cdsmnqxtyyoeoznmbidd"
MIGRATION = ROOT / "supabase/staging_only/20260829020000_736_email_monitor_reconciliation_audit_action_repair.sql"
BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRET = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")


def values() -> dict[str, str]:
    spec = importlib.util.spec_from_file_location("pdc_staging_bootstrap", BOOTSTRAP)
    if spec is None or spec.loader is None:
        raise RuntimeError("staging bootstrap loader unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    result = json.loads(module.unprotect(SECRET.read_bytes()).decode("utf-8"))
    module.validate(result)
    if result.get("PDC_STAGING_PROJECT_REF") != EXPECTED_REF:
        raise RuntimeError("staging project mismatch")
    return result


def main() -> int:
    evidence = ROOT / "review-evidence" / "email-monitor-735" / "migration-736-apply.json"
    event: dict[str, object] = {"ok": False, "migration": MIGRATION.name, "migration_sha256": hashlib.sha256(MIGRATION.read_bytes()).hexdigest(), "production_touched": False, "mailbox_contacted": False, "task_enabled": False}
    try:
        import psycopg2
        v = values()
        with psycopg2.connect(v["PDC_STAGING_DATABASE_URL"], connect_timeout=15, application_name="pdc_email_monitor_736_migration", sslmode="verify-full", sslrootcert=v["PDC_STAGING_SSLROOTCERT"]) as conn:
            with conn.cursor() as cur:
                cur.execute("select current_user,session_user,to_regclass('public.pdc_production_environment_sentinel') is not null")
                if cur.fetchone() != ("postgres", "postgres", False):
                    raise RuntimeError("exact staging database custody required")
                cur.execute("select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref=%s", (EXPECTED_REF,))
                if cur.fetchone()[0] != 1:
                    raise RuntimeError("staging sentinel mismatch")
                cur.execute("select max(version) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$'")
                if cur.fetchone()[0] != "20260829010000":
                    raise RuntimeError("exact 735 predecessor required")
                cur.execute(MIGRATION.read_text(encoding="utf-8"))
                conn.commit()
                cur.execute("select max(version),count(*) from supabase_migrations.schema_migrations where version='20260829020000'")
                head, count = cur.fetchone()
                if (head, count) != ("20260829020000", 1):
                    raise RuntimeError("736 ledger readback mismatch")
                cur.execute("select pg_get_functiondef('public.admin_reconcile_pdc_email_attachment_storage_735(uuid,uuid,text,text,text,text)'::regprocedure)")
                if "values('update'" not in cur.fetchone()[0]:
                    raise RuntimeError("736 function repair readback mismatch")
                event["after"] = {"head": head, "ledger_count": count, "audit_action_repaired": True}
                event["ok"] = True
    except Exception as exc:
        event["error"] = str(exc)[:500]
    evidence.parent.mkdir(parents=True, exist_ok=True)
    evidence.write_text(json.dumps(event, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
    print(json.dumps(event, sort_keys=True, separators=(",", ":")))
    return 0 if event["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
