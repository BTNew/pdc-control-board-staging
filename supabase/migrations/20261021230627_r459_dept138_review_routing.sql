-- r459 (F72, bug fix to r446 / F59; reported via Kajel from Bhavesh 22 Oct): Dept 138 New Vehicles approval follows the
-- reviewer's chosen station. Staging cdsmnqxtyyoeoznmbidd only.
-- Root cause (verified on staging 22 Oct 06:55 AWST): approve_pdc_new_vehicle_review_446 ignored the reviewer's pick for the
-- routing station and used pdc_bus_private.operation_station (the saved import routing), accepting only BUS_4X4 / TINT / TYRE /
-- SUBLET. The reported Coaster's line 2 'ENGINEERING CERTIFICATION, PIT INSPECTION, WEIGHBRIDGE & MODIFICATION PERMIT' routes to
-- PIT_INSPECTION, so every approval of it returned dept138_station_needs_review whatever the reviewer picked (Sublet), while
-- the review page's Needs Review count (category rule) showed 0. The Dept 138 route trigger also pins the saved stage to
-- operation_station, so the pick could not be saved even if the approve function had used it.
-- Fix:
-- (1) New private table pdc_bus_private.operation_review_station_459: the station the reviewer chose, one row per Dept 138
--     operation, written only by approve_pdc_new_vehicle_review_446 inside the approval transaction.
-- (2) pdc_bus_private.operation_station reads that row first (coalesce), so the route trigger, the planners and later edits
--     follow the reviewer. Operations without a row route exactly as before (no existing job changes).
-- (3) approve_pdc_new_vehicle_review_446: any of the 8 stations approves; routing station = Mechanical / Accessories /
--     Electrical / QA / Pit - external -> BUS_4X4 card (Pit - external has no bay; category BUS_PIT = Pit planner), Tint,
--     Tyre, Sublet as chosen. The only Dept 138 station rule is the 8 categories, the same rule as the Needs Review count.
--     A refused or failed approval rolls the routing record back. The base approve_pdc_new_vehicle_review is unchanged.
-- Pins: both changed functions (r459). Check dept138_review_routing_459 (F72, sort 258).
-- Not touched: the base approve, the route trigger, imports, bookings, bays, hours, the clock tick, Karratha 135, Dept 139,
-- existing jobs (no rows are written by this migration; the table starts empty).
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r459: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r459: staging only'; END IF;
 -- The clock tick is not touched: its body is recorded here and must be identical at the end (r452 / F65 changed it on 22 Oct 07:01 AWST).
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure) NOT IN('0aaaa15690ca286ed0db87fc72271d5a','84af7607bfd0ce9907c89bae8644d5b6') THEN RAISE EXCEPTION 'r459: clock tick is not a reviewed version'; END IF;
 PERFORM set_config('r459.tick_before',(SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure),true);
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r459: fault_regression_check changed'; END IF;
 IF (SELECT md5(replace(prosrc,chr(13),'')) FROM pg_proc WHERE oid='public.approve_pdc_new_vehicle_review(uuid,text,jsonb,uuid)'::regprocedure)<>'f099baf746f35b500389749ac844bc2f'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_new_vehicle_review_row(uuid)'::regprocedure)<>'200a8508a213613fbbddaecf166ce023'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_require_department138_bus_20260916()'::regprocedure)<>'541414352f5a4f83ee44112f302da62b'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.stage(text)'::regprocedure) IS NULL THEN RAISE EXCEPTION 'r459: approval dependencies are not the reviewed versions'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.approve_pdc_new_vehicle_review_446(uuid,text,jsonb,uuid)'::regprocedure)<>'f4ca4be91871a1de8e8125bbb2c82021'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_bus_private.operation_station(uuid)'::regprocedure)<>'f7ab4745fb8e97fcd58a209145cfab0f' THEN RAISE EXCEPTION 'r459: functions are not the r446 / r410 versions'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE (signature='public.approve_pdc_new_vehicle_review_446(uuid,text,jsonb,uuid)' AND prosrc_md5='f4ca4be91871a1de8e8125bbb2c82021' AND release='r446')
    OR (signature='pdc_bus_private.operation_station(uuid)' AND prosrc_md5='f7ab4745fb8e97fcd58a209145cfab0f' AND release='r410'))<>2 THEN RAISE EXCEPTION 'r459: pins unexpected'; END IF;
 IF to_regclass('pdc_bus_private.operation_review_station_459') IS NOT NULL
    OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r459')
    OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='dept138_review_routing_459' OR added_in='r459' OR fault_id='F72') THEN RAISE EXCEPTION 'r459: already applied (or F72 taken)'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=258) THEN RAISE EXCEPTION 'r459: sort_order 258 taken'; END IF;
 PERFORM set_config('r459.pins_before',(SELECT count(*) FROM pdc_ops.expected_function_md5)::text,true);
