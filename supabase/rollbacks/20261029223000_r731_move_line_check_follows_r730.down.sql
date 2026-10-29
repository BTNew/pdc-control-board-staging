-- r731 rollback: puts the r680 text of move_line_min_hour_680 back (only meaningful after the r730 rollback, which
-- restores the 60 minute clamp). Staging cdsmnqxtyyoeoznmbidd only.
UPDATE pdc_ops.regression_checks
SET description = 'Moving a line between stations never resizes an unstarted booking below 60 minutes or one whose start has passed (it failed with "could not be lengthened").',
    check_sql = $chk$
SELECT (SELECT count(*) FROM regexp_matches(a, 'IF mins<60 THEN mins:=60; END IF;', 'g')) = 2
   AND (SELECT count(*) FROM regexp_matches(a, 'IF rec\.scheduled_start_at >= clock_timestamp\(\) AND', 'g')) = 2
 AS ok, 'move line keeps 60 min minimum and skips passed starts' AS detail
FROM (SELECT prosrc a FROM pg_proc WHERE oid = to_regprocedure('public.set_vehicle_work_category(uuid,integer,text,text,integer,boolean,jsonb)')) x
$chk$
WHERE check_name = 'move_line_min_hour_680';
