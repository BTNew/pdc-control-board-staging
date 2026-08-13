-- Staging-only migration 060: administrator-approved PDC Monitor board activation.
-- This file deliberately lives outside normal production migration discovery.
-- The custom staging runner must create the pre-existing sentinel before this SQL runs.

begin;

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null then
    raise exception 'PDC_STAGING_SENTINEL_MISSING';
  end if;
  if not exists (
    select 1 from public.pdc_staging_environment_sentinel
    where singleton and project_ref = 'cdsmnqxtyyoeoznmbidd'
  ) then
    raise exception 'PDC_STAGING_SENTINEL_MISMATCH';
  end if;
end;
$guard$;

create table if not exists public.pdc_monitor_stage_activation_writers (
  user_id uuid primary key references auth.users(id) on delete cascade,
  active boolean not null default true,
  reason text not null check (length(btrim(reason)) >= 10),
  granted_by uuid not null references auth.users(id) on delete restrict,
  granted_at timestamptz not null default now(),
  revoked_at timestamptz
);

create table if not exists public.pdc_monitor_stage_activation_approvals (
  approval_id uuid primary key default gen_random_uuid(),
  proposal_id text not null unique,
  source_hash text not null unique,
  evidence_hash text not null,
  request_hash text not null,
  monitor_user_id uuid not null references auth.users(id) on delete restrict,
  sender_address text not null,
  source_received_at timestamptz not null,
  stock_number text not null,
  vin text not null,
  backend_record_id uuid not null references public.navision_backend_records(id) on delete restrict,
  expected_revision bigint not null check (expected_revision >= 1),
  reason text not null check (length(btrim(reason)) >= 10),
  approved_by uuid not null references auth.users(id) on delete restrict,
  approved_at timestamptz not null default now(),
  expires_at timestamptz not null,
  consumed_at timestamptz,
  response jsonb,
  check (sender_address = lower(sender_address)),
  check (sender_address ~ '^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?$'),
  check (expires_at > approved_at and expires_at <= approved_at + interval '2 hours'),
  check ((consumed_at is null and response is null) or (consumed_at is not null and response is not null))
);

alter table public.pdc_monitor_stage_activation_writers enable row level security;
alter table public.pdc_monitor_stage_activation_approvals enable row level security;
revoke all on table public.pdc_monitor_stage_activation_writers from public, anon, authenticated;
revoke all on table public.pdc_monitor_stage_activation_approvals from public, anon, authenticated;

create or replace function public.pdc_monitor_staging_guard()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $guard$
  select exists (
    select 1 from public.pdc_staging_environment_sentinel
    where singleton and project_ref = 'cdsmnqxtyyoeoznmbidd'
  );
$guard$;
revoke all on function public.pdc_monitor_staging_guard() from public, anon, authenticated;

