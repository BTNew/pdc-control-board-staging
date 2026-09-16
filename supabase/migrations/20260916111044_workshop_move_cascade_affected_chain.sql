-- Move only destination bookings actually displaced by a drag.
-- Existing actor, receipt, QA, fixed-work and per-booking conflict guards remain.
DO $guard$
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'Workshop affected-chain repair is staging only';
  END IF;
  IF md5(pg_get_functiondef('public.cascade_workshop_booking_move_pre_116(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb)'::regprocedure))
     <> '50117826a424754a47b092b5987c5437' THEN
    RAISE EXCEPTION 'Workshop move cascade source changed; review before applying';
  END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.cascade_workshop_booking_move_pre_116(p_booking_id uuid, p_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer, p_override_reason text DEFAULT NULL::text, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
declare
  v_target public.workshop_bookings%rowtype;
  v_shifted public.workshop_bookings%rowtype;
  v_stage public.workshop_stages%rowtype;
  v_bay public.workshop_bays%rowtype;
  v_expected_ids uuid[]:='{}'::uuid[];
  v_current_ids uuid[]:='{}'::uuid[];
  v_locked_count integer:=0;
  v_first_start timestamptz;
  v_target_end timestamptz;
  v_shift_minutes integer:=0;
  v_new_start timestamptz;
  v_new_end timestamptz;
  v_technician uuid;
  v_before jsonb;
  v_after jsonb;
  v_result jsonb;
  v_target_duration integer;
  v_row_duration integer;
  v_cursor timestamptz;
  v_plan jsonb := '[]'::jsonb;
  v_step jsonb;
  v_changed_ids uuid[] := '{}'::uuid[];
begin
  perform public.workshop_require_planner_operator();
  perform public.workshop_require_version(p_expected_version);
  perform pg_advisory_xact_lock(hashtextextended('pdc:workshop:cascade-move',0));

  if p_duration_minutes is null or p_duration_minutes<1 then
    return jsonb_build_object('ok',false,'error','minimum_duration','minimum_minutes',1);
  end if;
  if p_scheduled_start_at is null then
    return jsonb_build_object('ok',false,'error','invalid_schedule_interval');
  end if;

  select * into v_target
  from public.workshop_bookings b
  where b.id=p_booking_id
  for update;
  if not found then raise exception 'Workshop booking not found' using errcode='P0002'; end if;
  if v_target.version<>p_expected_version then
    return jsonb_build_object('ok',false,'error','version_conflict',
      'conflict',public.workshop_conflict_payload(v_target.id,'version_conflict'));
  end if;
  if v_target.deleted_at is not null or v_target.status<>'planned' then
    return jsonb_build_object('ok',false,'error','planned_booking_required');
  end if;

  select * into v_stage
  from public.workshop_stages s
  where s.code=upper(btrim(coalesce(p_stage_code,'')))
    and s.active and s.planner_enabled;
  if not found then return jsonb_build_object('ok',false,'error','stage_inactive_or_missing'); end if;

  select * into v_bay
  from public.workshop_bays b
  where b.stage_id=v_stage.id and b.bay_number=p_bay_number and b.is_active;
  if not found then return jsonb_build_object('ok',false,'error','bay_inactive_or_wrong_station'); end if;

  -- Exact same-bay time moves retain the ordinary conflict-checked move path.
  if v_target.bay_id=v_bay.id then
    return jsonb_build_object('ok',false,'error','same_bay_move_requires_open_slot');
  end if;

  -- The protected move recalculates planned duration in the destination bay.
  -- Build this chain from the same capacity basis, including slower bays.
  v_target_duration:=public.workshop_booking_capacity_duration_minutes(
    p_booking_id,v_target.vehicle_id,v_stage.id,v_bay.id);
  if v_target_duration is null or v_target_duration<1 then
    return jsonb_build_object('ok',false,'error','minimum_duration','minimum_minutes',1);
  end if;
  v_target_end:=public.workshop_add_operational_minutes(p_scheduled_start_at,v_target_duration);
  if v_target_end is null or v_target_end<=p_scheduled_start_at then
    return jsonb_build_object('ok',false,'error','calendar_unavailable');
  end if;

  -- Started/stoppage rows are fixed. Never push live work.
  if exists (
    select 1 from public.workshop_bookings b
    where b.bay_id=v_bay.id and b.deleted_at is null
      and b.status in('started','stoppage')
      and b.scheduled_start_at<v_target_end
      and public.workshop_booking_effective_end_at(b.id)>p_scheduled_start_at
  ) then return jsonb_build_object('ok',false,'error','live_booking_conflict'); end if;

  select coalesce(array_agg(b.id order by b.scheduled_start_at,b.id),'{}'::uuid[]),
         min(b.scheduled_start_at)
  into v_expected_ids,v_first_start
  from public.workshop_bookings b
  where b.bay_id=v_bay.id and b.id<>p_booking_id
    and b.status='planned' and b.deleted_at is null
    and public.workshop_booking_effective_end_at(b.id)>p_scheduled_start_at;

  -- Stable global order: target booking, affected bookings, vehicles, bay, technicians.
  perform 1 from public.workshop_bookings b
  where b.id=any(v_expected_ids)
  order by b.id
  for update;

  perform 1 from public.vehicles v
  where v.id in (
    select b.vehicle_id from public.workshop_bookings b where b.id=any(v_expected_ids)
    union select v_target.vehicle_id
  )
  order by v.id
  for update;

  perform public.workshop_lock_resources(v_bay.id,null);
  for v_technician in
    select distinct a.technician_id
    from public.workshop_booking_assignments a
    where (a.booking_id=any(v_expected_ids) or a.booking_id=p_booking_id)
      and a.released_at is null
      and a.technician_id is not null
    order by a.technician_id
  loop
    perform public.workshop_lock_resources(null,v_technician);
  end loop;

  if exists (
    select 1 from public.workshop_bookings b
    where b.bay_id=v_bay.id and b.deleted_at is null
      and b.status in('started','stoppage')
      and b.scheduled_start_at<v_target_end
      and public.workshop_booking_effective_end_at(b.id)>p_scheduled_start_at
  ) then return jsonb_build_object('ok',false,'error','live_booking_conflict'); end if;

  select coalesce(array_agg(b.id order by b.scheduled_start_at,b.id),'{}'::uuid[]),count(*)
  into v_current_ids,v_locked_count
  from public.workshop_bookings b
  where b.bay_id=v_bay.id and b.id<>p_booking_id
    and b.status='planned' and b.deleted_at is null
    and public.workshop_booking_effective_end_at(b.id)>p_scheduled_start_at;
  if v_locked_count<>cardinality(v_expected_ids) or v_current_ids<>v_expected_ids then
    return jsonb_build_object('ok',false,'error','concurrent_queue_change','retry',true);
  end if;

  -- Only the overlapping forward chain belongs to this move. A gap absorbs
  -- displacement; bookings beyond it keep their exact interval and version.
  -- Keep the existing queue/resource locks and QA boundary wrapper unchanged.
  v_cursor:=v_target_end;
  for v_shifted in
    select * from public.workshop_bookings b
    where b.id=any(v_expected_ids) and b.bay_id=v_bay.id
      and b.status='planned' and b.deleted_at is null
    order by b.scheduled_start_at,b.id
  loop
    exit when v_shifted.scheduled_start_at>=v_cursor;
    v_new_start:=public.workshop_admin_next_operational_minute(v_cursor);
    v_row_duration:=coalesce(public.workshop_booking_capacity_duration_minutes(
      v_shifted.id,v_shifted.vehicle_id,v_shifted.stage_id,v_shifted.bay_id),
      public.workshop_booking_effective_duration_minutes(v_shifted.id));
    v_new_end:=public.workshop_add_operational_minutes(v_new_start,v_row_duration);
    if v_new_start is null or v_row_duration is null or v_row_duration<1
       or v_new_end is null or v_new_end<=v_new_start then
      return jsonb_build_object('ok',false,'error','calendar_unavailable');
    end if;
    v_shift_minutes:=greatest(v_shift_minutes,
      public.workshop_operational_minutes_between(v_shifted.scheduled_start_at,v_new_start));
    v_plan:=v_plan||jsonb_build_array(jsonb_build_object(
      'id',v_shifted.id,'version',v_shifted.version,
      'start_at',v_new_start,'end_at',v_new_end,'duration_minutes',v_row_duration,
      'shift_minutes',public.workshop_operational_minutes_between(v_shifted.scheduled_start_at,v_new_start)));
    v_changed_ids:=array_append(v_changed_ids,v_shifted.id);
    v_cursor:=v_new_end;
  end loop;

  begin
    -- Latest-first releases only required destination space. Every ordinary
    -- booking/assignment/admin/vehicle/technician guard remains active.
    for v_step in
      select item.value from jsonb_array_elements(v_plan) with ordinality item(value,ordinal)
      order by item.ordinal desc
    loop
      v_before:=public.workshop_booking_snapshot((v_step->>'id')::uuid);
      v_new_start:=(v_step->>'start_at')::timestamptz;
      v_new_end:=(v_step->>'end_at')::timestamptz;
      update public.workshop_bookings
      set scheduled_start_at=v_new_start,
          scheduled_end_at=v_new_end,
          default_duration_minutes=(v_step->>'duration_minutes')::integer,
          updated_by=auth.uid(),
          version=version+1
      where id=(v_step->>'id')::uuid and version=(v_step->>'version')::integer
        and bay_id=v_bay.id and status='planned' and deleted_at is null;
      if not found then
        v_result:=jsonb_build_object('ok',false,'error','concurrent_queue_change','retry',true);
        raise exception 'Cascade move queue changed' using errcode='P0001';
      end if;
      select a.technician_id into v_technician
      from public.workshop_booking_assignments a
      where a.booking_id=(v_step->>'id')::uuid and a.released_at is null
      order by case when a.assignment_type='primary' then 0 else 1 end,a.assigned_at desc
      limit 1;
      perform public.workshop_upsert_primary_assignment(
        (v_step->>'id')::uuid,v_technician,v_new_start,v_new_end,'cascade_move_shifted'
      );
      v_after:=public.workshop_booking_snapshot((v_step->>'id')::uuid);
      perform public.workshop_write_history(
        (v_step->>'id')::uuid,'cascade_move_shifted',v_before,v_after,
        coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object(
          'cascade_target_id',p_booking_id,
          'signed_shift_minutes',(v_step->>'shift_minutes')::integer,
          'affected_overlap_chain',true
        )
      );
    end loop;

    v_result:=public.move_workshop_booking(
      p_booking_id,p_expected_version,v_stage.code,v_bay.bay_number,
      p_scheduled_start_at,p_duration_minutes,p_override_reason,
      coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('cascade_move',true)
    );
    if coalesce((v_result->>'ok')::boolean,false) is not true then
      raise exception 'Atomic cascade move target failed' using errcode='P0001';
    end if;
  exception when sqlstate 'P0001' then
    if v_result is not null and coalesce((v_result->>'ok')::boolean,false) is not true then
      return v_result;
    end if;
    raise;
  end;

  return v_result||jsonb_build_object(
    'cascade_shifted_booking_ids',to_jsonb(v_changed_ids),
    'cascade_shift_minutes',v_shift_minutes,
    'shifted_booking_ids',to_jsonb(v_changed_ids),
    'shift_minutes',v_shift_minutes,
    'shifted_count',cardinality(v_changed_ids)
  );
end
$function$;