END $g$;

CREATE TABLE pdc_bus_private.operation_review_station_459(
 operation_id uuid PRIMARY KEY, -- a Dept 138 pdc_pilbara_service_operations row of vehicle_id (checked by the writer and by check dept138_review_routing_459; no FK so creating or dropping this table never locks the operations table)
 vehicle_id uuid NOT NULL,
 stage_code text NOT NULL CHECK (stage_code IN('BUS_4X4','TINT','TYRE','SUBLET')),
 work_category text NOT NULL CHECK (work_category IN('BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA','BUS_PIT','TINT','TYRE','SUBLET')),
 previous_station text,
 approval_key uuid NOT NULL,
 recorded_by uuid NOT NULL,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CONSTRAINT operation_review_station_459_matches_category CHECK (stage_code=CASE WHEN work_category LIKE 'BUS\_%' THEN 'BUS_4X4' ELSE work_category END));
COMMENT ON TABLE pdc_bus_private.operation_review_station_459 IS 'r459 (F72): Dept 138 routing station chosen on the New Vehicles review (approve_pdc_new_vehicle_review_446); read first by pdc_bus_private.operation_station.';
CREATE INDEX operation_review_station_459_vehicle ON pdc_bus_private.operation_review_station_459(vehicle_id);
ALTER TABLE pdc_bus_private.operation_review_station_459 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_bus_private.operation_review_station_459 FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER qc_operation_lines_cache_row AFTER INSERT OR DELETE OR UPDATE ON pdc_bus_private.operation_review_station_459 FOR EACH ROW EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();
CREATE TRIGGER qc_operation_lines_cache_truncate AFTER TRUNCATE ON pdc_bus_private.operation_review_station_459 FOR EACH STATEMENT EXECUTE FUNCTION pdc_work_categories_private.invalidate_qc_operation_lines_cache();

