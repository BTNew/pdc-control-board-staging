-- r630 (F245) / sort 383. Staging cdsmnqxtyyoeoznmbidd only. Production vjdtsswhroyguxyfjdkt is not a target.
-- Craig, 28 Oct 2026 16:51 AWST: dropping a vehicle on the pit calendar asks for a time (07:00 to 17:00, every half
-- hour) and the place (PMB, Wangara, Wades) in one box, then saves. One calendar for all three places.
-- Adds pit_time to pdc_pit_private.bookings, returns it from get_pdc_pit_board_604 (body otherwise unchanged), and a new
-- writer set_pdc_pit_booking_630 that also takes the time. set_pdc_pit_booking_604 is left as is (it keeps the time).
-- No import function, pin, planner booking, vehicle location or Department 135 change. Pins stay 241.
-- Undo: supabase/rollbacks/20261028220000_r630_pit_time.down.sql

SET LOCAL lock_timeout = '4s';
SET LOCAL statement_timeout = '60s';

DO $guard630$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '06:50' AND time '07:30' OR awst BETWEEN time '17:50' AND time '18:10' THEN
    RAISE EXCEPTION 'r630: import window';
  END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'r630: staging only';
  END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r630: pin count'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 383 OR fault_id = 'F245' OR added_in = 'r630' OR check_name = 'pit_time_630') THEN
    RAISE EXCEPTION 'r630: sort 383 or F245 is taken';
  END IF;
  IF md5((SELECT prosrc FROM pg_proc WHERE oid = 'public.get_pdc_pit_board_604()'::regprocedure)) <> '0e5b8e6cd38b32188fb0a6aebe177e8a' THEN
    RAISE EXCEPTION 'r630: get_pdc_pit_board_604 changed';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'pdc_pit_private' AND table_name = 'bookings' AND column_name = 'pit_time') THEN
    RAISE EXCEPTION 'r630: pit_time exists';
  END IF;
  IF to_regprocedure('public.set_pdc_pit_booking_630(uuid,date,time,text,boolean,integer)') IS NOT NULL THEN RAISE EXCEPTION 'r630: writer exists'; END IF;
END $guard630$;

-- Half-hour slots only, 05:00 to 19:00 (the box offers 07:00 to 17:00).
ALTER TABLE pdc_pit_private.bookings ADD COLUMN pit_time time
  CONSTRAINT bookings_pit_time_slot_630 CHECK (pit_time IS NULL OR (pit_time BETWEEN time '05:00' AND time '19:00'
    AND extract(minute FROM pit_time) IN (0, 30) AND extract(second FROM pit_time) = 0));

