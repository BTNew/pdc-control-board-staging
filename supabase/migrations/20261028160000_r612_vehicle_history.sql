-- r612 (F226) / sort 377. Staging cdsmnqxtyyoeoznmbidd only.
-- Production vjdtsswhroyguxyfjdkt is not a target.
-- Craig, 28 Oct 2026: Completed must show every vehicle that has ever been at PMB, including vehicles taken
-- off the board because they dropped off an upload, with import date, completion times, bay times, what
-- was done and pit inspection data. Nothing is hard-deleted, so this reads the kept rows.
-- Two read-only functions. Pin count stays 241. Kajel and Department 135 untouched.
-- Undo: supabase/rollbacks/20261028160000_r612_vehicle_history.down.sql

SET LOCAL lock_timeout = '4s';
SET LOCAL statement_timeout = '60s';

DO $guard607$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45'
     OR awst BETWEEN time '06:50' AND time '07:30'
     OR awst BETWEEN time '17:50' AND time '18:10' THEN
    RAISE EXCEPTION 'r612: import window';
  END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'r612: staging only';
  END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r612: pin count'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks
             WHERE sort_order = 377 OR fault_id = 'F226' OR added_in = 'r612' OR check_name = 'vehicle_history_612') THEN
    RAISE EXCEPTION 'r612: sort 377 or F226 is taken';
  END IF;
  IF to_regprocedure('public.get_pdc_vehicle_history_612()') IS NOT NULL THEN RAISE EXCEPTION 'r612: function exists'; END IF;
END $guard607$;

-- Every vehicle that has been at PMB: a 138/139 job card, a date to PMB, or a workshop booking.
-- One summary row each, newest first. Board readers only.
CREATE FUNCTION public.get_pdc_vehicle_history_612()
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = pg_catalog, public
AS $fn$
  WITH v AS (
    SELECT v.* FROM public.vehicles v
    WHERE v.job_card_number ~* '^J13[89]' OR v.date_to_pmb IS NOT NULL
       OR EXISTS (SELECT 1 FROM public.workshop_bookings b WHERE b.vehicle_id = v.id)
  ), lines AS (
    SELECT o.vehicle_id, count(*) AS total,
           count(*) FILTER (WHERE t.completed) AS done,
           sum(coalesce(o.effective_estimated_hours, o.source_estimated_hours, 0)) AS hours
    FROM public.pdc_pilbara_service_operations o
    LEFT JOIN public.pdc_panel_line_completion_565 t ON t.vehicle_id = o.vehicle_id AND t.line_identity = 'source:' || o.operation_id::text
    WHERE o.vehicle_id IN (SELECT id FROM v)
    GROUP BY o.vehicle_id
  ), bays AS (
    SELECT b.vehicle_id, count(*) AS bookings,
           sum(EXTRACT(epoch FROM (b.scheduled_end_at - b.scheduled_start_at)) / 60) FILTER (WHERE b.status = 'completed') AS booked_min,
           sum(coalesce(b.actual_duration_minutes, EXTRACT(epoch FROM (b.actual_end_at - b.actual_start_at)) / 60)) FILTER (WHERE b.actual_end_at IS NOT NULL) AS actual_min,
           min(b.actual_start_at) AS first_start, max(b.actual_end_at) AS last_end,
           array_agg(DISTINCT s.display_name) FILTER (WHERE b.status IN ('started', 'stoppage', 'completed')) AS stations
    FROM public.workshop_bookings b
    JOIN public.workshop_stages s ON s.id = b.stage_id
    WHERE b.deleted_at IS NULL AND b.vehicle_id IN (SELECT id FROM v)
    GROUP BY b.vehicle_id
  )
  SELECT CASE WHEN NOT coalesce(public.is_pdc_role('viewer'::public.pdc_role), false) THEN NULL::jsonb ELSE
    jsonb_build_object('version', 'r612', 'generated_at', clock_timestamp(), 'vehicles', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'id', v.id, 'stock', v.stock_number, 'key', v.key_number, 'job_card', v.job_card_number,
        'vehicle', coalesce(nullif(btrim(v.vehicle_description), ''), v.model), 'customer', v.customer_name,
        'status', CASE
          WHEN v.deleted_at IS NOT NULL THEN 'deleted'
          WHEN v.board_purged_at IS NOT NULL THEN 'removed'
          WHEN v.lifecycle_state = 'completed' OR v.rft_collected_at IS NOT NULL THEN 'completed'
          WHEN v.lifecycle_state = 'rft' OR v.rft_transferred_at IS NOT NULL THEN 'rft'
          WHEN v.visible_on_board THEN 'on_board'
          ELSE 'hidden' END,
        'location', coalesce(nullif(v.location_override, ''), v.current_location),
        'imported_at', v.created_at, 'to_pmb', v.date_to_pmb,
        'qc_done_at', v.qc_completed_at, 'rft_at', coalesce(v.rft_transferred_at, v.date_to_rft::timestamptz),
        'collected_at', v.rft_collected_at, 'delivered', v.delivered_to_dealer_date,
        'removed_at', coalesce(v.deleted_at, v.board_purged_at), 'removed_reason', coalesce(v.deleted_reason, v.board_purge_reason),
        'lines', coalesce(l.total, 0), 'lines_done', coalesce(l.done, 0), 'quoted_hours', round(coalesce(l.hours, 0)::numeric, 1),
        'bookings', coalesce(b.bookings, 0), 'booked_hours', round(coalesce(b.booked_min, 0)::numeric / 60, 1),
        'actual_hours', round(coalesce(b.actual_min, 0)::numeric / 60, 1),
        'first_work', b.first_start, 'last_work', b.last_end, 'stations', coalesce(to_jsonb(b.stations), '[]'::jsonb),
        'pit_date', p.pit_date, 'pit_location', p.pit_location, 'pit_back', coalesce(p.back, false))
        ORDER BY coalesce(v.deleted_at, v.board_purged_at, v.rft_collected_at, v.qc_completed_at, v.updated_at) DESC NULLS LAST)
      FROM v
      LEFT JOIN lines l ON l.vehicle_id = v.id
      LEFT JOIN bays b ON b.vehicle_id = v.id
      LEFT JOIN pdc_pit_private.bookings p ON p.vehicle_id = v.id AND p.pit_date IS NOT NULL), '[]'::jsonb))
  END
