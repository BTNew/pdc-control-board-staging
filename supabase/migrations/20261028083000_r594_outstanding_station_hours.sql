-- r594 (F208) / sort 364. Staging cdsmnqxtyyoeoznmbidd only.
-- A station drag books the unticked lines for that station. Key 460 Hoist is the
-- GVM line (5.00 h), not the 12.00 h retained on the unallocated card.
-- r592 / F206 / sort 360 is the place-after release. r589 and r591 stay with their previews.
-- Nothing here books Key 460. Department 135 is not edited. No pin is inserted.
-- Undo: supabase/rollbacks/20261028083000_r594_outstanding_station_hours.down.sql

SET LOCAL lock_timeout = '2s';
DO $g$
DECLARE awst time;
BEGIN
  awst := (clock_timestamp() AT TIME ZONE 'Australia/Perth')::time;
  IF (awst >= time '06:50' AND awst < time '07:30')
     OR (awst >= time '12:20' AND awst < time '12:40')
     OR (awst >= time '17:50' AND awst < time '18:10') THEN
    RAISE EXCEPTION 'r594: Kajel import window';
  END IF;
  IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN
    RAISE EXCEPTION 'r594: run between :02 and :45';
  END IF;
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r594: staging only'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r594: pin count is not 241'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='hoist_place_after_592' AND fault_id='F206' AND sort_order=360 AND added_in='r592') THEN RAISE EXCEPTION 'r594: r592 is not present'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='new_to_pmb_view_593' AND fault_id='F207' AND sort_order=363 AND added_in='r593') THEN RAISE EXCEPTION 'r594: r593 is not present'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE sort_order=364 OR fault_id='F208' OR check_name='outstanding_station_hours_594' OR added_in='r594') THEN RAISE EXCEPTION 'r594: sort 364 / F208 is taken'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.workshop_vehicle_stage_estimated_hours(uuid,text)')) IS DISTINCT FROM '70f484ed3b141ecfa2d523dc4ebd805c' THEN RAISE EXCEPTION 'r594: station hours function is not the live body'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_pdc.fitter_job_command(uuid,uuid,integer,text,uuid,text,text,boolean,text)')) IS DISTINCT FROM 'fd05b9eef69498002ac06dd68e01cdff' THEN RAISE EXCEPTION 'r594: department 135 changed'; END IF;
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_pdc.workshop_vehicle_stage_estimated_hours(uuid,text)')) IS DISTINCT FROM '888513949fadd73e24323dbba8c8bc12' THEN RAISE EXCEPTION 'r594: department 135 hours changed'; END IF;
END $g$;

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
 -- r594 (F208): a ticked line is finished. The station total is the lines still open.
 SELECT CASE WHEN count(*) FILTER(WHERE jsonb_typeof(l->'estimated_hours') IS DISTINCT FROM 'number')=0
 THEN nullif(sum((l->>'estimated_hours')::numeric),0) END INTO result
 FROM jsonb_array_elements(lines) l WHERE coalesce((l->>'active')::boolean,true) AND l->>'stage_code'=stage
 AND NOT pdc_work_categories_private.line_completed(p_vehicle_id,l)
 AND NOT EXISTS (
   SELECT 1 FROM public.pdc_panel_line_completion_565 c
   WHERE c.vehicle_id=p_vehicle_id AND c.line_identity=l->>'line_identity' AND c.completed IS TRUE);
 RETURN result;
END $function$;

DO $after$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('karratha135_pdc.workshop_vehicle_stage_estimated_hours(uuid,text)')) IS DISTINCT FROM '888513949fadd73e24323dbba8c8bc12' THEN RAISE EXCEPTION 'r594: department 135 hours changed during the patch'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r594: pin count moved'; END IF;
END $after$;

INSERT INTO pdc_ops.regression_checks(check_name, fault_id, description, check_sql, enabled, sort_order, added_in) VALUES
('outstanding_station_hours_594', 'F208', 'A station estimate is the unticked lines only (r594). Key 460 Hoist is the open GVM line, not the ticked long-range tank or the ticked duplicate GVM line.',
$chk$
SELECT src.prosrc LIKE '%pdc_panel_line_completion_565%'
  AND src.prosrc LIKE '%r594 (F208)%'
  AND public.workshop_vehicle_stage_estimated_hours('7a64124b-ab39-4069-a6c0-b756b2dc580f'::uuid, 'HOIST') = open_hours.total
  AND open_hours.total = 5.00
  AS ok,
  'hoist open hours '||coalesce(open_hours.total::text, 'none') AS detail
FROM pg_proc src
CROSS JOIN LATERAL (
  SELECT sum((l->>'estimated_hours')::numeric) AS total
  FROM jsonb_array_elements(public.pdc_qc_operation_lines_379('7a64124b-ab39-4069-a6c0-b756b2dc580f'::uuid)) l
  WHERE l->>'stage_code'='HOIST'
    AND coalesce((l->>'active')::boolean, true)
    AND NOT EXISTS (
      SELECT 1 FROM public.pdc_panel_line_completion_565 c
      WHERE c.vehicle_id='7a64124b-ab39-4069-a6c0-b756b2dc580f'
        AND c.line_identity=l->>'line_identity'
        AND c.completed IS TRUE)
) open_hours
WHERE src.oid = 'public.workshop_vehicle_stage_estimated_hours(uuid,text)'::regprocedure
$chk$,
true, 364, 'r594');
