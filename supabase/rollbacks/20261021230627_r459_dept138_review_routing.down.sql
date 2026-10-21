-- r459 (F72) undo: restores approve_pdc_new_vehicle_review_446 (r446, f4ca4be9) and pdc_bus_private.operation_station
-- (r410, f7ab4745) and their pins, and drops check dept138_review_routing_459. Staging cdsmnqxtyyoeoznmbidd only, :02-:45.
-- The routing table pdc_bus_private.operation_review_station_459 is dropped only when empty. If approvals recorded reviewer
-- stations after the release, the table is kept (renamed ..._undone) so the record is not lost; those lines then route by
-- the import routing again (their saved stage stays as approved; the route trigger will ask for the import station on the
-- next edit of those lines). Revert the frontend commit at the same time.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r459 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r459 undo: staging only'; END IF;
 -- The clock tick is not touched: its body is recorded here and must be identical at the end (r452 / F65 changed it on 22 Oct 07:01 AWST).
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) NOT IN('0aaaa15690ca286ed0db87fc72271d5a','84af7607bfd0ce9907c89bae8644d5b6') THEN RAISE EXCEPTION 'r459 undo: clock tick is not a reviewed version'; END IF;
 PERFORM set_config('r459.tick_before',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r459 undo: fault_regression_check changed'; END IF;
 IF (SELECT md5(replace(prosrc,chr(13),'')) FROM pg_proc WHERE oid='public.approve_pdc_new_vehicle_review(uuid,text,jsonb,uuid)'::regprocedure)<>'f099baf746f35b500389749ac844bc2f'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_new_vehicle_review_row(uuid)'::regprocedure)<>'200a8508a213613fbbddaecf166ce023'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_require_department138_bus_20260916()'::regprocedure)<>'541414352f5a4f83ee44112f302da62b'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.stage(text)'::regprocedure) IS NULL THEN RAISE EXCEPTION 'r459 undo: approval dependencies are not the reviewed versions'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.approve_pdc_new_vehicle_review_446(uuid,text,jsonb,uuid)'::regprocedure)<>'a50e6a6988ae3a106f959e3163b4121c'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_bus_private.operation_station(uuid)'::regprocedure)<>'03e96225dc36891ec0d122aecd87b967' THEN RAISE EXCEPTION 'r459 undo: functions are not the r459 versions'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r459')<>2 THEN RAISE EXCEPTION 'r459 undo: expected exactly 2 r459 pins'; END IF;
 PERFORM set_config('r459.pins_before',(SELECT count(*) FROM pdc_ops.expected_function_md5)::text,true);
END $g$;

CREATE OR REPLACE FUNCTION pdc_bus_private.operation_station(p_operation_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $f$
BEGIN
 -- r410 (F26): PL/pgSQL so the plan is kept for the session (the SQL form with SET search_path
 -- is never inlined and was planned again on every call). Same query; LIMIT 1 keeps the SQL-function rule (first row) and the keys are unique anyway.
 RETURN (
-- r407 (F21): the approved description is looked up once per operation (OFFSET 0 keeps
 -- it a single evaluation) instead of once in the result and again in the routing join.
 -- The joined keys are unique (history pkey operation_id; ai_routing pkey
 -- (department, description_hash)), so at most one row, as before.
 SELECT coalesce(h.stage_code,pdc_work_categories_private.stage(r.category),
  public.pdc_department138_station_20260917(d.description))
 FROM public.pdc_pilbara_service_operations o
 CROSS JOIN LATERAL (
  SELECT coalesce(public.pdc_tune_approved_operation_source_20260912(o.operation_id)->>'operation_description',o.operation_description) AS description
  OFFSET 0) d
 LEFT JOIN pdc_bus_private.operation_routing_history_20261015 h ON h.operation_id=o.operation_id
 LEFT JOIN pdc_operation_updates_private.ai_routing_20261019 r ON r.department=btrim(o.department)
  AND r.description_hash=pdc_work_categories_private.import_description_hash_20261017(d.description)
 WHERE o.operation_id=p_operation_id
 LIMIT 1);
END
$f$;

CREATE OR REPLACE FUNCTION public.approve_pdc_new_vehicle_review_446(p_vehicle_id uuid, p_snapshot_hash text, p_assignments jsonb, p_idempotency_key uuid)
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

UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='f7ab4745fb8e97fcd58a209145cfab0f',release='r410',note='Operation station; PL/pgSQL so the plan is kept, approved description looked up once (r407/r410, F21/F26)',updated_at=now() WHERE signature='pdc_bus_private.operation_station(uuid)';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='f4ca4be91871a1de8e8125bbb2c82021',release='r446',note='r446 (F59): New Vehicles approval with Dept 138 review categories (wraps the unchanged approve; one transaction)',updated_at=now() WHERE signature='public.approve_pdc_new_vehicle_review_446(uuid,text,jsonb,uuid)';
DELETE FROM pdc_ops.regression_checks WHERE check_name='dept138_review_routing_459' AND added_in='r459';

DO $d$ BEGIN
 IF EXISTS(SELECT 1 FROM pdc_bus_private.operation_review_station_459) THEN
  ALTER TABLE pdc_bus_private.operation_review_station_459 RENAME TO operation_review_station_459_undone;
  RAISE NOTICE 'r459 undo: reviewer routing stations kept in pdc_bus_private.operation_review_station_459_undone';
 ELSE
  DROP TABLE pdc_bus_private.operation_review_station_459;
 END IF;
END $d$;

DO $p$ BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.approve_pdc_new_vehicle_review_446(uuid,text,jsonb,uuid)'::regprocedure)<>'f4ca4be91871a1de8e8125bbb2c82021'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_bus_private.operation_station(uuid)'::regprocedure)<>'f7ab4745fb8e97fcd58a209145cfab0f' THEN RAISE EXCEPTION 'r459 undo: functions not restored'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r459') OR (SELECT count(*) FROM pdc_ops.expected_function_md5)<>current_setting('r459.pins_before')::bigint
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r459') OR to_regclass('pdc_bus_private.operation_review_station_459') IS NOT NULL THEN RAISE EXCEPTION 'r459 undo: not fully restored'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>current_setting('r459.tick_before') THEN RAISE EXCEPTION 'r459 undo: clock tick changed'; END IF;
END $p$;
