-- r399 Bay 8 Electrical (Bhavesh, 20 Oct 2026 18:16 AWST). Staging cdsmnqxtyyoeoznmbidd only.
-- Cause: Key 504's only open Bus item on the board was its 74.5 h Mechanical booking (the 4x4 conversion was finished
-- before the board went live, but the board can only learn that from a completed bay booking). In the all-bays view the
-- schedule dialog offered every bay, so placing that Mechanical item in Bay 8 was correctly refused (category_bay_mismatch).
-- The Electrical work of 504 and 509 was always bookable in Bay 8.
-- 1. Managers (planner operator or administrator) can confirm Mechanical, Electrical or Accessories work as done off the
--    board, with a reason. Each confirmed line is recorded with its exact line hash (an edited line reopens), the original
--    hours/overrides/lines are untouched, unstarted bookings of that category are released through cancel_workshop_booking
--    (kept in history), and the confirmation is audited and can be undone. QA cannot be confirmed (stays in Bay 7).
-- 2. The conversion completion guard accepts a confirmed conversion line (its sections were never ticked on the board).
-- 3. Same root cause as r390 in a sibling gate: the non-Navision Dept 138 read required every open job to be 138-only,
--    so the Dept 138 delegated search/detail refused mixed 138/139 Tune vehicles (Key 509, Key 338): "Bookings could not
--    be checked". It now accepts the same 138/139 mix as r390; a Dept 138 job with evidence is still required.
-- Bay rules (preferred_bay, allowed_bay, capture_scope, booking_rule incl. Bay 3 HiAce-only) are unchanged.
-- Undo: supabase/rollbacks/<version>_r399_bay8_offboard_done.down.sql
DO $g$
DECLARE live jsonb;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.pdc_staging_environment_sentinel WHERE project_ref='cdsmnqxtyyoeoznmbidd')
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r399: staging cdsmnqxtyyoeoznmbidd only'; END IF;
 SELECT jsonb_object_agg(p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid))) INTO live FROM pg_proc p
  WHERE p.oid IN ('pdc_fitter_private.conversion_completion_guard()'::regprocedure,'pdc_codex_intake_private.workshop_nonnav138_read_allowed_20261012(jsonb,uuid,text)'::regprocedure,'pdc_work_categories_private.line_completed(uuid,jsonb)'::regprocedure,'pdc_work_categories_private.completed(uuid,text)'::regprocedure,'pdc_work_categories_private.vehicle_categories(uuid)'::regprocedure);
 IF live IS DISTINCT FROM '{"pdc_fitter_private.conversion_completion_guard()": "78031e2a1e71419627d1d3489610b588", "pdc_codex_intake_private.workshop_nonnav138_read_allowed_20261012(jsonb,uuid,text)": "2349b0df7e798906b00bd15a602e4ddf", "pdc_work_categories_private.line_completed(uuid,jsonb)": "b7f9842f3436df077172d70c59a23d30", "pdc_work_categories_private.completed(uuid,text)": "fe87953c3ada552d7aa3e6e2b409c828", "pdc_work_categories_private.vehicle_categories(uuid)": "622f4e0e720b610644b8186fd660f680"}'::jsonb THEN RAISE EXCEPTION 'r399: live functions are not the expected bodies: %', live; END IF;
 IF to_regclass('pdc_work_categories_private.offboard_done') IS NOT NULL THEN RAISE EXCEPTION 'r399: already applied'; END IF;
END $g$;

CREATE TABLE pdc_work_categories_private.offboard_done(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 vehicle_id uuid NOT NULL REFERENCES public.vehicles(id),
 work_category text NOT NULL CHECK (work_category IN ('BUS_MECHANICAL','BUS_ELECTRICAL','BUS_ACCESSORIES')),
 line_identity text NOT NULL,
 line_hash text NOT NULL,
 line_snapshot jsonb NOT NULL,
 reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 5 AND 500),
 confirmed_by uuid NOT NULL,
 confirmed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 revoked_at timestamptz,
 revoked_by uuid,
 revoke_reason text,
 CHECK ((revoked_at IS NULL) = (revoked_by IS NULL) AND (revoked_at IS NULL) = (revoke_reason IS NULL)));
CREATE UNIQUE INDEX offboard_done_active ON pdc_work_categories_private.offboard_done(vehicle_id,line_identity) WHERE revoked_at IS NULL;
ALTER TABLE pdc_work_categories_private.offboard_done ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_work_categories_private.offboard_done FROM PUBLIC, anon, authenticated;

