-- Staging-only migration 226: atomic application and safe append-only undo of immutable 225 plans.
-- Only operation-line adjustment overlays and derived required-work projection may change.
begin;
set local lock_timeout='10s';
set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-226-ai-auditor-atomic-apply-undo',0));

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
       select 1 from supabase_migrations.schema_migrations
       where version='225' and name='ai_auditor_telegram_plans'
     )
     or exists (
       select 1 from supabase_migrations.schema_migrations
       where version ~ '^[0-9]+$' and version::integer>225
     )
     or exists (
       select 1 from supabase_migrations.schema_migrations where version='226'
     ) then
    raise exception 'PDC_226_STAGING_OR_LEDGER_MISMATCH' using errcode='55000';
  end if;
  if to_regclass('public.pdc_auditor_service_identities_225') is null
     or to_regclass('public.pdc_auditor_telegram_instructions_225') is null
     or to_regclass('public.pdc_auditor_plans_225') is null
     or to_regclass('public.pdc_auditor_plan_items_225') is null
     or to_regclass('public.pdc_auditor_review_queue_225') is null
     or to_regclass('public.pdc_authenticated_email_operation_lines') is null
     or to_regclass('public.vehicle_workshop_line_adjustments') is null
     or to_regclass('public.vehicle_work_items') is null
     or to_regclass('public.pdc_effective_operation_lines') is null
     or to_regclass('public.audit_events') is null
     or to_regprocedure('public.pdc_auditor_telegram_actor_scope_225(bigint)') is null
     or to_regprocedure('public.pdc_auditor_plan_candidates_225(text,text,jsonb)') is null
     or to_regprocedure('public.pdc_auditor_operational_revision(text)') is null
     or to_regprocedure('public.pdc_auditor_vehicle_dealer(uuid)') is null
     or to_regprocedure('public.pdc_auditor_reject_history_mutation()') is null
     or to_regprocedure('public.workshop_stage_code_for_work_key(text)') is null then
    raise exception 'PDC_226_DEPENDENCY_MISSING' using errcode='55000';
  end if;
end
$guard$;

-- A run is an immutable consumption of one immutable plan. A plan can be consumed once.
create table public.pdc_auditor_telegram_runs_226 (
  run_id uuid primary key default gen_random_uuid(),
  plan_id uuid not null unique references public.pdc_auditor_plans_225(plan_id) on delete restrict,
  plan_hash text not null check (plan_hash ~ '^[a-f0-9]{64}$'),
  dealer_code text not null check (dealer_code in ('14450','37047')),
  environment text not null check (environment='staging'),
  service_identity_id uuid not null references public.pdc_auditor_service_identities_225(service_identity_id) on delete restrict,
  service_auth_user_id uuid not null references auth.users(id) on delete restrict,
  service_email text not null,
  authorizing_admin_user_id uuid not null references auth.users(id) on delete restrict,
  authorizing_admin_email text not null,
  exact_instruction text not null check (length(exact_instruction) between 3 and 4000),
  instruction_sha256 text not null check (instruction_sha256 ~ '^[a-f0-9]{64}$'),
  operational_revision_before text not null check (operational_revision_before ~ '^[a-f0-9]{64}$'),
  proposed_count integer not null check (proposed_count between 0 and 250),
  ambiguous_count integer not null check (ambiguous_count between 0 and 250),
  applied_count integer not null check (applied_count between 0 and 250),
  result_code text not null check (result_code in ('applied','no_proposed_changes')),
  applied_at timestamptz not null default clock_timestamp(),
  check (applied_count=proposed_count)
);

-- One row per proposed change, retaining exact plan evidence and logical before/after overlay state.
create table public.pdc_auditor_telegram_changes_226 (
  change_id uuid primary key default gen_random_uuid(),
  run_id uuid not null references public.pdc_auditor_telegram_runs_226(run_id) on delete restrict,
  plan_item_id uuid not null references public.pdc_auditor_plan_items_225(plan_item_id) on delete restrict,
  sequence_no integer not null check (sequence_no between 1 and 250),
  operation_action text not null check (operation_action in ('edit','delete','move')),
  operation_line_id uuid not null references public.pdc_authenticated_email_operation_lines(operation_line_id) on delete restrict,
  retained_operation_line_id uuid references public.pdc_authenticated_email_operation_lines(operation_line_id) on delete restrict,
  superseded_operation_line_id uuid references public.pdc_authenticated_email_operation_lines(operation_line_id) on delete restrict,
  vehicle_id uuid not null references public.vehicles(id) on delete restrict,
  adjustment_id uuid not null references public.vehicle_workshop_line_adjustments(adjustment_id) on delete restrict,
  before_value jsonb,
  after_value jsonb not null check (jsonb_typeof(after_value)='object'),
  source_evidence_hash text not null check (source_evidence_hash ~ '^[a-f0-9]{64}$'),
  exact_instruction text not null,
  rule_version_id uuid,
  changed_at timestamptz not null default clock_timestamp(),
  unique(run_id,sequence_no),
  unique(run_id,operation_line_id),
  unique(plan_item_id),
  check ((operation_action='delete' and retained_operation_line_id is not null
          and superseded_operation_line_id=operation_line_id)
         or (operation_action in ('edit','move') and retained_operation_line_id is null
          and superseded_operation_line_id is null))
);

