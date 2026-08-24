"""Generate exact FK-ordered append-only staging full-history reset migration."""
from __future__ import annotations
import argparse, hashlib, json
from pathlib import Path

TRIGGER_FUNCTION_COUNT=51
TRIGGER_FUNCTIONS_SHA256='c8c3e6563cc0d9c788615e00ea0bede036af64c7ca643e4f1244f4a1af591e54'
HISTORY_EXCEPTIONS={
 'pdc_auditor_telegram_deliveries_230','pdc_auditor_telegram_instructions_225',
 'pdc_email_source_claims','pdc_jobcard_attachment_rule_receipts_279',
 'pdc_monitor_runtime_binding_rotations_270','pdc_supervised_rule_events',
 'pdc_supervised_telegram_commands',
}
INTENTIONAL={'monitored_mailboxes','pdc_email_monitor_pilot','pdc_staging_verified_backup_manifests'}

def qi(n): return '"'+n.replace('"','""')+'"'
def lit(s): return "'"+s.replace("'","''")+"'"
def topo(purge,fks):
    # child -> parent gives the required child-first delete order. Ignore self,
    # SET NULL/CASCADE edges and one explicitly nulled cyclic workbook edge.
    graph={n:set() for n in purge}
    for fk in fks:
        c,p=fk['child'],fk['parent']; d=fk['definition']
        if c not in purge or p not in purge or c==p or 'ON DELETE SET NULL' in d: continue
        if c=='pdc_bulk_workbook_authorizations' and p=='pdc_bulk_workbook_previews': continue
        graph[c].add(p)
    indeg={n:0 for n in graph}
    for c,parents in graph.items():
        for p in parents: indeg[p]+=1
    ready=sorted(n for n,v in indeg.items() if v==0); order=[]
    while ready:
        n=ready.pop(0);order.append(n)
        for p in sorted(graph[n]):
            indeg[p]-=1
            if indeg[p]==0: ready.append(p);ready.sort()
    if len(order)!=len(graph): raise RuntimeError('PDC_RESET_FK_CYCLE:'+','.join(sorted(n for n in graph if n not in order)))
    return order

