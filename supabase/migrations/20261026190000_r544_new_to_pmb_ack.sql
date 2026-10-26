-- r544 (F158). PREVIEW. Staging cdsmnqxtyyoeoznmbidd only. Production is not a target.
-- Craig, 26 Oct 2026 10:55 AWST, refined 10:56 AWST: acknowledgement is per workshop
-- station, not one tick for the whole vehicle. SQL is not applied until Craig gives
-- the go-live.
--
-- At PMB for every downstream consumer: current_location stays 'PMB'. There is no new
-- location value. Planner unallocated lists, work-status columns, station ticks, Sales
-- views, the importer, Navision and email writers, and incomingBucketForVehicle all
-- keep treating the vehicle as at PMB. The Vehicle Locations tiles are the only split.
--
-- Rule (when the vehicle leaves New to PMB):
--   Stations are Bus 4x4, Tint, Hoist, Fitting, Fabrication, Electrical, Tyre and
--   Sublet. Parts and Pit are not stations. Department 135 is not a station and is
--   not granted.
--   Relevant stations are those with a required public.vehicle_work_items row. If the
--   vehicle has none yet, relevant stations are every station an approved user has
--   been assigned (the mapped departments). If nothing is mapped and there is no
--   required work, the vehicle is not pending and stays on the PMB tile.
--   Each relevant station needs one acknowledgement from anyone assigned to it, or
--   from a controller. That tick clears the station for everyone assigned to it.
--   Other stations stay pending. The vehicle leaves New to PMB for everyone only when
--   every relevant station on that arrival has been acknowledged.
--   Until then a controller still sees it in New to PMB, and that tile flashes, while
--   any station is outstanding. A person assigned to stations sees it, and their tile
--   flashes, only while one of their stations is still outstanding. Everyone else sees
--   the PMB tile. The vehicle lists each station, who acknowledged it, and when.
--   Work that appears after the arrival is fully acknowledged does not reopen it.
--   While it is still open, a new required station joins the outstanding list.
--
-- Who assigns stations: an administrator, in User Management, the same screen that
-- links a salesperson. User Management stays administrator-only. A user may have
-- several stations. Controllers (operator or administrator, active, approved, email
-- matching the JWT) can acknowledge any relevant station. Anyone else can acknowledge
-- only a station they have been assigned. The JWT name claim is not read.
--
-- Arrival (trigger only; writers are not replaced, so the pin count stays 241):
--   current_location becomes PMB from YH, Yard Hold, IT, In transit, Other
--   (All vehicles), or blank. A new key in that same update is the same arrival
--   (source 'key'). A key edit while the vehicle is already at PMB does not re-queue.
--   A return from QC, PIT or RFT does not re-queue. Existing PMB rows are backfilled
--   as closed, with no person and no station, so the new tile starts empty.
--
-- Sort 320 is live r542 (close_gaps_holds_populated). r541 (F155, #525) reserves sort
-- 319 and is not applied. Open preview #526 reserves r543 / F157 / sort 321 and the
-- filename 20261026180000 (email notes). This check is r544 / F158 / sort 322.
-- Filename 20261026190000 sorts after both. The Supabase CLI was not on this machine;
-- a clock stamp would have sorted before r542.
-- Undo: supabase/rollbacks/20261026190000_r544_new_to_pmb_ack.down.sql

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r544: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r544: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r544: pin count is not 241'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='close_gaps_holds_populated' AND fault_id='F156' AND sort_order=320 AND added_in='r542') THEN RAISE EXCEPTION 'r544: r542 / F156 sort 320 is not the live check'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=322 OR fault_id='F158' OR check_name='new_to_pmb_ack_544' OR added_in='r544') THEN RAISE EXCEPTION 'r544: sort 322 or F158 is taken'; END IF;
 IF pg_catalog.to_regclass('public.pdc_pmb_arrival_544') IS NOT NULL
    OR pg_catalog.to_regclass('public.pdc_pmb_arrival_dept_ack_544') IS NOT NULL
    OR pg_catalog.to_regclass('public.pdc_user_station_departments_544') IS NOT NULL
    OR pg_catalog.to_regclass('public.pdc_pmb_arrival_ack_544') IS NOT NULL
    OR pg_catalog.to_regnamespace('pdc_pmb_ack_private') IS NOT NULL THEN RAISE EXCEPTION 'r544: already applied'; END IF;
END $g$;

CREATE SCHEMA pdc_pmb_ack_private;
REVOKE ALL ON SCHEMA pdc_pmb_ack_private FROM PUBLIC;
REVOKE ALL ON SCHEMA pdc_pmb_ack_private FROM anon, authenticated, service_role;

CREATE TABLE public.pdc_pmb_arrival_544 (
 arrival_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 vehicle_id uuid NOT NULL,
 arrival_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 previous_location text,
 arrival_key text,
 source text NOT NULL CHECK (source IN ('location','key','backfill')),
 closed_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX pdc_pmb_arrival_544_vehicle ON public.pdc_pmb_arrival_544 (vehicle_id, arrival_at DESC);
CREATE UNIQUE INDEX pdc_pmb_arrival_544_one_open ON public.pdc_pmb_arrival_544 (vehicle_id) WHERE closed_at IS NULL;
ALTER TABLE public.pdc_pmb_arrival_544 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_pmb_arrival_544 FROM PUBLIC, anon, authenticated;
COMMENT ON TABLE public.pdc_pmb_arrival_544 IS 'r544 (F158): one PMB arrival. closed_at set means every relevant station has been acknowledged, or the row is the backfill. Location stays PMB.';

CREATE TABLE public.pdc_pmb_arrival_dept_ack_544 (
 ack_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 arrival_id uuid NOT NULL,
 station_code text NOT NULL CHECK (station_code IN ('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET')),
 acknowledged_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 acknowledged_by uuid NOT NULL,
 acknowledged_by_email text NOT NULL,
 acknowledged_by_name text NOT NULL,
 acknowledged_by_role text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE (arrival_id, station_code)
);
ALTER TABLE public.pdc_pmb_arrival_dept_ack_544 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_pmb_arrival_dept_ack_544 FROM PUBLIC, anon, authenticated;
COMMENT ON TABLE public.pdc_pmb_arrival_dept_ack_544 IS 'r544 (F158): one acknowledgement per station on an arrival. Who and when are stored. A backfill has no rows.';

CREATE TABLE public.pdc_user_station_departments_544 (
 assignment_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 user_role_id uuid NOT NULL,
 station_code text NOT NULL CHECK (station_code IN ('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET')),
 assigned_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 assigned_by uuid,
 assigned_by_email text,
 UNIQUE (user_role_id, station_code)
);
ALTER TABLE public.pdc_user_station_departments_544 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_user_station_departments_544 FROM PUBLIC, anon, authenticated;
COMMENT ON TABLE public.pdc_user_station_departments_544 IS 'r544 (F158): stations an administrator assigned in User Management. A user may have several. This is not Department 135.';

CREATE FUNCTION pdc_pmb_ack_private.arrival_guard_544() RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'pg_catalog' AS $lock$
BEGIN
 IF TG_OP = 'DELETE' OR TG_OP = 'TRUNCATE' THEN
  RAISE EXCEPTION 'PDC_544_ACK_APPEND_ONLY: % on % is not allowed', TG_OP, TG_TABLE_NAME USING ERRCODE = '42501';
 END IF;
 IF OLD.closed_at IS NOT NULL THEN
  RAISE EXCEPTION 'PDC_544_ACK_APPEND_ONLY: this arrival is already finished' USING ERRCODE = '42501';
 END IF;
 IF NEW.arrival_id IS DISTINCT FROM OLD.arrival_id
    OR NEW.vehicle_id IS DISTINCT FROM OLD.vehicle_id
    OR NEW.arrival_at IS DISTINCT FROM OLD.arrival_at
    OR NEW.source IS DISTINCT FROM OLD.source
    OR NEW.previous_location IS DISTINCT FROM OLD.previous_location
    OR NEW.arrival_key IS DISTINCT FROM OLD.arrival_key
    OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
  RAISE EXCEPTION 'PDC_544_ACK_APPEND_ONLY: arrival identity cannot change' USING ERRCODE = '42501';
 END IF;
 IF NEW.closed_at IS NULL THEN
  RAISE EXCEPTION 'PDC_544_ACK_APPEND_ONLY: only closing the arrival is allowed' USING ERRCODE = '42501';
 END IF;
 RETURN NEW;
END $lock$;
REVOKE ALL ON FUNCTION pdc_pmb_ack_private.arrival_guard_544() FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER pdc_pmb_arrival_544_guard
 BEFORE UPDATE OR DELETE ON public.pdc_pmb_arrival_544
 FOR EACH ROW EXECUTE FUNCTION pdc_pmb_ack_private.arrival_guard_544();
CREATE TRIGGER pdc_pmb_arrival_544_no_truncate
 BEFORE TRUNCATE ON public.pdc_pmb_arrival_544
 FOR EACH STATEMENT EXECUTE FUNCTION pdc_pmb_ack_private.arrival_guard_544();

CREATE FUNCTION pdc_pmb_ack_private.dept_guard_544() RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'pg_catalog' AS $dlock$
BEGIN
 RAISE EXCEPTION 'PDC_544_ACK_APPEND_ONLY: % on % is not allowed', TG_OP, TG_TABLE_NAME USING ERRCODE = '42501';
END $dlock$;
REVOKE ALL ON FUNCTION pdc_pmb_ack_private.dept_guard_544() FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER pdc_pmb_arrival_dept_ack_544_guard
 BEFORE UPDATE OR DELETE ON public.pdc_pmb_arrival_dept_ack_544
 FOR EACH ROW EXECUTE FUNCTION pdc_pmb_ack_private.dept_guard_544();
CREATE TRIGGER pdc_pmb_arrival_dept_ack_544_no_truncate
 BEFORE TRUNCATE ON public.pdc_pmb_arrival_dept_ack_544
 FOR EACH STATEMENT EXECUTE FUNCTION pdc_pmb_ack_private.dept_guard_544();

CREATE FUNCTION pdc_pmb_ack_private.relevant_stations_544(p_vehicle_id uuid)
 RETURNS text[]
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $rel$
  WITH work AS (
    SELECT DISTINCT CASE lower(btrim(w.work_key))
      WHEN 'bus4x4' THEN 'BUS_4X4'
      WHEN 'tint' THEN 'TINT'
      WHEN 'hoist' THEN 'HOIST'
      WHEN 'fitting' THEN 'FITTING'
      WHEN 'fabrication' THEN 'FABRICATION'
      WHEN 'electrical' THEN 'ELECTRICAL'
      WHEN 'tyre' THEN 'TYRE'
      WHEN 'sublet' THEN 'SUBLET'
      ELSE NULL
    END AS station_code
    FROM public.vehicle_work_items w
    WHERE w.vehicle_id = p_vehicle_id AND w.required IS TRUE
  ),
  mapped AS (
    SELECT DISTINCT a.station_code
    FROM public.pdc_user_station_departments_544 a
    JOIN public.pdc_user_roles r ON r.id = a.user_role_id
    WHERE r.active AND r.account_status = 'approved'
  )
  SELECT coalesce((
    SELECT array_agg(station_code ORDER BY station_code)
    FROM (
      SELECT station_code FROM work WHERE station_code IS NOT NULL
      UNION
      SELECT station_code FROM mapped
      WHERE NOT EXISTS (SELECT 1 FROM work WHERE station_code IS NOT NULL)
    ) chosen
  ), ARRAY[]::text[]);
$rel$;
REVOKE ALL ON FUNCTION pdc_pmb_ack_private.relevant_stations_544(uuid) FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION pdc_pmb_ack_private.capture_544() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $cap$
DECLARE
 v_old text := upper(btrim(coalesce(OLD.current_location, '')));
 v_new text := upper(btrim(coalesce(NEW.current_location, '')));
 v_key_changed boolean := OLD.key_number IS DISTINCT FROM NEW.key_number AND btrim(coalesce(NEW.key_number, '')) <> '';
 v_source text;
BEGIN
 IF v_new <> 'PMB' OR NEW.deleted_at IS NOT NULL THEN RETURN NULL; END IF;
 IF v_old NOT IN ('YH','YARD HOLD','YARDHOLD','IT','IN TRANSIT','INTRANSIT','OTHER','ALL VEHICLES','') THEN RETURN NULL; END IF;
 IF v_old = 'PMB' THEN RETURN NULL; END IF;
 v_source := CASE WHEN v_key_changed THEN 'key' ELSE 'location' END;
 BEGIN
  INSERT INTO public.pdc_pmb_arrival_544 (vehicle_id, previous_location, arrival_key, source)
  SELECT NEW.id, NULLIF(btrim(coalesce(OLD.current_location, '')), ''), NULLIF(btrim(coalesce(NEW.key_number, '')), ''), v_source
  WHERE NOT EXISTS (
    SELECT 1 FROM public.pdc_pmb_arrival_544 open_row
    WHERE open_row.vehicle_id = NEW.id AND open_row.closed_at IS NULL
  );
 EXCEPTION WHEN unique_violation THEN
  NULL;
 END;
 RETURN NULL;
END $cap$;
REVOKE ALL ON FUNCTION pdc_pmb_ack_private.capture_544() FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER zz_pdc_pmb_arrival_544
 AFTER UPDATE OF current_location, key_number ON public.vehicles
 FOR EACH ROW
 WHEN (
  upper(btrim(coalesce(NEW.current_location, ''))) = 'PMB'
  AND NEW.deleted_at IS NULL
  AND upper(btrim(coalesce(OLD.current_location, ''))) IN ('YH','YARD HOLD','YARDHOLD','IT','IN TRANSIT','INTRANSIT','OTHER','ALL VEHICLES','')
 )
 EXECUTE FUNCTION pdc_pmb_ack_private.capture_544();

INSERT INTO public.pdc_pmb_arrival_544 (vehicle_id, previous_location, arrival_key, source, closed_at)
SELECT v.id, v.current_location, NULLIF(btrim(coalesce(v.key_number, '')), ''), 'backfill', clock_timestamp()
FROM public.vehicles v
WHERE v.deleted_at IS NULL
  AND upper(btrim(coalesce(v.current_location, ''))) = 'PMB';

CREATE FUNCTION pdc_pmb_ack_private.state_544(p_arrival_id uuid, p_vehicle_id uuid, p_controller boolean, p_actor uuid, p_open boolean)
 RETURNS jsonb
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $view$
DECLARE
 v_relevant text[];
 v_mine text[];
 v_departments jsonb;
 v_pending boolean;
BEGIN
 v_relevant := CASE WHEN p_open THEN pdc_pmb_ack_private.relevant_stations_544(p_vehicle_id) ELSE (
   SELECT coalesce(array_agg(d.station_code), ARRAY[]::text[])
   FROM public.pdc_pmb_arrival_dept_ack_544 d
   WHERE d.arrival_id = p_arrival_id
 ) END;
 SELECT coalesce(array_agg(a.station_code), ARRAY[]::text[]) INTO v_mine
 FROM public.pdc_user_station_departments_544 a
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
 LEFT JOIN public.pdc_pmb_arrival_dept_ack_544 dept
   ON dept.arrival_id = p_arrival_id AND dept.station_code = catalog.code
 WHERE catalog.code = ANY (v_relevant);
 v_pending := p_open AND EXISTS (
   SELECT 1 FROM jsonb_array_elements(v_departments) item
   WHERE (item->>'pending') = 'true'
     AND (p_controller OR (item->>'station') = ANY (v_mine))
 );
 RETURN jsonb_build_object('viewer_pending', v_pending, 'departments', v_departments);
END $view$;
REVOKE ALL ON FUNCTION pdc_pmb_ack_private.state_544(uuid, uuid, boolean, uuid, boolean) FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.list_pmb_arrival_ack_544()
 RETURNS TABLE (
  vehicle_id uuid,
  source text,
  viewer_pending boolean,
  closed boolean,
  departments jsonb
 )
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public', 'auth' AS $list$
DECLARE
 v_actor uuid := auth.uid();
 v_role text;
 v_controller boolean;
 r record;
 v_state jsonb;
BEGIN
 IF v_actor IS NULL THEN RETURN; END IF;
 SELECT role.role::text INTO v_role
 FROM public.pdc_user_roles role
 WHERE role.auth_user_id = v_actor AND role.active AND role.account_status = 'approved'
   AND lower(btrim(role.email)) = lower(btrim(coalesce(auth.jwt()->>'email', '')))
 ORDER BY role.updated_at DESC
 LIMIT 1;
 IF v_role IS NULL THEN RETURN; END IF;
 v_controller := v_role IN ('operator', 'administrator');
 FOR r IN
   SELECT DISTINCT ON (a.vehicle_id) a.arrival_id, a.vehicle_id, a.source, a.closed_at
   FROM public.pdc_pmb_arrival_544 a
   WHERE a.closed_at IS NULL
      OR EXISTS (SELECT 1 FROM public.pdc_pmb_arrival_dept_ack_544 d WHERE d.arrival_id = a.arrival_id)
   ORDER BY a.vehicle_id, a.arrival_at DESC
 LOOP
  v_state := pdc_pmb_ack_private.state_544(r.arrival_id, r.vehicle_id, v_controller, v_actor, r.closed_at IS NULL);
  vehicle_id := r.vehicle_id;
  source := r.source;
  viewer_pending := coalesce((v_state->>'viewer_pending')::boolean, false);
  closed := r.closed_at IS NOT NULL;
  departments := coalesce(v_state->'departments', '[]'::jsonb);
  RETURN NEXT;
 END LOOP;
END $list$;
REVOKE ALL ON FUNCTION public.list_pmb_arrival_ack_544() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_pmb_arrival_ack_544() TO authenticated;

CREATE FUNCTION public.acknowledge_pmb_arrival_544(p_vehicle_id uuid, p_station text)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'public', 'auth' AS $ack$
DECLARE
 v_actor uuid := auth.uid();
 v_role text; v_email text; v_full text; v_display text; v_name text;
 v_station text := upper(btrim(coalesce(p_station, '')));
 v_controller boolean := false;
 v_open public.pdc_pmb_arrival_544%ROWTYPE;
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
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('pdc-544:' || p_vehicle_id::text, 0));
 SELECT * INTO v_open FROM public.pdc_pmb_arrival_544
  WHERE vehicle_id = p_vehicle_id AND closed_at IS NULL
  ORDER BY arrival_at DESC LIMIT 1 FOR UPDATE;
 IF NOT FOUND THEN
  RETURN jsonb_build_object('ok', false, 'code', 'not_pending', 'message', 'This vehicle is not waiting in New to PMB.');
 END IF;
 v_relevant := pdc_pmb_ack_private.relevant_stations_544(p_vehicle_id);
 IF NOT (v_station = ANY (v_relevant)) THEN
  RETURN jsonb_build_object('ok', false, 'code', 'not_relevant', 'message', 'That station has no work waiting on this vehicle.');
 END IF;
 IF NOT v_controller AND NOT EXISTS (
   SELECT 1 FROM public.pdc_user_station_departments_544 a
   JOIN public.pdc_user_roles r ON r.id = a.user_role_id
   WHERE r.auth_user_id = v_actor AND r.active AND r.account_status = 'approved'
     AND a.station_code = v_station
 ) THEN
  RETURN jsonb_build_object('ok', false, 'code', 'not_authorized',
    'message', 'A controller can acknowledge any station. Anyone else can acknowledge only a station an administrator assigned to them.');
 END IF;
 IF EXISTS (
   SELECT 1 FROM public.pdc_pmb_arrival_dept_ack_544 d
   WHERE d.arrival_id = v_open.arrival_id AND d.station_code = v_station
 ) THEN
  v_state := pdc_pmb_ack_private.state_544(v_open.arrival_id, p_vehicle_id, v_controller, v_actor, true);
  RETURN jsonb_build_object('ok', true, 'code', 'already_acknowledged', 'data', v_state || jsonb_build_object(
    'vehicle_id', p_vehicle_id, 'source', v_open.source, 'closed', v_open.closed_at IS NOT NULL));
 END IF;
 INSERT INTO public.pdc_pmb_arrival_dept_ack_544 (
  arrival_id, station_code, acknowledged_by, acknowledged_by_email, acknowledged_by_name, acknowledged_by_role
 ) VALUES (
  v_open.arrival_id, v_station, v_actor, v_email, v_name, v_role
 );
 v_relevant := pdc_pmb_ack_private.relevant_stations_544(p_vehicle_id);
 IF NOT EXISTS (
   SELECT 1 FROM unnest(v_relevant) station_code
   WHERE NOT EXISTS (
     SELECT 1 FROM public.pdc_pmb_arrival_dept_ack_544 d
     WHERE d.arrival_id = v_open.arrival_id AND d.station_code = station_code
   )
 ) THEN
  UPDATE public.pdc_pmb_arrival_544 SET closed_at = clock_timestamp()
   WHERE arrival_id = v_open.arrival_id AND closed_at IS NULL;
  v_open.closed_at := clock_timestamp();
 END IF;
 v_state := pdc_pmb_ack_private.state_544(v_open.arrival_id, p_vehicle_id, v_controller, v_actor, v_open.closed_at IS NULL);
 RETURN jsonb_build_object('ok', true, 'code', 'acknowledged', 'data', v_state || jsonb_build_object(
  'vehicle_id', p_vehicle_id, 'source', v_open.source, 'closed', v_open.closed_at IS NOT NULL));
END $ack$;
REVOKE ALL ON FUNCTION public.acknowledge_pmb_arrival_544(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.acknowledge_pmb_arrival_544(uuid, text) TO authenticated;

CREATE FUNCTION public.list_user_station_departments_544()
 RETURNS TABLE (email text, station_code text)
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public', 'auth' AS $slist$
DECLARE v_actor uuid := auth.uid();
BEGIN
 IF v_actor IS NULL OR NOT EXISTS (
   SELECT 1 FROM public.pdc_user_roles r
   WHERE r.auth_user_id = v_actor AND r.active AND r.account_status = 'approved'
     AND r.role::text = 'administrator'
     AND lower(btrim(r.email)) = lower(btrim(coalesce(auth.jwt()->>'email', '')))
 ) THEN
  RETURN;
 END IF;
 RETURN QUERY
 SELECT lower(btrim(r.email)), a.station_code
 FROM public.pdc_user_station_departments_544 a
 JOIN public.pdc_user_roles r ON r.id = a.user_role_id
 ORDER BY 1, 2;
END $slist$;
REVOKE ALL ON FUNCTION public.list_user_station_departments_544() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_user_station_departments_544() TO authenticated;

CREATE FUNCTION public.admin_set_user_station_departments_544(p_email text, p_stations text[])
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'public', 'auth' AS $set$
DECLARE
 v_actor uuid := auth.uid();
 v_actor_email text;
 v_target uuid;
 v_clean text[];
BEGIN
 IF v_actor IS NULL THEN
  RETURN jsonb_build_object('ok', false, 'code', 'not_authorized');
 END IF;
 SELECT lower(btrim(r.email)) INTO v_actor_email
 FROM public.pdc_user_roles r
 WHERE r.auth_user_id = v_actor AND r.active AND r.account_status = 'approved'
   AND r.role::text = 'administrator'
   AND lower(btrim(r.email)) = lower(btrim(coalesce(auth.jwt()->>'email', '')))
 ORDER BY r.updated_at DESC
 LIMIT 1;
 IF v_actor_email IS NULL THEN
  RETURN jsonb_build_object('ok', false, 'code', 'not_authorized', 'message', 'Only an administrator can assign workshop stations.');
 END IF;
 SELECT r.id INTO v_target
 FROM public.pdc_user_roles r
 WHERE lower(btrim(r.email)) = lower(btrim(coalesce(p_email, '')))
   AND r.account_status = 'approved'
 ORDER BY r.active DESC, r.updated_at DESC
 LIMIT 1;
 IF v_target IS NULL THEN
  RETURN jsonb_build_object('ok', false, 'code', 'not_found', 'message', 'That approved account was not found.');
 END IF;
 SELECT coalesce(array_agg(DISTINCT upper(btrim(item))), ARRAY[]::text[])
  INTO v_clean
 FROM unnest(coalesce(p_stations, ARRAY[]::text[])) item
 WHERE btrim(coalesce(item, '')) <> '';
 IF EXISTS (
   SELECT 1 FROM unnest(v_clean) station_code
   WHERE station_code NOT IN ('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET')
 ) THEN
  RETURN jsonb_build_object('ok', false, 'code', 'not_a_station', 'message', 'Choose workshop stations only.');
 END IF;
 DELETE FROM public.pdc_user_station_departments_544 WHERE user_role_id = v_target;
 INSERT INTO public.pdc_user_station_departments_544 (user_role_id, station_code, assigned_by, assigned_by_email)
 SELECT v_target, station_code, v_actor, v_actor_email
 FROM unnest(v_clean) station_code;
 RETURN jsonb_build_object('ok', true, 'code', 'saved', 'email', lower(btrim(p_email)), 'stations', to_jsonb(v_clean));
END $set$;
REVOKE ALL ON FUNCTION public.admin_set_user_station_departments_544(text, text[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_user_station_departments_544(text, text[]) TO authenticated;

INSERT INTO pdc_ops.regression_checks (check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES
('new_to_pmb_ack_544', 'F158',
 'New to PMB is one acknowledgement per workshop station beside location PMB. The pin count stays 241. Pending rows do not change current_location. Controllers are operator and administrator. An administrator assigns stations in User Management. The check uses search_path pg_catalog, schema-qualified types, and no regprocedure cast.',
 $chk544$
SELECT
  pins.n = 241
  AND added.n = 0
  AND arrival.relrowsecurity
  AND dept.relrowsecurity
  AND assigned.relrowsecurity
  AND trg.present
  AND cap.present
  AND cap.no_vehicle_update
  AND cap.release_from
  AND ack.present
  AND ack.no_vehicle_update
  AND ack.no_user_metadata
  AND ack.controller
  AND ack.stations
  AND ack.auth_exec
  AND ack.anon_blocked
  AND lst.present
  AND lst.auth_exec
  AND lst.anon_blocked
  AND setter.present
  AND setter.administrator
  AND setter.auth_exec
  AND setter.anon_blocked
  AS ok,
  ('pins ' || pins.n::pg_catalog.text || ' | ' || coalesce(cap.note, 'capture missing'::pg_catalog.text)) AS detail
FROM (SELECT count(*) AS n FROM pdc_ops.expected_function_md5) pins
CROSS JOIN (SELECT count(*) AS n FROM pdc_ops.expected_function_md5 WHERE release = 'r544') added
CROSS JOIN (
  SELECT c.relrowsecurity
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'pdc_pmb_arrival_544'
) arrival
CROSS JOIN (
  SELECT c.relrowsecurity
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'pdc_pmb_arrival_dept_ack_544'
) dept
CROSS JOIN (
  SELECT c.relrowsecurity
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'pdc_user_station_departments_544'
) assigned
CROSS JOIN (
  SELECT count(*) = 1 AS present
  FROM pg_catalog.pg_trigger t
  JOIN pg_catalog.pg_class c ON c.oid = t.tgrelid
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'vehicles' AND t.tgname = 'zz_pdc_pmb_arrival_544' AND NOT t.tgisinternal
) trg
CROSS JOIN (
  SELECT
    count(*) = 1 AS present,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'UPDATE public.vehicles') = 0), false) AS no_vehicle_update,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'YARD HOLD') > 0 AND pg_catalog.strpos(p.prosrc, 'IN TRANSIT') > 0 AND pg_catalog.strpos(p.prosrc, 'OTHER') > 0), false) AS release_from,
    pg_catalog.left(coalesce(max(p.prosrc), ''::pg_catalog.text), 80) AS note
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'pdc_pmb_ack_private' AND p.proname = 'capture_544'
) cap
CROSS JOIN (
  SELECT
    count(*) = 1 AS present,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'UPDATE public.vehicles') = 0), false) AS no_vehicle_update,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'user_metadata') = 0), false) AS no_user_metadata,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'operator') > 0 AND pg_catalog.strpos(p.prosrc, 'administrator') > 0), false) AS controller,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'FITTING') > 0 AND pg_catalog.strpos(p.prosrc, 'FABRICATION') > 0 AND pg_catalog.strpos(p.prosrc, 'HOIST') > 0 AND pg_catalog.strpos(p.prosrc, 'ELECTRICAL') > 0), false) AS stations,
    coalesce(bool_and(pg_catalog.has_function_privilege('authenticated'::pg_catalog.name, p.oid, 'EXECUTE'::pg_catalog.text)), false) AS auth_exec,
    coalesce(bool_and(NOT pg_catalog.has_function_privilege('anon'::pg_catalog.name, p.oid, 'EXECUTE'::pg_catalog.text)), false) AS anon_blocked
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'acknowledge_pmb_arrival_544'
    AND pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_vehicle_id uuid, p_station text'
) ack
CROSS JOIN (
  SELECT
    count(*) = 1 AS present,
    coalesce(bool_and(pg_catalog.has_function_privilege('authenticated'::pg_catalog.name, p.oid, 'EXECUTE'::pg_catalog.text)), false) AS auth_exec,
    coalesce(bool_and(NOT pg_catalog.has_function_privilege('anon'::pg_catalog.name, p.oid, 'EXECUTE'::pg_catalog.text)), false) AS anon_blocked
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'list_pmb_arrival_ack_544'
    AND pg_catalog.pg_get_function_identity_arguments(p.oid) = ''::pg_catalog.text
) lst
CROSS JOIN (
  SELECT
    count(*) = 1 AS present,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'administrator') > 0), false) AS administrator,
    coalesce(bool_and(pg_catalog.has_function_privilege('authenticated'::pg_catalog.name, p.oid, 'EXECUTE'::pg_catalog.text)), false) AS auth_exec,
    coalesce(bool_and(NOT pg_catalog.has_function_privilege('anon'::pg_catalog.name, p.oid, 'EXECUTE'::pg_catalog.text)), false) AS anon_blocked
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'admin_set_user_station_departments_544'
    AND pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_email text, p_stations text[]'
) setter
$chk544$, true, 322, 'r544');

