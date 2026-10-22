-- r469 (F82; Craig 22 Oct 2026 09:24 AWST: "Please fix it, make sure it doesn't happen again. This needs to work one hundred
-- percent of the time"). Staging cdsmnqxtyyoeoznmbidd only.
-- Fault: dragging an Unallocated vehicle onto a planner bay (administrator_schedule_workshop_vehicle, cascade on) runs
-- cascade_workshop_schedule('insert') -> ... -> cascade_workshop_schedule_pre_087, which pushed EVERY planned booking later in
-- that bay back by the full length of the new job, even bookings weeks away beyond free time. A pushed booking can then land
-- on its own vehicle's next-station booking, the booking trigger refuses it (vehicle_overlap) and the whole drop fails with
-- "This change would overlap a vehicle's booking in another bay or station...", although the dropped vehicle has no other
-- bookings. 22 Oct 09:24: every drop on Fitting Bay 01 before 13 Nov pushed one far-future vehicle's Fitting (13-16 Nov) into
-- its own Fabrication (16 Nov), so a vehicle with no bookings at all could not be placed anywhere on Bay 01.
-- Fix: insert and extend move only the overlapping forward chain (the rule cascade_workshop_booking_move already uses): a gap
-- absorbs the push; bookings beyond it keep their exact time and version. A drop into free time moves nothing. When a push is
-- really needed and would clash, the refusal now names the clashing booking and the pushed booking (no bare DB error).
-- Changed: public.cascade_workshop_schedule_pre_087 (bbdc1ae1 -> 5f76d7e7). New private schema pdc_cascade_private
-- (no app-role access): target_end_469, overlap_chain_469, validation_rejection_469. Check cascade_insert_overlap_chain_469
-- (sort 268). Not touched: workshop_clock_tick, the validation trigger, the move/start paths, any booking row, Karratha 135.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r469: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r469: staging only'; END IF;
 PERFORM set_config('pdc.r469_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 PERFORM set_config('pdc.r469_frc',(SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure),true);
 PERFORM set_config('pdc.r469_pins',(SELECT count(*) FROM pdc_ops.expected_function_md5)::text,true);
 IF current_setting('pdc.r469_tick')<>'0aaaa15690ca286ed0db87fc72271d5a' THEN RAISE EXCEPTION 'r469: clock tick changed since prepared (this release must not touch it)'; END IF;
 IF current_setting('pdc.r469_frc')<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r469: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.cascade_workshop_schedule_pre_087(text,uuid,integer,text,integer,timestamp with time zone,integer,uuid,integer,text,jsonb)')) IS DISTINCT FROM 'bbdc1ae1525d7e5060bfda8a8406b8f4' THEN RAISE EXCEPTION 'r469: cascade_workshop_schedule_pre_087 changed since prepared'; END IF;
 IF (SELECT coalesce(proacl::text,'NULL')||'|'||prosecdef::text||'|'||proowner::regrole::text FROM pg_proc WHERE oid=to_regprocedure('public.cascade_workshop_schedule_pre_087(text,uuid,integer,text,integer,timestamp with time zone,integer,uuid,integer,text,jsonb)')) IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres}|true|postgres' THEN RAISE EXCEPTION 'r469: pre_087 grants/owner changed'; END IF;
 IF to_regnamespace('pdc_cascade_private') IS NOT NULL OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r469')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='cascade_insert_overlap_chain_469' OR added_in='r469') THEN RAISE EXCEPTION 'r469: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=268 OR fault_id='F82') THEN RAISE EXCEPTION 'r469: sort_order 268 / F82 taken'; END IF;
END $g$;

CREATE SCHEMA pdc_cascade_private;
REVOKE ALL ON SCHEMA pdc_cascade_private FROM PUBLIC;
REVOKE ALL ON SCHEMA pdc_cascade_private FROM anon, authenticated, service_role;

