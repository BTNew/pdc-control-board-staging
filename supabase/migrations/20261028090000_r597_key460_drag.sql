-- r597 (F211) / sort 367. Staging cdsmnqxtyyoeoznmbidd only.
-- Key 460's card and drag were still the stored 12.00 h. A drop onto a running
-- job asked Craig to confirm every later job, then the 1-hour check could name
-- his own Hoist row. Outstanding hours are what the board shows and sends.
-- A booking never conflicts with itself. A row with no bay is not a conflict.
-- A drop into an occupied bay cascades without a question.
-- Undo: supabase/rollbacks/20261028090000_r597_key460_drag.down.sql

SET LOCAL lock_timeout = '2s';
DO $g$
DECLARE awst time; def text; n int;
BEGIN
  awst := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
  IF (awst >= time '06:50' AND awst < time '07:30')
     OR (awst >= time '12:20' AND awst < time '12:40')
     OR (awst >= time '17:50' AND awst < time '18:10') THEN
    RAISE EXCEPTION 'r597: Kajel import window';
  END IF;
  IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN
    RAISE EXCEPTION 'r597: run between :02 and :45';
  END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r597: staging only'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r597: pin count is not 241'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=367 OR fault_id='F211' OR check_name='key460_drag_597' OR added_in='r597') THEN RAISE EXCEPTION 'r597: sort 367 / F211 is taken'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='outstanding_station_hours_594' AND fault_id='F208' AND sort_order=364 AND added_in='r594') THEN RAISE EXCEPTION 'r597: r594 is not present'; END IF;
  IF (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)') IS DISTINCT FROM '6a02115d30578e8eb3807a283b1d60ea' THEN RAISE EXCEPTION 'r597: move pin is not r571'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)')) IS DISTINCT FROM '6a02115d30578e8eb3807a283b1d60ea' THEN RAISE EXCEPTION 'r597: move body is not the pinned text'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN RAISE EXCEPTION 'r597: department 135 changed'; END IF;

  def := pg_get_functiondef('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)'::regprocedure);
  IF strpos(def, 'and b.bay_id is distinct from v_target_bay') = 0
     OR strpos(def, 'if v_block is null then v_result:=jsonb_build_object(''ok'',false,''error'',''vehicle_overlap''); raise exception ''r576: cross-station overlap not pushed'' using errcode=''P0415''; end if;') = 0 THEN
    RAISE EXCEPTION 'r597: move text to patch was not found';
  END IF;
  def := replace(def, 'and b.bay_id is distinct from v_target_bay', 'and b.bay_id is not null and b.id is distinct from p_booking_id and b.bay_id is distinct from v_target_bay');
  def := replace(def,
    'if v_block is null then v_result:=jsonb_build_object(''ok'',false,''error'',''vehicle_overlap''); raise exception ''r576: cross-station overlap not pushed'' using errcode=''P0415''; end if;',
    'if v_block is null then null; end if; -- r597 (F211): a snapped start with no other bay booked for this vehicle is not a conflict');
  EXECUTE def;

  def := pg_get_functiondef('public.workshop_exclusion_conflict_571(uuid,uuid,timestamp with time zone,integer,text,integer,jsonb,boolean)'::regprocedure);
  IF strpos(def, 'and not (b.status=''queued'' and b.bay_id is null)') = 0 THEN RAISE EXCEPTION 'r597: exclusion helper text was not found'; END IF;
  def := replace(def, 'and not (b.status=''queued'' and b.bay_id is null)', 'and b.bay_id is not null -- r597 (F211): a row with no bay is not a conflict, and the booking being moved is already excluded');
  EXECUTE def;

  UPDATE pdc_ops.expected_function_md5
     SET prosrc_md5 = (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)'::regprocedure),
         note = 'r597 (F211): unallocated rows are not conflicts; a snapped start is not a self-conflict (was 6a02115d30578e8eb3807a283b1d60ea)',
         updated_at = now()
   WHERE signature = 'public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)'
     AND prosrc_md5 = '6a02115d30578e8eb3807a283b1d60ea';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'r597: move pin was not updated'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r597: pin count moved'; END IF;

  UPDATE pdc_ops.regression_checks
     SET check_sql = replace(check_sql,
       'md5(mv) = ''6a02115d30578e8eb3807a283b1d60ea''',
       'md5(mv) = (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature = ''public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)'')')
   WHERE check_name = 'hoist_place_after_592'
     AND strpos(check_sql, '6a02115d30578e8eb3807a283b1d60ea') > 0;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'r597: hoist check was not retargeted at the pin'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION public.workshop_overlay_canonical_booking_fields_397(p_snapshot jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO pg_catalog, public
AS $function$
DECLARE
  v_bookings jsonb;
BEGIN
  IF p_snapshot IS NULL OR jsonb_typeof(p_snapshot->'bookings') IS DISTINCT FROM 'array' THEN
    RETURN p_snapshot;
  END IF;

  -- r597 (F211): the card, the Control Board and the drag read this snapshot.
  -- A bayless row keeps its old full-station total in the table. Show and send
  -- only the unticked lines for that station.
  SELECT coalesce(jsonb_agg(
    CASE WHEN b.id IS NULL THEN item.booking ELSE item.booking||jsonb_build_object(
      'scheduled_start_at', b.scheduled_start_at,
      'scheduled_end_at', CASE
        WHEN b.bay_id IS NULL AND est.mins IS NOT NULL AND b.scheduled_start_at IS NOT NULL
          THEN public.workshop_add_operational_minutes(b.scheduled_start_at, est.mins)
        ELSE b.scheduled_end_at END,
      'default_duration_minutes', CASE WHEN b.bay_id IS NULL AND est.mins IS NOT NULL THEN est.mins ELSE b.default_duration_minutes END,
      'bus_calendar_version', b.bus_calendar_version,
      'capacity_base_minutes', CASE
        WHEN b.bay_id IS NULL AND est.mins IS NOT NULL THEN est.mins::numeric
        ELSE coalesce(b.capacity_base_minutes, b.default_duration_minutes::numeric) END,
      'capacity_efficiency_percent', coalesce(b.capacity_efficiency_percent, 100),
      'capacity_estimate_minutes', b.capacity_estimate_minutes,
      'estimated_operation_hours', est.hours,
      'fitter_progress', pdc_fitter_private.progress(b.id),
      'status', b.status,
      'version', b.version,
      'actual_start_at', b.actual_start_at,
      'actual_end_at', b.actual_end_at,
      'stoppage_reason', b.stoppage_reason,
      'stoppage_started_at', b.stoppage_started_at,
      'stoppage_accumulated_minutes', b.stoppage_accumulated_minutes
    )||pdc_bus_private.team_payload(b.id) END ORDER BY item.ordinality), '[]'::jsonb)
  INTO v_bookings
  FROM jsonb_array_elements(p_snapshot->'bookings') WITH ORDINALITY AS item(booking, ordinality)
  LEFT JOIN public.workshop_bookings b
    ON b.id = CASE
      WHEN coalesce(item.booking->>'booking_id','') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        THEN (item.booking->>'booking_id')::uuid
      WHEN coalesce(item.booking->>'id','') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        THEN (item.booking->>'id')::uuid
    END
  LEFT JOIN public.workshop_stages st ON st.id = b.stage_id
  LEFT JOIN LATERAL (
    SELECT h AS hours, CASE WHEN h IS NOT NULL AND h > 0 THEN round(h * 60)::integer END AS mins
    FROM (SELECT public.workshop_vehicle_stage_estimated_hours(b.vehicle_id, st.code) AS h) q
  ) est ON b.id IS NOT NULL;

  RETURN jsonb_set(p_snapshot, '{bookings}', v_bookings, true)||jsonb_build_object('planning_calendar', pdc_bus_private.planning_calendar());
END $function$;

ALTER TABLE public.workshop_bookings DROP CONSTRAINT workshop_bookings_active_vehicle_no_overlap;
ALTER TABLE public.workshop_bookings ADD CONSTRAINT workshop_bookings_active_vehicle_no_overlap
  EXCLUDE USING gist (vehicle_id WITH =, tstzrange(scheduled_start_at, scheduled_end_at, '[)'::text) WITH &&)
  WHERE (deleted_at IS NULL AND NOT legacy_ambiguity_quarantined AND bay_id IS NOT NULL
    AND status = ANY (ARRAY['queued'::public.workshop_booking_status, 'planned'::public.workshop_booking_status, 'started'::public.workshop_booking_status, 'stoppage'::public.workshop_booking_status]));

INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES
('key460_drag_597', 'F211', 'Key 460 Hoist shows the unticked hours. A row with no bay is not a vehicle conflict, and a booking is not a conflict with itself (r597).',
$chk$
SELECT src.prosrc LIKE '%r597 (F211)%'
  AND src.prosrc LIKE '%estimated_operation_hours%'
  AND public.workshop_vehicle_stage_estimated_hours('7a64124b-ab39-4069-a6c0-b756b2dc580f'::uuid, 'HOIST') = 5.00
  AND helper.prosrc LIKE '%b.bay_id is not null%'
  AND strpos(helper.prosrc, 'not (b.status=''queued'' and b.bay_id is null)') = 0
  AND strpos(mv.prosrc, 'if v_block is null then v_result:=jsonb_build_object(''ok'',false,''error'',''vehicle_overlap'')') = 0
  AND mv.prosrc LIKE '%b.bay_id is not null and b.id is distinct from p_booking_id%'
  AND pg_get_constraintdef('public.workshop_bookings_active_vehicle_no_overlap'::regclass) LIKE '%bay_id IS NOT NULL%'
  AS ok,
  'hoist open '||public.workshop_vehicle_stage_estimated_hours('7a64124b-ab39-4069-a6c0-b756b2dc580f'::uuid, 'HOIST')::text AS detail
FROM pg_proc src
JOIN pg_proc helper ON helper.oid = 'public.workshop_exclusion_conflict_571(uuid,uuid,timestamp with time zone,integer,text,integer,jsonb,boolean)'::regprocedure
JOIN pg_proc mv ON mv.oid = 'public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)'::regprocedure
WHERE src.oid = 'public.workshop_overlay_canonical_booking_fields_397(jsonb)'::regprocedure
$chk$,
true, 367, 'r597');