CREATE FUNCTION pdc_work_categories_private.offboard_line_done(vehicle uuid, line jsonb)
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog'
AS $function$
 SELECT EXISTS(SELECT 1 FROM pdc_work_categories_private.offboard_done o WHERE o.vehicle_id=vehicle
  AND o.line_identity=line->>'line_identity' AND o.work_category=line->>'work_category' AND o.revoked_at IS NULL
  AND o.line_hash=pdc_work_categories_private.line_hash(line))
$function$;
CREATE FUNCTION pdc_work_categories_private.offboard_identity_done(vehicle uuid, identity text)
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog'
AS $function$
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM pdc_work_categories_private.offboard_done o
   WHERE o.vehicle_id=vehicle AND o.line_identity=identity AND o.revoked_at IS NULL) THEN false
  ELSE EXISTS(SELECT 1 FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(vehicle)) x
   WHERE x->>'line_identity'=identity AND pdc_work_categories_private.offboard_line_done(vehicle,x)) END
$function$;
REVOKE ALL ON FUNCTION pdc_work_categories_private.offboard_line_done(uuid,jsonb), pdc_work_categories_private.offboard_identity_done(uuid,text) FROM PUBLIC, anon, authenticated;

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
$function$;
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
$function$;
CREATE OR REPLACE FUNCTION pdc_work_categories_private.vehicle_categories(vehicle uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
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
 'disabled_reason',CASE WHEN hours IS NULL OR hours<=0 THEN 'estimated_duration_missing' END,
 'offboard_confirmed',EXISTS(SELECT 1 FROM pdc_work_categories_private.offboard_done o WHERE o.vehicle_id=vehicle AND o.work_category=category AND o.revoked_at IS NULL))),'[]'::jsonb) FROM categories
