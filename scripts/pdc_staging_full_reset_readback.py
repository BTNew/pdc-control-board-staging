"""Authoritative read-only acceptance/idempotency controller for staging reset 354."""
from __future__ import annotations
import argparse, hashlib, json
from pathlib import Path
from pdc_staging_management_migration import _post,STAGING_REF
HISTORY={'pdc_auditor_telegram_deliveries_230','pdc_auditor_telegram_instructions_225','pdc_email_source_claims','pdc_jobcard_attachment_rule_receipts_279','pdc_monitor_runtime_binding_rotations_270','pdc_supervised_rule_events','pdc_supervised_telegram_commands'}
INTENTIONAL={'monitored_mailboxes','pdc_email_monitor_pilot','pdc_staging_verified_backup_manifests'}
def qi(n):return '"'+n.replace('"','""')+'"'
def lit(n):return "'"+n.replace("'","''")+"'"
def main():
 p=argparse.ArgumentParser();p.add_argument('--catalog',type=Path,required=True);p.add_argument('--prep-manifest',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 live=json.loads(a.catalog.read_text());prep=json.loads(a.prep_manifest.read_text());tables={x['name'] for x in live['tables']};sc={x['name']:x['scope'] for x in prep['tables']};preserve=sorted({n for n in tables if sc.get(n)=='preserve'}-HISTORY);purge=sorted(tables-set(preserve))
 count_union=' union all '.join(f"select {lit(n)} table_name,count(*)::bigint n from public.{qi(n)}" for n in purge)
 hash_union=' union all '.join(f"select {lit(n)} table_name,count(*)::bigint n,encode(extensions.digest(convert_to(coalesce(string_agg(to_jsonb(t)::text,'' order by to_jsonb(t)::text),''),'UTF8'),'sha256'),'hex') h from public.{qi(n)} t" for n in preserve if n not in INTENTIONAL)
 sql=f"""SET TRANSACTION READ ONLY;
select jsonb_build_object(
 'project_ref','cdsmnqxtyyoeoznmbidd',
 'production_sentinel_absent',to_regclass('public.pdc_production_environment_sentinel') is null,
 'head',(select jsonb_build_object('version',version,'name',name) from supabase_migrations.schema_migrations where version~'^[0-9]{{14}}$' order by version desc limit 1),
 'history_counts',(select jsonb_object_agg(table_name,n order by table_name) from ({count_union}) q),
 'preserved_current',(select jsonb_object_agg(table_name,jsonb_build_object('count',n,'sha256',h) order by table_name) from ({hash_union}) q),
 'receipt',(select to_jsonb(r) from public.pdc_staging_full_reset_receipts_354 r where action_key='craig-full-vehicle-history-reset-20260824'),
 'fences',(select jsonb_agg(to_jsonb(f)-'created_at' order by fence_key) from public.pdc_staging_replay_fences_354 f),
 'monitor',jsonb_build_object(
  'pilot_enabled',(select enabled from public.pdc_email_monitor_pilot where singleton),
  'outbound_email_enabled',(select outbound_email_enabled from public.pdc_email_monitor_pilot where singleton),
  'minimum_uid',(select minimum_uid from public.pdc_email_monitor_pilot where singleton),
  'active_mailboxes',(select count(*) from public.monitored_mailboxes where active),
  'active_writers',(select count(*) from public.pdc_monitor_stage_activation_writers where active and revoked_at is null),
  'running_status',(select running_status from public.pdc_email_monitor_status where singleton),
  'gateway_instance_id',(select gateway_instance_id from public.pdc_email_monitor_status where singleton)),
 'backup',jsonb_build_object('rows',(select count(*) from public.pdc_staging_verified_backup_manifests),'manifest',(select backup_manifest_sha256 from public.pdc_staging_verified_backup_manifests)),
 'authority',jsonb_build_object(
  'cleanse_authenticated',has_function_privilege('authenticated','public.pdc_admin_run_staging_cleanse_348()','EXECUTE'),
  'bulk_purge_authenticated',has_function_privilege('authenticated','public.purge_all_staging_board_vehicles(text,text)','EXECUTE'),
  'vehicle_purge_authenticated',has_function_privilege('authenticated','public.purge_vehicle_from_board(uuid,integer,text)','EXECUTE'),
  'passthrough_absent',to_regprocedure('public.pdc_full_reset_trigger_passthrough_354()') is null,
  'triggers_still_enabled',not exists(select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and not t.tgisinternal and t.tgenabled='D'))
) as evidence;"""
 rows=_post(f'https://api.supabase.com/v1/projects/{STAGING_REF}/database/query/read-only',sql)
 if not isinstance(rows,list) or len(rows)!=1:raise RuntimeError('PDC_354_READBACK_INVALID')
 e=rows[0]['evidence'];receipt=e['receipt'];pre=receipt['preserved_pre_sha256'];mismatch=[]
 for n,v in e['preserved_current'].items():
  if pre.get(n)!=v['sha256']:mismatch.append(n)
 e['preserved_mismatches']=mismatch;e['all_history_zero']=all(v==0 for v in e['history_counts'].values());e['history_relation_count']=len(e['history_counts'])
 e['uid594_deferred']=e['monitor']['minimum_uid']==594 and any(f['fence_key']=='email:Inbox' and f['denied_through']==593 and f['first_eligible']==594 and f['deferred_exact']==594 for f in e['fences']) and e['history_counts']['ai_email_intake']==0
 e['reset_authority_revoked']=not any([e['authority']['cleanse_authenticated'],e['authority']['bulk_purge_authenticated'],e['authority']['vehicle_purge_authenticated']]) and e['authority']['passthrough_absent'] and e['authority']['triggers_still_enabled']
 e['status']='NO_OP_ALREADY_RESET' if e['all_history_zero'] and not mismatch and e['uid594_deferred'] and e['reset_authority_revoked'] else 'FAILED'
 core=json.dumps(e,sort_keys=True,separators=(',',':')).encode();e['readback_sha256']=hashlib.sha256(core).hexdigest();a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(e,indent=2,sort_keys=True),encoding='utf-8');print(json.dumps({'status':e['status'],'history_relations':len(e['history_counts']),'all_history_zero':e['all_history_zero'],'preserved_mismatches':mismatch,'uid594_deferred':e['uid594_deferred'],'reset_authority_revoked':e['reset_authority_revoked'],'readback_sha256':e['readback_sha256'],'output':str(a.output.resolve())},sort_keys=True));return 0 if e['status']=='NO_OP_ALREADY_RESET' else 2
if __name__=='__main__':raise SystemExit(main())
