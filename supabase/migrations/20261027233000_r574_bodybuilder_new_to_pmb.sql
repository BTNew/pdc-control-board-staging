-- r582 (F195) / sort 353. Go-live. Staging cdsmnqxtyyoeoznmbidd only.
-- The preview claimed r574 / F188 / sort 345. That triple is pmb_dept_ack_book_574.
-- r578 stays free for the station-icon release. r580 is on the ledger from the
-- rolled-back parts stoppage. r581 / F194 / sort 352 is parts_eta_stoppage_573.
-- F191 and sort 349 stay free for the bay-manager rework. F193 and sort 351 stay unused.
-- Object names and the check name stay _574.
-- Staging cdsmnqxtyyoeoznmbidd only. Production vjdtsswhroyguxyfjdkt is not a target.
--
-- Craig, 27 Oct 2026 13:21 AWST: a vehicle whose Navision location is
-- "OD - Delivered To Bodybuilder" must not land on the PMB tile by itself.
-- It waits in New to PMB so someone can confirm the key number, then they
-- press the existing To PMB button. A key that is already on the vehicle
-- does not skip that wait.
--
-- The live feed spells that location OD + "Delivered - At Body Builder".
-- public.navision_exact_lifecycle_status folds that to deliveredatbodybuilder.
-- Craig's wording folds to deliveredtobodybuilder and oddeliveredtobodybuilder.
-- Those three are the body-builder delivery. "Delivered - At Dealer",
-- "Despatched - From Body Builder" and "Ready For Transport - From Body Builder"
-- are different and stay as they are.
--
-- Paths that were putting this location on the PMB tile:
--   1. public.navision_operational_location returns PMB for deliveredatbodybuilder.
--   2. public.pdc_project_linked_navision_location_20260905 writes current_location PMB
--      when that status is current and the vehicle is not already latched.
--   3. Importers and reconciles that trust navision_operational_location
--      (import_pdc_authenticated_backend_batches, the generic Navision enrichment,
--      the scoped activation, the hidden-vehicle restore, and the pre134/pre171
--      operational reconciles) write the same PMB location. The vehicles trigger
--      zz_pdc_pmb_arrival_557 sees every one of those writes.
--   4. vehicle-location-lifecycle.js resolveVehicleLifecycleLocation returned PMB
--      with transition released_to_pmb for "delivered - at body builder".
--   5. Key-present bypass: acknowledge_pmb_arrival_557 closed the arrival when the
--      last station was acknowledged and a key was already present, so the vehicle
--      left New to PMB without To PMB. state_557 then set viewer_pending false
--      once a key was present and no station was still outstanding.
--
-- What stays PMB underneath: current_location remains PMB. New to PMB is the open
-- arrival in front of that location, which is how r557 and r562 already work.
-- This release does not move a vehicle that is already at PMB. A staging read
-- on 27 Oct 2026, while imports were still landing, found 194 current Navision
-- records, 148 linked vehicles, and 136 of those already at PMB (124 with a key,
-- 118 visible, 5 with an open arrival). Four more were not latched and would
-- enter New to PMB on the next import. None of those rows are updated here.
-- The apply records the PMB count and fails if this migration changes it.
--
-- A later import of the same location does not open a second New to PMB row
-- after someone has pressed To PMB. Department 135 (karratha135_pdc) is not
-- edited. Broome Sales 37047 and Karratha Sales 14450 are not written.
-- Pin count stays 241. No pin is inserted. r571 / F185 / sort 343 stays free
-- for #559. r573 / F187 / sort 344 is the hours-wording preview already on staging.
--
-- The check bodybuilder_new_to_pmb_574 goes red if, after this apply, a vehicle
-- reached the PMB tile from this location without a user To PMB action.
-- Department 135 and the sales tile hashes are stored on bodybuilder_rule_574
-- when this applies. Later runs of the check read those columns. A transaction
-- setting would be empty after the apply and would leave the check red.

