-- Staging-only migration 225: immutable Telegram-bound, server-derived AI Auditor plans.
-- This release plans and reviews only. Migration 226 owns any future apply implementation.
begin;
set local lock_timeout='10s';
set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-225-ai-auditor-telegram-plans',0));

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists (
       select 1 from public.pdc_staging_environment_sentinel
       where singleton and project_ref='cdsmnqxtyyoeoznmbidd'
     )
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or to_regclass('supabase_migrations.schema_migrations') is null
     or not exists (
       select 1 from supabase_migrations.schema_migrations where version='224'
     )
     or exists (
       select 1 from supabase_migrations.schema_migrations
       where version ~ '^[0-9]+$' and version::integer>224
     )
     or exists (
       select 1 from supabase_migrations.schema_migrations where version='225'
     ) then
    raise exception 'PDC_225_STAGING_OR_LEDGER_MISMATCH' using errcode='55000';
  end if;
  if to_regclass('public.pdc_user_roles') is null
     or to_regclass('public.pdc_auditor_worker_identities') is null
     or to_regclass('public.pdc_auditor_user_dealer_scopes') is null
     or to_regclass('public.pdc_supervised_telegram_identities') is null
     or to_regclass('public.pdc_authenticated_email_operation_lines') is null
     or to_regclass('public.vehicle_workshop_line_adjustments') is null
     or to_regclass('public.vehicle_work_items') is null
     or to_regprocedure('public.pdc_auditor_operational_revision(text)') is null
     or to_regprocedure('public.pdc_auditor_vehicle_dealer(uuid)') is null
     or to_regprocedure('public.pdc_auditor_reject_history_mutation()') is null then
    raise exception 'PDC_225_DEPENDENCY_MISSING' using errcode='55000';
  end if;
end
$guard$;

-- An ordinary authenticated user may be enrolled here only by a server-side release or
-- separate privileged SQL ceremony. It receives no CRUD and is never service_role.
create table public.pdc_auditor_service_identities_225 (
  service_identity_id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null references auth.users(id) on delete restrict,
  normalized_email text not null check (
    normalized_email=lower(btrim(normalized_email))
    and normalized_email ~ '^[^[:space:]@]+@[^[:space:]@]+$'
  ),
  dealer_code text not null check (dealer_code in ('14450','37047')),
  environment text not null check (environment='staging'),
  identity_purpose text not null check (identity_purpose='ai_auditor_telegram_planner'),
  active boolean not null default true,
  approved_by_user_id uuid not null references auth.users(id) on delete restrict,
  approved_at timestamptz not null default clock_timestamp(),
  revoked_at timestamptz,
  check ((active and revoked_at is null) or (not active and revoked_at is not null)),
  unique(auth_user_id,normalized_email,dealer_code,environment,identity_purpose)
);
create unique index pdc_auditor_service_identities_225_one_active
  on public.pdc_auditor_service_identities_225(auth_user_id,normalized_email,environment)
  where active;

-- Server-approved exact GVM mappings. Empty is safe: no exact mapping means no GVM plan item.
-- Category and exact code/description are both required; tanks and generic hoist work cannot map.
create table public.pdc_auditor_gvm_mappings_225 (
  mapping_id uuid primary key default gen_random_uuid(),
  dealer_code text not null check (dealer_code in ('14450','37047')),
  environment text not null check (environment='staging'),
  exact_operation_code text not null check (
    exact_operation_code=upper(btrim(exact_operation_code))
    and length(exact_operation_code) between 1 and 80
    and exact_operation_code !~ '[[:cntrl:]]'
  ),
  exact_normalized_description text not null check (
    exact_normalized_description=lower(btrim(exact_normalized_description))
    and length(exact_normalized_description) between 3 and 240
    and exact_normalized_description !~ '[[:cntrl:]]'
    and exact_normalized_description ~ '(^| )(gvm|gross vehicle mass)( |$)'
    and exact_normalized_description !~ '(^| )(tank|fuel|long range|hoist)( |$)'
  ),
  category text not null check (category='genuine_gvm_upgrade'),
  active boolean not null default true,
  approved_by_user_id uuid not null references auth.users(id) on delete restrict,
  approved_at timestamptz not null default clock_timestamp(),
  revoked_at timestamptz,
  check ((active and revoked_at is null) or (not active and revoked_at is not null)),
  unique(dealer_code,environment,exact_operation_code,exact_normalized_description,approved_at)
);
create index pdc_auditor_gvm_mappings_225_lookup
  on public.pdc_auditor_gvm_mappings_225(dealer_code,exact_operation_code,exact_normalized_description)
  where active;

-- Enrol the already-provisioned staging-only Viewer worker.  The approving Administrator
-- is the active Craig Telegram enrolment; neither identity receives direct table DML.
do $enrol$
declare
  v_service_user uuid;
  v_service_email text;
  v_admin_user uuid;
  v_admin_count integer;
begin
  select e.auth_user_id,e.normalized_email into strict v_service_user,v_service_email
  from public.pdc_auditor_executor_identities e
  join public.pdc_user_roles r on r.auth_user_id=e.auth_user_id
    and lower(r.email)=e.normalized_email and r.role::text='viewer'
    and r.active and r.account_status='approved'
  where e.normalized_email='pdc.ai.auditor.staging@pmb.local'
    and e.dealer_code='14450' and e.environment='staging'
    and e.active and e.expires_at>clock_timestamp();

  select count(*),min(i.auth_user_id::text)::uuid into v_admin_count,v_admin_user
  from public.pdc_supervised_telegram_identities i
  join public.pdc_user_roles r on r.auth_user_id=i.auth_user_id
    and lower(r.email)=lower(i.actor_email) and r.role::text='administrator'
    and r.active and r.account_status='approved'
  where i.telegram_sender_id=7828138290 and i.active;
  if v_admin_count<>1 then
    raise exception 'PDC_225_CRAIG_ADMIN_ENROLMENT_REQUIRED' using errcode='42501';
  end if;

  insert into public.pdc_auditor_service_identities_225(
    auth_user_id,normalized_email,dealer_code,environment,identity_purpose,approved_by_user_id
  ) values(v_service_user,v_service_email,'14450','staging','ai_auditor_telegram_planner',v_admin_user);

  -- These exact pairs are deliberately narrower than a GVM keyword or Hoist/GVM search.
  insert into public.pdc_auditor_gvm_mappings_225(
    dealer_code,environment,exact_operation_code,exact_normalized_description,category,approved_by_user_id
  )
  select '14450','staging',m.code,m.description,'genuine_gvm_upgrade',v_admin_user
  from (values
    ('OP2','ome 3550kg nitro gvm premium includes wheel alignmen'),
    ('OP3','ome 3550kg nitro gvm premium includes wheel alignmen'),
    ('OP4','ome 3550kg nitro gvm w control arm upgrade includes'),
    ('OP4','ome gvm 3650kg nitro basic'),
    ('OP4','pedderrs 3620kg gvm upgrade 300kg rear pedders can'),
    ('OP5','ome 3550kg nitro gvm premium includes wheel alignmen'),
    ('OP6','ome 3550kg nitro gvm premium includes wheel alignmen'),
    ('OP10','ome 3550kg nitro gvm basic includes wheel alignment'),
    ('OP10','ome 3650kg nitro gvm premium includes wheel alignmen'),
    ('OP11','ome 3550kg nitro gvm basic includes wheel alignment'),
    ('OP11','ome 3650kg nitro gvm premium includes wheel alignmen'),
    ('OP12','ome 3550kg nitro gvm basic includes wheel alignment'),
    ('OP14','ome 3550kg nitro gvm basic includes wheel alignment'),
    ('OP14','ome 3650kg nitro gvm basic includes wheel alignment'),
    ('OP15','ome 3550kg nitro gvm basic includes wheel alignment'),
    ('OP18','ome 3650kg nitro gvm w control arm upgrade includes'),
    ('OP20','ome 3550kg nitro gvm w control arm upgrade includes'),
    ('OP21','ome 3550kg nitro gvm premium includes wheel alignmen'),
    ('OP23','ome 3550kg nitro gvm w control arm upgrade includes')
  ) as m(code,description);
