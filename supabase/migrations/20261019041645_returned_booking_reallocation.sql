-- Restore queued, unstarted reservations to a real bay through the existing
DO $environment$ BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'Staging only'; END IF;
END $environment$;

DO $guard$ BEGIN
IF md5(pg_get_functiondef('public.get_workshop_booking_search_scoped(jsonb)'::regprocedure)) <> '4940eb35cd8824940231166d11093eaa' THEN RAISE EXCEPTION 'Source changed: get_workshop_booking_search_scoped'; END IF;
IF md5(pg_get_functiondef('public.workshop_enforce_booking_lifecycle()'::regprocedure)) <> '77682f3106134006e1fcb99939757d9a' THEN RAISE EXCEPTION 'Source changed: workshop_enforce_booking_lifecycle'; END IF;
END $guard$;
CREATE OR REPLACE FUNCTION public.workshop_enforce_booking_lifecycle()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare v_allowed boolean:=false;
BEGIN
 IF TG_OP='UPDATE' AND pdc_navision_delivery_private.allowed_booking_cancel(to_jsonb(OLD),to_jsonb(NEW)) THEN RETURN NEW; END IF;

 if tg_op='UPDATE' and new.status='completed' and old.status in ('queued','planned','started','stoppage')
  and (to_jsonb(new)-array['status','version','updated_by','updated_at']) is not distinct from (to_jsonb(old)-array['status','version','updated_by','updated_at'])
  and (exists(select 1 from pdc_codex_intake_private.tune_pmb_complete_receipts r
      join public.workshop_stages s on s.id=new.stage_id
      where r.vehicle_id=new.vehicle_id and r.transaction_id=txid_current() and r.actor_id=new.updated_by
      and s.code in('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE')) or exists(select 1 from pdc_codex_intake_private.tune_checkout_receipts r where r.vehicle_id=new.vehicle_id and r.transaction_id=txid_current() and r.actor_id=new.updated_by))
 then return new; end if;
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
  -- Rebooking an unstarted returned reservation is a protected move, not a restart.
  if old.status='queued' and new.status='planned'
    and old.bay_id is null and new.bay_id is not null
    and old.returned_to_queue_at is not null
    and old.actual_start_at is null and new.actual_start_at is null
    and old.actual_end_at is null and new.actual_end_at is null
    and old.id=new.id and old.vehicle_id=new.vehicle_id
    and new.returned_to_queue_at is not distinct from old.returned_to_queue_at
    and new.version=old.version+1 and new.updated_by=auth.uid()
    and coalesce(nullif(current_setting('pdc.workshop_capacity_manual',true),''),'{}')::jsonb
      @> jsonb_build_object('actor',auth.uid(),'booking',old.id,'version',old.version,'duration',new.default_duration_minutes)
  then v_allowed:=public.workshop_is_planner_operator(); end if;
  if old.status='completed' and new.status='queued' then
    v_allowed:=public.workshop_consume_transition_authorization(old.id,'reopen_completed');
  elsif old.status='deleted' and new.status='queued' then
    v_allowed:=public.workshop_consume_transition_authorization(old.id,'restore');
  elsif old.status='planned' and new.status='queued'
    and new.bay_id is null and new.returned_to_queue_at is not null then
    v_allowed:=public.workshop_consume_transition_authorization(old.id,'return_to_queue');
   elsif old.status in ('started','stoppage') and new.status='queued' then
    v_allowed:=public.workshop_consume_transition_authorization(old.id,'return_to_queue');
  end if;
  if not v_allowed then
    raise exception 'Invalid Workshop Planner lifecycle transition: % -> %',old.status,new.status using errcode='22023';
  end if;
  return new;
