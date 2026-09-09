-- STAGING ONLY. New report vehicles wait for human station review.
-- Existing board/Job Card vehicles are grandfathered; no physical state is changed.
DO $guard$ BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE
    OR current_setting('app.environment',true)='production' THEN RAISE EXCEPTION 'STAGING required'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:new-vehicle-review:release',0));
END $guard$;
CREATE TABLE public.pdc_new_vehicle_reviews (
 vehicle_id uuid PRIMARY KEY REFERENCES public.vehicles(id) ON DELETE RESTRICT,
 status text NOT NULL CHECK(status IN('existing','pending','approved')),
 source_kind text NOT NULL DEFAULT 'revolution_report', first_job_card text,
 received_at timestamptz NOT NULL DEFAULT clock_timestamp(), approved_at timestamptz,
 approved_by uuid REFERENCES auth.users(id), approval_key uuid, approval_hash text, approval_receipt jsonb,
 CHECK ((status='approved')=(approved_at IS NOT NULL)), UNIQUE(approved_by,approval_key)
);
ALTER TABLE public.pdc_new_vehicle_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_new_vehicle_reviews FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_new_vehicle_reviews FROM PUBLIC,anon,authenticated;
INSERT INTO public.pdc_new_vehicle_reviews(vehicle_id,status,source_kind)
SELECT v.id,'existing','pre_existing_vehicle' FROM public.vehicles v
WHERE v.visible_on_board OR v.lifecycle_state::text IN('rft','completed')
 OR EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=v.id)
 OR EXISTS(SELECT 1 FROM public.pdc_authenticated_email_operation_lines o WHERE o.vehicle_id=v.id)
 OR EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.vehicle_id=v.id);
CREATE FUNCTION public.pdc_new_vehicle_review_row(p_vehicle_id uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='pg_catalog','public','extensions' AS $fn$
 SELECT jsonb_build_object('vehicle_id',v.id,'vehicle_version',v.version,'stock_number',v.stock_number,
  'customer_name',v.customer_name,'vehicle_description',v.vehicle_description,'vin',v.vin,
  'current_location',v.current_location,'eta_to_kewdale',v.eta_to_kewdale,'status',r.status,
  'received_at',r.received_at,'source_kind',r.source_kind,
  'job_cards',coalesce((SELECT jsonb_agg(DISTINCT l->>'job_card_number') FROM jsonb_array_elements(q.lines) l
      WHERE nullif(btrim(l->>'job_card_number'),'') IS NOT NULL),'[]'::jsonb),
  'operations',q.lines,
  'snapshot_hash',encode(extensions.digest(convert_to(jsonb_build_object(
      'id',v.id,'version',v.version,'status',r.status,'lines',q.lines)::text,'UTF8'),'sha256'),'hex'))
 FROM public.pdc_new_vehicle_reviews r JOIN public.vehicles v ON v.id=r.vehicle_id
 CROSS JOIN LATERAL (SELECT coalesce(jsonb_agg(l ORDER BY l->>'line_identity'),'[]'::jsonb) lines
  FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v.id)) l WHERE (l->>'active')::boolean IS TRUE) q
 WHERE r.vehicle_id=p_vehicle_id AND v.deleted_at IS NULL;
$fn$;
REVOKE ALL ON FUNCTION public.pdc_new_vehicle_review_row(uuid) FROM PUBLIC,anon,authenticated;
CREATE FUNCTION public.pdc_queue_new_report_vehicle() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='pg_catalog','public' AS $fn$
DECLARE v public.vehicles%rowtype; existing_status text;
BEGIN
 IF NEW.vehicle_id IS NULL OR nullif(btrim(NEW.repair_order_number),'') IS NULL THEN RETURN NEW; END IF;
 SELECT * INTO v FROM public.vehicles WHERE id=NEW.vehicle_id FOR UPDATE;
 IF NOT FOUND OR v.deleted_at IS NOT NULL OR v.lifecycle_state::text<>'active' THEN RETURN NEW; END IF;
 IF btrim(v.stock_number) IS DISTINCT FROM btrim(NEW.stock_number) THEN
  RAISE EXCEPTION 'new_vehicle_intake_stock_identity_mismatch' USING errcode='22023'; END IF;
 INSERT INTO public.pdc_new_vehicle_reviews(vehicle_id,status,first_job_card)
 VALUES(v.id,'pending',NEW.repair_order_number) ON CONFLICT(vehicle_id) DO NOTHING;
 SELECT status INTO existing_status FROM public.pdc_new_vehicle_reviews WHERE vehicle_id=v.id;
 IF existing_status='pending' AND v.visible_on_board THEN
  UPDATE public.vehicles SET visible_on_board=false,version=version+1,updated_at=clock_timestamp() WHERE id=v.id;
 END IF;
 UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;
 UPDATE public.navision_backend_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;
 RETURN NEW;
