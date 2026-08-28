from __future__ import annotations

import hashlib
import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
MIGRATION = ROOT / "supabase/staging_only/20260829163000_exact_stock_reset_13080534_13017855_phase1.sql"
BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
REF = "cdsmnqxtyyoeoznmbidd"
PROD = "vjdtsswhroyguxyfjdkt"
HEAD = ("20260829151000", "752_reactivate_exact_email_monitor_after_751")
NAME = "exact_stock_reset_13080534_13017855_phase1"
SNAPSHOT_RUN = "7f1c3315-ac42-46fb-99ed-70b43ef89f80"
SNAPSHOT_SHA = "6887bad60ba612c83584cb628829b70dcb0f2e6c8a08de64e46b2c7de3a77518"
SNAPSHOT_MANIFEST_SHA = "8de3b4cb413006d6850838a83ca1648215e0e589f1f61f7e01cb9339fc4bb018"
VEHICLE_13000769 = "d777b071-a2b0-5367-893b-aa83a07fcfce"


def staging_values():
    spec = importlib.util.spec_from_file_location("pdc_staging_bootstrap_exact_reset", BOOTSTRAP)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    values = json.loads(module.unprotect(SECRETS.read_bytes()).decode())
    module.validate(values)
    return values


def main():
    source = MIGRATION.read_text(encoding="utf-8")
    source_sha = hashlib.sha256(source.encode()).hexdigest()
    import os
    expected_approval = f"apply exact stock reset phase1 source {source_sha}"
    if os.environ.get("PDC_APPROVE_EXACT_STOCK_RESET_20260828") != expected_approval:
        raise RuntimeError("exact staging reset approval missing")
    values = staging_values()
    dsn = values["PDC_STAGING_DATABASE_URL"]
    if REF not in dsn or PROD in dsn:
        raise RuntimeError("exact staging database target required")
    import psycopg2
    conn = psycopg2.connect(dsn, sslmode="verify-full", sslrootcert=values["PDC_STAGING_SSLROOTCERT"], application_name="pdc_exact_stock_reset_phase1_controller")
    conn.autocommit = True
    try:
        with conn.cursor() as cur:
            cur.execute("select version,name from supabase_migrations.schema_migrations order by case when version~'^[0-9]{14}$' then version::bigint else 0 end desc,version desc limit 1")
            head_before = tuple(cur.fetchone())
            if head_before != HEAD:
                raise RuntimeError(f"live head changed before exact reset: {head_before}")
            cur.execute("select project_ref from public.pdc_staging_environment_sentinel where singleton")
            if cur.fetchone() != (REF,):
                raise RuntimeError("staging sentinel mismatch")
            cur.execute("select count(*) from public.backup_runs where id=%s::uuid and environment='staging' and status='success' and encrypted and file_sha256=%s", (SNAPSHOT_RUN, SNAPSHOT_SHA))
            if cur.fetchone()[0] != 1:
                raise RuntimeError("fresh encrypted closure snapshot binding missing")
            # Capture exact pre-state evidence without exposing secrets or full rows.
            cur.execute("select md5(coalesce(string_agg(to_jsonb(x)::text,E'\\n' order by to_jsonb(x)::text),'')) from public.vehicles x where x.id=%s::uuid", (VEHICLE_13000769,))
            stock_13000769_before = cur.fetchone()[0]
            cur.execute("select row_to_json(x) from public.pdc_email_monitor_pilot x where singleton")
            pilot_before = cur.fetchone()[0]
            cur.execute("select row_to_json(x) from public.pdc_email_monitor_authenticated_mailbox_activation_controls_674 x where singleton")
            control674_before = cur.fetchone()[0]
            cur.execute("select row_to_json(x) from public.pdc_email_monitor_authenticated_enqueue_trigger_controls_675 x where singleton")
            control675_before = cur.fetchone()[0]
            cur.execute("select row_to_json(x) from public.monitored_mailboxes x where id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57'")
            mailbox_before = cur.fetchone()[0]
            cur.execute(source)
    finally:
        conn.close()
    conn = psycopg2.connect(dsn, sslmode="verify-full", sslrootcert=values["PDC_STAGING_SSLROOTCERT"], application_name="pdc_exact_stock_reset_phase1_readback")
    try:
        with conn.cursor() as cur:
            cur.execute("select version,name from supabase_migrations.schema_migrations order by case when version~'^[0-9]{14}$' then version::bigint else 0 end desc,version desc limit 1")
            head_after = tuple(cur.fetchone())
            cur.execute("select receipt_id,action_key,expected_predecessor_head,snapshot_backup_run_id,snapshot_artifact_sha256,snapshot_manifest_sha256,deleted_table_count,deleted_row_count,deleted_counts,forced_rls,trigger_reset_restored,production_untouched,target_bindings from public.pdc_exact_stock_reset_receipts_20260828 where action_key='phase1-exact-stock-reset-13080534-13017855'")
            receipt = cur.fetchone()
            cur.execute("select stock_number,intake_id,source_uid,sender_email,internet_message_id,parent_source_hash,expected_backend_record_id,expected_canonical_vehicle_id,expected_job_card_number,status,one_time,consumed from public.pdc_exact_email_reimport_authorizations_20260828 order by stock_number")
            handoff = cur.fetchall()
            cur.execute("select count(*) from public.vehicles where stock_number_normalized in ('13080534','13017855')")
            vehicles = cur.fetchone()[0]
            cur.execute("select count(*) from public.navision_board_activations where backend_record_id in ('5721cafa-2b60-4d45-b69c-ab907eaf178e','e39eb741-cf03-44f2-8a75-54362ecc8a26') or canonical_vehicle_id='7fe33693-f519-5152-bbe0-9cc799c4ae33'")
            board_rows = cur.fetchone()[0]
            cur.execute("select count(*) from public.pdc_authenticated_email_operation_lines where vehicle_id='7fe33693-f519-5152-bbe0-9cc799c4ae33' or source_uid in ('1:640','1:680','1:681')")
            operations = cur.fetchone()[0]
            cur.execute("select count(*) from public.ai_email_intake where id in ('6836f01c-080f-4289-90a4-df8667a49ac9','d89a3bbd-590b-493b-84a8-ce557bbfe512')")
            intake_rows = cur.fetchone()[0]
            cur.execute("select md5(coalesce(string_agg(to_jsonb(x)::text,E'\\n' order by to_jsonb(x)::text),'')) from public.vehicles x where x.id=%s::uuid", (VEHICLE_13000769,))
            stock_13000769_after = cur.fetchone()[0]
            cur.execute("select row_to_json(x) from public.pdc_email_monitor_pilot x where singleton")
            pilot_after = cur.fetchone()[0]
            cur.execute("select row_to_json(x) from public.pdc_email_monitor_authenticated_mailbox_activation_controls_674 x where singleton")
            control674_after = cur.fetchone()[0]
            cur.execute("select row_to_json(x) from public.pdc_email_monitor_authenticated_enqueue_trigger_controls_675 x where singleton")
            control675_after = cur.fetchone()[0]
            cur.execute("select row_to_json(x) from public.monitored_mailboxes x where id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57'")
            mailbox_after = cur.fetchone()[0]
            cur.execute("select relrowsecurity,relforcerowsecurity from pg_class where oid='public.pdc_exact_stock_reset_receipts_20260828'::regclass")
            receipt_rls = cur.fetchone()
            cur.execute("select relrowsecurity,relforcerowsecurity from pg_class where oid='public.pdc_exact_email_reimport_authorizations_20260828'::regclass")
            handoff_rls = cur.fetchone()
            production = cur.fetchone() if False else None
    finally:
        conn.close()
    if head_after != ("20260829163000", NAME):
        raise RuntimeError(f"unexpected live head after reset: {head_after}")
    if not receipt or receipt[1] != "phase1-exact-stock-reset-13080534-13017855" or receipt[3] != SNAPSHOT_RUN or receipt[4] != SNAPSHOT_SHA or receipt[5] != SNAPSHOT_MANIFEST_SHA or not receipt[9] or not receipt[10] or not receipt[11]:
        raise RuntimeError(f"reset receipt readback failed: {receipt}")
    if len(handoff) != 2 or {row[0] for row in handoff} != {"13080534", "13017855"} or any(row[9:] != ("authorized", True, False) for row in handoff):
        raise RuntimeError(f"one-time handoff readback failed: {handoff}")
    if any(value != 0 for value in (vehicles, board_rows, operations, intake_rows)):
        raise RuntimeError(f"reset postconditions failed vehicles={vehicles} board={board_rows} operations={operations} intake={intake_rows}")
    if stock_13000769_before != stock_13000769_after or pilot_before != pilot_after or control674_before != control674_after or control675_before != control675_after or mailbox_before != mailbox_after:
        raise RuntimeError("unrelated 13000769 or monitor state changed")
    if receipt_rls != (True, True) or handoff_rls != (True, True):
        raise RuntimeError(f"forced RLS readback failed receipt={receipt_rls} handoff={handoff_rls}")
    print(json.dumps({"ok": True, "project_ref": REF, "migration": "20260829163000_exact_stock_reset_13080534_13017855_phase1", "migration_sha256": source_sha, "head_before": head_before, "head_after": head_after, "snapshot_backup_run_id": SNAPSHOT_RUN, "snapshot_artifact_sha256": SNAPSHOT_SHA, "snapshot_manifest_sha256": SNAPSHOT_MANIFEST_SHA, "receipt": receipt, "handoff": handoff, "postconditions": {"vehicles": vehicles, "board_rows": board_rows, "active_operation_rows": operations, "old_intake_rows": intake_rows, "forced_rls_receipt": receipt_rls, "forced_rls_handoff": handoff_rls, "stock_13000769_unchanged": True, "monitor_state_unchanged": True, "mailbox_sources_preserved": True, "production_untouched": True}, "production_contacted": False}, sort_keys=True, default=str))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc), "production_contacted": False}, sort_keys=True))
        raise SystemExit(1)
