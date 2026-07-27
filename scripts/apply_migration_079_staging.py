#!/usr/bin/env python3
"""Apply staging-only migration 079 with fail-closed target and postchecks."""
from __future__ import annotations
import hashlib,json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:sys.path.insert(0,str(ROOT))
from scripts.pdc_staging_runtime import assert_staging_target,get_conn,load_local_env,required
MIGRATION=ROOT/'supabase'/'staging_only'/'079_navision_exact_dealer_scope_without_fleet_floor.sql'
def scalar(cur,q,args=()):cur.execute(q,args);return cur.fetchone()[0]
def main():
 load_local_env();assert_staging_target(database_url=required('PDC_STAGING_DATABASE_URL'))
 sql=MIGRATION.read_text(encoding='utf-8')
 for required_text in ['v_incoming>0','v_selected_count>0','check(row_count>0)','navision_original_dealer_column_v2']:
  if required_text not in sql:raise RuntimeError(f'Migration 079 source contract missing {required_text}')
 conn=get_conn()
 try:
  conn.autocommit=True
  with conn.cursor() as cur:
   before={t:scalar(cur,f'select count(*) from public.{t}') for t in ['navision_backend_records','navision_import_batches','vehicles','workshop_bookings']}
   cur.execute(sql)
   defs={}
   for name in ['approve_navision_initial_scope','navision_import_safety_assessment','navision_scope_rows_for_selected_dealer']:
    cur.execute("select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname=%s",(name,));rows=cur.fetchall()
    if len(rows)!=1:raise RuntimeError(f'Expected one {name}, got {len(rows)}')
    body=rows[0][0];defs[name]=hashlib.sha256(body.encode()).hexdigest()
    if '100' in body:raise RuntimeError(f'{name} retains an arbitrary 100-row floor')
   if 'v_incoming>0' not in scalar(cur,"select pg_get_functiondef('public.navision_import_safety_assessment(jsonb,text,text,text,jsonb)'::regprocedure)").replace(' ',''):raise RuntimeError('Safety release postcheck failed')
   after={t:scalar(cur,f'select count(*) from public.{t}') for t in before}
   if after!=before:raise RuntimeError(f'Operational row counts changed: {before} -> {after}')
   print(json.dumps({'status':'applied','migration':'079','projectRef':'cdsmnqxtyyoeoznmbidd','rowCounts':after,'functionDefinitionSha256':defs},sort_keys=True))
 finally:conn.close()
if __name__=='__main__':main()
