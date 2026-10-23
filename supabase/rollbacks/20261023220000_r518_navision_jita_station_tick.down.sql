-- r518 undo (F132). Staging cdsmnqxtyyoeoznmbidd only. Only if 20261023220000_r518_navision_jita_station_tick.sql was applied.
-- Drops the trigger first so the reverse cannot tick again. Restores audited Parts rows.
-- public.pdc_772_protect_work_item_delete blocks DELETE on vehicle_work_items, so an inserted PARTS row is cleared
-- (completed false, required false, notes cleared) and left in place. parts_completed then reads false, as it did when the row was absent.
-- A parts row is put back only when ordered and the email date are still the values from the tick.
-- Does not change set_parts_eta or public.pdc_jita_eta.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r518 undo: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r518') <> 2 THEN RAISE EXCEPTION 'r518 undo: r518 pin count is not 2'; END IF;
 IF EXISTS (
    SELECT 1 FROM pdc_ops.expected_function_md5 p
    WHERE p.release = 'r518'
      AND p.prosrc_md5 IS DISTINCT FROM (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure(p.signature))
 ) THEN RAISE EXCEPTION 'r518 undo: a function drifted from its pin'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.set_parts_eta(text,text,integer,text,date,text,text,text,text,boolean,timestamp with time zone)')) IS DISTINCT FROM '88d31cbd6ca5ddd372e3143d5f8c013f'
  THEN RAISE EXCEPTION 'r518 undo: set_parts_eta is not the r436 body'; END IF;
END $g$;

DROP TRIGGER tick_parts_jita_from_navision_518 ON public.navision_backend_records;

UPDATE public.vehicle_work_items w
SET completed = coalesce((a.prev_work->>'completed')::boolean, false),
    completed_at = nullif(a.prev_work->>'completed_at', '')::timestamptz,
    completed_by = nullif(a.prev_work->>'completed_by', '')::uuid,
    notes = a.prev_work->>'notes',
    required = coalesce((a.prev_work->>'required')::boolean, w.required),
    updated_at = clock_timestamp()
FROM pdc_ops.r518_parts_jita_tick_audit a
WHERE NOT a.inserted_work_item
  AND a.prev_work IS NOT NULL
  AND w.id = (a.prev_work->>'id')::uuid
  AND w.vehicle_id = a.vehicle_id
  AND w.work_key = 'PARTS'
  AND position('r518: Navision JITA number station tick' IN coalesce(w.notes, '')) > 0
  AND w.completed IS TRUE
  AND coalesce((a.prev_work->>'completed')::boolean, false) IS NOT TRUE;

UPDATE public.vehicle_work_items w
SET completed = false,
    completed_at = NULL,
    completed_by = NULL,
    notes = NULL,
    required = false,
    updated_at = clock_timestamp()
FROM pdc_ops.r518_parts_jita_tick_audit a
WHERE a.inserted_work_item
  AND w.id = a.inserted_work_id
  AND w.vehicle_id = a.vehicle_id
  AND w.work_key = 'PARTS'
  AND w.notes = 'r518: Navision JITA number station tick'
  AND w.completed IS TRUE;

UPDATE public.vehicle_parts_updates p
SET parts_received = coalesce((a.prev_parts->>'parts_received')::boolean, false),
    parts_required = coalesce((a.prev_parts->>'parts_required')::boolean, p.parts_required),
    updated_at = clock_timestamp()
FROM pdc_ops.r518_parts_jita_tick_audit a
WHERE NOT a.inserted_parts_row
  AND a.prev_parts IS NOT NULL
  AND p.id = (a.prev_parts->>'id')::uuid
  AND p.vehicle_id = a.vehicle_id
  AND p.parts_received IS TRUE
  AND coalesce((a.prev_parts->>'parts_received')::boolean, false) IS NOT TRUE
  AND p.parts_ordered IS NOT DISTINCT FROM coalesce((a.prev_parts->>'parts_ordered')::boolean, false)
  AND p.worst_eta IS NOT DISTINCT FROM nullif(a.prev_parts->>'worst_eta', '')::date
  AND p.parts_stoppage IS NOT TRUE
  AND NOT (p.parts_ordered AND p.worst_eta IS NULL);