end
$enrol$;

-- One immutable reservation for every Telegram message. The unique message identity is
-- reserved before planning. Reuse with a different instruction hash is rejected.
create table public.pdc_auditor_telegram_instructions_225 (
  instruction_id uuid primary key default gen_random_uuid(),
  telegram_sender_id bigint not null,
  telegram_chat_id bigint not null,
  telegram_message_id bigint not null check (telegram_message_id>0),
  telegram_update_id bigint not null check (telegram_update_id>=0),
  bot_identity text not null check (
    bot_identity=btrim(bot_identity) and length(bot_identity) between 3 and 160
    and bot_identity !~ '[[:cntrl:]]'
  ),
  original_instruction text not null check (
    original_instruction=btrim(original_instruction)
    and length(original_instruction) between 3 and 4000
    and original_instruction !~ '[[:cntrl:]]'
  ),
  instruction_sha256 text not null check (instruction_sha256 ~ '^[a-f0-9]{64}$'),
  action text not null check (action in (
    'duplicate_bullbars','gvm_hours','long_range_tank_department','review_category',
    'stock_hours','line_department','apply_matching','show_rules','explain_line'
  )),
  mode text not null check (mode in ('review','apply','query')),
  scope jsonb not null check (jsonb_typeof(scope)='object' and octet_length(scope::text)<=8192),
  service_identity_id uuid not null references public.pdc_auditor_service_identities_225(service_identity_id) on delete restrict,
  service_auth_user_id uuid not null references auth.users(id) on delete restrict,
  service_email text not null,
  authorizing_admin_user_id uuid not null references auth.users(id) on delete restrict,
  authorizing_admin_email text not null,
  dealer_code text not null check (dealer_code in ('14450','37047')),
  environment text not null check (environment='staging'),
  received_at timestamptz not null default clock_timestamp(),
  unique(telegram_chat_id,telegram_message_id),
  unique(telegram_update_id,bot_identity)
);

create table public.pdc_auditor_plans_225 (
  plan_id uuid primary key default gen_random_uuid(),
  instruction_id uuid not null unique references public.pdc_auditor_telegram_instructions_225(instruction_id) on delete restrict,
  action text not null check (action in (
    'duplicate_bullbars','gvm_hours','long_range_tank_department','review_category',
    'stock_hours','line_department','apply_matching'
  )),
  mode text not null check (mode in ('review','apply')),
  dealer_code text not null check (dealer_code in ('14450','37047')),
  environment text not null check (environment='staging'),
  operational_revision text not null check (operational_revision ~ '^[a-f0-9]{64}$'),
  plan_hash text not null check (plan_hash ~ '^[a-f0-9]{64}$'),
  planner_contract text not null check (planner_contract='ai_auditor_telegram_plan_225_v1'),
  item_count integer not null check (item_count between 0 and 250),
  ambiguous_count integer not null check (ambiguous_count between 0 and 250),
  excluded_count integer not null check (excluded_count between 0 and 1000000),
  review_only boolean not null,
  created_at timestamptz not null default clock_timestamp(),
  unique(dealer_code,plan_hash),
  check (review_only=(mode='review'))
);

create table public.pdc_auditor_plan_items_225 (
  plan_item_id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.pdc_auditor_plans_225(plan_id) on delete restrict,
  sequence_no integer not null check (sequence_no between 1 and 250),
  disposition text not null check (disposition in ('proposed','ambiguous','excluded')),
  operation_action text not null check (operation_action in ('edit','delete','move')),
  vehicle_id uuid not null references public.vehicles(id) on delete restrict,
  stock_number text,
  job_card_number text,
  operation_line_id uuid not null references public.pdc_authenticated_email_operation_lines(operation_line_id) on delete restrict,
  matched_operation_line_id uuid references public.pdc_authenticated_email_operation_lines(operation_line_id) on delete restrict,
  old_value jsonb not null check (jsonb_typeof(old_value)='object' and octet_length(old_value::text)<=8192),
  new_value jsonb not null check (jsonb_typeof(new_value)='object' and octet_length(new_value::text)<=8192),
  match_kind text not null check (match_kind in (
    'same_vehicle_job_card_exact_code','same_vehicle_job_card_exact_description',
    'exact_gvm_mapping','exact_long_range_tank','exact_operation_line','exact_stock','review_category'
  )),
  match_reason text not null check (
    match_reason=btrim(match_reason) and length(match_reason) between 3 and 500
    and match_reason !~ '[[:cntrl:]]'
  ),
  source_evidence_hash text not null check (source_evidence_hash ~ '^[a-f0-9]{64}$'),
  exclusion_codes text[] not null default '{}'::text[],
  ambiguity_code text,
  created_at timestamptz not null default clock_timestamp(),
  unique(plan_id,sequence_no),
  unique(plan_id,operation_line_id),
  check ((disposition='ambiguous')=(ambiguity_code is not null)),
  check (ambiguity_code is null or ambiguity_code in (
    'multiple_duplicate_survivors','manual_or_completed_protected','quantity_or_variant_ambiguous',
    'mapping_not_exact','source_identity_ambiguous','target_value_missing'
  )),
  check (not (exclusion_codes && array[
    'kit','left','right','front','rear','quantity_gt_one','revised_source','manual_protected',
    'completed_protected','duplicated_source_evidence','tank_or_unrelated_hoist'
  ]::text[]) or disposition in ('ambiguous','excluded'))
);

create table public.pdc_auditor_review_queue_225 (
  review_queue_id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.pdc_auditor_plans_225(plan_id) on delete restrict,
  plan_item_id uuid not null unique references public.pdc_auditor_plan_items_225(plan_item_id) on delete restrict,
  queue_reason text not null check (queue_reason=btrim(queue_reason) and length(queue_reason) between 3 and 500),
  queue_state text not null check (queue_state='pending_review'),
  created_at timestamptz not null default clock_timestamp()
);

