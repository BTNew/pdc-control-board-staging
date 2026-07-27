#!/usr/bin/env python3
"""Apply staging-only migration 078 with fail-closed target and postchecks."""
from __future__ import annotations
import hashlib,json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:sys.path.insert(0,str(ROOT))
from scripts.pdc_staging_runtime import assert_staging_target,get_conn,load_local_env,required
MIGRATION=ROOT/'supabase'/'staging_only'/'078_workshop_viewer_read_snapshots.sql'
EXPECTED_REF='cdsmnqxtyyoeoznmbidd'
def scalar(cur,q,args=()):cur.execute(q,args);return cur.fetchone()[0]
def main():
 load_local_env();assert_staging_target(database_url=required('PDC_STAGING_DATABASE_URL'))
 sql=MIGRATION.read_text(encoding='utf-8')
 if sql.count("require_pdc_role('viewer')")!=2 or 'workshop_require_planner_operator' in sql:raise RuntimeError('Migration 078 source contract invalid')
 conn=get_conn();
 try:
  conn.autocommit=True
  with conn.cursor() as cur:
   before={'vehicles':scalar(cur,'select count(*) from public.vehicles'),'bookings':scalar(cur,'select count(*) from public.workshop_bookings')}
   cur.execute(sql)
   defs={}
   for name in ['get_workshop_eligibility_snapshot','get_station_workshop_snapshot']:
    cur.execute("select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname=%s",(name,));rows=cur.fetchall()
    if len(rows)!=1:raise RuntimeError(f'Expected one {name}, got {len(rows)}')
    body=rows[0][0]
    if "require_pdc_role('viewer')" not in body or 'workshop_require_planner_operator' in body:raise RuntimeError(f'{name} viewer contract missing')
    defs[name]=hashlib.sha256(body.encode()).hexdigest()
   after={'vehicles':scalar(cur,'select count(*) from public.vehicles'),'bookings':scalar(cur,'select count(*) from public.workshop_bookings')}
   if after!=before:raise RuntimeError(f'Operational row counts changed: {before} -> {after}')
   print(json.dumps({'status':'applied','migration':'078','projectRef':EXPECTED_REF,'rowCounts':after,'functionDefinitionSha256':defs},sort_keys=True))
 finally:conn.close()
if __name__=='__main__':main()
