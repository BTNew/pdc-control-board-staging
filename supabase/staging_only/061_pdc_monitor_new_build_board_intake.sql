-- Staging-only migration 061: directly approved new-build board intake by unique Stock.
-- Email location and VIN do not gate intake. Email never executes this function directly.
-- This file deliberately remains outside normal production migration discovery.

begin;

do $guard$
begin
  if not public.pdc_monitor_staging_guard() then
    raise exception 'PDC_STAGING_SENTINEL_MISMATCH';
  end if;
  if to_regclass('public.pdc_monitor_stage_activation_writers') is null then
    raise exception 'PDC_MONITOR_060_REQUIRED';
  end if;
end;
$guard$;

create table public.pdc_monitor_new_build_intake_approvals (
  approval_id uuid primary key default gen_random_uuid(),
  proposal_id text not null unique,
  source_hash text not null unique,
  evidence_hash text not null,
  request_hash text not null,
  monitor_user_id uuid not null references auth.users(id) on delete restrict,
  sender_address text not null,
  source_received_at timestamptz not null,
  stock_number text not null,
  backend_record_id uuid not null references public.navision_backend_records(id) on delete restrict,
  expected_revision bigint not null check (expected_revision >= 1),
  reason text not null check (length(btrim(reason)) >= 10),
  approved_by uuid not null references auth.users(id) on delete restrict,
  approved_at timestamptz not null default now(),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  response jsonb,
  check (sender_address = lower(sender_address)),
  check (sender_address ~ '^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@broometoyota[.]com[.]au$'),
  check (expires_at > approved_at and expires_at <= approved_at + interval '2 hours'),
  check ((consumed_at is null and response is null) or (consumed_at is not null and response is not null))
);

alter table public.pdc_monitor_new_build_intake_approvals enable row level security;
revoke all on table public.pdc_monitor_new_build_intake_approvals from public, anon, authenticated;

