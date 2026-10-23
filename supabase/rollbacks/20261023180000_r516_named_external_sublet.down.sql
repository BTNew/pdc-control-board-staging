-- r516 (F130) rollback. PREVIEW. Not applied.
-- Restores the six function bodies from before this release and drops the helper.
-- Does not delete vehicle_work_items rows the apply path inserted.
-- Staging cdsmnqxtyyoeoznmbidd only. Do not apply to production.
DO $g$ BEGIN
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r516 down: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.suggest(jsonb)'::regprocedure)<>'02e89f950140278c3b919a47c65be43a'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.named_external_sublet_516(jsonb)'::regprocedure)<>'2569698d6be7fc609f3098f1e2a74d1d'
 THEN RAISE EXCEPTION 'r516 down: not the r516 bodies'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION pdc_work_categories_private.suggest(line jsonb)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $old_suggest$
DECLARE d text:=upper(coalesce(line->>'description','')); c text:=upper(regexp_replace(coalesce(line->>'operation_code',''),'[^a-zA-Z0-9]','','g'));
BEGIN
 -- r504 (F117): Craig standing rule — pit inspection / pit and weigh / pit and way / weighbridge / waybridge are ALWAYS Sublet, any department.
 IF d ~ 'PIT[[:space:]]*(INSPECTION|AND[[:space:]]*(WEIGH|WAY))|(WEIGH|WAY)BRIDGE|DEPARTMENT OF TRANSPORT.*INSPECTION' THEN RETURN 'SUBLET'; END IF;
 IF line->>'department' IS DISTINCT FROM '138' AND line->>'stage_code' IS DISTINCT FROM 'BUS_4X4'
 THEN RETURN line->>'stage_code'; END IF;
 -- Craig's 15 October source examples take precedence over broad keyword rules.
 IF c IN('BV2DC','BYRNESIGNAGE','MMTMRCANVAS') OR d ~ 'BLACKVUE|BYRNECUT AUSTRALIA MULTI.COLOUR HI.VIS SIGNAGE|MMT MULTIPLE ROW CANVAS|RUSTPROOFING.*BEAMS ENGINEERING' THEN RETURN 'SUBLET'; END IF;
 IF d ~ '\mTINT(ING|S)?\M' AND d !~ 'BONNET[ -]*PROTECT|WEATHER[ -]*(SHIELD|SHEILD)' THEN RETURN 'TINT'; END IF;
 IF c IN('95LTRP','PR4X4CER') OR d ~ 'POST.?REGO.*CERTIFICATION|POST.REGISTRATION.*CERTIFICATION|95 LITRES OF FUEL' THEN RETURN 'BUS_QA'; END IF;
 IF d ~ 'SUPER SINGLE.*(TYRES?|RIMS?).*COASTER|COASTER.*SUPER SINGLE|CONVERSION|BATTERY COMPARTMENT|RELAY BOX PROTECTION|BULL ?BAR|SNORKEL|CLEARANCE POLES|FIRST AID|WHEEL.?CHOCK|SAFETY TRIANGLE|WHEEL.?NUT' OR c IN('BUS4X4C','COASTER4X4BS','COASTER1STAID','41MM') THEN RETURN 'BUS_MECHANICAL'; END IF;
 IF d ~ '\m(TYRES?|TIRES?|RIMS?)\M|WHEEL[ -]*(ALIGNMENT|BALANC(E|ING))' THEN RETURN 'TYRE'; END IF;
 IF c IN('COASTERBIJI','HLHBCOMBO','FMRL','XRS370CSA') OR d ~ 'PRE.DELIVERY|JUMP START|BATTERY ISOLATOR|MINE ?BAR|HEAD.?LAMP|HAND.?BRAKE.*ALARM|DRIVING LIGHT|REVERSE LIGHT|\mRADIO\M|\mUHF\M|AERIAL|ELECTRICAL|WIRING' THEN RETURN 'BUS_ELECTRICAL'; END IF;
 IF d ~ 'ACCESSOR|SEAT COVER|FLOOR MAT|CARGO BARRIER|ROOF RACK' THEN RETURN 'BUS_ACCESSORIES'; END IF;
 RETURN 'BUS_MECHANICAL';
END $old_suggest$;

