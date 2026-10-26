-- r559 (F173) undo. Staging cdsmnqxtyyoeoznmbidd only. Production is not a target.
-- Restores the r552 clock tick and the previous move body. Does not rewrite booking rows.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r559 undo: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r559 undo: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r559 undo: pin count is not 241'; END IF;
 IF (SELECT release FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)') IS DISTINCT FROM 'r559' THEN RAISE EXCEPTION 'r559 undo: tick pin is not r559'; END IF;
 IF (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)')
    IS DISTINCT FROM (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) THEN RAISE EXCEPTION 'r559 undo: tick pin does not match the live body'; END IF;
 IF position('v_bay_default_only' IN (SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('public.workshop_move_booking(uuid,integer,text,integer,timestamptz,integer,jsonb)')))=0 THEN RAISE EXCEPTION 'r559 undo: move is not the r559 body'; END IF;
END $g$;

UPDATE pdc_ops.regression_checks SET check_sql=replace(check_sql,
 (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)'),
 'fa17068b106bbb9488c257e61d32e483')
 WHERE check_name IN ('schedule_stale_version_window_552','read_once_snapshots_554')
 AND check_sql LIKE '%'||(SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)')||'%';

UPDATE pdc_ops.regression_checks SET check_sql=replace(check_sql, 'release=''r559''', 'release=''r552''')
 WHERE check_name IN ('clock_ticks_recent','clock_tick_resaves_per_tick') AND check_sql LIKE '%release=''r559''%';

DELETE FROM pdc_ops.regression_checks WHERE check_name='bay_default_clock_gap_559' AND fault_id='F173' AND added_in='r559' AND sort_order=334;

DO $clk$
DECLARE src text; newsrc text;
BEGIN
 SELECT prosrc INTO src FROM pg_proc WHERE oid=to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)');
 newsrc := replace(src, $old$    FOR predecessor IN SELECT * FROM pg_temp.clock_linked_plan x WHERE x.component_id=component.component_id AND x.ordinal<item.ordinal
     AND (x.bay_id=item.bay_id OR x.vehicle_id=item.vehicle_id OR x.technicians && item.technicians)
     AND (x.changed OR x.delay>0) ORDER BY x.ordinal LOOP
     -- r559 (F173): copy a predecessor delay only when its new end still
     -- covers this job original start. A gap stays a gap. Stock 12710966 was
     -- walked forward because a running step was added onto later bookings
     -- that share the mechanic and already start after that step.
     -- The cover test is not a CASE expression: PL/pgSQL treats END as the
     -- end of the IF.
     IF predecessor.final_end > item.original_start OR (predecessor.vehicle_id=item.vehicle_id AND predecessor.final_end + interval '1 hour' > item.original_start) THEN
      delay:=greatest(delay,predecessor.delay);
      proposed:=greatest(proposed,predecessor.final_end+CASE WHEN predecessor.vehicle_id=item.vehicle_id THEN interval '1 hour' ELSE interval '0 minutes' END);
     END IF;
    END LOOP;$old$, $new$    FOR predecessor IN SELECT * FROM pg_temp.clock_linked_plan x WHERE x.component_id=component.component_id AND x.ordinal<item.ordinal
     AND (x.bay_id=item.bay_id OR x.vehicle_id=item.vehicle_id OR x.technicians && item.technicians)
     AND (x.changed OR x.delay>0) ORDER BY x.ordinal LOOP
     delay:=greatest(delay,predecessor.delay);
     proposed:=greatest(proposed,predecessor.final_end+CASE WHEN predecessor.vehicle_id=item.vehicle_id THEN interval '1 hour' ELSE interval '0 minutes' END);
    END LOOP;$new$);
 IF newsrc IS NOT DISTINCT FROM src THEN RAISE EXCEPTION 'r559 undo: clock pattern was not found'; END IF;
 EXECUTE format($f$CREATE OR REPLACE FUNCTION public.workshop_clock_tick(p_apply boolean DEFAULT true, p_now timestamp with time zone DEFAULT clock_timestamp()) RETURNS jsonb LANGUAGE plpgsql SET search_path TO 'pg_catalog', 'public' SET lock_timeout TO '3s' SET statement_timeout TO '120s' AS $tick552$%s$tick552$$f$, newsrc);
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) IS DISTINCT FROM 'fa17068b106bbb9488c257e61d32e483' THEN RAISE EXCEPTION 'r559 undo: clock tick did not return to r552'; END IF;
 IF (SELECT proacl::text FROM pg_proc WHERE oid=to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) IS DISTINCT FROM '{postgres=X/postgres}' THEN RAISE EXCEPTION 'r559 undo: clock tick acl drifted'; END IF;
