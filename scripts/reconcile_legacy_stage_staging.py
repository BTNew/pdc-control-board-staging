#!/usr/bin/env python3
"""Persist reviewed no-create decisions for the five staging legacy-stage rows.

The exact preview is fail-closed. Four ambiguous records receive ambiguity
receipts only; one booking-represented record receives a skipped receipt. No
vehicle, booking or work-item field is changed by this approved batch.
"""
from __future__ import annotations
import argparse, json, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'_staging_test_tools'))
from staging_conn import get_conn  # noqa: E402
from staging_env import EXPECTED_STAGING_REF  # noqa: E402
from release_backup_gate import validate_release_backup  # noqa: E402
IDS=[
 '18e6b520-d3d0-434a-a4a6-9223b45b76af','23bd4310-c542-44f5-a421-bf2ffbda9341',
 '2c800223-5901-4854-a190-07ac72db9b83','781c3923-8a5d-4ea8-aa32-f9bd777008b0',
 'feba3549-dd9c-42bb-af65-d9ebda5c3579',
]
EXPECTED={
 IDS[0]:('D_AMBIGUOUS','multiple_active_same_station_bookings','HOIST','PMB',2,True,0,1),
 IDS[1]:('D_AMBIGUOUS','active_status_booking_has_completion_markers','HOIST','PMB',1,True,0,1),
 IDS[2]:('D_AMBIGUOUS','multiple_active_same_station_bookings','HOIST','PMB',2,True,0,1),
 IDS[3]:('D_AMBIGUOUS','multiple_active_same_station_bookings','HOIST','PMB',3,False,0,0),
 IDS[4]:('B_ACTIVE_BOOKING','active_booking_represents_job','FITTING','PMB',1,False,0,0),
}
BATCH='staging-legacy-pmb-stage-20260723-v1'
def state_hash(q):
 q.execute("""select md5(coalesce(string_agg(md5(to_jsonb(v)::text),'|' order by v.id),''))
  from public.vehicles v where v.id=any(%s::uuid[])""",(IDS,));vehicles=q.fetchone()[0]
 q.execute("""select md5(coalesce(string_agg(md5(to_jsonb(wi)::text),'|' order by wi.id),''))
  from public.vehicle_work_items wi where wi.vehicle_id=any(%s::uuid[])""",(IDS,));items=q.fetchone()[0]
 q.execute("""select md5(coalesce(string_agg(md5(to_jsonb(b)::text),'|' order by b.id),''))
  from public.workshop_bookings b where b.vehicle_id=any(%s::uuid[])""",(IDS,));bookings=q.fetchone()[0]
 return {'vehicles':vehicles,'work_items':items,'bookings':bookings}
def main():
 p=argparse.ArgumentParser();p.add_argument('--confirm-project',required=True);p.add_argument('--backup-path',required=True);p.add_argument('--backup-sha256',required=True);p.add_argument('--restore-schema',required=True);a=p.parse_args()
 if a.confirm_project!=EXPECTED_STAGING_REF:raise SystemExit('project confirmation mismatch')
 c=get_conn();q=c.cursor()
 try:
  backup_evidence=validate_release_backup(c,a.backup_path,a.backup_sha256,a.restore_schema)
  c.rollback();q=c.cursor()
  q.execute('begin');q.execute("select count(*) from supabase_migrations.schema_migrations where version='045'")
  if q.fetchone()[0]!=1:raise RuntimeError('migration 045 ledger entry missing')
  q.execute("""select vehicle_id::text,classification,reason_code,canonical_station,current_location,
   (evidence->>'active_same_station_bookings')::int,(evidence->>'booking_completion_markers')::boolean,
   (evidence->>'open_equivalent_work_items')::int,(evidence->>'completed_equivalent_work_items')::int
   from public.preview_legacy_stage_reconciliation(%s::uuid[]) order by vehicle_id""",(IDS,))
  preview={r[0]:tuple(r[1:]) for r in q.fetchall()}
  if preview!=EXPECTED:raise RuntimeError(f'preview drift: {preview}')
  if any(v[0]=='A_SAFE_CREATE' for v in preview.values()):raise RuntimeError('approved batch is no-create; A row detected')
  before=state_hash(q)
  q.execute("select public.apply_legacy_stage_reconciliation(%s,%s::uuid[])",(BATCH,IDS));first=q.fetchone()[0]
  q.execute("select public.apply_legacy_stage_reconciliation(%s,%s::uuid[])",(BATCH,IDS));second=q.fetchone()[0]
  after=state_hash(q)
  if before!=after:raise RuntimeError('forbidden operational state change detected')
  if first!=second:raise RuntimeError('idempotent replay result changed')
  q.execute("select classification,decision_state,count(*) from public.legacy_stage_reconciliation_receipts where batch_id=%s group by 1,2 order by 1,2",(BATCH,));receipts=q.fetchall()
  if receipts!=[('B_ACTIVE_BOOKING','skipped',1),('D_AMBIGUOUS','ambiguous',4)]:raise RuntimeError(f'receipt mismatch: {receipts}')
  q.execute("select count(*) from public.audit_events where metadata->>'source'='legacy_pmb_stage_reconciliation_decision' and metadata->>'batch_id'=%s",(BATCH,))
  if q.fetchone()[0]!=5:raise RuntimeError('every reconciliation decision requires one durable audit event')
  c.commit()
  print(json.dumps({'status':'recorded_no_create_decisions','project_ref':EXPECTED_STAGING_REF,'batch_id':BATCH,'preview':preview,'receipts':receipts,'operational_state_unchanged':True,'idempotent_replay':True,'backup_gate':backup_evidence},sort_keys=True))
 except Exception:c.rollback();raise
 finally:c.close()
if __name__=='__main__':main()
