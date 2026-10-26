-- Undo r537 (F151). Staging cdsmnqxtyyoeoznmbidd only. Do not run on production.
-- Restores workshop_create_booking body md5 f5375755bbb9c217198c4075e5c125ab
-- and the r531 text of planner_duration_cache_531. Drops the F151 check.
-- Pin count stays 241. workshop_validate_booking is not changed. No booking rows are rewritten.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r537 undo: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r537 undo: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r537 undo: pin count is not 241'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_create_booking(uuid,text,integer,timestamptz,integer,uuid,jsonb)'::regprocedure) IS DISTINCT FROM '864e9bdc638bd0003dab0302e9ab2de3' THEN RAISE EXCEPTION 'r537 undo: create body is not the r537 body'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,workshop_booking_status,uuid,boolean)'::regprocedure) IS DISTINCT FROM '9efb08f2415c28ac57a14b401cf9f605' THEN RAISE EXCEPTION 'r537 undo: validate body changed'; END IF;
END $g$;

DELETE FROM pdc_ops.regression_checks
WHERE check_name = 'planner_duration_after_insert_537' AND fault_id = 'F151' AND added_in = 'r537';

UPDATE pdc_ops.regression_checks
SET description = 'A new booking reads live operation-line minutes before the insert drops the QC cache, and the duration mismatch guard stays.',
    check_sql = $chk531old$
SELECT
  del_at > 0 AND est_at > del_at
  AND md5(src) = 'f5375755bbb9c217198c4075e5c125ab'
  AND strpos(val, 'operation_estimate_duration_mismatch') > 0
  AS ok,
  'create '||md5(src)||' delete '||del_at::text||' estimate '||est_at::text AS detail
FROM (
  SELECT prosrc AS src,
    strpos(prosrc, 'DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE vehicle_id = p_vehicle_id') AS del_at,
    strpos(prosrc, 'workshop_booking_capacity_duration_minutes(NULL,p_vehicle_id,v_stage_id,v_bay_id)') AS est_at
  FROM pg_proc
  WHERE oid = 'public.workshop_create_booking(uuid,text,integer,timestamptz,integer,uuid,jsonb)'::regprocedure
) c
CROSS JOIN (
  SELECT prosrc AS val FROM pg_proc
  WHERE oid = 'public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)'::regprocedure
) v
$chk531old$
WHERE check_name = 'planner_duration_cache_531' AND fault_id = 'F145' AND sort_order = 312 AND added_in = 'r531';

CREATE OR REPLACE FUNCTION public.workshop_create_booking(p_vehicle_id uuid, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer DEFAULT 180, p_technician_id uuid DEFAULT NULL::uuid, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $cb537down$
declare
  v_stage_id uuid;
  v_bay_id uuid;
  v_booking_id uuid;
  v_conflict_id uuid;
  v_history_id uuid;
  v_end timestamptz;
  v_after jsonb;
  v_leave_date date;
begin
  perform public.require_pdc_role('operator');
  if p_duration_minutes is null or p_duration_minutes <= 0 then
    raise exception 'Workshop duration must be positive' using errcode = '22023';
  end if;

  v_stage_id := public.workshop_resolve_stage_id(p_stage_code);
  v_bay_id := public.workshop_resolve_bay_id(p_stage_code, p_bay_number);
  -- r531 (F145): the booking insert drops this vehicle's QC operation-line cache.
  -- Read the live minutes first, so the stored length and the later check are the same total.
  DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE vehicle_id = p_vehicle_id;
  p_duration_minutes := coalesce(public.workshop_booking_capacity_duration_minutes(NULL,p_vehicle_id,v_stage_id,v_bay_id),p_duration_minutes);
  v_end := public.workshop_add_operational_minutes(p_scheduled_start_at, p_duration_minutes);

  if p_technician_id is not null then
    if not exists (select 1 from public.workshop_technicians where id = p_technician_id) then
      return jsonb_build_object('ok', false, 'error', 'technician_not_found', 'technician_id', p_technician_id);
    end if;
    if not exists (select 1 from public.workshop_technicians where id = p_technician_id and active) then
      return jsonb_build_object('ok', false, 'error', 'technician_inactive', 'technician_id', p_technician_id);
    end if;
    select public.workshop_technician_leave_date(p_technician_id, p_scheduled_start_at, v_end) into v_leave_date;
    if v_leave_date is not null then
      return jsonb_build_object('ok', false, 'error', 'technician_on_leave', 'technician_id', p_technician_id, 'date', v_leave_date);
    end if;
  end if;

  perform public.workshop_lock_resources(v_bay_id, p_technician_id);

  v_conflict_id := public.workshop_find_bay_conflict(null, v_bay_id, p_scheduled_start_at, v_end);
  if v_conflict_id is not null then
    return jsonb_build_object('ok', false, 'error', 'bay_overlap', 'conflict', public.workshop_conflict_payload(v_conflict_id, 'bay_overlap'));
  end if;

  if p_technician_id is not null then
    v_conflict_id := public.workshop_find_technician_conflict(null, p_technician_id, p_scheduled_start_at, v_end);
    if v_conflict_id is not null then
      return jsonb_build_object('ok', false, 'error', 'technician_overlap', 'conflict', public.workshop_conflict_payload(v_conflict_id, 'technician_overlap'), 'detail', pdc_cascade_private.technician_overlap_detail_531(v_conflict_id));
    end if;
  end if;

  insert into public.workshop_bookings (
    vehicle_id,
    stage_id,
    bay_id,
    status,
    scheduled_start_at,
    scheduled_end_at,
    default_duration_minutes,
    created_by,
    updated_by
  ) values (
    p_vehicle_id,
    v_stage_id,
    v_bay_id,
    'planned',
    p_scheduled_start_at,
    v_end,
    p_duration_minutes,
    auth.uid(),
    auth.uid()
  ) returning id into v_booking_id;

  perform public.workshop_upsert_primary_assignment(v_booking_id, p_technician_id, p_scheduled_start_at, v_end, 'created');

  v_after := public.workshop_booking_snapshot(v_booking_id);
  v_history_id := public.workshop_write_history(v_booking_id, 'created', null, v_after, coalesce(p_metadata, '{}'::jsonb));

  return jsonb_build_object('ok', true, 'booking', v_after, 'history_id', v_history_id);
end;
$cb537down$;

DO $post$
DECLARE r record;
BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_create_booking(uuid,text,integer,timestamptz,integer,uuid,jsonb)'::regprocedure) IS DISTINCT FROM 'f5375755bbb9c217198c4075e5c125ab' THEN RAISE EXCEPTION 'r537 undo: restored body md5 mismatch'; END IF;
 IF (SELECT proacl::text FROM pg_proc WHERE oid='public.workshop_create_booking(uuid,text,integer,timestamptz,integer,uuid,jsonb)'::regprocedure) IS DISTINCT FROM '{postgres=X/postgres,service_role=X/postgres}' THEN RAISE EXCEPTION 'r537 undo: acl changed'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='planner_duration_after_insert_537' OR fault_id='F151' OR added_in='r537') THEN RAISE EXCEPTION 'r537 undo: F151 check remains'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r537 undo: pin count changed'; END IF;
 SELECT * INTO r FROM pdc_ops.regression_checks WHERE check_name='planner_duration_cache_531';
 EXECUTE r.check_sql INTO r;
 IF coalesce(r.ok, false) IS NOT TRUE THEN RAISE EXCEPTION 'r537 undo: duration check failed: %', r.detail; END IF;
END $post$;
