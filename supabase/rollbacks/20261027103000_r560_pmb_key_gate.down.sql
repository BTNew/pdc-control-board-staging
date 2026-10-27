-- Undo r560 (F174). Staging only. Restores the r557 arrival capture, guard,
-- station state and acknowledgement. Drops the key-assignment time and the
-- key gate. Does not change vehicles.current_location and does not delete
-- arrival rows. Pin count stays 241.

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r560 undo: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r560 undo: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='pmb_key_gate_560' AND fault_id='F174' AND sort_order=335 AND added_in='r560')<>1 THEN RAISE EXCEPTION 'r560 undo: F174 check is not the r560 row'; END IF;
END $g$;

DROP TRIGGER IF EXISTS pdc_pmb_arrival_557_insert_guard ON public.pdc_pmb_arrival_557;
DROP TRIGGER IF EXISTS zz_pdc_key_assigned_560 ON public.vehicles;
DROP TRIGGER IF EXISTS zz_pdc_key_assigned_560_ins ON public.vehicles;
DROP TRIGGER IF EXISTS zz_pdc_pmb_arrival_557 ON public.vehicles;
DROP FUNCTION IF EXISTS public.push_new_to_pmb_560(uuid);
DROP FUNCTION IF EXISTS public.list_pmb_key_assigned_560();
DROP FUNCTION IF EXISTS pdc_pmb_ack_private.arrival_insert_guard_560();
DROP FUNCTION IF EXISTS pdc_pmb_ack_private.capture_key_assigned_560();
DROP TABLE IF EXISTS public.pdc_vehicle_key_assigned_560;

CREATE OR REPLACE FUNCTION pdc_pmb_ack_private.arrival_guard_557() RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'pg_catalog' AS $lock$
BEGIN
 IF TG_OP = 'DELETE' OR TG_OP = 'TRUNCATE' THEN
  RAISE EXCEPTION 'PDC_557_ACK_APPEND_ONLY: % on % is not allowed', TG_OP, TG_TABLE_NAME USING ERRCODE = '42501';
 END IF;
 IF OLD.closed_at IS NOT NULL THEN
  RAISE EXCEPTION 'PDC_557_ACK_APPEND_ONLY: this arrival is already finished' USING ERRCODE = '42501';
 END IF;
 IF NEW.arrival_id IS DISTINCT FROM OLD.arrival_id
    OR NEW.vehicle_id IS DISTINCT FROM OLD.vehicle_id
    OR NEW.arrival_at IS DISTINCT FROM OLD.arrival_at
    OR NEW.source IS DISTINCT FROM OLD.source
    OR NEW.previous_location IS DISTINCT FROM OLD.previous_location
    OR NEW.arrival_key IS DISTINCT FROM OLD.arrival_key
    OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
  RAISE EXCEPTION 'PDC_557_ACK_APPEND_ONLY: arrival identity cannot change' USING ERRCODE = '42501';
 END IF;
 IF NEW.closed_at IS NULL THEN
  RAISE EXCEPTION 'PDC_557_ACK_APPEND_ONLY: only closing the arrival is allowed' USING ERRCODE = '42501';
 END IF;
 RETURN NEW;
END $lock$;

CREATE OR REPLACE FUNCTION pdc_pmb_ack_private.capture_557() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $cap$
DECLARE
 v_old text := upper(btrim(coalesce(OLD.current_location, '')));
 v_new text := upper(btrim(coalesce(NEW.current_location, '')));
 v_key_changed boolean := OLD.key_number IS DISTINCT FROM NEW.key_number AND btrim(coalesce(NEW.key_number, '')) <> '';
 v_source text;
 v_inserted integer := 0;
BEGIN
 IF v_new <> 'PMB' OR NEW.deleted_at IS NOT NULL THEN RETURN NULL; END IF;
 IF v_old NOT IN ('YH','YARD HOLD','YARDHOLD','IT','IN TRANSIT','INTRANSIT','OTHER','ALL VEHICLES','') THEN RETURN NULL; END IF;
 IF v_old = 'PMB' THEN RETURN NULL; END IF;
 v_source := CASE WHEN v_key_changed THEN 'key' ELSE 'location' END;
 BEGIN
  INSERT INTO public.pdc_pmb_arrival_557 (vehicle_id, previous_location, arrival_key, source)
  SELECT NEW.id, NULLIF(btrim(coalesce(OLD.current_location, '')), ''), NULLIF(btrim(coalesce(NEW.key_number, '')), ''), v_source
  WHERE NOT EXISTS (
    SELECT 1 FROM public.pdc_pmb_arrival_557 open_row
    WHERE open_row.vehicle_id = NEW.id AND open_row.closed_at IS NULL
  );
  GET DIAGNOSTICS v_inserted = ROW_COUNT;
 EXCEPTION WHEN unique_violation THEN
  v_inserted := 0;
 END;
 IF v_inserted = 1 THEN
  PERFORM pdc_pmb_ack_private.drop_read_caches_557();
 END IF;
 RETURN NULL;
