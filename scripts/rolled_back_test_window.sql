-- Rolled-back release test window (F15, r405). Paste at the very top of every rolled-back test
-- that calls board write functions, and replace @TAG@ with the release tag (e.g. R405).
--
-- Why: board write functions take the top-level change lock
-- (pg_advisory_xact_lock('pdc:workshop:top-level-mutation')) and keep it until the test's
-- ROLLBACK. The live clock tick runs every minute at :00 and waits only 3 s for that lock
-- (lock_timeout), so a test that holds it across a minute boundary makes the real tick fail
-- (21:25, 21:28 and 21:30 AWST on 20 Oct 2026, r404 tests).
--
-- Rule: 1) wait until this minute's tick has finished, 2) start between :02 and :15,
-- 3) never wait long for a live lock (lock_timeout 2 s), 4) stop and roll back before :50
-- (each statement's statement_timeout is cut to the time left; call pg_temp.deadline() before
-- each step). Locks are only taken after step 1, so waiting holds nothing.

-- 1+2. Wait for the tick (holds no locks; reads cron history only).
DO $window_wait$
DECLARE i integer := 0;
BEGIN
  LOOP
    EXIT WHEN extract(second FROM clock_timestamp()) BETWEEN 2 AND 15
      AND EXISTS (SELECT 1 FROM cron.job_run_details d JOIN cron.job j USING (jobid)
                  WHERE j.jobname = 'staging-workshop-clock-cascade'
                    AND d.start_time >= date_trunc('minute', clock_timestamp())
                    AND d.end_time IS NOT NULL);
    i := i + 1;
    IF i > 75 THEN RAISE EXCEPTION '@TAG@_WINDOW: clock tick not seen; test not started'; END IF;
    PERFORM pg_sleep(1);
  END LOOP;
END $window_wait$;

BEGIN;
-- 3. Never queue behind live work.
SET LOCAL lock_timeout = '2s';
SET LOCAL statement_timeout = '40s';
CREATE TEMP TABLE t_window ON COMMIT DROP AS
  SELECT clock_timestamp() AS started, date_trunc('minute', clock_timestamp()) + interval '50 seconds' AS deadline;
-- 4. Call before each step: stops the test (rolled back) if it would reach the next tick.
CREATE FUNCTION pg_temp.deadline() RETURNS void LANGUAGE plpgsql AS $window_fn$
DECLARE left_ms integer;
BEGIN
  left_ms := floor(extract(epoch FROM (SELECT deadline FROM t_window) - clock_timestamp()) * 1000);
  IF left_ms < 1000 THEN
    RAISE EXCEPTION '@TAG@_DEADLINE: stopped before the next clock tick; everything rolled back';
  END IF;
  PERFORM set_config('statement_timeout', least(left_ms, 40000)::text || 'ms', true);
END $window_fn$;
CREATE FUNCTION pg_temp.window_report() RETURNS jsonb LANGUAGE sql AS $window_fn$
  SELECT jsonb_build_object(
    'started_awst', to_char(started AT TIME ZONE 'Australia/Perth', 'HH24:MI:SS.MS'),
    'now_awst', to_char(clock_timestamp() AT TIME ZONE 'Australia/Perth', 'HH24:MI:SS.MS'),
    'same_minute', date_trunc('minute', started) = date_trunc('minute', clock_timestamp()),
    'seconds', round(extract(epoch FROM clock_timestamp() - started)::numeric, 2))
  FROM t_window $window_fn$;
