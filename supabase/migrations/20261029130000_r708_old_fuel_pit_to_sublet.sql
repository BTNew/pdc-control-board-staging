-- r708 (F318). Staging cdsmnqxtyyoeoznmbidd only. Data only, no function changes.
-- Craig 29 Oct 11:16: move the older fuel / pit-and-weigh / M1 tint lines (created before the 09:00 always-Sublet rule)
-- to Sublet. Each open line goes through set_vehicle_work_category (the side panel's Move to), as Craig, so it keeps the
-- normal guards: a line whose station job has started or finished, or whose booking cannot be shortened, is not moved.
-- Ticked lines are left. Kajel's import functions and pins are untouched.
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';
DO $r708$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time; r record; res jsonb; ok int := 0; skipped int := 0;
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '06:50' AND time '07:30' OR awst BETWEEN time '17:50' AND time '18:10' THEN RAISE EXCEPTION 'r708: import window'; END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r708: staging only'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r708: pin count'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running')) THEN RAISE EXCEPTION 'r708: an import job is running'; END IF;
  PERFORM set_config('request.jwt.claims', '{"sub":"8a83b715-8d79-4b0e-95b2-02b55da6e8d7","role":"authenticated","email":"craig.watson@broometoyota.com.au"}', true);
  FOR r IN
    SELECT DISTINCT c.vehicle_id, x->>'line_identity' li
    FROM pdc_work_categories_private.qc_operation_lines_cache c
    JOIN public.vehicles v ON v.id = c.vehicle_id AND v.deleted_at IS NULL AND v.lifecycle_state = 'active',
         jsonb_array_elements(c.lines) x
    WHERE pdc_work_categories_private.always_sublet_20261029(x->>'description') IS NOT NULL AND x->>'stage_code' <> 'SUBLET'
      AND NOT coalesce((x->>'completed')::boolean, false)
  LOOP
    BEGIN
      res := public.set_vehicle_work_category(r.vehicle_id, (SELECT version FROM public.vehicles WHERE id = r.vehicle_id), r.li, 'SUBLET',
               coalesce((SELECT o.version FROM pdc_work_categories_private.line_overrides o WHERE o.vehicle_id = r.vehicle_id AND o.line_identity = r.li), 0), true, NULL);
    EXCEPTION WHEN OTHERS THEN res := jsonb_build_object('ok', false);
    END;
    IF res->>'ok' = 'true' THEN ok := ok + 1; ELSE skipped := skipped + 1; END IF;
  END LOOP;
  RAISE NOTICE 'r708: moved % lines to Sublet, % left (started/finished job or booking cannot shorten)', ok, skipped;
END $r708$;