-- Defense in depth: all 225 state is RPC-only and append-only.
do $secure$
declare t text;
begin
  foreach t in array array[
    'pdc_auditor_service_identities_225','pdc_auditor_gvm_mappings_225',
    'pdc_auditor_telegram_instructions_225','pdc_auditor_plans_225',
    'pdc_auditor_plan_items_225','pdc_auditor_review_queue_225'
  ] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on table public.%I from public,anon,authenticated,service_role',t);
    execute format('create trigger %I before update or delete on public.%I for each row execute function public.pdc_auditor_reject_history_mutation()',t||'_immutable',t);
  end loop;
end
$secure$;

create function public.pdc_auditor_normalize_identity_225(p_value text)
returns text
language sql immutable security definer set search_path=pg_catalog,public
as $$
  select btrim(regexp_replace(lower(coalesce(p_value,'')),'[^a-z0-9]+',' ','g'))
$$;
revoke all on function public.pdc_auditor_normalize_identity_225(text) from public,anon,authenticated,service_role;

-- Exact service JWT UUID/email plus ordinary Viewer worker/dealer scope. No role claim,
-- caller-supplied UUID/email, service_role JWT, or dealer claim is accepted as authority.
create function public.pdc_auditor_telegram_actor_scope_225(p_telegram_sender_id bigint)
returns jsonb
language plpgsql stable security definer set search_path=pg_catalog,public,auth
as $scope$
declare
  v_uid uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_service public.pdc_auditor_service_identities_225%rowtype;
  v_admin uuid;
  v_admin_email text;
  v_count integer;
begin
  if v_uid is null or v_email='' or coalesce(auth.jwt()->>'role','')='service_role' then
    raise exception 'PDC_225_SERVICE_IDENTITY_REQUIRED' using errcode='42501';
  end if;
  select count(*) into v_count
  from public.pdc_auditor_service_identities_225 s
  join auth.users au on au.id=s.auth_user_id and lower(coalesce(au.email,''))=s.normalized_email
  join public.pdc_user_roles r on r.auth_user_id=s.auth_user_id
    and lower(r.email)=s.normalized_email and r.role::text='viewer'
    and r.active and r.account_status='approved'
  join public.pdc_user_roles approver on approver.auth_user_id=s.approved_by_user_id
    and approver.role::text='administrator' and approver.active and approver.account_status='approved'
  join auth.users approving_user on approving_user.id=s.approved_by_user_id
    and lower(coalesce(approving_user.email,''))=lower(approver.email)
  join public.pdc_auditor_worker_identities w on w.auth_user_id=s.auth_user_id
    and w.normalized_email=s.normalized_email and w.dealer_code=s.dealer_code
    and w.environment=s.environment and w.active
  join public.pdc_auditor_user_dealer_scopes d on d.auth_user_id=s.auth_user_id
    and d.normalized_email=s.normalized_email and d.dealer_code=s.dealer_code
    and d.environment=s.environment and d.active
  where s.auth_user_id=v_uid and s.normalized_email=v_email
    and s.environment='staging' and s.identity_purpose='ai_auditor_telegram_planner'
    and s.active and s.revoked_at is null;
  if v_count<>1 then
    raise exception 'PDC_225_SERVICE_IDENTITY_REQUIRED' using errcode='42501';
  end if;
  select * into strict v_service
  from public.pdc_auditor_service_identities_225 s
  where s.auth_user_id=v_uid and s.normalized_email=v_email
    and s.environment='staging' and s.identity_purpose='ai_auditor_telegram_planner'
    and s.active and s.revoked_at is null;

  select count(*),min(i.auth_user_id::text)::uuid,min(lower(i.actor_email))
    into v_count,v_admin,v_admin_email
  from public.pdc_supervised_telegram_identities i
  join auth.users au on au.id=i.auth_user_id and lower(coalesce(au.email,''))=lower(i.actor_email)
  join public.pdc_user_roles r on r.auth_user_id=i.auth_user_id
    and lower(r.email)=lower(i.actor_email) and r.role::text='administrator'
    and r.active and r.account_status='approved'
  where i.telegram_sender_id=p_telegram_sender_id and i.active
    and (p_telegram_sender_id=7828138290 or r.role::text='administrator');
  if v_count<>1 then
    raise exception 'PDC_225_TELEGRAM_ADMINISTRATOR_REQUIRED' using errcode='42501';
  end if;
  return jsonb_build_object(
    'service_identity_id',v_service.service_identity_id,
    'service_user_id',v_uid,'service_email',v_email,
    'admin_user_id',v_admin,'admin_email',v_admin_email,
    'dealer_code',v_service.dealer_code,'environment','staging'
  );
end
$scope$;
revoke all on function public.pdc_auditor_telegram_actor_scope_225(bigint) from public,anon,authenticated,service_role;

-- Validates immutable Telegram evidence and reserves exactly one instruction identity.
create function public.pdc_auditor_bind_instruction_225(
  p_action text,p_mode text,p_scope jsonb,p_telegram_evidence jsonb
)
returns uuid
language plpgsql security definer set search_path=pg_catalog,public,extensions
as $bind$
declare
  v_actor jsonb;
  v_instruction uuid;
  v_existing public.pdc_auditor_telegram_instructions_225%rowtype;
  v_sender bigint;
  v_chat bigint;
  v_message bigint;
  v_update bigint;
  v_text text;
  v_bot text;
  v_hash text;
