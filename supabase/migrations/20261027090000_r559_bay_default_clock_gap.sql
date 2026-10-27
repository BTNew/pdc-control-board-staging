-- r559 (F173). Approved go-live 27 Oct 2026. Staging cdsmnqxtyyoeoznmbidd only. Production is not touched.
-- Next free after r558 / F172 / sort 333. This is r559 / F173 / sort 334.
-- Craig, 06:42 AWST 27 Oct: dropping Key 460 (stock 13071838, booking 26030b23) onto
-- Fitting bay 1 (PMB Bay 06, bay mechanic Chelsea Rees # 2) was refused because
-- Chelsea is booked on stock 12710966 (Key 411, booking 1d85ee5c) in Fitting bay 5
-- (PMB Bay 10). That booking is real. It was placed by close gaps at 11:09 AWST
-- 26 Oct for Mon 26 Oct 14:55 to Tue 27 Oct 14:16 (591 working minutes). The clock
-- then walked the window forward, about 15 minutes at a time, because a running
-- job's step delay was copied onto every later booking that shares the mechanic
-- even when that booking already starts after the running job's new end.
-- No booking row is rewritten. Key 411 stays. Pin count stays 241.
-- workshop_clock_tick moves in place from fa17068b106bbb9488c257e61d32e483 (r552).
-- workshop_move_booking is not pinned (prosrc was e72b96d1c9b3bf105ae975075f9b4434).
-- Department 135 is not edited.
-- Undo: supabase/rollbacks/20261027090000_r559_bay_default_clock_gap.down.sql

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r559: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r559: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r559: pin count is not 241'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) IS DISTINCT FROM 'fa17068b106bbb9488c257e61d32e483' THEN RAISE EXCEPTION 'r559: clock tick is not the r552 body'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_move_booking(uuid,integer,text,integer,timestamptz,integer,jsonb)')) IS DISTINCT FROM 'e72b96d1c9b3bf105ae975075f9b4434' THEN RAISE EXCEPTION 'r559: move body changed'; END IF;
 IF (SELECT proacl::text FROM pg_proc WHERE oid=to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) IS DISTINCT FROM '{postgres=X/postgres}' THEN RAISE EXCEPTION 'r559: clock tick acl changed'; END IF;
 IF (SELECT proacl::text FROM pg_proc WHERE oid=to_regprocedure('public.workshop_move_booking(uuid,integer,text,integer,timestamptz,integer,jsonb)')) IS DISTINCT FROM '{postgres=X/postgres,service_role=X/postgres}' THEN RAISE EXCEPTION 'r559: move acl changed'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=334 OR fault_id='F173' OR check_name='bay_default_clock_gap_559' OR added_in='r559') THEN RAISE EXCEPTION 'r559: sort 334 or F173 is taken'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='newvehiclebuild_pdc_route_558' AND fault_id='F172' AND sort_order=333 AND added_in='r558') THEN RAISE EXCEPTION 'r559: r558 / F172 sort 333 is not present'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE signature LIKE '%workshop_move_booking%') THEN RAISE EXCEPTION 'r559: move is already pinned'; END IF;
END $g$;

-- A predecessor delay is inherited only when that predecessor still covers this job's original start.
DO $clk$
DECLARE src text; newsrc text;
BEGIN
 SELECT prosrc INTO src FROM pg_proc WHERE oid=to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)');
 newsrc := replace(src, $old$    FOR predecessor IN SELECT * FROM pg_temp.clock_linked_plan x WHERE x.component_id=component.component_id AND x.ordinal<item.ordinal
     AND (x.bay_id=item.bay_id OR x.vehicle_id=item.vehicle_id OR x.technicians && item.technicians)
     AND (x.changed OR x.delay>0) ORDER BY x.ordinal LOOP
     delay:=greatest(delay,predecessor.delay);
     proposed:=greatest(proposed,predecessor.final_end+CASE WHEN predecessor.vehicle_id=item.vehicle_id THEN interval '1 hour' ELSE interval '0 minutes' END);
    END LOOP;$old$, $new$    FOR predecessor IN SELECT * FROM pg_temp.clock_linked_plan x WHERE x.component_id=component.component_id AND x.ordinal<item.ordinal
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
    END LOOP;$new$);
 IF newsrc IS NOT DISTINCT FROM src THEN RAISE EXCEPTION 'r559: clock gap pattern was not found'; END IF;
 IF length(src)-length(replace(src,'delay:=greatest(delay,predecessor.delay);','')) <> length('delay:=greatest(delay,predecessor.delay);') THEN RAISE EXCEPTION 'r559: clock delay copy is not unique'; END IF;
 EXECUTE format($f$CREATE OR REPLACE FUNCTION public.workshop_clock_tick(p_apply boolean DEFAULT true, p_now timestamp with time zone DEFAULT clock_timestamp()) RETURNS jsonb LANGUAGE plpgsql SET search_path TO 'pg_catalog', 'public' SET lock_timeout TO '3s' SET statement_timeout TO '120s' AS $tick559$%s$tick559$$f$, newsrc);
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) = 'fa17068b106bbb9488c257e61d32e483' THEN RAISE EXCEPTION 'r559: clock tick did not change'; END IF;
 IF (SELECT proacl::text FROM pg_proc WHERE oid=to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) IS DISTINCT FROM '{postgres=X/postgres}' THEN RAISE EXCEPTION 'r559: clock tick acl drifted'; END IF;
 IF (SELECT proconfig FROM pg_proc WHERE oid=to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) IS DISTINCT FROM ARRAY['search_path=pg_catalog, public','lock_timeout=3s','statement_timeout=120s']::text[] THEN RAISE EXCEPTION 'r559: clock tick settings drifted'; END IF;
