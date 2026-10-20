-- r405 (F14): Pit and weigh lines are recognised by their wording, whatever they were filed as.
-- Staging cdsmnqxtyyoeoznmbidd only. Key 340 / 13047338 had "PIT AND WEIGH" filed as FITTING (Dept 139) on its QC checklist.
-- 1. pdc_line_is_pit_401: also true when the description says Pit and weigh / Pit inspection.
-- 2. pdc_qc_line_not_checkable_400: also true for any pdc_line_is_pit_401 line (QC checklist, sign-off, reject list, rework, RFT).
-- 3. ensure_required_work_20261019: a Pit line never creates required work.
-- 4. vehicle_categories: a Pit line filed under Bus 4x4 never counts towards a Bus category (hours, completion).
-- 5. pdc_qc_gate_issues (PMB->QC gate): a Pit line is never unresolved job-card work.
-- No line, category, work item, booking or vehicle row is changed. The QC projection/cache is not affected.
DO $g$ BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'r405: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_line_is_pit_401(uuid,jsonb)'::regprocedure)<>'6d071672dd859d7ec3e889ece66624ff'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_qc_line_not_checkable_400(uuid,jsonb)'::regprocedure)<>'eac292a1d85506a02a6b5143d979a632'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_operation_updates_private.ensure_required_work_20261019(uuid)'::regprocedure)<>'4db6302844ef0da651d165a3716bbbac'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.vehicle_categories(uuid)'::regprocedure)<>'0f77e09d7ab31418082bf4beb6af036a'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_qc_gate_issues(uuid)'::regprocedure)<>'8187b6197138008bd0248979bbc64e1b' THEN RAISE EXCEPTION 'r405: base md5 mismatch (already applied or changed)'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION public.pdc_line_is_pit_401(p_vehicle_id uuid, p_line jsonb)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
  -- r401: a Pit and weigh / Pit inspection line, in any department. Optional; never blocks anything.
  -- r405 (F14): also by its wording, whatever stage or category it was filed under
  -- (Dept 139 files "PIT AND WEIGH" as FITTING; some Dept 138 lines are Bus 4x4 or Sublet).
  SELECT regexp_replace(upper(coalesce(p_line->>'description','')),'\s+',' ','g') ~ '(^|[^A-Z])PITS? ?(AND|&|\+|/|N|''N'')? ?WEIGH|(^|[^A-Z])PIT ?INSPECT'
  OR upper(btrim(coalesce(p_line->>'stage_code','')))='PIT_INSPECTION'
  OR upper(btrim(coalesce(p_line->>'work_category','')))='BUS_PIT'
  OR EXISTS(
    SELECT 1
    FROM public.pdc_authenticated_email_operation_lines ol
    WHERE ol.vehicle_id=p_vehicle_id
      AND 'source:'||ol.operation_line_id::text=lower(btrim(coalesce(p_line->>'line_identity','')))
      AND regexp_replace(upper(btrim(coalesce(ol.work_key,''))),'[^A-Z0-9]+','','g')='PITINSPECTION'
  )
$function$;

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
  -- r405 (F14): any Pit and weigh / Pit inspection line, by wording too (pdc_line_is_pit_401).
  OR public.pdc_line_is_pit_401(p_vehicle_id,p_line)
  OR EXISTS(
    SELECT 1
    FROM public.pdc_authenticated_email_operation_lines ol
    WHERE ol.vehicle_id=p_vehicle_id
      AND 'source:'||ol.operation_line_id::text=lower(btrim(coalesce(p_line->>'line_identity','')))
      AND regexp_replace(upper(btrim(coalesce(ol.work_key,''))),'[^A-Z0-9]+','','g')='PITINSPECTION'
  )
$function$;

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
  -- r405 (F14): a Pit and weigh line never creates required work, whatever stage it was filed under.
  AND NOT public.pdc_line_is_pit_401(p_vehicle_id,l)
 ON CONFLICT(vehicle_id,work_key) DO UPDATE SET required=true,updated_at=clock_timestamp()
 WHERE NOT vehicle_work_items.required AND NOT vehicle_work_items.completed;
 GET DIAGNOSTICS changed=ROW_COUNT;
 RETURN changed;
