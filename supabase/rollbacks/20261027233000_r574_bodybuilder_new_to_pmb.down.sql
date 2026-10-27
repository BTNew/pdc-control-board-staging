-- Undo r582 (F195) / sort 353. Staging only. Restores the location mapping, the linked
-- projection, and the New to PMB capture, guard, state, acknowledgement and
-- To PMB action that were live before this preview. Drops the body-builder
-- hold. Does not change a vehicle row and does not delete an arrival row.
-- Pin count stays 241. Production is not a target.

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN
  RAISE EXCEPTION 'r574 undo: run between :02 and :45';
 END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
    OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'r574 undo: staging only';
 END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name = 'bodybuilder_new_to_pmb_574' AND fault_id = 'F195' AND sort_order = 353 AND added_in = 'r582') <> 1 THEN
  RAISE EXCEPTION 'r582 undo: F195 check is not the r582 row';
 END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN
  RAISE EXCEPTION 'r574 undo: pin count is not 241';
 END IF;
END $g$;

CREATE OR REPLACE FUNCTION public.navision_operational_location(p_data jsonb)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $loc$
declare
  v_status text:=public.navision_exact_lifecycle_status(p_data);
  v_eta date:=public.navision_kewdale_eta(p_data);
  v_business_date date:=(statement_timestamp() at time zone 'Australia/Perth')::date;
  v_declared text:=lower(btrim(coalesce(p_data->>'navisionLocationStatus','')));
begin
  if v_status='deliveredatdealer' then return 'Completed'; end if;
  if v_status='deliveredatbodybuilder' then return 'PMB'; end if;
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
$loc$;

CREATE OR REPLACE FUNCTION public.pdc_project_linked_navision_location_20260905(p_backend_record_id uuid, p_actor_id uuid, p_actor_email text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
 SET statement_timeout TO '90s'
AS $proj$
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
  ELSIF v_location='PMB' AND v_status='deliveredatbodybuilder' AND v_current<>'PMB' THEN
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
END $proj$;

CREATE OR REPLACE FUNCTION pdc_pmb_ack_private.capture_557()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $cap$
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

CREATE OR REPLACE FUNCTION pdc_pmb_ack_private.arrival_guard_557()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $guard$
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
 RETURN NEW;
END $guard$;

CREATE OR REPLACE FUNCTION pdc_pmb_ack_private.state_557(p_arrival_id uuid, p_vehicle_id uuid, p_controller boolean, p_actor uuid, p_open boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $state$
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
END $state$;

CREATE OR REPLACE FUNCTION public.acknowledge_pmb_arrival_557(p_vehicle_id uuid, p_station text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $ack$
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

CREATE OR REPLACE FUNCTION public.push_new_to_pmb_562(p_vehicle_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'auth'
AS $push$
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
END $push$;

DELETE FROM pdc_ops.regression_checks
 WHERE check_name = 'bodybuilder_new_to_pmb_574' AND fault_id = 'F195' AND sort_order = 353 AND added_in = 'r582';

DROP FUNCTION IF EXISTS pdc_pmb_ack_private.bodybuilder_delivery_574(uuid, jsonb);
DROP FUNCTION IF EXISTS pdc_pmb_ack_private.bodybuilder_status_574(text);
DROP TABLE IF EXISTS pdc_pmb_ack_private.bodybuilder_hold_574;
DROP TABLE IF EXISTS pdc_pmb_ack_private.bodybuilder_rule_574;

DO $post$ BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN
  RAISE EXCEPTION 'r574 undo: pin count changed';
 END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release = 'r582') THEN
  RAISE EXCEPTION 'r582 undo: a pin was inserted';
 END IF;
 IF to_regprocedure('pdc_pmb_ack_private.bodybuilder_status_574(text)') IS NOT NULL
    OR to_regprocedure('pdc_pmb_ack_private.bodybuilder_delivery_574(uuid,jsonb)') IS NOT NULL
    OR to_regclass('pdc_pmb_ack_private.bodybuilder_hold_574') IS NOT NULL
    OR to_regclass('pdc_pmb_ack_private.bodybuilder_rule_574') IS NOT NULL THEN
  RAISE EXCEPTION 'r574 undo: a body-builder object remains';
 END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name = 'bodybuilder_new_to_pmb_574') THEN
  RAISE EXCEPTION 'r574 undo: the check remains';
 END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'navision_operational_location'
       AND pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_data jsonb')
    IS DISTINCT FROM '1e65de53c0f5a5dcf700015676ea8de2' THEN
  RAISE EXCEPTION 'r574 undo: location mapping was not restored';
 END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'pdc_project_linked_navision_location_20260905')
    IS DISTINCT FROM '3097226402c9e2d465049adc842282c0' THEN
  RAISE EXCEPTION 'r574 undo: projection was not restored';
 END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'pdc_pmb_ack_private' AND p.proname = 'capture_557')
    IS DISTINCT FROM 'a0e850991e249c49ed3563f03675f178' THEN
  RAISE EXCEPTION 'r574 undo: capture was not restored';
 END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'pdc_pmb_ack_private' AND p.proname = 'arrival_guard_557')
    IS DISTINCT FROM '79a1e4b6f5f20890a2ebe7f9809acda5' THEN
  RAISE EXCEPTION 'r574 undo: guard was not restored';
 END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'pdc_pmb_ack_private' AND p.proname = 'state_557')
    IS DISTINCT FROM 'bbd4d00fde44969abfa25e457371ba1a' THEN
  RAISE EXCEPTION 'r574 undo: state was not restored';
 END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'acknowledge_pmb_arrival_557'
       AND pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_vehicle_id uuid, p_station text')
    IS DISTINCT FROM 'ab8b4656158bec8e2adaaa1c58376a66' THEN
  RAISE EXCEPTION 'r574 undo: acknowledgement was not restored';
 END IF;
 IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'push_new_to_pmb_562'
       AND pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_vehicle_id uuid')
    IS DISTINCT FROM '96875016dd59c65fc55c7d168140eb4b' THEN
  RAISE EXCEPTION 'r574 undo: To PMB was not restored';
 END IF;
END $post$;
