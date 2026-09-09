-- STAGING ONLY. Extend the existing station-move RPC to resolve Review lines.
-- Original source evidence, hours, QC checks, photos and bookings are not recreated.
DO $guard$
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR current_setting('app.environment',true)='production' THEN RAISE EXCEPTION 'STAGING required'; END IF;
 IF md5(pg_get_functiondef('public.move_vehicle_workshop_source_line_stage(uuid,uuid,bigint,text,text)'::regprocedure))<>'15dd5e4ff707eaa0cc0bed14a58dfd79' THEN RAISE EXCEPTION 'Station move changed since review'; END IF;
 IF md5(pg_get_functiondef('public.get_pdc_email_vehicle_location_snapshot()'::regprocedure))<>'41cd93583b28fd98ba8590242f465403' THEN RAISE EXCEPTION 'Snapshot changed since review'; END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.move_vehicle_workshop_source_line_stage(
 p_vehicle_id uuid,p_adjustment_id uuid,p_expected_version bigint,p_line_key text,p_stage_code text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog,public SET lock_timeout TO '5s' SET statement_timeout TO '60s'
AS $function$
DECLARE
 actor uuid:=auth.uid(); v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
 key text:=lower(btrim(coalesce(p_line_key,''))); stage text:=upper(btrim(coalesce(p_stage_code,'')));
 v public.vehicles%rowtype; prior public.vehicle_workshop_line_adjustments%rowtype;
 saved public.vehicle_workshop_line_adjustments%rowtype; line jsonb; verified jsonb;
 source_id uuid; source_count integer; target_work_key text; resolving_review boolean;
 prior_defer text:=current_setting('pdc.defer_workshop_required_work_reconcile',true);
BEGIN
 PERFORM public.workshop_require_planner_operator();
 IF auth.role() IS DISTINCT FROM 'authenticated' OR actor IS NULL OR NOT EXISTS(
   SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=actor AND lower(btrim(r.email))=v_email
     AND r.active AND r.account_status='approved' AND r.role IN('operator','administrator') FOR SHARE
 ) THEN RAISE EXCEPTION 'unauthorized' USING errcode='42501'; END IF;
 IF p_vehicle_id IS NULL OR p_expected_version IS NULL OR p_expected_version<0
   OR key !~ '^source:[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
   OR stage NOT IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET')
 THEN RAISE EXCEPTION 'invalid_workshop_station_move' USING errcode='22023'; END IF;
 SELECT s.work_key INTO target_work_key FROM public.workshop_stages s WHERE s.code=stage AND s.active;
 IF NOT FOUND THEN RAISE EXCEPTION 'workshop_stage_not_editable' USING errcode='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
 IF NOT FOUND OR v.deleted_at IS NOT NULL OR v.lifecycle_state<>'active' OR v.qc_completed_at IS NOT NULL
   OR upper(btrim(coalesce(v.current_location,''))) IN('RFT','COLLECTED','COMPLETED')
 THEN RAISE EXCEPTION 'vehicle_not_active_for_station_move' USING errcode='22023'; END IF;
 source_id:=substring(key FROM 8)::uuid;
 SELECT count(*) INTO source_count FROM (
   SELECT e.operation_line_id FROM public.pdc_authenticated_email_operation_lines e WHERE e.vehicle_id=v.id AND e.operation_line_id=source_id
   UNION ALL
   SELECT o.operation_id FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=v.id AND o.operation_id=source_id AND o.stock_number=v.stock_number
 ) sources;
 IF source_count<>1 THEN RAISE EXCEPTION 'workshop_source_line_not_found_or_ambiguous' USING errcode='22023'; END IF;
 IF (SELECT count(*) FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v.id)) l WHERE l->>'line_identity'=key)<>1
 THEN RAISE EXCEPTION 'workshop_source_line_not_found_or_ambiguous' USING errcode='22023'; END IF;
 SELECT l INTO line FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v.id)) l WHERE l->>'line_identity'=key;
 IF line->>'source_kind'<>'authenticated' OR (line->>'active')::boolean IS NOT TRUE
 THEN RAISE EXCEPTION 'workshop_line_deleted' USING errcode='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('vehicle-workshop-line:'||v.id::text||':'||key,0));
 SELECT * INTO prior FROM public.vehicle_workshop_line_adjustments a WHERE a.vehicle_id=v.id AND a.line_key=key FOR UPDATE;
 IF p_adjustment_id IS NULL THEN
   IF FOUND OR p_expected_version<>0 THEN RAISE EXCEPTION 'stale_line_version' USING errcode='40001'; END IF;
 ELSE
   IF NOT FOUND OR prior.adjustment_id<>p_adjustment_id OR prior.source_kind<>'source' OR NOT prior.active
   THEN RAISE EXCEPTION 'workshop_line_identity_mismatch' USING errcode='22023'; END IF;
   IF prior.version<>p_expected_version THEN RAISE EXCEPTION 'stale_line_version' USING errcode='40001'; END IF;
 END IF;
 resolving_review:=line->>'stage_code'='UNALLOCATED_MAPPING_REVIEW';
 IF coalesce((line->>'completed')::boolean,false) THEN RAISE EXCEPTION 'completed_operation_station_protected' USING errcode='22023'; END IF;
 IF NOT resolving_review THEN
   IF NOT EXISTS(SELECT 1 FROM public.vehicle_work_items w WHERE w.vehicle_id=v.id AND w.required AND NOT w.completed AND public.workshop_stage_code_for_work_key(w.work_key)=line->>'stage_code')
   THEN RAISE EXCEPTION 'workshop_source_stage_completed_or_unavailable' USING errcode='22023'; END IF;
   IF NOT EXISTS(SELECT 1 FROM public.vehicle_work_items w WHERE w.vehicle_id=v.id AND w.required AND NOT w.completed AND public.workshop_stage_code_for_work_key(w.work_key)=stage)
   THEN RAISE EXCEPTION 'workshop_stage_not_editable' USING errcode='22023'; END IF;
 END IF;
 IF p_adjustment_id IS NULL AND (length(line->>'description') NOT BETWEEN 1 AND 180 OR (line->>'description')~'[[:cntrl:]]')
 THEN RAISE EXCEPTION 'source_description_requires_review' USING errcode='22023'; END IF;
 IF resolving_review THEN
   -- Only reconcile this newly assigned requirement, not unrelated imported work.
   PERFORM set_config('pdc.defer_workshop_required_work_reconcile','407',true);
   INSERT INTO public.vehicle_work_items(vehicle_id,work_key,required,completed,notes)
   VALUES(v.id,target_work_key,true,false,'Manually assigned Review operation')
   ON CONFLICT(vehicle_id,work_key) DO UPDATE SET required=true,updated_at=clock_timestamp();
 END IF;
 IF p_adjustment_id IS NULL THEN
   INSERT INTO public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,active,version,manual_assignment_locked,created_by,updated_by)
   VALUES(v.id,key,'source',stage,line->>'description',(line->>'estimated_hours')::numeric,true,1,true,actor,actor) RETURNING * INTO saved;
 ELSE
   UPDATE public.vehicle_workshop_line_adjustments SET stage_code=stage,manual_assignment_locked=true,version=version+1,updated_by=actor,updated_at=clock_timestamp()
   WHERE adjustment_id=prior.adjustment_id RETURNING * INTO saved;
 END IF;
 IF resolving_review THEN
   PERFORM set_config('pdc.defer_workshop_required_work_reconcile',coalesce(prior_defer,''),true);
   IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v.id)) l WHERE (l->>'active')::boolean AND l->>'stage_code'='UNALLOCATED_MAPPING_REVIEW') THEN
     UPDATE public.vehicle_work_items SET required=false,updated_at=clock_timestamp()
     WHERE vehicle_id=v.id AND required AND NOT completed AND lower(work_key) IN('review','owner_supplied_document','unallocated_mapping_review');
   END IF;
 END IF;
 UPDATE public.vehicles SET version=version+1,updated_by=actor,updated_at=clock_timestamp() WHERE id=v.id RETURNING * INTO v;
 SELECT l INTO verified FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v.id)) l WHERE l->>'line_identity'=key;
 IF verified->>'stage_code' IS DISTINCT FROM stage OR verified->'estimated_hours' IS DISTINCT FROM line->'estimated_hours'
   OR verified->'completed' IS DISTINCT FROM line->'completed' OR verified->'description' IS DISTINCT FROM line->'description'
 THEN RAISE EXCEPTION 'station_move_readback_failed' USING errcode='55000'; END IF;
 INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
 VALUES(CASE WHEN p_adjustment_id IS NULL THEN 'insert'::public.audit_action ELSE 'update'::public.audit_action END,
   'vehicle_workshop_line_adjustments',saved.adjustment_id,v.id,actor,v_email,
   CASE WHEN p_adjustment_id IS NULL THEN NULL ELSE to_jsonb(prior) END,to_jsonb(saved),
   jsonb_build_object('source','vehicle_detail_workshop_station_move_150','line_key',key,'review_resolved',resolving_review,
     'previous_effective_stage_code',line->>'stage_code','target_stage_code',stage,'source_operation_line_id',source_id,
     'hours_changed',false,'completion_changed',false,'location_changed',false,'manual_assignment_locked',true));
 RETURN jsonb_build_object('ok',true,'code','workshop_source_line_station_moved','data',jsonb_build_object(
   'adjustment_id',saved.adjustment_id,'line_key',saved.line_key,'stage_code',saved.stage_code,
   'description',saved.description,'estimated_hours',saved.estimated_hours,'version',saved.version,
   'vehicle_id',v.id,'vehicle_version_after',v.version,'review_resolved',resolving_review,'qc_line',verified));