-- End of the new (insert) or extended booking on the calendar the booking itself will use.
CREATE FUNCTION pdc_cascade_private.target_end_469(p_vehicle_id uuid, p_bay_id uuid, p_start timestamptz, p_minutes integer)
 RETURNS timestamptz
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
begin
  if p_start is null or p_minutes is null or p_minutes < 1 then return null; end if;
  if pdc_bus_private.active_vehicle(p_vehicle_id) and exists(
    select 1 from public.workshop_bays b join public.workshop_stages s on s.id=b.stage_id
    where b.id=p_bay_id and s.code='BUS_4X4') then
    return pdc_bus_private.add_minutes(p_start,p_minutes,p_bay_id);
  end if;
  return public.workshop_add_operational_minutes(p_start,p_minutes);
end
$function$;

-- r469 (F82): the bookings a cascade insert/extend must push, and where to. Walks the candidate bookings in start order
-- from the end of the new booking: a booking starting at or after the frontier is beyond a gap, so it and everything after
-- it stay exactly where they are. A booking inside the frontier moves to the next free minute after it (same duration,
-- same calendar rule the cascade always used) and the frontier moves to its new end. Returns [] when nothing has to move,
-- NULL when the calendar has no room. Read-only: the cascade applies the plan, the daily check proves it.
CREATE FUNCTION pdc_cascade_private.overlap_chain_469(p_candidate_ids uuid[], p_frontier timestamptz)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_cursor timestamptz := p_frontier;
  v_row record;
  v_new_start timestamptz;
  v_new_end timestamptz;
  v_tail interval;
  v_plan jsonb := '[]'::jsonb;
begin
  if p_frontier is null then return null; end if;
  for v_row in
    select b.id, b.version, b.scheduled_start_at, b.scheduled_end_at, b.default_duration_minutes
    from public.workshop_bookings b
    where b.id = any(coalesce(p_candidate_ids,'{}'::uuid[])) and b.status='planned' and b.deleted_at is null
    order by b.scheduled_start_at, b.id
  loop
    exit when v_row.scheduled_start_at >= v_cursor;
    v_new_start := public.workshop_next_calendar_window(v_cursor, v_row.default_duration_minutes);
    v_new_end := public.workshop_add_operational_minutes(v_new_start, v_row.default_duration_minutes);
    if v_new_start is null or v_new_end is null or v_new_end <= v_new_start then return null; end if;
    v_plan := v_plan || jsonb_build_array(jsonb_build_object(
      'id', v_row.id, 'version', v_row.version, 'start_at', v_new_start, 'end_at', v_new_end,
      'duration_minutes', v_row.default_duration_minutes,
      'shift_minutes', public.workshop_operational_minutes_between(v_row.scheduled_start_at, v_new_start)));
    -- Keep any tail the booking carries past its scheduled end (effective end) in front of the next booking.
    v_tail := greatest(interval '0', public.workshop_booking_effective_end_at(v_row.id) - v_row.scheduled_end_at);
    v_cursor := v_new_end + v_tail;
  end loop;
  return v_plan;
end
$function$;

-- The booking trigger's refusal ('Workshop Planner validation rejected booking: {...}') as jsonb, or NULL for anything else.
CREATE FUNCTION pdc_cascade_private.validation_rejection_469(p_message text)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
declare v jsonb;
begin
  if p_message is null or left(p_message, 46) <> 'Workshop Planner validation rejected booking: ' then return null; end if;
  begin
    v := substr(p_message, 47)::jsonb;
  exception when others then
    return null;
  end;
  if jsonb_typeof(v) <> 'object' or coalesce(v->>'ok','') <> 'false' or nullif(v->>'error','') is null then return null; end if;
  return v;
end
$function$;

