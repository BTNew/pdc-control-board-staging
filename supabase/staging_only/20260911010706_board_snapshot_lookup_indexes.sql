DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd') OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'STAGING only'; END IF; END $$;
SET LOCAL lock_timeout='3s';
CREATE INDEX pdc_service_operation_history_lookup_idx ON public.pdc_pilbara_service_operation_history(operation_id,created_at DESC);
CREATE INDEX pdc_service_operations_vehicle_order_idx ON public.pdc_pilbara_service_operations(vehicle_id,source_order);
