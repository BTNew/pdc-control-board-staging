-- Undo r577 (F191) / sort 349. Staging cdsmnqxtyyoeoznmbidd only.
-- Restores the nine pinned bodies and the three unpinned calendar bodies,
-- puts the old prosrc md5s back, and drops the bay-hours table.
-- Does not rewrite workshop_bookings. Department 135 is not edited.
-- Run between :02 and :45.

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r577 down: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r577 down: staging only'; END IF;
 IF EXISTS (SELECT 1 FROM public.pdc_staging_environment_sentinel WHERE project_ref='vjdtsswhroyguxyfjdkt') THEN RAISE EXCEPTION 'r577 down: production ref'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r577 down: pin count is not 241'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='bay_manager_hours_570' AND fault_id='F191' AND sort_order=349 AND added_in='r577') THEN RAISE EXCEPTION 'r577 down: check missing'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r577')<>9 THEN RAISE EXCEPTION 'r577 down: expected nine r577 pins'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_pdc.workshop_clock_tick(boolean,timestamptz)')) IS DISTINCT FROM 'eb25ab44d4d007d3b749bd7bc5e56abc' THEN RAISE EXCEPTION 'r577 down: department 135 clock changed'; END IF;
END $g$;

UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')), '83a2c8d5ff85b5a295343e5f3ef66ded')
 WHERE check_name IN ('bay_job_pause_569','schedule_stale_version_window_552','read_once_snapshots_554')
   AND check_sql LIKE '%' || (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) || '%';
UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)')), 'ae08aa9b0dc99e7c93b1710efdcb5070')
 WHERE check_sql LIKE '%' || (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)')) || '%'
   AND check_name IN ('planner_duration_after_insert_537','planner_duration_cache_531');
UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_capacity_plan(text,uuid,integer,timestamptz)')), 'bc237d9f466c45a086c251ec8c3071a7')
 WHERE check_sql LIKE '%' || (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_capacity_plan(text,uuid,integer,timestamptz)')) || '%'
   AND check_name IN ('close_gaps_preview_bay_label_and_tech_reason','close_gaps_holds_populated');
UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, 'release=''r577''', 'release=''r559''')
 WHERE check_name IN ('clock_ticks_recent','clock_tick_resaves_per_tick') AND check_sql LIKE '%release=''r577''%';
UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, $from$release=''r577''$from$, $to$release=''r559''$to$)
 WHERE check_name = 'bay_default_clock_gap_559' AND check_sql LIKE $like$%release=''r577''%$like$;
UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, 'tick_pin.release=''r577''', 'tick_pin.release=''r559''')
 WHERE check_name = 'bay_default_clock_gap_559' AND check_sql LIKE '%tick_pin.release=''r577''%';

CREATE FUNCTION pg_temp.r570_unpatch(p_sig text, p_from text, p_to text, p_expect text)
 RETURNS void LANGUAGE plpgsql AS $u$
DECLARE def text;
BEGIN
  def := pg_get_functiondef(to_regprocedure(p_sig));
  IF (length(def) - length(replace(def, p_from, ''))) / length(p_from) < 1 THEN
    RAISE EXCEPTION 'r577 down: pattern missing in %', p_sig;
  END IF;
  EXECUTE replace(def, p_from, p_to);
  IF p_expect IS NOT NULL AND (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure(p_sig)) IS DISTINCT FROM p_expect THEN
    RAISE EXCEPTION 'r577 down: % did not return to %', p_sig, p_expect;
  END IF;
END $u$;

SELECT pg_temp.r570_unpatch('public.cascade_workshop_booking_move_pre_116(uuid,integer,text,integer,timestamptz,integer,text,jsonb)',
 $n$v_target_end:=COALESCE((SELECT public.workshop_bay_add_minutes_570(p_scheduled_start_at,v_target_duration,b.id) FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE public.workshop_canonical_stage_code(s.code)=public.workshop_canonical_stage_code(p_stage_code) AND b.bay_number=p_bay_number AND NOT b.is_sublet_row AND public.workshop_bay_has_hours_570(b.id) LIMIT 1), public.workshop_add_operational_minutes(p_scheduled_start_at,v_target_duration));$n$,
 $o$v_target_end:=public.workshop_add_operational_minutes(p_scheduled_start_at,v_target_duration);$o$,
 'd5e0543537cafb026383c7338c8e2b82');

