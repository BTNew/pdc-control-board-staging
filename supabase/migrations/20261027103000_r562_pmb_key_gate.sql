-- r562 (F176) / sort 335. Craig approved go-live 27 Oct 2026 08:10 AWST.
-- Staging cdsmnqxtyyoeoznmbidd only. Production vjdtsswhroyguxyfjdkt is not a target.
--
-- Ledger at apply: r559 / F173 / sort 334 is bay_default_clock_gap_559.
-- r560 / F174 is the stock side panel (frontend, no sort).
-- r561 / F175 is the slim planner header (frontend, no sort).
-- Next free is r562 / F176 / sort 335. Unmerged #544 titled itself r562 / F176;
-- this release goes first and #544 renumbers later.
--
-- Craig, 27 Oct 2026 07:33 AWST: a vehicle that arrives at PMB waits in New to PMB
-- and cannot be pushed into PMB unless it has a key number.
-- Craig, 27 Oct 2026 07:34 AWST: the PMB age counts from when the key number was
-- assigned. A vehicle with no key number has no PMB age.
--
-- Paths into New to PMB (open arrival, current_location stays PMB):
--   release from All vehicles / In transit / Yard Hold (already r557),
--   an importer INSERT already at PMB, a manual move, and a location override.
--   A return from QC, PIT or RFT does not queue. A vehicle already at PMB,
--   including the r557 backfill, is not queued again.
--
-- Leaving New to PMB (closing the arrival) requires a non-blank key number.
-- The arrival guard enforces that for every UPDATE, including acknowledgement
-- completion, push_new_to_pmb_562, and any other RPC. A new arrival cannot be
-- inserted already closed.
--
-- Key assignment time is not a column on vehicles. r460 stores each change in
-- public.pdc_vehicle_key_number_audit_460. Older keys are in public.audit_events
-- and in pdc_codex_intake_private.service_location_fields.snapshot_at.
-- This release records public.pdc_vehicle_key_assigned_562 from the earliest of
-- those three, and a trigger keeps it from now on. Clearing the key removes the
-- row. Replacing one key with another keeps the original time.
-- Read-only count before this file was written, nothing written:
--   location PMB 248, closed backfill 243, open New to PMB 5, of which 0 have
--   no key number. 14 of the vehicles already at PMB have no key number. They
--   stay on the PMB tile. 234 keyed PMB vehicles all had at least one of the
--   three history sources.
-- Pin count stays 241. No pin is inserted. The pinned location snapshot is not
-- edited. The board reads the time from list_pmb_key_assigned_562.
-- Undo: supabase/rollbacks/20261027103000_r562_pmb_key_gate.down.sql

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r562: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r562: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r562: pin count is not 241'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='bay_default_clock_gap_559' AND fault_id='F173' AND sort_order=334 AND added_in='r559') THEN RAISE EXCEPTION 'r562: r559 / F173 sort 334 is not present'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='new_to_pmb_ack_557' AND fault_id='F171' AND sort_order=332 AND added_in='r557') THEN RAISE EXCEPTION 'r562: r557 / F171 sort 332 is not present'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=335 OR fault_id='F176' OR check_name='pmb_key_gate_562' OR added_in='r562') THEN RAISE EXCEPTION 'r562: sort 335 or F176 is taken'; END IF;
 IF pg_catalog.to_regclass('public.pdc_vehicle_key_assigned_562') IS NOT NULL
    OR EXISTS (
      SELECT 1 FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname IN ('push_new_to_pmb_562','list_pmb_key_assigned_562')
    ) THEN RAISE EXCEPTION 'r562: already applied'; END IF;
 PERFORM set_config('pdc.r562_pins', (SELECT count(*)::text FROM pdc_ops.expected_function_md5), true);
 PERFORM set_config('pdc.r562_pmb', (SELECT count(*)::text FROM public.vehicles WHERE deleted_at IS NULL AND upper(btrim(coalesce(current_location, '')))='PMB'), true);
 PERFORM set_config('pdc.r562_backfill', (SELECT count(*)::text FROM public.pdc_pmb_arrival_557 WHERE source='backfill' AND closed_at IS NOT NULL), true);
 PERFORM set_config('pdc.r562_open', (SELECT count(*)::text FROM public.pdc_pmb_arrival_557 WHERE closed_at IS NULL), true);
END $g$;

