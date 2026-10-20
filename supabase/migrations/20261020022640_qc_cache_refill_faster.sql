-- QC lines cache refill: 40 vehicles every 20 seconds (was 20 per minute).
-- Same refill function (md5 c9bad5fb...), unchanged; batch 40 is its own max; 3 s budget per run.
-- Staging cdsmnqxtyyoeoznmbidd only. Undo: qc_cache_refill_faster.down.sql
DO $g$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'staging_only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.refill_qc_operation_lines_cache(integer)'::regprocedure) IS DISTINCT FROM 'c9bad5fb2c6ce6f549539fc06647a215' THEN RAISE EXCEPTION 'refill_changed'; END IF;
 IF (SELECT schedule||'|'||command FROM cron.job WHERE jobname='staging-qc-operation-lines-cache-refill') IS DISTINCT FROM '* * * * *|SELECT pdc_work_categories_private.refill_qc_operation_lines_cache(20);' THEN RAISE EXCEPTION 'refill_job_changed'; END IF;
END $g$;
SELECT cron.alter_job((SELECT jobid FROM cron.job WHERE jobname='staging-qc-operation-lines-cache-refill'),
 schedule:='20 seconds', command:='SELECT pdc_work_categories_private.refill_qc_operation_lines_cache(40);');