begin
  if jsonb_typeof(p_scope) is distinct from 'object' or octet_length(p_scope::text)>8192
     or jsonb_typeof(p_telegram_evidence) is distinct from 'object'
     or (select array_agg(k order by k) from jsonb_object_keys(p_telegram_evidence) k)
       is distinct from array['bot_identity','instruction_sha256','original_instruction','telegram_chat_id','telegram_message_id','telegram_sender_id','telegram_update_id']::text[] then
    raise exception 'PDC_225_INVALID_TELEGRAM_EVIDENCE' using errcode='22023';
  end if;
  begin
    v_sender:=(p_telegram_evidence->>'telegram_sender_id')::bigint;
    v_chat:=(p_telegram_evidence->>'telegram_chat_id')::bigint;
    v_message:=(p_telegram_evidence->>'telegram_message_id')::bigint;
    v_update:=(p_telegram_evidence->>'telegram_update_id')::bigint;
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'PDC_225_INVALID_TELEGRAM_EVIDENCE' using errcode='22023';
  end;
  v_text:=p_telegram_evidence->>'original_instruction';
  v_bot:=p_telegram_evidence->>'bot_identity';
  v_hash:=lower(coalesce(p_telegram_evidence->>'instruction_sha256',''));
  if v_message<1 or v_update<0 or length(v_text) not between 3 and 4000
     or v_text<>btrim(v_text) or v_text~'[[:cntrl:]]'
     or length(v_bot) not between 3 and 160 or v_bot<>btrim(v_bot) or v_bot~'[[:cntrl:]]'
     or v_hash !~ '^[a-f0-9]{64}$'
     or v_hash<>encode(extensions.digest(convert_to(v_text,'UTF8'),'sha256'),'hex') then
    raise exception 'PDC_225_INVALID_TELEGRAM_EVIDENCE' using errcode='22023';
  end if;
  v_actor:=public.pdc_auditor_telegram_actor_scope_225(v_sender);
  perform pg_advisory_xact_lock(hashtextextended('pdc-225-telegram:'||v_chat||':'||v_message,0));
  select * into v_existing from public.pdc_auditor_telegram_instructions_225
  where telegram_chat_id=v_chat and telegram_message_id=v_message;
  if found then
    if v_existing.instruction_sha256<>v_hash
       or v_existing.original_instruction<>v_text
       or v_existing.telegram_sender_id<>v_sender
       or v_existing.telegram_update_id<>v_update
       or v_existing.bot_identity<>v_bot
       or v_existing.action<>p_action or v_existing.mode<>p_mode
       or v_existing.scope<>p_scope
       or v_existing.service_auth_user_id<>(v_actor->>'service_user_id')::uuid
       or v_existing.authorizing_admin_user_id<>(v_actor->>'admin_user_id')::uuid then
      raise exception 'PDC_225_TELEGRAM_MESSAGE_CONTENT_CONFLICT' using errcode='23505';
    end if;
    return v_existing.instruction_id;
  end if;
  if exists(select 1 from public.pdc_auditor_telegram_instructions_225
      where telegram_update_id=v_update and bot_identity=v_bot) then
    raise exception 'PDC_225_TELEGRAM_UPDATE_CONFLICT' using errcode='23505';
  end if;
  insert into public.pdc_auditor_telegram_instructions_225(
    telegram_sender_id,telegram_chat_id,telegram_message_id,telegram_update_id,
    bot_identity,original_instruction,instruction_sha256,action,mode,scope,
    service_identity_id,service_auth_user_id,service_email,
    authorizing_admin_user_id,authorizing_admin_email,dealer_code,environment
  ) values(
    v_sender,v_chat,v_message,v_update,v_bot,v_text,v_hash,p_action,p_mode,p_scope,
    (v_actor->>'service_identity_id')::uuid,(v_actor->>'service_user_id')::uuid,v_actor->>'service_email',
    (v_actor->>'admin_user_id')::uuid,v_actor->>'admin_email',v_actor->>'dealer_code','staging'
  ) returning instruction_id into v_instruction;
  return v_instruction;
end
$bind$;
revoke all on function public.pdc_auditor_bind_instruction_225(text,text,jsonb,jsonb) from public,anon,authenticated,service_role;

