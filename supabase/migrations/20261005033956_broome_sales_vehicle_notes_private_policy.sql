-- The private table is accessible only through the scoped RPC helpers.
DO $guard$ BEGIN IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'Staging only'; END IF; END $guard$;
CREATE POLICY vehicle_notes_rpc_only ON pdc_sales_private.vehicle_notes FOR ALL
TO anon,authenticated USING(false) WITH CHECK(false);
