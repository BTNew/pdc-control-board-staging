-- STAGING ONLY: QC rejection -> scoped rework -> fresh inspection.
-- No customer row is updated by this migration. Existing receipts/history remain immutable.
DO $guard$ BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR current_setting('app.environment',true)='production' THEN
  RAISE EXCEPTION 'STAGING required';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:qc-rework:20260909',0));
END $guard$;

CREATE OR REPLACE FUNCTION public.pdc_qc_rework_scope_20260909(p_vehicle_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO pg_catalog,public
AS $scope$
DECLARE
 v public.vehicles%rowtype; r public.pdc_qc_vehicle_rejection_receipts_767%rowtype;
 inspection_key uuid; inspection_at timestamptz; lines jsonb; stages jsonb; issues text[];
 matching_stop boolean; repaired boolean;
BEGIN
 SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id AND deleted_at IS NULL;
 IF NOT FOUND THEN RETURN jsonb_build_object('active',false); END IF;
 SELECT * INTO r FROM public.pdc_qc_vehicle_rejection_receipts_767
 WHERE vehicle_id=v.id ORDER BY created_at DESC,receipt_id DESC LIMIT 1;
 IF NOT FOUND THEN RETURN jsonb_build_object('active',false,'vehicle_id',v.id,'inspection_key',null); END IF;
 SELECT m.id,m.moved_at INTO inspection_key,inspection_at FROM public.vehicle_movements m
 WHERE m.vehicle_id=v.id AND upper(m.to_location)='QC' AND m.moved_at>r.created_at
 ORDER BY m.moved_at DESC,m.id DESC LIMIT 1;
 IF inspection_key IS NOT NULL OR v.lifecycle_state<>'active' OR upper(v.current_location)<>'PMB' THEN
  RETURN jsonb_build_object('active',false,'vehicle_id',v.id,'inspection_key',inspection_key,'inspection_started_at',inspection_at);
 END IF;
 -- New rejections freeze exact line IDs. Older receipts use the existing unchecked
 -- canonical checklist, never free-text matching or invented source operations.
 SELECT coalesce(jsonb_agg(l ORDER BY l->>'stage_code',l->>'operation_no',l->>'line_identity'),'[]'::jsonb)
 INTO lines FROM jsonb_array_elements(public.pdc_qc_checkable_operation_lines_10700(v.id)) l
 WHERE coalesce((l->>'active')::boolean,false)
 AND (CASE WHEN jsonb_typeof(r.after_state->'qc_rework_lines')='array' THEN
       EXISTS(SELECT 1 FROM jsonb_array_elements(r.after_state->'qc_rework_lines') old_line WHERE old_line->>'line_identity'=l->>'line_identity')
      ELSE NOT coalesce((l->>'completed')::boolean,false) OR coalesce((l->>'rejected')::boolean,false) END);
 SELECT coalesce(jsonb_agg(jsonb_build_object('stage_code',s.stage_code,'line_count',s.line_count,
   'estimated_hours',s.hours,'repair_completed',
   EXISTS(SELECT 1 FROM public.vehicle_work_items w
     WHERE w.vehicle_id=v.id AND public.workshop_stage_code_for_work_key(w.work_key)=s.stage_code
       AND w.required AND w.completed AND w.completed_by IS NOT NULL
       AND (w.completed_at>=r.created_at OR EXISTS(
        SELECT 1 FROM public.workshop_bookings b JOIN public.workshop_stages bs ON bs.id=b.stage_id
        WHERE b.vehicle_id=v.id AND bs.code=s.stage_code AND b.created_at>=r.created_at
          AND b.status='completed' AND b.deleted_at IS NULL AND b.actual_end_at IS NOT NULL
          AND b.updated_at>=r.created_at)))
    AND NOT EXISTS(SELECT 1 FROM public.workshop_bookings b JOIN public.workshop_stages bs ON bs.id=b.stage_id
      WHERE b.vehicle_id=v.id AND bs.code=s.stage_code AND b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage'))
   ) ORDER BY s.stage_code),'[]'::jsonb)
 INTO stages FROM (
  SELECT l->>'stage_code' stage_code,count(*) line_count,
   CASE WHEN bool_or(l->>'estimated_hours' IS NULL) THEN NULL ELSE round(sum((l->>'estimated_hours')::numeric),2) END hours
  FROM jsonb_array_elements(lines) l GROUP BY l->>'stage_code'
 ) s;
 matching_stop:=v.pmb_stoppage_started_at IS NOT NULL
  AND v.pmb_stoppage_started_at=(r.after_state->>'pmb_stoppage_started_at')::timestamptz
  AND v.pmb_stoppage_reason=r.reason AND v.pmb_stoppage_cleared_at IS NULL;
 issues:=coalesce(public.pdc_qc_gate_issues(v.id),ARRAY[]::text[]);
 IF jsonb_array_length(lines)=0 THEN issues:=array_append(issues,'qc_rework_scope_required'); END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(stages) s WHERE s->>'stage_code'='UNALLOCATED_MAPPING_REVIEW' OR s->>'estimated_hours' IS NULL)
  THEN issues:=array_append(issues,'qc_rework_estimate_or_mapping_required'); END IF;
 IF v.pmb_stoppage_started_at IS NOT NULL AND NOT coalesce(matching_stop,false)
  THEN issues:=array_append(issues,'unrelated_pmb_stoppage'); END IF;
 IF coalesce((SELECT p.parts_stoppage FROM public.vehicle_parts_updates p WHERE p.vehicle_id=v.id ORDER BY p.updated_at DESC,p.id DESC LIMIT 1),false)
  THEN issues:=array_append(issues,'parts_stoppage'); END IF;
 repaired:=jsonb_array_length(stages)>0 AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(stages) s WHERE NOT coalesce((s->>'repair_completed')::boolean,false));
 RETURN jsonb_build_object('contract','pdc-qc-rework-v1','active',true,'vehicle_id',v.id,'vehicle_version',v.version,
  'rejection_receipt_id',r.receipt_id,'rejected_at',r.created_at,'reason',r.reason,'inspection_key',null,
  'lines',lines,'stages',stages,'repairs_complete',repaired,'qc_stoppage_matches',coalesce(matching_stop,false),
  'ready_for_qc',repaired AND cardinality(issues)=0,'issues',to_jsonb(issues));
