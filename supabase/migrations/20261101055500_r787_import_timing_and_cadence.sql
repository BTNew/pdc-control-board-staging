-- r787 (F395) / sort 571. Staging cdsmnqxtyyoeoznmbidd only. Craig 1 Nov 2026 05:46 AWST: "Let's test it and see how we can make it
-- quicker without sacrificing integrity".
-- Measured on the 31 Oct 11:00 job (rolled-back reruns): preview 0.1-1.6 s and apply about 2 s per part, yet the job took 1000 s with the
-- worker busy 45-60 s of every minute. The steps are slower live than in a quiet rerun, and nothing records how long each one takes.
--   1. run_jobs writes 'ms' on every preview and apply step (parts[i].ms and parts[i].apply.ms), so the next real upload shows where the
--      time goes. No other behaviour changes; every check, lock, sleep and retry stays.
--   2. The worker starts every 10 seconds instead of every minute. The advisory lock already allows only one run, so the extra starts
--      return at once; the gap between one run's 55 s budget and the next start drops from up to 60 s to at most 10 s.
-- Rollback: supabase/rollbacks/20261101055500_r787_import_timing_and_cadence.down.sql
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';

INSERT INTO pdc_backup_r763_20261031.function_sources(sig, prosrc, md5)
SELECT 'pdc_import_620.run_jobs()@r787pre', p.prosrc, md5(p.prosrc) FROM pg_proc p WHERE p.oid = 'pdc_import_620.run_jobs()'::regprocedure
ON CONFLICT (sig) DO NOTHING;

DO $r787$
DECLARE v_old text; v_new text; v_def text; v_job bigint; sig regprocedure := 'pdc_import_620.run_jobs()'::regprocedure;
  a0 text := $a$v_start timestamptz := pg_catalog.clock_timestamp();$a$;
  b0 text := $a$v_start timestamptz := pg_catalog.clock_timestamp(); v_t0 timestamptz; -- r787 (F395): step timing$a$;
  a1 text := $a$v_step := pdc_import_620.apply_part(v_job.job_id, v_i, v_i = v_n - 1);$a$;
  b1 text := $a$v_t0 := pg_catalog.clock_timestamp();
        v_step := pdc_import_620.apply_part(v_job.job_id, v_i, v_i = v_n - 1);
        v_step := v_step || pg_catalog.jsonb_build_object('ms', round(extract(epoch FROM pg_catalog.clock_timestamp() - v_t0) * 1000));$a$;
  a2 text := $a$IF v_step IS NULL THEN v_step := pdc_import_620.preview_part(v_job.job_id, v_i); END IF;$a$;
  b2 text := $a$IF v_step IS NULL THEN
          v_t0 := pg_catalog.clock_timestamp();
          v_step := pdc_import_620.preview_part(v_job.job_id, v_i);
          v_step := v_step || pg_catalog.jsonb_build_object('ms', round(extract(epoch FROM pg_catalog.clock_timestamp() - v_t0) * 1000));
        END IF;$a$;
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r787: staging only'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 571 OR fault_id = 'F395' OR added_in = 'r787') THEN RAISE EXCEPTION 'r787: sort 571 or F395 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running', 'loading')) THEN RAISE EXCEPTION 'r787: an import job is running'; END IF;
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  IF md5(v_old) <> '5ffe3b511dd0884354eb068571defec5' THEN RAISE EXCEPTION 'r787: run_jobs is not the r782 body'; END IF;
  IF (length(v_old) - length(replace(v_old, a0, ''))) / length(a0) <> 1 OR (length(v_old) - length(replace(v_old, a1, ''))) / length(a1) <> 1
     OR (length(v_old) - length(replace(v_old, a2, ''))) / length(a2) <> 1 THEN RAISE EXCEPTION 'r787: anchors not found once'; END IF;
  v_new := replace(replace(replace(v_old, a0, b0), a1, b1), a2, b2);
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = sig) <> v_new THEN RAISE EXCEPTION 'r787: readback differs'; END IF;

  SELECT jobid INTO v_job FROM cron.job WHERE jobname = 'pdc-import-620-worker' AND schedule = '* * * * *';
  IF v_job IS NULL THEN RAISE EXCEPTION 'r787: worker job not found on its one-minute schedule'; END IF;
  PERFORM cron.alter_job(v_job, schedule := '10 seconds');

  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('import_timing_cadence_787', 'F395',
    'Import (r787): every preview/apply step records ms; the worker starts every 10 seconds (one run at a time by advisory lock).',
    $chk$
SELECT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'pdc-import-620-worker' AND active AND schedule = '10 seconds')
   AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_import_620.run_jobs()')), 'r787 (F395)') > 0
   AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_import_620.run_jobs()')), 'pg_try_advisory_lock') > 0
 AS ok, 'step timing recorded; worker every 10 s, single run' AS detail
$chk$, true, 571, 'r787');
END $r787$;
