#!/usr/bin/env python3
"""Rollback-only staging schema/ACL rehearsal for Migrations 160 and 161."""
from __future__ import annotations
import hashlib, json, os, re
from pathlib import Path
import psycopg2
from scripts.pdc_staging_runtime import assert_staging_target

ROOT=Path(__file__).resolve().parents[1]
FILES=[ROOT/'supabase'/'staging_only'/'160_email_communication_board_actions.sql',ROOT/'supabase'/'staging_only'/'161_non_navision_jobcard_board_creation.sql']
SIGS=[
 'public.process_pdc_email_communication(uuid,text,text,jsonb,text)',
 'public.read_pdc_email_communication_receipt(uuid)',
 'public.process_pdc_non_navision_jobcard(uuid,text,text,jsonb,text)',
 'public.read_pdc_non_navision_jobcard_receipt(uuid)',
]
TABLES=['pdc_email_communication_receipts','pdc_email_communication_action_receipts','pdc_non_navision_jobcard_receipts']

def body(path:Path)->str:
 text=path.read_text(encoding='utf-8')
 text=re.sub(r'^\s*begin;\s*','',text,count=1,flags=re.I)
 return re.sub(r'\s*commit;\s*$','',text,count=1,flags=re.I)

def one(cur,sql,params=()):
 cur.execute(sql,params);return cur.fetchone()[0]

def main()->int:
 dsn=os.getenv('PDC_STAGING_DIRECT_DATABASE_URL') or os.getenv('PDC_STAGING_DATABASE_URL')
 assert_staging_target(database_url=dsn)
 digests={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in FILES}
 conn=psycopg2.connect(dsn);conn.autocommit=False
 try:
  with conn.cursor() as cur:
   assert one(cur,"select project_ref from public.pdc_staging_environment_sentinel where singleton")=='cdsmnqxtyyoeoznmbidd'
   assert not one(cur,"select to_regclass('public.pdc_production_environment_sentinel') is not null")
   assert one(cur,"select exists(select 1 from supabase_migrations.schema_migrations where version='159')")
   assert not one(cur,"select exists(select 1 from supabase_migrations.schema_migrations where version in('160','161'))")
   before={t:one(cur,'select to_regclass(%s) is not null',(f'public.{t}',)) for t in TABLES}
   for p in FILES: cur.execute(body(p))
   for sig in SIGS:
    assert one(cur,'select to_regprocedure(%s) is not null',(sig,)),sig
    acl={role:one(cur,"select has_function_privilege(%s,%s,'EXECUTE')",(role,sig)) for role in ('public','anon','authenticated','service_role')}
    assert acl=={'public':False,'anon':False,'authenticated':True,'service_role':False},(sig,acl)
    definition=one(cur,'select pg_get_functiondef(%s::regprocedure)',(sig,))
    assert 'SECURITY DEFINER' in definition
   assert one(cur,"select count(*) from supabase_migrations.schema_migrations where version in('160','161')") == 2
   for t in TABLES:
    assert one(cur,'select to_regclass(%s) is not null',(f'public.{t}',))
  conn.rollback()
  with conn.cursor() as cur:
   assert one(cur,"select count(*) from supabase_migrations.schema_migrations where version in('160','161')") == 0
   for t,existed in before.items(): assert one(cur,'select to_regclass(%s) is not null',(f'public.{t}',))==existed
  conn.rollback()
  print(json.dumps({'ok':True,'mode':'rollback_rehearsal','migrations':['160','161'],'sha256':digests,'acl':'authenticated_only','rollback_verified':True},sort_keys=True))
  return 0
 finally: conn.close()

if __name__=='__main__': raise SystemExit(main())