END $function$;

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
      -- r405 (F14): a Pit and weigh line, whatever it was filed under, is never unresolved work.
      AND NOT public.pdc_line_is_pit_401(p_vehicle_id,l)
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

INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release,note) VALUES
 ('pdc_work_categories_private.vehicle_categories(uuid)','6c295090fc3bb9b500eef31072bcfe5f','r405','Bus categories ignore Pit lines (r405)'),
 ('public.pdc_qc_gate_issues(uuid)','2d9f3d968a51790d3395c0367af70578','r405','PMB->QC gate ignores Pit lines, any filing (r405)'),
 ('public.pdc_line_is_pit_401(uuid,jsonb)','2379b7ad49c2c472e09118cedc1bd8ce','r405','Pit line definition; r405 adds Pit/Weigh wording'),
 ('public.pdc_qc_line_not_checkable_400(uuid,jsonb)','c79f98485c69b285cdf43ea82bafa592','r405','QC cannot tick Pit / job-card notes; r405 uses the Pit helper'),
 ('pdc_operation_updates_private.ensure_required_work_20261019(uuid)','d164e32cdde78185f2dbdf2612459d9e','r405','Pit never required work, whatever stage (r405)')
ON CONFLICT (signature) DO UPDATE SET prosrc_md5=excluded.prosrc_md5,release=excluded.release,note=excluded.note,updated_at=now() WHERE true;
INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,enabled,sort_order,added_in) VALUES
 ('pit_text_lines_never_on_qc_checklist','F14','No line worded Pit and weigh / Pit inspection is on any active vehicle''s QC checklist, whatever stage or category it was filed under; Pit lines never create required work (r405).',$c405$WITH av AS (
  SELECT v.id, upper(btrim(coalesce(v.current_location,''))) loc FROM public.vehicles v WHERE v.deleted_at IS NULL AND v.lifecycle_state='active'
), pit_text AS (
  SELECT av.id, av.loc, l FROM av CROSS JOIN LATERAL jsonb_array_elements(public.pdc_qc_operation_lines_379(av.id)) l
  WHERE coalesce(l->>'active','true')='true' AND regexp_replace(upper(coalesce(l->>'description','')),'\s+',' ','g') ~ '(^|[^A-Z])PITS? ?(AND|&|\+|/|N|''N'')? ?WEIGH|(^|[^A-Z])PIT ?INSPECT'
), on_cl AS (
  SELECT p.id FROM pit_text p WHERE NOT public.pdc_qc_line_not_checkable_400(p.id,p.l)
  UNION ALL
  SELECT q.id FROM (SELECT DISTINCT id FROM pit_text WHERE loc='QC') q CROSS JOIN LATERAL jsonb_array_elements(public.pdc_qc_checkable_operation_lines_10700(q.id)) c
  WHERE regexp_replace(upper(coalesce(c->>'description','')),'\s+',' ','g') ~ '(^|[^A-Z])PITS? ?(AND|&|\+|/|N|''N'')? ?WEIGH|(^|[^A-Z])PIT ?INSPECT'
), s AS (
  SELECT public.pdc_line_is_pit_401(NULL,'{"description":"PIT AND WEIGH","stage_code":"FITTING","work_category":"FITTING"}'::jsonb)
     AND public.pdc_line_is_pit_401(NULL,'{"description":"Pit & Weigh","stage_code":"BUS_4X4"}'::jsonb)
     AND public.pdc_line_is_pit_401(NULL,'{"description":"PIT INSPECTION","stage_code":"SUBLET"}'::jsonb)
     AND public.pdc_qc_line_not_checkable_400(NULL,'{"description":"Pit and weigh","stage_code":"FITTING"}'::jsonb)
     AND NOT public.pdc_line_is_pit_401(NULL,'{"description":"Complete Pre-Delivery Inspection","stage_code":"FITTING"}'::jsonb)
     AND NOT public.pdc_line_is_pit_401(NULL,'{"description":"PITS - REFER BRYCE","stage_code":"SUBLET"}'::jsonb) AS samples,
   position('pdc_line_is_pit_401' in (SELECT prosrc FROM pg_catalog.pg_proc WHERE oid='pdc_operation_updates_private.ensure_required_work_20261019(uuid)'::regprocedure))>0 AS ensure_skips_pit,
   position('pdc_line_is_pit_401' in (SELECT prosrc FROM pg_catalog.pg_proc WHERE oid='public.pdc_qc_line_not_checkable_400(uuid,jsonb)'::regprocedure))>0
   AND position('pdc_line_is_pit_401' in (SELECT prosrc FROM pg_catalog.pg_proc WHERE oid='pdc_work_categories_private.vehicle_categories(uuid)'::regprocedure))>0
   AND position('pdc_line_is_pit_401' in (SELECT prosrc FROM pg_catalog.pg_proc WHERE oid='public.pdc_qc_gate_issues(uuid)'::regprocedure))>0 AS qc_rule_uses_pit
)
SELECT (SELECT count(*) FROM on_cl)=0 AND s.samples AND s.ensure_skips_pit AND s.qc_rule_uses_pit AS ok,
 format('%s Pit/Weigh-worded lines on a QC checklist (%s such lines on %s active vehicles); wording samples %s, required work skips Pit %s, QC rule, Bus categories and PMB->QC gate use Pit helper %s',
  (SELECT count(*) FROM on_cl),(SELECT count(*) FROM pit_text),(SELECT count(*) FROM av),s.samples,s.ensure_skips_pit,s.qc_rule_uses_pit) AS detail
FROM s$c405$,true,190,'r405');