-- The apply receipt binds the plan to exact Telegram delivery/content and stores the replay result.
create table public.pdc_auditor_telegram_apply_receipts_226 (
  receipt_id uuid primary key default gen_random_uuid(),
  run_id uuid not null unique references public.pdc_auditor_telegram_runs_226(run_id) on delete restrict,
  plan_id uuid not null unique references public.pdc_auditor_plans_225(plan_id) on delete restrict,
  telegram_sender_id bigint not null,
  telegram_chat_id bigint not null,
  telegram_message_id bigint not null check (telegram_message_id>0),
  telegram_update_id bigint not null check (telegram_update_id>=0),
  bot_identity text not null,
  exact_instruction text not null,
  instruction_sha256 text not null check (instruction_sha256 ~ '^[a-f0-9]{64}$'),
  request_content_hash text not null check (request_content_hash ~ '^[a-f0-9]{64}$'),
  response jsonb not null check (jsonb_typeof(response)='object'),
  created_at timestamptz not null default clock_timestamp(),
  unique(telegram_chat_id,telegram_message_id),
  unique(telegram_update_id,bot_identity)
);

-- A rollback receipt consumes a new exact Telegram delivery and identifies the server-resolved run.
create table public.pdc_auditor_telegram_rollback_receipts_226 (
  rollback_receipt_id uuid primary key default gen_random_uuid(),
  run_id uuid not null unique references public.pdc_auditor_telegram_runs_226(run_id) on delete restrict,
  dealer_code text not null check (dealer_code in ('14450','37047')),
  service_identity_id uuid not null references public.pdc_auditor_service_identities_225(service_identity_id) on delete restrict,
  authorizing_admin_user_id uuid not null references auth.users(id) on delete restrict,
  telegram_sender_id bigint not null,
  telegram_chat_id bigint not null,
  telegram_message_id bigint not null check (telegram_message_id>0),
  telegram_update_id bigint not null check (telegram_update_id>=0),
  bot_identity text not null,
  exact_instruction text not null check (length(exact_instruction) between 3 and 4000),
  instruction_sha256 text not null check (instruction_sha256 ~ '^[a-f0-9]{64}$'),
  request_content_hash text not null check (request_content_hash ~ '^[a-f0-9]{64}$'),
  restored_count integer not null check (restored_count between 0 and 250),
  conflict_count integer not null check (conflict_count between 0 and 250),
  response jsonb not null check (jsonb_typeof(response)='object'),
  rolled_back_at timestamptz not null default clock_timestamp(),
  unique(telegram_chat_id,telegram_message_id),
  unique(telegram_update_id,bot_identity)
);

-- Per-change rollback evidence is retained even when a later protected/manual change is preserved.
create table public.pdc_auditor_telegram_rollback_audit_226 (
  rollback_audit_id uuid primary key default gen_random_uuid(),
  rollback_receipt_id uuid not null references public.pdc_auditor_telegram_rollback_receipts_226(rollback_receipt_id) on delete restrict deferrable initially deferred,
  run_id uuid not null references public.pdc_auditor_telegram_runs_226(run_id) on delete restrict,
  change_id uuid not null references public.pdc_auditor_telegram_changes_226(change_id) on delete restrict,
  sequence_no integer not null check (sequence_no between 1 and 250),
  operation_line_id uuid not null references public.pdc_authenticated_email_operation_lines(operation_line_id) on delete restrict,
  adjustment_id uuid not null references public.vehicle_workshop_line_adjustments(adjustment_id) on delete restrict,
  outcome text not null check (outcome in ('restored','conflict_preserved')),
  conflict_code text,
  before_undo jsonb,
  after_undo jsonb,
  exact_instruction text not null,
  rule_version_id uuid,
  recorded_at timestamptz not null default clock_timestamp(),
  unique(rollback_receipt_id,change_id),
  check ((outcome='restored' and conflict_code is null and after_undo is not null)
      or (outcome='conflict_preserved' and conflict_code is not null))
);