CREATE OR REPLACE FUNCTION pdc_bus_private.operation_station(p_operation_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $f$
BEGIN
 -- r410 (F26): PL/pgSQL so the plan is kept for the session (the SQL form with SET search_path
 -- is never inlined and was planned again on every call). Same query; LIMIT 1 keeps the SQL-function rule (first row) and the keys are unique anyway.
 -- r459 (F72): the station the New Vehicles reviewer chose (operation_review_station_459, one row per operation, written
 -- only by approve_pdc_new_vehicle_review_446) comes first; operations without one route exactly as before.
 RETURN (
-- r407 (F21): the approved description is looked up once per operation (OFFSET 0 keeps
 -- it a single evaluation) instead of once in the result and again in the routing join.
 -- The joined keys are unique (history pkey operation_id; ai_routing pkey
 -- (department, description_hash)), so at most one row, as before.
 SELECT coalesce(rs.stage_code,h.stage_code,pdc_work_categories_private.stage(r.category),
  public.pdc_department138_station_20260917(d.description))
 FROM public.pdc_pilbara_service_operations o
 CROSS JOIN LATERAL (
  SELECT coalesce(public.pdc_tune_approved_operation_source_20260912(o.operation_id)->>'operation_description',o.operation_description) AS description
  OFFSET 0) d
 LEFT JOIN pdc_bus_private.operation_review_station_459 rs ON rs.operation_id=o.operation_id
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
-- r459 (F72): the reviewer's choice drives routing. Each Dept 138 assignment carries work_category (BUS_MECHANICAL /
-- BUS_ACCESSORIES / BUS_ELECTRICAL / BUS_QA / BUS_PIT / TINT / TYRE / SUBLET), any of the 8 stations. Its routing station
-- is derived from that choice (Mechanical / Accessories / Electrical / QA / Pit - external -> BUS_4X4 card, Pit - external
-- has no bay; Tint -> TINT; Tyre -> TYRE; Sublet -> SUBLET) and recorded per operation in
-- pdc_bus_private.operation_review_station_459, which pdc_bus_private.operation_station reads first, so the Dept 138 route
-- trigger, the planners and later edits all follow the reviewer. The saved import routing station (e.g. PIT_INSPECTION) no
-- longer blocks approval. The only Dept 138 station rule is "one of the 8 categories" - the same rule the review page uses
-- for its Needs Review count. Dept 139 and other lines carry no category and are passed through unchanged. The unchanged
-- approve_pdc_new_vehicle_review does the approval; this function then records the chosen categories
-- (pdc_work_categories_private.line_overrides, as the vehicle drop-down does) in the SAME transaction and reads them back.
-- Any refusal or failure after the routing record rolls the routing record back too.
-- Never books, never moves the vehicle, never changes hours, never touches the clock tick.
DECLARE stg text; stages jsonb:='{}'::jsonb; before_row jsonb; after_row jsonb; approved jsonb; x jsonb; l jsonb; cat text; cur text; n integer:=0;
 v_version integer; plain jsonb:='[]'::jsonb; wanted jsonb:='{}'::jsonb; old_o pdc_work_categories_private.line_overrides%rowtype;
 routes jsonb:='{}'::jsonb; op uuid; old_station text; v_hash text; r_written integer:=0;
 allowed constant text[]:=ARRAY['BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA','BUS_PIT','TINT','TYRE','SUBLET'];
BEGIN
 IF p_vehicle_id IS NULL OR p_snapshot_hash IS NULL OR p_idempotency_key IS NULL OR jsonb_typeof(p_assignments) IS DISTINCT FROM 'array'
 THEN RETURN jsonb_build_object('ok',false,'code','invalid_approval'); END IF;
 IF auth.uid() IS NULL THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
 -- Replay of an approval this user already made with this key: the review row has moved on (stages and hours now follow the
 -- recorded categories), so answer from the current state instead of rebuilding the original request.
 IF EXISTS(SELECT 1 FROM public.pdc_new_vehicle_reviews r WHERE r.vehicle_id=p_vehicle_id AND r.status='approved'
   AND r.approval_key=p_idempotency_key AND r.approved_by=auth.uid()) THEN
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
 IF before_row->>'snapshot_hash' IS DISTINCT FROM p_snapshot_hash THEN RETURN jsonb_build_object('ok',false,'code','review_changed'); END IF;
 FOR x IN SELECT a FROM jsonb_array_elements(p_assignments) a LOOP
  IF jsonb_typeof(x) IS DISTINCT FROM 'object' THEN RETURN jsonb_build_object('ok',false,'code','all_operations_need_stations'); END IF;
  SELECT o INTO l FROM jsonb_array_elements(before_row->'operations') o WHERE o->>'line_identity'=x->>'line_identity' LIMIT 1;
  IF l IS NULL THEN RETURN jsonb_build_object('ok',false,'code','all_operations_need_stations'); END IF;
  IF btrim(coalesce(l->>'department',''))='138' THEN
   cat:=x->>'work_category';
   -- The one Dept 138 station rule (same as the review page's Needs Review count): one of the 8 categories.
   IF cat IS NULL OR NOT cat=ANY(allowed) THEN RETURN jsonb_build_object('ok',false,'code','dept138_category_required','line_identity',x->>'line_identity'); END IF;
   -- Routing station from the reviewer's choice; Pit - external has no bay and sits on the Bus 4x4 card (category BUS_PIT
   -- puts it on the Pit planner). The client's stage_code for Dept 138 lines is replaced here.
   stg:=CASE WHEN cat LIKE 'BUS\_%' THEN 'BUS_4X4' ELSE cat END;
   x:=jsonb_set(x,'{stage_code}',to_jsonb(stg));
   IF l->>'line_identity' ~ '^source:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.operation_id=substr(l->>'line_identity',8)::uuid
       AND o.vehicle_id=p_vehicle_id AND btrim(o.department)='138') THEN
    routes:=routes||jsonb_build_object(substr(l->>'line_identity',8),jsonb_build_object('stage_code',stg,'work_category',cat));
   END IF;
   wanted:=wanted||jsonb_build_object(x->>'line_identity',cat);
   stages:=stages||jsonb_build_object(x->>'line_identity',stg);
  ELSIF x ? 'work_category' THEN RETURN jsonb_build_object('ok',false,'code','category_only_for_dept138','line_identity',x->>'line_identity');
  END IF;
  plain:=plain||jsonb_build_array(x-'work_category');
 END LOOP;
 BEGIN
  -- Record the reviewer's routing station first, so the Dept 138 route trigger accepts the chosen stage.
  FOR op, l IN SELECT key::uuid, value FROM jsonb_each(routes) LOOP
   old_station:=pdc_bus_private.operation_station(op);
   INSERT INTO pdc_bus_private.operation_review_station_459(operation_id,vehicle_id,stage_code,work_category,previous_station,approval_key,recorded_by)
   VALUES(op,p_vehicle_id,l->>'stage_code',l->>'work_category',old_station,p_idempotency_key,auth.uid())
   ON CONFLICT(operation_id) DO UPDATE SET stage_code=excluded.stage_code,work_category=excluded.work_category,
    previous_station=excluded.previous_station,approval_key=excluded.approval_key,recorded_by=excluded.recorded_by,recorded_at=clock_timestamp()
   WHERE operation_review_station_459.operation_id=excluded.operation_id;
   IF old_station IS DISTINCT FROM l->>'stage_code' THEN r_written:=r_written+1; END IF;
  END LOOP;
  -- The routing record can change the projected review row (stage-based estimates); the reviewer approved the snapshot
  -- checked above, so the base approval is given the current one.
  v_hash:=CASE WHEN routes='{}'::jsonb THEN p_snapshot_hash ELSE public.pdc_new_vehicle_review_row(p_vehicle_id)->>'snapshot_hash' END;
  approved:=public.approve_pdc_new_vehicle_review(p_vehicle_id,v_hash,plain,p_idempotency_key);
  IF approved->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'approval_refused' USING errcode='PDI59'; END IF;
  IF coalesce((approved->>'replay')::boolean,false) THEN approved:=jsonb_build_object('ok',false,'code','idempotency_payload_mismatch'); RAISE EXCEPTION 'replay' USING errcode='PDI59'; END IF;
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
    jsonb_build_object('source','r446_new_vehicle_review_approval','idempotency_key',p_idempotency_key,'source_hours_preserved',true,
     'routing_station',stages->>(l->>'line_identity'),'release','r459'));
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
   OR EXISTS(SELECT 1 FROM jsonb_each(routes) r WHERE pdc_bus_private.operation_station(r.key::uuid) IS DISTINCT FROM r.value->>'stage_code')
  THEN RAISE EXCEPTION 'category_readback_mismatch' USING errcode='PDI46'; END IF;
  IF routes<>'{}'::jsonb THEN
   INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
   VALUES('update','pdc_operation_review_station',p_vehicle_id,p_vehicle_id,auth.uid(),public.current_actor_email(),NULL,routes,
    jsonb_build_object('source','r459_review_station','idempotency_key',p_idempotency_key,'routing_changed',r_written));
  END IF;
  SELECT version INTO v_version FROM public.vehicles WHERE id=p_vehicle_id;
  approved:=jsonb_set(jsonb_set(approved,'{data,operations}',after_row->'operations'),'{data,vehicle_version}',to_jsonb(v_version))
   ||jsonb_build_object('categories_written',n,'routing_recorded',jsonb_array_length(coalesce((SELECT jsonb_agg(k) FROM jsonb_object_keys(routes) k),'[]'::jsonb)));
  RETURN approved;
 EXCEPTION WHEN SQLSTATE 'PDI46' THEN
  RETURN jsonb_build_object('ok',false,'code',SQLERRM);
 WHEN SQLSTATE 'PDI59' THEN
  RETURN approved;
 END;
