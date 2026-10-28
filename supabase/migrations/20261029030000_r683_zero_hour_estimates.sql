-- r683 (F293) / sort 428. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 29 Oct 06:57: no job on the board at 0 hours (a 0-hour station cannot be booked: "Estimated hours are
-- required before this vehicle can be scheduled into a bay"). Every open Fitting, Electrical, Fab and Tyres line
-- at 0 or no hours gets an estimate: the median hours of the same job wording on other vehicles, else the station
-- default (Tyres 0.5, Fitting 0.5, Electrical 0.5, Fab 1.0). Sublet (supplier work) and job card notes stay at 0.
-- Saved through the normal hours save (save_vehicle_workshop_line_hours_batch_768, as Craig), then marked
-- zero_hour_estimate_683 so the board shows "Estimate". A pg_cron job repeats it every 10 minutes for new imports,
-- outside the import windows and never while an import job is running. A person's own hours (manual) are never touched.
SET LOCAL lock_timeout = '4s';
SET LOCAL statement_timeout = '120s';

DO $guard683$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '06:50' AND time '07:30' OR awst BETWEEN time '17:50' AND time '18:10' THEN RAISE EXCEPTION 'r683: import window'; END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r683: staging only'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r683: pin count'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 428 OR fault_id = 'F293' OR added_in = 'r683' OR check_name = 'zero_hour_estimates_683') THEN RAISE EXCEPTION 'r683: sort 428 or F293 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running')) THEN RAISE EXCEPTION 'r683: an import job is running'; END IF;
  IF pg_get_constraintdef((SELECT oid FROM pg_constraint WHERE conname = 'pdc_auditor_adjustment_origin_check' AND conrelid = 'public.vehicle_workshop_line_adjustments'::regclass))
     <> 'CHECK (((correction_origin IS NULL) OR (correction_origin = ANY (ARRAY[''ai_auditor''::text, ''ai_auditor_rolled_back''::text, ''manual_operator''::text, ''manual_operator_unknown''::text, ''craig_standard_pd_1_5''::text, ''job_card_source_correction''::text]))))'
  THEN RAISE EXCEPTION 'r683: origin check is not the expected text'; END IF;
END $guard683$;

ALTER TABLE public.vehicle_workshop_line_adjustments DROP CONSTRAINT pdc_auditor_adjustment_origin_check;
ALTER TABLE public.vehicle_workshop_line_adjustments ADD CONSTRAINT pdc_auditor_adjustment_origin_check
  CHECK (correction_origin IS NULL OR correction_origin = ANY (ARRAY['ai_auditor'::text, 'ai_auditor_rolled_back'::text, 'manual_operator'::text, 'manual_operator_unknown'::text, 'craig_standard_pd_1_5'::text, 'job_card_source_correction'::text, 'zero_hour_estimate_683'::text]));

CREATE FUNCTION pdc_ops.zero_hour_estimate_683(p_max_vehicles integer DEFAULT 40)
RETURNS jsonb LANGUAGE plpgsql SET search_path = pg_catalog, public AS $fn$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
  v record; r jsonb; v_rows jsonb; v_jc text; v_ok integer := 0; v_lines integer := 0; v_failed jsonb := '[]'::jsonb; v_chg jsonb;
