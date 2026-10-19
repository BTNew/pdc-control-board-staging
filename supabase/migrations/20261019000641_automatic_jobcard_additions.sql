DO $version$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='pdc_capture_tune_operation_changes_20260912' AND pg_get_function_identity_arguments(p.oid)='preview_id uuid, applied_id uuid' AND md5(replace(pg_get_functiondef(p.oid),chr(13),''))='79831af33fb12b1844b75e8594bce8e7') THEN RAISE EXCEPTION 'source_version_changed: pdc_capture_tune_operation_changes_20260912'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='get_vehicle_workshop_detail_scoped' AND pg_get_function_identity_arguments(p.oid)='p_vehicle_id uuid, p_dealer_code text' AND md5(replace(pg_get_functiondef(p.oid),chr(13),''))='470fd3ad5ab40f4671b47946514f2540') THEN RAISE EXCEPTION 'source_version_changed: get_vehicle_workshop_detail_scoped'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='pdc_operation_updates_private' AND p.proname='reconcile_bookings' AND pg_get_function_identity_arguments(p.oid)='p_vehicle_id uuid, p_stage_codes text[], p_change_id uuid, p_actor uuid' AND md5(replace(pg_get_functiondef(p.oid),chr(13),''))='5cb064fddd6ce6381cc56a0732ac1338') THEN RAISE EXCEPTION 'source_version_changed: reconcile_bookings'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='pdc_operation_updates_private' AND p.proname='proposal' AND pg_get_function_identity_arguments(p.oid)='p_change_id uuid' AND md5(replace(pg_get_functiondef(p.oid),chr(13),''))='d156f42fdc7af1be01cfc89dc7bd137b') THEN RAISE EXCEPTION 'source_version_changed: proposal'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='pdc_operation_updates_private' AND p.proname='accept_change' AND pg_get_function_identity_arguments(p.oid)='p_change_id uuid' AND md5(replace(pg_get_functiondef(p.oid),chr(13),''))='536d7120307636ff60e29b050a9baa12') THEN RAISE EXCEPTION 'source_version_changed: accept_change'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='pdc_operation_updates_private' AND p.proname='process_pending' AND pg_get_function_identity_arguments(p.oid)='p_vehicle_ids uuid[], p_limit integer, p_department text' AND md5(replace(pg_get_functiondef(p.oid),chr(13),''))='72990aa8a7da40ca7be4efa4b9e7ea0d') THEN RAISE EXCEPTION 'source_version_changed: process_pending'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='pdc_bus_private' AND p.proname='operation_station' AND pg_get_function_identity_arguments(p.oid)='p_operation_id uuid' AND md5(replace(pg_get_functiondef(p.oid),chr(13),''))='980a01fafd9b1341cb57f44b8ac817f2') THEN RAISE EXCEPTION 'source_version_changed: operation_station'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='pdc_work_categories_private' AND p.proname='stage' AND pg_get_function_identity_arguments(p.oid)='category text' AND md5(replace(pg_get_functiondef(p.oid),chr(13),''))='e8264b095869152e0b50375a84ddafb8') THEN RAISE EXCEPTION 'source_version_changed: stage'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='pdc_work_categories_private' AND p.proname='route_import_line_20261017' AND pg_get_function_identity_arguments(p.oid)='line jsonb, preserve boolean' AND md5(replace(pg_get_functiondef(p.oid),chr(13),''))='a86d74aba126b7e58cae33da2f0574af') THEN RAISE EXCEPTION 'source_version_changed: route_import_line_20261017'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='pdc_qc_operation_lines_379' AND pg_get_function_identity_arguments(p.oid)='p_vehicle_id uuid' AND md5(replace(pg_get_functiondef(p.oid),chr(13),''))='7a957c8a4dca65ce77c1cb4a83c15ff7') THEN RAISE EXCEPTION 'source_version_changed: pdc_qc_operation_lines_379'; END IF;
END $version$;
-- Staging only. AI routing decisions are supplied by the existing authorised import agent.
-- Source evidence, staff overrides, identity, completion and scheduling guards remain authoritative.
DO $guard$ BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR auth.uid() IS NOT NULL
 OR NOT pdc_codex_intake_private.management_connection()
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RAISE EXCEPTION 'staging_management_required'; END IF;
END $guard$;
SET LOCAL lock_timeout='5s';
CREATE TABLE pdc_operation_updates_private.ai_routing_20261019 (
 department text NOT NULL CHECK(department IN('138','139')),
 description_hash text NOT NULL CHECK(length(description_hash)=32),
 category text NOT NULL CHECK(category IN('BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA','BUS_PIT','FITTING','HOIST','FABRICATION','ELECTRICAL','TINT','TYRE','SUBLET','JOB_CARD_NOTES')),
 estimated_hours numeric CHECK(estimated_hours BETWEEN 0 AND 999.99 AND estimated_hours=round(estimated_hours,2)),
 confidence numeric NOT NULL CHECK(confidence BETWEEN 0.85 AND 1),
 rationale text NOT NULL CHECK(length(rationale) BETWEEN 10 AND 1000),
 provider text NOT NULL DEFAULT 'codex_import_agent',
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(department,description_hash),
 CHECK((department='138' AND category NOT IN('FITTING','HOIST','FABRICATION','ELECTRICAL')) OR (department='139' AND category NOT LIKE 'BUS_%'))
);
ALTER TABLE pdc_operation_updates_private.ai_routing_20261019 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_operation_updates_private.ai_routing_20261019 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION pdc_operation_updates_private.remember_ai_routing_20261019(
 p_department text,p_description text,p_category text,p_hours numeric,p_confidence numeric,p_rationale text)
RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS $fn$
DECLARE h text; old pdc_operation_updates_private.ai_routing_20261019%rowtype;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR auth.uid() IS NOT NULL
 OR NOT pdc_codex_intake_private.management_connection()
 THEN RAISE EXCEPTION 'staging_management_required'; END IF;
 IF nullif(btrim(p_description),'') IS NULL THEN RAISE EXCEPTION 'description_required'; END IF;
 h:=pdc_work_categories_private.import_description_hash_20261017(p_description);
 SELECT * INTO old FROM pdc_operation_updates_private.ai_routing_20261019 WHERE department=p_department AND description_hash=h;
 IF FOUND THEN
  IF old.category IS DISTINCT FROM p_category OR old.estimated_hours IS DISTINCT FROM p_hours
  THEN RAISE EXCEPTION 'routing_decision_conflict'; END IF;
  RETURN jsonb_build_object('ok',true,'replay',true,'description_hash',h);
 END IF;
 INSERT INTO pdc_operation_updates_private.ai_routing_20261019(department,description_hash,category,estimated_hours,confidence,rationale)
 VALUES(p_department,h,p_category,p_hours,p_confidence,p_rationale);
 RETURN jsonb_build_object('ok',true,'description_hash',h);
END $fn$;
REVOKE ALL ON FUNCTION pdc_operation_updates_private.remember_ai_routing_20261019(text,text,text,numeric,numeric,text) FROM PUBLIC,anon,authenticated,service_role;

-- Keep the department station constraint authoritative, including learned notes/sublet.
-- Existing per-operation routing history still wins over a learned description.
CREATE OR REPLACE FUNCTION pdc_bus_private.operation_station(p_operation_id uuid)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
 SELECT coalesce(h.stage_code,pdc_work_categories_private.stage(r.category),
  public.pdc_department138_station_20260917(coalesce(public.pdc_tune_approved_operation_source_20260912(o.operation_id)->>'operation_description',o.operation_description)))
 FROM public.pdc_pilbara_service_operations o
 LEFT JOIN pdc_bus_private.operation_routing_history_20261015 h USING(operation_id)
 LEFT JOIN pdc_operation_updates_private.ai_routing_20261019 r ON r.department=btrim(o.department)
  AND r.description_hash=pdc_work_categories_private.import_description_hash_20261017(
   coalesce(public.pdc_tune_approved_operation_source_20260912(o.operation_id)->>'operation_description',o.operation_description))
 WHERE o.operation_id=p_operation_id;