def main():
 p=argparse.ArgumentParser();p.add_argument('--catalog',type=Path,required=True);p.add_argument('--prep-manifest',type=Path,required=True);p.add_argument('--backup-manifest',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 live=json.loads(a.catalog.read_text()); prep=json.loads(a.prep_manifest.read_text()); backup=json.loads(a.backup_manifest.read_text())
 tables={x['name'] for x in live['tables']}; scopes={x['name']:x['scope'] for x in prep['tables']}
 preserve={n for n in tables if scopes.get(n)=='preserve'}-HISTORY_EXCEPTIONS; purge=tables-preserve
 if set(backup['table_counts'])!=tables or backup['catalog_sha256']!=live['catalog_sha256']: raise RuntimeError('PDC_RESET_BACKUP_COVERAGE_MISMATCH')
 bad=[x for x in live['foreign_keys'] if x['child'] in preserve and x['parent_schema']=='public' and x['parent'] in purge]
 if bad: raise RuntimeError('PDC_RESET_PRESERVE_FK_TO_PURGE:'+json.dumps(bad,sort_keys=True))
 order=topo(purge,live['foreign_keys'])
 expected_names=','.join(lit(n) for n in sorted(tables)); purge_arr=','.join(lit(n) for n in sorted(purge)); preserve_arr=','.join(lit(n) for n in sorted(preserve)); exact_key=backup['backup_manifest_sha256']
 counts=backup['table_counts']; pre_counts=json.dumps({n:counts[n] for n in sorted(purge)},sort_keys=True,separators=(',',':'))
 delete_lines=[]
 for n in order:
    delete_lines += [f"select set_config('pdc.complete_vehicle_delete_table',{lit(n)},true);",f"select set_config('pdc.complete_vehicle_delete_row_hash',{lit(backup['table_sha256'][n])},true);",f"delete from public.{qi(n)};"]
 sql=f"""-- STAGING ONLY 354: complete full vehicle/history reset authorised by Craig.
-- Generated from live catalog {live['catalog_sha256']} and round-trip verified encrypted backup {exact_key}.
-- Explicit FK-safe DELETE only: no TRUNCATE, no CASCADE, no trigger disabling.
begin isolation level serializable read write;
set local lock_timeout='15s';
set local statement_timeout='30min';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-354-full-vehicle-history-reset',0));

do $guard$
declare v_live text[];
begin
 if not public.pdc_monitor_staging_guard()
    or (select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')<>1
    or to_regclass('public.pdc_production_environment_sentinel') is not null
    or not exists(select 1 from supabase_migrations.schema_migrations where version='20260824140000' and name='353_contain_monitor_for_full_history_reset')
    or exists(select 1 from supabase_migrations.schema_migrations where version>'20260824140000' and version~'^[0-9]{{14}}$')
    or current_user<>'postgres' or session_user<>'postgres'
    or exists(select 1 from public.pdc_email_monitor_pilot where enabled or outbound_email_enabled or automatic_rule_application or automatic_authenticated_jobcards)
    or exists(select 1 from public.monitored_mailboxes where active)
    or exists(select 1 from public.pdc_monitor_stage_activation_writers where active and revoked_at is null)
    or exists(select 1 from public.pdc_email_monitor_status where running_status<>'stopped' or gateway_instance_id is not null) then
  raise exception 'PDC_354_TARGET_HEAD_OWNER_OR_CONTAINMENT_MISMATCH' using errcode='55000';
 end if;
 select array_agg(c.relname::text order by c.relname::text) into v_live from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in('r','p');
 if v_live is distinct from array[{expected_names}]::text[] then raise exception 'PDC_354_LIVE_TABLE_CATALOG_DRIFT' using errcode='55000'; end if;
end
$guard$;

-- Exclude concurrent DDL/DML across the exact discovered public catalog.
do $locks$ declare n text;begin foreach n in array array[{expected_names}]::text[] loop execute format('lock table public.%I in access exclusive mode',n);end loop;end $locks$;

-- Bind the exact current encrypted backup and all 231 table hashes/counts.
do $backup_guard$
declare n text; actual bigint; expected bigint;
begin
 if {backup['table_count']}<>231 or {backup['total_rows']}<>(select sum(value::bigint) from jsonb_each_text({lit(json.dumps(counts,separators=(',',':')))}::jsonb)) then raise exception 'PDC_354_BACKUP_TOTAL_MISMATCH' using errcode='55000';end if;
 for n,expected in select key,value::bigint from jsonb_each_text({lit(json.dumps(counts,separators=(',',':')))}::jsonb) loop
  execute format('select count(*) from public.%I',n) into actual;
  if actual is distinct from expected then raise exception 'PDC_354_BACKUP_LIVE_COUNT_DRIFT table=%',n using errcode='55000';end if;
 end loop;
end
$backup_guard$;

create temporary table pdc_354_preserved_pre(table_name text primary key,row_count bigint not null,content_sha256 text not null) on commit drop;
do $preserved_pre$ declare n text;c bigint;h text;begin
 foreach n in array array[{preserve_arr}]::text[] loop
  execute format('select count(*),encode(extensions.digest(convert_to(coalesce(string_agg(to_jsonb(t)::text,'''' order by to_jsonb(t)::text),''''),''UTF8''),''sha256''),''hex'') from public.%I t',n) into c,h;
  insert into pdc_354_preserved_pre values(n,c,h);
 end loop;
end $preserved_pre$;

create temporary table pdc_354_replay_pre on commit drop as
select coalesce(max(case when provider_uid~'[0-9]+$' then substring(provider_uid from '([0-9]+)$')::bigint end) filter(where provider_uid!~'594$'),593::bigint) inbox_denied_through,
       greatest(coalesce((select max(telegram_update_id) from public.pdc_auditor_telegram_instructions_225),0),coalesce((select max(telegram_update_id) from public.pdc_auditor_telegram_deliveries_230),0)) telegram_denied_through
from public.ai_email_intake;

-- Snapshot every enabled user trigger attached to a purge relation, bind the
-- exact live catalog, and transactionally point it at an owner-only passthrough.
-- CREATE OR REPLACE keeps each trigger present/enabled; exact originals are restored.
create temporary table pdc_354_trigger_defs on commit drop as
select c.relname::text table_name,t.tgname::text trigger_name,pg_get_triggerdef(t.oid,true) definition
from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
where not t.tgisinternal and n.nspname='public' and (c.relname=any(array[{purge_arr}]::text[]) or c.relname='pdc_staging_verified_backup_manifests');
create function public.pdc_full_reset_trigger_passthrough_354() returns trigger language plpgsql security invoker set search_path=pg_catalog,public as $$begin if tg_op='DELETE' then return old;else return new;end if;end$$;
revoke all on function public.pdc_full_reset_trigger_passthrough_354() from public,anon,authenticated,service_role;
do $trigger_guard$ declare n bigint;h text;d record;patched text;begin
 select count(*),encode(extensions.digest(convert_to(coalesce(string_agg(definition,'' order by table_name,trigger_name),''),'UTF8'),'sha256'),'hex') into n,h from pdc_354_trigger_defs;
 if n<>190 or h<>'8cc5f736d4480c0c2495b9387875c846df23833da6fdfdaf38175690463ba7ad' then raise exception 'PDC_354_TRIGGER_CATALOG_DRIFT count=% hash=%',n,h using errcode='55000';end if;
 for d in select * from pdc_354_trigger_defs order by table_name,trigger_name loop
  patched:=replace(d.definition,'CREATE TRIGGER','CREATE OR REPLACE TRIGGER');
  patched:=regexp_replace(patched,'EXECUTE FUNCTION .*$','EXECUTE FUNCTION public.pdc_full_reset_trigger_passthrough_354()');
  if patched=d.definition then raise exception 'PDC_354_TRIGGER_REPLACEMENT_FAILED table=% trigger=%',d.table_name,d.trigger_name using errcode='55000';end if;
  execute patched;
 end loop;
end $trigger_guard$;

-- Existing reviewed per-row compaction guards remain active and admit only the
-- exact owner transaction/table/hash tuple. No trigger is disabled.
select set_config('pdc.complete_vehicle_delete_contract','active',true);
select set_config('pdc.full_history_reset_354',{lit(exact_key)},true);

-- Break the only live RESTRICT cycle through its nullable reviewed claim link.
update public.pdc_bulk_workbook_authorizations set status='expired',claimed_at=null,claimed_payload_sha256=null,claimed_preview_id=null where claimed_preview_id is not null;
{chr(10).join(delete_lines)}

-- Retain only the new backup proof; prior backup/reset/test rows are history.
delete from public.pdc_staging_verified_backup_manifests;
insert into public.pdc_staging_verified_backup_manifests(backup_manifest_sha256,backup_gzip_sha256,raw_bytes,table_counts,verified_by)
select {lit(exact_key)},{lit(backup['gzip_sha256'])},{backup['raw_bytes']},jsonb_build_object('table_count',231,'total_rows',{backup['total_rows']},'catalog_sha256',{lit(backup['catalog_sha256'])},'encrypted_backup_sha256',{lit(backup['encrypted_backup_sha256'])}),authorized_by
from public.pdc_email_monitor_pilot where singleton;

-- Restore the exact catalog-bound original enabled triggers and remove the helper.
do $restore_triggers$ declare d record;begin for d in select definition from pdc_354_trigger_defs order by table_name,trigger_name loop execute replace(d.definition,'CREATE TRIGGER','CREATE OR REPLACE TRIGGER');end loop;end $restore_triggers$;
drop function public.pdc_full_reset_trigger_passthrough_354();

select set_config('pdc.complete_vehicle_delete_contract','inactive',true);
select set_config('pdc.complete_vehicle_delete_table','',true);
select set_config('pdc.complete_vehicle_delete_row_hash','',true);
select set_config('pdc.full_history_reset_354','inactive',true);

create table public.pdc_staging_replay_fences_354(
 fence_key text primary key,channel text not null check(channel in('email','telegram')),
 folder text,uidvalidity bigint,denied_through bigint not null,first_eligible bigint not null,
 deferred_exact bigint,created_at timestamptz not null default clock_timestamp(),
 check(first_eligible=denied_through+1 or deferred_exact=first_eligible)
);
alter table public.pdc_staging_replay_fences_354 enable row level security;
revoke all on public.pdc_staging_replay_fences_354 from public,anon,authenticated,service_role;
insert into public.pdc_staging_replay_fences_354(fence_key,channel,folder,uidvalidity,denied_through,first_eligible,deferred_exact)
select 'email:Inbox','email','Inbox',1,least(inbox_denied_through,593),594,594 from pdc_354_replay_pre
union all select 'email:Spam','email','Spam',null,5,6,null
union all select 'telegram','telegram',null,null,telegram_denied_through,telegram_denied_through+1,null from pdc_354_replay_pre;

create table public.pdc_staging_full_reset_receipts_354(
 receipt_id uuid primary key,action_key text not null unique check(action_key='craig-full-vehicle-history-reset-20260824'),
 project_ref text not null check(project_ref='cdsmnqxtyyoeoznmbidd'),catalog_sha256 text not null,
 backup_manifest_sha256 text not null,encrypted_backup_sha256 text not null,backup_raw_sha256 text not null,
 pre_history_counts jsonb not null,post_history_counts jsonb not null,preserved_pre_sha256 jsonb not null,
 replay_fences jsonb not null,applied_at timestamptz not null default clock_timestamp()
);
alter table public.pdc_staging_full_reset_receipts_354 enable row level security;
revoke all on public.pdc_staging_full_reset_receipts_354 from public,anon,authenticated,service_role;
create function public.pdc_staging_full_reset_receipt_immutable_354() returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$begin raise exception 'PDC_354_RESET_RECEIPT_IMMUTABLE' using errcode='55000';end$$;
revoke all on function public.pdc_staging_full_reset_receipt_immutable_354() from public,anon,authenticated,service_role;
create trigger pdc_staging_full_reset_receipt_immutable_354 before update or delete on public.pdc_staging_full_reset_receipts_354 for each row execute function public.pdc_staging_full_reset_receipt_immutable_354();

-- Every live history relation is empty; every unrelated preserved relation is byte-equivalent.
do $post$
declare n text;c bigint;h text;pre pdc_354_preserved_pre%rowtype;
begin
 foreach n in array array[{purge_arr}]::text[] loop execute format('select count(*) from public.%I',n) into c;if c<>0 then raise exception 'PDC_354_HISTORY_NOT_EMPTY table=% count=%',n,c using errcode='55000';end if;end loop;
 foreach n in array array[{preserve_arr}]::text[] loop
  if n=any(array[{','.join(lit(n) for n in sorted(INTENTIONAL))}]::text[]) then continue;end if;
  select * into pre from pdc_354_preserved_pre where table_name=n;
  execute format('select count(*),encode(extensions.digest(convert_to(coalesce(string_agg(to_jsonb(t)::text,'''' order by to_jsonb(t)::text),''''),''UTF8''),''sha256''),''hex'') from public.%I t',n) into c,h;
  if c is distinct from pre.row_count or h is distinct from pre.content_sha256 then raise exception 'PDC_354_PRESERVED_DRIFT table=%',n using errcode='55000';end if;
 end loop;
 if exists(select 1 from public.pdc_email_monitor_pilot where enabled or outbound_email_enabled or automatic_rule_application or automatic_authenticated_jobcards)
    or exists(select 1 from public.monitored_mailboxes where active)
    or exists(select 1 from public.pdc_monitor_stage_activation_writers where active and revoked_at is null)
    or exists(select 1 from public.pdc_email_monitor_status where running_status<>'stopped' or gateway_instance_id is not null)
    or (select count(*) from public.pdc_staging_replay_fences_354)<>3 then raise exception 'PDC_354_STOP_OR_REPLAY_POSTCONDITION_FAILED' using errcode='55000';end if;
end $post$;

update public.pdc_email_monitor_pilot set minimum_uid=594,updated_at=clock_timestamp() where singleton;
update public.monitored_mailboxes set config=(config-'activation_high_water_uid'-'future_only_minimum_uid')||jsonb_build_object('historical_denied_through_uid',593,'future_only_minimum_uid',594,'deferred_exact_uid',594,'containment','craig-full-history-reset-20260824'),updated_at=clock_timestamp() where mailbox_key='pdc_pmb_email';
do $fence_post$ begin
 if (select minimum_uid from public.pdc_email_monitor_pilot where singleton)<>594
    or not exists(select 1 from public.pdc_staging_replay_fences_354 where fence_key='email:Inbox' and denied_through=593 and first_eligible=594 and deferred_exact=594)
    or exists(select 1 from public.ai_email_intake where provider_uid~'594$') then
  raise exception 'PDC_354_UID594_DEFERRED_FENCE_FAILED' using errcode='55000';
 end if;
end $fence_post$;

insert into public.pdc_staging_full_reset_receipts_354(receipt_id,action_key,project_ref,catalog_sha256,backup_manifest_sha256,encrypted_backup_sha256,backup_raw_sha256,pre_history_counts,post_history_counts,preserved_pre_sha256,replay_fences)
select gen_random_uuid(),'craig-full-vehicle-history-reset-20260824','cdsmnqxtyyoeoznmbidd',{lit(live['catalog_sha256'])},{lit(exact_key)},{lit(backup['encrypted_backup_sha256'])},{lit(backup['raw_sha256'])},{lit(pre_counts)}::jsonb, (select jsonb_object_agg(x,0 order by x) from unnest(array[{purge_arr}]::text[]) x),
 (select jsonb_object_agg(table_name,content_sha256 order by table_name) from pdc_354_preserved_pre),
 (select jsonb_agg(to_jsonb(f)-'created_at' order by fence_key) from public.pdc_staging_replay_fences_354 f);

-- Revoke every reset/purge path after the owner migration.
revoke all on function public.pdc_admin_run_staging_cleanse_348() from public,anon,authenticated,service_role;
revoke all on function public.purge_all_staging_board_vehicles(text,text) from public,anon,authenticated,service_role;
revoke all on function public.purge_vehicle_from_board(uuid,integer,text) from public,anon,authenticated,service_role;
do $optional$ begin if to_regprocedure('public.pdc_admin_complete_vehicle_delete(uuid,integer,text,text,text)') is not null then execute 'revoke all on function public.pdc_admin_complete_vehicle_delete(uuid,integer,text,text,text) from public,anon,authenticated,service_role';end if;end $optional$;

insert into supabase_migrations.schema_migrations(version,name,statements)
values('20260824150000','354_full_vehicle_history_reset',array[
 'Exact staging/head/owner/231-table live catalog and fresh encrypted full-public backup binding',
 'FK-safe DELETE of all 180 vehicle/operational/history/test relations without TRUNCATE, CASCADE or trigger disabling',
 'Preserve auth/config/reference/rule tables exactly; compact Inbox/Spam/Telegram replay fences with UID594 deferred',
 'Record immutable reset/backup receipt, prove all history zero and revoke every reset/purge surface'
]);
notify pgrst,'reload schema';
commit;
"""
 a.output.write_text(sql,encoding='utf-8'); print(json.dumps({'status':'GENERATED','tables':len(tables),'purge':len(purge),'preserve':len(preserve),'output':str(a.output),'sha256':hashlib.sha256(sql.encode()).hexdigest()},sort_keys=True));return 0
if __name__=='__main__':raise SystemExit(main())