END $function$;

-- Give every screen the effective manually assigned station, retaining the
-- original work key separately as source evidence. Source hours are unchanged.
DO $snapshot$
DECLARE d text; patched text;
BEGIN
 SELECT pg_get_functiondef('public.get_pdc_email_vehicle_location_snapshot()'::regprocedure) INTO d;
 patched:=replace(d,
 $old$'operation_lines',coalesce(row_value->'operation_lines','[]'::jsonb)||service_lines$old$,
 $new$'operation_lines',(SELECT coalesce(jsonb_agg(
   CASE WHEN a.adjustment_id IS NOT NULL THEN op||jsonb_build_object(
     'source_work_key',coalesce(op->'source_work_key',op->'work_key'),
     'work_key',CASE a.stage_code WHEN 'BUS_4X4' THEN 'bus4x4' ELSE lower(a.stage_code) END,
     'classification',a.stage_code,'station_assignment_source','manual_operator') ELSE op END ORDER BY ordinal),'[]'::jsonb)
   FROM jsonb_array_elements(coalesce(row_value->'operation_lines','[]'::jsonb)||service_lines) WITH ORDINALITY x(op,ordinal)
   LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=(row_value->>'id')::uuid
     AND a.line_key='source:'||(op->>'operation_line_id') AND a.active AND a.manual_assignment_locked
     AND a.stage_code IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET'))$new$);
 IF patched=d THEN RAISE EXCEPTION 'Snapshot station overlay patch mismatch'; END IF;
 EXECUTE patched;
END $snapshot$;