-- STAGING-only Craig-approved delivery fuel/charge classification rule.
BEGIN;
SET LOCAL lock_timeout='30s';
SET LOCAL statement_timeout='300s';
SELECT pg_advisory_xact_lock(hashtextextended('pilbara_delivery_fuel_charge_fitting_rule_20260908',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $migration$
DECLARE
  v_head jsonb;
  v_source_batch_id uuid;
  v_preview_batch_id uuid:=gen_random_uuid();
  v_apply_batch_id uuid:=gen_random_uuid();
  v_manifest jsonb;
  v_manifest_hash text;
  v_state_before text;
  v_state_after text;
  v_match_count integer;
  v_update_count integer;
  v_manual_conflict_count integer;
  v_updated integer:=0;
  v_work jsonb;
  v_operation record;
  v_prior_id uuid;
  v_new_id uuid;
  v_next_version integer;
BEGIN
  SELECT jsonb_build_array(version,name) INTO v_head
  FROM supabase_migrations.schema_migrations
  WHERE version~'^[0-9]{14}$'
  ORDER BY version::bigint DESC LIMIT 1;

  IF current_user<>'postgres' OR session_user<>'postgres'
     OR NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel
         WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR v_head IS DISTINCT FROM '["20260907114000","pilbara_service_operation_classifier_rollback_cleanup"]'::jsonb
     OR (SELECT count(*) FROM public.pdc_pilbara_service_operations)<>122
  THEN
    RAISE EXCEPTION 'PDC_PILBARA_FUEL_RULE_STAGING_HEAD_OR_DATA_GUARD_FAILED' USING ERRCODE='55000';
  END IF;

  SELECT batch_id INTO STRICT v_source_batch_id
  FROM public.pdc_pilbara_service_import_batches
  WHERE source_hash='9803905a50abcacef851a823f5d7bb708e9890a0aa4c49273e91566ea4ebf69e'
  ORDER BY created_at DESC LIMIT 1;

  CREATE TEMP TABLE fuel_rule_matches ON COMMIT DROP AS
  SELECT o.*,
         cur.classification_id prior_classification_id,
         h.category prior_category,
         h.rule_id prior_rule_id,
         encode(extensions.digest(convert_to(o.operation_description,'UTF8'),'sha256'),'hex') source_description_hash
  FROM public.pdc_pilbara_service_operations o
  LEFT JOIN public.pdc_pilbara_service_classification_current cur USING(operation_id)
  LEFT JOIN public.pdc_pilbara_service_classification_history h USING(classification_id)
  WHERE regexp_replace(upper(o.operation_description),'[^A-Z0-9]+',' ','g') LIKE ANY(ARRAY[
    '%COMPLIMENTARY FULL TANK OF FUEL%',
    '%FULL TANK OF FUEL%',
    '%VEHICLE DELIVERY FUEL FILL%',
    '%DELIVER WITH BATTERY FULLY CHARGED%',
    '%100 BATTERY STATE OF CHARGE%',
    '%100 PERCENT BATTERY STATE OF CHARGE%'
  ]);

  SELECT count(*),count(*) FILTER(
    WHERE prior_category IS DISTINCT FROM 'FITTING'
       OR prior_rule_id IS DISTINCT FROM 'craig-delivery-fuel-charge-fitting'
  ) INTO v_match_count,v_update_count
  FROM fuel_rule_matches;

  SELECT count(*) INTO v_manual_conflict_count
  FROM (SELECT DISTINCT vehicle_id FROM fuel_rule_matches) m
  JOIN public.vehicle_work_items w ON w.vehicle_id=m.vehicle_id AND lower(w.work_key)='fitting'
  LEFT JOIN public.pdc_pilbara_service_classification_work_controls c
    ON c.work_item_id=w.id AND c.vehicle_id=m.vehicle_id AND c.category='FITTING'
  WHERE c.work_item_id IS NULL;

  IF v_match_count<>18 OR v_update_count<>18 OR v_manual_conflict_count<>0 THEN
    RAISE EXCEPTION 'PDC_PILBARA_FUEL_RULE_PREVIEW_CONFLICT:%:%:%',v_match_count,v_update_count,v_manual_conflict_count USING ERRCODE='55000';
  END IF;

  v_manifest:=jsonb_build_object(
    'contract','craig-approved-delivery-fuel-charge-fitting-v1',
    'rule_id','craig-delivery-fuel-charge-fitting',
    'ruleset_version','rules-v2',
    'destination','FITTING',
    'authority','Craig approved specialist classification',
    'hours_policy','preserve source and effective hours; no fallback',
    'matched_operations',(SELECT jsonb_agg(jsonb_build_object(
      'natural_identity',jsonb_build_array(importer_version,stock_number,repair_order_number,original_line_number),
      'source_description_hash',source_description_hash,
      'source_semantic_hash',semantic_hash
    ) ORDER BY stock_number,repair_order_number,original_line_number) FROM fuel_rule_matches)
  );
  v_manifest_hash:=encode(extensions.digest(convert_to(v_manifest::text,'UTF8'),'sha256'),'hex');
  v_state_before:=public.pdc_pilbara_service_classification_state_hash_v1();

  INSERT INTO public.pdc_pilbara_service_classification_batches(
    batch_id,contract,batch_kind,source_importer_version,source_batch_id,classifier_version,
    manifest_hash,idempotency_key,current_state_hash,manifest,response,created_actor
  ) VALUES(
    v_preview_batch_id,'pilbara_service_operation_classifier_v1','preview','pilbara_service_open_jobcards_v1',v_source_batch_id,
    'craig-approved-semantics-2026-09-08.1',v_manifest_hash,'craig-fuel-charge-fitting-preview-20260908',v_state_before,v_manifest,
    jsonb_build_object('ok',true,'code','preview_created','matched',v_match_count,'update',v_update_count,
      'manual_fitting_conflict_count',v_manual_conflict_count,'apply_allowed',true),
    'postgres:staging-management'
  );

  INSERT INTO public.pdc_pilbara_service_classification_batches(
    batch_id,contract,batch_kind,source_importer_version,source_batch_id,classifier_version,
    manifest_hash,idempotency_key,current_state_hash,manifest,response,preview_of_batch_id,created_actor
  ) VALUES(
    v_apply_batch_id,'pilbara_service_operation_classifier_v1','apply','pilbara_service_open_jobcards_v1',v_source_batch_id,
    'craig-approved-semantics-2026-09-08.1',v_manifest_hash,'craig-fuel-charge-fitting-apply-20260908',v_state_before,v_manifest,
    '{}'::jsonb,v_preview_batch_id,'postgres:staging-management'
  );

  FOR v_operation IN SELECT * FROM fuel_rule_matches ORDER BY stock_number,repair_order_number,original_line_number
  LOOP
    v_prior_id:=v_operation.prior_classification_id;
    SELECT coalesce(max(classification_version),0)+1 INTO v_next_version
    FROM public.pdc_pilbara_service_classification_history
    WHERE operation_id=v_operation.operation_id;

    INSERT INTO public.pdc_pilbara_service_classification_history(
      operation_id,batch_id,classification_version,category,method,confidence,rationale,
      rule_id,ruleset_version,provider,model,model_run_id,source_description_hash,
      source_semantic_hash,classifier_version,supersedes_classification_id
    ) VALUES(
      v_operation.operation_id,v_apply_batch_id,v_next_version,'FITTING','deterministic_rule',1.0,
      'Craig-approved delivery fuel or battery-charge preparation maps to Fitting.',
      'craig-delivery-fuel-charge-fitting','rules-v2',null,null,null,
      v_operation.source_description_hash,v_operation.semantic_hash,
      'craig-approved-semantics-2026-09-08.1',v_prior_id
    ) RETURNING classification_id INTO v_new_id;

    INSERT INTO public.pdc_pilbara_service_classification_current(operation_id,classification_id,updated_at)
    VALUES(v_operation.operation_id,v_new_id,clock_timestamp())
    ON CONFLICT(operation_id) DO UPDATE
      SET classification_id=excluded.classification_id,updated_at=excluded.updated_at;
    v_updated:=v_updated+1;
  END LOOP;

  v_work:=public.pdc_pilbara_service_reconcile_work_controls_v1(v_apply_batch_id);
  v_state_after:=public.pdc_pilbara_service_classification_state_hash_v1();

  UPDATE public.pdc_pilbara_service_classification_batches
  SET response=jsonb_build_object(
    'ok',true,'code','applied','matched',v_match_count,'updated',v_updated,
    'work_controls',v_work,'before_state_hash',v_state_before,'after_state_hash',v_state_after,
    'production_touched',false
  )
  WHERE batch_id=v_apply_batch_id;

  IF EXISTS(
    SELECT 1 FROM fuel_rule_matches m
    JOIN public.pdc_pilbara_service_classification_current cur USING(operation_id)
    JOIN public.pdc_pilbara_service_classification_history h USING(classification_id)
    WHERE h.category<>'FITTING' OR h.method<>'deterministic_rule'
       OR h.rule_id<>'craig-delivery-fuel-charge-fitting'
       OR h.source_description_hash<>m.source_description_hash
       OR h.source_semantic_hash<>m.semantic_hash
  ) OR EXISTS(
    SELECT 1 FROM fuel_rule_matches m
    JOIN public.pdc_pilbara_service_operations o USING(operation_id)
    WHERE o.source_estimated_hours IS DISTINCT FROM m.source_estimated_hours
       OR o.effective_estimated_hours IS DISTINCT FROM m.effective_estimated_hours
       OR o.hours_provenance IS DISTINCT FROM m.hours_provenance
       OR o.operation_description IS DISTINCT FROM m.operation_description
       OR o.semantic_hash IS DISTINCT FROM m.semantic_hash
  ) THEN
    RAISE EXCEPTION 'PDC_PILBARA_FUEL_RULE_POSTCONDITION_FAILED' USING ERRCODE='55000';
  END IF;

  INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
  VALUES('20260908100000','pilbara_delivery_fuel_charge_fitting_rule',ARRAY[]::text[]);
END
$migration$;

COMMIT;
