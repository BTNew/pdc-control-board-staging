-- Owner-approved Department 139 Fitting/Electrical routing. No source text in public rules.
-- Existing line baselines, staff overrides, completed work and booked scopes stay unchanged.
DO $guard$ BEGIN
 IF NOT pdc_codex_intake_private.management_connection() OR NOT public.pdc_monitor_staging_guard()
  OR auth.uid() IS NOT NULL OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 THEN RAISE EXCEPTION 'staging_management_without_user_impersonation_required'; END IF;
 IF md5(replace(pg_get_functiondef('pdc_work_categories_private.route_import_line_20261017(jsonb,boolean)'::regprocedure),chr(13),'')) <> '22a45f28b9fa506b35407a42ff15664b'
 OR md5(replace(pg_get_functiondef('pdc_operation_updates_private.proposal(uuid)'::regprocedure),chr(13),'')) <> '5c22e9ad49cf60de859a92befb08e723'
 OR md5(replace(pg_get_functiondef('public.workshop_vehicle_stage_estimated_hours(uuid,text)'::regprocedure),chr(13),'')) <> 'c17d57c063cd741439b8401732843dd3'
 THEN RAISE EXCEPTION 'reviewed_import_rule_dependencies_changed'; END IF;
END $guard$;
SET LOCAL lock_timeout='5s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
CREATE TABLE pdc_work_categories_private.import_rules_139_20261018(
 description_hash text PRIMARY KEY CHECK(length(description_hash)=32),
 category text NOT NULL CHECK(category IN('FITTING','ELECTRICAL'))
);
ALTER TABLE pdc_work_categories_private.import_rules_139_20261018 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_work_categories_private.import_rules_139_20261018 FROM PUBLIC,anon,authenticated,service_role;
INSERT INTO pdc_work_categories_private.import_rules_139_20261018 VALUES
('014c399ae44deb3336379092f68902b3','FITTING'),
('05314d237a64bec3baf1d9acd1ce595e','FITTING'),
('05ed2a95308c3dd3dd5665e6be206b34','FITTING'),
('069d52525caa6aff49eec0eda9949d2b','FITTING'),
('0ea9f457a8a0d8c6ed83f04d3a513043','FITTING'),
('10cc8d67b1ef76e3ff67a6bc3af8dfa5','FITTING'),
('1187d404e59b2f346dba700935ff4c6d','ELECTRICAL'),
('133397af4c141acba2b30522fbfc20e3','ELECTRICAL'),
('269bb2045180f150e9442632a0ccbf4b','FITTING'),
('29459372f5f358b21d8e2d8e74618f13','FITTING'),
('312bbca239ba174ee2242e8fac847590','ELECTRICAL'),
('387b15b05411366550ca66500c635909','FITTING'),
('3c1334660a38771c9557c528442bfdbe','ELECTRICAL'),
('4274da0a103d447aca4e50b84db310d1','FITTING'),
('468ff9a0f9ceee0c2bf148e5ebfb76e8','FITTING'),
('52dc362298a5fa73aaab9cdbea9d9681','FITTING'),
('54dbf84f6ea9aa516518beb4f2bd742d','FITTING'),
('56ef99312cd4db647e097081d7d62512','FITTING'),
('5b297a6b0585d83c9d81917d09da64f2','ELECTRICAL'),
('5b6544dc655b8c9fe5a0ec22f2fdacc7','FITTING'),
('6184fd07b4bcc5db1921f8e9f013ef9d','FITTING'),
('67d11ecceb3a753e2718fe707d106017','ELECTRICAL'),
('684060604896b5c253084d22a87279ca','FITTING'),
('6ab957c6a14015d91cc895551ab75c49','FITTING'),
('7dc6fd0d340e372536d01b423658c64d','ELECTRICAL'),
('8300a7a78de539bc1371ea53a16187ac','FITTING'),
('87e4768130ceecf4f8db132162ceefd7','ELECTRICAL'),
('934c47916595a846cd9888c4a5d127dc','FITTING'),
('9374a6b1cd2b0997ff43b93e1c939701','ELECTRICAL'),
('96b3d78a3c0fe54dad0fe64d50317c9e','ELECTRICAL'),
('9adccd27998c781299428e8d3604eb5c','FITTING'),
('a22abfc700d29682306aa508675f40bf','FITTING'),
('a5409e95506e6a6b313a43a163bcb86f','FITTING'),
('a72a0fd0bd4b3f116eedc66f7e474aa4','FITTING'),
('a787d2b03f41ff7a50426737e289dec3','ELECTRICAL'),
('aae6866027e88be39aa5a4eea8a57aee','FITTING'),
('ac80769117206b4386f9fc7ffe8fbe9e','FITTING'),
('bc15f0240d051fb68a89a84f4ec0d432','FITTING'),
('c271c57154e1256c372790db1759cb88','FITTING'),
('c76f9be05265146536977c62939827ae','ELECTRICAL'),
('cac0b0b0fc8715768fc8eb22a2dac14a','FITTING'),
('cce6d463f57446a53b0d5bbec57fae67','FITTING'),
('ce880cc98e886b11b0992955e69dfecf','ELECTRICAL'),
('d25a053ed73c31da2f9849a5bd40efd3','ELECTRICAL'),
('d48b9cd48724e2f083a21caf2f45c57f','ELECTRICAL'),
('ede456cf0d45b3dbe9a7b28933970a6b','ELECTRICAL'),
('ef55703d70c19a49151f5089ba391b56','ELECTRICAL'),
('f0f08b487349a5ece236070700ede2e8','ELECTRICAL'),
('f246d0aafbb75a2062dbb6569c1388bb','FITTING'),
('f4c28279ef1f8b0aa25f94adb90ea321','FITTING'),
('ff6d1ccc1f6a5b5fa35c98d2f192ba05','FITTING');

