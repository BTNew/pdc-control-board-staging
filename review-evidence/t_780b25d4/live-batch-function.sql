CREATE OR REPLACE FUNCTION public.save_vehicle_workshop_line_hours_batch_768(p_vehicle_id uuid, p_stock_number text, p_job_card_number text, p_expected_vehicle_version bigint, p_estimated_rows jsonb, p_idempotency_key uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
  v_actor uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_scope jsonb;
  v_vehicle_dealer text;
  v_vehicle public.vehicles%rowtype;
  v_receipt public.vehicle_workshop_hours_batch_receipts_768%rowtype;
  v_rows jsonb:=coalesce(p_estimated_rows,'[]'::jsonb);
  v_canonical_rows jsonb;
  v_request jsonb;
  v_request_hash text;
  v_current_rows jsonb:='[]'::jsonb;
  v_conflicts jsonb:='[]'::jsonb;
  v_changes jsonb:='[]'::jsonb;
  v_revision bigint;
  v_vehicle_after public.vehicles%rowtype;
  v_changed_count integer:=0;
  v_receipt_id uuid:=gen_random_uuid();
BEGIN
  IF v_actor IS NULL OR v_email='' THEN
    RETURN jsonb_build_object('ok',false,'code','unauthorized');
  END IF;
  PERFORM public.require_pdc_role('operator');
  v_scope:=public.pdc_auditor_actor_scope();
  v_vehicle_dealer:=public.pdc_auditor_vehicle_dealer(p_vehicle_id);
  IF v_scope->>'environment' IS DISTINCT FROM 'staging'
     OR v_scope->>'dealer_code' IS DISTINCT FROM v_vehicle_dealer THEN
    RETURN jsonb_build_object('ok',false,'code','dealer_scope_denied');
  END IF;

  IF p_vehicle_id IS NULL OR p_idempotency_key IS NULL
    OR nullif(btrim(coalesce(p_stock_number,'')),'') IS NULL
    OR nullif(btrim(coalesce(p_job_card_number,'')),'') IS NULL
    OR p_expected_vehicle_version IS NULL OR p_expected_vehicle_version<1
    OR jsonb_typeof(v_rows)<>'array' OR jsonb_array_length(v_rows) NOT BETWEEN 1 AND 250
    OR EXISTS(
      SELECT 1 FROM jsonb_array_elements(v_rows) x
      WHERE jsonb_typeof(x)<>'object'
        OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(x) k)
           IS DISTINCT FROM ARRAY['adjustment_id','estimated_hours','expected_line_version','line_key','operation_line_id','stage_code','work_key']::text[]
        OR coalesce(x->>'operation_line_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        OR coalesce(x->>'line_key','')<>('source:'||lower(coalesce(x->>'operation_line_id','')))
        OR coalesce(x->>'work_key','')<>lower(btrim(coalesce(x->>'work_key','')))
        OR coalesce(x->>'work_key','') IN ('parts','pit_inspection','unallocated_mapping_review')
        OR coalesce(x->>'stage_code','')<>upper(btrim(coalesce(x->>'stage_code','')))
        OR coalesce(x->>'stage_code','') !~ '^[A-Z][A-Z0-9_]{1,39}$'
        OR coalesce(x->>'expected_line_version','') !~ '^[0-9]+$'
        OR jsonb_typeof(x->'adjustment_id') IS NULL
        OR (jsonb_typeof(x->'adjustment_id')='string' AND coalesce(x->>'adjustment_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
        OR jsonb_typeof(x->'adjustment_id') NOT IN ('string','null')
        OR jsonb_typeof(x->'estimated_hours') IS NULL
        OR jsonb_typeof(x->'estimated_hours') NOT IN ('number','null')
        OR (jsonb_typeof(x->'estimated_hours')='number' AND (
          coalesce(x->>'estimated_hours','') !~ '^(0|[0-9]+)(\.[0-9]{1,2})?$'
          OR (x->>'estimated_hours')::numeric<0 OR (x->>'estimated_hours')::numeric>999.99
        ))
    )
    OR (SELECT count(*) FROM jsonb_array_elements(v_rows))
      <>(SELECT count(DISTINCT lower(x->>'operation_line_id')) FROM jsonb_array_elements(v_rows) x)
  THEN RETURN jsonb_build_object('ok',false,'code','invalid_hours_batch'); END IF;

  SELECT coalesce(jsonb_agg(x ORDER BY lower(x->>'operation_line_id')),'[]'::jsonb)
    INTO v_canonical_rows FROM jsonb_array_elements(v_rows) x;
  v_request:=jsonb_build_object(
    'contract','vehicle_workshop_hours_batch_768.1','actor_id',v_actor,'vehicle_id',p_vehicle_id,
    'stock_number',btrim(p_stock_number),'job_card_number',btrim(p_job_card_number),
    'expected_vehicle_version',p_expected_vehicle_version,'estimated_rows',v_canonical_rows,
    'idempotency_key',p_idempotency_key);
  v_request_hash:=encode(extensions.digest(convert_to(v_request::text,'UTF8'),'sha256'),'hex');

  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-workshop-hours-batch:'||v_actor::text||':'||p_idempotency_key::text,0));
  SELECT * INTO v_receipt FROM public.vehicle_workshop_hours_batch_receipts_768
   WHERE actor_id=v_actor AND idempotency_key=p_idempotency_key FOR UPDATE;
  IF FOUND THEN
    IF v_receipt.request_hash<>v_request_hash THEN
      RETURN jsonb_build_object('ok',false,'code','idempotency_conflict','data',jsonb_build_object('receipt_id',v_receipt.receipt_id));
    END IF;
    RETURN jsonb_set(v_receipt.response,'{replay}','true'::jsonb,false);
  END IF;

  SELECT * INTO v_vehicle FROM public.vehicles
   WHERE id=p_vehicle_id AND lifecycle_state='active' AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_found'); END IF;
  IF btrim(coalesce(v_vehicle.stock_number::text,''))<>btrim(p_stock_number) THEN
    RETURN jsonb_build_object('ok',false,'code','vehicle_identity_conflict','data',jsonb_build_object('vehicle_id',p_vehicle_id));
  END IF;

  CREATE TEMP TABLE pdc_hours_batch_request_t780 ON COMMIT DROP AS
  SELECT lower(x->>'operation_line_id')::uuid operation_line_id,
    NULLIF(x->>'adjustment_id','')::uuid adjustment_id,
    (x->>'expected_line_version')::bigint expected_line_version,
    x->>'line_key' line_key,upper(x->>'stage_code') stage_code,lower(x->>'work_key') work_key,
    CASE WHEN jsonb_typeof(x->'estimated_hours')='null' THEN NULL ELSE (x->>'estimated_hours')::numeric END estimated_hours
  FROM jsonb_array_elements(v_rows) x;
  CREATE UNIQUE INDEX ON pdc_hours_batch_request_t780(operation_line_id);

  CREATE TEMP TABLE pdc_hours_batch_source_t780 ON COMMIT DROP AS
  SELECT ol.operation_line_id,ol.vehicle_id,'authenticated'::text source_contract,
    coalesce(nullif(btrim(ol.job_card_number),''),nullif(btrim(v_vehicle.job_card_number),'')) job_card_number,
    lower(ol.work_key) work_key,public.workshop_stage_code_for_work_key(ol.work_key) stage_code,
    ol.description,ol.estimated_hours source_estimated_hours,ol.estimated_hours effective_estimated_hours,
    ol.operation_no,ol.source_row_no display_order
  FROM public.pdc_authenticated_email_operation_lines ol
  JOIN pdc_hours_batch_request_t780 r ON r.operation_line_id=ol.operation_line_id
  WHERE ol.vehicle_id=p_vehicle_id
  UNION ALL
  SELECT o.operation_id,o.vehicle_id,'pilbara_service_open_jobcards_v1',o.repair_order_number,
    CASE coalesce(h.category,'REVIEW') WHEN 'BUS_4X4' THEN 'bus4x4' ELSE lower(coalesce(h.category,'REVIEW')) END,
    coalesce(h.category,'REVIEW'),o.operation_description,o.source_estimated_hours,o.effective_estimated_hours,
    'PD'||lpad(o.original_line_number::text,3,'0')||'-'||upper(substr(o.semantic_hash,1,8)),o.original_line_number
  FROM public.pdc_pilbara_service_operations o
  JOIN pdc_hours_batch_request_t780 r ON r.operation_line_id=o.operation_id
  LEFT JOIN public.pdc_pilbara_service_classification_current cc USING(operation_id)
  LEFT JOIN public.pdc_pilbara_service_classification_history h USING(classification_id)
  WHERE o.vehicle_id=p_vehicle_id;
  CREATE UNIQUE INDEX ON pdc_hours_batch_source_t780(operation_line_id);

  IF EXISTS(SELECT 1 FROM pdc_hours_batch_request_t780 WHERE work_key='parts' OR stage_code='PARTS') THEN
    RETURN jsonb_build_object('ok',false,'code','parts_not_hour_bearing','data',jsonb_build_object('vehicle_id',p_vehicle_id,'booking_created',false,'parts_mutated',false));
  END IF;

  PERFORM 1 FROM public.vehicle_workshop_line_adjustments a
   JOIN pdc_hours_batch_request_t780 r ON r.line_key=a.line_key
   WHERE a.vehicle_id=p_vehicle_id FOR UPDATE;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'operation_line_id',r.operation_line_id,'line_key',r.line_key,'work_key',r.work_key,'stage_code',r.stage_code,
    'source_contract',s.source_contract,'source_estimated_hours',s.source_estimated_hours,
    'adjustment_id',a.adjustment_id,'line_version',coalesce(a.version,0),
    'estimated_hours',CASE WHEN a.adjustment_id IS NOT NULL AND a.active THEN a.estimated_hours ELSE s.effective_estimated_hours END,
    'active',coalesce(a.active,true)
  ) ORDER BY r.operation_line_id),'[]'::jsonb) INTO v_current_rows
  FROM pdc_hours_batch_request_t780 r
  LEFT JOIN pdc_hours_batch_source_t780 s USING(operation_line_id)
  LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=p_vehicle_id AND a.line_key=r.line_key;

  IF v_vehicle.version<>p_expected_vehicle_version THEN
    RETURN jsonb_build_object('ok',false,'code','vehicle_version_conflict','data',jsonb_build_object(
      'vehicle_id',p_vehicle_id,'current_vehicle_version',v_vehicle.version,'base_vehicle_version',p_expected_vehicle_version,
      'current_rows',v_current_rows));
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'operation_line_id',r.operation_line_id,'requested_work_key',r.work_key,'requested_stage_code',r.stage_code,
    'requested_line_version',r.expected_line_version,'source_contract',s.source_contract,
    'current_work_key',s.work_key,'current_stage_code',s.stage_code,
    'current_adjustment_id',a.adjustment_id,'current_line_version',coalesce(a.version,0),
    'reason',CASE
      WHEN s.operation_line_id IS NULL THEN 'operation_line_not_found'
      WHEN coalesce(a.active,true)=false THEN 'operation_line_adjustment_inactive'
      WHEN s.job_card_number<>btrim(p_job_card_number) THEN 'job_card_identity_conflict'
      WHEN s.work_key<>r.work_key THEN 'work_key_conflict'
      WHEN s.stage_code<>r.stage_code THEN 'stage_identity_conflict'
      WHEN a.adjustment_id IS DISTINCT FROM r.adjustment_id THEN 'adjustment_identity_conflict'
      WHEN coalesce(a.version,0)<>r.expected_line_version THEN 'line_version_conflict'
      ELSE 'row_drift'
    END
  ) ORDER BY r.operation_line_id),'[]'::jsonb) INTO v_conflicts
  FROM pdc_hours_batch_request_t780 r
  LEFT JOIN pdc_hours_batch_source_t780 s USING(operation_line_id)
  LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=p_vehicle_id AND a.line_key=r.line_key
  WHERE s.operation_line_id IS NULL OR coalesce(a.active,true)=false
     OR s.job_card_number IS DISTINCT FROM btrim(p_job_card_number)
     OR s.work_key IS DISTINCT FROM r.work_key OR s.stage_code IS DISTINCT FROM r.stage_code
     OR a.adjustment_id IS DISTINCT FROM r.adjustment_id OR coalesce(a.version,0)<>r.expected_line_version;
  IF jsonb_array_length(v_conflicts)>0 THEN
    RETURN jsonb_build_object('ok',false,'code','line_version_conflict','data',jsonb_build_object(
      'vehicle_id',p_vehicle_id,'current_vehicle_version',v_vehicle.version,'base_vehicle_version',p_expected_vehicle_version,
      'conflicts',v_conflicts,'current_rows',v_current_rows));
  END IF;

  CREATE TEMP TABLE pdc_hours_batch_changes_t780 ON COMMIT DROP AS
  SELECT r.operation_line_id,r.adjustment_id current_adjustment_id,r.expected_line_version,
    r.line_key,r.stage_code,r.work_key,r.estimated_hours,s.source_contract,s.description source_description,
    s.source_estimated_hours,s.effective_estimated_hours source_effective_hours,s.operation_no,s.display_order,
    CASE WHEN a.adjustment_id IS NOT NULL THEN a.estimated_hours ELSE s.effective_estimated_hours END current_estimated_hours,
    coalesce(a.version,0) current_line_version
  FROM pdc_hours_batch_request_t780 r
  JOIN pdc_hours_batch_source_t780 s USING(operation_line_id)
  LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=p_vehicle_id AND a.line_key=r.line_key
  WHERE r.estimated_hours IS DISTINCT FROM CASE WHEN a.adjustment_id IS NOT NULL THEN a.estimated_hours ELSE s.effective_estimated_hours END;
  SELECT count(*) INTO v_changed_count FROM pdc_hours_batch_changes_t780;

  IF v_changed_count>0 THEN
    UPDATE public.vehicle_workshop_line_adjustments a SET
      stage_code=c.stage_code,
      description=c.source_description,
      estimated_hours=c.estimated_hours,
      correction_origin=CASE WHEN c.estimated_hours IS NULL THEN 'manual_operator_unknown' ELSE 'manual_operator' END,
      manual_assignment_locked=false,
      active=true,
      version=a.version+1,
      updated_by=v_actor,
      updated_at=clock_timestamp()
    FROM pdc_hours_batch_changes_t780 c
    WHERE a.adjustment_id=c.current_adjustment_id
      AND a.vehicle_id=p_vehicle_id;

    INSERT INTO public.vehicle_workshop_line_adjustments(
      vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,correction_origin,active,version,
      created_by,updated_by,source_operation_line_id,job_card_number,operation_code,display_order,manual_assignment_locked
    )
    SELECT p_vehicle_id,c.line_key,'source',c.stage_code,c.source_description,c.estimated_hours,
      CASE WHEN c.estimated_hours IS NULL THEN 'manual_operator_unknown' ELSE 'manual_operator' END,
      true,1,v_actor,v_actor,CASE WHEN c.source_contract='authenticated' THEN c.operation_line_id ELSE NULL END,
      p_job_card_number,c.operation_no,c.display_order,false
    FROM pdc_hours_batch_changes_t780 c WHERE c.current_adjustment_id IS NULL
    ON CONFLICT(vehicle_id,line_key) DO UPDATE SET
      stage_code=excluded.stage_code,description=excluded.description,estimated_hours=excluded.estimated_hours,
      correction_origin=excluded.correction_origin,manual_assignment_locked=false,
      active=true,version=public.vehicle_workshop_line_adjustments.version+1,updated_by=v_actor,updated_at=clock_timestamp();

    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'operation_line_id',c.operation_line_id,'line_key',c.line_key,'work_key',c.work_key,'source_contract',c.source_contract,
      'source_estimated_hours',c.source_estimated_hours,
      'before',jsonb_build_object('adjustment_id',c.current_adjustment_id,'estimated_hours',c.current_estimated_hours,'version',c.current_line_version),
      'after',jsonb_build_object('adjustment_id',a.adjustment_id,'estimated_hours',a.estimated_hours,'version',a.version,'correction_origin',a.correction_origin)
    ) ORDER BY c.operation_line_id),'[]'::jsonb) INTO v_changes
    FROM pdc_hours_batch_changes_t780 c
    JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=p_vehicle_id AND a.line_key=c.line_key;

    INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
    SELECT CASE WHEN c.current_adjustment_id IS NULL THEN 'insert'::public.audit_action ELSE 'update'::public.audit_action END,
      'vehicle_workshop_line_adjustments',a.adjustment_id,p_vehicle_id,v_actor,v_email,
      jsonb_build_object('adjustment_id',c.current_adjustment_id,'operation_line_id',c.operation_line_id,
        'source_contract',c.source_contract,'source_estimated_hours',c.source_estimated_hours,
        'effective_estimated_hours',c.current_estimated_hours,'version',c.current_line_version),
      jsonb_build_object('adjustment_id',a.adjustment_id,'operation_line_id',c.operation_line_id,
        'source_contract',c.source_contract,'source_estimated_hours',c.source_estimated_hours,
        'effective_estimated_hours',a.estimated_hours,'version',a.version,'correction_origin',a.correction_origin),
      jsonb_build_object('source','vehicle_workshop_hours_batch_768.1','request_id',p_idempotency_key,
        'request_hash',v_request_hash,'bookings_changed',false,'parts_changed',false,'completion_changed',false)
    FROM pdc_hours_batch_changes_t780 c
    JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=p_vehicle_id AND a.line_key=c.line_key;

    UPDATE public.vehicles SET version=version+1,updated_by=v_actor,updated_at=clock_timestamp()
    WHERE id=p_vehicle_id RETURNING * INTO v_vehicle_after;
  ELSE
    v_vehicle_after:=v_vehicle;
  END IF;

  SELECT revision INTO v_revision FROM public.pdc_email_vehicle_revision WHERE singleton;
  v_receipt.response:=jsonb_build_object('ok',true,'code',CASE WHEN v_changed_count>0 THEN 'workshop_hours_batch_saved' ELSE 'workshop_hours_batch_no_changes' END,
    'replay',false,'receipt_id',v_receipt_id,'request_sha256',v_request_hash,'vehicle_id',p_vehicle_id,
    'vehicle_version_before',v_vehicle.version,'vehicle_version_after',v_vehicle_after.version,
    'revision',v_revision,'changed_count',v_changed_count,'changes',v_changes,
    'booking_created',false,'parts_mutated',false,'completion_changed',false);
  INSERT INTO public.vehicle_workshop_hours_batch_receipts_768(
    receipt_id,idempotency_key,actor_id,vehicle_id,request_hash,base_vehicle_version,response)
  VALUES(v_receipt_id,p_idempotency_key,v_actor,p_vehicle_id,v_request_hash,v_vehicle.version,v_receipt.response)
  RETURNING * INTO v_receipt;
  RETURN v_receipt.response;
END $function$
