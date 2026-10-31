-- r784 (F392) / sort 570. Staging cdsmnqxtyyoeoznmbidd only. Health check 31 Oct 2026 (Craig 12:25: "make sure everything is running
-- as quick as possible, smooth"). Measured: board snapshot 6.5 s and location snapshot 5.5 s on every load today, because:
--   1. The board prewarm (every 3 s, keeps the 15 s cache warm) runs Monday to Friday only, so on a Saturday every page load computes.
--      Now Monday to Saturday, same hours (05:30-18:30 AWST).
--   2. The location snapshot works out the Dept 138 station twice for every Pilbara service line (operation_station is ~3 ms a call,
--      about 0.8 s a load). The dept138 lateral now reuses the station the service line already carries; any line without one is
--      worked out exactly as before. The migration proves the operation_lines output is identical before it keeps the change.
-- Every regression check pinning the compute_554 md5 is moved to the new body.
-- Rollback: supabase/rollbacks/20261031130000_r784_board_speed_saturday_prewarm.down.sql
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';

INSERT INTO pdc_backup_r763_20261031.function_sources(sig, prosrc, md5)
SELECT 'pdc_ops.vehicle_location_snapshot_compute_554()@r784pre', p.prosrc, md5(p.prosrc) FROM pg_proc p WHERE p.oid = 'pdc_ops.vehicle_location_snapshot_compute_554()'::regprocedure
ON CONFLICT (sig) DO NOTHING;

DO $r784$
DECLARE v_old text; v_new text; v_def text; v_oldmd5 text; v_newmd5 text; before_j jsonb; after_j jsonb; n_diff integer; n_rows integer;
  sig regprocedure := 'pdc_ops.vehicle_location_snapshot_compute_554()'::regprocedure; v_job bigint;
  a1 text := $a$     SELECT coalesce(pdc_bus_private.operation_station(nullif(op->>'operation_line_id','')::uuid),public.pdc_department138_station_20260917(op->>'description')) AS station_code$a$;
  b1 text := $a$     -- r784 (F392): a Pilbara service line already carries its Dept 138 station; reuse it instead of a second operation_station call.
     SELECT CASE WHEN op->>'source_uid' LIKE 'pilbara_service_open_jobcards_v1:%' AND nullif(op->>'classification','') IS NOT NULL
                  AND op->>'classification' = upper(op->>'classification') AND op->>'classification' <> 'REVIEW'
       THEN op->>'classification'
       ELSE coalesce(pdc_bus_private.operation_station(nullif(op->>'operation_line_id','')::uuid),public.pdc_department138_station_20260917(op->>'description')) END AS station_code$a$;
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r784: staging only'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 570 OR fault_id = 'F392' OR added_in = 'r784') THEN RAISE EXCEPTION 'r784: sort 570 or F392 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running', 'loading')) THEN RAISE EXCEPTION 'r784: an import job is running'; END IF;

  -- 1. Saturday prewarm.
  SELECT jobid INTO v_job FROM cron.job WHERE jobname = 'staging-vehicle-board-prewarm-729';
  IF v_job IS NULL THEN RAISE EXCEPTION 'r784: prewarm job not found'; END IF;
  IF (SELECT position($q$extract(isodow FROM clock_timestamp() AT TIME ZONE 'Australia/Perth') < 6$q$ IN command) FROM cron.job WHERE jobid = v_job) = 0 THEN RAISE EXCEPTION 'r784: prewarm weekday rule not found'; END IF;
  PERFORM cron.alter_job(v_job, command := (SELECT replace(command, $q$extract(isodow FROM clock_timestamp() AT TIME ZONE 'Australia/Perth') < 6$q$,
                                                                   $q$extract(isodow FROM clock_timestamp() AT TIME ZONE 'Australia/Perth') < 7$q$) FROM cron.job WHERE jobid = v_job));
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, $q$extract(isodow FROM clock_timestamp() AT TIME ZONE 'Australia/Perth') < 6$q$,
                                                                       $q$extract(isodow FROM clock_timestamp() AT TIME ZONE 'Australia/Perth') < 7$q$)
  WHERE check_name = 'board_prewarm_729';

  -- 2. One Dept 138 station call per service line, proven identical.
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  v_oldmd5 := md5(v_old);
  IF position('r780 (F384)' IN v_old) = 0 THEN RAISE EXCEPTION 'r784: compute_554 is not the r780 body'; END IF;
  IF (length(v_old) - length(replace(v_old, a1, ''))) / length(a1) <> 1 THEN RAISE EXCEPTION 'r784: anchor not found once'; END IF;
  PERFORM set_config('request.jwt.claims', jsonb_build_object('role', 'authenticated', 'email', 'craig.watson@broometoyota.com.au', 'sub', '8a83b715-8d79-4b0e-95b2-02b55da6e8d7')::text, true);
  before_j := pdc_ops.vehicle_location_snapshot_compute_554();
  v_new := replace(v_old, a1, b1);
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = sig) <> v_new THEN RAISE EXCEPTION 'r784: readback differs'; END IF;
  after_j := pdc_ops.vehicle_location_snapshot_compute_554();
  SELECT count(*), count(*) FILTER (WHERE a.v->'operation_lines' IS DISTINCT FROM b.v->'operation_lines') INTO n_rows, n_diff
  FROM jsonb_array_elements(before_j#>'{data,vehicles}') a(v) FULL JOIN jsonb_array_elements(after_j#>'{data,vehicles}') b(v) ON a.v->>'id' = b.v->>'id';
  IF n_rows = 0 OR n_diff <> 0 THEN RAISE EXCEPTION 'r784: operation_lines differ on % of % vehicles', n_diff, n_rows; END IF;
  PERFORM set_config('request.jwt.claims', '', true);
  v_newmd5 := md5(v_new);
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, v_oldmd5, v_newmd5) WHERE position(v_oldmd5 IN check_sql) > 0;

  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('board_speed_784', 'F392',
    'Board speed (r784): prewarm runs Monday to Saturday; the location snapshot works out the Dept 138 station once per Pilbara service line.',
    $chk$
SELECT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'staging-vehicle-board-prewarm-729' AND active
                 AND position($$AT TIME ZONE 'Australia/Perth') < 7$$ IN command) > 0)
   AND position('r784 (F392)' IN (SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_ops.vehicle_location_snapshot_compute_554()'))) > 0
 AS ok, 'Saturday prewarm and single Dept 138 station call' AS detail
$chk$, true, 570, 'r784');
  RAISE NOTICE 'r784: % vehicles, operation_lines identical; compute md5 % -> %', n_rows, v_oldmd5, v_newmd5;
END $r784$;
