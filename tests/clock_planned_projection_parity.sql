-- Owned disposable loopback restore only. No copied customer writes.
BEGIN;
DO $guard$ BEGIN
 IF inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet THEN RAISE EXCEPTION 'loopback_required'; END IF;
END $guard$;
CREATE TEMP TABLE clock_perf_time AS SELECT clock_timestamp() test_at;
CREATE TEMP TABLE clock_perf_before AS SELECT public.workshop_clock_tick(false,test_at) result FROM clock_perf_time;
\ir ../supabase/migrations/20261018100300_clock_planned_projection_cost.sql
CREATE TEMP TABLE clock_perf_after AS SELECT public.workshop_clock_tick(false,test_at) result FROM clock_perf_time;
DO $verify$ BEGIN
 IF (SELECT result FROM clock_perf_before) IS DISTINCT FROM (SELECT result FROM clock_perf_after)
 THEN RAISE EXCEPTION 'clock_plan_changed'; END IF;
END $verify$;
ROLLBACK;
