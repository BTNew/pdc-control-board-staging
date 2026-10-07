-- Department 135 only: dealer delivery is local fitment arrival.
-- Raw source status, staff hours, approvals, QC and completed lifecycle remain authoritative.
-- CREATE OR REPLACE preserves existing owners, grants and security boundaries.

CREATE OR REPLACE FUNCTION karratha135_pdc.pdc_apply_tune_vehicle_fields_v5(p_vehicle_id uuid, p_batch_id uuid, p_preview_batch_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'karratha135_pdc'
AS $function$
DECLARE b karratha135_pdc.pdc_pilbara_service_import_batches%rowtype; v karratha135_pdc.vehicles%rowtype; fields jsonb; e karratha135_pdc.pdc_tune_intake_evidence_v5%rowtype;
 details jsonb; p karratha135_pdc.vehicle_parts_updates%rowtype; desired text; n karratha135_pdc.navision_backend_records%rowtype; target_location text;
BEGIN
 SELECT * INTO STRICT b FROM karratha135_pdc.pdc_pilbara_service_import_batches WHERE batch_id=p_batch_id AND batch_kind='apply' AND contract_revision='pmg_stock_v5';
 SELECT * INTO STRICT v FROM karratha135_pdc.vehicles WHERE id=p_vehicle_id FOR UPDATE;
 SELECT jsonb_agg(r.normalized_payload->'tune_source_fields' ORDER BY r.source_order) INTO fields FROM karratha135_pdc.pdc_pilbara_service_import_rows r
 WHERE r.batch_id=p_preview_batch_id
 AND r.stock_number=v.stock_number AND r.decision IN('insert','unchanged');
 -- Apply batches on this route bind their preview in request data, not a separate FK.
 IF fields IS NULL THEN RAISE EXCEPTION 'missing_tune_source_fields'; END IF;
 desired:=karratha135_pdc.pdc_tune_parts_status_v5(fields);
 INSERT INTO karratha135_pdc.pdc_tune_intake_evidence_v5(vehicle_id,batch_id,source_hash,workbook_sha256,customer_name,vehicle_description,tune_vin,parts_status,purchase_order_numbers,source_fields,created_by)
 SELECT v.id,b.batch_id,b.source_hash,b.source_link->>'workbook_sha256',min(nullif(f->>'customer_name','')),min(nullif(f->>'vehicle_description','')),min(nullif(f->>'vin','')),desired,
 coalesce(jsonb_agg(DISTINCT f->>'purchase_order_number') FILTER(WHERE nullif(f->>'purchase_order_number','') IS NOT NULL),'[]'),fields,b.created_by
 FROM jsonb_array_elements(fields) f RETURNING * INTO e;
 INSERT INTO karratha135_pdc.pdc_tune_intake_current_v5(vehicle_id,evidence_id) VALUES(v.id,e.evidence_id) ON CONFLICT(vehicle_id) DO UPDATE SET evidence_id=excluded.evidence_id;
 details:=karratha135_pdc.pdc_tune_vehicle_details_v5(v.id);
 UPDATE karratha135_pdc.vehicles SET customer_name=details->>'customer_name',vehicle_description=details->>'vehicle_description',
 source_payload=coalesce(source_payload,'{}')||jsonb_build_object('tune_details_evidence_id',e.evidence_id,'details_source',details->>'details_source'),
 version=version+1,updated_by=b.created_by,updated_at=clock_timestamp() WHERE id=v.id;

 -- Pending Tune intake follows its unique current Navision location.
 -- Department 135 owner rule: exact dealer/body-builder arrival enters local fitment, pending intake review.
 IF NOT v.visible_on_board AND v.deleted_at IS NULL AND v.lifecycle_state::text='active'
  AND v.qc_completed_at IS NULL AND v.rft_transferred_at IS NULL AND v.date_to_pmb IS NULL
  AND upper(btrim(coalesce(v.current_location,''))) IN('YARD HOLD','YH','IT','OTHER')
  AND NOT EXISTS(SELECT 1 FROM karratha135_pdc.pdc_new_vehicle_reviews r WHERE r.vehicle_id=v.id AND r.status<>'pending')
  AND NOT EXISTS(SELECT 1 FROM karratha135_pdc.workshop_bookings w WHERE w.vehicle_id=v.id AND w.deleted_at IS NULL)
  AND NOT EXISTS(SELECT 1 FROM karratha135_pdc.vehicle_movements m WHERE m.vehicle_id=v.id)
  AND details->>'details_source'='microsoft_navision' THEN
  SELECT * INTO n FROM karratha135_pdc.navision_backend_records
   WHERE id=(details->>'details_backend_record_id')::uuid AND canonical_vehicle_id=v.id
    AND is_current AND record_status='current';
  IF FOUND THEN
   target_location:=karratha135_pdc.navision_operational_location(n.normalized_data);
   IF target_location IN('PMB','YH','IT','Other') THEN
    UPDATE karratha135_pdc.vehicles SET current_location=target_location,
     eta_to_kewdale=coalesce(karratha135_pdc.navision_kewdale_eta(n.normalized_data),eta_to_kewdale),
     source_payload=coalesce(source_payload,'{}')||jsonb_build_object(
      'tune_location_authority','navision_pending_intake_exact_sublocation',
      'tune_location_backend_record_id',n.id,'tune_location_backend_version',n.version,
      'tune_location_navision_code',n.normalized_data->>'navisionLocationStatus',
      'tune_location_navision_description',n.normalized_data->>'navisionSubLocationDescription'),
     version=version+1,updated_by=b.created_by,updated_at=clock_timestamp()
    WHERE id=v.id;
   END IF;
  END IF;
 END IF;
 IF details->>'details_source'<>'microsoft_navision' AND NOT v.visible_on_board
  AND v.lifecycle_state::text='active' AND v.deleted_at IS NULL AND v.date_to_pmb IS NULL
  AND upper(btrim(v.current_location)) IN('YARD HOLD','YH')
  AND NOT EXISTS(SELECT 1 FROM karratha135_pdc.vehicle_movements WHERE vehicle_id=v.id)
  AND NOT EXISTS(SELECT 1 FROM karratha135_pdc.workshop_bookings WHERE vehicle_id=v.id AND deleted_at IS NULL)
 THEN
  UPDATE karratha135_pdc.vehicles SET current_location='Other',eta_to_kewdale=NULL,
   source_payload=coalesce(source_payload,'{}')||jsonb_build_object('tune_incoming_group','nonnavision'),
   version=version+1,updated_by=b.created_by WHERE id=v.id;
 END IF;
 -- Numeric parts evidence never signs off receipt or overwrites staff Parts state.
 PERFORM karratha135_pdc.audit_pdc_event('update','vehicles',v.id,v.id,to_jsonb(v),jsonb_build_object('details',details,'parts_status',desired),jsonb_build_object('contract','tune_daily_fields_v5','evidence_id',e.evidence_id,'source_batch_id',p_batch_id));
 RETURN jsonb_build_object('vehicle_id',v.id,'evidence_id',e.evidence_id,'details_source',details->>'details_source','parts_status',desired);
END $function$;

CREATE OR REPLACE FUNCTION karratha135_pdc.apply_navision_backend_import(p_idempotency_key text, p_rows jsonb, p_source_system text, p_dealer_code text, p_source_name text, p_source_timestamp timestamp with time zone, p_source_hash text, p_preview_hash text, p_expected_revision bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'karratha135_pdc', 'extensions'
AS $function$
DECLARE
  v_result jsonb;
  v_batch karratha135_pdc.navision_import_batches%rowtype;
  v_sequence bigint;
  v_new_update boolean;
  v_record karratha135_pdc.navision_backend_records%rowtype;
  v_first_sequence bigint;
  v_last_present_sequence bigint;
  v_consecutive_absences integer;
  v_present boolean;
  v_status text;
  v_decision text;
  v_retained integer:=0;
  v_retired integer:=0;
  v_terminal integer:=0;
  v_observations integer:=0;
BEGIN
  IF current_setting('app.environment',true)='production'
     OR NOT karratha135_pdc.pdc_monitor_staging_guard()
     OR lower(btrim(coalesce(p_source_system,'')))<>'microsoft_navision'
     OR btrim(coalesce(p_dealer_code,'')) NOT IN('14450','37047','002345','001234') THEN
    RETURN karratha135_pdc.navision_backend_response(false,'wrong_environment_or_scope');
  END IF;
  v_result:=karratha135_pdc.apply_navision_backend_import_pre_20260902271000(
    p_idempotency_key,p_rows,p_source_system,p_dealer_code,p_source_name,
    p_source_timestamp,p_source_hash,p_preview_hash,p_expected_revision
  );
  IF NOT coalesce((v_result->>'ok')::boolean,false) THEN RETURN v_result; END IF;

  SELECT b.* INTO v_batch FROM karratha135_pdc.navision_import_batches b
  WHERE b.idempotency_key=btrim(p_idempotency_key)
    AND b.source_system=lower(btrim(p_source_system)) AND b.dealer_code=btrim(p_dealer_code)
    AND b.status='applied' ORDER BY b.applied_at DESC,b.id DESC LIMIT 1;
  IF v_batch.id IS NULL THEN RAISE EXCEPTION 'PDC_20260903140000_IMPORT_BATCH_READBACK_FAILED' USING errcode='55000'; END IF;

  INSERT INTO karratha135_pdc.pdc_navision_applicable_updates_20260903(
    source_system,dealer_code,sequence_no,batch_id,idempotency_key,source_hash,result_revision,applied_at
  ) VALUES(v_batch.source_system,v_batch.dealer_code,
    coalesce((SELECT max(u.sequence_no)+1 FROM karratha135_pdc.pdc_navision_applicable_updates_20260903 u
      WHERE u.source_system=v_batch.source_system AND u.dealer_code=v_batch.dealer_code),1),
    v_batch.id,v_batch.idempotency_key,v_batch.source_hash,v_batch.result_revision,v_batch.applied_at)
  ON CONFLICT(batch_id) DO NOTHING RETURNING sequence_no INTO v_sequence;
  v_new_update:=FOUND;
  IF NOT v_new_update THEN
    SELECT sequence_no INTO v_sequence FROM karratha135_pdc.pdc_navision_applicable_updates_20260903 WHERE batch_id=v_batch.id;
    RETURN v_result||jsonb_build_object('absence_retention_contract','absence_from_last_seven_applicable_updates',
      'canonical_observation_contract','pdc_navision_retention_canonical_20260903140000',
      'applicable_update_sequence',v_sequence,'exact_retention_replay',true,
      'backend_only_retention',true,'direct_board_write_by_retention',false,'existing_operational_reconciliation_preserved',true);
  END IF;

  FOR v_record IN SELECT r.* FROM karratha135_pdc.navision_backend_records r
    WHERE r.source_system=v_batch.source_system AND r.dealer_code=v_batch.dealer_code
    ORDER BY r.id FOR UPDATE
  LOOP
    SELECT EXISTS(
      SELECT 1 FROM karratha135_pdc.navision_import_items i
      WHERE i.batch_id=v_batch.id AND i.backend_record_id=v_record.id
        AND i.classification IN('new','changed','unchanged')
    ) INTO v_present;
    v_status:=karratha135_pdc.navision_exact_lifecycle_status(v_record.normalized_data);
    SELECT min(o.first_sequence),max(o.sequence_no) FILTER(WHERE o.present_in_update)
      INTO v_first_sequence,v_last_present_sequence
    FROM karratha135_pdc.pdc_navision_retention_canonical_observations_20260903 o
    WHERE o.source_system=v_batch.source_system AND o.dealer_code=v_batch.dealer_code
      AND o.backend_record_id=v_record.id;
    v_first_sequence:=coalesce(v_first_sequence,v_sequence);
    v_consecutive_absences:=CASE WHEN v_present THEN 0 ELSE least(7,(v_sequence-coalesce(v_last_present_sequence,v_first_sequence-1))::integer) END;

    IF v_status='deliveredatdealer' AND karratha135_pdc.navision_operational_location(v_record.normalized_data)='Completed' THEN v_decision:='delivered_at_dealer';v_terminal:=v_terminal+1;
    ELSIF v_present THEN v_decision:='present';
    ELSIF v_consecutive_absences<karratha135_pdc.pdc_navision_retention_threshold_20260903()
      AND karratha135_pdc.pdc_navision_retain_after_absence_count_20260903(v_consecutive_absences,v_status) THEN
      UPDATE karratha135_pdc.navision_backend_records
      SET is_current=true,record_status='current',missing_since_batch_id=NULL,updated_at=clock_timestamp()
      WHERE id=v_record.id;
      SELECT * INTO v_record FROM karratha135_pdc.navision_backend_records WHERE id=v_record.id;
      v_decision:='absent_retained';v_retained:=v_retained+1;
    ELSE v_decision:='absent_retired';v_retired:=v_retired+1;
    END IF;

    INSERT INTO karratha135_pdc.pdc_navision_retention_canonical_observations_20260903(
      source_system,dealer_code,sequence_no,batch_id,backend_record_id,source_record_id,first_sequence,
      present_in_update,lifecycle_status,consecutive_absences,decision,record_is_current_after,
      record_status_after,missing_since_batch_id_after,evidence
    ) VALUES(v_batch.source_system,v_batch.dealer_code,v_sequence,v_batch.id,v_record.id,v_record.source_record_id,v_first_sequence,
      v_present,v_status,v_consecutive_absences,v_decision,v_record.is_current,v_record.record_status,v_record.missing_since_batch_id,
      jsonb_build_object('contract','pdc_navision_retention_canonical_20260903140000','bootstrap',false,
        'threshold',karratha135_pdc.pdc_navision_retention_threshold_20260903(),'last_present_sequence',v_last_present_sequence,
        'hard_delete',false,'evidence_sha256',encode(extensions.digest(convert_to(jsonb_build_object(
          'batch_id',v_batch.id,'record_id',v_record.id,'sequence',v_sequence,'first_sequence',v_first_sequence,
          'present',v_present,'status',v_status,'absences',v_consecutive_absences,'decision',v_decision,
          'is_current',v_record.is_current,'record_status',v_record.record_status
        )::text,'UTF8'),'sha256'),'hex')));
    v_observations:=v_observations+1;
  END LOOP;

  RETURN v_result||jsonb_build_object('absence_retention_contract','absence_from_last_seven_applicable_updates',
    'canonical_observation_contract','pdc_navision_retention_canonical_20260903140000',
    'applicable_update_sequence',v_sequence,'exact_retention_replay',false,
    'retention_observations_appended',v_observations,'backend_rows_retained',v_retained,
    'backend_rows_retired',v_retired,'backend_rows_terminal',v_terminal,
    'backend_only_retention',true,'direct_board_write_by_retention',false,'existing_operational_reconciliation_preserved',true);
END
$function$;

CREATE OR REPLACE FUNCTION karratha135_pdc.navision_operational_location(p_data jsonb)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'karratha135_pdc'
AS $function$
declare
  v_status text:=karratha135_pdc.navision_exact_lifecycle_status(p_data);
  v_eta date:=karratha135_pdc.navision_kewdale_eta(p_data);
  v_business_date date:=(statement_timestamp() at time zone 'Australia/Perth')::date;
  v_declared text:=lower(btrim(coalesce(p_data->>'navisionLocationStatus','')));
begin
  -- Department 135: delivery to dealer is local fitment arrival, not completed delivery.
  if v_status in ('deliveredatdealer','deliveredatbodybuilder') then return 'PMB'; end if;
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
$function$;

CREATE OR REPLACE FUNCTION karratha135_pdc.pdc_navision_retain_after_absence_count_20260903(p_applicable_absences integer, p_lifecycle_status text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'pg_catalog', 'karratha135_pdc'
AS $function$
  SELECT coalesce(p_applicable_absences,0)<karratha135_pdc.pdc_navision_retention_threshold_20260903()
$function$;

CREATE OR REPLACE FUNCTION karratha135_pdc.pdc_project_linked_navision_location_20260905(p_backend_record_id uuid, p_actor_id uuid, p_actor_email text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'karratha135_pdc', 'extensions'
 SET statement_timeout TO '90s'
AS $function$
DECLARE
  v_record karratha135_pdc.navision_backend_records%rowtype;
  v_vehicle karratha135_pdc.vehicles%rowtype;
  v_after karratha135_pdc.vehicles%rowtype;
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
  IF NOT karratha135_pdc.pdc_monitor_staging_guard() OR p_backend_record_id IS NULL THEN
    RETURN karratha135_pdc.navision_backend_response(false,'wrong_environment_or_invalid_input');
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('k135:navision-operational-record:'||p_backend_record_id::text,0));
  SELECT * INTO v_record FROM karratha135_pdc.navision_backend_records WHERE id=p_backend_record_id FOR UPDATE;
  IF NOT FOUND OR NOT v_record.is_current OR v_record.record_status<>'current' OR v_record.canonical_vehicle_id IS NULL THEN
    RETURN karratha135_pdc.navision_backend_response(true,'projection_not_required',jsonb_build_object('changed',false,'reason','no_current_canonical_link'));
  END IF;
  v_stock:=nullif(karratha135_pdc.normalize_vehicle_stock_number(v_record.normalized_data->>'batch'),'');
  v_vin:=karratha135_pdc.pdc_navision_effective_vin_471(v_record.normalized_data);
  SELECT coalesce(array_agg(v.id ORDER BY v.id),'{}'::uuid[]) INTO v_vehicle_ids
  FROM karratha135_pdc.vehicles v
  WHERE v.deleted_at IS NULL AND (v.stock_number_normalized=v_stock OR (v_vin IS NOT NULL AND v.vin_normalized=v_vin));
  IF cardinality(v_vehicle_ids)<>1 OR v_vehicle_ids[1] IS DISTINCT FROM v_record.canonical_vehicle_id
     OR (SELECT count(*) FROM karratha135_pdc.navision_backend_records n WHERE n.is_current AND n.record_status='current'
           AND nullif(karratha135_pdc.normalize_vehicle_stock_number(n.normalized_data->>'batch'),'')=v_stock)<>1 THEN
    RETURN karratha135_pdc.navision_backend_response(false,'canonical_identity_conflict',jsonb_build_object(
      'backend_record_id',p_backend_record_id,'candidate_count',cardinality(v_vehicle_ids)));
  END IF;
  SELECT * INTO STRICT v_vehicle FROM karratha135_pdc.vehicles WHERE id=v_record.canonical_vehicle_id FOR UPDATE;
  v_location:=karratha135_pdc.navision_operational_location(v_record.normalized_data);
  v_status:=karratha135_pdc.navision_exact_lifecycle_status(v_record.normalized_data);
  v_current:=upper(btrim(coalesce(v_vehicle.current_location,'')));

  IF lower(btrim(coalesce(v_vehicle.lifecycle_state::text,'')))='completed'
     OR v_current IN ('PMB','PIT','QC','RFT','COLLECTED','COMPLETED')
     OR v_vehicle.date_to_pmb IS NOT NULL THEN
    RETURN karratha135_pdc.navision_backend_response(true,'location_latch_preserved',jsonb_build_object(
      'changed',false,'vehicle_id',v_vehicle.id,'current_location',v_vehicle.current_location,
      'date_to_pmb',v_vehicle.date_to_pmb,'navision_location',v_location));
  END IF;

  IF v_location='YH' AND v_current<>'YH' THEN
    v_target:='YH';
  ELSIF v_location='PMB' AND v_status IN ('deliveredatbodybuilder','deliveredatdealer') AND v_current<>'PMB' THEN
    v_target:='PMB';
  ELSE
    RETURN karratha135_pdc.navision_backend_response(true,'projection_not_required',jsonb_build_object(
      'changed',false,'vehicle_id',v_vehicle.id,'current_location',v_vehicle.current_location,
      'date_to_pmb',v_vehicle.date_to_pmb,'navision_location',v_location));
  END IF;

  IF NOT v_vehicle.visible_on_board AND EXISTS(
    SELECT 1 FROM karratha135_pdc.pdc_new_vehicle_reviews r WHERE r.vehicle_id=v_vehicle.id AND r.status='pending'
  ) THEN
    RETURN karratha135_pdc.navision_backend_response(true,'intake_review_required',jsonb_build_object('changed',false,'vehicle_id',v_vehicle.id));
  END IF;

  v_before:=to_jsonb(v_vehicle);
  UPDATE karratha135_pdc.vehicles SET
    current_location=v_target,
    visible_on_board=true,
    eta_to_kewdale=coalesce(karratha135_pdc.navision_kewdale_eta(v_record.normalized_data),eta_to_kewdale),
    source_payload=coalesce(source_payload,'{}'::jsonb)||jsonb_build_object(
      'authority','navision_linked_location_projection_20260905',
      'navision_location_projection',v_target,
      'navision_location_projected_at',v_now,
      'navision_record_id',p_backend_record_id),
    version=version+1,updated_at=v_now,updated_by=p_actor_id
  WHERE id=v_vehicle.id RETURNING * INTO v_after;
  INSERT INTO karratha135_pdc.vehicle_movements(
    vehicle_id,from_location,to_location,from_pmb_stage,to_pmb_stage,
    from_pmb_bay_stage,to_pmb_bay_stage,from_pmb_bay_number,to_pmb_bay_number,reason,moved_by)
  VALUES(v_after.id,v_vehicle.current_location,v_after.current_location,
    v_vehicle.pmb_stage,v_after.pmb_stage,v_vehicle.pmb_bay_stage,v_after.pmb_bay_stage,
    v_vehicle.pmb_bay_number,v_after.pmb_bay_number,
    'Authoritative linked Navision operational location projection',p_actor_id);
  PERFORM karratha135_pdc.audit_pdc_event('move','vehicles',v_after.id,v_after.id,v_before,to_jsonb(v_after),jsonb_build_object(
    'action','pdc_project_linked_navision_location_20260905','backend_record_id',p_backend_record_id,
    'from',v_vehicle.current_location,'to',v_after.current_location,'navision_status',v_status));
  UPDATE karratha135_pdc.pdc_email_vehicle_revision SET revision=revision+1,updated_at=v_now WHERE singleton;
  UPDATE karratha135_pdc.navision_backend_revision SET revision=revision+1,updated_at=v_now WHERE singleton;
  v_parity:=karratha135_pdc.pdc_navision_vehicle_parity_494(v_after.id);
  IF NOT coalesce((v_parity->>'ok')::boolean,false) OR coalesce((v_parity->>'mismatch_count')::integer,-1)<>0 THEN
    RAISE EXCEPTION 'PDC_NAVISION_LINKED_LOCATION_PARITY_FAILED:%',v_parity USING errcode='23514';
  END IF;
  RETURN karratha135_pdc.navision_backend_response(true,'linked_location_projected',jsonb_build_object(
    'changed',true,'vehicle_id',v_after.id,'from_location',v_vehicle.current_location,
    'location',v_after.current_location,'date_to_pmb',v_after.date_to_pmb,
    'eta_to_kewdale',v_after.eta_to_kewdale,'vehicle_version_before',v_vehicle.version,
    'vehicle_version_after',v_after.version,'parity',v_parity));
END $function$;

CREATE OR REPLACE FUNCTION karratha135_pdc.reconcile_navision_delivery_734(p_backend_record_id uuid, p_actor_id uuid DEFAULT NULL::uuid, p_actor_email text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'karratha135_pdc', 'extensions'
 SET statement_timeout TO '120s'
AS $function$
DECLARE
  actor_id uuid:=p_actor_id; actor_email text:=lower(btrim(coalesce(p_actor_email,''))); b karratha135_pdc.navision_backend_records%rowtype; v karratha135_pdc.vehicles%rowtype; old karratha135_pdc.pdc_rft_transport_lifecycle_receipts_734%rowtype;
  raw_status text; normalized text; request_payload jsonb; request_sha text; before_state jsonb; after_state jsonb; receipt uuid; result jsonb; closed_at timestamptz:=clock_timestamp(); duration bigint; statistic uuid; activation karratha135_pdc.navision_board_activations%rowtype;
BEGIN
  IF NOT karratha135_pdc.pdc_monitor_staging_guard() OR p_backend_record_id IS NULL THEN RETURN karratha135_pdc.navision_backend_response(false,'wrong_environment_or_invalid_input'); END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('k135:pdc-734-delivery-record:'||p_backend_record_id::text,0));
  SELECT * INTO b FROM karratha135_pdc.navision_backend_records WHERE id=p_backend_record_id FOR UPDATE;
  IF NOT FOUND OR NOT b.is_current OR b.record_status<>'current' OR b.canonical_vehicle_id IS NULL THEN RETURN karratha135_pdc.navision_backend_response(false,'delivery_record_not_current'); END IF;
  raw_status:=btrim(coalesce(b.normalized_data->>'toyotaStatus',''));
  normalized:=lower(replace(replace(replace(btrim(raw_status),'–','-'),' ',''),'-',''));
  IF normalized<>'deliveredatdealer' THEN RETURN karratha135_pdc.navision_backend_response(false,'delivery_status_not_exact'); END IF;
  IF karratha135_pdc.navision_exact_lifecycle_status(b.normalized_data)='deliveredatdealer'
     AND karratha135_pdc.navision_operational_location(b.normalized_data)='PMB' THEN
    RETURN karratha135_pdc.navision_backend_response(true,'dealer_fitment_not_terminal',jsonb_build_object('changed',false,'backend_record_id',b.id));
  END IF;
  SELECT * INTO v FROM karratha135_pdc.vehicles WHERE id=b.canonical_vehicle_id FOR UPDATE;
  IF NOT FOUND OR v.deleted_at IS NOT NULL THEN RETURN karratha135_pdc.navision_backend_response(false,'delivery_vehicle_not_found'); END IF;
  IF b.dealer_code IS DISTINCT FROM v.source_batch_id THEN RETURN karratha135_pdc.navision_backend_response(false,'delivery_wrong_dealer_scope'); END IF;
  SELECT * INTO old FROM karratha135_pdc.pdc_rft_transport_lifecycle_receipts_734 WHERE vehicle_id=v.id AND action='delivered';
  IF FOUND THEN RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false); END IF;
  IF NOT EXISTS(SELECT 1 FROM karratha135_pdc.pdc_rft_transport_lifecycle_receipts_734 r WHERE r.vehicle_id=v.id AND r.action='rft_booked')
     OR NOT EXISTS(SELECT 1 FROM karratha135_pdc.pdc_rft_transport_lifecycle_receipts_734 r WHERE r.vehicle_id=v.id AND r.action='collected') THEN RETURN karratha135_pdc.navision_backend_response(false,'delivery_requires_collected_interval'); END IF;
  IF v.lifecycle_state<>'rft' OR upper(btrim(coalesce(v.current_location,'')))<>'COLLECTED' OR v.dealer_transit_started_at IS NULL OR v.dealer_transit_closed_at IS NOT NULL OR v.dealer_transit_duration_seconds IS NOT NULL THEN RETURN karratha135_pdc.navision_backend_response(false,'delivery_interval_not_open'); END IF;
  duration:=greatest(0,floor(extract(epoch FROM (closed_at-v.dealer_transit_started_at)))::bigint);
  request_payload:=jsonb_build_object('contract','pdc-durable-navision-delivery-734','backend_record_id',p_backend_record_id,'vehicle_id',v.id,'status','Delivered - At Dealer');
  request_sha:=encode(extensions.digest(convert_to(request_payload::text,'UTF8'),'sha256'),'hex');
  before_state:=karratha135_pdc.pdc_rft_transport_snapshot_734(v.id);
  UPDATE karratha135_pdc.vehicles SET lifecycle_state='completed',current_location='Completed',visible_on_board=false,dealer_transit_closed_at=closed_at,dealer_transit_duration_seconds=duration,delivered_to_dealer_date=coalesce(delivered_to_dealer_date,(closed_at AT TIME ZONE 'Australia/Perth')::date),source_payload=coalesce(source_payload,'{}'::jsonb)||jsonb_build_object('authority','pdc_durable_rft_transport_734','navision_record_id',p_backend_record_id,'navision_status_literal','Delivered - At Dealer','delivered_at',closed_at),version=version+1,updated_at=closed_at,updated_by=actor_id WHERE id=v.id RETURNING * INTO v;
  UPDATE karratha135_pdc.navision_board_activations SET canonical_vehicle_id=v.id,active=false,completed_at=coalesce(completed_at,closed_at),completion_reason='Delivered - At Dealer',completed_by=actor_id,completed_by_email=actor_email,updated_at=closed_at WHERE backend_record_id=b.id RETURNING * INTO activation;
  receipt:=extensions.uuid_generate_v5('73400000-0000-5000-8000-000000000734'::uuid,'delivery:'||p_backend_record_id::text||':'||v.id::text);
  result:=jsonb_build_object('ok',true,'code','delivered_at_dealer_completed','replay',false,'data',jsonb_build_object('receipt_id',receipt,'vehicle_id',v.id,'backend_record_id',p_backend_record_id,'status','Delivered - At Dealer','vehicle_version_after',v.version,'dealer_transit_started_at',v.dealer_transit_started_at,'dealer_transit_closed_at',closed_at,'dealer_transit_duration_seconds',duration,'current_location','Completed','lifecycle_state','completed'));
  after_state:=karratha135_pdc.pdc_rft_transport_snapshot_734(v.id);
  INSERT INTO karratha135_pdc.pdc_rft_transport_lifecycle_receipts_734(receipt_id,vehicle_id,action,actor_id,actor_email,idempotency_key,request_sha256,request_payload,before_state,after_state,evidence,response)
  VALUES(receipt,v.id,'delivered',actor_id,coalesce(nullif(actor_email,''),'system@staging.invalid'),extensions.uuid_generate_v5('73400000-0000-5000-8000-000000000734'::uuid,'delivery-idempotency:'||p_backend_record_id::text||':'||v.id::text),request_sha,request_payload,before_state,after_state,jsonb_build_object('exact_status_literal',true,'normalized_status',normalized,'dealer_scope_exact',true,'open_interval_required',true,'duration_seconds',duration),result);
  statistic:=extensions.uuid_generate_v5('73400000-0000-5000-8000-000000000734'::uuid,'statistic:'||v.id::text);
  INSERT INTO karratha135_pdc.pdc_rft_dealer_transit_statistics_734(statistic_id,vehicle_id,delivered_receipt_id,started_at,closed_at,duration_seconds,status_literal)
  VALUES(statistic,v.id,receipt,v.dealer_transit_started_at,closed_at,duration,'Delivered - At Dealer');
  PERFORM karratha135_pdc.audit_pdc_event('update','vehicles',v.id,v.id,before_state,after_state,jsonb_build_object('action','reconcile_navision_delivery_734','receipt_id',receipt,'backend_record_id',p_backend_record_id,'status_literal','Delivered - At Dealer','duration_seconds',duration));
  UPDATE karratha135_pdc.pdc_email_vehicle_revision SET revision=revision+1,updated_at=closed_at WHERE singleton;
  UPDATE karratha135_pdc.navision_backend_revision SET revision=revision+1,updated_at=closed_at WHERE singleton;
  RETURN result;
EXCEPTION WHEN unique_violation THEN
  SELECT * INTO old FROM karratha135_pdc.pdc_rft_transport_lifecycle_receipts_734 WHERE vehicle_id=b.canonical_vehicle_id AND action='delivered';
  IF FOUND THEN RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false); END IF;
  RETURN karratha135_pdc.navision_backend_response(false,'delivery_replay_conflict');
END $function$;

CREATE OR REPLACE FUNCTION karratha135_pdc.reconcile_navision_operational_record(p_backend_record_id uuid, p_actor_id uuid DEFAULT NULL::uuid, p_actor_email text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'karratha135_pdc', 'extensions'
AS $function$
DECLARE b karratha135_pdc.navision_backend_records%rowtype; v karratha135_pdc.vehicles%rowtype; raw_status text; normalized text;
BEGIN
  IF NOT karratha135_pdc.pdc_monitor_staging_guard() THEN RETURN karratha135_pdc.navision_backend_response(false,'wrong_environment'); END IF;
  SELECT * INTO b FROM karratha135_pdc.navision_backend_records WHERE id=p_backend_record_id;
  IF FOUND THEN
    raw_status:=btrim(coalesce(b.normalized_data->>'toyotaStatus',''));
    normalized:=lower(replace(replace(replace(btrim(raw_status),'–','-'),' ',''),'-',''));
    IF normalized='deliveredatdealer' AND karratha135_pdc.navision_operational_location(b.normalized_data)='Completed' THEN
      IF b.canonical_vehicle_id IS NULL
         AND EXISTS(SELECT 1 FROM karratha135_pdc.navision_board_activations a
           WHERE a.backend_record_id=b.id AND a.active AND a.activation_source='approved_email_build')
         AND karratha135_pdc.current_pdc_user_role()::text='viewer'
         AND EXISTS(SELECT 1 FROM karratha135_pdc.pdc_email_ai_successor_runtime_identities i
           WHERE i.auth_user_id=auth.uid() AND i.normalized_email=lower(btrim(coalesce(auth.jwt()->>'email','')))
             AND i.environment='staging' AND i.identity_purpose='pdc_email_ai_transaction_successor'
             AND i.active AND i.revoked_at IS NULL)
         AND EXISTS(SELECT 1 FROM karratha135_pdc.pdc_monitor_stage_activation_writers w
           WHERE w.user_id=auth.uid() AND w.active AND w.revoked_at IS NULL) THEN
        RETURN karratha135_pdc.reconcile_navision_operational_record_pre_700(p_backend_record_id,p_actor_id,p_actor_email);
      END IF;
      RETURN karratha135_pdc.reconcile_navision_delivery_734(p_backend_record_id,p_actor_id,p_actor_email);
    END IF;
    IF b.canonical_vehicle_id IS NOT NULL THEN
      SELECT * INTO v FROM karratha135_pdc.vehicles WHERE id=b.canonical_vehicle_id;
      IF FOUND AND (v.lifecycle_state='completed' OR upper(btrim(coalesce(v.current_location,'')))='COMPLETED') THEN RETURN karratha135_pdc.navision_backend_response(false,'protected_completed_lifecycle'); END IF;
      IF FOUND AND (upper(btrim(coalesce(v.current_location,'')))='COLLECTED' OR v.rft_collected_at IS NOT NULL) THEN RETURN karratha135_pdc.navision_backend_response(false,'protected_collected_lifecycle'); END IF;
    END IF;
  END IF;
  RETURN karratha135_pdc.reconcile_navision_operational_record_pre_734(p_backend_record_id,p_actor_id,p_actor_email);
END
$function$;

CREATE OR REPLACE FUNCTION karratha135_pdc.reconcile_navision_operational_record_pre707(p_backend_record_id uuid, p_actor_id uuid DEFAULT NULL::uuid, p_actor_email text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'karratha135_pdc', 'extensions'
AS $function$
DECLARE b karratha135_pdc.navision_backend_records%rowtype; raw_status text; normalized text;
BEGIN
  IF NOT karratha135_pdc.pdc_monitor_staging_guard() THEN RETURN karratha135_pdc.navision_backend_response(false,'wrong_environment'); END IF;
  SELECT * INTO b FROM karratha135_pdc.navision_backend_records WHERE id=p_backend_record_id;
  IF FOUND THEN
    raw_status:=coalesce(b.normalized_data->>'toyotaStatus',b.normalized_data->>'navisionSubLocationDescription',b.normalized_data->>'vehicleStatus',b.normalized_data->>'navisionLocationStatus','');
    normalized:=regexp_replace(lower(btrim(raw_status)),'[^a-z0-9]+','','g');
    IF normalized='deliveredatdealer' AND karratha135_pdc.navision_operational_location(b.normalized_data)='Completed' THEN RETURN karratha135_pdc.reconcile_navision_delivery_700(p_backend_record_id,p_actor_id,p_actor_email); END IF;
  END IF;
  RETURN karratha135_pdc.reconcile_navision_operational_record_pre_700(p_backend_record_id,p_actor_id,p_actor_email);
END $function$;

CREATE OR REPLACE FUNCTION karratha135_pdc.reconcile_navision_operational_record_pre709(p_backend_record_id uuid, p_actor_id uuid DEFAULT NULL::uuid, p_actor_email text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'karratha135_pdc', 'auth', 'extensions'
AS $function$
DECLARE
  v_uid uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  b karratha135_pdc.navision_backend_records%rowtype;
  raw_status text;
  normalized text;
BEGIN
  IF NOT (
    coalesce(karratha135_pdc.pdc_monitor_authenticated_active_scope_674(NULL),false)
    OR (
      karratha135_pdc.pdc_monitor_staging_guard()
      AND auth.role()='authenticated'
      AND v_uid IS NOT NULL
      AND v_email<>''
      AND EXISTS(
        SELECT 1 FROM karratha135_pdc.pdc_email_ai_successor_runtime_identities i
        WHERE i.auth_user_id=v_uid AND i.normalized_email=v_email
          AND i.environment='staging'
          AND i.identity_purpose='pdc_email_ai_transaction_successor'
          AND i.active AND i.revoked_at IS NULL
      )
      AND EXISTS(
        SELECT 1 FROM karratha135_pdc.pdc_user_roles r
        WHERE r.auth_user_id=v_uid AND lower(r.email)=v_email
          AND r.active AND r.account_status='approved' AND r.role::text='viewer'
      )
      AND EXISTS(
        SELECT 1 FROM karratha135_pdc.pdc_monitor_stage_activation_writers w
        WHERE w.user_id=v_uid AND w.active AND w.revoked_at IS NULL
      )
    )
  ) THEN
    RETURN karratha135_pdc.navision_backend_response(false,'monitor_identity_required');
  END IF;
  IF (p_actor_id IS NOT NULL AND p_actor_id IS DISTINCT FROM v_uid)
     OR (p_actor_email IS NOT NULL AND lower(btrim(p_actor_email)) IS DISTINCT FROM v_email) THEN
    RETURN karratha135_pdc.navision_backend_response(false,'actor_identity_mismatch');
  END IF;
  IF p_backend_record_id IS NULL THEN
    RETURN karratha135_pdc.navision_backend_response(false,'invalid_input');
  END IF;
  SELECT * INTO b FROM karratha135_pdc.navision_backend_records WHERE id=p_backend_record_id;
  IF FOUND THEN
    raw_status:=coalesce(b.normalized_data->>'toyotaStatus',b.normalized_data->>'navisionSubLocationDescription',b.normalized_data->>'vehicleStatus',b.normalized_data->>'navisionLocationStatus','');
    normalized:=regexp_replace(lower(btrim(raw_status)),'[^a-z0-9]+','','g');
    IF normalized='deliveredatdealer' AND karratha135_pdc.navision_operational_location(b.normalized_data)='Completed' THEN
      RETURN karratha135_pdc.reconcile_navision_delivery_700(p_backend_record_id);
    END IF;
  END IF;
  RETURN karratha135_pdc.reconcile_navision_operational_record_pre707(p_backend_record_id,v_uid,v_email);
END $function$;

CREATE OR REPLACE FUNCTION karratha135_pdc.reconcile_navision_operational_record_pre_734(p_backend_record_id uuid, p_actor_id uuid, p_actor_email text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'karratha135_pdc', 'auth', 'extensions'
AS $function$
DECLARE
  v_uid uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  b karratha135_pdc.navision_backend_records%rowtype;
  raw_status text;
  normalized text;
BEGIN
  IF NOT (
    coalesce(karratha135_pdc.pdc_monitor_authenticated_active_scope_674(NULL),false)
    OR (
      karratha135_pdc.pdc_monitor_staging_guard()
      AND auth.role()='authenticated'
      AND v_uid IS NOT NULL
      AND v_email<>''
      AND EXISTS(
        SELECT 1 FROM karratha135_pdc.pdc_email_ai_successor_runtime_identities i
        WHERE i.auth_user_id=v_uid AND i.normalized_email=v_email
          AND i.environment='staging'
          AND i.identity_purpose='pdc_email_ai_transaction_successor'
          AND i.active AND i.revoked_at IS NULL
      )
      AND EXISTS(
        SELECT 1 FROM karratha135_pdc.pdc_user_roles r
        WHERE r.auth_user_id=v_uid AND lower(r.email)=v_email
          AND r.active AND r.account_status='approved' AND r.role::text='viewer'
      )
      AND EXISTS(
        SELECT 1 FROM karratha135_pdc.pdc_monitor_stage_activation_writers w
        WHERE w.user_id=v_uid AND w.active AND w.revoked_at IS NULL
      )
    )
  ) THEN
    RETURN karratha135_pdc.navision_backend_response(false,'monitor_identity_required');
  END IF;
  IF (p_actor_id IS NOT NULL AND p_actor_id IS DISTINCT FROM v_uid)
     OR (p_actor_email IS NOT NULL AND lower(btrim(p_actor_email)) IS DISTINCT FROM v_email) THEN
    RETURN karratha135_pdc.navision_backend_response(false,'actor_identity_mismatch');
  END IF;
  IF p_backend_record_id IS NULL THEN
    RETURN karratha135_pdc.navision_backend_response(false,'invalid_input');
  END IF;
  SELECT * INTO b FROM karratha135_pdc.navision_backend_records WHERE id=p_backend_record_id;
  IF FOUND THEN
    raw_status:=coalesce(b.normalized_data->>'toyotaStatus',b.normalized_data->>'navisionSubLocationDescription',b.normalized_data->>'vehicleStatus',b.normalized_data->>'navisionLocationStatus','');
    normalized:=regexp_replace(lower(btrim(raw_status)),'[^a-z0-9]+','','g');
    IF normalized='deliveredatdealer' AND karratha135_pdc.navision_operational_location(b.normalized_data)='Completed' THEN
      RETURN karratha135_pdc.reconcile_navision_delivery_700(p_backend_record_id);
    END IF;
  END IF;
  RETURN karratha135_pdc.reconcile_navision_operational_record_pre709(p_backend_record_id,v_uid,v_email);
END $function$;

CREATE OR REPLACE FUNCTION karratha135_pdc.reconcile_navision_delivery_700_pre707(p_backend_record_id uuid, p_actor_id uuid DEFAULT NULL::uuid, p_actor_email text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'karratha135_pdc', 'extensions'
 SET statement_timeout TO '120s'
AS $function$
DECLARE
  uid uuid:=coalesce(p_actor_id,auth.uid()); actor_email text:=lower(btrim(coalesce(p_actor_email,auth.jwt()->>'email',''))); b karratha135_pdc.navision_backend_records%rowtype; v karratha135_pdc.vehicles%rowtype; old karratha135_pdc.pdc_final_pdc_lifecycle_receipts_700%rowtype;
  raw_status text; request_payload jsonb; request_sha text; before_state jsonb; after_state jsonb; receipt uuid; result jsonb; closed_at timestamptz:=clock_timestamp(); duration bigint; activation karratha135_pdc.navision_board_activations%rowtype;
BEGIN
  IF NOT karratha135_pdc.pdc_monitor_staging_guard() OR p_backend_record_id IS NULL THEN RETURN karratha135_pdc.navision_backend_response(false,'wrong_environment_or_invalid_input'); END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('k135:pdc-700-delivery-record:'||p_backend_record_id::text,0));
  SELECT * INTO b FROM karratha135_pdc.navision_backend_records WHERE id=p_backend_record_id FOR UPDATE;
  IF NOT FOUND OR NOT b.is_current OR b.record_status<>'current' OR b.canonical_vehicle_id IS NULL THEN RETURN karratha135_pdc.navision_backend_response(false,'delivery_record_not_current'); END IF;
  raw_status:=coalesce(b.normalized_data->>'toyotaStatus',b.normalized_data->>'navisionSubLocationDescription',b.normalized_data->>'vehicleStatus',b.normalized_data->>'navisionLocationStatus','');
  IF btrim(raw_status)<>'Delivered - At Dealer' THEN RETURN karratha135_pdc.navision_backend_response(false,'delivery_status_not_exact'); END IF;
  IF karratha135_pdc.navision_exact_lifecycle_status(b.normalized_data)='deliveredatdealer'
     AND karratha135_pdc.navision_operational_location(b.normalized_data)='PMB' THEN
    RETURN karratha135_pdc.navision_backend_response(true,'dealer_fitment_not_terminal',jsonb_build_object('changed',false,'backend_record_id',b.id));
  END IF;
  SELECT * INTO v FROM karratha135_pdc.vehicles WHERE id=b.canonical_vehicle_id FOR UPDATE;
  IF NOT FOUND OR v.deleted_at IS NOT NULL THEN RETURN karratha135_pdc.navision_backend_response(false,'delivery_vehicle_not_found'); END IF;
  IF b.dealer_code IS DISTINCT FROM v.source_batch_id THEN RETURN karratha135_pdc.navision_backend_response(false,'delivery_wrong_dealer_scope'); END IF;
  SELECT * INTO old FROM karratha135_pdc.pdc_final_pdc_lifecycle_receipts_700 WHERE vehicle_id=v.id AND action='delivered';
  IF FOUND THEN RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false); END IF;
  IF NOT EXISTS(SELECT 1 FROM karratha135_pdc.pdc_final_pdc_lifecycle_receipts_700 WHERE vehicle_id=v.id AND action='rft_booked') OR NOT EXISTS(SELECT 1 FROM karratha135_pdc.pdc_final_pdc_lifecycle_receipts_700 WHERE vehicle_id=v.id AND action='collected') THEN RETURN karratha135_pdc.navision_backend_response(false,'delivery_requires_collected_interval'); END IF;
  IF v.lifecycle_state<>'rft' OR upper(btrim(coalesce(v.current_location,'')))<>'COLLECTED' OR v.dealer_transit_started_at IS NULL OR v.dealer_transit_closed_at IS NOT NULL OR v.dealer_transit_duration_seconds IS NOT NULL THEN RETURN karratha135_pdc.navision_backend_response(false,'delivery_interval_not_open'); END IF;
  duration:=greatest(0,floor(extract(epoch from (closed_at-v.dealer_transit_started_at)))::bigint);
  request_payload:=jsonb_build_object('contract','pdc-final-navision-delivery-700','backend_record_id',p_backend_record_id,'vehicle_id',v.id,'status',raw_status,'actor_id',uid);
  request_sha:=encode(extensions.digest(convert_to(request_payload::text,'UTF8'),'sha256'),'hex');
  before_state:=jsonb_build_object('vehicle',to_jsonb(v),'navision_record_id',p_backend_record_id,'status',raw_status,'timer_started_at',v.dealer_transit_started_at);
  UPDATE karratha135_pdc.vehicles SET lifecycle_state='completed',current_location='Completed',visible_on_board=false,dealer_transit_closed_at=closed_at,dealer_transit_duration_seconds=duration,delivered_to_dealer_date=coalesce(delivered_to_dealer_date,(closed_at at time zone 'Australia/Perth')::date),source_payload=coalesce(source_payload,'{}'::jsonb)||jsonb_build_object('authority','pdc_final_authoritative_lifecycle_700','navision_record_id',p_backend_record_id,'navision_status_literal',raw_status,'delivered_at',closed_at),version=version+1,updated_at=closed_at,updated_by=uid WHERE id=v.id RETURNING * INTO v;
  UPDATE karratha135_pdc.navision_board_activations SET canonical_vehicle_id=v.id,active=false,completed_at=coalesce(completed_at,closed_at),completion_reason='Delivered - At Dealer',completed_by=uid,completed_by_email=actor_email,updated_at=closed_at WHERE backend_record_id=b.id RETURNING * INTO activation;
  INSERT INTO karratha135_pdc.vehicle_movements(vehicle_id,from_location,to_location,from_pmb_stage,to_pmb_stage,from_pmb_bay_stage,to_pmb_bay_stage,from_pmb_bay_number,to_pmb_bay_number,reason,moved_by)
  VALUES(v.id,'Collected','Completed',NULL,NULL,NULL,NULL,NULL,NULL,'Exact Navision status Delivered - At Dealer closed dealer-transit timer',uid);
  after_state:=jsonb_build_object('vehicle',to_jsonb(v),'navision_record_id',p_backend_record_id,'status',raw_status,'timer_closed_at',closed_at,'duration_seconds',duration);
  receipt:=extensions.uuid_generate_v5('70000000-0000-5000-8000-000000000700'::uuid,'delivery:'||p_backend_record_id::text||':'||v.id::text);
  result:=jsonb_build_object('ok',true,'code','delivered_at_dealer_completed','replay',false,'data',jsonb_build_object('receipt_id',receipt,'vehicle_id',v.id,'backend_record_id',p_backend_record_id,'status','Delivered - At Dealer','vehicle_version_after',v.version,'dealer_transit_started_at',v.dealer_transit_started_at,'dealer_transit_closed_at',closed_at,'dealer_transit_duration_seconds',duration,'current_location','Completed','lifecycle_state','completed'));
  INSERT INTO karratha135_pdc.pdc_final_pdc_lifecycle_receipts_700(receipt_id,vehicle_id,action,actor_id,actor_email,idempotency_key,request_sha256,request_payload,before_state,after_state,evidence,response)
  VALUES(receipt,v.id,'delivered',uid,coalesce(actor_email,'system@staging.invalid'),extensions.uuid_generate_v5('70000000-0000-5000-8000-000000000700'::uuid,'delivery-idempotency:'||p_backend_record_id::text||':'||v.id::text),request_sha,request_payload,before_state,after_state,jsonb_build_object('exact_status_literal',true,'dealer_scope_exact',true,'open_interval_required',true,'duration_seconds',duration),result);
  PERFORM karratha135_pdc.audit_pdc_event('update','vehicles',v.id,v.id,before_state->'vehicle',to_jsonb(v),jsonb_build_object('action','reconcile_navision_delivery_700','receipt_id',receipt,'backend_record_id',p_backend_record_id,'status_literal',raw_status,'duration_seconds',duration));
  UPDATE karratha135_pdc.pdc_email_vehicle_revision SET revision=revision+1,updated_at=closed_at WHERE singleton;
  UPDATE karratha135_pdc.navision_backend_revision SET revision=revision+1,updated_at=closed_at WHERE singleton;
  RETURN result;
EXCEPTION WHEN unique_violation THEN
  SELECT * INTO old FROM karratha135_pdc.pdc_final_pdc_lifecycle_receipts_700 WHERE vehicle_id=b.canonical_vehicle_id AND action='delivered';
  IF FOUND THEN RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false); END IF;
  RETURN karratha135_pdc.navision_backend_response(false,'delivery_replay_conflict');
END $function$;