create or replace function public.admin_set_pdc_monitor_stage_activation_writer(
  p_monitor_user_id uuid,
  p_active boolean,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $enroll$
declare
  v_admin_id uuid := auth.uid();
  v_role text := public.current_pdc_user_role()::text;
  v_monitor_role text;
begin
  if not public.pdc_monitor_staging_guard() then
    return public.navision_backend_response(false, 'wrong_environment');
  end if;
  if v_admin_id is null or v_role is distinct from 'administrator' then
    return public.navision_backend_response(false, 'unauthorized');
  end if;
  if p_monitor_user_id is null or length(btrim(coalesce(p_reason,''))) < 10 then
    return public.navision_backend_response(false, 'invalid_input');
  end if;
  select r.role::text into v_monitor_role
  from auth.users u join public.pdc_user_roles r on lower(r.email)=lower(u.email)
  where u.id=p_monitor_user_id and r.active;
  if v_monitor_role is distinct from 'viewer' then
    return public.navision_backend_response(false, 'monitor_must_be_viewer');
  end if;

  insert into public.pdc_monitor_vehicle_identity_readers(user_id,active,reason,granted_by,revoked_at)
  values(p_monitor_user_id,p_active,btrim(p_reason),v_admin_id,case when p_active then null else now() end)
  on conflict(user_id) do update set active=excluded.active, reason=excluded.reason,
    granted_by=excluded.granted_by, granted_at=now(), revoked_at=excluded.revoked_at;

  insert into public.pdc_monitor_stage_activation_writers(user_id,active,reason,granted_by,revoked_at)
  values(p_monitor_user_id,p_active,btrim(p_reason),v_admin_id,case when p_active then null else now() end)
  on conflict(user_id) do update set active=excluded.active, reason=excluded.reason,
    granted_by=excluded.granted_by, granted_at=now(), revoked_at=excluded.revoked_at;

  return public.navision_backend_response(true, case when p_active then 'enrolled' else 'revoked' end,
    jsonb_build_object('monitor_user_id',p_monitor_user_id,'active',p_active));
end;
$enroll$;

create or replace function public.admin_approve_pdc_monitor_stage_activation(
  p_proposal_id text,
  p_source_hash text,
  p_evidence_hash text,
  p_monitor_user_id uuid,
  p_sender_address text,
  p_source_received_at timestamptz,
  p_stock_number text,
  p_vin text,
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
  v_vin text;
  v_request_hash text;
  v_existing public.pdc_monitor_stage_activation_approvals%rowtype;
  v_approval_id uuid;
  v_expires_at timestamptz;
begin
  if not public.pdc_monitor_staging_guard() then
    return public.navision_backend_response(false, 'wrong_environment');
  end if;
  if v_admin_id is null or v_role is distinct from 'administrator' then
    return public.navision_backend_response(false, 'unauthorized');
  end if;
  if not exists (select 1 from public.pdc_monitor_stage_activation_writers w
                 where w.user_id=p_monitor_user_id and w.active and w.revoked_at is null) then
    return public.navision_backend_response(false, 'monitor_not_enrolled');
  end if;
  if v_proposal !~ '^PDC-[0-9]{8}-[A-F0-9]{10}$'
     or v_source_hash !~ '^[a-f0-9]{64}$'
     or v_evidence_hash !~ '^[a-f0-9]{64}$'
     or v_sender !~ '^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?$'
     or p_backend_record_id is null or p_expected_revision is null or p_expected_revision < 1
     or length(btrim(coalesce(p_reason,''))) < 10 then
    return public.navision_backend_response(false, 'invalid_input');
  end if;
  if p_source_received_at is null or p_source_received_at > clock_timestamp()+interval '5 minutes'
     or p_source_received_at < clock_timestamp()-interval '24 hours' then
    return public.navision_backend_response(false, 'email_evidence_expired');
  end if;
  if not public.is_real_vehicle_stock_number(p_stock_number) or not public.is_valid_vehicle_vin(p_vin) then
    return public.navision_backend_response(false, 'invalid_input');
  end if;
  v_stock := public.normalize_vehicle_stock_number(p_stock_number);
  v_vin := public.normalize_vehicle_vin(p_vin);
  v_request_hash := encode(extensions.digest(jsonb_build_object(
    'contract_version',2,'proposal_id',v_proposal,'source_hash',v_source_hash,
    'evidence_hash',v_evidence_hash,'monitor_user_id',p_monitor_user_id,
    'sender_address',v_sender,'source_received_at',p_source_received_at,
    'stock_number',v_stock,'vin',v_vin,'backend_record_id',p_backend_record_id,
    'expected_revision',p_expected_revision,'reason',btrim(p_reason),'approved_by',v_admin_id
  )::text,'sha256'),'hex');

  perform pg_advisory_xact_lock(hashtextextended('pdc-monitor-approval:'||v_proposal,0));
  select * into v_existing from public.pdc_monitor_stage_activation_approvals where proposal_id=v_proposal;
  if found then
    if v_existing.request_hash <> v_request_hash then
      return public.navision_backend_response(false,'approval_conflict');
    end if;
    return public.navision_backend_response(true,'approved',jsonb_build_object(
      'approval_id',v_existing.approval_id,'proposal_id',v_existing.proposal_id,
      'expires_at',v_existing.expires_at));
  end if;
  if exists(select 1 from public.pdc_monitor_stage_activation_approvals where source_hash=v_source_hash) then
    return public.navision_backend_response(false,'source_already_approved');
  end if;

  v_approval_id := gen_random_uuid();
  v_expires_at := clock_timestamp()+interval '30 minutes';
  insert into public.pdc_monitor_stage_activation_approvals(
    approval_id,proposal_id,source_hash,evidence_hash,request_hash,monitor_user_id,
    sender_address,source_received_at,stock_number,vin,backend_record_id,
    expected_revision,reason,approved_by,expires_at
  ) values(
    v_approval_id,v_proposal,v_source_hash,v_evidence_hash,v_request_hash,p_monitor_user_id,
    v_sender,p_source_received_at,v_stock,v_vin,p_backend_record_id,
    p_expected_revision,btrim(p_reason),v_admin_id,v_expires_at
  );
  return public.navision_backend_response(true,'approved',jsonb_build_object(
    'approval_id',v_approval_id,'proposal_id',v_proposal,
    'expires_at',v_expires_at));
exception when unique_violation then
  return public.navision_backend_response(false,'approval_conflict');
end;
$approve$;

create or replace function public.pdc_monitor_execute_approved_stage_activation(p_approval_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $execute$
declare
  v_user_id uuid := auth.uid();
  v_role text;
  v_actor_email text;
  v_approval public.pdc_monitor_stage_activation_approvals%rowtype;
  v_record public.navision_backend_records%rowtype;
  v_stock_ids uuid[] := '{}'::uuid[];
  v_vin_ids uuid[] := '{}'::uuid[];
  v_operational_stock_ids uuid[] := '{}'::uuid[];
  v_operational_vin_ids uuid[] := '{}'::uuid[];
  v_revision bigint;
  v_result_revision bigint;
  v_response jsonb;
begin
  if not public.pdc_monitor_staging_guard() then
    return public.navision_backend_response(false,'wrong_environment');
  end if;
  if v_user_id is null then
    return public.navision_backend_response(false,'unauthorized');
  end if;
  if p_approval_id is null then
    return public.navision_backend_response(false,'invalid_input');
  end if;

  select * into v_approval from public.pdc_monitor_stage_activation_approvals
  where approval_id=p_approval_id and monitor_user_id=v_user_id for update;
  if not found then return public.navision_backend_response(false,'approval_not_found'); end if;
  if v_approval.consumed_at is not null then return v_approval.response; end if;
  if v_approval.expires_at < clock_timestamp() then
    return public.navision_backend_response(false,'approval_expired');
  end if;

  select lower(u.email) into v_actor_email from auth.users u where u.id=v_user_id;
  select r.role::text into v_role from public.pdc_user_roles r
  where lower(r.email)=v_actor_email and r.active for share;
  if v_role is distinct from 'viewer' then
    return public.navision_backend_response(false,'unauthorized');
  end if;
  perform 1 from public.pdc_monitor_stage_activation_writers w
  where w.user_id=v_user_id and w.active and w.revoked_at is null for share;
  if not found then return public.navision_backend_response(false,'unauthorized'); end if;

  perform pg_advisory_xact_lock(hashtextextended('navision-backend-store',0));
  lock table public.vehicles, public.vehicle_aliases in share row exclusive mode;
  select revision into v_revision from public.navision_backend_revision where singleton for update;
  if v_revision is distinct from v_approval.expected_revision then
    return public.navision_backend_response(false,'stale_revision',jsonb_build_object('current_revision',v_revision));
  end if;

  select coalesce(array_agg(r.id order by r.id),'{}'::uuid[]) into v_stock_ids
  from public.navision_backend_records r
  where r.source_system='microsoft_navision' and r.dealer_code in ('14450','37047')
    and r.is_current and r.record_status='current'
    and public.is_real_vehicle_stock_number(r.normalized_data->>'batch')
    and public.normalize_vehicle_stock_number(r.normalized_data->>'batch')=v_approval.stock_number;
  select coalesce(array_agg(r.id order by r.id),'{}'::uuid[]) into v_vin_ids
  from public.navision_backend_records r
  where r.source_system='microsoft_navision' and r.dealer_code in ('14450','37047')
    and r.is_current and r.record_status='current'
    and public.is_valid_vehicle_vin(r.normalized_data->>'vin')
    and public.normalize_vehicle_vin(r.normalized_data->>'vin')=v_approval.vin;
  if cardinality(v_stock_ids)<>1 or cardinality(v_vin_ids)<>1
     or v_stock_ids[1]<>v_vin_ids[1] or v_stock_ids[1]<>v_approval.backend_record_id then
    return public.navision_backend_response(false,'identity_conflict');
  end if;

  select coalesce(array_agg(distinct candidate_id order by candidate_id),'{}'::uuid[]) into v_operational_stock_ids
  from (
    select v.id candidate_id from public.vehicles v where v.stock_number_normalized=v_approval.stock_number
    union select a.vehicle_id from public.vehicle_aliases a
      where a.active and a.alias_type_normalized='stock_number' and a.normalized_alias_value=v_approval.stock_number
  ) x;
  select coalesce(array_agg(distinct candidate_id order by candidate_id),'{}'::uuid[]) into v_operational_vin_ids
  from (
    select v.id candidate_id from public.vehicles v where v.vin_normalized=v_approval.vin
    union select a.vehicle_id from public.vehicle_aliases a
      where a.active and a.alias_type_normalized='vin' and a.normalized_alias_value=v_approval.vin
  ) x;
  if cardinality(v_operational_stock_ids)<>0 or cardinality(v_operational_vin_ids)<>0 then
    return public.navision_backend_response(false,'operational_identity_present');
  end if;

  select * into v_record from public.navision_backend_records
  where id=v_approval.backend_record_id for update;
  if not found or not v_record.is_current or v_record.record_status<>'current' then
    return public.navision_backend_response(false,'record_not_current');
  end if;

  if exists(select 1 from public.navision_board_activations
            where backend_record_id=v_approval.backend_record_id) then
    v_result_revision:=v_revision;
    v_response:=public.navision_backend_response(true,'already_activated',jsonb_build_object(
      'approval_id',v_approval.approval_id,'backend_record_id',v_approval.backend_record_id,
      'result_revision',v_result_revision,'activated',true,'activation_source','approved_monitor_proposal'));
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
      'activation_source','approved_monitor_proposal','approval_id',v_approval.approval_id,
      'proposal_id',v_approval.proposal_id,'source_hash',v_approval.source_hash,
      'evidence_hash',v_approval.evidence_hash,'sender_address',v_approval.sender_address,
      'source_received_at',v_approval.source_received_at,'stock_number',v_approval.stock_number,
      'vin',v_approval.vin,'approved_by',v_approval.approved_by,'approval_reason',v_approval.reason,
      'automated',false),v_user_id,public.current_actor_email());
    v_response:=public.navision_backend_response(true,'board_activated',jsonb_build_object(
      'approval_id',v_approval.approval_id,'backend_record_id',v_approval.backend_record_id,
      'result_revision',v_result_revision,'activated',true,'activation_source','approved_monitor_proposal'));
  end if;

  update public.pdc_monitor_stage_activation_approvals
  set consumed_at=clock_timestamp(),response=v_response where approval_id=v_approval.approval_id;
  return v_response;
end;
$execute$;

revoke all on function public.admin_set_pdc_monitor_stage_activation_writer(uuid,boolean,text) from public,anon,authenticated;
revoke all on function public.admin_approve_pdc_monitor_stage_activation(text,text,text,uuid,text,timestamptz,text,text,uuid,bigint,text) from public,anon,authenticated;
revoke all on function public.pdc_monitor_execute_approved_stage_activation(uuid) from public,anon,authenticated;
grant execute on function public.admin_set_pdc_monitor_stage_activation_writer(uuid,boolean,text) to authenticated;
grant execute on function public.admin_approve_pdc_monitor_stage_activation(text,text,text,uuid,text,timestamptz,text,text,uuid,bigint,text) to authenticated;
grant execute on function public.pdc_monitor_execute_approved_stage_activation(uuid) to authenticated;

commit;