END
$f$;

UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='03e96225dc36891ec0d122aecd87b967',release='r459',note='r459 (F72): reads the New Vehicles reviewer''s station (operation_review_station_459) first (was f7ab4745fb8e97fcd58a209145cfab0f r410)',updated_at=now() WHERE signature='pdc_bus_private.operation_station(uuid)';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='a50e6a6988ae3a106f959e3163b4121c',release='r459',note='r459 (F72): any of the 8 Dept 138 stations approves; the reviewer''s station is recorded and drives routing (was f4ca4be91871a1de8e8125bbb2c82021 r446)',updated_at=now() WHERE signature='public.approve_pdc_new_vehicle_review_446(uuid,text,jsonb,uuid)';

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('dept138_review_routing_459','F72','Dept 138 review routing (r459): approve_pdc_new_vehicle_review_446 accepts any of the 8 review stations (its only Dept 138 station rule, the same as the review page''s Needs Review count), no longer refuses on the saved import routing station, and records the reviewer''s station in the private pdc_bus_private.operation_review_station_459 before the base approval; pdc_bus_private.operation_station reads that record first; every recorded row matches its category, the routing function and the saved line stage; no session is refused',
  $chk$WITH a AS (SELECT p.prosrc,p.prosecdef,p.proconfig,p.oid FROM pg_catalog.pg_proc p WHERE p.oid=to_regprocedure('public.approve_pdc_new_vehicle_review_446(uuid,text,jsonb,uuid)')),
 s AS (SELECT p.prosrc,p.prosecdef,p.proconfig FROM pg_catalog.pg_proc p WHERE p.oid=to_regprocedure('pdc_bus_private.operation_station(uuid)')),
 t AS (SELECT to_regclass('pdc_bus_private.operation_review_station_459') rel),
 rows AS (SELECT rs.*,(SELECT x.stage_code FROM public.vehicle_workshop_line_adjustments x WHERE x.vehicle_id=rs.vehicle_id AND x.line_key='source:'||rs.operation_id::text AND x.active) saved
  FROM pdc_bus_private.operation_review_station_459 rs),
 b AS (SELECT
  (SELECT count(*) FROM a)=1 AND (SELECT bool_and(prosecdef AND proconfig=ARRAY['search_path=pg_catalog']
     AND has_function_privilege('authenticated',oid,'EXECUTE') AND NOT has_function_privilege('anon',oid,'EXECUTE')) FROM a) AS shape,
  -- the approve check's only Dept 138 station rule is the 8 categories (the review page's Needs Review rule); the saved
  -- import routing station no longer refuses a line, and the reviewer's station is recorded before the base approval
  (SELECT bool_and(prosrc ~ $q$allowed constant text\[\]:=ARRAY\['BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA','BUS_PIT','TINT','TYRE','SUBLET'\]$q$
     AND prosrc !~ 'dept138_station_needs_review' AND prosrc !~ 'dept138_sublet_needs_hours'
     AND position('operation_review_station_459' IN prosrc)>0
     AND position('operation_review_station_459' IN prosrc)<position('public.approve_pdc_new_vehicle_review(' IN prosrc)
     AND prosrc !~* '(INSERT INTO|UPDATE|DELETE FROM)\s+public\.(workshop_bookings|vehicle_workshop_line_adjustments|pdc_pilbara_service_operations|pdc_new_vehicle_reviews)\b'
     AND prosrc !~* '(workshop_clock_tick|outbox|net\.http|smtp|send_email|DELETE FROM)') FROM a) AS approve_rule,
  (SELECT bool_and(prosecdef AND prosrc ~ 'coalesce\(rs\.stage_code,h\.stage_code,' AND prosrc ~ 'operation_review_station_459 rs ON rs\.operation_id=o\.operation_id') FROM s) AS routing_reads_choice,
  (SELECT rel IS NOT NULL FROM t) AND (SELECT c.relrowsecurity FROM pg_catalog.pg_class c WHERE c.oid=to_regclass('pdc_bus_private.operation_review_station_459'))
   AND NOT has_table_privilege('anon','pdc_bus_private.operation_review_station_459','SELECT')
   AND NOT has_table_privilege('authenticated','pdc_bus_private.operation_review_station_459','SELECT,INSERT,UPDATE,DELETE') AS table_private,
  NOT EXISTS(SELECT 1 FROM rows WHERE stage_code IS DISTINCT FROM CASE WHEN work_category LIKE 'BUS\_%' THEN 'BUS_4X4' ELSE work_category END
    OR pdc_bus_private.operation_station(operation_id) IS DISTINCT FROM stage_code
    OR (saved IS NOT NULL AND saved IS DISTINCT FROM stage_code)
    OR NOT EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.operation_id=rows.operation_id AND o.vehicle_id=rows.vehicle_id AND btrim(o.department)='138')) AS rows_consistent,
  auth.uid() IS NOT NULL OR (public.approve_pdc_new_vehicle_review_446('00000000-0000-4000-8000-000000000459',repeat('0',64),'[]'::jsonb,'00000000-0000-4000-8000-000000000459')->>'code')='not_authorized' AS no_session_refused)
