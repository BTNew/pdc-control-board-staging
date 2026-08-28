from __future__ import annotations
import hashlib, importlib.util, json, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
MIGRATION=ROOT/"supabase/staging_only/20260829140000_747_restore_stock_13000769_qc_retest.sql"
REPAIR_MIGRATION=ROOT/"supabase/staging_only/20260829141000_748_repair_recovery_identity_guard.sql"
BACKUP_DIR=Path(r"C:/Users/nwmgr/AppData/Local/hermes/profiles/website-development-lead/backups/stock-13000769-prepurge")
ARTIFACT=BACKUP_DIR/"pdc_backup_staging_20260828T100607Z_847b7b9a.bin"
MANIFEST=BACKUP_DIR/"pdc_backup_staging_20260828T100607Z_847b7b9a.bin.manifest.json"
BOOTSTRAP=Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
STAGING_SECRETS=Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
BACKUP_KEY=Path(r"C:/Users/nwmgr/AppData/Local/hermes/secrets/pdc_backup_key_staging.dpapi")
STAGING_REF="cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF="vjdtsswhroyguxyfjdkt"
VEHICLE_ID="d777b071-a2b0-5367-893b-aa83a07fcfce"
BACKEND_ID="de800087-d086-4f7b-9569-bb8a88660475"
STOCK="13000769"
EXPECTED_FILE="949a8fa7274364b43ecd1fb5248af9f7628f6350cc8196b41733f6322fb8d0e7"
EXPECTED_MANIFEST="7326179925f024eb3f295bdc504aa84b15f416c6e37cf71b777f7946958a817d"
EXPECTED_RUN="847b7b9a-7f25-4a13-868d-fb3a95b9e447"
DASHBOARD_SESSION="20260828_161016_aa9508"
RECOVERY_KEY="recover-stock-13000769-to-qc-20260828_161016_aa9508"
RECOVERY_IDEMPOTENCY="74700000-0000-5000-8000-000000000001"
EXCLUDED={"pdc_qc_salesperson_update_outbox_399"}
LOAD_ORDER=(
    "vehicles","navision_backend_records","navision_import_items","navision_board_activations",
    "pdc_ai_intake_proposals","pdc_ai_intake_history","pdc_email_source_claims",
    "pdc_authenticated_email_import_receipts","pdc_authenticated_email_operation_lines","pdc_exact_email_import_receipts_501",
    "pdc_qc_operation_completions_379","pdc_qc_operation_completion_history_379","pdc_qc_operation_completion_receipts_379",
    "vehicle_workshop_line_adjustments","vehicle_work_items","vehicle_parts_updates","vehicle_movements",
    "pdc_parts_order_receipts_377","pdc_vehicle_salesperson_assignment_receipts_386","pdc_vehicle_salesperson_assignment_history_386",
    "pdc_qc_finalization_photo_evidence_399","pdc_qc_finalization_receipts_399","pdc_rft_confirmation_receipts_736",
    "workshop_bookings","workshop_booking_history","workshop_booking_move_receipts","vehicle_master_history","audit_events",
)

def load_bootstrap():
    spec=importlib.util.spec_from_file_location("pdc_bootstrap_747",BOOTSTRAP); mod=importlib.util.module_from_spec(spec); assert spec and spec.loader; spec.loader.exec_module(mod)
    values=json.loads(mod.unprotect(STAGING_SECRETS.read_bytes()).decode()); mod.validate(values)
    return values

def connect(values):
    import psycopg2
    return psycopg2.connect(values["PDC_STAGING_DATABASE_URL"],sslmode="verify-full",sslrootcert=values["PDC_STAGING_SSLROOTCERT"],application_name="pdc_13000769_recovery_747_controller")

