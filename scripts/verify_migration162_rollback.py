#!/usr/bin/env python3
"""Explicit rollback-only schema/security proof for staging Migration162.

This script never commits. It refuses to connect unless PDC_162_ROLLBACK_ONLY=YES,
uses the shared structured staging-target guard, applies Migration162 inside one
outer transaction, checks its effective ACL/immutability/function contracts,
rolls back, then proves from a fresh connection that no 162 objects/ledger row remain.
It intentionally does not approve or activate any operational pair.
"""
from __future__ import annotations
import os
import re
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:sys.path.insert(0,str(ROOT))
import psycopg2
from scripts.pdc_staging_runtime import assert_staging_target

MIGRATION=ROOT/'supabase'/'staging_only'/'162_manager_approved_workbook_canonical_activation.sql'
TABLES=(
 'pdc_pmb_canonical_manager_authorities','pdc_pmb_canonical_manager_approvals','pdc_pmb_canonical_admin_countersignatures',
 'pdc_pmb_canonical_apply_authorizations','pdc_pmb_canonical_apply_receipts','pdc_pmb_canonical_pair_receipts',
)
IMMUTABLE_TABLES=set(TABLES)-{'pdc_pmb_canonical_manager_authorities'}
FUNCTIONS=(
 'pdc_pmb_workbook_canonical_candidate(uuid)',
 'configure_pdc_pmb_canonical_manager_authority(uuid,boolean,text)',
 'manager_approve_pdc_pmb_canonical_activation(uuid,uuid,text,text,text,uuid,integer,uuid,integer,text,text)',
 'administrator_countersign_pdc_pmb_canonical_activation(uuid,text,text,text)',
 'authorize_pdc_pmb_canonical_activation_apply(uuid,text,text,integer,text)',
 'apply_pdc_pmb_canonical_activations(uuid,text,text,integer,text)',
)

def body(text:str)->str:
 text=text.replace('\r\n','\n')
 text=re.sub(r'^\s*begin;\s*','',text,count=1,flags=re.I)
 return re.sub(r'\s*commit;\s*$','',text,count=1,flags=re.I)

def main()->int:
 if os.getenv('PDC_162_ROLLBACK_ONLY')!='YES':
  raise SystemExit('Refusing: set PDC_162_ROLLBACK_ONLY=YES for explicit rollback-only execution')
 dsn=os.getenv('PDC_STAGING_DIRECT_DATABASE_URL') or os.getenv('PDC_STAGING_DATABASE_URL')
 assert_staging_target(database_url=dsn)
 sql=body(MIGRATION.read_text(encoding='utf-8'))
 con=psycopg2.connect(dsn);con.autocommit=False
 try:
  with con.cursor() as cur:
   cur.execute("select exists(select 1 from supabase_migrations.schema_migrations where version='162')")
   if cur.fetchone()[0]:raise AssertionError('Migration162 is already applied; pre-deployment rollback proof is not applicable')
   cur.execute(sql)
   cur.execute("select name from supabase_migrations.schema_migrations where version='162'")
   assert cur.fetchone()==('manager_approved_workbook_canonical_activation',)
   for table in TABLES:
    cur.execute("select to_regclass(%s)::text",(f'public.{table}',));assert cur.fetchone()[0]==table
    for role in ('anon','authenticated','service_role'):
     cur.execute("select has_table_privilege(%s,%s,'SELECT,INSERT,UPDATE,DELETE')",(role,f'public.{table}'))
     assert cur.fetchone()==(False,),(table,role)
    if table in IMMUTABLE_TABLES:
     cur.execute("""select count(*) from pg_trigger where tgrelid=to_regclass(%s) and tgname=%s and not tgisinternal and tgenabled<>'D'""",
                 (f'public.{table}',f'{table}_immutable'))
     assert cur.fetchone()==(1,),table
   for signature in FUNCTIONS:
    cur.execute("select to_regprocedure(%s)::text",(f'public.{signature}',));assert cur.fetchone()[0] is not None,signature
   for signature in FUNCTIONS[1:]:
    cur.execute("select has_function_privilege('authenticated',to_regprocedure(%s),'EXECUTE'),has_function_privilege('service_role',to_regprocedure(%s),'EXECUTE')",
                (f'public.{signature}',f'public.{signature}'))
    assert cur.fetchone()==(True,False),signature
   cur.execute("select pg_get_functiondef('public.apply_pdc_pmb_canonical_activations(uuid,text,text,integer,text)'::regprocedure)")
   definition=cur.fetchone()[0].lower()
   for marker in ('exact_canonical_apply_replay','backend_revision_conflict','canonical_candidate_drift',
                  'canonical_approval_set_hash_conflict','repreview_required','migration157_apply_not_bypassed'):
    assert marker in definition,marker
  con.rollback()
 finally:
  con.rollback();con.close()
 fresh=psycopg2.connect(dsn);fresh.autocommit=True
 try:
  with fresh.cursor() as cur:
   cur.execute("select exists(select 1 from supabase_migrations.schema_migrations where version='162')")
   assert cur.fetchone()==(False,)
   for table in TABLES:
    cur.execute("select to_regclass(%s)",(f'public.{table}',));assert cur.fetchone()==(None,),table
   for signature in FUNCTIONS:
    cur.execute("select to_regprocedure(%s)",(f'public.{signature}',));assert cur.fetchone()==(None,),signature
 finally:
  fresh.close()
 print({'ok':True,'mode':'rollback_only','migration':'162','ledger_restored_to':'161','created_objects_absent':True,
        'direct_table_privileges_denied':True,'service_role_rpc_execute_denied':True,'authenticated_public_rpcs_present_in_transaction':True})
 return 0
if __name__=='__main__':raise SystemExit(main())
