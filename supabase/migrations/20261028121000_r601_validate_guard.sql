-- r601 (F215) / sort 372. Staging cdsmnqxtyyoeoznmbidd only.
-- The booking check that refused Craig's 10:02 drop now follows the cross-bay guard.
-- The guard stays off. Same-bay overlap is unchanged.
-- Undo: supabase/rollbacks/20261028121000_r601_validate_guard.down.sql

SET LOCAL lock_timeout = '4s';
SET LOCAL statement_timeout = '60s';

DO $r601$
DECLARE
  awst time;
  def text;
  old_line text := $old$if v_conflict is not null then return jsonb_build_object('ok',false,'error','vehicle_overlap','conflict_booking_id',v_conflict); end if;$old$;
  new_line text := $new$if v_conflict is not null and pdc_ops.cross_bay_vehicle_guard_on() then return jsonb_build_object('ok',false,'error','vehicle_overlap','conflict_booking_id',v_conflict); end if; -- r601 (F215)$new$;
  n integer;
  ok boolean;
  detail text;
BEGIN
  awst := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
  IF awst BETWEEN time '12:15' AND time '12:45'
     OR awst BETWEEN time '06:50' AND time '07:30'
     OR awst BETWEEN time '17:50' AND time '18:10' THEN
    RAISE EXCEPTION 'r601: import window';
  END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'r601: staging only';
  END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r601: pin count'; END IF;
  IF EXISTS (
    SELECT 1 FROM pdc_ops.regression_checks
    WHERE sort_order = 372 OR fault_id = 'F215' OR added_in = 'r601' OR check_name = 'validate_cross_bay_off_601'
  ) THEN RAISE EXCEPTION 'r601: sort 372 or F215 is taken'; END IF;
  IF (SELECT cross_bay_vehicle_guard FROM pdc_ops.workshop_guard_599) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'r601: cross-bay guard is on';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)'))
     IS DISTINCT FROM '4e8dfda7795a8a547358554c5720a174' THEN
    RAISE EXCEPTION 'r601: validator changed';
  END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)'))
     IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN
    RAISE EXCEPTION 'r601: department 135 changed';
  END IF;

  def := pg_get_functiondef('public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,integer,public.workshop_booking_status,uuid,boolean)'::regprocedure);
  IF (length(def) - length(replace(def, old_line, ''))) <> length(old_line) THEN
    RAISE EXCEPTION 'r601: validator overlap line is not unique';
  END IF;
  def := replace(def, old_line, new_line);
  EXECUTE def;

  UPDATE pdc_ops.expected_function_md5 SET
    prosrc_md5 = (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)')),
    note = 'r601 (F215): the cross-bay vehicle overlap follows the guard, which is off (was 4e8dfda7795a8a547358554c5720a174)',
    updated_at = now()
  WHERE signature = 'public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,integer,public.workshop_booking_status,uuid,boolean)'
    AND prosrc_md5 = '4e8dfda7795a8a547358554c5720a174'
    AND release = 'r548';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'r601: validator pin was not moved'; END IF;

  INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
  VALUES (
    'validate_cross_bay_off_601',
    'F215',
    'The booking check that maps to the cross-bay overlap toast follows the guard. The guard is off. Same-bay overlap text remains.',
    $chk601$
SELECT
  NOT g.cross_bay_vehicle_guard
  AND pg_catalog.strpos(body.prosrc, 'pdc_ops.cross_bay_vehicle_guard_on()') > 0
  AND pg_catalog.strpos(body.prosrc, 'vehicle_overlap') > 0
  AND pg_catalog.strpos(body.prosrc, 'and b.bay_id IS NOT NULL') > 0
  AND pg_catalog.strpos(body.prosrc, 'if v_conflict is not null then return jsonb_build_object(''ok'',false,''error'',''vehicle_overlap''') = 0
  AND (SELECT count(*) FROM pdc_ops.expected_function_md5) = 241
  AND (SELECT pg_catalog.md5(prosrc) FROM pg_catalog.pg_proc WHERE oid = pg_catalog.to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) = 'fd05b9eef69498002ac06dd68e01cdff'
 AS ok,
 'validator follows the guard' AS detail
FROM pdc_ops.workshop_guard_599 g
CROSS JOIN pg_catalog.pg_proc body
WHERE body.oid = pg_catalog.to_regprocedure('public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)')
$chk601$,
    true, 372, 'r601'
  );

  EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'validate_cross_bay_off_601') INTO ok, detail;
  IF ok IS NOT TRUE THEN RAISE EXCEPTION 'r601: check red: %', left(coalesce(detail, ''), 200); END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r601: pin count changed'; END IF;
  IF (SELECT status FROM public.workshop_bookings WHERE id = '0b48d8ac-4fa5-4a4c-83ea-0ff2e9ee95cd')::text IS DISTINCT FROM 'queued'
     OR (SELECT bay_id FROM public.workshop_bookings WHERE id = '0b48d8ac-4fa5-4a4c-83ea-0ff2e9ee95cd') IS NOT NULL THEN
    RAISE EXCEPTION 'r601: key 460 hoist was booked';
  END IF;
END $r601$;
