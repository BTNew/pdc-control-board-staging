-- Work categories are operation scopes, not additional physical bays.
-- Existing unscoped bookings retain their identity, dates and whole-job scope.
DO $guard$ BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR
    to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'Staging project required';
 END IF;
END $guard$;

CREATE SCHEMA pdc_work_categories_private;
REVOKE ALL ON SCHEMA pdc_work_categories_private FROM PUBLIC,anon,authenticated;

ALTER TABLE public.workshop_bookings ADD COLUMN work_category text,
 ADD COLUMN work_category_scope jsonb;
ALTER TABLE public.workshop_bookings ADD CONSTRAINT workshop_work_category_valid
 CHECK (work_category IS NULL OR work_category IN('BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA'));

CREATE TABLE pdc_work_categories_private.line_overrides(
 vehicle_id uuid NOT NULL REFERENCES public.vehicles(id),
 line_identity text NOT NULL,
 category text NOT NULL CHECK(category IN('BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA','BUS_PIT','HOIST','FABRICATION','FITTING','ELECTRICAL','TINT','TYRE','SUBLET')),
 version integer NOT NULL DEFAULT 1,
 updated_by uuid NOT NULL REFERENCES auth.users(id),
 updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(vehicle_id,line_identity)
);
ALTER TABLE pdc_work_categories_private.line_overrides ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_work_categories_private.line_overrides FROM PUBLIC,anon,authenticated;

CREATE FUNCTION pdc_work_categories_private.stage(category text) RETURNS text
 LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $fn$
 SELECT CASE WHEN category='BUS_PIT' THEN 'PIT_INSPECTION'
 WHEN category IN('BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA') THEN 'BUS_4X4' ELSE category END
$fn$;

CREATE FUNCTION pdc_work_categories_private.suggest(line jsonb) RETURNS text
 LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $fn$
DECLARE d text:=upper(coalesce(line->>'description','')); c text:=upper(regexp_replace(coalesce(line->>'operation_code',''),'[^a-zA-Z0-9]','','g'));
BEGIN
 IF line->>'department' IS DISTINCT FROM '138' AND line->>'stage_code' IS DISTINCT FROM 'BUS_4X4'
 THEN RETURN line->>'stage_code'; END IF;
 -- Craig's 15 October source examples take precedence over broad keyword rules.
 IF c IN('BV2DC','BYRNESIGNAGE','MMTMRCANVAS') OR d ~ 'BLACKVUE|BYRNECUT AUSTRALIA MULTI.COLOUR HI.VIS SIGNAGE|MMT MULTIPLE ROW CANVAS|RUSTPROOFING.*BEAMS ENGINEERING' THEN RETURN 'SUBLET'; END IF;
 IF d ~ '\mTINT(ING|S)?\M' AND d !~ 'BONNET[ -]*PROTECT|WEATHER[ -]*(SHIELD|SHEILD)' THEN RETURN 'TINT'; END IF;
 IF d ~ 'PIT (INSPECTION|AND WEIGH)|DEPARTMENT OF TRANSPORT.*INSPECTION' THEN RETURN 'BUS_PIT'; END IF;
 IF c IN('95LTRP','PR4X4CER') OR d ~ 'POST.?REGO.*CERTIFICATION|POST.REGISTRATION.*CERTIFICATION|95 LITRES OF FUEL' THEN RETURN 'BUS_QA'; END IF;
 IF d ~ 'SUPER SINGLE.*(TYRES?|RIMS?).*COASTER|COASTER.*SUPER SINGLE|CONVERSION|BATTERY COMPARTMENT|RELAY BOX PROTECTION|BULL ?BAR|SNORKEL|CLEARANCE POLES|FIRST AID|WHEEL.?CHOCK|SAFETY TRIANGLE|WHEEL.?NUT' OR c IN('BUS4X4C','COASTER4X4BS','COASTER1STAID','41MM') THEN RETURN 'BUS_MECHANICAL'; END IF;
 IF d ~ '\m(TYRES?|TIRES?|RIMS?)\M|WHEEL[ -]*(ALIGNMENT|BALANC(E|ING))' THEN RETURN 'TYRE'; END IF;
 IF c IN('COASTERBIJI','HLHBCOMBO','FMRL','XRS370CSA') OR d ~ 'PRE.DELIVERY|JUMP START|BATTERY ISOLATOR|MINE ?BAR|HEAD.?LAMP|HAND.?BRAKE.*ALARM|DRIVING LIGHT|REVERSE LIGHT|\mRADIO\M|\mUHF\M|AERIAL|ELECTRICAL|WIRING' THEN RETURN 'BUS_ELECTRICAL'; END IF;
 IF d ~ 'ACCESSOR|SEAT COVER|FLOOR MAT|CARGO BARRIER|ROOF RACK' THEN RETURN 'BUS_ACCESSORIES'; END IF;
 RETURN 'BUS_MECHANICAL';
END $fn$;

CREATE FUNCTION pdc_work_categories_private.line_hash(line jsonb) RETURNS text
 LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $fn$
 SELECT md5(jsonb_build_array(line->>'line_identity',line->>'description',line->>'work_category',line->'estimated_hours',line->>'job_card_number')::text)
$fn$;

CREATE FUNCTION pdc_work_categories_private.preferred_bay(category text,bay integer) RETURNS boolean
 LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $fn$
 SELECT CASE category WHEN 'BUS_MECHANICAL' THEN bay IN(1,2,3,4)
 WHEN 'BUS_ELECTRICAL' THEN bay IN(8,9) WHEN 'BUS_ACCESSORIES' THEN bay=10 WHEN 'BUS_QA' THEN bay=7 ELSE false END
$fn$;

CREATE FUNCTION pdc_work_categories_private.context_category(vehicle uuid, stage uuid) RETURNS text
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
DECLARE ctx jsonb;
BEGIN
 BEGIN ctx:=nullif(current_setting('pdc.work_category',true),'')::jsonb; EXCEPTION WHEN OTHERS THEN RETURN NULL; END;
 IF ctx->>'actor' IS DISTINCT FROM auth.uid()::text OR ctx->>'vehicle' IS DISTINCT FROM vehicle::text
 OR NOT EXISTS(SELECT 1 FROM public.workshop_stages s WHERE s.id=stage AND s.code='BUS_4X4') THEN RETURN NULL; END IF;
 RETURN ctx->>'category';
END $fn$;

CREATE FUNCTION pdc_work_categories_private.booking_category(booking uuid, vehicle uuid, stage uuid) RETURNS text
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
 SELECT CASE WHEN EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.id=booking)
 THEN (SELECT b.work_category FROM public.workshop_bookings b WHERE b.id=booking AND b.vehicle_id=vehicle AND b.stage_id=stage)
 ELSE pdc_work_categories_private.context_category(vehicle,stage) END
$fn$;

CREATE FUNCTION pdc_work_categories_private.line_completed(vehicle uuid, line jsonb) RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
 SELECT EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.vehicle_id=vehicle
  AND b.work_category=line->>'work_category' AND b.status='completed' AND b.deleted_at IS NULL
  AND b.work_category_scope->>(line->>'line_identity')=pdc_work_categories_private.line_hash(line))
$fn$;

CREATE FUNCTION pdc_work_categories_private.hours(vehicle uuid, category text) RETURNS numeric
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
 SELECT CASE WHEN count(*)=0 THEN 0 WHEN count(*) FILTER(WHERE jsonb_typeof(l->'estimated_hours') IS DISTINCT FROM 'number')=0
 THEN sum((l->>'estimated_hours')::numeric) ELSE NULL END
 FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(vehicle)) l
 WHERE coalesce((l->>'active')::boolean,true) AND l->>'work_category'=category AND NOT pdc_work_categories_private.line_completed(vehicle,l)
$fn$;

CREATE FUNCTION pdc_work_categories_private.minutes(booking uuid, vehicle uuid, stage uuid) RETURNS integer
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
DECLARE category text; hrs numeric;
BEGIN
 category:=pdc_work_categories_private.booking_category(booking,vehicle,stage);
 IF category IS NULL THEN RETURN public.workshop_vehicle_stage_estimated_duration_minutes(vehicle,stage); END IF;
 hrs:=pdc_work_categories_private.hours(vehicle,category);
 RETURN CASE WHEN hrs>0 THEN greatest(1,round(hrs*60)::integer) ELSE NULL END;
END $fn$;

CREATE FUNCTION pdc_work_categories_private.completed(vehicle uuid, category text) RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
 SELECT count(*)>0 AND bool_and(EXISTS(SELECT 1 FROM public.workshop_bookings b
  WHERE b.vehicle_id=vehicle AND b.work_category=category AND b.status='completed' AND b.deleted_at IS NULL
    AND b.work_category_scope->>(l->>'line_identity')=pdc_work_categories_private.line_hash(l)))
 FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(vehicle)) l
 WHERE coalesce((l->>'active')::boolean,true) AND l->>'work_category'=category
$fn$;

CREATE FUNCTION pdc_work_categories_private.capture_scope() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $fn$
DECLARE category text;
BEGIN
 IF TG_OP='INSERT' THEN
  category:=pdc_work_categories_private.context_category(NEW.vehicle_id,NEW.stage_id);
  IF NEW.work_category IS NOT NULL AND NEW.work_category IS DISTINCT FROM category THEN RAISE EXCEPTION 'Invalid work category context'; END IF;
  NEW.work_category:=category;
 ELSIF NEW.work_category IS DISTINCT FROM OLD.work_category OR NEW.work_category_scope IS DISTINCT FROM OLD.work_category_scope THEN
  RAISE EXCEPTION 'A booking work category cannot be changed after creation';
 END IF;
 IF NEW.work_category IS NULL THEN
  IF TG_OP='INSERT' AND EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.vehicle_id=NEW.vehicle_id AND b.stage_id=NEW.stage_id
   AND b.work_category IS NOT NULL AND b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage')) THEN
   RAISE EXCEPTION 'This vehicle already has category bookings. Refresh and book the remaining work by category.';
  END IF;
  RETURN NEW;
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.workshop_stages WHERE id=NEW.stage_id AND code='BUS_4X4') THEN RAISE EXCEPTION 'Wrong physical station for Bus work'; END IF;
 IF TG_OP='INSERT' THEN
  IF pdc_work_categories_private.hours(NEW.vehicle_id,NEW.work_category) IS NULL OR pdc_work_categories_private.hours(NEW.vehicle_id,NEW.work_category)<=0 THEN
   RAISE EXCEPTION 'Category needs approved positive hours before bay booking';
  END IF;
  SELECT jsonb_object_agg(l->>'line_identity',pdc_work_categories_private.line_hash(l)) INTO NEW.work_category_scope
  FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(NEW.vehicle_id)) l
  WHERE coalesce((l->>'active')::boolean,true) AND l->>'work_category'=NEW.work_category AND NOT pdc_work_categories_private.line_completed(NEW.vehicle_id,l);
 END IF;
 IF TG_OP='UPDATE' AND NEW.status='completed' AND OLD.status<>'completed' THEN
  SELECT jsonb_object_agg(l->>'line_identity',pdc_work_categories_private.line_hash(l)) INTO NEW.work_category_scope
  FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(NEW.vehicle_id)) l
  WHERE coalesce((l->>'active')::boolean,true) AND l->>'work_category'=NEW.work_category AND NOT pdc_work_categories_private.line_completed(NEW.vehicle_id,l);
 END IF;
 -- Both category and old whole-job bookings reserve the same real vehicle/bay.
 IF NEW.deleted_at IS NULL AND NEW.status IN('queued','planned','started','stoppage') AND EXISTS(
  SELECT 1 FROM public.workshop_bookings b WHERE b.vehicle_id=NEW.vehicle_id AND b.stage_id=NEW.stage_id AND b.id<>NEW.id
  AND b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage')
  AND (b.work_category IS NULL OR b.work_category=NEW.work_category)) THEN
  RAISE EXCEPTION 'This category already has an active booking, or an existing whole-job booking needs to be returned first';
 END IF;
 RETURN NEW;
END $fn$;
CREATE TRIGGER workshop_booking_042_work_category BEFORE INSERT OR UPDATE ON public.workshop_bookings
 FOR EACH ROW EXECUTE FUNCTION pdc_work_categories_private.capture_scope();

CREATE FUNCTION pdc_work_categories_private.set_context(vehicle uuid, stage text, metadata jsonb) RETURNS void
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $fn$
DECLARE category text:=nullif(metadata->>'work_category','');
BEGIN
 PERFORM public.workshop_require_planner_operator();
 IF category IS NOT NULL THEN
  IF category NOT IN('BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA')
  OR public.workshop_canonical_stage_code(stage) IS DISTINCT FROM 'BUS_4X4' THEN RAISE EXCEPTION 'Invalid work category'; END IF;
  IF pdc_work_categories_private.completed(vehicle,category) THEN RAISE EXCEPTION 'This work category is already complete'; END IF;
 END IF;
 PERFORM set_config('pdc.work_category',jsonb_build_object('actor',auth.uid(),'vehicle',vehicle,'category',category)::text,true);
END $fn$;

