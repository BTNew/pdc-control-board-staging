-- Staging-only migration 106: atomic booked-chip moves between Workshop bays.
-- The dropped booking keeps the requested bay/time. Planned work occupying
-- that position, plus every later planned booking in the destination bay,
-- is shifted by one common operational-minute delta so order, gaps, duration
-- and configured calendars are preserved. Live work is never shifted.

begin;

do $guard$
begin
  if not exists (
    select 1 from public.pdc_staging_environment_sentinel
    where singleton and project_ref='cdsmnqxtyyoeoznmbidd'
  ) then raise exception 'PDC_STAGING_SENTINEL_MISMATCH'; end if;
  if exists (
    select 1 from public.pdc_staging_environment_sentinel
    where project_ref='vjdtsswhroyguxyfjdkt'
  ) then raise exception 'PDC_PRODUCTION_SENTINEL_PRESENT'; end if;
  if not exists (
    select 1 from supabase_migrations.schema_migrations
    where version='105' and name='authenticated_operation_hours_exact_replay'
  ) then raise exception 'PDC_MIGRATION_105_PREREQUISITE_MISSING'; end if;
  if to_regprocedure('public.workshop_require_planner_operator()') is null
     or to_regprocedure('public.workshop_require_version(integer)') is null
     or to_regprocedure('public.workshop_lock_resources(uuid,uuid)') is null
     or to_regprocedure('public.workshop_add_operational_minutes(timestamptz,integer)') is null
     or to_regprocedure('public.workshop_shift_operational_minutes(timestamptz,integer)') is null
     or to_regprocedure('public.workshop_operational_minutes_between(timestamptz,timestamptz)') is null
     or to_regprocedure('public.move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb)') is null
     or to_regprocedure('public.workshop_upsert_primary_assignment(uuid,uuid,timestamptz,timestamptz,text)') is null
     or to_regprocedure('public.workshop_booking_snapshot(uuid)') is null
     or to_regprocedure('public.workshop_write_history(uuid,text,jsonb,jsonb,jsonb)') is null
  then raise exception 'PDC_WORKSHOP_MOVE_CASCADE_DEPENDENCY_MISSING'; end if;
end
$guard$;

create or replace function public.cascade_workshop_booking_move(
  p_booking_id uuid,
  p_expected_version integer,
  p_stage_code text,
  p_bay_number integer,
  p_scheduled_start_at timestamptz,
  p_duration_minutes integer,
  p_override_reason text default null,
  p_metadata jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path=public,auth
as $fn$
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
begin
  perform public.workshop_require_planner_operator();
  perform public.workshop_require_version(p_expected_version);
  perform pg_advisory_xact_lock(hashtextextended('pdc:workshop:cascade-move',0));

  if p_duration_minutes is null or p_duration_minutes<60 then
    return jsonb_build_object('ok',false,'error','minimum_duration','minimum_minutes',60);
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

  v_target_end:=public.workshop_add_operational_minutes(p_scheduled_start_at,p_duration_minutes);
  if v_target_end is null or v_target_end<=p_scheduled_start_at then
    return jsonb_build_object('ok',false,'error','calendar_unavailable');
  end if;

  -- Started/stoppage rows are fixed. Never push live work.
  if exists (
    select 1 from public.workshop_bookings b
    where b.bay_id=v_bay.id and b.deleted_at is null
      and b.status in('started','stoppage')
      and b.scheduled_start_at<v_target_end
      and b.scheduled_end_at>p_scheduled_start_at
  ) then return jsonb_build_object('ok',false,'error','live_booking_conflict'); end if;

  select coalesce(array_agg(b.id order by b.scheduled_start_at,b.id),'{}'::uuid[]),
         min(b.scheduled_start_at)
  into v_expected_ids,v_first_start
  from public.workshop_bookings b
  where b.bay_id=v_bay.id and b.id<>p_booking_id
    and b.status='planned' and b.deleted_at is null
    and b.scheduled_end_at>p_scheduled_start_at;

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
      and b.scheduled_end_at>p_scheduled_start_at
  ) then return jsonb_build_object('ok',false,'error','live_booking_conflict'); end if;

  select coalesce(array_agg(b.id order by b.scheduled_start_at,b.id),'{}'::uuid[]),count(*)
  into v_current_ids,v_locked_count
  from public.workshop_bookings b
  where b.bay_id=v_bay.id and b.id<>p_booking_id
    and b.status='planned' and b.deleted_at is null
    and b.scheduled_end_at>p_scheduled_start_at;
  if v_locked_count<>cardinality(v_expected_ids) or v_current_ids<>v_expected_ids then
    return jsonb_build_object('ok',false,'error','concurrent_queue_change','retry',true);
  end if;

  if v_first_start is not null and v_first_start<v_target_end then
    v_shift_minutes:=public.workshop_operational_minutes_between(v_first_start,v_target_end);
  end if;

  begin
    if v_shift_minutes>0 then
      -- Latest-first clears destination space without transient planned-row overlap.
      for v_shifted in
        select * from public.workshop_bookings b
        where b.id=any(v_expected_ids) and b.bay_id=v_bay.id
          and b.status='planned' and b.deleted_at is null
        order by b.scheduled_start_at desc,b.id desc
      loop
        v_new_start:=public.workshop_shift_operational_minutes(v_shifted.scheduled_start_at,v_shift_minutes);
        v_new_end:=public.workshop_shift_operational_minutes(v_shifted.scheduled_end_at,v_shift_minutes);
        v_before:=public.workshop_booking_snapshot(v_shifted.id);
        update public.workshop_bookings
        set scheduled_start_at=v_new_start,
            scheduled_end_at=v_new_end,
            updated_by=auth.uid(),
            version=version+1
        where id=v_shifted.id and bay_id=v_bay.id
          and status='planned' and deleted_at is null;
        if not found then
          v_result:=jsonb_build_object('ok',false,'error','concurrent_queue_change','retry',true);
          raise exception 'Cascade move queue changed' using errcode='P0001';
        end if;
        select a.technician_id into v_technician
        from public.workshop_booking_assignments a
        where a.booking_id=v_shifted.id and a.released_at is null
        order by case when a.assignment_type='primary' then 0 else 1 end,a.assigned_at desc
        limit 1;
        perform public.workshop_upsert_primary_assignment(
          v_shifted.id,v_technician,v_new_start,v_new_end,'cascade_move_shifted'
        );
        v_after:=public.workshop_booking_snapshot(v_shifted.id);
        perform public.workshop_write_history(
          v_shifted.id,'cascade_move_shifted',v_before,v_after,
          coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object(
            'cascade_target_id',p_booking_id,
            'signed_shift_minutes',v_shift_minutes
          )
        );
      end loop;
    end if;

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
    'cascade_shifted_booking_ids',to_jsonb(v_expected_ids),
    'cascade_shift_minutes',v_shift_minutes,
    'shifted_booking_ids',to_jsonb(v_expected_ids),
    'shift_minutes',v_shift_minutes,
    'shifted_count',cardinality(v_expected_ids)
  );
end
$fn$;

revoke all on function public.cascade_workshop_booking_move(uuid,integer,text,integer,timestamptz,integer,text,jsonb) from public,anon,authenticated;
grant execute on function public.cascade_workshop_booking_move(uuid,integer,text,integer,timestamptz,integer,text,jsonb) to authenticated;
comment on function public.cascade_workshop_booking_move(uuid,integer,text,integer,timestamptz,integer,text,jsonb)
is 'Atomically moves a planned booking across bays and shifts all conflicting/later planned destination work. Live work is fixed.';

commit;