-- Server-owned candidate relation. Caller supplies only a bounded action/mode/scope;
-- operation IDs, old/new values, evidence, exclusions and ambiguity are derived here.
create function public.pdc_auditor_plan_candidates_225(
  p_dealer_code text,p_action text,p_scope jsonb
)
returns table(
  disposition text,operation_action text,vehicle_id uuid,stock_number text,
  job_card_number text,operation_line_id uuid,matched_operation_line_id uuid,
  old_value jsonb,new_value jsonb,match_kind text,match_reason text,
  source_evidence_hash text,exclusion_codes text[],ambiguity_code text
)
language sql stable security definer set search_path=pg_catalog,public,extensions
as $candidates$
with effective as materialized (
  select ol.operation_line_id,ol.vehicle_id,v.stock_number,
    coalesce(nullif(ol.job_card_number,''),nullif(v.job_card_number,''),'') job_card_number,
    coalesce(nullif(a.operation_code,''),nullif(ol.operation_no,''),'') operation_code,
    public.pdc_auditor_normalize_identity_225(coalesce(nullif(a.description,''),ol.description)) normalized_description,
    coalesce(nullif(public.pdc_auditor_work_key_for_stage(a.stage_code),''),ol.work_key) work_key,
    coalesce(a.estimated_hours,ol.estimated_hours) estimated_hours,
    ol.source_hash,ol.operation_fingerprint,
    coalesce(a.manual_assignment_locked,false) manual_locked,
    coalesce(a.active,true) active,
    coalesce(a.correction_origin,'') correction_origin,
    exists(select 1 from public.vehicle_work_items wi where wi.vehicle_id=ol.vehicle_id and wi.completed) completed_protected,
    (v.deleted_at is not null or v.lifecycle_state::text<>'active' or v.rft_collected_at is not null
      or upper(coalesce(v.current_location,''))='COMPLETED') vehicle_protected
  from public.pdc_authenticated_email_operation_lines ol
  join public.vehicles v on v.id=ol.vehicle_id
  left join public.vehicle_workshop_line_adjustments a
    on a.vehicle_id=ol.vehicle_id and a.line_key='source:'||ol.operation_line_id::text
  where public.pdc_auditor_vehicle_dealer(ol.vehicle_id)=p_dealer_code
), marked as (
  select e.*,
    array_remove(array[
      case when e.normalized_description~'(^| )kit( |$)' then 'kit' end,
      case when e.normalized_description~'(^| )left( |$)' then 'left' end,
      case when e.normalized_description~'(^| )right( |$)' then 'right' end,
      case when e.normalized_description~'(^| )front( |$)' then 'front' end,
      case when e.normalized_description~'(^| )rear( |$)' then 'rear' end,
      case when e.normalized_description~'(^| )((qty|quantity|x) *[2-9][0-9]*|pair|pairs|double|two|three|four)( |$)' then 'quantity_gt_one' end,
      case when e.normalized_description~'(^| )(revised|revision|superseded|updated source)( |$)' then 'revised_source' end,
      case when e.manual_locked or e.correction_origin not in ('','ai_auditor') then 'manual_protected' end,
      case when e.completed_protected or e.vehicle_protected then 'completed_protected' end
    ],null) exclusions
  from effective e
), bullbars as (
  select m.*,
    count(*) over(partition by vehicle_id,job_card_number,
      case when operation_code<>'' then operation_code||'|'||normalized_description else normalized_description end) duplicate_count,
    row_number() over(partition by vehicle_id,job_card_number,
      case when operation_code<>'' then operation_code||'|'||normalized_description else normalized_description end
      order by operation_line_id) duplicate_rank,
    first_value(operation_line_id) over(partition by vehicle_id,job_card_number,
      case when operation_code<>'' then operation_code||'|'||normalized_description else normalized_description end
      order by operation_line_id) survivor_id,
    min(source_hash) over(partition by vehicle_id,job_card_number,
      case when operation_code<>'' then operation_code||'|'||normalized_description else normalized_description end) min_source_hash,
    max(source_hash) over(partition by vehicle_id,job_card_number,
      case when operation_code<>'' then operation_code||'|'||normalized_description else normalized_description end) max_source_hash
  from marked m
  where m.normalized_description~'(^| )(bullbar|bull bar)( |$)'
), selected as (
  -- Duplicate bullbars: retain one deterministic source line and propose deleting only
  -- later lines where same vehicle+JC and exact code (when present) or exact description agree.
  select
    case when b.exclusions<>'{}'::text[] or b.min_source_hash<>b.max_source_hash then 'ambiguous' else 'proposed' end disposition,
    'delete' operation_action,b.vehicle_id,b.stock_number,b.job_card_number,b.operation_line_id,
    b.survivor_id matched_operation_line_id,
    jsonb_build_object('active',b.active,'operation_code',nullif(b.operation_code,''),
      'normalized_description',b.normalized_description,'work_key',b.work_key,
      'estimated_hours',b.estimated_hours) old_value,
    jsonb_build_object('active',false,'operation_code',nullif(b.operation_code,''),
      'normalized_description',b.normalized_description,'work_key',b.work_key,
      'estimated_hours',b.estimated_hours) new_value,
    case when b.operation_code<>'' then 'same_vehicle_job_card_exact_code'
      else 'same_vehicle_job_card_exact_description' end match_kind,
    case when b.operation_code<>'' then 'Same vehicle and job card with identical normalized operation code and equivalent bullbar identity.'
      else 'Same vehicle and job card with equivalent normalized bullbar description/accessory identity.' end match_reason,
    encode(extensions.digest(convert_to(concat_ws('|',b.operation_line_id,b.source_hash,b.operation_fingerprint,b.vehicle_id,b.job_card_number,b.operation_code,b.normalized_description),'UTF8'),'sha256'),'hex') source_evidence_hash,
    b.exclusions||case when b.min_source_hash<>b.max_source_hash then array['duplicated_source_evidence']::text[] else '{}'::text[] end exclusion_codes,
    case when b.exclusions<>'{}'::text[] then 'quantity_or_variant_ambiguous'
      when b.min_source_hash<>b.max_source_hash then 'source_identity_ambiguous' end ambiguity_code
  from bullbars b
  where p_action='duplicate_bullbars' and b.duplicate_count>1 and b.duplicate_rank>1

  union all
  -- GVM is exact allowlist only: exact category + exact operation code + exact normalized description.
  select
    case when m.exclusions<>'{}'::text[] then 'ambiguous' else 'proposed' end,
    'edit',m.vehicle_id,m.stock_number,m.job_card_number,m.operation_line_id,null,
    jsonb_build_object('work_key',m.work_key,'estimated_hours',m.estimated_hours,
      'operation_code',m.operation_code,'normalized_description',m.normalized_description),
    jsonb_build_object('work_key','hoist','estimated_hours',coalesce((p_scope->>'estimated_hours')::numeric,m.estimated_hours),
      'operation_code',m.operation_code,'normalized_description',m.normalized_description),
    'exact_gvm_mapping','Exact server-approved genuine GVM category, operation code and normalized description mapping.',
    encode(extensions.digest(convert_to(concat_ws('|',m.operation_line_id,m.source_hash,m.operation_fingerprint,g.mapping_id),'UTF8'),'sha256'),'hex'),
    m.exclusions,'manual_or_completed_protected'
  from marked m
  join public.pdc_auditor_gvm_mappings_225 g
    on g.dealer_code=p_dealer_code and g.environment='staging' and g.active and g.revoked_at is null
   and g.category='genuine_gvm_upgrade' and g.exact_operation_code=upper(m.operation_code)
   and g.exact_normalized_description=m.normalized_description
  where p_action='gvm_hours'
    and m.normalized_description~'(^| )(gvm|gross vehicle mass)( |$)'
    and m.normalized_description!~'(^| )(tank|fuel|long range)( |$)'

  union all
  -- GVM-like rows without an exact approved code+description pair remain visible but
  -- excluded.  They cannot silently broaden a batch and do not block exact matches.
  select
    'excluded','edit',m.vehicle_id,m.stock_number,m.job_card_number,m.operation_line_id,null,
    jsonb_build_object('work_key',m.work_key,'estimated_hours',m.estimated_hours,
      'operation_code',m.operation_code,'normalized_description',m.normalized_description),
    jsonb_build_object('work_key',m.work_key,'estimated_hours',m.estimated_hours,
      'operation_code',m.operation_code,'normalized_description',m.normalized_description),
    'review_category','GVM-like wording is not an exact active approved operation-code and normalized-description mapping.',
    encode(extensions.digest(convert_to(concat_ws('|',m.operation_line_id,m.source_hash,m.operation_fingerprint),'UTF8'),'sha256'),'hex'),
    m.exclusions||array['mapping_not_exact']::text[],null
  from marked m
  where p_action='gvm_hours'
    and m.normalized_description~'(^| )(gvm|gross vehicle mass)( |$)'
    and not exists (
      select 1 from public.pdc_auditor_gvm_mappings_225 g
      where g.dealer_code=p_dealer_code and g.environment='staging'
        and g.active and g.revoked_at is null and g.category='genuine_gvm_upgrade'
        and g.exact_operation_code=upper(m.operation_code)
        and g.exact_normalized_description=m.normalized_description
    )

  union all
  -- The GVM-hours report explicitly proves long-range tanks are excluded and retain
  -- their own values; these rows can never become proposed mutations in this action.
  select
    'excluded','edit',m.vehicle_id,m.stock_number,m.job_card_number,m.operation_line_id,null,
    jsonb_build_object('work_key',m.work_key,'estimated_hours',m.estimated_hours,
      'operation_code',nullif(m.operation_code,''),'normalized_description',m.normalized_description),
    jsonb_build_object('work_key',m.work_key,'estimated_hours',m.estimated_hours,
      'operation_code',nullif(m.operation_code,''),'normalized_description',m.normalized_description),
    'review_category','Long-range fuel tank is explicitly excluded from genuine GVM-upgrade hours.',
    encode(extensions.digest(convert_to(concat_ws('|',m.operation_line_id,m.source_hash,m.operation_fingerprint),'UTF8'),'sha256'),'hex'),
    m.exclusions||array['tank_or_unrelated_hoist']::text[],null
  from marked m
  where p_action='gvm_hours'
    and m.normalized_description~'(^| )long range( fuel)? tank(s)?( |$)'

  union all
  select
    case when m.exclusions<>'{}'::text[] then 'ambiguous' else 'proposed' end,
    'move',m.vehicle_id,m.stock_number,m.job_card_number,m.operation_line_id,null,
    jsonb_build_object('work_key',m.work_key,'estimated_hours',m.estimated_hours,
      'operation_code',nullif(m.operation_code,''),'normalized_description',m.normalized_description),
    jsonb_build_object('work_key','hoist','estimated_hours',m.estimated_hours,
      'operation_code',nullif(m.operation_code,''),'normalized_description',m.normalized_description),
    'exact_long_range_tank','Exact normalized long-range fuel tank identity; separate from genuine GVM mapping.',
    encode(extensions.digest(convert_to(concat_ws('|',m.operation_line_id,m.source_hash,m.operation_fingerprint),'UTF8'),'sha256'),'hex'),
    m.exclusions,'manual_or_completed_protected'
  from marked m
  where p_action='long_range_tank_department'
    and m.normalized_description~'(^| )long range( fuel)? tank(s)?( |$)'
    and m.normalized_description!~'(^| )(gvm|gross vehicle mass)( |$)'

  union all
  select
    case when m.exclusions<>'{}'::text[] then 'ambiguous' else 'proposed' end,
    'edit',m.vehicle_id,m.stock_number,m.job_card_number,m.operation_line_id,null,
    jsonb_build_object('work_key',m.work_key,'estimated_hours',m.estimated_hours,
      'operation_code',nullif(m.operation_code,''),'normalized_description',m.normalized_description),
    jsonb_build_object('work_key',m.work_key,'estimated_hours',(p_scope->>'estimated_hours')::numeric,
      'operation_code',nullif(m.operation_code,''),'normalized_description',m.normalized_description),
    'exact_stock','Exact normalized stock number with server-resolved operation line.',
    encode(extensions.digest(convert_to(concat_ws('|',m.operation_line_id,m.source_hash,m.operation_fingerprint),'UTF8'),'sha256'),'hex'),
    m.exclusions,'manual_or_completed_protected'
  from marked m
  where p_action='stock_hours'
    and public.normalize_vehicle_stock_number(m.stock_number)=public.normalize_vehicle_stock_number(p_scope->>'stock_number')

  union all
  select
    case when m.exclusions<>'{}'::text[] then 'ambiguous' else 'proposed' end,
    'move',m.vehicle_id,m.stock_number,m.job_card_number,m.operation_line_id,null,
    jsonb_build_object('work_key',m.work_key,'estimated_hours',m.estimated_hours,
      'operation_code',nullif(m.operation_code,''),'normalized_description',m.normalized_description),
    jsonb_build_object('work_key',p_scope->>'work_key','estimated_hours',m.estimated_hours,
      'operation_code',nullif(m.operation_code,''),'normalized_description',m.normalized_description),
    'exact_operation_line','Exact immutable operation_line_id supplied as Telegram reply context; target is a bounded work key.',
    encode(extensions.digest(convert_to(concat_ws('|',m.operation_line_id,m.source_hash,m.operation_fingerprint),'UTF8'),'sha256'),'hex'),
    m.exclusions,'manual_or_completed_protected'
  from marked m
  where p_action='line_department' and m.operation_line_id=(p_scope->>'operation_line_id')::uuid

  union all
  select
    case when m.exclusions<>'{}'::text[] then 'ambiguous' else 'proposed' end,
    'edit',m.vehicle_id,m.stock_number,m.job_card_number,m.operation_line_id,null,
    jsonb_build_object('work_key',m.work_key,'estimated_hours',m.estimated_hours,
      'operation_code',nullif(m.operation_code,''),'normalized_description',m.normalized_description),
    jsonb_build_object('work_key',m.work_key,'estimated_hours',m.estimated_hours,
      'operation_code',nullif(m.operation_code,''),'normalized_description',m.normalized_description),
    'review_category','Read/review candidate only; old and new values are identical and cannot mutate operational state.',
    encode(extensions.digest(convert_to(concat_ws('|',m.operation_line_id,m.source_hash,m.operation_fingerprint),'UTF8'),'sha256'),'hex'),
    m.exclusions,'manual_or_completed_protected'
  from marked m
  where p_action='review_category'
    and p_scope->>'category' in ('tint')
    and m.normalized_description~'(^| )(window )?tint(ing)?( |$)'
), bounded as (
  select * from selected
  order by vehicle_id,job_card_number,operation_line_id
  limit 250
)
select disposition,operation_action,vehicle_id,stock_number,job_card_number,
  operation_line_id,matched_operation_line_id,old_value,new_value,match_kind,match_reason,
  source_evidence_hash,exclusion_codes,
  case when disposition='ambiguous' then ambiguity_code else null end
