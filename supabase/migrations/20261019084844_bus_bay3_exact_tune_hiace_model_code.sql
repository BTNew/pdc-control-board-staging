-- Exact Tune model-code recognition for the existing HiAce-only Bus Bay3.
DO $guard$ BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR auth.uid() IS NOT NULL OR NOT pdc_codex_intake_private.management_connection() THEN RAISE EXCEPTION 'staging_management_required'; END IF;
 IF md5((SELECT prosrc FROM pg_proc WHERE oid='pdc_bus_private.booking_rule(uuid,uuid,uuid)'::regprocedure))<>'4df68a4ea1ebc2d9732317cfe298dcaf' THEN RAISE EXCEPTION 'booking_rule_changed_review_required'; END IF;
END $guard$;
CREATE OR REPLACE FUNCTION pdc_bus_private.booking_rule(p_vehicle_id uuid, p_bay_id uuid, p_booking_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE bay integer; code text; stage text; ready jsonb; model_name text;
BEGIN
 SELECT b.bay_number,s.code INTO bay,code FROM public.workshop_bays b JOIN public.workshop_stages s ON s.id=b.stage_id WHERE b.id=p_bay_id;
 IF code IS DISTINCT FROM 'BUS_4X4' OR NOT pdc_bus_private.active_vehicle(p_vehicle_id) THEN RETURN jsonb_build_object('ok',true); END IF;
 SELECT concat_ws(' ',v.model,v.vehicle_description) INTO model_name FROM public.vehicles v WHERE id=p_vehicle_id;
 IF bay=3 AND (model_name~* 'coaster' OR (model_name!~* 'hi[[:space:]-]?ace' AND upper(btrim(model_name))<>'TOYHIA')) THEN RETURN jsonb_build_object('ok',false,'error','bus_bay_vehicle_incompatible','bay_number',3,'required_model','HiAce'); END IF;
 IF EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.id=p_booking_id AND b.vehicle_id=p_vehicle_id
  AND b.bay_id=p_bay_id AND b.deleted_at IS NULL AND b.status IN('planned','started','stoppage')) THEN RETURN jsonb_build_object('ok',true); END IF;
 RETURN jsonb_build_object('ok',true);
END $function$

;
-- CREATE OR REPLACE retains the existing postgres-only function ACL.
