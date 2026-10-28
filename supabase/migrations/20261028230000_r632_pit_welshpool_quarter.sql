-- r632 (F247) / sort 385. Staging cdsmnqxtyyoeoznmbidd only. Production vjdtsswhroyguxyfjdkt is not a target.
-- Craig, 28 Oct 2026 17:13 AWST: pit bookings need Welshpool as a 4th place and quarter-hour times (9.15am, 9.45am).
-- Widens the place and time checks on pdc_pit_private.bookings, set_pdc_pit_booking_630 (same body, wider lists) and the
-- read's place list. The r604 and r630 regression checks are widened to match. set_pdc_pit_booking_604 is unchanged
-- (old screens only). No import function, pin, planner booking, vehicle location or Department 135 change. Pins stay 241.
-- Undo: supabase/rollbacks/20261028230000_r632_pit_welshpool_quarter.down.sql

SET LOCAL lock_timeout = '4s';
SET LOCAL statement_timeout = '60s';

DO $guard632$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '06:50' AND time '07:30' OR awst BETWEEN time '17:50' AND time '18:10' THEN
    RAISE EXCEPTION 'r632: import window';
  END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'r632: staging only';
  END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r632: pin count'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 385 OR fault_id = 'F247' OR added_in = 'r632' OR check_name = 'pit_places_632') THEN
    RAISE EXCEPTION 'r632: sort 385 or F247 is taken';
  END IF;
  IF md5((SELECT prosrc FROM pg_proc WHERE oid = 'public.get_pdc_pit_board_604()'::regprocedure)) <> 'ec9da903db683d61d19281fd2db30dad'
     OR md5((SELECT prosrc FROM pg_proc WHERE oid = 'public.set_pdc_pit_booking_630(uuid,date,time,text,boolean,integer)'::regprocedure)) <> '31d8dad3932121e6e77b50faf4d8b7b8'
     OR md5((SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'pit_bookings_604')) <> 'b4dd3e3fed2ae0c1a4ea6c8fdf90e7ed'
     OR md5((SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'pit_time_630')) <> 'a40f03672d614752b44549eeb66dcccb' THEN
    RAISE EXCEPTION 'r632: pit objects changed since r630';
  END IF;
END $guard632$;

ALTER TABLE pdc_pit_private.bookings DROP CONSTRAINT bookings_pit_location_check;
ALTER TABLE pdc_pit_private.bookings ADD CONSTRAINT bookings_pit_location_check
  CHECK (pit_location = ANY (ARRAY['PMB'::text, 'Wangara'::text, 'Wades'::text, 'Welshpool'::text]));
ALTER TABLE pdc_pit_private.bookings DROP CONSTRAINT bookings_pit_time_slot_630;
ALTER TABLE pdc_pit_private.bookings ADD CONSTRAINT bookings_pit_time_slot_632 CHECK (pit_time IS NULL OR (pit_time BETWEEN time '05:00' AND time '19:00'
    AND extract(minute FROM pit_time) IN (0, 15, 30, 45) AND extract(second FROM pit_time) = 0));

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
      'version', 'r632',
      'today', (clock_timestamp() AT TIME ZONE 'Australia/Perth')::date,
      'can_edit', EXISTS (SELECT 1 FROM public.pdc_user_roles r
                          WHERE r.auth_user_id = auth.uid() AND lower(r.email) = lower(coalesce(auth.jwt()->>'email', ''))
                            AND r.active AND r.account_status = 'approved' AND r.role::text IN ('operator', 'administrator')),
      'locations', jsonb_build_array('PMB', 'Wangara', 'Wades', 'Welshpool'),
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

