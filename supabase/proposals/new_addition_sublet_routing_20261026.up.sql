-- Working staging cdsmnqxtyyoeoznmbidd only; guarded proposal repair.
-- Only future, unapproved new additions matching existing canonical external rules change.
-- No existing rows, mappings, hours, approvals, reservations or permissions are edited.
SET LOCAL lock_timeout='3s';
SET LOCAL statement_timeout='15s';
DO $new_addition_routing$
DECLARE
 v_target oid:='pdc_operation_updates_private.proposal(uuid)'::regprocedure;
 v_before jsonb;
 v_definition text;
 v_anchor text:=' p:=q.proposed_source;';
 v_insert text:=$new_source_only$
 -- New additions must use the same already-approved external-line rules as the
 -- canonical projection. Existing/approved/manual work retains the original path.
 IF q.source_operation_id IS NULL AND q.change_kind='added' AND q.status='pending'
  AND q.approval_key IS NULL AND q.approved_at IS NULL AND q.approved_by IS NULL
  AND coalesce(q.approval_receipt,'{}'::jsonb)='{}'::jsonb
  AND (pdc_work_categories_private.note_fee_sublet_521(jsonb_build_object(
        'description',p->>'operation_description','operation_code',p->>'operation_code'))
    OR pdc_work_categories_private.perth_delivery_sublet_523(jsonb_build_object(
        'description',p->>'operation_description','operation_code',p->>'operation_code')))
 THEN
  h:=coalesce((p->>'effective_estimated_hours')::numeric,(p->>'source_estimated_hours')::numeric,0);
  -- Dept139 retains its established effective-hours standards; source stays intact.
  IF p->>'department'='139' THEN h:=coalesce(public.pdc_standard_operation_hours_20260910(p->>'operation_description',h),0); END IF;
  IF h<0 OR h>999.99 OR mod(h,0.01)<>0
  THEN RETURN jsonb_build_object('ok',false,'code','estimated_hours_required'); END IF;
  RETURN jsonb_build_object('ok',true,'stage_code','SUBLET','adjustment_stage_code','SUBLET',
   'work_category','SUBLET','estimated_hours',h,
   'hours_provenance',coalesce(nullif(p->>'hours_provenance',''),'source_explicit'),
   'routing_rule','canonical_external_sublet_20261026');
 END IF;

 -- Later uploads for an operation created by this policy use its current
 -- projected choice, including subsequent staff categories, rather than stale AI.
 IF q.source_operation_id IS NOT NULL AND q.status='pending'
  AND EXISTS(SELECT 1 FROM public.pdc_tune_operation_change_reviews prior
   WHERE prior.source_operation_id=q.source_operation_id AND prior.vehicle_id=q.vehicle_id
    AND prior.change_kind='added' AND prior.status='approved'
    AND prior.approval_receipt#>>'{data,estimate,routing_rule}'='canonical_external_sublet_20261026'
    AND prior.approval_receipt#>>'{data,estimate,ok}'='true'
    AND prior.approval_receipt#>>'{data,estimate,stage_code}'='SUBLET'
    AND prior.approval_receipt#>>'{data,estimate,work_category}'='SUBLET')
  AND (pdc_work_categories_private.note_fee_sublet_521(jsonb_build_object(
        'description',p->>'operation_description','operation_code',p->>'operation_code'))
    OR pdc_work_categories_private.perth_delivery_sublet_523(jsonb_build_object(
        'description',p->>'operation_description','operation_code',p->>'operation_code')))
 THEN
  SELECT l INTO actual FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(q.vehicle_id)) l
   WHERE l->>'line_identity'='source:'||q.source_operation_id;
  IF actual IS NULL OR actual->>'completed'='true' OR actual->>'rejected'='true'
   OR actual->>'active' IS DISTINCT FROM 'true'
  THEN RETURN jsonb_build_object('ok',false,'code','completed_or_removed_line_protected'); END IF;
  c:=actual->>'work_category'; stage:=actual->>'stage_code';
  h:=coalesce((p->>'effective_estimated_hours')::numeric,(p->>'source_estimated_hours')::numeric,0);
  IF p->>'department'='139' THEN h:=coalesce(public.pdc_standard_operation_hours_20260910(p->>'operation_description',h),0); END IF;
  provenance:=coalesce(nullif(p->>'hours_provenance',''),'source_explicit');
  IF EXISTS(SELECT 1 FROM public.vehicle_workshop_line_adjustments a
    WHERE a.vehicle_id=q.vehicle_id AND a.line_key='source:'||q.source_operation_id AND a.manual_assignment_locked)
   OR (q.before_source->'source_estimated_hours' IS NOT DISTINCT FROM p->'source_estimated_hours'
    AND q.before_source->>'operation_description' IS NOT DISTINCT FROM p->>'operation_description')
  THEN h:=(actual->>'estimated_hours')::numeric; provenance:='retained_accepted_estimate'; END IF;
  IF h IS NULL OR h<0 OR h>999.99 OR mod(h,0.01)<>0
   OR (h=0 AND c NOT IN('SUBLET','BUS_PIT','BUS_QA','JOB_CARD_NOTES'))
  THEN RETURN jsonb_build_object('ok',false,'code','estimated_hours_required'); END IF;
  RETURN jsonb_build_object('ok',true,'stage_code',stage,
   'adjustment_stage_code',CASE WHEN p->>'department'='138' THEN pdc_bus_private.operation_station(q.source_operation_id) ELSE stage END,
   'work_category',c,'estimated_hours',h,'hours_provenance',provenance,
   'routing_rule','retained_canonical_external_20261026');
 END IF;
