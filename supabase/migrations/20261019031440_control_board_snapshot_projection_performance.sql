-- Control Board search identity must not rebuild every operation at every station.
-- Department and active flags are inherited unchanged from source operations and adjustments.
-- Preserve all grants, authorization callers, bookings, categories and hours.
DO $repair$
DECLARE before_values jsonb; after_values jsonb;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'staging_only'; END IF;
 IF md5(replace(pg_get_functiondef('pdc_bus_private.active_vehicle(uuid)'::regprocedure),chr(13),'')) <> 'f45c60e44690bc3092f761465cd968e7' THEN RAISE EXCEPTION 'reviewed_function_changed'; END IF;
 SELECT jsonb_object_agg(v.id::text,pdc_bus_private.active_vehicle(v.id)) INTO before_values FROM public.vehicles v;
 EXECUTE $definition$
 CREATE OR REPLACE FUNCTION pdc_bus_private.active_vehicle(p_vehicle_id uuid)
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'pg_catalog'
 AS $body$
 SELECT EXISTS(
  SELECT 1 FROM public.vehicles v
  JOIN public.pdc_pilbara_service_operations o ON o.vehicle_id=v.id AND o.stock_number=v.stock_number
  LEFT JOIN public.vehicle_workshop_line_adjustments a
   ON a.vehicle_id=o.vehicle_id AND a.line_key='source:'||o.operation_id::text
  WHERE v.id=p_vehicle_id AND v.deleted_at IS NULL AND v.lifecycle_state='active'
   AND o.department='138' AND coalesce(a.active,true)
 )
 $body$
 $definition$;
 SELECT jsonb_object_agg(v.id::text,pdc_bus_private.active_vehicle(v.id)) INTO after_values FROM public.vehicles v;
 IF before_values IS DISTINCT FROM after_values THEN RAISE EXCEPTION 'department_identity_parity_failed'; END IF;
END $repair$;
