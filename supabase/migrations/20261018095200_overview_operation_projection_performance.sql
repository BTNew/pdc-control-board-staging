-- Evaluate expensive operation projections once per line, without changing routing or hours.
DO $repair$
DECLARE d text; before_hash text;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'staging_only'; END IF;
 SELECT replace(pg_get_functiondef('pdc_work_categories_private.base_pdc_qc_operation_lines_379(uuid)'::regprocedure),chr(13),'') INTO d;
 IF md5(d)<>'cd4b326bb94467c07ad269467034fe40' THEN RAISE EXCEPTION 'reviewed_base_changed'; END IF;
 IF position(' ) hours_origin ON true' IN d)=0 THEN RAISE EXCEPTION 'projection_boundary_missing'; END IF;
 EXECUTE replace(d,' ) hours_origin ON true',E' OFFSET 0\n ) hours_origin ON true');
 SELECT replace(pg_get_functiondef('pdc_work_categories_private.before_import_rules_20261017(uuid)'::regprocedure),chr(13),'') INTO d;
 IF md5(d)<>'3fb3bab4c70c3a6ede2e0eacfc882611' THEN RAISE EXCEPTION 'reviewed_projection_changed'; END IF;
 EXECUTE replace(d,'projected AS (','projected AS MATERIALIZED (');
END $repair$;

CREATE OR REPLACE FUNCTION pdc_work_categories_private.hours_from_lines_20261018(p_vehicle_id uuid, p_stage_code text, p_lines jsonb)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE lines jsonb; result numeric; stage text:=public.workshop_canonical_stage_code(p_stage_code);
BEGIN
 IF coalesce((public.pdc_qc_rework_scope_20260909(p_vehicle_id)->>'active')::boolean,false)
 THEN RETURN pdc_work_categories_private.base_workshop_vehicle_stage_estimated_hours(p_vehicle_id,p_stage_code); END IF;
 lines:=p_lines;
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(lines) l WHERE l->>'department' IN('138','139'))
 AND NOT EXISTS(SELECT 1 FROM pdc_work_categories_private.line_overrides WHERE vehicle_id=p_vehicle_id)
 THEN RETURN pdc_work_categories_private.base_workshop_vehicle_stage_estimated_hours(p_vehicle_id,p_stage_code); END IF;
 SELECT CASE WHEN count(*) FILTER(WHERE jsonb_typeof(l->'estimated_hours') IS DISTINCT FROM 'number')=0
 THEN nullif(sum((l->>'estimated_hours')::numeric),0) END INTO result
 FROM jsonb_array_elements(lines) l WHERE coalesce((l->>'active')::boolean,true) AND l->>'stage_code'=stage
 AND NOT pdc_work_categories_private.line_completed(p_vehicle_id,l);
 RETURN result;
END $function$;

CREATE OR REPLACE FUNCTION pdc_work_categories_private.all_station_eligibility_20261018()
RETURNS TABLE(vehicle_id uuid,stage_code text,work_key text,current_location text,eta_to_kewdale date,existing_booking boolean,schedule_enabled boolean,disabled_reason text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog' AS $body$
WITH station AS MATERIALIZED(SELECT s.id,s.code,s.work_key FROM public.workshop_stages s WHERE s.active AND s.planner_enabled),
outstanding AS(
 SELECT wi.vehicle_id,st.id stage_id,st.code,st.work_key FROM station st
 JOIN public.workshop_stage_aliases wa ON wa.stage_code=st.code
 JOIN public.vehicle_work_items wi ON wa.alias_normalized=public.workshop_normalize_identifier(wi.work_key)
 WHERE wi.required AND NOT wi.completed GROUP BY wi.vehicle_id,st.id,st.code,st.work_key
),active_booking AS(
 SELECT DISTINCT b.vehicle_id,st.code FROM public.workshop_bookings b JOIN station st ON st.id=b.stage_id
 WHERE b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage')
),eligible AS MATERIALIZED(
 SELECT v.id,o.code,o.work_key,public.workshop_location_code(coalesce(nullif(v.location_override,''),v.current_location)) current_location,
 v.eta_to_kewdale,(ab.vehicle_id IS NOT NULL) existing_booking
 FROM outstanding o JOIN public.vehicles v ON v.id=o.vehicle_id LEFT JOIN active_booking ab ON ab.vehicle_id=v.id AND ab.code=o.code
 WHERE v.lifecycle_state='active' AND v.deleted_at IS NULL AND v.visible_on_board
 AND public.workshop_location_code(coalesce(nullif(v.location_override,''),v.current_location)) IN('PMB','YH','IT')
 AND (public.workshop_location_code(coalesce(nullif(v.location_override,''),v.current_location))<>'IT' OR v.eta_to_kewdale IS NOT NULL)
),vehicle_lines AS MATERIALIZED(
 SELECT v.id,public.pdc_qc_operation_lines_379(v.id) lines FROM (SELECT DISTINCT id FROM eligible) v
),estimated AS MATERIALIZED(
 SELECT e.*,pdc_work_categories_private.hours_from_lines_20261018(e.id,e.code,l.lines) approved_hours
 FROM eligible e JOIN vehicle_lines l USING(id)
)
SELECT e.id,e.code,e.work_key,e.current_location,e.eta_to_kewdale,e.existing_booking,
 e.approved_hours IS NOT NULL,CASE WHEN e.approved_hours IS NULL THEN 'estimated_duration_missing' ELSE NULL::text END FROM estimated e
$body$;
REVOKE ALL ON FUNCTION pdc_work_categories_private.hours_from_lines_20261018(uuid,text,jsonb),pdc_work_categories_private.all_station_eligibility_20261018() FROM PUBLIC,anon,authenticated,service_role;

DO $snapshot$ DECLARE d text; BEGIN
 SELECT replace(pg_get_functiondef('public.get_workshop_eligibility_snapshot()'::regprocedure),chr(13),'') INTO d;
 IF md5(d)<>'9bd238a4bee7e8a4c82b639956f76e5d' THEN RAISE EXCEPTION 'reviewed_overview_changed'; END IF;
 EXECUTE replace(d,$old$SELECT e.* FROM public.workshop_stages s
    CROSS JOIN LATERAL public.workshop_station_eligibility(s.code) e
    WHERE s.active AND s.planner_enabled AND s.code=e.stage_code$old$,'SELECT * FROM pdc_work_categories_private.all_station_eligibility_20261018()');
END $snapshot$;

