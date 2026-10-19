DO $guard$ BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR auth.uid() IS NOT NULL OR NOT pdc_codex_intake_private.management_connection()
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'staging_management_required'; END IF;
 IF md5(pg_get_functiondef('pdc_operation_updates_private.accept_change(uuid)'::regprocedure))<>'d061e520dcd23135bccbbb668ae3fc8e' THEN RAISE EXCEPTION 'accept_source_changed'; END IF;
END $guard$;
SET LOCAL lock_timeout='5s';
CREATE OR REPLACE FUNCTION pdc_operation_updates_private.accept_change(p_change_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE q public.pdc_tune_operation_change_reviews%rowtype; v public.vehicles%rowtype;
 a public.vehicle_workshop_line_adjustments%rowtype; evidence public.pdc_pilbara_service_import_rows%rowtype;
 actor uuid; choice jsonb; candidate jsonb; p jsonb; actual jsonb; new_line jsonb; schedule jsonb; reply jsonb;
 source_id uuid; key text; stage text; work text; h numeric; before_vehicle jsonb;
 original_claims text:=current_setting('request.jwt.claims',true);
 bound_actor boolean:=false; actor_email text;
 original_defer text:=current_setting('pdc.defer_workshop_adjustment_reconcile',true);
 original_required_defer text:=current_setting('pdc.defer_workshop_required_work_reconcile',true);
BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RETURN jsonb_build_object('ok',false,'code','wrong_environment'); END IF;
 -- Same lock order as the workshop clock. Do not hold up an upload behind it.
 IF NOT pg_try_advisory_xact_lock(hashtextextended('workshop-clock-cascade-20260911',0))
 THEN RETURN jsonb_build_object('ok',false,'code','operation_schedule_busy'); END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 PERFORM 1 FROM public.workshop_bookings WHERE deleted_at IS NULL
  AND status IN('queued','planned','started','stoppage') ORDER BY id FOR UPDATE NOWAIT;
 PERFORM 1 FROM public.workshop_admin_blocks WHERE deleted_at IS NULL ORDER BY id FOR SHARE NOWAIT;
 PERFORM 1 FROM public.workshop_booking_assignments WHERE released_at IS NULL ORDER BY id FOR UPDATE NOWAIT;
 SELECT * INTO q FROM public.pdc_tune_operation_change_reviews WHERE change_id=p_change_id FOR UPDATE NOWAIT;
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','operation_review_not_found'); END IF;
 IF q.status='approved' THEN RETURN q.approval_receipt||jsonb_build_object('replay',true); END IF;
 IF q.status<>'pending' THEN RETURN jsonb_build_object('ok',false,'code','review_not_pending'); END IF;
 SELECT * INTO v FROM public.vehicles WHERE id=q.vehicle_id FOR UPDATE NOWAIT;
 IF v.deleted_at IS NOT NULL OR v.visible_on_board IS NOT TRUE OR v.lifecycle_state::text<>'active'
  OR v.qc_completed_at IS NOT NULL OR upper(btrim(coalesce(v.current_location,''))) IN('QC','RFT','COLLECTED','COMPLETED','AT DEALER')
  OR NOT EXISTS(SELECT 1 FROM public.pdc_new_vehicle_reviews r WHERE r.vehicle_id=v.id AND r.status='approved' AND r.approved_at IS NOT NULL)
 THEN RETURN jsonb_build_object('ok',false,'code','vehicle_or_review_state_protected'); END IF;
 p:=q.proposed_source;
 IF p->>'department' NOT IN('138','139') OR q.company<>'01' OR q.division<>'1'
  OR v.stock_number IS DISTINCT FROM p->>'stock_number'
  OR q.repair_order_number IS DISTINCT FROM p->>'repair_order_number'
  OR q.original_line_number IS DISTINCT FROM (p->>'original_line_number')::integer
  OR (q.before_source->>'department' IS NOT NULL AND q.before_source->>'department' IS DISTINCT FROM p->>'department')
 THEN RETURN jsonb_build_object('ok',false,'code','operation_identity_needs_review'); END IF;
 SELECT * INTO evidence FROM public.pdc_pilbara_service_import_rows WHERE evidence_id=q.evidence_id;
 SELECT created_by INTO actor FROM public.pdc_pilbara_service_import_batches WHERE batch_id=q.batch_id AND batch_kind='apply';
 IF actor IS NULL OR evidence.normalized_payload IS DISTINCT FROM p
 THEN RETURN jsonb_build_object('ok',false,'code','source_evidence_mismatch'); END IF;
 candidate:=public.pdc_tune_operation_change_candidate_20260912(v.id,p||jsonb_build_object('raw_row',evidence.raw_row));
 IF candidate ? 'conflict' OR candidate->>'proposed_hash' IS DISTINCT FROM q.proposed_hash
  OR (candidate->>'source_operation_id')::uuid IS DISTINCT FROM q.source_operation_id
 THEN RETURN jsonb_build_object('ok',false,'code','operation_identity_changed'); END IF;
 choice:=pdc_operation_updates_private.proposal(q.change_id);
 IF choice->>'ok' IS DISTINCT FROM 'true' THEN RETURN choice; END IF;
 stage:=choice->>'stage_code';h:=(choice->>'estimated_hours')::numeric;
 SELECT work_key INTO work FROM public.workshop_stages WHERE code=stage AND active;
 IF work IS NULL AND stage<>'JOB_CARD_NOTES' THEN RETURN jsonb_build_object('ok',false,'code','station_needs_review'); END IF;
 IF EXISTS(SELECT 1 FROM public.vehicle_work_items WHERE vehicle_id=v.id AND work_key=work AND completed)
 THEN RETURN jsonb_build_object('ok',false,'code','completed_station_requires_rework_review'); END IF;
 source_id:=q.source_operation_id;key:='source:'||source_id;
 SELECT l INTO actual FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v.id)) l WHERE l->>'line_identity'=key;
 IF source_id IS NOT NULL AND (actual IS NULL OR actual->>'completed'='true' OR actual->>'rejected'='true' OR actual->>'active' IS DISTINCT FROM 'true')
 THEN RETURN jsonb_build_object('ok',false,'code','completed_or_removed_line_protected'); END IF;
 -- Background management imports retain the authenticated source batch actor.
 -- Do not invent a user or accept caller-supplied actor identities.
 IF auth.uid() IS NULL THEN
  IF NOT pdc_codex_intake_private.management_connection() THEN
   RETURN jsonb_build_object('ok',false,'code','authenticated_import_actor_required'); END IF;
  SELECT u.email INTO actor_email FROM auth.users u JOIN public.pdc_user_roles r
   ON r.auth_user_id=u.id AND lower(r.email)=lower(u.email)
   WHERE u.id=actor AND r.active AND r.account_status='approved' AND r.role::text IN('operator','administrator');
  IF actor_email IS NULL THEN RETURN jsonb_build_object('ok',false,'code','authenticated_import_actor_unavailable'); END IF;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor,'email',actor_email,'role','authenticated')::text,true);
  bound_actor:=true;
 END IF;
 before_vehicle:=to_jsonb(v)-ARRAY['version','updated_at','updated_by'];
 PERFORM set_config('pdc.defer_workshop_adjustment_reconcile','407',true);
 PERFORM set_config('pdc.defer_workshop_required_work_reconcile','407',true);
 IF source_id IS NULL THEN
  IF EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations WHERE vehicle_id=v.id AND repair_order_number=q.repair_order_number AND original_line_number=q.original_line_number)
  THEN RAISE EXCEPTION 'operation_identity_changed'; END IF;
  INSERT INTO public.pdc_pilbara_service_operations(department,operation_code,proposed_station,importer_version,stock_number,repair_order_number,original_line_number,source_order,vehicle_id,operation_description,
   source_estimated_hours,effective_estimated_hours,hours_provenance,parts_on_backorder_raw,parts_semantics,classification,semantic_hash,raw_evidence_id)
  VALUES(p->>'department',p->>'operation_code','REVIEW','pilbara_service_open_jobcards_v1',v.stock_number,q.repair_order_number,q.original_line_number,(p->>'source_order')::integer,v.id,p->>'operation_description',
   (p->>'source_estimated_hours')::numeric,(p->>'effective_estimated_hours')::numeric,p->>'hours_provenance',coalesce(p->>'parts_on_backorder_raw',''),'review','Review',p->>'semantic_hash',q.evidence_id)
  RETURNING operation_id INTO source_id;
  key:='source:'||source_id;
  INSERT INTO public.pdc_pilbara_service_operation_history(operation_id,batch_id,event_kind,prior_semantic_hash,resulting_semantic_hash,immutable_snapshot)
  VALUES(source_id,q.batch_id,'insert',NULL,p->>'semantic_hash',p);
 END IF;
 UPDATE public.pdc_tune_operation_change_reviews SET status='approved',source_operation_id=source_id,
  approved_at=clock_timestamp(),approved_by=actor WHERE change_id=q.change_id;
 IF stage<>'JOB_CARD_NOTES' THEN
 INSERT INTO public.vehicle_work_items(vehicle_id,work_key,required,completed,notes)
 VALUES(v.id,work,true,false,'Automatically accepted uploaded operation')
 ON CONFLICT(vehicle_id,work_key) DO UPDATE SET required=true,updated_at=clock_timestamp();
 END IF;
 SELECT * INTO a FROM public.vehicle_workshop_line_adjustments WHERE vehicle_id=v.id AND line_key=key FOR UPDATE;
 IF FOUND THEN
  UPDATE public.vehicle_workshop_line_adjustments SET stage_code=coalesce(choice->>'adjustment_stage_code',stage),estimated_hours=h,
   version=version+1,updated_by=actor,updated_at=clock_timestamp() WHERE adjustment_id=a.adjustment_id;
 ELSE
  INSERT INTO public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,active,version,manual_assignment_locked,created_by,updated_by,correction_origin)
  VALUES(v.id,key,'source',coalesce(choice->>'adjustment_stage_code',stage),btrim(left(btrim(regexp_replace(p->>'operation_description','[[:cntrl:]]',' ','g')),180)),h,true,1,(stage<>'JOB_CARD_NOTES' AND (q.source_operation_id IS NOT NULL OR p->>'department'<>'138')),actor,actor,CASE WHEN q.source_operation_id IS NULL AND p->>'department'='138' THEN 'job_card_source_correction' END);
 END IF;
 SELECT l INTO new_line FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v.id)) l WHERE l->>'line_identity'=key;
 IF new_line->>'stage_code' IS DISTINCT FROM stage OR (new_line->>'estimated_hours')::numeric IS DISTINCT FROM h
  OR new_line->>'description' IS DISTINCT FROM p->>'operation_description' OR new_line->>'completed' IS DISTINCT FROM 'false'
 THEN RAISE EXCEPTION 'operation_readback_mismatch'; END IF;
 IF stage='JOB_CARD_NOTES' THEN schedule:=jsonb_build_object('changed_count',0);
 ELSE schedule:=pdc_operation_updates_private.reconcile_bookings(v.id,ARRAY[stage,actual->>'stage_code'],q.change_id,actor); END IF;
 IF before_vehicle IS DISTINCT FROM (SELECT to_jsonb(x)-ARRAY['version','updated_at','updated_by'] FROM public.vehicles x WHERE id=v.id)
 THEN RAISE EXCEPTION 'protected_vehicle_state_changed'; END IF;
 reply:=jsonb_build_object('ok',true,'code','operation_change_auto_approved','data',jsonb_build_object(
  'change_id',q.change_id,'vehicle_id',v.id,'operation',new_line,'estimate',choice,'location_changed',false,
  'bookings_changed',(schedule->>'changed_count')::integer>0,'schedule',schedule));
 UPDATE public.pdc_tune_operation_change_reviews SET approval_key=q.change_id,
  approval_hash=q.proposed_hash,approval_receipt=reply,version=version+1 WHERE change_id=q.change_id;
 PERFORM public.audit_pdc_event('update','pdc_tune_operation_change_reviews',q.change_id,v.id,q.before_source,p,
  jsonb_build_object('action','auto_accept_uploaded_operation','source_evidence_id',q.evidence_id,'estimate',choice));
 DELETE FROM pdc_operation_updates_private.schedule_writes WHERE transaction_id=txid_current() AND change_id=q.change_id;
 UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;
 PERFORM public.workshop_bump_revision();
 PERFORM set_config('pdc.defer_workshop_adjustment_reconcile',coalesce(original_defer,''),true);
 PERFORM set_config('pdc.defer_workshop_required_work_reconcile',coalesce(original_required_defer,''),true);
 IF bound_actor THEN PERFORM set_config('request.jwt.claims',coalesce(original_claims,''),true); END IF;
 RETURN reply;
EXCEPTION WHEN OTHERS THEN
 IF bound_actor THEN PERFORM set_config('request.jwt.claims',coalesce(original_claims,''),true); END IF;
 -- Each failed change rolls back independently; immutable uploaded evidence stays.
 PERFORM set_config('pdc.defer_workshop_adjustment_reconcile',coalesce(original_defer,''),true);
 PERFORM set_config('pdc.defer_workshop_required_work_reconcile',coalesce(original_required_defer,''),true);
 RETURN jsonb_build_object('ok',false,'code',CASE WHEN SQLSTATE IN('40001','40P01','55P03') THEN 'operation_schedule_busy' ELSE 'operation_schedule_conflict' END,
  'detail',SQLERRM);
END $function$
;
