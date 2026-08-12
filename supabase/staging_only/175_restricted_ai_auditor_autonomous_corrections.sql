-- Staging-only migration 175: restricted autonomous AI Auditor station/hour overlays.
-- Dedicated Viewer executor identities can only create source-bound Workshop overlays.
-- Vehicles, source operation lines, work requirements, bookings, Parts and completion remain immutable.
begin;

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists (
       select 1 from public.pdc_staging_environment_sentinel
       where singleton and project_ref = 'cdsmnqxtyyoeoznmbidd'
     ) then
    raise exception 'PDC_AUDITOR_175_STAGING_SENTINEL_MISMATCH';
  end if;
  if to_regclass('supabase_migrations.schema_migrations') is null
     or not exists (
       select 1 from supabase_migrations.schema_migrations
       where version='174' and name='restore_provider_attestation_boundary_and_key_snapshot'
     ) then
    raise exception 'PDC_AUDITOR_175_PREDECESSOR_174_IDENTITY_MISMATCH';
  end if;
  if exists (
       select 1 from supabase_migrations.schema_migrations
       where version='175' and name<>'restricted_ai_auditor_autonomous_corrections'
     ) then
    raise exception 'PDC_AUDITOR_175_VERSION_CONFLICT';
  end if;
  if to_regclass('public.pdc_auditor_worker_identities') is null
     or to_regclass('public.pdc_auditor_user_dealer_scopes') is null
     or to_regclass('public.pdc_auditor_runs') is null
     or to_regclass('public.pdc_authenticated_email_operation_lines') is null
     or to_regclass('public.vehicle_workshop_line_adjustments') is null
     or to_regclass('public.audit_events') is null
     or to_regprocedure('public.pdc_auditor_operational_revision(text)') is null
     or to_regprocedure('public.pdc_auditor_vehicle_dealer(uuid)') is null
     or to_regprocedure('public.pdc_auditor_reject_history_mutation()') is null then
    raise exception 'PDC_AUDITOR_175_DEPENDENCY_MISSING';
  end if;
end;
$guard$;

-- Station-only overlays are valid even while hours remain unknown. Existing operator RPCs
-- retain their positive quarter-hour validation; only the restricted executor may insert null.
alter table public.vehicle_workshop_line_adjustments
  alter column estimated_hours drop not null;
alter table public.vehicle_workshop_line_adjustments
  drop constraint if exists vehicle_workshop_line_adjustments_estimated_hours_check;
alter table public.vehicle_workshop_line_adjustments
  add constraint vehicle_workshop_line_adjustments_estimated_hours_check
  check (estimated_hours is null or (
    estimated_hours between 0.25 and 999.75 and mod(estimated_hours,0.25)=0
  ));

create table if not exists public.pdc_auditor_executor_identities (
  executor_identity_id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null,
  normalized_email text not null check (
    normalized_email=lower(btrim(normalized_email))
    and normalized_email ~ '^[^[:space:]@]+@[^[:space:]@]+$'
  ),
  dealer_code text not null check (dealer_code in ('14450','37047')),
  environment text not null check (environment='staging'),
  active boolean not null default true,
  expires_at timestamptz not null,
  max_corrections_per_run integer not null default 25 check (max_corrections_per_run between 1 and 50),
  enabled_by_user_id uuid not null,
  enabled_at timestamptz not null default clock_timestamp(),
  disabled_at timestamptz,
  check ((active and disabled_at is null) or (not active and disabled_at is not null)),
  check (expires_at>enabled_at),
  check (active)
);
create index if not exists pdc_auditor_executor_identity_lookup_idx
  on public.pdc_auditor_executor_identities(auth_user_id,normalized_email,environment,expires_at);

-- Hour changes are allowed only from an Administrator-recorded exact normalized description.
-- There is no fuzzy, model-authored or regex hour rule.
create table if not exists public.pdc_auditor_autonomous_hour_rules (
  hour_rule_id uuid primary key default gen_random_uuid(),
  dealer_code text not null check (dealer_code in ('14450','37047')),
  environment text not null check (environment='staging'),
  description_pattern text not null default 'exact_normalized_description'
    check (description_pattern='exact_normalized_description'),
  normalized_description text not null check (
    normalized_description=btrim(normalized_description)
    and length(normalized_description) between 3 and 180
    and normalized_description !~ '[[:cntrl:]]'
  ),
  target_estimated_hours numeric(6,2) not null check (
    target_estimated_hours between 0.25 and 999.75
    and mod(target_estimated_hours,0.25)=0
  ),
  active boolean not null default true,
  effective_from timestamptz not null default clock_timestamp(),
  effective_to timestamptz,
  created_by_user_id uuid not null,
  created_at timestamptz not null default clock_timestamp(),
  check (effective_to is null or effective_to>effective_from),
  unique(dealer_code,environment,normalized_description,effective_from)
);
create index if not exists pdc_auditor_hour_rules_current_lookup_idx
  on public.pdc_auditor_autonomous_hour_rules(dealer_code,environment,normalized_description,effective_from)
  where active;

create table if not exists public.pdc_auditor_restricted_authority_revocations (
  revocation_id uuid primary key default gen_random_uuid(),
  target_type text not null check (target_type in ('executor_identity','hour_rule')),
  target_id uuid not null,
  reason text not null check (length(btrim(reason)) between 4 and 500 and reason !~ '[[:cntrl:]]'),
  revoked_by_user_id uuid not null,
  revoked_at timestamptz not null default clock_timestamp(),
  unique(target_type,target_id)
);

