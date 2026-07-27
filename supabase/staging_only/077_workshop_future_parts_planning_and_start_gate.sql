-- Staging-only migration 077.
-- Keep future Workshop planning available to ordinary planner operators while
-- preserving an audited planning reason, and enforce the Parts gate at the
-- actual Start job boundary. Only administrators may start a Parts-incomplete
-- physical job, and only with an explicit reason.
begin;

CREATE OR REPLACE FUNCTION public.schedule_vehicle_work(p_vehicle_id uuid, p_vehicle_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer DEFAULT 180, p_technician_id uuid DEFAULT NULL::uuid, p_override_reason text DEFAULT NULL::text, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare v_vehicle public.vehicles%rowtype; v_stage public.workshop_stages%rowtype; v_result jsonb; v_override_id uuid; v_revision bigint; v_code text;
begin
 perform public.workshop_require_planner_operator(); perform public.workshop_require_version(p_vehicle_expected_version);
 select * into v_vehicle from public.vehicles where id=p_vehicle_id for update;
 if not found then raise exception 'Vehicle not found' using errcode='P0002'; end if;
 if v_vehicle.version<>p_vehicle_expected_version then return jsonb_build_object('ok',false,'error','vehicle_version_conflict'); end if;
 v_code:=public.workshop_canonical_stage_code(p_stage_code);
 select * into v_stage from public.workshop_stages where code=v_code and active and planner_enabled;
 if not found then raise exception 'Unknown or planner-disabled workshop station' using errcode='22023'; end if;
 if not exists(select 1 from public.workshop_station_eligibility(v_code)e where e.vehicle_id=p_vehicle_id) then
  return jsonb_build_object('ok',false,'error','vehicle_not_eligible_for_station');
 end if;
 if v_stage.is_physical and not public.workshop_parts_ready(p_vehicle_id) then
  if p_override_reason is null or btrim(p_override_reason)='' then return jsonb_build_object('ok',false,'error','parts_incomplete'); end if;
  -- Future planning is not physical bay entry. The explicit reason is
  -- still written to workshop_parts_overrides, but any planner operator
  -- may create or move a planned booking before Parts are ready.
 end if;
 v_result:=public.workshop_create_booking(p_vehicle_id,v_code,p_bay_number,p_scheduled_start_at,p_duration_minutes,p_technician_id,p_metadata);
 if not (v_result->>'ok')::boolean then return v_result; end if;
 if p_override_reason is not null and btrim(p_override_reason)<>'' then
  insert into public.workshop_parts_overrides(vehicle_id,booking_id,work_key,intended_stage_id,reason,previous_state,resulting_state,approved_by,approved_by_email)
  values(p_vehicle_id,(v_result->'booking'->>'booking_id')::uuid,'PARTS',v_stage.id,btrim(p_override_reason),
   jsonb_build_object('vehicle_id',p_vehicle_id,'version',v_vehicle.version),
   jsonb_build_object('vehicle_id',p_vehicle_id,'version',v_vehicle.version),auth.uid(),public.current_actor_email()) returning id into v_override_id;
 end if;
 v_revision:=public.workshop_bump_revision();
 return v_result||jsonb_build_object('override_id',v_override_id,'revision',v_revision);
end $function$;

CREATE OR REPLACE FUNCTION public.move_workshop_booking(p_booking_id uuid, p_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer DEFAULT NULL::integer, p_override_reason text DEFAULT NULL::text, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare v_before public.workshop_bookings%rowtype; v_stage public.workshop_stages%rowtype; v_result jsonb; v_override_id uuid; v_revision bigint; v_code text;
begin
 perform public.workshop_require_planner_operator(); perform public.workshop_require_version(p_expected_version);
 select * into v_before from public.workshop_bookings where id=p_booking_id for update;
 if not found then raise exception 'Workshop booking not found' using errcode='P0002'; end if;
 v_code:=public.workshop_canonical_stage_code(p_stage_code);
 perform public.workshop_require_booking_schedule_eligibility(p_booking_id,v_code);
 select * into v_stage from public.workshop_stages where code=v_code and active and planner_enabled;
 if not found then raise exception 'Unknown or planner-disabled workshop station' using errcode='22023'; end if;
 if v_stage.is_physical and not public.workshop_parts_ready(v_before.vehicle_id) then
  if p_override_reason is null or btrim(p_override_reason)='' then return jsonb_build_object('ok',false,'error','parts_incomplete'); end if;
    -- Moving a planned/live board card is planning, not physical bay entry.
  -- Keep the explicit audited reason without escalating to administrator.
 end if;
 v_result:=public.workshop_move_booking(p_booking_id,p_expected_version,v_code,p_bay_number,p_scheduled_start_at,p_duration_minutes,p_metadata);
 if not (v_result->>'ok')::boolean then return v_result; end if;
 if p_override_reason is not null and btrim(p_override_reason)<>'' then
  insert into public.workshop_parts_overrides(vehicle_id,booking_id,work_key,intended_stage_id,reason,previous_state,resulting_state,approved_by,approved_by_email)
  values(v_before.vehicle_id,p_booking_id,'PARTS',v_stage.id,btrim(p_override_reason),
   jsonb_build_object('booking_id',v_before.id,'version',v_before.version),v_result->'booking',auth.uid(),public.current_actor_email()) returning id into v_override_id;
 end if;
 v_revision:=public.workshop_bump_revision(); return v_result||jsonb_build_object('override_id',v_override_id,'revision',v_revision);
end $function$;

CREATE OR REPLACE FUNCTION public.cascade_workshop_schedule(p_operation text, p_target_id uuid, p_target_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer, p_technician_id uuid DEFAULT NULL::uuid, p_shift_minutes integer DEFAULT 0, p_override_reason text DEFAULT NULL::text, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_operation text := lower(trim(coalesce(p_operation, '')));
  v_stage public.workshop_stages%rowtype;
  v_bay public.workshop_bays%rowtype;
  v_target public.workshop_bookings%rowtype;
  v_shifted public.workshop_bookings%rowtype;
  v_expected_ids uuid[] := '{}'::uuid[];
  v_new_start timestamptz;
  v_new_end timestamptz;
  v_before jsonb;
  v_after jsonb;
  v_result jsonb;
  v_technician uuid;
  v_conflict uuid;
  v_locked_count integer;
begin
  perform public.workshop_require_planner_operator();
  perform public.workshop_require_version(p_target_expected_version);
  perform pg_advisory_xact_lock(hashtextextended('pdc:workshop:cascade',0));

  if v_operation not in ('insert', 'extend') then
    raise exception 'Cascade operation must be insert or extend' using errcode = '22023';
  end if;
  if p_duration_minutes is null or p_duration_minutes < 60 then
    return jsonb_build_object('ok', false, 'error', 'minimum_duration', 'minimum_minutes', 60);
  end if;
  if p_shift_minutes is null or p_shift_minutes < 0 then
    raise exception 'Cascade shift minutes must be non-negative' using errcode = '22023';
  end if;

  if v_operation = 'insert' then
    select * into v_stage from public.workshop_stages
      where code = upper(trim(coalesce(p_stage_code, ''))) and active;
    if not found then raise exception 'Workshop stage not found' using errcode = 'P0002'; end if;
    select * into v_bay from public.workshop_bays
      where stage_id = v_stage.id and bay_number = p_bay_number and is_active;
    if not found then raise exception 'Workshop bay not found or inactive' using errcode = 'P0002'; end if;
    if p_shift_minutes <> p_duration_minutes then
      raise exception 'Insert cascade shift must equal inserted duration' using errcode = '22023';
    end if;
    perform 1 from public.vehicles where id = p_target_id and version = p_target_expected_version for update;
    if not found then return jsonb_build_object('ok', false, 'error', 'vehicle_version_conflict'); end if;
    if v_stage.is_physical and not public.workshop_parts_ready(p_target_id) then
      if p_override_reason is null or trim(p_override_reason) = '' then
        return jsonb_build_object('ok', false, 'error', 'parts_incomplete');
      end if;
      -- Future planning is not physical bay entry. The explicit reason is
  -- still written to workshop_parts_overrides, but any planner operator
  -- may create or move a planned booking before Parts are ready.
    end if;
  else
    select * into v_target from public.workshop_bookings where id = p_target_id for update;
    if not found then raise exception 'Workshop booking not found' using errcode = 'P0002'; end if;
    if v_target.version <> p_target_expected_version then
      return jsonb_build_object('ok', false, 'error', 'version_conflict', 'conflict', public.workshop_conflict_payload(v_target.id, 'version_conflict'));
    end if;
    if v_target.status = 'completed' then return jsonb_build_object('ok', false, 'error', 'completed_booking'); end if;
    if p_duration_minutes <= v_target.default_duration_minutes then
      return public.resize_workshop_booking(p_target_id, p_target_expected_version, p_duration_minutes, coalesce(p_metadata, '{}'::jsonb));
    end if;
    if p_shift_minutes <> p_duration_minutes - v_target.default_duration_minutes then
      raise exception 'Extend cascade shift must equal the duration increase' using errcode = '22023';
    end if;
    select * into v_stage from public.workshop_stages where id = v_target.stage_id;
    select * into v_bay from public.workshop_bays where id = v_target.bay_id;
    if upper(trim(coalesce(p_stage_code, ''))) <> v_stage.code or p_bay_number <> v_bay.bay_number then
      raise exception 'Extend cascade cannot change stage or bay' using errcode = '22023';
    end if;
    p_scheduled_start_at := v_target.scheduled_start_at;
  end if;

  select coalesce(array_agg(b.id order by b.scheduled_start_at, b.id), '{}'::uuid[])
    into v_expected_ids
  from public.workshop_bookings b
  where b.bay_id = v_bay.id and b.status = 'planned' and b.deleted_at is null
    and (case when v_operation = 'insert' then b.scheduled_start_at >= p_scheduled_start_at
              else b.id <> p_target_id and b.scheduled_start_at > v_target.scheduled_start_at end);

  perform 1 from public.workshop_bookings b where b.id = any(v_expected_ids) order by b.scheduled_start_at, b.id for update;

  -- Booking validation locks the vehicle row too. Acquire every affected
  -- vehicle before the bay lock so create/move/cascade share a non-cyclic
  -- booking -> vehicle -> bay order.
  perform 1 from public.vehicles v
  where v.id in (
    select b.vehicle_id from public.workshop_bookings b where b.id=any(v_expected_ids)
    union select case when v_operation='insert' then p_target_id else v_target.vehicle_id end
  )
  order by v.id
  for update;

  -- Lock booking rows before the bay resource everywhere. This matches
  -- move/resize and prevents a bay-lock/row-lock deadlock cycle.
  perform public.workshop_lock_resources(v_bay.id, null);

  -- A move-out RPC can hold a captured booking row while moving it to another
  -- bay because that legacy path locks only its destination bay. Revalidate
  -- every locked row before shifting anything. PostgreSQL rechecks the row
  -- after a concurrent updater commits, so a moved row fails this source-bay
  -- predicate and the whole cascade returns without partial movement.
  select count(*) into v_locked_count
  from public.workshop_bookings b
  where b.id = any(v_expected_ids)
    and b.bay_id = v_bay.id
    and b.status = 'planned'
    and b.deleted_at is null;
  if v_locked_count <> cardinality(v_expected_ids) then
    return jsonb_build_object(
      'ok', false,
      'error', 'concurrent_queue_change',
      'retry', true
    );
  end if;

  -- Keep the target action and every shifted timestamp in one subtransaction.
  -- If the protected target RPC returns a structured business rejection, the
  -- exception block rolls back all shifts and returns that rejection intact.
  begin
  for v_shifted in
    select * from public.workshop_bookings b
    where b.id = any(v_expected_ids)
      and b.bay_id = v_bay.id
      and b.status = 'planned'
      and b.deleted_at is null
    order by b.scheduled_start_at desc, b.id desc
  loop
    v_new_start := public.workshop_next_calendar_window(
      public.workshop_add_operational_minutes(v_shifted.scheduled_start_at, p_shift_minutes),
      v_shifted.default_duration_minutes
    );
    v_new_end := public.workshop_add_operational_minutes(v_new_start,v_shifted.default_duration_minutes);
    v_before := public.workshop_booking_snapshot(v_shifted.id);
    update public.workshop_bookings
      set scheduled_start_at = v_new_start,
          scheduled_end_at = v_new_end,
          updated_by = auth.uid(),
          version = version + 1
      where id = v_shifted.id
        and bay_id = v_bay.id
        and status = 'planned'
        and deleted_at is null;
    if not found then
      v_result := jsonb_build_object('ok', false, 'error', 'concurrent_queue_change', 'retry', true);
      raise exception 'Cascade queue changed' using errcode = 'P0001';
    end if;
    select technician_id into v_technician from public.workshop_booking_assignments
      where booking_id = v_shifted.id and released_at is null
      order by case when assignment_type = 'primary' then 0 else 1 end, assigned_at desc limit 1;
    perform public.workshop_upsert_primary_assignment(v_shifted.id, v_technician, v_new_start, v_new_end, 'cascade_shifted');
    v_after := public.workshop_booking_snapshot(v_shifted.id);
    perform public.workshop_write_history(v_shifted.id, 'cascade_shifted', v_before, v_after,
      coalesce(p_metadata, '{}'::jsonb) || jsonb_build_object('cascade_operation', v_operation, 'cascade_target_id', p_target_id));
  end loop;

  -- Validate the final technician allocation after every shifted timestamp is in place.
  for v_shifted in
    select * from public.workshop_bookings
    where id = any(v_expected_ids)
      and bay_id = v_bay.id
      and status = 'planned'
      and deleted_at is null
  loop
    v_conflict := public.workshop_find_bay_conflict(
      v_shifted.id, v_bay.id, v_shifted.scheduled_start_at, v_shifted.scheduled_end_at
    );
    if v_conflict is not null then
      v_result := jsonb_build_object(
        'ok', false,
        'error', 'bay_overlap',
        'conflict', public.workshop_conflict_payload(v_conflict, 'bay_overlap')
      );
      raise exception 'Cascade bay conflict' using errcode = 'P0001';
    end if;
    select technician_id into v_technician from public.workshop_booking_assignments
      where booking_id = v_shifted.id and released_at is null
      order by case when assignment_type = 'primary' then 0 else 1 end, assigned_at desc limit 1;
    if v_technician is not null then
      v_conflict := public.workshop_find_technician_conflict(v_shifted.id, v_technician, v_shifted.scheduled_start_at, v_shifted.scheduled_end_at);
      if v_conflict is not null then
        v_result := jsonb_build_object(
          'ok', false,
          'error', 'technician_overlap',
          'conflict', public.workshop_conflict_payload(v_conflict, 'technician_overlap')
        );
        raise exception 'Cascade technician conflict' using errcode = 'P0001';
      end if;
      if public.workshop_technician_leave_date(v_technician, v_shifted.scheduled_start_at, v_shifted.scheduled_end_at) is not null then
        v_result := jsonb_build_object('ok', false, 'error', 'technician_leave_conflict');
        raise exception 'Cascade technician leave conflict' using errcode = 'P0001';
      end if;
    end if;
  end loop;

  if v_operation = 'insert' then
    v_result := public.schedule_vehicle_work(
      p_target_id, p_target_expected_version, v_stage.code, v_bay.bay_number,
      p_scheduled_start_at, p_duration_minutes, p_technician_id, p_override_reason, coalesce(p_metadata, '{}'::jsonb)
    );
  else
    v_result := public.resize_workshop_booking(p_target_id, p_target_expected_version, p_duration_minutes, coalesce(p_metadata, '{}'::jsonb));
  end if;

  if coalesce((v_result->>'ok')::boolean, false) is not true then
    raise exception 'Atomic cascade target action failed' using errcode = 'P0001';
  end if;
  exception when sqlstate 'P0001' then
    if v_result is not null and coalesce((v_result->>'ok')::boolean, false) is not true then
      return v_result;
    end if;
    raise;
  end;

  return v_result || jsonb_build_object(
    'cascade_operation', v_operation,
    'shifted_booking_ids', to_jsonb(v_expected_ids),
    'shifted_count', cardinality(v_expected_ids)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.start_workshop_work(p_booking_id uuid, p_expected_version integer, p_actual_start_at timestamp with time zone DEFAULT now(), p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_target public.workshop_bookings%rowtype; v_shifted public.workshop_bookings%rowtype;
  v_now timestamptz:=date_trunc('minute',statement_timestamp()); v_new_end timestamptz;
  v_delta integer; v_result jsonb; v_revision bigint; v_before jsonb; v_after jsonb;
  v_technician uuid; v_queue_ids uuid[]:='{}'::uuid[];
  v_stage public.workshop_stages%rowtype; v_override_reason text; v_override_id uuid;
  v_parts_override_required boolean:=false;
begin
  perform public.workshop_require_planner_operator();
  perform public.workshop_require_version(p_expected_version);
  perform pg_advisory_xact_lock(hashtextextended('pdc:workshop:start:'||p_booking_id::text,0));
  select * into v_target from public.workshop_bookings where id=p_booking_id for update;
  if not found then raise exception 'Workshop booking not found' using errcode='P0002'; end if;
  if v_target.version<>p_expected_version then return jsonb_build_object('ok',false,'error','version_conflict'); end if;
  if v_target.status not in('queued','planned') or v_target.deleted_at is not null then return jsonb_build_object('ok',false,'error','not_startable'); end if;
  if v_target.bay_id is null then return jsonb_build_object('ok',false,'error','bay_required'); end if;
  if not public.workshop_calendar_minute_available(v_now) then return jsonb_build_object('ok',false,'error','calendar_unavailable'); end if;
  perform public.workshop_require_booking_active_vehicle(p_booking_id,false);

  select s.* into v_stage from public.workshop_stages s where s.id=v_target.stage_id;
  v_override_reason:=nullif(btrim(coalesce(p_metadata->>'parts_override_reason','')),'');
  if v_stage.is_physical and not public.workshop_parts_ready(v_target.vehicle_id) then
    if v_override_reason is null then
      return jsonb_build_object('ok',false,'error','parts_incomplete_entry');
    end if;
    perform public.require_pdc_role('administrator');
    v_parts_override_required:=true;
  end if;

  select coalesce(array_agg(b.id order by b.scheduled_start_at,b.id),'{}'::uuid[]) into v_queue_ids
  from public.workshop_bookings b
  where b.bay_id=v_target.bay_id and b.id<>v_target.id and b.deleted_at is null
    and b.status='planned' and b.scheduled_start_at>v_target.scheduled_start_at;
  perform 1 from public.workshop_bookings b where b.id=any(v_queue_ids) order by b.scheduled_start_at,b.id for update;
  perform 1 from public.workshop_bays where id=v_target.bay_id for update;

  if exists(select 1 from public.workshop_bookings b where b.bay_id=v_target.bay_id and b.id<>v_target.id and b.deleted_at is null and b.status='started') then
    return jsonb_build_object('ok',false,'error','bay_already_started');
  end if;

  v_delta:=case when v_now>=v_target.scheduled_start_at
    then public.workshop_operational_minutes_between(v_target.scheduled_start_at,v_now)
    else -public.workshop_operational_minutes_between(v_now,v_target.scheduled_start_at) end;
  v_new_end:=public.workshop_add_operational_minutes(v_now,v_target.default_duration_minutes);

  begin
    -- Moving later: clear destination space from the end backwards first.
    if v_delta>0 then
      for v_shifted in select * from public.workshop_bookings b where b.id=any(v_queue_ids) order by b.scheduled_start_at desc,b.id desc loop
        v_before:=public.workshop_booking_snapshot(v_shifted.id);
        update public.workshop_bookings set
          scheduled_start_at=public.workshop_shift_operational_minutes(v_shifted.scheduled_start_at,v_delta),
          scheduled_end_at=public.workshop_shift_operational_minutes(v_shifted.scheduled_end_at,v_delta),
          updated_by=auth.uid(),version=version+1 where id=v_shifted.id and status='planned' and deleted_at is null;
        if not found then raise exception 'Concurrent queue change' using errcode='P0001'; end if;
        select technician_id into v_technician from public.workshop_booking_assignments where booking_id=v_shifted.id and released_at is null order by case when assignment_type='primary' then 0 else 1 end,assigned_at desc limit 1;
        perform public.workshop_upsert_primary_assignment(v_shifted.id,v_technician,public.workshop_shift_operational_minutes(v_shifted.scheduled_start_at,v_delta),public.workshop_shift_operational_minutes(v_shifted.scheduled_end_at,v_delta),'start_cascade_shifted');
        v_after:=public.workshop_booking_snapshot(v_shifted.id);
        perform public.workshop_write_history(v_shifted.id,'start_cascade_shifted',v_before,v_after,coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('start_target_id',p_booking_id,'signed_shift_minutes',v_delta));
      end loop;
    end if;

    v_before:=public.workshop_booking_snapshot(v_target.id);
    update public.workshop_bookings set scheduled_start_at=v_now,scheduled_end_at=v_new_end,updated_by=auth.uid(),version=version+1 where id=v_target.id;
    select technician_id into v_technician from public.workshop_booking_assignments where booking_id=v_target.id and released_at is null order by case when assignment_type='primary' then 0 else 1 end,assigned_at desc limit 1;
    perform public.workshop_upsert_primary_assignment(v_target.id,v_technician,v_now,v_new_end,'start_snapped_to_now');
    v_after:=public.workshop_booking_snapshot(v_target.id);
    perform public.workshop_write_history(v_target.id,'start_snapped_to_now',v_before,v_after,coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('signed_shift_minutes',v_delta));

    -- Moving earlier: move later queued work from the front forwards after the
    -- target has vacated its old interval.
    if v_delta<0 then
      for v_shifted in select * from public.workshop_bookings b where b.id=any(v_queue_ids) order by b.scheduled_start_at,b.id loop
        v_before:=public.workshop_booking_snapshot(v_shifted.id);
        update public.workshop_bookings set
          scheduled_start_at=public.workshop_shift_operational_minutes(v_shifted.scheduled_start_at,v_delta),
          scheduled_end_at=public.workshop_shift_operational_minutes(v_shifted.scheduled_end_at,v_delta),
          updated_by=auth.uid(),version=version+1 where id=v_shifted.id and status='planned' and deleted_at is null;
        if not found then raise exception 'Concurrent queue change' using errcode='P0001'; end if;
        select technician_id into v_technician from public.workshop_booking_assignments where booking_id=v_shifted.id and released_at is null order by case when assignment_type='primary' then 0 else 1 end,assigned_at desc limit 1;
        perform public.workshop_upsert_primary_assignment(v_shifted.id,v_technician,public.workshop_shift_operational_minutes(v_shifted.scheduled_start_at,v_delta),public.workshop_shift_operational_minutes(v_shifted.scheduled_end_at,v_delta),'start_cascade_shifted');
        v_after:=public.workshop_booking_snapshot(v_shifted.id);
        perform public.workshop_write_history(v_shifted.id,'start_cascade_shifted',v_before,v_after,coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('start_target_id',p_booking_id,'signed_shift_minutes',v_delta));
      end loop;
    end if;

    v_result:=public.workshop_start_booking(p_booking_id,p_expected_version+1,v_now,coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('database_clock_start',true));
    if not coalesce((v_result->>'ok')::boolean,false) then raise exception 'Protected start rejected' using errcode='P0001'; end if;
    if v_parts_override_required then
      insert into public.workshop_parts_overrides(
        vehicle_id,booking_id,work_key,intended_stage_id,reason,
        previous_state,resulting_state,approved_by,approved_by_email
      ) values(
        v_target.vehicle_id,v_target.id,'PARTS',v_stage.id,v_override_reason,
        v_before,public.workshop_booking_snapshot(v_target.id),auth.uid(),public.current_actor_email()
      ) returning id into v_override_id;
    end if;
  exception
    when exclusion_violation or unique_violation or sqlstate '22023' then
      return jsonb_build_object('ok',false,'error','fixed_booking_conflict');
    when sqlstate 'P0001' then
      return jsonb_build_object('ok',false,'error','concurrent_queue_change','retry',true);
  end;
  v_revision:=public.workshop_bump_revision();
  return v_result||jsonb_build_object('revision',v_revision,'signed_shift_minutes',v_delta,'parts_override_id',v_override_id);
end $function$;

revoke all on function public.schedule_vehicle_work(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb) from public,anon;
grant execute on function public.schedule_vehicle_work(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb) to authenticated;
revoke all on function public.move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb) from public,anon;
grant execute on function public.move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb) to authenticated;
revoke all on function public.cascade_workshop_schedule(text,uuid,integer,text,integer,timestamptz,integer,uuid,integer,text,jsonb) from public,anon;
grant execute on function public.cascade_workshop_schedule(text,uuid,integer,text,integer,timestamptz,integer,uuid,integer,text,jsonb) to authenticated;
revoke all on function public.start_workshop_work(uuid,integer,timestamptz,jsonb) from public,anon;
grant execute on function public.start_workshop_work(uuid,integer,timestamptz,jsonb) to authenticated;

commit;
