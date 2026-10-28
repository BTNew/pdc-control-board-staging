-- r670 (F280) / sort 420. Staging cdsmnqxtyyoeoznmbidd only. Production vjdtsswhroyguxyfjdkt is not a target.
-- Craig, 28 Oct 2026 19:24: "I want it fail proof." Kajel's preview job 60856d36 stopped at part 31 because the
-- importer refused the whole part (ambiguous_existing_operation) without naming a line, and the job then failed.
-- Now one bad stock never stops the run:
--   * preview: when a part is refused without conflict rows, each stock in the part is previewed on its own; the
--     stocks that are refused are held for this run (reason = the importer's code) and the rest of the part goes on.
--   * apply: if a part's apply is refused (any data error, including a protected-value check), that part is rolled
--     back, its stocks are held for this run and the job carries on. Lock waits / timeouts still retry the step.
--   * holds found by a run are no longer stored as permanent holds: the next file re-checks them, so a fixed
--     stock imports again by itself. Standing holds (13044312 L7, Perth delivery) and holds added with add_hold stay.
--   * the 29 stocks copied in from Kajel's 12:30 run are switched off for the same reason (they are re-checked).
-- Only pdc_import_620 functions change. Kajel's import functions and pins are untouched. Pins stay 241.
SET LOCAL lock_timeout = '4s';
SET LOCAL statement_timeout = '60s';

DO $guard670$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '06:50' AND time '07:30' OR awst BETWEEN time '17:50' AND time '18:10' THEN RAISE EXCEPTION 'r670: import window'; END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r670: staging only'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r670: pin count'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 420 OR fault_id = 'F280' OR added_in = 'r670' OR check_name = 'import_self_isolating_670') THEN RAISE EXCEPTION 'r670: sort 420 or F280 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running')) THEN RAISE EXCEPTION 'r670: an import job is running'; END IF;
END $guard670$;

UPDATE pdc_import_620.holds SET active = false
WHERE active AND reason = 'carried_from_kajel_20261028:preview_or_apply_hold';

