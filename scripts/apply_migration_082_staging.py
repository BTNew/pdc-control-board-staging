#!/usr/bin/env python3
"""Apply staging-only migration 082 with fail-closed role postchecks."""
from __future__ import annotations
import json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:sys.path.insert(0,str(ROOT))
from scripts.pdc_staging_runtime import assert_staging_target,get_conn,load_local_env,required
MIGRATION=ROOT/'supabase'/'staging_only'/'082_navision_authenticated_api_timeout.sql'
def scalar(cur,q,args=()):cur.execute(q,args);return cur.fetchone()[0]
def main():
 load_local_env();assert_staging_target(database_url=required('PDC_STAGING_DATABASE_URL'))
 sql=MIGRATION.read_text(encoding='utf-8')
 if "alter role authenticated set statement_timeout = '30s'" not in sql or 'alter role anon' in sql.lower():raise RuntimeError('Migration 082 source contract invalid')
 conn=get_conn()
 try:
  conn.autocommit=True
  with conn.cursor() as cur:
   before={t:scalar(cur,f'select count(*) from public.{t}') for t in ['navision_backend_records','navision_import_batches','vehicles','workshop_bookings']}
   cur.execute(sql)
   configs={role:scalar(cur,'select rolconfig from pg_roles where rolname=%s',(role,)) for role in ('authenticated','anon','authenticator')}
   if 'statement_timeout=30s' not in (configs['authenticated'] or []):raise RuntimeError(f'Authenticated timeout postcheck failed: {configs}')
   if 'statement_timeout=3s' not in (configs['anon'] or []) or 'statement_timeout=8s' not in (configs['authenticator'] or []):raise RuntimeError(f'Unrelated role timeout changed: {configs}')
   after={t:scalar(cur,f'select count(*) from public.{t}') for t in before}
   if after!=before:raise RuntimeError(f'Operational row counts changed: {before} -> {after}')
   print(json.dumps({'status':'applied','migration':'082','projectRef':'cdsmnqxtyyoeoznmbidd','rowCounts':after,'roleConfig':configs},sort_keys=True))
 finally:conn.close()
if __name__=='__main__':main()
