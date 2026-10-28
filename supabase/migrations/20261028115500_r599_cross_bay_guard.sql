-- r599 (F213) / sort 369. Staging cdsmnqxtyyoeoznmbidd only.
-- The cross-bay same-vehicle overlap rule and the 1-hour gap are switched off.
-- They stay in the database and turn back on by setting
-- pdc_ops.workshop_guard_599.cross_bay_vehicle_guard to true.
-- Jobs in the same bay still cannot overlap.
-- Undo: supabase/rollbacks/20261028115500_r599_cross_bay_guard.down.sql

SET LOCAL lock_timeout = '4s';
SET LOCAL statement_timeout = '60s';

CREATE TABLE pdc_ops.workshop_guard_599 (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  cross_bay_vehicle_guard boolean NOT NULL DEFAULT false,
  vehicle_exclude_def text NOT NULL
);

INSERT INTO pdc_ops.workshop_guard_599 (singleton, cross_bay_vehicle_guard, vehicle_exclude_def)
VALUES (
  true,
  false,
  'EXCLUDE USING gist (vehicle_id WITH =, tstzrange(scheduled_start_at, scheduled_end_at, ''[)''::text) WITH &&) WHERE (deleted_at IS NULL AND NOT legacy_ambiguity_quarantined AND bay_id IS NOT NULL AND status = ANY (ARRAY[''queued''::public.workshop_booking_status, ''planned''::public.workshop_booking_status, ''started''::public.workshop_booking_status, ''stoppage''::public.workshop_booking_status]))'
);

REVOKE ALL ON TABLE pdc_ops.workshop_guard_599 FROM PUBLIC, anon, authenticated;

CREATE FUNCTION pdc_ops.cross_bay_vehicle_guard_on()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO pg_catalog, public, pdc_ops
AS $$
  SELECT cross_bay_vehicle_guard FROM pdc_ops.workshop_guard_599 WHERE singleton
$$;

REVOKE ALL ON FUNCTION pdc_ops.cross_bay_vehicle_guard_on() FROM PUBLIC, anon, authenticated;

CREATE FUNCTION pdc_ops.enforce_vehicle_cross_bay_599()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, public, pdc_ops
AS $$
BEGIN
  -- r599 (F213): the saved rule. Off until cross_bay_vehicle_guard is true.
  IF NOT pdc_ops.cross_bay_vehicle_guard_on() THEN
    RETURN NEW;
  END IF;
  IF NEW.deleted_at IS NULL
     AND NOT NEW.legacy_ambiguity_quarantined
     AND NEW.bay_id IS NOT NULL
     AND NEW.status IN ('queued', 'planned', 'started', 'stoppage')
     AND EXISTS (
       SELECT 1
       FROM public.workshop_bookings b
       WHERE b.vehicle_id = NEW.vehicle_id
         AND b.id IS DISTINCT FROM NEW.id
         AND b.deleted_at IS NULL
         AND NOT b.legacy_ambiguity_quarantined
         AND b.bay_id IS NOT NULL
         AND b.status IN ('queued', 'planned', 'started', 'stoppage')
         AND tstzrange(b.scheduled_start_at, b.scheduled_end_at, '[)')
             && tstzrange(NEW.scheduled_start_at, NEW.scheduled_end_at, '[)')
     ) THEN
    RAISE EXCEPTION 'vehicle cross-bay overlap' USING ERRCODE = '23P01';
  END IF;
  RETURN NEW;
END
$$;

REVOKE ALL ON FUNCTION pdc_ops.enforce_vehicle_cross_bay_599() FROM PUBLIC, anon, authenticated;

DO $r599$
DECLARE
  awst time;
  def text;
  n integer;
  ok boolean;
  detail text;
  new_tick text;
