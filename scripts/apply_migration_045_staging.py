#!/usr/bin/env python3
"""Apply reviewed migration 045 to the one approved staging project only.

Requires a fresh encrypted backup path and caller-supplied SHA-256. This script
applies schema/contract changes only; it never runs reconciliation.
"""
from __future__ import annotations
import argparse, hashlib, json, sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'_staging_test_tools'))
from staging_conn import get_conn  # noqa: E402
from staging_env import EXPECTED_STAGING_REF  # noqa: E402

MIGRATION=ROOT/'supabase/migrations/045_canonical_work_item_eligibility_and_legacy_stage_reconciliation.sql'
NAME='canonical_work_item_eligibility_and_legacy_stage_reconciliation'
IDS=[
 '18e1ec63-503c-41f8-b6c0-8737911d73e5','23bdac02-842a-43c4-9f5b-a864487efca2',
 '2c800952-1624-4b0f-bfd5-10a6d7758347','781eb0c0-b932-4a7d-88cb-2cfbb66619f9',
 'feba398a-a3ed-4e96-beef-8ba316dc220f',
]
EXPECTED={IDS[0]:'D_AMBIGUOUS',IDS[1]:'D_AMBIGUOUS',IDS[2]:'D_AMBIGUOUS',IDS[3]:'D_AMBIGUOUS',IDS[4]:'B_ACTIVE_BOOKING'}

def sha256(path:Path)->str:
 h=hashlib.sha256()
 with path.open('rb') as f:
  for chunk in iter(lambda:f.read(1024*1024),b''): h.update(chunk)
 return h.hexdigest()

def main():
 p=argparse.ArgumentParser();p.add_argument('--confirm-project',required=True);p.add_argument('--backup-path',required=True);p.add_argument('--backup-sha256',required=True);a=p.parse_args()
 if a.confirm_project!=EXPECTED_STAGING_REF: raise SystemExit('project confirmation mismatch')
 backup=Path(a.backup_path)
 if not backup.is_file() or sha256(backup).lower()!=a.backup_sha256.lower(): raise SystemExit('encrypted backup file/hash verification failed')
 sql=MIGRATION.read_text(encoding='utf-8')
 c=get_conn();q=c.cursor()
 try:
  q.execute('begin')
  q.execute("select version from supabase_migrations.schema_migrations where version in('044','045') order by version")
  versions=[r[0] for r in q.fetchall()]
  if versions!=['044']: raise RuntimeError(f'ledger precondition failed: {versions}')
  q.execute(sql)
  q.execute("select vehicle_id::text,classification from public.preview_legacy_stage_reconciliation(%s::uuid[]) order by vehicle_id",(IDS,))
  actual=dict(q.fetchall())
  if actual!=EXPECTED: raise RuntimeError(f'sanitized preview drift: {actual}')
  q.execute("insert into supabase_migrations.schema_migrations(version,name,statements) values('045',%s,%s)",(NAME,[sql]))
  q.execute("select count(*) from public.legacy_stage_reconciliation_receipts")
  if q.fetchone()[0]!=0: raise RuntimeError('migration-only apply unexpectedly created receipts')
  c.commit()
  print(json.dumps({'status':'applied','project_ref':EXPECTED_STAGING_REF,'migration':'045','preview':actual,'reconciliation_run':False,'backup_sha256':a.backup_sha256.lower()},sort_keys=True))
 except Exception:
  c.rollback();raise
 finally:c.close()
if __name__=='__main__':main()
