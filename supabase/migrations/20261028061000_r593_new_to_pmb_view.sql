-- r593 (F207) / sort 363. Craig approved go-live 28 Oct 2026 08:05 AWST.
-- Staging cdsmnqxtyyoeoznmbidd only. Production vjdtsswhroyguxyfjdkt is not a target.
--
-- Ledger tip required: hoist_place_after_592 (r592 / F206 / sort 360).
-- Left for the others: r589 / F203 / sort 361 is the Parts ETA go-live (#571).
-- r590 / F204 also names sort 361 (QC sign-off preview). r591 / F205 / sort 362
-- is the Revolution upload (#575). r584 / F198 / sort 356 stays with #498.
-- r588 / F202 is the live side-panel tick grid and has no check.
-- This release does not require sort 356, 361 or 362.
--
-- Craig, 28 Oct 2026 06:01 AWST, clarified 06:03 AWST: a Yard Hold vehicle or a
-- non-division vehicle that arrives off a truck is ticked To PMB, given a key
-- number, and goes straight into the PMB bucket. Nobody approves or acknowledges
-- it. New to PMB is a view of vehicles whose key number is under 4 days old.
-- Those vehicles stay in the PMB bucket as well. The tag and the counter are
-- display only. They do not change bookings, eligibility, stations or QC.
--
-- The key instant is public.pdc_vehicle_key_assigned_562.assigned_at. r562
-- already stores the earliest real source: the key audit (audit_460), a vehicle
-- audit event (audit_events), the service key snapshot (service_snapshot), or
-- the clock when a blank key is first filled (assigned). This release does not
-- invent a timestamp. A vehicle with no row in that table is not "new".
--
-- OD - Delivered To Bodybuilder still does not enter the PMB bucket by itself.
-- It waits until someone presses To PMB. The acknowledgement after that press
-- is gone: To PMB no longer waits for a department tick.
--
-- A read on 28 Oct 2026 about 06:10 AWST found 20 open acknowledgement rows and
-- no open body-builder hold. This file, when Craig applies it, closes those 20
-- and leaves location, bookings and keys untouched. The list is in
-- docs/REPORTED_FAULTS.md. Two of them have no key and no assignment time, so
-- they enter the PMB bucket and are not tagged. One is already at RFT.
--
-- Pin count stays 241. No pin is inserted. Department 135 fitter_job_command
-- stays fd05b9eef69498002ac06dd68e01cdff. Kajel's rows stay
-- 9be0883b1a555f48f3c1ba9fa111c891 and apply stays
-- b62fb7c29ffd2a1629f214f696e5cb14.
-- Undo: supabase/rollbacks/20261028061000_r593_new_to_pmb_view.down.sql

DO $pre$
BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN
  RAISE EXCEPTION 'r593: run between :02 and :45';
 END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
    OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'r593: staging only';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name = 'hoist_place_after_592' AND fault_id = 'F206' AND sort_order = 360 AND added_in = 'r592') THEN
  RAISE EXCEPTION 'r593: r592 / F206 sort 360 is not present';
 END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order = 363 OR fault_id = 'F207' OR check_name = 'new_to_pmb_view_593' OR added_in = 'r593') THEN
  RAISE EXCEPTION 'r593: sort 363 or F207 is taken';
 END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN
  RAISE EXCEPTION 'r593: pin count is not 241';
 END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release = 'r593') THEN
  RAISE EXCEPTION 'r593: a pin already claims this release';
 END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)'))
    IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN
  RAISE EXCEPTION 'r593: department 135 fitter_job_command is not fd05b9eef69498002ac06dd68e01cdff';
 END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)'))
    IS DISTINCT FROM '9be0883b1a555f48f3c1ba9fa111c891' THEN
  RAISE EXCEPTION 'r593: Kajel rows md5 changed';
 END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.pdc_pilbara_service_apply_v1(uuid,text,text)'))
    IS DISTINCT FROM 'b62fb7c29ffd2a1629f214f696e5cb14' THEN
  RAISE EXCEPTION 'r593: Kajel apply md5 changed';
 END IF;
 IF pg_catalog.to_regclass('public.pdc_vehicle_key_assigned_562') IS NULL
    OR pg_catalog.to_regprocedure('pdc_pmb_ack_private.capture_557()') IS NULL THEN
  RAISE EXCEPTION 'r593: key assignment or arrival capture is missing';
 END IF;
 PERFORM set_config('pdc.r593_pins', (SELECT count(*)::text FROM pdc_ops.expected_function_md5), true);
 PERFORM set_config('pdc.r593_pmb', (
   SELECT count(*)::text FROM public.vehicles
   WHERE deleted_at IS NULL AND upper(btrim(coalesce(current_location, ''))) = 'PMB'
 ), true);
 PERFORM set_config('pdc.r593_open', (SELECT count(*)::text FROM public.pdc_pmb_arrival_557 WHERE closed_at IS NULL), true);