end $function$
;
CREATE OR REPLACE FUNCTION public.get_workshop_booking_search_scoped(p_vehicles jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
 SET statement_timeout TO '15s'
AS $function$
DECLARE actor_scope jsonb; results jsonb;
BEGIN
 -- Actual signed-in identity plus the existing role check are required.
 -- The private read helper applies only the owner-authorised Department138 delegation.
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE='42501'; END IF;
 PERFORM public.require_pdc_role('viewer');
 actor_scope:=pdc_codex_intake_private.workshop_read_actor_scope_20261013();
 IF jsonb_typeof(p_vehicles) IS DISTINCT FROM 'array' THEN
  RETURN jsonb_build_object('ok',false,'error','invalid_identity');
 END IF;
 IF jsonb_array_length(p_vehicles) NOT BETWEEN 1 AND 25 THEN
  RETURN jsonb_build_object('ok',false,'error','invalid_identity');
 END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_vehicles) x WHERE jsonb_typeof(x) IS DISTINCT FROM 'object'
   OR jsonb_typeof(x->'vehicle_id') IS DISTINCT FROM 'string'
   OR coalesce(x->>'vehicle_id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
   OR jsonb_typeof(x->'dealer_code') IS DISTINCT FROM 'string'
   OR length(btrim(coalesce(x->>'dealer_code',''))) NOT BETWEEN 1 AND 80)
 OR (SELECT count(DISTINCT lower(x->>'vehicle_id')) FROM jsonb_array_elements(p_vehicles) x)<>jsonb_array_length(p_vehicles) THEN
  RETURN jsonb_build_object('ok',false,'error','invalid_identity');
 END IF;

 WITH requested AS MATERIALIZED (
  SELECT (x->>'vehicle_id')::uuid vehicle_id,btrim(x->>'dealer_code') dealer_code,ordinal
  FROM jsonb_array_elements(p_vehicles) WITH ORDINALITY q(x,ordinal)
 ), authorized AS MATERIALIZED (
  SELECT r.*,CASE
   WHEN pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(actor_scope,r.vehicle_id,r.dealer_code) IS NOT TRUE THEN 'dealer_scope_denied'
   WHEN NOT EXISTS(SELECT 1 FROM public.vehicles v WHERE v.id=r.vehicle_id AND v.deleted_at IS NULL AND v.lifecycle_state='active'
     AND (public.pdc_auditor_vehicle_dealer(v.id)=r.dealer_code OR pdc_codex_intake_private.workshop_nonnav138_read_allowed_20261012(actor_scope,v.id,r.dealer_code))) THEN 'vehicle_not_in_dealer_scope'
   ELSE NULL END error
  FROM requested r
 ), booking_rows AS (
  SELECT a.vehicle_id,jsonb_agg(jsonb_build_object(
   'booking_id',b.id,'booking_version',b.version,'work_category',b.work_category,'stage_code',s.code,'stage_name',s.display_name,
   'bay_number',bay.bay_number,'bay_name',bay.display_name,'status',b.status,
   'scheduled_start_at',b.scheduled_start_at,'scheduled_end_at',b.scheduled_end_at,
   'default_duration_minutes',b.default_duration_minutes,'actual_start_at',b.actual_start_at,'actual_end_at',b.actual_end_at)
   ORDER BY s.sort_order,b.scheduled_start_at,b.id) bookings
  FROM authorized a JOIN public.workshop_bookings b ON b.vehicle_id=a.vehicle_id AND a.error IS NULL
  JOIN public.workshop_stages s ON s.id=b.stage_id LEFT JOIN public.workshop_bays bay ON bay.id=b.bay_id
  WHERE b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage','completed')
  GROUP BY a.vehicle_id
 )
 SELECT jsonb_agg(jsonb_build_object('vehicle_id',a.vehicle_id,'dealer_code',a.dealer_code,'ok',a.error IS NULL)
  ||CASE WHEN a.error IS NULL THEN jsonb_build_object('bookings',coalesce(b.bookings,'[]'::jsonb))
    ELSE jsonb_build_object('error',a.error) END ORDER BY a.ordinal)
 INTO results FROM authorized a LEFT JOIN booking_rows b ON b.vehicle_id=a.vehicle_id;
 RETURN jsonb_build_object('ok',true,'results',results);
END $function$
;

-- protected move and cascade paths. Existing identity, permissions and guards stay.
DO $guard$
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'Staging only'; END IF;
 IF md5(pg_get_functiondef('public.cascade_workshop_booking_move_pre_116(uuid,integer,text,integer,timestamptz,integer,text,jsonb)'::regprocedure)) <> 'e308c00e13b29b331ec8e7b7ac6d19ab' THEN RAISE EXCEPTION 'Reallocation source changed: cascade_workshop_booking_move_pre_116'; END IF;
 IF md5(pg_get_functiondef('public.workshop_move_booking(uuid,integer,text,integer,timestamptz,integer,jsonb)'::regprocedure)) <> '35aaab2892b9be454be6fb41762eea1a' THEN RAISE EXCEPTION 'Reallocation source changed: workshop_move_booking'; END IF;
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
  if v_target.deleted_at is not null or NOT (
    v_target.status='planned' OR (v_target.status='queued' AND v_target.bay_id IS NULL
      AND v_target.returned_to_queue_at IS NOT NULL AND v_target.actual_start_at IS NULL
      AND v_target.actual_end_at IS NULL)) then
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
$function$
;