create or replace function public.admin_approve_pdc_monitor_new_build_intake(
  p_proposal_id text,
  p_source_hash text,
  p_evidence_hash text,
  p_monitor_user_id uuid,
  p_sender_address text,
  p_source_received_at timestamptz,
  p_stock_number text,
  p_backend_record_id uuid,
  p_expected_revision bigint,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $approve$
declare
  v_admin_id uuid := auth.uid();
  v_role text := public.current_pdc_user_role()::text;
  v_proposal text := upper(btrim(coalesce(p_proposal_id,'')));
  v_source_hash text := lower(btrim(coalesce(p_source_hash,'')));
  v_evidence_hash text := lower(btrim(coalesce(p_evidence_hash,'')));
  v_sender text := lower(btrim(coalesce(p_sender_address,'')));
  v_stock text;
  v_revision bigint;
  v_match_ids uuid[] := '{}'::uuid[];
  v_operational_ids uuid[] := '{}'::uuid[];
  v_request_hash text;
  v_existing public.pdc_monitor_new_build_intake_approvals%rowtype;
  v_existing_found boolean := false;
  v_id uuid;
  v_approved_at timestamptz;
  v_expires_at timestamptz;
begin
  if not public.pdc_monitor_staging_guard() then
    return public.navision_backend_response(false,'wrong_environment');
  end if;
  if v_admin_id is null or v_role is distinct from 'administrator' then
    return public.navision_backend_response(false,'unauthorized');
  end if;
  perform 1 from auth.users u join public.pdc_user_roles r on lower(r.email)=lower(u.email)
  where u.id=v_admin_id and r.active and r.role::text='administrator' for share of r;
  if not found then
    return public.navision_backend_response(false,'unauthorized');
  end if;
  if not exists (
    select 1 from public.pdc_monitor_stage_activation_writers w
    join auth.users u on u.id=w.user_id
    join public.pdc_user_roles r on lower(r.email)=lower(u.email)
    where w.user_id=p_monitor_user_id and w.active and w.revoked_at is null
      and r.active and r.role::text='viewer'
  ) then
    return public.navision_backend_response(false,'monitor_not_enrolled_viewer');
  end if;
  if v_proposal !~ '^PDC-[0-9]{8}-[A-F0-9]{10}$'
     or v_source_hash !~ '^[a-f0-9]{64}$'
     or v_evidence_hash !~ '^[a-f0-9]{64}$'
     or v_sender !~ '^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@broometoyota[.]com[.]au$'
     or p_backend_record_id is null or p_expected_revision is null or p_expected_revision < 1
     or length(btrim(coalesce(p_reason,''))) < 10 then
    return public.navision_backend_response(false,'invalid_input');
  end if;
  if p_source_received_at is null or p_source_received_at > clock_timestamp()+interval '5 minutes'
     or p_source_received_at < clock_timestamp()-interval '24 hours' then
    return public.navision_backend_response(false,'email_evidence_expired');
  end if;
  if not public.is_real_vehicle_stock_number(p_stock_number) then
    return public.navision_backend_response(false,'invalid_stock');
  end if;
  v_stock := public.normalize_vehicle_stock_number(p_stock_number);

  perform pg_advisory_xact_lock(hashtextextended('pdc-monitor-new-build:'||v_proposal,0));
  perform pg_advisory_xact_lock(hashtextextended('pdc-monitor-new-build-source:'||v_source_hash,0));

  select * into v_existing from public.pdc_monitor_new_build_intake_approvals
  where proposal_id=v_proposal or source_hash=v_source_hash
  order by case when proposal_id=v_proposal then 0 else 1 end limit 1 for update;
  v_existing_found := found;

  perform pg_advisory_xact_lock(hashtextextended('navision-backend-store',0));
  select revision into v_revision from public.navision_backend_revision where singleton for update;
  if v_revision <> p_expected_revision then
    return public.navision_backend_response(false,'stale_revision',jsonb_build_object('current_revision',v_revision));
  end if;

  select coalesce(array_agg(r.id order by r.id),'{}'::uuid[]) into v_match_ids
  from public.navision_backend_records r
  where r.source_system='microsoft_navision' and r.dealer_code in ('14450','37047')
    and r.is_current and r.record_status='current'
    and public.is_real_vehicle_stock_number(r.normalized_data->>'batch')
    and public.normalize_vehicle_stock_number(r.normalized_data->>'batch')=v_stock;
  if cardinality(v_match_ids)<>1 or v_match_ids[1]<>p_backend_record_id then
    return public.navision_backend_response(false,'stock_identity_conflict');
  end if;

  select coalesce(array_agg(distinct candidate_id order by candidate_id),'{}'::uuid[]) into v_operational_ids
  from (
    select v.id candidate_id from public.vehicles v where v.stock_number_normalized=v_stock
    union
    select a.vehicle_id from public.vehicle_aliases a
    where a.active and a.alias_type_normalized='stock_number' and a.normalized_alias_value=v_stock
  ) x;
  if cardinality(v_operational_ids)<>0 then
    return public.navision_backend_response(false,'operational_identity_present');
  end if;

  v_request_hash:=encode(extensions.digest(jsonb_build_object(
    'contract_version',1,'approval_kind','new_vehicle_build_board_intake',
    'proposal_id',v_proposal,'source_hash',v_source_hash,'evidence_hash',v_evidence_hash,
    'monitor_user_id',p_monitor_user_id,'sender_address',v_sender,
    'source_received_at',p_source_received_at,'stock_number',v_stock,
    'backend_record_id',p_backend_record_id,'expected_revision',p_expected_revision,
    'reason',btrim(p_reason)
  )::text,'sha256'),'hex');

  if v_existing_found then
    if v_existing.request_hash<>v_request_hash then
      return public.navision_backend_response(false,'approval_conflict');
    end if;
    return public.navision_backend_response(true,'approved',jsonb_build_object(
      'approval_id',v_existing.approval_id,'expires_at',v_existing.expires_at));
  end if;

  v_approved_at:=clock_timestamp();
  v_expires_at:=least(v_approved_at+interval '2 hours',p_source_received_at+interval '24 hours');
  if v_expires_at<=v_approved_at then
    return public.navision_backend_response(false,'email_evidence_expired');
  end if;
  insert into public.pdc_monitor_new_build_intake_approvals(
    proposal_id,source_hash,evidence_hash,request_hash,monitor_user_id,sender_address,
    source_received_at,stock_number,backend_record_id,expected_revision,reason,approved_by,approved_at,expires_at
  ) values(
    v_proposal,v_source_hash,v_evidence_hash,v_request_hash,p_monitor_user_id,v_sender,
    p_source_received_at,v_stock,p_backend_record_id,p_expected_revision,btrim(p_reason),v_admin_id,v_approved_at,
    v_expires_at
  ) returning approval_id into v_id;
  return public.navision_backend_response(true,'approved',jsonb_build_object(
    'approval_id',v_id,'expires_at',v_expires_at));
end;
$approve$;

create or replace function public.pdc_monitor_execute_approved_new_build_intake(p_approval_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $execute$
declare
  v_user_id uuid:=auth.uid();
  v_actor_email text;
  v_role text;
  v_approval public.pdc_monitor_new_build_intake_approvals%rowtype;
  v_revision bigint;
  v_result_revision bigint;
  v_match_ids uuid[]:='{}'::uuid[];
  v_operational_ids uuid[]:='{}'::uuid[];
  v_record public.navision_backend_records%rowtype;
  v_response jsonb;
begin
  if not public.pdc_monitor_staging_guard() then
    return public.navision_backend_response(false,'wrong_environment');
  end if;
  if v_user_id is null or p_approval_id is null then return public.navision_backend_response(false,'unauthorized'); end if;

  select lower(u.email) into v_actor_email from auth.users u where u.id=v_user_id;
  select r.role::text into v_role from public.pdc_user_roles r
  where lower(r.email)=v_actor_email and r.active for share;
  if v_role is distinct from 'viewer' then return public.navision_backend_response(false,'monitor_must_be_viewer'); end if;
  perform 1 from public.pdc_monitor_stage_activation_writers w
  where w.user_id=v_user_id and w.active and w.revoked_at is null for share;
  if not found then return public.navision_backend_response(false,'monitor_not_enrolled'); end if;

  select * into v_approval from public.pdc_monitor_new_build_intake_approvals
  where approval_id=p_approval_id for update;
  if not found or v_approval.monitor_user_id<>v_user_id then
    return public.navision_backend_response(false,'approval_not_found');
  end if;
  if v_approval.consumed_at is not null then return v_approval.response; end if;
  if v_approval.expires_at<=clock_timestamp() then
    return public.navision_backend_response(false,'approval_expired');
  end if;

  perform pg_advisory_xact_lock(hashtextextended('navision-backend-store',0));
  lock table public.vehicles, public.vehicle_aliases in share row exclusive mode;
  select revision into v_revision from public.navision_backend_revision where singleton for update;
  if v_revision<>v_approval.expected_revision then
    return public.navision_backend_response(false,'stale_revision',jsonb_build_object('current_revision',v_revision));
  end if;

  select coalesce(array_agg(r.id order by r.id),'{}'::uuid[]) into v_match_ids
  from public.navision_backend_records r
  where r.source_system='microsoft_navision' and r.dealer_code in ('14450','37047')
    and r.is_current and r.record_status='current'
    and public.is_real_vehicle_stock_number(r.normalized_data->>'batch')
    and public.normalize_vehicle_stock_number(r.normalized_data->>'batch')=v_approval.stock_number;
  if cardinality(v_match_ids)<>1 or v_match_ids[1]<>v_approval.backend_record_id then
    return public.navision_backend_response(false,'stock_identity_conflict');
  end if;

  select coalesce(array_agg(distinct candidate_id order by candidate_id),'{}'::uuid[]) into v_operational_ids
  from (
    select v.id candidate_id from public.vehicles v where v.stock_number_normalized=v_approval.stock_number
    union
    select a.vehicle_id from public.vehicle_aliases a
    where a.active and a.alias_type_normalized='stock_number' and a.normalized_alias_value=v_approval.stock_number
  ) x;
  if cardinality(v_operational_ids)<>0 then
    return public.navision_backend_response(false,'operational_identity_present');
  end if;

  select * into v_record from public.navision_backend_records
  where id=v_approval.backend_record_id for update;
  if not found or not v_record.is_current or v_record.record_status<>'current' then
    return public.navision_backend_response(false,'record_not_current');
  end if;

  if exists(select 1 from public.navision_board_activations where backend_record_id=v_approval.backend_record_id) then
    v_result_revision:=v_revision;
    v_response:=public.navision_backend_response(true,'already_activated',jsonb_build_object(
      'approval_id',v_approval.approval_id,'backend_record_id',v_approval.backend_record_id,
      'result_revision',v_result_revision,'activated',true,'activation_source','approved_new_build_email'));
  else
    insert into public.navision_board_activations(
      backend_record_id,activation_source,activated_stock_number,activated_by,activated_by_email
    ) values(
      v_approval.backend_record_id,'approved_email_build',v_record.normalized_data->>'batch',
      v_user_id,public.current_actor_email()
    );
    v_result_revision:=v_revision+1;
    update public.navision_backend_revision set revision=v_result_revision,updated_at=now() where singleton;
    insert into public.navision_backend_audit(action,backend_record_id,revision,evidence,actor_id,actor_email)
    values('board_activate',v_approval.backend_record_id,v_result_revision,jsonb_build_object(
      'activation_source','approved_new_build_email','approval_id',v_approval.approval_id,
      'proposal_id',v_approval.proposal_id,'source_hash',v_approval.source_hash,
      'evidence_hash',v_approval.evidence_hash,'sender_address',v_approval.sender_address,
      'source_received_at',v_approval.source_received_at,'stock_number',v_approval.stock_number,
      'approved_by',v_approval.approved_by,'approval_reason',v_approval.reason,
      'location_gate','not_applicable','automated',false),v_user_id,public.current_actor_email());
    v_response:=public.navision_backend_response(true,'board_activated',jsonb_build_object(
      'approval_id',v_approval.approval_id,'backend_record_id',v_approval.backend_record_id,
      'result_revision',v_result_revision,'activated',true,'activation_source','approved_new_build_email'));
  end if;

  update public.pdc_monitor_new_build_intake_approvals
  set consumed_at=clock_timestamp(),response=v_response where approval_id=v_approval.approval_id;
  return v_response;
end;
$execute$;

revoke all on function public.admin_approve_pdc_monitor_new_build_intake(text,text,text,uuid,text,timestamptz,text,uuid,bigint,text) from public,anon,authenticated;
revoke all on function public.pdc_monitor_execute_approved_new_build_intake(uuid) from public,anon,authenticated;
grant execute on function public.admin_approve_pdc_monitor_new_build_intake(text,text,text,uuid,text,timestamptz,text,uuid,bigint,text) to authenticated;
grant execute on function public.pdc_monitor_execute_approved_new_build_intake(uuid) to authenticated;

commit;
