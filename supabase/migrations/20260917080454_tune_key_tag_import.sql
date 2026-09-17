-- Exact-stock Tune key tags; blank/zero preserve keys; conflicting tags fail atomically.
begin;
create or replace function public.pdc_tune_key_number_v1(p_row jsonb)
returns text language plpgsql immutable set search_path=pg_catalog,public as $key$
declare value text;
begin
 value:=public.pdc_tune_text_field_v5(coalesce(p_row->'raw_row','{}')||p_row,
  array['Key Tag Number','key_tag_number','key_number','key number','key tag','key no']);
 if value is null or lower(value) in ('','0','none','null','n/a','na','unknown','not recorded','-') then return null; end if;
 if value ~ '^0+([.]0+)?$' then return null; end if;
 if value ~ '^[0-9]+[.]0+$' then value:=split_part(value,'.',1); end if;
 if value !~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$' then return null; end if;
 return upper(value);
end $key$;
revoke all on function public.pdc_tune_key_number_v1(jsonb) from public,anon;
grant execute on function public.pdc_tune_key_number_v1(jsonb) to authenticated,service_role;


CREATE OR REPLACE FUNCTION public.pdc_tune_source_fields_v5(p_row jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE r jsonb:=coalesce(p_row->'raw_row','{}')||p_row; po text; bo text;
BEGIN
 po:=public.pdc_tune_text_field_v5(r,ARRAY['purchase_order_number','parts_purchase_order_number','purchase order no','purchase order','po number','po no','po #','p/o #']);
 IF lower(coalesce(po,'')) IN('','0','no','none','n/a','na','unknown','not recorded','-','all') THEN po:=NULL; END IF;
 bo:=public.pdc_tune_text_field_v5(r,ARRAY['parts_on_backorder_raw','parts on backorder','parts on back order','backorder']);
 RETURN jsonb_build_object('key_number',public.pdc_tune_key_number_v1(r),'customer_name',public.pdc_tune_text_field_v5(r,ARRAY['customer_name','customer name','customer surname','customer','client','owner name']),
 'vehicle_description',public.pdc_tune_text_field_v5(r,ARRAY['range #','range id','vehicle_description','vehicle description','vehicle','model description','model']),
 'vin',upper(public.pdc_tune_text_field_v5(r,ARRAY['vin','vehicle identification number'])),
 'parts_on_backorder_raw',bo,'purchase_order_number',po,
 'parts_attached',public.pdc_numeric_parts_flag_20260911(r->'Parts Attached'),
 'backorder',public.pdc_numeric_parts_flag_20260911(r->'Parts on Backorder'),
 'backorder_with_po',public.pdc_numeric_parts_flag_20260911(r->'Backorder with PO (1=Yes, 0=No)'));
END $function$
;
create or replace function public.pdc_apply_tune_key_number_v1(p_vehicle_id uuid,p_batch_id uuid,p_preview_batch_id uuid)
returns jsonb language plpgsql set search_path=pg_catalog,public as $key_apply$
declare b public.pdc_pilbara_service_import_batches%rowtype; v public.vehicles%rowtype; after_v public.vehicles%rowtype; keys text[];
begin
 select * into strict b from public.pdc_pilbara_service_import_batches where batch_id=p_batch_id and batch_kind='apply' and contract_revision='pmg_stock_v5';
 if not exists(select 1 from public.pdc_pilbara_service_import_batches where batch_id=p_preview_batch_id and batch_kind='preview' and source_hash=b.source_hash and contract_revision=b.contract_revision) then
  raise exception 'tune_key_preview_apply_mismatch' using errcode='22023';
 end if;
 select * into strict v from public.vehicles where id=p_vehicle_id and deleted_at is null for update;
 select array_agg(distinct k.key_number) filter(where k.key_number is not null) into keys
 from public.pdc_pilbara_service_import_rows r
 cross join lateral(select public.pdc_tune_key_number_v1(r.raw_row||r.normalized_payload) key_number) k
 where r.batch_id=p_preview_batch_id and r.stock_number=v.stock_number and (r.decision in('insert','unchanged') or (r.decision='quarantine' and r.reason='operation_update_review' and r.vehicle_id=v.id));
 if cardinality(keys)>1 then raise exception 'conflicting_tune_key_numbers' using errcode='22023'; end if;
 if keys[1] is null or keys[1] is not distinct from v.key_number then
  return jsonb_build_object('changed',false,'key_number',v.key_number);
 end if;
 update public.vehicles set key_number=keys[1],
  source_payload=coalesce(source_payload,'{}')||jsonb_build_object('tune_key_number',keys[1],'tune_key_batch_id',p_batch_id,'tune_key_source','Key Tag Number'),
  version=version+1,updated_by=b.created_by,updated_at=clock_timestamp() where id=v.id returning * into after_v;
 perform public.audit_pdc_event('update','vehicles',v.id,v.id,to_jsonb(v),to_jsonb(after_v),
  jsonb_build_object('contract','tune_key_tag_import_v1','source_batch_id',p_batch_id,'preview_batch_id',p_preview_batch_id));
 return jsonb_build_object('changed',true,'key_number',keys[1]);
end $key_apply$;
revoke all on function public.pdc_apply_tune_key_number_v1(uuid,uuid,uuid) from public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.pdc_pilbara_service_apply_v1(p_preview_batch_id uuid, p_source_hash text, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
 SET lock_timeout TO '5s'
 SET statement_timeout TO '60s'
AS $function$
DECLARE
  v_codex_scoped boolean := public.pdc_email_ai_runtime_authorized_v1() IS NOT TRUE;
  v_candidate jsonb; v_stock text; v_tune boolean; v_code text; v_backend uuid;
  v_actor uuid:=pdc_codex_intake_private.import_actor();v_actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));v_actor_label text:=v_actor_email||':viewer:'||coalesce(v_actor::text,'missing');
  v_source_hash text:=lower(btrim(coalesce(p_source_hash,'')));v_idem text:=btrim(coalesce(p_idempotency_key,''));v_request_hash text;
  v_preview public.pdc_pilbara_service_import_batches%rowtype;v_prior public.pdc_pilbara_service_import_batches%rowtype;v_apply_batch uuid:=gen_random_uuid();
  v_row public.pdc_pilbara_service_import_rows%rowtype;v_op public.pdc_pilbara_service_operations%rowtype;v_vehicle_id uuid;v_first_ro text;v_operation_id uuid;v_identity_hash text;v_response jsonb;
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE OR current_setting('app.environment',true)='production' OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  THEN RETURN jsonb_build_object('ok',false,'code','wrong_environment');END IF;
  IF v_codex_scoped AND pdc_codex_intake_private.authorized('apply',NULL,p_source_hash,p_idempotency_key,p_preview_batch_id) IS NOT TRUE THEN RETURN jsonb_build_object('ok',false,'code','not_authorized');END IF;
  IF v_codex_scoped THEN v_actor_label:=v_actor_email||':codex_workbook_importer:'||v_actor::text; END IF;
  IF pdc_codex_intake_private.management_connection() IS TRUE THEN v_actor_label:='codex_supabase_management:postgres:'||v_actor::text; END IF;
  IF p_preview_batch_id IS NULL OR v_source_hash !~ '^[a-f0-9]{64}$' OR length(v_idem) NOT BETWEEN 12 AND 160 THEN RETURN jsonb_build_object('ok',false,'code','invalid_apply_request');END IF;
  SELECT * INTO v_preview FROM public.pdc_pilbara_service_import_batches b WHERE b.batch_id=p_preview_batch_id AND b.importer_version='pilbara_service_open_jobcards_v1' AND b.batch_kind='preview' FOR SHARE;
  IF NOT FOUND OR v_preview.source_hash<>v_source_hash OR NOT coalesce((v_preview.response->>'apply_allowed')::boolean,false) THEN RETURN jsonb_build_object('ok',false,'code','apply_not_eligible');END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
  v_tune:=v_preview.contract_revision IN('pmg_stock_v3','pmg_stock_v4','pmg_stock_v5');
  v_request_hash:=encode(extensions.digest(convert_to(jsonb_build_object('contract','pdc_pilbara_service_apply_v1_dynamic_20260910','preview_batch_id',p_preview_batch_id,'source_hash',v_source_hash)::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pilbara_service_open_jobcards_v1:apply:'||v_source_hash,0));
  SELECT * INTO v_prior FROM public.pdc_pilbara_service_import_batches b WHERE b.importer_version='pilbara_service_open_jobcards_v1' AND b.source_hash=v_source_hash AND b.batch_kind='apply' AND b.contract_revision=v_preview.contract_revision;
  IF FOUND THEN
    IF v_codex_scoped AND pdc_codex_intake_private.authorized('readback',NULL,NULL,NULL,v_prior.batch_id) IS NOT TRUE
    THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
    IF v_prior.request_hash<>v_request_hash THEN RETURN jsonb_build_object('ok',false,'code','source_apply_conflict');END IF;
    INSERT INTO public.pdc_pilbara_service_import_receipts(batch_id,importer_version,source_hash,receipt_kind,outcome,created_by,created_actor)
    VALUES(v_prior.batch_id,'pilbara_service_open_jobcards_v1',v_source_hash,'replay',v_prior.response||jsonb_build_object('code','apply_replay','replay',true),v_actor,v_actor_label);
    RETURN v_prior.response||jsonb_build_object('code','apply_replay','replay',true,'tune_checkout_transfers',(SELECT count(*) FROM pdc_codex_intake_private.tune_checkout_receipts WHERE batch_id=v_prior.batch_id));END IF;
  IF v_preview.contract_revision IN('pmg_stock_v3','pmg_stock_v4') AND v_preview.accepted_line_count>0 THEN
    RETURN jsonb_build_object('ok',false,'code','preview_refresh_required','contract_revision','pmg_stock_v5');
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
  IF NOT v_tune AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows r0 LEFT JOIN public.navision_backend_records b ON b.id=r0.backend_record_id LEFT JOIN public.vehicles v ON v.id=r0.vehicle_id
    WHERE r0.batch_id=v_preview.batch_id AND r0.decision IN('insert','unchanged') AND (b.id IS NULL OR NOT b.is_current OR b.record_status<>'current' OR b.source_system<>'microsoft_navision'
      OR b.dealer_code<>'37047' OR b.canonical_vehicle_id IS DISTINCT FROM r0.vehicle_id
      OR btrim(coalesce(b.normalized_data->>'batch',b.normalized_data->>'stock','')) IS DISTINCT FROM btrim(r0.stock_number)
      OR v.id IS NULL OR v.deleted_at IS NOT NULL OR v.lifecycle_state::text<>'active' OR v.stock_number_normalized IS DISTINCT FROM btrim(r0.stock_number)
      OR (SELECT count(*) FROM public.navision_backend_records x WHERE x.source_system='microsoft_navision' AND x.dealer_code='37047' AND x.is_current AND x.record_status='current'
        AND btrim(coalesce(x.normalized_data->>'batch',x.normalized_data->>'stock',''))=btrim(r0.stock_number))<>1))
  THEN RETURN jsonb_build_object('ok',false,'code','apply_cardinality_changed');END IF;
  IF EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows r0 WHERE r0.batch_id=v_preview.batch_id AND r0.decision='insert'
      AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.importer_version='pilbara_service_open_jobcards_v1'
        AND public.pdc_pilbara_service_operation_identity_hash_v3(o.department,o.stock_number,o.repair_order_number,o.original_line_number,o.operation_description)=r0.normalized_payload->>'operation_identity_hash'))
     OR EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows r0 WHERE r0.batch_id=v_preview.batch_id AND r0.decision='unchanged'
      AND NOT EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.importer_version='pilbara_service_open_jobcards_v1'
        AND public.pdc_pilbara_service_operation_identity_hash_v3(o.department,o.stock_number,o.repair_order_number,o.original_line_number,o.operation_description)=r0.normalized_payload->>'operation_identity_hash'
        AND o.semantic_hash=r0.semantic_hash))
  THEN RETURN jsonb_build_object('ok',false,'code','operation_state_changed_after_preview');END IF;
  IF v_tune THEN
    -- Serialize Stock creation with all canonical writers and validate every candidate before any write.
    LOCK TABLE public.vehicles, public.navision_backend_records IN SHARE ROW EXCLUSIVE MODE;
    FOR v_row IN SELECT * FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged') ORDER BY stock_number LOOP
      v_candidate:=public.pdc_pmg_stock_candidate_v5(v_row.stock_number);
      IF (v_candidate->>'ok')::boolean IS NOT TRUE
        OR (v_row.vehicle_id IS NOT NULL AND v_row.vehicle_id IS DISTINCT FROM (v_candidate->>'vehicle_id')::uuid)
        OR v_row.backend_record_id IS DISTINCT FROM (v_candidate->>'backend_record_id')::uuid
      THEN RETURN jsonb_build_object('ok',false,'code','apply_cardinality_changed','stock_number',v_row.stock_number); END IF;
    END LOOP;
  END IF;
  IF v_tune AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows r JOIN public.pdc_unidentified_tune_review u ON u.workbook_sha256=r.normalized_payload->>'workbook_sha256' AND u.operation_identity_hash=r.normalized_payload->>'operation_identity_hash'
    WHERE r.batch_id=v_preview.batch_id AND r.reason='unidentified_tune_review' AND (u.source_estimated_hours IS DISTINCT FROM (r.normalized_payload->>'source_estimated_hours')::numeric OR u.raw_row IS DISTINCT FROM r.raw_row))
  THEN RETURN jsonb_build_object('ok',false,'code','unidentified_source_changed'); END IF;
  v_response:=jsonb_build_object('ok',true,'code','applied','replay',false,'apply_batch_id',v_apply_batch,'source_hash',v_source_hash,'source_link',v_preview.source_link,'unidentified_rows',(SELECT count(*) FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND reason='unidentified_tune_review'),'operation_updates_for_review',coalesce((v_preview.response->>'operation_updates_for_review')::integer,0),'approvals_created',0,'insert',v_preview.insert_count,'update',0,
    'unchanged',v_preview.unchanged_count,'duplicate_ignored',coalesce((v_preview.response->'operations'->>'duplicate_ignored')::integer,0),'bookings_created',0,'completions_created',0,'atomic',true);
  INSERT INTO public.pdc_pilbara_service_import_batches(contract_revision,source_link,batch_id,importer_version,source_hash,request_hash,idempotency_key,batch_kind,source_row_count,accepted_line_count,quarantined_line_count,
    matched_stock_count,unmatched_stock_count,ambiguous_stock_count,insert_count,update_count,unchanged_count,conflict_count,response,created_by,created_actor)
  VALUES(v_preview.contract_revision,v_preview.source_link,v_apply_batch,'pilbara_service_open_jobcards_v1',v_source_hash,v_request_hash,v_idem,'apply',v_preview.source_row_count,v_preview.accepted_line_count,v_preview.quarantined_line_count,
    v_preview.matched_stock_count,v_preview.unmatched_stock_count,v_preview.ambiguous_stock_count,v_preview.insert_count,0,v_preview.unchanged_count,v_preview.conflict_count,v_response,v_actor,v_actor_label);
  IF v_tune THEN
    FOR v_stock IN SELECT DISTINCT stock_number FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged') ORDER BY stock_number LOOP
      v_candidate:=public.pdc_pmg_stock_candidate_v5(v_stock);
      IF (v_candidate->>'create_vehicle')::boolean THEN
        INSERT INTO public.vehicles(permanent_vehicle_id,stock_number,vin,source_system,source_record_id,current_location,visible_on_board,lifecycle_state,created_by,updated_by,source_payload)
        VALUES('TUNE/PMG:'||v_stock,v_stock,NULL,'tune_pmg',v_stock,'Yard Hold',false,'active',v_actor,v_actor,v_preview.source_link||jsonb_build_object('intake_source_system','tune_pmg'));
      END IF;
      v_backend:=(v_candidate->>'backend_record_id')::uuid;
      IF v_backend IS NOT NULL THEN
        SELECT id INTO STRICT v_vehicle_id FROM public.vehicles
        WHERE stock_number_normalized=public.normalize_vehicle_stock_number(v_stock) AND deleted_at IS NULL;
        -- Link only the unique current exact-Stock record accepted by this revision.
        -- Keep the pending vehicle's lifecycle and location; do not activate the board.
        UPDATE public.navision_backend_records SET canonical_vehicle_id=v_vehicle_id
        WHERE id=v_backend AND canonical_vehicle_id IS NULL;
        UPDATE public.vehicles SET source_system='microsoft_navision',source_record_id=v_backend::text,
          source_payload=coalesce(source_payload,'{}')||v_preview.source_link||jsonb_build_object('intake_source_system','tune_pmg')
        WHERE id=v_vehicle_id;
        PERFORM public.navision_refresh_linked_vehicle_projection_770(v_backend);
      END IF;
    END LOOP;
    IF v_preview.contract_revision='pmg_stock_v5' THEN
      FOR v_stock IN SELECT DISTINCT stock_number FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged') LOOP
        SELECT id INTO STRICT v_vehicle_id FROM public.vehicles WHERE stock_number=v_stock AND deleted_at IS NULL;
        PERFORM public.pdc_apply_tune_vehicle_fields_v5(v_vehicle_id,v_apply_batch,v_preview.batch_id);
      END LOOP;
    END IF;
    -- Key tags are vehicle metadata, including when operation edits await review.
    IF v_preview.contract_revision='pmg_stock_v5' THEN
      FOR v_stock IN SELECT DISTINCT stock_number FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND (decision IN('insert','unchanged') OR (decision='quarantine' AND reason='operation_update_review' AND vehicle_id IS NOT NULL)) AND stock_number IS NOT NULL LOOP
        SELECT id INTO STRICT v_vehicle_id FROM public.vehicles WHERE stock_number=v_stock AND deleted_at IS NULL;
        PERFORM public.pdc_apply_tune_key_number_v1(v_vehicle_id,v_apply_batch,v_preview.batch_id);
      END LOOP;
    END IF;
    INSERT INTO public.pdc_unidentified_tune_review(workbook_sha256,repair_order_number,department,original_line_number,operation_description,operation_identity_hash,source_estimated_hours,operation_code,proposed_station,raw_row,source_hash,source_batch_id)
    SELECT r.normalized_payload->>'workbook_sha256',r.repair_order_number,r.normalized_payload->>'department',r.original_line_number,r.normalized_payload->>'operation_description',r.normalized_payload->>'operation_identity_hash',
      (r.normalized_payload->>'source_estimated_hours')::numeric,r.normalized_payload->>'operation_code',r.normalized_payload->>'proposed_station',r.raw_row,v_source_hash,v_apply_batch
    FROM public.pdc_pilbara_service_import_rows r WHERE r.batch_id=v_preview.batch_id AND r.reason='unidentified_tune_review'
    ON CONFLICT(workbook_sha256,operation_identity_hash) DO NOTHING;
  END IF;
  FOR v_row IN SELECT * FROM public.pdc_pilbara_service_import_rows r WHERE r.batch_id=v_preview.batch_id AND r.decision IN('insert','unchanged') ORDER BY r.source_order LOOP
    IF v_tune THEN SELECT id INTO STRICT v_row.vehicle_id FROM public.vehicles WHERE stock_number_normalized=public.normalize_vehicle_stock_number(v_row.stock_number) AND deleted_at IS NULL; END IF;
    v_identity_hash:=v_row.normalized_payload->>'operation_identity_hash';
    SELECT * INTO v_op FROM public.pdc_pilbara_service_operations x WHERE x.importer_version='pilbara_service_open_jobcards_v1'
      AND public.pdc_pilbara_service_operation_identity_hash_v3(x.department,x.stock_number,x.repair_order_number,x.original_line_number,x.operation_description)=v_identity_hash FOR SHARE;
    IF v_row.decision='insert' THEN
      IF FOUND THEN RAISE EXCEPTION 'operation state changed after preview' USING ERRCODE='40001';END IF;
      INSERT INTO public.pdc_pilbara_service_operations(department,operation_code,proposed_station,importer_version,stock_number,repair_order_number,original_line_number,source_order,vehicle_id,operation_description,
        source_estimated_hours,effective_estimated_hours,hours_provenance,parts_on_backorder_raw,parts_semantics,classification,semantic_hash,raw_evidence_id)
      VALUES(v_row.normalized_payload->>'department',v_row.normalized_payload->>'operation_code',v_row.normalized_payload->>'proposed_station','pilbara_service_open_jobcards_v1',v_row.stock_number,v_row.repair_order_number,v_row.original_line_number,v_row.source_order,v_row.vehicle_id,v_row.normalized_payload->>'operation_description',
        CASE WHEN v_row.normalized_payload->>'source_estimated_hours' IS NULL THEN NULL ELSE (v_row.normalized_payload->>'source_estimated_hours')::numeric END,
        (v_row.normalized_payload->>'effective_estimated_hours')::numeric,v_row.normalized_payload->>'hours_provenance',coalesce(v_row.normalized_payload->>'parts_on_backorder_raw',''),
        v_row.normalized_payload->>'parts_semantics','Review',v_row.semantic_hash,v_row.evidence_id) RETURNING operation_id INTO v_operation_id;
      INSERT INTO public.pdc_pilbara_service_operation_history(operation_id,batch_id,event_kind,prior_semantic_hash,resulting_semantic_hash,immutable_snapshot)
      VALUES(v_operation_id,v_apply_batch,'insert',NULL,v_row.semantic_hash,v_row.normalized_payload);
    ELSE
      IF NOT FOUND OR v_op.semantic_hash<>v_row.semantic_hash THEN RAISE EXCEPTION 'operation state changed after preview' USING ERRCODE='40001';END IF;
      v_operation_id:=v_op.operation_id;
      INSERT INTO public.pdc_pilbara_service_operation_history(operation_id,batch_id,event_kind,prior_semantic_hash,resulting_semantic_hash,immutable_snapshot)
      VALUES(v_operation_id,v_apply_batch,'unchanged',v_op.semantic_hash,v_op.semantic_hash,v_row.normalized_payload);
    END IF;
  END LOOP;
  FOR v_vehicle_id IN SELECT DISTINCT o.vehicle_id FROM public.pdc_pilbara_service_operation_history h JOIN public.pdc_pilbara_service_operations o USING(operation_id) WHERE h.batch_id=v_apply_batch LOOP
    -- Rolling imports retain operations absent from this file.
    SELECT CASE WHEN count(DISTINCT r0.repair_order_number)=1 THEN min(r0.repair_order_number) ELSE NULL END INTO v_first_ro FROM public.pdc_pilbara_service_import_rows r0
    WHERE r0.batch_id=v_preview.batch_id AND (r0.vehicle_id=v_vehicle_id OR (v_tune AND r0.stock_number=(SELECT stock_number FROM public.vehicles WHERE id=v_vehicle_id))) AND r0.decision IN('insert','unchanged');
    IF EXISTS(SELECT 1 FROM public.vehicles v WHERE v.id=v_vehicle_id AND NOT v.visible_on_board)
      AND NOT EXISTS(SELECT 1 FROM public.pdc_new_vehicle_reviews r WHERE r.vehicle_id=v_vehicle_id AND r.status='closed') THEN
      INSERT INTO public.pdc_new_vehicle_reviews(vehicle_id,status,source_kind,first_job_card,received_at,approved_at,approved_by,approval_key,approval_hash,approval_receipt)
      VALUES(v_vehicle_id,'pending',CASE WHEN v_tune THEN 'tune_pmg' ELSE 'revolution_report' END,v_first_ro,clock_timestamp(),NULL,NULL,NULL,NULL,NULL)
      ON CONFLICT(vehicle_id) DO UPDATE SET status='pending',source_kind=excluded.source_kind,first_job_card=excluded.first_job_card,received_at=clock_timestamp(),
        approved_at=NULL,approved_by=NULL,approval_key=NULL,approval_hash=NULL,approval_receipt=NULL;
      UPDATE public.vehicles SET job_card_number=v_first_ro,version=version+1,updated_by=v_actor,updated_at=clock_timestamp() WHERE id=v_vehicle_id AND visible_on_board=false;
    END IF;
  END LOOP;
  PERFORM public.pdc_capture_tune_operation_changes_20260912(v_preview.batch_id,v_apply_batch);
  INSERT INTO public.pdc_pilbara_service_import_receipts(batch_id,importer_version,source_hash,receipt_kind,outcome,created_by,created_actor)
  VALUES(v_apply_batch,'pilbara_service_open_jobcards_v1',v_source_hash,'apply',v_response,v_actor,v_actor_label);
  UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;
  UPDATE public.navision_backend_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;
  PERFORM public.workshop_bump_revision();
  PERFORM pdc_parts_private.sync_service_jobs();
  PERFORM pdc_codex_intake_private.capture_service_locations(v_preview.batch_id,v_apply_batch);
  IF v_preview.contract_revision='pmg_stock_v5' THEN PERFORM pdc_codex_intake_private.capture_service_status(v_preview.batch_id,v_apply_batch); END IF;
  PERFORM pdc_codex_intake_private.apply_service_arrival(v_apply_batch);
  RETURN v_response||jsonb_build_object('tune_checkout_transfers',(SELECT count(*) FROM pdc_codex_intake_private.tune_checkout_receipts WHERE batch_id=v_apply_batch));
END
$function$
;
commit;