DO $pre$
BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN
  RAISE EXCEPTION 'r582: run between :02 and :45';
 END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
    OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'r582: staging only';
 END IF;
 IF EXISTS (
   SELECT 1 FROM pdc_ops.regression_checks
   WHERE sort_order = 353 OR fault_id = 'F195' OR added_in = 'r582'
      OR check_name = 'bodybuilder_new_to_pmb_574'
 ) THEN
  RAISE EXCEPTION 'r582: sort 353 or F195 is taken';
 END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN
  RAISE EXCEPTION 'r582: pin count is not 241';
 END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release = 'r582') THEN
  RAISE EXCEPTION 'r582: a pin already claims this release';
 END IF;
 IF to_regprocedure('pdc_pmb_ack_private.bodybuilder_status_574(text)') IS NOT NULL
    OR to_regprocedure('pdc_pmb_ack_private.bodybuilder_delivery_574(uuid,jsonb)') IS NOT NULL THEN
  RAISE EXCEPTION 'r574: helper already exists';
 END IF;
 PERFORM set_config('pdc.r574_pins', (SELECT count(*)::text FROM pdc_ops.expected_function_md5), true);
 PERFORM set_config('pdc.r574_open', (SELECT count(*)::text FROM public.pdc_pmb_arrival_557 WHERE closed_at IS NULL), true);
 PERFORM set_config('pdc.r574_pmb', (
   SELECT count(*)::text FROM public.vehicles
   WHERE deleted_at IS NULL AND upper(btrim(coalesce(current_location, ''))) = 'PMB'
 ), true);
 PERFORM set_config('pdc.r574_body_pmb', (
   SELECT count(DISTINCT v.id)::text
   FROM public.vehicles v
   JOIN public.navision_backend_records n
     ON n.canonical_vehicle_id = v.id AND n.is_current AND n.record_status = 'current'
   WHERE v.deleted_at IS NULL
     AND upper(btrim(coalesce(v.current_location, ''))) = 'PMB'
     AND public.navision_exact_lifecycle_status(n.normalized_data) = 'deliveredatbodybuilder'
 ), true);
 PERFORM set_config('pdc.r574_k135_loc', (
   SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p
   JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'karratha135_pdc' AND p.proname = 'navision_operational_location'
 ), true);
 PERFORM set_config('pdc.r574_k135_proj', (
   SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p
   JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'karratha135_pdc' AND p.proname = 'pdc_project_linked_navision_location_20260905'
 ), true);
 PERFORM set_config('pdc.r574_sales_tile', (
   SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p
   JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'pdc_sales_private' AND p.proname = 'sales_tracker_tile'
 ), true);
 IF current_setting('pdc.r574_k135_loc', true) IS NULL
    OR current_setting('pdc.r574_k135_proj', true) IS NULL
    OR current_setting('pdc.r574_sales_tile', true) IS NULL THEN
  RAISE EXCEPTION 'r574: department 135 or the sales tile is missing';
 END IF;
END $pre$;

