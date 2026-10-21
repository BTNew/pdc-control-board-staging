-- r450 undo (F63): restores the 14 functions, the pins (release, note, time), check bus_bay_guide_447 and constraint
-- workshop_work_category_valid exactly as before r450, drops the 3 whole_job_*_450 helpers and check bus_whole_job_450.
-- A whole-job booking cannot exist without r450: the undo refuses while any BUS_WHOLE_JOB booking row exists (active or done)
-- and says how many; return or finish them first, or keep r450. No booking, hours, override or history is changed.
-- Run between :02 and :45. Staging only.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r450 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r450 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r450 undo: clock tick changed (this release must not touch it)'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r450 undo: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_work_categories_private.allowed_bay(text,integer)')) IS DISTINCT FROM 'b229ccc9276b630905c49b8160b5644b' THEN RAISE EXCEPTION 'r450 undo: pdc_work_categories_private.allowed_bay(text,integer) is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_work_categories_private.capture_scope()')) IS DISTINCT FROM 'd04b1157c19a6dfbaf85e8afd55ca36d' THEN RAISE EXCEPTION 'r450 undo: pdc_work_categories_private.capture_scope() is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_work_categories_private.line_completed(uuid,jsonb)')) IS DISTINCT FROM 'bc3bf530a4538aef879c9a52ff70a377' THEN RAISE EXCEPTION 'r450 undo: pdc_work_categories_private.line_completed(uuid,jsonb) is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_work_categories_private.completed(uuid,text)')) IS DISTINCT FROM 'cb5cf573bdaf09c1d32071b584f6915a' THEN RAISE EXCEPTION 'r450 undo: pdc_work_categories_private.completed(uuid,text) is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_work_categories_private.vehicle_categories(uuid)')) IS DISTINCT FROM 'f8c064e6bcecad7ca35b5ec0f2e93144' THEN RAISE EXCEPTION 'r450 undo: pdc_work_categories_private.vehicle_categories(uuid) is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_work_categories_private.hours(uuid,text)')) IS DISTINCT FROM '8e832239aec841cda3c3c0ee20b58fa1' THEN RAISE EXCEPTION 'r450 undo: pdc_work_categories_private.hours(uuid,text) is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.confirm_bus_category_done(uuid,integer,text,text,text[])')) IS DISTINCT FROM '03d475905ce629d1e8e0843de4d9633e' THEN RAISE EXCEPTION 'r450 undo: public.confirm_bus_category_done(uuid,integer,text,text,text[]) is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_work_categories_private.minutes(uuid,uuid,uuid)')) IS DISTINCT FROM '8b0d6160a9b2233045b848c13602369a' THEN RAISE EXCEPTION 'r450 undo: pdc_work_categories_private.minutes(uuid,uuid,uuid) is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_work_categories_private.set_context(uuid,text,jsonb)')) IS DISTINCT FROM 'e570c65e575ced2c334ed300fbb72267' THEN RAISE EXCEPTION 'r450 undo: pdc_work_categories_private.set_context(uuid,text,jsonb) is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_work_categories_private.snapshot(jsonb)')) IS DISTINCT FROM 'a5d08b2454ae9074379f75e8b40777c1' THEN RAISE EXCEPTION 'r450 undo: pdc_work_categories_private.snapshot(jsonb) is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_fitter_private.lines(uuid,uuid)')) IS DISTINCT FROM '6773b7cf4e6bc040f14fc39548f77797' THEN RAISE EXCEPTION 'r450 undo: pdc_fitter_private.lines(uuid,uuid) is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.book_all_vehicle_stations(uuid,integer)')) IS DISTINCT FROM '90fc0d4727d827db53c308ff9dfa8bcd' THEN RAISE EXCEPTION 'r450 undo: public.book_all_vehicle_stations(uuid,integer) is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.set_vehicle_work_category(uuid,integer,text,text,integer)')) IS DISTINCT FROM '1c0424ad5da9a534ea4ae7b0ebae5c29' THEN RAISE EXCEPTION 'r450 undo: public.set_vehicle_work_category(uuid,integer,text,text,integer) is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_work_categories_private.before_import_rules_20261017(uuid)')) IS DISTINCT FROM 'dc2737a6264c179314041fe41845ae87' THEN RAISE EXCEPTION 'r450 undo: pdc_work_categories_private.before_import_rules_20261017(uuid) is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_work_categories_private.whole_job_lines_450(uuid,uuid)')) IS DISTINCT FROM 'ac270eeffc881c6fa4af76ca695ef159' THEN RAISE EXCEPTION 'r450 undo: pdc_work_categories_private.whole_job_lines_450(uuid,uuid) is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_work_categories_private.whole_job_hours_450(uuid,uuid)')) IS DISTINCT FROM '9175876875091136899bfa2678fe97fe' THEN RAISE EXCEPTION 'r450 undo: pdc_work_categories_private.whole_job_hours_450(uuid,uuid) is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_work_categories_private.whole_job_covers_450(uuid,text)')) IS DISTINCT FROM 'f6b0b562f2dba1b4fb585eeaaa8cae4a' THEN RAISE EXCEPTION 'r450 undo: pdc_work_categories_private.whole_job_covers_450(uuid,text) is not the expected version'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='bus_whole_job_450' AND added_in='r450') IS DISTINCT FROM '7d6f5fdff816778f5c2c10c943ada173' THEN RAISE EXCEPTION 'r450 undo: check is not the r450 version'; END IF;
 IF EXISTS(SELECT 1 FROM public.workshop_bookings WHERE work_category='BUS_WHOLE_JOB') THEN
  RAISE EXCEPTION 'r450 undo: % whole-job booking(s) exist (% active). Nothing was changed.',
   (SELECT count(*) FROM public.workshop_bookings WHERE work_category='BUS_WHOLE_JOB'),
   (SELECT count(*) FROM public.workshop_bookings WHERE work_category='BUS_WHOLE_JOB' AND deleted_at IS NULL AND status IN('queued','planned','started','stoppage'));
 END IF;
