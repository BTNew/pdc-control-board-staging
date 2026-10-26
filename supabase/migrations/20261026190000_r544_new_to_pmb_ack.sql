-- r544 (F158). PREVIEW. Staging cdsmnqxtyyoeoznmbidd only. Production is not a target.
-- Craig, 26 Oct 2026 10:55 AWST: a vehicle released to PMB waits in "New to PMB" until
-- someone acknowledges it. SQL is not applied until Craig gives the go-live.
--
-- At PMB for every downstream consumer: current_location stays 'PMB'. There is no new
-- location value. Planner unallocated lists, work-status columns, station ticks, Sales
-- views, the importer, Navision and email writers, and incomingBucketForVehicle all
-- keep treating the vehicle as at PMB. The Vehicle Locations tiles are the only split:
-- an open row in public.pdc_pmb_arrival_ack_544 is "New to PMB"; after Acknowledge, or
-- when no open row exists, the vehicle stays on the PMB tile.
--
-- Who may acknowledge (server, not the browser):
--   Controllers: public.pdc_user_roles.role in ('operator','administrator'), active and
--   approved, email matching the JWT. The board calls operator "controller". Any vehicle.
--   There is no department-manager role and no department on the login. A manager who
--   can acknowledge is a controller.
--   Department staff: role 'fitter' whose full_name or display_name equals an active
--   workshop_technicians.name (those names are staff records, not user_metadata), and
--   that technician's can_fit_stages includes BUS_4X4, and the vehicle's department
--   codes from public.pdc_vehicle_department_membership_20260919 include '138'
--   (Bus 4x4). That is the only login-to-department join that exists. Department 139
--   has no technician stage stored against a login, so only a controller can
--   acknowledge a 139-only vehicle. Department 135 is not a code on this board and is
--   not granted. viewer, salesperson and importer cannot acknowledge.
--
-- Arrival (trigger only; writers are not replaced, so the pin count stays 241):
--   current_location becomes PMB from YH, Yard Hold, IT, In transit, Other
--   (All vehicles), or blank. A new key in that same update is the same arrival
--   (source 'key'). A key edit while the vehicle is already at PMB does not re-queue.
--   A return from QC, PIT or RFT does not re-queue. Existing PMB rows are backfilled
--   as acknowledged with no person, so the new tile starts empty.
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
 IF pg_catalog.to_regclass('public.pdc_pmb_arrival_ack_544') IS NOT NULL OR pg_catalog.to_regnamespace('pdc_pmb_ack_private') IS NOT NULL THEN RAISE EXCEPTION 'r544: already applied'; END IF;
END $g$;

CREATE SCHEMA pdc_pmb_ack_private;
REVOKE ALL ON SCHEMA pdc_pmb_ack_private FROM PUBLIC;
REVOKE ALL ON SCHEMA pdc_pmb_ack_private FROM anon, authenticated, service_role;

CREATE TABLE public.pdc_pmb_arrival_ack_544 (
 ack_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 vehicle_id uuid NOT NULL,
 arrival_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 previous_location text,
 arrival_key text,
 source text NOT NULL CHECK (source IN ('location','key','backfill')),
 acknowledged_at timestamptz,
 acknowledged_by uuid,
 acknowledged_by_email text,
 acknowledged_by_name text,
 acknowledged_by_role text,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CONSTRAINT pdc_pmb_arrival_ack_544_person CHECK (
   acknowledged_at IS NULL
   OR source = 'backfill'
   OR (acknowledged_by IS NOT NULL AND acknowledged_by_email IS NOT NULL AND acknowledged_by_role IS NOT NULL)
 )
);
CREATE INDEX pdc_pmb_arrival_ack_544_vehicle ON public.pdc_pmb_arrival_ack_544 (vehicle_id, arrival_at DESC);
CREATE UNIQUE INDEX pdc_pmb_arrival_ack_544_one_open ON public.pdc_pmb_arrival_ack_544 (vehicle_id) WHERE acknowledged_at IS NULL;
ALTER TABLE public.pdc_pmb_arrival_ack_544 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_pmb_arrival_ack_544 FROM PUBLIC, anon, authenticated;
COMMENT ON TABLE public.pdc_pmb_arrival_ack_544 IS 'r544 (F158): acknowledgement beside location PMB. An open row (acknowledged_at null) is New to PMB. Location stays PMB. Backfill rows have no person.';