CREATE OR REPLACE FUNCTION pdc_operation_updates_private.ensure_required_work_20261019(p_vehicle_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $old_ensure$
DECLARE changed integer;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'staging_required'; END IF;
 -- Existing deferred mutation paths explicitly reconcile their accepted changes.
 IF current_setting('pdc.defer_workshop_required_work_reconcile',true)='407' THEN RETURN 0; END IF;
 PERFORM 1 FROM public.vehicles v WHERE v.id=p_vehicle_id AND v.deleted_at IS NULL
  AND v.lifecycle_state='active' AND v.visible_on_board AND v.qc_completed_at IS NULL
  AND upper(coalesce(v.current_location,'')) NOT IN('QC','RFT','COLLECTED','COMPLETED','AT DEALER')
  AND EXISTS(SELECT 1 FROM public.pdc_new_vehicle_reviews r WHERE r.vehicle_id=v.id AND r.status='approved')
  AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=v.id AND o.department IN('138','139')) FOR UPDATE;
 IF NOT FOUND THEN RETURN 0; END IF;
 INSERT INTO public.vehicle_work_items(vehicle_id,work_key,required,completed,notes)
 SELECT DISTINCT p_vehicle_id,s.work_key,true,false,'Required by canonical imported jobcard work'
 FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) l
 JOIN public.workshop_stages s ON s.code=CASE
   -- r504 (F117): Pit lines are always Sublet required work (Craig standing rule).
   WHEN public.pdc_line_is_pit_401(p_vehicle_id,l) THEN 'SUBLET'
   WHEN l->>'stage_code' IN('BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA','BUS_PIT') THEN 'BUS_4X4'
   ELSE l->>'stage_code' END
 WHERE l->>'active'='true' AND coalesce(l->>'rejected','false')<>'true'
  AND coalesce(l->>'completed','false')<>'true' AND s.work_key IS NOT NULL
  AND s.code IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET')
 ON CONFLICT(vehicle_id,work_key) DO UPDATE SET required=true,updated_at=clock_timestamp()
 WHERE NOT vehicle_work_items.required AND NOT vehicle_work_items.completed;
 GET DIAGNOSTICS changed=ROW_COUNT;
 RETURN changed;
END $old_ensure$;