CREATE FUNCTION pdc_pmb_ack_private.bodybuilder_status_574(p_status text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path TO 'pg_catalog'
AS $status574$
 SELECT p_status IN ('deliveredatbodybuilder', 'deliveredtobodybuilder', 'oddeliveredtobodybuilder');
$status574$;

REVOKE ALL ON FUNCTION pdc_pmb_ack_private.bodybuilder_status_574(text) FROM PUBLIC, anon, authenticated;

CREATE FUNCTION pdc_pmb_ack_private.bodybuilder_delivery_574(p_vehicle_id uuid, p_payload jsonb)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $delivery574$
 SELECT pdc_pmb_ack_private.bodybuilder_status_574(public.navision_exact_lifecycle_status(coalesce(p_payload, '{}'::jsonb)))
  OR EXISTS (
    SELECT 1
    FROM public.navision_backend_records n
    WHERE n.canonical_vehicle_id = p_vehicle_id
      AND n.is_current
      AND n.record_status = 'current'
      AND pdc_pmb_ack_private.bodybuilder_status_574(public.navision_exact_lifecycle_status(n.normalized_data))
  );
$delivery574$;

REVOKE ALL ON FUNCTION pdc_pmb_ack_private.bodybuilder_delivery_574(uuid, jsonb) FROM PUBLIC, anon, authenticated;

CREATE TABLE pdc_pmb_ack_private.bodybuilder_rule_574 (
 singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
 applied_at timestamptz NOT NULL,
 k135_loc_md5 text NOT NULL,
 k135_proj_md5 text NOT NULL,
 sales_tile_md5 text NOT NULL
);
INSERT INTO pdc_pmb_ack_private.bodybuilder_rule_574 (
 singleton, applied_at, k135_loc_md5, k135_proj_md5, sales_tile_md5
) VALUES (
 true,
 clock_timestamp(),
 current_setting('pdc.r574_k135_loc', true),
 current_setting('pdc.r574_k135_proj', true),
 current_setting('pdc.r574_sales_tile', true)
);
ALTER TABLE pdc_pmb_ack_private.bodybuilder_rule_574 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE pdc_pmb_ack_private.bodybuilder_rule_574 FROM PUBLIC, anon, authenticated;

CREATE TABLE pdc_pmb_ack_private.bodybuilder_hold_574 (
 hold_id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 vehicle_id uuid NOT NULL,
 arrival_id uuid NOT NULL UNIQUE,
 opened_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 released_at timestamptz,
 released_by uuid,
 release_action text,
 CONSTRAINT bodybuilder_hold_574_release_chk CHECK (
   (released_at IS NULL AND released_by IS NULL AND release_action IS NULL)
   OR (released_at IS NOT NULL AND released_by IS NOT NULL AND release_action = 'to_pmb')
 )
);
CREATE INDEX bodybuilder_hold_574_vehicle_idx ON pdc_pmb_ack_private.bodybuilder_hold_574 (vehicle_id);
ALTER TABLE pdc_pmb_ack_private.bodybuilder_hold_574 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE pdc_pmb_ack_private.bodybuilder_hold_574 FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.navision_operational_location(p_data jsonb)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $location574$
declare
  v_status text:=public.navision_exact_lifecycle_status(p_data);
  v_eta date:=public.navision_kewdale_eta(p_data);
  v_business_date date:=(statement_timestamp() at time zone 'Australia/Perth')::date;
  v_declared text:=lower(btrim(coalesce(p_data->>'navisionLocationStatus','')));
begin
  if v_status='deliveredatdealer' then return 'Completed'; end if;
  -- r574 (F188): body-builder delivery still resolves to location PMB so the
  -- New to PMB arrival can open. It does not mean the PMB tile. A key does not skip it.
  if pdc_pmb_ack_private.bodybuilder_status_574(v_status) then return 'PMB'; end if;
  if v_status in('vehicleinyardhold','inyardhold','yardhold') then return 'YH'; end if;
  if v_status=any(array['waitingpd2','vehicledelayed','awaitingtrayfit','vehiclewaitingwholesale','vehiclewaitingforwholesale'])
     and v_eta is not null and v_eta<v_business_date then return 'YH'; end if;
  if v_eta is not null and (
       v_declared='it'
       or (v_status like '%fromtwa%' and (v_status like '%despatch%' or v_status like '%dispatch%'))
       or v_status like '%intransit%'
       or v_status like '%shipment%'
       or v_status like '%wharf%'
     ) then return 'IT'; end if;
  return 'Other';
end
$location574$;

CREATE OR REPLACE FUNCTION public.pdc_project_linked_navision_location_20260905(p_backend_record_id uuid, p_actor_id uuid, p_actor_email text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
 SET statement_timeout TO '90s'
AS $project574$
DECLARE
  v_record public.navision_backend_records%rowtype;
  v_vehicle public.vehicles%rowtype;
  v_after public.vehicles%rowtype;
  v_vehicle_ids uuid[];
  v_stock text;
  v_vin text;
  v_location text;
  v_status text;
  v_current text;
  v_target text;
  v_before jsonb;
  v_parity jsonb;
  v_now timestamptz:=clock_timestamp();
BEGIN
  IF NOT public.pdc_monitor_staging_guard() OR p_backend_record_id IS NULL THEN
    RETURN public.navision_backend_response(false,'wrong_environment_or_invalid_input');
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('navision-operational-record:'||p_backend_record_id::text,0));
  SELECT * INTO v_record FROM public.navision_backend_records WHERE id=p_backend_record_id FOR UPDATE;
  IF NOT FOUND OR NOT v_record.is_current OR v_record.record_status<>'current' OR v_record.canonical_vehicle_id IS NULL THEN
    RETURN public.navision_backend_response(true,'projection_not_required',jsonb_build_object('changed',false,'reason','no_current_canonical_link'));
  END IF;
  v_stock:=nullif(public.normalize_vehicle_stock_number(v_record.normalized_data->>'batch'),'');
  v_vin:=public.pdc_navision_effective_vin_471(v_record.normalized_data);
  SELECT coalesce(array_agg(v.id ORDER BY v.id),'{}'::uuid[]) INTO v_vehicle_ids
  FROM public.vehicles v
  WHERE v.deleted_at IS NULL AND (v.stock_number_normalized=v_stock OR (v_vin IS NOT NULL AND v.vin_normalized=v_vin));
  IF cardinality(v_vehicle_ids)<>1 OR v_vehicle_ids[1] IS DISTINCT FROM v_record.canonical_vehicle_id
     OR (SELECT count(*) FROM public.navision_backend_records n WHERE n.is_current AND n.record_status='current'
           AND nullif(public.normalize_vehicle_stock_number(n.normalized_data->>'batch'),'')=v_stock)<>1 THEN
    RETURN public.navision_backend_response(false,'canonical_identity_conflict',jsonb_build_object(
      'backend_record_id',p_backend_record_id,'candidate_count',cardinality(v_vehicle_ids)));
  END IF;
  SELECT * INTO STRICT v_vehicle FROM public.vehicles WHERE id=v_record.canonical_vehicle_id FOR UPDATE;
  v_location:=public.navision_operational_location(v_record.normalized_data);
  v_status:=public.navision_exact_lifecycle_status(v_record.normalized_data);
  v_current:=upper(btrim(coalesce(v_vehicle.current_location,'')));

  IF lower(btrim(coalesce(v_vehicle.lifecycle_state::text,'')))='completed'
     OR v_current IN ('PMB','PIT','QC','RFT','COLLECTED','COMPLETED')
     OR v_vehicle.date_to_pmb IS NOT NULL THEN
    RETURN public.navision_backend_response(true,'location_latch_preserved',jsonb_build_object(
      'changed',false,'vehicle_id',v_vehicle.id,'current_location',v_vehicle.current_location,
      'date_to_pmb',v_vehicle.date_to_pmb,'navision_location',v_location));
  END IF;

  IF v_location='YH' AND v_current<>'YH' THEN
    v_target:='YH';
  ELSIF v_location='PMB' AND pdc_pmb_ack_private.bodybuilder_status_574(v_status) AND v_current<>'PMB' THEN
    v_target:='PMB';
  ELSE
    RETURN public.navision_backend_response(true,'projection_not_required',jsonb_build_object(
      'changed',false,'vehicle_id',v_vehicle.id,'current_location',v_vehicle.current_location,
      'date_to_pmb',v_vehicle.date_to_pmb,'navision_location',v_location));
  END IF;

  v_before:=to_jsonb(v_vehicle);
  UPDATE public.vehicles SET
    current_location=v_target,
    visible_on_board=true,
    eta_to_kewdale=coalesce(public.navision_kewdale_eta(v_record.normalized_data),eta_to_kewdale),
    source_payload=coalesce(source_payload,'{}'::jsonb)||jsonb_build_object(
      'authority','navision_linked_location_projection_20260905',
      'navision_location_projection',v_target,
      'navision_location_projected_at',v_now,
      'navision_record_id',p_backend_record_id),
    version=version+1,updated_at=v_now,updated_by=p_actor_id
  WHERE id=v_vehicle.id RETURNING * INTO v_after;
  INSERT INTO public.vehicle_movements(
    vehicle_id,from_location,to_location,from_pmb_stage,to_pmb_stage,
    from_pmb_bay_stage,to_pmb_bay_stage,from_pmb_bay_number,to_pmb_bay_number,reason,moved_by)
  VALUES(v_after.id,v_vehicle.current_location,v_after.current_location,
    v_vehicle.pmb_stage,v_after.pmb_stage,v_vehicle.pmb_bay_stage,v_after.pmb_bay_stage,
    v_vehicle.pmb_bay_number,v_after.pmb_bay_number,
    'Authoritative linked Navision operational location projection',p_actor_id);
  PERFORM public.audit_pdc_event('move','vehicles',v_after.id,v_after.id,v_before,to_jsonb(v_after),jsonb_build_object(
    'action','pdc_project_linked_navision_location_20260905','backend_record_id',p_backend_record_id,
    'from',v_vehicle.current_location,'to',v_after.current_location,'navision_status',v_status));
  UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=v_now WHERE singleton;
  UPDATE public.navision_backend_revision SET revision=revision+1,updated_at=v_now WHERE singleton;
  v_parity:=public.pdc_navision_vehicle_parity_494(v_after.id);
  IF NOT coalesce((v_parity->>'ok')::boolean,false) OR coalesce((v_parity->>'mismatch_count')::integer,-1)<>0 THEN
    RAISE EXCEPTION 'PDC_NAVISION_LINKED_LOCATION_PARITY_FAILED:%',v_parity USING errcode='23514';
  END IF;
  RETURN public.navision_backend_response(true,'linked_location_projected',jsonb_build_object(
    'changed',true,'vehicle_id',v_after.id,'from_location',v_vehicle.current_location,
    'location',v_after.current_location,'date_to_pmb',v_after.date_to_pmb,
    'eta_to_kewdale',v_after.eta_to_kewdale,'vehicle_version_before',v_vehicle.version,
    'vehicle_version_after',v_after.version,'parity',v_parity));
END
$project574$;

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

CREATE OR REPLACE FUNCTION pdc_pmb_ack_private.state_557(p_arrival_id uuid, p_vehicle_id uuid, p_controller boolean, p_actor uuid, p_open boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $state574$
DECLARE
 v_relevant text[];
 v_mine text[];
 v_departments jsonb;
 v_pending boolean;
 v_has_key boolean;
 v_hold boolean;
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
 v_hold := p_open AND EXISTS (
   SELECT 1 FROM pdc_pmb_ack_private.bodybuilder_hold_574 h
   WHERE h.arrival_id = p_arrival_id AND h.released_at IS NULL
 );
 -- A body-builder delivery stays in New to PMB for every viewer until To PMB,
 -- even when a key number is already present and every station has acknowledged.
 IF v_hold THEN
  v_pending := true;
 END IF;
 RETURN jsonb_build_object('viewer_pending', v_pending, 'departments', v_departments, 'needs_key', NOT coalesce(v_has_key, false));
END
$state574$;

CREATE OR REPLACE FUNCTION public.acknowledge_pmb_arrival_557(p_vehicle_id uuid, p_station text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $ack574$
DECLARE
 v_actor uuid := auth.uid();
 v_role text; v_email text; v_full text; v_display text; v_name text;
 v_station text := upper(btrim(coalesce(p_station, '')));
 v_controller boolean := false;
 v_open public.pdc_pmb_arrival_557%ROWTYPE;
 v_state jsonb;
 v_relevant text[];
 v_has_key boolean;
 v_hold boolean := false;
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
 SELECT EXISTS (
   SELECT 1 FROM pdc_pmb_ack_private.bodybuilder_hold_574 h
   WHERE h.arrival_id = v_open.arrival_id AND h.released_at IS NULL
 ) INTO v_hold;
 IF NOT v_hold AND NOT v_has_key AND NOT EXISTS (
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
 -- A body-builder hold is not closed by the last acknowledgement. To PMB is the only close.
 IF NOT v_hold AND NOT EXISTS (
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
END
$ack574$;

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

INSERT INTO pdc_ops.regression_checks (check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES
('bodybuilder_new_to_pmb_574', 'F195',
 'A body-builder delivery (OD Delivered to body builder, including Delivered - At Body Builder) opens New to PMB and stays there until a user presses To PMB, even when a key number is already present. Re-import after To PMB does not open another arrival. Vehicles already at PMB are not moved. The pin count stays 241. Department 135 and the sales tile are not edited. The check uses search_path pg_catalog, schema-qualified types, and no regprocedure cast.',
 $chk574$
SELECT
  pins.n = 241
  AND added.n = 0
  AND hold.present
  AND slipped.n = 0
  AND reached.n = 0
  AND cap.holds
  AND cap.idempotent
  AND cap.no_vehicle_update
  AND guard.to_pmb_only
  AND guard.key_needed
  AND state.holds_with_key
  AND ack.no_auto_close
  AND ack.no_vehicle_update
  AND push.records_user
  AND push.key_needed
  AND loc.phrases
  AND proj.phrases
  AND k135.same
  AND sales.same
  AS ok,
  ('pins ' || pins.n::pg_catalog.text
    || ' | body-builder deliveries still in PMB without To PMB: ' || slipped.n::pg_catalog.text
    || ' | reached PMB after apply without To PMB: ' || reached.n::pg_catalog.text) AS detail
FROM (SELECT count(*) AS n FROM pdc_ops.expected_function_md5) pins
CROSS JOIN (SELECT count(*) AS n FROM pdc_ops.expected_function_md5 WHERE release = 'r582') added
CROSS JOIN (
  SELECT count(*) = 1 AS present
  FROM pdc_pmb_ack_private.bodybuilder_rule_574
) hold
CROSS JOIN (
  SELECT count(*) AS n
  FROM pdc_pmb_ack_private.bodybuilder_hold_574 h
  JOIN public.pdc_pmb_arrival_557 a ON a.arrival_id = h.arrival_id
  WHERE a.closed_at IS NOT NULL
    AND a.closed_at >= (SELECT applied_at FROM pdc_pmb_ack_private.bodybuilder_rule_574)
    AND (h.release_action IS DISTINCT FROM 'to_pmb' OR h.released_by IS NULL)
) slipped
CROSS JOIN (
  SELECT count(*) AS n
  FROM public.vehicle_movements m
  JOIN public.vehicles v ON v.id = m.vehicle_id
  WHERE m.moved_at >= (SELECT applied_at FROM pdc_pmb_ack_private.bodybuilder_rule_574)
    AND upper(btrim(coalesce(m.to_location, ''))) = 'PMB'
    AND upper(btrim(coalesce(m.from_location, ''))) IS DISTINCT FROM 'PMB'
    AND pdc_pmb_ack_private.bodybuilder_delivery_574(v.id, v.source_payload)
    AND NOT EXISTS (
      SELECT 1 FROM public.pdc_pmb_arrival_557 open_row
      WHERE open_row.vehicle_id = v.id AND open_row.closed_at IS NULL
    )
    AND NOT EXISTS (
      SELECT 1 FROM pdc_pmb_ack_private.bodybuilder_hold_574 released
      WHERE released.vehicle_id = v.id AND released.release_action = 'to_pmb' AND released.released_by IS NOT NULL
    )
) reached
CROSS JOIN (
  SELECT
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'bodybuilder') > 0 AND pg_catalog.strpos(p.prosrc, 'bodybuilder_hold_574') > 0), false) AS holds,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'release_action = ''to_pmb''') > 0), false) AS idempotent,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'UPDATE public.vehicles') = 0), false) AS no_vehicle_update
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'pdc_pmb_ack_private' AND p.proname = 'capture_557'
) cap
CROSS JOIN (
  SELECT
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'PDC_574_TO_PMB_ONLY') > 0), false) AS to_pmb_only,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'PDC_562_KEY_NUMBER_NEEDED') > 0), false) AS key_needed
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'pdc_pmb_ack_private' AND p.proname = 'arrival_guard_557'
) guard
CROSS JOIN (
  SELECT coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'v_hold THEN') > 0 AND pg_catalog.strpos(p.prosrc, 'v_pending := true') > 0), false) AS holds_with_key
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'pdc_pmb_ack_private' AND p.proname = 'state_557'
) state
CROSS JOIN (
  SELECT
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'NOT v_hold AND NOT EXISTS') > 0 AND pg_catalog.strpos(p.prosrc, 'key_number_needed') > 0), false) AS no_auto_close,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'UPDATE public.vehicles') = 0), false) AS no_vehicle_update
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'acknowledge_pmb_arrival_557'
    AND pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_vehicle_id uuid, p_station text'
) ack
CROSS JOIN (
  SELECT
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'pdc.bodybuilder_to_pmb_574') > 0 AND pg_catalog.strpos(p.prosrc, 'release_action = ''to_pmb''') > 0 AND pg_catalog.strpos(p.prosrc, 'released_by = v_actor') > 0), false) AS records_user,
    coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'key_number_needed') > 0), false) AS key_needed
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'push_new_to_pmb_562'
    AND pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_vehicle_id uuid'
) push
CROSS JOIN (
  SELECT coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'bodybuilder_status_574') > 0), false) AS phrases
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'navision_operational_location'
    AND pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_data jsonb'
) loc
CROSS JOIN (
  SELECT coalesce(bool_and(pg_catalog.strpos(p.prosrc, 'bodybuilder_status_574') > 0), false) AS phrases
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'pdc_project_linked_navision_location_20260905'
) proj
CROSS JOIN (
  SELECT
    (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'karratha135_pdc' AND p.proname = 'navision_operational_location')
    IS NOT DISTINCT FROM (SELECT k135_loc_md5 FROM pdc_pmb_ack_private.bodybuilder_rule_574)
    AND (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'karratha135_pdc' AND p.proname = 'pdc_project_linked_navision_location_20260905')
    IS NOT DISTINCT FROM (SELECT k135_proj_md5 FROM pdc_pmb_ack_private.bodybuilder_rule_574)
    AS same
) k135
CROSS JOIN (
  SELECT
    (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_sales_private' AND p.proname = 'sales_tracker_tile')
    IS NOT DISTINCT FROM (SELECT sales_tile_md5 FROM pdc_pmb_ack_private.bodybuilder_rule_574)
    AS same
) sales
$chk574$, true, 353, 'r582');

