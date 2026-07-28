#!/usr/bin/env python3
"""Apply staging-only migration 081 with fail-closed timeout postchecks."""
from __future__ import annotations
import json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:sys.path.insert(0,str(ROOT))
from scripts.pdc_staging_runtime import assert_staging_target,get_conn,load_local_env,required
MIGRATION=ROOT/'supabase'/'staging_only'/'081_navision_restore_bounded_wrapper_timeout.sql'
SIGNATURES=(
 'public.preview_navision_backend_import(jsonb,text,text,text,timestamptz)',
 'public.apply_navision_backend_import(text,jsonb,text,text,text,timestamptz,text,text,bigint)',
 'public.preview_navision_backend_import_pre076(jsonb,text,text,text,timestamptz)',
 'public.apply_navision_backend_import_pre076(text,jsonb,text,text,text,timestamptz,text,text,bigint)',
)
def scalar(cur,q,args=()):cur.execute(q,args);return cur.fetchone()[0]
def main():
 load_local_env();assert_staging_target(database_url=required('PDC_STAGING_DATABASE_URL'))
 sql=MIGRATION.read_text(encoding='utf-8')
 if sql.count("set statement_timeout = '120s'")!=4:raise RuntimeError('Migration 081 source contract invalid')
 conn=get_conn()
 try:
  conn.autocommit=True
  with conn.cursor() as cur:
   before={t:scalar(cur,f'select count(*) from public.{t}') for t in ['navision_backend_records','navision_import_batches','vehicles','workshop_bookings']}
   cur.execute(sql)
   checks={}
   for signature in SIGNATURES:
    config=scalar(cur,"select proconfig from pg_proc where oid=%s::regprocedure",(signature,)) or []
    checks[signature]=config
    if 'statement_timeout=120s' not in config:raise RuntimeError(f'Timeout postcheck failed for {signature}: {config}')
   after={t:scalar(cur,f'select count(*) from public.{t}') for t in before}
   if after!=before:raise RuntimeError(f'Operational row counts changed: {before} -> {after}')
   print(json.dumps({'status':'applied','migration':'081','projectRef':'cdsmnqxtyyoeoznmbidd','rowCounts':after,'functionConfig':checks},sort_keys=True))
 finally:conn.close()
if __name__=='__main__':main()