CREATE OR REPLACE FUNCTION public.set_pdc_pit_booking_630(
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
     OR (v_location IS NOT NULL AND v_location NOT IN ('PMB', 'Wangara', 'Wades', 'Welshpool'))
     OR (p_pit_date IS NULL AND v_back) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_input', 'message', 'Choose a date and PMB, Wangara, Wades or Welshpool.');
  END IF;
  IF v_time IS NOT NULL AND NOT (v_time BETWEEN time '05:00' AND time '19:00' AND extract(minute FROM v_time) IN (0, 15, 30, 45)
                                 AND extract(second FROM v_time) = 0) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_time', 'message', 'Pick a quarter-hour time between 05:00 and 19:00.');
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

UPDATE pdc_ops.regression_checks SET check_sql = $chk604$
SELECT
  (SELECT relrowsecurity FROM pg_catalog.pg_class WHERE oid = 'pdc_pit_private.bookings'::regclass)
  AND NOT pg_catalog.has_function_privilege('anon', 'public.get_pdc_pit_board_604()', 'execute')
  AND NOT pg_catalog.has_function_privilege('anon', 'public.set_pdc_pit_booking_604(uuid,date,text,boolean,integer)', 'execute')
  AND NOT pg_catalog.has_table_privilege('authenticated', 'pdc_pit_private.bookings', 'select')
  AND NOT EXISTS (SELECT 1 FROM pdc_pit_private.bookings WHERE pit_location NOT IN ('PMB', 'Wangara', 'Wades', 'Welshpool'))
  AND (SELECT count(*) FROM pdc_ops.expected_function_md5) = 241
 AS ok,
 'pit bookings stay private and valid' AS detail
$chk604$ WHERE check_name = 'pit_bookings_604';
UPDATE pdc_ops.regression_checks SET check_sql = $chk630$
SELECT
  NOT pg_catalog.has_function_privilege('anon', 'public.set_pdc_pit_booking_630(uuid,date,time,text,boolean,integer)', 'execute')
  AND pg_catalog.has_function_privilege('authenticated', 'public.set_pdc_pit_booking_630(uuid,date,time,text,boolean,integer)', 'execute')
  AND strpos((SELECT prosrc FROM pg_catalog.pg_proc WHERE oid = 'public.get_pdc_pit_board_604()'::regprocedure), '''pit_time''') > 0
  AND NOT EXISTS (SELECT 1 FROM pdc_pit_private.bookings WHERE pit_time IS NOT NULL
                   AND NOT (extract(minute FROM pit_time) IN (0, 15, 30, 45) AND pit_time BETWEEN time '05:00' AND time '19:00'))
  AND (SELECT count(*) FROM pdc_ops.expected_function_md5) = 241
 AS ok,
 'pit times stay on the half hour and the writer stays private' AS detail
$chk630$ WHERE check_name = 'pit_time_630';

DO $check632$
DECLARE ok boolean; detail text; name text;
BEGIN
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('pit_places_632', 'F247',
    'Pit places are PMB, Wangara, Wades and Welshpool; times on the quarter hour; the writer accepts both; pins stay 241.',
    $chk632$
SELECT
  strpos((SELECT prosrc FROM pg_catalog.pg_proc WHERE oid = 'public.set_pdc_pit_booking_630(uuid,date,time,text,boolean,integer)'::regprocedure), '''Welshpool''') > 0
  AND strpos((SELECT prosrc FROM pg_catalog.pg_proc WHERE oid = 'public.set_pdc_pit_booking_630(uuid,date,time,text,boolean,integer)'::regprocedure), 'IN (0, 15, 30, 45)') > 0
  AND NOT EXISTS (SELECT 1 FROM pdc_pit_private.bookings WHERE pit_location NOT IN ('PMB', 'Wangara', 'Wades', 'Welshpool'))
  AND NOT EXISTS (SELECT 1 FROM pdc_pit_private.bookings WHERE pit_time IS NOT NULL AND extract(minute FROM pit_time) NOT IN (0, 15, 30, 45))
  AND NOT pg_catalog.has_function_privilege('anon', 'public.set_pdc_pit_booking_630(uuid,date,time,text,boolean,integer)', 'execute')
  AND (SELECT count(*) FROM pdc_ops.expected_function_md5) = 241
 AS ok,
 'pit places and quarter-hour times are allowed and nothing else' AS detail
$chk632$,
    true, 385, 'r632');
  FOREACH name IN ARRAY ARRAY['pit_bookings_604', 'pit_time_630', 'pit_places_632'] LOOP
    EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = name) INTO ok, detail;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r632: % red: %', name, detail; END IF;
  END LOOP;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r632: pin count changed'; END IF;
END $check632$;
