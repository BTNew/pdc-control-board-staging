from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_REF = "cdsmnqxtyyoeoznmbidd"
MIGRATION = ROOT / "supabase/staging_only/20260829010000_735_email_monitor_storage_reconcile_requeue_successor.sql"
BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRET = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
TARGETS = (
    "d89a3bbd-590b-493b-84a8-ce557bbfe512",
    "6836f01c-080f-4289-90a4-df8667a49ac9",
)


def load_values() -> dict[str, str]:
    spec = importlib.util.spec_from_file_location("pdc_staging_bootstrap", BOOTSTRAP)
    if spec is None or spec.loader is None:
        raise RuntimeError("staging bootstrap loader unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    values = json.loads(module.unprotect(SECRET.read_bytes()).decode("utf-8"))
    module.validate(values)
    if values.get("PDC_STAGING_PROJECT_REF") != EXPECTED_REF:
        raise RuntimeError("staging project reference mismatch")
    return values


def main() -> int:
    evidence = ROOT / "review-evidence" / "email-monitor-735" / "migration-apply.json"
    event: dict[str, object] = {
        "ok": False,
        "migration": MIGRATION.name,
        "migration_sha256": hashlib.sha256(MIGRATION.read_bytes()).hexdigest(),
        "production_touched": False,
        "mailbox_contacted": False,
        "task_enabled": False,
    }
    try:
        import psycopg2

        values = load_values()
        conn = psycopg2.connect(
            values["PDC_STAGING_DATABASE_URL"],
            connect_timeout=15,
            application_name="pdc_email_monitor_735_migration",
            sslmode="verify-full",
            sslrootcert=values["PDC_STAGING_SSLROOTCERT"],
        )
        try:
            cur = conn.cursor()
            cur.execute("select current_database(),current_user,session_user")
            if cur.fetchone() != ("postgres", "postgres", "postgres"):
                raise RuntimeError("exact staging database custody required")
            cur.execute("select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref=%s", (EXPECTED_REF,))
            if cur.fetchone()[0] != 1:
                raise RuntimeError("staging sentinel mismatch")
            cur.execute("select to_regclass('public.pdc_production_environment_sentinel') is not null")
            if cur.fetchone()[0]:
                raise RuntimeError("production sentinel present")
            cur.execute("select max(version) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$'")
            if cur.fetchone()[0] != "20260829000000":
                raise RuntimeError("migration 735 exact 734 prestate mismatch")
            cur.execute("select count(*) from supabase_migrations.schema_migrations where version='20260829010000'")
            if cur.fetchone()[0]:
                raise RuntimeError("migration 735 already exists")
            cur.execute(
                "select id,storage_path from public.ai_email_attachments where intake_id = any(%s::uuid[]) order by intake_id,id",
                (list(TARGETS),),
            )
            before_paths = cur.fetchall()
            event["before_attachment_rows"] = len(before_paths)
            cur.execute(MIGRATION.read_text(encoding="utf-8"))
            conn.commit()
            cur.execute("select max(version) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$'")
            if cur.fetchone()[0] != "20260829010000":
                raise RuntimeError("migration 735 ledger head mismatch")
            cur.execute("select count(*) from public.pdc_email_monitor_requeue_targets_735")
            if cur.fetchone()[0] != 2:
                raise RuntimeError("migration 735 target count mismatch")
            cur.execute(
                "select id,storage_path from public.ai_email_attachments where intake_id = any(%s::uuid[]) order by intake_id,id",
                (list(TARGETS),),
            )
            after_paths = cur.fetchall()
            if after_paths != before_paths:
                raise RuntimeError("migration 735 rewrote historical attachment evidence")
            cur.execute(
                """select jsonb_build_object(
                  'head',(select max(version) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$'),
                  'ledger',(select jsonb_agg(jsonb_build_object('version',version,'name',name) order by version) from supabase_migrations.schema_migrations where version='20260829010000'),
                  'targets',(select count(*) from public.pdc_email_monitor_requeue_targets_735),
                  'reconciliations',(select count(*) from public.pdc_email_monitor_storage_reconciliations_735),
                  'requeue_receipts',(select count(*) from public.pdc_email_monitor_requeue_receipts_735),
                  'monitor_reconcile_execute',has_function_privilege('authenticated','public.admin_reconcile_pdc_email_attachment_storage_735(uuid,uuid,text,text,text,text)','execute'),
                  'monitor_requeue_execute',has_function_privilege('authenticated','public.admin_requeue_pdc_email_intake_735(uuid,text,text)','execute'),
                  'monitor_attachment_execute',has_function_privilege('authenticated','public.get_pdc_monitor_intake_attachments_735(uuid,uuid,text)','execute'),
                  'anon_requeue_execute',has_function_privilege('anon','public.admin_requeue_pdc_email_intake_735(uuid,text,text)','execute'),
                  'service_requeue_execute',has_function_privilege('service_role','public.admin_requeue_pdc_email_intake_735(uuid,text,text)','execute'),
                  'authenticated_reconcile_table_select',has_table_privilege('authenticated','public.pdc_email_monitor_storage_reconciliations_735','select'),
                  'authenticated_requeue_table_select',has_table_privilege('authenticated','public.pdc_email_monitor_requeue_receipts_735','select'),
                  'uid514_count',(select count(*) from public.ai_email_intake where provider_uid='imap_uid:514'),
                  'active_mailboxes',(select count(*) from public.monitored_mailboxes where active),
                  'outbound_disabled',(select count(*) from public.pdc_email_monitor_pilot where singleton and not outbound_email_enabled)
                )"""
            )
            event["after"] = cur.fetchone()[0]
            event["ok"] = True
        finally:
            conn.close()
    except Exception as exc:
        event["error"] = str(exc)[:500]
    evidence.parent.mkdir(parents=True, exist_ok=True)
    evidence.write_text(json.dumps(event, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
    print(json.dumps(event, sort_keys=True, separators=(",", ":")))
    return 0 if event["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
