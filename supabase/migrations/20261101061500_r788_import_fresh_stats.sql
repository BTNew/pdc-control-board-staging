-- r788 (F396) / sort 572. Staging cdsmnqxtyyoeoznmbidd only. Craig 1 Nov 2026 06:08 AWST: "i did an upload and its taking ages?"
-- The 06:02 upload (7 parts thanks to r782) failed: part 1's unchanged-part check (part_skip_771) hit the 2 min timeout three times.
-- Cause: the job's 1,142 new job_rows had no planner statistics yet, so the check picked a nested plan over 109k rows.
-- After ANALYZE the same check took 1.4 s. Fix: run_jobs analyzes job_rows and jobs when it starts a queued job. Nothing else changes.
-- Rollback: supabase/rollbacks/20261101061500_r788_import_fresh_stats.down.sql
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';

INSERT INTO pdc_backup_r763_20261031.function_sources(sig, prosrc, md5)
SELECT 'pdc_import_620.run_jobs()@r788pre', p.prosrc, md5(p.prosrc) FROM pg_proc p WHERE p.oid = 'pdc_import_620.run_jobs()'::regprocedure
ON CONFLICT (sig) DO NOTHING;

DO $r788$
DECLARE v_old text; v_new text; v_def text; sig regprocedure := 'pdc_import_620.run_jobs()'::regprocedure;
  a1 text := $a$      UPDATE pdc_import_620.jobs SET status = 'running', started_at = pg_catalog.clock_timestamp(), parts = '[]', step_attempts = 0 WHERE job_id = v_job.job_id;$a$;
  b1 text := $a$      UPDATE pdc_import_620.jobs SET status = 'running', started_at = pg_catalog.clock_timestamp(), parts = '[]', step_attempts = 0 WHERE job_id = v_job.job_id;
      -- r788 (F396): fresh planner statistics for the rows just loaded, so the per-part checks keep a good plan.
      ANALYZE pdc_import_620.job_rows; ANALYZE pdc_import_620.jobs;$a$;
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r788: staging only'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 572 OR fault_id = 'F396' OR added_in = 'r788') THEN RAISE EXCEPTION 'r788: sort 572 or F396 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running', 'loading')) THEN RAISE EXCEPTION 'r788: an import job is running'; END IF;
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  IF position('r787 (F395)' IN v_old) = 0 THEN RAISE EXCEPTION 'r788: run_jobs is not the r787 body'; END IF;
  IF (length(v_old) - length(replace(v_old, a1, ''))) / length(a1) <> 1 THEN RAISE EXCEPTION 'r788: anchor not found once'; END IF;
  v_new := replace(v_old, a1, b1);
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = sig) <> v_new THEN RAISE EXCEPTION 'r788: readback differs'; END IF;
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('import_fresh_stats_788', 'F396', 'Import (r788): run_jobs analyzes job_rows when it starts a job, so per-part checks keep a good plan.',
    $chk$
SELECT strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_import_620.run_jobs()')), 'ANALYZE pdc_import_620.job_rows;') > 0 AS ok,
 'run_jobs analyzes job_rows at job start' AS detail
$chk$, true, 572, 'r788');
END $r788$;
