#!/usr/bin/env python3
"""Apply staging-only migration 080 with fail-closed target and postchecks."""
from __future__ import annotations
import hashlib,json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:sys.path.insert(0,str(ROOT))
from scripts.pdc_staging_runtime import assert_staging_target,get_conn,load_local_env,required
MIGRATION=ROOT/'supabase'/'staging_only'/'080_navision_generic_header_dealer_evidence.sql'
def scalar(cur,q,args=()):cur.execute(q,args);return cur.fetchone()[0]
def main():
 load_local_env();assert_staging_target(database_url=required('PDC_STAGING_DATABASE_URL'))
 sql=MIGRATION.read_text(encoding='utf-8')
 if "count(distinct code)=1" not in sql or "('14450','37047')" not in sql:raise RuntimeError('Migration 080 source contract invalid')
 conn=get_conn()
 try:
  conn.autocommit=True
  with conn.cursor() as cur:
   before={t:scalar(cur,f'select count(*) from public.{t}') for t in ['navision_backend_records','navision_import_batches','vehicles','workshop_bookings']}
   cur.execute(sql)
   body=scalar(cur,"select pg_get_functiondef('public.navision_row_declared_dealer_code(jsonb)'::regprocedure)")
   if 'unique_fallback' not in body or 'having count(distinct code)=1' not in body.lower():raise RuntimeError('Generic-header dealer evidence postcheck failed')
   exact=scalar(cur,"select public.navision_row_declared_dealer_code(jsonb_build_object('navisionRawEvidence',jsonb_build_object('columns',jsonb_build_array(jsonb_build_object('header','Dealer','value','014450')))))")
   generic=scalar(cur,"select public.navision_row_declared_dealer_code(jsonb_build_object('navisionRawEvidence',jsonb_build_object('columns',jsonb_build_array(jsonb_build_object('header','Column 18','value','014450'),jsonb_build_object('header','Column 24','value','PILBARA TOYOTA')))))")
   ambiguous=scalar(cur,"select public.navision_row_declared_dealer_code(jsonb_build_object('navisionRawEvidence',jsonb_build_object('columns',jsonb_build_array(jsonb_build_object('header','Column 18','value','014450'),jsonb_build_object('header','Column 41','value','037047')))))")
   if exact!='14450' or generic!='14450' or ambiguous is not None:raise RuntimeError(f'Dealer evidence behavior invalid: {exact},{generic},{ambiguous}')
   after={t:scalar(cur,f'select count(*) from public.{t}') for t in before}
   if after!=before:raise RuntimeError(f'Operational row counts changed: {before} -> {after}')
   print(json.dumps({'status':'applied','migration':'080','projectRef':'cdsmnqxtyyoeoznmbidd','rowCounts':after,'functionDefinitionSha256':hashlib.sha256(body.encode()).hexdigest(),'checks':{'exactHeader':exact,'genericHeader':generic,'ambiguous':ambiguous}},sort_keys=True))
 finally:conn.close()
if __name__=='__main__':main()