CREATE OR REPLACE FUNCTION public.get_pdc_pit_board_604()
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = pg_catalog, public
AS $fn$
  WITH board AS (
    SELECT v.id, v.stock_number, v.key_number, v.job_card_number, v.vehicle_description, v.model,
           v.current_location, v.location_override
    FROM public.vehicles v
    WHERE v.deleted_at IS NULL AND v.visible_on_board
  ), lines AS (
    SELECT o.vehicle_id, o.operation_description AS description
    FROM public.pdc_pilbara_service_operations o
    WHERE o.operation_description ~* '\mpit' AND o.operation_description !~* '\mno\s+pit'
    UNION
    SELECT r.vehicle_id, r.description
    FROM public.pdc_service_line_po_refs_439 r
    WHERE r.active AND r.description ~* '\mpit' AND r.description !~* '\mno\s+pit'
  ), needs AS (
    SELECT l.vehicle_id, jsonb_agg(DISTINCT btrim(l.description)) AS pit_lines
    FROM lines l JOIN board b ON b.id = l.vehicle_id
    GROUP BY l.vehicle_id
  )
  SELECT CASE WHEN NOT coalesce(public.is_pdc_role('viewer'::public.pdc_role), false) THEN NULL::jsonb ELSE
    jsonb_build_object(
      'version', 'r630',
      'today', (clock_timestamp() AT TIME ZONE 'Australia/Perth')::date,
      'can_edit', EXISTS (SELECT 1 FROM public.pdc_user_roles r
                          WHERE r.auth_user_id = auth.uid() AND lower(r.email) = lower(coalesce(auth.jwt()->>'email', ''))
                            AND r.active AND r.account_status = 'approved' AND r.role::text IN ('operator', 'administrator')),
      'locations', jsonb_build_array('PMB', 'Wangara', 'Wades'),
      'vehicles', coalesce((
        SELECT jsonb_agg(jsonb_build_object(
          'vehicle_id', b.id, 'stock_number', b.stock_number, 'key_number', b.key_number,
          'job_card_number', b.job_card_number,
          'vehicle', coalesce(nullif(btrim(b.vehicle_description), ''), b.model),
          'location', coalesce(nullif(b.location_override, ''), b.current_location),
          'pit_lines', coalesce(n.pit_lines, '[]'::jsonb),
          'needs_pit', n.vehicle_id IS NOT NULL,
          'pit_date', k.pit_date, 'pit_time', to_char(k.pit_time, 'HH24:MI'), 'pit_location', k.pit_location,
          'back', coalesce(k.back, false), 'back_at', k.back_at, 'booking_version', coalesce(k.version, 0))
          ORDER BY k.pit_date NULLS FIRST, k.pit_time NULLS FIRST, b.stock_number)
        FROM board b
        LEFT JOIN needs n ON n.vehicle_id = b.id
        LEFT JOIN pdc_pit_private.bookings k ON k.vehicle_id = b.id AND k.pit_date IS NOT NULL
        WHERE n.vehicle_id IS NOT NULL OR k.vehicle_id IS NOT NULL), '[]'::jsonb))
  END
$fn$;

