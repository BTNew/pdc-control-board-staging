-- r402 undo: restore the r399 clock_ticks_recent check (check_sql md5 722699364dbf5227d839c2dd6230af0f). Staging only.
DO $g$
BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r402 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r402 undo: fault_regression_check body changed'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='clock_ticks_recent')<>'e2b18fca49f1516b4255fb5c47a32037' THEN RAISE EXCEPTION 'r402 undo: clock_ticks_recent is not the expected r402 body'; END IF;
END $g$;
UPDATE pdc_ops.regression_checks SET check_sql=$c$WITH d AS (SELECT d.status, extract(epoch FROM d.end_time-d.start_time)*1000 ms FROM cron.job_run_details d JOIN cron.job j ON j.jobid=d.jobid
  WHERE j.jobname='staging-workshop-clock-cascade' AND d.start_time>now()-interval '30 minutes')
SELECT count(*)>=25 AND count(*) FILTER (WHERE status<>'succeeded')=0 AND coalesce(percentile_cont(0.95) WITHIN GROUP (ORDER BY ms),0)<2000 AS ok,
 count(*)||' runs, '||count(*) FILTER (WHERE status<>'succeeded')||' not succeeded, p95 '||round(coalesce(percentile_cont(0.95) WITHIN GROUP (ORDER BY ms),0)::numeric)||' ms, max '||round(coalesce(max(ms),0)::numeric)||' ms' AS detail FROM d$c$,
 description=$d$workshop_clock_tick ran every minute for the last 30 minutes, none failed, p95 under 2 s.$d$
WHERE check_name='clock_ticks_recent';
DO $p$
BEGIN
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='clock_ticks_recent')<>'722699364dbf5227d839c2dd6230af0f'
  OR (SELECT description FROM pdc_ops.regression_checks WHERE check_name='clock_ticks_recent')<>$d$workshop_clock_tick ran every minute for the last 30 minutes, none failed, p95 under 2 s.$d$ THEN RAISE EXCEPTION 'r402 undo: restore check failed'; END IF;
END $p$;