create table if not exists public.pdc_auditor_correction_executions (
  execution_id uuid primary key default gen_random_uuid(),
  request_id uuid not null,
  execution_kind text not null check (execution_kind in ('apply','rollback')),
  supersedes_execution_id uuid,
  executor_identity_id uuid not null,
  dealer_code text not null check (dealer_code in ('14450','37047')),
  environment text not null check (environment='staging'),
  expected_operational_revision text not null check (expected_operational_revision ~ '^[a-f0-9]{64}$'),
  discovered_candidate_count integer not null check (discovered_candidate_count between 0 and 100000),
  correction_count integer not null check (correction_count between 0 and 50),
  result_code text not null check (result_code in ('applied','no_changes','rolled_back')),
  executed_by_user_id uuid not null,
  executed_by_email text not null,
  executed_at timestamptz not null default clock_timestamp(),
  unique(executor_identity_id,request_id),
  foreign key(executor_identity_id) references public.pdc_auditor_executor_identities(executor_identity_id) on delete restrict,
  foreign key(supersedes_execution_id) references public.pdc_auditor_correction_executions(execution_id) on delete restrict,
  check ((execution_kind='apply' and supersedes_execution_id is null and result_code in ('applied','no_changes'))
      or (execution_kind='rollback' and supersedes_execution_id is not null and result_code='rolled_back'))
);
create unique index if not exists pdc_auditor_correction_one_rollback_idx
  on public.pdc_auditor_correction_executions(supersedes_execution_id)
  where supersedes_execution_id is not null;

create table if not exists public.pdc_auditor_correction_execution_items (
  execution_item_id uuid primary key default gen_random_uuid(),
  execution_id uuid not null references public.pdc_auditor_correction_executions(execution_id) on delete restrict,
  dealer_code text not null check (dealer_code in ('14450','37047')),
  environment text not null check (environment='staging'),
  operation_line_id uuid not null references public.pdc_authenticated_email_operation_lines(operation_line_id) on delete restrict,
  vehicle_id uuid not null references public.vehicles(id) on delete restrict,
  adjustment_id uuid not null references public.vehicle_workshop_line_adjustments(adjustment_id) on delete restrict,
  rule_code text not null check (rule_code in ('station_exact_description','hours_exact_normalized_description','station_and_hours_exact')),
  source_stage_code text,
  target_stage_code text not null check (target_stage_code ~ '^[A-Z][A-Z0-9_]{1,39}$'),
  source_estimated_hours numeric(6,2),
  target_estimated_hours numeric(6,2),
  before_data jsonb,
  after_data jsonb not null,
  created_at timestamptz not null default clock_timestamp(),
  unique(execution_id,operation_line_id),
  check (target_estimated_hours is null or (
    target_estimated_hours between 0.25 and 999.75 and mod(target_estimated_hours,0.25)=0
  ))
);

do $history$
begin
  execute 'drop trigger if exists pdc_auditor_executor_identities_immutable on public.pdc_auditor_executor_identities';
  execute 'drop trigger if exists pdc_auditor_hour_rules_immutable on public.pdc_auditor_autonomous_hour_rules';
  execute 'drop trigger if exists pdc_auditor_authority_revocations_immutable on public.pdc_auditor_restricted_authority_revocations';
  execute 'drop trigger if exists pdc_auditor_correction_executions_immutable on public.pdc_auditor_correction_executions';
  execute 'drop trigger if exists pdc_auditor_correction_items_immutable on public.pdc_auditor_correction_execution_items';
end;
$history$;
create trigger pdc_auditor_executor_identities_immutable
  before update or delete on public.pdc_auditor_executor_identities
  for each row execute function public.pdc_auditor_reject_history_mutation();
create trigger pdc_auditor_hour_rules_immutable
  before update or delete on public.pdc_auditor_autonomous_hour_rules
  for each row execute function public.pdc_auditor_reject_history_mutation();
create trigger pdc_auditor_authority_revocations_immutable
  before update or delete on public.pdc_auditor_restricted_authority_revocations
  for each row execute function public.pdc_auditor_reject_history_mutation();
create trigger pdc_auditor_correction_executions_immutable
  before update or delete on public.pdc_auditor_correction_executions
  for each row execute function public.pdc_auditor_reject_history_mutation();
create trigger pdc_auditor_correction_items_immutable
  before update or delete on public.pdc_auditor_correction_execution_items
  for each row execute function public.pdc_auditor_reject_history_mutation();

create or replace function public.pdc_auditor_normalized_operation_description(p_description text)
returns text
language sql immutable security definer set search_path=pg_catalog,public
as $normalize$
  select btrim(regexp_replace(lower(coalesce(p_description,'')),'[^a-z0-9]+',' ','g'))
$normalize$;
revoke all on function public.pdc_auditor_normalized_operation_description(text) from public,anon,authenticated,service_role;

create or replace function public.pdc_auditor_recommended_operation_stage(p_description text)
returns text
language plpgsql immutable security definer set search_path=pg_catalog,public
as $stage$
declare
  v_description text:=public.pdc_auditor_normalized_operation_description(p_description);
  v_fitting boolean;
  v_hoist boolean;
  v_tint boolean;
  v_match_count integer;