END $g$;

CREATE OR REPLACE FUNCTION pdc_work_categories_private.allowed_bay(category text, bay integer)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
 -- r447 (F60): no warning in the category's own bays or in the overflow Bays 5-6 (any Bus 4x4 work). Anything else is
 -- warn-and-confirm with a logged override (pdc_bay_rules_private, r417).
 SELECT pdc_work_categories_private.preferred_bay(category,bay)
  OR (bay IN (5,6) AND category IN ('BUS_MECHANICAL','BUS_ELECTRICAL','BUS_ACCESSORIES','BUS_QA'))
$function$
;
CREATE OR REPLACE FUNCTION pdc_work_categories_private.capture_scope()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
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
 IF NEW.deleted_at IS NULL AND NEW.status IN('queued','planned','started','stoppage')
    AND NEW.bay_id IS NOT NULL
    AND NOT EXISTS(SELECT 1 FROM public.workshop_bays bay WHERE bay.id=NEW.bay_id
      AND pdc_work_categories_private.allowed_bay(NEW.work_category,bay.bay_number))
    -- r417 (F32): a planner-confirmed, logged override lets this one booking use this bay.
    AND NOT pdc_bay_rules_private.override_active(NEW.id,NEW.vehicle_id,NEW.bay_id,'category_bay_mismatch') THEN
  IF NOT (TG_OP='UPDATE' AND OLD.status='started' AND NEW.status='stoppage'
    AND OLD.actual_start_at IS NOT NULL AND OLD.deleted_at IS NULL
    AND NEW.vehicle_id=OLD.vehicle_id AND NEW.stage_id=OLD.stage_id AND NEW.bay_id=OLD.bay_id
    AND NEW.scheduled_start_at=OLD.scheduled_start_at AND NEW.scheduled_end_at=OLD.scheduled_end_at
    AND NEW.default_duration_minutes=OLD.default_duration_minutes) THEN
    RAISE EXCEPTION 'category_bay_mismatch' USING ERRCODE='22023';
  END IF;
 END IF;

 -- Both category and old whole-job bookings reserve the same real vehicle/bay.
 IF NEW.deleted_at IS NULL AND NEW.status IN('queued','planned','started','stoppage') AND EXISTS(
  SELECT 1 FROM public.workshop_bookings b WHERE b.vehicle_id=NEW.vehicle_id AND b.stage_id=NEW.stage_id AND b.id<>NEW.id
  AND b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage')
  AND (b.work_category IS NULL OR b.work_category=NEW.work_category)) THEN
  RAISE EXCEPTION 'This category already has an active booking, or an existing whole-job booking needs to be returned first';
 END IF;
 RETURN NEW;