-- Narrow invalidation ledger: exactly one row is appended by each first apply and first undo.
create table public.pdc_auditor_workshop_revisions (
  revision_id bigint generated always as identity primary key,
  dealer_code text not null check (dealer_code in ('14450','37047')),
  environment text not null check (environment='staging'),
  event_type text not null check (event_type in ('telegram_plan_applied_226','telegram_run_rolled_back_226')),
  run_id uuid not null references public.pdc_auditor_telegram_runs_226(run_id) on delete restrict,
  rollback_receipt_id uuid references public.pdc_auditor_telegram_rollback_receipts_226(rollback_receipt_id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  check ((event_type='telegram_plan_applied_226' and rollback_receipt_id is null)
      or (event_type='telegram_run_rolled_back_226' and rollback_receipt_id is not null)),
  unique(run_id,event_type)
);

-- Defense in depth: history is RPC-only, RLS-protected, and append-only even for service_role.
do $history$
declare t text;
begin
  foreach t in array array[
    'pdc_auditor_telegram_runs_226','pdc_auditor_telegram_changes_226',
    'pdc_auditor_telegram_apply_receipts_226','pdc_auditor_telegram_rollback_receipts_226',
    'pdc_auditor_telegram_rollback_audit_226','pdc_auditor_workshop_revisions'
  ] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on table public.%I from public,anon,authenticated,service_role',t);
    execute format('create trigger %I before update or delete on public.%I for each row execute function public.pdc_auditor_reject_history_mutation()',t||'_immutable',t);
  end loop;
end
$history$;
revoke all on sequence public.pdc_auditor_workshop_revisions_revision_id_seq from public,anon,authenticated,service_role;

-- Strict Telegram evidence parser. It reuses 225 actor authorization but never reserves a
-- 225 planning instruction; apply must equal the plan's original delivery, while undo is new.
create function public.pdc_auditor_validate_telegram_evidence_226(p_evidence jsonb)
returns jsonb
language plpgsql security definer set search_path=pg_catalog,public,extensions
as $validate$
declare
  v_sender bigint;
  v_chat bigint;
  v_message bigint;
  v_update bigint;
  v_text text;
  v_bot text;
  v_hash text;
  v_actor jsonb;
begin
  if jsonb_typeof(p_evidence) is distinct from 'object'
     or (select array_agg(k order by k) from jsonb_object_keys(p_evidence) k)
       is distinct from array['bot_identity','instruction_sha256','original_instruction','telegram_chat_id','telegram_message_id','telegram_sender_id','telegram_update_id']::text[] then
    raise exception 'PDC_226_INVALID_TELEGRAM_EVIDENCE' using errcode='22023';
  end if;
  begin
    v_sender:=(p_evidence->>'telegram_sender_id')::bigint;
    v_chat:=(p_evidence->>'telegram_chat_id')::bigint;
    v_message:=(p_evidence->>'telegram_message_id')::bigint;
    v_update:=(p_evidence->>'telegram_update_id')::bigint;
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'PDC_226_INVALID_TELEGRAM_EVIDENCE' using errcode='22023';
  end;
  v_text:=p_evidence->>'original_instruction';
  v_bot:=p_evidence->>'bot_identity';
  v_hash:=lower(coalesce(p_evidence->>'instruction_sha256',''));
  if v_message<1 or v_update<0 or length(v_text) not between 3 and 4000
     or v_text<>btrim(v_text) or v_text~'[[:cntrl:]]'
     or length(v_bot) not between 3 and 160 or v_bot<>btrim(v_bot) or v_bot~'[[:cntrl:]]'
     or v_hash !~ '^[a-f0-9]{64}$'
     or v_hash<>encode(extensions.digest(convert_to(v_text,'UTF8'),'sha256'),'hex') then
    raise exception 'PDC_226_INVALID_TELEGRAM_EVIDENCE' using errcode='22023';
  end if;
  v_actor:=public.pdc_auditor_telegram_actor_scope_225(v_sender);
  return v_actor||jsonb_build_object(
    'telegram_sender_id',v_sender,'telegram_chat_id',v_chat,
    'telegram_message_id',v_message,'telegram_update_id',v_update,
    'bot_identity',v_bot,'original_instruction',v_text,'instruction_sha256',v_hash
  );
end
$validate$;
revoke all on function public.pdc_auditor_validate_telegram_evidence_226(jsonb) from public,anon,authenticated,service_role;

-- Rebuild only non-completed required-work projection from the canonical effective adjustment
-- projection. Completed rows are never changed; adjustment triggers/views remain authoritative
-- for line identifiers and totals.
create function public.pdc_auditor_recalculate_required_work_226(p_vehicle_ids uuid[])
returns void
language plpgsql security definer set search_path=pg_catalog,public
as $recalculate$
declare v_vehicle uuid;
begin
  for v_vehicle in select distinct unnest(p_vehicle_ids) loop
    insert into public.vehicle_work_items(
      vehicle_id,work_key,required,completed,completed_by,completed_at,notes,updated_at
    )
    select v_vehicle,e.work_key,true,false,null,null,null,clock_timestamp()
    from (select distinct work_key from public.pdc_effective_operation_lines
          where vehicle_id=v_vehicle and active and work_key is not null) e
    on conflict(vehicle_id,work_key) do update
      set required=true,updated_at=clock_timestamp()
      where not public.vehicle_work_items.completed and not public.vehicle_work_items.required;
    update public.vehicle_work_items wi
       set required=false,updated_at=clock_timestamp()
     where wi.vehicle_id=v_vehicle and wi.required and not wi.completed
       and not exists (
         select 1 from public.pdc_effective_operation_lines e
         where e.vehicle_id=v_vehicle and e.active and e.work_key=wi.work_key
       );
  end loop;
end
$recalculate$;
revoke all on function public.pdc_auditor_recalculate_required_work_226(uuid[]) from public,anon,authenticated,service_role;

create function public.apply_pdc_auditor_telegram_plan_226(
  p_plan uuid,p_plan_hash text,p_telegram_evidence jsonb
)
returns jsonb
language plpgsql security definer set search_path=pg_catalog,public,extensions
as $apply$
declare
  v_actor jsonb:=public.pdc_auditor_validate_telegram_evidence_226(p_telegram_evidence);
  v_plan public.pdc_auditor_plans_225%rowtype;
  v_instruction public.pdc_auditor_telegram_instructions_225%rowtype;
  v_existing public.pdc_auditor_telegram_apply_receipts_226%rowtype;
  v_run uuid:=gen_random_uuid();
  v_item record;
  v_source public.pdc_authenticated_email_operation_lines%rowtype;
  v_before public.vehicle_workshop_line_adjustments%rowtype;
  v_after public.vehicle_workshop_line_adjustments%rowtype;
  v_has_before boolean;
  v_stage text;
  v_work_key text;
  v_current_work_key text;
  v_current_description text;
  v_current_code text;
  v_current_hours numeric;
  v_current_active boolean;
  v_proposed integer;
  v_ambiguous integer;
  v_seq integer:=0;
  v_affected uuid[]:='{}'::uuid[];
  v_request_hash text;
  v_response jsonb;
begin
  if p_plan is null or coalesce(p_plan_hash,'')!~'^[a-f0-9]{64}$' then
    raise exception 'PDC_226_INVALID_APPLY_REQUEST' using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('pdc-226-plan:'||p_plan::text,0));
  select * into v_plan from public.pdc_auditor_plans_225 where plan_id=p_plan;
  if not found then raise exception 'PDC_226_PLAN_NOT_FOUND' using errcode='P0002'; end if;
  select * into strict v_instruction from public.pdc_auditor_telegram_instructions_225
    where instruction_id=v_plan.instruction_id;
  v_request_hash:=encode(extensions.digest(convert_to(concat_ws('|',
    'apply_pdc_auditor_telegram_plan_226_v1',p_plan,p_plan_hash,
    v_actor->>'telegram_sender_id',v_actor->>'telegram_chat_id',v_actor->>'telegram_message_id',
    v_actor->>'telegram_update_id',v_actor->>'bot_identity',v_actor->>'original_instruction',
    v_actor->>'instruction_sha256'),'UTF8'),'sha256'),'hex');

  select * into v_existing from public.pdc_auditor_telegram_apply_receipts_226 where plan_id=p_plan;
  if found then
    if v_existing.request_content_hash<>v_request_hash then
      raise exception 'PDC_226_PLAN_ALREADY_CONSUMED_CONTENT_CONFLICT' using errcode='23505';
    end if;
    return v_existing.response;
  end if;
  if exists(select 1 from public.pdc_auditor_telegram_apply_receipts_226
      where telegram_chat_id=(v_actor->>'telegram_chat_id')::bigint
        and telegram_message_id=(v_actor->>'telegram_message_id')::bigint)
     or exists(select 1 from public.pdc_auditor_telegram_apply_receipts_226
      where telegram_update_id=(v_actor->>'telegram_update_id')::bigint
        and bot_identity=v_actor->>'bot_identity') then
    raise exception 'PDC_226_TELEGRAM_DELIVERY_CONTENT_CONFLICT' using errcode='23505';
  end if;
  if v_plan.plan_hash<>p_plan_hash then
    raise exception 'PDC_226_PLAN_HASH_MISMATCH' using errcode='22023';
  end if;
  if v_plan.mode<>'apply' or v_plan.review_only or v_plan.action='review_category' then
    raise exception 'PDC_226_REVIEW_PLAN_CANNOT_APPLY' using errcode='42501';
  end if;
  if v_plan.item_count>250 then raise exception 'PDC_226_PLAN_CAP_EXCEEDED' using errcode='54000'; end if;
  if v_instruction.service_identity_id<>(v_actor->>'service_identity_id')::uuid
     or v_instruction.service_auth_user_id<>(v_actor->>'service_user_id')::uuid
     or v_instruction.authorizing_admin_user_id<>(v_actor->>'admin_user_id')::uuid
     or v_instruction.dealer_code<>v_actor->>'dealer_code'
     or v_instruction.telegram_sender_id<>(v_actor->>'telegram_sender_id')::bigint
     or v_instruction.telegram_chat_id<>(v_actor->>'telegram_chat_id')::bigint
     or v_instruction.telegram_message_id<>(v_actor->>'telegram_message_id')::bigint
     or v_instruction.telegram_update_id<>(v_actor->>'telegram_update_id')::bigint
     or v_instruction.bot_identity<>v_actor->>'bot_identity'
     or v_instruction.original_instruction<>v_actor->>'original_instruction'
     or v_instruction.instruction_sha256<>v_actor->>'instruction_sha256' then
    raise exception 'PDC_226_PLAN_TELEGRAM_OR_ACTOR_MISMATCH' using errcode='42501';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('pdc-226-dealer:'||v_plan.dealer_code,0));
  if public.pdc_auditor_operational_revision(v_plan.dealer_code)<>v_plan.operational_revision then
    raise exception 'PDC_226_OPERATIONAL_REVISION_STALE' using errcode='40001';
  end if;
  select count(*) filter(where disposition='proposed'),count(*) filter(where disposition='ambiguous')
    into v_proposed,v_ambiguous from public.pdc_auditor_plan_items_225 where plan_id=p_plan;
  if v_proposed+v_ambiguous>250 or v_proposed<>coalesce(v_plan.item_count-v_plan.ambiguous_count-v_plan.excluded_count,0) then
    raise exception 'PDC_226_PLAN_CONTENT_ALTERED' using errcode='40001';
  end if;

  -- Preflight all proposed rows under source, vehicle, work-item and overlay locks. Any unsafe
  -- proposed row aborts the whole apply; ambiguous rows remain queued and never block apply.
  for v_item in
    select i.* from public.pdc_auditor_plan_items_225 i
    where i.plan_id=p_plan and i.disposition='proposed' order by i.sequence_no
  loop
    select * into v_source from public.pdc_authenticated_email_operation_lines
      where operation_line_id=v_item.operation_line_id for share;
    if not found or v_source.vehicle_id<>v_item.vehicle_id
       or public.pdc_auditor_vehicle_dealer(v_item.vehicle_id)<>v_plan.dealer_code then
      raise exception 'PDC_226_SOURCE_SCOPE_CHANGED' using errcode='40001';
    end if;
    perform 1 from public.vehicles v where v.id=v_item.vehicle_id
      and v.deleted_at is null and v.lifecycle_state::text='active'
      and v.rft_collected_at is null and upper(coalesce(v.current_location,''))<>'COMPLETED'
      for update;
    if not found then raise exception 'PDC_226_VEHICLE_PROTECTED' using errcode='42501'; end if;
    perform 1 from public.vehicle_work_items wi where wi.vehicle_id=v_item.vehicle_id for update;
    if exists(select 1 from public.vehicle_work_items wi where wi.vehicle_id=v_item.vehicle_id and wi.completed) then
      raise exception 'PDC_226_COMPLETED_WORK_PROTECTED' using errcode='42501';
    end if;
    select * into v_before from public.vehicle_workshop_line_adjustments a
      where a.vehicle_id=v_item.vehicle_id and a.line_key='source:'||v_item.operation_line_id::text for update;
    v_has_before:=found;
    if v_has_before and (v_before.manual_assignment_locked
       or coalesce(v_before.correction_origin,'') not in ('','ai_auditor')) then
      raise exception 'PDC_226_MANUAL_OR_PROTECTED_OVERLAY' using errcode='42501';
    end if;
    v_current_work_key:=coalesce(public.pdc_auditor_work_key_for_stage(v_before.stage_code),v_source.work_key);
    v_current_hours:=coalesce(v_before.estimated_hours,v_source.estimated_hours);
    v_current_code:=coalesce(nullif(v_before.operation_code,''),nullif(v_source.operation_no,''));
    v_current_description:=public.pdc_auditor_normalize_identity_225(coalesce(nullif(v_before.description,''),v_source.description));
    v_current_active:=coalesce(v_before.active,true);
    if v_item.old_value->>'work_key' is distinct from v_current_work_key
       or nullif(v_item.old_value->>'estimated_hours','')::numeric is distinct from v_current_hours
       or nullif(v_item.old_value->>'operation_code','') is distinct from v_current_code
       or v_item.old_value->>'normalized_description' is distinct from v_current_description
       or (v_item.old_value ? 'active' and (v_item.old_value->>'active')::boolean is distinct from v_current_active) then
      raise exception 'PDC_226_ITEM_EVIDENCE_CHANGED' using errcode='40001';
    end if;
    if not exists(
      select 1 from public.pdc_auditor_plan_candidates_225(v_plan.dealer_code,v_plan.action,v_instruction.scope) c
      where c.disposition='proposed' and c.operation_action=v_item.operation_action
        and c.operation_line_id=v_item.operation_line_id
        and c.matched_operation_line_id is not distinct from v_item.matched_operation_line_id
        and c.old_value=v_item.old_value and c.new_value=v_item.new_value
        and c.source_evidence_hash=v_item.source_evidence_hash
    ) then
      raise exception 'PDC_226_ITEM_NO_LONGER_UNAMBIGUOUS' using errcode='40001';
    end if;
  end loop;

  insert into public.pdc_auditor_telegram_runs_226(
    run_id,plan_id,plan_hash,dealer_code,environment,service_identity_id,
    service_auth_user_id,service_email,authorizing_admin_user_id,authorizing_admin_email,
    exact_instruction,instruction_sha256,operational_revision_before,proposed_count,
    ambiguous_count,applied_count,result_code
  ) values(v_run,p_plan,p_plan_hash,v_plan.dealer_code,'staging',v_instruction.service_identity_id,
    v_instruction.service_auth_user_id,v_instruction.service_email,
    v_instruction.authorizing_admin_user_id,v_instruction.authorizing_admin_email,
    v_instruction.original_instruction,v_instruction.instruction_sha256,v_plan.operational_revision,
    v_proposed,v_ambiguous,v_proposed,case when v_proposed=0 then 'no_proposed_changes' else 'applied' end);

  for v_item in
    select i.* from public.pdc_auditor_plan_items_225 i
    where i.plan_id=p_plan and i.disposition='proposed' order by i.sequence_no
  loop
    v_seq:=v_seq+1;
    select * into v_source from public.pdc_authenticated_email_operation_lines
      where operation_line_id=v_item.operation_line_id;
    select * into v_before from public.vehicle_workshop_line_adjustments a
      where a.vehicle_id=v_item.vehicle_id and a.line_key='source:'||v_item.operation_line_id::text for update;
    v_has_before:=found;
    v_work_key:=v_item.new_value->>'work_key';
    v_stage:=public.workshop_stage_code_for_work_key(v_work_key);
    if v_stage is null then raise exception 'PDC_226_TARGET_WORK_KEY_INVALID' using errcode='22023'; end if;
    if not v_has_before then
      insert into public.vehicle_workshop_line_adjustments(
        vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,active,
        version,created_by,updated_by,operation_code,display_order,
        manual_assignment_locked,correction_origin,source_operation_line_id,job_card_number
      ) values(
        v_item.vehicle_id,'source:'||v_item.operation_line_id::text,'source',v_stage,
        v_source.description,nullif(v_item.new_value->>'estimated_hours','')::numeric,
        coalesce((v_item.new_value->>'active')::boolean,true),1,
        (v_actor->>'service_user_id')::uuid,(v_actor->>'service_user_id')::uuid,
        v_source.operation_no,v_source.source_row_no,false,'ai_auditor',
        v_item.operation_line_id,coalesce(v_source.job_card_number,v_item.job_card_number)
      ) returning * into v_after;
    else
      update public.vehicle_workshop_line_adjustments set
        stage_code=v_stage,
        estimated_hours=nullif(v_item.new_value->>'estimated_hours','')::numeric,
        active=coalesce((v_item.new_value->>'active')::boolean,true),
        version=version+1,updated_by=(v_actor->>'service_user_id')::uuid,
        updated_at=clock_timestamp(),correction_origin='ai_auditor',
        source_operation_line_id=v_item.operation_line_id
      where adjustment_id=v_before.adjustment_id returning * into v_after;
    end if;
    v_affected:=array_append(v_affected,v_item.vehicle_id);
    insert into public.pdc_auditor_telegram_changes_226(
      run_id,plan_item_id,sequence_no,operation_action,operation_line_id,
      retained_operation_line_id,superseded_operation_line_id,vehicle_id,adjustment_id,
      before_value,after_value,source_evidence_hash,exact_instruction,rule_version_id
    ) values(
      v_run,v_item.plan_item_id,v_seq,v_item.operation_action,v_item.operation_line_id,
      case when v_item.operation_action='delete' then v_item.matched_operation_line_id end,
      case when v_item.operation_action='delete' then v_item.operation_line_id end,
      v_item.vehicle_id,v_after.adjustment_id,case when v_has_before then to_jsonb(v_before) end,
      to_jsonb(v_after),v_item.source_evidence_hash,v_instruction.original_instruction,null
    );
    insert into public.audit_events(
      action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata
    ) values(
      'update','vehicle_workshop_line_adjustments',v_after.adjustment_id,v_item.vehicle_id,
      (v_actor->>'service_user_id')::uuid,v_actor->>'service_email',
      case when v_has_before then to_jsonb(v_before) end,to_jsonb(v_after),jsonb_build_object(
        'source','ai_auditor_telegram_plan_226','run_id',v_run,'plan_id',p_plan,
        'operation_line_id',v_item.operation_line_id,
        'retained_operation_line_id',case when v_item.operation_action='delete' then v_item.matched_operation_line_id end,
        'superseded_operation_line_id',case when v_item.operation_action='delete' then v_item.operation_line_id end,
        'exact_instruction',v_instruction.original_instruction,'rule_version_id',null,
        'bookings_changed',false,'dates_changed',false,'vehicle_state_changed',false,
        'location_changed',false,'completion_changed',false,'users_changed',false,'pricing_changed',false
      )
    );
  end loop;
  perform public.pdc_auditor_recalculate_required_work_226(v_affected);
  insert into public.pdc_auditor_workshop_revisions(
    dealer_code,environment,event_type,run_id
  ) values(v_plan.dealer_code,'staging','telegram_plan_applied_226',v_run);
  v_response:=jsonb_build_object('ok',true,'code',case when v_proposed=0 then 'no_proposed_changes' else 'telegram_plan_applied' end,
    'idempotent',false,'data',jsonb_build_object('run_id',v_run,'plan_id',p_plan,
      'applied_count',v_proposed,'queued_ambiguous_count',v_ambiguous,
      'bookings_changed',false,'dates_changed',false,'vehicle_state_changed',false,
      'locations_changed',false,'completion_changed',false,'users_changed',false,'pricing_changed',false));
  insert into public.pdc_auditor_telegram_apply_receipts_226(
    run_id,plan_id,telegram_sender_id,telegram_chat_id,telegram_message_id,telegram_update_id,
    bot_identity,exact_instruction,instruction_sha256,request_content_hash,response
  ) values(v_run,p_plan,(v_actor->>'telegram_sender_id')::bigint,
    (v_actor->>'telegram_chat_id')::bigint,(v_actor->>'telegram_message_id')::bigint,
    (v_actor->>'telegram_update_id')::bigint,v_actor->>'bot_identity',
    v_actor->>'original_instruction',v_actor->>'instruction_sha256',v_request_hash,v_response);
  return v_response;
