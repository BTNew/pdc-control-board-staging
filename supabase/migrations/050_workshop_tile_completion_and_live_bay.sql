-- 050: Workshop tile completion, customer display and physical-bay live-job safety.
-- Forward-only staging migration. Bay identity is the workshop_bays UUID, so
-- identically numbered bays in different departments remain independent.

begin;
set local lock_timeout = '5s';

-- Never rewrite operational rows to make this guard pass. Existing duplicates
-- require explicit review before the migration can proceed.
do $$
begin
  if exists (
    select 1
    from public.workshop_bookings
    where deleted_at is null and status='started' and bay_id is not null
    group by bay_id having count(*)>1
  ) then
    raise exception 'Migration 050 blocked: a physical bay has multiple started jobs' using errcode='23514';
  end if;
end $$;

create unique index if not exists workshop_bookings_one_started_per_bay_uidx
on public.workshop_bookings (bay_id)
where deleted_at is null and status='started' and bay_id is not null;

-- Signed operational movement for Start-to-now. Positive shifts move later;
-- negative shifts move earlier while still skipping breaks, closures and
-- non-working minutes.
create or replace function public.workshop_shift_operational_minutes(p_start timestamptz,p_delta_minutes integer)
returns timestamptz language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare v_cursor timestamptz:=date_trunc('minute',p_start); v_remaining integer; v_limit timestamptz;
begin
  if p_start is null or p_delta_minutes is null then raise exception 'Operational shift inputs are required' using errcode='22023'; end if;
  if p_delta_minutes>=0 then return public.workshop_add_operational_minutes(v_cursor,p_delta_minutes); end if;
  v_remaining:=-p_delta_minutes; v_limit:=v_cursor-interval '90 days';
  while v_remaining>0 and v_cursor>v_limit loop
    v_cursor:=v_cursor-interval '1 minute';
    if public.workshop_calendar_minute_available(v_cursor) then v_remaining:=v_remaining-1; end if;
  end loop;
  if v_remaining>0 then raise exception 'Operational shift exceeded canonical calendar guard' using errcode='22023'; end if;
  return v_cursor;
end $$;
revoke all on function public.workshop_shift_operational_minutes(timestamptz,integer) from public,anon,authenticated;

