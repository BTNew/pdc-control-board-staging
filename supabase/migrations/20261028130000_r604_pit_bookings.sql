-- r604 (F218) / sort 374. Staging cdsmnqxtyyoeoznmbidd only.
-- Production vjdtsswhroyguxyfjdkt is not a target.
-- Craig, 28 Oct 2026: the PIT tile lists every board vehicle that needs pitting, with a calendar
-- to book the pit date and place (PMB, Wangara or Wades). Vehicle Locations shows the pit date
-- left of Parts ETA with a day counter, and a green tick once the vehicle is ticked Back.
-- New objects only. No import function, pin, booking, location or Department 135 object changes.
-- Pin count stays 241. Kajel rows 9be0883b1a555f48f3c1ba9fa111c891 and apply
-- b62fb7c29ffd2a1629f214f696e5cb14 are not edited.
-- Undo: supabase/rollbacks/20261028130000_r604_pit_bookings.down.sql

SET LOCAL lock_timeout = '4s';
SET LOCAL statement_timeout = '60s';

DO $guard604$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45'
     OR awst BETWEEN time '06:50' AND time '07:30'
     OR awst BETWEEN time '17:50' AND time '18:10' THEN
    RAISE EXCEPTION 'r604: import window';
  END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'r604: staging only';
  END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r604: pin count'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks
             WHERE sort_order = 374 OR fault_id = 'F218' OR added_in = 'r604' OR check_name = 'pit_bookings_604') THEN
    RAISE EXCEPTION 'r604: sort 374 or F218 is taken';
  END IF;
  IF to_regnamespace('pdc_pit_private') IS NOT NULL THEN RAISE EXCEPTION 'r604: pdc_pit_private exists'; END IF;
END $guard604$;

CREATE SCHEMA pdc_pit_private;
REVOKE ALL ON SCHEMA pdc_pit_private FROM PUBLIC, anon, authenticated;

-- One pit booking per vehicle. A cleared date keeps the row (and its history) with pit_date null.
CREATE TABLE pdc_pit_private.bookings (
  vehicle_id uuid PRIMARY KEY REFERENCES public.vehicles(id) ON DELETE CASCADE,
  pit_date date,
  pit_location text CHECK (pit_location IN ('PMB', 'Wangara', 'Wades')),
  back boolean NOT NULL DEFAULT false,
  back_at timestamptz,
  back_by_email text,
  version integer NOT NULL DEFAULT 1,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid,
  updated_by_email text,
  CHECK ((pit_date IS NULL) = (pit_location IS NULL)),
  CHECK (NOT back OR pit_date IS NOT NULL)
);
ALTER TABLE pdc_pit_private.bookings ENABLE ROW LEVEL SECURITY;

CREATE TABLE pdc_pit_private.booking_history (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  vehicle_id uuid NOT NULL,
  before_value jsonb,
  after_value jsonb NOT NULL,
  actor_id uuid NOT NULL,
  actor_email text NOT NULL,
  actor_role text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX booking_history_vehicle_idx ON pdc_pit_private.booking_history (vehicle_id, created_at DESC);
ALTER TABLE pdc_pit_private.booking_history ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA pdc_pit_private FROM PUBLIC, anon, authenticated;

-- Read: every board vehicle with a PIT line (job card line or sublet PO description), plus its booking.
-- "NO PIT..." lines (e.g. NO PITTING REQUIRED) do not count. Board readers only (viewer role and up).
CREATE FUNCTION public.get_pdc_pit_board_604()
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
      'version', 'r604',
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
          'pit_date', k.pit_date, 'pit_location', k.pit_location,
          'back', coalesce(k.back, false), 'back_at', k.back_at, 'booking_version', coalesce(k.version, 0))
          ORDER BY k.pit_date NULLS FIRST, b.stock_number)
        FROM board b
        LEFT JOIN needs n ON n.vehicle_id = b.id
        LEFT JOIN pdc_pit_private.bookings k ON k.vehicle_id = b.id AND k.pit_date IS NOT NULL
        WHERE n.vehicle_id IS NOT NULL OR k.vehicle_id IS NOT NULL), '[]'::jsonb))
  END
$fn$;

-- Write: book, move, clear or tick Back. Controllers (operator) and administrators only.
-- p_pit_date null clears the booking. Back needs a booked date. Version guards a stale screen.
CREATE FUNCTION public.set_pdc_pit_booking_604(
  p_vehicle_id uuid, p_pit_date date, p_pit_location text, p_back boolean, p_expected_version integer)
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
    (vehicle_id, pit_date, pit_location, back, back_at, back_by_email, version, updated_at, updated_by, updated_by_email)
  VALUES (p_vehicle_id, p_pit_date, CASE WHEN p_pit_date IS NULL THEN NULL ELSE v_location END, v_back,
          CASE WHEN v_back THEN now() END, CASE WHEN v_back THEN v_email END, 1, now(), v_actor, v_email)
  ON CONFLICT (vehicle_id) DO UPDATE SET
    pit_date = excluded.pit_date,
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
    'pit_location', v_after.pit_location, 'back', v_after.back, 'back_at', v_after.back_at, 'version', v_after.version);
END
$fn$;

REVOKE ALL ON FUNCTION public.get_pdc_pit_board_604() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_pdc_pit_booking_604(uuid, date, text, boolean, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pdc_pit_board_604() TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_pdc_pit_booking_604(uuid, date, text, boolean, integer) TO authenticated;

DO $check604$
DECLARE ok boolean; detail text;
BEGIN
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('pit_bookings_604', 'F218',
    'Pit bookings: private table with RLS on, anon cannot read or write, locations limited to PMB/Wangara/Wades, pins stay 241.',
    $chk604$
SELECT
  (SELECT relrowsecurity FROM pg_catalog.pg_class WHERE oid = 'pdc_pit_private.bookings'::regclass)
  AND NOT pg_catalog.has_function_privilege('anon', 'public.get_pdc_pit_board_604()', 'execute')
  AND NOT pg_catalog.has_function_privilege('anon', 'public.set_pdc_pit_booking_604(uuid,date,text,boolean,integer)', 'execute')
  AND NOT pg_catalog.has_table_privilege('authenticated', 'pdc_pit_private.bookings', 'select')
  AND NOT EXISTS (SELECT 1 FROM pdc_pit_private.bookings WHERE pit_location NOT IN ('PMB', 'Wangara', 'Wades'))
  AND (SELECT count(*) FROM pdc_ops.expected_function_md5) = 241
 AS ok,
 'pit bookings stay private and valid' AS detail
$chk604$,
    true, 374, 'r604');
  EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'pit_bookings_604') INTO ok, detail;
  IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r604: check red: %', detail; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r604: pin count changed'; END IF;
END $check604$;
