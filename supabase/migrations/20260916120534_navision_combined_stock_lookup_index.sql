-- Match the exact current-dealer stock predicate used by import preflight.
-- This index preserves all duplicate counts and validation outcomes.
CREATE INDEX navision_preflight_current_dealer_stock_idx
ON public.navision_backend_records(dealer_code,public.normalize_vehicle_stock_number(normalized_data->>'batch'))
WHERE source_system='microsoft_navision' AND is_current AND record_status='current';
ANALYZE public.navision_backend_records;
