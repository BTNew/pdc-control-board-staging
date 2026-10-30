-- r754 (F359) / sort 464. Staging cdsmnqxtyyoeoznmbidd only.
-- Craig 30 Oct 11:11: "the cascade still isnt fixed". After r752 an overdue planned job moved to now only once it was
-- 15 minutes late (the r552 floor in workshop_clock_tick was written for live overruns), so at 11:11 the 11:00 jobs in
-- every bay still sat at 11:00. An overdue planned job now follows the clock once it is 5 minutes late (one re-save per
-- bay every 5 minutes instead of every minute); a live overrun keeps its 15 minute step. One anchored line in the
-- tick; the pin and every check literal move with it, as r737 did. clock_tick_resaves_per_tick counts "cosmetic"
-- moves under 5 minutes instead of 15.
-- Rollback: supabase/rollbacks/20261030111500_r754_overdue_job_follows_clock.down.sql
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';

DO $r754$
DECLARE awst time := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time; v_old text; v_new text; v_def text; v_md5 text; v_n integer;
  c_old text := E'      WHERE id=(movement->>''id'')::uuid\n       AND (abs(extract(epoch FROM ((movement->>''to'')::timestamptz-original_start)))>=900\n         OR abs(extract(epoch FROM ((movement->>''end'')::timestamptz-original_end)))>=900);';
  c_new text := E'      WHERE id=(movement->>''id'')::uuid\n       AND (abs(extract(epoch FROM ((movement->>''to'')::timestamptz-original_start)))>=900\n         OR abs(extract(epoch FROM ((movement->>''end'')::timestamptz-original_end)))>=900\n         -- r754 (F359): an overdue planned job follows the clock within 5 minutes; a live overrun keeps the 15 minute step.\n         OR (status=''planned'' AND actual_start_at IS NULL AND original_start<p_now AND abs(extract(epoch FROM ((movement->>''to'')::timestamptz-original_start)))>=300));';
BEGIN
  IF awst BETWEEN time '12:15' AND time '12:45' OR awst BETWEEN time '06:50' AND time '07:30' OR awst BETWEEN time '17:50' AND time '18:10' THEN RAISE EXCEPTION 'r754: import window'; END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r754: staging only'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 464 OR fault_id = 'F359' OR added_in = 'r754') THEN RAISE EXCEPTION 'r754: sort 464 or F359 is taken'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running')) THEN RAISE EXCEPTION 'r754: an import job is running'; END IF;
  SELECT prosrc, md5(prosrc) INTO v_old, v_md5 FROM pg_proc WHERE oid = 'public.workshop_clock_tick(boolean,timestamptz)'::regprocedure;
  IF v_md5 <> '593971a38ed792793513985f49156ac6' THEN RAISE EXCEPTION 'r754: tick is not the r737 body'; END IF;
  IF (length(v_old) - length(replace(v_old, c_old, ''))) / length(c_old) <> 1 THEN RAISE EXCEPTION 'r754: anchor not found once'; END IF;
  v_new := replace(v_old, c_old, c_new);
  v_def := regexp_replace(pg_get_functiondef('public.workshop_clock_tick(boolean,timestamptz)'::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF (SELECT prosrc FROM pg_proc WHERE oid = 'public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) <> v_new THEN RAISE EXCEPTION 'r754: readback differs'; END IF;
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = md5(v_new) WHERE prosrc_md5 = v_md5;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN RAISE EXCEPTION 'r754: pin row not moved (%)', v_n; END IF;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, v_md5, md5(v_new)) WHERE strpos(check_sql, v_md5) > 0;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n < 6 THEN RAISE EXCEPTION 'r754: md5 literals not moved (%)', v_n; END IF;
  -- "cosmetic" clock moves are now the ones under 5 minutes.
  UPDATE pdc_ops.regression_checks SET check_sql = replace(replace(check_sql,
      $a$(before_data->>'scheduled_start_at')::timestamptz)))<900$a$, $a$(before_data->>'scheduled_start_at')::timestamptz)))<300$a$),
      $a$(before_data->>'scheduled_end_at')::timestamptz)))<900$a$, $a$(before_data->>'scheduled_end_at')::timestamptz)))<300$a$)
    WHERE check_name = 'clock_tick_resaves_per_tick' AND strpos(check_sql, $a$(before_data->>'scheduled_start_at')::timestamptz)))<900$a$) > 0;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN RAISE EXCEPTION 'r754: resaves check not updated'; END IF;
  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES ('overdue_job_follows_clock_754', 'F359',
    'Clock (r754): an overdue planned job follows the clock within 5 minutes. The tick carries the r754 line and no planned job in an active bay is more than 7 minutes overdue while the clock runs.',
    $chk$
SELECT strpos((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')),
  'original_start<p_now AND abs(extract(epoch FROM ((movement->>''to'')::timestamptz-original_start)))>=300') > 0
  AND NOT EXISTS (
    SELECT 1 FROM public.workshop_bookings b JOIN public.workshop_bays y ON y.id = b.bay_id JOIN public.workshop_stages s ON s.id = b.stage_id
    WHERE b.deleted_at IS NULL AND b.status = 'planned' AND b.actual_start_at IS NULL AND y.is_active AND s.active AND s.planner_enabled
      AND b.scheduled_start_at < now() - interval '7 minutes'
      AND public.workshop_calendar_minute_available(now()) IS NOT NULL
      AND (SELECT max(last_success_at) FROM public.workshop_clock_status) > now() - interval '3 minutes')
 AS ok, 'overdue jobs follow the clock within 5 minutes' AS detail
$chk$, true, 464, 'r754');
END $r754$;