END $cap$;

CREATE OR REPLACE FUNCTION pdc_pmb_ack_private.state_557(p_arrival_id uuid, p_vehicle_id uuid, p_controller boolean, p_actor uuid, p_open boolean)
 RETURNS jsonb
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $view$
DECLARE
 v_relevant text[];
 v_mine text[];
 v_departments jsonb;
 v_pending boolean;
BEGIN
 v_relevant := CASE WHEN p_open THEN pdc_pmb_ack_private.relevant_stations_557(p_vehicle_id) ELSE (
   SELECT coalesce(array_agg(d.station_code), ARRAY[]::text[])
   FROM public.pdc_pmb_arrival_dept_ack_557 d
   WHERE d.arrival_id = p_arrival_id
 ) END;
 SELECT coalesce(array_agg(a.station_code), ARRAY[]::text[]) INTO v_mine
 FROM public.pdc_user_station_departments_557 a
 JOIN public.pdc_user_roles r ON r.id = a.user_role_id
 WHERE r.auth_user_id = p_actor AND r.active AND r.account_status = 'approved';
 SELECT coalesce(jsonb_agg(jsonb_build_object(
    'station', catalog.code,
    'label', catalog.label,
    'pending', p_open AND dept.ack_id IS NULL,
    'can_acknowledge', p_open AND dept.ack_id IS NULL AND (p_controller OR catalog.code = ANY (v_mine)),
    'acknowledged_at', dept.acknowledged_at,
    'acknowledged_by_name', dept.acknowledged_by_name,
    'acknowledged_by_role', dept.acknowledged_by_role
   ) ORDER BY catalog.ord), '[]'::jsonb)
  INTO v_departments
 FROM (
   SELECT * FROM (VALUES
     ('BUS_4X4','Bus 4x4',1),
     ('TINT','Tint',2),
     ('HOIST','Hoist',3),
     ('FITTING','Fitting',4),
     ('FABRICATION','Fabrication',5),
     ('ELECTRICAL','Electrical',6),
     ('TYRE','Tyre',7),
     ('SUBLET','Sublet',8)
   ) AS station_catalog(code, label, ord)
 ) catalog
 LEFT JOIN public.pdc_pmb_arrival_dept_ack_557 dept
   ON dept.arrival_id = p_arrival_id AND dept.station_code = catalog.code
 WHERE catalog.code = ANY (v_relevant);
 v_pending := p_open AND EXISTS (
   SELECT 1 FROM jsonb_array_elements(v_departments) item
   WHERE (item->>'pending') = 'true'
     AND (p_controller OR (item->>'station') = ANY (v_mine))
 );
 RETURN jsonb_build_object('viewer_pending', v_pending, 'departments', v_departments);
END $view$;

