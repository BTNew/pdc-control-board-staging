-- r518 (F132): a verified Navision JITA number ticks Parts Jita. Craig approved go-live 23 Oct 2026.
-- Staging cdsmnqxtyyoeoznmbidd only. Not applied by this commit.
-- The tick source is navision_backend_records.normalized_data.jitQty with authority validated-navision-import-v1.
-- public.pdc_jita_eta (r516 Planned Delivery Date) is not read. public.set_parts_eta is not called or changed.
-- The email parts date column is not written. A blank, zero or non-numeric number does not tick, and a later blank number does not untick.
-- Undo: supabase/rollbacks/20261023220000_r518_navision_jita_station_tick.down.sql
-- Dry run on staging 23 Oct 2026 (read only, not applied): 261 live board vehicles would be written;
-- 12 live vehicles have a current JITA ETA and no verified number and would be left as they are; parts stoppage among the 261 was 0.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r518: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r518: staging only'; END IF;
 PERFORM set_config('pdc.r518_tick',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 PERFORM set_config('pdc.r518_frc',(SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure),true);
 PERFORM set_config('pdc.r518_pins',(SELECT count(*) FROM pdc_ops.expected_function_md5)::text,true);
 PERFORM set_config('pdc.r518_parts',(SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.set_parts_eta(text,text,integer,text,date,text,text,text,text,boolean,timestamp with time zone)')),true);
 IF current_setting('pdc.r518_tick') IS DISTINCT FROM (SELECT prosrc_md5 FROM pdc_ops.expected_function_md5 WHERE signature='public.workshop_clock_tick(boolean,timestamp with time zone)') THEN RAISE EXCEPTION 'r518: clock tick does not match its pin'; END IF;
 IF current_setting('pdc.r518_parts') IS DISTINCT FROM '88d31cbd6ca5ddd372e3143d5f8c013f' THEN RAISE EXCEPTION 'r518: set_parts_eta is not the r436 body'; END IF;
 IF current_setting('pdc.r518_pins') IS DISTINCT FROM '228' THEN RAISE EXCEPTION 'r518: pin count is not 228'; END IF;
 IF to_regprocedure('public.tick_parts_jita_from_navision_518(uuid)') IS NOT NULL
    OR to_regprocedure('public.tick_parts_jita_from_navision_518_trg()') IS NOT NULL
    OR to_regclass('pdc_ops.r518_parts_jita_tick_audit') IS NOT NULL
    OR EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='tick_parts_jita_from_navision_518' AND NOT tgisinternal)
    OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r518')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='navision_jita_station_tick_518' OR added_in='r518' OR fault_id='F132' OR sort_order=304)
  THEN RAISE EXCEPTION 'r518: already applied or sort 304 / F132 taken'; END IF;
END $g$;

CREATE TABLE pdc_ops.r518_parts_jita_tick_audit (
  vehicle_id uuid PRIMARY KEY,
  had_parts_row boolean NOT NULL,
  had_work_item boolean NOT NULL,
  prev_parts jsonb,
  prev_work jsonb,
  inserted_parts_row boolean NOT NULL,
  inserted_work_item boolean NOT NULL,
  inserted_parts_id uuid,
  inserted_work_id uuid,
  at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE pdc_ops.r518_parts_jita_tick_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE pdc_ops.r518_parts_jita_tick_audit FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.tick_parts_jita_from_navision_518(p_vehicle_id uuid)
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

CREATE FUNCTION public.tick_parts_jita_from_navision_518_trg()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog
AS $r518trg$
BEGIN
  IF NEW.is_current AND NEW.canonical_vehicle_id IS NOT NULL THEN
    PERFORM public.tick_parts_jita_from_navision_518(NEW.canonical_vehicle_id);
  END IF;
  RETURN NULL;
END
$r518trg$;

REVOKE ALL ON FUNCTION public.tick_parts_jita_from_navision_518(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.tick_parts_jita_from_navision_518_trg() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.tick_parts_jita_from_navision_518_trg() TO service_role;

CREATE TRIGGER tick_parts_jita_from_navision_518
AFTER INSERT OR UPDATE OF normalized_data, is_current, canonical_vehicle_id, record_status, source_system
ON public.navision_backend_records
FOR EACH ROW
WHEN (NEW.is_current AND NEW.canonical_vehicle_id IS NOT NULL)
EXECUTE FUNCTION public.tick_parts_jita_from_navision_518_trg();

-- One pass over live board vehicles that already have a digit in jitQty. The function decides the tick.
-- As of 23 Oct 2026 that decision was 261 writes. Apply ticks whoever matches at apply time.
DO $backfill$
DECLARE
  v_id uuid;
  v_n int := 0;
BEGIN
  FOR v_id IN
    SELECT DISTINCT v.id
    FROM public.vehicles v
    JOIN public.navision_backend_records n
      ON n.canonical_vehicle_id = v.id
     AND n.is_current
     AND n.record_status = 'current'
     AND n.source_system = 'microsoft_navision'
     AND upper(btrim(coalesce(n.normalized_data->>'stock', ''))) = upper(btrim(coalesce(v.stock_number, '')))
    WHERE v.deleted_at IS NULL
      AND v.board_purged_at IS NULL
      AND v.visible_on_board
      AND v.lifecycle_state::text = 'active'
      AND NOT EXISTS (
        SELECT 1 FROM public.pdc_overnight_synthetic_fleet_registry_363 r WHERE r.vehicle_id = v.id
      )
      AND btrim(coalesce(n.normalized_data->>'jitQty', '')) ~ '[0-9]'
    ORDER BY v.id
  LOOP
    IF public.tick_parts_jita_from_navision_518(v_id) THEN v_n := v_n + 1; END IF;
  END LOOP;
  RAISE NOTICE 'r518 backfill wrote %', v_n;
END
$backfill$;

INSERT INTO pdc_ops.expected_function_md5 (signature, prosrc_md5, release, note, updated_at)
SELECT 'public.tick_parts_jita_from_navision_518(uuid)', md5(p.prosrc), 'r518',
       'r518 (F132): Navision JITA number completes the Parts Jita station', clock_timestamp()
FROM pg_proc p
WHERE p.oid = 'public.tick_parts_jita_from_navision_518(uuid)'::regprocedure
UNION ALL
SELECT 'public.tick_parts_jita_from_navision_518_trg()', md5(p.prosrc), 'r518',
       'r518 (F132): after a current Navision row is saved, tick Parts Jita when the number is verified', clock_timestamp()
FROM pg_proc p
WHERE p.oid = 'public.tick_parts_jita_from_navision_518_trg()'::regprocedure;

INSERT INTO pdc_ops.regression_checks (check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES
('navision_jita_station_tick_518', 'F132',
 'Parts Jita (r518): a verified Navision JITA number completes the station. The JITA planned-date table is not read. The email parts date writer is not called. Both new functions are pinned to their live bodies.',
 $chk$WITH pins AS (
  SELECT count(*) n, bool_and(p.prosrc_md5 = md5(f.prosrc)) match
  FROM pdc_ops.expected_function_md5 p
  JOIN pg_proc f ON f.oid = to_regprocedure(p.signature)
  WHERE p.release = 'r518'
), body AS (
  SELECT position('validated-navision-import-v1' IN prosrc) > 0 AS authority,
   position('pdc_jita_eta' IN prosrc) = 0 AS no_eta_table,
   position('worst_eta' IN prosrc) = 0 AS no_email_date,
   position('set_parts_eta' IN prosrc) = 0 AS no_email_writer,
   prosecdef
  FROM pg_proc WHERE oid = to_regprocedure('public.tick_parts_jita_from_navision_518(uuid)')
), trg AS (
  SELECT position('pdc_jita_eta' IN prosrc) = 0 AS no_eta_table, prosecdef
  FROM pg_proc WHERE oid = to_regprocedure('public.tick_parts_jita_from_navision_518_trg()')
), hook AS (
  SELECT count(*) n
  FROM pg_trigger t
  WHERE t.tgname = 'tick_parts_jita_from_navision_518'
    AND t.tgrelid = 'public.navision_backend_records'::regclass
    AND NOT t.tgisinternal
    AND t.tgenabled <> 'D'
), acl AS (
  SELECT bool_and(NOT has_function_privilege('anon', p.oid, 'EXECUTE')) no_anon,
   bool_and(NOT has_function_privilege('authenticated', p.oid, 'EXECUTE')) no_auth,
   bool_and(CASE WHEN p.oid = to_regprocedure('public.tick_parts_jita_from_navision_518(uuid)')
     THEN NOT has_function_privilege('service_role', p.oid, 'EXECUTE')
     ELSE has_function_privilege('service_role', p.oid, 'EXECUTE') END) svc_ok
  FROM pg_proc p
  WHERE p.oid IN (
    to_regprocedure('public.tick_parts_jita_from_navision_518(uuid)'),
    to_regprocedure('public.tick_parts_jita_from_navision_518_trg()'))
), aud AS (
  SELECT c.relrowsecurity rls,
   NOT has_table_privilege('anon', c.oid, 'SELECT')
   AND NOT has_table_privilege('authenticated', c.oid, 'SELECT')
   AND NOT has_table_privilege('service_role', c.oid, 'SELECT') closed
  FROM pg_class c WHERE c.oid = 'pdc_ops.r518_parts_jita_tick_audit'::regclass
), parts AS (
  SELECT md5(prosrc) = '88d31cbd6ca5ddd372e3143d5f8c013f' AS same
  FROM pg_proc WHERE oid = to_regprocedure('public.set_parts_eta(text,text,integer,text,date,text,text,text,text,boolean,timestamp with time zone)')
)
SELECT coalesce((SELECT n = 2 AND match FROM pins), false)
 AND coalesce((SELECT authority AND no_eta_table AND no_email_date AND no_email_writer AND prosecdef FROM body), false)
 AND coalesce((SELECT no_eta_table AND prosecdef FROM trg), false)
 AND coalesce((SELECT n = 1 FROM hook), false)
 AND coalesce((SELECT no_anon AND no_auth AND svc_ok FROM acl), false)
 AND coalesce((SELECT rls AND closed FROM aud), false)
 AND coalesce((SELECT same FROM parts), false) AS ok,
 'pins '||coalesce((SELECT n FROM pins), 0)||'/2 match '||coalesce((SELECT match FROM pins)::text, 'missing')
 ||'; authority '||coalesce((SELECT authority FROM body)::text, 'missing')
 ||'; email parts writer still r436 '||coalesce((SELECT same FROM parts)::text, 'missing') AS detail
$chk$, true, 304, 'r518');

DO $land$ DECLARE y record; BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release = 'r518') <> 2
    OR (SELECT count(*) FROM pdc_ops.expected_function_md5) <> current_setting('pdc.r518_pins')::int + 2
  THEN RAISE EXCEPTION 'r518: pins not as expected'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) IS DISTINCT FROM current_setting('pdc.r518_tick') THEN RAISE EXCEPTION 'r518: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'pdc_ops.fault_regression_check()'::regprocedure) IS DISTINCT FROM current_setting('pdc.r518_frc') THEN RAISE EXCEPTION 'r518: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('public.set_parts_eta(text,text,integer,text,date,text,text,text,text,boolean,timestamp with time zone)')) IS DISTINCT FROM '88d31cbd6ca5ddd372e3143d5f8c013f' THEN RAISE EXCEPTION 'r518: set_parts_eta changed'; END IF;
 PERFORM set_config('search_path', 'pg_catalog', true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'navision_jita_station_tick_518') INTO y;
 IF y.ok IS NOT TRUE THEN RAISE EXCEPTION 'r518: check not OK: %', y.detail; END IF;
 PERFORM set_config('search_path', 'public, extensions', true);
END $land$;
