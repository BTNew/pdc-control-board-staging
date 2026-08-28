from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path

BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
REF = "cdsmnqxtyyoeoznmbidd"
PROD = "vjdtsswhroyguxyfjdkt"
RESET_TABLES = [
    "ai_email_attachments", "ai_email_intake", "audit_events", "navision_backend_records", "navision_board_activations", "navision_import_items", "pdc_ai_intake_history", "pdc_ai_intake_proposals", "pdc_authenticated_email_import_receipts", "pdc_authenticated_email_operation_lines", "pdc_authenticated_parts_received_receipts_751", "pdc_email_monitor_requeue_receipts_735", "pdc_email_monitor_requeue_targets_735", "pdc_email_monitor_storage_reconciliations_735", "pdc_email_source_claims", "pdc_exact_email_import_receipts_501", "pdc_parts_order_receipts_377", "pdc_qc_operation_completion_history_379", "pdc_qc_operation_completion_receipts_379", "pdc_qc_operation_completions_379", "pdc_vehicle_detail_edit_history_388", "pdc_vehicle_detail_edit_receipts_388", "vehicle_master_history", "vehicle_movements", "vehicle_parts_updates", "vehicle_work_items", "vehicle_workshop_line_adjustments", "vehicles", "workshop_booking_history", "workshop_booking_move_receipts", "workshop_bookings",
]
TOKENS = ["13080534", "13017855", "5721cafa-2b60-4d45-b69c-ab907eaf178e", "e39eb741-cf03-44f2-8a75-54362ecc8a26", "7fe33693-f519-5152-bbe0-9cc799c4ae33", "J139125422", "MR0MABAV902402464", "1:640", "imap_uid:680", "imap_uid:681", "f205342f4ff4361b88bf21b83a11e92957a796792bcc0bfa4150d0abaa5b4916", "d6756c523ffb7336556492fe0ef25c202d744ffd2645846b19cbbcdffed60493", "812c2291fe80a143e8fe8a55e34f9869476926d69d6bbddd345b61a6a5448a8a", "6836f01c-080f-4289-90a4-df8667a49ac9", "d89a3bbd-590b-493b-84a8-ce557bbfe512", "0f190df5-09df-4df6-a111-66f658318d57", "3415271f-e6df-4d1e-a763-3341f9b066f4", "91eadf28-e8d6-482a-9dd9-b3b6b7862489", "5d907dc4-c2c3-4eb1-b028-a771b8d447d7", "842405e4-5209-45f5-9729-0d22327daeaa", "c3786a12-18a0-4c88-8636-8b09800aed56"]

def values():
    spec = importlib.util.spec_from_file_location("pdc_staging_bootstrap_verify_reset", BOOTSTRAP)
    module = importlib.util.module_from_spec(spec); assert spec and spec.loader; spec.loader.exec_module(module)
    result = json.loads(module.unprotect(SECRETS.read_bytes()).decode()); module.validate(result); return result

