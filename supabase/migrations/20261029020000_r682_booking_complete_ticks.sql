-- r682 (F292) / sort 427. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 29 Oct 06:32 (key 456, 13017852): a controller started and completed the Electrical booking, but the 18
-- Electrical items stayed unticked because the fitter had no iPad. When a workshop controller (operator or
-- administrator) completes a booking, every open item of that station is now ticked, except items marked Later
-- (r627), which stay outstanding. Fitter iPad completions are unchanged. A tick that fails never blocks the completion.
-- Backfill: the 13017852 Electrical booking completed at 06:31 is ticked as Craig.
SET LOCAL lock_timeout = '4s';
SET LOCAL statement_timeout = '60s';

CREATE TEMP TABLE r682_green ON COMMIT DROP AS SELECT check_name, check_sql FROM pdc_ops.regression_checks WHERE false;
DO $pre682$
DECLARE r record; ok boolean; detail text;
BEGIN
  FOR r IN SELECT check_name, check_sql FROM pdc_ops.regression_checks WHERE enabled AND check_sql ~* 'pg_trigger' AND check_sql ~* 'workshop_bookings' LOOP
    BEGIN EXECUTE r.check_sql INTO ok, detail; EXCEPTION WHEN OTHERS THEN ok := false; END;
    IF ok IS TRUE THEN INSERT INTO r682_green VALUES (r.check_name, r.check_sql); END IF;
  END LOOP;
END $pre682$;

DO $guard682$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '06:50' AND time '07:30' OR awst BETWEEN time '17:50' AND time '18:10' THEN RAISE EXCEPTION 'r682: import window'; END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r682: staging only'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r682: pin count'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 427 OR fault_id = 'F292' OR added_in = 'r682' OR check_name = 'booking_complete_ticks_682') THEN RAISE EXCEPTION 'r682: sort 427 or F292 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'zz_pdc_booking_complete_ticks_682') THEN RAISE EXCEPTION 'r682: already applied'; END IF;
END $guard682$;

CREATE FUNCTION pdc_ops.booking_complete_ticks_682() RETURNS trigger LANGUAGE plpgsql SET search_path = pg_catalog, public AS $fn$
DECLARE v_stage text; v_line jsonb;
BEGIN
  IF coalesce(public.current_pdc_user_role()::text, '') NOT IN ('operator', 'administrator') THEN RETURN NULL; END IF;
  SELECT s.code INTO v_stage FROM public.workshop_stages s WHERE s.id = NEW.stage_id;
  FOR v_line IN
    SELECT l FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(NEW.vehicle_id)) l
    WHERE coalesce((l->>'active')::boolean, true) AND NOT coalesce((l->>'rejected')::boolean, false)
      AND NOT coalesce((l->>'completed')::boolean, false)
      AND l->>'line_identity' ~* '^(source|manual):[0-9a-f-]{36}$'
      AND CASE WHEN NEW.work_category = 'BUS_WHOLE_JOB' THEN coalesce(NEW.work_category_scope ? (l->>'line_identity'), false)
               ELSE l->>'stage_code' = v_stage AND (NEW.work_category IS NULL OR l->>'work_category' = NEW.work_category) END
      AND NOT EXISTS (SELECT 1 FROM public.pdc_line_later_627 lt WHERE lt.vehicle_id = NEW.vehicle_id AND lt.line_identity = l->>'line_identity')
  LOOP
    BEGIN
      PERFORM public.set_panel_line_completion_565(NEW.vehicle_id, v_line->>'line_identity', true);
    EXCEPTION WHEN OTHERS THEN NULL; -- a tick never blocks the completion
    END;
  END LOOP;
  RETURN NULL;
END $fn$;
REVOKE ALL ON FUNCTION pdc_ops.booking_complete_ticks_682() FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER zz_pdc_booking_complete_ticks_682 AFTER UPDATE OF status ON public.workshop_bookings
  FOR EACH ROW WHEN (NEW.status = 'completed' AND OLD.status IS DISTINCT FROM 'completed' AND NEW.deleted_at IS NULL)
  EXECUTE FUNCTION pdc_ops.booking_complete_ticks_682();

-- Backfill 13017852 (key 456): its Electrical booking was completed by a controller at 06:31 AWST.
DO $backfill682$
DECLARE b record; v_line jsonb; n integer := 0; v_stage text;
BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"8a83b715-8d79-4b0e-95b2-02b55da6e8d7","role":"authenticated","email":"craig.watson@broometoyota.com.au"}', true);
  FOR b IN SELECT wb.* FROM public.workshop_bookings wb JOIN public.vehicles v ON v.id = wb.vehicle_id
           WHERE v.stock_number = '13017852' AND wb.status = 'completed' AND wb.deleted_at IS NULL LOOP
    SELECT s.code INTO v_stage FROM public.workshop_stages s WHERE s.id = b.stage_id;
    FOR v_line IN
      SELECT l FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(b.vehicle_id)) l
      WHERE coalesce((l->>'active')::boolean, true) AND NOT coalesce((l->>'rejected')::boolean, false)
        AND NOT coalesce((l->>'completed')::boolean, false) AND l->>'line_identity' ~* '^(source|manual):[0-9a-f-]{36}$'
        AND l->>'stage_code' = v_stage AND (b.work_category IS NULL OR l->>'work_category' = b.work_category)
        AND NOT EXISTS (SELECT 1 FROM public.pdc_line_later_627 lt WHERE lt.vehicle_id = b.vehicle_id AND lt.line_identity = l->>'line_identity')
    LOOP
      IF public.set_panel_line_completion_565(b.vehicle_id, v_line->>'line_identity', true)->>'ok' = 'true' THEN n := n + 1; END IF;
    END LOOP;
  END LOOP;
  PERFORM set_config('request.jwt.claims', '', true);
  RAISE NOTICE 'r682 backfill ticked % lines on 13017852', n;
END $backfill682$;

DO $check682$
DECLARE r record; ok boolean; detail text;
BEGIN
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('booking_complete_ticks_682', 'F292',
    'A controller completing a booking ticks every open item of that station except Later items.',
    $chk$
SELECT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'zz_pdc_booking_complete_ticks_682' AND tgrelid = 'public.workshop_bookings'::regclass AND tgenabled <> 'D')
  AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_ops.booking_complete_ticks_682()')), 'pdc_line_later_627') > 0
  AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_ops.booking_complete_ticks_682()')), 'set_panel_line_completion_565') > 0
 AS ok, 'controller complete ticks the station' AS detail
$chk$, true, 427, 'r682');
  FOR r IN SELECT check_name, check_sql FROM r682_green UNION ALL SELECT check_name, check_sql FROM pdc_ops.regression_checks WHERE check_name = 'booking_complete_ticks_682' LOOP
    EXECUTE r.check_sql INTO ok, detail;
    IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r682: check % red: %', r.check_name, detail; END IF;
  END LOOP;
END $check682$;