END $function$
;
CREATE OR REPLACE FUNCTION pdc_work_categories_private.line_completed(vehicle uuid, line jsonb)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
 SELECT EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.vehicle_id=vehicle
  AND b.work_category=line->>'work_category' AND b.status='completed' AND b.deleted_at IS NULL
  AND b.work_category_scope->>(line->>'line_identity')=pdc_work_categories_private.line_hash(line))
 -- r399: or a manager confirmed this exact line version was done before the board.
 OR EXISTS(SELECT 1 FROM pdc_work_categories_private.offboard_done o WHERE o.vehicle_id=vehicle AND o.line_identity=line->>'line_identity'
  AND o.revoked_at IS NULL AND o.work_category=line->>'work_category' AND o.line_hash=pdc_work_categories_private.line_hash(line))
$function$
;
CREATE OR REPLACE FUNCTION pdc_work_categories_private.completed(vehicle uuid, category text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
 SELECT count(*)>0 AND bool_and(EXISTS(SELECT 1 FROM public.workshop_bookings b
  WHERE b.vehicle_id=vehicle AND b.work_category=category AND b.status='completed' AND b.deleted_at IS NULL
    AND b.work_category_scope->>(l->>'line_identity')=pdc_work_categories_private.line_hash(l))
  -- r399: same rule as line_completed: or a manager confirmed this exact line version was done before the board.
  OR EXISTS(SELECT 1 FROM pdc_work_categories_private.offboard_done o WHERE o.vehicle_id=vehicle AND o.line_identity=l->>'line_identity'
    AND o.revoked_at IS NULL AND o.work_category=category AND o.line_hash=pdc_work_categories_private.line_hash(l)))
 FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(vehicle)) l
 WHERE coalesce((l->>'active')::boolean,true) AND l->>'work_category'=category
$function$
;
CREATE OR REPLACE FUNCTION pdc_work_categories_private.vehicle_categories(vehicle uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
 WITH lines AS MATERIALIZED(SELECT l,pdc_work_categories_private.line_completed(vehicle,l) done FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(vehicle)) l
 WHERE coalesce((l->>'active')::boolean,true) AND l->>'stage_code'='BUS_4X4'
 -- r405 (F14): a Pit and weigh line filed under Bus 4x4 never counts towards a Bus category (hours or completion).
 AND NOT public.pdc_line_is_pit_401(vehicle,l)),
 categories AS (SELECT l->>'work_category' category,
 CASE WHEN count(*) FILTER(WHERE NOT done AND jsonb_typeof(l->'estimated_hours') IS DISTINCT FROM 'number')=0 THEN coalesce(sum((l->>'estimated_hours')::numeric) FILTER(WHERE NOT done),0) END hours,
 bool_and(done) completed
 FROM lines GROUP BY l->>'work_category')
 SELECT coalesce(jsonb_agg(jsonb_build_object('work_category',category,'estimated_hours',hours,'completed',completed,
 'existing_booking',EXISTS(SELECT 1 FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
  WHERE b.vehicle_id=vehicle AND s.code='BUS_4X4' AND b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage')
  AND (b.work_category IS NULL OR b.work_category=category)),
 'schedule_enabled',coalesce(hours>0,false) AND NOT completed,
 'disabled_reason',CASE WHEN hours IS NULL OR hours<=0 THEN 'estimated_duration_missing' END,
 'offboard_confirmed',EXISTS(SELECT 1 FROM pdc_work_categories_private.offboard_done o WHERE o.vehicle_id=vehicle AND o.work_category=category AND o.revoked_at IS NULL))),'[]'::jsonb) FROM categories
