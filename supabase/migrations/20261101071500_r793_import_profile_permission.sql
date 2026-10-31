-- r793 (F402). Staging cdsmnqxtyyoeoznmbidd only. Craig 1 Nov 2026 07:13 AWST: service upload stopped "preview part 1: permission
-- denied to set parameter track_functions". Caused by r789 (mine): run_jobs set track_functions per step, which the cron worker's role
-- may not change (my rolled-back test ran as postgres). Nothing was written by the failed job.
-- Fix: run_jobs no longer sets track_functions. Step 'ms' timing stays; 'top' just stays empty unless tracking is on server-wide.
-- Rollback: supabase/rollbacks/20261101071500_r793_import_profile_permission.down.sql (puts the broken r789 line back; do not use).
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';

INSERT INTO pdc_backup_r763_20261031.function_sources(sig, prosrc, md5)
SELECT 'pdc_import_620.run_jobs()@r793pre', p.prosrc, md5(p.prosrc) FROM pg_proc p WHERE p.oid = 'pdc_import_620.run_jobs()'::regprocedure
ON CONFLICT (sig) DO NOTHING;

DO $r793$
DECLARE v_old text; v_new text; v_def text; sig regprocedure := 'pdc_import_620.run_jobs()'::regprocedure;
  a1 text := $a$PERFORM pg_catalog.set_config('track_functions', 'pl', true); $a$;
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r793: staging only'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 576 OR fault_id = 'F402' OR added_in = 'r793') THEN RAISE EXCEPTION 'r793: sort 576 or F402 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running', 'loading')) THEN RAISE EXCEPTION 'r793: an import job is running'; END IF;
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  IF md5(v_old) <> '24968dc50480acc40ea85719013fe101' THEN RAISE EXCEPTION 'r793: run_jobs is not the r789 body'; END IF;
  IF (length(v_old) - length(replace(v_old, a1, ''))) / length(a1) <> 2 THEN RAISE EXCEPTION 'r793: expected the setting twice'; END IF;
  v_new := replace(v_old, a1, '');
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = sig) <> v_new THEN RAISE EXCEPTION 'r793: readback differs'; END IF;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, md5(v_old), md5(v_new)) WHERE position(md5(v_old) IN check_sql) > 0;

  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('import_no_superuser_settings_793', 'F402',
    'Import (r793): run_jobs sets no parameter the cron role may not change (track_functions broke the 07:10 upload).',
    $chk$
SELECT strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_import_620.run_jobs()')), 'track_functions') = 0
   AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_import_620.run_jobs()')), 'r787 (F395)') > 0
 AS ok, 'run_jobs sets no restricted parameter' AS detail
$chk$, true, 576, 'r793');
END $r793$;
