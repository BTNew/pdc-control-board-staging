-- r599 (F213) undo. Staging only. Turns the cross-bay overlap rule back on
-- by restoring the exclusion constraint and the previous function text.
-- It does not rewrite booking rows.

SET LOCAL lock_timeout = '8s';
SET LOCAL statement_timeout = '60s';

DO $undo599$
DECLARE
  def text;
  n integer;
  new_tick text;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'r599 undo: staging only'; END IF;
  new_tick := (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)'));

  DROP TRIGGER IF EXISTS workshop_vehicle_cross_bay_599 ON public.workshop_bookings;
  ALTER TABLE public.workshop_bookings ADD CONSTRAINT workshop_bookings_active_vehicle_no_overlap
    EXCLUDE USING gist (vehicle_id WITH =, tstzrange(scheduled_start_at, scheduled_end_at, '[)'::text) WITH &&)
    WHERE (deleted_at IS NULL AND NOT legacy_ambiguity_quarantined AND bay_id IS NOT NULL
      AND status = ANY (ARRAY['queued'::public.workshop_booking_status, 'planned'::public.workshop_booking_status, 'started'::public.workshop_booking_status, 'stoppage'::public.workshop_booking_status]));

  def := pg_get_functiondef('public.workshop_exclusion_conflict_571(uuid,uuid,timestamp with time zone,integer,text,integer,jsonb,boolean)'::regprocedure);
  def := replace(def, E'\n if not pdc_ops.cross_bay_vehicle_guard_on() then return null; end if; -- r599 (F213): cross-bay overlap is switched off', '');
  EXECUTE def;

  def := pg_get_functiondef('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)'::regprocedure);
  def := replace(def, 'if v_block is not null and pdc_ops.cross_bay_vehicle_guard_on() then -- r599 (F213)', 'if v_block is not null then');
  EXECUTE def;

  def := pg_get_functiondef('public.workshop_clock_tick(boolean,timestamp with time zone)'::regprocedure);
  def := replace(def, 'predecessor.vehicle_id=item.vehicle_id AND pdc_ops.cross_bay_vehicle_guard_on() AND predecessor.final_end + interval ''1 hour''',
                      'predecessor.vehicle_id=item.vehicle_id AND predecessor.final_end + interval ''1 hour''');
  def := replace(def, 'AND pdc_ops.cross_bay_vehicle_guard_on() THEN interval ''1 hour'' ELSE interval ''0 minutes''',
                      'THEN interval ''1 hour'' ELSE interval ''0 minutes''');
  EXECUTE def;

  UPDATE pdc_ops.expected_function_md5 SET
    prosrc_md5 = '3b2398e33a2ea35fc137deeedeca4af5',
    note = 'r577: per-bay hours when an override exists (was 83a2c8d5ff85b5a295343e5f3ef66ded, r559)',
    updated_at = now()
  WHERE signature = 'public.workshop_clock_tick(boolean,timestamp with time zone)' AND release = 'r577';
  UPDATE pdc_ops.expected_function_md5 SET
    prosrc_md5 = '268ca10df3854660ee84b463b3579d8b',
    note = 'r597 (F211): unallocated rows are not conflicts; a snapped start is not a self-conflict (was 6a02115d30578e8eb3807a283b1d60ea)',
    updated_at = now()
  WHERE signature = 'public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)' AND release = 'r571';

  UPDATE pdc_ops.regression_checks
  SET check_sql = replace(check_sql, new_tick, '3b2398e33a2ea35fc137deeedeca4af5')
  WHERE check_name IN ('schedule_stale_version_window_552','read_once_snapshots_554','bay_job_pause_569','parts_eta_stoppage_573','qc_signoff_override_590','pilbara_apply_lock_timeout_596');
  UPDATE pdc_ops.regression_checks
  SET check_sql = replace(check_sql,
        'NOT pdc_ops.cross_bay_vehicle_guard_on() AND to_regclass(''pdc_ops.workshop_guard_599'') IS NOT NULL',
        '(SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname=''workshop_bookings_active_vehicle_no_overlap'' AND conrelid=''public.workshop_bookings''::regclass) LIKE ''%bay_id IS NOT NULL%''')
  WHERE check_name = 'key460_drag_597';
  DELETE FROM pdc_ops.regression_checks WHERE check_name = 'cross_bay_guard_off_599' AND added_in = 'r599';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'r599 undo: check not removed'; END IF;

  DROP FUNCTION pdc_ops.enforce_vehicle_cross_bay_599();
  DROP FUNCTION pdc_ops.cross_bay_vehicle_guard_on();
  DROP TABLE pdc_ops.workshop_guard_599;

  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) IS DISTINCT FROM '3b2398e33a2ea35fc137deeedeca4af5' THEN
    RAISE EXCEPTION 'r599 undo: clock checksum';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)')) IS DISTINCT FROM '268ca10df3854660ee84b463b3579d8b' THEN
    RAISE EXCEPTION 'r599 undo: move checksum';
  END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r599 undo: pin count'; END IF;
END $undo599$;