END $clk$;

DO $mv$
DECLARE src text; newsrc text;
BEGIN
 SELECT prosrc INTO src FROM pg_proc WHERE oid=to_regprocedure('public.workshop_move_booking(uuid,integer,text,integer,timestamptz,integer,jsonb)');
 newsrc := replace(src, $old$  v_technician_id uuid;
  v_bay_default_only boolean := false;$old$, $new$  v_technician_id uuid;$new$);
 newsrc := replace(newsrc, $old$    select default_technician_id into v_technician_id from public.workshop_bays where id=v_bay_id;
    v_bay_default_only := true;
  end if;$old$, $new$    select default_technician_id into v_technician_id from public.workshop_bays where id=v_bay_id;
  end if;$new$);
 newsrc := replace(newsrc, $old$  if v_technician_id is not null then
    v_conflict_id := public.workshop_find_technician_conflict(p_booking_id, v_technician_id, p_scheduled_start_at, v_end);
    if v_conflict_id is not null then
      -- r559 (F173): the bay default is a preference. When that mechanic is
      -- already booked, save the bay booking with no technician. A technician
      -- who was chosen on purpose still conflicts.
      if v_bay_default_only then
        v_technician_id := null;
        v_conflict_id := null;
      else
        return jsonb_build_object('ok', false, 'error', 'technician_overlap', 'conflict', public.workshop_conflict_payload(v_conflict_id, 'technician_overlap'));
      end if;
    end if;
  end if;$old$, $new$  if v_technician_id is not null then
    v_conflict_id := public.workshop_find_technician_conflict(p_booking_id, v_technician_id, p_scheduled_start_at, v_end);
    if v_conflict_id is not null then
      return jsonb_build_object('ok', false, 'error', 'technician_overlap', 'conflict', public.workshop_conflict_payload(v_conflict_id, 'technician_overlap'));
    end if;
  end if;$new$);
 IF position('v_bay_default_only' IN newsrc)>0 THEN RAISE EXCEPTION 'r559 undo: bay default flag still present'; END IF;
 EXECUTE format($f$CREATE OR REPLACE FUNCTION public.workshop_move_booking(p_booking_id uuid, p_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer DEFAULT NULL::integer, p_metadata jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $move559undo$%s$move559undo$$f$, newsrc);
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_move_booking(uuid,integer,text,integer,timestamptz,integer,jsonb)')) IS DISTINCT FROM 'e72b96d1c9b3bf105ae975075f9b4434' THEN RAISE EXCEPTION 'r559 undo: move did not return to the previous body'; END IF;
 IF (SELECT prosecdef FROM pg_proc WHERE oid=to_regprocedure('public.workshop_move_booking(uuid,integer,text,integer,timestamptz,integer,jsonb)')) IS NOT TRUE THEN RAISE EXCEPTION 'r559 undo: move lost security definer'; END IF;
 IF (SELECT proacl::text FROM pg_proc WHERE oid=to_regprocedure('public.workshop_move_booking(uuid,integer,text,integer,timestamptz,integer,jsonb)')) IS DISTINCT FROM '{postgres=X/postgres,service_role=X/postgres}' THEN RAISE EXCEPTION 'r559 undo: move acl drifted'; END IF;
END $mv$;

UPDATE pdc_ops.expected_function_md5 SET
 prosrc_md5='fa17068b106bbb9488c257e61d32e483',
 release='r552',
 note='r552: running end steps 15 minutes; a one-minute clock creep does not re-save the chain (was 0aaaa15690ca286ed0db87fc72271d5a, r452)',
 updated_at=now()
 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)' AND release='r559';

DO $z$ BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r559 undo: pin count changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r559')<>0 THEN RAISE EXCEPTION 'r559 undo: r559 pin remains'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='bay_default_clock_gap_559' OR fault_id='F173' OR added_in='r559') THEN RAISE EXCEPTION 'r559 undo: check remains'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='clock_ticks_recent' AND check_sql LIKE '%release=''r552''%') THEN RAISE EXCEPTION 'r559 undo: clock_ticks_recent was not restored'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name IN ('schedule_stale_version_window_552','read_once_snapshots_554') AND check_sql NOT LIKE '%fa17068b106bbb9488c257e61d32e483%') THEN RAISE EXCEPTION 'r559 undo: tick md5 was not restored in a check'; END IF;
END $z$;