$function$
;
CREATE OR REPLACE FUNCTION pdc_work_categories_private.hours(vehicle uuid, category text)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
 SELECT CASE WHEN count(*)=0 THEN 0 WHEN count(*) FILTER(WHERE jsonb_typeof(l->'estimated_hours') IS DISTINCT FROM 'number')=0
 THEN sum((l->>'estimated_hours')::numeric) ELSE NULL END
 FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(vehicle)) l
 WHERE coalesce((l->>'active')::boolean,true) AND l->>'work_category'=category AND NOT pdc_work_categories_private.line_completed(vehicle,l)
$function$
;
CREATE OR REPLACE FUNCTION public.confirm_bus_category_done(p_vehicle_id uuid, p_vehicle_expected_version integer, p_category text, p_reason text, p_line_identities text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE v public.vehicles; why text:=btrim(coalesce(p_reason,'')); outstanding jsonb; picked jsonb; b record; r jsonb; released jsonb:='[]'::jsonb;
BEGIN
 IF auth.uid() IS NULL OR coalesce(public.current_pdc_user_role()::text,'') NOT IN ('operator','administrator') THEN
  RAISE EXCEPTION 'Operator or administrator role required' USING ERRCODE='42501';
 END IF;
 IF p_category IS NULL OR p_category NOT IN ('BUS_MECHANICAL','BUS_ELECTRICAL','BUS_ACCESSORIES') THEN
  RETURN jsonb_build_object('ok',false,'error','category_not_confirmable','message','Only Mechanical, Electrical or Accessories work can be confirmed as done off the board. QA stays on the board in Bay 7.');
 END IF;
 IF length(why) NOT BETWEEN 5 AND 500 THEN
  RETURN jsonb_build_object('ok',false,'error','reason_required','message','Enter a reason of 5 to 500 characters, for example who did the work and when.');
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id AND deleted_at IS NULL AND lifecycle_state='active' FOR UPDATE;
 IF NOT FOUND OR v.version IS DISTINCT FROM p_vehicle_expected_version THEN RETURN jsonb_build_object('ok',false,'error','vehicle_version_conflict'); END IF;
 IF EXISTS(SELECT 1 FROM public.workshop_bookings bk JOIN public.workshop_stages s ON s.id=bk.stage_id WHERE bk.vehicle_id=v.id AND s.code='BUS_4X4'
   AND bk.deleted_at IS NULL AND bk.work_category IS NULL AND bk.status IN('queued','planned','started','stoppage')) THEN
  RETURN jsonb_build_object('ok',false,'error','whole_job_booking_exists','message','This job still has a whole-job Bus 4x4 booking. Split it into categories first.');
 END IF;
 IF EXISTS(SELECT 1 FROM public.workshop_bookings bk JOIN public.workshop_stages s ON s.id=bk.stage_id WHERE bk.vehicle_id=v.id AND s.code='BUS_4X4'
   AND bk.deleted_at IS NULL AND bk.work_category=p_category AND (bk.status IN('started','stoppage') OR (bk.status IN('queued','planned') AND bk.actual_start_at IS NOT NULL))) THEN
  RETURN jsonb_build_object('ok',false,'error','category_booking_started','message','This work has already been started on the board. Finish it with Done on the bay instead.');
 END IF;
 SELECT coalesce(jsonb_agg(l),'[]'::jsonb) INTO outstanding FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(v.id)) l
  WHERE coalesce((l->>'active')::boolean,true) AND l->>'stage_code'='BUS_4X4' AND l->>'work_category'=p_category
   AND NOT pdc_work_categories_private.line_completed(v.id,l);
 IF p_line_identities IS NOT NULL AND (cardinality(p_line_identities)=0 OR EXISTS(SELECT 1 FROM unnest(p_line_identities) i
   WHERE NOT EXISTS(SELECT 1 FROM jsonb_array_elements(outstanding) l WHERE l->>'line_identity'=i))) THEN
  RETURN jsonb_build_object('ok',false,'error','line_not_outstanding','message','A selected line is not outstanding in this category. Refresh and try again.');
 END IF;
 SELECT coalesce(jsonb_agg(l),'[]'::jsonb) INTO picked FROM jsonb_array_elements(outstanding) l
  WHERE p_line_identities IS NULL OR l->>'line_identity'=ANY(p_line_identities);
 IF jsonb_array_length(picked)=0 THEN RETURN jsonb_build_object('ok',false,'error','nothing_outstanding','message','No outstanding work in this category.'); END IF;
 -- Unstarted bookings of this category reserve hours for work that is now done: release them (kept in history).
 FOR b IN SELECT bk.id, bk.version FROM public.workshop_bookings bk JOIN public.workshop_stages s ON s.id=bk.stage_id
   WHERE bk.vehicle_id=v.id AND s.code='BUS_4X4' AND bk.deleted_at IS NULL AND bk.work_category=p_category
    AND bk.status IN('queued','planned') AND bk.actual_start_at IS NULL ORDER BY bk.id LOOP
  r:=public.cancel_workshop_booking(b.id,b.version,'Confirmed done off the board: '||why,jsonb_build_object('source','confirm_bus_category_done_399'));
  IF NOT coalesce((r->>'ok')::boolean,false) THEN RAISE EXCEPTION 'r399: releasing booking % failed: %', b.id, r USING ERRCODE='P0001'; END IF;
  released:=released||jsonb_build_array(b.id);
 END LOOP;
 INSERT INTO pdc_work_categories_private.offboard_done(vehicle_id,work_category,line_identity,line_hash,line_snapshot,reason,confirmed_by)
 SELECT v.id,p_category,l->>'line_identity',pdc_work_categories_private.line_hash(l),
   jsonb_build_object('description',l->'description','estimated_hours',l->'estimated_hours','job_card',coalesce(l->'job_card_number',l->'job_card')),why,auth.uid()
 FROM jsonb_array_elements(picked) l;
 UPDATE public.vehicles SET version=version+1,updated_at=clock_timestamp(),updated_by=auth.uid() WHERE id=v.id;
 INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
 VALUES('update','vehicle_work_category_offboard_done',v.id,v.id,auth.uid(),public.current_actor_email(),NULL,
  jsonb_build_object('work_category',p_category,'lines',(SELECT jsonb_agg(jsonb_build_object('line_identity',l->>'line_identity','estimated_hours',l->'estimated_hours')) FROM jsonb_array_elements(picked) l),'released_bookings',released),
  jsonb_build_object('source','confirm_bus_category_done_399','reason',why,'source_hours_preserved',true));
 RETURN jsonb_build_object('ok',true,'work_category',p_category,'lines_confirmed',jsonb_array_length(picked),
  'hours_confirmed',(SELECT sum((l->>'estimated_hours')::numeric) FROM jsonb_array_elements(picked) l WHERE jsonb_typeof(l->'estimated_hours')='number'),
  'released_bookings',released,'vehicle_version',v.version+1,'revision',public.workshop_bump_revision());
