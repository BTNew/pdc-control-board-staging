-- Staging only: canonical vehicle work-state edits and unallocated stoppage persistence.
-- Replaces the unreleased operation-routing migration 142 candidate.
begin;

do $guard$
begin
  if not exists (
    select 1 from public.pdc_staging_environment_sentinel
    where singleton and project_ref='cdsmnqxtyyoeoznmbidd'
  ) or to_regclass('public.pdc_production_environment_sentinel') is not null then
    raise exception 'Migration 142 is staging-only';
  end if;
  if not exists (
    select 1 from supabase_migrations.schema_migrations
    where version='141' and name='sublet_queued_rebind_and_concurrency_corrections'
  ) or exists (
    select 1 from supabase_migrations.schema_migrations where version='142'
  ) then
    raise exception 'Migration 142 predecessor/target guard failed';
  end if;
end;
$guard$;

create or replace function public.workshop_return_booking_to_queue(
  p_booking_id uuid,
  p_expected_version integer,
  p_reason text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_booking public.workshop_bookings%rowtype;
  v_before_snapshot jsonb;
  v_after_snapshot jsonb;
  v_history_id uuid;
  v_stoppage_reason text := nullif(trim(coalesce(p_reason, '')), '');
begin
  perform public.require_pdc_role('operator');
  select * into v_booking from public.workshop_bookings where id = p_booking_id for update;
  if not found then
    raise exception 'Workshop booking not found' using errcode = 'P0002';
  end if;
  if v_booking.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'version_conflict', 'conflict', public.workshop_conflict_payload(v_booking.id, 'version_conflict'));
  end if;

  v_before_snapshot := public.workshop_booking_snapshot(p_booking_id);

  update public.workshop_bookings
  set status = case when v_stoppage_reason is null then 'queued'::public.workshop_booking_status else 'stoppage'::public.workshop_booking_status end,
      bay_id = null,
      returned_to_queue_at = clock_timestamp(),
      stoppage_reason = v_stoppage_reason,
      stoppage_started_at = case when v_stoppage_reason is null then null else coalesce(stoppage_started_at, clock_timestamp()) end,
      updated_by = auth.uid(),
      updated_at = clock_timestamp(),
      version = version + 1
  where id = p_booking_id;

  -- The public wrapper authorizes a return-to-queue transition before calling
  -- this helper. An explicit unallocated stoppage remains in stoppage status,
  -- so the lifecycle trigger does not consume that authorization; remove it
  -- deterministically in the same transaction.
  if v_stoppage_reason is not null then
    perform public.workshop_consume_transition_authorization(p_booking_id, 'return_to_queue');
  end if;

  update public.workshop_booking_assignments
  set released_at = coalesce(released_at, clock_timestamp()),
      updated_at = clock_timestamp()
  where booking_id = p_booking_id and released_at is null;

  v_after_snapshot := public.workshop_booking_snapshot(p_booking_id);
  v_history_id := public.workshop_write_history(
    p_booking_id,
    case when v_stoppage_reason is null then 'returned_to_queue' else 'stoppage_returned_to_queue' end,
    v_before_snapshot,
    v_after_snapshot,
    coalesce(p_metadata, '{}'::jsonb) || jsonb_build_object('unallocated_stoppage', v_stoppage_reason is not null)
  );
  return jsonb_build_object('ok', true, 'booking', v_after_snapshot, 'history_id', v_history_id);
end;
$$;

-- Preserve the lifecycle guard while admitting only the legacy anomaly repair:
-- an already-started, already-returned queued row that still has its original
-- explicit stoppage reason may be projected back to unallocated stoppage.
create or replace function public.workshop_enforce_booking_lifecycle()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare v_allowed boolean:=false;
begin
  if tg_op='INSERT' or new.status=old.status then return new; end if;
  v_allowed :=
    (old.status in ('queued','planned') and new.status='started') or
    (old.status='started' and new.status='stoppage') or
    (old.status='stoppage' and new.status='started') or
    (old.status in ('started','stoppage') and new.status='completed') or
    (old.status in ('queued','planned','stoppage') and new.status='deleted') or
    (old.status='queued' and new.status='stoppage'
      and old.actual_start_at is not null
      and old.returned_to_queue_at is not null
      and nullif(trim(coalesce(old.stoppage_reason,'')),'') is not null
      and new.bay_id is null);
  if old.status='completed' and new.status='queued' then
    v_allowed:=public.workshop_consume_transition_authorization(old.id,'reopen_completed');
  elsif old.status='deleted' and new.status='queued' then
    v_allowed:=public.workshop_consume_transition_authorization(old.id,'restore');
  elsif old.status in ('started','stoppage') and new.status='queued' then
    v_allowed:=public.workshop_consume_transition_authorization(old.id,'return_to_queue');
  end if;
  if not v_allowed then
    raise exception 'Invalid Workshop Planner lifecycle transition: % -> %',old.status,new.status using errcode='22023';
  end if;
  return new;