from bounded
$candidates$;
revoke all on function public.pdc_auditor_plan_candidates_225(text,text,jsonb) from public,anon,authenticated,service_role;

create function public.plan_pdc_auditor_telegram_instruction_225(
  p_action text,p_mode text,p_scope jsonb,p_telegram_evidence jsonb
)
returns jsonb
language plpgsql security definer set search_path=pg_catalog,public,extensions
as $plan$
declare
  v_instruction uuid;
  v_bound public.pdc_auditor_telegram_instructions_225%rowtype;
  v_existing public.pdc_auditor_plans_225%rowtype;
  v_plan uuid:=gen_random_uuid();
  v_revision text;
  v_canonical text;
  v_plan_hash text;
  v_item record;
  v_seq integer:=0;
  v_ambiguous integer:=0;
  v_excluded integer:=0;
  v_response_items jsonb;
begin
  if p_action not in ('duplicate_bullbars','gvm_hours','long_range_tank_department',
      'review_category','stock_hours','line_department','apply_matching')
     or p_mode not in ('review','apply')
     or jsonb_typeof(p_scope) is distinct from 'object'
     or octet_length(p_scope::text)>8192 then
    raise exception 'PDC_225_INVALID_PLAN_REQUEST' using errcode='22023';
  end if;
  -- Review verbs can create immutable review evidence only; they can never create an apply plan.
  if p_action='review_category' and p_mode<>'review' then
    raise exception 'PDC_225_REVIEW_VERB_CANNOT_APPLY' using errcode='42501';
  end if;
  if p_action='duplicate_bullbars' and p_scope<>jsonb_build_object('category','bullbar','confirmed_only',p_mode<>'review') then
    raise exception 'PDC_225_INVALID_DUPLICATE_SCOPE' using errcode='22023';
  elsif p_action='gvm_hours' and (
      p_scope->>'category'<>'gvm_upgrade'
      or (p_mode='review' and (select array_agg(k order by k) from jsonb_object_keys(p_scope) k)
        is distinct from array['category']::text[])
      or (p_mode='apply' and ((select array_agg(k order by k) from jsonb_object_keys(p_scope) k)
        is distinct from array['category','estimated_hours']::text[]
        or jsonb_typeof(p_scope->'estimated_hours')<>'number'
        or (p_scope->>'estimated_hours')::numeric not between 0.25 and 999.75
        or mod((p_scope->>'estimated_hours')::numeric,0.25)<>0))
    ) then raise exception 'PDC_225_INVALID_GVM_SCOPE' using errcode='22023';
  elsif p_action='long_range_tank_department' and p_scope<>jsonb_build_object('category','long_range_fuel_tank','work_key','hoist') then
    raise exception 'PDC_225_INVALID_TANK_SCOPE' using errcode='22023';
  elsif p_action='review_category' and p_scope<>jsonb_build_object('category','tint') then
    raise exception 'PDC_225_INVALID_REVIEW_SCOPE' using errcode='22023';
  elsif p_action='stock_hours' and (
      (select array_agg(k order by k) from jsonb_object_keys(p_scope) k)
        is distinct from array['estimated_hours','stock_number']::text[]
      or coalesce(p_scope->>'stock_number','')!~'^[0-9]{4,20}$'
      or jsonb_typeof(p_scope->'estimated_hours')<>'number'
      or (p_scope->>'estimated_hours')::numeric not between 0.25 and 999.75
      or mod((p_scope->>'estimated_hours')::numeric,0.25)<>0
    ) then raise exception 'PDC_225_INVALID_STOCK_SCOPE' using errcode='22023';
  elsif p_action='line_department' and (
      (select array_agg(k order by k) from jsonb_object_keys(p_scope) k)
        is distinct from array['operation_line_id','work_key']::text[]
      or coalesce(p_scope->>'operation_line_id','')!~'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      or p_scope->>'work_key' not in ('fitting','tint','hoist','electrical','fabrication','tyre','pitInspection')
    ) then raise exception 'PDC_225_INVALID_LINE_SCOPE' using errcode='22023';
  elsif p_action='apply_matching' then
    -- 225 deliberately does not expand a prior reviewed correction into mutation scope.
    raise exception 'PDC_225_APPLY_MATCHING_REQUIRES_226' using errcode='0A000';
  end if;

  v_instruction:=public.pdc_auditor_bind_instruction_225(p_action,p_mode,p_scope,p_telegram_evidence);
  select * into strict v_bound from public.pdc_auditor_telegram_instructions_225 where instruction_id=v_instruction;
  select * into v_existing from public.pdc_auditor_plans_225 where instruction_id=v_instruction;
  if found then
    select coalesce(jsonb_agg(jsonb_build_object(
      'sequence_no',i.sequence_no,'disposition',i.disposition,'operation_action',i.operation_action,
      'vehicle_id',i.vehicle_id,'stock_number',i.stock_number,'job_card_number',i.job_card_number,
      'operation_line_id',i.operation_line_id,'matched_operation_line_id',i.matched_operation_line_id,
      'old_value',i.old_value,'new_value',i.new_value,'match_kind',i.match_kind,
      'match_reason',i.match_reason,'source_evidence_hash',i.source_evidence_hash,
      'exclusion_codes',to_jsonb(i.exclusion_codes),'ambiguity_code',i.ambiguity_code
    ) order by i.sequence_no),'[]'::jsonb) into v_response_items
    from public.pdc_auditor_plan_items_225 i where i.plan_id=v_existing.plan_id;
    return jsonb_build_object('ok',true,'code','exact_plan_replay','data',jsonb_build_object(
      'plan_id',v_existing.plan_id,'plan_hash',v_existing.plan_hash,
      'operational_revision',v_existing.operational_revision,'mode',v_existing.mode,
      'item_count',v_existing.item_count,'ambiguous_count',v_existing.ambiguous_count,
      'excluded_count',v_existing.excluded_count,'review_only',v_existing.review_only,
      'items',v_response_items));
  end if;

  perform pg_advisory_xact_lock(hashtextextended('pdc-225-plan:'||v_bound.dealer_code,0));
  v_revision:=public.pdc_auditor_operational_revision(v_bound.dealer_code);
  create temporary table if not exists pg_temp.pdc_225_candidates(
    disposition text,operation_action text,vehicle_id uuid,stock_number text,
    job_card_number text,operation_line_id uuid,matched_operation_line_id uuid,
    old_value jsonb,new_value jsonb,match_kind text,match_reason text,
    source_evidence_hash text,exclusion_codes text[],ambiguity_code text
  ) on commit drop;
  truncate pg_temp.pdc_225_candidates;
  insert into pg_temp.pdc_225_candidates
    select * from public.pdc_auditor_plan_candidates_225(v_bound.dealer_code,p_action,p_scope);
  select count(*) filter(where disposition='ambiguous'),count(*) filter(where disposition='excluded')
    into v_ambiguous,v_excluded from pg_temp.pdc_225_candidates;
  select coalesce(string_agg(concat_ws('|',disposition,operation_action,vehicle_id,coalesce(stock_number,''),
      coalesce(job_card_number,''),operation_line_id,coalesce(matched_operation_line_id::text,''),
      old_value::text,new_value::text,match_kind,match_reason,source_evidence_hash,
      array_to_string(exclusion_codes,','),coalesce(ambiguity_code,'')),';' order by vehicle_id,job_card_number,operation_line_id),'')
    into v_canonical from pg_temp.pdc_225_candidates;
  v_plan_hash:=encode(extensions.digest(convert_to(concat_ws('|',
    'ai_auditor_telegram_plan_225_v1',v_instruction,p_action,p_mode,p_scope::text,
    v_bound.instruction_sha256,v_bound.dealer_code,v_revision,v_canonical),'UTF8'),'sha256'),'hex');
  insert into public.pdc_auditor_plans_225(
    plan_id,instruction_id,action,mode,dealer_code,environment,operational_revision,
    plan_hash,planner_contract,item_count,ambiguous_count,excluded_count,review_only
  ) values(v_plan,v_instruction,p_action,p_mode,v_bound.dealer_code,'staging',v_revision,
    v_plan_hash,'ai_auditor_telegram_plan_225_v1',
    (select count(*) from pg_temp.pdc_225_candidates),v_ambiguous,v_excluded,p_mode='review');
  for v_item in select * from pg_temp.pdc_225_candidates order by vehicle_id,job_card_number,operation_line_id loop
    v_seq:=v_seq+1;
    insert into public.pdc_auditor_plan_items_225(
      plan_id,sequence_no,disposition,operation_action,vehicle_id,stock_number,job_card_number,
      operation_line_id,matched_operation_line_id,old_value,new_value,match_kind,match_reason,
      source_evidence_hash,exclusion_codes,ambiguity_code
    ) values(v_plan,v_seq,v_item.disposition,v_item.operation_action,v_item.vehicle_id,
      v_item.stock_number,v_item.job_card_number,v_item.operation_line_id,
      v_item.matched_operation_line_id,v_item.old_value,v_item.new_value,v_item.match_kind,
      v_item.match_reason,v_item.source_evidence_hash,v_item.exclusion_codes,
      case when v_item.disposition='ambiguous' then v_item.ambiguity_code end);
  end loop;
  insert into public.pdc_auditor_review_queue_225(plan_id,plan_item_id,queue_reason,queue_state)
  select i.plan_id,i.plan_item_id,
    case when i.ambiguity_code is not null then 'Ambiguous: '||i.ambiguity_code
      else 'Review-only Telegram instruction; no operational mutation is authorized.' end,
    'pending_review'
  from public.pdc_auditor_plan_items_225 i
  where i.plan_id=v_plan and (p_mode='review' or i.disposition='ambiguous');
  select coalesce(jsonb_agg(jsonb_build_object(
    'sequence_no',i.sequence_no,'disposition',i.disposition,'operation_action',i.operation_action,
    'vehicle_id',i.vehicle_id,'stock_number',i.stock_number,'job_card_number',i.job_card_number,
    'operation_line_id',i.operation_line_id,'matched_operation_line_id',i.matched_operation_line_id,
    'old_value',i.old_value,'new_value',i.new_value,'match_kind',i.match_kind,
    'match_reason',i.match_reason,'source_evidence_hash',i.source_evidence_hash,
    'exclusion_codes',to_jsonb(i.exclusion_codes),'ambiguity_code',i.ambiguity_code
  ) order by i.sequence_no),'[]'::jsonb) into v_response_items
  from public.pdc_auditor_plan_items_225 i where i.plan_id=v_plan;
  return jsonb_build_object('ok',true,'code',case when p_mode='review' then 'review_plan_created' else 'apply_plan_created' end,
    'data',jsonb_build_object('plan_id',v_plan,'plan_hash',v_plan_hash,
      'operational_revision',v_revision,'mode',p_mode,'item_count',v_seq,
      'ambiguous_count',v_ambiguous,'excluded_count',v_excluded,'review_only',p_mode='review',
      'apply_available',false,'items',v_response_items,
      'forbidden_mutations',jsonb_build_array('bookings','location','status','completion','users')));