-- Holds for this run only (the job's own rows and its receipt). Permanent holds come from add_hold / standing holds.
CREATE OR REPLACE FUNCTION pdc_import_620.hold_stocks(p_job uuid, p_part integer, p_stocks text[], p_reason text)
RETURNS jsonb LANGUAGE plpgsql SET search_path = pg_catalog, public AS $fn$
BEGIN
  UPDATE pdc_import_620.jobs j SET holds = j.holds || (SELECT coalesce(jsonb_agg(jsonb_build_object('stock', s, 'part', p_part + 1, 'reason', p_reason,
      'lines', (SELECT count(*) FROM pdc_import_620.job_rows r WHERE r.job_id = p_job AND r.part = p_part AND r.stock_number = s AND r.held_reason IS NULL))), '[]')
    FROM unnest(p_stocks) s)
  WHERE j.job_id = p_job;
  UPDATE pdc_import_620.job_rows SET held_reason = p_reason
  WHERE job_id = p_job AND part = p_part AND stock_number = ANY (p_stocks) AND held_reason IS NULL;
  RETURN pdc_import_620.part_rows(p_job, p_part);
END $fn$;

-- Rows of one stock in one partition, still to be sent.
CREATE FUNCTION pdc_import_620.stock_rows(p_job uuid, p_part integer, p_stock text) RETURNS jsonb LANGUAGE sql STABLE SET search_path = pg_catalog, public AS $fn$
  SELECT coalesce(jsonb_agg(r.row ORDER BY r.ord), '[]'::jsonb) FROM pdc_import_620.job_rows r
  WHERE r.job_id = p_job AND r.part = p_part AND r.stock_number = p_stock AND r.held_reason IS NULL
$fn$;

CREATE OR REPLACE FUNCTION pdc_import_620.preview_part(p_job uuid, p_part integer)
RETURNS jsonb LANGUAGE plpgsql SET search_path = pg_catalog, public AS $fn$
DECLARE v_job pdc_import_620.jobs; v_rows jsonb; v_result jsonb; v_one jsonb; v_stocks text[]; v_try integer := 0; v_s text; v_found integer;
BEGIN
  PERFORM set_config('lock_timeout', '20s', true); PERFORM set_config('statement_timeout', '600s', true);
  PERFORM pdc_import_620.require_management();
  IF md5((SELECT prosrc FROM pg_proc WHERE oid = 'public.pdc_pilbara_service_preview_v1(jsonb,text,text)'::regprocedure)) <> 'ea9a62537a146f05a01e866c636d367b' THEN RAISE EXCEPTION 'preview_contract_changed'; END IF;
  IF md5((SELECT prosrc FROM pg_proc WHERE oid = 'pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)'::regprocedure)) <> '9be0883b1a555f48f3c1ba9fa111c891' THEN RAISE EXCEPTION 'row_validator_contract_changed'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('workshop-clock-cascade-20260911', 0));
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation', 0));
  LOCK TABLE public.vehicles, public.navision_backend_records IN SHARE ROW EXCLUSIVE MODE;
  LOOP
    v_try := v_try + 1;
    SELECT * INTO STRICT v_job FROM pdc_import_620.jobs WHERE job_id = p_job;
    v_rows := pdc_import_620.part_rows(p_job, p_part);
    IF jsonb_array_length(v_rows) = 0 THEN RETURN jsonb_build_object('part', p_part + 1, 'rows', 0, 'skipped', 'all_rows_held'); END IF;
    v_result := pdc_import_620.preview_rows(v_job, p_part + 1, v_rows);
    IF v_result->>'ok' = 'true' AND v_result->>'apply_allowed' = 'true' AND coalesce((v_result->'operations'->>'conflict')::integer, 0) = 0 THEN
      RETURN jsonb_build_object('part', p_part + 1, 'rows', jsonb_array_length(v_rows), 'source_hash', v_result->>'source_hash_620',
        'preview_batch_id', v_result->>'preview_batch_id', 'operations', v_result->'operations', 'tries', v_try);
    END IF;
    IF v_try >= 12 THEN RAISE EXCEPTION 'preview_not_allowed part % after 12 tries %', p_part + 1, left(v_result::text, 1500); END IF;
    SELECT array_agg(DISTINCT r.stock_number) INTO v_stocks FROM public.pdc_pilbara_service_import_rows r
    WHERE r.batch_id = (v_result->>'preview_batch_id')::uuid AND r.decision = 'conflict';
    IF v_stocks IS NOT NULL THEN
      PERFORM pdc_import_620.hold_stocks(p_job, p_part, v_stocks, 'conflict:' || coalesce((SELECT string_agg(DISTINCT r.reason, ',') FROM public.pdc_pilbara_service_import_rows r
        WHERE r.batch_id = (v_result->>'preview_batch_id')::uuid AND r.decision = 'conflict'), 'conflict'));
      CONTINUE;
    END IF;
    -- r670 (F280): refused without naming a line. Preview each stock on its own and hold the ones that are refused.
    v_found := 0;
    FOR v_s IN SELECT DISTINCT stock_number FROM pdc_import_620.job_rows WHERE job_id = p_job AND part = p_part AND held_reason IS NULL ORDER BY 1 LOOP
      v_one := pdc_import_620.preview_rows(v_job, p_part + 1, pdc_import_620.stock_rows(p_job, p_part, v_s));
      IF NOT (v_one->>'ok' = 'true' AND v_one->>'apply_allowed' = 'true' AND coalesce((v_one->'operations'->>'conflict')::integer, 0) = 0) THEN
        PERFORM pdc_import_620.hold_stocks(p_job, p_part, ARRAY[v_s], 'refused:' || coalesce(v_one->>'code', v_one->>'error', 'preview_not_allowed'));
        v_found := v_found + 1;
      END IF;
    END LOOP;
    IF v_found = 0 THEN
      -- Every stock passes alone but the part is refused together: send each stock as its own part is not possible here,
      -- so hold the part for this run rather than stop the job.
      SELECT array_agg(DISTINCT stock_number) INTO v_stocks FROM pdc_import_620.job_rows WHERE job_id = p_job AND part = p_part AND held_reason IS NULL;
      PERFORM pdc_import_620.hold_stocks(p_job, p_part, v_stocks, 'refused_together:' || coalesce(v_result->>'code', 'preview_not_allowed'));
    END IF;
  END LOOP;