begin
  v_fitting:=v_description ~ '(^| )(loose safety items?|bonnet protectors?|weather shields?|headlamp covers?|headlight covers?|pdi|pre delivery inspections?|seat covers?|recovery points?)( |$)';
  v_hoist:=v_description ~ '(^| )(long range (fuel )?tanks?)( |$)';
  v_tint:=v_description ~ '(^| )(window )?tint(ing)?( |$)';
  v_match_count:=(v_fitting::integer+v_hoist::integer+v_tint::integer);
  -- A description matches more than one autonomous station family: fail closed.
  if v_match_count<>1 then return null; end if;
  if v_fitting then return 'FITTING'; end if;
  if v_hoist then return 'HOIST'; end if;
  return 'TINT';
end;
$stage$;
revoke all on function public.pdc_auditor_recommended_operation_stage(text) from public,anon,authenticated,service_role;

-- Viewer workers may submit deterministic findings, but only exact enrolled workers qualify.
create or replace function public.pdc_auditor_worker_scope(p_dealer_code text)
returns jsonb
language plpgsql stable security definer set search_path=pg_catalog,public
as $worker$
declare
  v_uid uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_count integer;
begin
  if v_uid is null or v_email='' or p_dealer_code not in ('14450','37047') then
    raise exception 'pdc_auditor_worker_unauthorized' using errcode='42501';
  end if;
  select count(*) into v_count
  from public.pdc_auditor_worker_identities w
  join public.pdc_auditor_user_dealer_scopes s
    on s.auth_user_id=w.auth_user_id and s.normalized_email=w.normalized_email
   and s.dealer_code=w.dealer_code and s.environment=w.environment and s.active
  join public.pdc_user_roles r
    on r.auth_user_id=v_uid and lower(r.email)=v_email
   and r.active and r.account_status='approved'
   and r.role::text in ('viewer','operator','administrator')
  join auth.users au on au.id=v_uid and lower(coalesce(au.email,''))=v_email
  where w.auth_user_id=v_uid and w.normalized_email=v_email
    and w.dealer_code=p_dealer_code and w.environment='staging' and w.active;
  if v_count<>1 then
    raise exception 'pdc_auditor_worker_unauthorized' using errcode='42501';
  end if;
  return jsonb_build_object('user_id',v_uid,'email',v_email,
    'dealer_code',p_dealer_code,'environment','staging');
end;
$worker$;
revoke all on function public.pdc_auditor_worker_scope(text) from public,anon,authenticated,service_role;

create or replace function public.configure_pdc_auditor_executor_identity(
  p_auth_user_id uuid,p_normalized_email text,p_dealer_code text,
  p_expires_at timestamptz,p_max_corrections_per_run integer default 25
)
returns jsonb
language plpgsql security definer set search_path=pg_catalog,public
as $configure$
declare
  v_actor_scope jsonb:=public.pdc_auditor_actor_scope();
  v_actor uuid:=(v_actor_scope->>'user_id')::uuid;
  v_email text:=lower(btrim(coalesce(p_normalized_email,'')));
  v_count integer;
  v_identity_id uuid;
begin
  if v_actor_scope->>'role'<>'administrator' then
    raise exception 'pdc_auditor_executor_configuration_forbidden' using errcode='42501';
  end if;
  if p_auth_user_id is null or v_email='' or p_dealer_code not in ('14450','37047')
     or p_expires_at<=clock_timestamp() or p_expires_at>clock_timestamp()+interval '31 days'
     or p_max_corrections_per_run not between 1 and 50 then
    raise exception 'pdc_auditor_executor_configuration_invalid' using errcode='22023';
  end if;
  select count(*) into v_count
  from public.pdc_auditor_worker_identities w
  join public.pdc_auditor_user_dealer_scopes s
    on s.auth_user_id=w.auth_user_id and s.normalized_email=w.normalized_email
   and s.dealer_code=w.dealer_code and s.environment=w.environment and s.active
  join public.pdc_user_roles r
    on r.auth_user_id=w.auth_user_id and lower(r.email)=w.normalized_email
   and r.active and r.account_status='approved' and r.role::text='viewer'
  join auth.users au on au.id=w.auth_user_id and lower(coalesce(au.email,''))=w.normalized_email
  where w.auth_user_id=p_auth_user_id and w.normalized_email=v_email
    and w.dealer_code=p_dealer_code and w.environment='staging' and w.active;
  if v_count<>1 then
    raise exception 'pdc_auditor_executor_requires_dedicated_viewer' using errcode='42501';
  end if;
  if exists(select 1 from public.pdc_auditor_executor_identities e
      where e.auth_user_id=p_auth_user_id and e.normalized_email=v_email
        and e.environment='staging' and e.expires_at>clock_timestamp()
        and not exists(select 1 from public.pdc_auditor_restricted_authority_revocations x
          where x.target_type='executor_identity' and x.target_id=e.executor_identity_id)) then
    raise exception 'pdc_auditor_executor_identity_already_recorded' using errcode='23505';
  end if;
  insert into public.pdc_auditor_executor_identities(
    auth_user_id,normalized_email,dealer_code,environment,active,expires_at,
    max_corrections_per_run,enabled_by_user_id
  ) values(p_auth_user_id,v_email,p_dealer_code,'staging',true,p_expires_at,
    p_max_corrections_per_run,v_actor)
  returning executor_identity_id into v_identity_id;
  return jsonb_build_object('ok',true,'code','pdc_auditor_executor_enabled',
    'executor_identity_id',v_identity_id,'dealer_code',p_dealer_code,
    'expires_at',p_expires_at,'max_corrections_per_run',p_max_corrections_per_run);