end
$plan$;
revoke all on function public.plan_pdc_auditor_telegram_instruction_225(text,text,jsonb,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.plan_pdc_auditor_telegram_instruction_225(text,text,jsonb,jsonb) to authenticated;

create function public.query_pdc_auditor_telegram_225(
  p_action text,p_scope jsonb,p_telegram_evidence jsonb
)
returns jsonb
language plpgsql security definer set search_path=pg_catalog,public
as $query$
declare
  v_instruction uuid;
  v_bound public.pdc_auditor_telegram_instructions_225%rowtype;
  v_data jsonb;
begin
  if p_action not in ('show_rules','explain_line') or jsonb_typeof(p_scope) is distinct from 'object' then
    raise exception 'PDC_225_INVALID_QUERY' using errcode='22023';
  end if;
  if p_action='show_rules' and p_scope<>'{}'::jsonb then
    raise exception 'PDC_225_INVALID_QUERY_SCOPE' using errcode='22023';
  elsif p_action='explain_line' and (
      (select array_agg(k order by k) from jsonb_object_keys(p_scope) k) is distinct from array['operation_line_id']::text[]
      or coalesce(p_scope->>'operation_line_id','')!~'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    ) then raise exception 'PDC_225_INVALID_QUERY_SCOPE' using errcode='22023';
  end if;
  v_instruction:=public.pdc_auditor_bind_instruction_225(p_action,'query',p_scope,p_telegram_evidence);
  select * into strict v_bound from public.pdc_auditor_telegram_instructions_225 where instruction_id=v_instruction;
  if p_action='show_rules' then
    select jsonb_build_object(
      'gvm_exact_mapping_count',count(*),
      'gvm_policy','Exact active server-approved operation code + normalized description + genuine_gvm_upgrade category only; tanks and generic hoist excluded.',
      'duplicate_bullbar_policy','Same vehicle and job card; exact normalized code when present, otherwise equivalent normalized description; variants, quantity, revised evidence, completed and manual rows require review.',
      'apply_available',false
    ) into v_data
    from public.pdc_auditor_gvm_mappings_225 g
    where g.dealer_code=v_bound.dealer_code and g.environment='staging' and g.active and g.revoked_at is null;
  else
    select jsonb_build_object(
      'operation_line_id',e.operation_line_id,'vehicle_id',e.vehicle_id,
      'stock_number',e.stock_number,'job_card_number',e.job_card_number,
      'operation_code',e.operation_code,'work_key',e.work_key,
      'normalized_description',public.pdc_auditor_normalize_identity_225(e.description),
      'estimated_hours',e.estimated_hours,'estimated_hours_source',e.estimated_hours_source,
      'source_hash',e.source_hash,'operation_fingerprint',e.operation_fingerprint,
      'manual_protected',coalesce(a.manual_assignment_locked,false),
      'completed_protected',exists(select 1 from public.vehicle_work_items wi where wi.vehicle_id=e.vehicle_id and wi.completed),
      'precedence','manual/completed protection > exact operation code > exact normalized description > approved category mapping > review',
      'apply_available',false
    ) into v_data
    from public.pdc_authenticated_email_operation_lines e
    join public.vehicles v on v.id=e.vehicle_id
    left join public.vehicle_workshop_line_adjustments a
      on a.vehicle_id=e.vehicle_id and a.line_key='source:'||e.operation_line_id::text
    where e.operation_line_id=(p_scope->>'operation_line_id')::uuid
      and public.pdc_auditor_vehicle_dealer(e.vehicle_id)=v_bound.dealer_code;
    if v_data is null then
      return jsonb_build_object('ok',false,'code','operation_line_not_found','data',null);
    end if;
  end if;
  return jsonb_build_object('ok',true,'code',case when p_action='show_rules' then 'auditor_rules' else 'operation_line_explained' end,'data',v_data);
end
$query$;
revoke all on function public.query_pdc_auditor_telegram_225(text,jsonb,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.query_pdc_auditor_telegram_225(text,jsonb,jsonb) to authenticated;

-- Remove authenticated access to legacy arbitrary client-supplied review/apply/rollback surfaces.
-- The functions remain for historical compatibility, but cannot be invoked by API users.
do $legacy_acl$
declare r record;
begin
  for r in
    select p.oid::regprocedure sig
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in (
      'review_pdc_auditor_operation_batch','apply_pdc_auditor_operation_batch',
      'rollback_pdc_auditor_operation_run','execute_pdc_auditor_autonomous_corrections',
      'rollback_pdc_auditor_autonomous_correction'
    )
  loop
    execute format('revoke execute on function %s from public,anon,authenticated,service_role',r.sig);
  end loop;
end
$legacy_acl$;

comment on function public.plan_pdc_auditor_telegram_instruction_225(text,text,jsonb,jsonb) is
  'Staging-only typed Telegram planner. Server derives immutable, revision-bound operation IDs, old/new values, match evidence, exclusions, ambiguity and plan hash. No apply or operational mutation.';
comment on function public.query_pdc_auditor_telegram_225(text,jsonb,jsonb) is
  'Staging-only Telegram-bound query for bounded rule summary and exact scoped operation-line explanation; no operational mutation.';

insert into supabase_migrations.schema_migrations(version,name,statements) values(
  '225','ai_auditor_telegram_plans',array[
    'ordinary authenticated scoped AI Auditor service identity with exact JWT UUID and email binding; no service_role',
    'approved Administrator Telegram identity binding including Craig sender 7828138290 and immutable exactly-once message content',
    'server-derived immutable operational-revision plans and items with exact IDs old/new values match reasons exclusions ambiguity and SHA-256 plan hash',
    'deterministic duplicate bullbar safeguards and exact allowlisted genuine GVM mapping excluding tanks and unrelated hoist work',
    'review queue and review/query verbs with no operational mutation; bookings location status completion and users forbidden',
    'no direct table grants; authenticated EXECUTE only on typed planner and query; legacy arbitrary client mutation RPC access revoked',
    'apply deliberately absent until migration 226'
  ]
);
notify pgrst,'reload schema';
commit;