END $pre$;

CREATE OR REPLACE FUNCTION pdc_pmb_ack_private.capture_557()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $capture593$
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
 -- INSERT, a manual move, and a location override all reach PMB. QC, PIT and RFT
 -- returns do not. A vehicle already at PMB is left where it is.
 -- r593_no_ack: only a body-builder delivery still opens New to PMB. Yard Hold,
 -- a non-division vehicle, and every other move are already in the PMB bucket.
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
 IF NOT v_body THEN
  RETURN NULL;
 END IF;
 IF EXISTS (
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
 IF v_inserted = 1 AND v_arrival IS NOT NULL THEN
  INSERT INTO pdc_pmb_ack_private.bodybuilder_hold_574 (vehicle_id, arrival_id)
  VALUES (NEW.id, v_arrival);
 END IF;
 IF v_inserted = 1 THEN
  PERFORM pdc_pmb_ack_private.drop_read_caches_557();
 END IF;
 RETURN NULL;
END
$capture593$;

CREATE OR REPLACE FUNCTION pdc_pmb_ack_private.arrival_guard_557()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $guard593$
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
 -- One-time release of an acknowledgement queue. A body-builder hold is not released here.
 IF current_setting('pdc.r593_release_ack', true) IS NOT DISTINCT FROM NEW.arrival_id::text
    AND NOT EXISTS (
      SELECT 1 FROM pdc_pmb_ack_private.bodybuilder_hold_574 h
      WHERE h.arrival_id = NEW.arrival_id AND h.released_at IS NULL
    ) THEN
  RETURN NEW;
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
$guard593$;

CREATE OR REPLACE FUNCTION public.push_new_to_pmb_562(p_vehicle_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $push593$
DECLARE
 v_actor uuid := auth.uid();
 v_role text;
 v_controller boolean := false;
 v_open public.pdc_pmb_arrival_557%ROWTYPE;
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
 -- r593: To PMB does not wait for a department acknowledgement.
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
$push593$;

CREATE TABLE pdc_pmb_ack_private.new_to_pmb_window_593 (
 singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
 days integer NOT NULL DEFAULT 4 CHECK (days >= 1 AND days <= 30)
);
INSERT INTO pdc_pmb_ack_private.new_to_pmb_window_593 (singleton, days) VALUES (true, 4);
ALTER TABLE pdc_pmb_ack_private.new_to_pmb_window_593 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE pdc_pmb_ack_private.new_to_pmb_window_593 FROM PUBLIC, anon, authenticated;
COMMENT ON TABLE pdc_pmb_ack_private.new_to_pmb_window_593 IS 'r593 (F207): how many days a key number stays on the New to PMB view. Display only. 4 for now.';

CREATE FUNCTION public.list_new_to_pmb_window_593()
 RETURNS integer
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $window593$
 SELECT days FROM pdc_pmb_ack_private.new_to_pmb_window_593 WHERE singleton;
$window593$;
REVOKE ALL ON FUNCTION public.list_new_to_pmb_window_593() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_new_to_pmb_window_593() TO authenticated;
COMMENT ON FUNCTION public.list_new_to_pmb_window_593() IS 'r593 (F207): the New to PMB view window in days. Display only. Does not read or write a vehicle, a booking, eligibility, a station or QC.';

CREATE TABLE pdc_pmb_ack_private.ack_release_593 (
 arrival_id uuid PRIMARY KEY,
 vehicle_id uuid NOT NULL,
 released_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE pdc_pmb_ack_private.ack_release_593 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE pdc_pmb_ack_private.ack_release_593 FROM PUBLIC, anon, authenticated;
COMMENT ON TABLE pdc_pmb_ack_private.ack_release_593 IS 'r593 (F207): acknowledgement rows closed when the queue was removed. The down file reopens these ids. Location and bookings are not stored here.';

DO $release$
DECLARE r record;
BEGIN
 FOR r IN
   SELECT a.arrival_id, a.vehicle_id
   FROM public.pdc_pmb_arrival_557 a
   WHERE a.closed_at IS NULL
     AND NOT EXISTS (
       SELECT 1 FROM pdc_pmb_ack_private.bodybuilder_hold_574 h
       WHERE h.arrival_id = a.arrival_id AND h.released_at IS NULL
     )
 LOOP
  INSERT INTO pdc_pmb_ack_private.ack_release_593 (arrival_id, vehicle_id)
  VALUES (r.arrival_id, r.vehicle_id);
  PERFORM set_config('pdc.r593_release_ack', r.arrival_id::text, true);
  UPDATE public.pdc_pmb_arrival_557
     SET closed_at = clock_timestamp()
   WHERE arrival_id = r.arrival_id AND closed_at IS NULL;
 END LOOP;
 PERFORM set_config('pdc.r593_release_ack', '', true);
END $release$;

INSERT INTO pdc_ops.regression_checks (check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES
('new_to_pmb_view_593', 'F207',
 'New to PMB is a display of key numbers under the stored day window, default 4. A non-bodybuilder move does not open an acknowledgement. A body-builder delivery still waits for To PMB. Booking functions are not replaced. The pin count stays 241. Department 135 and Kajel imports are unchanged. The check uses search_path pg_catalog, schema-qualified types, and no regprocedure cast.',
 $chk593$
SELECT
  pins.n = 241
  AND added.n = 0
  AND window_row.days = 4
  AND window_row.secured
  AND listed.present
  AND listed.auth_exec
  AND listed.anon_blocked
  AND listed.display_only
  AND cap.no_ack
  AND cap.holds
  AND cap.idempotent
  AND cap.no_vehicle_update
  AND cap.keeps_release
  AND guard.key_needed
  AND guard.to_pmb_only
  AND guard.one_time
  AND push.no_station_wait
  AND push.key_needed
  AND queue.only_holds
  AND book.untouched
  AND k135.same
  AND kajel.same
  AS ok,
  ('pins ' || pins.n::pg_catalog.text
    || ' | window ' || coalesce(window_row.days, 0)::pg_catalog.text
    || ' | open arrivals that are not a body-builder hold: ' || queue.strays::pg_catalog.text) AS detail
FROM (SELECT count(*) AS n FROM pdc_ops.expected_function_md5) pins
CROSS JOIN (SELECT count(*) AS n FROM pdc_ops.expected_function_md5 WHERE release = 'r593') added
CROSS JOIN (
  SELECT w.days, c.relrowsecurity AS secured
  FROM pdc_pmb_ack_private.new_to_pmb_window_593 w
  JOIN pg_catalog.pg_class c ON c.relname = 'new_to_pmb_window_593'
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'pdc_pmb_ack_private'
) window_row
CROSS JOIN (
  SELECT count(*) = 1 AS present,
    coalesce(bool_or(pg_catalog.has_function_privilege('authenticated'::pg_catalog.name, p.oid, 'EXECUTE'::pg_catalog.text)), false) AS auth_exec,
    coalesce(bool_and(NOT pg_catalog.has_function_privilege('anon'::pg_catalog.name, p.oid, 'EXECUTE'::pg_catalog.text)), false) AS anon_blocked,
    coalesce(bool_and(
      pg_catalog.strpos(p.prosrc, 'UPDATE public.vehicles') = 0
      AND pg_catalog.strpos(p.prosrc, 'workshop_create_booking') = 0
      AND pg_catalog.strpos(p.prosrc, 'user_metadata') = 0
      AND pg_catalog.strpos(p.prosrc, 'new_to_pmb_window_593') > 0
    ), false) AS display_only
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'list_new_to_pmb_window_593'
) listed
CROSS JOIN (
  SELECT
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'r593_no_ack') > 0 AND pg_catalog.strpos(p.prosrc, 'IF NOT v_body THEN') > 0), false) AS no_ack,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'bodybuilder_hold_574') > 0), false) AS holds,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'release_action = ''to_pmb''') > 0), false) AS idempotent,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'UPDATE public.vehicles') = 0), false) AS no_vehicle_update,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'YARD HOLD') > 0 AND pg_catalog.strpos(p.prosrc, 'IN TRANSIT') > 0 AND pg_catalog.strpos(p.prosrc, 'OTHER') > 0), false) AS keeps_release
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'pdc_pmb_ack_private' AND p.proname = 'capture_557'
) cap
CROSS JOIN (
  SELECT
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'PDC_562_KEY_NUMBER_NEEDED') > 0), false) AS key_needed,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'PDC_574_TO_PMB_ONLY') > 0), false) AS to_pmb_only,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'pdc.r593_release_ack') > 0), false) AS one_time
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'pdc_pmb_ack_private' AND p.proname = 'arrival_guard_557'
) guard
CROSS JOIN (
  SELECT
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'stations_outstanding') = 0 AND pg_catalog.strpos(p.prosrc, 'pdc.bodybuilder_to_pmb_574') > 0), false) AS no_station_wait,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'key_number_needed') > 0), false) AS key_needed
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'push_new_to_pmb_562'
    AND pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_vehicle_id uuid'
) push
CROSS JOIN (
  SELECT count(*) AS strays,
    count(*) = 0 AS only_holds
  FROM public.pdc_pmb_arrival_557 a
  WHERE a.closed_at IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM pdc_pmb_ack_private.bodybuilder_hold_574 h
      WHERE h.arrival_id = a.arrival_id AND h.released_at IS NULL
    )
) queue
CROSS JOIN (
  SELECT count(DISTINCT p.proname) = 3 AS untouched
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN ('workshop_create_booking', 'schedule_vehicle_work', 'administrator_schedule_workshop_vehicle')
    AND pg_catalog.strpos(p.prosrc, 'r593') = 0
) book
CROSS JOIN (
  SELECT (SELECT md5(p.prosrc)
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'karratha135_pdc' AND p.proname = 'fitter_job_command'
      AND pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_technician_id uuid, p_booking_id uuid, p_expected_version integer, p_catalog_hash text, p_request_id uuid, p_action text, p_line_identity text, p_completed boolean, p_note text'
  ) IS NOT DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' AS same
) k135
CROSS JOIN (
  SELECT (SELECT md5(p.prosrc)
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'pdc_codex_intake_private' AND p.proname = 'revolution_service_rows_20261006'
      AND pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_rows jsonb'
  ) IS NOT DISTINCT FROM '9be0883b1a555f48f3c1ba9fa111c891'
  AND (SELECT md5(p.prosrc)
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'pdc_pilbara_service_apply_v1'
      AND pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_preview_batch_id uuid, p_source_hash text, p_idempotency_key text'
  ) IS NOT DISTINCT FROM 'b62fb7c29ffd2a1629f214f696e5cb14' AS same
) kajel
$chk593$, true, 363, 'r593');