END $fn$;

-- apply_part: a refused part is rolled back and held for this run; the job goes on. Edited in place.
DO $edit670$
DECLARE v_old text; v_new text; v_def text;
  c_handler text := E'    EXCEPTION WHEN raise_exception THEN\n      IF SQLERRM = ''pdc620_archive_gate'' THEN\n        RETURN jsonb_build_object(''part'', p_part + 1, ''held'', true, ''reason'', format(''sanity gate: would archive %s vehicles (more than 15); this partition was rolled back'', v_archived));\n      ELSIF SQLERRM <> ''pdc620_staff_hold'' THEN\n        RAISE;\n      END IF;\n    END;';
  c_new text := E'    EXCEPTION WHEN OTHERS THEN\n      IF SQLERRM = ''pdc620_archive_gate'' THEN\n        RETURN jsonb_build_object(''part'', p_part + 1, ''held'', true, ''reason'', format(''sanity gate: would archive %s vehicles (more than 15); this partition was rolled back'', v_archived));\n      ELSIF SQLERRM = ''pdc620_staff_hold'' THEN\n        NULL;\n      ELSIF SQLSTATE IN (''55P03'', ''57014'', ''40P01'', ''40001'') OR SQLERRM IN (''unexpected_importer_state'', ''importer_restore_failed'') THEN\n        RAISE;  -- lock wait, timeout, deadlock, importer state: the worker retries the step or stops\n      ELSE\n        -- r670 (F280): this part is refused (rolled back). Hold its stocks for this run and carry on.\n        v_stocks := ARRAY(SELECT DISTINCT stock_number FROM pdc_import_620.job_rows WHERE job_id = p_job AND part = p_part AND held_reason IS NULL);\n        PERFORM pdc_import_620.hold_stocks(p_job, p_part, v_stocks, ''apply_refused:'' || left(SQLERRM, 200));\n        RETURN jsonb_build_object(''part'', p_part + 1, ''ok'', false, ''part_held'', true, ''reason'', left(SQLERRM, 500), ''stocks'', to_jsonb(v_stocks));\n      END IF;\n    END;';
BEGIN
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = 'pdc_import_620.apply_part(uuid,integer,boolean)'::regprocedure;
  v_old := replace(v_old, E'\r\n', E'\n');
  IF (length(v_old) - length(replace(v_old, c_handler, ''))) / length(c_handler) <> 1 THEN RAISE EXCEPTION 'r670: apply handler not found once'; END IF;
  v_new := replace(v_old, c_handler, c_new);
  v_def := pg_get_functiondef('pdc_import_620.apply_part(uuid,integer,boolean)'::regprocedure);
  v_def := regexp_replace(v_def, '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
END $edit670$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA pdc_import_620 FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON PROCEDURE pdc_import_620.run_jobs() FROM PUBLIC, anon, authenticated, service_role;

DO $check670$
DECLARE ok boolean; detail text;
BEGIN
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('import_self_isolating_670', 'F280',
    'One-step import isolates refused stocks at preview and refused parts at apply instead of failing the run; run holds are not stored as permanent holds.',
    $chk670$
SELECT strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_import_620.preview_part(uuid,integer)')), 'stock_rows(p_job, p_part, v_s)') > 0
  AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_import_620.apply_part(uuid,integer,boolean)')), 'apply_refused:') > 0
  AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_import_620.hold_stocks(uuid,integer,text[],text)')), 'INSERT INTO pdc_import_620.holds') = 0
  AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_import_620.apply_part(uuid,integer,boolean)')), 'public.pdc_pilbara_service_apply_v1(') > 0
 AS ok, 'import isolates bad stocks and carries on' AS detail
$chk670$, true, 420, 'r670');
  EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'import_self_isolating_670') INTO ok, detail;
  IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r670: check red: %', detail; END IF;
END $check670$;
