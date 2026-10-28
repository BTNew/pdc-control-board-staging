-- r593 (F207) undo. Staging cdsmnqxtyyoeoznmbidd only. Production is not a target.
-- Restores the r582 / r574 arrival capture, the close guard, and To PMB.
-- Reopens only the acknowledgement rows this release closed. Does not move a
-- vehicle, rewrite a booking, or change a pin. Department 135 and Kajel stay.

DO $pre$
BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN
  RAISE EXCEPTION 'r593 undo: run between :02 and :45';
 END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
    OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'r593 undo: staging only';
 END IF;
 IF pg_catalog.to_regclass('pdc_pmb_ack_private.ack_release_593') IS NULL THEN
  RAISE EXCEPTION 'r593 undo: release ledger is missing';
 END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN
  RAISE EXCEPTION 'r593 undo: pin count is not 241';
 END IF;
END $pre$;

ALTER TABLE public.pdc_pmb_arrival_557 DISABLE TRIGGER pdc_pmb_arrival_557_guard;
UPDATE public.pdc_pmb_arrival_557 a
   SET closed_at = NULL
  FROM pdc_pmb_ack_private.ack_release_593 rel
 WHERE a.arrival_id = rel.arrival_id
   AND a.closed_at IS NOT NULL
   AND NOT EXISTS (
     SELECT 1 FROM pdc_pmb_ack_private.bodybuilder_hold_574 h
     WHERE h.arrival_id = a.arrival_id AND h.release_action = 'to_pmb'
   );
ALTER TABLE public.pdc_pmb_arrival_557 ENABLE TRIGGER pdc_pmb_arrival_557_guard;

CREATE OR REPLACE FUNCTION pdc_pmb_ack_private.capture_557()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $capture574$
DECLARE
 v_old_loc text;
 v_old_over text;
 v_new_loc text := upper(btrim(coalesce(NEW.current_location, '')));
 v_new_over text := upper(btrim(coalesce(NEW.location_override, '')));
 v_old_eff text;
 v_new_eff text;
 v_key_changed boolean;
 v_source text;
 v_inserted integer := 0;
 v_body boolean;
 v_arrival uuid;
BEGIN
 -- Release from YARD HOLD, IN TRANSIT or OTHER (All vehicles), an importer
 -- INSERT, a manual move, and a location override all queue. QC, PIT and RFT
 -- returns do not. A vehicle already at PMB is left where it is.
 IF TG_OP = 'INSERT' THEN
  v_old_loc := '';
  v_old_over := '';
  v_key_changed := false;
 ELSE
  v_old_loc := upper(btrim(coalesce(OLD.current_location, '')));
  v_old_over := upper(btrim(coalesce(OLD.location_override, '')));
  v_key_changed := OLD.key_number IS DISTINCT FROM NEW.key_number AND btrim(coalesce(NEW.key_number, '')) <> '';
 END IF;
 v_old_eff := CASE WHEN v_old_over <> '' THEN v_old_over ELSE v_old_loc END;
 v_new_eff := CASE WHEN v_new_over <> '' THEN v_new_over ELSE v_new_loc END;
 IF v_new_eff <> 'PMB' OR NEW.deleted_at IS NOT NULL THEN RETURN NULL; END IF;
 IF v_old_eff IN ('PMB','QC','PIT','RFT') THEN RETURN NULL; END IF;
 v_body := pdc_pmb_ack_private.bodybuilder_delivery_574(NEW.id, NEW.source_payload);
 v_source := CASE WHEN v_body THEN 'bodybuilder' WHEN v_key_changed THEN 'key' ELSE 'location' END;
 -- A body-builder delivery that someone already sent with To PMB stays on PMB.
 -- Re-importing the same location does not open New to PMB again.
 IF v_body AND EXISTS (
   SELECT 1 FROM pdc_pmb_ack_private.bodybuilder_hold_574 h
   WHERE h.vehicle_id = NEW.id AND h.release_action = 'to_pmb'
 ) THEN
  RETURN NULL;
 END IF;
 BEGIN
  INSERT INTO public.pdc_pmb_arrival_557 (vehicle_id, previous_location, arrival_key, source)
  SELECT NEW.id, NULLIF(btrim(coalesce(CASE WHEN TG_OP = 'INSERT' THEN '' ELSE OLD.current_location END, '')), ''), NULLIF(btrim(coalesce(NEW.key_number, '')), ''), v_source
  WHERE NOT EXISTS (
    SELECT 1 FROM public.pdc_pmb_arrival_557 open_row
    WHERE open_row.vehicle_id = NEW.id AND open_row.closed_at IS NULL
  )
  RETURNING arrival_id INTO v_arrival;
  GET DIAGNOSTICS v_inserted = ROW_COUNT;
 EXCEPTION WHEN unique_violation THEN
  v_inserted := 0;
 END;
 IF v_inserted = 1 AND v_body AND v_arrival IS NOT NULL THEN
  INSERT INTO pdc_pmb_ack_private.bodybuilder_hold_574 (vehicle_id, arrival_id)
  VALUES (NEW.id, v_arrival);
 END IF;
 IF v_inserted = 1 THEN
  PERFORM pdc_pmb_ack_private.drop_read_caches_557();
 END IF;
 RETURN NULL;