SELECT pg_temp.r570_unpatch('public.workshop_booking_effective_end_at(uuid)',
 $n$RETURN (SELECT CASE WHEN public.workshop_bay_has_hours_570(b.bay_id) AND b.status IN('queued','planned','started','stoppage')
 THEN public.workshop_bay_add_minutes_570(b.scheduled_start_at,public.workshop_booking_effective_duration_minutes(b.id),b.bay_id)
 WHEN b.bus_calendar_version=1 AND b.status IN('queued','planned','started','stoppage')
 THEN pdc_bus_private.add_minutes(b.scheduled_start_at,public.workshop_booking_effective_duration_minutes(b.id),b.bay_id)$n$,
 $o$RETURN (SELECT CASE WHEN b.bus_calendar_version=1 AND b.status IN('queued','planned','started','stoppage')
 THEN pdc_bus_private.add_minutes(b.scheduled_start_at,public.workshop_booking_effective_duration_minutes(b.id),b.bay_id)$o$,
 '3cd30a49767b2b79fadc325d56cbca42');

SELECT pg_temp.r570_unpatch('public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)',
 $n$END ELSE CASE WHEN public.workshop_bay_has_hours_570(p_bay_id) THEN public.workshop_bay_add_minutes_570(p_scheduled_start_at,v_estimated_duration,p_bay_id) ELSE public.workshop_add_operational_minutes(p_scheduled_start_at,v_estimated_duration) END END else p_scheduled_end_at end$n$,
 $o$END ELSE public.workshop_add_operational_minutes(p_scheduled_start_at,v_estimated_duration) END else p_scheduled_end_at end$o$,
 NULL);

SELECT pg_temp.r570_unpatch('public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)',
 $n$if NOT v_bus_calendar AND NOT v_preserve_historical_calendar AND NOT (public.workshop_bay_has_hours_570(p_bay_id) AND EXISTS (SELECT 1 FROM public.workshop_bookings b WHERE b.id=p_booking_id AND b.bay_id=p_bay_id AND b.scheduled_start_at=p_scheduled_start_at AND b.scheduled_end_at=p_scheduled_end_at AND b.default_duration_minutes=p_duration_minutes AND b.deleted_at IS NULL)) AND (CASE WHEN public.workshop_bay_has_hours_570(p_bay_id) THEN public.workshop_bay_minutes_between_570(p_scheduled_start_at,p_scheduled_end_at,p_bay_id) ELSE public.workshop_operational_minutes_between(p_scheduled_start_at,p_scheduled_end_at) END) <>p_duration_minutes then$n$,
 $o$if NOT v_bus_calendar AND NOT v_preserve_historical_calendar AND public.workshop_operational_minutes_between(p_scheduled_start_at,p_scheduled_end_at)<>p_duration_minutes then$o$,
 'ae08aa9b0dc99e7c93b1710efdcb5070');

SELECT pg_temp.r570_unpatch('public.book_all_vehicle_stations(uuid,integer)',
 $n$calendar_bay:=CASE WHEN (item->>'code'='BUS_4X4' AND pdc_bus_private.active_vehicle(v.id)) OR public.workshop_bay_has_hours_570(bay.id) THEN bay.id END;$n$,
 $o$calendar_bay:=CASE WHEN item->>'code'='BUS_4X4' AND pdc_bus_private.active_vehicle(v.id) THEN bay.id END;$o$,
 '90fc0d4727d827db53c308ff9dfa8bcd');

SELECT pg_temp.r570_unpatch('public.workshop_capacity_plan(text,uuid,integer,timestamptz)',
 $n$CASE WHEN (s.code='BUS_4X4' AND b.bay_id IS NOT NULL AND pdc_bus_private.active_vehicle(b.vehicle_id)) OR public.workshop_bay_has_hours_570(b.bay_id) THEN b.bay_id END$n$,
 $o$CASE WHEN s.code='BUS_4X4' AND b.bay_id IS NOT NULL AND pdc_bus_private.active_vehicle(b.vehicle_id) THEN b.bay_id END$o$,
 'bc237d9f466c45a086c251ec8c3071a7');

SELECT pg_temp.r570_unpatch('public.workshop_clock_tick(boolean,timestamptz)',
 $n$CASE WHEN (s.code='BUS_4X4' AND pdc_bus_private.active_vehicle(b.vehicle_id)) OR public.workshop_bay_has_hours_570(b.bay_id) THEN b.bay_id END$n$,
 $o$CASE WHEN s.code='BUS_4X4' AND pdc_bus_private.active_vehicle(b.vehicle_id) THEN b.bay_id END$o$,
 '83a2c8d5ff85b5a295343e5f3ef66ded');

SELECT pg_temp.r570_unpatch('pdc_cascade_private.overlap_chain_469(uuid[],timestamptz)',
 $n$    v_new_start := CASE WHEN public.workshop_bay_has_hours_570(v_row.bay_id) THEN public.workshop_bay_next_minute_570(v_cursor, v_row.bay_id) ELSE public.workshop_next_calendar_window(v_cursor, v_row.default_duration_minutes) END;
    v_new_end := CASE WHEN public.workshop_bay_has_hours_570(v_row.bay_id) THEN public.workshop_bay_add_minutes_570(v_new_start, v_row.default_duration_minutes, v_row.bay_id) ELSE public.workshop_add_operational_minutes(v_new_start, v_row.default_duration_minutes) END;$n$,
 $o$    v_new_start := public.workshop_next_calendar_window(v_cursor, v_row.default_duration_minutes);
    v_new_end := public.workshop_add_operational_minutes(v_new_start, v_row.default_duration_minutes);$o$,
 NULL);

SELECT pg_temp.r570_unpatch('pdc_cascade_private.overlap_chain_469(uuid[],timestamptz)',
 $n$select b.id, b.version, b.scheduled_start_at, b.scheduled_end_at, b.default_duration_minutes, b.bay_id$n$,
 $o$select b.id, b.version, b.scheduled_start_at, b.scheduled_end_at, b.default_duration_minutes$o$,
 'e3602ba6f9d5973deea4eef09f5077c0');

SELECT pg_temp.r570_unpatch('pdc_cascade_private.target_end_469(uuid,uuid,timestamptz,integer)',
 $n$if p_start is null or p_minutes is null or p_minutes < 1 then return null; end if;
  if public.workshop_bay_has_hours_570(p_bay_id) then return public.workshop_bay_add_minutes_570(p_start, p_minutes, p_bay_id); end if;$n$,
 $o$if p_start is null or p_minutes is null or p_minutes < 1 then return null; end if;$o$,
 'b7b98893bfc7a04b39330ca689f8f1b1');

SELECT pg_temp.r570_unpatch('pdc_bay_seq_private.next_start(timestamptz,uuid)',
 $n$IF p_at IS NULL THEN RETURN NULL; END IF;
 IF public.workshop_bay_has_hours_570(p_bay) THEN RETURN public.workshop_bay_next_minute_570(p_at, p_bay); END IF;$n$,
 $o$IF p_at IS NULL THEN RETURN NULL; END IF;$o$,
 '6d2cdc4cb26bb37794c6998b206f6e0c');

SELECT pg_temp.r570_unpatch('pdc_bay_seq_private.end_at(timestamptz,integer,uuid)',
 $n$BEGIN
 IF public.workshop_bay_has_hours_570(p_bay) THEN RETURN public.workshop_bay_add_minutes_570(p_start, greatest(p_minutes,0), p_bay); END IF;
 IF EXISTS(SELECT 1 FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.id=p_bay AND s.code='BUS_4X4') THEN$n$,
 $o$BEGIN
 IF EXISTS(SELECT 1 FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.id=p_bay AND s.code='BUS_4X4') THEN$o$,
 '8067dd22688d7b93d90c9c03eabfbe7d');

SELECT pg_temp.r570_unpatch('pdc_bus_private.clock_minutes_between(timestamptz,timestamptz,uuid)',
 $n$IF p_calendar_bay_id IS NULL THEN RETURN public.workshop_operational_minutes_between(p_start,p_end); END IF;
 IF public.workshop_bay_has_hours_570(p_calendar_bay_id) THEN RETURN public.workshop_bay_minutes_between_570(p_start, p_end, p_calendar_bay_id); END IF;$n$,
 $o$IF p_calendar_bay_id IS NULL THEN RETURN public.workshop_operational_minutes_between(p_start,p_end); END IF;$o$,
 'c1e4e6b69cd67aebcbce738fd1a68dc2');

SELECT pg_temp.r570_unpatch('pdc_bus_private.clock_next_minute(timestamptz,uuid)',
 $n$IF p_at IS NULL THEN RAISE EXCEPTION 'Clock time required' USING errcode='22023'; END IF;
 IF public.workshop_bay_has_hours_570(p_calendar_bay_id) THEN RETURN public.workshop_bay_next_minute_570(p_at, p_calendar_bay_id); END IF;$n$,
 $o$IF p_at IS NULL THEN RAISE EXCEPTION 'Clock time required' USING errcode='22023'; END IF;$o$,
 '734b6fc0d468b8a8a9cee2b955f9b21b');

SELECT pg_temp.r570_unpatch('pdc_bus_private.add_minutes(timestamptz,integer,uuid)',
 $n$IF p_start IS NULL OR p_minutes IS NULL OR p_minutes<0 OR p_minutes>59999 THEN RAISE EXCEPTION 'Invalid duration' USING errcode='22023'; END IF;
 IF public.workshop_bay_has_hours_570(p_bay_id) THEN RETURN public.workshop_bay_add_minutes_570(p_start, p_minutes, p_bay_id); END IF;$n$,
 $o$IF p_start IS NULL OR p_minutes IS NULL OR p_minutes<0 OR p_minutes>59999 THEN RAISE EXCEPTION 'Invalid duration' USING errcode='22023'; END IF;$o$,
 'c43afa5c1312392aa5d3666a8aa7cf65');

SELECT pg_temp.r570_unpatch('pdc_bus_private.minute_available(timestamptz,uuid)',
 $n$BEGIN
 IF public.workshop_bay_has_hours_570(p_bay_id) THEN RETURN public.workshop_bay_minute_open_570(p_at, p_bay_id); END IF;
 SELECT f.bay_number, f.code INTO bay, code FROM public.workshop_bay_stage_554(p_bay_id) f;$n$,
 $o$BEGIN
 SELECT f.bay_number, f.code INTO bay, code FROM public.workshop_bay_stage_554(p_bay_id) f;$o$,
 'ca85b70cf2728a523a6e8d4231a19b08');

UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='c43afa5c1312392aa5d3666a8aa7cf65', release='20261020015824', note='restored by r577 down', updated_at=now()
 WHERE signature='pdc_bus_private.add_minutes(timestamp with time zone,integer,uuid)' AND release='r577';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='8067dd22688d7b93d90c9c03eabfbe7d', release='r424', note='restored by r577 down', updated_at=now()
 WHERE signature='pdc_bay_seq_private.end_at(timestamp with time zone,integer,uuid)' AND release='r577';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='6d2cdc4cb26bb37794c6998b206f6e0c', release='r424', note='restored by r577 down', updated_at=now()
 WHERE signature='pdc_bay_seq_private.next_start(timestamp with time zone,uuid)' AND release='r577';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='b7b98893bfc7a04b39330ca689f8f1b1', release='r469', note='restored by r577 down', updated_at=now()
 WHERE signature='pdc_cascade_private.target_end_469(uuid,uuid,timestamp with time zone,integer)' AND release='r577';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='e3602ba6f9d5973deea4eef09f5077c0', release='r469', note='restored by r577 down', updated_at=now()
 WHERE signature='pdc_cascade_private.overlap_chain_469(uuid[],timestamp with time zone)' AND release='r577';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='83a2c8d5ff85b5a295343e5f3ef66ded', release='r559', note='restored by r577 down', updated_at=now()
 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)' AND release='r577';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='bc237d9f466c45a086c251ec8c3071a7', release='r542', note='restored by r577 down', updated_at=now()
 WHERE signature='public.workshop_capacity_plan(text,uuid,integer,timestamp with time zone)' AND release='r577';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='90fc0d4727d827db53c308ff9dfa8bcd', release='r450', note='restored by r577 down', updated_at=now()
 WHERE signature='public.book_all_vehicle_stations(uuid,integer)' AND release='r577';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='ae08aa9b0dc99e7c93b1710efdcb5070', release='r548', note='restored by r577 down', updated_at=now()
 WHERE signature='public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,integer,public.workshop_booking_status,uuid,boolean)' AND release='r577';

DELETE FROM pdc_ops.regression_checks WHERE check_name='bay_manager_hours_570' AND fault_id='F191' AND sort_order=349 AND added_in='r577';

DROP FUNCTION IF EXISTS public.set_workshop_bay_hours_570(uuid, integer, jsonb, text);
DROP FUNCTION IF EXISTS public.list_workshop_bay_hours_570();
DROP FUNCTION IF EXISTS public.workshop_bay_hours_outside_570(uuid[]);
DROP FUNCTION IF EXISTS public.workshop_bay_hours_normalize_570(jsonb);
DROP FUNCTION IF EXISTS public.workshop_bay_station_default_570(uuid);
DROP FUNCTION IF EXISTS public.workshop_bay_station_key_570(uuid);
DROP FUNCTION IF EXISTS public.workshop_bay_minutes_between_570(timestamptz, timestamptz, uuid);
DROP FUNCTION IF EXISTS public.workshop_bay_add_minutes_570(timestamptz, integer, uuid);
DROP FUNCTION IF EXISTS public.workshop_bay_next_minute_570(timestamptz, uuid);
DROP FUNCTION IF EXISTS public.workshop_bay_minute_open_570(timestamptz, uuid);
DROP FUNCTION IF EXISTS public.workshop_bay_segments_570(uuid, date);
DROP FUNCTION IF EXISTS public.workshop_bay_date_closed_570(date, boolean);
DROP FUNCTION IF EXISTS public.workshop_bay_dow_key_570(timestamptz);
DROP FUNCTION IF EXISTS public.workshop_bay_has_hours_570(uuid);
DROP FUNCTION IF EXISTS public.workshop_bay_hours_blob_570();
DROP TABLE IF EXISTS public.workshop_bay_work_hours_570;

DO $z$ BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r577 down: pin count changed'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r577') THEN RAISE EXCEPTION 'r577 down: an r577 pin remains'; END IF;
 IF to_regclass('public.workshop_bay_work_hours_570') IS NOT NULL THEN RAISE EXCEPTION 'r577 down: table remains'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_pdc.workshop_clock_tick(boolean,timestamptz)')) IS DISTINCT FROM 'eb25ab44d4d007d3b749bd7bc5e56abc' THEN RAISE EXCEPTION 'r577 down: department 135 clock moved'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_bus.add_minutes(timestamptz,integer,uuid)')) IS DISTINCT FROM '832bf8be742c16b86f937fa9579ee056' THEN RAISE EXCEPTION 'r577 down: department 135 bus add moved'; END IF;
END $z$;