CREATE FUNCTION pdc_work_categories_private.vehicle_categories(vehicle uuid) RETURNS jsonb
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
 WITH lines AS MATERIALIZED(SELECT l,pdc_work_categories_private.line_completed(vehicle,l) done FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(vehicle)) l
 WHERE coalesce((l->>'active')::boolean,true) AND l->>'stage_code'='BUS_4X4'),
 categories AS (SELECT l->>'work_category' category,
 CASE WHEN count(*) FILTER(WHERE NOT done AND jsonb_typeof(l->'estimated_hours') IS DISTINCT FROM 'number')=0 THEN coalesce(sum((l->>'estimated_hours')::numeric) FILTER(WHERE NOT done),0) END hours,
 bool_and(done) completed
 FROM lines GROUP BY l->>'work_category')
 SELECT coalesce(jsonb_agg(jsonb_build_object('work_category',category,'estimated_hours',hours,'completed',completed,
 'existing_booking',EXISTS(SELECT 1 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
  WHERE b.vehicle_id=vehicle AND s.code='BUS_4X4' AND b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage')
  AND (b.work_category IS NULL OR b.work_category=category)),
 'schedule_enabled',coalesce(hours>0,false) AND NOT completed,
 'disabled_reason',CASE WHEN hours IS NULL OR hours<=0 THEN 'estimated_duration_missing' END)),'[]'::jsonb) FROM categories
$fn$;

CREATE FUNCTION pdc_work_categories_private.snapshot(snapshot jsonb) RETURNS jsonb
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
DECLARE result jsonb:=snapshot;
BEGIN
 IF snapshot->'scope'->>'stage_code'='BUS_4X4' THEN
  SELECT jsonb_set(result,'{outstanding_candidates}',coalesce(jsonb_agg(candidate||jsonb_build_object('work_categories',
   pdc_work_categories_private.vehicle_categories((candidate->>'vehicle_id')::uuid))),'[]'::jsonb)) INTO result
  FROM jsonb_array_elements(coalesce(snapshot->'outstanding_candidates','[]'::jsonb)) candidate;
 END IF;
 SELECT jsonb_set(result,'{bookings}',coalesce(jsonb_agg(j||jsonb_build_object('work_category',b.work_category)||
 CASE WHEN b.work_category IS NOT NULL THEN jsonb_build_object('estimated_operation_hours',pdc_work_categories_private.hours(b.vehicle_id,b.work_category)) ELSE '{}'::jsonb END), '[]'::jsonb)) INTO result
 FROM jsonb_array_elements(coalesce(snapshot->'bookings','[]'::jsonb)) j
 LEFT JOIN public.workshop_bookings b ON b.id=(j->>'booking_id')::uuid;
 RETURN result;
END $fn$;

CREATE FUNCTION public.set_vehicle_work_category(p_vehicle_id uuid,p_vehicle_expected_version integer,
 p_line_identity text,p_category text,p_category_expected_version integer DEFAULT 0) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $fn$
DECLARE v public.vehicles; l jsonb; old pdc_work_categories_private.line_overrides;
 target text:=pdc_work_categories_private.stage(p_category); before_line jsonb;
BEGIN
 PERFORM public.workshop_require_planner_operator();
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id AND deleted_at IS NULL AND lifecycle_state='active' FOR UPDATE;
 IF NOT FOUND OR v.version IS DISTINCT FROM p_vehicle_expected_version THEN RETURN jsonb_build_object('ok',false,'error','vehicle_version_conflict'); END IF;
 SELECT x INTO l FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v.id)) x
 WHERE x->>'line_identity'=p_line_identity AND coalesce((x->>'active')::boolean,true);
 IF l IS NULL THEN RETURN jsonb_build_object('ok',false,'error','operation_not_found'); END IF;
 IF p_category NOT IN('BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA','BUS_PIT','HOIST','FABRICATION','FITTING','ELECTRICAL','TINT','TYRE','SUBLET')
 OR ((l->>'department'='138' OR l->>'stage_code'='BUS_4X4') AND p_category IN('HOIST','FABRICATION','FITTING','ELECTRICAL'))
 OR (l->>'department'='139' AND p_category LIKE 'BUS_%') THEN RETURN jsonb_build_object('ok',false,'error','wrong_department_category'); END IF;
 IF coalesce((l->>'completed')::boolean,false) OR EXISTS(SELECT 1 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
  WHERE b.vehicle_id=v.id AND b.deleted_at IS NULL AND s.code IN(l->>'stage_code',target)
  AND (b.status IN('queued','planned','started','stoppage') OR (b.status='completed' AND (b.work_category IS NULL OR b.work_category_scope ? p_line_identity)))
  AND (b.work_category IS NULL OR b.work_category IN(l->>'work_category',p_category))) THEN
  RETURN jsonb_build_object('ok',false,'error','category_booking_exists','message','Split or cancel the affected unstarted booking before changing its work category. Started and completed work stays protected.');
 END IF;
 SELECT * INTO old FROM pdc_work_categories_private.line_overrides WHERE vehicle_id=v.id AND line_identity=p_line_identity FOR UPDATE;
 IF coalesce(old.version,0) IS DISTINCT FROM p_category_expected_version THEN RETURN jsonb_build_object('ok',false,'error','category_version_conflict'); END IF;
 INSERT INTO pdc_work_categories_private.line_overrides(vehicle_id,line_identity,category,updated_by)
 VALUES(v.id,p_line_identity,p_category,auth.uid()) ON CONFLICT(vehicle_id,line_identity) DO UPDATE
 SET category=excluded.category,version=line_overrides.version+1,updated_by=auth.uid(),updated_at=clock_timestamp();
 PERFORM public.pdc_auditor_recalculate_required_work_226(ARRAY[v.id]);
 INSERT INTO public.vehicle_work_items(vehicle_id,work_key,required,completed)
 SELECT v.id,work_key,true,false FROM public.workshop_stages WHERE code=target
 ON CONFLICT(vehicle_id,work_key) DO UPDATE SET required=true WHERE NOT public.vehicle_work_items.completed;
 UPDATE public.vehicles SET version=version+1,updated_at=clock_timestamp(),updated_by=auth.uid() WHERE id=v.id;
 INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
 VALUES('update','vehicle_work_category',v.id,v.id,auth.uid(),public.current_actor_email(),to_jsonb(old),jsonb_build_object('line_identity',p_line_identity,'category',p_category),
 jsonb_build_object('source','jobcard_work_categories_20261015','source_hours_preserved',true));
 RETURN jsonb_build_object('ok',true,'revision',public.workshop_bump_revision());