BEGIN
  awst := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
  IF awst BETWEEN time '12:15' AND time '12:45'
     OR awst BETWEEN time '06:50' AND time '07:30'
     OR awst BETWEEN time '17:50' AND time '18:10' THEN
    RAISE EXCEPTION 'r599: import window';
  END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'r599: staging only';
  END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r599: pin count is not 241'; END IF;
  IF EXISTS (
    SELECT 1 FROM pdc_ops.regression_checks
    WHERE sort_order = 369 OR fault_id = 'F213' OR added_in = 'r599' OR check_name = 'cross_bay_guard_off_599'
  ) THEN RAISE EXCEPTION 'r599: sort 369 or F213 is taken'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)'))
     IS DISTINCT FROM '3b2398e33a2ea35fc137deeedeca4af5' THEN
    RAISE EXCEPTION 'r599: clock tick is not the r577 body';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)'))
     IS DISTINCT FROM '268ca10df3854660ee84b463b3579d8b' THEN
    RAISE EXCEPTION 'r599: move body changed';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)'))
     IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN
    RAISE EXCEPTION 'r599: department 135 changed';
  END IF;

  def := pg_get_functiondef('public.workshop_exclusion_conflict_571(uuid,uuid,timestamp with time zone,integer,text,integer,jsonb,boolean)'::regprocedure);
  IF (length(def) - length(replace(def, '-- r571 (F185): name the booking the exclusion constraint would reject.', ''))) <> length('-- r571 (F185): name the booking the exclusion constraint would reject.') THEN
    RAISE EXCEPTION 'r599: exclusion comment is not unique';
  END IF;
  def := replace(def,
    '-- r571 (F185): name the booking the exclusion constraint would reject.',
    '-- r571 (F185): name the booking the exclusion constraint would reject.' || E'\n'
    || ' if not pdc_ops.cross_bay_vehicle_guard_on() then return null; end if; -- r599 (F213): cross-bay overlap is switched off');
  EXECUTE def;

  def := pg_get_functiondef('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)'::regprocedure);
  IF (length(def) - length(replace(def, 'if v_block is not null then', ''))) <> length('if v_block is not null then') THEN
    RAISE EXCEPTION 'r599: move block is not unique';
  END IF;
  def := replace(def, 'if v_block is not null then', 'if v_block is not null and pdc_ops.cross_bay_vehicle_guard_on() then -- r599 (F213)');
  EXECUTE def;

  def := pg_get_functiondef('public.workshop_clock_tick(boolean,timestamp with time zone)'::regprocedure);
  IF (length(def) - length(replace(def, 'THEN interval ''1 hour'' ELSE interval ''0 minutes''', ''))) / length('THEN interval ''1 hour'' ELSE interval ''0 minutes''') <> 3 THEN
    RAISE EXCEPTION 'r599: expected 3 clock hour gaps';
  END IF;
  IF (length(def) - length(replace(def, 'predecessor.final_end + interval ''1 hour''', ''))) / length('predecessor.final_end + interval ''1 hour''') <> 1 THEN
    RAISE EXCEPTION 'r599: expected 1 clock predecessor hour';
  END IF;
  def := replace(def, 'predecessor.vehicle_id=item.vehicle_id AND predecessor.final_end + interval ''1 hour''',
                      'predecessor.vehicle_id=item.vehicle_id AND pdc_ops.cross_bay_vehicle_guard_on() AND predecessor.final_end + interval ''1 hour''');
  def := replace(def, 'THEN interval ''1 hour'' ELSE interval ''0 minutes''',
                      'AND pdc_ops.cross_bay_vehicle_guard_on() THEN interval ''1 hour'' ELSE interval ''0 minutes''');
  EXECUTE def;
  IF (SELECT proconfig FROM pg_proc WHERE oid = to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)'))
     IS DISTINCT FROM ARRAY['search_path=pg_catalog, public','lock_timeout=3s','statement_timeout=120s']::text[] THEN
    RAISE EXCEPTION 'r599: clock settings drifted';
  END IF;

  ALTER TABLE public.workshop_bookings DROP CONSTRAINT workshop_bookings_active_vehicle_no_overlap;
  CREATE TRIGGER workshop_vehicle_cross_bay_599
    BEFORE INSERT OR UPDATE OF vehicle_id, bay_id, status, scheduled_start_at, scheduled_end_at, deleted_at, legacy_ambiguity_quarantined
    ON public.workshop_bookings
    FOR EACH ROW EXECUTE FUNCTION pdc_ops.enforce_vehicle_cross_bay_599();

  UPDATE pdc_ops.expected_function_md5 SET
    prosrc_md5 = (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')),
    note = 'r599 (F213): the 1-hour same-vehicle gap follows the cross-bay guard, which is off (was 3b2398e33a2ea35fc137deeedeca4af5, r577)',
    updated_at = now()
  WHERE signature = 'public.workshop_clock_tick(boolean,timestamp with time zone)'
    AND prosrc_md5 = '3b2398e33a2ea35fc137deeedeca4af5'
    AND release = 'r577';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'r599: clock pin was not moved'; END IF;

  UPDATE pdc_ops.expected_function_md5 SET
    prosrc_md5 = (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)')),
    note = 'r599 (F213): the cross-bay 1-hour block follows the guard, which is off (was 268ca10df3854660ee84b463b3579d8b)',
    updated_at = now()
  WHERE signature = 'public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamp with time zone,integer,text,jsonb,uuid,boolean)'
    AND prosrc_md5 = '268ca10df3854660ee84b463b3579d8b'
    AND release = 'r571';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'r599: move pin was not moved'; END IF;

  new_tick := (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)'));
  UPDATE pdc_ops.regression_checks
  SET check_sql = replace(check_sql, '3b2398e33a2ea35fc137deeedeca4af5', new_tick)
  WHERE check_name IN ('schedule_stale_version_window_552','read_once_snapshots_554','bay_job_pause_569','parts_eta_stoppage_573','qc_signoff_override_590','pilbara_apply_lock_timeout_596')
    AND check_sql LIKE '%3b2398e33a2ea35fc137deeedeca4af5%';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 6 THEN RAISE EXCEPTION 'r599: expected 6 tick checksum checks, updated %', n; END IF;

  UPDATE pdc_ops.regression_checks
  SET check_sql = replace(check_sql,
        '(SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname=''workshop_bookings_active_vehicle_no_overlap'' AND conrelid=''public.workshop_bookings''::regclass) LIKE ''%bay_id IS NOT NULL%''',
        'NOT pdc_ops.cross_bay_vehicle_guard_on() AND to_regclass(''pdc_ops.workshop_guard_599'') IS NOT NULL')
  WHERE check_name = 'key460_drag_597'
    AND check_sql LIKE '%workshop_bookings_active_vehicle_no_overlap%';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'r599: key 460 check was not marked disabled'; END IF;

  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES (
    'cross_bay_guard_off_599',
    'F213',
    'Craig switched off the cross-bay same-vehicle overlap and the 1-hour gap. Same-bay overlap stays. The guard can be turned back on.',
    $chk599$
SELECT
  NOT guard.cross_bay_vehicle_guard
  AND guard.vehicle_exclude_def LIKE '%vehicle_id WITH =%'
  AND to_regclass('public.workshop_bookings') IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'workshop_bookings_active_vehicle_no_overlap'
      AND conrelid = 'public.workshop_bookings'::regclass
  )
  AND EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'workshop_bookings_active_bay_no_overlap'
      AND conrelid = 'public.workshop_bookings'::regclass
  )
  AND pg_catalog.strpos(excl.prosrc, 'if not pdc_ops.cross_bay_vehicle_guard_on() then return null;') > 0
  AND pg_catalog.strpos(mv.prosrc, 'if v_block is not null and pdc_ops.cross_bay_vehicle_guard_on()') > 0
  AND pg_catalog.strpos(tick.prosrc, 'pdc_ops.cross_bay_vehicle_guard_on()') > 0
  AND (SELECT count(*) FROM pdc_ops.expected_function_md5) = 241
  AND (SELECT pg_catalog.md5(prosrc) FROM pg_catalog.pg_proc WHERE oid = pg_catalog.to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) = 'fd05b9eef69498002ac06dd68e01cdff'
 AS ok,
 'cross-bay guard off' AS detail