END $fn$;
REVOKE ALL ON FUNCTION public.pdc_queue_new_report_vehicle() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER pdc_new_report_vehicle_review AFTER INSERT ON public.pdc_pilbara_service_operations
 FOR EACH ROW EXECUTE FUNCTION public.pdc_queue_new_report_vehicle();
CREATE FUNCTION public.pdc_pending_intake_visibility_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='pg_catalog','public' AS $fn$
BEGIN
 IF NEW.visible_on_board AND EXISTS(SELECT 1 FROM public.pdc_new_vehicle_reviews r WHERE r.vehicle_id=NEW.id AND r.status='pending')
 THEN NEW.visible_on_board:=false; END IF;
 RETURN NEW;
END $fn$;
REVOKE ALL ON FUNCTION public.pdc_pending_intake_visibility_guard() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER pdc_pending_intake_visibility BEFORE INSERT OR UPDATE OF visible_on_board ON public.vehicles
 FOR EACH ROW EXECUTE FUNCTION public.pdc_pending_intake_visibility_guard();
CREATE FUNCTION public.list_pdc_new_vehicle_reviews(p_offset integer DEFAULT 0,p_limit integer DEFAULT 50) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='pg_catalog','public' AS $fn$
DECLARE rows jsonb; total integer;
BEGIN
 IF auth.role() IS DISTINCT FROM 'authenticated' OR auth.uid() IS NULL OR NOT EXISTS(
  SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=auth.uid()
  AND lower(btrim(r.email))=lower(btrim(coalesce(auth.jwt()->>'email','')))
  AND r.active AND r.account_status='approved' AND r.role IN('viewer','operator','importer','administrator'))
 THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
 IF p_offset IS NULL OR p_offset<0 OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100
 THEN RETURN jsonb_build_object('ok',false,'code','invalid_page'); END IF;
 SELECT count(*) INTO total FROM public.pdc_new_vehicle_reviews r JOIN public.vehicles v ON v.id=r.vehicle_id
 WHERE r.status='pending' AND v.deleted_at IS NULL AND v.lifecycle_state::text='active';
 SELECT coalesce(jsonb_agg(public.pdc_new_vehicle_review_row(x.vehicle_id) ORDER BY x.received_at DESC,x.vehicle_id),'[]') INTO rows
 FROM (SELECT r.vehicle_id,r.received_at FROM public.pdc_new_vehicle_reviews r JOIN public.vehicles v ON v.id=r.vehicle_id
  WHERE r.status='pending' AND v.deleted_at IS NULL AND v.lifecycle_state::text='active'
  ORDER BY r.received_at DESC,r.vehicle_id LIMIT p_limit OFFSET p_offset) x;
 RETURN jsonb_build_object('ok',true,'code','new_vehicle_reviews','data',jsonb_build_object(
  'items',rows,'total',total,'offset',p_offset,'has_more',p_offset+jsonb_array_length(rows)<total));