BEGIN
  IF awst BETWEEN time '12:10' AND time '12:50' OR awst BETWEEN time '06:45' AND time '07:35' OR awst BETWEEN time '17:45' AND time '18:15'
     OR EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running')) THEN
    RETURN jsonb_build_object('ok', true, 'skipped', 'import_window_or_job');
  END IF;
  IF NOT pg_try_advisory_xact_lock(hashtextextended('pdc:zero-hour-estimate-683', 0)) THEN RETURN jsonb_build_object('ok', true, 'skipped', 'already_running'); END IF;
  PERFORM set_config('request.jwt.claims', '{"sub":"8a83b715-8d79-4b0e-95b2-02b55da6e8d7","role":"authenticated","email":"craig.watson@broometoyota.com.au"}', true);
  CREATE TEMP TABLE IF NOT EXISTS z683_hist ON COMMIT DROP AS
    SELECT lower(btrim(x->>'description')) d, round((percentile_cont(0.5) WITHIN GROUP (ORDER BY (x->>'estimated_hours')::numeric))::numeric, 2) med
    FROM pdc_work_categories_private.qc_operation_lines_cache c, jsonb_array_elements(c.lines) x
    WHERE jsonb_typeof(x->'estimated_hours') = 'number' AND (x->>'estimated_hours')::numeric > 0 GROUP BY 1;
  FOR v IN
    SELECT c.vehicle_id, vv.stock_number, vv.version
    FROM pdc_work_categories_private.qc_operation_lines_cache c JOIN public.vehicles vv ON vv.id = c.vehicle_id
    WHERE vv.deleted_at IS NULL AND vv.lifecycle_state = 'active'
      AND EXISTS (SELECT 1 FROM jsonb_array_elements(c.lines) x
        WHERE coalesce((x->>'active')::boolean, true) AND NOT coalesce((x->>'completed')::boolean, false) AND NOT coalesce((x->>'rejected')::boolean, false)
          AND x->>'stage_code' IN ('FITTING', 'ELECTRICAL', 'FABRICATION', 'TYRE') AND x->>'line_identity' ~* '^source:[0-9a-f-]{36}$'
          AND coalesce((x->>'estimated_hours')::numeric, 0) = 0
          AND NOT EXISTS (SELECT 1 FROM public.vehicle_workshop_line_adjustments a WHERE a.vehicle_id = c.vehicle_id AND a.line_key = x->>'line_identity'
                          AND a.active AND a.correction_origin IN ('manual_operator', 'manual_operator_unknown')))
    ORDER BY vv.stock_number LIMIT greatest(1, least(p_max_vehicles, 200))
  LOOP
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'operation_line_id', lower(substr(x->>'line_identity', 8)), 'line_key', x->>'line_identity',
             'work_key', s.work_key, 'stage_code', x->>'stage_code',
             'expected_line_version', coalesce(a.version, 0), 'adjustment_id', a.adjustment_id,
             'estimated_hours', coalesce(h.med, CASE x->>'stage_code' WHEN 'FABRICATION' THEN 1.0 ELSE 0.5 END))), '[]'::jsonb),
           min(x->>'job_card_number')
    INTO v_rows, v_jc
    FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v.vehicle_id)) x
    JOIN public.workshop_stages s ON s.code = x->>'stage_code'
    LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id = v.vehicle_id AND a.line_key = x->>'line_identity'
    LEFT JOIN z683_hist h ON h.d = lower(btrim(x->>'description'))
    WHERE coalesce((x->>'active')::boolean, true) AND NOT coalesce((x->>'completed')::boolean, false) AND NOT coalesce((x->>'rejected')::boolean, false)
      AND x->>'stage_code' IN ('FITTING', 'ELECTRICAL', 'FABRICATION', 'TYRE') AND x->>'line_identity' ~* '^source:[0-9a-f-]{36}$'
      AND coalesce((x->>'estimated_hours')::numeric, 0) = 0
      AND NOT (a.active IS TRUE AND a.correction_origin IN ('manual_operator', 'manual_operator_unknown'));
    IF jsonb_array_length(v_rows) = 0 OR v_jc IS NULL THEN CONTINUE; END IF;
    BEGIN
      r := public.save_vehicle_workshop_line_hours_batch_768(v.vehicle_id, v.stock_number, v_jc,
             (SELECT version FROM public.vehicles WHERE id = v.vehicle_id), v_rows, gen_random_uuid());
      IF coalesce((r->>'ok')::boolean, false) THEN
        FOR v_chg IN SELECT e FROM jsonb_array_elements(coalesce(r->'changes', '[]'::jsonb)) e LOOP
          UPDATE public.vehicle_workshop_line_adjustments SET correction_origin = 'zero_hour_estimate_683'
          WHERE adjustment_id = (v_chg#>>'{after,adjustment_id}')::uuid AND vehicle_id = v.vehicle_id;
        END LOOP;
        v_ok := v_ok + 1; v_lines := v_lines + jsonb_array_length(v_rows);
      ELSE
        v_failed := v_failed || jsonb_build_object('stock', v.stock_number, 'code', r->>'code');
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_failed := v_failed || jsonb_build_object('stock', v.stock_number, 'error', left(SQLERRM, 200));
    END;
  END LOOP;
  RETURN jsonb_build_object('ok', true, 'vehicles', v_ok, 'lines', v_lines, 'failed', v_failed);
END $fn$;
REVOKE ALL ON FUNCTION pdc_ops.zero_hour_estimate_683(integer) FROM PUBLIC, anon, authenticated, service_role;

SELECT cron.schedule('pdc_zero_hour_estimate_683', '*/10 * * * *', 'SELECT pdc_ops.zero_hour_estimate_683(40)');

DO $check683$
DECLARE ok boolean; detail text;
BEGIN
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('zero_hour_estimates_683', 'F293',
    'Open Fitting/Electrical/Fab/Tyres lines with 0 hours get an estimate every 10 minutes (Sublet stays 0).',
    $chk$
SELECT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'pdc_zero_hour_estimate_683' AND active)
  AND to_regprocedure('pdc_ops.zero_hour_estimate_683(integer)') IS NOT NULL
  AND strpos(pg_get_constraintdef((SELECT oid FROM pg_constraint WHERE conname = 'pdc_auditor_adjustment_origin_check')), 'zero_hour_estimate_683') > 0
 AS ok, 'zero hour estimates scheduled' AS detail
$chk$, true, 428, 'r683');
  EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'zero_hour_estimates_683') INTO ok, detail;
  IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r683: check red: %', detail; END IF;
END $check683$;
