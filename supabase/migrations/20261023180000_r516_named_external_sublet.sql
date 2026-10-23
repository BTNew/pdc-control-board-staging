-- r516 (F130). PREVIEW. Not applied. Do not merge. Do not apply to production.
-- Staging cdsmnqxtyyoeoznmbidd only.
-- Craig Watson (23 Oct, about 3:15 pm AWST): a Navision / import line whose description
-- or operation code contains MMT seat covers, IVMS, RADLINK or reflective stripes
-- is an external Sublet. It is never Fitting, Electrical, Bus or any other workshop station.
-- Whole operation line only. A GP PO item on a different line is not read.
-- Same standing-rule shape as pit inspection / weighbridge (r504). That pit rule is not changed.
-- A line override, a booking, an owner review or a manual lock still wins.
-- Manage sublets is unchanged. No app.js. Karratha 135 is not changed.
DO $g$ BEGIN
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r516: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.suggest(jsonb)'::regprocedure)<>'ee799302c1bdd37bcfba15837859e200'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_operation_updates_private.ensure_required_work_20261019(uuid)'::regprocedure)<>'794492676469d3f4404fbc4e1bb2e08c'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.before_import_rules_20261017(uuid)'::regprocedure)<>'dc2737a6264c179314041fe41845ae87'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.route_import_line_20261017(jsonb,boolean)'::regprocedure)<>'735ba960e92bec6cd9727b425cfe1c83'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_pending_work_category_20260912(jsonb)'::regprocedure)<>'9f4d0f9f2e0b2daf782cedeca19f2b75'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.reviewed_import_choice_139_20261018(jsonb)'::regprocedure)<>'0b6acb19bb9926e93e5addb11b214a26'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_line_is_pit_401(uuid,jsonb)'::regprocedure)<>'7e10e4f66633cf5129c5b2c21aa905e0'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_department138_station_20260917(text)'::regprocedure)<>'9f1cf3370971e3a77f5335632d4f3f8c'
  OR (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='pdc_bus_private' AND p.proname='operation_station' AND md5(p.prosrc)='03e96225dc36891ec0d122aecd87b967')<>1
 THEN RAISE EXCEPTION 'r516: base md5 mismatch (already applied or tip changed)'; END IF;
 IF to_regprocedure('pdc_work_categories_private.named_external_sublet_516(jsonb)') IS NOT NULL
  OR EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=302 OR fault_id='F130' OR check_name='named_external_sublet_516')
 THEN RAISE EXCEPTION 'r516: helper or check slot already taken'; END IF;
END $g$;

CREATE FUNCTION pdc_work_categories_private.named_external_sublet_516(line jsonb)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $r516h$
 -- r516 (F130): whole operation line. description plus operation_code. Not a GP PO item on another line.
 -- MMT.*SEAT COVER(S) is the existing seat-cover pattern. IVMS and RADLINK are whole tokens. REFLECTIVE STRIPES after space collapse, any case.
 SELECT regexp_replace(upper(coalesce(line->>'description','')||' '||coalesce(line->>'operation_code','')),'[[:space:]]+',' ','g')
  ~ 'MMT.*SEAT[ -]?COVERS?|(^|[^A-Z0-9])IVMS([^A-Z0-9]|$)|(^|[^A-Z0-9])RADLINK([^A-Z0-9]|$)|REFLECTIVE STRIPES'
$r516h$;

