SET track_functions = 'all';
DELETE FROM public.probe_result WHERE phase = :'phase';
DELETE FROM public.probe_timing WHERE phase = :'phase';

SELECT pg_stat_reset();
SELECT pg_stat_force_next_flush();
SELECT probe_scenario(:'phase', 'cascade');
SELECT pg_stat_force_next_flush();
SELECT probe_store_calls(:'phase', 'cascade');

SELECT pg_stat_reset();
SELECT pg_stat_force_next_flush();
SELECT probe_scenario(:'phase', 'closure');
SELECT pg_stat_force_next_flush();
SELECT probe_store_calls(:'phase', 'closure');

SELECT pg_stat_reset();
SELECT pg_stat_force_next_flush();
SELECT probe_scenario(:'phase', 'bus');
SELECT pg_stat_force_next_flush();
SELECT probe_store_calls(:'phase', 'bus');

SELECT pg_stat_reset();
SELECT pg_stat_force_next_flush();
SELECT probe_scenario(:'phase', 'running_conflict');
SELECT pg_stat_force_next_flush();
SELECT probe_store_calls(:'phase', 'running_conflict');

SELECT pg_stat_reset();
SELECT pg_stat_force_next_flush();
SELECT probe_scenario(:'phase', 'stoppage_conflict');
SELECT pg_stat_force_next_flush();
SELECT probe_store_calls(:'phase', 'stoppage_conflict');

SELECT pg_stat_reset();
SELECT pg_stat_force_next_flush();
SELECT probe_scenario(:'phase', 'quiet');
SELECT pg_stat_force_next_flush();
SELECT probe_store_calls(:'phase', 'quiet');

SELECT CASE WHEN :'time' = 'yes' THEN probe_time(:'phase', 'idle') ELSE 0 END;
SELECT CASE WHEN :'time' = 'yes' THEN probe_time(:'phase', 'busy') ELSE 0 END;