CREATE TABLE public.pdc_vehicle_key_assigned_562 (
 vehicle_id uuid PRIMARY KEY,
 assigned_at timestamptz NOT NULL,
 source text NOT NULL CHECK (source IN ('audit_460','audit_events','service_snapshot','assigned')),
 assigned_key text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_vehicle_key_assigned_562 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_vehicle_key_assigned_562 FROM PUBLIC, anon, authenticated;
COMMENT ON TABLE public.pdc_vehicle_key_assigned_562 IS 'r562 (F176): when this vehicle first had a key number. The PMB age starts here. A blank key has no row.';

INSERT INTO public.pdc_vehicle_key_assigned_562 (vehicle_id, assigned_at, source, assigned_key)
SELECT picked.id, picked.assigned_at, picked.source, picked.assigned_key
FROM (
  SELECT k.id, k.assigned_key, src.assigned_at, src.source
  FROM (
    SELECT v.id, btrim(v.key_number) AS assigned_key
    FROM public.vehicles v
    WHERE v.deleted_at IS NULL AND btrim(coalesce(v.key_number, '')) <> ''
  ) k
  CROSS JOIN LATERAL (
    SELECT assigned_at, source
    FROM (
      SELECT min(a.changed_at) AS assigned_at, 'audit_460'::text AS source
      FROM public.pdc_vehicle_key_number_audit_460 a
      WHERE a.vehicle_id = k.id AND btrim(coalesce(a.new_value, '')) <> ''
      UNION ALL
      SELECT min(e.created_at), 'audit_events'
      FROM public.audit_events e
      WHERE e.vehicle_id = k.id AND e.table_name = 'vehicles'
        AND btrim(coalesce(e.after_data->>'key_number', '')) <> ''
        AND e.before_data->>'key_number' IS DISTINCT FROM e.after_data->>'key_number'
      UNION ALL
      SELECT min(s.snapshot_at), 'service_snapshot'
      FROM pdc_codex_intake_private.service_location_fields s
      WHERE s.vehicle_id = k.id
        AND CASE WHEN s.vehicle_key_number ~ '^[0-9]+$' THEN s.vehicle_key_number::numeric > 0 ELSE false END
    ) candidates
    WHERE assigned_at IS NOT NULL
    ORDER BY assigned_at ASC, source ASC
    LIMIT 1
  ) src
) picked;

CREATE FUNCTION pdc_pmb_ack_private.capture_key_assigned_562() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $key562$
DECLARE
 v_new text := nullif(btrim(coalesce(NEW.key_number, '')), '');
 v_old text := CASE WHEN TG_OP = 'UPDATE' THEN nullif(btrim(coalesce(OLD.key_number, '')), '') ELSE NULL END;
BEGIN
 IF v_new IS NULL THEN
  DELETE FROM public.pdc_vehicle_key_assigned_562 WHERE vehicle_id = NEW.id;
  RETURN NULL;
 END IF;
 IF v_old IS NULL THEN
  INSERT INTO public.pdc_vehicle_key_assigned_562 (vehicle_id, assigned_at, source, assigned_key)
  VALUES (NEW.id, clock_timestamp(), 'assigned', v_new)
  ON CONFLICT (vehicle_id) DO UPDATE
    SET assigned_key = EXCLUDED.assigned_key
    WHERE pdc_vehicle_key_assigned_562.vehicle_id = EXCLUDED.vehicle_id
      AND pdc_vehicle_key_assigned_562.assigned_at IS NOT NULL;
  RETURN NULL;
 END IF;
 UPDATE public.pdc_vehicle_key_assigned_562
    SET assigned_key = v_new
  WHERE vehicle_id = NEW.id;
 IF NOT FOUND THEN
  INSERT INTO public.pdc_vehicle_key_assigned_562 (vehicle_id, assigned_at, source, assigned_key)
  VALUES (NEW.id, clock_timestamp(), 'assigned', v_new);
 END IF;
 RETURN NULL;
END $key562$;
REVOKE ALL ON FUNCTION pdc_pmb_ack_private.capture_key_assigned_562() FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER zz_pdc_key_assigned_562_ins
 AFTER INSERT ON public.vehicles
 FOR EACH ROW
 WHEN (btrim(coalesce(NEW.key_number, '')) <> '')
 EXECUTE FUNCTION pdc_pmb_ack_private.capture_key_assigned_562();
CREATE TRIGGER zz_pdc_key_assigned_562
 AFTER UPDATE OF key_number ON public.vehicles
 FOR EACH ROW
 WHEN (OLD.key_number IS DISTINCT FROM NEW.key_number)
 EXECUTE FUNCTION pdc_pmb_ack_private.capture_key_assigned_562();

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
 IF NOT EXISTS (
   SELECT 1 FROM public.vehicles v
   WHERE v.id = NEW.vehicle_id AND btrim(coalesce(v.key_number, '')) <> ''
 ) THEN
  RAISE EXCEPTION 'PDC_562_KEY_NUMBER_NEEDED: a key number is needed before this vehicle can move from New to PMB into PMB' USING ERRCODE = '23514';
 END IF;
 RETURN NEW;
END $lock$;

CREATE FUNCTION pdc_pmb_ack_private.arrival_insert_guard_562() RETURNS trigger
LANGUAGE plpgsql SET search_path TO 'pg_catalog' AS $ins562$
BEGIN
 IF NEW.closed_at IS NOT NULL THEN
  RAISE EXCEPTION 'PDC_562_OPEN_ARRIVAL_ONLY: a new arrival stays in New to PMB until it is closed with a key number' USING ERRCODE = '23514';
 END IF;
 RETURN NEW;
END $ins562$;
REVOKE ALL ON FUNCTION pdc_pmb_ack_private.arrival_insert_guard_562() FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER pdc_pmb_arrival_557_insert_guard
 BEFORE INSERT ON public.pdc_pmb_arrival_557
 FOR EACH ROW EXECUTE FUNCTION pdc_pmb_ack_private.arrival_insert_guard_562();

CREATE OR REPLACE FUNCTION pdc_pmb_ack_private.capture_557() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $cap$
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
 v_source := CASE WHEN v_key_changed THEN 'key' ELSE 'location' END;
 BEGIN
  INSERT INTO public.pdc_pmb_arrival_557 (vehicle_id, previous_location, arrival_key, source)
  SELECT NEW.id, NULLIF(btrim(coalesce(CASE WHEN TG_OP = 'INSERT' THEN '' ELSE OLD.current_location END, '')), ''), NULLIF(btrim(coalesce(NEW.key_number, '')), ''), v_source
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

DROP TRIGGER IF EXISTS zz_pdc_pmb_arrival_557 ON public.vehicles;
CREATE TRIGGER zz_pdc_pmb_arrival_557
 AFTER INSERT OR UPDATE OF current_location, key_number, location_override ON public.vehicles
 FOR EACH ROW
 WHEN (
  NEW.deleted_at IS NULL
  AND (
    upper(btrim(coalesce(NEW.current_location, ''))) = 'PMB'
    OR upper(btrim(coalesce(NEW.location_override, ''))) = 'PMB'
  )
 )
 EXECUTE FUNCTION pdc_pmb_ack_private.capture_557();

CREATE OR REPLACE FUNCTION pdc_pmb_ack_private.state_557(p_arrival_id uuid, p_vehicle_id uuid, p_controller boolean, p_actor uuid, p_open boolean)
 RETURNS jsonb
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public' AS $view$
DECLARE
 v_relevant text[];
 v_mine text[];
 v_departments jsonb;
 v_pending boolean;
 v_has_key boolean;
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
 SELECT EXISTS (
   SELECT 1 FROM public.vehicles v
   WHERE v.id = p_vehicle_id AND btrim(coalesce(v.key_number, '')) <> ''
 ) INTO v_has_key;
 v_pending := p_open AND (
   EXISTS (
     SELECT 1 FROM jsonb_array_elements(v_departments) item
     WHERE (item->>'pending') = 'true'
       AND (p_controller OR (item->>'station') = ANY (v_mine))
   )
   OR (p_controller AND (NOT coalesce(v_has_key, false) OR coalesce(cardinality(v_relevant), 0) = 0))
 );
 RETURN jsonb_build_object('viewer_pending', v_pending, 'departments', v_departments, 'needs_key', NOT coalesce(v_has_key, false));
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
 v_has_key boolean;
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
 SELECT EXISTS (
   SELECT 1 FROM public.vehicles v
   WHERE v.id = p_vehicle_id AND btrim(coalesce(v.key_number, '')) <> ''
 ) INTO v_has_key;
 IF NOT v_has_key AND NOT EXISTS (
   SELECT 1 FROM unnest(v_relevant) station_code
   WHERE station_code <> v_station
     AND NOT EXISTS (
       SELECT 1 FROM public.pdc_pmb_arrival_dept_ack_557 d
       WHERE d.arrival_id = v_open.arrival_id AND d.station_code = station_code
     )
 ) THEN
  RETURN jsonb_build_object('ok', false, 'code', 'key_number_needed',
    'message', 'A key number is needed before this vehicle can move from New to PMB into PMB.');
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

CREATE FUNCTION public.push_new_to_pmb_562(p_vehicle_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog', 'public', 'auth' AS $push562$
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
 UPDATE public.pdc_pmb_arrival_557 SET closed_at = clock_timestamp()
  WHERE arrival_id = v_open.arrival_id AND closed_at IS NULL;
 PERFORM pdc_pmb_ack_private.drop_read_caches_557();
 RETURN jsonb_build_object('ok', true, 'code', 'pushed', 'data', jsonb_build_object(
  'vehicle_id', p_vehicle_id, 'closed', true, 'needs_key', false));
END $push562$;
REVOKE ALL ON FUNCTION public.push_new_to_pmb_562(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.push_new_to_pmb_562(uuid) TO authenticated;

CREATE FUNCTION public.list_pmb_key_assigned_562()
 RETURNS TABLE (vehicle_id uuid, assigned_at timestamptz, has_key boolean)
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog', 'public', 'auth' AS $list562$
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
 SELECT v.id, a.assigned_at, (btrim(coalesce(v.key_number, '')) <> '')
 FROM public.vehicles v
 LEFT JOIN public.pdc_vehicle_key_assigned_562 a ON a.vehicle_id = v.id
 WHERE v.deleted_at IS NULL
   AND (
     upper(btrim(coalesce(v.current_location, ''))) IN ('PMB','QC','PIT','RFT')
     OR upper(btrim(coalesce(v.location_override, ''))) IN ('PMB','QC')
     OR a.vehicle_id IS NOT NULL
   );
END $list562$;
REVOKE ALL ON FUNCTION public.list_pmb_key_assigned_562() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_pmb_key_assigned_562() TO authenticated;

INSERT INTO pdc_ops.regression_checks (check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES
('pmb_key_gate_562', 'F176',
 'A vehicle enters New to PMB before PMB, including an importer insert and a location override, and cannot leave New to PMB without a key number. The PMB age is stored from the key assignment, backfilled from the key audit, vehicle audit events, or the service key snapshot. The pin count stays 241. Existing closed backfill arrivals stay closed. The check uses search_path pg_catalog, schema-qualified types, and no regprocedure cast.',
 $chk562$
SELECT
  pins.n = 241
  AND added.n = 0
  AND keyed.relrowsecurity
  AND cap.present
  AND cap.keeps_release
  AND cap.covers_insert
  AND cap.no_vehicle_update
  AND cap.skips_existing
  AND guard.key_needed
  AND ins.blocks_closed
  AND ack.present
  AND ack.key_needed
  AND ack.no_vehicle_update
  AND ack.stations
  AND push.present
  AND push.key_needed
  AND push.auth_exec
  AND push.anon_blocked
  AND ages.present
  AND ages.auth_exec
  AND ages.anon_blocked
  AND trg.present
  AND keytrg.present
  AND backfill.still_closed
  AS ok,
  ('pins ' || pins.n::pg_catalog.text || ' | open arrivals stay in New to PMB until a key number is present') AS detail
FROM (SELECT count(*) AS n FROM pdc_ops.expected_function_md5) pins
CROSS JOIN (SELECT count(*) AS n FROM pdc_ops.expected_function_md5 WHERE release = 'r562') added
CROSS JOIN (
  SELECT c.relrowsecurity
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'pdc_vehicle_key_assigned_562'
) keyed
CROSS JOIN (
  SELECT
    count(*) = 1 AS present,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'YARD HOLD') > 0 AND pg_catalog.strpos(p.prosrc, 'IN TRANSIT') > 0 AND pg_catalog.strpos(p.prosrc, 'OTHER') > 0), false) AS keeps_release,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'INSERT') > 0 AND pg_catalog.strpos(p.prosrc, 'location_override') > 0), false) AS covers_insert,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'UPDATE public.vehicles') = 0), false) AS no_vehicle_update,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'PMB') > 0 AND pg_catalog.strpos(p.prosrc, 'QC') > 0 AND pg_catalog.strpos(p.prosrc, 'PIT') > 0 AND pg_catalog.strpos(p.prosrc, 'RFT') > 0), false) AS skips_existing
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'pdc_pmb_ack_private' AND p.proname = 'capture_557'
) cap
CROSS JOIN (
  SELECT coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'PDC_562_KEY_NUMBER_NEEDED') > 0), false) AS key_needed
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'pdc_pmb_ack_private' AND p.proname = 'arrival_guard_557'
) guard
CROSS JOIN (
  SELECT coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'PDC_562_OPEN_ARRIVAL_ONLY') > 0), false) AS blocks_closed
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'pdc_pmb_ack_private' AND p.proname = 'arrival_insert_guard_562'
) ins
CROSS JOIN (
  SELECT
    count(*) = 1 AS present,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'key_number_needed') > 0), false) AS key_needed,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'UPDATE public.vehicles') = 0), false) AS no_vehicle_update,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'FITTING') > 0 AND pg_catalog.strpos(p.prosrc, 'FABRICATION') > 0 AND pg_catalog.strpos(p.prosrc, 'HOIST') > 0 AND pg_catalog.strpos(p.prosrc, 'ELECTRICAL') > 0), false) AS stations
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'acknowledge_pmb_arrival_557'
    AND pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_vehicle_id uuid, p_station text'
) ack
CROSS JOIN (
  SELECT
    count(*) = 1 AS present,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'key_number_needed') > 0), false) AS key_needed,
    coalesce(bool_and(pg_catalog.has_function_privilege('authenticated'::pg_catalog.name, p.oid, 'EXECUTE'::pg_catalog.text)), false) AS auth_exec,
    coalesce(bool_and(NOT pg_catalog.has_function_privilege('anon'::pg_catalog.name, p.oid, 'EXECUTE'::pg_catalog.text)), false) AS anon_blocked
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'push_new_to_pmb_562'
    AND pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_vehicle_id uuid'
) push
CROSS JOIN (
  SELECT
    count(*) = 1 AS present,
    coalesce(bool_and(pg_catalog.has_function_privilege('authenticated'::pg_catalog.name, p.oid, 'EXECUTE'::pg_catalog.text)), false) AS auth_exec,
    coalesce(bool_and(NOT pg_catalog.has_function_privilege('anon'::pg_catalog.name, p.oid, 'EXECUTE'::pg_catalog.text)), false) AS anon_blocked
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'list_pmb_key_assigned_562'
    AND pg_catalog.pg_get_function_identity_arguments(p.oid) = ''::pg_catalog.text
) ages
CROSS JOIN (
  SELECT count(*) = 1 AS present
  FROM pg_catalog.pg_trigger t
  JOIN pg_catalog.pg_class c ON c.oid = t.tgrelid
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'vehicles' AND t.tgname = 'zz_pdc_pmb_arrival_557' AND NOT t.tgisinternal
) trg
CROSS JOIN (
  SELECT count(*) = 2 AS present
  FROM pg_catalog.pg_trigger t
  JOIN pg_catalog.pg_class c ON c.oid = t.tgrelid
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname = 'vehicles'
    AND t.tgname IN ('zz_pdc_key_assigned_562','zz_pdc_key_assigned_562_ins')
    AND NOT t.tgisinternal
) keytrg
CROSS JOIN (
  SELECT NOT EXISTS (
    SELECT 1 FROM public.pdc_pmb_arrival_557
    WHERE source = 'backfill' AND closed_at IS NULL
  ) AS still_closed
) backfill
$chk562$, true, 335, 'r562');

