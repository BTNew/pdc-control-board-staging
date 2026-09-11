-- STAGING only: atomic review hours + stations, with existing actor/replay gates.
DO $$ BEGIN IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'wrong_environment'; END IF; END $$;
CREATE OR REPLACE FUNCTION public.pdc_review_positive_hours_20260911(p_line jsonb,p_assignment jsonb)
RETURNS numeric LANGUAGE sql STABLE
SET search_path TO 'pg_catalog','public'
AS $hours$
 WITH value AS (
   SELECT CASE WHEN p_assignment ? 'estimated_hours' THEN p_assignment->'estimated_hours'
     ELSE p_line->'estimated_hours' END j
 ), parsed AS (
   SELECT CASE WHEN jsonb_typeof(j)='number' THEN (j#>>'{}')::numeric ELSE NULL END h FROM value
 )
 SELECT CASE WHEN h>0 AND h<=999.99 AND h=round(h,2)
   AND (NOT public.pdc_is_pre_delivery_20260910(p_line->>'description') OR h=1)
   THEN h ELSE NULL END FROM parsed
$hours$;
REVOKE ALL ON FUNCTION public.pdc_review_positive_hours_20260911(jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.approve_pdc_new_vehicle_review(p_vehicle_id uuid, p_snapshot_hash text, p_assignments jsonb, p_idempotency_key uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
 SET lock_timeout TO '5s'
 SET statement_timeout TO '60s'
AS $function$
DECLARE actor uuid:=auth.uid(); v_actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
 r public.pdc_new_vehicle_reviews%rowtype; v public.vehicles%rowtype; a public.vehicle_workshop_line_adjustments%rowtype;
 before_row jsonb; after_row jsonb; line jsonb; assignment jsonb; result jsonb; response jsonb; request_hash text;
BEGIN
 IF auth.role() IS DISTINCT FROM 'authenticated' OR actor IS NULL OR NOT EXISTS(
  SELECT 1 FROM public.pdc_user_roles x WHERE x.auth_user_id=actor AND lower(btrim(x.email))=v_actor_email
   AND x.active AND x.account_status='approved' AND x.role IN('operator','administrator') FOR SHARE)
 THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
 IF p_vehicle_id IS NULL OR p_snapshot_hash IS NULL OR p_snapshot_hash!~'^[a-f0-9]{64}$'
  OR p_idempotency_key IS NULL OR jsonb_typeof(p_assignments) IS DISTINCT FROM 'array'
 THEN RETURN jsonb_build_object('ok',false,'code','invalid_approval'); END IF;
 request_hash:=encode(extensions.digest(convert_to(jsonb_build_object('vehicle_id',p_vehicle_id,
  'snapshot_hash',p_snapshot_hash,'assignments',p_assignments)::text,'UTF8'),'sha256'),'hex');
 LOCK TABLE public.pdc_pilbara_service_operations IN SHARE MODE;
 LOCK TABLE public.pdc_pilbara_service_classification_current IN SHARE MODE;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
 SELECT * INTO r FROM public.pdc_new_vehicle_reviews WHERE vehicle_id=p_vehicle_id FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','review_not_found'); END IF;
 IF r.status='approved' THEN
  IF r.approved_by=actor AND r.approval_key=p_idempotency_key AND r.approval_hash=request_hash
   THEN RETURN r.approval_receipt||jsonb_build_object('replay',true); END IF;
  RETURN jsonb_build_object('ok',false,'code','already_approved');
 END IF;
 IF r.status<>'pending' OR v.deleted_at IS NOT NULL OR v.lifecycle_state::text<>'active'
  OR v.qc_completed_at IS NOT NULL OR upper(coalesce(v.current_location,'')) IN('QC','RFT','COLLECTED','COMPLETED')
 THEN RETURN jsonb_build_object('ok',false,'code','review_not_pending'); END IF;
 IF v.source_system='microsoft_navision' AND NOT EXISTS(SELECT 1 FROM public.navision_backend_records n WHERE n.canonical_vehicle_id=v.id AND n.is_current AND n.record_status='current' AND btrim(coalesce(n.normalized_data->>'batch',n.normalized_data->>'stock',''))=btrim(v.stock_number))
 THEN RETURN jsonb_build_object('ok',false,'code','backend_identity_changed'); END IF;
 IF EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.vehicle_id=v.id AND b.deleted_at IS NULL)
 THEN RETURN jsonb_build_object('ok',false,'code','existing_workshop_history_requires_review'); END IF;
 before_row:=public.pdc_new_vehicle_review_row(v.id);
 IF before_row->>'details_source'='identity_review' THEN RETURN jsonb_build_object('ok',false,'code','backend_identity_changed'); END IF;
 IF before_row->>'snapshot_hash' IS DISTINCT FROM p_snapshot_hash
 THEN RETURN jsonb_build_object('ok',false,'code','review_changed'); END IF;
 IF jsonb_array_length(before_row->'operations')=0
  OR jsonb_array_length(p_assignments)<>jsonb_array_length(before_row->'operations')
  OR (SELECT count(DISTINCT x->>'line_identity') FROM jsonb_array_elements(p_assignments) x)<>jsonb_array_length(p_assignments)
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_assignments) x WHERE
    jsonb_typeof(x) IS DISTINCT FROM 'object'
    OR coalesce(x->>'stage_code','') NOT IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET')
    OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(before_row->'operations') l WHERE l->>'line_identity'=x->>'line_identity'))
 THEN RETURN jsonb_build_object('ok',false,'code','all_operations_need_stations'); END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(before_row->'operations') l
  JOIN jsonb_array_elements(p_assignments) x ON x->>'line_identity'=l->>'line_identity'
  WHERE public.pdc_review_positive_hours_20260911(l,x) IS NULL
    OR (l->>'completed')::boolean IS TRUE OR (l->>'active')::boolean IS DISTINCT FROM true
    OR l->>'source_kind'<>'authenticated')
 THEN RETURN jsonb_build_object('ok',false,'code','operation_hours_or_state_need_review'); END IF;
 FOR line IN SELECT l FROM jsonb_array_elements(before_row->'operations') l LOOP
  SELECT x INTO assignment FROM jsonb_array_elements(p_assignments) x WHERE x->>'line_identity'=line->>'line_identity';
  SELECT * INTO a FROM public.vehicle_workshop_line_adjustments WHERE vehicle_id=v.id AND line_key=line->>'line_identity';
  result:=public.move_vehicle_workshop_source_line_stage(v.id,a.adjustment_id,coalesce(a.version,0),line->>'line_identity',assignment->>'stage_code');
  IF result->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'station_assignment_failed' USING errcode='PDI01'; END IF;
  IF (line->>'estimated_hours')::numeric IS DISTINCT FROM public.pdc_review_positive_hours_20260911(line,assignment) THEN
    SELECT * INTO STRICT a FROM public.vehicle_workshop_line_adjustments WHERE vehicle_id=v.id AND line_key=line->>'line_identity' FOR UPDATE;
    result:=public.upsert_vehicle_workshop_line_adjustment(v.id,a.adjustment_id,a.version,a.line_key,a.stage_code,
      a.description,public.pdc_review_positive_hours_20260911(line,assignment));
    IF result->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'approved_hours_save_failed' USING errcode='PDI01'; END IF;
  END IF;
 END LOOP;
 after_row:=public.pdc_new_vehicle_review_row(v.id);
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(before_row->'operations') oldline
  WHERE NOT EXISTS(SELECT 1 FROM jsonb_array_elements(after_row->'operations') newl
   JOIN jsonb_array_elements(p_assignments) chosen ON chosen->>'line_identity'=newl->>'line_identity'
   WHERE newl->>'line_identity'=oldline->>'line_identity' AND newl->>'stage_code'=chosen->>'stage_code'
    AND newl->'description'=oldline->'description' AND newl->'estimated_hours'=to_jsonb(public.pdc_review_positive_hours_20260911(oldline,chosen))
    AND newl->'source_line_id'=oldline->'source_line_id' AND newl->'completed'=oldline->'completed'))
 THEN RAISE EXCEPTION 'approval_readback_mismatch' USING errcode='PDI01'; END IF;
 UPDATE public.vehicle_work_items w SET required=false,updated_at=clock_timestamp()
 WHERE w.vehicle_id=v.id AND w.required AND NOT w.completed
  AND w.notes IN('Pilbara Service classifier managed control','Manually assigned Review operation')
  AND public.workshop_stage_code_for_work_key(w.work_key) IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET')
  AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(after_row->'operations') l WHERE l->>'stage_code'=public.workshop_stage_code_for_work_key(w.work_key));
 UPDATE public.pdc_new_vehicle_reviews SET status='approved',approved_at=clock_timestamp(),approved_by=actor,
  approval_key=p_idempotency_key,approval_hash=request_hash WHERE vehicle_id=v.id;
 UPDATE public.vehicles SET visible_on_board=true,version=version+1,updated_by=actor,updated_at=clock_timestamp()
 WHERE id=v.id RETURNING * INTO v;
 after_row:=public.pdc_new_vehicle_review_row(v.id);
 response:=jsonb_build_object('ok',true,'code','new_vehicle_approved','replay',false,'data',jsonb_build_object(
  'vehicle_id',v.id,'stock_number',v.stock_number,'vehicle_version',v.version,'visible_on_board',v.visible_on_board,
  'current_location',v.current_location,'operations',after_row->'operations','bookings_created',0,'qc_completed',false));
 UPDATE public.pdc_new_vehicle_reviews SET approval_receipt=response WHERE vehicle_id=v.id;
 PERFORM public.audit_pdc_event('update','pdc_new_vehicle_reviews',v.id,v.id,before_row,after_row,
  jsonb_build_object('action','approve_new_vehicle_review','idempotency_key',p_idempotency_key,'request_hash',request_hash,
    'physical_location_changed',false,'bookings_created',0,'source_hours_changed',false));
 UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;
 UPDATE public.navision_backend_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;
 RETURN response;
EXCEPTION WHEN SQLSTATE 'PDI01' THEN RETURN jsonb_build_object('ok',false,'code',SQLERRM);
END $function$
;