DO $post$
DECLARE r record; probe record;
BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r544: pin count changed'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r544') THEN RAISE EXCEPTION 'r544: a pin was inserted'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='new_to_pmb_ack_544' AND fault_id='F158' AND sort_order=322 AND added_in='r544' AND enabled)<>1 THEN RAISE EXCEPTION 'r544: check missing'; END IF;
 IF (SELECT count(*) FROM public.pdc_pmb_arrival_544 WHERE source='backfill' AND closed_at IS NOT NULL)
    <> (SELECT count(*) FROM public.vehicles WHERE deleted_at IS NULL AND upper(btrim(coalesce(current_location,'')))='PMB') THEN
  RAISE EXCEPTION 'r544: backfill does not match vehicles already at PMB';
 END IF;
 IF EXISTS (SELECT 1 FROM public.pdc_pmb_arrival_544 WHERE closed_at IS NULL) THEN RAISE EXCEPTION 'r544: backfill left an open arrival'; END IF;
 IF EXISTS (SELECT 1 FROM public.pdc_pmb_arrival_dept_ack_544) THEN RAISE EXCEPTION 'r544: backfill stored a person'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 FOR r IN SELECT check_name, check_sql FROM pdc_ops.regression_checks WHERE check_name='new_to_pmb_ack_544' LOOP
  EXECUTE r.check_sql INTO probe;
  IF coalesce(probe.ok, false) IS NOT TRUE THEN RAISE EXCEPTION 'r544: % failed: %', r.check_name, probe.detail; END IF;
 END LOOP;
END $post$;
