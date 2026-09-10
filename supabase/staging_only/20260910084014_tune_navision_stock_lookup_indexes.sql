-- STAGING only. Keep exact Stock review and daily identity matching indexed.
DO $$ BEGIN IF public.pdc_monitor_staging_guard() IS NOT TRUE OR NOT EXISTS(SELECT 1 FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd') OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'STAGING only'; END IF; END $$;
CREATE INDEX pdc_navision_exact_stock_tune_v5_idx ON public.navision_backend_records ((btrim(coalesce(normalized_data->>'batch',normalized_data->>'stock','')))) WHERE source_system='microsoft_navision' AND is_current AND record_status='current';
CREATE INDEX pdc_navision_normalized_stock_tune_v5_idx ON public.navision_backend_records ((public.normalize_vehicle_stock_number(coalesce(normalized_data->>'batch',normalized_data->>'stock')))) WHERE source_system='microsoft_navision' AND is_current AND record_status='current';
ANALYZE public.navision_backend_records;