CREATE OR REPLACE FUNCTION public.acknowledge_pmb_arrival_557(p_vehicle_id uuid, p_station text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'public', 'auth' AS $ack$
DECLARE
 v_actor uuid := auth.uid();
 v_role text; v_email text; v_full text; v_display text; v_name text;
 v_station text := upper(btrim(coalesce(p_station, '')));
 v_controller boolean := false;
 v_open public.pdc_pmb_arrival_557%ROWTYPE;
 v_state jsonb;
 v_relevant text[];
BEGIN
 IF v_actor IS NULL OR p_vehicle_id IS NULL THEN
  RETURN jsonb_build_object('ok', false, 'code', 'not_authorized');
 END IF;
 IF v_station NOT IN ('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET') THEN
  RETURN jsonb_build_object('ok', false, 'code', 'not_a_station', 'message', 'Choose a workshop station.');
 END IF;
 SELECT r.role::text, lower(btrim(r.email)), nullif(btrim(r.full_name), ''), nullif(btrim(r.display_name), '')
  INTO v_role, v_email, v_full, v_display
 FROM public.pdc_user_roles r
 WHERE r.auth_user_id = v_actor AND r.active AND r.account_status = 'approved'
   AND lower(btrim(r.email)) = lower(btrim(coalesce(auth.jwt()->>'email', '')))
 ORDER BY r.updated_at DESC
 LIMIT 1;
 IF v_role IS NULL THEN
  RETURN jsonb_build_object('ok', false, 'code', 'not_authorized');
 END IF;
 v_name := coalesce(v_full, v_display, v_email);
 v_controller := v_role IN ('operator', 'administrator');
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('pdc-557:' || p_vehicle_id::text, 0));
 SELECT * INTO v_open FROM public.pdc_pmb_arrival_557
  WHERE vehicle_id = p_vehicle_id AND closed_at IS NULL
  ORDER BY arrival_at DESC LIMIT 1 FOR UPDATE;
 IF NOT FOUND THEN
  RETURN jsonb_build_object('ok', false, 'code', 'not_pending', 'message', 'This vehicle is not waiting in New to PMB.');
 END IF;
 v_relevant := pdc_pmb_ack_private.relevant_stations_557(p_vehicle_id);
 IF NOT (v_station = ANY (v_relevant)) THEN
  RETURN jsonb_build_object('ok', false, 'code', 'not_relevant', 'message', 'That station has no work waiting on this vehicle.');
 END IF;
 IF NOT v_controller AND NOT EXISTS (
   SELECT 1 FROM public.pdc_user_station_departments_557 a
   JOIN public.pdc_user_roles r ON r.id = a.user_role_id
   WHERE r.auth_user_id = v_actor AND r.active AND r.account_status = 'approved'
     AND a.station_code = v_station
 ) THEN
  RETURN jsonb_build_object('ok', false, 'code', 'not_authorized',
    'message', 'A controller can acknowledge any station. Anyone else can acknowledge only a station an administrator assigned to them.');
 END IF;
 IF EXISTS (
   SELECT 1 FROM public.pdc_pmb_arrival_dept_ack_557 d
   WHERE d.arrival_id = v_open.arrival_id AND d.station_code = v_station
 ) THEN
  v_state := pdc_pmb_ack_private.state_557(v_open.arrival_id, p_vehicle_id, v_controller, v_actor, true);
  RETURN jsonb_build_object('ok', true, 'code', 'already_acknowledged', 'data', v_state || jsonb_build_object(
    'vehicle_id', p_vehicle_id, 'source', v_open.source, 'closed', v_open.closed_at IS NOT NULL));
 END IF;
 INSERT INTO public.pdc_pmb_arrival_dept_ack_557 (
  arrival_id, station_code, acknowledged_by, acknowledged_by_email, acknowledged_by_name, acknowledged_by_role
 ) VALUES (
  v_open.arrival_id, v_station, v_actor, v_email, v_name, v_role
 );
 v_relevant := pdc_pmb_ack_private.relevant_stations_557(p_vehicle_id);
 IF NOT EXISTS (
   SELECT 1 FROM unnest(v_relevant) station_code
   WHERE NOT EXISTS (
     SELECT 1 FROM public.pdc_pmb_arrival_dept_ack_557 d
     WHERE d.arrival_id = v_open.arrival_id AND d.station_code = station_code
   )
 ) THEN
  UPDATE public.pdc_pmb_arrival_557 SET closed_at = clock_timestamp()
   WHERE arrival_id = v_open.arrival_id AND closed_at IS NULL;
  v_open.closed_at := clock_timestamp();
 END IF;
 PERFORM pdc_pmb_ack_private.drop_read_caches_557();
 v_state := pdc_pmb_ack_private.state_557(v_open.arrival_id, p_vehicle_id, v_controller, v_actor, v_open.closed_at IS NULL);
 RETURN jsonb_build_object('ok', true, 'code', 'acknowledged', 'data', v_state || jsonb_build_object(
  'vehicle_id', p_vehicle_id, 'source', v_open.source, 'closed', v_open.closed_at IS NOT NULL));
END $ack$;


CREATE TRIGGER zz_pdc_pmb_arrival_557
 AFTER UPDATE OF current_location, key_number ON public.vehicles
 FOR EACH ROW
 WHEN (
  upper(btrim(coalesce(NEW.current_location, ''))) = 'PMB'
  AND NEW.deleted_at IS NULL
  AND upper(btrim(coalesce(OLD.current_location, ''))) IN ('YH','YARD HOLD','YARDHOLD','IT','IN TRANSIT','INTRANSIT','OTHER','ALL VEHICLES','')
 )
 EXECUTE FUNCTION pdc_pmb_ack_private.capture_557();

DELETE FROM pdc_ops.regression_checks
WHERE check_name='pmb_key_gate_560' AND fault_id='F174' AND sort_order=335 AND added_in='r560';

DO $post$ BEGIN
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='pmb_key_gate_560' OR fault_id='F174' OR added_in='r560' OR sort_order=335) THEN RAISE EXCEPTION 'r560 undo: check remains'; END IF;
 IF pg_catalog.to_regclass('public.pdc_vehicle_key_assigned_560') IS NOT NULL THEN RAISE EXCEPTION 'r560 undo: key table remains'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r560 undo: pin count changed'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r560') THEN RAISE EXCEPTION 'r560 undo: a pin remains'; END IF;
 IF EXISTS (
   SELECT 1 FROM pg_catalog.pg_proc p
   JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
   WHERE p.proname IN ('push_new_to_pmb_560','list_pmb_key_assigned_560','arrival_insert_guard_560','capture_key_assigned_560')
 ) THEN RAISE EXCEPTION 'r560 undo: a function remains'; END IF;
END $post$;
