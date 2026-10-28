-- r675 (F284) / sort 423. Staging cdsmnqxtyyoeoznmbidd only.
-- set_pdc_qc_operation_completion_379 raised its version conflicts with SQLSTATE 40001 (serialization_failure).
-- PostgREST retries 40001 inside the request, and a stale QC tick sent at 06:43 AWST on 28 Oct has been retried
-- about 1,100 times a second since (set_config / pdc_check_fitter_request counts), loading the database all day.
-- A version conflict is not a transient failure: raise it as PT409 (HTTP 409, never retried). Same messages.
SET LOCAL lock_timeout = '4s';
SET LOCAL statement_timeout = '60s';

DO $r675$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time; v_old text; v_new text; v_def text;
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '06:50' AND time '07:30' OR awst BETWEEN time '17:50' AND time '18:10' THEN RAISE EXCEPTION 'r675: import window'; END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r675: staging only'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r675: pin count'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 423 OR fault_id = 'F284' OR added_in = 'r675' OR check_name = 'qc_conflict_not_retryable_675') THEN RAISE EXCEPTION 'r675: sort 423 or F284 is taken'; END IF;
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = 'public.set_pdc_qc_operation_completion_379(uuid,integer,text,integer,uuid,boolean)'::regprocedure;
  IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE prosrc_md5 = md5(v_old)) THEN RAISE EXCEPTION 'r675: function is pinned'; END IF;
  IF (SELECT count(*) FROM regexp_matches(v_old, 'CONFLICT'' USING errcode=''40001''', 'g')) <> 2 THEN RAISE EXCEPTION 'r675: expected 2 conflict raises'; END IF;
  v_new := replace(v_old, 'CONFLICT'' USING errcode=''40001''', 'CONFLICT'' USING errcode=''PT409''');
  v_def := pg_get_functiondef('public.set_pdc_qc_operation_completion_379(uuid,integer,text,integer,uuid,boolean)'::regprocedure);
  v_def := regexp_replace(v_def, '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('qc_conflict_not_retryable_675', 'F284',
    'QC tick version conflicts are PT409 (never retried by PostgREST), not 40001.',
    $chk$
SELECT strpos(a, 'errcode=''40001''') = 0 AND strpos(a, 'VEHICLE_VERSION_CONFLICT'' USING errcode=''PT409''') > 0
 AS ok, 'QC conflict is PT409' AS detail
FROM (SELECT prosrc a FROM pg_proc WHERE oid = to_regprocedure('public.set_pdc_qc_operation_completion_379(uuid,integer,text,integer,uuid,boolean)')) x
$chk$, true, 423, 'r675');
END $r675$;
