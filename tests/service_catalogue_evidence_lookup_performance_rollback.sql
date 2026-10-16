-- Run only in the owned disposable restore. Inject the candidate migration at
-- CATALOGUE_LOOKUP_INDEX_CANDIDATE below, after collecting the unindexed baseline.
-- Output contains aggregate counts/timings only; payloads remain in temp tables.
BEGIN;
SET LOCAL statement_timeout='300s';
SET LOCAL lock_timeout='10s';
SET LOCAL TIME ZONE 'Australia/Perth';
DO $guard$ BEGIN
 IF inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet
 OR current_database()<>'pdc_restore_check'
 OR public.pdc_monitor_staging_guard() IS NOT TRUE
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'Owned disposable staging restore required';
 END IF;
 IF to_regclass('public.pdc_service_import_rows_catalogue_lookup_idx') IS NOT NULL THEN
  RAISE EXCEPTION 'Catalogue benchmark requires an unindexed baseline';
 END IF;
END $guard$;

DO $actor$
DECLARE a uuid:=gen_random_uuid(); e text;
BEGIN
 e:='catalogue-performance-'||a||'@example.invalid';
 INSERT INTO auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 VALUES(a,'authenticated','authenticated',e,clock_timestamp(),'{"provider":"email","providers":["email"]}',
  '{"full_name":"TEST VEHICLE performance actor"}',clock_timestamp(),clock_timestamp());
 UPDATE public.pdc_user_roles SET role='operator',active=true,account_status='approved',approved_at=clock_timestamp()
 WHERE auth_user_id=a AND email=e;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',a,'email',e,'role','authenticated')::text,true);
 IF public.workshop_is_planner_operator() IS NOT TRUE THEN RAISE EXCEPTION 'Synthetic actor failed'; END IF;
END $actor$;

CREATE TEMP TABLE perf_catalogue_function_metadata ON COMMIT DROP AS
 SELECT oid,proowner,proacl,md5(pg_get_functiondef(oid)) definition_hash FROM pg_proc
 WHERE oid='pdc_codex_intake_private.service_catalogue_hours_20260917(jsonb)'::regprocedure;
CREATE TEMP TABLE perf_catalogue_inputs ON COMMIT DROP AS
 SELECT operation_id,jsonb_build_object('source_line_id',operation_id,'description',operation_description,
  'department',department,'source_estimated_hours',source_estimated_hours,
  'estimated_hours',effective_estimated_hours,'stage_code','FITTING','hours_provenance',hours_provenance) payload
 FROM public.pdc_pilbara_service_operations
 WHERE coalesce(source_estimated_hours,0)<=0
 AND NOT coalesce(hours_provenance LIKE 'craig_%' AND effective_estimated_hours>0,false)
 ORDER BY operation_id LIMIT 120;
CREATE TEMP TABLE perf_catalogue_results(variant text,operation_id uuid,payload jsonb) ON COMMIT DROP;
CREATE TEMP TABLE perf_catalogue_boards(variant text PRIMARY KEY,payload jsonb,duration_ms numeric) ON COMMIT DROP;
CREATE TEMP TABLE perf_catalogue_timings(variant text,round integer,duration_ms numeric) ON COMMIT DROP;

CREATE FUNCTION pg_temp.measure_catalogue(variant text) RETURNS void LANGUAGE plpgsql AS $measure$
DECLARE started timestamptz; i integer; checksum text;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM perf_catalogue_inputs) THEN RAISE EXCEPTION 'No catalogue fixtures'; END IF;
 INSERT INTO perf_catalogue_results
 SELECT variant,operation_id,pdc_codex_intake_private.service_catalogue_hours_20260917(payload) FROM perf_catalogue_inputs;
 FOR i IN 1..3 LOOP
  started:=clock_timestamp();
  SELECT md5(string_agg(pdc_codex_intake_private.service_catalogue_hours_20260917(payload)::text,'' ORDER BY operation_id))
  INTO checksum FROM perf_catalogue_inputs;
  INSERT INTO perf_catalogue_timings VALUES(variant,i,extract(epoch FROM clock_timestamp()-started)*1000);
 END LOOP;
END $measure$;
CREATE FUNCTION pg_temp.measure_catalogue_board(variant text) RETURNS void LANGUAGE plpgsql AS $measure$
DECLARE started timestamptz:=clock_timestamp(); payload jsonb;
BEGIN
 payload:=public.get_pdc_email_vehicle_board_snapshot();
 IF (payload->>'ok')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'Board snapshot failed'; END IF;
 INSERT INTO perf_catalogue_boards VALUES(variant,payload,extract(epoch FROM clock_timestamp()-started)*1000);
END $measure$;
SELECT pg_temp.measure_catalogue('before');
SELECT pg_temp.measure_catalogue_board('before');

-- CATALOGUE_LOOKUP_INDEX_CANDIDATE

DO $index$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_index WHERE indexrelid=to_regclass('public.pdc_service_import_rows_catalogue_lookup_idx')
  AND indisvalid AND indisready) THEN RAISE EXCEPTION 'Candidate lookup index missing or invalid'; END IF;
 IF EXISTS(SELECT 1 FROM perf_catalogue_function_metadata before JOIN pg_proc after USING(oid)
  WHERE before.proowner IS DISTINCT FROM after.proowner OR before.proacl IS DISTINCT FROM after.proacl
   OR before.definition_hash IS DISTINCT FROM md5(pg_get_functiondef(after.oid))) THEN
  RAISE EXCEPTION 'Index candidate changed the catalogue reader or its permissions';
 END IF;
END $index$;
SELECT pg_temp.measure_catalogue('after');
SELECT pg_temp.measure_catalogue_board('after');
DO $parity$ BEGIN
 IF EXISTS(SELECT 1 FROM perf_catalogue_results before JOIN perf_catalogue_results after USING(operation_id)
  WHERE before.variant='before' AND after.variant='after' AND before.payload IS DISTINCT FROM after.payload) THEN
  RAISE EXCEPTION 'Catalogue helper JSON changed after index';
 END IF;
 -- STABLE now() timestamps are identical in this transaction. The root
 -- generated_at diagnostic alone may use the wall clock and is not business data.
 IF (SELECT payload-'generated_at' FROM perf_catalogue_boards WHERE variant='before') IS DISTINCT FROM
    (SELECT payload-'generated_at' FROM perf_catalogue_boards WHERE variant='after') THEN
  RAISE EXCEPTION 'Full board JSON changed after index';
 END IF;
END $parity$;
SELECT 'Catalogue helper JSON parity' check_name,'PASS' status,count(*) comparisons
 FROM perf_catalogue_inputs;
SELECT 'Whole-board JSON parity' check_name,'PASS' status,
 jsonb_array_length(payload#>'{data,vehicles}') vehicle_count FROM perf_catalogue_boards WHERE variant='after';
SELECT 'Catalogue lookup benchmark' check_name,variant,count(*) rounds,round(avg(duration_ms),2) mean_ms,
 round(min(duration_ms),2) min_ms,round(max(duration_ms),2) max_ms FROM perf_catalogue_timings GROUP BY variant ORDER BY variant;
SELECT 'Whole-board benchmark' check_name,variant,round(duration_ms,2) duration_ms FROM perf_catalogue_boards ORDER BY variant;
SELECT 'Lookup index' check_name,pg_relation_size('public.pdc_service_import_rows_catalogue_lookup_idx') index_bytes;
ROLLBACK;