DO $p$ DECLARE r record; BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_line_is_pit_401(uuid,jsonb)'::regprocedure)<>'2379b7ad49c2c472e09118cedc1bd8ce'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_qc_line_not_checkable_400(uuid,jsonb)'::regprocedure)<>'c79f98485c69b285cdf43ea82bafa592'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_operation_updates_private.ensure_required_work_20261019(uuid)'::regprocedure)<>'d164e32cdde78185f2dbdf2612459d9e'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_work_categories_private.vehicle_categories(uuid)'::regprocedure)<>'6c295090fc3bb9b500eef31072bcfe5f'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_qc_gate_issues(uuid)'::regprocedure)<>'2d9f3d968a51790d3395c0367af70578' THEN RAISE EXCEPTION 'r405: new md5 mismatch'; END IF;
 IF (SELECT proacl::text FROM pg_proc WHERE oid='public.pdc_line_is_pit_401(uuid,jsonb)'::regprocedure)<>'{postgres=X/postgres}'
  OR (SELECT proacl::text FROM pg_proc WHERE oid='public.pdc_qc_line_not_checkable_400(uuid,jsonb)'::regprocedure)<>'{postgres=X/postgres}'
  OR (SELECT proacl::text FROM pg_proc WHERE oid='pdc_operation_updates_private.ensure_required_work_20261019(uuid)'::regprocedure)<>'{postgres=X/postgres}'
  OR (SELECT proacl::text FROM pg_proc WHERE oid='pdc_work_categories_private.vehicle_categories(uuid)'::regprocedure)<>'{postgres=X/postgres}'
  OR (SELECT proacl::text FROM pg_proc WHERE oid='public.pdc_qc_gate_issues(uuid)'::regprocedure)<>'{postgres=X/postgres,service_role=X/postgres}' THEN RAISE EXCEPTION 'r405: ACL changed'; END IF;
 PERFORM set_config('request.jwt.claims','',true);
 EXECUTE (SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name='pit_text_lines_never_on_qc_checklist') INTO r;
 IF NOT r.ok THEN RAISE EXCEPTION 'r405: check failed: %', r.detail; END IF;
END $p$;