def main():
    md=json.loads(MANIFEST.read_text(encoding="utf-8")); file_sha=hashlib.sha256(ARTIFACT.read_bytes()).hexdigest(); manifest_sha=hashlib.sha256(MANIFEST.read_bytes()).hexdigest()
    if file_sha!=EXPECTED_FILE or manifest_sha!=EXPECTED_MANIFEST: raise RuntimeError("backup artifact or manifest hash mismatch")
    sys.path.insert(0,str(ROOT))
    from scripts import pdc_backup, pdc_restore
    pdc_backup.WORKSHOP_ALIASES_044["PARTS"]="PARTS"; pdc_backup.WORKSHOP_ALIAS_VALUES_044["PARTS"]="PARTS"
    import win32crypt
    key=win32crypt.CryptUnprotectData(BACKUP_KEY.read_bytes(),None,None,None,0)[1]
    payload=pdc_backup.decrypt_backup(ARTIFACT,key)
    tables=payload["tables"]; expected=md["row_counts"]
    if payload.get("environment")!="staging" or payload.get("backup_run_id")!=EXPECTED_RUN or set(tables)!=set(expected): raise RuntimeError("encrypted backup closure contract mismatch")
    if any(len(detail["rows"])!=expected[name] for name,detail in tables.items()): raise RuntimeError("encrypted backup row-count evidence mismatch")
    if sum(len(detail["rows"]) for name,detail in tables.items() if name not in EXCLUDED)!=206: raise RuntimeError("restorable closure row count is not 206")
    vehicle_rows=tables["vehicles"]["rows"]
    if len(vehicle_rows)!=1 or vehicle_rows[0].get("id")!=VEHICLE_ID or vehicle_rows[0].get("stock_number")!=STOCK: raise RuntimeError("backup vehicle identity mismatch")
    original_version=int(vehicle_rows[0]["version"])
    values=load_bootstrap(); conn=connect(values)
    try:
        conn.autocommit=True; q=conn.cursor(); q.execute("set statement_timeout='60s'")
        q.execute("select version,name from supabase_migrations.schema_migrations order by case when version~'^[0-9]+$' then version::bigint else 0 end desc,version desc limit 1"); head=q.fetchone()
        if head==("20260829130000","746_purge_stock_13000769"):
            q.execute(MIGRATION.read_text(encoding="utf-8"))
            head=("20260829140000","747_restore_stock_13000769_qc_retest")
        if head==("20260829140000","747_restore_stock_13000769_qc_retest"):
            q.execute(REPAIR_MIGRATION.read_text(encoding="utf-8"))
            head=("20260829141000","748_repair_recovery_identity_guard")
        if head!=("20260829141000","748_repair_recovery_identity_guard"):
            raise RuntimeError(f"unexpected live head before 747 recovery: {head}")
        conn.autocommit=False; q=conn.cursor(); q.execute("set local statement_timeout='15min'"); q.execute("set local lock_timeout='30s'"); q.execute("select pg_advisory_xact_lock(hashtextextended('pdc-staging-747-recover-stock-13000769',0))")
        q.execute("select count(*) from public.pdc_stock_13000769_recovery_receipts_747 where recovery_key=%s",(RECOVERY_KEY,))
        if q.fetchone()[0]: conn.rollback(); print(json.dumps({"ok":True,"replay":True,"recovery_key":RECOVERY_KEY,"production_contacted":False},sort_keys=True)); return
        q.execute("select count(*) from public.vehicles where id=%s::uuid or stock_number_normalized=%s",(VEHICLE_ID,STOCK))
        if q.fetchone()[0]!=0: raise RuntimeError("target identity already exists before restore")
        q.execute("select count(*) from public.navision_backend_records where id=%s::uuid",(BACKEND_ID,))
        if q.fetchone()[0]!=0: raise RuntimeError("target backend already exists before restore")
        for table in LOAD_ORDER:
            if table not in tables: continue
            q.execute(f'alter table public."{table}" disable trigger user')
        for table in LOAD_ORDER:
            if table not in tables or table in EXCLUDED: continue
            detail=tables[table]
            pdc_restore.load_table_rows(q,"public",table,detail["columns"],detail["rows"])
        for table in LOAD_ORDER:
            if table not in tables: continue
            q.execute(f'alter table public."{table}" enable trigger user')
        claims=json.dumps({"sub":"8a83b715-8d79-4b0e-95b2-02b55da6e8d7","email":"craig.watson@broometoyota.com.au","role":"authenticated"})
        q.execute("select set_config('request.jwt.claims',%s,true),set_config('request.jwt.claim.sub','8a83b715-8d79-4b0e-95b2-02b55da6e8d7',true)",(claims,))
        q.execute("select public.pdc_admin_recover_stock_13000769_to_qc_747(%s::uuid,%s,%s,%s::uuid,%s)",(VEHICLE_ID,original_version,STOCK,RECOVERY_IDEMPOTENCY,DASHBOARD_SESSION)); result=q.fetchone()[0]
        if not result.get("ok"): raise RuntimeError(f"recovery RPC failed: {result}")
        q.execute("select count(*) from public.vehicles where id=%s::uuid and stock_number_normalized=%s and current_location='QC' and lifecycle_state::text='active' and visible_on_board and qc_completed_at is null and rft_confirmed_at is null and rft_transport_booked_at is null and dealer_transit_started_at is null and rft_collected_at is null",(VEHICLE_ID,STOCK))
        if q.fetchone()[0]!=1: raise RuntimeError("recovery postcondition failed")
        conn.commit(); print(json.dumps({"ok":True,"replay":False,"head":"20260829141000/748_repair_recovery_identity_guard","recovery":result,"backup_file_sha256":file_sha,"backup_manifest_sha256":manifest_sha,"restored_table_count":28,"restored_row_count":206,"excluded_pending_outbox_count":1,"production_contacted":False},default=str,sort_keys=True))
    except Exception:
        conn.rollback(); raise
    finally: conn.close()
if __name__=="__main__":
    try: main()
    except Exception as exc: print(json.dumps({"ok":False,"error":str(exc),"production_contacted":False},sort_keys=True)); raise
