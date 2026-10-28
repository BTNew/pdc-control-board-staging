-- r605 (F219) / sort 375. Staging cdsmnqxtyyoeoznmbidd only.
-- Production vjdtsswhroyguxyfjdkt is not a target.
-- Craig, 28 Oct 2026: a workshop TV that shows every station's bays on today and the next working day
-- like the control board, red when a job is running past its end. View only. One lean read, no writes.
-- New function only. Pin count stays 241. Kajel and Department 135 untouched.
-- Undo: supabase/rollbacks/20261028140000_r605_workshop_tv.down.sql

SET LOCAL lock_timeout = '4s';
SET LOCAL statement_timeout = '60s';

DO $guard605$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45'
     OR awst BETWEEN time '06:50' AND time '07:30'
     OR awst BETWEEN time '17:50' AND time '18:10' THEN
    RAISE EXCEPTION 'r605: import window';
  END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'r605: staging only';
  END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r605: pin count'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks
             WHERE sort_order = 375 OR fault_id = 'F219' OR added_in = 'r605' OR check_name = 'workshop_tv_605') THEN
    RAISE EXCEPTION 'r605: sort 375 or F219 is taken';
  END IF;
  IF to_regprocedure('public.get_pdc_workshop_tv_605()') IS NOT NULL THEN RAISE EXCEPTION 'r605: function exists'; END IF;
END $guard605$;

-- Today and the next working day (Perth, from workshop_settings.working_week) for every planner station with
-- active bays, and every booking in a bay that touches either day or is live now. "overrun" is the planner's
-- red rule: started (or on stoppage since after its end) and past its scheduled end. Board readers only.
CREATE FUNCTION public.get_pdc_workshop_tv_605()
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = pg_catalog, public
AS $fn$
  WITH clock AS (
    SELECT clock_timestamp() AS now_at,
           (clock_timestamp() AT TIME ZONE 'Australia/Perth')::date AS today,
           coalesce((SELECT value #>> '{}' FROM public.workshop_settings WHERE key = 'day_start_time'), '07:00') AS day_start,
           coalesce((SELECT value #>> '{}' FROM public.workshop_settings WHERE key = 'day_end_time'), '17:00') AS day_end,
           coalesce((SELECT array_agg(lower(d)) FROM public.workshop_settings w, jsonb_array_elements_text(w.value) d
                     WHERE w.key = 'working_week' AND jsonb_typeof(w.value) = 'array'),
                    ARRAY['monday','tuesday','wednesday','thursday','friday']) AS week
  ), days AS (
    SELECT c.today AS day, 1 AS n FROM clock c
    UNION ALL
    SELECT (SELECT d::date FROM generate_series(c.today + 1, c.today + 10, interval '1 day') d
            WHERE lower(trim(to_char(d, 'FMday'))) = ANY (c.week) ORDER BY d LIMIT 1), 2
    FROM clock c
  ), win AS (
    SELECT d.n, d.day, ((d.day + c.day_start::time) AT TIME ZONE 'Australia/Perth') AS from_at,
                       ((d.day + c.day_end::time) AT TIME ZONE 'Australia/Perth') AS to_at
    FROM days d CROSS JOIN clock c WHERE d.day IS NOT NULL
  ), bays AS (
    SELECT b.id, b.stage_id, b.bay_number, b.display_name, t.name AS technician
    FROM public.workshop_bays b
    JOIN public.workshop_stages s ON s.id = b.stage_id AND s.active AND s.planner_enabled AND NOT s.is_sublet
    LEFT JOIN public.workshop_technicians t ON t.id = b.default_technician_id AND t.active
    WHERE b.is_active AND NOT b.is_sublet_row
  ), jobs AS (
    SELECT k.bay_id, k.status::text AS status, k.scheduled_start_at, k.scheduled_end_at, k.actual_start_at,
           k.stoppage_reason, v.key_number, v.stock_number,
           coalesce(nullif(btrim(v.model), ''), nullif(btrim(v.vehicle_description), '')) AS vehicle,
           (k.status = 'started' AND c.now_at > k.scheduled_end_at)
             OR (k.status = 'stoppage' AND coalesce(k.stoppage_started_at, c.now_at) > k.scheduled_end_at) AS overrun
    FROM public.workshop_bookings k
    JOIN bays b ON b.id = k.bay_id
    JOIN public.vehicles v ON v.id = k.vehicle_id AND v.deleted_at IS NULL
    CROSS JOIN clock c
    WHERE k.deleted_at IS NULL AND k.status IN ('queued', 'planned', 'started', 'stoppage', 'completed')
      AND (k.status IN ('started', 'stoppage')
           OR EXISTS (SELECT 1 FROM win w WHERE k.scheduled_start_at < w.to_at AND k.scheduled_end_at > w.from_at))
  )
  SELECT CASE WHEN NOT coalesce(public.is_pdc_role('viewer'::public.pdc_role), false) THEN NULL::jsonb ELSE (
    SELECT jsonb_build_object(
      'version', 'r605', 'now', c.now_at, 'day_start', c.day_start, 'day_end', c.day_end,
      'days', (SELECT jsonb_agg(jsonb_build_object('date', w.day, 'from', w.from_at, 'to', w.to_at) ORDER BY w.n) FROM win w),
      'stations', coalesce((
        SELECT jsonb_agg(jsonb_build_object('code', s.code, 'name', s.display_name, 'bays', (
            SELECT jsonb_agg(jsonb_build_object('id', b.id, 'number', b.bay_number,
                     'name', coalesce(nullif(btrim(b.display_name), ''), s.display_name || ' ' || b.bay_number),
                     'technician', b.technician,
                     'jobs', coalesce((SELECT jsonb_agg(jsonb_build_object(
                         'status', j.status, 'start', j.scheduled_start_at, 'end', j.scheduled_end_at,
                         'actual_start', j.actual_start_at, 'stoppage', j.stoppage_reason,
                         'key', j.key_number, 'stock', j.stock_number, 'vehicle', j.vehicle, 'overrun', j.overrun)
                         ORDER BY j.scheduled_start_at) FROM jobs j WHERE j.bay_id = b.id), '[]'::jsonb))
                     ORDER BY b.bay_number)
            FROM bays b WHERE b.stage_id = s.id))
          ORDER BY s.sort_order)
        FROM public.workshop_stages s
        WHERE EXISTS (SELECT 1 FROM bays b WHERE b.stage_id = s.id)), '[]'::jsonb))
    FROM clock c)
  END
$fn$;

REVOKE ALL ON FUNCTION public.get_pdc_workshop_tv_605() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pdc_workshop_tv_605() TO authenticated;

DO $check605$
DECLARE ok boolean; detail text;
BEGIN
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('workshop_tv_605', 'F219',
    'Workshop TV read: read-only (STABLE), anon cannot call it, pins stay 241.',
    $chk605$
SELECT
  (SELECT provolatile = 's' FROM pg_catalog.pg_proc WHERE oid = pg_catalog.to_regprocedure('public.get_pdc_workshop_tv_605()'))
  AND NOT pg_catalog.has_function_privilege('anon', 'public.get_pdc_workshop_tv_605()', 'execute')
  AND (SELECT count(*) FROM pdc_ops.expected_function_md5) = 241
 AS ok,
 'workshop TV read stays read-only and signed-in' AS detail
$chk605$,
    true, 375, 'r605');
  EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'workshop_tv_605') INTO ok, detail;
  IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r605: check red: %', detail; END IF;
END $check605$;