-- Pin all existing Department139 source lines. Applying the separately approved
-- exact-line manifest is a private audited management operation after publication.
CREATE TEMP TABLE dept139_before_routing ON COMMIT DROP AS
 SELECT v.id vehicle_id,public.pdc_qc_operation_lines_379(v.id) lines
 FROM public.vehicles v WHERE EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=v.id AND o.department='139')
 OR EXISTS(SELECT 1 FROM public.pdc_authenticated_email_operation_lines e WHERE e.vehicle_id=v.id);
INSERT INTO pdc_work_categories_private.import_baseline_20261017(vehicle_id,line_identity,source_signature)
 SELECT vehicle_id,l->>'line_identity',pdc_work_categories_private.source_signature(l)
 FROM dept139_before_routing CROSS JOIN LATERAL jsonb_array_elements(lines) l WHERE l->>'department'='139'
 ON CONFLICT(vehicle_id,line_identity) DO UPDATE SET source_signature=excluded.source_signature;
CREATE OR REPLACE FUNCTION pdc_work_categories_private.route_import_line_20261017(line jsonb, preserve boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE category text; hours numeric;
BEGIN
 IF line->>'department'='139' THEN
  IF preserve IS TRUE OR line->>'stage_code' IS DISTINCT FROM 'UNALLOCATED_MAPPING_REVIEW'
   OR NOT coalesce((line->>'active')::boolean,true)
   OR coalesce((line->>'completed')::boolean,false) OR coalesce((line->>'rejected')::boolean,false)
   THEN RETURN line; END IF;
  SELECT r.category INTO category FROM pdc_work_categories_private.import_rules_139_20261018 r
   WHERE r.description_hash=pdc_work_categories_private.import_description_hash_20261017(line->>'description');
  hours:=CASE WHEN jsonb_typeof(line->'estimated_hours')='number' THEN (line->>'estimated_hours')::numeric END;
  IF category IS NULL OR hours IS NULL OR hours<=0 OR hours>999.99 THEN RETURN line; END IF;
  RETURN line||jsonb_build_object('work_category',category,'stage_code',category,'zero_hour_task',false);
 END IF;
 IF preserve IS TRUE OR line->>'department' IS DISTINCT FROM '138'
 OR NOT coalesce((line->>'active')::boolean,true)
 OR coalesce((line->>'completed')::boolean,false)
 OR coalesce((line->>'rejected')::boolean,false)
 THEN RETURN line; END IF;
 SELECT r.category INTO category FROM pdc_work_categories_private.import_rules_20261017 r
 WHERE r.description_hash=pdc_work_categories_private.import_description_hash_20261017(line->>'description');
 -- NULL is either an explicitly held package or an unmatched description.
 category:=coalesce(category,'UNALLOCATED_MAPPING_REVIEW');
 hours:=CASE WHEN jsonb_typeof(line->'estimated_hours')='number' THEN (line->>'estimated_hours')::numeric END;
 -- Do not turn nominal import estimates into internal bay reservations.
 IF category IN('BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA','TINT','TYRE')
 AND (hours IS NULL OR hours<=0.01)
 AND NOT(category='BUS_QA' AND hours=0 AND coalesce((line->>'zero_hour_task')::boolean,false))
 THEN category:='UNALLOCATED_MAPPING_REVIEW'; END IF;
 RETURN line||jsonb_build_object('work_category',category,
  'stage_code',pdc_work_categories_private.stage(category),
  'zero_hour_task',category='BUS_QA' AND hours=0);
END $function$
;
CREATE FUNCTION pdc_work_categories_private.reviewed_import_choice_139_20261018(p_line jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path='pg_catalog' AS $function$
DECLARE base jsonb; category text; hours numeric;
BEGIN
 base:=public.pdc_pending_work_category_20260912(p_line);
 IF p_line->>'department'='139' THEN
  SELECT r.category INTO category FROM pdc_work_categories_private.import_rules_139_20261018 r
   WHERE r.description_hash=pdc_work_categories_private.import_description_hash_20261017(p_line->>'description');
  IF category IS NOT NULL THEN
   hours:=CASE WHEN jsonb_typeof(p_line->'estimated_hours')='number' THEN (p_line->>'estimated_hours')::numeric END;
   RETURN base||jsonb_build_object('stage_code',CASE WHEN hours>0 AND hours<=999.99 THEN category ELSE 'REVIEW' END,
    'estimated_hours',hours,'hours_provenance',coalesce(nullif(p_line->>'hours_provenance',''),'source_explicit'),
    'routing_rule','craig_dept139_reviewed_20261018');
  END IF;
 END IF;
 RETURN base;
END $function$;
REVOKE ALL ON FUNCTION pdc_work_categories_private.reviewed_import_choice_139_20261018(jsonb) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION pdc_operation_updates_private.proposal(p_change_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE q public.pdc_tune_operation_change_reviews%rowtype; p jsonb; choice jsonb; actual jsonb; h numeric; stage text; category text;
BEGIN
 SELECT * INTO q FROM public.pdc_tune_operation_change_reviews WHERE change_id=p_change_id;
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','operation_review_not_found'); END IF;
 p:=q.proposed_source;
 choice:=pdc_work_categories_private.reviewed_import_choice_139_20261018(jsonb_build_object(
  'description',p->>'operation_description','department',p->>'department',
  'stage_code',p->>'proposed_station','estimated_hours',p->'effective_estimated_hours',
  'source_estimated_hours',p->'source_estimated_hours','hours_provenance',p->>'hours_provenance'));
 SELECT l INTO actual FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(q.vehicle_id)) l
 WHERE l->>'line_identity'='source:'||q.source_operation_id;
 stage:=choice->>'stage_code';
 -- Preserve the previously accepted station on existing work. Dept138's shared
 -- Tint exception remains authoritative, including after a description change.
 IF p->>'department'='138' THEN
  stage:=public.pdc_department138_station_20260917(p->>'operation_description');
  choice:=choice||jsonb_build_object('adjustment_stage_code',stage);
  IF actual->>'description'=p->>'operation_description' THEN
   stage:=actual->>'stage_code'; category:=actual->>'work_category';
  END IF;
 ELSIF actual->>'stage_code' IN('FITTING','ELECTRICAL','FABRICATION','HOIST','TINT','TYRE','BUS_4X4','SUBLET')
 THEN stage:=actual->>'stage_code'; END IF;
 h:=public.pdc_standard_operation_hours_20260910(p->>'operation_description',(choice->>'estimated_hours')::numeric);
 IF p->>'department'='139' AND choice->>'routing_rule'='craig_dept139_reviewed_20261018' THEN h:=(choice->>'estimated_hours')::numeric; END IF;
 IF p->>'department'='138' AND p->>'hours_provenance'='source_explicit'
 THEN h:=(p->>'effective_estimated_hours')::numeric; END IF;
 IF p->>'department'='138' AND q.source_operation_id IS NULL THEN
  SELECT r.category INTO category FROM pdc_work_categories_private.import_rules_20261017 r
   WHERE r.description_hash=pdc_work_categories_private.import_description_hash_20261017(p->>'operation_description');
  IF category IS NULL THEN RETURN jsonb_build_object('ok',false,'code','station_needs_review','proposal',choice); END IF;
  choice:=choice||jsonb_build_object('work_category',category);
  stage:=pdc_work_categories_private.stage(category);
  IF pdc_work_categories_private.route_import_line_20261017(jsonb_build_object(
    'department','138','description',p->>'operation_description','estimated_hours',h,'active',true,
    'zero_hour_task',category='BUS_QA' AND h=0),false)->>'work_category'='UNALLOCATED_MAPPING_REVIEW'
  THEN RETURN jsonb_build_object('ok',false,'code','estimated_hours_required','proposal',choice); END IF;
 END IF;

 -- A metadata-only update must not replace a saved estimate with source zero.
 IF actual IS NOT NULL AND q.before_source->'source_estimated_hours' IS NOT DISTINCT FROM p->'source_estimated_hours'
  AND q.before_source->>'operation_description' IS NOT DISTINCT FROM p->>'operation_description'
 THEN h:=(actual->>'estimated_hours')::numeric; choice:=choice||jsonb_build_object('hours_provenance','retained_accepted_estimate'); END IF;
 IF stage IS NULL OR (stage NOT IN('FITTING','ELECTRICAL','FABRICATION','HOIST','TINT','TYRE','BUS_4X4','SUBLET') AND NOT coalesce(stage='PIT_INSPECTION' AND category='BUS_PIT',false))
 THEN RETURN jsonb_build_object('ok',false,'code','station_needs_review','proposal',choice); END IF;
 IF choice->>'hours_provenance'='conflicting_description_times'
 THEN RETURN jsonb_build_object('ok',false,'code','conflicting_description_times','proposal',choice); END IF;
 IF stage<>'SUBLET' AND NOT coalesce(category='BUS_QA' AND h=0,false) AND (h IS NULL OR h<=0 OR h>999.99 OR mod(h,0.01)<>0)
 THEN RETURN jsonb_build_object('ok',false,'code','estimated_hours_required','proposal',choice); END IF;
 RETURN choice||jsonb_build_object('ok',true,'stage_code',stage,'estimated_hours',coalesce(h,0));
END $function$
;
CREATE OR REPLACE FUNCTION public.workshop_vehicle_stage_estimated_hours(p_vehicle_id uuid, p_stage_code text)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE lines jsonb; result numeric; stage text:=public.workshop_canonical_stage_code(p_stage_code);
BEGIN
 IF coalesce((public.pdc_qc_rework_scope_20260909(p_vehicle_id)->>'active')::boolean,false)
 THEN RETURN pdc_work_categories_private.base_workshop_vehicle_stage_estimated_hours(p_vehicle_id,p_stage_code); END IF;
 lines:=public.pdc_qc_operation_lines_379(p_vehicle_id);
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(lines) l WHERE l->>'department' IN('138','139'))
 AND NOT EXISTS(SELECT 1 FROM pdc_work_categories_private.line_overrides WHERE vehicle_id=p_vehicle_id)
 THEN RETURN pdc_work_categories_private.base_workshop_vehicle_stage_estimated_hours(p_vehicle_id,p_stage_code); END IF;
 SELECT CASE WHEN count(*) FILTER(WHERE jsonb_typeof(l->'estimated_hours') IS DISTINCT FROM 'number')=0
 THEN nullif(sum((l->>'estimated_hours')::numeric),0) END INTO result
 FROM jsonb_array_elements(lines) l WHERE coalesce((l->>'active')::boolean,true) AND l->>'stage_code'=stage
 AND NOT pdc_work_categories_private.line_completed(p_vehicle_id,l);
 RETURN result;
END $function$
;

DO $verify$ BEGIN
 IF EXISTS(SELECT 1 FROM dept139_before_routing b WHERE b.lines IS DISTINCT FROM public.pdc_qc_operation_lines_379(b.vehicle_id))
 THEN RAISE EXCEPTION 'existing_operations_changed_by_future_rules'; END IF;
END $verify$;