DO $post$
DECLARE r record; probe record;
BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r593: pin count changed'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release = 'r593') THEN RAISE EXCEPTION 'r593: a pin was inserted'; END IF;
 IF current_setting('pdc.r593_pmb', true) IS DISTINCT FROM (
   SELECT count(*)::text FROM public.vehicles
   WHERE deleted_at IS NULL AND upper(btrim(coalesce(current_location, ''))) = 'PMB'
 ) THEN RAISE EXCEPTION 'r593: PMB vehicle count changed'; END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)'))
    IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN
  RAISE EXCEPTION 'r593: department 135 fitter_job_command changed';
 END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)'))
    IS DISTINCT FROM '626ca8b23a2e5f02e2ca8f96a4533d6f' THEN
  RAISE EXCEPTION 'r593: fitter command changed';
 END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)'))
    IS DISTINCT FROM '9be0883b1a555f48f3c1ba9fa111c891'
    OR (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p WHERE p.oid = pg_catalog.to_regprocedure('public.pdc_pilbara_service_apply_v1(uuid,text,text)'))
    IS DISTINCT FROM 'b62fb7c29ffd2a1629f214f696e5cb14' THEN
  RAISE EXCEPTION 'r593: Kajel import md5 changed';
 END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name = 'new_to_pmb_view_593' AND fault_id = 'F207' AND sort_order = 363 AND added_in = 'r593' AND enabled) <> 1 THEN
  RAISE EXCEPTION 'r593: check missing';
 END IF;
 PERFORM set_config('search_path', 'pg_catalog', true);
 FOR r IN SELECT check_name, check_sql FROM pdc_ops.regression_checks WHERE check_name = 'new_to_pmb_view_593' LOOP
  EXECUTE r.check_sql INTO probe;
  IF coalesce(probe.ok, false) IS NOT TRUE THEN RAISE EXCEPTION 'r593: % failed: %', r.check_name, probe.detail; END IF;
 END LOOP;
END $post$;