$fn$;

ALTER FUNCTION pdc_operation_updates_private.proposal(uuid) RENAME TO proposal_before_automatic_20261019;
CREATE FUNCTION pdc_operation_updates_private.proposal(p_change_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=pg_catalog AS $fn$
DECLARE q public.pdc_tune_operation_change_reviews%rowtype; r pdc_operation_updates_private.ai_routing_20261019%rowtype;
 p jsonb; actual jsonb; h numeric; c text; stage text; provenance text;
BEGIN
 SELECT * INTO q FROM public.pdc_tune_operation_change_reviews WHERE change_id=p_change_id;
 p:=q.proposed_source;
 SELECT * INTO r FROM pdc_operation_updates_private.ai_routing_20261019
 WHERE department=p->>'department' AND description_hash=pdc_work_categories_private.import_description_hash_20261017(p->>'operation_description');
 IF NOT FOUND THEN RETURN pdc_operation_updates_private.proposal_before_automatic_20261019(p_change_id); END IF;
 SELECT l INTO actual FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(q.vehicle_id)) l WHERE l->>'line_identity'='source:'||q.source_operation_id;
 c:=r.category;
 h:=coalesce((p->>'effective_estimated_hours')::numeric,(p->>'source_estimated_hours')::numeric);
 provenance:='source_explicit';
 IF c='JOB_CARD_NOTES' AND coalesce(h,0)>0 THEN RETURN jsonb_build_object('ok',false,'code','note_has_labour_hours'); END IF;
 IF c IN('SUBLET','BUS_PIT','JOB_CARD_NOTES') THEN h:=coalesce(h,0);
 ELSIF c='BUS_QA' AND h=0 THEN NULL;
 ELSIF h IS NULL OR h<=0 THEN h:=r.estimated_hours;provenance:='ai_estimate'; END IF;
 -- Saved manual routing and estimates win over subsequent automatic classifications.
 IF EXISTS(SELECT 1 FROM public.vehicle_workshop_line_adjustments a WHERE a.vehicle_id=q.vehicle_id AND a.line_key='source:'||q.source_operation_id AND a.manual_assignment_locked)
 THEN c:=coalesce(actual->>'work_category',actual->>'stage_code');h:=(actual->>'estimated_hours')::numeric;provenance:='retained_staff_choice'; END IF;
 stage:=pdc_work_categories_private.stage(c);
 IF h IS NULL OR h<0 OR h>999.99 OR mod(h,0.01)<>0
 OR (h=0 AND c NOT IN('SUBLET','BUS_PIT','BUS_QA','JOB_CARD_NOTES'))
 THEN RETURN jsonb_build_object('ok',false,'code','estimated_hours_required'); END IF;
 RETURN jsonb_build_object('ok',true,'stage_code',stage,'adjustment_stage_code',stage,'work_category',c,
  'estimated_hours',h,'hours_provenance',provenance,'routing_rule','ai_import_20261019','confidence',r.confidence);
END $fn$;
REVOKE ALL ON FUNCTION pdc_operation_updates_private.proposal(uuid) FROM PUBLIC,anon,authenticated,service_role;