SELECT b.shape AND b.approve_rule AND b.routing_reads_choice AND b.table_private AND b.rows_consistent AND b.no_session_refused AS ok,
 format('%s reviewer routing station(s) recorded on %s vehicle(s) (r459); shape %s, approve rule %s, routing reads choice %s, table private %s, rows consistent %s, no-session refused %s',
  (SELECT count(*) FROM rows),(SELECT count(DISTINCT vehicle_id) FROM rows),b.shape,b.approve_rule,b.routing_reads_choice,b.table_private,b.rows_consistent,b.no_session_refused) AS detail
FROM b$chk$,true,258,'r459');

DO $p$ DECLARE x record; BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.approve_pdc_new_vehicle_review_446(uuid,text,jsonb,uuid)'::regprocedure)<>'a50e6a6988ae3a106f959e3163b4121c'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_bus_private.operation_station(uuid)'::regprocedure)<>'03e96225dc36891ec0d122aecd87b967' THEN RAISE EXCEPTION 'r459: functions did not land as expected'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r459')<>2 OR (SELECT count(*) FROM pdc_ops.expected_function_md5)<>current_setting('r459.pins_before')::bigint THEN RAISE EXCEPTION 'r459: pins not written'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>current_setting('r459.tick_before') THEN RAISE EXCEPTION 'r459: clock tick changed'; END IF;
 IF NOT ((SELECT proacl::text FROM pg_proc WHERE oid='pdc_bus_private.operation_station(uuid)'::regprocedure)='{postgres=X/postgres}'
    AND has_function_privilege('authenticated','public.approve_pdc_new_vehicle_review_446(uuid,text,jsonb,uuid)','EXECUTE')
    AND NOT has_function_privilege('anon','public.approve_pdc_new_vehicle_review_446(uuid,text,jsonb,uuid)','EXECUTE')) THEN RAISE EXCEPTION 'r459: unexpected function grants'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_bus_private.operation_review_station_459) THEN RAISE EXCEPTION 'r459: table must start empty'; END IF;
 PERFORM set_config('search_path','pg_catalog',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='dept138_review_routing_459') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r459: check failed after apply: %',x.detail; END IF;
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='dept138_review_categories_446') INTO x;
 IF x.ok IS NOT TRUE THEN RAISE EXCEPTION 'r459: r446 check failed after apply: %',x.detail; END IF;
END $p$;
