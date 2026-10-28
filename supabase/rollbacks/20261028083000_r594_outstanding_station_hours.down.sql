-- Undo r594 (F208). Restores the station total that included ticked lines.
-- Does not rewrite booking rows and does not book Key 460.

SET LOCAL lock_timeout = '2s';
CREATE OR REPLACE FUNCTION public.workshop_vehicle_stage_estimated_hours(p_vehicle_id uuid, p_stage_code text)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO pg_catalog
AS $function$
DECLARE lines jsonb; result numeric; stage text:=public.workshop_canonical_stage_code(p_stage_code);
BEGIN
 IF coalesce((public.pdc_qc_rework_scope_20260909(p_vehicle_id)->>'active')::boolean,false)
 THEN RETURN pdc_work_categories_private.base_workshop_vehicle_stage_estimated_hours(p_vehicle_id,p_stage_code); END IF;
 lines:=public.pdc_qc_operation_lines_379(p_vehicle_id);
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(lines) l WHERE l->>'department' IN('138','139'))
 AND NOT EXISTS(SELECT 1 FROM pdc_work_categories_private.line_overrides WHERE vehicle_id=p_vehicle_id)
 THEN RETURN pdc_work_categories_private.base_workshop_vehicle_stage_estimated_hours(p_vehicle_id,p_stage_code); END IF;
 SELECT CASE WHEN count(*) FILTER(WHERE jsonb_typeof(l->'estimated_hours') IS DISTINCT FROM 'number')=0
 THEN nullif(sum((l->>'estimated_hours')::numeric),0) END INTO result
 FROM jsonb_array_elements(lines) l WHERE coalesce((l->>'active')::boolean,true) AND l->>'stage_code'=stage
 AND NOT pdc_work_categories_private.line_completed(p_vehicle_id,l);
 RETURN result;
END $function$;

DO $g$
BEGIN
  IF strpos((SELECT prosrc FROM pg_proc WHERE oid='public.workshop_vehicle_stage_estimated_hours(uuid,text)'::regprocedure), 'pdc_panel_line_completion_565') <> 0 THEN
    RAISE EXCEPTION 'r594 undo: ticked lines are still excluded';
  END IF;
  DELETE FROM pdc_ops.regression_checks WHERE check_name='outstanding_station_hours_594' AND added_in='r594';
END $g$;