END
$capture574$;

CREATE OR REPLACE FUNCTION pdc_pmb_ack_private.arrival_guard_557()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $guard574$
BEGIN
 IF TG_OP = 'DELETE' OR TG_OP = 'TRUNCATE' THEN
  RAISE EXCEPTION 'PDC_557_ACK_APPEND_ONLY: % on % is not allowed', TG_OP, TG_TABLE_NAME USING ERRCODE = '42501';
 END IF;
 IF OLD.closed_at IS NOT NULL THEN
  RAISE EXCEPTION 'PDC_557_ACK_APPEND_ONLY: this arrival is already finished' USING ERRCODE = '42501';
 END IF;
 IF NEW.arrival_id IS DISTINCT FROM OLD.arrival_id OR NEW.vehicle_id IS DISTINCT FROM OLD.vehicle_id OR NEW.arrival_at IS DISTINCT FROM OLD.arrival_at OR NEW.source IS DISTINCT FROM OLD.source OR NEW.previous_location IS DISTINCT FROM OLD.previous_location OR NEW.arrival_key IS DISTINCT FROM OLD.arrival_key OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
  RAISE EXCEPTION 'PDC_557_ACK_APPEND_ONLY: arrival identity cannot change' USING ERRCODE = '42501';
 END IF;
 IF NEW.closed_at IS NULL THEN
  RAISE EXCEPTION 'PDC_557_ACK_APPEND_ONLY: only closing the arrival is allowed' USING ERRCODE = '42501';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM public.vehicles v WHERE v.id = NEW.vehicle_id AND btrim(coalesce(v.key_number, '')) <> '') THEN
  RAISE EXCEPTION 'PDC_562_KEY_NUMBER_NEEDED: a key number is needed before this vehicle can move from New to PMB into PMB' USING ERRCODE = '23514';
 END IF;
 IF EXISTS (
   SELECT 1 FROM pdc_pmb_ack_private.bodybuilder_hold_574 h
   WHERE h.arrival_id = NEW.arrival_id AND h.released_at IS NULL
 ) AND current_setting('pdc.bodybuilder_to_pmb_574', true) IS DISTINCT FROM NEW.arrival_id::text THEN
  RAISE EXCEPTION 'PDC_574_TO_PMB_ONLY: a body-builder delivery stays in New to PMB until someone presses To PMB' USING ERRCODE = '23514';
 END IF;
 RETURN NEW;
END
$guard574$;

