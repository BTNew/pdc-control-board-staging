-- r789 (F397) / sort 573. Staging cdsmnqxtyyoeoznmbidd only. Craig 1 Nov 2026 06:29 AWST: "yes" (speed up the save step, no checks dropped).
-- The 06:02 upload's save (apply) steps took 13-39 s each while checking took ~3.5 s. A rolled-back replay cannot show why: the apply
-- function recognises a part it already applied and returns in 19 ms, so only a first-time apply does the real work.
-- run_jobs now turns on function timing for each step (track_functions = pl, this transaction only) and stores the 8 slowest
-- functions with the step (parts[i].top and parts[i].apply.top). The next real upload shows exactly which function to speed up.
-- No behaviour change: every lock, check, sleep and retry stays.
-- Rollback: supabase/rollbacks/20261101064000_r789_import_step_profile.down.sql
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';

INSERT INTO pdc_backup_r763_20261031.function_sources(sig, prosrc, md5)
SELECT 'pdc_import_620.run_jobs()@r789pre', p.prosrc, md5(p.prosrc) FROM pg_proc p WHERE p.oid = 'pdc_import_620.run_jobs()'::regprocedure
ON CONFLICT (sig) DO NOTHING;

DO $r789$
DECLARE v_old text; v_new text; v_def text; sig regprocedure := 'pdc_import_620.run_jobs()'::regprocedure;
  a1 text := $a$v_t0 := pg_catalog.clock_timestamp();$a$;
  b1 text := $a$PERFORM pg_catalog.set_config('track_functions', 'pl', true); v_t0 := pg_catalog.clock_timestamp(); -- r789 (F397)$a$;
  a2 text := $a$v_step := v_step || pg_catalog.jsonb_build_object('ms', round(extract(epoch FROM pg_catalog.clock_timestamp() - v_t0) * 1000));$a$;
  b2 text := $a$v_step := v_step || pg_catalog.jsonb_build_object('ms', round(extract(epoch FROM pg_catalog.clock_timestamp() - v_t0) * 1000),
          'top', (SELECT pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('f', s.schemaname || '.' || s.funcname, 'n', s.calls,
                    'self_ms', round(s.self_time), 'total_ms', round(s.total_time)) ORDER BY s.self_time DESC)
                  FROM (SELECT * FROM pg_catalog.pg_stat_xact_user_functions ORDER BY self_time DESC LIMIT 8) s));$a$;
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r789: staging only'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 573 OR fault_id = 'F397' OR added_in = 'r789') THEN RAISE EXCEPTION 'r789: sort 573 or F397 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running', 'loading')) THEN RAISE EXCEPTION 'r789: an import job is running'; END IF;
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  IF md5(v_old) <> '3c9916cfc89c13f67529429f8b0e42f6' THEN RAISE EXCEPTION 'r789: run_jobs is not the r788 body'; END IF;
  IF (length(v_old) - length(replace(v_old, a1, ''))) / length(a1) <> 2 OR (length(v_old) - length(replace(v_old, a2, ''))) / length(a2) <> 2 THEN
    RAISE EXCEPTION 'r789: anchors not found twice'; END IF;
  v_new := replace(replace(v_old, a1, b1), a2, b2);
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = sig) <> v_new THEN RAISE EXCEPTION 'r789: readback differs'; END IF;
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('import_step_profile_789', 'F397', 'Import (r789): each preview/apply step stores its 8 slowest functions (track_functions per step).',
    $chk$
SELECT strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_import_620.run_jobs()')), 'pg_stat_xact_user_functions') > 0
   AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_import_620.run_jobs()')), 'pg_try_advisory_lock') > 0 AS ok,
 'import steps record their slowest functions' AS detail
$chk$, true, 573, 'r789');
END $r789$;
