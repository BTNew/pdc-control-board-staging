-- r709 (F319). Staging cdsmnqxtyyoeoznmbidd only. Data only, no function changes.
-- Craig 29 Oct 11:23: force the rest of the older open fuel / pit-and-weigh lines to Sublet, including lines on a
-- started or finished station job and lines whose booking cannot be shortened. Same writes as set_vehicle_work_category
-- after its booking checks (line override, required work, Sublet work item, vehicle version, audit), as Craig.
-- Bookings are not changed (no shortening or cancelling). Ticked lines are left.
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';
DO $r709$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time; r record; n int := 0; vids uuid[] := '{}'; old jsonb;
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '06:50' AND time '07:30' OR awst BETWEEN time '17:50' AND time '18:10' THEN RAISE EXCEPTION 'r709: import window'; END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r709: staging only'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r709: pin count'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running')) THEN RAISE EXCEPTION 'r709: an import job is running'; END IF;
  PERFORM set_config('request.jwt.claims', '{"sub":"8a83b715-8d79-4b0e-95b2-02b55da6e8d7","role":"authenticated","email":"craig.watson@broometoyota.com.au"}', true);
  FOR r IN
    SELECT DISTINCT c.vehicle_id, x->>'line_identity' li
    FROM pdc_work_categories_private.qc_operation_lines_cache c
    JOIN public.vehicles v ON v.id = c.vehicle_id AND v.deleted_at IS NULL AND v.lifecycle_state = 'active',
         jsonb_array_elements(c.lines) x
    WHERE pdc_work_categories_private.always_sublet_20261029(x->>'description') IS NOT NULL AND x->>'stage_code' <> 'SUBLET'
      AND NOT coalesce((x->>'completed')::boolean, false)
  LOOP
    SELECT to_jsonb(o) INTO old FROM pdc_work_categories_private.line_overrides o WHERE o.vehicle_id = r.vehicle_id AND o.line_identity = r.li;
    INSERT INTO pdc_work_categories_private.line_overrides(vehicle_id, line_identity, category, updated_by)
    VALUES (r.vehicle_id, r.li, 'SUBLET', auth.uid()) ON CONFLICT (vehicle_id, line_identity) DO UPDATE
    SET category = excluded.category, version = line_overrides.version + 1, updated_by = auth.uid(), updated_at = clock_timestamp()
    WHERE line_overrides.vehicle_id = excluded.vehicle_id;
    INSERT INTO public.audit_events(action, table_name, row_id, vehicle_id, actor_id, actor_email, before_data, after_data, metadata)
    VALUES ('update', 'vehicle_work_category', r.vehicle_id, r.vehicle_id, auth.uid(), public.current_actor_email(), old,
      jsonb_build_object('line_identity', r.li, 'category', 'SUBLET'),
      jsonb_build_object('source', 'r709_force_fuel_pit_sublet', 'source_hours_preserved', true, 'bookings_unchanged', true));
    n := n + 1;
    IF NOT r.vehicle_id = ANY (vids) THEN vids := vids || r.vehicle_id; END IF;
  END LOOP;
  IF n > 0 THEN
    PERFORM public.pdc_auditor_recalculate_required_work_226(vids);
    INSERT INTO public.vehicle_work_items(vehicle_id, work_key, required, completed)
    SELECT u, s.work_key, true, false FROM unnest(vids) u CROSS JOIN public.workshop_stages s WHERE s.code = 'SUBLET'
    ON CONFLICT (vehicle_id, work_key) DO UPDATE SET required = true WHERE NOT public.vehicle_work_items.completed;
    UPDATE public.vehicles SET version = version + 1, updated_at = clock_timestamp(), updated_by = auth.uid() WHERE id = ANY (vids);
  END IF;
  RAISE NOTICE 'r709: % lines on % vehicles forced to Sublet', n, cardinality(vids);
END $r709$;