CREATE FUNCTION pdc_pmb_ack_private.append_only_544() RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'pg_catalog' AS $lock$
BEGIN
 IF TG_OP = 'DELETE' OR TG_OP = 'TRUNCATE' THEN
  RAISE EXCEPTION 'PDC_544_ACK_APPEND_ONLY: % on % is not allowed', TG_OP, TG_TABLE_NAME USING ERRCODE = '42501';
 END IF;
 IF OLD.acknowledged_at IS NOT NULL THEN
  RAISE EXCEPTION 'PDC_544_ACK_APPEND_ONLY: acknowledgement is already recorded' USING ERRCODE = '42501';
 END IF;
 IF NEW.vehicle_id IS DISTINCT FROM OLD.vehicle_id
    OR NEW.arrival_at IS DISTINCT FROM OLD.arrival_at
    OR NEW.source IS DISTINCT FROM OLD.source
    OR NEW.previous_location IS DISTINCT FROM OLD.previous_location
    OR NEW.arrival_key IS DISTINCT FROM OLD.arrival_key
    OR NEW.ack_id IS DISTINCT FROM OLD.ack_id THEN
  RAISE EXCEPTION 'PDC_544_ACK_APPEND_ONLY: arrival identity cannot change' USING ERRCODE = '42501';
 END IF;
 IF NEW.acknowledged_at IS NULL THEN
  RAISE EXCEPTION 'PDC_544_ACK_APPEND_ONLY: only the acknowledgement can be filled in' USING ERRCODE = '42501';
 END IF;
 RETURN NEW;
END $lock$;
REVOKE ALL ON FUNCTION pdc_pmb_ack_private.append_only_544() FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER pdc_pmb_arrival_ack_544_append_only
 BEFORE UPDATE OR DELETE ON public.pdc_pmb_arrival_ack_544
 FOR EACH ROW EXECUTE FUNCTION pdc_pmb_ack_private.append_only_544();
CREATE TRIGGER pdc_pmb_arrival_ack_544_no_truncate
 BEFORE TRUNCATE ON public.pdc_pmb_arrival_ack_544
 FOR EACH STATEMENT EXECUTE FUNCTION pdc_pmb_ack_private.append_only_544();

-- Every release into PMB from All vehicles (Other), In transit, Yard Hold or blank.
-- Does not rewrite the vehicle. A failure to record still must not block the writer
-- only for a duplicate open row; any other error is real.
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
  INSERT INTO public.pdc_pmb_arrival_ack_544 (vehicle_id, previous_location, arrival_key, source)
  SELECT NEW.id, NULLIF(btrim(coalesce(OLD.current_location, '')), ''), NULLIF(btrim(coalesce(NEW.key_number, '')), ''), v_source
  WHERE NOT EXISTS (
    SELECT 1 FROM public.pdc_pmb_arrival_ack_544 open_row
    WHERE open_row.vehicle_id = NEW.id AND open_row.acknowledged_at IS NULL
  );
 EXCEPTION WHEN unique_violation THEN
  NULL;
 END;
 RETURN NULL;
END $cap$;
REVOKE ALL ON FUNCTION pdc_pmb_ack_private.capture_544() FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER zz_pdc_pmb_arrival_ack_544
 AFTER UPDATE OF current_location, key_number ON public.vehicles
 FOR EACH ROW
 WHEN (
  upper(btrim(coalesce(NEW.current_location, ''))) = 'PMB'
  AND NEW.deleted_at IS NULL
  AND upper(btrim(coalesce(OLD.current_location, ''))) IN ('YH','YARD HOLD','YARDHOLD','IT','IN TRANSIT','INTRANSIT','OTHER','ALL VEHICLES','')
 )
 EXECUTE FUNCTION pdc_pmb_ack_private.capture_544();

-- Vehicles already at PMB are already acknowledged. No person is stored.
INSERT INTO public.pdc_pmb_arrival_ack_544 (vehicle_id, previous_location, arrival_key, source, acknowledged_at)
SELECT v.id, v.current_location, NULLIF(btrim(coalesce(v.key_number, '')), ''), 'backfill', clock_timestamp()
FROM public.vehicles v
WHERE v.deleted_at IS NULL
  AND upper(btrim(coalesce(v.current_location, ''))) = 'PMB';

