-- Staging-only migration 735: append-only Monitor storage reconciliation and
-- exact-ID Administrator requeue custody. Production is intentionally absent.
begin;
set local lock_timeout='5s';
set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-email-monitor-735',0));
lock table supabase_migrations.schema_migrations in exclusive mode;

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists (select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or (select max(version) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$')<>'20260829000000'
     or not exists (select 1 from supabase_migrations.schema_migrations where version='20260829000000' and name='734_durable_rft_transport_lifecycle')
     or exists (select 1 from supabase_migrations.schema_migrations where version='20260829010000')
     or to_regclass('public.ai_email_intake') is null
     or to_regclass('public.ai_email_attachments') is null
     or to_regprocedure('public.pdc_monitor_actor_scope()') is null
     or to_regprocedure('public.require_pdc_role(public.pdc_role)') is null
  then
    raise exception 'PDC_735_EXACT_STAGING_734_PRESTATE_REQUIRED' using errcode='55000';
  end if;
  if not exists (select 1 from public.ai_email_intake where id='d89a3bbd-590b-493b-84a8-ce557bbfe512'::uuid and provider_uid='imap_uid:680' and source_hash='d6756c523ffb7336556492fe0ef25c202d744ffd2645846b19cbbcdffed60493')
     or not exists (select 1 from public.ai_email_intake where id='6836f01c-080f-4289-90a4-df8667a49ac9'::uuid and provider_uid='imap_uid:681' and source_hash='f205342f4ff4361b88bf21b83a11e92957a796792bcc0bfa4150d0abaa5b4916')
  then
    raise exception 'PDC_735_EXACT_FAILED_INTAKE_PRESTATE_REQUIRED' using errcode='55000';
  end if;
end
$guard$;

create table public.pdc_email_monitor_requeue_targets_735(
  intake_id uuid primary key references public.ai_email_intake(id) on delete restrict,
  provider_uid text not null unique,
  source_hash text not null unique check(source_hash~'^[a-f0-9]{64}$'),
  target_kind text not null check(target_kind='staging_remediation_exact_failed_intake'),
  created_at timestamptz not null default clock_timestamp(),
  check((intake_id='d89a3bbd-590b-493b-84a8-ce557bbfe512'::uuid and provider_uid='imap_uid:680' and source_hash='d6756c523ffb7336556492fe0ef25c202d744ffd2645846b19cbbcdffed60493')
     or (intake_id='6836f01c-080f-4289-90a4-df8667a49ac9'::uuid and provider_uid='imap_uid:681' and source_hash='f205342f4ff4361b88bf21b83a11e92957a796792bcc0bfa4150d0abaa5b4916'))
);
insert into public.pdc_email_monitor_requeue_targets_735(intake_id,provider_uid,source_hash,target_kind)
values
 ('d89a3bbd-590b-493b-84a8-ce557bbfe512','imap_uid:680','d6756c523ffb7336556492fe0ef25c202d744ffd2645846b19cbbcdffed60493','staging_remediation_exact_failed_intake'),
 ('6836f01c-080f-4289-90a4-df8667a49ac9','imap_uid:681','f205342f4ff4361b88bf21b83a11e92957a796792bcc0bfa4150d0abaa5b4916','staging_remediation_exact_failed_intake');

create table public.pdc_email_monitor_storage_reconciliations_735(
  reconciliation_id uuid primary key default gen_random_uuid(),
  intake_id uuid not null references public.ai_email_intake(id) on delete restrict,
  attachment_id uuid not null unique references public.ai_email_attachments(id) on delete restrict,
  original_storage_path text,
  canonical_storage_path text,
  source_hash text not null check(source_hash~'^[a-f0-9]{64}$'),
  file_name text not null check(length(file_name) between 1 and 180),
  outcome text not null check(outcome in('canonical_verified','permanent_fail_closed')),
  evidence_hash text not null check(evidence_hash~'^[a-f0-9]{64}$'),
  actor_id uuid not null references auth.users(id) on delete restrict,
  actor_email text not null check(length(actor_email) between 3 and 320),
  created_at timestamptz not null default clock_timestamp(),
  check(outcome='permanent_fail_closed' or canonical_storage_path is not null),
  check(canonical_storage_path is null or canonical_storage_path~('^pdc-email-intake-private/'||source_hash||'/[A-Za-z0-9._-]{1,120}$'))
);

create table public.pdc_email_monitor_requeue_receipts_735(
  receipt_id uuid primary key default gen_random_uuid(),
  intake_id uuid not null unique references public.ai_email_intake(id) on delete restrict,
  target_kind text not null check(target_kind='staging_remediation_exact_failed_intake'),
  request_key text not null unique check(request_key~'^pdc-email-monitor-735:[0-9a-f-]{36}$'),
  before_status text not null,
  before_permanent_failure boolean not null,
  after_status text not null check(after_status='received'),
  actor_id uuid not null references auth.users(id) on delete restrict,
  actor_email text not null check(length(actor_email) between 3 and 320),
  reason text not null check(length(reason) between 1 and 500),
  created_at timestamptz not null default clock_timestamp()
);

create or replace function public.pdc_email_monitor_735_immutable()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $body$
begin
  raise exception 'PDC_735_APPEND_ONLY_EVIDENCE_IMMUTABLE' using errcode='55000';
end
$body$;
create trigger pdc_email_monitor_storage_reconciliations_735_immutable
before update or delete on public.pdc_email_monitor_storage_reconciliations_735
for each row execute function public.pdc_email_monitor_735_immutable();
create trigger pdc_email_monitor_requeue_receipts_735_immutable
before update or delete on public.pdc_email_monitor_requeue_receipts_735
for each row execute function public.pdc_email_monitor_735_immutable();

alter table public.pdc_email_monitor_requeue_targets_735 enable row level security;
alter table public.pdc_email_monitor_requeue_targets_735 force row level security;
alter table public.pdc_email_monitor_storage_reconciliations_735 enable row level security;
alter table public.pdc_email_monitor_storage_reconciliations_735 force row level security;
alter table public.pdc_email_monitor_requeue_receipts_735 enable row level security;
alter table public.pdc_email_monitor_requeue_receipts_735 force row level security;
revoke all on table public.pdc_email_monitor_requeue_targets_735,public.pdc_email_monitor_storage_reconciliations_735,public.pdc_email_monitor_requeue_receipts_735 from public,anon,authenticated,service_role;

create function public.admin_reconcile_pdc_email_attachment_storage_735(
  p_intake_id uuid,
  p_attachment_id uuid,
  p_original_storage_path text,
  p_canonical_storage_path text,
  p_outcome text,
  p_evidence_hash text
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,auth as $body$
declare
  v_actor uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_target public.pdc_email_monitor_requeue_targets_735%rowtype;
  v_attachment public.ai_email_attachments%rowtype;
  v_existing public.pdc_email_monitor_storage_reconciliations_735%rowtype;
  v_safe_name text;
  v_expected_path text;
begin
  perform public.require_pdc_role('administrator');
  if v_actor is null or v_email='' or coalesce(auth.jwt()->>'role','')<>'authenticated'
     or p_outcome not in('canonical_verified','permanent_fail_closed')
     or lower(btrim(coalesce(p_evidence_hash,'')))!~'^[a-f0-9]{64}$'
  then raise exception 'PDC_735_ADMIN_RECONCILE_INPUT_INVALID' using errcode='22023'; end if;
  select * into v_target from public.pdc_email_monitor_requeue_targets_735 where intake_id=p_intake_id;
  if not found then raise exception 'PDC_735_EXACT_RECONCILE_TARGET_REQUIRED' using errcode='42501'; end if;
  select * into v_attachment from public.ai_email_attachments where id=p_attachment_id and intake_id=p_intake_id for share;
  if not found or v_attachment.source_hash is null or v_attachment.source_hash!~'^[a-f0-9]{64}$'
     or p_original_storage_path is distinct from v_attachment.storage_path
  then raise exception 'PDC_735_ATTACHMENT_EVIDENCE_BINDING_MISMATCH' using errcode='42501'; end if;
  v_safe_name:=left(nullif(regexp_replace(v_attachment.file_name,'[^A-Za-z0-9._-]+','_','g'),''),120);
  v_safe_name:=coalesce(v_safe_name,'attachment');
  v_expected_path:='pdc-email-intake-private/'||lower(v_attachment.source_hash)||'/'||v_safe_name;
  if p_outcome='canonical_verified' and (p_canonical_storage_path is distinct from v_expected_path
     or p_canonical_storage_path~'[\\%:]' or p_canonical_storage_path~'(^|/)\.\.(/|$)')
  then raise exception 'PDC_735_CANONICAL_PATH_BINDING_INVALID' using errcode='22023'; end if;
  if p_outcome='permanent_fail_closed' and p_canonical_storage_path is not null
  then raise exception 'PDC_735_PERMANENT_OUTCOME_MUST_NOT_BIND_PATH' using errcode='22023'; end if;
  select * into v_existing from public.pdc_email_monitor_storage_reconciliations_735 where attachment_id=p_attachment_id;
  if found then
    if v_existing.intake_id<>p_intake_id or v_existing.original_storage_path is distinct from p_original_storage_path
       or v_existing.canonical_storage_path is distinct from p_canonical_storage_path or v_existing.outcome<>p_outcome
       or v_existing.evidence_hash<>lower(p_evidence_hash)
    then raise exception 'PDC_735_RECONCILE_REPLAY_CONFLICT' using errcode='23505'; end if;
    return jsonb_build_object('ok',true,'code','storage_reconciliation_replayed','reconciliation_id',v_existing.reconciliation_id,'outcome',v_existing.outcome);
  end if;
  insert into public.pdc_email_monitor_storage_reconciliations_735(
    intake_id,attachment_id,original_storage_path,canonical_storage_path,source_hash,file_name,outcome,evidence_hash,actor_id,actor_email)
  values(p_intake_id,p_attachment_id,p_original_storage_path,p_canonical_storage_path,lower(v_attachment.source_hash),v_attachment.file_name,p_outcome,lower(p_evidence_hash),v_actor,v_email)
  returning * into v_existing;
  insert into public.audit_events(action,table_name,row_id,actor_id,actor_email,after_data,metadata)
  values('reconcile','pdc_email_monitor_storage_reconciliations_735',v_existing.reconciliation_id,v_actor,v_email,
    jsonb_build_object('intake_id',p_intake_id,'attachment_id',p_attachment_id,'outcome',p_outcome,'evidence_hash',lower(p_evidence_hash)),
    jsonb_build_object('contract','pdc_email_monitor_storage_reconcile_735','original_storage_path_retained',true,'append_only',true));
  return jsonb_build_object('ok',true,'code','storage_reconciled','reconciliation_id',v_existing.reconciliation_id,'outcome',p_outcome);
end
$body$;

create function public.admin_requeue_pdc_email_intake_735(
  p_intake_id uuid,
  p_request_key text,
  p_reason text
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,auth as $body$
declare
  v_actor uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_target public.pdc_email_monitor_requeue_targets_735%rowtype;
  v_row public.ai_email_intake%rowtype;
  v_existing public.pdc_email_monitor_requeue_receipts_735%rowtype;
  v_receipt public.pdc_email_monitor_requeue_receipts_735%rowtype;
begin
  perform public.require_pdc_role('administrator');
  if v_actor is null or v_email='' or coalesce(auth.jwt()->>'role','')<>'authenticated'
     or p_request_key!~'^pdc-email-monitor-735:[0-9a-f-]{36}$'
     or length(btrim(coalesce(p_reason,''))) not between 1 and 500
  then raise exception 'PDC_735_ADMIN_REQUEUE_INPUT_INVALID' using errcode='22023'; end if;
  select * into v_target from public.pdc_email_monitor_requeue_targets_735 where intake_id=p_intake_id;
  if not found then raise exception 'PDC_735_EXACT_REQUEUE_TARGET_REQUIRED' using errcode='42501'; end if;
  select * into v_existing from public.pdc_email_monitor_requeue_receipts_735 where request_key=p_request_key;
  if found then
    if v_existing.intake_id<>p_intake_id or v_existing.actor_id<>v_actor then raise exception 'PDC_735_REQUEUE_REPLAY_CONFLICT' using errcode='23505'; end if;
    return jsonb_build_object('ok',true,'code','email_requeue_replayed','receipt_id',v_existing.receipt_id,'intake_id',p_intake_id,'status',v_existing.after_status);
  end if;
  select * into v_row from public.ai_email_intake where id=p_intake_id for update;
  if not found or v_row.status<>'failed' or v_row.permanent_failure is not true
  then raise exception 'PDC_735_FAILED_PERMANENT_TARGET_REQUIRED' using errcode='55000'; end if;
  update public.ai_email_intake
  set status='received',permanent_failure=false,retry_class=null,next_attempt_at=clock_timestamp(),
      locked_at=null,locked_by=null,claim_token=null,gateway_instance_id=null,error_details=null,last_error_code=null
  where id=p_intake_id;
  insert into public.pdc_email_monitor_requeue_receipts_735(
    intake_id,target_kind,request_key,before_status,before_permanent_failure,after_status,actor_id,actor_email,reason)
  values(p_intake_id,v_target.target_kind,p_request_key,v_row.status,v_row.permanent_failure,'received',v_actor,v_email,btrim(p_reason))
  returning * into v_receipt;
  update public.pdc_email_monitor_status set updated_at=clock_timestamp() where singleton;
  insert into public.audit_events(action,table_name,row_id,actor_id,actor_email,before_data,after_data,metadata)
  values('update','ai_email_intake',v_receipt.intake_id,v_actor,v_email,
    jsonb_build_object('id',p_intake_id,'status',v_row.status,'permanent_failure',v_row.permanent_failure),
    jsonb_build_object('id',p_intake_id,'status','received','permanent_failure',false),
    jsonb_build_object('contract','pdc_email_monitor_admin_requeue_735','receipt_id',v_receipt.receipt_id,'exact_target',true,'direct_dml',false));
  return jsonb_build_object('ok',true,'code','email_requeued','receipt_id',v_receipt.receipt_id,'intake_id',p_intake_id,'status','received');
end
$body$;

create function public.get_pdc_monitor_intake_attachments_735(
  p_intake_id uuid,
  p_claim_token uuid,
  p_gateway_instance_id text
) returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,auth as $body$
declare
  v_rows jsonb;
begin
  if not public.pdc_email_monitor_runtime_authorized_502(p_gateway_instance_id)
     or not public.pdc_monitor_authenticated_active_scope_674(p_gateway_instance_id)
     or not exists(select 1 from public.ai_email_intake i where i.id=p_intake_id and i.locked_by=auth.uid()
       and i.status='processing' and i.claim_token=p_claim_token and i.gateway_instance_id=btrim(p_gateway_instance_id)
       and i.locked_at>=clock_timestamp()-interval '10 minutes')
  then raise exception 'PDC_735_MONITOR_ATTACHMENT_CLAIM_MISSING' using errcode='42501'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',a.id,'file_name',a.file_name,'source_hash',a.source_hash,
    'storage_path',case when r.outcome='permanent_fail_closed' then null
                         when r.outcome='canonical_verified' then r.canonical_storage_path
                         else a.storage_path end,
    'storage_reconciliation',coalesce(r.outcome,'unreconciled')) order by a.created_at,a.id),'[]'::jsonb)
    into v_rows
  from public.ai_email_attachments a
  left join public.pdc_email_monitor_storage_reconciliations_735 r on r.attachment_id=a.id
  where a.intake_id=p_intake_id;
  return jsonb_build_object('ok',true,'attachments',v_rows,'contract','pdc_email_monitor_attachments_735');
end
$body$;

revoke all on function public.pdc_email_monitor_735_immutable() from public,anon,authenticated,service_role;
revoke all on function public.admin_reconcile_pdc_email_attachment_storage_735(uuid,uuid,text,text,text,text) from public,anon,authenticated,service_role;
revoke all on function public.admin_requeue_pdc_email_intake_735(uuid,text,text) from public,anon,authenticated,service_role;
revoke all on function public.get_pdc_monitor_intake_attachments_735(uuid,uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.admin_reconcile_pdc_email_attachment_storage_735(uuid,uuid,text,text,text,text) to authenticated;
grant execute on function public.admin_requeue_pdc_email_intake_735(uuid,text,text) to authenticated;
grant execute on function public.get_pdc_monitor_intake_attachments_735(uuid,uuid,text) to authenticated;

do $verify$
begin
  if has_function_privilege('anon','public.admin_reconcile_pdc_email_attachment_storage_735(uuid,uuid,text,text,text,text)','execute')
     or has_function_privilege('service_role','public.admin_reconcile_pdc_email_attachment_storage_735(uuid,uuid,text,text,text,text)','execute')
     or has_function_privilege('anon','public.admin_requeue_pdc_email_intake_735(uuid,text,text)','execute')
     or has_function_privilege('service_role','public.admin_requeue_pdc_email_intake_735(uuid,text,text)','execute')
     or has_function_privilege('anon','public.get_pdc_monitor_intake_attachments_735(uuid,uuid,text)','execute')
     or has_function_privilege('service_role','public.get_pdc_monitor_intake_attachments_735(uuid,uuid,text)','execute')
     or not has_function_privilege('authenticated','public.admin_reconcile_pdc_email_attachment_storage_735(uuid,uuid,text,text,text,text)','execute')
     or not has_function_privilege('authenticated','public.admin_requeue_pdc_email_intake_735(uuid,text,text)','execute')
     or not has_function_privilege('authenticated','public.get_pdc_monitor_intake_attachments_735(uuid,uuid,text)','execute')
     or has_table_privilege('authenticated','public.pdc_email_monitor_storage_reconciliations_735','select')
     or has_table_privilege('authenticated','public.pdc_email_monitor_requeue_receipts_735','select')
  then raise exception 'PDC_735_SECURITY_POSTSTATE_FAILED' using errcode='55000'; end if;
end
$verify$;

insert into supabase_migrations.schema_migrations(version,name,statements) values(
 '20260829010000','735_email_monitor_storage_reconcile_requeue_successor',array[
  'Exact staging 734 predecessor and exactly two failed intake targets are bound before installation',
  'Strict canonical pdc-email-intake-private hash and filename binding is returned only through a claim-bound Monitor successor RPC',
  'Historical storage paths remain immutable and are reconciled through append-only receipt-bound evidence',
  'Only an authenticated Administrator can invoke the exact-ID audited requeue function; Monitor remains non-administrator and direct DML is denied',
  'UID514, prior receipts, mailbox read-only state, outbound-disabled state, RLS and production exclusion are preserved'
 ]
);
notify pgrst,'reload schema';
commit;
