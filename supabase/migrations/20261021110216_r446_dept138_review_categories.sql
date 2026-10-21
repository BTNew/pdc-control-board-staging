-- r446 (F59, change request; Bhavesh 21 Oct 17:53 AWST, Craig approved 18:12 AWST): Dept 138 New Vehicles review uses the
-- Bus 4x4 stations. Staging cdsmnqxtyyoeoznmbidd only.
-- Root cause: the review page forced every Dept 138 line to Bus 4x4 / Tint / Tyre (locked dropdown, no drag) and the approval
-- RPC takes stage codes only, so the per-line work category (Mechanical / Accessories / Electrical / QA / Pit) could only be
-- fixed later in the vehicle drop-down.
-- This migration adds ONE function, public.approve_pdc_new_vehicle_review_446, which validates Dept 138 categories, calls the
-- UNCHANGED approve_pdc_new_vehicle_review, records the chosen categories in pdc_work_categories_private.line_overrides (as the
-- vehicle drop-down's set_vehicle_work_category does) and reads them back, all in one transaction.
-- Pins: the new function plus its unchanged dependencies approve_pdc_new_vehicle_review and pdc_new_vehicle_review_row
-- (pdc_work_categories_private.stage is already pinned by r410). Check dept138_review_categories_446 (sort 245).
-- Not touched: the approve function body, imports, bookings, bays, hours, the clock tick, Karratha 135, Dept 139.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r446: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r446: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r446: clock tick changed (this release must not touch it)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r446: fault_regression_check changed'; END IF;
 IF (SELECT md5(replace(prosrc,chr(13),'')) FROM pg_proc WHERE oid='public.approve_pdc_new_vehicle_review(uuid,text,jsonb,uuid)'::regprocedure)<>'f099baf746f35b500389749ac844bc2f'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.stage(text)'::regprocedure) IS NULL
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_new_vehicle_review_row(uuid)'::regprocedure) IS NULL THEN RAISE EXCEPTION 'r446: approval dependencies are not the reviewed versions'; END IF;
 IF to_regprocedure('public.approve_pdc_new_vehicle_review_446(uuid,text,jsonb,uuid)') IS NOT NULL
    OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r446')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='dept138_review_categories_446' OR added_in='r446') THEN RAISE EXCEPTION 'r446: already applied'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=245) THEN RAISE EXCEPTION 'r446: sort_order 245 taken'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE signature IN('public.approve_pdc_new_vehicle_review(uuid,text,jsonb,uuid)','public.pdc_new_vehicle_review_row(uuid)'))  THEN RAISE EXCEPTION 'r446: dependency already pinned'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>165 THEN RAISE EXCEPTION 'r446: expected 165 pins before'; END IF;
END $g$;

CREATE FUNCTION public.approve_pdc_new_vehicle_review_446(p_vehicle_id uuid, p_snapshot_hash text, p_assignments jsonb, p_idempotency_key uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $f$
-- r446 (F59): New Vehicles approval with Dept 138 work categories chosen on the review screen.
-- Each Dept 138 assignment carries work_category (BUS_MECHANICAL / BUS_ACCESSORIES / BUS_ELECTRICAL / BUS_QA / BUS_PIT /
-- TINT / TYRE / SUBLET). Its stage stays server-owned (pdc_bus_private.operation_station, enforced by the Dept 138 route
-- trigger); the category is what routes the line to the Bus 4x4 / Tint / Tyre / Sublet / Pit planners. Dept 139 and other
-- lines carry no category and are passed through unchanged. The unchanged approve_pdc_new_vehicle_review does the approval;
-- this function then records the chosen categories (pdc_work_categories_private.line_overrides, as the vehicle drop-down does)
-- in the SAME transaction and reads them back. Any failure after approval rolls the approval back too.
-- Never books, never moves the vehicle, never changes hours, never touches the clock tick.
DECLARE stg text; stages jsonb:='{}'::jsonb; before_row jsonb; after_row jsonb; approved jsonb; x jsonb; l jsonb; cat text; cur text; n integer:=0;
 v_version integer; plain jsonb:='[]'::jsonb; wanted jsonb:='{}'::jsonb; old_o pdc_work_categories_private.line_overrides%rowtype;
 allowed constant text[]:=ARRAY['BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA','BUS_PIT','TINT','TYRE','SUBLET'];
BEGIN
 IF p_vehicle_id IS NULL OR p_snapshot_hash IS NULL OR p_idempotency_key IS NULL OR jsonb_typeof(p_assignments) IS DISTINCT FROM 'array'
 THEN RETURN jsonb_build_object('ok',false,'code','invalid_approval'); END IF;
 -- Replay of an approval this user already made with this key: the review row has moved on (stages and hours now follow the
 -- recorded categories), so answer from the current state instead of rebuilding the original request.
 IF EXISTS(SELECT 1 FROM public.pdc_new_vehicle_reviews r WHERE r.vehicle_id=p_vehicle_id AND r.status='approved'
   AND r.approval_key=p_idempotency_key AND r.approved_by=auth.uid() AND auth.uid() IS NOT NULL) THEN
  after_row:=public.pdc_new_vehicle_review_row(p_vehicle_id);
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_assignments) a WHERE a ? 'work_category' AND NOT EXISTS(
    SELECT 1 FROM jsonb_array_elements(after_row->'operations') o WHERE o->>'line_identity'=a->>'line_identity' AND o->>'work_category'=a->>'work_category'))
  THEN RETURN jsonb_build_object('ok',false,'code','idempotency_payload_mismatch'); END IF;
  SELECT r.approval_receipt INTO approved FROM public.pdc_new_vehicle_reviews r WHERE r.vehicle_id=p_vehicle_id;
  SELECT version INTO v_version FROM public.vehicles WHERE id=p_vehicle_id;
  RETURN jsonb_set(jsonb_set(approved,'{data,operations}',after_row->'operations'),'{data,vehicle_version}',to_jsonb(v_version))
   ||jsonb_build_object('replay',true,'categories_written',0);
 END IF;
 before_row:=public.pdc_new_vehicle_review_row(p_vehicle_id);
 IF before_row IS NULL OR jsonb_typeof(before_row->'operations') IS DISTINCT FROM 'array' THEN RETURN jsonb_build_object('ok',false,'code','review_not_found'); END IF;
 FOR x IN SELECT a FROM jsonb_array_elements(p_assignments) a LOOP
  IF jsonb_typeof(x) IS DISTINCT FROM 'object' THEN RETURN jsonb_build_object('ok',false,'code','all_operations_need_stations'); END IF;
  SELECT o INTO l FROM jsonb_array_elements(before_row->'operations') o WHERE o->>'line_identity'=x->>'line_identity' LIMIT 1;
  IF l IS NULL THEN RETURN jsonb_build_object('ok',false,'code','all_operations_need_stations'); END IF;
  IF btrim(coalesce(l->>'department',''))='138' THEN
   cat:=x->>'work_category';
   IF cat IS NULL OR NOT cat=ANY(allowed) THEN RETURN jsonb_build_object('ok',false,'code','dept138_category_required','line_identity',x->>'line_identity'); END IF;
   -- The Dept 138 STAGE stays server-owned (trigger pdc_department138_bus_route requires pdc_bus_private.operation_station for
   -- source lines); the reviewer's choice is the work category, exactly as in the vehicle drop-down. The client's stage_code
   -- for Dept 138 lines is replaced here.
   stg:=NULL;
   IF l->>'line_identity' ~ '^source:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
    stg:=pdc_bus_private.operation_station(substr(l->>'line_identity',8)::uuid);
   END IF;
   stg:=coalesce(stg,CASE WHEN cat LIKE 'BUS\_%' THEN 'BUS_4X4' ELSE cat END);
   IF NOT stg=ANY(ARRAY['BUS_4X4','TINT','TYRE','SUBLET']) THEN RETURN jsonb_build_object('ok',false,'code','dept138_station_needs_review','line_identity',x->>'line_identity'); END IF;
   x:=jsonb_set(x,'{stage_code}',to_jsonb(stg));
   -- Sublet needs no hours on screen; when the server stage is still a workshop stage, the line keeps its own imported hours.
   IF cat='SUBLET' AND stg<>'SUBLET' AND NOT x ? 'estimated_hours' THEN
    IF coalesce((l->>'estimated_hours')::numeric,0)>0 THEN x:=x||jsonb_build_object('estimated_hours',(l->>'estimated_hours')::numeric);
    ELSIF coalesce((l->>'source_estimated_hours')::numeric,0)>0 THEN x:=x||jsonb_build_object('estimated_hours',(l->>'source_estimated_hours')::numeric);
    ELSE RETURN jsonb_build_object('ok',false,'code','dept138_sublet_needs_hours','line_identity',x->>'line_identity'); END IF;
   END IF;
   wanted:=wanted||jsonb_build_object(x->>'line_identity',cat);
   stages:=stages||jsonb_build_object(x->>'line_identity',stg);
  ELSIF x ? 'work_category' THEN RETURN jsonb_build_object('ok',false,'code','category_only_for_dept138','line_identity',x->>'line_identity');
  END IF;
  plain:=plain||jsonb_build_array(x-'work_category');
 END LOOP;
 BEGIN
  approved:=public.approve_pdc_new_vehicle_review(p_vehicle_id,p_snapshot_hash,plain,p_idempotency_key);
  IF approved->>'ok' IS DISTINCT FROM 'true' THEN RETURN approved; END IF;
  IF coalesce((approved->>'replay')::boolean,false) THEN RETURN jsonb_build_object('ok',false,'code','idempotency_payload_mismatch'); END IF;
  after_row:=public.pdc_new_vehicle_review_row(p_vehicle_id);
  FOR l IN SELECT o FROM jsonb_array_elements(after_row->'operations') o WHERE wanted ? (o->>'line_identity') LOOP
   cat:=wanted->>(l->>'line_identity'); cur:=l->>'work_category';
   CONTINUE WHEN cur IS NOT DISTINCT FROM cat;
   SELECT * INTO old_o FROM pdc_work_categories_private.line_overrides WHERE vehicle_id=p_vehicle_id AND line_identity=l->>'line_identity' FOR UPDATE;
   INSERT INTO pdc_work_categories_private.line_overrides(vehicle_id,line_identity,category,updated_by)
   VALUES(p_vehicle_id,l->>'line_identity',cat,auth.uid())
   ON CONFLICT(vehicle_id,line_identity) DO UPDATE SET category=excluded.category,version=line_overrides.version+1,updated_by=excluded.updated_by,updated_at=clock_timestamp() WHERE line_overrides.category IS DISTINCT FROM excluded.category;
   INSERT INTO public.vehicle_work_items(vehicle_id,work_key,required,completed)
   SELECT p_vehicle_id,s.work_key,true,false FROM public.workshop_stages s WHERE s.code=pdc_work_categories_private.stage(cat)
   ON CONFLICT(vehicle_id,work_key) DO UPDATE SET required=true WHERE NOT public.vehicle_work_items.completed;
   INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
   VALUES('update','vehicle_work_category',p_vehicle_id,p_vehicle_id,auth.uid(),public.current_actor_email(),
    CASE WHEN old_o.vehicle_id IS NULL THEN NULL ELSE to_jsonb(old_o) END,
    jsonb_build_object('line_identity',l->>'line_identity','category',cat,'previous_projected_category',cur),
    jsonb_build_object('source','r446_new_vehicle_review_approval','idempotency_key',p_idempotency_key,'source_hours_preserved',true));
   old_o:=NULL; n:=n+1;
  END LOOP;
  IF n>0 THEN
   PERFORM public.pdc_auditor_recalculate_required_work_226(ARRAY[p_vehicle_id]);
   UPDATE public.vehicles SET version=version+1,updated_at=clock_timestamp(),updated_by=auth.uid() WHERE id=p_vehicle_id;
   PERFORM public.workshop_bump_revision();
  END IF;
  after_row:=public.pdc_new_vehicle_review_row(p_vehicle_id);
  IF EXISTS(SELECT 1 FROM jsonb_each_text(wanted) w WHERE NOT EXISTS(SELECT 1 FROM jsonb_array_elements(after_row->'operations') o
    WHERE o->>'line_identity'=w.key AND o->>'work_category'=w.value
      AND o->>'stage_code' IN(stages->>w.key,pdc_work_categories_private.stage(w.value))))
  THEN RAISE EXCEPTION 'category_readback_mismatch' USING errcode='PDI46'; END IF;
  SELECT version INTO v_version FROM public.vehicles WHERE id=p_vehicle_id;
  approved:=jsonb_set(jsonb_set(approved,'{data,operations}',after_row->'operations'),'{data,vehicle_version}',to_jsonb(v_version))
   ||jsonb_build_object('categories_written',n);
  RETURN approved;
 EXCEPTION WHEN SQLSTATE 'PDI46' THEN
  RETURN jsonb_build_object('ok',false,'code',SQLERRM);
 END;