ALTER FUNCTION pdc_work_categories_private.route_import_line_20261017(jsonb,boolean) RENAME TO route_before_automatic_20261019;
CREATE FUNCTION pdc_work_categories_private.route_import_line_20261017(line jsonb,preserve boolean)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=pg_catalog AS $fn$
DECLARE r pdc_operation_updates_private.ai_routing_20261019%rowtype; h numeric;
BEGIN
 IF preserve IS TRUE OR coalesce((line->>'completed')::boolean,false) OR coalesce((line->>'rejected')::boolean,false) OR NOT coalesce((line->>'active')::boolean,true)
 THEN RETURN pdc_work_categories_private.route_before_automatic_20261019(line,preserve); END IF;
 SELECT * INTO r FROM pdc_operation_updates_private.ai_routing_20261019 WHERE department=line->>'department'
 AND description_hash=pdc_work_categories_private.import_description_hash_20261017(line->>'description');
 IF NOT FOUND THEN RETURN pdc_work_categories_private.route_before_automatic_20261019(line,preserve); END IF;
 h:=(line->>'estimated_hours')::numeric;
 IF (h IS NULL OR h<=0) AND r.category NOT IN('SUBLET','BUS_PIT','BUS_QA','JOB_CARD_NOTES')
 THEN RETURN pdc_work_categories_private.route_before_automatic_20261019(line,preserve); END IF;
 RETURN line||jsonb_build_object('work_category',r.category,'stage_code',pdc_work_categories_private.stage(r.category),
 'zero_hour_task',r.category='BUS_QA' AND h=0,'information_only',r.category='JOB_CARD_NOTES');
END $fn$;
REVOKE ALL ON FUNCTION pdc_work_categories_private.route_import_line_20261017(jsonb,boolean) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION pdc_operation_updates_private.accept_change(p_change_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE q public.pdc_tune_operation_change_reviews%rowtype; v public.vehicles%rowtype;
 a public.vehicle_workshop_line_adjustments%rowtype; evidence public.pdc_pilbara_service_import_rows%rowtype;
 actor uuid; choice jsonb; candidate jsonb; p jsonb; actual jsonb; new_line jsonb; schedule jsonb; reply jsonb;
 source_id uuid; key text; stage text; work text; h numeric; before_vehicle jsonb;
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
  VALUES(v.id,key,'source',coalesce(choice->>'adjustment_stage_code',stage),btrim(left(btrim(regexp_replace(p->>'operation_description','[[:cntrl:]]',' ','g')),180)),h,true,1,(q.source_operation_id IS NOT NULL OR p->>'department'<>'138'),actor,actor,CASE WHEN q.source_operation_id IS NULL AND p->>'department'='138' THEN 'job_card_source_correction' END);
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
 RETURN reply;
EXCEPTION WHEN OTHERS THEN
 -- Each failed change rolls back independently; immutable uploaded evidence stays.
 PERFORM set_config('pdc.defer_workshop_adjustment_reconcile',coalesce(original_defer,''),true);
 PERFORM set_config('pdc.defer_workshop_required_work_reconcile',coalesce(original_required_defer,''),true);
 RETURN jsonb_build_object('ok',false,'code',CASE WHEN SQLSTATE IN('40001','40P01','55P03') THEN 'operation_schedule_busy' ELSE 'operation_schedule_conflict' END,
  'detail',SQLERRM);
END $function$
;

-- Pending additions remain visible on the owning card without becoming bookable work.
-- The existing scoped reader still performs all identity/role/dealer checks first.
DO $patch$
DECLARE d text;
BEGIN
 d:=pg_get_functiondef('public.get_vehicle_workshop_detail_scoped(uuid,text)'::regprocedure);
 IF position('RETURN public.get_vehicle_workshop_detail(p_vehicle_id);' in d)=0 THEN RAISE EXCEPTION 'scoped_reader_changed'; END IF;
 d:=replace(d,'RETURN public.get_vehicle_workshop_detail(p_vehicle_id);',
 $replacement$RETURN public.get_vehicle_workshop_detail(p_vehicle_id) || jsonb_build_object('imported_additions',
  (SELECT coalesce(jsonb_agg(jsonb_build_object('change_id',q.change_id,'description',q.proposed_source->>'operation_description',
    'department',q.proposed_source->>'department','job_card',q.repair_order_number,'line_number',q.original_line_number,
    'source_hours',q.proposed_source->'source_estimated_hours','status',coalesce(q.automation_result->>'code','classification_pending')) ORDER BY q.created_at),'[]')
   FROM public.pdc_tune_operation_change_reviews q WHERE q.vehicle_id=p_vehicle_id AND q.status='pending'));
 $replacement$);
 EXECUTE d;
END $patch$;