def main():
    import psycopg2
    v = values(); dsn = v["PDC_STAGING_DATABASE_URL"]
    if REF not in dsn or PROD in dsn: raise RuntimeError("non-staging target")
    c = psycopg2.connect(dsn, sslmode="verify-full", sslrootcert=v["PDC_STAGING_SSLROOTCERT"], application_name="pdc_exact_stock_reset_phase1_verify")
    try:
        q = c.cursor(); out = {}
        q.execute("select version,name from supabase_migrations.schema_migrations order by case when version~'^[0-9]{14}$' then version::bigint else 0 end desc,version desc limit 1"); out["head"] = q.fetchone()
        q.execute("select project_ref from public.pdc_staging_environment_sentinel where singleton"); out["sentinel"] = q.fetchone()
        q.execute("select to_regclass('public.pdc_production_environment_sentinel') is not null"); out["production_sentinel_exists"] = q.fetchone()[0]
        q.execute("select receipt_id,action_key,expected_predecessor_head,snapshot_backup_run_id,snapshot_artifact_sha256,snapshot_manifest_sha256,deleted_table_count,deleted_row_count,deleted_counts,forced_rls,trigger_reset_restored,production_untouched,target_bindings from public.pdc_exact_stock_reset_receipts_20260828 where action_key='phase1-exact-stock-reset-13080534-13017855'"); out["receipt"] = q.fetchone()
        q.execute("select stock_number,intake_id,source_uid,sender_email,internet_message_id,parent_source_hash,expected_backend_record_id,expected_canonical_vehicle_id,expected_job_card_number,status,one_time,consumed,attachment_manifest from public.pdc_exact_email_reimport_authorizations_20260828 order by stock_number"); out["handoff"] = q.fetchall()
        q.execute("select relrowsecurity,relforcerowsecurity from pg_class where oid='public.pdc_exact_stock_reset_receipts_20260828'::regclass"); out["receipt_rls"] = q.fetchone()
        q.execute("select relrowsecurity,relforcerowsecurity from pg_class where oid='public.pdc_exact_email_reimport_authorizations_20260828'::regclass"); out["handoff_rls"] = q.fetchone()
        out["remaining_target_rows"] = {}
        for table in RESET_TABLES:
            q.execute("select to_regclass(%s) is not null", (f"public.{table}",))
            if not q.fetchone()[0] or table == "audit_events": continue
            q.execute(f"select count(*) from public.\"{table}\" x where exists (select 1 from unnest(%s::text[]) k(token) where jsonb_path_exists(to_jsonb(x),'$.** ? (@ == $token)',jsonb_build_object('token',to_jsonb(k.token))))", (TOKENS,))
            n = q.fetchone()[0]
            if n: out["remaining_target_rows"][table] = n
        q.execute("select count(*) from public.vehicles where stock_number_normalized in ('13080534','13017855')"); out["canonical_vehicle_rows"] = q.fetchone()[0]
        q.execute("select count(*) from public.navision_board_activations where backend_record_id in ('5721cafa-2b60-4d45-b69c-ab907eaf178e','e39eb741-cf03-44f2-8a75-54362ecc8a26') or canonical_vehicle_id='7fe33693-f519-5152-bbe0-9cc799c4ae33'"); out["board_rows"] = q.fetchone()[0]
        q.execute("select count(*) from public.pdc_authenticated_email_operation_lines where vehicle_id='7fe33693-f519-5152-bbe0-9cc799c4ae33' or source_uid in ('1:640','1:680','1:681')"); out["active_operation_rows"] = q.fetchone()[0]
        q.execute("select count(*) from public.ai_email_intake where id in ('6836f01c-080f-4289-90a4-df8667a49ac9','d89a3bbd-590b-493b-84a8-ce557bbfe512')"); out["old_intake_rows"] = q.fetchone()[0]
        q.execute("select count(*) from public.ai_email_attachments where intake_id in ('6836f01c-080f-4289-90a4-df8667a49ac9','d89a3bbd-590b-493b-84a8-ce557bbfe512')"); out["old_attachment_rows"] = q.fetchone()[0]
        q.execute("select count(*) from public.ai_email_intake where lower(sender_email)='craig.watson@broometoyota.com.au' and provider_uid in ('imap_uid:680','imap_uid:681')"); out["reset_sender_intakes"] = q.fetchone()[0]
        q.execute("select enabled,automatic_rule_application,automatic_authenticated_jobcards,outbound_email_enabled,minimum_uid from public.pdc_email_monitor_pilot where singleton"); out["pilot"] = q.fetchone()
        q.execute("select active,test_mode,mailbox_key,mailbox_address,provider from public.monitored_mailboxes where id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57'"); out["mailbox"] = q.fetchone()
        q.execute("select enabled from public.pdc_email_monitor_authenticated_mailbox_activation_controls_674 where singleton"); out["control_674"] = q.fetchone()
        q.execute("select enabled from public.pdc_email_monitor_authenticated_enqueue_trigger_controls_675 where singleton"); out["control_675"] = q.fetchone()
        q.execute("select count(*) from public.ai_email_intake where provider_uid='imap_uid:514'"); out["uid514_rows"] = q.fetchone()[0]
        out["untouched_13000769"] = {}
        for table in ("navision_backend_records", "navision_board_activations", "navision_import_items", "pdc_authenticated_email_import_receipts", "vehicles"):
            q.execute(f"select count(*),coalesce(encode(extensions.digest(string_agg(to_jsonb(x)::text,E'\\n' order by to_jsonb(x)::text),'sha256'),'hex'),'') from public.\"{table}\" x where jsonb_path_exists(to_jsonb(x),'$.** ? (@ == $token)',jsonb_build_object('token',to_jsonb('13000769'::text)))")
            out["untouched_13000769"][table] = q.fetchone()
        q.execute("select to_regclass('storage.objects') is not null"); storage_exists=q.fetchone()[0]; out["storage_objects_table_exists"] = storage_exists
        if storage_exists:
            q.execute("select count(*) from storage.objects where bucket_id='pdc-email-intake-private' and name in (%s,%s,%s)", ("090749692e975cec1b490f42d07af95e9693edadbf42c7399947f7ebaf7bfc34/13080534.pdf", "ffaa2bfbca036f9dbcbe10de9a43f8a141fd2a84f9fea75c0e114b96b87b4cf3/image.png", "23416bd8de1ef1fa6bb40b3b81b3613d969fdb3bd897dc090f0d6747b7b1831f/13017855.pdf")); out["preserved_storage_objects"] = q.fetchone()[0]
    finally: c.close()
    current=Path(r"C:/ProgramData/PDCMonitor/Staging/CURRENT")
    out["runtime_current"] = current.read_text().strip() if current.is_file() else None
    out["expected_phase2_entrypoint"] = r"C:\ProgramData\PDCMonitor\Staging\control\2026.08.65\run-current-active.ps1 -InstallRoot C:\ProgramData\PDCMonitor\Staging -Mode OneCycle"
    out["canonical_monitor_launcher"] = r"C:\ProgramData\PDCMonitor\Staging\releases\2026.08.65\runtime_launcher.py --mode monitor"
    checks = {"head": out["head"] == ("20260829163000", "exact_stock_reset_13080534_13017855_phase1"), "sentinel": out["sentinel"] == (REF,), "production_absent": out["production_sentinel_exists"] is False, "vehicles_zero": out["canonical_vehicle_rows"] == 0, "board_zero": out["board_rows"] == 0, "operations_zero": out["active_operation_rows"] == 0, "old_intake_zero": out["old_intake_rows"] == 0, "old_attachments_zero": out["old_attachment_rows"] == 0, "handoff_exact_two": len(out["handoff"]) == 2 and {r[0] for r in out["handoff"]} == {"13080534", "13017855"}, "remaining_target_rows_empty": not out["remaining_target_rows"], "forced_rls": out["receipt_rls"] == (True,True) and out["handoff_rls"] == (True,True), "pilot_remains_disabled": out["pilot"][:4] == (False,False,False,False), "uid514_preserved": out["uid514_rows"] == 1, "storage_objects_preserved": (not storage_exists) or out["preserved_storage_objects"] == 3, "runtime_current": out["runtime_current"] == "2026.08.65"}
    out["checks"] = checks; out["ok"] = all(checks.values()); out["production_contacted"] = False
    print(json.dumps(out, sort_keys=True, default=str))
    if not out["ok"]: raise SystemExit(1)
if __name__=='__main__': main()