END $fn$;
REVOKE ALL ON FUNCTION public.list_pdc_new_vehicle_reviews(integer,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.list_pdc_new_vehicle_reviews(integer,integer) TO authenticated;
DO $patch$
DECLARE d text; p text;
BEGIN
 SELECT pg_get_functiondef('public.move_vehicle_workshop_source_line_stage(uuid,uuid,bigint,text,text)'::regprocedure) INTO d;
 IF md5(d)<>'07e8c89f7378e17cc70641a31411ce89' THEN RAISE EXCEPTION 'station move changed; reconcile'; END IF;
 p:=replace(d,'resolving_review:=line->>''stage_code''=''UNALLOCATED_MAPPING_REVIEW'';',
 'resolving_review:=line->>''stage_code''=''UNALLOCATED_MAPPING_REVIEW'' OR EXISTS(SELECT 1 FROM public.pdc_new_vehicle_reviews r WHERE r.vehicle_id=v.id AND r.status=''pending'');');
 IF p=d THEN RAISE EXCEPTION 'station move patch mismatch'; END IF; EXECUTE p;
 SELECT pg_get_functiondef('public.get_navision_visible_snapshot_pre_82000(text,text,uuid,integer,bigint)'::regprocedure) INTO d;
 IF md5(d)<>'119b02d42625ba4018f7558d0ede2f90' THEN RAISE EXCEPTION 'Navision display changed; reconcile'; END IF;
 p:=replace(d,'''board_activated'',activation_source is not null and activation_active',
 '''board_activated'',NOT EXISTS(SELECT 1 FROM public.pdc_new_vehicle_reviews nr WHERE nr.vehicle_id=coalesce(activation_vehicle_id,canonical_vehicle_id) AND nr.status=''pending'') and activation_source is not null and activation_active');
 IF p=d THEN RAISE EXCEPTION 'Navision display patch mismatch'; END IF; EXECUTE p;
 SELECT pg_get_functiondef('public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)'::regprocedure) INTO d;
 p:=replace(d,'if not found then return jsonb_build_object(''ok'',false,''error'',''vehicle_inactive_or_missing''); end if;',
 'if not found then return jsonb_build_object(''ok'',false,''error'',''vehicle_inactive_or_missing''); end if;
  if exists(select 1 from public.pdc_new_vehicle_reviews r where r.vehicle_id=p_vehicle_id and r.status=''pending'') then return jsonb_build_object(''ok'',false,''error'',''new_vehicle_review_required''); end if;');
 IF p=d THEN RAISE EXCEPTION 'Workshop intake gate patch mismatch'; END IF; EXECUTE p;
 SELECT pg_get_functiondef('public.mark_vehicle_ready_for_qc(uuid,integer)'::regprocedure) INTO d;
 p:=replace(d,'IF p_expected_version IS NULL THEN',
 'IF EXISTS(SELECT 1 FROM public.pdc_new_vehicle_reviews r WHERE r.vehicle_id=p_vehicle_id AND r.status=''pending'') THEN RETURN jsonb_build_object(''ok'',false,''error'',''new_vehicle_review_required''); END IF;
  IF p_expected_version IS NULL THEN');
 IF p=d THEN RAISE EXCEPTION 'QC intake gate patch mismatch'; END IF; EXECUTE p;
END $patch$;
CREATE FUNCTION public.approve_pdc_new_vehicle_review(p_vehicle_id uuid,p_snapshot_hash text,p_assignments jsonb,p_idempotency_key uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='pg_catalog','public','extensions'
 SET lock_timeout='5s' SET statement_timeout='60s' AS $fn$
DECLARE actor uuid:=auth.uid(); email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
 r public.pdc_new_vehicle_reviews%rowtype; v public.vehicles%rowtype; a public.vehicle_workshop_line_adjustments%rowtype;
 before_row jsonb; after_row jsonb; line jsonb; assignment jsonb; result jsonb; response jsonb; request_hash text;
BEGIN
 IF auth.role() IS DISTINCT FROM 'authenticated' OR actor IS NULL OR NOT EXISTS(
  SELECT 1 FROM public.pdc_user_roles x WHERE x.auth_user_id=actor AND lower(btrim(x.email))=email
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
  WHERE l->'estimated_hours' IS NULL OR l->'estimated_hours'='null'::jsonb
    OR (l->>'completed')::boolean IS TRUE OR (l->>'active')::boolean IS DISTINCT FROM true
    OR l->>'source_kind'<>'authenticated')
 THEN RETURN jsonb_build_object('ok',false,'code','operation_hours_or_state_need_review'); END IF;
 FOR line IN SELECT l FROM jsonb_array_elements(before_row->'operations') l LOOP
  SELECT x INTO assignment FROM jsonb_array_elements(p_assignments) x WHERE x->>'line_identity'=line->>'line_identity';
  SELECT * INTO a FROM public.vehicle_workshop_line_adjustments WHERE vehicle_id=v.id AND line_key=line->>'line_identity';
  result:=public.move_vehicle_workshop_source_line_stage(v.id,a.adjustment_id,coalesce(a.version,0),line->>'line_identity',assignment->>'stage_code');
  IF result->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'station_assignment_failed' USING errcode='PDI01'; END IF;
 END LOOP;
 after_row:=public.pdc_new_vehicle_review_row(v.id);
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(before_row->'operations') oldline
  WHERE NOT EXISTS(SELECT 1 FROM jsonb_array_elements(after_row->'operations') newl
   JOIN jsonb_array_elements(p_assignments) chosen ON chosen->>'line_identity'=newl->>'line_identity'
   WHERE newl->>'line_identity'=oldline->>'line_identity' AND newl->>'stage_code'=chosen->>'stage_code'
    AND newl->'description'=oldline->'description' AND newl->'estimated_hours'=oldline->'estimated_hours'
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
END $fn$;
REVOKE ALL ON FUNCTION public.approve_pdc_new_vehicle_review(uuid,text,jsonb,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.approve_pdc_new_vehicle_review(uuid,text,jsonb,uuid) TO authenticated;