end $$;
revoke all on function public.workshop_enforce_booking_lifecycle() from public,anon,authenticated;

create or replace function public.workshop_enforce_booking_validation()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare
  v_result jsonb;
  v_technician uuid;
  v_allow_unchanged_past boolean:=false;
begin
  if new.deleted_at is not null or new.status not in ('queued','planned','started','stoppage') then return new; end if;
  -- A real started stoppage may remain active and visible after its bay is
  -- released. This is the only active state allowed through without a bay.
  if new.status='stoppage'
     and new.bay_id is null
     and new.actual_start_at is not null
     and nullif(trim(coalesce(new.stoppage_reason,'')),'') is not null then
    return new;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('workshop:vehicle:'||new.vehicle_id::text,0));
  select a.technician_id into v_technician from public.workshop_booking_assignments a
  where a.booking_id=new.id and a.released_at is null
  order by case when a.assignment_type='primary' then 0 else 1 end,a.assigned_at desc limit 1;
  if tg_op='UPDATE'
     and new.scheduled_start_at is not distinct from old.scheduled_start_at
     and new.scheduled_end_at is not distinct from old.scheduled_end_at then
    v_allow_unchanged_past:=true;
  end if;
  v_result:=public.workshop_validate_booking(new.id,new.vehicle_id,new.stage_id,new.bay_id,new.scheduled_start_at,
    new.scheduled_end_at,new.default_duration_minutes,new.status,v_technician,v_allow_unchanged_past);
  if not coalesce((v_result->>'ok')::boolean,false) then
    raise exception 'Workshop Planner validation rejected booking: %',v_result::text using errcode='22023';
  end if;
  return new;
end $$;
revoke all on function public.workshop_enforce_booking_validation() from public,anon,authenticated;

-- Repair only the exact legacy anomaly produced by the old helper: a started
-- booking explicitly returned with a stoppage reason but rewritten to queued.
update public.workshop_bookings
set status = 'stoppage'::public.workshop_booking_status,
    stoppage_started_at = coalesce(stoppage_started_at, returned_to_queue_at, updated_at),
    updated_at = clock_timestamp(),
    version = version + 1
where status = 'queued'::public.workshop_booking_status
  and actual_start_at is not null
  and returned_to_queue_at is not null
  and nullif(trim(coalesce(stoppage_reason, '')), '') is not null;