END $function$
;
CREATE OR REPLACE FUNCTION pdc_work_categories_private.minutes(booking uuid, vehicle uuid, stage uuid)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE category text; hrs numeric;
BEGIN
 category:=pdc_work_categories_private.booking_category(booking,vehicle,stage);
 IF category IS NULL THEN RETURN public.workshop_vehicle_stage_estimated_duration_minutes(vehicle,stage); END IF;
 hrs:=pdc_work_categories_private.hours(vehicle,category);
 RETURN CASE WHEN hrs>0 THEN greatest(1,round(hrs*60)::integer) ELSE NULL END;
END $function$
;
CREATE OR REPLACE FUNCTION pdc_work_categories_private.set_context(vehicle uuid, stage text, metadata jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE category text:=nullif(metadata->>'work_category','');
BEGIN
 PERFORM public.workshop_require_planner_operator();
 IF category IS NOT NULL THEN
  IF category NOT IN('BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA')
  OR public.workshop_canonical_stage_code(stage) IS DISTINCT FROM 'BUS_4X4' THEN RAISE EXCEPTION 'Invalid work category'; END IF;
  IF pdc_work_categories_private.completed(vehicle,category) THEN RAISE EXCEPTION 'This work category is already complete'; END IF;
 END IF;
 PERFORM set_config('pdc.work_category',jsonb_build_object('actor',auth.uid(),'vehicle',vehicle,'category',category)::text,true);
END $function$
;
CREATE OR REPLACE FUNCTION pdc_work_categories_private.snapshot(snapshot jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
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
END $function$
;
CREATE OR REPLACE FUNCTION pdc_fitter_private.lines(p_vehicle_id uuid, p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
 WITH booking AS(SELECT work_category,work_category_scope,status FROM public.workshop_bookings WHERE id=p_booking_id),
 canonical AS MATERIALIZED(SELECT l FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) l)
 SELECT coalesce(jsonb_agg(a.l||jsonb_build_object('work_category',c.l->>'work_category','zero_hour_task',c.l->'zero_hour_task') ORDER BY ord),'[]'::jsonb)
 FROM jsonb_array_elements(pdc_work_categories_private.base_lines(p_vehicle_id,p_booking_id)) WITH ORDINALITY a(l,ord)
 LEFT JOIN canonical c ON c.l->>'line_identity'=a.l->>'line_identity'
 WHERE (SELECT work_category FROM booking) IS NULL OR (c.l->>'work_category'=(SELECT work_category FROM booking)
  AND ((SELECT work_category_scope FROM booking) ? (c.l->>'line_identity')
    OR ((SELECT status FROM booking)<>'completed' AND NOT pdc_work_categories_private.line_completed(p_vehicle_id,c.l))))
$function$
;
CREATE OR REPLACE FUNCTION public.book_all_vehicle_stations(p_vehicle_id uuid, p_expected_version integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
 SET lock_timeout TO '45s'
 SET statement_timeout TO '75s'
AS $function$
DECLARE
 v public.vehicles%rowtype; st record; bay record; item jsonb; result jsonb;
 pending jsonb:='[]'; booked jsonb:='[]'; skipped jsonb:='[]';
 minutes integer; best_minutes integer; increment integer; current_version integer;
 earliest timestamptz; horizon timestamptz; candidate timestamptz; finish timestamptz;
 blocked_until timestamptz; away_date date; best_start timestamptz; best_end timestamptz; best_bay integer;
 calendar_bay uuid;
 failure text; failure_code text;
 busy_rows jsonb;
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
  -- Freeze relevant conflicts once per station under the existing mutation lock.
  -- Rebuild after each saved station so all canonical effects remain visible.
  SELECT coalesce(jsonb_agg(jsonb_build_object(
   'vehicle_id',b.vehicle_id,'bay_id',b.bay_id,'starts',b.scheduled_start_at,
   'ends',greatest(b.scheduled_end_at,public.workshop_booking_effective_end_at(b.id),
    CASE WHEN b.status IN('started','stoppage') THEN now() ELSE b.scheduled_end_at END))),'[]')
   INTO busy_rows
   FROM public.workshop_bookings b
   WHERE b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage')
    AND (b.vehicle_id=v.id OR b.stage_id=(item->>'id')::uuid);
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
     FROM jsonb_to_recordset(busy_rows) b(vehicle_id uuid,bay_id uuid,starts timestamptz,ends timestamptz)
     CROSS JOIN LATERAL(SELECT b.ends) e
     WHERE (b.vehicle_id=v.id OR b.bay_id=bay.id)
      AND ((b.vehicle_id=v.id AND b.starts<finish+interval '1 hour' AND e.ends+interval '1 hour'>candidate)
        OR (b.bay_id=bay.id AND b.starts<finish AND e.ends>candidate))
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
END $function$
;
CREATE OR REPLACE FUNCTION public.set_vehicle_work_category(p_vehicle_id uuid, p_vehicle_expected_version integer, p_line_identity text, p_category text, p_category_expected_version integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
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
END $function$
;
CREATE OR REPLACE FUNCTION pdc_work_categories_private.before_import_rules_20261017(p_vehicle_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
 WITH source AS MATERIALIZED(SELECT l,ord FROM jsonb_array_elements(pdc_work_categories_private.base_pdc_qc_operation_lines_379(p_vehicle_id)) WITH ORDINALITY a(l,ord)),
 projected AS MATERIALIZED (SELECT l,ord,o.category override_category,o.version category_version,
   a.adjustment_id,a.manual_assignment_locked,a.stage_code saved_stage,r.category owner_reviewed_category,
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
$function$
;

UPDATE pdc_ops.regression_checks SET check_sql=replace(check_sql,'e.signature IN (''pdc_work_categories_private.preferred_bay(text,integer)'',''pdc_work_categories_private.allowed_bay(text,integer)'')','e.release=''r447''')
 WHERE check_name='bus_bay_guide_447';
DELETE FROM pdc_ops.regression_checks WHERE check_name='bus_whole_job_450' AND added_in='r450';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='bb83ffbf0580d6a384dc28b04d9361ea',release='r447',note='r447: Dept 138 bay guide, no-warning bays incl. overflow 5-6 (F60)',updated_at='2026-10-21 10:46:12.483541+00' WHERE signature='pdc_work_categories_private.allowed_bay(text,integer)';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='8c82869f9c236c2d89ab10de6e6e47fa',release='r417',note='F32: bay rule mismatch warns; confirmed overrides are logged',updated_at='2026-10-20 23:36:17.059572+00' WHERE signature='pdc_work_categories_private.capture_scope()';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='0c8cc64db074645da4adea3be9d15a79',release='r399',note=NULL,updated_at='2026-10-20 10:55:01.195622+00' WHERE signature='pdc_work_categories_private.line_completed(uuid,jsonb)';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='7039c06acd173d890c4d7ffbdd4b749d',release='r399',note=NULL,updated_at='2026-10-20 10:55:01.195622+00' WHERE signature='pdc_work_categories_private.completed(uuid,text)';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='6c295090fc3bb9b500eef31072bcfe5f',release='r405',note='Bus categories ignore Pit lines (r405)',updated_at='2026-10-20 13:54:27.067868+00' WHERE signature='pdc_work_categories_private.vehicle_categories(uuid)';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='e01e0cd55ddb1b8d05d6ec952debf8d6',release='baseline',note=NULL,updated_at='2026-10-20 10:55:01.195622+00' WHERE signature='pdc_work_categories_private.hours(uuid,text)';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='77925eadb63b0433cdb4580acf2be911',release='r399',note=NULL,updated_at='2026-10-20 10:55:01.195622+00' WHERE signature='public.confirm_bus_category_done(uuid,integer,text,text,text[])';
DELETE FROM pdc_ops.expected_function_md5 WHERE release='r450' AND signature IN ('pdc_work_categories_private.minutes(uuid,uuid,uuid)','pdc_work_categories_private.set_context(uuid,text,jsonb)','pdc_work_categories_private.snapshot(jsonb)','pdc_fitter_private.lines(uuid,uuid)','public.book_all_vehicle_stations(uuid,integer)','public.set_vehicle_work_category(uuid,integer,text,text,integer)','pdc_work_categories_private.before_import_rules_20261017(uuid)','pdc_work_categories_private.whole_job_lines_450(uuid,uuid)','pdc_work_categories_private.whole_job_hours_450(uuid,uuid)','pdc_work_categories_private.whole_job_covers_450(uuid,text)');
DROP FUNCTION pdc_work_categories_private.whole_job_lines_450(uuid,uuid);
DROP FUNCTION pdc_work_categories_private.whole_job_hours_450(uuid,uuid);
DROP FUNCTION pdc_work_categories_private.whole_job_covers_450(uuid,text);
ALTER TABLE public.workshop_bookings DROP CONSTRAINT workshop_work_category_valid,
 ADD CONSTRAINT workshop_work_category_valid CHECK (((work_category IS NULL) OR (work_category = ANY (ARRAY['BUS_MECHANICAL'::text, 'BUS_ACCESSORIES'::text, 'BUS_ELECTRICAL'::text, 'BUS_QA'::text]))));

DO $g$ BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_work_categories_private.allowed_bay(text,integer)')) IS DISTINCT FROM 'bb83ffbf0580d6a384dc28b04d9361ea' THEN RAISE EXCEPTION 'r450 undo: pdc_work_categories_private.allowed_bay(text,integer) is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_work_categories_private.capture_scope()')) IS DISTINCT FROM '8c82869f9c236c2d89ab10de6e6e47fa' THEN RAISE EXCEPTION 'r450 undo: pdc_work_categories_private.capture_scope() is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_work_categories_private.line_completed(uuid,jsonb)')) IS DISTINCT FROM '0c8cc64db074645da4adea3be9d15a79' THEN RAISE EXCEPTION 'r450 undo: pdc_work_categories_private.line_completed(uuid,jsonb) is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_work_categories_private.completed(uuid,text)')) IS DISTINCT FROM '7039c06acd173d890c4d7ffbdd4b749d' THEN RAISE EXCEPTION 'r450 undo: pdc_work_categories_private.completed(uuid,text) is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_work_categories_private.vehicle_categories(uuid)')) IS DISTINCT FROM '6c295090fc3bb9b500eef31072bcfe5f' THEN RAISE EXCEPTION 'r450 undo: pdc_work_categories_private.vehicle_categories(uuid) is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_work_categories_private.hours(uuid,text)')) IS DISTINCT FROM 'e01e0cd55ddb1b8d05d6ec952debf8d6' THEN RAISE EXCEPTION 'r450 undo: pdc_work_categories_private.hours(uuid,text) is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.confirm_bus_category_done(uuid,integer,text,text,text[])')) IS DISTINCT FROM '77925eadb63b0433cdb4580acf2be911' THEN RAISE EXCEPTION 'r450 undo: public.confirm_bus_category_done(uuid,integer,text,text,text[]) is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_work_categories_private.minutes(uuid,uuid,uuid)')) IS DISTINCT FROM '0c8423441e81705290d74f4a85c78ea2' THEN RAISE EXCEPTION 'r450 undo: pdc_work_categories_private.minutes(uuid,uuid,uuid) is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_work_categories_private.set_context(uuid,text,jsonb)')) IS DISTINCT FROM 'a66b8e0030adde2b4639abf92539b8a5' THEN RAISE EXCEPTION 'r450 undo: pdc_work_categories_private.set_context(uuid,text,jsonb) is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_work_categories_private.snapshot(jsonb)')) IS DISTINCT FROM '5d7fb5593c83e4814ad526c61fcffcb2' THEN RAISE EXCEPTION 'r450 undo: pdc_work_categories_private.snapshot(jsonb) is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_fitter_private.lines(uuid,uuid)')) IS DISTINCT FROM '28c3949d357c203601bfbee42da6c879' THEN RAISE EXCEPTION 'r450 undo: pdc_fitter_private.lines(uuid,uuid) is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.book_all_vehicle_stations(uuid,integer)')) IS DISTINCT FROM '272096219f487881fdb31f4b9d6386ac' THEN RAISE EXCEPTION 'r450 undo: public.book_all_vehicle_stations(uuid,integer) is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.set_vehicle_work_category(uuid,integer,text,text,integer)')) IS DISTINCT FROM '924d52a4385346c34d39870466bed4ce' THEN RAISE EXCEPTION 'r450 undo: public.set_vehicle_work_category(uuid,integer,text,text,integer) is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('pdc_work_categories_private.before_import_rules_20261017(uuid)')) IS DISTINCT FROM 'ba18b6fbdbbfbf44c68cee8c5599968b' THEN RAISE EXCEPTION 'r450 undo: pdc_work_categories_private.before_import_rules_20261017(uuid) is not the expected version'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>168 OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r450') THEN RAISE EXCEPTION 'r450 undo: pins not restored'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='bus_bay_guide_447') IS DISTINCT FROM '77df90f3b79ed50823d68f6bef1bc3f2' THEN RAISE EXCEPTION 'r450 undo: bus_bay_guide_447 not restored'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r450' OR sort_order=249) OR to_regprocedure('pdc_work_categories_private.whole_job_lines_450(uuid,uuid)') IS NOT NULL THEN RAISE EXCEPTION 'r450 undo: not fully removed'; END IF;
 IF (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid='public.workshop_bookings'::regclass AND conname='workshop_work_category_valid') IS DISTINCT FROM 'CHECK (((work_category IS NULL) OR (work_category = ANY (ARRAY[''BUS_MECHANICAL''::text, ''BUS_ACCESSORIES''::text, ''BUS_ELECTRICAL''::text, ''BUS_QA''::text]))))' THEN RAISE EXCEPTION 'r450 undo: constraint not restored'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r450 undo: clock tick changed'; END IF;
END $g$;