$new_source_only$;
BEGIN
 -- Keep this inserted block deterministic when a Windows client sends CRLF.
 -- The existing function body retains its exact original line endings.
 v_insert:=replace(v_insert,E'\r\n',E'\n');
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR auth.uid() IS NOT NULL
  OR NOT pdc_codex_intake_private.management_connection()
  OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RAISE EXCEPTION 'new_addition_sublet_staging_management_required'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=v_target
  AND md5(p.prosrc)='48d590c26ddc7e1c92449450a841c931' AND pg_get_userbyid(p.proowner)='postgres'
  AND p.proacl='{postgres=X/postgres}'::aclitem[] AND p.proconfig=ARRAY['search_path=pg_catalog']::text[]
  AND NOT p.prosecdef AND p.provolatile='s' AND NOT p.proisstrict AND NOT p.proleakproof AND p.proparallel='u')
  OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE signature='pdc_operation_updates_private.proposal(uuid)')
 THEN RAISE EXCEPTION 'new_addition_sublet_proposal_or_metadata_changed'; END IF;
 IF md5(pg_get_functiondef('pdc_operation_updates_private.proposal_before_automatic_20261019(uuid)'::regprocedure))<>'149f4b42c250636155f8d19e135280e7' THEN RAISE EXCEPTION 'new_addition_sublet_dependency_changed: pdc_operation_updates_private.proposal_before_automatic_20261019(uuid)'; END IF;
 IF md5(pg_get_functiondef('pdc_operation_updates_private.accept_change(uuid)'::regprocedure))<>'061f651cfe522cfcee00cdcdfe3b4409' THEN RAISE EXCEPTION 'new_addition_sublet_dependency_changed: pdc_operation_updates_private.accept_change(uuid)'; END IF;
 IF md5(pg_get_functiondef('pdc_work_categories_private.route_import_line_20261017(jsonb,boolean)'::regprocedure))<>'e3f898b2609e098c58aaf31290e1927b' THEN RAISE EXCEPTION 'new_addition_sublet_dependency_changed: pdc_work_categories_private.route_import_line_20261017(jsonb,boolean)'; END IF;
 IF md5(pg_get_functiondef('pdc_work_categories_private.note_fee_sublet_521(jsonb)'::regprocedure))<>'a5e081c31037886985f77ba2f4209c84' THEN RAISE EXCEPTION 'new_addition_sublet_dependency_changed: pdc_work_categories_private.note_fee_sublet_521(jsonb)'; END IF;
 IF md5(pg_get_functiondef('pdc_work_categories_private.perth_delivery_sublet_523(jsonb)'::regprocedure))<>'2613c2ca36345a3bcb10bf6be2c4c111' THEN RAISE EXCEPTION 'new_addition_sublet_dependency_changed: pdc_work_categories_private.perth_delivery_sublet_523(jsonb)'; END IF;
 SELECT to_jsonb(p)-'prosrc',pg_get_functiondef(p.oid) INTO STRICT v_before,v_definition FROM pg_proc p WHERE p.oid=v_target;
 IF md5(pg_get_functiondef('public.pdc_standard_operation_hours_20260910(text,numeric)'::regprocedure))<>'4888c0c147484c9873bbf196e5c2e50c' THEN RAISE EXCEPTION 'new_addition_sublet_standard_hours_changed'; END IF;
 IF (length(v_definition)-length(replace(v_definition,v_anchor,'')))/length(v_anchor)<>1
  OR position(v_insert IN v_definition)>0 THEN RAISE EXCEPTION 'new_addition_sublet_anchor_changed'; END IF;
 EXECUTE replace(v_definition,v_anchor,v_anchor||v_insert);
 IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=v_target AND md5(p.prosrc)='1c1eb17a1594f36489cf33572117d642' AND to_jsonb(p)-'prosrc'=v_before)
 THEN RAISE EXCEPTION 'new_addition_sublet_readback_failed: source %, metadata fields %',
  (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid=v_target),
  (SELECT array_agg(k ORDER BY k) FROM pg_proc p,
   jsonb_object_keys(v_before) k WHERE p.oid=v_target AND (to_jsonb(p)->k) IS DISTINCT FROM (v_before->k)); END IF;
END
$new_addition_routing$;