CREATE FUNCTION public.list_pmb_arrival_ack_544()
 RETURNS TABLE (
  vehicle_id uuid,
  pending boolean,
  acknowledged_at timestamptz,
  acknowledged_by_name text,
  acknowledged_by_role text,
  source text,
  arrival_at timestamptz
 )
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public', 'auth' AS $list$
DECLARE v_actor uuid := auth.uid();
BEGIN
 IF v_actor IS NULL OR NOT EXISTS (
   SELECT 1 FROM public.pdc_user_roles r
   WHERE r.auth_user_id = v_actor AND r.active AND r.account_status = 'approved'
     AND lower(btrim(r.email)) = lower(btrim(coalesce(auth.jwt()->>'email', '')))
 ) THEN
  RETURN;
 END IF;
 RETURN QUERY
 SELECT DISTINCT ON (a.vehicle_id)
  a.vehicle_id,
  a.acknowledged_at IS NULL,
  a.acknowledged_at,
  a.acknowledged_by_name,
  a.acknowledged_by_role,
  a.source,
  a.arrival_at
 FROM public.pdc_pmb_arrival_ack_544 a
 ORDER BY a.vehicle_id, a.arrival_at DESC;
END $list$;
REVOKE ALL ON FUNCTION public.list_pmb_arrival_ack_544() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_pmb_arrival_ack_544() TO authenticated;

CREATE FUNCTION public.acknowledge_pmb_arrival_544(p_vehicle_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'public', 'auth' AS $ack$
DECLARE
 v_actor uuid := auth.uid();
 v_role text; v_email text; v_full text; v_display text; v_name text;
 v_stages text[]; v_dept jsonb; v_allowed boolean := false;
 v_open public.pdc_pmb_arrival_ack_544%ROWTYPE;
 v_done public.pdc_pmb_arrival_ack_544%ROWTYPE;
BEGIN
 IF v_actor IS NULL OR p_vehicle_id IS NULL THEN
  RETURN jsonb_build_object('ok', false, 'code', 'not_authorized');
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
 IF v_role IN ('operator', 'administrator') THEN
  v_allowed := true;
 ELSIF v_role = 'fitter' THEN
  -- Department staff: the login has no department. Match the staff-list name to a
  -- technician, then BUS_4X4 to department 138 only. The JWT name claim is not read.
  SELECT t.can_fit_stages INTO v_stages
  FROM public.workshop_technicians t
  WHERE t.active
    AND lower(btrim(t.name)) IN (lower(btrim(coalesce(v_full, ''))), lower(btrim(coalesce(v_display, ''))))
    AND btrim(t.name) <> ''
  ORDER BY t.sort_order NULLS LAST, t.name
  LIMIT 1;
  v_dept := public.pdc_vehicle_department_membership_20260919(p_vehicle_id);
  IF v_stages IS NOT NULL AND 'BUS_4X4' = ANY (v_stages) AND coalesce(v_dept->'department_codes', '[]'::jsonb) ? '138' THEN
   v_allowed := true;
  END IF;
 END IF;
 IF NOT v_allowed THEN
  RETURN jsonb_build_object('ok', false, 'code', 'not_authorized',
    'message', 'A controller can acknowledge any arrival. A fitter can acknowledge one only when their staff name is a Bus 4x4 technician and the vehicle is in Department 138.');
 END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('pdc-544:' || p_vehicle_id::text, 0));
 SELECT * INTO v_open FROM public.pdc_pmb_arrival_ack_544
  WHERE vehicle_id = p_vehicle_id AND acknowledged_at IS NULL
  ORDER BY arrival_at DESC LIMIT 1 FOR UPDATE;
 IF NOT FOUND THEN
  SELECT * INTO v_done FROM public.pdc_pmb_arrival_ack_544
   WHERE vehicle_id = p_vehicle_id AND acknowledged_at IS NOT NULL
   ORDER BY arrival_at DESC LIMIT 1;
  IF NOT FOUND THEN
   RETURN jsonb_build_object('ok', false, 'code', 'not_pending', 'message', 'This vehicle is not waiting in New to PMB.');
  END IF;
  RETURN jsonb_build_object('ok', true, 'code', 'already_acknowledged', 'data', jsonb_build_object(
    'vehicle_id', v_done.vehicle_id, 'acknowledged_at', v_done.acknowledged_at,
    'acknowledged_by_name', v_done.acknowledged_by_name, 'source', v_done.source));
 END IF;
 UPDATE public.pdc_pmb_arrival_ack_544 SET
  acknowledged_at = clock_timestamp(),
  acknowledged_by = v_actor,
  acknowledged_by_email = v_email,
  acknowledged_by_name = v_name,
  acknowledged_by_role = v_role
  WHERE ack_id = v_open.ack_id AND acknowledged_at IS NULL
  RETURNING * INTO v_done;
 IF v_done.ack_id IS NULL THEN
  RAISE EXCEPTION 'PDC_544_ACK_NOT_RECORDED' USING ERRCODE = '55000';
 END IF;
 RETURN jsonb_build_object('ok', true, 'code', 'acknowledged', 'data', jsonb_build_object(
  'vehicle_id', v_done.vehicle_id, 'acknowledged_at', v_done.acknowledged_at,
  'acknowledged_by_name', v_done.acknowledged_by_name, 'acknowledged_by_role', v_done.acknowledged_by_role,
  'source', v_open.source));