DO $post$
DECLARE r record; probe record;
BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r574: pin count changed'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release = 'r582') THEN RAISE EXCEPTION 'r582: a pin was inserted'; END IF;
 IF current_setting('pdc.r574_open', true) IS DISTINCT FROM (SELECT count(*)::text FROM public.pdc_pmb_arrival_557 WHERE closed_at IS NULL) THEN
  RAISE EXCEPTION 'r574: open New to PMB count changed';
 END IF;
 IF current_setting('pdc.r574_pmb', true) IS DISTINCT FROM (
   SELECT count(*)::text FROM public.vehicles
   WHERE deleted_at IS NULL AND upper(btrim(coalesce(current_location, ''))) = 'PMB'
 ) THEN RAISE EXCEPTION 'r574: PMB vehicle count changed'; END IF;
 IF current_setting('pdc.r574_body_pmb', true) IS DISTINCT FROM (
   SELECT count(DISTINCT v.id)::text
   FROM public.vehicles v
   JOIN public.navision_backend_records n
     ON n.canonical_vehicle_id = v.id AND n.is_current AND n.record_status = 'current'
   WHERE v.deleted_at IS NULL
     AND upper(btrim(coalesce(v.current_location, ''))) = 'PMB'
     AND public.navision_exact_lifecycle_status(n.normalized_data) = 'deliveredatbodybuilder'
 ) THEN RAISE EXCEPTION 'r574: PMB body-builder count changed'; END IF;
 IF current_setting('pdc.r574_k135_loc', true) IS DISTINCT FROM (
   SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'karratha135_pdc' AND p.proname = 'navision_operational_location'
 ) OR current_setting('pdc.r574_k135_proj', true) IS DISTINCT FROM (
   SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'karratha135_pdc' AND p.proname = 'pdc_project_linked_navision_location_20260905'
 ) THEN RAISE EXCEPTION 'r574: department 135 changed'; END IF;
 IF current_setting('pdc.r574_sales_tile', true) IS DISTINCT FROM (
   SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'pdc_sales_private' AND p.proname = 'sales_tracker_tile'
 ) THEN RAISE EXCEPTION 'r574: sales tile changed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name = 'bodybuilder_new_to_pmb_574' AND fault_id = 'F195' AND sort_order = 353 AND added_in = 'r582' AND enabled) <> 1 THEN
  RAISE EXCEPTION 'r582: check missing';
 END IF;
 PERFORM set_config('search_path', 'pg_catalog', true);
 FOR r IN SELECT check_name, check_sql FROM pdc_ops.regression_checks WHERE check_name = 'bodybuilder_new_to_pmb_574' LOOP
  EXECUTE r.check_sql INTO probe;
  IF coalesce(probe.ok, false) IS NOT TRUE THEN RAISE EXCEPTION 'r574: % failed: %', r.check_name, probe.detail; END IF;
 END LOOP;
END $post$;