create or replace function public.set_pdc_vehicle_work_states(
  p_vehicle_id uuid,
  p_expected_version integer,
  p_work_states jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_vehicle public.vehicles%rowtype;
  v_before public.vehicle_work_items%rowtype;
  v_after public.vehicle_work_items%rowtype;
  v_parts_before public.vehicle_parts_updates%rowtype;
  v_parts_after public.vehicle_parts_updates%rowtype;
  v_input_key text;
  v_work_key text;
  v_state text;
  v_stage text;
  v_changed boolean := false;
  v_actor uuid := auth.uid();
  v_email text := public.current_actor_email();
  v_allowed constant text[] := array['bus4x4','tint','hoist','fitting','fabrication','electrical','tyre','pitInspection','sublet','parts'];
begin
  perform public.require_pdc_role('operator');
  if p_vehicle_id is null or p_expected_version is null or p_expected_version < 1 then
    return jsonb_build_object('ok', false, 'error', 'invalid_input');
  end if;
  if p_work_states is null or jsonb_typeof(p_work_states) <> 'object' then
    return jsonb_build_object('ok', false, 'error', 'invalid_work_states');
  end if;
  if exists(select 1 from jsonb_object_keys(p_work_states) key where not (key = any(v_allowed)))
     or exists(select 1 from unnest(v_allowed) key where not (p_work_states ? key)) then
    return jsonb_build_object('ok', false, 'error', 'invalid_work_state_keys');
  end if;

  select * into v_vehicle from public.vehicles where id = p_vehicle_id for update;
  if not found or v_vehicle.deleted_at is not null then
    return jsonb_build_object('ok', false, 'error', 'vehicle_not_found');
  end if;
  if v_vehicle.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'vehicle_version_conflict', 'current_version', v_vehicle.version);
  end if;

  -- Validate the complete requested state map before the first durable write.
  -- The vehicle row lock serializes this decision with the canonical vehicle
  -- mutation paths, while this full pass guarantees a structured rejection is
  -- side-effect free for every key in the request.
  foreach v_input_key in array v_allowed loop
    v_state := lower(trim(coalesce(p_work_states->>v_input_key, '')));
    if v_state not in ('none','required','complete') then
      return jsonb_build_object('ok', false, 'error', 'invalid_work_state', 'work_key', v_input_key);
    end if;
    if v_input_key <> 'parts' then
      v_work_key := case when v_input_key = 'pitInspection' then 'pitinspection' else lower(v_input_key) end;
      v_stage := public.workshop_stage_code_for_work_key(v_work_key);
      if v_state in ('none','complete') and exists(
        select 1 from public.workshop_bookings b
        join public.workshop_stages s on s.id=b.stage_id
        where b.vehicle_id=p_vehicle_id and upper(s.code)=upper(v_stage)
          and b.status::text not in ('completed','deleted','cancelled')
      ) then
        return jsonb_build_object('ok', false, 'error', 'active_booking_exists', 'work_key', v_work_key, 'stage_code', v_stage);
      end if;
    end if;
  end loop;

  foreach v_input_key in array v_allowed loop
    v_state := lower(trim(coalesce(p_work_states->>v_input_key, '')));

    if v_input_key = 'parts' then
      select * into v_parts_before
      from public.vehicle_parts_updates
      where vehicle_id = p_vehicle_id
      order by updated_at desc, id desc
      limit 1;
      if v_parts_before.id is null
         or v_parts_before.parts_required is distinct from (v_state <> 'none')
         or v_parts_before.parts_received is distinct from (v_state = 'complete') then
        insert into public.vehicle_parts_updates(
          vehicle_id, parts_required, parts_ordered, parts_received, updated_by, updated_at
        ) values (
          p_vehicle_id,
          v_state <> 'none',
          (v_state = 'complete') or (v_state = 'required' and coalesce(v_parts_before.parts_ordered,false)),
          v_state = 'complete',
          v_actor,
          clock_timestamp()
        ) returning * into v_parts_after;
        v_changed := true;
        insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
        values('insert'::public.audit_action,'vehicle_parts_updates',v_parts_after.id,p_vehicle_id,v_actor,v_email,
          case when v_parts_before.id is null then null else to_jsonb(v_parts_before) end,to_jsonb(v_parts_after),
          jsonb_build_object('source','vehicle_detail_work_states','work_key','parts','requested_state',v_state));
      end if;
      continue;
    end if;

    v_work_key := case when v_input_key = 'pitInspection' then 'pitinspection' else lower(v_input_key) end;

    select * into v_before from public.vehicle_work_items where vehicle_id=p_vehicle_id and work_key=v_work_key for update;
    insert into public.vehicle_work_items(vehicle_id,work_key,required,completed,completed_by,completed_at,updated_at)
    values(p_vehicle_id,v_work_key,v_state <> 'none',v_state='complete',case when v_state='complete' then v_actor else null end,case when v_state='complete' then clock_timestamp() else null end,clock_timestamp())
    on conflict(vehicle_id,work_key) do update set
      required=excluded.required,
      completed=excluded.completed,
      completed_by=excluded.completed_by,
      completed_at=excluded.completed_at,
      updated_at=excluded.updated_at
    returning * into v_after;
    if to_jsonb(v_before) is distinct from to_jsonb(v_after) then
      v_changed := true;
      insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
      values(case when v_before.id is null then 'insert'::public.audit_action else 'update'::public.audit_action end,
        'vehicle_work_items',v_after.id,p_vehicle_id,v_actor,v_email,
        case when v_before.id is null then null else to_jsonb(v_before) end,to_jsonb(v_after),
        jsonb_build_object('source','vehicle_detail_work_states','work_key',v_work_key,'requested_state',v_state));
    end if;
  end loop;

  if v_changed then
    update public.vehicles
    set version=version+1,
        qc_completed_at=null,
        qc_completed_by=null,
        updated_at=clock_timestamp()
    where id=p_vehicle_id;
    perform public.workshop_bump_revision();
  end if;

  select * into v_vehicle from public.vehicles where id=p_vehicle_id;
  return jsonb_build_object(
    'ok',true,
    'changed',v_changed,
    'vehicle_id',p_vehicle_id,
    'vehicle_version',v_vehicle.version,
    'work_items',coalesce((select jsonb_agg(jsonb_build_object('work_key',wi.work_key,'required',wi.required,'completed',wi.completed,'completed_at',wi.completed_at,'completed_by',wi.completed_by) order by wi.work_key) from public.vehicle_work_items wi where wi.vehicle_id=p_vehicle_id),'[]'::jsonb),
    'parts',coalesce((select to_jsonb(pu) from public.vehicle_parts_updates pu where pu.vehicle_id=p_vehicle_id order by pu.updated_at desc, pu.id desc limit 1),'{}'::jsonb)
  );
end;
$$;

revoke all on function public.set_pdc_vehicle_work_states(uuid,integer,jsonb) from public,anon,authenticated;
grant execute on function public.set_pdc_vehicle_work_states(uuid,integer,jsonb) to authenticated,service_role;
comment on function public.set_pdc_vehicle_work_states(uuid,integer,jsonb) is
'Operator/admin canonical tri-state requirement update with vehicle-version concurrency, active-booking protection, audit and Workshop revision.';

insert into supabase_migrations.schema_migrations(version,name,statements)
values('142','vehicle_work_states_and_unallocated_stoppages',array['canonical work states and unallocated stoppage persistence'])
on conflict(version) do nothing;

commit;