END $scope$;
REVOKE ALL ON FUNCTION public.pdc_qc_rework_scope_20260909(uuid) FROM PUBLIC,anon,authenticated;

DO $repair$
DECLARE d text; p text; source_sql text; c record;
BEGIN
 SELECT pg_get_functiondef('public.workshop_vehicle_stage_estimated_hours(uuid,text)'::regprocedure),prosrc
 INTO d,source_sql FROM pg_proc WHERE oid='public.workshop_vehicle_stage_estimated_hours(uuid,text)'::regprocedure;
 IF md5(d)<>'35955e34f413de02854fbe6a144bf0bc' THEN RAISE EXCEPTION 'Stage-hours source changed since review'; END IF;
 p:=regexp_replace(d,'AS \$function\$[\s\S]*\$function\$',
  'AS $function$ WITH rework AS (SELECT public.pdc_qc_rework_scope_20260909(p_vehicle_id) body), normal AS ('||source_sql||') SELECT CASE WHEN (rework.body->>''active'')::boolean THEN (SELECT (s->>''estimated_hours'')::numeric FROM jsonb_array_elements(rework.body->''stages'') s WHERE s->>''stage_code''=public.workshop_canonical_stage_code(p_stage_code)) ELSE (SELECT * FROM normal) END FROM rework $function$');
 IF p=d THEN RAISE EXCEPTION 'Stage-hours patch failed'; END IF; EXECUTE p;

 SELECT pg_get_functiondef('public.workshop_vehicle_stage_estimated_duration_minutes(uuid,uuid)'::regprocedure) INTO d;
 IF md5(d)<>'bf1a80fa34124380fd2549b3020c85b1' THEN RAISE EXCEPTION 'Duration source changed'; END IF;
 p:=replace(d,'WHEN h.hours IS NULL THEN NULL ELSE greatest(60,round(h.hours*60)::integer) END',
  'WHEN h.hours IS NULL THEN NULL WHEN (public.pdc_qc_rework_scope_20260909(p_vehicle_id)->>''active'')::boolean THEN greatest(1,round(h.hours*60)::integer) ELSE greatest(60,round(h.hours*60)::integer) END');
 IF p=d THEN RAISE EXCEPTION 'Duration patch failed'; END IF; EXECUTE p;

 SELECT pg_get_functiondef('public.reject_pdc_qc_vehicle_to_pmb_stoppage_767(uuid,text,integer,text,uuid)'::regprocedure) INTO d;
 IF md5(d)<>'1ee071798dafe561afb64d723a255891' THEN RAISE EXCEPTION 'QC rejection source changed'; END IF;
 p:=replace(d,'  UPDATE public.vehicles SET', $capture$
  v_before:=v_before||jsonb_build_object('qc_rework_lines',coalesce((
    SELECT jsonb_agg(l) FROM jsonb_array_elements(public.pdc_qc_checkable_operation_lines_10700(v_vehicle.id)) l
    WHERE coalesce((l->>'active')::boolean,false)
      AND (NOT coalesce((l->>'completed')::boolean,false) OR coalesce((l->>'rejected')::boolean,false))),'[]'::jsonb));
  UPDATE public.vehicle_work_items w SET completed=false,completed_at=null,completed_by=null,updated_at=clock_timestamp()
  WHERE w.vehicle_id=v_vehicle.id AND w.required AND EXISTS(
    SELECT 1 FROM jsonb_array_elements(v_before->'qc_rework_lines') l
    WHERE l->>'stage_code'=public.workshop_stage_code_for_work_key(w.work_key));
  UPDATE public.vehicles SET$capture$);
 p:=replace(p,'  v_receipt_id:=extensions.uuid_generate_v5(',
  E'  v_after:=v_after||jsonb_build_object(''qc_rework_lines'',v_before->''qc_rework_lines'');\n  v_receipt_id:=extensions.uuid_generate_v5(');
 IF p=d OR position('qc_rework_lines' IN p)=0 THEN RAISE EXCEPTION 'Rejection scope patch failed'; END IF; EXECUTE p;

 SELECT pg_get_functiondef('public.mark_vehicle_ready_for_qc(uuid,integer)'::regprocedure) INTO d;
 IF md5(d)<>'82f7ac9c08c470f967e3902023fe302d' THEN RAISE EXCEPTION 'QC entry source changed'; END IF;
 p:=replace(d,'  v_bay_stage text;',E'  v_bay_stage text;\n  rework jsonb; prior_completion public.pdc_qc_operation_completions_379%rowtype; reset_completion public.pdc_qc_operation_completions_379%rowtype;');
 p:=replace(p,'  v_issues:=public.pdc_qc_gate_issues(p_vehicle_id);',$gate$
  rework:=public.pdc_qc_rework_scope_20260909(p_vehicle_id);
  IF coalesce((rework->>'active')::boolean,false) AND NOT coalesce((rework->>'ready_for_qc')::boolean,false) THEN
    RETURN jsonb_build_object('ok',false,'error','qc_rework_not_completed','issues',rework->'issues','rework',rework);
  END IF;
  IF v_before.pmb_stoppage_started_at IS NOT NULL AND NOT coalesce((rework->>'qc_stoppage_matches')::boolean,false) THEN
    RETURN jsonb_build_object('ok',false,'error','qc_gate_blocked','issues',jsonb_build_array('active_pmb_stoppage'));
  END IF;
  v_issues:=public.pdc_qc_gate_issues(p_vehicle_id);$gate$);
 p:=replace(p,E'  UPDATE public.vehicles\n  SET current_location=', $reset$
  IF coalesce((rework->>'active')::boolean,false) THEN
    -- A workshop repair is NOT a QC sign-off. Preserve every prior check in
    -- append-only history and require the inspector to recheck all active items.
    FOR prior_completion IN SELECT q.* FROM public.pdc_qc_operation_completions_379 q
      WHERE q.vehicle_id=p_vehicle_id AND q.completed FOR UPDATE LOOP
      UPDATE public.pdc_qc_operation_completions_379 SET completed=false,completed_at=null,completed_by=null,
        version=version+1,updated_at=clock_timestamp()
      WHERE vehicle_id=p_vehicle_id AND line_identity=prior_completion.line_identity RETURNING * INTO reset_completion;
      INSERT INTO public.pdc_qc_operation_completion_history_379(history_id,vehicle_id,line_identity,actor_id,before_state,after_state,reason)
      VALUES(gen_random_uuid(),p_vehicle_id,prior_completion.line_identity,auth.uid(),to_jsonb(prior_completion),to_jsonb(reset_completion),
        'Fresh QC reinspection after repaired rejection '||(rework->>'rejection_receipt_id'));
    END LOOP;
  END IF;
  UPDATE public.vehicles
  SET current_location=$reset$);
 p:=replace(p,'      version=version+1,updated_by=auth.uid(),updated_at=clock_timestamp()',
  $clear$      pmb_stoppage_started_at=CASE WHEN coalesce((rework->>'qc_stoppage_matches')::boolean,false) THEN null ELSE pmb_stoppage_started_at END,
      pmb_stoppage_reason=CASE WHEN coalesce((rework->>'qc_stoppage_matches')::boolean,false) THEN null ELSE pmb_stoppage_reason END,
      pmb_stoppage_cleared_at=CASE WHEN coalesce((rework->>'qc_stoppage_matches')::boolean,false) THEN clock_timestamp() ELSE pmb_stoppage_cleared_at END,
      pmb_stoppage_cleared_by=CASE WHEN coalesce((rework->>'qc_stoppage_matches')::boolean,false) THEN auth.uid() ELSE pmb_stoppage_cleared_by END,
      workshop_status='queued',qc_completed_at=null,qc_completed_by=null,
      version=version+1,updated_by=auth.uid(),updated_at=clock_timestamp()$clear$);
 p:=replace(p,'''action'',''mark_vehicle_ready_for_qc'',''from''', '''qc_rework'',rework,''action'',''mark_vehicle_ready_for_qc'',''from''');
 IF p=d OR position('Fresh QC reinspection' IN p)=0 THEN RAISE EXCEPTION 'QC return patch failed'; END IF; EXECUTE p;

 SELECT pg_get_functiondef('public.get_pdc_email_vehicle_location_snapshot()'::regprocedure) INTO d;
 IF md5(d)<>'05a6a6611401bfaaecb64081b6659caa' THEN RAISE EXCEPTION 'Vehicle snapshot changed'; END IF;
 p:=replace(d,'''pilbara_service_operations'',service_lines,',
  '''qc_rework'',public.pdc_qc_rework_scope_20260909((row_value->>''id'')::uuid),''pilbara_service_operations'',service_lines,');
 IF p=d THEN RAISE EXCEPTION 'Snapshot patch failed'; END IF; EXECUTE p;

 SELECT pg_get_functiondef('public.workshop_overlay_authoritative_candidate_hours_175(jsonb)'::regprocedure) INTO d;
 IF md5(d)<>'884b8d255e088f35bb705ae0f9d1cb13' THEN RAISE EXCEPTION 'Candidate hours changed'; END IF;
 p:=replace(d,'  RETURN jsonb_set(p_snapshot,''{outstanding_candidates}'',v_candidates,false);',
  $candidate$  RETURN jsonb_set(jsonb_set(p_snapshot,'{outstanding_candidates}',v_candidates,false),'{vehicles}',
    coalesce((SELECT jsonb_agg(x||jsonb_build_object('qc_rework',public.pdc_qc_rework_scope_20260909((x->>'id')::uuid)))
      FROM jsonb_array_elements(coalesce(p_snapshot->'vehicles','[]'::jsonb)) x),'[]'::jsonb),false);$candidate$);
 IF p=d THEN RAISE EXCEPTION 'Candidate projection failed'; END IF; EXECUTE p;
END $repair$;

-- Keep old photos immutable. Each repaired QC attempt can store a new photo,
-- while a unique attempt key and advisory lock prevent duplicate uploads.
ALTER TABLE public.pdc_qc_finalization_photo_evidence_399 ADD COLUMN qc_inspection_key uuid;
ALTER TABLE public.pdc_qc_finalization_photo_evidence_399 DROP CONSTRAINT pdc_qc_finalization_photo_evidence_399_vehicle_id_key;
ALTER TABLE public.pdc_qc_finalization_photo_evidence_399 ADD CONSTRAINT pdc_qc_photo_one_per_inspection UNIQUE NULLS NOT DISTINCT(vehicle_id,qc_inspection_key);
DO $photos$
DECLARE d text; p text; fn text; expected text;
BEGIN
 SELECT pg_get_functiondef('public.record_pdc_qc_photo_evidence_399(uuid,integer,text,text,text,integer,integer,integer,integer,text,text,uuid)'::regprocedure) INTO d;
 IF md5(d)<>'cb3f02dfb82e44c0c7f675e108b711ff' THEN RAISE EXCEPTION 'Photo registration changed'; END IF;
 p:=replace(d,'  v_actor uuid:=auth.uid();','  inspection_key uuid; v_actor uuid:=auth.uid();');
 p:=replace(p,'  v_request:=jsonb_build_object(',E'  inspection_key:=(public.pdc_qc_rework_scope_20260909(p_vehicle_id)->>''inspection_key'')::uuid;\n  v_request:=jsonb_build_object(');
 p:=replace(p,'  SELECT * INTO v_vehicle FROM public.vehicles',E'  PERFORM pg_advisory_xact_lock(hashtextextended(''pdc:qc-photo-vehicle:''||p_vehicle_id::text,0));\n  SELECT * INTO v_vehicle FROM public.vehicles');
 p:=replace(p,'WHERE vehicle_id=p_vehicle_id;', 'WHERE vehicle_id=p_vehicle_id AND qc_inspection_key IS NOT DISTINCT FROM inspection_key;');
 p:=replace(p,'''vehicle_id'',p_vehicle_id,''vehicle_version'',v_vehicle.version', '''qc_inspection_key'',inspection_key,''vehicle_id'',p_vehicle_id,''vehicle_version'',v_vehicle.version');
 p:=replace(p,'request_sha256,response)', 'request_sha256,response,qc_inspection_key)');
 p:=replace(p,'p_idempotency_key,v_sha,v_response);', 'p_idempotency_key,v_sha,v_response,inspection_key);');
 IF p=d OR position('v_response,inspection_key' IN p)=0 THEN RAISE EXCEPTION 'Photo attempt patch failed'; END IF; EXECUTE p;
 FOR fn,expected IN SELECT * FROM (VALUES
  ('finalize_pdc_qc_to_rft_700','cc0aaf43d50f78ee3f693a189a326ce2'),
  ('finalize_pdc_qc_to_rft_399','a1b4909363f9e221462e5bdbee47cb4f')) t LOOP
  SELECT pg_get_functiondef((format('public.%I(uuid,integer,uuid,uuid)',fn))::regprocedure) INTO d;
  IF md5(d)<>expected THEN RAISE EXCEPTION 'QC finalizer changed: %',fn; END IF;
  p:=replace(d,'IF NOT FOUND OR '||CASE WHEN fn LIKE '%700' THEN 'photo' ELSE 'v_photo' END||'.bucket_id',
    'IF NOT FOUND OR '||CASE WHEN fn LIKE '%700' THEN 'photo' ELSE 'v_photo' END||'.qc_inspection_key IS DISTINCT FROM (public.pdc_qc_rework_scope_20260909(p_vehicle_id)->>''inspection_key'')::uuid OR '||CASE WHEN fn LIKE '%700' THEN 'photo' ELSE 'v_photo' END||'.bucket_id');
  IF p=d THEN RAISE EXCEPTION 'QC photo finalization patch failed'; END IF; EXECUTE p;
 END LOOP;
END $photos$;