$fn$;

-- Everything kept for one vehicle: job lines and ticks, every bay booking with actual times, fitter line
-- timings, pit booking and pit line ticks, lifecycle events and board removals. Board readers only.
CREATE FUNCTION public.get_pdc_vehicle_history_detail_612(p_vehicle_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = pg_catalog, public
AS $fn$
  SELECT CASE WHEN NOT coalesce(public.is_pdc_role('viewer'::public.pdc_role), false) OR p_vehicle_id IS NULL THEN NULL::jsonb ELSE (
    SELECT jsonb_build_object(
      'version', 'r612', 'id', v.id, 'stock', v.stock_number, 'key', v.key_number, 'job_card', v.job_card_number,
      'vin', v.vin, 'rego', v.registration, 'vehicle', coalesce(nullif(btrim(v.vehicle_description), ''), v.model),
      'customer', v.customer_name, 'location', coalesce(nullif(v.location_override, ''), v.current_location),
      'lifecycle', v.lifecycle_state, 'on_board', v.visible_on_board AND v.deleted_at IS NULL,
      'imported_at', v.created_at, 'to_pmb', v.date_to_pmb, 'qc_done_at', v.qc_completed_at,
      'rft_at', coalesce(v.rft_transferred_at, v.date_to_rft::timestamptz), 'rft_confirmed_at', v.rft_confirmed_at,
      'collected_at', v.rft_collected_at, 'delivered', v.delivered_to_dealer_date,
      'removed_at', coalesce(v.deleted_at, v.board_purged_at), 'removed_reason', coalesce(v.deleted_reason, v.board_purge_reason),
      'lines', coalesce((
        SELECT jsonb_agg(jsonb_build_object('ro', o.repair_order_number, 'line', o.original_line_number,
                 'description', o.operation_description, 'station', o.proposed_station, 'department', o.department,
                 'hours', coalesce(o.effective_estimated_hours, o.source_estimated_hours),
                 'imported_at', o.created_at, 'done', coalesce(t.completed, false), 'done_at', t.acted_at, 'done_by', t.actor_email,
                 'pit', o.operation_description ~* '\mpit' AND o.operation_description !~* '\mno\s+pit')
               ORDER BY o.repair_order_number, o.original_line_number)
        FROM public.pdc_pilbara_service_operations o
        LEFT JOIN public.pdc_panel_line_completion_565 t ON t.vehicle_id = o.vehicle_id AND t.line_identity = 'source:' || o.operation_id::text
        WHERE o.vehicle_id = v.id), '[]'::jsonb),
      'bookings', coalesce((
        SELECT jsonb_agg(jsonb_build_object('id', b.id, 'station', s.display_name, 'bay', coalesce(nullif(btrim(wb.display_name), ''), s.display_name || ' ' || wb.bay_number),
                 'technician', tech.name, 'status', b.status, 'start', b.scheduled_start_at, 'end', b.scheduled_end_at,
                 'actual_start', b.actual_start_at, 'actual_end', b.actual_end_at,
                 'actual_minutes', coalesce(b.actual_duration_minutes, round(EXTRACT(epoch FROM (b.actual_end_at - b.actual_start_at)) / 60)),
                 'stoppage', b.stoppage_reason, 'stoppage_minutes', b.stoppage_accumulated_minutes,
                 'line_timings', coalesce((
                   SELECT jsonb_agg(jsonb_build_object('line', ot.line_identity, 'technician', ft.name, 'status', ot.status,
                            'started_at', ot.started_at, 'completed_at', ot.completed_at, 'minutes', round(coalesce(ot.actual_seconds, 0) / 60.0))
                          ORDER BY ot.started_at)
                   FROM pdc_fitter_private.operation_timing ot
                   LEFT JOIN public.workshop_technicians ft ON ft.id = ot.technician_id
                   WHERE ot.booking_id = b.id), '[]'::jsonb))
               ORDER BY b.scheduled_start_at)
        FROM public.workshop_bookings b
        JOIN public.workshop_stages s ON s.id = b.stage_id
        LEFT JOIN public.workshop_bays wb ON wb.id = b.bay_id
        LEFT JOIN public.workshop_technicians tech ON tech.id = wb.default_technician_id
        WHERE b.vehicle_id = v.id AND b.deleted_at IS NULL), '[]'::jsonb),
      'pit', (SELECT jsonb_build_object('date', p.pit_date, 'location', p.pit_location, 'back', p.back, 'back_at', p.back_at,
                       'back_by', p.back_by_email, 'updated_at', p.updated_at, 'updated_by', p.updated_by_email)
              FROM pdc_pit_private.bookings p WHERE p.vehicle_id = v.id AND p.pit_date IS NOT NULL),
      'pit_ticks', coalesce((
        SELECT jsonb_agg(jsonb_build_object('line', pt.line_identity, 'ticked', pt.ticked, 'at', pt.ticked_at, 'by', pt.ticked_by_email,
                 'description', (SELECT o.operation_description FROM public.pdc_pilbara_service_operations o
                                 WHERE pt.line_identity = 'source:' || o.operation_id::text)) ORDER BY pt.ticked_at)
        FROM public.pdc_pit_line_ticks_401 pt WHERE pt.vehicle_id = v.id), '[]'::jsonb),
      'events', coalesce((
        SELECT jsonb_agg(e ORDER BY e->>'at') FROM (
          SELECT jsonb_build_object('at', le.event_at, 'what', le.event_kind, 'by', le.actor_email) e
          FROM public.pdc_vehicle_lifecycle_events le WHERE le.vehicle_id = v.id
          UNION ALL
          SELECT jsonb_build_object('at', a.archived_at, 'what', 'Removed from board: no longer on the Service as a Whole upload', 'by', a.archived_by::text)
          FROM pdc_codex_intake_private.service_whole_archive_receipt_569 a WHERE a.vehicle_id = v.id
          UNION ALL
          SELECT jsonb_build_object('at', a.unarchived_at, 'what', 'Put back on board', 'by', a.unarchived_by::text)
          FROM pdc_codex_intake_private.service_whole_archive_receipt_569 a WHERE a.vehicle_id = v.id AND a.unarchived_at IS NOT NULL
          UNION ALL
          SELECT jsonb_build_object('at', tb.deleted_at, 'what', 'Deleted: ' || coalesce(tb.reason, tb.tombstone_kind), 'by', tb.deleted_by_email)
          FROM public.pdc_vehicle_tombstones tb WHERE tb.vehicle_id = v.id) x), '[]'::jsonb))
    FROM public.vehicles v WHERE v.id = p_vehicle_id)
  END
$fn$;

REVOKE ALL ON FUNCTION public.get_pdc_vehicle_history_612() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_pdc_vehicle_history_detail_612(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_pdc_vehicle_history_612() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_pdc_vehicle_history_detail_612(uuid) TO authenticated;

DO $check607$
DECLARE ok boolean; detail text;
BEGIN
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('vehicle_history_612', 'F226',
    'Vehicle history reads are read-only and signed-in; removed and deleted vehicles stay in the vehicles table.',
    $chk607$
SELECT
  (SELECT bool_and(provolatile = 's') FROM pg_catalog.pg_proc WHERE oid IN (pg_catalog.to_regprocedure('public.get_pdc_vehicle_history_612()'), pg_catalog.to_regprocedure('public.get_pdc_vehicle_history_detail_612(uuid)')))
  AND NOT pg_catalog.has_function_privilege('anon', 'public.get_pdc_vehicle_history_612()', 'execute')
  AND NOT pg_catalog.has_function_privilege('anon', 'public.get_pdc_vehicle_history_detail_612(uuid)', 'execute')
  AND (SELECT count(*) FROM public.vehicles WHERE board_purged_at IS NOT NULL) > 0
 AS ok,
 'vehicle history stays read-only and keeps removed vehicles' AS detail
$chk607$,
    true, 377, 'r612');
  EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'vehicle_history_612') INTO ok, detail;
  IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r612: check red: %', detail; END IF;
END $check607$;