end;
$configure$;
revoke all on function public.configure_pdc_auditor_executor_identity(uuid,text,text,timestamptz,integer) from public,anon,authenticated,service_role;
grant execute on function public.configure_pdc_auditor_executor_identity(uuid,text,text,timestamptz,integer) to authenticated;

create or replace function public.revoke_pdc_auditor_restricted_authority(
  p_target_type text,p_target_id uuid,p_reason text
)
returns jsonb
language plpgsql security definer set search_path=pg_catalog,public
as $revoke$
declare
  v_scope jsonb:=public.pdc_auditor_actor_scope();
  v_reason text:=btrim(coalesce(p_reason,''));
  v_revocation_id uuid;
begin
  if v_scope->>'role'<>'administrator' then
    raise exception 'pdc_auditor_authority_revocation_forbidden' using errcode='42501';
  end if;
  if p_target_type not in ('executor_identity','hour_rule') or p_target_id is null
     or length(v_reason) not between 4 and 500 or v_reason ~ '[[:cntrl:]]' then
    raise exception 'pdc_auditor_authority_revocation_invalid' using errcode='22023';
  end if;
  if p_target_type='executor_identity'
     and not exists(select 1 from public.pdc_auditor_executor_identities where executor_identity_id=p_target_id) then
    raise exception 'pdc_auditor_executor_identity_not_found' using errcode='P0002';
  end if;
  if p_target_type='hour_rule'
     and not exists(select 1 from public.pdc_auditor_autonomous_hour_rules where hour_rule_id=p_target_id) then
    raise exception 'pdc_auditor_hour_rule_not_found' using errcode='P0002';
  end if;
  insert into public.pdc_auditor_restricted_authority_revocations(
    target_type,target_id,reason,revoked_by_user_id
  ) values(p_target_type,p_target_id,v_reason,(v_scope->>'user_id')::uuid)
  on conflict(target_type,target_id) do nothing
  returning revocation_id into v_revocation_id;
  if v_revocation_id is null then
    select revocation_id into v_revocation_id from public.pdc_auditor_restricted_authority_revocations
      where target_type=p_target_type and target_id=p_target_id;
  end if;
  return jsonb_build_object('ok',true,'code','pdc_auditor_authority_revoked',
    'revocation_id',v_revocation_id,'target_type',p_target_type,'target_id',p_target_id);