DO $post$
DECLARE r record; probe record;
BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r562: pin count changed'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r562') THEN RAISE EXCEPTION 'r562: a pin was inserted'; END IF;
 IF current_setting('pdc.r562_pmb', true) IS DISTINCT FROM (SELECT count(*)::text FROM public.vehicles WHERE deleted_at IS NULL AND upper(btrim(coalesce(current_location, '')))='PMB') THEN RAISE EXCEPTION 'r562: PMB vehicle count changed'; END IF;
 IF current_setting('pdc.r562_backfill', true) IS DISTINCT FROM (SELECT count(*)::text FROM public.pdc_pmb_arrival_557 WHERE source='backfill' AND closed_at IS NOT NULL) THEN RAISE EXCEPTION 'r562: closed backfill count changed'; END IF;
 IF current_setting('pdc.r562_open', true) IS DISTINCT FROM (SELECT count(*)::text FROM public.pdc_pmb_arrival_557 WHERE closed_at IS NULL) THEN RAISE EXCEPTION 'r562: open New to PMB count changed'; END IF;
 IF current_setting('pdc.r562_pins', true) IS DISTINCT FROM '241' THEN RAISE EXCEPTION 'r562: pin count changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='pmb_key_gate_562' AND fault_id='F176' AND sort_order=335 AND added_in='r562' AND enabled)<>1 THEN RAISE EXCEPTION 'r562: check missing'; END IF;
 PERFORM set_config('search_path','pg_catalog', true);
 FOR r IN SELECT check_name, check_sql FROM pdc_ops.regression_checks WHERE check_name='pmb_key_gate_562' LOOP
  EXECUTE r.check_sql INTO probe;
  IF coalesce(probe.ok, false) IS NOT TRUE THEN RAISE EXCEPTION 'r562: % failed: %', r.check_name, probe.detail; END IF;
 END LOOP;
END $post$;
