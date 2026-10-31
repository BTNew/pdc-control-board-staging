-- r785 (F393). Staging cdsmnqxtyyoeoznmbidd only. Craig 31 Oct 2026 13:06 AWST "Okay to fix" (the 8 red health checks).
-- Four checks were red because the check, not the board, was out of date. Check text only; no data or function changes.
--   pmb_bay_names_483      wanted 2 active Tyre bays. Craig turned Tyre Bay 02 off in Bay Manager (30 Oct 08:33 AWST). Now: at least 1.
--   bay_code_identity_579  looked for the r483 active rule as written before Hoist 01 was turned off (29 Oct). Now looks for the current rule.
--   overdue_job_moves_to_now_752  flagged 10 jobs moved at 16:29 Fri to 06:00 Mon. That is the calendar (the workshop closes 16:30),
--                          not a missed move. Now measured from the next open workshop minute (workshop_clock_next_minute).
--   bodybuilder_new_to_pmb_574  counted 3 arrivals (13109753, 13077203, 13047269) released by key number as slipped. r745
--                          releases the hold when a key is given (release_action 'key_number'); that is an allowed release.
DO $r785$
DECLARE n integer;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r785: staging only'; END IF;

  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql,
    $q$coalesce((SELECT n FROM o WHERE code='TYRE'),0)=2$q$, $q$coalesce((SELECT n FROM o WHERE code='TYRE'),0)>=1 /* r785: Tyre bays set in Bay Manager */$q$)
  WHERE check_name = 'pmb_bay_names_483' AND position($q$coalesce((SELECT n FROM o WHERE code='TYRE'),0)=2$q$ IN check_sql) > 0;
  GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'r785: 483 not updated'; END IF;

  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql,
    $q$'b.is_active = (m.stage_code <> ''ELECTRICAL'' OR m.bay_number <= 7)'$q$,
    $q$'b.is_active = (NOT (m.stage_code = ''HOIST'' AND m.bay_number = 1) AND (m.stage_code <> ''ELECTRICAL'' OR m.bay_number <= 7))'$q$)
  WHERE check_name = 'bay_code_identity_579';
  GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'r785: 579 not updated'; END IF;

  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql,
    $q$> h.clock_at + interval '16 minutes'$q$, $q$> public.workshop_clock_next_minute(h.clock_at) + interval '16 minutes' /* r785: closed hours are not a missed move */$q$)
  WHERE check_name = 'overdue_job_moves_to_now_752' AND (length(check_sql) - length(replace(check_sql, $q$> h.clock_at + interval '16 minutes'$q$, ''))) / length($q$> h.clock_at + interval '16 minutes'$q$) = 1;
  GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'r785: 752 not updated'; END IF;

  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql,
    $q$AND (h.release_action IS DISTINCT FROM 'to_pmb' OR h.released_by IS NULL)$q$,
    $q$AND (h.release_action IS DISTINCT FROM 'to_pmb' OR h.released_by IS NULL) AND h.release_action IS DISTINCT FROM 'key_number' /* r785: r745 key release */$q$)
  WHERE check_name = 'bodybuilder_new_to_pmb_574' AND position($q$AND (h.release_action IS DISTINCT FROM 'to_pmb' OR h.released_by IS NULL)$q$ IN check_sql) > 0;
  GET DIAGNOSTICS n = ROW_COUNT; IF n <> 1 THEN RAISE EXCEPTION 'r785: 574 not updated'; END IF;
END $r785$;
