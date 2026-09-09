-- STAGING ONLY: select multiple QC defects and reject them atomically.
-- The five-argument API remains compatible. No customer records are changed here.
DO $migration$
DECLARE d text; p text; original_filter text;
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR current_setting('app.environment',true)='production' THEN RAISE EXCEPTION 'STAGING required'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:qc-selected-rejection:20260909',0));
 SELECT pg_get_functiondef('public.reject_pdc_qc_vehicle_to_pmb_stoppage_767(uuid,text,integer,text,uuid)'::regprocedure) INTO d;
 IF md5(d)<>'654e36ee339525a76991eb0540139362' THEN RAISE EXCEPTION 'QC rejection definition changed since review'; END IF;
 p:=replace(d,'p_idempotency_key uuid)', 'p_idempotency_key uuid, p_rejected_lines jsonb)');
 p:=replace(p,'  v_actor uuid:=auth.uid();', E'  selected_completion record; saved_completion public.pdc_qc_operation_completions_379%rowtype;\n  v_actor uuid:=auth.uid();');
 p:=replace(p,'  v_request:=jsonb_build_object(', $validate$
  IF p_rejected_lines IS NOT NULL THEN
    IF jsonb_typeof(p_rejected_lines) IS DISTINCT FROM 'array' OR jsonb_array_length(p_rejected_lines) NOT BETWEEN 1 AND 500 THEN
      RAISE EXCEPTION 'PDC_QC_REJECTION_SELECTION_REQUIRED' USING errcode='22023';
    END IF;
    IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_rejected_lines) x
      WHERE jsonb_typeof(x) IS DISTINCT FROM 'object'
        OR coalesce(x->>'line_identity','')!~'^(source|manual):[0-9a-f-]{36}$'
        OR coalesce(x->>'line_version','')!~'^[0-9]{1,10}$')
      OR (SELECT count(DISTINCT x->>'line_identity') FROM jsonb_array_elements(p_rejected_lines) x)<>jsonb_array_length(p_rejected_lines) THEN
      RAISE EXCEPTION 'PDC_QC_REJECTION_SELECTION_INVALID' USING errcode='22023';
    END IF;
  END IF;
  v_request:=jsonb_build_object($validate$);
 p:=replace(p, '  v_sha:=encode(', $request$
  IF p_rejected_lines IS NOT NULL THEN
    v_request:=v_request||jsonb_build_object('rejected_lines',p_rejected_lines);
  END IF;
  v_sha:=encode($request$);
 p:=replace(p,'  v_before:=jsonb_build_object(', $binding$
  IF p_rejected_lines IS NOT NULL AND (
    SELECT count(*) FROM jsonb_array_elements(p_rejected_lines) selected
    JOIN jsonb_array_elements(public.pdc_qc_checkable_operation_lines_10700(v_vehicle.id)) l
      ON l->>'line_identity'=selected->>'line_identity'
      AND (l->>'active')::boolean IS TRUE
      AND (l->>'line_version')::bigint=(selected->>'line_version')::bigint
  )<>jsonb_array_length(p_rejected_lines) THEN
    RAISE EXCEPTION 'PDC_QC_REJECTION_LINE_VERSION_CONFLICT' USING errcode='40001';
  END IF;
  v_before:=jsonb_build_object($binding$);
 original_filter:=$old$SELECT jsonb_agg(l) FROM jsonb_array_elements(public.pdc_qc_checkable_operation_lines_10700(v_vehicle.id)) l
    WHERE coalesce((l->>'active')::boolean,false)
      AND (NOT coalesce((l->>'completed')::boolean,false) OR coalesce((l->>'rejected')::boolean,false))$old$;
 p:=replace(p,original_filter,$selected$SELECT jsonb_agg(CASE WHEN p_rejected_lines IS NOT NULL THEN l||jsonb_build_object('completed',false) ELSE l END)
    FROM jsonb_array_elements(public.pdc_qc_checkable_operation_lines_10700(v_vehicle.id)) l
    WHERE coalesce((l->>'active')::boolean,false)
      AND CASE WHEN p_rejected_lines IS NULL THEN
        (NOT coalesce((l->>'completed')::boolean,false) OR coalesce((l->>'rejected')::boolean,false))
      ELSE EXISTS(SELECT 1 FROM jsonb_array_elements(p_rejected_lines) x WHERE x->>'line_identity'=l->>'line_identity') END$selected$);
 p:=replace(p,'  UPDATE public.vehicle_work_items w SET completed=false', $uncheck$
  -- An inspector may reject an item previously ticked in this attempt. Clear
  -- only the selected ticks, preserving their before/after audit history.
  IF p_rejected_lines IS NOT NULL THEN
    FOR selected_completion IN SELECT c.* FROM public.pdc_qc_operation_completions_379 c
      WHERE c.vehicle_id=v_vehicle.id AND c.completed AND EXISTS(
        SELECT 1 FROM jsonb_array_elements(p_rejected_lines) x WHERE x->>'line_identity'=c.line_identity)
      FOR UPDATE
    LOOP
      UPDATE public.pdc_qc_operation_completions_379 SET completed=false,completed_at=null,completed_by=null,
        version=version+1,updated_at=clock_timestamp()
      WHERE vehicle_id=v_vehicle.id AND line_identity=selected_completion.line_identity RETURNING * INTO saved_completion;
      INSERT INTO public.pdc_qc_operation_completion_history_379(history_id,vehicle_id,line_identity,actor_id,before_state,after_state,reason)
      VALUES(gen_random_uuid(),v_vehicle.id,selected_completion.line_identity,v_actor,to_jsonb(selected_completion),to_jsonb(saved_completion),
        'Inspector explicitly rejected selected QC item: '||v_reason);
    END LOOP;
  END IF;
  UPDATE public.vehicle_work_items w SET completed=false$uncheck$);
 p:=replace(p, '  INSERT INTO public.pdc_qc_vehicle_rejection_receipts_767(', $receipt$
  v_response:=v_response||jsonb_build_object('rejected_lines',v_before->'qc_rework_lines','rejected_count',jsonb_array_length(v_before->'qc_rework_lines'));
  INSERT INTO public.pdc_qc_vehicle_rejection_receipts_767($receipt$);
 IF p=d OR position('PDC_QC_REJECTION_LINE_VERSION_CONFLICT' IN p)=0 OR position('ELSE EXISTS(SELECT 1 FROM jsonb_array_elements(p_rejected_lines)' IN p)=0 THEN RAISE EXCEPTION 'QC selection patch mismatch'; END IF;
 EXECUTE p;
END $migration$;
REVOKE ALL ON FUNCTION public.reject_pdc_qc_vehicle_to_pmb_stoppage_767(uuid,text,integer,text,uuid,jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.reject_pdc_qc_vehicle_to_pmb_stoppage_767(uuid,text,integer,text,uuid,jsonb) TO authenticated;
CREATE OR REPLACE FUNCTION public.reject_pdc_qc_vehicle_to_pmb_stoppage_767(p_vehicle_id uuid,p_stock_number text,p_expected_vehicle_version integer,p_reason text,p_idempotency_key uuid)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO pg_catalog,public
AS $compat$ SELECT public.reject_pdc_qc_vehicle_to_pmb_stoppage_767(p_vehicle_id,p_stock_number,p_expected_vehicle_version,p_reason,p_idempotency_key,NULL::jsonb) $compat$;