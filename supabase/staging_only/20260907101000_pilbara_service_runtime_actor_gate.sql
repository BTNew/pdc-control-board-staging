-- STAGING ONLY: bind Pilbara Service apply to the scoped runtime actor required by controlled Navision activation.
BEGIN;
SET LOCAL lock_timeout='30s';
SET LOCAL statement_timeout='300s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-pilbara-service-runtime-actor-gate',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR current_setting('app.environment',true)='production'
     OR NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel
         WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT (version,name)::text FROM supabase_migrations.schema_migrations
         WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1)
        IS DISTINCT FROM '(20260907100000,pilbara_service_open_jobcards_v1)'
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260907101000')
  THEN RAISE EXCEPTION 'PDC_20260907101000_STAGING_PREDECESSOR_OR_SCOPE_GUARD_FAILED' USING ERRCODE='55000';
  END IF;
END
$guard$;

CREATE OR REPLACE FUNCTION public.pdc_pilbara_service_apply_v1(p_preview_batch_id uuid,p_source_hash text,p_idempotency_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions AS $apply$
DECLARE
  v_role text:=public.current_pdc_user_role()::text;
  v_actor uuid:=auth.uid();
  v_actor_label text:=lower(btrim(coalesce(auth.jwt()->>'email','')))||':'||coalesce(v_role,'unknown')||':'||coalesce(v_actor::text,'missing');
  v_preview public.pdc_pilbara_service_import_batches%rowtype;
  v_prior public.pdc_pilbara_service_import_batches%rowtype;
  v_batch uuid:=gen_random_uuid();
  v_backend uuid;
  v_activation jsonb;
  v_revision bigint;
  v_vehicle uuid;
  v_row public.pdc_pilbara_service_import_rows%rowtype;
  v_operation uuid;
  v_response jsonb;
  v_request_hash text;
BEGIN
  IF current_setting('app.environment',true)='production'
     OR NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel
         WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RETURN jsonb_build_object('ok',false,'code','wrong_environment');
  END IF;
  IF v_actor IS NULL OR NOT coalesce(v_role='viewer',false)
     OR NOT EXISTS(SELECT 1 FROM public.pdc_email_ai_successor_runtime_identities i
       WHERE i.auth_user_id=v_actor AND i.normalized_email=lower(btrim(coalesce(auth.jwt()->>'email','')))
         AND i.environment='staging' AND i.identity_purpose='pdc_email_ai_transaction_successor'
         AND i.active AND i.revoked_at IS NULL)
     OR NOT EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers w
       WHERE w.user_id=v_actor AND w.active AND w.revoked_at IS NULL) THEN
    RETURN jsonb_build_object('ok',false,'code','unauthorized');
  END IF;
  IF length(btrim(coalesce(p_idempotency_key,''))) NOT BETWEEN 12 AND 160 THEN
    RETURN jsonb_build_object('ok',false,'code','invalid_idempotency_key');
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pilbara_service_open_jobcards_v1:apply:'||lower(btrim(coalesce(p_source_hash,''))),0));
  SELECT * INTO v_preview FROM public.pdc_pilbara_service_import_batches
   WHERE batch_id=p_preview_batch_id AND batch_kind='preview' FOR SHARE;
  IF NOT FOUND OR v_preview.source_hash<>lower(btrim(coalesce(p_source_hash,'')))
     OR NOT coalesce((v_preview.response->>'apply_allowed')::boolean,false)
     OR (v_preview.response->'matched'->>'stocks')::integer<>21
     OR (v_preview.response->'matched'->>'lines')::integer<>122
     OR (v_preview.response->'unmatched'->>'stocks')::integer<>16
     OR (v_preview.response->'unmatched'->>'lines')::integer<>39
     OR (v_preview.response->'ambiguous'->>'stocks')::integer<>0
     OR v_preview.quarantined_line_count<>40
     OR v_preview.conflict_count<>0 THEN
    RETURN jsonb_build_object('ok',false,'code','apply_not_eligible');
  END IF;
  LOCK TABLE public.navision_backend_records IN SHARE ROW EXCLUSIVE MODE;
  LOCK TABLE public.vehicles IN SHARE ROW EXCLUSIVE MODE;
  PERFORM pg_advisory_xact_lock(hashtextextended('navision-backend-store',0));
  PERFORM 1 FROM public.navision_backend_records b
    JOIN (SELECT DISTINCT backend_record_id FROM public.pdc_pilbara_service_import_rows
      WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged')) r ON r.backend_record_id=b.id
    FOR UPDATE OF b;
  PERFORM 1 FROM public.vehicles v
    JOIN (SELECT DISTINCT stock_number FROM public.pdc_pilbara_service_import_rows
      WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged')) r ON btrim(v.stock_number)=btrim(r.stock_number)
    WHERE v.deleted_at IS NULL FOR SHARE OF v;
  v_request_hash:=encode(extensions.digest(convert_to(
    jsonb_build_object('preview_batch_id',p_preview_batch_id,'source_hash',v_preview.source_hash,
      'idempotency_key',btrim(p_idempotency_key),'importer_version','pilbara_service_open_jobcards_v1')::text,'UTF8'),'sha256'),'hex');
  SELECT * INTO v_prior FROM public.pdc_pilbara_service_import_batches
   WHERE importer_version='pilbara_service_open_jobcards_v1' AND batch_kind='apply' AND source_hash=v_preview.source_hash;
  IF FOUND THEN
    IF v_prior.request_hash<>v_request_hash THEN RETURN jsonb_build_object('ok',false,'code','idempotency_conflict'); END IF;
    v_response:=v_prior.response||jsonb_build_object('code','apply_replay');
    INSERT INTO public.pdc_pilbara_service_import_receipts(
      batch_id,importer_version,source_hash,receipt_kind,outcome,created_by,created_actor)
    VALUES(v_prior.batch_id,'pilbara_service_open_jobcards_v1',v_preview.source_hash,'replay',v_response,v_actor,v_actor_label);
    RETURN v_response;
  END IF;
  IF EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows r
    LEFT JOIN public.navision_backend_records b ON b.id=r.backend_record_id
    WHERE r.batch_id=v_preview.batch_id AND r.decision IN('insert','unchanged') AND (
      b.id IS NULL OR NOT b.is_current OR b.record_status<>'current' OR b.source_system<>'microsoft_navision'
      OR b.dealer_code<>'37047'
      OR btrim(coalesce(b.normalized_data->>'batch',b.normalized_data->>'stock',''))<>btrim(r.stock_number)
      OR (SELECT count(*) FROM public.navision_backend_records x WHERE x.source_system='microsoft_navision'
        AND x.is_current AND x.record_status='current' AND x.dealer_code='37047'
        AND btrim(coalesce(x.normalized_data->>'batch',x.normalized_data->>'stock',''))=btrim(r.stock_number))<>1
      OR (SELECT count(*) FROM public.vehicles v WHERE v.deleted_at IS NULL
        AND btrim(v.stock_number)=btrim(r.stock_number))>1
      OR (r.vehicle_id IS NULL AND EXISTS(SELECT 1 FROM public.vehicles v
        WHERE v.deleted_at IS NULL AND btrim(v.stock_number)=btrim(r.stock_number)))
      OR (r.vehicle_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.vehicles v
        WHERE v.deleted_at IS NULL AND v.id=r.vehicle_id AND btrim(v.stock_number)=btrim(r.stock_number)))
      OR EXISTS(SELECT 1 FROM public.vehicles v
        WHERE v.deleted_at IS NULL AND btrim(v.stock_number)=btrim(r.stock_number)
          AND NOT (b.canonical_vehicle_id IS NULL OR b.canonical_vehicle_id=v.id))
    )) THEN
    RETURN jsonb_build_object('ok',false,'code','apply_cardinality_changed');
  END IF;
  IF EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows r JOIN public.pdc_pilbara_service_operations o
    ON o.importer_version=r.importer_version AND o.stock_number=r.stock_number AND o.repair_order_number=r.repair_order_number
      AND o.original_line_number=r.original_line_number
    WHERE r.batch_id=v_preview.batch_id AND o.semantic_hash<>r.semantic_hash) THEN
    RETURN jsonb_build_object('ok',false,'code','semantic_identity_conflict');
  END IF;

  FOR v_backend IN SELECT DISTINCT backend_record_id FROM public.pdc_pilbara_service_import_rows
    WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged') ORDER BY backend_record_id
  LOOP
    SELECT revision INTO v_revision FROM public.navision_backend_revision WHERE singleton;
    v_activation:=public.activate_navision_backend_record(
      'pilbara-service-v1-'||substr(v_preview.source_hash,1,24)||'-'||substr(v_backend::text,1,8),
      v_backend,v_revision,'approved_email_build');
    IF NOT coalesce((v_activation->>'ok')::boolean,false) THEN
      RAISE EXCEPTION 'PDC_PILBARA_CONTROLLED_ACTIVATION_FAILED:%',v_activation USING ERRCODE='55000';
    END IF;
    SELECT canonical_vehicle_id INTO v_vehicle FROM public.navision_backend_records WHERE id=v_backend;
    IF v_vehicle IS NULL OR NOT EXISTS(SELECT 1 FROM public.vehicles v JOIN public.navision_backend_records b ON b.id=v_backend
      WHERE v.id=v_vehicle AND v.deleted_at IS NULL AND b.canonical_vehicle_id=v.id
        AND btrim(v.stock_number)=btrim(coalesce(b.normalized_data->>'batch',b.normalized_data->>'stock',''))) THEN
      RAISE EXCEPTION 'PDC_PILBARA_CONTROLLED_ACTIVATION_DID_NOT_LINK:%',v_backend USING ERRCODE='55000';
    END IF;
  END LOOP;

  v_response:=jsonb_build_object('ok',true,'code','applied','apply_batch_id',v_batch,
    'source_hash',v_preview.source_hash,'insert',v_preview.insert_count,'update',0,
    'unchanged',v_preview.unchanged_count,'quarantine',v_preview.quarantined_line_count,
    'matched_stock_numbers',v_preview.response->'matched'->'matched_stock_numbers',
    'unmatched_stock_numbers',v_preview.response->'unmatched'->'unmatched_stock_numbers',
    'standalone_vehicles_created',0,'identity_authority','exact_current_navision_controlled_activation',
    'activation_source','approved_email_build','atomic',true,'service_forbidden_vehicle_fields_changed',0);
  INSERT INTO public.pdc_pilbara_service_import_batches(batch_id,importer_version,source_hash,request_hash,idempotency_key,batch_kind,
    source_row_count,accepted_line_count,quarantined_line_count,matched_stock_count,unmatched_stock_count,ambiguous_stock_count,
    insert_count,update_count,unchanged_count,conflict_count,response,created_by,created_actor)
  VALUES(v_batch,'pilbara_service_open_jobcards_v1',v_preview.source_hash,v_request_hash,btrim(p_idempotency_key),'apply',162,
    (v_preview.response->'matched'->>'lines')::integer,v_preview.quarantined_line_count,
    (v_preview.response->'matched'->>'stocks')::integer,(v_preview.response->'unmatched'->>'stocks')::integer,
    (v_preview.response->'ambiguous'->>'stocks')::integer,v_preview.insert_count,0,v_preview.unchanged_count,0,v_response,
    v_actor,v_actor_label);
  FOR v_row IN SELECT * FROM public.pdc_pilbara_service_import_rows
    WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged') ORDER BY source_order
  LOOP
    SELECT canonical_vehicle_id INTO v_vehicle FROM public.navision_backend_records WHERE id=v_row.backend_record_id;
    SELECT operation_id INTO v_operation FROM public.pdc_pilbara_service_operations
     WHERE importer_version=v_row.importer_version AND stock_number=v_row.stock_number
       AND repair_order_number=v_row.repair_order_number AND original_line_number=v_row.original_line_number;
    IF NOT FOUND THEN
      INSERT INTO public.pdc_pilbara_service_operations(importer_version,stock_number,repair_order_number,original_line_number,source_order,
        vehicle_id,operation_description,source_estimated_hours,effective_estimated_hours,hours_provenance,parts_on_backorder_raw,
        parts_semantics,classification,semantic_hash,raw_evidence_id)
      VALUES('pilbara_service_open_jobcards_v1',v_row.stock_number,v_row.repair_order_number,v_row.original_line_number,v_row.source_order,
        v_vehicle,v_row.normalized_payload->>'operation_description',(v_row.normalized_payload->>'source_estimated_hours')::numeric,
        (v_row.normalized_payload->>'effective_estimated_hours')::numeric,v_row.normalized_payload->>'hours_provenance',
        coalesce(v_row.normalized_payload->>'parts_on_backorder_raw',''),v_row.normalized_payload->>'parts_semantics','Review',
        v_row.semantic_hash,v_row.evidence_id)
      RETURNING operation_id INTO v_operation;
    END IF;
    INSERT INTO public.pdc_pilbara_service_operation_history(operation_id,batch_id,event_kind,prior_semantic_hash,resulting_semantic_hash,immutable_snapshot)
    VALUES(v_operation,v_batch,v_row.decision,CASE WHEN v_row.decision='unchanged' THEN v_row.semantic_hash END,
      v_row.semantic_hash,v_row.normalized_payload);
  END LOOP;
  UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;
  INSERT INTO public.pdc_pilbara_service_import_receipts(
    batch_id,importer_version,source_hash,receipt_kind,outcome,created_by,created_actor)
  VALUES(v_batch,'pilbara_service_open_jobcards_v1',v_preview.source_hash,'apply',v_response,v_actor,v_actor_label);
  RETURN v_response;
END
$apply$;
REVOKE ALL ON FUNCTION public.pdc_pilbara_service_apply_v1(uuid,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.pdc_pilbara_service_apply_v1(uuid,text,text) TO authenticated;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
 '20260907101000','pilbara_service_runtime_actor_gate',ARRAY[
  'bind Pilbara Service apply to the existing scoped authenticated runtime viewer and activation-writer identity',
  'keep administrator credentials out of the Email AI activation path while retaining exact-source and STAGING gates'
 ]);
NOTIFY pgrst,'reload schema';
COMMIT;