END $fn$;
REVOKE ALL ON FUNCTION public.set_vehicle_work_category(uuid,integer,text,text,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.set_vehicle_work_category(uuid,integer,text,text,integer) TO authenticated;

CREATE FUNCTION public.split_bus_booking_to_categories(p_booking_id uuid,p_expected_version integer) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $fn$
DECLARE b public.workshop_bookings; result jsonb;
BEGIN
 PERFORM public.workshop_require_planner_operator();
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id FOR UPDATE;
 IF NOT FOUND OR b.version IS DISTINCT FROM p_expected_version THEN RETURN jsonb_build_object('ok',false,'error','version_conflict'); END IF;
 IF b.deleted_at IS NOT NULL OR b.status NOT IN('queued','planned') OR b.actual_start_at IS NOT NULL OR b.work_category IS NOT NULL
 OR NOT EXISTS(SELECT 1 FROM public.workshop_stages WHERE id=b.stage_id AND code='BUS_4X4')
 OR EXISTS(SELECT 1 FROM pdc_fitter_private.operation_progress WHERE booking_id=b.id) THEN
  RETURN jsonb_build_object('ok',false,'error','booking_scope_protected','message','Only an unstarted whole-job Bus booking can be split. Completed work and fitter progress stay protected.');
 END IF;
 result:=public.cancel_workshop_booking(b.id,b.version,'Split whole-job Bus booking into work categories',jsonb_build_object('source','jobcard_category_split','work_category_split',true));
 IF result->>'ok' IS DISTINCT FROM 'true' THEN RETURN result; END IF;
 PERFORM public.pdc_auditor_recalculate_required_work_226(ARRAY[b.vehicle_id]);
 RETURN result||jsonb_build_object('work_categories',pdc_work_categories_private.vehicle_categories(b.vehicle_id));
END $fn$;
REVOKE ALL ON FUNCTION public.split_bus_booking_to_categories(uuid,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.split_bus_booking_to_categories(uuid,integer) TO authenticated;








-- GENERATED CURRENT-FUNCTION ADAPTATIONS
DO $versions$ DECLARE item jsonb; found_hash text; BEGIN FOR item IN SELECT x FROM jsonb_array_elements($expected$[{"schema": "pdc_fitter_private", "name": "clock_start_version", "hash": "11f21c8f4a72fcf3928211647aa0f0bc"}, {"schema": "pdc_fitter_private", "name": "conversion_completion_guard", "hash": "a64c959fa15fd1e3cdc7c9470ce6e252"}, {"schema": "pdc_fitter_private", "name": "lines", "hash": "875f8a35904fcae237fb0d84f83f3ed9"}, {"schema": "pdc_fitter_private", "name": "summary", "hash": "4321f4a01b5549db2c68cfd39d0b9918"}, {"schema": "public", "name": "administrator_schedule_workshop_vehicle", "hash": "6794b51cc04625342696f063ba801977"}, {"schema": "public", "name": "book_all_vehicle_stations", "hash": "6a67df560ba1732eb98bfb29968fdf43"}, {"schema": "public", "name": "complete_workshop_work_pre345", "hash": "3c1418fbbf63b194f8b3252ea7f6999d"}, {"schema": "public", "name": "get_fitter_job", "hash": "7cfe317b12800342a892259904a412a9"}, {"schema": "public", "name": "get_station_workshop_snapshot", "hash": "40aac6a2d1bb7e6cee9026a2e0954d08"}, {"schema": "public", "name": "get_vehicle_workshop_detail", "hash": "4ff03323511789cf8cea07eea8270adf"}, {"schema": "public", "name": "pdc_auditor_recalculate_required_work_226", "hash": "964d6c037cc733e19ed8a47b0daac47e"}, {"schema": "public", "name": "pdc_qc_operation_lines_379", "hash": "fb63b01d434c35c7f58f13c46de20189"}, {"schema": "public", "name": "pdc_tune_reconcile_booking_plan_20260913", "hash": "3a14a77b05103bde274b2d48fa335fef"}, {"schema": "public", "name": "schedule_vehicle_work", "hash": "cd7f75424cb68e91c82e5b6ddc3f7050"}, {"schema": "public", "name": "workshop_booking_capacity_base_minutes", "hash": "eaeb7f6c95b7c8d929af0399c603d423"}, {"schema": "public", "name": "workshop_booking_capacity_duration_before_bus_20260921", "hash": "5e540a8381fe6f27d79be84affe0e75e"}, {"schema": "public", "name": "workshop_booking_capacity_duration_minutes", "hash": "edc1bcf51952c22cb998a4549649fc6c"}, {"schema": "public", "name": "workshop_booking_snapshot", "hash": "7d8eef1f05015773b3a31955168f9589"}, {"schema": "public", "name": "workshop_candidate_schedule_gate", "hash": "8f95fc48c14fdac6347324be32e141ff"}, {"schema": "public", "name": "workshop_capacity_manual_minutes", "hash": "b10a7cb5706395c1cc4d3e6fd2b643ed"}, {"schema": "public", "name": "workshop_capture_capacity_basis", "hash": "46f1cf101c844c5ed07a1f1e71e9d1a3"}, {"schema": "public", "name": "workshop_require_positive_estimate_for_planned_booking_317", "hash": "4777e8682f6935d68967370cd49b883d"}, {"schema": "public", "name": "workshop_sync_vehicle_stage_booking_duration", "hash": "86effd0ca609c0f4a51190dfa713a13b"}, {"schema": "public", "name": "workshop_vehicle_stage_estimated_hours", "hash": "3b3d3bfc88cd2580208077c3b1a85293"}]$expected$::jsonb) x LOOP SELECT md5(pg_get_functiondef(p.oid)) INTO STRICT found_hash FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname=item->>'schema' AND p.proname=item->>'name'; IF found_hash IS DISTINCT FROM item->>'hash' THEN RAISE EXCEPTION 'Current function changed since review: %.%',item->>'schema',item->>'name'; END IF; END LOOP; END $versions$;
DO $preserve$ DECLARE definition text; BEGIN SELECT pg_get_functiondef(p.oid) INTO STRICT definition FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='pdc_qc_operation_lines_379'; EXECUTE replace(definition,'FUNCTION public.pdc_qc_operation_lines_379(','FUNCTION pdc_work_categories_private.base_pdc_qc_operation_lines_379('); END $preserve$;

CREATE OR REPLACE FUNCTION public.pdc_qc_operation_lines_379(p_vehicle_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
 WITH source AS MATERIALIZED(SELECT l,ord FROM jsonb_array_elements(pdc_work_categories_private.base_pdc_qc_operation_lines_379(p_vehicle_id)) WITH ORDINALITY a(l,ord)),
 projected AS (SELECT l,ord,o.category override_category,o.version category_version,
   a.adjustment_id,a.manual_assignment_locked,a.stage_code saved_stage,
   CASE WHEN l->>'department'='138' AND public.pdc_is_pre_delivery_20260910(l->>'description')
     THEN coalesce(a.estimated_hours,op.effective_estimated_hours,(l->>'estimated_hours')::numeric) ELSE (l->>'estimated_hours')::numeric END hours,
   pdc_work_categories_private.suggest(l) suggested,
   (SELECT b.work_category FROM public.workshop_bookings b
     WHERE b.vehicle_id=p_vehicle_id AND b.deleted_at IS NULL AND b.work_category IS NOT NULL
       AND b.status IN('queued','planned','started','stoppage','completed') AND b.work_category_scope ? (l->>'line_identity')
     ORDER BY (b.status<>'completed') DESC,b.created_at DESC LIMIT 1) booked_category,
   EXISTS(SELECT 1 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
     WHERE b.vehicle_id=p_vehicle_id AND b.deleted_at IS NULL AND s.code=l->>'stage_code'
       AND b.status IN('queued','planned','started','stoppage','completed') AND b.work_category IS NULL) protected_booking
 FROM source LEFT JOIN pdc_work_categories_private.line_overrides o ON o.vehicle_id=p_vehicle_id AND o.line_identity=l->>'line_identity'
 LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=p_vehicle_id AND a.line_key=l->>'line_identity'
 LEFT JOIN public.pdc_pilbara_service_operations op ON op.vehicle_id=p_vehicle_id AND 'source:'||op.operation_id::text=l->>'line_identity'),
 chosen AS (SELECT *,coalesce(override_category,booked_category,CASE
 WHEN l->>'stage_code'='UNALLOCATED_MAPPING_REVIEW' THEN l->>'stage_code'
 WHEN l->>'stage_code'='BUS_4X4' THEN CASE WHEN suggested LIKE 'BUS_%' AND suggested<>'BUS_PIT' THEN suggested ELSE CASE WHEN protected_booking OR coalesce(manual_assignment_locked,false) THEN 'BUS_MECHANICAL' ELSE suggested END END
 WHEN protected_booking OR coalesce(manual_assignment_locked,false) OR l->>'department' IS DISTINCT FROM '138' THEN l->>'stage_code'
 ELSE suggested END) category FROM projected)
 SELECT coalesce(jsonb_agg(l||jsonb_build_object('work_category',category,'category_version',coalesce(category_version,0),
 'stage_code',pdc_work_categories_private.stage(category),'estimated_hours',hours,
 'zero_hour_task',category='BUS_QA' AND hours=0,
 'category_rule','craig_jobcard_categories_20261015') ORDER BY ord),'[]'::jsonb) FROM chosen
$fn$;

CREATE OR REPLACE FUNCTION public.schedule_vehicle_work(p_vehicle_id uuid, p_vehicle_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer DEFAULT 180, p_technician_id uuid DEFAULT NULL::uuid, p_override_reason text DEFAULT NULL::text, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$ declare previous_context text:=current_setting('pdc.work_category',true); result jsonb;
 begin
 perform pdc_work_categories_private.set_context(p_vehicle_id,p_stage_code,p_metadata);
 perform pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));result:=public.schedule_vehicle_work_pre345(p_vehicle_id,p_vehicle_expected_version,p_stage_code,p_bay_number,p_scheduled_start_at,p_duration_minutes,p_technician_id,p_override_reason,p_metadata);perform set_config('pdc.work_category',coalesce(previous_context,''),true);return result; exception when others then perform set_config('pdc.work_category',coalesce(previous_context,''),true);raise;end $function$;

CREATE OR REPLACE FUNCTION public.administrator_schedule_workshop_vehicle(p_vehicle_id uuid, p_vehicle_expected_version integer, p_stage_code text, p_bay_number integer, p_scheduled_start_at timestamp with time zone, p_duration_minutes integer, p_technician_id uuid, p_metadata jsonb, p_request_id uuid, p_cascade boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
 previous_context text:=current_setting('pdc.work_category',true);
 v_actor uuid:=auth.uid(); v_email text; v_existing public.workshop_booking_move_receipts%rowtype;
 v_stage uuid; v_bay uuid; v_result jsonb; v_booking_id uuid; v_booking_version integer; v_receipt uuid;
 v_ids_before uuid[]; v_ids_after uuid[]; v_before jsonb; v_after jsonb; v_intent jsonb; v_hash text; v_intent_hash_source text;
begin
 perform pdc_planner_access_private.require_vehicle_planner();
 perform pdc_work_categories_private.set_context(p_vehicle_id,p_stage_code,p_metadata);
 if p_request_id is null or p_vehicle_id is null or p_vehicle_expected_version is null then raise exception 'PDC_244_REQUIRED_ARGUMENT_MISSING' using errcode='22023'; end if;
 v_intent:=jsonb_build_object('operation','create','vehicle_id',p_vehicle_id,'vehicle_expected_version',p_vehicle_expected_version,
   'stage_code',public.workshop_canonical_stage_code(p_stage_code),'bay_number',p_bay_number,'scheduled_start_at',p_scheduled_start_at,
   'duration_minutes',p_duration_minutes,'technician_id',p_technician_id,'metadata',coalesce(p_metadata,'{}'::jsonb),'cascade',coalesce(p_cascade,true));
 v_hash:=encode(extensions.digest(convert_to(v_intent::text,'UTF8'),'sha256'),'hex');
 select * into v_existing from public.workshop_booking_move_receipts where actor_user_id=v_actor and request_id=p_request_id;
 if found then
   if v_existing.request_intent is distinct from v_intent or v_existing.request_intent_hash is distinct from v_hash then
     raise exception 'PDC_244_IDEMPOTENCY_INTENT_MISMATCH' using errcode='22023';
   end if;
   perform set_config('pdc.work_category',coalesce(previous_context,''),true);
   return v_existing.result||jsonb_build_object('receipt_id',v_existing.receipt_id,'idempotent_replay',true);
 end if;
 select id into v_stage from public.workshop_stages where code=public.workshop_canonical_stage_code(p_stage_code) and active and planner_enabled;
 select id into v_bay from public.workshop_bays where stage_id=v_stage and bay_number=p_bay_number and is_active;
 if v_stage is null or v_bay is null then perform set_config('pdc.work_category',coalesce(previous_context,''),true); return jsonb_build_object('ok',false,'error','bay_inactive_or_wrong_station'); end if;
 perform pg_advisory_xact_lock(hashtextextended('workshop-admin-create:'||p_vehicle_id::text,0));
 perform 1 from public.vehicles where id=p_vehicle_id for update;
 select coalesce(array_agg(b.id order by b.id),'{}'::uuid[]) into v_ids_before from public.workshop_bookings b
 where b.deleted_at is null and b.status='planned' and b.bay_id=v_bay and public.workshop_booking_effective_end_at(b.id)>p_scheduled_start_at;
 perform 1 from public.workshop_bookings b where b.id=any(v_ids_before) order by b.id for update;
 v_before:=public.workshop_admin_state_244(v_ids_before,p_vehicle_id);
 if p_cascade then
   v_result:=public.cascade_workshop_schedule('insert',p_vehicle_id,p_vehicle_expected_version,p_stage_code,p_bay_number,p_scheduled_start_at,
     p_duration_minutes,p_technician_id,p_duration_minutes,null,coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('request_id',p_request_id,'authority',case when public.current_pdc_user_role()='administrator' then 'website_administrator' else 'website_controller' end));
 else
   v_result:=public.schedule_vehicle_work(p_vehicle_id,p_vehicle_expected_version,p_stage_code,p_bay_number,p_scheduled_start_at,
     p_duration_minutes,p_technician_id,null,coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('request_id',p_request_id,'authority',case when public.current_pdc_user_role()='administrator' then 'website_administrator' else 'website_controller' end));
 end if;
 if coalesce((v_result->>'ok')::boolean,false) is not true then perform set_config('pdc.work_category',coalesce(previous_context,''),true); return v_result; end if;
 v_booking_id:=nullif(v_result->'booking'->>'booking_id','')::uuid;
 if v_booking_id is null then raise exception 'PDC_244_AUTHORITATIVE_BOOKING_ID_MISSING' using errcode='55000'; end if;
 if not exists(select 1 from public.workshop_bookings where id=v_booking_id and vehicle_id=p_vehicle_id and stage_id=v_stage) then
   raise exception 'PDC_244_AUTHORITATIVE_BOOKING_ID_INVALID' using errcode='55000';
 end if;
 v_ids_after:=array(select distinct x from unnest(v_ids_before||array[v_booking_id]) x order by x);
 v_after:=public.workshop_admin_state_244(v_ids_after,p_vehicle_id);
 select version into v_booking_version from public.workshop_bookings where id=v_booking_id;
 select email into v_email from public.pdc_user_roles where auth_user_id=v_actor;
 v_result:=v_result||jsonb_build_object('booking_id',v_booking_id,'booking_version',v_booking_version,'operation_type','create');
 insert into public.workshop_booking_move_receipts(request_id,actor_user_id,actor_email,booking_id,vehicle_id,operation_type,source,reason,cascade,
   before_rows,after_rows,result,request_intent,request_intent_hash,before_state,after_state)
 values(p_request_id,v_actor,coalesce(v_email,auth.jwt()->>'email',''),v_booking_id,p_vehicle_id,'create',
   left(coalesce(nullif(btrim(p_metadata->>'source'),''),'website_unallocated_drag'),80),nullif(left(btrim(coalesce(p_metadata->>'reason','')),500),''),p_cascade,
   v_before->'bookings',v_after->'bookings',v_result,v_intent,v_hash,v_before,v_after) returning receipt_id into v_receipt;
 perform set_config('pdc.work_category',coalesce(previous_context,''),true);
 return v_result||jsonb_build_object('receipt_id',v_receipt,'idempotent_replay',false);
exception when unique_violation then
 select * into v_existing from public.workshop_booking_move_receipts where actor_user_id=v_actor and request_id=p_request_id;
 if found and v_existing.request_intent is not distinct from v_intent and v_existing.request_intent_hash is not distinct from v_hash then
   perform set_config('pdc.work_category',coalesce(previous_context,''),true);
   return v_existing.result||jsonb_build_object('receipt_id',v_existing.receipt_id,'idempotent_replay',true);
 end if;
 raise exception 'PDC_244_IDEMPOTENCY_INTENT_MISMATCH' using errcode='22023';
end $function$;

CREATE OR REPLACE FUNCTION public.workshop_candidate_schedule_gate(p_vehicle_id uuid, p_stage_code text, p_scheduled_start_at timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_stage_code text;
  v_candidate record;
  v_schedule_date date;
BEGIN
  v_stage_code:=public.workshop_canonical_stage_code(p_stage_code);
  -- Only this vehicle is being scheduled. The board-wide reader also computes
  -- each eligible vehicle's estimated hours; this gate never consumes them.
  -- Keep its membership and active-booking predicates identical.
  SELECT public.workshop_location_code(coalesce(nullif(v.location_override,''),v.current_location)) current_location,
    v.eta_to_kewdale,
    EXISTS (
      SELECT 1 FROM public.workshop_bookings b
      JOIN public.workshop_stages booked_stage ON booked_stage.id=b.stage_id
      WHERE b.vehicle_id=v.id AND booked_stage.code=st.code
        AND b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage')
        AND (pdc_work_categories_private.context_category(v.id,st.id) IS NULL OR b.work_category IS NULL
             OR b.work_category=pdc_work_categories_private.context_category(v.id,st.id))
    ) existing_booking
  INTO v_candidate
  FROM public.vehicles v CROSS JOIN public.workshop_stages st
  WHERE v.id=p_vehicle_id
    AND st.code=v_stage_code AND st.active AND st.planner_enabled
    AND v.lifecycle_state='active' AND v.deleted_at IS NULL AND v.visible_on_board
    AND public.workshop_location_code(coalesce(nullif(v.location_override,''),v.current_location)) IN('PMB','YH','IT')
    AND (public.workshop_location_code(coalesce(nullif(v.location_override,''),v.current_location))<>'IT' OR v.eta_to_kewdale IS NOT NULL)
    AND EXISTS (
      SELECT 1 FROM public.vehicle_work_items wi
      WHERE wi.vehicle_id=v.id AND public.workshop_stage_code_for_work_key(wi.work_key)=st.code
        AND wi.required AND NOT wi.completed
    );
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok',false,'error','vehicle_not_eligible_for_station');
  END IF;
  IF coalesce(v_candidate.existing_booking,false) THEN
    RETURN jsonb_build_object('ok',false,'error','active_booking_exists');
  END IF;
  v_schedule_date:=(p_scheduled_start_at AT TIME ZONE 'Australia/Perth')::date;
  IF public.pdc_sublet_away_on_date(p_vehicle_id,v_schedule_date) THEN
    RETURN jsonb_build_object('ok',false,'error','sublet_away','sublet_date',v_schedule_date);
  END IF;
  IF v_candidate.current_location='IT' AND v_candidate.eta_to_kewdale IS NULL THEN
    RETURN jsonb_build_object('ok',false,'error','it_eta_missing');
  END IF;
  IF v_candidate.current_location='IT'
     AND v_schedule_date<v_candidate.eta_to_kewdale+7 THEN
    RETURN jsonb_build_object(
      'ok',false,
      'error','it_before_eta_plus_seven',
      'earliest_permitted_date',v_candidate.eta_to_kewdale+7
    );
  END IF;
  RETURN jsonb_build_object(
    'ok',true,
    'earliest_permitted_date',CASE WHEN v_candidate.current_location='IT' THEN v_candidate.eta_to_kewdale+7 ELSE NULL END
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.workshop_booking_capacity_base_minutes(p_booking_id uuid)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
 SELECT CASE WHEN b.capacity_base_minutes IS NULL THEN greatest(q.minutes,b.default_duration_minutes)::numeric
 ELSE greatest(1,b.capacity_base_minutes+CASE WHEN q.minutes IS NOT NULL AND b.capacity_estimate_minutes IS NOT NULL
  THEN q.minutes-b.capacity_estimate_minutes ELSE 0 END) END
 FROM public.workshop_bookings b
 CROSS JOIN LATERAL(SELECT pdc_work_categories_private.minutes(b.id,b.vehicle_id,b.stage_id) minutes) q
 WHERE b.id=p_booking_id
$function$;

CREATE OR REPLACE FUNCTION public.workshop_booking_capacity_duration_before_bus_20260921(p_booking_id uuid, p_vehicle_id uuid, p_stage_id uuid, p_bay_id uuid)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
 SELECT CASE WHEN p_bay_id IS NULL AND EXISTS(
  SELECT 1 FROM public.workshop_bookings b WHERE b.id=p_booking_id AND b.vehicle_id=p_vehicle_id AND b.stage_id=p_stage_id)
 THEN (SELECT default_duration_minutes FROM public.workshop_bookings WHERE id=p_booking_id)
 ELSE public.workshop_capacity_duration_minutes(
  CASE WHEN EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.id=p_booking_id AND b.vehicle_id=p_vehicle_id AND b.stage_id=p_stage_id)
   THEN public.workshop_booking_capacity_base_minutes(p_booking_id)
   ELSE pdc_work_categories_private.minutes(p_booking_id,p_vehicle_id,p_stage_id)::numeric END,p_bay_id) END
$function$;

CREATE OR REPLACE FUNCTION public.workshop_capacity_manual_minutes(p_booking_id uuid, p_vehicle_id uuid, p_stage_id uuid, p_bay_id uuid, p_duration integer)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE context jsonb; b public.workshop_bookings%rowtype; minimum_minutes integer;
BEGIN
 BEGIN context:=nullif(current_setting('pdc.workshop_capacity_manual',true),'')::jsonb;
 EXCEPTION WHEN OTHERS THEN RETURN NULL; END;
 IF context IS NULL OR context->>'actor' IS DISTINCT FROM auth.uid()::text
 OR context->>'booking' IS DISTINCT FROM p_booking_id::text
 OR context->>'duration' IS DISTINCT FROM p_duration::text THEN RETURN NULL; END IF;
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id AND vehicle_id=p_vehicle_id AND stage_id=p_stage_id
  AND bay_id IS NOT DISTINCT FROM p_bay_id AND deleted_at IS NULL AND status IN('queued','planned');
 IF NOT FOUND OR context->>'version' IS DISTINCT FROM b.version::text THEN RETURN NULL; END IF;
 minimum_minutes:=public.workshop_capacity_duration_minutes(pdc_work_categories_private.minutes(p_booking_id,p_vehicle_id,p_stage_id),p_bay_id);
 IF minimum_minutes IS NULL OR p_duration<minimum_minutes OR p_duration>59999 THEN RETURN NULL; END IF;
 RETURN p_duration;
END $function$;

CREATE OR REPLACE FUNCTION public.workshop_capture_capacity_basis()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE base numeric; quote integer; efficiency integer; manual integer;
BEGIN
 -- Completed/live history and its applied duration stay fixed.
 IF NEW.deleted_at IS NOT NULL OR NEW.status NOT IN('queued','planned') THEN
  IF TG_OP='UPDATE' THEN
   NEW.capacity_base_minutes:=OLD.capacity_base_minutes;
   NEW.capacity_efficiency_percent:=OLD.capacity_efficiency_percent;
   NEW.capacity_estimate_minutes:=OLD.capacity_estimate_minutes;
  END IF;
  RETURN NEW;
 END IF;
 IF TG_OP='UPDATE' AND NEW.status='queued' AND NEW.bay_id IS NULL
  AND NEW.vehicle_id=OLD.vehicle_id AND NEW.stage_id=OLD.stage_id
  AND NEW.default_duration_minutes=OLD.default_duration_minutes
  AND NEW.scheduled_start_at=OLD.scheduled_start_at AND NEW.scheduled_end_at=OLD.scheduled_end_at THEN
  NEW.capacity_base_minutes:=OLD.capacity_base_minutes;
  NEW.capacity_efficiency_percent:=OLD.capacity_efficiency_percent;
  NEW.capacity_estimate_minutes:=OLD.capacity_estimate_minutes;
  RETURN NEW;
 END IF;
 IF TG_OP='UPDATE' AND NEW.vehicle_id IS NOT DISTINCT FROM OLD.vehicle_id
  AND NEW.stage_id IS NOT DISTINCT FROM OLD.stage_id AND NEW.bay_id IS NOT DISTINCT FROM OLD.bay_id
  AND NEW.scheduled_start_at IS NOT DISTINCT FROM OLD.scheduled_start_at
  AND NEW.scheduled_end_at IS NOT DISTINCT FROM OLD.scheduled_end_at
  AND NEW.default_duration_minutes IS NOT DISTINCT FROM OLD.default_duration_minutes
  AND OLD.capacity_base_minutes IS NOT NULL
  AND coalesce((SELECT efficiency_percent FROM public.workshop_bays WHERE id=NEW.bay_id),100)=OLD.capacity_efficiency_percent THEN
  NEW.capacity_base_minutes:=OLD.capacity_base_minutes;
  NEW.capacity_efficiency_percent:=OLD.capacity_efficiency_percent;
  NEW.capacity_estimate_minutes:=OLD.capacity_estimate_minutes;
  RETURN NEW;
 END IF;
 quote:=pdc_work_categories_private.minutes(NEW.id,NEW.vehicle_id,NEW.stage_id);
 SELECT coalesce(b.efficiency_percent,100) INTO efficiency FROM (SELECT 1) one LEFT JOIN public.workshop_bays b ON b.id=NEW.bay_id;
 base:=CASE WHEN TG_OP='UPDATE' AND NEW.vehicle_id=OLD.vehicle_id AND NEW.stage_id=OLD.stage_id
  THEN public.workshop_booking_capacity_base_minutes(OLD.id) ELSE quote END;
 IF TG_OP='INSERT' AND NEW.work_category IS NULL AND pdc_bus_private.active_vehicle(NEW.vehicle_id) THEN
  SELECT greatest(1,quote-coalesce(round(sum((l->>'saved_hours')::numeric)*60),0)) INTO base
  FROM jsonb_array_elements(pdc_bus_private.supplier_lines(NEW.vehicle_id)) l
  WHERE l->>'stage_code'=(SELECT code FROM public.workshop_stages WHERE id=NEW.stage_id)
  AND jsonb_typeof(l->'saved_hours')='number';
 END IF;
 manual:=public.workshop_capacity_manual_minutes(NEW.id,NEW.vehicle_id,NEW.stage_id,NEW.bay_id,NEW.default_duration_minutes);
 IF manual IS NOT NULL AND manual IS DISTINCT FROM public.workshop_capacity_duration_minutes(base,NEW.bay_id) THEN
  base:=manual::numeric*efficiency/100;
 END IF;
 IF base IS NOT NULL THEN
  NEW.capacity_base_minutes:=base;
  NEW.capacity_efficiency_percent:=efficiency;
  NEW.capacity_estimate_minutes:=quote;
 END IF;
 RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.workshop_require_positive_estimate_for_planned_booking_317()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
begin
  if new.deleted_at is null and new.status='planned'::public.workshop_booking_status
     and pdc_work_categories_private.minutes(new.id,new.vehicle_id,new.stage_id) is null then
    raise exception 'PDC_317_ESTIMATED_DURATION_REQUIRED' using errcode='22023';
  end if;
  return new;
end
$function$;

CREATE OR REPLACE FUNCTION pdc_fitter_private.clock_start_version(p_booking_id uuid, p_expected_version integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE b public.workshop_bookings; h record; prior jsonb; first_before jsonb;
 n integer:=0; expected integer:=p_expected_version; cutoff timestamptz;
 allowed text[]:=ARRAY['scheduled_start_at','scheduled_end_at','version','updated_at','updated_by','eta_at_booking','eta_risk_status','eta_risk_detected_at'];
BEGIN
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id;
 IF NOT FOUND OR b.deleted_at IS NOT NULL OR b.status<>'planned' OR b.actual_start_at IS NOT NULL
 OR p_expected_version IS NULL OR p_expected_version>=b.version OR b.version-p_expected_version>10 THEN RETURN NULL; END IF;
 FOR h IN SELECT before_data,after_data,created_at FROM public.workshop_clock_history
  WHERE booking_id=b.id AND actor_kind='automatic_workshop_clock'
   AND (before_data->>'version')::integer>=p_expected_version
   AND (after_data->>'version')::integer<=b.version
  ORDER BY (before_data->>'version')::integer,id LOOP
  -- Clock workers and browsers can serialize the same timestamp in UTC or Perth.
  -- Compare typed booking rows, preserving every field while normalizing zones.
  h.before_data:=to_jsonb(jsonb_populate_record(NULL::public.workshop_bookings,h.before_data));
  h.after_data:=to_jsonb(jsonb_populate_record(NULL::public.workshop_bookings,h.after_data));
  IF h.created_at<clock_timestamp()-interval '10 minutes'
    OR (h.before_data->>'version')::integer<>expected
    OR (h.after_data->>'version')::integer<>expected+1
    OR h.before_data-allowed IS DISTINCT FROM h.after_data-allowed
    OR (prior IS NOT NULL AND prior IS DISTINCT FROM h.before_data)
    OR h.before_data->>'id' IS DISTINCT FROM b.id::text THEN RETURN NULL; END IF;
  IF first_before IS NULL THEN first_before:=h.before_data; END IF;
  prior:=h.after_data; expected:=expected+1; n:=n+1;
 END LOOP;
 IF n<>b.version-p_expected_version OR expected<>b.version OR prior IS DISTINCT FROM to_jsonb(b) THEN RETURN NULL; END IF;
 -- Keep default technician/capacity fixed while this proof and Start run.
 PERFORM 1 FROM public.vehicles WHERE id=b.vehicle_id FOR UPDATE NOWAIT;
 PERFORM 1 FROM public.workshop_bays WHERE id=b.bay_id FOR UPDATE NOWAIT;
 PERFORM 1 FROM public.workshop_booking_assignments WHERE booking_id=b.id ORDER BY id FOR UPDATE NOWAIT;
 PERFORM 1 FROM public.vehicle_workshop_line_adjustments WHERE vehicle_id=b.vehicle_id ORDER BY adjustment_id FOR UPDATE NOWAIT;
 cutoff:=(first_before->>'updated_at')::timestamptz;
 IF cutoff IS NULL THEN RETURN NULL; END IF;
 -- Assignment APIs increment the booking version and therefore break the chain.
 -- Also reject newly assigned/released technicians and changed bay defaults,
 -- which are related resources outside the booking's own version counter.
 IF EXISTS(SELECT 1 FROM public.workshop_bays bay WHERE bay.id=b.bay_id AND bay.updated_at>cutoff)
 OR EXISTS(SELECT 1 FROM public.workshop_booking_assignments a WHERE a.booking_id=b.id
   AND (a.assigned_at>cutoff OR a.released_at>cutoff))
 OR EXISTS(SELECT 1 FROM public.workshop_booking_history bh WHERE bh.booking_id=b.id AND bh.created_at>cutoff)
 THEN RETURN NULL; END IF;
 -- Reconcile with authoritative operation hours. Any work-scope update since
 -- that version is conservative: require the caller to refresh, even if its
 -- total hours happen to be unchanged.
 IF pdc_work_categories_private.minutes(b.id,b.vehicle_id,b.stage_id)
    IS DISTINCT FROM b.capacity_estimate_minutes
 OR EXISTS(SELECT 1 FROM public.vehicles v WHERE v.id=b.vehicle_id AND v.updated_at>cutoff)
 OR EXISTS(SELECT 1 FROM public.vehicle_workshop_line_adjustments a WHERE a.vehicle_id=b.vehicle_id AND a.updated_at>cutoff)
 OR EXISTS(SELECT 1 FROM public.pdc_authenticated_email_operation_lines o WHERE o.vehicle_id=b.vehicle_id AND o.created_at>cutoff)
 OR EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=b.vehicle_id AND (
   o.created_at>cutoff
   OR EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operation_history oh WHERE oh.operation_id=o.operation_id AND oh.created_at>cutoff)
   OR EXISTS(SELECT 1 FROM public.pdc_pilbara_service_classification_current c WHERE c.operation_id=o.operation_id AND c.updated_at>cutoff)
   OR EXISTS(SELECT 1 FROM public.pdc_tune_operation_change_reviews cr WHERE cr.source_operation_id=o.operation_id AND cr.approved_at>cutoff)))
 THEN RETURN NULL; END IF;
 RETURN b.version;
EXCEPTION WHEN lock_not_available THEN
 -- Scope writers can lock vehicle before booking. Never wait in the reverse
 -- order: preserve the version conflict and require a fresh request instead.
 RETURN NULL;
END $function$;

CREATE OR REPLACE FUNCTION public.workshop_sync_vehicle_stage_booking_duration(p_vehicle_id uuid, p_stage_code text, p_reason text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
 v_stage text:=public.workshop_canonical_stage_code(p_stage_code);v_booking public.workshop_bookings%rowtype;
 v_minutes integer;v_end timestamptz;v_before jsonb;v_after jsonb;v_count integer:=0;
 v_increment integer;v_from timestamptz;v_cascade jsonb;
 v_original_claims text:=current_setting('request.jwt.claims',true);v_initiator_uid uuid:=auth.uid();v_initiator_email text:=public.current_actor_email();
 v_system_actor uuid;v_system_email text;
BEGIN
 IF p_vehicle_id IS NULL OR v_stage IS NULL THEN RETURN 0;END IF;
 SELECT r.auth_user_id,r.email INTO v_system_actor,v_system_email FROM public.pdc_user_roles r JOIN auth.users u ON u.id=r.auth_user_id
 WHERE r.active AND r.account_status='approved' AND r.role='administrator' AND r.auth_user_id IS NOT NULL ORDER BY r.created_at,r.id LIMIT 1;
 IF v_system_actor IS NULL THEN RAISE EXCEPTION 'PDC_156_WORKSHOP_SYSTEM_ACTOR_MISSING' USING errcode='55000';END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_system_actor,'email',v_system_email,'role','authenticated')::text,true);
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:estimate-sync:'||p_vehicle_id::text,0));
 LOCK TABLE public.workshop_bookings,public.workshop_booking_assignments IN EXCLUSIVE MODE;
 FOR v_booking IN SELECT b.* FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
  WHERE b.vehicle_id=p_vehicle_id AND b.deleted_at IS NULL AND b.status::text IN('queued','planned','started','stoppage')
    AND public.workshop_canonical_stage_code(s.code)=v_stage ORDER BY b.scheduled_start_at,b.id FOR UPDATE OF b LOOP
  v_minutes:=CASE WHEN v_booking.status IN('queued','planned') THEN coalesce(public.workshop_booking_capacity_duration_minutes(v_booking.id,p_vehicle_id,v_booking.stage_id,v_booking.bay_id),v_booking.default_duration_minutes) ELSE coalesce(pdc_work_categories_private.minutes(v_booking.id,p_vehicle_id,v_booking.stage_id),60) END;
  v_end:=public.workshop_add_operational_minutes(v_booking.scheduled_start_at,v_minutes);
  IF v_booking.default_duration_minutes IS DISTINCT FROM v_minutes OR v_booking.scheduled_end_at IS DISTINCT FROM v_end THEN
   v_before:=public.workshop_booking_snapshot(v_booking.id);
   IF v_booking.status::text<>'planned' THEN
    INSERT INTO public.workshop_booking_history(booking_id,event_type,before_data,after_data,metadata,actor_user_id,actor_email)
    VALUES(v_booking.id,'operation_estimate_duration_reconcile_deferred',v_before,v_before,
     jsonb_build_object('system_reconciliation',true,'source',coalesce(p_reason,'operation_estimate_change'),'stage_code',v_stage,
      'proposed_duration_minutes',v_minutes,'reason','protected_non_planned_booking_window','protected_status',v_booking.status::text,
      'initiator_auth_uid',v_initiator_uid,'initiator_email',v_initiator_email),v_system_actor,v_system_email);
   ELSE
    SELECT coalesce((value#>>'{}')::integer,15) INTO v_increment FROM public.workshop_settings WHERE key='scheduling_increment_minutes';
    v_increment:=greatest(1,coalesce(v_increment,15));
    v_from:=CASE WHEN v_booking.scheduled_start_at>clock_timestamp() THEN v_booking.scheduled_start_at ELSE
      date_trunc('minute',clock_timestamp())+
      (v_increment-mod((extract(epoch from clock_timestamp())/60)::bigint,v_increment)) * interval '1 minute' END;
    v_cascade:=public.workshop_admin_repack_planned(v_booking.bay_id,v_from,
      jsonb_build_object('system_reconciliation',true,'source',coalesce(p_reason,'operation_estimate_change'),'stage_code',v_stage,
       'operation_estimate_duration_cascade',true,'recover_overdue',v_booking.scheduled_start_at<=clock_timestamp(),
       'initiator_auth_uid',v_initiator_uid,'initiator_email',v_initiator_email));
    v_count:=v_count+coalesce((v_cascade->>'shifted_count')::integer,0);
   END IF;
  END IF;
 END LOOP;
 PERFORM set_config('request.jwt.claims',coalesce(v_original_claims,''),true);RETURN v_count;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims',coalesce(v_original_claims,''),true);RAISE;
END $function$;

CREATE OR REPLACE FUNCTION public.workshop_booking_capacity_duration_minutes(p_booking_id uuid, p_vehicle_id uuid, p_stage_id uuid, p_bay_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE quote numeric; supplied numeric; result integer; code text;
BEGIN
 result:=public.workshop_booking_capacity_duration_before_bus_20260921(p_booking_id,p_vehicle_id,p_stage_id,p_bay_id);
 IF EXISTS(SELECT 1 FROM public.workshop_bookings WHERE id=p_booking_id) OR pdc_work_categories_private.context_category(p_vehicle_id,p_stage_id) IS NOT NULL THEN RETURN result; END IF;
 SELECT s.code INTO code FROM public.workshop_stages s WHERE s.id=p_stage_id;
 IF code NOT IN('BUS_4X4','TINT') OR NOT pdc_bus_private.active_vehicle(p_vehicle_id) THEN RETURN result; END IF;
 SELECT coalesce(sum((l->>'saved_hours')::numeric),0) INTO supplied FROM jsonb_array_elements(pdc_bus_private.supplier_lines(p_vehicle_id)) l
 WHERE l->>'stage_code'=code AND jsonb_typeof(l->'saved_hours')='number';
 IF supplied<=0 THEN RETURN result; END IF;
 quote:=public.workshop_vehicle_stage_estimated_hours(p_vehicle_id,code);
 RETURN public.workshop_capacity_duration_minutes(greatest(1,round(greatest(0,quote-supplied)*60)),p_bay_id);
END $function$;

CREATE OR REPLACE FUNCTION public.pdc_tune_reconcile_booking_plan_20260913(p_vehicle_id uuid, p_stage_codes text[], p_change_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
 SET statement_timeout TO '120s'
AS $function$
#variable_conflict use_column
<<plan>>
DECLARE
 item record; prior record; n integer; minutes integer; proposed_start timestamptz;
 proposed_end timestamptz; blocked_until timestamptz; unavailable_date date;
 old_snapshot jsonb; new_snapshot jsonb; receipt jsonb:='[]'; changed boolean;
 root_change boolean; technician uuid; validation jsonb; graph_count integer;
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR current_setting('app.environment',true)='production'
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'Operation approval is available on staging only.';
 END IF;
 PERFORM public.workshop_require_planner_operator();
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 IF NOT EXISTS(SELECT 1 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
   WHERE b.vehicle_id=p_vehicle_id AND b.deleted_at IS NULL AND b.bay_id IS NOT NULL
    AND b.status IN('queued','planned','started','stoppage') AND s.code=ANY(p_stage_codes)
    AND s.is_physical AND NOT s.is_sublet AND s.code<>'SUBLET') THEN
  RETURN jsonb_build_object('bookings',receipt,'changed_count',0,'extended_count',0,'moved_count',0,'buffer_minutes',60);
 END IF;
 -- These are the same rows written by the existing planner. Preserve its guards
 -- and immediate overlap constraints; never hide or temporarily delete a job.
 PERFORM 1 FROM public.workshop_bookings WHERE deleted_at IS NULL
  AND status IN('queued','planned','started','stoppage') ORDER BY id FOR UPDATE NOWAIT;
 PERFORM 1 FROM public.workshop_admin_blocks WHERE deleted_at IS NULL ORDER BY id FOR SHARE NOWAIT;
 PERFORM 1 FROM public.workshop_booking_assignments WHERE released_at IS NULL ORDER BY id FOR UPDATE NOWAIT;
 DROP TABLE IF EXISTS pg_temp.pdc_tune_cascade_plan;
 CREATE TEMP TABLE pdc_tune_cascade_plan(
  ordinal bigint PRIMARY KEY,booking_id uuid UNIQUE NOT NULL,vehicle_id uuid NOT NULL,
  stage_id uuid NOT NULL,stage_code text NOT NULL,bay_id uuid,status text NOT NULL,
  original_start timestamptz NOT NULL,original_end timestamptz NOT NULL,
  original_minutes integer NOT NULL,minutes integer NOT NULL,version integer NOT NULL,
  final_start timestamptz NOT NULL,final_end timestamptz NOT NULL,
  technicians uuid[] NOT NULL,root_change boolean NOT NULL DEFAULT false,
  changed boolean NOT NULL DEFAULT false,before_row jsonb NOT NULL
 ) ON COMMIT DROP;
 INSERT INTO pg_temp.pdc_tune_cascade_plan
  (ordinal,booking_id,vehicle_id,stage_id,stage_code,bay_id,status,original_start,original_end,
   original_minutes,minutes,version,final_start,final_end,technicians,before_row)
 SELECT row_number() OVER(ORDER BY b.scheduled_start_at,b.id),b.id,b.vehicle_id,b.stage_id,s.code,b.bay_id,b.status::text,
  b.scheduled_start_at,b.scheduled_end_at,b.default_duration_minutes,b.default_duration_minutes,b.version,
  b.scheduled_start_at,b.scheduled_end_at,
  coalesce((SELECT array_agg(DISTINCT a.technician_id) FROM public.workshop_booking_assignments a
    WHERE a.booking_id=b.id AND a.released_at IS NULL),'{}'::uuid[]),to_jsonb(b)
 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
 WHERE b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage')
  AND s.is_physical AND NOT s.is_sublet AND s.code<>'SUBLET';
 SELECT count(*) INTO graph_count FROM pg_temp.pdc_tune_cascade_plan;
 IF graph_count>10000 THEN RAISE EXCEPTION 'The workshop queue needs a smaller scheduling review.'
  USING DETAIL='operation_schedule_limit'; END IF;
 -- A station booking is the whole station estimate, not just the changed line.
 -- Never manufacture a booking for a newly required, unbooked station.
 FOR item IN SELECT * FROM pg_temp.pdc_tune_cascade_plan
  WHERE vehicle_id=p_vehicle_id AND stage_code=ANY(p_stage_codes) AND bay_id IS NOT NULL ORDER BY ordinal
 LOOP
  IF (SELECT count(*) FROM pg_temp.pdc_tune_cascade_plan x
    WHERE x.vehicle_id=p_vehicle_id AND x.stage_id=item.stage_id AND x.bay_id IS NOT NULL AND (SELECT work_category FROM public.workshop_bookings WHERE id=x.booking_id) IS NOT DISTINCT FROM (SELECT work_category FROM public.workshop_bookings WHERE id=item.booking_id))>1 THEN
   RAISE EXCEPTION 'This station has more than one active booking. Review those bookings before approving the operation.'
    USING DETAIL='operation_schedule_multiple_station_bookings';
  END IF;
  minutes:=CASE WHEN item.status IN('queued','planned') THEN public.workshop_booking_capacity_duration_minutes(item.booking_id,p_vehicle_id,item.stage_id,item.bay_id) ELSE pdc_work_categories_private.minutes(item.booking_id,p_vehicle_id,item.stage_id) END;
  IF minutes IS NULL OR minutes<1 THEN
   RAISE EXCEPTION 'This change would leave a booked station without work. Move or remove its booking before approving.'
    USING DETAIL='operation_schedule_empty_station';
  END IF;
  -- Reducing an estimate must not shorten a job that is already in progress.
  IF item.status IN('started','stoppage') THEN minutes:=greatest(minutes,item.original_minutes); END IF;
  proposed_end:=public.workshop_add_operational_minutes(item.original_start,minutes);
  UPDATE pg_temp.pdc_tune_cascade_plan SET minutes=plan.minutes,
   root_change=(plan.minutes IS DISTINCT FROM item.original_minutes OR proposed_end IS DISTINCT FROM item.original_end)
   WHERE booking_id=item.booking_id;
 END LOOP;
 IF NOT EXISTS(SELECT 1 FROM pg_temp.pdc_tune_cascade_plan WHERE root_change) THEN
  RETURN jsonb_build_object('bookings',receipt,'changed_count',0,'extended_count',0,'moved_count',0,'buffer_minutes',60);
 END IF;
 -- Dependency order is the original queue order. Every move is to the right,
 -- so a later bay or vehicle job can never jump ahead of its predecessor.
 FOR item IN SELECT * FROM pg_temp.pdc_tune_cascade_plan ORDER BY ordinal LOOP
  root_change:=item.root_change;
  SELECT max(greatest(x.final_end,CASE WHEN x.status IN('started','stoppage') THEN date_trunc('minute',clock_timestamp()) ELSE x.final_end END)
      +CASE WHEN x.vehicle_id=item.vehicle_id THEN interval '1 hour' ELSE interval '0 minutes' END) INTO blocked_until
   FROM pg_temp.pdc_tune_cascade_plan x WHERE x.ordinal<item.ordinal AND x.changed
    AND (x.bay_id=item.bay_id OR x.vehicle_id=item.vehicle_id OR x.technicians && item.technicians);
  IF NOT root_change AND coalesce(blocked_until,item.original_start)<=item.original_start THEN CONTINUE; END IF;
  IF item.bay_id IS NULL THEN
   RAISE EXCEPTION 'A later job is queued without a bay. Review that booking before approving this change.'
    USING DETAIL='operation_schedule_queued_without_bay';
  END IF;
  proposed_start:=greatest(item.original_start,coalesce(blocked_until,item.original_start));
  IF item.status IN('started','stoppage') AND proposed_start>item.original_start THEN
   RAISE EXCEPTION 'A later job is already in progress or stopped. Resolve that booking before approving this change.'
    USING DETAIL='operation_schedule_protected_active_booking';
  END IF;
  minutes:=item.minutes;
  IF item.status IN('queued','planned') THEN
   minutes:=coalesce(public.workshop_booking_capacity_duration_minutes(item.booking_id,item.vehicle_id,item.stage_id,item.bay_id),minutes);
   proposed_start:=greatest(proposed_start,date_trunc('minute',clock_timestamp())+interval '1 minute');
  END IF;
  -- Once a booking moves, also respect unchanged predecessors and technician
  -- reservations. Unrelated jobs with no incoming change are left untouched.
  SELECT max(greatest(x.final_end,CASE WHEN x.status IN('started','stoppage') THEN date_trunc('minute',clock_timestamp()) ELSE x.final_end END)
     +CASE WHEN x.vehicle_id=item.vehicle_id THEN interval '1 hour' ELSE interval '0 minutes' END) INTO blocked_until
   FROM pg_temp.pdc_tune_cascade_plan x WHERE x.ordinal<item.ordinal
    AND (x.bay_id=item.bay_id OR x.vehicle_id=item.vehicle_id OR x.technicians && item.technicians);
  proposed_start:=greatest(proposed_start,coalesce(blocked_until,proposed_start));
  IF item.status IN('started','stoppage') AND proposed_start>item.original_start THEN
   RAISE EXCEPTION 'The current job cannot be moved automatically. Resolve its earlier booking conflict first.'
    USING DETAIL='operation_schedule_protected_active_booking';
  END IF;
  n:=0;
  LOOP
   n:=n+1;
   IF n>1000 THEN RAISE EXCEPTION 'No safe workshop slot was found for this change.'
    USING DETAIL='operation_schedule_no_slot'; END IF;
   IF item.status IN('queued','planned') THEN
    proposed_start:=public.workshop_admin_next_operational_minute(proposed_start);
    IF proposed_start IS NULL THEN RAISE EXCEPTION 'No open workshop time was found for this change.'
     USING DETAIL='operation_schedule_calendar_unavailable'; END IF;
   END IF;
   proposed_end:=public.workshop_add_operational_minutes(proposed_start,minutes);
   SELECT max(a.scheduled_end_at) INTO blocked_until FROM public.workshop_admin_blocks a
    WHERE a.deleted_at IS NULL AND a.bay_id=item.bay_id
     AND a.scheduled_start_at<proposed_end AND a.scheduled_end_at>proposed_start;
   SELECT max(d::date) INTO unavailable_date FROM generate_series(
    (proposed_start AT TIME ZONE 'Australia/Perth')::date::timestamp,
    ((proposed_end-interval '1 minute') AT TIME ZONE 'Australia/Perth')::date::timestamp,interval '1 day') d
    WHERE public.pdc_sublet_away_on_date(item.vehicle_id,d::date);
   IF unavailable_date IS NOT NULL THEN
    blocked_until:=greatest(blocked_until,(unavailable_date+1)::timestamp AT TIME ZONE 'Australia/Perth');
   END IF;
   FOREACH technician IN ARRAY item.technicians LOOP
    unavailable_date:=public.workshop_technician_leave_date(technician,proposed_start,proposed_end);
    IF unavailable_date IS NOT NULL THEN
     blocked_until:=greatest(blocked_until,(unavailable_date+1)::timestamp AT TIME ZONE 'Australia/Perth');
    END IF;
   END LOOP;
   EXIT WHEN blocked_until IS NULL;
   IF item.status IN('started','stoppage') THEN
    RAISE EXCEPTION 'The longer current job conflicts with an Admin block, Sublet visit or technician leave. Resolve that conflict before approving.'
     USING DETAIL='operation_schedule_protected_reservation';
   END IF;
   proposed_start:=greatest(proposed_start+interval '1 minute',blocked_until);
  END LOOP;
  changed:=proposed_start IS DISTINCT FROM item.original_start OR proposed_end IS DISTINCT FROM item.original_end OR minutes IS DISTINCT FROM item.original_minutes;
  UPDATE pg_temp.pdc_tune_cascade_plan SET final_start=proposed_start,final_end=proposed_end,
   minutes=plan.minutes,changed=plan.changed
   WHERE booking_id=item.booking_id;
 END LOOP;
 -- Move downstream jobs first, vacating intervals before earlier extensions.
 -- Immediate bay, vehicle and technician exclusion constraints remain enabled.
 FOR item IN SELECT * FROM pg_temp.pdc_tune_cascade_plan WHERE changed ORDER BY ordinal DESC LOOP
  old_snapshot:=public.workshop_booking_snapshot(item.booking_id);
  UPDATE public.workshop_bookings SET scheduled_start_at=item.final_start,scheduled_end_at=item.final_end,
   default_duration_minutes=item.minutes,version=version+1,updated_by=auth.uid(),updated_at=clock_timestamp()
   WHERE id=item.booking_id AND version=item.version AND status::text=item.status AND deleted_at IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'A booking changed while this operation was being approved. Refresh and try again.'
   USING ERRCODE='40001',DETAIL='operation_schedule_changed'; END IF;
  -- Retain every assignment and its identity, including secondary technicians.
  UPDATE public.workshop_booking_assignments SET scheduled_start_at=item.final_start,
   scheduled_end_at=item.final_end,updated_at=clock_timestamp()
   WHERE booking_id=item.booking_id AND released_at IS NULL;
  new_snapshot:=public.workshop_booking_snapshot(item.booking_id);
  IF (SELECT to_jsonb(b)-ARRAY['scheduled_start_at','scheduled_end_at','default_duration_minutes','version','updated_by','updated_at','eta_at_booking','eta_risk_status','eta_risk_detected_at','capacity_base_minutes','capacity_efficiency_percent','capacity_estimate_minutes']
      FROM public.workshop_bookings b WHERE id=item.booking_id)
    IS DISTINCT FROM item.before_row-ARRAY['scheduled_start_at','scheduled_end_at','default_duration_minutes','version','updated_by','updated_at','eta_at_booking','eta_risk_status','eta_risk_detected_at','capacity_base_minutes','capacity_efficiency_percent','capacity_estimate_minutes'] THEN
   RAISE EXCEPTION 'Operation approval changed protected booking details.' USING DETAIL='operation_schedule_readback_mismatch';
  END IF;
  PERFORM public.workshop_write_history(item.booking_id,'operation_change_schedule_updated',old_snapshot,new_snapshot,
   jsonb_build_object('source','approved_tune_operation_change','change_id',p_change_id,
    'approved_vehicle_id',p_vehicle_id,'buffer_minutes',60,'previous_duration_minutes',item.original_minutes,
    'duration_minutes',item.minutes,'moved',item.final_start IS DISTINCT FROM item.original_start));
 END LOOP;
 -- Check the final vehicle handovers against the calculated plan. General
 -- planner validation separately verifies bay, technician, ETA and calendar.
 IF EXISTS(SELECT 1 FROM pg_temp.pdc_tune_cascade_plan a JOIN pg_temp.pdc_tune_cascade_plan b
   ON a.vehicle_id=b.vehicle_id AND a.ordinal<b.ordinal
   WHERE (a.changed OR b.changed) AND a.final_end+interval '1 hour'>b.final_start) THEN
  RAISE EXCEPTION 'The vehicle needs one hour between workshop jobs.' USING DETAIL='operation_schedule_handover_conflict';
 END IF;
 FOR item IN SELECT * FROM pg_temp.pdc_tune_cascade_plan WHERE changed LOOP
  FOREACH technician IN ARRAY item.technicians LOOP
   IF public.workshop_find_technician_conflict(item.booking_id,technician,item.final_start,item.final_end) IS NOT NULL THEN
    RAISE EXCEPTION 'The revised job conflicts with another technician booking.' USING DETAIL='operation_schedule_technician_conflict';
   END IF;
  END LOOP;
 END LOOP;
 SELECT coalesce(jsonb_agg(jsonb_build_object('booking_id',x.booking_id,'vehicle_id',x.vehicle_id,
  'stock_number',coalesce(nullif(btrim(v.stock_number),''),'—'),'stage_code',x.stage_code,'bay_id',x.bay_id,'bay_name',coalesce(nullif(btrim(b.display_name),''),'Bay '||b.bay_number),
  'previous_start_at',x.original_start,'previous_end_at',x.original_end,'start_at',x.final_start,'end_at',x.final_end,
  'previous_estimated_hours',x.original_minutes::numeric/60,'estimated_hours',x.minutes::numeric/60,
  'status',x.status) ORDER BY x.ordinal),'[]') INTO receipt
 FROM pg_temp.pdc_tune_cascade_plan x JOIN public.vehicles v ON v.id=x.vehicle_id
 LEFT JOIN public.workshop_bays b ON b.id=x.bay_id WHERE x.changed;
 RETURN jsonb_build_object('bookings',receipt,'changed_count',jsonb_array_length(receipt),
  'extended_count',(SELECT count(*) FROM pg_temp.pdc_tune_cascade_plan WHERE changed AND minutes>original_minutes),
  'moved_count',(SELECT count(*) FROM pg_temp.pdc_tune_cascade_plan WHERE changed AND final_start IS DISTINCT FROM original_start),
  'buffer_minutes',60);
END $function$;

CREATE OR REPLACE FUNCTION public.workshop_booking_snapshot(p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with active_assignment as (
    select a.booking_id, a.technician_id, t.name as technician_name, a.assignment_type
    from public.workshop_booking_assignments a
    join public.workshop_technicians t on t.id = a.technician_id
    where a.booking_id = p_booking_id
      and a.released_at is null
    order by case when a.assignment_type = 'primary' then 0 else 1 end, a.assigned_at desc
    limit 1
  )
  select jsonb_build_object(
    'booking_id', b.id,'work_category',b.work_category,
    'vehicle_id', b.vehicle_id,
    'vehicle', jsonb_build_object(
      'bus_workflow_department138', pdc_bus_private.active_vehicle(v.id),'permanent_vehicle_id', v.permanent_vehicle_id,
      'stock_number', v.stock_number,
      'job_card_number', v.job_card_number,
      'customer_name', v.customer_name,
      'model', v.model
    ),
    'stage', jsonb_build_object(
      'id', s.id,
      'code', s.code,
      'display_name', s.display_name,
      'sort_order', s.sort_order
    ),
    'bay', case when bay.id is null then null else jsonb_build_object(
      'id', bay.id,
      'bay_number', bay.bay_number,
      'code', bay.code,
      'display_name', bay.display_name,
      'is_sublet_row', bay.is_sublet_row
    ) end,
    'status', b.status,
    'scheduled_start_at', b.scheduled_start_at,
    'scheduled_end_at', b.scheduled_end_at,
    'default_duration_minutes', b.default_duration_minutes,'bus_calendar_version', b.bus_calendar_version,
    'capacity_base_minutes',coalesce(b.capacity_base_minutes,b.default_duration_minutes::numeric),
    'capacity_efficiency_percent',coalesce(b.capacity_efficiency_percent,100),
    'capacity_estimate_minutes',b.capacity_estimate_minutes,
    'actual_start_at', b.actual_start_at,
    'actual_end_at', b.actual_end_at,
    'actual_duration_minutes', b.actual_duration_minutes,
    'stoppage_reason', b.stoppage_reason,
    'stoppage_started_at', b.stoppage_started_at,
    'stoppage_accumulated_minutes', b.stoppage_accumulated_minutes,
    'returned_to_queue_at', b.returned_to_queue_at,
    'deleted_at', b.deleted_at,
    'deleted_reason', b.deleted_reason,
    'version', b.version,
    'assignment', case when aa.technician_id is null then null else jsonb_build_object(
      'technician_id', aa.technician_id,
      'technician_name', aa.technician_name,
      'assignment_type', aa.assignment_type
    ) end,
    'updated_at', b.updated_at,
    'created_at', b.created_at
  )||pdc_bus_private.team_payload(b.id)
  from public.workshop_bookings b
  join public.vehicles v on v.id = b.vehicle_id
  join public.workshop_stages s on s.id = b.stage_id
  left join public.workshop_bays bay on bay.id = b.bay_id
  left join active_assignment aa on aa.booking_id = b.id
  where b.id = p_booking_id;
$function$;

CREATE OR REPLACE FUNCTION public.get_vehicle_workshop_detail(p_vehicle_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare v_vehicle_version bigint;
begin
  perform public.require_pdc_role('viewer');
  select v.version into v_vehicle_version from public.vehicles v
   where v.id=p_vehicle_id and v.lifecycle_state IN('active','rft','completed') and v.deleted_at is null;
  if not found then raise exception 'vehicle_not_found' using errcode='P0001'; end if;
  return jsonb_build_object(
    'work_categories',pdc_work_categories_private.vehicle_categories(p_vehicle_id),'job_card_lines',public.pdc_qc_operation_lines_379(p_vehicle_id),'vehicle_id',p_vehicle_id,'vehicle_version',v_vehicle_version,'generated_at',now(),
    'requirements',coalesce((select jsonb_agg(jsonb_build_object(
      'work_item_id',wi.id,'work_key',wi.work_key,
      'stage_code',coalesce(public.workshop_stage_code_for_work_key(wi.work_key),case lower(btrim(wi.work_key)) when 'parts' then 'PARTS' when 'sublet' then 'SUBLET' else upper(regexp_replace(btrim(wi.work_key),'[^a-zA-Z0-9]+','_','g')) end),
      'required',wi.required,'completed',wi.completed,'completed_at',wi.completed_at)
      order by coalesce(s.sort_order,999),wi.work_key,wi.id)
      from public.vehicle_work_items wi left join public.workshop_stages s on s.code=public.workshop_stage_code_for_work_key(wi.work_key)
      where wi.vehicle_id=p_vehicle_id and wi.required),'[]'::jsonb),
    'bookings',coalesce((select jsonb_agg(jsonb_build_object(
      'booking_id',b.id,'work_category',b.work_category,'booking_version',b.version,'stage_code',s.code,'stage_name',s.display_name,
      'bay_number',bay.bay_number,'bay_name',bay.display_name,'status',b.status,
      'scheduled_start_at',b.scheduled_start_at,'scheduled_end_at',b.scheduled_end_at,
      'default_duration_minutes',b.default_duration_minutes,'actual_start_at',b.actual_start_at,'actual_end_at',b.actual_end_at)
      order by s.sort_order,b.scheduled_start_at,b.id)
      from public.workshop_bookings b join public.workshop_stages s on s.id=b.stage_id left join public.workshop_bays bay on bay.id=b.bay_id
      where b.vehicle_id=p_vehicle_id and b.deleted_at is null and b.status in ('queued','planned','started','stoppage','completed')),'[]'::jsonb),
    'line_adjustments',coalesce((select jsonb_agg(jsonb_build_object(
      'adjustment_id',a.adjustment_id,'line_key',a.line_key,'source_kind',a.source_kind,'stage_code',a.stage_code,'department',(SELECT o.department FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=a.vehicle_id AND a.line_key='source:'||o.operation_id::text LIMIT 1),
      'description',a.description,'estimated_hours',a.estimated_hours,'correction_origin',a.correction_origin,'manual_assignment_locked',a.manual_assignment_locked,'version',a.version,'created_at',a.created_at,'updated_at',a.updated_at)
      order by a.created_at,a.adjustment_id) from public.vehicle_workshop_line_adjustments a where a.vehicle_id=p_vehicle_id and a.active),'[]'::jsonb)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_station_workshop_snapshot(p_stage_code text, p_date_from date, p_date_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_snapshot jsonb;
BEGIN
  v_snapshot:=public.get_station_workshop_snapshot_pre_397(p_stage_code,p_date_from,p_date_to);
  v_snapshot:=public.workshop_overlay_canonical_booking_fields_397(v_snapshot);
  RETURN pdc_work_categories_private.snapshot(pdc_parts_private.planner_search_snapshot_20260917(public.workshop_overlay_authoritative_candidate_hours_175(v_snapshot)));
END
$function$;

DO $preserve$ DECLARE definition text; BEGIN SELECT pg_get_functiondef(p.oid) INTO STRICT definition FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='pdc_fitter_private' AND p.proname='lines'; EXECUTE replace(definition,'FUNCTION pdc_fitter_private.lines(','FUNCTION pdc_work_categories_private.base_lines('); END $preserve$;

CREATE OR REPLACE FUNCTION pdc_fitter_private.lines(p_vehicle_id uuid,p_booking_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
 WITH booking AS(SELECT work_category,work_category_scope,status FROM public.workshop_bookings WHERE id=p_booking_id),
 canonical AS MATERIALIZED(SELECT l FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) l)
 SELECT coalesce(jsonb_agg(a.l||jsonb_build_object('work_category',c.l->>'work_category','zero_hour_task',c.l->'zero_hour_task') ORDER BY ord),'[]'::jsonb)
 FROM jsonb_array_elements(pdc_work_categories_private.base_lines(p_vehicle_id,p_booking_id)) WITH ORDINALITY a(l,ord)
 LEFT JOIN canonical c ON c.l->>'line_identity'=a.l->>'line_identity'
 WHERE (SELECT work_category FROM booking) IS NULL OR (c.l->>'work_category'=(SELECT work_category FROM booking)
  AND ((SELECT work_category_scope FROM booking) ? (c.l->>'line_identity')
    OR ((SELECT status FROM booking)<>'completed' AND NOT pdc_work_categories_private.line_completed(p_vehicle_id,c.l))))
$fn$;

CREATE OR REPLACE FUNCTION pdc_fitter_private.summary(p_lines jsonb, p_stage text)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
 WITH lines AS(
 SELECT l,CASE WHEN l->>'external_work'='true' THEN 0
 WHEN jsonb_typeof(l->'hours')='number' THEN (l->>'hours')::numeric END hours
 FROM jsonb_array_elements(p_lines) l WHERE l->>'stage_code'=p_stage
 ),totals AS(
 SELECT count(*) total_lines,count(*) FILTER(WHERE (l->>'completed')::boolean) completed_lines,
 count(*) FILTER(WHERE (hours IS NULL OR hours<=0) AND l->>'external_work' IS DISTINCT FROM 'true' AND l->>'zero_hour_task' IS DISTINCT FROM 'true') unknown_hours,
 coalesce(sum(greatest(hours,0)),0) total_hours,
 coalesce(sum(greatest(hours,0)*CASE WHEN (l->>'completed')::boolean THEN 1 ELSE coalesce((l->>'completed_fraction')::numeric,0) END),0) completed_hours
 FROM lines)
 SELECT jsonb_build_object('total_lines',total_lines,'completed_lines',completed_lines,'unknown_hours',unknown_hours,
 'total_hours',total_hours,'completed_hours',completed_hours,
 'percent',CASE WHEN total_lines>0 AND total_lines=completed_lines AND unknown_hours=0 THEN 100
 WHEN total_hours>0 THEN least(99,floor(100*completed_hours/total_hours)) ELSE 0 END,
 'can_complete',total_lines>0 AND total_lines=completed_lines AND unknown_hours=0) FROM totals
$function$;

CREATE OR REPLACE FUNCTION pdc_fitter_private.conversion_completion_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE bid uuid; vid uuid; stage text; l jsonb; identity text;
BEGIN
 IF TG_TABLE_NAME='workshop_bookings' THEN
  IF NEW.status<>'completed' OR (TG_OP='UPDATE' AND OLD.status='completed') THEN RETURN NEW; END IF;
  bid:=NEW.id; vid:=NEW.vehicle_id; SELECT code INTO stage FROM public.workshop_stages WHERE id=NEW.stage_id;
 ELSIF TG_TABLE_NAME='vehicle_work_items' THEN
  IF NOT NEW.completed OR (TG_OP='UPDATE' AND OLD.completed) THEN RETURN NEW; END IF;
  vid:=NEW.vehicle_id; stage:=CASE WHEN NEW.work_key='bus4x4' THEN 'BUS_4X4' END;
 ELSE
  IF NOT NEW.completed THEN RETURN NEW; END IF;
  SELECT vehicle_id INTO vid FROM public.workshop_bookings WHERE id=NEW.booking_id;
  stage:='BUS_4X4'; identity:=NEW.line_identity;
 END IF;
 IF stage IS DISTINCT FROM 'BUS_4X4' THEN RETURN NEW; END IF;
 FOR l IN SELECT x FROM jsonb_array_elements(pdc_fitter_private.lines(vid,bid)) x
 WHERE x->'conversion' IS NOT NULL AND (identity IS NULL OR x->>'line_identity'=identity) LOOP
  IF NOT coalesce((l->>'completed')::boolean,false) THEN
   RAISE EXCEPTION '{"error":"conversion_sections_required"}' USING errcode='23514';
  END IF;
 END LOOP;
 RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.complete_workshop_work_pre345(p_booking_id uuid, p_expected_version integer, p_work_key text DEFAULT NULL::text, p_actual_end_at timestamp with time zone DEFAULT now(), p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_booking public.workshop_bookings%rowtype;
  v_stage_code text;
  v_stage_work_key text;
  v_requested_stage text;
  v_result jsonb;
  v_revision bigint;
  v_end timestamptz := date_trunc('minute', coalesce(p_actual_end_at, statement_timestamp()));
begin
  perform public.workshop_require_planner_operator();
  perform public.workshop_require_version(p_expected_version);
  perform public.workshop_require_booking_active_vehicle(p_booking_id, false);

  select * into v_booking
  from public.workshop_bookings
  where id = p_booking_id
  for update;
  if not found then
    raise exception 'Workshop booking not found' using errcode = 'P0002';
  end if;
  if v_booking.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'version_conflict');
  end if;
  if v_booking.deleted_at is not null or v_booking.status not in ('started','stoppage') then
    return jsonb_build_object('ok', false, 'error', 'not_completable');
  end if;
  if v_booking.actual_start_at is not null and v_end < v_booking.actual_start_at then
    return jsonb_build_object('ok', false, 'error', 'completion_before_start');
  end if;

  select code, work_key into v_stage_code, v_stage_work_key
  from public.workshop_stages
  where id = v_booking.stage_id;

  if p_work_key is not null and btrim(p_work_key) <> '' then
    v_requested_stage := public.workshop_stage_code_for_work_key(p_work_key);
    if v_requested_stage is distinct from v_stage_code then
      raise exception 'Completion work item does not match booking station' using errcode = '22023';
    end if;
  end if;

  v_result := public.workshop_complete_booking(
    p_booking_id,
    p_expected_version,
    v_end,
    coalesce(p_metadata, '{}'::jsonb) || jsonb_build_object('database_clock_completion', p_actual_end_at is null)
  );
  if not coalesce((v_result->>'ok')::boolean, false) then
    return v_result;
  end if;

  IF v_booking.work_category IS NOT NULL THEN
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v_booking.vehicle_id)) l
   WHERE coalesce((l->>'active')::boolean,true) AND l->>'stage_code'=v_stage_code
    AND NOT pdc_work_categories_private.completed(v_booking.vehicle_id,l->>'work_category')) THEN
   RETURN v_result||jsonb_build_object('work_item_completed',false,'work_category_completed',v_booking.work_category,'revision',public.workshop_bump_revision());
  END IF;
 END IF;
 update public.vehicle_work_items
  set completed = true,
      completed_by = auth.uid(),
      completed_at = v_end,
      updated_at = statement_timestamp()
  where vehicle_id = v_booking.vehicle_id
    and required
    and public.workshop_stage_code_for_work_key(work_key) = v_stage_code;

  if not found and v_stage_work_key is not null then
    insert into public.vehicle_work_items (vehicle_id, work_key, required, completed, completed_by, completed_at)
    values (v_booking.vehicle_id, v_stage_work_key, true, true, auth.uid(), v_end)
    on conflict (vehicle_id, work_key) do update
    set required = true,
        completed = true,
        completed_by = auth.uid(),
        completed_at = excluded.completed_at,
        updated_at = statement_timestamp();
  end if;

  v_revision := public.workshop_bump_revision();
  return v_result || jsonb_build_object('revision', v_revision, 'work_item_completed', true);
end $function$;

CREATE OR REPLACE FUNCTION public.pdc_auditor_recalculate_required_work_226(p_vehicle_ids uuid[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_vehicle uuid; v_work_keys text[];
BEGIN
  FOR v_vehicle IN SELECT DISTINCT unnest(p_vehicle_ids) LOOP
    SELECT coalesce(array_agg(DISTINCT work_key),'{}'::text[]) INTO v_work_keys
    FROM (
      SELECT s.work_key
      FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v_vehicle)) l
      JOIN public.workshop_stages s ON s.code=l->>'stage_code'
      WHERE coalesce((l->>'active')::boolean,true)
        AND s.code IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET','PIT_INSPECTION')
      UNION
      SELECT e.work_key FROM public.pdc_effective_operation_lines e
      WHERE e.vehicle_id=v_vehicle AND e.active AND e.work_key IS NOT NULL
        AND public.pdc_qc_operation_lines_379(v_vehicle)='[]'::jsonb
    ) effective;
    -- A completed category is a versioned line scope. Newly accepted operations
    -- reopen the outstanding stage without changing historical bookings.
    UPDATE public.vehicle_work_items wi SET completed=false,completed_at=NULL,completed_by=NULL,
      required=true,updated_at=clock_timestamp()
    WHERE wi.vehicle_id=v_vehicle AND wi.work_key=(SELECT work_key FROM public.workshop_stages WHERE code='BUS_4X4')
      AND wi.completed AND EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.vehicle_id=v_vehicle
        AND b.work_category IS NOT NULL AND b.status='completed' AND b.deleted_at IS NULL)
      AND EXISTS(SELECT 1 FROM jsonb_array_elements(pdc_work_categories_private.vehicle_categories(v_vehicle)) c
        WHERE c->>'completed'='false');
    INSERT INTO public.vehicle_work_items(
      vehicle_id,work_key,required,completed,completed_by,completed_at,notes,updated_at
    )
    SELECT v_vehicle,work_key,true,false,null,null,null,clock_timestamp()
    FROM unnest(v_work_keys) work_key
    ON CONFLICT(vehicle_id,work_key) DO UPDATE
      SET required=true,updated_at=clock_timestamp()
      WHERE NOT public.vehicle_work_items.completed AND NOT public.vehicle_work_items.required;
    UPDATE public.vehicle_work_items wi SET required=false,updated_at=clock_timestamp()
    WHERE wi.vehicle_id=v_vehicle AND wi.required AND NOT wi.completed
      AND NOT (wi.work_key=ANY(v_work_keys));
  END LOOP;
END $function$;

CREATE OR REPLACE FUNCTION public.pdc_department138_station_20260917(p_description text)
RETURNS text LANGUAGE sql IMMUTABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
 SELECT pdc_work_categories_private.stage(pdc_work_categories_private.suggest(jsonb_build_object('department','138','description',p_description)))
$fn$;

CREATE OR REPLACE FUNCTION public.get_fitter_job(p_technician_id uuid, p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE b public.workshop_bookings; code text; lines jsonb;
BEGIN
 PERFORM public.require_pdc_role('viewer');
 IF NOT pdc_fitter_private.assigned(p_booking_id,p_technician_id)
 THEN RETURN jsonb_build_object('ok',false,'error','assignment_changed'); END IF;
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id;
 PERFORM public.workshop_require_booking_active_vehicle(p_booking_id,false);
 SELECT s.code INTO code FROM public.workshop_stages s WHERE s.id=b.stage_id;
 lines:=pdc_fitter_private.lines(b.vehicle_id,b.id);
 RETURN jsonb_build_object('ok',true,'booking_id',b.id,'version',b.version,
   'work_category',b.work_category,'vehicle_id',b.vehicle_id,'supplier_lines','[]'::jsonb,'status',b.status,'stage_code',code,'stoppage_reason',b.stoppage_reason,'lines',lines,
   'progress',pdc_fitter_private.summary(lines,code),
   'catalog_hash',md5((SELECT coalesce(jsonb_agg(l->>'scope_hash' ORDER BY l->>'line_identity'),'[]'::jsonb)::text
      FROM jsonb_array_elements(lines) l WHERE l->>'stage_code'=code)))
   ||pdc_fitter_private.timing(b.id,statement_timestamp())||pdc_bus_private.team_payload(b.id);
END $function$;

CREATE OR REPLACE FUNCTION public.book_all_vehicle_stations(p_vehicle_id uuid, p_expected_version integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
 v public.vehicles%rowtype; st record; bay record; item jsonb; result jsonb;
 pending jsonb:='[]'; booked jsonb:='[]'; skipped jsonb:='[]';
 minutes integer; best_minutes integer; increment integer; current_version integer;
 earliest timestamptz; horizon timestamptz; candidate timestamptz; finish timestamptz;
 blocked_until timestamptz; away_date date; best_start timestamptz; best_end timestamptz; best_bay integer;
 calendar_bay uuid;
 failure text; failure_code text;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'This action is available on staging only.'; END IF;
 PERFORM public.workshop_require_planner_operator();
 PERFORM public.workshop_require_version(p_expected_version);
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
 IF NOT FOUND OR v.deleted_at IS NOT NULL OR v.lifecycle_state<>'active' OR NOT v.visible_on_board THEN
  RAISE EXCEPTION 'This vehicle is not available for workshop booking.' USING DETAIL='vehicle_inactive_or_missing';
 END IF;
 IF v.version<>p_expected_version THEN RAISE EXCEPTION 'This vehicle changed. Refresh and try again.' USING DETAIL='vehicle_version_conflict'; END IF;
 IF public.workshop_location_code(coalesce(nullif(v.location_override,''),v.current_location)) NOT IN('PMB','YH','IT') OR coalesce(nullif(v.location_override,''),v.current_location) IS NULL THEN
  RAISE EXCEPTION 'Workshop booking requires PMB, Yard Hold or In Transit with an ETA.' USING DETAIL='location_ineligible';
 END IF;
 IF public.workshop_location_code(coalesce(nullif(v.location_override,''),v.current_location))='IT' AND v.eta_to_kewdale IS NULL THEN
  RAISE EXCEPTION 'Enter an ETA to Kewdale before booking this vehicle.' USING DETAIL='it_eta_missing';
 END IF;
 IF EXISTS(SELECT 1 FROM public.pdc_new_vehicle_reviews r WHERE r.vehicle_id=v.id AND r.status='pending') THEN
  RAISE EXCEPTION 'Approve the New Vehicles review before booking.' USING DETAIL='new_vehicle_review_required';
 END IF;
 -- Preflight every requirement before making any booking.
 FOR st IN SELECT s.*,cat->>'work_category' work_category FROM public.workshop_stages s
 CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN s.code='BUS_4X4'
 THEN pdc_work_categories_private.vehicle_categories(v.id) ELSE '[{}]'::jsonb END) cat
  WHERE s.active AND s.planner_enabled AND s.is_physical AND NOT s.is_sublet AND s.code<>'SUBLET'
   AND EXISTS(SELECT 1 FROM public.vehicle_work_items wi WHERE wi.vehicle_id=v.id AND wi.required AND NOT wi.completed AND public.workshop_stage_code_for_work_key(wi.work_key)=s.code)
  ORDER BY s.sort_order,s.code
 LOOP
  IF st.work_category IS NOT NULL AND pdc_work_categories_private.completed(v.id,st.work_category) THEN CONTINUE; END IF;
  IF EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.vehicle_id=v.id AND b.stage_id=st.id AND b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage') AND (st.work_category IS NULL OR b.work_category IS NULL OR b.work_category=st.work_category) AND b.bay_id IS NULL) THEN
   RAISE EXCEPTION '% has an existing booking without a bay. Allocate or cancel that booking first.',st.display_name USING DETAIL='existing_booking_without_bay';
  END IF;
  IF EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.vehicle_id=v.id AND b.stage_id=st.id AND b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage') AND (st.work_category IS NULL OR b.work_category IS NULL OR b.work_category=st.work_category)) THEN
   skipped:=skipped||jsonb_build_array(jsonb_build_object('stage',st.display_name,'reason','Already booked')); CONTINUE;
  END IF;
  minutes:=CASE WHEN st.work_category IS NULL THEN public.workshop_vehicle_stage_estimated_duration_minutes(v.id,st.id) ELSE round(pdc_work_categories_private.hours(v.id,st.work_category)*60)::integer END;
  IF minutes IS NULL OR minutes<1 THEN RAISE EXCEPTION 'Confirm the hours for % before booking all stations.',st.display_name USING DETAIL='estimated_duration_missing'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.workshop_bays b WHERE b.stage_id=st.id AND b.is_active) THEN RAISE EXCEPTION 'No active bay is configured for %.',st.display_name USING DETAIL='no_active_bay'; END IF;
  pending:=pending||jsonb_build_array(jsonb_build_object('id',st.id,'code',st.code,'name',coalesce(st.work_category,st.display_name),'minutes',minutes,'work_category',st.work_category));
 END LOOP;
 IF jsonb_array_length(pending)=0 THEN RETURN jsonb_build_object('ok',true,'bookings',booked,'skipped',skipped,'message','No unbooked workshop stations remain.'); END IF;
 SELECT greatest(1,coalesce((value#>>'{}')::integer,15)) INTO increment FROM public.workshop_settings WHERE key='scheduling_increment_minutes';
 increment:=coalesce(increment,15);
 earliest:=date_trunc('minute',clock_timestamp())+interval '1 minute';
 IF public.workshop_location_code(coalesce(nullif(v.location_override,''),v.current_location))='IT' THEN earliest:=greatest(earliest,(v.eta_to_kewdale+7)::timestamp AT TIME ZONE 'Australia/Perth'); END IF;
 horizon:=earliest+interval '300 days';
 FOR item IN SELECT value FROM jsonb_array_elements(pending) LOOP
  minutes:=(item->>'minutes')::integer; best_start:=NULL; best_end:=NULL; best_bay:=NULL;
  FOR bay IN SELECT * FROM public.workshop_bays WHERE stage_id=(item->>'id')::uuid AND is_active AND (item->>'work_category' IS NULL OR pdc_work_categories_private.preferred_bay(item->>'work_category',bay_number)) ORDER BY bay_number LOOP
   -- Preferred category bays still have vehicle compatibility requirements.
   IF item->>'code'='BUS_4X4' AND (pdc_bus_private.booking_rule(v.id,bay.id,NULL)->>'ok') IS DISTINCT FROM 'true' THEN CONTINUE; END IF;
   calendar_bay:=CASE WHEN item->>'code'='BUS_4X4' AND pdc_bus_private.active_vehicle(v.id) THEN bay.id END;
   minutes:=public.workshop_capacity_duration_minutes((item->>'minutes')::numeric,bay.id);
   candidate:=to_timestamp(ceil(extract(epoch FROM earliest)/(increment*60))*(increment*60));
   WHILE candidate<horizon AND (best_start IS NULL OR candidate<best_start) LOOP
    IF NOT (CASE WHEN calendar_bay IS NULL THEN public.workshop_calendar_minute_available(candidate) ELSE pdc_bus_private.minute_available(candidate,calendar_bay) END) THEN candidate:=candidate+make_interval(mins=>increment); CONTINUE; END IF;
    finish:=pdc_bus_private.clock_add_minutes(candidate,minutes,calendar_bay);
    IF finish>horizon THEN EXIT; END IF;
    -- A vehicle cannot work in a bay while it is away with a Sublet provider.
    SELECT d::date INTO away_date FROM generate_series((candidate AT TIME ZONE 'Australia/Perth')::date::timestamp,((finish-interval '1 minute') AT TIME ZONE 'Australia/Perth')::date::timestamp,interval '1 day') d
     WHERE public.pdc_sublet_away_on_date(v.id,d::date) ORDER BY d DESC LIMIT 1;
    IF FOUND THEN candidate:=(away_date+1)::timestamp AT TIME ZONE 'Australia/Perth'; CONTINUE; END IF;
    SELECT max(x.next_at) INTO blocked_until FROM (
     SELECT CASE WHEN b.vehicle_id=v.id THEN e.ends+interval '1 hour' ELSE e.ends END next_at
     FROM public.workshop_bookings b
     CROSS JOIN LATERAL(SELECT greatest(b.scheduled_end_at,public.workshop_booking_effective_end_at(b.id),CASE WHEN b.status IN('started','stoppage') THEN now() ELSE b.scheduled_end_at END) ends) e
     WHERE b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage') AND (b.vehicle_id=v.id OR b.bay_id=bay.id)
      AND ((b.vehicle_id=v.id AND b.scheduled_start_at<finish+interval '1 hour' AND e.ends+interval '1 hour'>candidate)
        OR (b.bay_id=bay.id AND b.scheduled_start_at<finish AND e.ends>candidate))
     UNION ALL
     SELECT a.scheduled_end_at FROM public.workshop_admin_blocks a WHERE a.deleted_at IS NULL AND a.bay_id=bay.id AND a.scheduled_start_at<finish AND a.scheduled_end_at>candidate
    ) x;
    IF blocked_until IS NOT NULL THEN
     candidate:=to_timestamp(ceil(extract(epoch FROM greatest(blocked_until,candidate+make_interval(mins=>increment)))/(increment*60))*(increment*60)); CONTINUE;
    END IF;
    best_start:=candidate; best_end:=finish; best_bay:=bay.bay_number; best_minutes:=minutes; EXIT;
   END LOOP;
  END LOOP;
  IF best_start IS NULL THEN RAISE EXCEPTION 'No available bay was found for % within the next 300 days.',item->>'name' USING DETAIL='no_available_slot'; END IF;
  SELECT version INTO current_version FROM public.vehicles WHERE id=v.id;
  result:=public.schedule_vehicle_work(v.id,current_version,item->>'code',best_bay,best_start,best_minutes,NULL,NULL,jsonb_build_object('source','book_all_stations','buffer_minutes',60,'work_category',item->>'work_category'));
  IF result->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Could not book % (%). Refresh and try again.',item->>'name',coalesce(result->>'error','schedule rejected') USING DETAIL='booking_rejected'; END IF;
  booked:=booked||jsonb_build_array(jsonb_build_object('stage',item->>'name','bay',best_bay,'start_at',best_start,'end_at',best_end,'booking_id',coalesce(result#>>'{booking,booking_id}',result#>>'{booking,id}')));
 END LOOP;
 RETURN jsonb_build_object('ok',true,'bookings',booked,'skipped',skipped,'buffer_minutes',60);
EXCEPTION WHEN OTHERS THEN
 GET STACKED DIAGNOSTICS failure=MESSAGE_TEXT,failure_code=PG_EXCEPTION_DETAIL;
 RETURN jsonb_build_object('ok',false,'error',coalesce(nullif(failure_code,''),SQLSTATE),'message',failure||' No new bookings were saved.');
END $function$;

DO $preserve$ DECLARE definition text; BEGIN SELECT pg_get_functiondef(p.oid) INTO STRICT definition FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='workshop_vehicle_stage_estimated_hours'; EXECUTE replace(definition,'FUNCTION public.workshop_vehicle_stage_estimated_hours(','FUNCTION pdc_work_categories_private.base_workshop_vehicle_stage_estimated_hours('); END $preserve$;

CREATE OR REPLACE FUNCTION public.workshop_vehicle_stage_estimated_hours(p_vehicle_id uuid,p_stage_code text)
RETURNS numeric LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
DECLARE lines jsonb; result numeric; stage text:=public.workshop_canonical_stage_code(p_stage_code);
BEGIN
 IF coalesce((public.pdc_qc_rework_scope_20260909(p_vehicle_id)->>'active')::boolean,false)
 THEN RETURN pdc_work_categories_private.base_workshop_vehicle_stage_estimated_hours(p_vehicle_id,p_stage_code); END IF;
 lines:=public.pdc_qc_operation_lines_379(p_vehicle_id);
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(lines) l WHERE l->>'department'='138')
 AND NOT EXISTS(SELECT 1 FROM pdc_work_categories_private.line_overrides WHERE vehicle_id=p_vehicle_id)
 THEN RETURN pdc_work_categories_private.base_workshop_vehicle_stage_estimated_hours(p_vehicle_id,p_stage_code); END IF;
 SELECT CASE WHEN count(*) FILTER(WHERE jsonb_typeof(l->'estimated_hours') IS DISTINCT FROM 'number')=0
 THEN nullif(sum((l->>'estimated_hours')::numeric),0) END INTO result
 FROM jsonb_array_elements(lines) l WHERE coalesce((l->>'active')::boolean,true) AND l->>'stage_code'=stage
 AND NOT pdc_work_categories_private.line_completed(p_vehicle_id,l);
 RETURN result;
END $fn$;

DO $requirements$
DECLARE ids uuid[];
BEGIN
 SELECT array_agg(DISTINCT o.vehicle_id) INTO ids FROM public.pdc_pilbara_service_operations o
 JOIN public.vehicles v ON v.id=o.vehicle_id
 WHERE o.department='138' AND v.deleted_at IS NULL AND v.lifecycle_state='active';
 IF ids IS NOT NULL THEN PERFORM public.pdc_auditor_recalculate_required_work_226(ids); END IF;
END $requirements$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA pdc_work_categories_private FROM PUBLIC,anon,authenticated;