FROM pdc_ops.workshop_guard_599 guard
CROSS JOIN pg_catalog.pg_proc excl
CROSS JOIN pg_catalog.pg_proc mv
CROSS JOIN pg_catalog.pg_proc tick
WHERE excl.oid = pg_catalog.to_regprocedure('public.workshop_exclusion_conflict_571(uuid,uuid,timestamptz,integer,text,integer,jsonb,boolean)')
  AND mv.oid = pg_catalog.to_regprocedure('public.administrator_move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb,uuid,boolean)')
  AND tick.oid = pg_catalog.to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')
$chk599$,
    true, 369, 'r599'
  );

  EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'cross_bay_guard_off_599') INTO ok, detail;
  IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r599: guard check red: %', left(coalesce(detail, ''), 200); END IF;
  EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'key460_drag_597') INTO ok, detail;
  IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r599: key 460 check red: %', left(coalesce(detail, ''), 200); END IF;
  EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'slot_between_571') INTO ok, detail;
  IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r599: slot check red: %', left(coalesce(detail, ''), 200); END IF;
  EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'hoist_place_after_592') INTO ok, detail;
  IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r599: hoist check red: %', left(coalesce(detail, ''), 200); END IF;

  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r599: pin count changed'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release = 'r571') <> 1 THEN RAISE EXCEPTION 'r599: r571 pin count changed'; END IF;
  IF (SELECT status FROM public.workshop_bookings WHERE id = '0b48d8ac-4fa5-4a4c-83ea-0ff2e9ee95cd')::text IS DISTINCT FROM 'queued'
     OR (SELECT bay_id FROM public.workshop_bookings WHERE id = '0b48d8ac-4fa5-4a4c-83ea-0ff2e9ee95cd') IS NOT NULL THEN
    RAISE EXCEPTION 'r599: key 460 hoist was booked';
  END IF;
END $r599$;