end
$apply$;
revoke all on function public.apply_pdc_auditor_telegram_plan_226(uuid,text,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.apply_pdc_auditor_telegram_plan_226(uuid,text,jsonb) to authenticated;

create function public.undo_last_pdc_auditor_telegram_run_226(p_telegram_evidence jsonb)
returns jsonb
language plpgsql security definer set search_path=pg_catalog,public,extensions
as $undo$
declare
  v_actor jsonb:=public.pdc_auditor_validate_telegram_evidence_226(p_telegram_evidence);
  v_existing public.pdc_auditor_telegram_rollback_receipts_226%rowtype;
  v_run public.pdc_auditor_telegram_runs_226%rowtype;
  v_change public.pdc_auditor_telegram_changes_226%rowtype;
  v_current public.vehicle_workshop_line_adjustments%rowtype;
  v_after public.vehicle_workshop_line_adjustments%rowtype;
  v_receipt uuid:=gen_random_uuid();
  v_request_hash text;
  v_restored integer:=0;
  v_conflicts integer:=0;
  v_conflict text;
  v_affected uuid[]:='{}'::uuid[];
  v_response jsonb;
begin
  v_request_hash:=encode(extensions.digest(convert_to(concat_ws('|',
    'undo_last_pdc_auditor_telegram_run_226_v1',v_actor->>'service_identity_id',
    v_actor->>'admin_user_id',v_actor->>'dealer_code',v_actor->>'telegram_sender_id',
    v_actor->>'telegram_chat_id',v_actor->>'telegram_message_id',v_actor->>'telegram_update_id',
    v_actor->>'bot_identity',v_actor->>'original_instruction',v_actor->>'instruction_sha256'),
    'UTF8'),'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended('pdc-226-undo-delivery:'||
    (v_actor->>'telegram_chat_id')||':'||(v_actor->>'telegram_message_id'),0));
  select * into v_existing from public.pdc_auditor_telegram_rollback_receipts_226
    where telegram_chat_id=(v_actor->>'telegram_chat_id')::bigint
      and telegram_message_id=(v_actor->>'telegram_message_id')::bigint;
  if found then
    if v_existing.request_content_hash<>v_request_hash then
      raise exception 'PDC_226_UNDO_TELEGRAM_CONTENT_CONFLICT' using errcode='23505';
    end if;
    return v_existing.response;
  end if;
  if exists(select 1 from public.pdc_auditor_telegram_rollback_receipts_226
      where telegram_update_id=(v_actor->>'telegram_update_id')::bigint
        and bot_identity=v_actor->>'bot_identity') then
    raise exception 'PDC_226_UNDO_TELEGRAM_UPDATE_CONFLICT' using errcode='23505';
  end if;
  -- An apply delivery cannot be repurposed as an undo delivery, even if its text happened
  -- to contain an undo word. Telegram identities are globally single-purpose in this release.
  if exists(select 1 from public.pdc_auditor_telegram_apply_receipts_226
      where telegram_chat_id=(v_actor->>'telegram_chat_id')::bigint
        and telegram_message_id=(v_actor->>'telegram_message_id')::bigint)
     or exists(select 1 from public.pdc_auditor_telegram_apply_receipts_226
      where telegram_update_id=(v_actor->>'telegram_update_id')::bigint
        and bot_identity=v_actor->>'bot_identity') then
    raise exception 'PDC_226_UNDO_DELIVERY_ALREADY_USED_FOR_APPLY' using errcode='23505';
  end if;
  if lower(v_actor->>'original_instruction') !~ '(^|[^a-z])(undo|rollback|roll back|revert)([^a-z]|$)' then
    raise exception 'PDC_226_EXPLICIT_UNDO_INSTRUCTION_REQUIRED' using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('pdc-226-dealer:'||(v_actor->>'dealer_code'),0));
  select r.* into v_run from public.pdc_auditor_telegram_runs_226 r
    where r.dealer_code=v_actor->>'dealer_code'
      and r.service_identity_id=(v_actor->>'service_identity_id')::uuid
      and r.authorizing_admin_user_id=(v_actor->>'admin_user_id')::uuid
      and not exists(select 1 from public.pdc_auditor_telegram_rollback_receipts_226 ur where ur.run_id=r.run_id)
    order by r.applied_at desc,r.run_id desc limit 1;
  if not found then raise exception 'PDC_226_NO_APPLIED_RUN_TO_UNDO' using errcode='P0002'; end if;

  -- Rollback-audit FK checking is deferred, allowing all immutable audit rows and the final
  -- immutable receipt/response to be appended once, at the end of this same transaction.
  for v_change in
    select c.* from public.pdc_auditor_telegram_changes_226 c
    where c.run_id=v_run.run_id order by c.sequence_no desc
  loop
    v_conflict:=null;
    select * into v_current from public.vehicle_workshop_line_adjustments a
      where a.adjustment_id=v_change.adjustment_id and a.vehicle_id=v_change.vehicle_id for update;
    if not found then
      v_conflict:='adjustment_missing';
    elsif v_current.manual_assignment_locked
       or coalesce(v_current.correction_origin,'') not in ('ai_auditor','') then
      v_conflict:='later_manual_or_protected_change';
    elsif v_current.version<>(v_change.after_value->>'version')::bigint
       or v_current.stage_code is distinct from v_change.after_value->>'stage_code'
       or v_current.estimated_hours is distinct from nullif(v_change.after_value->>'estimated_hours','')::numeric
       or v_current.active is distinct from (v_change.after_value->>'active')::boolean
       or v_current.source_operation_line_id is distinct from nullif(v_change.after_value->>'source_operation_line_id','')::uuid then
      v_conflict:='later_adjustment_change';
    elsif exists(select 1 from public.vehicles v where v.id=v_change.vehicle_id
       and (v.deleted_at is not null or v.lifecycle_state::text<>'active'
         or v.rft_collected_at is not null or upper(coalesce(v.current_location,''))='COMPLETED'))
       or exists(select 1 from public.vehicle_work_items wi
          where wi.vehicle_id=v_change.vehicle_id and wi.completed) then
      v_conflict:='later_completed_or_vehicle_protection';
    end if;
    if v_conflict is not null then
      v_conflicts:=v_conflicts+1;
      insert into public.pdc_auditor_telegram_rollback_audit_226(
        rollback_receipt_id,run_id,change_id,sequence_no,operation_line_id,adjustment_id,
        outcome,conflict_code,before_undo,after_undo,exact_instruction,rule_version_id
      ) values(v_receipt,v_run.run_id,v_change.change_id,v_change.sequence_no,
        v_change.operation_line_id,v_change.adjustment_id,'conflict_preserved',v_conflict,
        case when found then to_jsonb(v_current) end,case when found then to_jsonb(v_current) end,
        v_actor->>'original_instruction',v_change.rule_version_id);
      continue;
    end if;
    if v_change.before_value is null then
      update public.vehicle_workshop_line_adjustments set
        active=false,version=version+1,updated_by=(v_actor->>'service_user_id')::uuid,
        updated_at=clock_timestamp(),correction_origin='ai_auditor_rolled_back'
      where adjustment_id=v_change.adjustment_id returning * into v_after;
    else
      update public.vehicle_workshop_line_adjustments set
        stage_code=v_change.before_value->>'stage_code',
        description=v_change.before_value->>'description',
        estimated_hours=nullif(v_change.before_value->>'estimated_hours','')::numeric,
        active=(v_change.before_value->>'active')::boolean,
        version=version+1,updated_by=(v_actor->>'service_user_id')::uuid,
        updated_at=clock_timestamp(),operation_code=v_change.before_value->>'operation_code',
        display_order=nullif(v_change.before_value->>'display_order','')::integer,
        manual_assignment_locked=coalesce((v_change.before_value->>'manual_assignment_locked')::boolean,false),
        correction_origin=v_change.before_value->>'correction_origin',
        source_operation_line_id=nullif(v_change.before_value->>'source_operation_line_id','')::uuid,
        job_card_number=v_change.before_value->>'job_card_number'
      where adjustment_id=v_change.adjustment_id returning * into v_after;
    end if;
    v_restored:=v_restored+1;
    v_affected:=array_append(v_affected,v_change.vehicle_id);
    insert into public.pdc_auditor_telegram_rollback_audit_226(
      rollback_receipt_id,run_id,change_id,sequence_no,operation_line_id,adjustment_id,
      outcome,conflict_code,before_undo,after_undo,exact_instruction,rule_version_id
    ) values(v_receipt,v_run.run_id,v_change.change_id,v_change.sequence_no,
      v_change.operation_line_id,v_change.adjustment_id,'restored',null,to_jsonb(v_current),
      to_jsonb(v_after),v_actor->>'original_instruction',v_change.rule_version_id);
    insert into public.audit_events(
      action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata
    ) values('rollback','vehicle_workshop_line_adjustments',v_after.adjustment_id,v_change.vehicle_id,
      (v_actor->>'service_user_id')::uuid,v_actor->>'service_email',to_jsonb(v_current),to_jsonb(v_after),
      jsonb_build_object('source','ai_auditor_telegram_plan_226_undo','run_id',v_run.run_id,
        'rollback_receipt_id',v_receipt,'operation_line_id',v_change.operation_line_id,
        'exact_instruction',v_actor->>'original_instruction','rule_version_id',v_change.rule_version_id,
        'bookings_changed',false,'dates_changed',false,'vehicle_state_changed',false,
        'location_changed',false,'completion_changed',false,'users_changed',false,'pricing_changed',false));
  end loop;
  perform public.pdc_auditor_recalculate_required_work_226(v_affected);
  v_response:=jsonb_build_object('ok',true,
    'code',case when v_conflicts=0 then 'telegram_run_rolled_back'
                when v_restored=0 then 'rollback_conflicts_preserved'
                else 'telegram_run_partially_rolled_back' end,
    'idempotent',false,'data',jsonb_build_object('run_id',v_run.run_id,
      'rollback_receipt_id',v_receipt,'restored_count',v_restored,'conflict_count',v_conflicts,
      'conflicts',coalesce((select jsonb_agg(jsonb_build_object(
        'operation_line_id',a.operation_line_id,'adjustment_id',a.adjustment_id,
        'conflict_code',a.conflict_code) order by a.sequence_no)
        from public.pdc_auditor_telegram_rollback_audit_226 a
        where a.rollback_receipt_id=v_receipt and a.outcome='conflict_preserved'),'[]'::jsonb),
      'bookings_changed',false,'dates_changed',false,'vehicle_state_changed',false,
      'locations_changed',false,'completion_changed',false,'users_changed',false,'pricing_changed',false));
  insert into public.pdc_auditor_telegram_rollback_receipts_226(
    rollback_receipt_id,run_id,dealer_code,service_identity_id,authorizing_admin_user_id,
    telegram_sender_id,telegram_chat_id,telegram_message_id,telegram_update_id,bot_identity,
    exact_instruction,instruction_sha256,request_content_hash,restored_count,conflict_count,response
  ) values(v_receipt,v_run.run_id,v_run.dealer_code,(v_actor->>'service_identity_id')::uuid,
    (v_actor->>'admin_user_id')::uuid,(v_actor->>'telegram_sender_id')::bigint,
    (v_actor->>'telegram_chat_id')::bigint,(v_actor->>'telegram_message_id')::bigint,
    (v_actor->>'telegram_update_id')::bigint,v_actor->>'bot_identity',
    v_actor->>'original_instruction',v_actor->>'instruction_sha256',v_request_hash,
    v_restored,v_conflicts,v_response);
  insert into public.pdc_auditor_workshop_revisions(
    dealer_code,environment,event_type,run_id,rollback_receipt_id
  ) values(v_run.dealer_code,'staging','telegram_run_rolled_back_226',v_run.run_id,v_receipt);
  return v_response;
