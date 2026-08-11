#!/usr/bin/env python3
"""Explicit rollback-only schema/security proof for staging Migrations160-162.

This script never commits. It refuses to connect unless PDC_162_ROLLBACK_ONLY=YES,
uses the shared structured staging-target guard, applies Migrations160-162 inside one
outer transaction, checks its effective ACL/immutability/function contracts,
rolls back, then proves from a fresh connection that no 162 objects/ledger row remain.
It intentionally does not approve or activate any operational pair.
"""
from __future__ import annotations
import os
import hashlib
import re
import subprocess
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:sys.path.insert(0,str(ROOT))
import psycopg2
from scripts.pdc_staging_runtime import assert_staging_target

MIGRATIONS=(
 ROOT/'supabase'/'staging_only'/'160_email_communication_board_actions.sql',
 ROOT/'supabase'/'staging_only'/'161_non_navision_jobcard_board_creation.sql',
 ROOT/'supabase'/'staging_only'/'162_manager_approved_workbook_canonical_activation.sql',
)
EXPECTED_SHA256=(
 'b78f1b8b610eb9348954723b2c1e734ad401cc20cfa0b6204257b6f9317520bc',
 'b2a447bd1412da545673713d97f3c67474bb6e8440e3db079ed96e66fa4ecc09',
 '09e80662b0f861a03b39544b9238334c6df6b0e9e9dd343b45501be0ceaada4b',
)
TABLES=(
 'pdc_email_communication_receipts','pdc_email_communication_action_receipts','pdc_email_evidence_consumptions',
 'pdc_non_navision_jobcard_receipts','pdc_non_navision_jobcard_source_row_receipts',
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
 expected_commit=os.getenv('PDC_162_EXPECTED_COMMIT','')
 head=subprocess.run(['git','rev-parse','HEAD'],cwd=ROOT,check=True,capture_output=True,text=True).stdout.strip()
 dirty=subprocess.run(['git','status','--porcelain','--untracked-files=all'],cwd=ROOT,check=True,capture_output=True,text=True).stdout.strip()
 if not re.fullmatch(r'[a-f0-9]{40}',expected_commit) or head!=expected_commit or dirty:
  raise SystemExit('Refusing: exact clean reviewed commit must match PDC_162_EXPECTED_COMMIT')
 actual_hashes=tuple(hashlib.sha256(path.read_bytes()).hexdigest() for path in MIGRATIONS)
 if actual_hashes!=EXPECTED_SHA256:
  raise SystemExit(f'Refusing: migration source digest mismatch {actual_hashes}')
 dsn=os.getenv('PDC_STAGING_DIRECT_DATABASE_URL') or os.getenv('PDC_STAGING_DATABASE_URL')
 assert_staging_target(database_url=dsn)
 sources=[body(path.read_text(encoding='utf-8')) for path in MIGRATIONS]
 con=psycopg2.connect(dsn);con.autocommit=False
 try:
  with con.cursor() as cur:
   cur.execute("select count(*) from supabase_migrations.schema_migrations where version in ('160','161','162')")
   if cur.fetchone()!=(0,):raise AssertionError('Migrations160-162 already partly applied; pre-deployment rollback proof is not applicable')
   for source in sources:cur.execute(source)
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
                  'canonical_approval_set_hash_conflict','repreview_required','migration157_apply_not_bypassed',
                  'lock table public.navision_backend_records in share row exclusive mode',
                  'lock table public.navision_board_activations in share row exclusive mode',
                  'lock table public.vehicles in share row exclusive mode',
                  'lock table public.vehicle_aliases in share row exclusive mode'):
    assert marker in definition,marker
   assert definition.index('lock table public.navision_backend_records') < definition.index('pdc_pmb_workbook_canonical_candidate'),definition
   # A second session cannot establish any competing canonical identity while
   # Apply's complete identity-surface locks are held.
   for table in ('navision_backend_records','navision_board_activations','vehicles','vehicle_aliases'):
    cur.execute(f'lock table public.{table} in share row exclusive mode')
   competing=psycopg2.connect(dsn);competing.autocommit=False
   try:
    with competing.cursor() as other:
     other.execute("set local lock_timeout='500ms'")
     for statement in (
      "update public.navision_backend_records set updated_at=updated_at where id=(select id from public.navision_backend_records order by id limit 1)",
      "update public.navision_board_activations set updated_at=updated_at where backend_record_id=(select backend_record_id from public.navision_board_activations order by backend_record_id limit 1)",
      "update public.vehicles set updated_at=updated_at where id=(select id from public.vehicles order by id limit 1)",
      "update public.vehicle_aliases set updated_at=updated_at where id=(select id from public.vehicle_aliases order by id limit 1)",
     ):
      try:
       other.execute(statement)
      except psycopg2.Error as exc:
       assert exc.pgcode=='55P03',exc
       competing.rollback();other.execute("set local lock_timeout='500ms'")
      else:
       raise AssertionError('competing identity writer was not blocked')
   finally:
    competing.rollback();competing.close()
  con.rollback()
 finally:
  con.rollback();con.close()
 fresh=psycopg2.connect(dsn);fresh.autocommit=True
 try:
  with fresh.cursor() as cur:
   cur.execute("select count(*) from supabase_migrations.schema_migrations where version in ('160','161','162')")
   assert cur.fetchone()==(0,)
   for table in TABLES:
    cur.execute("select to_regclass(%s)",(f'public.{table}',));assert cur.fetchone()==(None,),table
   for signature in FUNCTIONS:
    cur.execute("select to_regprocedure(%s)",(f'public.{signature}',));assert cur.fetchone()==(None,),signature
 finally:
  fresh.close()
 print({'ok':True,'mode':'rollback_only','migrations':'160-162','ledger_restored_to':'159','created_objects_absent':True,
        'direct_table_privileges_denied':True,'service_role_rpc_execute_denied':True,'authenticated_public_rpcs_present_in_transaction':True})
 return 0
if __name__=='__main__':raise SystemExit(main())
