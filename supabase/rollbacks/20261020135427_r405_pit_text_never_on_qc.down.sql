-- r405 undo (staging only). Restores the exact r400/r401 bodies and pins; removes the r405 check.
DO $g$ BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'r405 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_line_is_pit_401(uuid,jsonb)'::regprocedure)<>'2379b7ad49c2c472e09118cedc1bd8ce'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_qc_line_not_checkable_400(uuid,jsonb)'::regprocedure)<>'c79f98485c69b285cdf43ea82bafa592'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_operation_updates_private.ensure_required_work_20261019(uuid)'::regprocedure)<>'d164e32cdde78185f2dbdf2612459d9e'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.vehicle_categories(uuid)'::regprocedure)<>'6c295090fc3bb9b500eef31072bcfe5f'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_qc_gate_issues(uuid)'::regprocedure)<>'2d9f3d968a51790d3395c0367af70578' THEN RAISE EXCEPTION 'r405 undo: r405 md5s not present'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION pdc_operation_updates_private.ensure_required_work_20261019(p_vehicle_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog', 'public'
AS $function$
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
 JOIN public.workshop_stages s ON s.code=CASE WHEN l->>'stage_code' IN('BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA','BUS_PIT') THEN 'BUS_4X4' ELSE l->>'stage_code' END
 WHERE l->>'active'='true' AND coalesce(l->>'rejected','false')<>'true'
  AND coalesce(l->>'completed','false')<>'true' AND s.work_key IS NOT NULL
  -- r401: Pit and weigh is never required work (optional, ticked by any department).
  AND s.code IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET')
 ON CONFLICT(vehicle_id,work_key) DO UPDATE SET required=true,updated_at=clock_timestamp()
 WHERE NOT vehicle_work_items.required AND NOT vehicle_work_items.completed;
 GET DIAGNOSTICS changed=ROW_COUNT;
 RETURN changed;
END $function$;

CREATE OR REPLACE FUNCTION public.pdc_qc_line_not_checkable_400(p_vehicle_id uuid, p_line jsonb)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
  -- r400: lines QC cannot tick. Pit inspection is the external Department of
  -- Transport check after QC; job-card notes are information only. Both were
  -- missed for job-card category lines (stage_code), so they blocked sign-off.
  SELECT upper(btrim(coalesce(p_line->>'stage_code',''))) IN ('PIT_INSPECTION','JOB_CARD_NOTES')
  OR EXISTS(
    SELECT 1
    FROM public.pdc_authenticated_email_operation_lines ol
    WHERE ol.vehicle_id=p_vehicle_id
      AND 'source:'||ol.operation_line_id::text=lower(btrim(coalesce(p_line->>'line_identity','')))
      AND regexp_replace(upper(btrim(coalesce(ol.work_key,''))),'[^A-Z0-9]+','','g')='PITINSPECTION'
  )
$function$;

CREATE OR REPLACE FUNCTION public.pdc_line_is_pit_401(p_vehicle_id uuid, p_line jsonb)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
  -- r401: a Pit and weigh / Pit inspection line, in any department. Optional; never blocks anything.
  SELECT upper(btrim(coalesce(p_line->>'stage_code','')))='PIT_INSPECTION'
  OR upper(btrim(coalesce(p_line->>'work_category','')))='BUS_PIT'
  OR EXISTS(
    SELECT 1
    FROM public.pdc_authenticated_email_operation_lines ol
    WHERE ol.vehicle_id=p_vehicle_id
      AND 'source:'||ol.operation_line_id::text=lower(btrim(coalesce(p_line->>'line_identity','')))
      AND regexp_replace(upper(btrim(coalesce(ol.work_key,''))),'[^A-Z0-9]+','','g')='PITINSPECTION'
  )
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

CREATE OR REPLACE FUNCTION public.pdc_qc_gate_issues(p_vehicle_id uuid)
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
  WITH vehicle AS (
    SELECT id,upper(btrim(coalesce(current_location,''))) location,
           CASE WHEN regexp_replace(upper(btrim(coalesce(pmb_stage,''))),'[^A-Z0-9]+','','g')='PITINSPECTION' THEN ''
                ELSE regexp_replace(upper(btrim(coalesce(pmb_stage,''))),'[^A-Z0-9]+','','g') END stage
    FROM public.vehicles WHERE id=p_vehicle_id AND lifecycle_state='active' AND deleted_at IS NULL
  ), outstanding AS (
    SELECT string_agg(distinct upper(btrim(wi.work_key)),', ' ORDER BY upper(btrim(wi.work_key))) labels
    FROM public.vehicle_work_items wi
    WHERE wi.vehicle_id=p_vehicle_id AND wi.required AND NOT wi.completed
      AND regexp_replace(upper(btrim(coalesce(wi.work_key,''))),'[^A-Z0-9]+','','g') NOT IN ('QC','PARTS','PITINSPECTION')
  ), canonical_missing AS (
    SELECT count(*) n FROM jsonb_array_elements(public.pdc_qc_operation_lines_379(p_vehicle_id)) l
    LEFT JOIN public.workshop_stages s ON s.code=CASE WHEN l->>'stage_code' IN('BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA','BUS_PIT') THEN 'BUS_4X4' ELSE l->>'stage_code' END
    WHERE l->>'active'='true' AND coalesce(l->>'rejected','false')<>'true' AND coalesce(l->>'completed','false')<>'true'
      AND coalesce(l->>'stage_code','') NOT IN('JOB_CARD_NOTES','PIT_INSPECTION','QC','PARTS')
      AND (s.work_key IS NULL OR NOT EXISTS(SELECT 1 FROM public.vehicle_work_items wi
        WHERE wi.vehicle_id=p_vehicle_id AND wi.work_key=s.work_key AND (wi.required OR wi.completed)))
  ), active_planner AS (
    SELECT string_agg(distinct s.code,', ' ORDER BY s.code) labels
    FROM public.workshop_bookings b
    JOIN public.workshop_stages s ON s.id=b.stage_id
    WHERE b.vehicle_id=p_vehicle_id AND b.deleted_at IS NULL
      AND b.status IN ('queued','planned','started','stoppage') AND s.planner_enabled AND s.code<>'PIT_INSPECTION'
  )
  SELECT array_remove(array[
    CASE WHEN (SELECT n FROM canonical_missing)>0 THEN 'unresolved_jobcard_work' END,
    CASE WHEN NOT EXISTS(SELECT 1 FROM vehicle) THEN 'active_vehicle_required' END,
    CASE WHEN (SELECT location FROM vehicle) NOT IN ('PMB','QC') THEN 'vehicle_must_be_at_pmb_or_qc_gate' END,
    CASE WHEN coalesce((SELECT stage FROM vehicle),'')<>'' THEN 'vehicle_still_in_workshop_stage:'||(SELECT stage FROM vehicle) END,
    CASE WHEN (SELECT labels FROM outstanding) IS NOT NULL THEN 'outstanding_required_work:'||(SELECT labels FROM outstanding) END,
    CASE WHEN (SELECT labels FROM active_planner) IS NOT NULL THEN 'active_workshop_booking:'||(SELECT labels FROM active_planner) END
  ],null::text)
$function$;

DELETE FROM pdc_ops.regression_checks WHERE check_name='pit_text_lines_never_on_qc_checklist' AND added_in='r405';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='0f77e09d7ab31418082bf4beb6af036a',release='r399',note=NULL,updated_at=now() WHERE signature='pdc_work_categories_private.vehicle_categories(uuid)' AND release='r405';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='6d071672dd859d7ec3e889ece66624ff',release='r401',note='Pit line definition',updated_at=now() WHERE signature='public.pdc_line_is_pit_401(uuid,jsonb)' AND release='r405';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='eac292a1d85506a02a6b5143d979a632',release='r400',note='QC cannot tick Pit inspection / job-card notes',updated_at=now() WHERE signature='public.pdc_qc_line_not_checkable_400(uuid,jsonb)' AND release='r405';
UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='4db6302844ef0da651d165a3716bbbac',release='r401',note='Pit never required work',updated_at=now() WHERE signature='pdc_operation_updates_private.ensure_required_work_20261019(uuid)' AND release='r405';
DELETE FROM pdc_ops.expected_function_md5 WHERE signature='public.pdc_qc_gate_issues(uuid)' AND release='r405';

DO $p$ BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_line_is_pit_401(uuid,jsonb)'::regprocedure)<>'6d071672dd859d7ec3e889ece66624ff'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_qc_line_not_checkable_400(uuid,jsonb)'::regprocedure)<>'eac292a1d85506a02a6b5143d979a632'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_operation_updates_private.ensure_required_work_20261019(uuid)'::regprocedure)<>'4db6302844ef0da651d165a3716bbbac'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.vehicle_categories(uuid)'::regprocedure)<>'0f77e09d7ab31418082bf4beb6af036a'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_qc_gate_issues(uuid)'::regprocedure)<>'8187b6197138008bd0248979bbc64e1b' THEN RAISE EXCEPTION 'r405 undo: old md5 not restored'; END IF;
 IF md5(pg_get_functiondef('public.pdc_line_is_pit_401(uuid,jsonb)'::regprocedure))<>'62e4d92c764b5cca671768e3ddf114cc' OR (SELECT proacl::text FROM pg_proc WHERE oid='public.pdc_line_is_pit_401(uuid,jsonb)'::regprocedure)<>'{postgres=X/postgres}'
  OR md5(pg_get_functiondef('public.pdc_qc_line_not_checkable_400(uuid,jsonb)'::regprocedure))<>'e5e1223fc03b25d3385a7299dc4219ee' OR (SELECT proacl::text FROM pg_proc WHERE oid='public.pdc_qc_line_not_checkable_400(uuid,jsonb)'::regprocedure)<>'{postgres=X/postgres}'
  OR md5(pg_get_functiondef('pdc_operation_updates_private.ensure_required_work_20261019(uuid)'::regprocedure))<>'7eb619fe454d2dc7dbfc739fc0ec4dff' OR (SELECT proacl::text FROM pg_proc WHERE oid='pdc_operation_updates_private.ensure_required_work_20261019(uuid)'::regprocedure)<>'{postgres=X/postgres}'
  OR md5(pg_get_functiondef('pdc_work_categories_private.vehicle_categories(uuid)'::regprocedure))<>'ab0872e6ec33e633d5e328b4fd577d90' OR (SELECT proacl::text FROM pg_proc WHERE oid='pdc_work_categories_private.vehicle_categories(uuid)'::regprocedure)<>'{postgres=X/postgres}'
  OR md5(pg_get_functiondef('public.pdc_qc_gate_issues(uuid)'::regprocedure))<>'9aa780590f5c7d328d0a93885b888c05' OR (SELECT proacl::text FROM pg_proc WHERE oid='public.pdc_qc_gate_issues(uuid)'::regprocedure)<>'{postgres=X/postgres,service_role=X/postgres}' THEN RAISE EXCEPTION 'r405 undo: functiondef or ACL differs'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5 WHERE release='r405')<>0 OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r405') THEN RAISE EXCEPTION 'r405 undo: pins/check left'; END IF;
END $p$;
