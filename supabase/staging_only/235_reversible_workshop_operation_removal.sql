-- Staging-only migration 235: reversible soft removal of Workshop operation lines.
begin;
set local lock_timeout='20s';
set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-installation',0));

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or not exists(select 1 from supabase_migrations.schema_migrations where version='234')
     or exists(select 1 from supabase_migrations.schema_migrations where version~'^[0-9]+$' and version::numeric>234)
     or exists(select 1 from supabase_migrations.schema_migrations where version='235')
     or to_regprocedure('public.pdc_auditor_recalculate_required_work_226(uuid[])') is null
     or to_regprocedure('public.pdc_auditor_reject_history_mutation()') is null then
    raise exception 'PDC_235_STAGING_OR_DEPENDENCY_MISMATCH' using errcode='55000';
  end if;
end
$guard$;

-- The Auditor publisher and removal RPC must serialize on the same absent-row
-- key. Patch the existing publisher in place so its authentication, complete-
-- snapshot validation, append-only evidence, grants, and caller contract stay
-- exactly as installed by migration 121. The prosrc digest makes this patch
-- fail closed if any byte of that function body has drifted.
do $patch_auditor_publisher$
declare
  v_signature constant regprocedure := 'public.submit_pdc_auditor_findings(jsonb,jsonb)'::regprocedure;
  v_definition text;
  v_source text;
  v_before_security jsonb;
  v_after_security jsonb;
  v_validation_marker text := $old$      if not public.pdc_auditor_entity_in_scope(v_dealer,v_evidence->>'entity_type',v_entity_id) then$old$;
  v_validation_replacement text := $new$      if v_evidence->>'entity_type'='operation_line' then
        perform pg_advisory_xact_lock(hashtextextended(
          'pdc-operation-line-evidence-serialization-v1:'||v_entity_id::text,0));
      end if;
      if not public.pdc_auditor_entity_in_scope(v_dealer,v_evidence->>'entity_type',v_entity_id) then$new$;
  v_insert_marker text := $old$      insert into public.pdc_auditor_finding_evidence($old$;
  v_insert_replacement text := $new$      if v_evidence->>'entity_type'='operation_line' then
        perform pg_advisory_xact_lock(hashtextextended(
          'pdc-operation-line-evidence-serialization-v1:'||
          (v_evidence->>'entity_id')::uuid::text,0));
      end if;
      insert into public.pdc_auditor_finding_evidence($new$;
begin
  select p.prosrc,
         jsonb_build_object(
           'owner',p.proowner,'acl',p.proacl,'security_definer',p.prosecdef,
           'leakproof',p.proleakproof,'strict',p.proisstrict,'volatility',p.provolatile,
           'parallel',p.proparallel,'config',p.proconfig,'language',p.prolang)
    into strict v_source,v_before_security
    from pg_proc p where p.oid=v_signature;
  if encode(extensions.digest(convert_to(v_source,'UTF8'),'sha256'),'hex')
       <> '8164fd754e9b9757efbded9e18db8d089e66decbb7c108b050d0ecd2a7b46428'
     or not (v_before_security @> jsonb_build_object(
       'security_definer',true,'leakproof',false,'strict',false,'volatility','v','parallel','u')) then
    raise exception 'PDC_235_AUDITOR_PUBLISHER_EXACT_DEFINITION_DRIFT' using errcode='55000';
  end if;
  select pg_get_functiondef(v_signature) into strict v_definition;
  if (length(v_definition)-length(replace(v_definition,v_validation_marker,'')))/length(v_validation_marker)<>1
     or (length(v_definition)-length(replace(v_definition,v_insert_marker,'')))/length(v_insert_marker)<>1
     or position('pdc-operation-line-evidence-serialization-v1:' in v_definition)>0 then
    raise exception 'PDC_235_AUDITOR_PUBLISHER_PATCH_ANCHOR_DRIFT' using errcode='55000';
  end if;
  execute replace(replace(v_definition,v_validation_marker,v_validation_replacement),
                  v_insert_marker,v_insert_replacement);
  select jsonb_build_object(
           'owner',p.proowner,'acl',p.proacl,'security_definer',p.prosecdef,
           'leakproof',p.proleakproof,'strict',p.proisstrict,'volatility',p.provolatile,
           'parallel',p.proparallel,'config',p.proconfig,'language',p.prolang)
    into strict v_after_security from pg_proc p where p.oid=v_signature;
  select pg_get_functiondef(v_signature) into strict v_definition;
  if v_after_security<>v_before_security
     or (length(v_definition)-length(replace(v_definition,'pdc-operation-line-evidence-serialization-v1:','')))
          /length('pdc-operation-line-evidence-serialization-v1:')<>2
     or position(v_validation_replacement in v_definition)=0
     or position(v_insert_replacement in v_definition)=0 then
    raise exception 'PDC_235_AUDITOR_PUBLISHER_POSTCONDITION_FAILED' using errcode='55000';
  end if;
end
$patch_auditor_publisher$;

create table public.pdc_workshop_operation_removal_receipts_235(
  receipt_id uuid primary key default gen_random_uuid(),
  idempotency_key text not null check(length(idempotency_key) between 8 and 160),
  request_sha256 text not null check(request_sha256~'^[a-f0-9]{64}$'),
  operation_line_id uuid not null references public.pdc_authenticated_email_operation_lines(operation_line_id) on delete restrict,
  vehicle_id uuid not null references public.vehicles(id) on delete restrict,
  adjustment_id uuid not null references public.vehicle_workshop_line_adjustments(adjustment_id) on delete restrict,
  actor_id uuid not null references auth.users(id) on delete restrict,
  actor_email text not null,
  reason text not null check(length(reason) between 3 and 500),
  previous_value jsonb,
  removed_value jsonb not null check(jsonb_typeof(removed_value)='object'),
  source_evidence jsonb not null check(jsonb_typeof(source_evidence)='object'),
  source_evidence_sha256 text not null check(source_evidence_sha256~'^[a-f0-9]{64}$'),
  adjustment_version integer not null check(adjustment_version>0),
  realtime_revision bigint not null,
  created_at timestamptz not null default clock_timestamp(),
  unique(actor_id,idempotency_key)
);

create table public.pdc_workshop_operation_removal_undo_receipts_235(
  undo_receipt_id uuid primary key default gen_random_uuid(),
  removal_receipt_id uuid not null unique references public.pdc_workshop_operation_removal_receipts_235(receipt_id) on delete restrict,
  actor_id uuid not null references auth.users(id) on delete restrict,
  actor_email text not null,
  reason text not null check(length(reason) between 3 and 500),
  before_undo jsonb not null check(jsonb_typeof(before_undo)='object'),
  after_undo jsonb not null check(jsonb_typeof(after_undo)='object'),
  outcome text not null check(outcome in('restored','conflict_preserved')),
  conflict_code text,
  realtime_revision bigint,
  created_at timestamptz not null default clock_timestamp(),
  check((outcome='restored' and conflict_code is null and realtime_revision is not null)
     or (outcome='conflict_preserved' and conflict_code is not null))
);

alter table public.pdc_workshop_operation_removal_receipts_235 enable row level security;
alter table public.pdc_workshop_operation_removal_undo_receipts_235 enable row level security;
revoke all on table public.pdc_workshop_operation_removal_receipts_235 from public,anon,authenticated,service_role;
revoke all on table public.pdc_workshop_operation_removal_undo_receipts_235 from public,anon,authenticated,service_role;
create trigger pdc_workshop_operation_removal_receipts_235_immutable before update or delete on public.pdc_workshop_operation_removal_receipts_235 for each row execute function public.pdc_auditor_reject_history_mutation();
create trigger pdc_workshop_operation_removal_undo_receipts_235_immutable before update or delete on public.pdc_workshop_operation_removal_undo_receipts_235 for each row execute function public.pdc_auditor_reject_history_mutation();

create function public.remove_pdc_workshop_operation_line_235(
  p_operation_line_id uuid,
  p_expected_adjustment_version integer,
  p_reason text,
  p_source_evidence jsonb,
  p_idempotency_key text
) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public,extensions
as $remove$
declare
  v_actor uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_role text:=coalesce(public.current_pdc_user_role()::text,'');
  v_reason text:=btrim(coalesce(p_reason,''));
  v_key text:=btrim(coalesce(p_idempotency_key,''));
  v_evidence jsonb:=coalesce(p_source_evidence,'null'::jsonb);
  v_source public.pdc_authenticated_email_operation_lines%rowtype;
  v_vehicle public.vehicles%rowtype;
  v_before public.vehicle_workshop_line_adjustments%rowtype;
  v_after public.vehicle_workshop_line_adjustments%rowtype;
  v_existing public.pdc_workshop_operation_removal_receipts_235%rowtype;
  v_has_before boolean;
  v_request text;
  v_evidence_hash text;
  v_receipt uuid:=gen_random_uuid();
  v_revision bigint;
  v_effective_stage text;
begin
  if not public.pdc_monitor_staging_guard() or v_actor is null or v_email='' or v_role not in('operator','administrator') then
    return public.navision_backend_response(false,'unauthorized');
  end if;
  if p_operation_line_id is null or length(v_reason) not between 3 and 500
     or length(v_key) not between 8 and 160 or jsonb_typeof(v_evidence) is distinct from 'object' then
    return public.navision_backend_response(false,'invalid_input');
  end if;
  v_evidence_hash:=encode(extensions.digest(convert_to(v_evidence::text,'UTF8'),'sha256'),'hex');
  v_request:=encode(extensions.digest(convert_to(concat_ws('|','remove_operation_235_v1',p_operation_line_id,
    coalesce(p_expected_adjustment_version,0),v_reason,v_evidence_hash,v_key,v_actor),'UTF8'),'sha256'),'hex');
  -- Shared with submit_pdc_auditor_findings: unlike a row lock, this also
  -- serializes the no-evidence-row case through the overlay mutation.
  perform pg_advisory_xact_lock(hashtextextended(
    'pdc-operation-line-evidence-serialization-v1:'||p_operation_line_id::text,0));
  select * into v_existing from public.pdc_workshop_operation_removal_receipts_235 where actor_id=v_actor and idempotency_key=v_key;
  if found then
    if v_existing.request_sha256<>v_request then return public.navision_backend_response(false,'idempotency_conflict'); end if;
    return public.navision_backend_response(true,'already_removed',jsonb_build_object('receipt_id',v_existing.receipt_id,'operation_line_id',v_existing.operation_line_id,'revision',v_existing.realtime_revision));
  end if;
  select * into v_source from public.pdc_authenticated_email_operation_lines where operation_line_id=p_operation_line_id for share;
  if not found then return public.navision_backend_response(false,'operation_line_not_found'); end if;
  select * into v_vehicle from public.vehicles where id=v_source.vehicle_id for update;
  if not found or v_vehicle.deleted_at is not null or v_vehicle.lifecycle_state::text<>'active'
     or v_vehicle.rft_collected_at is not null or upper(coalesce(v_vehicle.current_location,''))='COMPLETED' then
    return public.navision_backend_response(false,'vehicle_protected');
  end if;
  perform 1 from public.vehicle_work_items where vehicle_id=v_source.vehicle_id for update;
  if exists(select 1 from public.vehicle_work_items where vehicle_id=v_source.vehicle_id and completed) then
    return public.navision_backend_response(false,'completed_work_protected');
  end if;
  select * into v_before from public.vehicle_workshop_line_adjustments
   where vehicle_id=v_source.vehicle_id and line_key='source:'||p_operation_line_id::text for update;
  v_has_before:=found;
  v_effective_stage:=coalesce(
    case when v_has_before and v_before.active then v_before.stage_code end,
    public.workshop_stage_code_for_work_key(v_source.work_key),upper(v_source.work_key));
  -- Lock and reject immutable Auditor evidence and live planner rows before
  -- changing the effective operation overlay. The repeat immediately before
  -- mutation protects against relevant changes made while this RPC waited.
  perform 1 from public.pdc_auditor_finding_evidence
   where entity_type='operation_line' and entity_id=p_operation_line_id for share;
  if found then return public.navision_backend_response(false,'auditor_evidence_protected'); end if;
  perform 1 from public.workshop_bookings b join public.workshop_stages s on s.id=b.stage_id
   where b.vehicle_id=v_source.vehicle_id and b.deleted_at is null
     and b.status::text not in('completed','cancelled') and s.code=v_effective_stage
   for share of b;
  if found then return public.navision_backend_response(false,'live_workshop_booking_protected'); end if;
  if v_has_before and (v_before.manual_assignment_locked or coalesce(v_before.correction_origin,'') not in('','ai_auditor','manual_operator')) then
    return public.navision_backend_response(false,'manual_or_protected_overlay');
  end if;
  if coalesce(p_expected_adjustment_version,0)<>(case when v_has_before then v_before.version else 0 end) then
    return public.navision_backend_response(false,'version_conflict',jsonb_build_object('current_version',(case when v_has_before then v_before.version else 0 end)));
  end if;
  if v_has_before and not v_before.active and v_before.correction_origin='manual_operator' then
    return public.navision_backend_response(false,'already_removed_without_matching_key');
  end if;
  if exists(select 1 from public.pdc_auditor_finding_evidence
      where entity_type='operation_line' and entity_id=p_operation_line_id) then
    return public.navision_backend_response(false,'auditor_evidence_protected');
  end if;
  if exists(select 1 from public.workshop_bookings b join public.workshop_stages s on s.id=b.stage_id
      where b.vehicle_id=v_source.vehicle_id and b.deleted_at is null
        and b.status::text not in('completed','cancelled') and s.code=v_effective_stage) then
    return public.navision_backend_response(false,'live_workshop_booking_protected');
  end if;
  if not v_has_before then
    insert into public.vehicle_workshop_line_adjustments(
      vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,active,version,
      created_by,updated_by,operation_code,display_order,manual_assignment_locked,
      correction_origin,source_operation_line_id,job_card_number
    ) values(
      v_source.vehicle_id,'source:'||p_operation_line_id::text,'source',public.workshop_stage_code_for_work_key(v_source.work_key),
      v_source.description,v_source.estimated_hours,false,1,v_actor,v_actor,v_source.operation_no,
      v_source.source_row_no,true,'manual_operator',p_operation_line_id,v_source.job_card_number
    ) returning * into v_after;
  else
    update public.vehicle_workshop_line_adjustments set active=false,manual_assignment_locked=true,
      correction_origin='manual_operator',version=version+1,updated_by=v_actor,updated_at=clock_timestamp()
    where adjustment_id=v_before.adjustment_id returning * into v_after;
  end if;
  perform public.pdc_auditor_recalculate_required_work_226(array[v_source.vehicle_id]);
  select revision into strict v_revision from public.pdc_email_vehicle_revision where singleton;
  insert into public.pdc_workshop_operation_removal_receipts_235(
    receipt_id,idempotency_key,request_sha256,operation_line_id,vehicle_id,adjustment_id,actor_id,actor_email,
    reason,previous_value,removed_value,source_evidence,source_evidence_sha256,adjustment_version,realtime_revision
  ) values(v_receipt,v_key,v_request,p_operation_line_id,v_source.vehicle_id,v_after.adjustment_id,v_actor,v_email,
    v_reason,case when v_has_before then to_jsonb(v_before) end,to_jsonb(v_after),v_evidence,v_evidence_hash,v_after.version,v_revision);
  return public.navision_backend_response(true,'operation_removed',jsonb_build_object(
    'receipt_id',v_receipt,'operation_line_id',p_operation_line_id,'vehicle_id',v_source.vehicle_id,
    'adjustment_version',v_after.version,'revision',v_revision,'undo_available',true));
end
$remove$;

create function public.undo_pdc_workshop_operation_removal_235(p_receipt_id uuid,p_reason text)
returns jsonb
language plpgsql security definer set search_path=pg_catalog,public
as $undo$
declare
  v_actor uuid:=auth.uid();v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_role text:=coalesce(public.current_pdc_user_role()::text,'');v_reason text:=btrim(coalesce(p_reason,''));
  v_receipt public.pdc_workshop_operation_removal_receipts_235%rowtype;
  v_existing public.pdc_workshop_operation_removal_undo_receipts_235%rowtype;
  v_current public.vehicle_workshop_line_adjustments%rowtype;v_after public.vehicle_workshop_line_adjustments%rowtype;
  v_previous public.vehicle_workshop_line_adjustments%rowtype;v_revision bigint;v_undo uuid:=gen_random_uuid();
begin
  if not public.pdc_monitor_staging_guard() or v_actor is null or v_email='' or v_role not in('operator','administrator') then
    return public.navision_backend_response(false,'unauthorized');
  end if;
  if p_receipt_id is null or length(v_reason) not between 3 and 500 then return public.navision_backend_response(false,'invalid_input'); end if;
  perform pg_advisory_xact_lock(hashtextextended('pdc-operation-removal-undo-235:'||p_receipt_id::text,0));
  select * into v_existing from public.pdc_workshop_operation_removal_undo_receipts_235 where removal_receipt_id=p_receipt_id;
  if found then return public.navision_backend_response(v_existing.outcome='restored',case when v_existing.outcome='restored' then 'already_restored' else v_existing.conflict_code end,
    jsonb_build_object('undo_receipt_id',v_existing.undo_receipt_id,'outcome',v_existing.outcome,'revision',v_existing.realtime_revision)); end if;
  select * into v_receipt from public.pdc_workshop_operation_removal_receipts_235 where receipt_id=p_receipt_id;
  if not found then return public.navision_backend_response(false,'removal_receipt_not_found'); end if;
  select * into v_current from public.vehicle_workshop_line_adjustments where adjustment_id=v_receipt.adjustment_id for update;
  if not found or to_jsonb(v_current)<>v_receipt.removed_value then
    insert into public.pdc_workshop_operation_removal_undo_receipts_235(
      undo_receipt_id,removal_receipt_id,actor_id,actor_email,reason,before_undo,after_undo,outcome,conflict_code
    ) values(v_undo,p_receipt_id,v_actor,v_email,v_reason,coalesce(to_jsonb(v_current),'{}'::jsonb),coalesce(to_jsonb(v_current),'{}'::jsonb),'conflict_preserved','later_manual_or_protected_change');
    return public.navision_backend_response(false,'later_manual_or_protected_change',jsonb_build_object('undo_receipt_id',v_undo,'outcome','conflict_preserved'));
  end if;
  if v_receipt.previous_value is null then
    update public.vehicle_workshop_line_adjustments set active=true,manual_assignment_locked=false,
      correction_origin='manual_operator',version=version+1,updated_by=v_actor,updated_at=clock_timestamp()
    where adjustment_id=v_current.adjustment_id returning * into v_after;
  else
    v_previous:=jsonb_populate_record(null::public.vehicle_workshop_line_adjustments,v_receipt.previous_value);
    update public.vehicle_workshop_line_adjustments set
      stage_code=v_previous.stage_code,description=v_previous.description,estimated_hours=v_previous.estimated_hours,
      active=v_previous.active,operation_code=v_previous.operation_code,display_order=v_previous.display_order,
      manual_assignment_locked=v_previous.manual_assignment_locked,correction_origin=v_previous.correction_origin,
      version=v_current.version+1,updated_by=v_actor,updated_at=clock_timestamp()
    where adjustment_id=v_current.adjustment_id returning * into v_after;
  end if;
  perform public.pdc_auditor_recalculate_required_work_226(array[v_receipt.vehicle_id]);
  select revision into strict v_revision from public.pdc_email_vehicle_revision where singleton;
  insert into public.pdc_workshop_operation_removal_undo_receipts_235(
    undo_receipt_id,removal_receipt_id,actor_id,actor_email,reason,before_undo,after_undo,outcome,realtime_revision
  ) values(v_undo,p_receipt_id,v_actor,v_email,v_reason,to_jsonb(v_current),to_jsonb(v_after),'restored',v_revision);
  return public.navision_backend_response(true,'operation_restored',jsonb_build_object('undo_receipt_id',v_undo,'operation_line_id',v_receipt.operation_line_id,'revision',v_revision));
end
$undo$;

revoke all on function public.remove_pdc_workshop_operation_line_235(uuid,integer,text,jsonb,text) from public,anon,authenticated,service_role;
revoke all on function public.undo_pdc_workshop_operation_removal_235(uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.remove_pdc_workshop_operation_line_235(uuid,integer,text,jsonb,text) to authenticated;
grant execute on function public.undo_pdc_workshop_operation_removal_235(uuid,text) to authenticated;

insert into supabase_migrations.schema_migrations(version,name,statements) values(
  '235','reversible_workshop_operation_removal',array[
    'soft-remove operation lines only through protected adjustment overlays; preserve immutable source lines',
    'append reason actor timestamp previous value source evidence and Undo receipts with idempotency and conflict checks',
    'recalculate required work and publish the existing Realtime vehicle revision without moving bookings locations or lifecycle',
    'serialize operation-line evidence publication and removal on one advisory transaction lock key'
  ]
);
commit;