end
$undo$;
revoke all on function public.undo_last_pdc_auditor_telegram_run_226(jsonb) from public,anon,authenticated,service_role;
grant execute on function public.undo_last_pdc_auditor_telegram_run_226(jsonb) to authenticated;

comment on function public.apply_pdc_auditor_telegram_plan_226(uuid,text,jsonb) is
  'Staging-only atomic consumer of one immutable migration-225 apply plan. Requires exact scoped service JWT and exact original Administrator Telegram delivery; revalidates revision, evidence, completion/manual protection, applies only adjustment overlays, queues ambiguity, and never changes bookings, dates, vehicle lifecycle/location/completion, users, or pricing.';
comment on function public.undo_last_pdc_auditor_telegram_run_226(jsonb) is
  'Staging-only exact-Telegram undo. Server resolves the latest unconsumed run for the same service, Administrator and dealer; restores only unchanged safe adjustment values, preserves and reports later protected conflicts, and is exactly-once for the Telegram delivery.';
comment on table public.pdc_auditor_workshop_revisions is
  'Narrow append-only invalidation ledger: exactly one revision row per first migration-226 apply and rollback.';

insert into supabase_migrations.schema_migrations(version,name,statements) values(
  '226','ai_auditor_atomic_apply_undo',array[
    'exact staging sentinel and migration-225 predecessor guard with no later/current ledger entry',
    'atomic typed apply of immutable revision-bound 225 plans with exact service and Telegram Administrator authorization and 250-item cap',
    'exactly-once plan receipt and conflicting content rejection; review plans rejected and ambiguous items remain queued',
    'edit move and duplicate-deactivation only through vehicle_workshop_line_adjustments with retained and superseded source IDs',
    'transactional stale evidence completed manual lifecycle and later-protection validation; no booking date vehicle lifecycle location completion user or pricing mutation',
    'canonical effective-operation required-work recalculation and exactly one workshop revision per apply and rollback',
    'immutable RLS-protected run change receipt rollback and conflict audit history with no direct grants including service_role',
    'server-resolved last-run safe undo with exact replay idempotency and preservation/reporting of later protected conflicts'
  ]
);
notify pgrst,'reload schema';
commit;
