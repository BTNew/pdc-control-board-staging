#!/usr/bin/env python3
"""Apply reviewed migration 045 to the one approved staging project only.

Requires a fresh encrypted backup path and caller-supplied SHA-256. This script
applies schema/contract changes only; it never runs reconciliation.
"""
from __future__ import annotations
import argparse, json, sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'_staging_test_tools'))
from staging_conn import get_conn  # noqa: E402
from staging_env import EXPECTED_STAGING_REF  # noqa: E402
from release_backup_gate import validate_release_backup  # noqa: E402

MIGRATION=ROOT/'supabase/migrations/045_canonical_work_item_eligibility_and_legacy_stage_reconciliation.sql'
NAME='canonical_work_item_eligibility_and_legacy_stage_reconciliation'
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

def main():
 p=argparse.ArgumentParser();p.add_argument('--confirm-project',required=True);p.add_argument('--backup-path',required=True);p.add_argument('--backup-sha256',required=True);p.add_argument('--restore-schema',required=True);a=p.parse_args()
 if a.confirm_project!=EXPECTED_STAGING_REF: raise SystemExit('project confirmation mismatch')
 sql=MIGRATION.read_text(encoding='utf-8')
 c=get_conn();q=c.cursor()
 try:
  backup_evidence=validate_release_backup(c,a.backup_path,a.backup_sha256,a.restore_schema)
  c.rollback()
  q=c.cursor()
  q.execute('begin')
  q.execute("select version from supabase_migrations.schema_migrations where version in('044','045') order by version")
  versions=[r[0] for r in q.fetchall()]
  if versions!=['044']: raise RuntimeError(f'ledger precondition failed: {versions}')
  q.execute(sql)
  q.execute("""select vehicle_id::text,classification,reason_code,canonical_station,current_location,
   (evidence->>'active_same_station_bookings')::int,(evidence->>'booking_completion_markers')::boolean,
   (evidence->>'open_equivalent_work_items')::int,(evidence->>'completed_equivalent_work_items')::int
   from public.preview_legacy_stage_reconciliation(%s::uuid[]) order by vehicle_id""",(IDS,))
  actual={r[0]:tuple(r[1:]) for r in q.fetchall()}
  if actual!=EXPECTED: raise RuntimeError(f'sanitized preview drift: {actual}')
  q.execute("insert into supabase_migrations.schema_migrations(version,name,statements) values('045',%s,%s)",(NAME,[sql]))
  q.execute("select count(*) from public.legacy_stage_reconciliation_receipts")
  if q.fetchone()[0]!=0: raise RuntimeError('migration-only apply unexpectedly created receipts')
  c.commit()
  print(json.dumps({'status':'applied','project_ref':EXPECTED_STAGING_REF,'migration':'045','preview':actual,'reconciliation_run':False,'backup_gate':backup_evidence},sort_keys=True))
 except Exception:
  c.rollback();raise
 finally:c.close()
if __name__=='__main__':main()
