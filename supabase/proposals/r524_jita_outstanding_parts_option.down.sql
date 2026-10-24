-- r524 (F138) OPTION undo. Do not apply unless r524_jita_outstanding_parts_option.sql was applied.
-- Staging cdsmnqxtyyoeoznmbidd only. Puts the audited parts rows and PARTS work items back,
-- restores the r518 tick body, and drops the option audit.
-- Up function md5 1e6833c19f876a1abddb3c26aa90a2aa. Down function md5 d39a7051efd9669c6eda97437150feab.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r524 option undo: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r524 option undo: staging only'; END IF;
 IF to_regclass('pdc_ops.r524_outstanding_parts_option_audit') IS NULL THEN RAISE EXCEPTION 'r524 option undo: audit missing'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.tick_parts_jita_from_navision_518(uuid)'::regprocedure) IS DISTINCT FROM '1e6833c19f876a1abddb3c26aa90a2aa' THEN RAISE EXCEPTION 'r524 option undo: tick function is not the option body'; END IF;
 IF (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.tick_parts_jita_from_navision_518(uuid)') IS DISTINCT FROM '1e6833c19f876a1abddb3c26aa90a2aa' THEN RAISE EXCEPTION 'r524 option undo: pin is not the option md5'; END IF;
 IF EXISTS (
    SELECT 1 FROM pdc_ops.r524_outstanding_parts_option_audit a
    JOIN public.vehicle_parts_updates p ON p.vehicle_id = a.vehicle_id OR p.id = (a.parts_row->>'id')::uuid
 ) THEN RAISE EXCEPTION 'r524 option undo: a parts row already exists for an audited vehicle'; END IF;
 PERFORM set_config('pdc.r524_pins', (SELECT count(*)::text FROM pdc_ops.expected_function_md5), true);
 PERFORM set_config('pdc.r524_n', (SELECT count(*)::text FROM pdc_ops.r524_outstanding_parts_option_audit), true);
END $g$;

INSERT INTO public.vehicle_parts_updates
SELECT r.*
FROM pdc_ops.r524_outstanding_parts_option_audit a
CROSS JOIN LATERAL jsonb_populate_record(NULL::public.vehicle_parts_updates, a.parts_row) r
WHERE NOT EXISTS (
  SELECT 1 FROM public.vehicle_parts_updates p
  WHERE p.vehicle_id = a.vehicle_id OR p.id = (a.parts_row->>'id')::uuid
);

UPDATE public.vehicle_work_items w
SET required = (a.work_row->>'required')::boolean,
    completed = (a.work_row->>'completed')::boolean,
    completed_at = nullif(a.work_row->>'completed_at', '')::timestamptz,
    completed_by = nullif(a.work_row->>'completed_by', '')::uuid,
    notes = a.work_row->>'notes',
    updated_at = coalesce(nullif(a.work_row->>'updated_at', '')::timestamptz, w.updated_at)
FROM pdc_ops.r524_outstanding_parts_option_audit a
WHERE w.id = (a.work_row->>'id')::uuid
  AND w.vehicle_id = a.vehicle_id
  AND w.work_key = 'PARTS'
  AND w.completed IS NOT TRUE
  AND w.required IS NOT TRUE
  AND w.notes IS NULL;

CREATE OR REPLACE FUNCTION public.tick_parts_jita_from_navision_518(p_vehicle_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog
AS $r518tick$
DECLARE
  v_matches int;
  v_ok boolean;
  v_number text;
  v_parts public.vehicle_parts_updates%ROWTYPE;
  v_work public.vehicle_work_items%ROWTYPE;
  v_had_parts boolean := false;
  v_had_work boolean := false;
  v_inserted_parts boolean := false;
  v_inserted_work boolean := false;
  v_changed boolean := false;
  v_new_parts_id uuid;
  v_new_work_id uuid;
  v_n int;
  v_note text := 'r518: Navision JITA number station tick';
BEGIN
  IF p_vehicle_id IS NULL THEN RETURN false; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.vehicles v
    WHERE v.id = p_vehicle_id
      AND v.deleted_at IS NULL
      AND v.board_purged_at IS NULL
      AND v.visible_on_board
      AND v.lifecycle_state::text = 'active'
      AND NOT EXISTS (
        SELECT 1 FROM public.pdc_overnight_synthetic_fleet_registry_363 r
        WHERE r.vehicle_id = v.id
      )
  ) THEN RETURN false; END IF;

  SELECT count(*)::int,
         coalesce(bool_and(s.good), false),
         max(s.number) FILTER (WHERE s.good)
    INTO v_matches, v_ok, v_number
  FROM (
    SELECT btrim(coalesce(n.normalized_data->>'jitQty', '')) AS number,
           (
             n.normalized_data->>'_navisionJitaNumberColumnPresent' = 'true'
             AND n.normalized_data->>'navisionJitaNumberAuthority' = 'validated-navision-import-v1'
             AND btrim(coalesce(n.normalized_data->>'jitQty', '')) <> ''
             AND btrim(n.normalized_data->>'jitQty') ~ '[0-9]'
             AND btrim(n.normalized_data->>'jitQty') !~ '^0+(\.0+)?$'
           ) AS good
    FROM public.navision_backend_records n
    JOIN public.vehicles v ON v.id = p_vehicle_id
    WHERE n.is_current
      AND n.record_status = 'current'
      AND n.source_system = 'microsoft_navision'
      AND n.canonical_vehicle_id = v.id
      AND upper(btrim(coalesce(n.normalized_data->>'stock', ''))) = upper(btrim(coalesce(v.stock_number, '')))
  ) s;
  IF v_matches IS DISTINCT FROM 1 OR NOT coalesce(v_ok, false) OR coalesce(v_number, '') = '' THEN
    RETURN false;
  END IF;

  SELECT * INTO v_parts
  FROM public.vehicle_parts_updates p
  WHERE p.vehicle_id = p_vehicle_id
  ORDER BY p.updated_at DESC, p.id DESC
  LIMIT 1;
  v_had_parts := FOUND;
  IF v_had_parts AND v_parts.parts_stoppage THEN RETURN false; END IF;

  SELECT * INTO v_work
  FROM public.vehicle_work_items w
  WHERE w.vehicle_id = p_vehicle_id
    AND w.work_key = 'PARTS';
  v_had_work := FOUND;
  IF v_had_work AND v_work.completed AND (NOT v_had_parts OR v_parts.parts_received) THEN
    RETURN false;
  END IF;

  IF NOT v_had_work THEN
    INSERT INTO public.vehicle_work_items (vehicle_id, work_key, required, completed, completed_at, notes)
    VALUES (p_vehicle_id, 'PARTS', true, true, clock_timestamp(), v_note)
    RETURNING id INTO v_new_work_id;
    v_inserted_work := FOUND;
    v_changed := v_changed OR v_inserted_work;
  ELSIF NOT v_work.completed THEN
    UPDATE public.vehicle_work_items w
    SET required = true,
        completed = true,
        completed_at = clock_timestamp(),
        notes = CASE
          WHEN w.notes IS NULL OR btrim(w.notes) = '' THEN v_note
          WHEN position(v_note IN w.notes) > 0 THEN w.notes
          ELSE w.notes || E'\n' || v_note
        END,
        updated_at = clock_timestamp()
    WHERE w.id = v_work.id
      AND w.vehicle_id = p_vehicle_id
      AND w.work_key = 'PARTS'
      AND w.completed IS NOT TRUE;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_changed := v_changed OR v_n > 0;
  END IF;

  IF NOT v_had_parts THEN
    INSERT INTO public.vehicle_parts_updates (vehicle_id, parts_required, parts_ordered, parts_received, parts_stoppage)
    SELECT p_vehicle_id, true, false, true, false
    WHERE NOT EXISTS (
      SELECT 1 FROM public.vehicle_parts_updates p WHERE p.vehicle_id = p_vehicle_id
    )
    RETURNING id INTO v_new_parts_id;
    v_inserted_parts := FOUND;
    v_changed := v_changed OR v_inserted_parts;
  ELSIF NOT v_parts.parts_received THEN
    UPDATE public.vehicle_parts_updates p
    SET parts_required = true,
        parts_received = true,
        updated_at = clock_timestamp()
    WHERE p.id = v_parts.id
      AND p.vehicle_id = p_vehicle_id
      AND p.parts_received IS NOT TRUE
      AND p.parts_stoppage IS NOT TRUE;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_changed := v_changed OR v_n > 0;
  END IF;

  IF NOT v_changed THEN RETURN false; END IF;
  INSERT INTO pdc_ops.r518_parts_jita_tick_audit (
    vehicle_id, had_parts_row, had_work_item, prev_parts, prev_work,
    inserted_parts_row, inserted_work_item, inserted_parts_id, inserted_work_id
  ) VALUES (
    p_vehicle_id, v_had_parts, v_had_work,
    CASE WHEN v_had_parts THEN to_jsonb(v_parts) ELSE NULL END,
    CASE WHEN v_had_work THEN to_jsonb(v_work) ELSE NULL END,
    v_inserted_parts, v_inserted_work, v_new_parts_id, v_new_work_id
  );
  RETURN true;
END
$r518tick$;

UPDATE pdc_ops.expected_function_md5
SET prosrc_md5 = 'd39a7051efd9669c6eda97437150feab',
    note = 'r518 (F132): Navision JITA number completes the Parts Jita station',
    updated_at = clock_timestamp()
WHERE signature = 'public.tick_parts_jita_from_navision_518(uuid)'
  AND release = 'r518'
  AND prosrc_md5 = '1e6833c19f876a1abddb3c26aa90a2aa';

DO $land$ DECLARE y record; v_n int; BEGIN
 IF (SELECT count(*) FROM public.vehicle_parts_updates p
     JOIN pdc_ops.r524_outstanding_parts_option_audit a ON a.vehicle_id = p.vehicle_id
     WHERE p.id = (a.parts_row->>'id')::uuid AND p.parts_received IS TRUE) IS DISTINCT FROM current_setting('pdc.r524_n')::int
  THEN RAISE EXCEPTION 'r524 option undo: parts rows not restored'; END IF;
 IF (SELECT count(*) FROM public.vehicle_work_items w
     JOIN pdc_ops.r524_outstanding_parts_option_audit a ON a.vehicle_id = w.vehicle_id
     WHERE w.id = (a.work_row->>'id')::uuid AND w.work_key = 'PARTS' AND w.completed IS TRUE
       AND w.notes = 'r518: Navision JITA number station tick') IS DISTINCT FROM current_setting('pdc.r524_n')::int
  THEN RAISE EXCEPTION 'r524 option undo: work items not restored'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.tick_parts_jita_from_navision_518(uuid)'::regprocedure) IS DISTINCT FROM 'd39a7051efd9669c6eda97437150feab' THEN RAISE EXCEPTION 'r524 option undo: tick md5 not restored'; END IF;
 IF (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.tick_parts_jita_from_navision_518(uuid)') IS DISTINCT FROM 'd39a7051efd9669c6eda97437150feab' THEN RAISE EXCEPTION 'r524 option undo: pin not restored'; END IF;
 IF (SELECT count(*)::text FROM pdc_ops.expected_function_md5) IS DISTINCT FROM current_setting('pdc.r524_pins') THEN RAISE EXCEPTION 'r524 option undo: pin count changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.set_parts_eta(text,text,integer,text,date,text,text,text,text,boolean,timestamp with time zone)')) IS DISTINCT FROM '88d31cbd6ca5ddd372e3143d5f8c013f' THEN RAISE EXCEPTION 'r524 option undo: set_parts_eta changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_imported_parts_flags_vehicle_20260912(uuid)'::regprocedure) IS DISTINCT FROM '79dcb7e2b2eb795efb9e0d7b020dbaaa' THEN RAISE EXCEPTION 'r524 option undo: imported parts flags changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_parts_flags_vehicle_20260911(uuid)'::regprocedure) IS DISTINCT FROM '6c828cb4ffdd7e0717bd5d9f50f4c764' THEN RAISE EXCEPTION 'r524 option undo: parts flags changed'; END IF;
 PERFORM set_config('search_path', 'pg_catalog', true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'navision_jita_station_tick_518') INTO y;
 IF y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r524 option undo: r518 check not OK: %', y.detail; END IF;
 PERFORM set_config('search_path', 'public, extensions', true);
END $land$;

DROP TABLE pdc_ops.r524_outstanding_parts_option_audit;