END $clk$;

-- A bay default that is already booked does not refuse the whole drop.
DO $mv$
DECLARE src text; newsrc text;
BEGIN
 SELECT prosrc INTO src FROM pg_proc WHERE oid=to_regprocedure('public.workshop_move_booking(uuid,integer,text,integer,timestamptz,integer,jsonb)');
 newsrc := replace(src, $old$  v_technician_id uuid;$old$, $new$  v_technician_id uuid;
  v_bay_default_only boolean := false;$new$);
 newsrc := replace(newsrc, $old$    select default_technician_id into v_technician_id from public.workshop_bays where id=v_bay_id;
  end if;$old$, $new$    select default_technician_id into v_technician_id from public.workshop_bays where id=v_bay_id;
    v_bay_default_only := true;
  end if;$new$);
 newsrc := replace(newsrc, $old$  if v_technician_id is not null then
    v_conflict_id := public.workshop_find_technician_conflict(p_booking_id, v_technician_id, p_scheduled_start_at, v_end);
    if v_conflict_id is not null then
      return jsonb_build_object('ok', false, 'error', 'technician_overlap', 'conflict', public.workshop_conflict_payload(v_conflict_id, 'technician_overlap'));
    end if;
  end if;$old$, $new$  if v_technician_id is not null then
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
  end if;$new$);
 IF newsrc IS NOT DISTINCT FROM src THEN RAISE EXCEPTION 'r559: move pattern was not found'; END IF;
 IF position('v_bay_default_only' IN newsrc)=0 THEN RAISE EXCEPTION 'r559: bay default flag missing'; END IF;
 EXECUTE format($f$CREATE OR REPLACE FUNCTION public.workshop_move_booking(p_booking_id uuid, p_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer DEFAULT NULL::integer, p_metadata jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $move559$%s$move559$$f$, newsrc);
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_move_booking(uuid,integer,text,integer,timestamptz,integer,jsonb)')) = 'e72b96d1c9b3bf105ae975075f9b4434' THEN RAISE EXCEPTION 'r559: move did not change'; END IF;
 IF (SELECT prosecdef FROM pg_proc WHERE oid=to_regprocedure('public.workshop_move_booking(uuid,integer,text,integer,timestamptz,integer,jsonb)')) IS NOT TRUE THEN RAISE EXCEPTION 'r559: move lost security definer'; END IF;
 IF (SELECT proacl::text FROM pg_proc WHERE oid=to_regprocedure('public.workshop_move_booking(uuid,integer,text,integer,timestamptz,integer,jsonb)')) IS DISTINCT FROM '{postgres=X/postgres,service_role=X/postgres}' THEN RAISE EXCEPTION 'r559: move acl drifted'; END IF;
END $mv$;

UPDATE pdc_ops.expected_function_md5 SET
 prosrc_md5=(SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')),
 release='r559',
 note='r559: a running step does not walk a later booking that already starts after it (was fa17068b106bbb9488c257e61d32e483, r552)',
 updated_at=now()
 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)' AND prosrc_md5='fa17068b106bbb9488c257e61d32e483' AND release='r552';

UPDATE pdc_ops.regression_checks SET check_sql=replace(check_sql, 'release=''r552''', 'release=''r559''')
 WHERE check_name IN ('clock_ticks_recent','clock_tick_resaves_per_tick') AND check_sql LIKE '%release=''r552''%';

UPDATE pdc_ops.regression_checks SET check_sql=replace(check_sql, 'fa17068b106bbb9488c257e61d32e483', (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')))
 WHERE check_name IN ('schedule_stale_version_window_552','read_once_snapshots_554') AND check_sql LIKE '%fa17068b106bbb9488c257e61d32e483%';

INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in)
VALUES ('bay_default_clock_gap_559','F173','A running step does not walk a later booking across a gap, and a busy bay default does not refuse the bay.',
$chk559$
SELECT
 pins.n=241
 AND tick_pin.release='r559'
 AND tick_pin.prosrc_md5=pg_catalog.md5(tick.prosrc)
 AND pg_catalog.strpos(tick.prosrc,'r559 (F173)')>0
 AND pg_catalog.strpos(tick.prosrc,'predecessor.final_end > item.original_start OR')>0
 AND pg_catalog.strpos(tick.prosrc, E'LOOP\n     delay:=greatest(delay,predecessor.delay);')=0
 AND pg_catalog.strpos(move.prosrc,'v_bay_default_only')>0
 AND pg_catalog.strpos(move.prosrc,'technician_overlap')>0
 AND NOT EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 e WHERE e.signature LIKE '%workshop_move_booking%')
 AND pg_catalog.strpos(recent.check_sql,'release=''r559''')>0
 AND pg_catalog.strpos(resave.check_sql,'release=''r559''')>0
 AND pg_catalog.strpos(sched.check_sql,tick_pin.prosrc_md5)>0
 AND pg_catalog.strpos(snap.check_sql,tick_pin.prosrc_md5)>0
 AND NOT (pg_catalog.timestamptz '2026-10-26 06:55:00+00' > pg_catalog.timestamptz '2026-10-27 02:00:00+00')
 AND (pg_catalog.timestamptz '2026-10-27 06:16:00+00' > pg_catalog.timestamptz '2026-10-27 02:00:00+00')
 AND coalesce((SELECT b.default_duration_minutes FROM public.workshop_bookings b WHERE b.id='1d85ee5c-d1a7-4d63-8be9-c6b8b9bcbec7' AND b.deleted_at IS NULL),591)<=591
 AND (
   (SELECT b.status FROM public.workshop_bookings b WHERE b.id='1d85ee5c-d1a7-4d63-8be9-c6b8b9bcbec7' AND b.deleted_at IS NULL) NOT IN ('queued','planned','started','stoppage')
   OR NOT EXISTS (SELECT 1 FROM public.workshop_booking_assignments a WHERE a.booking_id='1d85ee5c-d1a7-4d63-8be9-c6b8b9bcbec7' AND a.released_at IS NULL AND a.technician_id='f175c2aa-5b0e-4f5c-83f6-eca0df573bff')
   OR public.workshop_find_technician_conflict('26030b23-7d53-402c-9cdc-46abe5e89832','f175c2aa-5b0e-4f5c-83f6-eca0df573bff',k411.scheduled_start_at,k411.scheduled_end_at)='1d85ee5c-d1a7-4d63-8be9-c6b8b9bcbec7'
 ) AS ok,
 'tick '||tick_pin.prosrc_md5||' move '||pg_catalog.md5(move.prosrc)
 ||' stock 12710966 duration '||coalesce((SELECT b.default_duration_minutes::text FROM public.workshop_bookings b WHERE b.id='1d85ee5c-d1a7-4d63-8be9-c6b8b9bcbec7'),'gone')
 ||' gap-before-10:00 '||(NOT (pg_catalog.timestamptz '2026-10-26 06:55:00+00' > pg_catalog.timestamptz '2026-10-27 02:00:00+00'))::text AS detail
FROM (SELECT count(*) n FROM pdc_ops.expected_function_md5) pins
CROSS JOIN (SELECT prosrc_md5, release FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)') tick_pin
CROSS JOIN (SELECT prosrc FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) tick
CROSS JOIN (SELECT prosrc FROM pg_catalog.pg_proc WHERE oid=pg_catalog.to_regprocedure('public.workshop_move_booking(uuid,integer,text,integer,timestamptz,integer,jsonb)')) move
CROSS JOIN (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='clock_ticks_recent') recent
CROSS JOIN (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='clock_tick_resaves_per_tick') resave
CROSS JOIN (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='schedule_stale_version_window_552') sched
CROSS JOIN (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='read_once_snapshots_554') snap
CROSS JOIN (SELECT scheduled_start_at, scheduled_end_at FROM public.workshop_bookings WHERE id='1d85ee5c-d1a7-4d63-8be9-c6b8b9bcbec7') k411
$chk559$, true, 334, 'r559');

DO $z$ BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r559: pin count changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r559')<>1 THEN RAISE EXCEPTION 'r559: expected one pin to move'; END IF;
 IF (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)')
    IS DISTINCT FROM (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_clock_tick(boolean,timestamptz)')) THEN RAISE EXCEPTION 'r559: tick pin does not match'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='clock_ticks_recent' AND check_sql LIKE '%release=''r559''%') THEN RAISE EXCEPTION 'r559: clock_ticks_recent still names r552'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name IN ('schedule_stale_version_window_552','read_once_snapshots_554') AND check_sql LIKE '%fa17068b106bbb9488c257e61d32e483%') THEN RAISE EXCEPTION 'r559: an old tick md5 is still in a check'; END IF;
END $z$;