-- Start is database-clock authoritative: snap the target to now, preserve its
-- planned duration and atomically apply the same signed movement to later
-- planned work in this exact physical bay. Started/stopped/completed work is
-- fixed and is never moved. The partial unique index remains the race-safe final
-- authority for one started job per bay.
create or replace function public.start_workshop_work(
  p_booking_id uuid,p_expected_version integer,p_actual_start_at timestamptz default now(),p_metadata jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare
  v_target public.workshop_bookings%rowtype; v_shifted public.workshop_bookings%rowtype;
  v_now timestamptz:=date_trunc('minute',statement_timestamp()); v_new_end timestamptz;
  v_delta integer; v_result jsonb; v_revision bigint; v_before jsonb; v_after jsonb;
  v_technician uuid; v_queue_ids uuid[]:='{}'::uuid[];
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
  exception
    when exclusion_violation or unique_violation or sqlstate '22023' then
      return jsonb_build_object('ok',false,'error','fixed_booking_conflict');
    when sqlstate 'P0001' then
      return jsonb_build_object('ok',false,'error','concurrent_queue_change','retry',true);
  end;
  v_revision:=public.workshop_bump_revision();
  return v_result||jsonb_build_object('revision',v_revision,'signed_shift_minutes',v_delta);
end $$;
revoke all on function public.start_workshop_work(uuid,integer,timestamptz,jsonb) from public,anon;
grant execute on function public.start_workshop_work(uuid,integer,timestamptz,jsonb) to authenticated;

-- Completion signs off the canonical station work item in the same transaction.
-- required=true is retained as historical intent; completed=true removes it from
-- outstanding eligibility. Cycling the work state back to "needs work" resets
-- completed=false through the normal vehicle-work-item editor.
create or replace function public.complete_workshop_work(
  p_booking_id uuid,p_expected_version integer,p_work_key text default null,p_actual_end_at timestamptz default now(),p_metadata jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_booking public.workshop_bookings%rowtype; v_stage_code text; v_stage_work_key text; v_requested_stage text; v_result jsonb; v_revision bigint;
begin
  perform public.workshop_require_planner_operator(); perform public.workshop_require_version(p_expected_version);
  perform public.workshop_require_booking_active_vehicle(p_booking_id,false);
  select * into v_booking from public.workshop_bookings where id=p_booking_id for update;
  if not found then raise exception 'Workshop booking not found' using errcode='P0002'; end if;
  select code,work_key into v_stage_code,v_stage_work_key from public.workshop_stages where id=v_booking.stage_id;
  if p_work_key is not null and btrim(p_work_key)<>'' then
    v_requested_stage:=public.workshop_stage_code_for_work_key(p_work_key);
    if v_requested_stage is distinct from v_stage_code then raise exception 'Completion work item does not match booking station' using errcode='22023'; end if;
  end if;
  v_result:=public.workshop_complete_booking(p_booking_id,p_expected_version,p_actual_end_at,p_metadata);
  if not (v_result->>'ok')::boolean then return v_result; end if;
  update public.vehicle_work_items set completed=true,completed_by=auth.uid(),completed_at=p_actual_end_at,updated_at=now()
  where vehicle_id=v_booking.vehicle_id and required and public.workshop_stage_code_for_work_key(work_key)=v_stage_code;
  if not found and v_stage_work_key is not null then
    insert into public.vehicle_work_items(vehicle_id,work_key,required,completed,completed_by,completed_at)
    values(v_booking.vehicle_id,v_stage_work_key,true,true,auth.uid(),p_actual_end_at)
    on conflict(vehicle_id,work_key) do update set required=true,completed=true,completed_by=auth.uid(),completed_at=excluded.completed_at,updated_at=now();
  end if;
  v_revision:=public.workshop_bump_revision();
  return v_result||jsonb_build_object('revision',v_revision,'work_item_completed',true);
end $$;
revoke all on function public.complete_workshop_work(uuid,integer,text,timestamptz,jsonb) from public,anon;
grant execute on function public.complete_workshop_work(uuid,integer,text,timestamptz,jsonb) to authenticated;

-- Restricted operator/admin station projection. Customer name is approved for
-- the Workshop tile; notes, audit, metadata and other broad vehicle fields stay
-- excluded.
create or replace function public.get_station_workshop_snapshot(p_stage_code text,p_date_from date,p_date_to date)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare v_stage text; v_stage_id uuid; v_from timestamptz; v_to timestamptz; v_ids uuid[];
begin
 perform public.workshop_require_planner_operator();
 v_stage:=public.workshop_canonical_stage_code(p_stage_code);
 select id into v_stage_id from public.workshop_stages where code=v_stage and active and planner_enabled;
 if v_stage_id is null then raise exception 'Unknown, inactive or planner-disabled workshop station' using errcode='22023'; end if;
 if p_date_from is null or p_date_to is null or p_date_to<p_date_from or p_date_to>p_date_from+31 then raise exception 'Invalid station planner date range' using errcode='22023'; end if;
 v_from:=p_date_from::timestamp at time zone 'Australia/Perth'; v_to:=(p_date_to+1)::timestamp at time zone 'Australia/Perth';
 select coalesce(array_agg(distinct q.vehicle_id),'{}'::uuid[]) into v_ids from(
  select e.vehicle_id from public.workshop_station_eligibility(v_stage)e
  union
  select b.vehicle_id from public.workshop_bookings b join public.vehicles v on v.id=b.vehicle_id and v.lifecycle_state='active' and v.deleted_at is null
  where b.stage_id=v_stage_id and b.deleted_at is null and b.status in('queued','planned','started','stoppage','completed')
   and((b.status in('queued','planned') and b.scheduled_start_at<v_to and b.scheduled_end_at>v_from)
    or(b.status in('started','stoppage') and b.scheduled_start_at<v_to)
    or(b.status='completed' and b.actual_end_at>=v_from and b.actual_end_at<v_to))
 )q;
 return jsonb_build_object(
  'revision',public.workshop_current_station_revision(v_stage),'generated_at',now(),
  'semantics',jsonb_build_object('outstanding_candidates','required canonical work items not completed and location-visible','unscheduled_candidates','outstanding candidates without any active booking','selected_date_bookings','scheduled rows intersecting the date plus started or stopped work carried forward until resolved'),
  'scope',jsonb_build_object('stage_code',v_stage,'date_from',p_date_from,'date_to',p_date_to),
  'counts',jsonb_build_object(
   'outstanding_candidates',(select count(*) from public.workshop_station_eligibility(v_stage)),
   'unscheduled_candidates',(select count(*) from public.workshop_station_eligibility(v_stage)e where not e.existing_booking),
   'selected_date_bookings',(select count(*) from public.workshop_bookings b join public.vehicles v on v.id=b.vehicle_id and v.lifecycle_state='active' and v.deleted_at is null where b.stage_id=v_stage_id and b.deleted_at is null and b.status in('queued','planned','started','stoppage','completed') and((b.status in('queued','planned') and b.scheduled_start_at<v_to and b.scheduled_end_at>v_from)or(b.status in('started','stoppage') and b.scheduled_start_at<v_to)or(b.status='completed' and b.actual_end_at>=v_from and b.actual_end_at<v_to)))),
  'stages',(select jsonb_agg(jsonb_build_object('id',s.id,'code',s.code,'display_name',s.display_name,'is_physical',s.is_physical,'work_key',s.work_key)) from public.workshop_stages s where s.id=v_stage_id),
  'bays',(select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'bay_number',b.bay_number,'code',b.code,'display_name',b.display_name) order by b.bay_number),'[]'::jsonb) from public.workshop_bays b where b.stage_id=v_stage_id and b.is_active),
  'outstanding_candidates',(select coalesce(jsonb_agg(jsonb_build_object('vehicle_id',e.vehicle_id,'existing_booking',e.existing_booking,'schedule_enabled',e.schedule_enabled,'disabled_reason',e.disabled_reason,'requirements',(select coalesce(jsonb_agg(jsonb_build_object('vehicle_id',wi.vehicle_id,'work_key',wi.work_key,'required',wi.required,'completed',wi.completed,'completed_at',wi.completed_at) order by wi.work_key),'[]'::jsonb) from public.vehicle_work_items wi where wi.vehicle_id=e.vehicle_id and wi.required and not wi.completed)) order by e.vehicle_id),'[]'::jsonb) from public.workshop_station_eligibility(v_stage)e),
  'bookings',(select coalesce(jsonb_agg(public.workshop_planner_booking_dto(b.id) order by b.scheduled_start_at,b.id),'[]'::jsonb) from public.workshop_bookings b join public.vehicles v on v.id=b.vehicle_id and v.lifecycle_state='active' and v.deleted_at is null where b.stage_id=v_stage_id and b.vehicle_id=any(v_ids) and b.deleted_at is null and b.status in('queued','planned','started','stoppage','completed') and((b.status in('queued','planned') and b.scheduled_start_at<v_to and b.scheduled_end_at>v_from)or(b.status in('started','stoppage') and b.scheduled_start_at<v_to)or(b.status='completed' and b.actual_end_at>=v_from and b.actual_end_at<v_to))),
  'vehicles',(select coalesce(jsonb_agg(jsonb_build_object('id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,'stock_number',v.stock_number,'toyota_order_number',v.toyota_order_number,'job_card_number',v.job_card_number,'customer_name',v.customer_name,'make',v.make,'model',v.model,'registration',v.registration,'current_location',v.current_location,'pmb_stage',v.pmb_stage,'pmb_bay_stage',v.pmb_bay_stage,'pmb_bay_number',v.pmb_bay_number,'eta_to_kewdale',v.eta_to_kewdale,'active_workshop_booking_id',v.active_workshop_booking_id,'workshop_status',v.workshop_status,'version',v.version) order by v.stock_number nulls last,v.id),'[]'::jsonb) from public.vehicles v where v.id=any(v_ids) and v.lifecycle_state='active' and v.deleted_at is null),
  'work_items',(select coalesce(jsonb_agg(jsonb_build_object('vehicle_id',wi.vehicle_id,'work_key',wi.work_key,'required',wi.required,'completed',wi.completed,'completed_at',wi.completed_at) order by wi.vehicle_id,wi.work_key),'[]'::jsonb) from public.vehicle_work_items wi where wi.vehicle_id=any(v_ids) and public.workshop_stage_code_for_work_key(wi.work_key)=v_stage)
 );
end $$;
revoke all on function public.get_station_workshop_snapshot(text,date,date) from public,anon,authenticated;
grant execute on function public.get_station_workshop_snapshot(text,date,date) to authenticated;
comment on function public.get_station_workshop_snapshot(text,date,date) is 'Operator/admin-only station DTO. Includes customer name for Workshop tiles; excludes notes, audit and broad vehicle payloads.';

commit;
