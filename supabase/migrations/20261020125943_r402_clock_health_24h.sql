-- r402: the clock-tick health check also fails on any whole-tick failure in the last 24 h (was: last 30 runs only).
-- Staging cdsmnqxtyyoeoznmbidd only. Data-only change to pdc_ops.regression_checks; no function body changes, no pins change.
DO $g$
BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r402: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r402: fault_regression_check body changed'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='clock_ticks_recent')<>'722699364dbf5227d839c2dd6230af0f' THEN RAISE EXCEPTION 'r402: clock_ticks_recent is not the expected r399 body'; END IF;
END $g$;
UPDATE pdc_ops.regression_checks SET check_sql=$c$WITH j AS (SELECT jobid FROM cron.job WHERE jobname='staging-workshop-clock-cascade'),
d AS (SELECT d.status, d.start_time, extract(epoch FROM d.end_time-d.start_time)*1000 ms FROM cron.job_run_details d JOIN j ON j.jobid=d.jobid
  WHERE d.start_time>now()-interval '24 hours'),
r AS (SELECT * FROM d WHERE start_time>now()-interval '30 minutes'),
f AS (SELECT * FROM d WHERE status<>'succeeded')
SELECT (SELECT count(*) FROM r)>=25 AND (SELECT count(*) FROM f)=0 AND coalesce((SELECT percentile_cont(0.95) WITHIN GROUP (ORDER BY ms) FROM r),0)<2000 AS ok,
 'last 30 min: '||(SELECT count(*) FROM r)||' runs, p95 '||round(coalesce((SELECT percentile_cont(0.95) WITHIN GROUP (ORDER BY ms) FROM r),0)::numeric)||' ms, max '||round(coalesce((SELECT max(ms) FROM r),0)::numeric)||' ms; last 24 h: '||(SELECT count(*) FROM d)||' runs, '||(SELECT count(*) FROM f)||' whole-tick failures'
 ||coalesce(' (AWST '||(SELECT string_agg(to_char(f.start_time AT TIME ZONE 'Australia/Perth','DD Mon HH24:MI'),', ' ORDER BY f.start_time) FROM f)||')','') AS detail$c$,
 description=$d$workshop_clock_tick ran every minute for the last 30 minutes with p95 under 2 s, and no whole tick failed (lock timeout, deadlock, statement timeout or any error) in the last 24 hours (r402).$d$
WHERE check_name='clock_ticks_recent';
DO $p$
BEGIN
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='clock_ticks_recent')<>'e2b18fca49f1516b4255fb5c47a32037' THEN RAISE EXCEPTION 'r402: post-check md5 mismatch'; END IF;
END $p$;
