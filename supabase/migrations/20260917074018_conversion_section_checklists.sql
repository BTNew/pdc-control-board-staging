DO $$ BEGIN IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'staging_only'; END IF; END $$;
CREATE TABLE pdc_fitter_private.conversion_state (
 vehicle_id uuid NOT NULL REFERENCES public.vehicles(id), line_identity text NOT NULL, scope_hash text NOT NULL,
 template_id text NOT NULL, template_version text NOT NULL, sections jsonb NOT NULL DEFAULT '{}', metadata jsonb NOT NULL DEFAULT '{}',
 updated_at timestamptz NOT NULL DEFAULT now(), updated_by uuid NOT NULL REFERENCES auth.users(id),
 PRIMARY KEY(vehicle_id,line_identity,scope_hash)
);
CREATE TABLE pdc_fitter_private.conversion_audit (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, vehicle_id uuid NOT NULL, line_identity text NOT NULL,
 scope_hash text NOT NULL, booking_id uuid NOT NULL, technician_id uuid NOT NULL, actor_id uuid NOT NULL,
 action text NOT NULL, before_state jsonb NOT NULL, after_state jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE pdc_fitter_private.conversion_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE pdc_fitter_private.conversion_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_fitter_private.conversion_state,pdc_fitter_private.conversion_audit FROM PUBLIC,anon,authenticated;
CREATE INDEX conversion_review_model ON pdc_fitter_private.conversion_state(template_id,template_version);
CREATE INDEX conversion_audit_line ON pdc_fitter_private.conversion_audit(vehicle_id,line_identity,created_at);
CREATE FUNCTION pdc_fitter_private.conversion_catalog() RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $catalog$
 SELECT '{"coaster": {"id": "coaster", "model": "Toyota Coaster", "version": "2026-09-17.1", "sections": [{"id": "PA", "label": "Pre-assembly A", "description": "Transfer case and crossmember preparation", "planned_minutes": 120, "preassembly": true, "provisional": false}, {"id": "PB", "label": "Pre-assembly B", "description": "Front differential and K-frame preparation", "planned_minutes": 210, "preassembly": true, "provisional": false}, {"id": "PC", "label": "Pre-assembly C", "description": "Both front hubs and brake rotors", "planned_minutes": 120, "preassembly": true, "provisional": false}, {"id": "1", "label": "Section 1", "description": "Vehicle preparation, hoisting, wheels and driveshaft removal", "planned_minutes": 120, "preassembly": false, "provisional": false}, {"id": "2", "label": "Section 2", "description": "Rear lift: dismantling, springs, axle modification and reassembly", "planned_minutes": 480, "preassembly": false, "provisional": false}, {"id": "3", "label": "Section 3", "description": "Transfer case and crossmember installation", "planned_minutes": 180, "preassembly": false, "provisional": false}, {"id": "4", "label": "Section 4", "description": "Gearbox crossmember replacement", "planned_minutes": 90, "preassembly": false, "provisional": false}, {"id": "5", "label": "Section 5", "description": "Front dismantling and front/rear K-frame installation", "planned_minutes": 450, "preassembly": false, "provisional": false}, {"id": "6", "label": "Section 6", "description": "Driveshaft installation and supports", "planned_minutes": 150, "preassembly": false, "provisional": false}, {"id": "7", "label": "Section 7", "description": "Front suspension, steering, CV shafts, hubs and brakes", "planned_minutes": 705, "preassembly": false, "provisional": false}, {"id": "8", "label": "Section 8", "description": "Front sway bar and bash guard", "planned_minutes": 120, "preassembly": false, "provisional": false}, {"id": "9", "label": "Section 9", "description": "Driver, passenger and emergency exit steps", "planned_minutes": 240, "preassembly": false, "provisional": false}, {"id": "10", "label": "Section 10", "description": "Mudflaps and brackets", "planned_minutes": 120, "preassembly": false, "provisional": false}, {"id": "11", "label": "Section 11", "description": "Electrical harnesses, modules, controls and speed ratio box", "planned_minutes": 480, "preassembly": false, "provisional": false}, {"id": "12", "label": "Section 12", "description": "Completion checks and sign-off \u2014 provisional allowance", "planned_minutes": 180, "preassembly": false, "provisional": true}], "preassembly_minutes": 450, "installation_minutes": 3315, "total_minutes": 3765, "main_technicians": 1, "status": "workshop_planning_allowance", "review_after_comparable_builds": 3, "note": "Owner-supplied main-technician planning allowance; Section 12 scope remains provisional.", "manual_reference": {"title": "Bus 4x4 - Service Manager_Coaster Bus4x4 Complete Build Installation Instruction Manual.pdf", "sha256": "e7d7b5e53d431f87ad9ccc436fee2b66e48f1452f769a05cc1f0fb2a5fd0152a", "pages": 8, "revision": "Not stated in supplied PDF", "completion_checklist": "Not included: Section 12 is listed on page 2, but the document ends after Section 11."}}, "hiace_commuter": {"id": "hiace_commuter", "model": "Toyota HiAce Commuter", "version": "2026-09-17.1", "sections": [{"id": "PA", "label": "Pre-assembly A", "description": "Adaptor housing preparation", "planned_minutes": 60, "preassembly": true, "provisional": false}, {"id": "PB", "label": "Pre-assembly B", "description": "Transfer case preparation", "planned_minutes": 30, "preassembly": true, "provisional": false}, {"id": "PC", "label": "Pre-assembly C", "description": "Both front hubs and stub-axle assemblies", "planned_minutes": 120, "preassembly": true, "provisional": false}, {"id": "PD", "label": "Pre-assembly D", "description": "Differential mounting to K-frame", "planned_minutes": 90, "preassembly": true, "provisional": false}, {"id": "1", "label": "Section 1", "description": "Vehicle preparation: hoist, steering restraint, battery, engine brace, wheels, guards and driveshaft removal", "planned_minutes": 120, "preassembly": false, "provisional": false}, {"id": "2", "label": "Section 2", "description": "Rear lift: axle relocation, welding, differential change and reassembly", "planned_minutes": 360, "preassembly": false, "provisional": false}, {"id": "3", "label": "Section 3", "description": "Extension housing installation and associated modifications", "planned_minutes": 120, "preassembly": false, "provisional": false}, {"id": "4", "label": "Section 4", "description": "Transfer case and crossmember installation", "planned_minutes": 120, "preassembly": false, "provisional": false}, {"id": "5", "label": "Section 5", "description": "Dismantle and prepare front end", "planned_minutes": 180, "preassembly": false, "provisional": false}, {"id": "6", "label": "Section 6", "description": "Steering and K-frame installation", "planned_minutes": 180, "preassembly": false, "provisional": false}, {"id": "7", "label": "Section 7", "description": "Front suspension, CV shafts, hubs, brakes and ABS assembly", "planned_minutes": 240, "preassembly": false, "provisional": false}, {"id": "8", "label": "Section 8", "description": "Driveshaft installation, supports and selector reconnection", "planned_minutes": 90, "preassembly": false, "provisional": false}, {"id": "9", "label": "Section 9", "description": "Breather installation", "planned_minutes": 30, "preassembly": false, "provisional": false}, {"id": "10", "label": "Section 10", "description": "Splash guards, mudflaps and wheel-arch flares", "planned_minutes": 120, "preassembly": false, "provisional": false}, {"id": "11", "label": "Section 11", "description": "Electrical harness installation and rear-light relocation", "planned_minutes": 240, "preassembly": false, "provisional": false}, {"id": "12", "label": "Section 12", "description": "Completion checks and sign-off \u2014 provisional allowance", "planned_minutes": 180, "preassembly": false, "provisional": true}], "preassembly_minutes": 300, "installation_minutes": 1980, "total_minutes": 2280, "main_technicians": 1, "status": "workshop_planning_allowance", "review_after_comparable_builds": 3, "note": "Draft 33-hour installation allocation pending workshop validation. The supplied BUS 4X4 HiAce manual, page 2, expects under 32 hours excluding pre-assembly; crew size and individual stage times are unspecified.", "manual_reference": {"title": "Bus 4x4 - Service Manager HiAce Commuter Bus4x4 Installation Manual.pdf", "sha256": "ed5fa25f054c05a365f0fae597fd0828a5e70834d9c3dd670ac94e9e8b79172e", "pages": 8, "revision": "Not stated in supplied PDF", "completion_checklist": "Not included: Section 12 is listed on page 2, but the document ends after Section 11."}}}'::jsonb;
$catalog$;

CREATE FUNCTION pdc_fitter_private.conversion_model(p_description text,p_vehicle text) RETURNS text
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE d text:=upper(coalesce(p_description,'')); v text:=upper(coalesce(p_vehicle,''));
BEGIN
 -- Only the main conversion operation. Branded accessory descriptions are not conversions.
 IF d !~ '^(COASTER[ -]*(BUS[ -]*)?|BUS[ -]*)?4[ -]*X[ -]*4[ -]+CONVERSION'
  OR d ~ '(TYRES?|TIRES?|RIMS?|BULL[ -]*BAR|SNORKEL|HEADLIGHT|SERVICE|SAFETY CHECK)' THEN RETURN NULL; END IF;
 IF d ~ '(QUOTE|REPAIR|REWORK)' THEN RETURN 'review'; END IF;
 IF v ~ 'COASTER' AND d !~ '(HIACE|COMMUTER|SLWB)' THEN RETURN 'coaster'; END IF;
 IF v ~ 'HI[ -]*ACE' AND v ~ 'COMMUTER' AND d !~ 'COASTER' THEN RETURN 'hiace_commuter'; END IF;
 RETURN 'review';
END $$;

CREATE FUNCTION pdc_fitter_private.conversion_view(p_vehicle uuid,p_line jsonb) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE model text; tpl jsonb; saved pdc_fitter_private.conversion_state; vdesc text; h text; s jsonb; v jsonb;
 rows jsonb:='[]'; remain numeric:=0; actual numeric:=0; done numeric:=0; unknown boolean:=false;
 actual_known boolean:=true; all_done boolean:=true; blockers boolean:=false; risk text; avail numeric; delay numeric; due timestamptz;
 meta jsonb; review_count integer; baseline_avg numeric; current_sections jsonb:='[]';
BEGIN
 SELECT vehicle_description INTO vdesc FROM public.vehicles WHERE id=p_vehicle;
 model:=pdc_fitter_private.conversion_model(p_line->>'description',vdesc);
 IF model IS NULL OR p_line->>'stage_code'<>'BUS_4X4' THEN RETURN NULL; END IF;
 IF model='review' THEN RETURN jsonb_build_object('model','Model / conversion scope needs review','needs_review',true,'complete',false,'risk','Progress update required'); END IF;
 tpl:=pdc_fitter_private.conversion_catalog()->model;
 h:=md5(jsonb_build_array(p_line->>'scope_hash',model,tpl->>'version')::text);
 SELECT * INTO saved FROM pdc_fitter_private.conversion_state WHERE vehicle_id=p_vehicle AND line_identity=p_line->>'line_identity' AND scope_hash=h;
 meta:=coalesce(saved.metadata,'{}');
 FOR s IN SELECT value FROM jsonb_array_elements(tpl->'sections') LOOP
  v:=coalesce(saved.sections->(s->>'id'),'{}');
  v:=jsonb_build_object('status','not_started','actual_minutes',NULL,'remaining_minutes',s->'planned_minutes','blocker','','deferred','')||v;
  IF v->>'status'='complete' THEN done:=done+(s->>'planned_minutes')::numeric; v:=v||'{"remaining_minutes":0}';
  ELSE all_done:=false; END IF;
  IF nullif(v->>'blocker','') IS NOT NULL OR nullif(v->>'deferred','') IS NOT NULL THEN blockers:=true; END IF;
  IF v->>'status'='in_progress' THEN current_sections:=current_sections||jsonb_build_array(s->>'label'); END IF;
  IF v->>'remaining_minutes' IS NULL THEN unknown:=true; ELSE remain:=remain+(v->>'remaining_minutes')::numeric; END IF;
  IF v->>'actual_minutes' IS NULL THEN actual_known:=false; ELSE actual:=actual+(v->>'actual_minutes')::numeric; END IF;
  rows:=rows||jsonb_build_array(s||v);
 END LOOP;
 delay:=nullif(meta->>'delay_remaining_minutes','')::numeric;
 due:=nullif(meta->>'promised_at','')::timestamptz;
 avail:=nullif(meta->>'available_minutes','')::numeric;
 IF avail IS NOT NULL AND meta->>'capacity_as_of' IS NOT NULL THEN
  avail:=greatest(0,avail-pdc_fitter_private.operational_seconds((meta->>'capacity_as_of')::timestamptz,statement_timestamp())/60);
 END IF;
 IF due<statement_timestamp() AND NOT all_done THEN risk:='At risk';
 ELSIF saved.updated_at IS NULL OR saved.updated_at<statement_timestamp()-interval '24 hours' OR unknown OR avail IS NULL OR due IS NULL OR delay IS NULL
 OR (blockers AND delay=0) THEN risk:='Progress update required';
 ELSIF remain+delay>avail THEN risk:='At risk'; ELSE risk:='Within reported capacity'; END IF;
 IF all_done THEN risk:='Conversion sections complete'; END IF;
 SELECT count(*),avg(minutes) INTO review_count,baseline_avg FROM (
  SELECT (SELECT sum((x.value->>'actual_minutes')::numeric) FROM jsonb_each(cs.sections) x) minutes
  FROM pdc_fitter_private.conversion_state cs
  WHERE cs.template_id=model AND cs.template_version=tpl->>'version'
  AND coalesce((cs.metadata->>'comparable')::boolean,true)
  AND (SELECT count(*) FROM jsonb_each(cs.sections))=jsonb_array_length(tpl->'sections') AND NOT EXISTS(SELECT 1 FROM jsonb_each(cs.sections) x WHERE x.value->>'status'<>'complete' OR x.value->>'actual_minutes' IS NULL) AND nullif(cs.metadata->>'checklist_reference','') IS NOT NULL ORDER BY cs.updated_at LIMIT 3
 ) builds;
 RETURN tpl||jsonb_build_object('scope_hash',h,'sections',rows,'metadata',meta,'remaining_minutes',CASE WHEN unknown THEN NULL ELSE remain END,
 'actual_minutes',actual,'actual_complete',actual_known,'completed_planned_minutes',done,'complete',all_done AND NOT blockers AND nullif(meta->>'checklist_reference','') IS NOT NULL,
 'current_sections',current_sections,'risk',risk,'release_blocked',nullif(meta->>'checklist_reference','') IS NULL,
 'comparable_builds',review_count,'first_three_average_minutes',baseline_avg,'allowance_review_due',review_count>=3,'updated_at',saved.updated_at);
END $$;

CREATE FUNCTION pdc_fitter_private.conversion_enrich(p_vehicle uuid,p_line jsonb) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE c jsonb;
BEGIN
 c:=pdc_fitter_private.conversion_view(p_vehicle,p_line);
 IF c IS NULL THEN RETURN p_line; END IF;
 RETURN p_line||jsonb_build_object('conversion',c,'scope_hash',coalesce(c->>'scope_hash',md5((p_line->>'scope_hash')||':model-review')),
 'completed',coalesce((c->>'complete')::boolean,false),
 'completed_fraction',CASE WHEN (c->>'total_minutes')::numeric>0 THEN least(0.99,(c->>'completed_planned_minutes')::numeric/(c->>'total_minutes')::numeric) ELSE 0 END);
END $$;

CREATE FUNCTION pdc_fitter_private.conversion_save(p_tech uuid,p_booking uuid,p_line text,p_change jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE b public.workshop_bookings; l jsonb; c jsonb; sec jsonb; oldstate pdc_fitter_private.conversion_state;
 beforej jsonb; sections jsonb; meta jsonb; valuej jsonb; mode text:=p_change->>'mode'; k text; v numeric;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in required' USING errcode='42501'; END IF;
 PERFORM public.workshop_require_planner_operator();
 IF NOT pdc_fitter_private.assigned(p_booking,p_tech) THEN RETURN jsonb_build_object('ok',false,'error','assignment_changed'); END IF;
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking FOR UPDATE;
 IF b.status<>'started' THEN RETURN jsonb_build_object('ok',false,'error','job_not_running'); END IF;
 SELECT x INTO l FROM jsonb_array_elements(pdc_fitter_private.lines(b.vehicle_id,b.id)) x WHERE x->>'line_identity'=p_line AND x->>'stage_code'='BUS_4X4';
 IF l IS NULL OR l->'conversion' IS NULL OR coalesce((l#>>'{conversion,needs_review}')::boolean,false) THEN RETURN jsonb_build_object('ok',false,'error','conversion_model_review'); END IF;
 c:=l->'conversion';
 SELECT * INTO oldstate FROM pdc_fitter_private.conversion_state WHERE vehicle_id=b.vehicle_id AND line_identity=p_line AND scope_hash=l->>'scope_hash' FOR UPDATE;
 beforej:=coalesce(to_jsonb(oldstate),'{}'); sections:=coalesce(oldstate.sections,'{}'); meta:=coalesce(oldstate.metadata,'{}');
 IF mode='section' THEN
  SELECT x INTO sec FROM jsonb_array_elements(c->'sections') x WHERE x->>'id'=p_change->>'section';
  IF sec IS NULL OR coalesce(p_change->>'status','') NOT IN ('not_started','in_progress','complete') THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
  FOR k IN SELECT unnest(ARRAY['actual_minutes','remaining_minutes']) LOOP
   IF p_change->>k IS NOT NULL THEN
    IF jsonb_typeof(p_change->k)<>'number' THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
    v:=(p_change->>k)::numeric;
    IF v<0 OR v>60000 THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
   END IF;
  END LOOP;
  IF p_change->>'status'='complete' AND (nullif(btrim(p_change->>'deferred'),'') IS NOT NULL OR nullif(btrim(p_change->>'blocker'),'') IS NOT NULL) THEN RETURN jsonb_build_object('ok',false,'error','conversion_deferred'); END IF;
  IF p_change->>'status'='complete' AND sec->>'id'='12' AND nullif(meta->>'checklist_reference','') IS NULL THEN RETURN jsonb_build_object('ok',false,'error','conversion_checklist_required'); END IF;
  IF length(coalesce(p_change->>'note',''))>500 OR length(coalesce(p_change->>'deferred',''))>500 OR length(coalesce(p_change->>'blocker',''))>500 THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
  valuej:=jsonb_build_object('status',p_change->>'status','actual_minutes',p_change->'actual_minutes',
    'remaining_minutes',CASE WHEN p_change->>'status'='complete' THEN '0'::jsonb WHEN p_change->>'status'='not_started' THEN sec->'planned_minutes' ELSE coalesce(p_change->'remaining_minutes','null'::jsonb) END,
    'deferred',btrim(coalesce(p_change->>'deferred','')),'blocker',btrim(coalesce(p_change->>'blocker','')),'note',coalesce(p_change->>'note',''),
    'technician_id',p_tech,'technician',(SELECT name FROM public.workshop_technicians WHERE id=p_tech),'confirmed_by',auth.uid(),'updated_at',clock_timestamp());
  sections:=jsonb_set(sections,ARRAY[sec->>'id'],valuej);
 ELSIF mode='planning' THEN
  -- Cumulative additional time is separate from conversion labour. Delay remaining is prospective, not elapsed waiting.
  FOR k IN SELECT unnest(ARRAY['helper_minutes','parts_delay_minutes','waiting_minutes','repair_minutes','rework_minutes','delay_remaining_minutes','available_minutes']) LOOP
   IF p_change->>k IS NOT NULL THEN
    IF jsonb_typeof(p_change->k)<>'number' THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
    v:=(p_change->>k)::numeric;
    IF v<0 OR v>600000 THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
   END IF;
   meta:=jsonb_set(meta,ARRAY[k],coalesce(p_change->k,'null'::jsonb));
  END LOOP;
  IF p_change->>'promised_at' IS NOT NULL THEN PERFORM (p_change->>'promised_at')::timestamptz; END IF;
  IF length(coalesce(p_change->>'note',''))>500 THEN RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
  meta:=meta||jsonb_build_object('promised_at',p_change->>'promised_at','capacity_as_of',clock_timestamp(),'planning_note',coalesce(p_change->>'note',''),
   'comparable',coalesce((p_change->>'comparable')::boolean,true),'planning_updated_by',auth.uid(),'planning_technician_id',p_tech);
 ELSIF mode='checklist' THEN
  IF coalesce(public.current_pdc_user_role()::text,'') NOT IN ('operator','administrator') THEN RETURN jsonb_build_object('ok',false,'error','conversion_controller_required'); END IF;
  IF length(btrim(coalesce(p_change->>'reference','')))<5 OR length(btrim(coalesce(p_change->>'scope','')))<10 OR length(p_change->>'reference')>500 OR length(p_change->>'scope')>1000 THEN RETURN jsonb_build_object('ok',false,'error','conversion_checklist_required'); END IF;
  IF sections#>>'{12,status}'='complete' THEN RETURN jsonb_build_object('ok',false,'error','conversion_reopen_section'); END IF;
  meta:=meta||jsonb_build_object('checklist_reference',btrim(p_change->>'reference'),'checklist_scope',btrim(p_change->>'scope'),'checklist_confirmed_by',auth.uid(),'checklist_confirmed_at',clock_timestamp());
 ELSE RETURN jsonb_build_object('ok',false,'error','conversion_invalid'); END IF;
 INSERT INTO pdc_fitter_private.conversion_state(vehicle_id,line_identity,scope_hash,template_id,template_version,sections,metadata,updated_by)
 VALUES(b.vehicle_id,p_line,l->>'scope_hash',c->>'id',c->>'version',sections,meta,auth.uid())
 ON CONFLICT(vehicle_id,line_identity,scope_hash) DO UPDATE SET sections=excluded.sections,metadata=excluded.metadata,updated_by=excluded.updated_by,updated_at=clock_timestamp();
 INSERT INTO pdc_fitter_private.conversion_audit(vehicle_id,line_identity,scope_hash,booking_id,technician_id,actor_id,action,before_state,after_state)
 VALUES(b.vehicle_id,p_line,l->>'scope_hash',b.id,p_tech,auth.uid(),mode,beforej,jsonb_build_object('sections',sections,'metadata',meta));
 UPDATE public.workshop_bookings SET version=version+1,updated_by=auth.uid() WHERE id=b.id;
 PERFORM public.workshop_bump_revision();
 RETURN jsonb_build_object('ok',true);
END $$;

-- Completion through controller, bulk completion, imports or old clients must not skip section confirmation.
CREATE FUNCTION pdc_fitter_private.conversion_completion_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE vid uuid; stage text; l jsonb; identity text;
BEGIN
 IF TG_TABLE_NAME='workshop_bookings' THEN
  IF NEW.status<>'completed' OR (TG_OP='UPDATE' AND OLD.status='completed') THEN RETURN NEW; END IF;
  vid:=NEW.vehicle_id; SELECT code INTO stage FROM public.workshop_stages WHERE id=NEW.stage_id;
 ELSIF TG_TABLE_NAME='vehicle_work_items' THEN
  IF NOT NEW.completed OR (TG_OP='UPDATE' AND OLD.completed) THEN RETURN NEW; END IF;
  vid:=NEW.vehicle_id; stage:=CASE WHEN NEW.work_key='bus4x4' THEN 'BUS_4X4' END;
 ELSE
  IF NOT NEW.completed THEN RETURN NEW; END IF;
  SELECT vehicle_id INTO vid FROM public.workshop_bookings WHERE id=NEW.booking_id;
  stage:='BUS_4X4'; identity:=NEW.line_identity;
 END IF;
 IF stage IS DISTINCT FROM 'BUS_4X4' THEN RETURN NEW; END IF;
 FOR l IN SELECT x FROM jsonb_array_elements(pdc_fitter_private.lines(vid,NULL)) x
 WHERE x->'conversion' IS NOT NULL AND (identity IS NULL OR x->>'line_identity'=identity) LOOP
  IF NOT coalesce((l->>'completed')::boolean,false) THEN
   RAISE EXCEPTION '{"error":"conversion_sections_required"}' USING errcode='23514';
  END IF;
 END LOOP;
 RETURN NEW;
END $$;
CREATE TRIGGER conversion_booking_completion BEFORE INSERT OR UPDATE OF status ON public.workshop_bookings FOR EACH ROW EXECUTE FUNCTION pdc_fitter_private.conversion_completion_guard();
CREATE TRIGGER conversion_work_completion BEFORE INSERT OR UPDATE OF completed ON public.vehicle_work_items FOR EACH ROW EXECUTE FUNCTION pdc_fitter_private.conversion_completion_guard();
CREATE TRIGGER conversion_parent_completion BEFORE INSERT OR UPDATE OF completed ON pdc_fitter_private.operation_progress FOR EACH ROW EXECUTE FUNCTION pdc_fitter_private.conversion_completion_guard();

DO $guard$ BEGIN IF md5(pg_get_functiondef('pdc_fitter_private.lines(uuid,uuid)'::regprocedure))<>'646b31fde0ccf9a6fb566fc70cce2428' THEN RAISE EXCEPTION 'Concurrent function change: lines'; END IF; END $guard$;
CREATE OR REPLACE FUNCTION pdc_fitter_private.lines(p_vehicle_id uuid, p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
 WITH source AS (
  SELECT l,md5(jsonb_build_array(l->>'line_identity',l->>'description',
    l->>'stage_code',l->'estimated_hours',l->>'job_card_number')::text) scope_hash
  FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) l
  WHERE coalesce((l->>'active')::boolean,true)
 )
 SELECT coalesce(jsonb_agg(pdc_fitter_private.conversion_enrich(p_vehicle_id,jsonb_build_object(
  'line_identity',s.l->>'line_identity','description',s.l->>'description',
  'stage_code',s.l->>'stage_code','hours',s.l->'estimated_hours',
  'operation_no',s.l->'operation_no','source_note',s.l->>'review_note',
  'scope_hash',s.scope_hash,'completed',coalesce(p.completed AND p.scope_hash=s.scope_hash,false),
  'note',coalesce(p.note,''),'scope_changed',p.scope_hash IS NOT NULL AND p.scope_hash<>s.scope_hash,
  'updated_at',p.updated_at,'technician_id',p.technician_id
 )) ORDER BY s.l->>'stage_code',s.l->>'operation_no',s.l->>'line_identity'),'[]'::jsonb)
 FROM source s LEFT JOIN pdc_fitter_private.operation_progress p
   ON p.booking_id=p_booking_id AND p.line_identity=s.l->>'line_identity'
$function$
;

DO $guard$ BEGIN IF md5(pg_get_functiondef('pdc_fitter_private.summary(jsonb,text)'::regprocedure))<>'91bab6de1ab390020e3a73d62d3e503e' THEN RAISE EXCEPTION 'Concurrent function change: summary'; END IF; END $guard$;
CREATE OR REPLACE FUNCTION pdc_fitter_private.summary(p_lines jsonb, p_stage text)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
 WITH lines AS (
  SELECT l, CASE WHEN jsonb_typeof(l->'hours')='number' THEN (l->>'hours')::numeric END hours
  FROM jsonb_array_elements(p_lines) l WHERE l->>'stage_code'=p_stage
 ), totals AS (
  SELECT count(*) total_lines,count(*) FILTER(WHERE (l->>'completed')::boolean) completed_lines,
   count(*) FILTER(WHERE hours IS NULL OR hours<=0) unknown_hours,
   coalesce(sum(greatest(hours,0)),0) total_hours,
   coalesce(sum(greatest(hours,0)*CASE WHEN (l->>'completed')::boolean THEN 1 ELSE coalesce((l->>'completed_fraction')::numeric,0) END),0) completed_hours FROM lines
 )
 SELECT jsonb_build_object('total_lines',total_lines,'completed_lines',completed_lines,
 'unknown_hours',unknown_hours,'total_hours',total_hours,'completed_hours',completed_hours,
 'percent',CASE WHEN total_hours>0 THEN least(CASE WHEN unknown_hours>0 THEN 99 ELSE 100 END,
 floor(100*completed_hours/total_hours)) ELSE 0 END,
 'can_complete',total_lines>0 AND total_lines=completed_lines AND unknown_hours=0) FROM totals
$function$
;

DO $guard$ BEGIN IF md5(pg_get_functiondef('pdc_fitter_private.progress(uuid)'::regprocedure))<>'5a6323cd37a2c0359e65fef13e5cf008' THEN RAISE EXCEPTION 'Concurrent function change: progress'; END IF; END $guard$;
CREATE OR REPLACE FUNCTION pdc_fitter_private.progress(p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE b public.workshop_bookings; code text;
BEGIN
 -- Avoid rebuilding operation catalogues for the many bookings with no fitter work.
 IF NOT EXISTS(SELECT 1 FROM pdc_fitter_private.operation_progress WHERE booking_id=p_booking_id) AND NOT EXISTS(SELECT 1 FROM pdc_fitter_private.conversion_state cs JOIN public.workshop_bookings cb ON cb.vehicle_id=cs.vehicle_id WHERE cb.id=p_booking_id) THEN RETURN NULL; END IF;
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id;
 SELECT s.code INTO code FROM public.workshop_stages s WHERE s.id=b.stage_id;
 RETURN pdc_fitter_private.summary(pdc_fitter_private.lines(b.vehicle_id,b.id),code);
END $function$
;

DO $guard$ BEGIN IF md5(pg_get_functiondef('public.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)'::regprocedure))<>'8b0d7e1d1828f218fbc98861fc8aa767' THEN RAISE EXCEPTION 'Concurrent function change: fitter_job_command'; END IF; END $guard$;
CREATE OR REPLACE FUNCTION public.fitter_job_command(p_technician_id uuid, p_booking_id uuid, p_expected_version integer, p_catalog_hash text, p_request_id uuid, p_action text, p_line_identity text DEFAULT NULL::text, p_completed boolean DEFAULT NULL::boolean, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE b public.workshop_bookings; d jsonb; l jsonb; r jsonb; h text; receipt record; clock_version integer;
BEGIN
 PERFORM public.workshop_require_planner_operator();
 IF p_request_id IS NULL OR p_expected_version IS NULL
 THEN RAISE EXCEPTION 'Request id and booking version required' USING errcode='22023'; END IF;
 IF p_action IS NULL OR p_action NOT IN('start','line','stop','resume','complete','conversion')
 THEN RAISE EXCEPTION 'Unknown fitter action' USING errcode='22023'; END IF;
 IF length(coalesce(p_note,''))>2000 THEN RAISE EXCEPTION 'Note too long' USING errcode='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 h:=md5(jsonb_build_array(p_technician_id,p_booking_id,p_expected_version,p_catalog_hash,
    p_action,p_line_identity,p_completed,p_note)::text);
 SELECT * INTO receipt FROM pdc_fitter_private.command_receipts WHERE actor_id=auth.uid() AND request_id=p_request_id;
 IF FOUND THEN
   IF receipt.request_hash<>h THEN RETURN jsonb_build_object('ok',false,'error','request_reused'); END IF;
   RETURN receipt.result||jsonb_build_object('replayed',true);
 END IF;
 IF NOT pdc_fitter_private.assigned(p_booking_id,p_technician_id)
 THEN RETURN jsonb_build_object('ok',false,'error','assignment_changed'); END IF;
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id FOR UPDATE;
 PERFORM public.workshop_require_booking_active_vehicle(p_booking_id,false);
 -- Another controller may have started this exact job already. Never start twice.
 IF NOT(p_action='start' AND b.status='started') AND b.version<>p_expected_version
 THEN
   IF p_action='start' THEN
     clock_version:=pdc_fitter_private.clock_start_version(b.id,p_expected_version);
     IF clock_version IS NOT NULL THEN
       d:=public.get_fitter_job(p_technician_id,b.id);
       IF d->>'catalog_hash' IS DISTINCT FROM p_catalog_hash THEN
         RETURN jsonb_build_object('ok',false,'error','scope_changed');
       END IF;
     END IF;
   END IF;
   IF clock_version IS NULL THEN RETURN jsonb_build_object('ok',false,'error','version_conflict'); END IF;
 END IF;
 IF p_action='start' THEN
   IF b.status='started' THEN r:=jsonb_build_object('ok',true,'already_started',true);
   ELSE r:=public.start_workshop_work(b.id,b.version,NULL,jsonb_build_object('source','fitter','technician_id',p_technician_id,'clock_rebased_from_version',CASE WHEN clock_version IS NOT NULL THEN p_expected_version END)); END IF;
 ELSIF p_action='stop' THEN
   IF length(btrim(coalesce(p_note,'')))<3 THEN RETURN jsonb_build_object('ok',false,'error','reason_required'); END IF;
   r:=public.stop_workshop_work(b.id,b.version,p_note,jsonb_build_object('source','fitter','technician_id',p_technician_id));
 ELSIF p_action='resume' THEN
   r:=public.resume_workshop_work(b.id,b.version,jsonb_build_object('source','fitter','technician_id',p_technician_id));
 ELSE
   IF b.status<>'started' THEN RETURN jsonb_build_object('ok',false,'error','job_not_running'); END IF;
   d:=public.get_fitter_job(p_technician_id,b.id);
   IF d->>'catalog_hash' IS DISTINCT FROM p_catalog_hash THEN RETURN jsonb_build_object('ok',false,'error','scope_changed'); END IF;
   IF p_action='conversion' THEN
     r:=pdc_fitter_private.conversion_save(p_technician_id,b.id,p_line_identity,p_note::jsonb);
   ELSIF p_action='complete' THEN
     IF NOT coalesce((d#>>'{progress,can_complete}')::boolean,false)
     THEN RETURN jsonb_build_object('ok',false,'error','items_incomplete'); END IF;
     r:=public.complete_workshop_work(b.id,b.version,NULL,NULL,jsonb_build_object('source','fitter','technician_id',p_technician_id));
   ELSE
     SELECT item INTO l FROM jsonb_array_elements(d->'lines') item
      WHERE item->>'line_identity'=p_line_identity AND item->>'stage_code'=d->>'stage_code';
     IF l IS NULL OR p_completed IS NULL THEN RETURN jsonb_build_object('ok',false,'error','line_unavailable'); END IF;
     IF l->'conversion' IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'error','conversion_sections_required'); END IF;
     INSERT INTO pdc_fitter_private.operation_progress(booking_id,line_identity,scope_hash,completed,note,technician_id,updated_by)
     VALUES(b.id,p_line_identity,l->>'scope_hash',p_completed,coalesce(p_note,''),p_technician_id,auth.uid())
     ON CONFLICT(booking_id,line_identity) DO UPDATE SET scope_hash=excluded.scope_hash,
      completed=excluded.completed,note=excluded.note,technician_id=excluded.technician_id,
      updated_by=excluded.updated_by,updated_at=clock_timestamp();
     -- Canonical booking revision triggers notify existing station and board subscribers.
     UPDATE public.workshop_bookings SET version=version+1,updated_by=auth.uid() WHERE id=b.id;
     PERFORM public.workshop_bump_revision();
     r:=jsonb_build_object('ok',true);
   END IF;
 END IF;
 IF coalesce((r->>'ok')::boolean,false) THEN
   -- A successful response must confirm the booking state read by the planners.
   SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id;
   IF p_action='start' AND (b.status<>'started' OR b.actual_start_at IS NULL) THEN
     RAISE EXCEPTION 'Fitter start did not produce a running booking' USING errcode='23514';
   END IF;
   r:=jsonb_build_object('ok',true,'booking_id',b.id,'action',p_action,
    'already_started',coalesce((r->>'already_started')::boolean,false),
    'status',b.status,'version',b.version,'revision',public.workshop_current_revision(),
    'clock_rebased',clock_version IS NOT NULL,
    'clock_rebased_from_version',CASE WHEN clock_version IS NOT NULL THEN p_expected_version END,
    'start_priority',coalesce((r->>'start_priority')::boolean,false),
    'shifted_count',coalesce((r->>'shifted_count')::integer,0))
    ||pdc_fitter_private.timing(b.id,clock_timestamp());
   INSERT INTO pdc_fitter_private.command_receipts VALUES(auth.uid(),p_request_id,h,r,clock_timestamp());
 END IF;
 -- Explain the exact booking that prevented a start to this authorized operator.
 -- Preserve the canonical rejection; no sequence or fixed work is changed here.
 IF p_action='start' AND NOT coalesce((r->>'ok')::boolean,false)
    AND r#>>'{blocker,booking_id}' IS NOT NULL THEN
   SELECT jsonb_build_object('booking_id',x.id,'stage_code',s.code,'stage_name',s.display_name,
     'bay_number',bay.bay_number,'bay_name',bay.display_name,'status',x.status,
     'start_at',x.scheduled_start_at,'end_at',x.scheduled_end_at)
   INTO d FROM public.workshop_bookings x
    JOIN public.workshop_stages s ON s.id=x.stage_id
    LEFT JOIN public.workshop_bays bay ON bay.id=x.bay_id
   WHERE x.id=(r#>>'{blocker,booking_id}')::uuid AND x.deleted_at IS NULL;
   IF d IS NOT NULL THEN r:=jsonb_set(r,'{blocker}',coalesce(r->'blocker','{}'::jsonb)||d); END IF;
 END IF;
 RETURN r;
END $function$
;

DO $permissions$ DECLARE f record; BEGIN
 FOR f IN SELECT p.oid::regprocedure sig FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='pdc_fitter_private' AND p.proname LIKE 'conversion_%' LOOP
 EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated',f.sig);
 END LOOP;
END $permissions$;
NOTIFY pgrst,'reload schema';
DO $$ BEGIN IF md5(pg_get_functiondef('public.get_fitter_refresh(uuid,uuid,text)'::regprocedure))<>'525e7328cb80345bcf1fad4373b7d1d5' THEN RAISE EXCEPTION 'Concurrent fitter refresh change'; END IF; END $$;
CREATE OR REPLACE FUNCTION public.get_fitter_refresh(p_technician_id uuid, p_booking_id uuid DEFAULT NULL::uuid, p_known_revision text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE revision_base text; revision_key text; queue jsonb; selected_id uuid; detail jsonb;
BEGIN
 PERFORM public.require_pdc_role('viewer');
 IF NOT EXISTS(SELECT 1 FROM public.workshop_technicians WHERE id=p_technician_id AND active)
 THEN RETURN jsonb_build_object('ok',false,'error','mechanic_unavailable'); END IF;
 -- Booking/assignment/config triggers advance station revisions. Source lines,
 -- manual estimates, vehicle identity and imported operation approvals advance
 -- the email revision. Do not use booking.version alone: scope can change too.
 -- STABLE keeps the revision, queue, checklist and timer in one read snapshot.
 SELECT md5(jsonb_build_array(p_technician_id,auth.uid(),auth.jwt()->>'session_id',
  (SELECT string_agg(r.role::text,',' ORDER BY r.role::text) FROM public.pdc_user_roles r WHERE r.auth_user_id=auth.uid()
   AND r.active AND r.account_status='approved' AND lower(btrim(r.email))=lower(btrim(coalesce(auth.jwt()->>'email','')))),
  (SELECT revision FROM public.pdc_email_vehicle_revision WHERE singleton), CASE WHEN EXISTS(SELECT 1 FROM pdc_fitter_private.conversion_state cs JOIN public.workshop_bookings cb ON cb.vehicle_id=cs.vehicle_id WHERE cb.id=p_booking_id) THEN date_trunc('minute',statement_timestamp()) END,
  (SELECT coalesce(jsonb_object_agg(stage_code,revision),'{}'::jsonb) FROM public.workshop_station_revision))::text)
 INTO revision_base;
 revision_key:=md5(jsonb_build_array(revision_base,p_booking_id)::text);
 IF p_known_revision=revision_key AND (p_booking_id IS NULL OR EXISTS(
  SELECT 1 FROM public.workshop_bookings b JOIN public.vehicles v ON v.id=b.vehicle_id
  WHERE b.id=p_booking_id AND b.deleted_at IS NULL AND b.status IN('planned','queued','started','stoppage')
   AND v.deleted_at IS NULL AND v.lifecycle_state='active'
   AND pdc_fitter_private.assigned(b.id,p_technician_id))) THEN
  RETURN jsonb_build_object('ok',true,'unchanged',true,'revision',revision_key,'booking_id',p_booking_id,
   'timing',CASE WHEN p_booking_id IS NOT NULL THEN pdc_fitter_private.timing(p_booking_id,statement_timestamp()) ELSE NULL END);
 END IF;
 queue:=public.get_fitter_jobs(p_technician_id);
 IF (queue->>'ok')::boolean IS DISTINCT FROM true THEN RETURN queue; END IF;
 -- Match fitterJobFlow: retain a selected active job; otherwise first active,
 -- then the planner's first planned/queued job. Never pick a stale next job.
 SELECT (item->>'id')::uuid INTO selected_id
 FROM jsonb_array_elements(queue->'jobs') WITH ORDINALITY jobs(item,position)
 WHERE item->>'status' IN('started','stoppage','planned','queued')
 ORDER BY CASE WHEN item->>'status' IN('started','stoppage') THEN 0 ELSE 1 END,
  CASE WHEN item->>'status' IN('started','stoppage') AND item->>'id'=p_booking_id::text THEN 0 ELSE 1 END,
  position LIMIT 1;
 IF selected_id IS NOT NULL THEN
  detail:=public.get_fitter_job(p_technician_id,selected_id);
  IF (detail->>'ok')::boolean IS DISTINCT FROM true THEN RETURN detail; END IF;
 END IF;
 revision_key:=md5(jsonb_build_array(revision_base,selected_id)::text);
 RETURN queue||jsonb_build_object('revision',revision_key,'unchanged',false,'booking_id',selected_id,'detail',detail);
END $function$
;