END
$f$;
REVOKE ALL ON FUNCTION public.approve_pdc_new_vehicle_review_446(uuid,text,jsonb,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_pdc_new_vehicle_review_446(uuid,text,jsonb,uuid) TO authenticated;

INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note,updated_at)
SELECT s.sig, md5(p.prosrc), 'r446', s.note, now()
FROM (VALUES
 ('public.approve_pdc_new_vehicle_review_446(uuid,text,jsonb,uuid)','r446 (F59): New Vehicles approval with Dept 138 review categories (wraps the unchanged approve; one transaction)'),
 ('public.approve_pdc_new_vehicle_review(uuid,text,jsonb,uuid)','r446 (F59): unchanged dependency of approve_pdc_new_vehicle_review_446'),
 ('public.pdc_new_vehicle_review_row(uuid)','r446 (F59): unchanged dependency (review row incl. work_category) of approve_pdc_new_vehicle_review_446')
) s(sig,note) JOIN pg_catalog.pg_proc p ON p.oid=s.sig::regprocedure;

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('dept138_review_categories_446','F59','Dept 138 review categories (r446): approve_pdc_new_vehicle_review_446 exists, SECURITY DEFINER with search_path pg_catalog, executable by authenticated and not anon; it delegates to approve_pdc_new_vehicle_review and only writes line_overrides / vehicle_work_items / audit_events / vehicles.version (never bookings, hours adjustments, the clock tick, email or outbox); a call without a session is refused; every category it recorded is one of the 8 Dept 138 review categories on a Dept 138 line',
  $chk$WITH f AS (SELECT p.oid,p.prosrc,p.prosecdef,p.proconfig FROM pg_catalog.pg_proc p WHERE p.oid=to_regprocedure('public.approve_pdc_new_vehicle_review_446(uuid,text,jsonb,uuid)')),
 b AS (
 SELECT (SELECT count(*) FROM f)=1 AND (SELECT bool_and(prosecdef AND proconfig=ARRAY['search_path=pg_catalog']) FROM f) AS shape,
  (SELECT bool_and(has_function_privilege('authenticated',oid,'EXECUTE') AND NOT has_function_privilege('anon',oid,'EXECUTE')) FROM f) AS grants,
  (SELECT bool_and(prosrc ~ 'public\.approve_pdc_new_vehicle_review\(' AND prosrc !~* '(INSERT INTO|UPDATE|DELETE FROM)\s+public\.(workshop_bookings|vehicle_workshop_line_adjustments|pdc_pilbara_service_operations|pdc_new_vehicle_reviews)\b'
    AND prosrc !~* '(workshop_clock_tick|outbox|net\.http|smtp|send_email)') FROM f) AS writes,
  auth.uid() IS NOT NULL OR (public.approve_pdc_new_vehicle_review_446(NULL,NULL,'[]'::jsonb,NULL)->>'code')='invalid_approval'
   AND (public.approve_pdc_new_vehicle_review_446('00000000-0000-4000-8000-000000000446',repeat('0',64),'[]'::jsonb,'00000000-0000-4000-8000-000000000446')->>'ok') IS DISTINCT FROM 'true' AS no_session_refused,
  NOT EXISTS(SELECT 1 FROM public.audit_events e WHERE e.table_name='vehicle_work_category' AND e.metadata->>'source'='r446_new_vehicle_review_approval'
    AND NOT coalesce(e.after_data->>'category' IN('BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA','BUS_PIT','TINT','TYRE','SUBLET'),false)) AS categories_valid
)
SELECT b.shape AND b.grants AND b.writes AND b.no_session_refused AND b.categories_valid AS ok,
 format('%s Dept 138 review categories recorded at approval (r446) on %s vehicle(s); shape %s, grants %s, writes %s, no-session refused %s, categories valid %s',
  (SELECT count(*) FROM public.audit_events e WHERE e.table_name='vehicle_work_category' AND e.metadata->>'source'='r446_new_vehicle_review_approval'),
  (SELECT count(DISTINCT e.vehicle_id) FROM public.audit_events e WHERE e.table_name='vehicle_work_category' AND e.metadata->>'source'='r446_new_vehicle_review_approval'),
  b.shape,b.grants,b.writes,b.no_session_refused,b.categories_valid) AS detail
FROM b
$chk$,true,245,'r446');
DO $g$ BEGIN
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r446')<>3 OR (SELECT count(*) FROM pdc_ops.expected_function_md5)<>168 THEN RAISE EXCEPTION 'r446: pins not written'; END IF;
 IF (SELECT md5(replace(prosrc,chr(13),'')) FROM pg_proc WHERE oid='public.approve_pdc_new_vehicle_review(uuid,text,jsonb,uuid)'::regprocedure)<>'f099baf746f35b500389749ac844bc2f' THEN RAISE EXCEPTION 'r446: approve changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r446: clock tick changed'; END IF;
 IF has_function_privilege('anon','public.approve_pdc_new_vehicle_review_446(uuid,text,jsonb,uuid)','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.approve_pdc_new_vehicle_review_446(uuid,text,jsonb,uuid)','EXECUTE') THEN RAISE EXCEPTION 'r446: unexpected function grants'; END IF;
END $g$;
