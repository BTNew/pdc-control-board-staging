-- Restore the QC cache refill job to 20 vehicles per minute.
SELECT cron.alter_job((SELECT jobid FROM cron.job WHERE jobname='staging-qc-operation-lines-cache-refill'),
 schedule:='* * * * *', command:='SELECT pdc_work_categories_private.refill_qc_operation_lines_cache(20);');
DO $p$ BEGIN
 IF (SELECT schedule||'|'||command FROM cron.job WHERE jobname='staging-qc-operation-lines-cache-refill') IS DISTINCT FROM '* * * * *|SELECT pdc_work_categories_private.refill_qc_operation_lines_cache(20);' THEN RAISE EXCEPTION 'refill_job_not_restored'; END IF;
END $p$;