CREATE OR REPLACE FUNCTION public.workshop_move_booking(p_booking_id uuid, p_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer DEFAULT NULL::integer, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_before public.workshop_bookings%rowtype;
  v_before_snapshot jsonb;
  v_after_snapshot jsonb;
  v_stage_id uuid;
  v_bay_id uuid;
  v_technician_id uuid;
  v_conflict_id uuid;
  v_duration integer;
  v_end timestamptz;
  v_history_id uuid;
  v_leave_date date;
  v_capacity_context text:=current_setting('pdc.workshop_capacity_manual',true);
begin
  perform public.require_pdc_role('operator');

  select * into v_before
  from public.workshop_bookings
  where id = p_booking_id
  for update;

  if not found then
    raise exception 'Workshop booking not found' using errcode = 'P0002';
  end if;
  if v_before.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'version_conflict', 'conflict', public.workshop_conflict_payload(v_before.id, 'version_conflict'));
  end if;
  perform 1 from public.vehicles where id=v_before.vehicle_id for update;

  select technician_id into v_technician_id
  from public.workshop_booking_assignments
  where booking_id = p_booking_id and released_at is null
  order by case when assignment_type = 'primary' then 0 else 1 end, assigned_at desc
  limit 1;

  v_stage_id := public.workshop_resolve_stage_id(p_stage_code);
  v_bay_id := public.workshop_resolve_bay_id(p_stage_code, p_bay_number);
  -- Unstarted work inherited from the old bay follows the destination's default.
  -- Preserve deliberate team choices, helpers and any work already performed.
  if v_bay_id is distinct from v_before.bay_id
     and v_before.status in ('queued','planned') and v_before.actual_start_at is null
     and not exists(select 1 from pdc_fitter_private.operation_progress where booking_id=p_booking_id)
     and not exists(select 1 from public.workshop_booking_history
       where booking_id=p_booking_id and event_type in ('team_changed','reassigned','technician_assigned','technician_changed','assigned'))
     and (v_technician_id is null or v_technician_id = (
       select default_technician_id from public.workshop_bays where id=v_before.bay_id))
     and exists(select 1 from public.workshop_bays bay
       join public.workshop_technicians t on t.id=bay.default_technician_id and t.active
       where bay.id=v_bay_id) then
    select default_technician_id into v_technician_id from public.workshop_bays where id=v_bay_id;
  end if;

  v_duration := CASE WHEN v_before.status IN('queued','planned') AND (v_bay_id IS DISTINCT FROM v_before.bay_id OR v_stage_id IS DISTINCT FROM v_before.stage_id) THEN public.workshop_booking_capacity_duration_minutes(p_booking_id,v_before.vehicle_id,v_stage_id,v_bay_id) ELSE coalesce(p_duration_minutes,v_before.default_duration_minutes) END;
  if v_duration <= 0 then
    raise exception 'Workshop duration must be positive' using errcode = '22023';
  end if;
  v_end := public.workshop_add_operational_minutes(p_scheduled_start_at, v_duration);

  perform public.workshop_lock_resources(v_bay_id, v_technician_id);

  v_conflict_id := public.workshop_find_bay_conflict(p_booking_id, v_bay_id, p_scheduled_start_at, v_end);
  if v_conflict_id is not null then
    return jsonb_build_object('ok', false, 'error', 'bay_overlap', 'conflict', public.workshop_conflict_payload(v_conflict_id, 'bay_overlap'));
  end if;
  if v_technician_id is not null then
    v_conflict_id := public.workshop_find_technician_conflict(p_booking_id, v_technician_id, p_scheduled_start_at, v_end);
    if v_conflict_id is not null then
      return jsonb_build_object('ok', false, 'error', 'technician_overlap', 'conflict', public.workshop_conflict_payload(v_conflict_id, 'technician_overlap'));
    end if;
  end if;

  if v_technician_id is not null then
    v_leave_date := public.workshop_technician_leave_date(v_technician_id, p_scheduled_start_at, v_end);
    if v_leave_date is not null then
      return jsonb_build_object('ok', false, 'error', 'technician_on_leave', 'date', v_leave_date, 'technician_id', v_technician_id);
    end if;
  end if;

  v_before_snapshot := public.workshop_booking_snapshot(p_booking_id);

  perform set_config('pdc.workshop_capacity_manual',jsonb_build_object('actor',auth.uid(),'booking',p_booking_id,'version',p_expected_version,'duration',v_duration)::text,true);
  update public.workshop_bookings
  set status = CASE WHEN v_before.status='queued' AND v_before.bay_id IS NULL
        AND v_before.returned_to_queue_at IS NOT NULL AND v_before.actual_start_at IS NULL
        AND v_before.actual_end_at IS NULL THEN 'planned'::public.workshop_booking_status ELSE v_before.status END,
      stage_id = v_stage_id,
      bay_id = v_bay_id,
      scheduled_start_at = p_scheduled_start_at,
      scheduled_end_at = v_end,
      default_duration_minutes = v_duration,
      updated_by = auth.uid(),
      version = version + 1
  where id = p_booking_id;

  perform set_config('pdc.workshop_capacity_manual',coalesce(v_capacity_context,''),true);
  perform public.workshop_upsert_primary_assignment(p_booking_id, v_technician_id, p_scheduled_start_at, v_end, 'moved');

  v_after_snapshot := public.workshop_booking_snapshot(p_booking_id);
  v_history_id := public.workshop_write_history(p_booking_id, 'moved', v_before_snapshot, v_after_snapshot, coalesce(p_metadata, '{}'::jsonb));

  return jsonb_build_object('ok', true, 'booking', v_after_snapshot, 'history_id', v_history_id);
EXCEPTION WHEN OTHERS THEN
 perform set_config('pdc.workshop_capacity_manual',coalesce(v_capacity_context,''),true);
 RAISE;
end;
$function$
;