CREATE OR REPLACE FUNCTION pdc_work_categories_private.before_import_rules_20261017(p_vehicle_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $old_before$
 WITH source AS MATERIALIZED(SELECT l,ord FROM jsonb_array_elements(pdc_work_categories_private.base_pdc_qc_operation_lines_379(p_vehicle_id)) WITH ORDINALITY a(l,ord)),
 projected AS MATERIALIZED (SELECT l,ord,o.category override_category,o.version category_version,
   a.adjustment_id,a.manual_assignment_locked,a.stage_code saved_stage,r.category owner_reviewed_category,
   CASE WHEN l->>'department'='138' AND public.pdc_is_pre_delivery_20260910(l->>'description')
     THEN coalesce(a.estimated_hours,op.effective_estimated_hours,(l->>'estimated_hours')::numeric) ELSE (l->>'estimated_hours')::numeric END hours,
   pdc_work_categories_private.suggest(l) suggested,
   (SELECT b.work_category FROM public.workshop_bookings b
     -- r450 (F63): a whole-job booking holds lines of several categories; each line keeps its own category.
     WHERE b.vehicle_id=p_vehicle_id AND b.deleted_at IS NULL AND b.work_category IS NOT NULL AND b.work_category<>'BUS_WHOLE_JOB'
       AND b.status IN('queued','planned','started','stoppage','completed') AND b.work_category_scope ? (l->>'line_identity')
     ORDER BY (b.status<>'completed') DESC,b.created_at DESC LIMIT 1) booked_category,
   EXISTS(SELECT 1 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
     WHERE b.vehicle_id=p_vehicle_id AND b.deleted_at IS NULL AND s.code=l->>'stage_code'
       AND b.status IN('queued','planned','started','stoppage','completed') AND b.work_category IS NULL) protected_booking
 FROM source LEFT JOIN pdc_work_categories_private.line_overrides o ON o.vehicle_id=p_vehicle_id AND o.line_identity=l->>'line_identity'
 LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=p_vehicle_id AND a.line_key=l->>'line_identity'
 LEFT JOIN pdc_work_categories_private.owner_line_reviews r
 ON r.vehicle_id=p_vehicle_id AND r.line_identity=l->>'line_identity'
 AND l->>'department'='138' AND r.source_signature=pdc_work_categories_private.source_signature(l)
 AND r.adjustment_signature=pdc_work_categories_private.adjustment_signature(to_jsonb(a))
 LEFT JOIN public.pdc_pilbara_service_operations op ON op.vehicle_id=p_vehicle_id AND 'source:'||op.operation_id::text=l->>'line_identity'),
 chosen AS (SELECT *,coalesce(override_category,booked_category,owner_reviewed_category,CASE
 WHEN l->>'stage_code'='UNALLOCATED_MAPPING_REVIEW' THEN l->>'stage_code'
 WHEN l->>'stage_code'='BUS_4X4' THEN CASE WHEN suggested LIKE 'BUS_%' AND suggested<>'BUS_PIT' THEN suggested ELSE CASE WHEN protected_booking OR coalesce(manual_assignment_locked,false) THEN 'BUS_MECHANICAL' ELSE suggested END END
 WHEN protected_booking OR coalesce(manual_assignment_locked,false) OR l->>'department' IS DISTINCT FROM '138' THEN l->>'stage_code'
 ELSE suggested END) category FROM projected)
 SELECT coalesce(jsonb_agg(l||jsonb_build_object('work_category',category,'category_version',coalesce(category_version,0),
 'stage_code',pdc_work_categories_private.stage(category),'estimated_hours',hours,
 'zero_hour_task',category='BUS_QA' AND hours=0,
 'category_rule','craig_jobcard_categories_20261015') ORDER BY ord),'[]'::jsonb) FROM chosen
$old_before$;

CREATE OR REPLACE FUNCTION pdc_work_categories_private.route_import_line_20261017(line jsonb, preserve boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog'
AS $old_route$
DECLARE r pdc_operation_updates_private.ai_routing_20261019%rowtype; h numeric;
BEGIN
 IF preserve IS TRUE OR coalesce((line->>'completed')::boolean,false) OR coalesce((line->>'rejected')::boolean,false) OR NOT coalesce((line->>'active')::boolean,true)
 THEN RETURN pdc_work_categories_private.route_before_automatic_20261019(line,preserve); END IF;
 SELECT * INTO r FROM pdc_operation_updates_private.ai_routing_20261019 WHERE department=line->>'department'
 AND description_hash=pdc_work_categories_private.import_description_hash_20261017(line->>'description');
 IF NOT FOUND THEN RETURN pdc_work_categories_private.route_before_automatic_20261019(line,preserve); END IF;
 h:=(line->>'estimated_hours')::numeric;
 -- Apply the same saved fallback used by new-addition acceptance to existing
 -- unresolved work. Source labour and all preservation gates remain authoritative.
 IF (h IS NULL OR h<=0) AND (line->>'stage_code'='UNALLOCATED_MAPPING_REVIEW'
 OR pdc_work_categories_private.route_before_automatic_20261019(line,preserve)->>'stage_code'='UNALLOCATED_MAPPING_REVIEW')
 AND r.category NOT IN('SUBLET','BUS_PIT','BUS_QA','JOB_CARD_NOTES')
 AND r.estimated_hours>0 AND r.estimated_hours<=999.99 THEN
  h:=r.estimated_hours;
  line:=line||jsonb_build_object('estimated_hours',h,'hours_provenance','ai_estimate',
   'estimate_basis',r.rationale);
 END IF;
 IF (h IS NULL OR h<=0) AND r.category NOT IN('SUBLET','BUS_PIT','BUS_QA','JOB_CARD_NOTES')
 THEN RETURN pdc_work_categories_private.route_before_automatic_20261019(line,preserve); END IF;
 RETURN line||jsonb_build_object('work_category',r.category,'stage_code',pdc_work_categories_private.stage(r.category),
 'zero_hour_task',r.category='BUS_QA' AND h=0,'information_only',r.category='JOB_CARD_NOTES');
END $old_route$;

CREATE OR REPLACE FUNCTION public.pdc_pending_work_category_20260912(p_line jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $old_pending$
DECLARE base jsonb; estimate jsonb;
BEGIN
 base:=public.pdc_pending_work_category_before_dept138_20260916(p_line);
 estimate:=pdc_codex_intake_private.service_catalogue_hours_20260917(p_line||jsonb_build_object('stage_code',base->>'stage_code'));
 IF NOT (base->>'hours_provenance' LIKE 'craig_%' AND coalesce((base->>'estimated_hours')::numeric,0)>0) THEN base:=base||estimate; END IF;
 RETURN base||CASE WHEN btrim(coalesce(p_line->>'department',''))='138' THEN jsonb_build_object('stage_code',public.pdc_department138_station_20260917(p_line->>'description'),'routing_rule',CASE public.pdc_department138_station_20260917(p_line->>'description') WHEN 'TINT' THEN 'dept138_tint_exception' WHEN 'TYRE' THEN 'dept138_tyre_shared' ELSE 'dept138_bus4x4' END) ELSE '{}'::jsonb END;
END $old_pending$;

DO $rev$
DECLARE src text;
BEGIN
 src := $old_reviewed$
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
END $old_reviewed$;
 src := replace(src, E'\n', E'\r\n');
 IF md5(src)<>'0b6acb19bb9926e93e5addb11b214a26' THEN RAISE EXCEPTION 'r516 down: reviewed preimage md5 %', md5(src); END IF;
 EXECUTE 'CREATE OR REPLACE FUNCTION pdc_work_categories_private.reviewed_import_choice_139_20261018(p_line jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path TO pg_catalog AS $fn$' || src || '$fn$';
END
$rev$;

DROP FUNCTION pdc_work_categories_private.named_external_sublet_516(jsonb);

UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='ee799302c1bdd37bcfba15837859e200', release='r504', note='Pit phrases suggest SUBLET (F117)', updated_at=now()
 WHERE signature='pdc_work_categories_private.suggest(jsonb)';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='794492676469d3f4404fbc4e1bb2e08c', release='r504', note='Pit lines require Sublet work (F117)', updated_at=now()
 WHERE signature='pdc_operation_updates_private.ensure_required_work_20261019(uuid)';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='dc2737a6264c179314041fe41845ae87', release='r450', note='r450: a whole job never becomes a line category (F63)', updated_at=now()
 WHERE signature='pdc_work_categories_private.before_import_rules_20261017(uuid)';
DELETE FROM pdc_ops.expected_function_md5 WHERE signature IN (
 'pdc_work_categories_private.named_external_sublet_516(jsonb)',
 'pdc_work_categories_private.route_import_line_20261017(jsonb,boolean)',
 'public.pdc_pending_work_category_20260912(jsonb)',
 'pdc_work_categories_private.reviewed_import_choice_139_20261018(jsonb)'
);
DELETE FROM pdc_ops.regression_checks WHERE check_name='named_external_sublet_516' AND fault_id='F130' AND sort_order=302;

DO $bf$
DECLARE ids uuid[];
BEGIN
 SELECT coalesce(array_agg(DISTINCT o.vehicle_id), ARRAY[]::uuid[]) INTO ids
 FROM public.pdc_pilbara_service_operations o
 WHERE regexp_replace(upper(coalesce(o.operation_description,'')||' '||coalesce(o.operation_code,'')),'[[:space:]]+',' ','g')
  ~ 'MMT.*SEAT[ -]?COVERS?|(^|[^A-Z0-9])IVMS([^A-Z0-9]|$)|(^|[^A-Z0-9])RADLINK([^A-Z0-9]|$)|REFLECTIVE STRIPES';
 PERFORM pdc_work_categories_private.bump_qc_operation_lines_cache_epoch(ids, false);
 DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE vehicle_id = ANY(ids);
END
$bf$;

DO $p$ BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.suggest(jsonb)'::regprocedure)<>'ee799302c1bdd37bcfba15837859e200'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_operation_updates_private.ensure_required_work_20261019(uuid)'::regprocedure)<>'794492676469d3f4404fbc4e1bb2e08c'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.before_import_rules_20261017(uuid)'::regprocedure)<>'dc2737a6264c179314041fe41845ae87'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.route_import_line_20261017(jsonb,boolean)'::regprocedure)<>'735ba960e92bec6cd9727b425cfe1c83'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_pending_work_category_20260912(jsonb)'::regprocedure)<>'9f4d0f9f2e0b2daf782cedeca19f2b75'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.reviewed_import_choice_139_20261018(jsonb)'::regprocedure)<>'0b6acb19bb9926e93e5addb11b214a26'
  OR to_regprocedure('pdc_work_categories_private.named_external_sublet_516(jsonb)') IS NOT NULL
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_line_is_pit_401(uuid,jsonb)'::regprocedure)<>'7e10e4f66633cf5129c5b2c21aa905e0'
 THEN RAISE EXCEPTION 'r516 down: restore md5 mismatch'; END IF;
END $p$;
