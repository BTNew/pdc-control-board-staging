-- Existing unresolved lines use the already-reviewed import estimate, without
-- rewriting source evidence, staff choices, completed work or bay reservations.
DO $guard$ BEGIN
 IF NOT pdc_codex_intake_private.management_connection() OR NOT public.pdc_monitor_staging_guard() OR auth.uid() IS NOT NULL THEN RAISE EXCEPTION 'staging_management_required'; END IF;
 IF md5(replace(pg_get_functiondef('pdc_work_categories_private.route_import_line_20261017(jsonb,boolean)'::regprocedure),chr(13),''))<>'e8272a6753579860eb88eee006ce7c4c' THEN RAISE EXCEPTION 'routing_dependency_changed'; END IF;
END $guard$;
CREATE OR REPLACE FUNCTION pdc_work_categories_private.route_import_line_20261017(line jsonb, preserve boolean)
 RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path TO 'pg_catalog'
AS $function$
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
END $function$;
REVOKE ALL ON FUNCTION pdc_work_categories_private.route_import_line_20261017(jsonb,boolean) FROM PUBLIC,anon,authenticated,service_role;