-- Write: book, move, re-time, clear or tick Back. Controllers (operator) and administrators only.
-- p_pit_date null clears the booking and its time. Back needs a booked date. Version guards a stale screen.
CREATE FUNCTION public.set_pdc_pit_booking_630(
  p_vehicle_id uuid, p_pit_date date, p_pit_time time, p_pit_location text, p_back boolean, p_expected_version integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $fn$
DECLARE
  v_actor uuid := auth.uid();
  v_email text := lower(btrim(coalesce(auth.jwt()->>'email', '')));
  v_role text;
  v_before pdc_pit_private.bookings%ROWTYPE;
  v_after pdc_pit_private.bookings%ROWTYPE;
  v_location text := nullif(btrim(coalesce(p_pit_location, '')), '');
  v_back boolean := coalesce(p_back, false);
  v_time time := CASE WHEN p_pit_date IS NULL THEN NULL ELSE p_pit_time END;
BEGIN
  SELECT r.role::text INTO v_role FROM public.pdc_user_roles r
   WHERE r.auth_user_id = v_actor AND lower(r.email) = v_email AND r.active AND r.account_status = 'approved'
     AND r.role::text IN ('operator', 'administrator') LIMIT 1;
  IF v_actor IS NULL OR v_email = '' OR v_role IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_allowed', 'message', 'Only controllers and administrators can book pits.');
  END IF;
  IF p_vehicle_id IS NULL OR p_expected_version IS NULL OR p_expected_version < 0
     OR (p_pit_date IS NOT NULL AND v_location IS NULL)
     OR (v_location IS NOT NULL AND v_location NOT IN ('PMB', 'Wangara', 'Wades'))
     OR (p_pit_date IS NULL AND v_back) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_input', 'message', 'Choose a date and PMB, Wangara or Wades.');
  END IF;
  IF v_time IS NOT NULL AND NOT (v_time BETWEEN time '05:00' AND time '19:00' AND extract(minute FROM v_time) IN (0, 30)
                                 AND extract(second FROM v_time) = 0) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_time', 'message', 'Pick a half-hour time between 05:00 and 19:00.');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.vehicles v WHERE v.id = p_vehicle_id AND v.deleted_at IS NULL) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'vehicle_missing', 'message', 'That vehicle is no longer on the board.');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-pit-604:' || p_vehicle_id::text, 0));
  SELECT * INTO v_before FROM pdc_pit_private.bookings WHERE vehicle_id = p_vehicle_id FOR UPDATE;
  IF coalesce(v_before.version, 0) <> p_expected_version THEN
    RETURN jsonb_build_object('ok', false, 'error', 'stale', 'message', 'Someone else changed this pit booking. Refresh and try again.',
                              'version', coalesce(v_before.version, 0));
  END IF;

  INSERT INTO pdc_pit_private.bookings AS b
    (vehicle_id, pit_date, pit_time, pit_location, back, back_at, back_by_email, version, updated_at, updated_by, updated_by_email)
  VALUES (p_vehicle_id, p_pit_date, v_time, CASE WHEN p_pit_date IS NULL THEN NULL ELSE v_location END, v_back,
          CASE WHEN v_back THEN now() END, CASE WHEN v_back THEN v_email END, 1, now(), v_actor, v_email)
  ON CONFLICT (vehicle_id) DO UPDATE SET
    pit_date = excluded.pit_date,
    pit_time = excluded.pit_time,
    pit_location = excluded.pit_location,
    back = excluded.back,
    back_at = CASE WHEN excluded.back AND b.back THEN b.back_at WHEN excluded.back THEN now() END,
    back_by_email = CASE WHEN excluded.back AND b.back THEN b.back_by_email WHEN excluded.back THEN v_email END,
    version = b.version + 1,
    updated_at = now(), updated_by = v_actor, updated_by_email = v_email
  WHERE b.vehicle_id = excluded.vehicle_id
  RETURNING * INTO v_after;

  INSERT INTO pdc_pit_private.booking_history (vehicle_id, before_value, after_value, actor_id, actor_email, actor_role)
  VALUES (p_vehicle_id, CASE WHEN v_before.vehicle_id IS NULL THEN NULL ELSE to_jsonb(v_before) END, to_jsonb(v_after),
          v_actor, v_email, v_role);

  RETURN jsonb_build_object('ok', true, 'vehicle_id', p_vehicle_id, 'pit_date', v_after.pit_date,
    'pit_time', to_char(v_after.pit_time, 'HH24:MI'), 'pit_location', v_after.pit_location, 'back', v_after.back,
    'back_at', v_after.back_at, 'version', v_after.version);
END
$fn$;

REVOKE ALL ON FUNCTION public.set_pdc_pit_booking_630(uuid, date, time, text, boolean, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_pdc_pit_booking_630(uuid, date, time, text, boolean, integer) TO authenticated;

DO $check630$
DECLARE ok boolean; detail text;
BEGIN
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('pit_time_630', 'F245',
    'Pit booking time: half-hour slots only, anon cannot call the writer, the read returns pit_time, pins stay 241.',
    $chk630$
SELECT
  NOT pg_catalog.has_function_privilege('anon', 'public.set_pdc_pit_booking_630(uuid,date,time,text,boolean,integer)', 'execute')
  AND pg_catalog.has_function_privilege('authenticated', 'public.set_pdc_pit_booking_630(uuid,date,time,text,boolean,integer)', 'execute')
  AND strpos((SELECT prosrc FROM pg_catalog.pg_proc WHERE oid = 'public.get_pdc_pit_board_604()'::regprocedure), '''pit_time''') > 0
  AND NOT EXISTS (SELECT 1 FROM pdc_pit_private.bookings WHERE pit_time IS NOT NULL
                   AND NOT (extract(minute FROM pit_time) IN (0, 30) AND pit_time BETWEEN time '05:00' AND time '19:00'))
  AND (SELECT count(*) FROM pdc_ops.expected_function_md5) = 241
 AS ok,
 'pit times stay on the half hour and the writer stays private' AS detail
$chk630$,
    true, 383, 'r630');
  EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'pit_time_630') INTO ok, detail;
  IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r630: check red: %', detail; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r630: pin count changed'; END IF;
END $check630$;