REVOKE ALL ON FUNCTION pdc_cascade_private.target_end_469(uuid,uuid,timestamptz,integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION pdc_cascade_private.overlap_chain_469(uuid[],timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION pdc_cascade_private.validation_rejection_469(text) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.cascade_workshop_schedule_pre_087(p_operation text, p_target_id uuid, p_target_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer, p_technician_id uuid DEFAULT NULL::uuid, p_shift_minutes integer DEFAULT 0, p_override_reason text DEFAULT NULL::text, p_metadata jsonb DEFAULT '{}'::jsonb)
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
  -- r469 (F82): only the overlapping forward chain moves (same rule as cascade_workshop_booking_move).
  v_insert_end timestamptz;
  v_plan jsonb := '[]'::jsonb;
  v_step jsonb;
  v_chain_ids uuid[] := '{}'::uuid[];
  v_pushing_id uuid;
  v_rejection jsonb;
begin
  perform public.workshop_require_planner_operator();
  perform public.workshop_require_version(p_target_expected_version);
  perform pg_advisory_xact_lock(hashtextextended('pdc:workshop:cascade',0));

  if v_operation not in ('insert', 'extend') then
    raise exception 'Cascade operation must be insert or extend' using errcode = '22023';
  end if;
  if p_duration_minutes is null or p_duration_minutes < 1 then
    return jsonb_build_object('ok', false, 'error', 'minimum_duration', 'minimum_minutes', 1);
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
  where (b.bay_id = v_bay.id or b.vehicle_id = nullif(current_setting('pdc.hermes_test_wrapper_vehicle_365',true),'')::uuid)
    and b.status = 'planned' and b.deleted_at is null
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
    and (b.bay_id = v_bay.id or b.vehicle_id = nullif(current_setting('pdc.hermes_test_wrapper_vehicle_365',true),'')::uuid)
    and b.status = 'planned'
    and b.deleted_at is null;
  if v_locked_count <> cardinality(v_expected_ids) then
    return jsonb_build_object(
      'ok', false,
      'error', 'concurrent_queue_change',
      'retry', true
    );
  end if;

  -- r469 (F82): a gap absorbs the displacement. Only bookings that would overlap the new or extended booking (or a
  -- booking already pushed by it) move, each to the next free minute after the one before it. Bookings beyond a gap keep
  -- their exact time and version, so a far-future booking (and its vehicle's later stations) is never pushed into a clash.
  v_insert_end := pdc_cascade_private.target_end_469(
    case when v_operation = 'insert' then p_target_id else v_target.vehicle_id end,
    v_bay.id,
    case when v_operation = 'insert' then p_scheduled_start_at else v_target.scheduled_start_at end,
    p_duration_minutes);
  if v_insert_end is null then return jsonb_build_object('ok', false, 'error', 'calendar_unavailable'); end if;
  v_plan := pdc_cascade_private.overlap_chain_469(v_expected_ids, v_insert_end);
  if v_plan is null then return jsonb_build_object('ok', false, 'error', 'calendar_unavailable'); end if;
  select coalesce(array_agg((item.value->>'id')::uuid order by item.ordinal), '{}'::uuid[]) into v_chain_ids
    from jsonb_array_elements(v_plan) with ordinality item(value, ordinal);

  -- Keep the target action and every shifted timestamp in one subtransaction.
  -- If the protected target RPC returns a structured business rejection, the
  -- exception block rolls back all shifts and returns that rejection intact.
  begin
  -- Latest-first, so a pushed booking never passes through the one after it.
  for v_step in
    select item.value from jsonb_array_elements(v_plan) with ordinality item(value, ordinal)
    order by item.ordinal desc
  loop
    select * into v_shifted from public.workshop_bookings where id = (v_step->>'id')::uuid;
    v_pushing_id := v_shifted.id;
    v_new_start := (v_step->>'start_at')::timestamptz;
    v_new_end := (v_step->>'end_at')::timestamptz;
    v_before := public.workshop_booking_snapshot(v_shifted.id);
    update public.workshop_bookings
      set scheduled_start_at = v_new_start,
          scheduled_end_at = v_new_end,
          updated_by = auth.uid(),
          version = version + 1
      where id = v_shifted.id and version = (v_step->>'version')::integer
        and (bay_id = v_bay.id or vehicle_id = nullif(current_setting('pdc.hermes_test_wrapper_vehicle_365',true),'')::uuid)
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
      coalesce(p_metadata, '{}'::jsonb) || jsonb_build_object('cascade_operation', v_operation, 'cascade_target_id', p_target_id,
        'signed_shift_minutes', (v_step->>'shift_minutes')::integer, 'affected_overlap_chain', true));
  end loop;
  v_pushing_id := null;

  -- Validate the final technician allocation after every shifted timestamp is in place.
  for v_shifted in
    select * from public.workshop_bookings
    where id = any(v_chain_ids)
      and (bay_id = v_bay.id or vehicle_id = nullif(current_setting('pdc.hermes_test_wrapper_vehicle_365',true),'')::uuid)
      and status = 'planned'
      and deleted_at is null
  loop
    v_conflict := public.workshop_find_bay_conflict(
      v_shifted.id, v_shifted.bay_id, v_shifted.scheduled_start_at, v_shifted.scheduled_end_at
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
  exception
  when sqlstate 'P0001' then
    if v_result is not null and coalesce((v_result->>'ok')::boolean, false) is not true then
      return v_result;
    end if;
    raise;
  when sqlstate '22023' then
    -- r469 (F82): the booking trigger refused a row. Every shift above is rolled back; say which booking clashed (and
    -- which pushed booking caused it) instead of a bare database error, so the planner can name it.
    v_rejection := pdc_cascade_private.validation_rejection_469(sqlerrm);
    if v_rejection is null then raise; end if;
    return v_rejection || jsonb_build_object(
      'conflict', case when v_rejection ? 'conflict_booking_id'
        then public.workshop_conflict_payload((v_rejection->>'conflict_booking_id')::uuid, coalesce(v_rejection->>'error','validation_rejected')) end,
      'pushed_booking_id', v_pushing_id,
      'pushed_booking', case when v_pushing_id is not null then public.workshop_booking_snapshot(v_pushing_id) end,
      'cascade_operation', v_operation,
      'shifted_booking_ids', '[]'::jsonb,
      'shifted_count', 0);
  end;

  return v_result || jsonb_build_object(
    'cascade_operation', v_operation,
    'shifted_booking_ids', to_jsonb(v_chain_ids),
    'shifted_count', cardinality(v_chain_ids)
  );
end;
$function$;

INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note) VALUES
 ('public.cascade_workshop_schedule_pre_087(text,uuid,integer,text,integer,timestamp with time zone,integer,uuid,integer,text,jsonb)','5f76d7e74c9ced8e948beebdee02a250','r469','r469: cascade insert/extend moves only the overlapping chain; names the clash (F82)'),
 ('pdc_cascade_private.target_end_469(uuid,uuid,timestamp with time zone,integer)','b7b98893bfc7a04b39330ca689f8f1b1','r469','r469: overlap-chain helper (F82)'),
 ('pdc_cascade_private.overlap_chain_469(uuid[],timestamp with time zone)','e3602ba6f9d5973deea4eef09f5077c0','r469','r469: overlap-chain helper (F82)'),
 ('pdc_cascade_private.validation_rejection_469(text)','621c8e5756bf4996b416c25b38c783b9','r469','r469: overlap-chain helper (F82)');

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('cascade_insert_overlap_chain_469','F82','A vehicle dropped into free bay time can always be booked: a cascade insert/extend pushes only bookings it overlaps, never a booking beyond a gap (r469)',$chk$WITH pins AS (
  SELECT count(*) n, count(*) FILTER (WHERE md5(p.prosrc)=e.prosrc_md5) ok
  FROM pdc_ops.expected_function_md5 e LEFT JOIN pg_catalog.pg_proc p ON p.oid=pg_catalog.to_regprocedure(e.signature) WHERE e.release='r469'),
uses AS (
  SELECT strpos(p.prosrc,'v_plan := pdc_cascade_private.overlap_chain_469(v_expected_ids, v_insert_end);')>0
     AND strpos(p.prosrc,'public.workshop_add_operational_minutes(v_shifted.scheduled_start_at, p_shift_minutes)')=0 AS ok
  FROM pg_catalog.pg_proc p WHERE p.oid=pg_catalog.to_regprocedure('public.cascade_workshop_schedule_pre_087(text,uuid,integer,text,integer,timestamp with time zone,integer,uuid,integer,text,jsonb)')),
bays AS (
  SELECT b.id bay_id FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id
  WHERE b.is_active AND NOT b.is_sublet_row AND s.active AND s.planner_enabled AND s.is_physical),
busy AS (
  SELECT bk.bay_id, bk.scheduled_start_at st, public.workshop_booking_effective_end_at(bk.id) en
  FROM public.workshop_bookings bk JOIN bays USING (bay_id)
  WHERE bk.deleted_at IS NULL AND bk.status IN ('planned','started','stoppage')
    AND public.workshop_booking_effective_end_at(bk.id)>now() AND bk.scheduled_start_at<now()+interval '30 days'),
edges AS (
  SELECT bay_id, st, max(en) OVER (PARTITION BY bay_id ORDER BY st, en ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) prev_end FROM busy),
gaps AS (
  SELECT bay_id, greatest(coalesce(prev_end,now()),now()) gs, st ge FROM edges WHERE st>greatest(coalesce(prev_end,now()),now())
  UNION ALL SELECT bay_id, greatest(max(en),now()), now()+interval '30 days' FROM busy GROUP BY bay_id
  UNION ALL SELECT bay_id, now(), now()+interval '30 days' FROM bays WHERE bay_id NOT IN (SELECT bay_id FROM busy)),
probe AS (
  SELECT g.bay_id, x.t, public.workshop_add_operational_minutes(x.t,60) e, g.ge
  FROM gaps g CROSS JOIN LATERAL (SELECT public.workshop_next_calendar_window(g.gs,60) t) x WHERE x.t IS NOT NULL),
slots AS (
  SELECT f.bay_id, f.t, f.e,
    pdc_cascade_private.overlap_chain_469(ARRAY(SELECT b.id FROM public.workshop_bookings b WHERE b.bay_id=f.bay_id
      AND b.status='planned' AND b.deleted_at IS NULL AND b.scheduled_start_at>=f.t), f.e) AS plan,
    EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.bay_id=f.bay_id AND b.status='planned' AND b.deleted_at IS NULL AND b.scheduled_start_at>=f.t) AS old_rule_pushed
  FROM probe f WHERE f.e<=f.ge),
unit AS (
  SELECT pdc_cascade_private.overlap_chain_469('{}'::uuid[], now())='[]'::jsonb
     AND pdc_cascade_private.validation_rejection_469('Workshop Planner validation rejected booking: {"ok": false, "error": "vehicle_overlap", "conflict_booking_id": "00000000-0000-0000-0000-000000000000"}')->>'error'='vehicle_overlap'
     AND pdc_cascade_private.validation_rejection_469('some other error') IS NULL
     AND pdc_cascade_private.validation_rejection_469('Workshop Planner validation rejected booking: not json') IS NULL AS ok),
grants AS (
  SELECT NOT has_schema_privilege('authenticated','pdc_cascade_private','USAGE') AND NOT has_schema_privilege('anon','pdc_cascade_private','USAGE') AS ok)
SELECT (SELECT n FROM pins)=4 AND (SELECT ok FROM pins)=4 AND coalesce((SELECT ok FROM uses),false)
   AND (SELECT count(*) FROM slots)>0 AND (SELECT count(*) FROM slots WHERE plan IS DISTINCT FROM '[]'::jsonb)=0
   AND (SELECT ok FROM unit) AND (SELECT ok FROM grants) AS ok,
 format('%s free 1-hour slots in %s planner bays over the next 30 days; a drop there pushes %s booking(s) (must be 0, so a vehicle with no other bookings can always be placed); the pre-r469 rule would have pushed a later booking from %s of them; r469 pins %s/%s; cascade uses the overlap chain: %s; helper self-test %s; private schema closed %s',
  (SELECT count(*) FROM slots),(SELECT count(DISTINCT bay_id) FROM slots),(SELECT count(*) FROM slots WHERE plan IS DISTINCT FROM '[]'::jsonb),
  (SELECT count(*) FROM slots WHERE old_rule_pushed),(SELECT ok FROM pins),(SELECT n FROM pins),coalesce((SELECT ok FROM uses),false),(SELECT ok FROM unit),(SELECT ok FROM grants)) AS detail$chk$,true,268,'r469');

DO $g$ DECLARE x record; y record; BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.cascade_workshop_schedule_pre_087(text,uuid,integer,text,integer,timestamp with time zone,integer,uuid,integer,text,jsonb)')) IS DISTINCT FROM '5f76d7e74c9ced8e948beebdee02a250' THEN RAISE EXCEPTION 'r469: public.cascade_workshop_schedule_pre_087(text,uuid,integer,text,integer,timestamp with time zone,integer,uuid,integer,text,jsonb) is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_cascade_private.target_end_469(uuid,uuid,timestamp with time zone,integer)')) IS DISTINCT FROM 'b7b98893bfc7a04b39330ca689f8f1b1' THEN RAISE EXCEPTION 'r469: pdc_cascade_private.target_end_469(uuid,uuid,timestamp with time zone,integer) is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_cascade_private.overlap_chain_469(uuid[],timestamp with time zone)')) IS DISTINCT FROM 'e3602ba6f9d5973deea4eef09f5077c0' THEN RAISE EXCEPTION 'r469: pdc_cascade_private.overlap_chain_469(uuid[],timestamp with time zone) is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_cascade_private.validation_rejection_469(text)')) IS DISTINCT FROM '621c8e5756bf4996b416c25b38c783b9' THEN RAISE EXCEPTION 'r469: pdc_cascade_private.validation_rejection_469(text) is not the expected version'; END IF;
 IF (SELECT proacl::text FROM pg_proc WHERE oid=to_regprocedure('public.cascade_workshop_schedule_pre_087(text,uuid,integer,text,integer,timestamp with time zone,integer,uuid,integer,text,jsonb)')) IS DISTINCT FROM '{postgres=X/postgres,authenticated=X/postgres}' THEN RAISE EXCEPTION 'r469: pre_087 grants changed'; END IF;
 IF has_schema_privilege('authenticated','pdc_cascade_private','USAGE') OR has_schema_privilege('anon','pdc_cascade_private','USAGE') THEN RAISE EXCEPTION 'r469: private schema is reachable'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r469')<>4 OR (SELECT count(*) FROM pdc_ops.expected_function_md5)<>current_setting('pdc.r469_pins')::int+4 THEN RAISE EXCEPTION 'r469: pins not as expected'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='cascade_insert_overlap_chain_469' AND added_in='r469' AND sort_order=268) IS DISTINCT FROM 'b0d3fd25dda98dc213d7b993730acba2' THEN RAISE EXCEPTION 'r469: check did not land as expected'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 FOR x IN SELECT r.check_name, r.check_sql FROM pdc_ops.regression_checks r WHERE r.check_name='cascade_insert_overlap_chain_469' LOOP
  EXECUTE x.check_sql INTO y; IF y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r469: check % not OK: %',x.check_name,y.detail; END IF;
 END LOOP;
 PERFORM set_config('search_path','public, extensions',true);
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r469_tick') THEN RAISE EXCEPTION 'r469: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure) IS DISTINCT FROM current_setting('pdc.r469_frc') THEN RAISE EXCEPTION 'r469: fault_regression_check changed'; END IF;
END $g$;