DELETE FROM public.vehicle_parts_updates p
USING pdc_ops.r518_parts_jita_tick_audit a
WHERE a.inserted_parts_row
  AND p.id = a.inserted_parts_id
  AND p.vehicle_id = a.vehicle_id
  AND p.parts_received IS TRUE
  AND p.parts_ordered IS FALSE
  AND p.worst_eta IS NULL
  AND p.parts_stoppage IS FALSE
  AND NOT EXISTS (
    SELECT 1 FROM public.vehicle_parts_updates newer
    WHERE newer.vehicle_id = p.vehicle_id
      AND (newer.updated_at, newer.id) > (p.updated_at, p.id)
  );

DO $g$ DECLARE n int; BEGIN
 SELECT count(*) INTO n
 FROM pdc_ops.r518_parts_jita_tick_audit a
 JOIN public.vehicle_parts_updates p ON p.id = (a.prev_parts->>'id')::uuid AND p.vehicle_id = a.vehicle_id
 WHERE NOT a.inserted_parts_row
   AND coalesce((a.prev_parts->>'parts_received')::boolean, false) IS NOT TRUE
   AND p.parts_received IS TRUE;
 IF n > 0 THEN RAISE EXCEPTION 'r518 undo: % parts rows still received; ordered, the email date, or stoppage changed after the tick', n; END IF;
 SELECT count(*) INTO n
 FROM pdc_ops.r518_parts_jita_tick_audit a
 JOIN public.vehicle_parts_updates p ON p.id = a.inserted_parts_id AND p.vehicle_id = a.vehicle_id
 WHERE a.inserted_parts_row
   AND p.parts_received IS TRUE
   AND NOT EXISTS (
     SELECT 1 FROM public.vehicle_parts_updates newer
     WHERE newer.vehicle_id = p.vehicle_id
       AND (newer.updated_at, newer.id) > (p.updated_at, p.id)
   );
 IF n > 0 THEN RAISE EXCEPTION 'r518 undo: % inserted parts rows are still the latest received row', n; END IF;
 SELECT count(*) INTO n
 FROM pdc_ops.r518_parts_jita_tick_audit a
 JOIN public.vehicle_work_items w ON w.vehicle_id = a.vehicle_id AND w.work_key = 'PARTS'
 WHERE w.completed IS TRUE
   AND position('r518: Navision JITA number station tick' IN coalesce(w.notes, '')) > 0;
 IF n > 0 THEN RAISE EXCEPTION 'r518 undo: % PARTS work items still carry the r518 tick', n; END IF;
END $g$;

DROP FUNCTION public.tick_parts_jita_from_navision_518_trg();
DROP FUNCTION public.tick_parts_jita_from_navision_518(uuid);

DELETE FROM pdc_ops.regression_checks
WHERE check_name = 'navision_jita_station_tick_518' AND added_in = 'r518' AND fault_id = 'F132';
DELETE FROM pdc_ops.expected_function_md5
WHERE release = 'r518'
  AND signature IN (
    'public.tick_parts_jita_from_navision_518(uuid)',
    'public.tick_parts_jita_from_navision_518_trg()'
  );

DROP TABLE pdc_ops.r518_parts_jita_tick_audit;

DO $g$ BEGIN
 IF to_regprocedure('public.tick_parts_jita_from_navision_518(uuid)') IS NOT NULL
    OR to_regprocedure('public.tick_parts_jita_from_navision_518_trg()') IS NOT NULL
    OR to_regclass('pdc_ops.r518_parts_jita_tick_audit') IS NOT NULL
    OR EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='tick_parts_jita_from_navision_518' AND NOT tgisinternal)
    OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r518')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='navision_jita_station_tick_518' OR fault_id='F132')
  THEN RAISE EXCEPTION 'r518 undo: objects remain'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.set_parts_eta(text,text,integer,text,date,text,text,text,text,boolean,timestamp with time zone)')) IS DISTINCT FROM '88d31cbd6ca5ddd372e3143d5f8c013f'
  THEN RAISE EXCEPTION 'r518 undo: set_parts_eta changed'; END IF;
END $g$;