end;
$revoke$;
revoke all on function public.revoke_pdc_auditor_restricted_authority(text,uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.revoke_pdc_auditor_restricted_authority(text,uuid,text) to authenticated;

create or replace function public.append_pdc_auditor_autonomous_hour_rule(
  p_normalized_description text,p_target_estimated_hours numeric
)
returns jsonb
language plpgsql security definer set search_path=pg_catalog,public
as $hour_rule$
declare
  v_scope jsonb:=public.pdc_auditor_actor_scope();
  v_description text:=public.pdc_auditor_normalized_operation_description(p_normalized_description);
  v_rule_id uuid;
begin
  if v_scope->>'role'<>'administrator' then
    raise exception 'pdc_auditor_hour_rule_forbidden' using errcode='42501';
  end if;
  if length(v_description) not between 3 and 180
     or p_target_estimated_hours is null or p_target_estimated_hours not between 0.25 and 999.75
     or mod(p_target_estimated_hours,0.25)<>0 then
    raise exception 'pdc_auditor_hour_rule_invalid' using errcode='22023';
  end if;
  if exists(select 1 from public.pdc_auditor_autonomous_hour_rules h
      where h.dealer_code=v_scope->>'dealer_code' and h.environment='staging'
        and h.normalized_description=v_description and h.active
        and h.effective_from<=clock_timestamp()
        and (h.effective_to is null or h.effective_to>clock_timestamp())
        and not exists(select 1 from public.pdc_auditor_restricted_authority_revocations x
          where x.target_type='hour_rule' and x.target_id=h.hour_rule_id)) then
    raise exception 'pdc_auditor_hour_rule_already_current' using errcode='23505';
  end if;
  insert into public.pdc_auditor_autonomous_hour_rules(
    dealer_code,environment,description_pattern,normalized_description,
    target_estimated_hours,created_by_user_id
  ) values(v_scope->>'dealer_code','staging','exact_normalized_description',v_description,
    p_target_estimated_hours,(v_scope->>'user_id')::uuid)
  returning hour_rule_id into v_rule_id;
  return jsonb_build_object('ok',true,'code','pdc_auditor_hour_rule_appended',
    'hour_rule_id',v_rule_id,'description_pattern','exact_normalized_description');
end;
$hour_rule$;
revoke all on function public.append_pdc_auditor_autonomous_hour_rule(text,numeric) from public,anon,authenticated,service_role;
grant execute on function public.append_pdc_auditor_autonomous_hour_rule(text,numeric) to authenticated;

create or replace function public.pdc_auditor_executor_scope()
returns jsonb
language plpgsql stable security definer set search_path=pg_catalog,public
as $executor$
declare
  v_uid uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_count integer;
  v_identity public.pdc_auditor_executor_identities%rowtype;
begin
  if v_uid is null or v_email='' then
    raise exception 'pdc_auditor_executor_unauthorized' using errcode='42501';
  end if;
  select count(*) into v_count
  from public.pdc_auditor_executor_identities e
  join public.pdc_auditor_worker_identities w
    on w.auth_user_id=e.auth_user_id and w.normalized_email=e.normalized_email
   and w.dealer_code=e.dealer_code and w.environment=e.environment and w.active
  join public.pdc_auditor_user_dealer_scopes s
    on s.auth_user_id=e.auth_user_id and s.normalized_email=e.normalized_email
   and s.dealer_code=e.dealer_code and s.environment=e.environment and s.active
  join public.pdc_user_roles r
    on r.auth_user_id=e.auth_user_id and lower(r.email)=e.normalized_email
   and r.active and r.account_status='approved' and r.role::text='viewer'
  join auth.users au on au.id=e.auth_user_id and lower(coalesce(au.email,''))=e.normalized_email
  where e.auth_user_id=v_uid and e.normalized_email=v_email
    and e.environment='staging' and e.active and e.expires_at>clock_timestamp()
    and not exists(select 1 from public.pdc_auditor_restricted_authority_revocations x
      where x.target_type='executor_identity' and x.target_id=e.executor_identity_id);
  if v_count<>1 then
    raise exception 'pdc_auditor_executor_unauthorized' using errcode='42501';
  end if;
  select * into strict v_identity
  from public.pdc_auditor_executor_identities e
  where e.auth_user_id=v_uid and e.normalized_email=v_email
    and e.environment='staging' and e.active and e.expires_at>clock_timestamp()
    and not exists(select 1 from public.pdc_auditor_restricted_authority_revocations x
      where x.target_type='executor_identity' and x.target_id=e.executor_identity_id);
  return jsonb_build_object('executor_identity_id',v_identity.executor_identity_id,
    'user_id',v_uid,'email',v_email,'dealer_code',v_identity.dealer_code,
    'environment','staging','max_corrections_per_run',v_identity.max_corrections_per_run,
    'expires_at',v_identity.expires_at);
end;
$executor$;
revoke all on function public.pdc_auditor_executor_scope() from public,anon,authenticated,service_role;

create or replace function public.pdc_auditor_autonomous_correction_candidates(p_dealer_code text)
returns table(
  operation_line_id uuid,vehicle_id uuid,stock_number text,description text,
  source_stage_code text,target_stage_code text,source_estimated_hours numeric,
  target_estimated_hours numeric,rule_code text
)
language sql stable security definer set search_path=pg_catalog,public
as $candidates$
  with source_rows as (
    select ol.operation_line_id,ol.vehicle_id,v.stock_number,
      left(btrim(ol.description),180) description,
      upper(btrim(coalesce(ol.work_key,''))) source_stage_code,
      public.pdc_auditor_recommended_operation_stage(ol.description) target_stage_code,
      ol.estimated_hours source_estimated_hours,
      public.pdc_auditor_normalized_operation_description(ol.description) normalized_description
    from public.pdc_authenticated_email_operation_lines ol
    join public.vehicles v on v.id=ol.vehicle_id
    where public.pdc_auditor_vehicle_dealer(ol.vehicle_id)=p_dealer_code
      and v.lifecycle_state='active' and v.deleted_at is null
      and length(btrim(coalesce(ol.description,''))) between 1 and 180
      and not exists(
        select 1 from public.vehicle_workshop_line_adjustments a
        where a.vehicle_id=ol.vehicle_id and a.line_key='source:'||ol.operation_line_id::text
          and a.active
      )
  ), resolved as (
    select s.*,h.target_estimated_hours exact_rule_hours
    from source_rows s
    left join public.pdc_auditor_autonomous_hour_rules h
      on h.dealer_code=p_dealer_code and h.environment='staging'
     and h.description_pattern='exact_normalized_description'
     and h.normalized_description=s.normalized_description
     and h.active and h.effective_from<=clock_timestamp()
     and (h.effective_to is null or h.effective_to>clock_timestamp())
     and not exists(select 1 from public.pdc_auditor_restricted_authority_revocations x
       where x.target_type='hour_rule' and x.target_id=h.hour_rule_id)
    where s.target_stage_code is not null
      and exists(
        select 1 from public.vehicle_work_items wi
        where wi.vehicle_id=s.vehicle_id and wi.required and not wi.completed
          and coalesce(public.workshop_stage_code_for_work_key(wi.work_key),
            upper(regexp_replace(btrim(wi.work_key),'[^a-zA-Z0-9]+','_','g')))=s.target_stage_code
      )
  )
  select r.operation_line_id,r.vehicle_id,r.stock_number,r.description,
    nullif(r.source_stage_code,''),r.target_stage_code,r.source_estimated_hours,
    case when r.source_estimated_hours is null then r.exact_rule_hours else r.source_estimated_hours end,
    case when r.source_stage_code is distinct from r.target_stage_code
           and r.source_estimated_hours is null and r.exact_rule_hours is not null
      then 'station_and_hours_exact'
      when r.source_stage_code is distinct from r.target_stage_code then 'station_exact_description'
      else 'hours_exact_normalized_description' end
  from resolved r
  where r.source_stage_code is distinct from r.target_stage_code
     or (r.source_estimated_hours is null and r.exact_rule_hours is not null)
  order by r.vehicle_id,r.operation_line_id
$candidates$;
revoke all on function public.pdc_auditor_autonomous_correction_candidates(text) from public,anon,authenticated,service_role;

create or replace function public.get_pdc_auditor_autonomous_correction_preview()
returns jsonb
language plpgsql stable security definer set search_path=pg_catalog,public
as $preview$
declare
  v_scope jsonb:=public.pdc_auditor_actor_scope();
  v_dealer text:=v_scope->>'dealer_code';
  v_uid uuid:=(v_scope->>'user_id')::uuid;
  v_email text:=v_scope->>'email';
  v_can_execute boolean;
  v_items jsonb;
  v_candidate_count integer;
begin
  select count(*)=1 into v_can_execute
  from public.pdc_auditor_executor_identities e
  join public.pdc_user_roles r on r.auth_user_id=e.auth_user_id
    and lower(r.email)=e.normalized_email and r.active and r.account_status='approved'
    and r.role::text='viewer'
  where e.auth_user_id=v_uid and e.normalized_email=v_email
    and e.dealer_code=v_dealer and e.environment='staging' and e.active
    and e.expires_at>clock_timestamp()
    and not exists(select 1 from public.pdc_auditor_restricted_authority_revocations x
      where x.target_type='executor_identity' and x.target_id=e.executor_identity_id);
  select count(*) into v_candidate_count
    from public.pdc_auditor_autonomous_correction_candidates(v_dealer);
  select coalesce(jsonb_agg(jsonb_build_object(
    'operation_line_id',c.operation_line_id,'vehicle_id',c.vehicle_id,
    'stock_number',c.stock_number,'description',c.description,
    'source_stage_code',c.source_stage_code,'target_stage_code',c.target_stage_code,
    'source_estimated_hours',c.source_estimated_hours,
    'target_estimated_hours',c.target_estimated_hours,'rule_code',c.rule_code
  ) order by c.vehicle_id,c.operation_line_id),'[]'::jsonb)
  into v_items from (
    select * from public.pdc_auditor_autonomous_correction_candidates(v_dealer)
    order by vehicle_id,operation_line_id limit 50
  ) c;
  return jsonb_build_object('ok',true,'code','pdc_auditor_autonomous_correction_preview',
    'environment','staging','dealer_code',v_dealer,
    'operational_revision',public.pdc_auditor_operational_revision(v_dealer),
    'can_execute',v_can_execute,'candidate_count',v_candidate_count,
    'batch_limit',50,'remaining_count',greatest(v_candidate_count-50,0),'items',v_items);
end;
$preview$;
revoke all on function public.get_pdc_auditor_autonomous_correction_preview() from public,anon,authenticated,service_role;
grant execute on function public.get_pdc_auditor_autonomous_correction_preview() to authenticated;

create or replace function public.execute_pdc_auditor_autonomous_corrections(
  p_expected_operational_revision text,p_request_id uuid
)
returns jsonb
language plpgsql security definer set search_path=pg_catalog,public
as $execute$
declare
  v_scope jsonb:=public.pdc_auditor_executor_scope();
  v_dealer text:=v_scope->>'dealer_code';
  v_uid uuid:=(v_scope->>'user_id')::uuid;
  v_email text:=v_scope->>'email';
  v_identity uuid:=(v_scope->>'executor_identity_id')::uuid;
  v_max_corrections integer:=(v_scope->>'max_corrections_per_run')::integer;
  v_candidate_count integer;
  v_batch_count integer;
  v_execution_id uuid;
  v_existing public.pdc_auditor_correction_executions%rowtype;
  v_candidate record;
  v_after public.vehicle_workshop_line_adjustments%rowtype;
begin
  if p_request_id is null or coalesce(p_expected_operational_revision,'') !~ '^[a-f0-9]{64}$' then
    raise exception 'pdc_auditor_autonomous_request_invalid' using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('pdc-auditor-autonomous:'||v_dealer,0));
  select * into v_existing from public.pdc_auditor_correction_executions e
    where e.executor_identity_id=v_identity and e.request_id=p_request_id;
  if found then
    return jsonb_build_object('ok',true,'idempotent',true,'code',v_existing.result_code,
      'execution_id',v_existing.execution_id,'correction_count',v_existing.correction_count,
      'candidate_count',v_existing.discovered_candidate_count,
      'remaining_count',greatest(v_existing.discovered_candidate_count-v_existing.correction_count,0),
      'operational_change',v_existing.correction_count>0);
  end if;
  if public.pdc_auditor_operational_revision(v_dealer)<>p_expected_operational_revision then
    raise exception 'pdc_auditor_autonomous_snapshot_stale' using errcode='40001';
  end if;
  select count(*) into v_candidate_count
    from public.pdc_auditor_autonomous_correction_candidates(v_dealer);
  v_batch_count:=least(v_candidate_count,v_max_corrections,50);
  insert into public.pdc_auditor_correction_executions(
    request_id,execution_kind,executor_identity_id,dealer_code,environment,
    expected_operational_revision,discovered_candidate_count,correction_count,result_code,
    executed_by_user_id,executed_by_email
  ) values(p_request_id,'apply',v_identity,v_dealer,'staging',
    p_expected_operational_revision,v_candidate_count,v_batch_count,
    case when v_batch_count=0 then 'no_changes' else 'applied' end,
    v_uid,v_email)
  returning execution_id into v_execution_id;
  for v_candidate in
    select * from public.pdc_auditor_autonomous_correction_candidates(v_dealer)
    order by vehicle_id,operation_line_id limit v_batch_count
  loop
    if public.pdc_auditor_vehicle_dealer(v_candidate.vehicle_id)<>v_dealer then
      raise exception 'pdc_auditor_autonomous_scope_changed' using errcode='40001';
    end if;
    perform 1 from public.vehicle_work_items wi
      where wi.vehicle_id=v_candidate.vehicle_id and wi.required and not wi.completed
        and coalesce(public.workshop_stage_code_for_work_key(wi.work_key),
          upper(regexp_replace(btrim(wi.work_key),'[^a-zA-Z0-9]+','_','g')))=v_candidate.target_stage_code
      for share;
    if not found then
      raise exception 'pdc_auditor_autonomous_target_completed' using errcode='40001';
    end if;
    if exists(select 1 from public.vehicle_workshop_line_adjustments a
      where a.vehicle_id=v_candidate.vehicle_id
        and a.line_key='source:'||v_candidate.operation_line_id::text and a.active) then
      raise exception 'pdc_auditor_autonomous_line_changed' using errcode='40001';
    end if;
    insert into public.vehicle_workshop_line_adjustments(
      vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,
      active,version,created_by,updated_by
    ) values(v_candidate.vehicle_id,'source:'||v_candidate.operation_line_id::text,
      'source',v_candidate.target_stage_code,v_candidate.description,
      v_candidate.target_estimated_hours,true,1,v_uid,v_uid)
    returning * into v_after;
    insert into public.audit_events(
      action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata
    ) values('insert','vehicle_workshop_line_adjustments',v_after.adjustment_id,
      v_candidate.vehicle_id,v_uid,v_email,null,to_jsonb(v_after),jsonb_build_object(
        'source','pdc_ai_auditor_autonomous_175','execution_id',v_execution_id,
        'operation_line_id',v_candidate.operation_line_id,'rule_code',v_candidate.rule_code,
        'bookings_changed',false,'parts_changed',false,'completion_changed',false));
    insert into public.pdc_auditor_correction_execution_items(
      execution_id,dealer_code,environment,operation_line_id,vehicle_id,adjustment_id,
      rule_code,source_stage_code,target_stage_code,source_estimated_hours,
      target_estimated_hours,before_data,after_data
    ) values(v_execution_id,v_dealer,'staging',v_candidate.operation_line_id,
      v_candidate.vehicle_id,v_after.adjustment_id,v_candidate.rule_code,
      v_candidate.source_stage_code,v_candidate.target_stage_code,
      v_candidate.source_estimated_hours,v_candidate.target_estimated_hours,null,to_jsonb(v_after));
  end loop;
  return jsonb_build_object('ok',true,'idempotent',false,
    'code',case when v_batch_count=0 then 'no_changes' else 'applied' end,
    'execution_id',v_execution_id,'candidate_count',v_candidate_count,
    'correction_count',v_batch_count,
    'remaining_count',greatest(v_candidate_count-v_batch_count,0),
    'operational_change',v_batch_count>0,
    'bookings_changed',false,'parts_changed',false,'completion_changed',false);
