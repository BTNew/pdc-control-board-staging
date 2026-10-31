-- r782 (F387) / sort 569. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 31 Oct 2026 11:42 AWST: "then lets work out how to get the service one uploading quicker :)"
-- The 11:00 file took 1051 s for 40 parts. Two changes:
--   1. Edge function (same release): Apply sends only the stocks that changed since their last OK apply (r771 hash), plus
--      new and held-before stocks. Unchanged stocks are not sent at all, so most parts never exist. The whole-file snapshot
--      is still recorded first, so the last-part archive still sees every car on the file.
--   2. run_jobs works up to 55 s per one-minute cron tick instead of 40 s (the advisory lock still stops two runs at once;
--      the 2 min statement timeout still bounds a tick).
-- Rollback: supabase/rollbacks/20261031123000_r782_faster_service_upload.down.sql
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';

INSERT INTO pdc_backup_r763_20261031.function_sources(sig, prosrc, md5)
SELECT 'pdc_import_620.run_jobs()@r782pre', p.prosrc, md5(p.prosrc) FROM pg_proc p WHERE p.oid = 'pdc_import_620.run_jobs()'::regprocedure
ON CONFLICT (sig) DO NOTHING;

DO $r782$
DECLARE v_old text; v_new text; v_def text; sig regprocedure := 'pdc_import_620.run_jobs()'::regprocedure;
  a1 text := $a$ELSE interval '40 seconds' END;$a$;
  b1 text := $a$ELSE interval '55 seconds' END; -- r782 (F387): was 40 seconds$a$;
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r782: staging only'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 569 OR fault_id = 'F387' OR added_in = 'r782') THEN RAISE EXCEPTION 'r782: sort 569 or F387 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running', 'loading')) THEN RAISE EXCEPTION 'r782: an import job is running'; END IF;
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  IF md5(v_old) <> '1036f5fbbceb08d2b13e87531df0253b' THEN RAISE EXCEPTION 'r782: run_jobs is not the expected body'; END IF;
  IF (length(v_old) - length(replace(v_old, a1, ''))) / length(a1) <> 1 THEN RAISE EXCEPTION 'r782: anchor not found once'; END IF;
  v_new := replace(v_old, a1, b1);
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = sig) <> v_new THEN RAISE EXCEPTION 'r782: readback differs'; END IF;
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('faster_service_upload_782', 'F387',
    'Upload (r782): run_jobs works up to 55 s per cron tick (lock still single-run). The edge function sends only changed, new and held-before stocks.',
    $chk$
SELECT strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_import_620.run_jobs()')), $$ELSE interval '55 seconds' END; -- r782 (F387)$$) > 0
   AND strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('pdc_import_620.run_jobs()')), 'pg_try_advisory_lock') > 0
 AS ok, 'run_jobs 55 s per tick' AS detail
$chk$, true, 569, 'r782');
END $r782$;