$function$;
CREATE OR REPLACE FUNCTION pdc_fitter_private.conversion_completion_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE bid uuid; vid uuid; stage text; l jsonb; identity text;
BEGIN
 IF TG_TABLE_NAME = 'workshop_bookings' THEN
  IF NEW.status <> 'completed' OR (TG_OP = 'UPDATE' AND OLD.status = 'completed') THEN RETURN NEW; END IF;
  bid := NEW.id; vid := NEW.vehicle_id; SELECT code INTO stage FROM public.workshop_stages WHERE id = NEW.stage_id;
 ELSIF TG_TABLE_NAME = 'vehicle_work_items' THEN
  IF NOT NEW.completed OR (TG_OP = 'UPDATE' AND OLD.completed) THEN RETURN NEW; END IF;
  vid := NEW.vehicle_id; stage := CASE WHEN NEW.work_key = 'bus4x4' THEN 'BUS_4X4' END;
 ELSE
  IF NOT NEW.completed THEN RETURN NEW; END IF;
  SELECT vehicle_id INTO vid FROM public.workshop_bookings WHERE id = NEW.booking_id;
  stage := 'BUS_4X4'; identity := NEW.line_identity;
 END IF;
 IF stage IS DISTINCT FROM 'BUS_4X4' THEN RETURN NEW; END IF;
 FOR l IN SELECT x FROM jsonb_array_elements(pdc_fitter_private.lines(vid, bid)) x
  WHERE x->'conversion' IS NOT NULL AND (identity IS NULL OR x->>'line_identity' = identity) LOOP
  -- r399: a conversion a manager confirmed was done before the board (audited, with a reason,
  -- for this exact line version) counts as complete; its sections were never ticked on the board.
  IF pdc_work_categories_private.offboard_identity_done(vid, l->>'line_identity') THEN CONTINUE; END IF;
  IF NOT coalesce((l->>'completed')::boolean, false) THEN
   -- A ticked Coaster or HiAce parent is complete. Work-item and booking rows
   -- have no line_identity; only the progress branch may read that field.
   -- The progress insert itself is not visible to lines() yet.
   IF l#>>'{conversion,id}' IN ('coaster', 'hiace_commuter')
      AND coalesce((l#>>'{conversion,needs_review}')::boolean, false) = false THEN
    IF TG_TABLE_NAME = 'operation_progress' THEN
     IF NEW.completed AND NEW.line_identity = l->>'line_identity' THEN
      NULL;
     ELSIF EXISTS (
      SELECT 1 FROM pdc_fitter_private.operation_progress p
      JOIN public.workshop_bookings wb ON wb.id = p.booking_id
      WHERE wb.vehicle_id = vid AND wb.deleted_at IS NULL
        AND p.line_identity = l->>'line_identity' AND p.completed
        AND p.scope_hash = l->>'scope_hash') THEN
      NULL;
     ELSE
      RAISE EXCEPTION '{"error":"conversion_sections_required"}' USING ERRCODE = '23514';
     END IF;
    ELSIF EXISTS (
     SELECT 1 FROM pdc_fitter_private.operation_progress p
     JOIN public.workshop_bookings wb ON wb.id = p.booking_id
     WHERE wb.vehicle_id = vid AND wb.deleted_at IS NULL
       AND p.line_identity = l->>'line_identity' AND p.completed
       AND p.scope_hash = l->>'scope_hash') THEN
     NULL;
    ELSE
     RAISE EXCEPTION '{"error":"conversion_sections_required"}' USING ERRCODE = '23514';
    END IF;
   ELSE
    RAISE EXCEPTION '{"error":"conversion_sections_required"}' USING ERRCODE = '23514';
   END IF;
  END IF;
 END LOOP;
 RETURN NEW;
END
$function$;
CREATE OR REPLACE FUNCTION pdc_codex_intake_private.workshop_nonnav138_read_allowed_20261012(p_scope jsonb, p_vehicle_id uuid, p_requested_dealer text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$ SELECT coalesce(p_scope->>'environment'='staging' AND p_scope->>'role' IN ('viewer','operator','administrator') AND p_scope->>'dealer_code'='14450' AND p_requested_dealer='14450' AND EXISTS (
SELECT 1 FROM public.vehicles v JOIN public.pdc_new_vehicle_reviews n ON n.vehicle_id=v.id
WHERE v.id=p_vehicle_id AND v.source_system='tune_pmg' AND v.lifecycle_state='active' AND v.visible_on_board AND v.deleted_at IS NULL AND v.board_purged_at IS NULL AND nullif(btrim(v.stock_number),'') IS NOT NULL
AND n.status='approved' AND n.approved_at IS NOT NULL AND n.approved_by IS NOT NULL AND n.approval_receipt->>'ok'='true' AND n.approval_receipt->>'code'='new_vehicle_approved'
AND NOT EXISTS(SELECT 1 FROM public.navision_backend_records nr WHERE nr.canonical_vehicle_id=v.id AND nr.is_current)
AND EXISTS(SELECT 1 FROM pdc_parts_private.jobs j WHERE j.vehicle_id=v.id AND j.closed_at IS NULL AND j.source_system='tune_pmg' AND j.company='01' AND j.division='1' AND j.departments=ARRAY['138']::text[] AND j.stock_number=v.stock_number)
AND NOT EXISTS(SELECT 1 FROM pdc_parts_private.jobs j WHERE j.vehicle_id=v.id AND j.closed_at IS NULL AND (j.source_system IS DISTINCT FROM 'tune_pmg' OR j.company IS DISTINCT FROM '01' OR j.division IS DISTINCT FROM '1' OR (j.departments IS DISTINCT FROM ARRAY['138']::text[] AND j.departments IS DISTINCT FROM ARRAY['139']::text[]) OR j.stock_number IS DISTINCT FROM v.stock_number))
AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o JOIN pdc_parts_private.jobs j ON j.vehicle_id=o.vehicle_id AND j.ro_number=o.repair_order_number AND j.closed_at IS NULL WHERE o.vehicle_id=v.id AND o.department='138' AND o.stock_number=v.stock_number AND o.raw_evidence_id IS NOT NULL)
AND NOT EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=v.id AND ((o.department IS DISTINCT FROM '138' AND o.department IS DISTINCT FROM '139') OR o.stock_number IS DISTINCT FROM v.stock_number OR o.raw_evidence_id IS NULL))
),false); $function$;

CREATE FUNCTION public.confirm_bus_category_done(p_vehicle_id uuid, p_vehicle_expected_version integer, p_category text, p_reason text, p_line_identities text[] DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog'
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
END $function$;

CREATE FUNCTION public.undo_bus_category_done(p_vehicle_id uuid, p_vehicle_expected_version integer, p_category text, p_reason text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog'
AS $function$
DECLARE v public.vehicles; why text:=btrim(coalesce(p_reason,'')); n integer;
BEGIN
 IF auth.uid() IS NULL OR coalesce(public.current_pdc_user_role()::text,'') NOT IN ('operator','administrator') THEN
  RAISE EXCEPTION 'Operator or administrator role required' USING ERRCODE='42501';
 END IF;
 IF length(why) NOT BETWEEN 5 AND 500 THEN RETURN jsonb_build_object('ok',false,'error','reason_required','message','Enter a reason of 5 to 500 characters.'); END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
 SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id AND deleted_at IS NULL AND lifecycle_state='active' FOR UPDATE;
 IF NOT FOUND OR v.version IS DISTINCT FROM p_vehicle_expected_version THEN RETURN jsonb_build_object('ok',false,'error','vehicle_version_conflict'); END IF;
 IF EXISTS(SELECT 1 FROM public.vehicle_work_items wi WHERE wi.vehicle_id=v.id AND wi.work_key='bus4x4' AND wi.completed) THEN
  RETURN jsonb_build_object('ok',false,'error','stage_already_completed','message','Bus 4x4 is already complete for this job. Reopen it first.');
 END IF;
 IF EXISTS(SELECT 1 FROM public.workshop_bookings bk JOIN public.workshop_stages s ON s.id=bk.stage_id WHERE bk.vehicle_id=v.id AND s.code='BUS_4X4'
   AND bk.deleted_at IS NULL AND bk.work_category=p_category AND bk.status IN('queued','planned','started','stoppage')) THEN
  RETURN jsonb_build_object('ok',false,'error','category_booking_exists','message','This category has an active booking. Remove it from the bay before undoing the confirmation.');
 END IF;
 UPDATE pdc_work_categories_private.offboard_done SET revoked_at=clock_timestamp(),revoked_by=auth.uid(),revoke_reason=why
 WHERE vehicle_id=v.id AND work_category=p_category AND revoked_at IS NULL;
 GET DIAGNOSTICS n=ROW_COUNT;
 IF n=0 THEN RETURN jsonb_build_object('ok',false,'error','nothing_to_undo'); END IF;
 UPDATE public.vehicles SET version=version+1,updated_at=clock_timestamp(),updated_by=auth.uid() WHERE id=v.id;
 INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
 VALUES('update','vehicle_work_category_offboard_done',v.id,v.id,auth.uid(),public.current_actor_email(),jsonb_build_object('work_category',p_category,'lines_reopened',n),NULL,
  jsonb_build_object('source','undo_bus_category_done_399','reason',why));
 RETURN jsonb_build_object('ok',true,'work_category',p_category,'lines_reopened',n,'vehicle_version',v.version+1,'revision',public.workshop_bump_revision());
END $function$;
REVOKE ALL ON FUNCTION public.confirm_bus_category_done(uuid,integer,text,text,text[]), public.undo_bus_category_done(uuid,integer,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_bus_category_done(uuid,integer,text,text,text[]), public.undo_bus_category_done(uuid,integer,text,text) TO authenticated;

DO $post$
DECLARE live jsonb;
BEGIN
 SELECT jsonb_object_agg(p.oid::regprocedure::text, md5(p.prosrc)) INTO live FROM pg_proc p
  WHERE p.oid IN ('pdc_fitter_private.conversion_completion_guard()'::regprocedure,'pdc_codex_intake_private.workshop_nonnav138_read_allowed_20261012(jsonb,uuid,text)'::regprocedure,'pdc_work_categories_private.line_completed(uuid,jsonb)'::regprocedure,'pdc_work_categories_private.completed(uuid,text)'::regprocedure,'pdc_work_categories_private.vehicle_categories(uuid)'::regprocedure);
 IF live IS DISTINCT FROM '{"pdc_fitter_private.conversion_completion_guard()": "4222b51b637b85cf22315b38f7ea16d4", "pdc_codex_intake_private.workshop_nonnav138_read_allowed_20261012(jsonb,uuid,text)": "ed61f7d555d910abbf02b7ede6bda288", "pdc_work_categories_private.line_completed(uuid,jsonb)": "0c8cc64db074645da4adea3be9d15a79", "pdc_work_categories_private.completed(uuid,text)": "7039c06acd173d890c4d7ffbdd4b749d", "pdc_work_categories_private.vehicle_categories(uuid)": "0f77e09d7ab31418082bf4beb6af036a"}'::jsonb THEN RAISE EXCEPTION 'r399: post md5 mismatch: %', live; END IF;
END $post$;