ALTER FUNCTION pdc_work_categories_private.named_external_sublet_516(jsonb) OWNER TO postgres;
REVOKE ALL ON FUNCTION pdc_work_categories_private.named_external_sublet_516(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION pdc_work_categories_private.named_external_sublet_516(jsonb) TO service_role;

CREATE OR REPLACE FUNCTION pdc_work_categories_private.suggest(line jsonb)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $r516s$
DECLARE d text:=upper(coalesce(line->>'description','')); c text:=upper(regexp_replace(coalesce(line->>'operation_code',''),'[^a-zA-Z0-9]','','g'));
BEGIN
 -- r504 (F117): Craig standing rule — pit inspection / pit and weigh / pit and way / weighbridge / waybridge are ALWAYS Sublet, any department.
 IF d ~ 'PIT[[:space:]]*(INSPECTION|AND[[:space:]]*(WEIGH|WAY))|(WEIGH|WAY)BRIDGE|DEPARTMENT OF TRANSPORT.*INSPECTION' THEN RETURN 'SUBLET'; END IF;
 -- r516 (F130): MMT seat covers, IVMS, RADLINK and reflective stripes are always an external Sublet, any department.
 IF pdc_work_categories_private.named_external_sublet_516(line) THEN RETURN 'SUBLET'; END IF;
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
END $r516s$;

CREATE OR REPLACE FUNCTION pdc_operation_updates_private.ensure_required_work_20261019(p_vehicle_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $r516e$
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
   WHEN pdc_work_categories_private.named_external_sublet_516(l) THEN 'SUBLET'
   WHEN l->>'stage_code' IN('BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA','BUS_PIT') THEN 'BUS_4X4'
   ELSE l->>'stage_code' END
 WHERE l->>'active'='true' AND coalesce(l->>'rejected','false')<>'true'
  AND coalesce(l->>'completed','false')<>'true' AND s.work_key IS NOT NULL
  AND s.code IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET')
 ON CONFLICT(vehicle_id,work_key) DO UPDATE SET required=true,updated_at=clock_timestamp()
 WHERE NOT vehicle_work_items.required AND NOT vehicle_work_items.completed;
 GET DIAGNOSTICS changed=ROW_COUNT;
 RETURN changed;
END $r516e$;

CREATE OR REPLACE FUNCTION pdc_work_categories_private.before_import_rules_20261017(p_vehicle_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $r516b$
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
 WHEN NOT protected_booking AND NOT coalesce(manual_assignment_locked,false) AND pdc_work_categories_private.named_external_sublet_516(l) THEN 'SUBLET'
 WHEN l->>'stage_code'='UNALLOCATED_MAPPING_REVIEW' THEN l->>'stage_code'
 WHEN l->>'stage_code'='BUS_4X4' THEN CASE WHEN suggested LIKE 'BUS_%' AND suggested<>'BUS_PIT' THEN suggested ELSE CASE WHEN protected_booking OR coalesce(manual_assignment_locked,false) THEN 'BUS_MECHANICAL' ELSE suggested END END
 WHEN protected_booking OR coalesce(manual_assignment_locked,false) OR l->>'department' IS DISTINCT FROM '138' THEN l->>'stage_code'
 ELSE suggested END) category FROM projected)
 SELECT coalesce(jsonb_agg(l||jsonb_build_object('work_category',category,'category_version',coalesce(category_version,0),
 'stage_code',pdc_work_categories_private.stage(category),'estimated_hours',hours,
 'zero_hour_task',category='BUS_QA' AND hours=0,
 'category_rule','craig_jobcard_categories_20261015') ORDER BY ord),'[]'::jsonb) FROM chosen
$r516b$;

CREATE OR REPLACE FUNCTION pdc_work_categories_private.route_import_line_20261017(line jsonb, preserve boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog'
AS $r516r$
DECLARE r pdc_operation_updates_private.ai_routing_20261019%rowtype; h numeric;
BEGIN
 IF preserve IS TRUE OR coalesce((line->>'completed')::boolean,false) OR coalesce((line->>'rejected')::boolean,false) OR NOT coalesce((line->>'active')::boolean,true)
 THEN RETURN pdc_work_categories_private.route_before_automatic_20261019(line,preserve); END IF;
 IF pdc_work_categories_private.named_external_sublet_516(line) THEN
  RETURN line||jsonb_build_object('work_category','SUBLET','stage_code','SUBLET','zero_hour_task',false);
 END IF;
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
END $r516r$;

CREATE OR REPLACE FUNCTION public.pdc_pending_work_category_20260912(p_line jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $r516p$
DECLARE base jsonb; estimate jsonb;
BEGIN
 base:=public.pdc_pending_work_category_before_dept138_20260916(p_line);
 IF pdc_work_categories_private.named_external_sublet_516(p_line) THEN base:=base||jsonb_build_object('stage_code','SUBLET','routing_rule','named_external_sublet_516','routing_rule_version','r516'); END IF;
 estimate:=pdc_codex_intake_private.service_catalogue_hours_20260917(p_line||jsonb_build_object('stage_code',base->>'stage_code'));
 IF NOT (base->>'hours_provenance' LIKE 'craig_%' AND coalesce((base->>'estimated_hours')::numeric,0)>0) THEN base:=base||estimate; END IF;
 RETURN base||CASE WHEN btrim(coalesce(p_line->>'department',''))='138' THEN jsonb_build_object('stage_code',public.pdc_department138_station_20260917(p_line->>'description'),'routing_rule',CASE public.pdc_department138_station_20260917(p_line->>'description') WHEN 'TINT' THEN 'dept138_tint_exception' WHEN 'TYRE' THEN 'dept138_tyre_shared' WHEN 'SUBLET' THEN 'named_external_sublet_516' ELSE 'dept138_bus4x4' END) ELSE '{}'::jsonb END;
END $r516p$;

CREATE OR REPLACE FUNCTION pdc_work_categories_private.reviewed_import_choice_139_20261018(p_line jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog'
AS $r516v$
DECLARE base jsonb; category text; hours numeric;
BEGIN
 base:=public.pdc_pending_work_category_20260912(p_line);
 IF pdc_work_categories_private.named_external_sublet_516(p_line) THEN RETURN base; END IF;
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
END $r516v$;

INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note) VALUES
 ('pdc_work_categories_private.named_external_sublet_516(jsonb)','2569698d6be7fc609f3098f1e2a74d1d','r516','MMT seat covers, IVMS, RADLINK, reflective stripes (F130)'),
 ('pdc_work_categories_private.suggest(jsonb)','02e89f950140278c3b919a47c65be43a','r516','Named phrases suggest SUBLET before the department gate (F130)'),
 ('pdc_operation_updates_private.ensure_required_work_20261019(uuid)','1a20c73875de745806973b42128166f2','r516','Named phrases require Sublet work (F130)'),
 ('pdc_work_categories_private.before_import_rules_20261017(uuid)','c6fc3c7a5eae108fe31a8507ac61f1a5','r516','Named phrases beat automatic station, not a person lock (F130)'),
 ('pdc_work_categories_private.route_import_line_20261017(jsonb,boolean)','97268ab179790796309798e085603522','r516','Named phrases are not put back on Electrical or Fitting (F130)'),
 ('public.pdc_pending_work_category_20260912(jsonb)','6e7e09706da0a94e3c994c82f6f23e8e','r516','Pending import lines use the named external sublet rule (F130)'),
 ('pdc_work_categories_private.reviewed_import_choice_139_20261018(jsonb)','0dc6ec6fc4f73793365943a64fa446a2','r516','Dept 139 reviewed import does not force Fitting over the named rule (F130)')
ON CONFLICT (signature) DO UPDATE SET prosrc_md5=excluded.prosrc_md5,release=excluded.release,note=excluded.note,updated_at=now() WHERE true;

INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('named_external_sublet_516','F130','MMT seat covers, IVMS, RADLINK and reflective stripes are an external Sublet (not Fitting or any other station). Plain seat covers, DIVMS and reflective striping are not. Pit / weighbridge is unchanged (r516).',$c516$
SELECT
 pdc_work_categories_private.suggest('{"department":"139","stage_code":"FITTING","description":"MMT Seat Covers"}'::jsonb)='SUBLET'
 AND pdc_work_categories_private.suggest('{"department":"138","description":"MMT SEAT COVERS"}'::jsonb)='SUBLET'
 AND pdc_work_categories_private.suggest('{"department":"138","description":"MMT CLOTH/COMMUTER SEAT COVERS"}'::jsonb)='SUBLET'
 AND pdc_work_categories_private.suggest('{"department":"139","stage_code":"FITTING","description":"Fit Navman IVMS"}'::jsonb)='SUBLET'
 AND pdc_work_categories_private.suggest('{"department":"139","stage_code":"ELECTRICAL","description":"FMG IVMS to be fitted"}'::jsonb)='SUBLET'
 AND pdc_work_categories_private.suggest('{"department":"139","stage_code":"FITTING","description":"reflective stripes"}'::jsonb)='SUBLET'
 AND pdc_work_categories_private.suggest('{"department":"138","description":"Reflective Stripes - Yellow"}'::jsonb)='SUBLET'
 AND pdc_work_categories_private.suggest('{"department":"139","stage_code":"FITTING","description":"REFLECTIVE STRIPES WHITE"}'::jsonb)='SUBLET'
 AND pdc_work_categories_private.suggest('{"department":"139","stage_code":"ELECTRICAL","description":"RADLINK quote"}'::jsonb)='SUBLET'
 AND pdc_work_categories_private.suggest('{"department":"138","description":"Radlink"}'::jsonb)='SUBLET'
 AND pdc_work_categories_private.suggest('{"department":"139","stage_code":"FITTING","description":"Leaf springs","operation_code":"RADLINK"}'::jsonb)='SUBLET'
 AND pdc_work_categories_private.suggest('{"department":"138","description":"Canvas seat covers"}'::jsonb)='BUS_ACCESSORIES'
 AND pdc_work_categories_private.suggest('{"department":"139","stage_code":"FITTING","description":"Canvas seat covers"}'::jsonb)='FITTING'
 AND pdc_work_categories_private.suggest('{"department":"138","description":"DIVMS unit"}'::jsonb) IS DISTINCT FROM 'SUBLET'
 AND pdc_work_categories_private.suggest('{"department":"139","stage_code":"FITTING","description":"reflective striping"}'::jsonb)='FITTING'
 AND pdc_work_categories_private.suggest('{"department":"139","stage_code":"FITTING","description":"PIT AND WEIGH"}'::jsonb)='SUBLET'
 AND pdc_work_categories_private.suggest('{"department":"138","description":"weighbridge"}'::jsonb)='SUBLET'
 AND pdc_work_categories_private.named_external_sublet_516('{"description":"mmt seat covers"}'::jsonb)
 AND pdc_work_categories_private.named_external_sublet_516('{"description":"  Reflective   Stripes - Yellow"}'::jsonb)
 AND pdc_work_categories_private.named_external_sublet_516('{"description":"radio quote","operation_code":"radlink"}'::jsonb)
 AND NOT pdc_work_categories_private.named_external_sublet_516('{"description":"Canvas seat covers"}'::jsonb)
 AND NOT pdc_work_categories_private.named_external_sublet_516('{"description":"DIVMS unit"}'::jsonb)
 AND NOT pdc_work_categories_private.named_external_sublet_516('{"description":"reflective striping"}'::jsonb)
 AND NOT pdc_work_categories_private.named_external_sublet_516('{"description":"Leaf springs","operation_code":"SPRING","po_details":"IVMS"}'::jsonb)
 AND pdc_work_categories_private.route_import_line_20261017('{"department":"139","description":"Fit Navman IVMS","stage_code":"FITTING","active":true,"estimated_hours":1}'::jsonb,false)->>'work_category'='SUBLET'
 AND pdc_work_categories_private.route_import_line_20261017('{"department":"139","description":"Fit Navman IVMS","stage_code":"FITTING","active":true,"estimated_hours":1}'::jsonb,false)->>'stage_code'='SUBLET'
 AND pdc_work_categories_private.route_import_line_20261017('{"department":"139","description":"Canvas seat covers r516 negative","stage_code":"FITTING","active":true,"estimated_hours":1}'::jsonb,false)->>'stage_code'='FITTING'
 AND public.pdc_pending_work_category_20260912('{"department":"139","stage_code":"FITTING","description":"MMT Seat Covers"}'::jsonb)->>'stage_code'='SUBLET'
 AND public.pdc_pending_work_category_20260912('{"department":"139","stage_code":"ELECTRICAL","description":"Fit Navman IVMS"}'::jsonb)->>'stage_code'='SUBLET'
 AND public.pdc_pending_work_category_20260912('{"department":"139","stage_code":"FITTING","description":"reflective stripes"}'::jsonb)->>'stage_code'='SUBLET'
 AND public.pdc_pending_work_category_20260912('{"department":"139","stage_code":"ELECTRICAL","description":"RADLINK quote"}'::jsonb)->>'stage_code'='SUBLET'
 AND public.pdc_pending_work_category_20260912('{"department":"138","description":"MMT SEAT COVERS"}'::jsonb)->>'stage_code'='SUBLET'
 AND public.pdc_pending_work_category_20260912('{"department":"138","description":"Reflective Stripes - Yellow"}'::jsonb)->>'routing_rule'='named_external_sublet_516'
 AND public.pdc_pending_work_category_20260912('{"department":"138","description":"Canvas seat covers"}'::jsonb)->>'stage_code' IS DISTINCT FROM 'SUBLET'
 AND pdc_work_categories_private.reviewed_import_choice_139_20261018('{"department":"139","stage_code":"FITTING","description":"REFLECTIVE STRIPES"}'::jsonb)->>'stage_code'='SUBLET'
 AND pdc_work_categories_private.reviewed_import_choice_139_20261018('{"department":"139","stage_code":"ELECTRICAL","description":"IVMS"}'::jsonb)->>'stage_code'='SUBLET'
 AND (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_line_is_pit_401(uuid,jsonb)'::regprocedure)='7e10e4f66633cf5129c5b2c21aa905e0'
 AND (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.named_external_sublet_516(jsonb)'::regprocedure)='2569698d6be7fc609f3098f1e2a74d1d'
 AND (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.suggest(jsonb)'::regprocedure)='02e89f950140278c3b919a47c65be43a'
 AND (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_operation_updates_private.ensure_required_work_20261019(uuid)'::regprocedure)='1a20c73875de745806973b42128166f2'
 AND (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.before_import_rules_20261017(uuid)'::regprocedure)='c6fc3c7a5eae108fe31a8507ac61f1a5'
 AND (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.route_import_line_20261017(jsonb,boolean)'::regprocedure)='97268ab179790796309798e085603522'
 AND (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_pending_work_category_20260912(jsonb)'::regprocedure)='6e7e09706da0a94e3c994c82f6f23e8e'
 AND (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.reviewed_import_choice_139_20261018(jsonb)'::regprocedure)='0dc6ec6fc4f73793365943a64fa446a2'
 AND position('named_external_sublet_516' in s)>position('PIT[[:space:]]' in s)
 AND position('named_external_sublet_516' in s)<position('IS DISTINCT FROM ''138''' in s)
 AND position('pdc_line_is_pit_401' in e)<position('named_external_sublet_516' in e)
 AND position('named_external_sublet_516' in b)<position('UNALLOCATED_MAPPING_REVIEW' in b)
 AND position('named_external_sublet_516' in r)<position('SELECT * INTO r FROM pdc_operation_updates_private.ai_routing_20261019' in r)
 AND position('named_external_sublet_516(p_line)' in p)<position('service_catalogue_hours' in p)
 AND position('WHEN ''SUBLET'' THEN ''named_external_sublet_516''' in p)>0
 AND position('named_external_sublet_516' in v)<position('import_rules_139' in v)
 AND position('po_details' in h)=0
 AND (
  SELECT count(*) FROM public.pdc_pilbara_service_operations o
  WHERE pdc_work_categories_private.named_external_sublet_516(jsonb_build_object('description',o.operation_description,'operation_code',o.operation_code))
    AND (
      pdc_work_categories_private.suggest(jsonb_build_object('description',o.operation_description,'operation_code',o.operation_code,'department','139','stage_code','FITTING')) IS DISTINCT FROM 'SUBLET'
      OR pdc_work_categories_private.suggest(jsonb_build_object('description',o.operation_description,'operation_code',o.operation_code,'department','138')) IS DISTINCT FROM 'SUBLET'
    )
 )=0
 AS ok,
 'named external sublet samples, pit unchanged, stored lines suggest SUBLET'::text AS detail
FROM (SELECT prosrc AS s FROM pg_proc WHERE oid='pdc_work_categories_private.suggest(jsonb)'::regprocedure) sx
, (SELECT prosrc AS e FROM pg_proc WHERE oid='pdc_operation_updates_private.ensure_required_work_20261019(uuid)'::regprocedure) ex
, (SELECT prosrc AS b FROM pg_proc WHERE oid='pdc_work_categories_private.before_import_rules_20261017(uuid)'::regprocedure) bx
, (SELECT prosrc AS r FROM pg_proc WHERE oid='pdc_work_categories_private.route_import_line_20261017(jsonb,boolean)'::regprocedure) rx
, (SELECT prosrc AS p FROM pg_proc WHERE oid='public.pdc_pending_work_category_20260912(jsonb)'::regprocedure) px
, (SELECT prosrc AS v FROM pg_proc WHERE oid='pdc_work_categories_private.reviewed_import_choice_139_20261018(jsonb)'::regprocedure) vx
, (SELECT prosrc AS h FROM pg_proc WHERE oid='pdc_work_categories_private.named_external_sublet_516(jsonb)'::regprocedure) hx
$c516$,true,302,'r516');

-- Drop cached QC lines for vehicles that have one of these phrases, then reconcile required work.
-- Stored proposed_station is left as imported evidence. The board reads the projection.
DO $bf$
DECLARE ids uuid[];
 vid uuid;
 n integer := 0;
BEGIN
 SELECT coalesce(array_agg(DISTINCT o.vehicle_id), ARRAY[]::uuid[]) INTO ids
 FROM public.pdc_pilbara_service_operations o
 WHERE pdc_work_categories_private.named_external_sublet_516(jsonb_build_object('description', o.operation_description, 'operation_code', o.operation_code));
 PERFORM pdc_work_categories_private.bump_qc_operation_lines_cache_epoch(ids, false);
 DELETE FROM pdc_work_categories_private.qc_operation_lines_cache WHERE vehicle_id = ANY(ids);
 FOREACH vid IN ARRAY ids LOOP
  n := n + pdc_operation_updates_private.ensure_required_work_20261019(vid);
 END LOOP;
 RAISE NOTICE 'r516: % vehicles cache-invalidated, ensure_required_work changes %', cardinality(ids), n;
END
$bf$;

DO $p$ DECLARE r record; BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.named_external_sublet_516(jsonb)'::regprocedure)<>'2569698d6be7fc609f3098f1e2a74d1d'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.suggest(jsonb)'::regprocedure)<>'02e89f950140278c3b919a47c65be43a'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_operation_updates_private.ensure_required_work_20261019(uuid)'::regprocedure)<>'1a20c73875de745806973b42128166f2'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.before_import_rules_20261017(uuid)'::regprocedure)<>'c6fc3c7a5eae108fe31a8507ac61f1a5'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.route_import_line_20261017(jsonb,boolean)'::regprocedure)<>'97268ab179790796309798e085603522'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_pending_work_category_20260912(jsonb)'::regprocedure)<>'6e7e09706da0a94e3c994c82f6f23e8e'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.reviewed_import_choice_139_20261018(jsonb)'::regprocedure)<>'0dc6ec6fc4f73793365943a64fa446a2'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_line_is_pit_401(uuid,jsonb)'::regprocedure)<>'7e10e4f66633cf5129c5b2c21aa905e0'
 THEN RAISE EXCEPTION 'r516: new md5 mismatch'; END IF;
 PERFORM set_config('request.jwt.claims','',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='named_external_sublet_516') INTO r;
 IF NOT r.ok THEN RAISE EXCEPTION 'r516: named_external_sublet_516 failed: %', r.detail; END IF;
END $p$;
