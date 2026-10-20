-- r399 undo: restores the 5 original function bodies (exact md5s), drops the r399 RPCs, helpers and the confirmation table.
DO $g$
DECLARE live jsonb; n integer;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.pdc_staging_environment_sentinel WHERE project_ref='cdsmnqxtyyoeoznmbidd')
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r399 undo: staging only'; END IF;
 SELECT jsonb_object_agg(p.oid::regprocedure::text, md5(p.prosrc)) INTO live FROM pg_proc p
  WHERE p.oid IN ('pdc_fitter_private.conversion_completion_guard()'::regprocedure,'pdc_codex_intake_private.workshop_nonnav138_read_allowed_20261012(jsonb,uuid,text)'::regprocedure,'pdc_work_categories_private.line_completed(uuid,jsonb)'::regprocedure,'pdc_work_categories_private.completed(uuid,text)'::regprocedure,'pdc_work_categories_private.vehicle_categories(uuid)'::regprocedure);
 IF live IS DISTINCT FROM '{"pdc_fitter_private.conversion_completion_guard()": "4222b51b637b85cf22315b38f7ea16d4", "pdc_codex_intake_private.workshop_nonnav138_read_allowed_20261012(jsonb,uuid,text)": "ed61f7d555d910abbf02b7ede6bda288", "pdc_work_categories_private.line_completed(uuid,jsonb)": "0c8cc64db074645da4adea3be9d15a79", "pdc_work_categories_private.completed(uuid,text)": "7039c06acd173d890c4d7ffbdd4b749d", "pdc_work_categories_private.vehicle_categories(uuid)": "0f77e09d7ab31418082bf4beb6af036a"}'::jsonb THEN RAISE EXCEPTION 'r399 undo: live functions are not the r399 bodies: %', live; END IF;
 SELECT count(*) INTO n FROM pdc_work_categories_private.offboard_done WHERE revoked_at IS NULL;
 IF n>0 AND coalesce(current_setting('pdc.r399_undo_with_confirmations',true),'')<>'yes' THEN
  RAISE EXCEPTION 'r399 undo: % active off-board confirmations exist; their work would reopen. Undo them in the app, or SET pdc.r399_undo_with_confirmations=yes', n;
 END IF;
END $g$;
DROP FUNCTION public.confirm_bus_category_done(uuid,integer,text,text,text[]);
DROP FUNCTION public.undo_bus_category_done(uuid,integer,text,text);
DO $r$
BEGIN
 EXECUTE $r399def$CREATE OR REPLACE FUNCTION pdc_fitter_private.conversion_completion_guard()
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
$function$$r399def$;
 EXECUTE $r399def$CREATE OR REPLACE FUNCTION pdc_codex_intake_private.workshop_nonnav138_read_allowed_20261012(p_scope jsonb, p_vehicle_id uuid, p_requested_dealer text)
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
AND NOT EXISTS(SELECT 1 FROM pdc_parts_private.jobs j WHERE j.vehicle_id=v.id AND j.closed_at IS NULL AND (j.source_system IS DISTINCT FROM 'tune_pmg' OR j.company IS DISTINCT FROM '01' OR j.division IS DISTINCT FROM '1' OR j.departments IS DISTINCT FROM ARRAY['138']::text[] OR j.stock_number IS DISTINCT FROM v.stock_number))
AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o JOIN pdc_parts_private.jobs j ON j.vehicle_id=o.vehicle_id AND j.ro_number=o.repair_order_number AND j.closed_at IS NULL WHERE o.vehicle_id=v.id AND o.department='138' AND o.stock_number=v.stock_number AND o.raw_evidence_id IS NOT NULL)
AND NOT EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=v.id AND (o.department IS DISTINCT FROM '138' OR o.stock_number IS DISTINCT FROM v.stock_number OR o.raw_evidence_id IS NULL))
),false); $function$$r399def$;
 EXECUTE $r399def$CREATE OR REPLACE FUNCTION pdc_work_categories_private.line_completed(vehicle uuid, line jsonb)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
 SELECT EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.vehicle_id=vehicle
  AND b.work_category=line->>'work_category' AND b.status='completed' AND b.deleted_at IS NULL
  AND b.work_category_scope->>(line->>'line_identity')=pdc_work_categories_private.line_hash(line))
$function$$r399def$;
 EXECUTE $r399def$CREATE OR REPLACE FUNCTION pdc_work_categories_private.completed(vehicle uuid, category text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
 SELECT count(*)>0 AND bool_and(EXISTS(SELECT 1 FROM public.workshop_bookings b
  WHERE b.vehicle_id=vehicle AND b.work_category=category AND b.status='completed' AND b.deleted_at IS NULL
    AND b.work_category_scope->>(l->>'line_identity')=pdc_work_categories_private.line_hash(l)))
 FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(vehicle)) l
 WHERE coalesce((l->>'active')::boolean,true) AND l->>'work_category'=category
$function$$r399def$;
 EXECUTE $r399def$CREATE OR REPLACE FUNCTION pdc_work_categories_private.vehicle_categories(vehicle uuid)
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
 'disabled_reason',CASE WHEN hours IS NULL OR hours<=0 THEN 'estimated_duration_missing' END)),'[]'::jsonb) FROM categories
$function$$r399def$;
END $r$;
DROP FUNCTION pdc_work_categories_private.offboard_identity_done(uuid,text);
DROP FUNCTION pdc_work_categories_private.offboard_line_done(uuid,jsonb);
DROP TABLE pdc_work_categories_private.offboard_done;
DO $post$
DECLARE live jsonb;
BEGIN
 SELECT jsonb_object_agg(p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid))) INTO live FROM pg_proc p
  WHERE p.oid IN ('pdc_fitter_private.conversion_completion_guard()'::regprocedure,'pdc_codex_intake_private.workshop_nonnav138_read_allowed_20261012(jsonb,uuid,text)'::regprocedure,'pdc_work_categories_private.line_completed(uuid,jsonb)'::regprocedure,'pdc_work_categories_private.completed(uuid,text)'::regprocedure,'pdc_work_categories_private.vehicle_categories(uuid)'::regprocedure);
 IF live IS DISTINCT FROM '{"pdc_fitter_private.conversion_completion_guard()": "78031e2a1e71419627d1d3489610b588", "pdc_codex_intake_private.workshop_nonnav138_read_allowed_20261012(jsonb,uuid,text)": "2349b0df7e798906b00bd15a602e4ddf", "pdc_work_categories_private.line_completed(uuid,jsonb)": "b7f9842f3436df077172d70c59a23d30", "pdc_work_categories_private.completed(uuid,text)": "fe87953c3ada552d7aa3e6e2b409c828", "pdc_work_categories_private.vehicle_categories(uuid)": "622f4e0e720b610644b8186fd660f680"}'::jsonb THEN RAISE EXCEPTION 'r399 undo: restored md5 mismatch: %', live; END IF;
END $post$;