END $ack$;
REVOKE ALL ON FUNCTION public.acknowledge_pmb_arrival_544(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.acknowledge_pmb_arrival_544(uuid) TO authenticated;

INSERT INTO pdc_ops.regression_checks (check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES
('new_to_pmb_ack_544', 'F158',
 'New to PMB is an acknowledgement beside location PMB. The pin count stays 241. Pending rows do not change current_location. Controllers are operator and administrator. A fitter is department staff only for BUS_4X4 and department 138. The check uses search_path pg_catalog, schema-qualified types, and no regprocedure cast.',
 $chk544$
SELECT
  pins.n = 241
  AND added.n = 0
  AND tbl.relrowsecurity
  AND trg.present
  AND cap.present
  AND ack.present
  AND lst.present
  AND cap.no_vehicle_update
  AND ack.no_vehicle_update
  AND ack.no_user_metadata
  AND ack.controller
  AND ack.dept138
  AND cap.release_from
  AND ack.auth_exec
  AND ack.anon_blocked
  AND lst.auth_exec
  AND lst.anon_blocked
  AS ok,
  ('pins ' || pins.n::pg_catalog.text || ' | ' || coalesce(cap.note, 'capture missing'::pg_catalog.text)) AS detail
FROM (SELECT count(*) AS n FROM pdc_ops.expected_function_md5) pins
CROSS JOIN (SELECT count(*) AS n FROM pdc_ops.expected_function_md5 WHERE release = 'r544') added
CROSS JOIN (
  SELECT c.relrowsecurity
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'pdc_pmb_arrival_ack_544'
) tbl
CROSS JOIN (
  SELECT count(*) = 1 AS present
  FROM pg_catalog.pg_trigger t
  JOIN pg_catalog.pg_class c ON c.oid = t.tgrelid
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'vehicles' AND t.tgname = 'zz_pdc_pmb_arrival_ack_544' AND NOT t.tgisinternal
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
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'BUS_4X4') > 0 AND pg_catalog.strpos(p.prosrc, '138') > 0), false) AS dept138,
    coalesce(bool_and(pg_catalog.has_function_privilege('authenticated'::pg_catalog.name, p.oid, 'EXECUTE'::pg_catalog.text)), false) AS auth_exec,
    coalesce(bool_and(NOT pg_catalog.has_function_privilege('anon'::pg_catalog.name, p.oid, 'EXECUTE'::pg_catalog.text)), false) AS anon_blocked
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'acknowledge_pmb_arrival_544'
    AND pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_vehicle_id uuid'
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
$chk544$, true, 322, 'r544');

DO $post$
DECLARE r record; probe record;
BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r544: pin count changed'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r544') THEN RAISE EXCEPTION 'r544: a pin was inserted'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='new_to_pmb_ack_544' AND fault_id='F158' AND sort_order=322 AND added_in='r544' AND enabled)<>1 THEN RAISE EXCEPTION 'r544: check missing'; END IF;
 IF (SELECT count(*) FROM public.pdc_pmb_arrival_ack_544 WHERE source='backfill' AND acknowledged_by IS NULL AND acknowledged_at IS NOT NULL)
    <> (SELECT count(*) FROM public.vehicles WHERE deleted_at IS NULL AND upper(btrim(coalesce(current_location,'')))='PMB') THEN
  RAISE EXCEPTION 'r544: backfill does not match vehicles already at PMB';
 END IF;
 IF EXISTS (SELECT 1 FROM public.pdc_pmb_arrival_ack_544 WHERE acknowledged_at IS NULL) THEN RAISE EXCEPTION 'r544: backfill left an open row'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 FOR r IN SELECT check_name, check_sql FROM pdc_ops.regression_checks WHERE check_name='new_to_pmb_ack_544' LOOP
  EXECUTE r.check_sql INTO probe;
  IF coalesce(probe.ok, false) IS NOT TRUE THEN RAISE EXCEPTION 'r544: % failed: %', r.check_name, probe.detail; END IF;
 END LOOP;
END $post$;
