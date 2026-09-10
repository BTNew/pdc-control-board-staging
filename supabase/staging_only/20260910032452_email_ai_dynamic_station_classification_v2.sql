-- STAGING ONLY: dynamic station classification for Revolution/Pilbara operation lines.
-- The Email AI classifies each imported operation before New Vehicles review.
-- REVIEW is reserved for genuinely uncertain classifications (< 0.80 confidence).

DO $guard$
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'STAGING only';
  END IF;
END
$guard$;

ALTER TABLE public.pdc_pilbara_service_classification_batches
  DROP CONSTRAINT IF EXISTS pdc_pilbara_service_classification_batches_contract_check;
ALTER TABLE public.pdc_pilbara_service_classification_batches
  ADD CONSTRAINT pdc_pilbara_service_classification_batches_contract_check
  CHECK (contract = ANY(ARRAY[
    'pilbara_service_operation_classifier_v1',
    'pilbara_service_operation_classifier_v2'
  ]));

CREATE OR REPLACE FUNCTION public.pdc_pilbara_service_classification_source_state_hash_v2(p_source_batch_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
AS $$
  SELECT encode(extensions.digest(convert_to(coalesce((
    SELECT jsonb_agg(jsonb_build_array(
      o.operation_id,o.semantic_hash,cc.classification_id,v.version,v.visible_on_board,r.status
    ) ORDER BY o.operation_id)::text
    FROM public.pdc_pilbara_service_operation_history oh
    JOIN public.pdc_pilbara_service_operations o ON o.operation_id=oh.operation_id
    JOIN public.vehicles v ON v.id=o.vehicle_id
    LEFT JOIN public.pdc_new_vehicle_reviews r ON r.vehicle_id=v.id
    LEFT JOIN public.pdc_pilbara_service_classification_current cc ON cc.operation_id=o.operation_id
    WHERE oh.batch_id=p_source_batch_id
  ),'[]'),'UTF8'),'sha256'),'hex');
$$;
REVOKE ALL ON FUNCTION public.pdc_pilbara_service_classification_source_state_hash_v2(uuid) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.pdc_pilbara_service_classification_source_v2(p_source_batch_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
SET statement_timeout TO '30s'
AS $$
DECLARE
  b public.pdc_pilbara_service_import_batches%rowtype;
  n integer;
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RETURN jsonb_build_object('ok',false,'code','wrong_environment');
  END IF;
  IF NOT public.pdc_email_ai_runtime_authorized_v1() THEN
    RETURN jsonb_build_object('ok',false,'code','not_authorized');
  END IF;
  SELECT * INTO b
  FROM public.pdc_pilbara_service_import_batches ib
  WHERE ib.batch_id=p_source_batch_id
    AND ib.batch_kind='apply'
    AND ib.importer_version='pilbara_service_open_jobcards_v1';
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','source_apply_batch_not_found'); END IF;
  SELECT count(DISTINCT oh.operation_id) INTO n
  FROM public.pdc_pilbara_service_operation_history oh
  WHERE oh.batch_id=b.batch_id;
  IF n<1 THEN RETURN jsonb_build_object('ok',false,'code','source_apply_batch_has_no_operations'); END IF;

  RETURN jsonb_build_object(
    'ok',true,
    'code','classification_source_ready',
    'source_batch_id',b.batch_id,
    'source_hash',b.source_hash,
    'operation_count',n,
    'operations',(
      SELECT jsonb_agg(jsonb_build_object(
        'operation_id',o.operation_id,
        'vehicle_id',o.vehicle_id,
        'stock_number',o.stock_number,
        'repair_order_number',o.repair_order_number,
        'original_line_number',o.original_line_number,
        'operation_description',o.operation_description,
        'estimated_hours',o.effective_estimated_hours,
        'source_semantic_hash',o.semantic_hash,
        'source_description_hash',encode(extensions.digest(convert_to(o.operation_description,'UTF8'),'sha256'),'hex'),
        'current_category',h.category,
        'current_method',h.method,
        'current_confidence',h.confidence,
        'prior_exact_description_hint',(
          SELECT jsonb_build_object(
            'category',ph.category,
            'method',ph.method,
            'confidence',ph.confidence,
            'rationale',ph.rationale
          )
          FROM public.pdc_pilbara_service_operations po
          JOIN public.pdc_pilbara_service_classification_current pc ON pc.operation_id=po.operation_id
          JOIN public.pdc_pilbara_service_classification_history ph ON ph.classification_id=pc.classification_id
          WHERE po.operation_id<>o.operation_id
            AND lower(regexp_replace(btrim(po.operation_description),'[^a-z0-9]+','','g'))
              = lower(regexp_replace(btrim(o.operation_description),'[^a-z0-9]+','','g'))
          ORDER BY ph.confidence DESC,ph.created_at DESC
          LIMIT 1
        )
      ) ORDER BY o.stock_number,o.repair_order_number,o.source_order,o.operation_id)
      FROM public.pdc_pilbara_service_operation_history oh
      JOIN public.pdc_pilbara_service_operations o ON o.operation_id=oh.operation_id
      LEFT JOIN public.pdc_pilbara_service_classification_current cc ON cc.operation_id=o.operation_id
      LEFT JOIN public.pdc_pilbara_service_classification_history h ON h.classification_id=cc.classification_id
      WHERE oh.batch_id=b.batch_id
    ),
    'allowed_stations',jsonb_build_array('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET','REVIEW'),
    'confidence_rule','assign station at >=0.80; use REVIEW below 0.80',
    'booking_changes',0,
    'completion_changes',0
  );
END
$$;
REVOKE ALL ON FUNCTION public.pdc_pilbara_service_classification_source_v2(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.pdc_pilbara_service_classification_source_v2(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.pdc_pilbara_service_classification_preview_v2(
  p_source_batch_id uuid,
  p_classifications jsonb,
  p_idempotency_key text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
SET lock_timeout TO '5s'
SET statement_timeout TO '60s'
AS $$
DECLARE
  b public.pdc_pilbara_service_import_batches%rowtype;
  prior public.pdc_pilbara_service_classification_batches%rowtype;
  rowj jsonb;
  o public.pdc_pilbara_service_operations%rowtype;
  v_batch_id uuid:=gen_random_uuid();
  idem text:=btrim(coalesce(p_idempotency_key,''));
  state_hash text;
  manifest jsonb;
  manifest_hash text;
  response jsonb;
  op_count integer;
  insert_count integer:=0;
  update_count integer:=0;
  unchanged_count integer:=0;
  review_count integer:=0;
  category text;
  method text;
  confidence numeric;
  current_h public.pdc_pilbara_service_classification_history%rowtype;
  actor_label text:=lower(btrim(coalesce(auth.jwt()->>'email','')))||':viewer:'||coalesce(auth.uid()::text,'missing');
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RETURN jsonb_build_object('ok',false,'code','wrong_environment');
  END IF;
  IF NOT public.pdc_email_ai_runtime_authorized_v1() THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
  IF p_source_batch_id IS NULL
     OR jsonb_typeof(p_classifications) IS DISTINCT FROM 'array'
     OR length(idem) NOT BETWEEN 12 AND 160 THEN
    RETURN jsonb_build_object('ok',false,'code','invalid_classification_request');
  END IF;

  SELECT * INTO b
  FROM public.pdc_pilbara_service_import_batches ib
  WHERE ib.batch_id=p_source_batch_id
    AND ib.batch_kind='apply'
    AND ib.importer_version='pilbara_service_open_jobcards_v1'
  FOR SHARE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','source_apply_batch_not_found'); END IF;

  SELECT count(DISTINCT oh.operation_id) INTO op_count
  FROM public.pdc_pilbara_service_operation_history oh
  WHERE oh.batch_id=b.batch_id;

  IF op_count<1
     OR jsonb_array_length(p_classifications)<>op_count
     OR (SELECT count(DISTINCT value->>'operation_id') FROM jsonb_array_elements(p_classifications))<>op_count THEN
    RETURN jsonb_build_object(
      'ok',false,'code','all_operations_require_one_classification',
      'expected',op_count,'received',jsonb_array_length(p_classifications)
    );
  END IF;

  manifest:=jsonb_build_object(
    'contract','pilbara_service_operation_classifier_v2',
    'classifier_version','pdc-email-ai-station-classifier-v2',
    'source_batch_id',b.batch_id,
    'source_hash',b.source_hash,
    'classifications',p_classifications
  );
  manifest_hash:=encode(extensions.digest(convert_to(manifest::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pilbara_service_operation_classifier_v2:preview:'||idem,0));

  SELECT * INTO prior
  FROM public.pdc_pilbara_service_classification_batches cb
  WHERE cb.batch_kind='preview' AND cb.idempotency_key=idem;
  IF FOUND THEN
    IF prior.manifest_hash<>manifest_hash THEN RETURN jsonb_build_object('ok',false,'code','idempotency_conflict'); END IF;
    RETURN prior.response||jsonb_build_object('code','preview_replay','replay',true);
  END IF;

  FOR rowj IN SELECT value FROM jsonb_array_elements(p_classifications) LOOP
    BEGIN
      category:=upper(btrim(coalesce(rowj->>'category','')));
      method:=lower(btrim(coalesce(rowj->>'method','')));
      confidence:=(rowj->>'confidence')::numeric;
    EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
      RETURN jsonb_build_object('ok',false,'code','classification_schema_failed');
    END;

    IF jsonb_typeof(rowj) IS DISTINCT FROM 'object'
       OR coalesce(rowj->>'operation_id','') !~ '^[0-9a-fA-F-]{36}$'
       OR category NOT IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET','REVIEW')
       OR method NOT IN('deterministic_rule','ai_semantic','review')
       OR confidence NOT BETWEEN 0 AND 1
       OR length(btrim(coalesce(rowj->>'rationale',''))) NOT BETWEEN 3 AND 240
       OR coalesce(rowj->>'source_semantic_hash','') !~ '^[a-f0-9]{64}$'
       OR coalesce(rowj->>'source_description_hash','') !~ '^[a-f0-9]{64}$'
       OR (category='REVIEW' AND (method<>'review' OR confidence>=0.80))
       OR (category<>'REVIEW' AND confidence<0.80)
       OR (method='deterministic_rule' AND (
          nullif(btrim(coalesce(rowj->>'rule_id','')),'') IS NULL
          OR nullif(btrim(coalesce(rowj->>'ruleset_version','')),'') IS NULL
          OR nullif(btrim(coalesce(rowj->>'provider','')),'') IS NOT NULL
          OR nullif(btrim(coalesce(rowj->>'model','')),'') IS NOT NULL
          OR nullif(btrim(coalesce(rowj->>'run_id','')),'') IS NOT NULL
       ))
       OR (method IN('ai_semantic','review') AND (
          nullif(btrim(coalesce(rowj->>'rule_id','')),'') IS NOT NULL
          OR nullif(btrim(coalesce(rowj->>'ruleset_version','')),'') IS NOT NULL
          OR nullif(btrim(coalesce(rowj->>'provider','')),'') IS NULL
          OR nullif(btrim(coalesce(rowj->>'model','')),'') IS NULL
          OR nullif(btrim(coalesce(rowj->>'run_id','')),'') IS NULL
       )) THEN
      RETURN jsonb_build_object('ok',false,'code','classification_contract_failed','operation_id',rowj->>'operation_id');
    END IF;

    SELECT op.* INTO o
    FROM public.pdc_pilbara_service_operations op
    JOIN public.pdc_pilbara_service_operation_history oh
      ON oh.operation_id=op.operation_id AND oh.batch_id=b.batch_id
    WHERE op.operation_id=(rowj->>'operation_id')::uuid;

    IF NOT FOUND
       OR o.semantic_hash IS DISTINCT FROM rowj->>'source_semantic_hash'
       OR encode(extensions.digest(convert_to(o.operation_description,'UTF8'),'sha256'),'hex') IS DISTINCT FROM rowj->>'source_description_hash' THEN
      RETURN jsonb_build_object('ok',false,'code','source_binding_conflict','operation_id',rowj->>'operation_id');
    END IF;

    SELECT h.* INTO current_h
    FROM public.pdc_pilbara_service_classification_current cc
    JOIN public.pdc_pilbara_service_classification_history h USING(classification_id)
    WHERE cc.operation_id=o.operation_id;

    IF NOT FOUND THEN
      insert_count:=insert_count+1;
    ELSIF current_h.category=category
      AND current_h.method=method
      AND current_h.confidence=confidence
      AND current_h.rationale=rowj->>'rationale'
      AND coalesce(current_h.rule_id,'')=coalesce(rowj->>'rule_id','')
      AND coalesce(current_h.ruleset_version,'')=coalesce(rowj->>'ruleset_version','')
      AND coalesce(current_h.provider,'')=coalesce(rowj->>'provider','')
      AND coalesce(current_h.model,'')=coalesce(rowj->>'model','')
      AND coalesce(current_h.model_run_id,'')=coalesce(rowj->>'run_id','')
      AND current_h.source_semantic_hash=o.semantic_hash THEN
      unchanged_count:=unchanged_count+1;
    ELSE
      update_count:=update_count+1;
    END IF;
    IF category='REVIEW' THEN review_count:=review_count+1; END IF;
  END LOOP;

  state_hash:=public.pdc_pilbara_service_classification_source_state_hash_v2(b.batch_id);
  response:=jsonb_build_object(
    'ok',true,'code','preview_created','preview_batch_id',v_batch_id,
    'source_batch_id',b.batch_id,'source_hash',b.source_hash,
    'operation_count',op_count,'insert',insert_count,'update',update_count,'unchanged',unchanged_count,
    'review',review_count,'assigned',op_count-review_count,
    'category_totals',(
      SELECT jsonb_object_agg(q.category,q.total)
      FROM (
        SELECT upper(value->>'category') category,count(*) total
        FROM jsonb_array_elements(p_classifications)
        GROUP BY 1 ORDER BY 1
      ) q
    ),
    'apply_allowed',true,'booking_changes',0,'completion_changes',0
  );

  INSERT INTO public.pdc_pilbara_service_classification_batches(
    batch_id,contract,batch_kind,source_importer_version,source_batch_id,classifier_version,
    manifest_hash,idempotency_key,current_state_hash,manifest,response,created_actor
  ) VALUES(
    v_batch_id,'pilbara_service_operation_classifier_v2','preview','pilbara_service_open_jobcards_v1',b.batch_id,
    'pdc-email-ai-station-classifier-v2',manifest_hash,idem,state_hash,manifest,response,actor_label
  );
  RETURN response;
END
$$;
REVOKE ALL ON FUNCTION public.pdc_pilbara_service_classification_preview_v2(uuid,jsonb,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.pdc_pilbara_service_classification_preview_v2(uuid,jsonb,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.pdc_pilbara_service_classification_apply_v2(
  p_preview_batch_id uuid,
  p_idempotency_key text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
SET lock_timeout TO '5s'
SET statement_timeout TO '60s'
AS $$
DECLARE
  preview public.pdc_pilbara_service_classification_batches%rowtype;
  prior public.pdc_pilbara_service_classification_batches%rowtype;
  rowj jsonb;
  o public.pdc_pilbara_service_operations%rowtype;
  current_h public.pdc_pilbara_service_classification_history%rowtype;
  new_id uuid;
  version_no integer;
  v_batch_id uuid:=gen_random_uuid();
  idem text:=btrim(coalesce(p_idempotency_key,''));
  state_hash text;
  v_response jsonb;
  inserted integer:=0;
  updated integer:=0;
  unchanged integer:=0;
  actor_label text:=lower(btrim(coalesce(auth.jwt()->>'email','')))||':viewer:'||coalesce(auth.uid()::text,'missing');
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RETURN jsonb_build_object('ok',false,'code','wrong_environment');
  END IF;
  IF NOT public.pdc_email_ai_runtime_authorized_v1() THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
  IF p_preview_batch_id IS NULL OR length(idem) NOT BETWEEN 12 AND 160 THEN RETURN jsonb_build_object('ok',false,'code','invalid_apply_request'); END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('pilbara_service_operation_classifier_v2:apply:'||idem,0));
  SELECT * INTO preview
  FROM public.pdc_pilbara_service_classification_batches cb
  WHERE cb.batch_id=p_preview_batch_id
    AND cb.batch_kind='preview'
    AND cb.contract='pilbara_service_operation_classifier_v2'
  FOR SHARE;
  IF NOT FOUND OR coalesce((preview.response->>'apply_allowed')::boolean,false) IS NOT TRUE THEN
    RETURN jsonb_build_object('ok',false,'code','preview_not_eligible');
  END IF;

  SELECT * INTO prior
  FROM public.pdc_pilbara_service_classification_batches cb
  WHERE cb.batch_kind='apply' AND cb.idempotency_key=idem;
  IF FOUND THEN
    IF prior.preview_of_batch_id IS DISTINCT FROM preview.batch_id OR prior.manifest_hash<>preview.manifest_hash THEN
      RETURN jsonb_build_object('ok',false,'code','idempotency_conflict');
    END IF;
    RETURN prior.response||jsonb_build_object('code','apply_replay','replay',true);
  END IF;

  state_hash:=public.pdc_pilbara_service_classification_source_state_hash_v2(preview.source_batch_id);
  IF state_hash<>preview.current_state_hash THEN RETURN jsonb_build_object('ok',false,'code','current_state_changed'); END IF;

  FOR rowj IN SELECT value FROM jsonb_array_elements(preview.manifest->'classifications') LOOP
    SELECT op.* INTO o
    FROM public.pdc_pilbara_service_operations op
    JOIN public.pdc_pilbara_service_operation_history oh
      ON oh.operation_id=op.operation_id AND oh.batch_id=preview.source_batch_id
    WHERE op.operation_id=(rowj->>'operation_id')::uuid;
    IF NOT FOUND
       OR o.semantic_hash IS DISTINCT FROM rowj->>'source_semantic_hash'
       OR encode(extensions.digest(convert_to(o.operation_description,'UTF8'),'sha256'),'hex') IS DISTINCT FROM rowj->>'source_description_hash' THEN
      RETURN jsonb_build_object('ok',false,'code','source_binding_conflict','operation_id',rowj->>'operation_id');
    END IF;
  END LOOP;

  v_response:=jsonb_build_object(
    'ok',true,'code','applied','apply_batch_id',v_batch_id,
    'source_batch_id',preview.source_batch_id,
    'operation_count',preview.response->'operation_count',
    'assigned',preview.response->'assigned',
    'review',preview.response->'review',
    'category_totals',preview.response->'category_totals',
    'booking_changes',0,'completion_changes',0,'work_item_changes',0,'atomic',true,'replay',false
  );

  INSERT INTO public.pdc_pilbara_service_classification_batches(
    batch_id,contract,batch_kind,source_importer_version,source_batch_id,classifier_version,
    manifest_hash,idempotency_key,current_state_hash,manifest,response,preview_of_batch_id,created_actor
  ) VALUES(
    v_batch_id,'pilbara_service_operation_classifier_v2','apply',preview.source_importer_version,
    preview.source_batch_id,preview.classifier_version,preview.manifest_hash,idem,preview.current_state_hash,
    preview.manifest,'{}'::jsonb,preview.batch_id,actor_label
  );

  FOR rowj IN SELECT value FROM jsonb_array_elements(preview.manifest->'classifications') LOOP
    SELECT * INTO o FROM public.pdc_pilbara_service_operations
    WHERE operation_id=(rowj->>'operation_id')::uuid FOR SHARE;

    SELECT h.* INTO current_h
    FROM public.pdc_pilbara_service_classification_current cc
    JOIN public.pdc_pilbara_service_classification_history h USING(classification_id)
    WHERE cc.operation_id=o.operation_id
    FOR SHARE OF h;

    IF FOUND
       AND current_h.category=upper(rowj->>'category')
       AND current_h.method=lower(rowj->>'method')
       AND current_h.confidence=(rowj->>'confidence')::numeric
       AND current_h.rationale=rowj->>'rationale'
       AND coalesce(current_h.rule_id,'')=coalesce(rowj->>'rule_id','')
       AND coalesce(current_h.ruleset_version,'')=coalesce(rowj->>'ruleset_version','')
       AND coalesce(current_h.provider,'')=coalesce(rowj->>'provider','')
       AND coalesce(current_h.model,'')=coalesce(rowj->>'model','')
       AND coalesce(current_h.model_run_id,'')=coalesce(rowj->>'run_id','')
       AND current_h.source_semantic_hash=o.semantic_hash THEN
      unchanged:=unchanged+1;
      CONTINUE;
    END IF;

    SELECT coalesce(max(classification_version),0)+1 INTO version_no
    FROM public.pdc_pilbara_service_classification_history
    WHERE operation_id=o.operation_id;

    INSERT INTO public.pdc_pilbara_service_classification_history(
      operation_id,batch_id,classification_version,category,method,confidence,rationale,
      rule_id,ruleset_version,provider,model,model_run_id,
      source_description_hash,source_semantic_hash,classifier_version,supersedes_classification_id
    ) VALUES(
      o.operation_id,v_batch_id,version_no,upper(rowj->>'category'),lower(rowj->>'method'),
      (rowj->>'confidence')::numeric,rowj->>'rationale',
      nullif(rowj->>'rule_id',''),nullif(rowj->>'ruleset_version',''),
      nullif(rowj->>'provider',''),nullif(rowj->>'model',''),nullif(rowj->>'run_id',''),
      rowj->>'source_description_hash',rowj->>'source_semantic_hash',preview.classifier_version,current_h.classification_id
    ) RETURNING classification_id INTO new_id;

    INSERT INTO public.pdc_pilbara_service_classification_current(operation_id,classification_id)
    VALUES(o.operation_id,new_id)
    ON CONFLICT(operation_id) DO UPDATE
      SET classification_id=excluded.classification_id,updated_at=clock_timestamp();

    IF current_h.classification_id IS NULL THEN inserted:=inserted+1; ELSE updated:=updated+1; END IF;
  END LOOP;

  v_response:=v_response||jsonb_build_object('insert',inserted,'update',updated,'unchanged',unchanged);
  UPDATE public.pdc_pilbara_service_classification_batches
    SET response=v_response
    WHERE pdc_pilbara_service_classification_batches.batch_id=v_batch_id;
  UPDATE public.pdc_email_vehicle_revision
    SET revision=revision+1,updated_at=clock_timestamp()
    WHERE singleton;
  RETURN v_response;
END
$$;
REVOKE ALL ON FUNCTION public.pdc_pilbara_service_classification_apply_v2(uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.pdc_pilbara_service_classification_apply_v2(uuid,text) TO authenticated;