end;
$execute$;
revoke all on function public.execute_pdc_auditor_autonomous_corrections(text,uuid) from public,anon,authenticated,service_role;
grant execute on function public.execute_pdc_auditor_autonomous_corrections(text,uuid) to authenticated;

create or replace function public.rollback_pdc_auditor_autonomous_correction(
  p_execution_id uuid,p_expected_adjustment_version bigint,p_request_id uuid
)
returns jsonb
language plpgsql security definer set search_path=pg_catalog,public
as $rollback$
declare
  v_scope jsonb:=public.pdc_auditor_executor_scope();
  v_dealer text:=v_scope->>'dealer_code';
  v_uid uuid:=(v_scope->>'user_id')::uuid;
  v_email text:=v_scope->>'email';
  v_identity uuid:=(v_scope->>'executor_identity_id')::uuid;
  v_source public.pdc_auditor_correction_executions%rowtype;
  v_execution_id uuid;
  v_item record;
  v_before public.vehicle_workshop_line_adjustments%rowtype;
  v_after public.vehicle_workshop_line_adjustments%rowtype;
  v_source_metadata jsonb;
begin
  if p_execution_id is null or p_request_id is null or p_expected_adjustment_version is null
     or p_expected_adjustment_version<1 then
    raise exception 'pdc_auditor_rollback_invalid' using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('pdc-auditor-autonomous:'||v_dealer,0));
  select * into v_source from public.pdc_auditor_correction_executions e
    where e.execution_id=p_execution_id and e.execution_kind='apply'
      and e.executor_identity_id=v_identity and e.dealer_code=v_dealer
      and e.result_code='applied';
  if not found then raise exception 'pdc_auditor_rollback_not_found' using errcode='P0002'; end if;
  if exists(select 1 from public.pdc_auditor_correction_executions e
      where e.supersedes_execution_id=p_execution_id) then
    return jsonb_build_object('ok',true,'idempotent',true,'code','rolled_back',
      'execution_id',(select e.execution_id from public.pdc_auditor_correction_executions e
        where e.supersedes_execution_id=p_execution_id));
  end if;
  for v_item in select * from public.pdc_auditor_correction_execution_items i
    where i.execution_id=p_execution_id order by i.operation_line_id
  loop
    select * into v_before from public.vehicle_workshop_line_adjustments a
      where a.adjustment_id=v_item.adjustment_id and a.vehicle_id=v_item.vehicle_id for update;
    if not found or not v_before.active or v_before.version<>p_expected_adjustment_version
       or v_before.version<>(v_item.after_data->>'version')::bigint then
      raise exception 'stale_line_version' using errcode='40001';
    end if;
    select e.metadata into v_source_metadata from public.audit_events e
      where e.table_name='vehicle_workshop_line_adjustments'
        and e.row_id=v_item.adjustment_id and e.action='insert'
      order by e.created_at,e.id limit 1;
    if coalesce(v_source_metadata->>'source','')<>'pdc_ai_auditor_autonomous_175'
       or v_source_metadata->>'execution_id'<>p_execution_id::text then
      raise exception 'pdc_auditor_rollback_source_mismatch' using errcode='42501';
    end if;
  end loop;
  insert into public.pdc_auditor_correction_executions(
    request_id,execution_kind,supersedes_execution_id,executor_identity_id,
    dealer_code,environment,expected_operational_revision,discovered_candidate_count,correction_count,
    result_code,executed_by_user_id,executed_by_email
  ) values(p_request_id,'rollback',p_execution_id,v_identity,v_dealer,'staging',
    public.pdc_auditor_operational_revision(v_dealer),v_source.correction_count,v_source.correction_count,
    'rolled_back',v_uid,v_email)
  returning execution_id into v_execution_id;
  for v_item in select * from public.pdc_auditor_correction_execution_items i
    where i.execution_id=p_execution_id order by i.operation_line_id
  loop
    select * into strict v_before from public.vehicle_workshop_line_adjustments a
      where a.adjustment_id=v_item.adjustment_id for update;
    update public.vehicle_workshop_line_adjustments set
      active=false,version=version+1,updated_by=v_uid,updated_at=clock_timestamp()
      where adjustment_id=v_before.adjustment_id returning * into v_after;
    insert into public.audit_events(
      action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata
    ) values('delete','vehicle_workshop_line_adjustments',v_after.adjustment_id,
      v_after.vehicle_id,v_uid,v_email,to_jsonb(v_before),to_jsonb(v_after),jsonb_build_object(
        'source','pdc_ai_auditor_autonomous_175_rollback','execution_id',v_execution_id,
        'supersedes_execution_id',p_execution_id,
        'bookings_changed',false,'parts_changed',false,'completion_changed',false));
    insert into public.pdc_auditor_correction_execution_items(
      execution_id,dealer_code,environment,operation_line_id,vehicle_id,adjustment_id,
      rule_code,source_stage_code,target_stage_code,source_estimated_hours,
      target_estimated_hours,before_data,after_data
    ) values(v_execution_id,v_dealer,'staging',v_item.operation_line_id,v_item.vehicle_id,
      v_item.adjustment_id,v_item.rule_code,v_item.target_stage_code,
      v_item.source_stage_code,v_item.target_estimated_hours,
      v_item.source_estimated_hours,to_jsonb(v_before),to_jsonb(v_after));
  end loop;
  return jsonb_build_object('ok',true,'idempotent',false,'code','rolled_back',
    'execution_id',v_execution_id,'supersedes_execution_id',p_execution_id,
    'correction_count',v_source.correction_count,'operational_change',true,
    'bookings_changed',false,'parts_changed',false,'completion_changed',false);
