-- r686 (F296, Craig 29 Oct 2026): Workshop TV shows a done job only up to when it was completed.
-- Read-only change: the TV read also returns each job's actual_end, and lists a completed job whose actual
-- start-to-finish falls on a shown day. Staging cdsmnqxtyyoeoznmbidd only.
-- Undo: supabase/rollbacks/20261029010000_r686_tv_done_ends.down.sql
SET LOCAL lock_timeout = '4s';
DO $c$ BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.get_pdc_workshop_tv_605()'::regprocedure) <> '845f391f2915c53dfceb68fc8e7f992b' THEN RAISE EXCEPTION 'r686 before: md5'; END IF;
  IF (SELECT proacl::text FROM pg_proc WHERE oid = 'public.get_pdc_workshop_tv_605()'::regprocedure) <> '{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}' THEN RAISE EXCEPTION 'r686 before: acl'; END IF;
  IF (SELECT provolatile FROM pg_proc WHERE oid = 'public.get_pdc_workshop_tv_605()'::regprocedure) <> 's' THEN RAISE EXCEPTION 'r686 before: stable'; END IF;
END $c$;

CREATE OR REPLACE FUNCTION public.get_pdc_workshop_tv_605()
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
    SELECT k.bay_id, k.status::text AS status, k.scheduled_start_at, k.scheduled_end_at, k.actual_start_at, k.actual_end_at,
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
           OR EXISTS (SELECT 1 FROM win w WHERE k.scheduled_start_at < w.to_at AND k.scheduled_end_at > w.from_at)
           OR (k.status = 'completed' AND k.actual_end_at IS NOT NULL
               AND EXISTS (SELECT 1 FROM win w WHERE coalesce(k.actual_start_at, k.actual_end_at) < w.to_at AND k.actual_end_at > w.from_at)))
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
                         'actual_start', j.actual_start_at, 'actual_end', j.actual_end_at, 'stoppage', j.stoppage_reason,
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

DO $c$ BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.get_pdc_workshop_tv_605()'::regprocedure) <> 'e8e93e9026e251fb00e934c4e1e160b8' THEN RAISE EXCEPTION 'r686 after: md5'; END IF;
  IF (SELECT proacl::text FROM pg_proc WHERE oid = 'public.get_pdc_workshop_tv_605()'::regprocedure) <> '{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}' THEN RAISE EXCEPTION 'r686 after: acl'; END IF;
  IF (SELECT provolatile FROM pg_proc WHERE oid = 'public.get_pdc_workshop_tv_605()'::regprocedure) <> 's' THEN RAISE EXCEPTION 'r686 after: stable'; END IF;
END $c$;