CREATE OR REPLACE FUNCTION public.push_new_to_pmb_562(p_vehicle_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $push574$
DECLARE
 v_actor uuid := auth.uid();
 v_role text;
 v_controller boolean := false;
 v_open public.pdc_pmb_arrival_557%ROWTYPE;
 v_relevant text[];
 v_has_key boolean;
BEGIN
 IF v_actor IS NULL OR p_vehicle_id IS NULL THEN
  RETURN jsonb_build_object('ok', false, 'code', 'not_authorized');
 END IF;
 SELECT r.role::text INTO v_role
 FROM public.pdc_user_roles r
 WHERE r.auth_user_id = v_actor AND r.active AND r.account_status = 'approved'
   AND lower(btrim(r.email)) = lower(btrim(coalesce(auth.jwt()->>'email', '')))
 ORDER BY r.updated_at DESC
 LIMIT 1;
 IF v_role IS NULL THEN
  RETURN jsonb_build_object('ok', false, 'code', 'not_authorized');
 END IF;
 v_controller := v_role IN ('operator', 'administrator');
 IF NOT v_controller THEN
  RETURN jsonb_build_object('ok', false, 'code', 'not_authorized', 'message', 'A controller moves a vehicle from New to PMB into PMB.');
 END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('pdc-557:' || p_vehicle_id::text, 0));
 SELECT * INTO v_open FROM public.pdc_pmb_arrival_557
  WHERE vehicle_id = p_vehicle_id AND closed_at IS NULL
  ORDER BY arrival_at DESC LIMIT 1 FOR UPDATE;
 IF NOT FOUND THEN
  RETURN jsonb_build_object('ok', false, 'code', 'not_pending', 'message', 'This vehicle is not waiting in New to PMB.');
 END IF;
 SELECT EXISTS (
   SELECT 1 FROM public.vehicles v
   WHERE v.id = p_vehicle_id AND btrim(coalesce(v.key_number, '')) <> ''
 ) INTO v_has_key;
 IF NOT v_has_key THEN
  RETURN jsonb_build_object('ok', false, 'code', 'key_number_needed',
    'message', 'A key number is needed before this vehicle can move from New to PMB into PMB.');
 END IF;
 v_relevant := pdc_pmb_ack_private.relevant_stations_557(p_vehicle_id);
 IF EXISTS (
   SELECT 1 FROM unnest(v_relevant) station_code
   WHERE NOT EXISTS (
     SELECT 1 FROM public.pdc_pmb_arrival_dept_ack_557 d
     WHERE d.arrival_id = v_open.arrival_id AND d.station_code = station_code
   )
 ) THEN
  RETURN jsonb_build_object('ok', false, 'code', 'stations_outstanding', 'message', 'Every workshop station still has to acknowledge this vehicle.');
 END IF;
 PERFORM set_config('pdc.bodybuilder_to_pmb_574', v_open.arrival_id::text, true);
 UPDATE public.pdc_pmb_arrival_557 SET closed_at = clock_timestamp()
  WHERE arrival_id = v_open.arrival_id AND closed_at IS NULL;
 UPDATE pdc_pmb_ack_private.bodybuilder_hold_574
  SET released_at = clock_timestamp(), released_by = v_actor, release_action = 'to_pmb'
  WHERE arrival_id = v_open.arrival_id AND released_at IS NULL;
 PERFORM pdc_pmb_ack_private.drop_read_caches_557();
 RETURN jsonb_build_object('ok', true, 'code', 'pushed', 'data', jsonb_build_object(
  'vehicle_id', p_vehicle_id, 'closed', true, 'needs_key', false));
END
$push574$;

DROP FUNCTION IF EXISTS public.list_new_to_pmb_window_593();
DROP TABLE IF EXISTS pdc_pmb_ack_private.new_to_pmb_window_593;
DROP TABLE IF EXISTS pdc_pmb_ack_private.ack_release_593;
DELETE FROM pdc_ops.regression_checks WHERE check_name = 'new_to_pmb_view_593' AND fault_id = 'F207' AND sort_order = 363 AND added_in = 'r593';

DO $post$
BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r593 undo: pin count changed'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release = 'r593') THEN RAISE EXCEPTION 'r593 undo: a pin remains'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name = 'new_to_pmb_view_593' OR fault_id = 'F207' OR added_in = 'r593') THEN
  RAISE EXCEPTION 'r593 undo: check remains';
 END IF;
 IF pg_catalog.to_regclass('pdc_pmb_ack_private.new_to_pmb_window_593') IS NOT NULL
    OR pg_catalog.to_regprocedure('public.list_new_to_pmb_window_593()') IS NOT NULL THEN
  RAISE EXCEPTION 'r593 undo: window remains';
 END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)'))
    IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN
  RAISE EXCEPTION 'r593 undo: department 135 changed';
 END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)'))
    IS DISTINCT FROM '9be0883b1a555f48f3c1ba9fa111c891'
    OR (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.pdc_pilbara_service_apply_v1(uuid,text,text)'))
    IS DISTINCT FROM 'b62fb7c29ffd2a1629f214f696e5cb14' THEN
  RAISE EXCEPTION 'r593 undo: Kajel import md5 changed';
 END IF;
END $post$;