end;
$rollback$;
revoke all on function public.rollback_pdc_auditor_autonomous_correction(uuid,bigint,uuid) from public,anon,authenticated,service_role;
grant execute on function public.rollback_pdc_auditor_autonomous_correction(uuid,bigint,uuid) to authenticated;

alter table public.pdc_auditor_executor_identities enable row level security;
alter table public.pdc_auditor_autonomous_hour_rules enable row level security;
alter table public.pdc_auditor_restricted_authority_revocations enable row level security;
alter table public.pdc_auditor_correction_executions enable row level security;
alter table public.pdc_auditor_correction_execution_items enable row level security;
revoke all on table public.pdc_auditor_executor_identities from public,anon,authenticated,service_role;
revoke all on table public.pdc_auditor_autonomous_hour_rules from public,anon,authenticated,service_role;
revoke all on table public.pdc_auditor_restricted_authority_revocations from public,anon,authenticated,service_role;
revoke all on table public.pdc_auditor_correction_executions from public,anon,authenticated,service_role;
revoke all on table public.pdc_auditor_correction_execution_items from public,anon,authenticated,service_role;

comment on function public.execute_pdc_auditor_autonomous_corrections(text,uuid) is
  'Staging-only restricted Viewer executor. Server derives exact-description station/hour overlays, enforces dealer/completion/revision/cap boundaries, and cannot mutate bookings, Parts, completion or source rows.';
comment on function public.rollback_pdc_auditor_autonomous_correction(uuid,bigint,uuid) is
  'Rollback for unchanged AI-created migration-175 overlays only; appends a rollback execution and audit evidence.';

insert into supabase_migrations.schema_migrations(version,name,statements) values(
  '175','restricted_ai_auditor_autonomous_corrections',array[
    'enrol expiring dedicated Viewer executor identities bound to exact worker and dealer scope',
    'derive bounded station overlays from unambiguous description families and exact Administrator hour rules',
    'append immutable execution evidence and permit version-checked rollback of unchanged AI-created overlays only'
  ]
);
commit;
