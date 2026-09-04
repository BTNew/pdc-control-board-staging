-- Executed only after 20260904010800 in the same transaction; caller must ROLLBACK.
SELECT set_config('request.jwt.claims','{"sub":"df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b","email":"sales@broometoyota.com.au","role":"authenticated"}',true);

DO $regression$
DECLARE
 target constant uuid:='e49685ca-c9b7-448d-9b45-1aba97d6d3b4';
 source_receipt constant uuid:='5d4f30f7-561c-4998-a68d-7dfd5e188fe1';
 source_hash constant text:='7e7d24755e4856f0d7fe22086b6b84842874c0474fe60a2f9e754fe088fcbc95';
 source_vin constant text:='JTFHB8CP806024409';
 other_vehicle uuid;backend_batch uuid;result jsonb;success_receipt uuid;
 fixture_vehicle constant uuid:='f33d9bf0-1536-5d3e-a7cd-fbb945e785f1';
BEGIN
 SELECT id INTO STRICT other_vehicle FROM public.vehicles WHERE id<>target AND deleted_at IS NULL ORDER BY id LIMIT 1;
 SELECT first_seen_batch_id INTO STRICT backend_batch FROM public.navision_backend_records WHERE is_current AND record_status='current' ORDER BY id LIMIT 1;

 -- Active canonical vehicle collision rejects atomically.
 INSERT INTO public.vehicles(id,permanent_vehicle_id,vin,lifecycle_state,visible_on_board,source_payload,source_system,source_batch_id,source_record_id)
 VALUES(fixture_vehicle,'HERMES-VIN-COLLISION-ACTIVE',source_vin,'active',false,'{"test":"20260904010800"}'::jsonb,'hermes_test','20260904010800','active-collision');
 result:=public.project_pdc_non_navision_jobcard_vin_20260904(target,2,source_receipt,source_hash,source_vin,'11111111-1111-4111-8111-111111111111');
 IF result->>'code'<>'non_navision_vin_collision' OR (SELECT (vin IS NOT NULL OR version<>2) FROM public.vehicles WHERE id=target)
    OR EXISTS(SELECT 1 FROM public.pdc_non_navision_vin_projection_receipts_20260904 WHERE vehicle_id=target) THEN
  RAISE EXCEPTION 'PDC_20260904010800_ACTIVE_VEHICLE_COLLISION_REGRESSION:%',result USING errcode='55000';
 END IF;
 DELETE FROM public.vehicles WHERE id=fixture_vehicle;

 -- Soft-deleted canonical identities remain collision owners.
 INSERT INTO public.vehicles(id,permanent_vehicle_id,vin,lifecycle_state,visible_on_board,source_payload,source_system,source_batch_id,source_record_id,deleted_at)
 VALUES(fixture_vehicle,'HERMES-VIN-COLLISION-DELETED',source_vin,'active',false,'{"test":"20260904010800"}'::jsonb,'hermes_test','20260904010800','deleted-collision',clock_timestamp());
 result:=public.project_pdc_non_navision_jobcard_vin_20260904(target,2,source_receipt,source_hash,source_vin,'22222222-2222-4222-8222-222222222222');
 IF result->>'code'<>'non_navision_vin_collision' OR (SELECT (vin IS NOT NULL OR version<>2) FROM public.vehicles WHERE id=target) THEN
  RAISE EXCEPTION 'PDC_20260904010800_DELETED_VEHICLE_COLLISION_REGRESSION:%',result USING errcode='55000';
 END IF;
 DELETE FROM public.vehicles WHERE id=fixture_vehicle;

 -- Active and inactive alias identities both fail closed.
 INSERT INTO public.vehicle_aliases(vehicle_id,alias_type,alias_value,active,source_system,source_batch_id)
 VALUES(other_vehicle,'vin',source_vin,true,'hermes_test','20260904010800');
 result:=public.project_pdc_non_navision_jobcard_vin_20260904(target,2,source_receipt,source_hash,source_vin,'33333333-3333-4333-8333-333333333333');
 IF result->>'code'<>'non_navision_vin_collision' OR (SELECT vin IS NOT NULL FROM public.vehicles WHERE id=target) THEN
  RAISE EXCEPTION 'PDC_20260904010800_ACTIVE_ALIAS_COLLISION_REGRESSION:%',result USING errcode='55000';
 END IF;
 DELETE FROM public.vehicle_aliases WHERE vehicle_id=other_vehicle AND alias_type_normalized='vin' AND normalized_alias_value=source_vin;
 INSERT INTO public.vehicle_aliases(vehicle_id,alias_type,alias_value,active,source_system,source_batch_id)
 VALUES(other_vehicle,'vin',source_vin,false,'hermes_test','20260904010800');
 result:=public.project_pdc_non_navision_jobcard_vin_20260904(target,2,source_receipt,source_hash,source_vin,'44444444-4444-4444-8444-444444444444');
 IF result->>'code'<>'non_navision_vin_collision' OR (SELECT vin IS NOT NULL FROM public.vehicles WHERE id=target) THEN
  RAISE EXCEPTION 'PDC_20260904010800_INACTIVE_ALIAS_COLLISION_REGRESSION:%',result USING errcode='55000';
 END IF;
 DELETE FROM public.vehicle_aliases WHERE vehicle_id=other_vehicle AND alias_type_normalized='vin' AND normalized_alias_value=source_vin;

 -- Any current backend identity, not only the two Navision dealer scopes, collides.
 INSERT INTO public.navision_backend_records(source_record_id,row_hash,normalized_data,raw_evidence,first_seen_batch_id,last_seen_batch_id,
  is_current,version,source_system,dealer_code,record_status)
 VALUES('pdc-test-vin-collision-20260904010800',repeat('c',64),jsonb_build_object('vin',source_vin,'batch','HERMES-VIN-COLLISION'),
  '{"test":"20260904010800"}'::jsonb,backend_batch,backend_batch,true,1,'hermes_test','14450','current');
 result:=public.project_pdc_non_navision_jobcard_vin_20260904(target,2,source_receipt,source_hash,source_vin,'55555555-5555-4555-8555-555555555555');
 IF result->>'code'<>'non_navision_vin_collision' OR (SELECT vin IS NOT NULL FROM public.vehicles WHERE id=target) THEN
  RAISE EXCEPTION 'PDC_20260904010800_BACKEND_COLLISION_REGRESSION:%',result USING errcode='55000';
 END IF;
 DELETE FROM public.navision_backend_records WHERE source_system='hermes_test' AND source_record_id='pdc-test-vin-collision-20260904010800';

 -- Exact source-bound correction succeeds once and returns authoritative provenance.
 result:=public.project_pdc_non_navision_jobcard_vin_20260904(target,2,source_receipt,source_hash,lower(source_vin),'6e32736d-e774-5d66-b2c7-35261c6f02ec');
 IF NOT coalesce((result->>'ok')::boolean,false) OR result->>'code'<>'non_navision_vin_projected'
    OR result#>>'{data,vin_after}'<>source_vin OR result#>>'{data,vehicle_version_before}'<>'2'
    OR result#>>'{data,vehicle_version_after}'<>'3' OR result#>>'{data,effective_provenance,vin,value}'<>source_vin
    OR (SELECT (vin<>source_vin OR version<>3 OR stock_number<>'U158318' OR job_card_number<>'J138000812'
       OR registration<>'1HJX697' OR customer_name<>'CATALYST METALS PTY LTD' OR current_location<>'YH'
       OR lifecycle_state<>'active' OR NOT visible_on_board) FROM public.vehicles WHERE id=target) THEN
  RAISE EXCEPTION 'PDC_20260904010800_SUCCESS_REGRESSION:%',result USING errcode='55000';
 END IF;
 success_receipt:=(result#>>'{data,receipt_id}')::uuid;

 -- The original actor-owned Job Card receipt now reads corrected VIN evidence
 -- from the immutable projection receipt, not mutable intake/vehicle payloads.
 result:=public.read_pdc_non_navision_jobcard_receipt(source_receipt);
 IF NOT coalesce((result->>'ok')::boolean,false)
    OR result#>>'{data,canonical_vin}'<>source_vin
    OR result#>>'{data,source_provenance,source_receipt_id}'<>source_receipt::text
    OR result#>>'{data,source_provenance,authenticated_source_vin}'<>source_vin
    OR result#>>'{data,effective_provenance,vin,value}'<>source_vin
    OR result#>>'{data,effective_provenance,vin,source_receipt_id}'<>source_receipt::text THEN
  RAISE EXCEPTION 'PDC_20260904010800_JOB_CARD_READBACK_PROVENANCE_REGRESSION:%',result USING errcode='55000';
 END IF;

 -- Exact replay is idempotent; changed payload under the same key fails.
 result:=public.project_pdc_non_navision_jobcard_vin_20260904(target,2,source_receipt,source_hash,source_vin,'6e32736d-e774-5d66-b2c7-35261c6f02ec');
 IF NOT coalesce((result->>'ok')::boolean,false) OR result#>>'{data,replay}'<>'true'
    OR (result#>>'{data,receipt_id}')::uuid<>success_receipt OR (SELECT version<>3 FROM public.vehicles WHERE id=target) THEN
  RAISE EXCEPTION 'PDC_20260904010800_EXACT_REPLAY_REGRESSION:%',result USING errcode='55000';
 END IF;
 result:=public.project_pdc_non_navision_jobcard_vin_20260904(target,2,source_receipt,source_hash,'JTFHB8CP806024408','6e32736d-e774-5d66-b2c7-35261c6f02ec');
 IF result->>'code'<>'non_navision_vin_projection_replay_mismatch' OR (SELECT vin<>source_vin OR version<>3 FROM public.vehicles WHERE id=target) THEN
  RAISE EXCEPTION 'PDC_20260904010800_REPLAY_MISMATCH_REGRESSION:%',result USING errcode='55000';
 END IF;

 -- A new idempotency key cannot create a duplicate no-op projection receipt.
 result:=public.project_pdc_non_navision_jobcard_vin_20260904(target,3,source_receipt,source_hash,source_vin,'88888888-8888-4888-8888-888888888888');
 IF result->>'code'<>'non_navision_vin_already_projected'
    OR (SELECT vin<>source_vin OR version<>3 FROM public.vehicles WHERE id=target)
    OR (SELECT count(*) FROM public.pdc_non_navision_vin_projection_receipts_20260904 WHERE vehicle_id=target)<>1 THEN
  RAISE EXCEPTION 'PDC_20260904010800_DUPLICATE_PROJECTION_REGRESSION:%',result USING errcode='55000';
 END IF;

 -- A different existing VIN is never overwritten.
 result:=public.project_pdc_non_navision_jobcard_vin_20260904(target,3,source_receipt,source_hash,'JTFHB8CP806024408','77777777-7777-4777-8777-777777777777');
 IF result->>'code'<>'non_navision_vin_projection_source_mismatch' OR (SELECT vin<>source_vin OR version<>3 FROM public.vehicles WHERE id=target) THEN
  RAISE EXCEPTION 'PDC_20260904010800_EXISTING_VIN_REGRESSION:%',result USING errcode='55000';
 END IF;

 IF (SELECT count(*) FROM public.pdc_non_navision_vin_projection_receipts_20260904 WHERE vehicle_id=target)<>1 THEN
  RAISE EXCEPTION 'PDC_20260904010800_RECEIPT_CARDINALITY_REGRESSION' USING errcode='55000';
 END IF;
END
$regression$;
