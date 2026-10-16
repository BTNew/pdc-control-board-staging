-- The catalogue reader repeatedly finds one exact operation inside an import
-- batch. Keep its full JSON/source checks and latest-observation ordering; only
-- provide an index for the existing equality predicates. No data or RPC changes.
DO $guard$
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'Staging project required';
 END IF;
 IF md5(pg_get_functiondef('pdc_codex_intake_private.service_catalogue_hours_20260917(jsonb)'::regprocedure))
      IS DISTINCT FROM '87a97ec186c44e1f737b10615dcbfcac' THEN
  RAISE EXCEPTION 'Reviewed catalogue evidence reader changed';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='public.pdc_pilbara_service_import_rows'::regclass AND relkind='r')
 OR (SELECT count(*) FROM (VALUES
     ('batch_id','uuid'),('stock_number','text'),('repair_order_number','text'),
     ('original_line_number','integer'),('decision','text')) expected(name,type)
     JOIN pg_attribute a ON a.attrelid='public.pdc_pilbara_service_import_rows'::regclass
      AND a.attname=expected.name AND a.attnum>0 AND NOT a.attisdropped
      AND format_type(a.atttypid,a.atttypmod)=expected.type)<>5 THEN
  RAISE EXCEPTION 'Reviewed catalogue evidence table changed';
 END IF;
END $guard$;

-- The reviewed table is about 22,500 rows / 36 MB. Bound lock acquisition so
-- deployment backs off instead of waiting behind active imports indefinitely.
SET LOCAL lock_timeout='5s';
CREATE INDEX pdc_service_import_rows_catalogue_lookup_idx
 ON public.pdc_pilbara_service_import_rows
 (batch_id,stock_number,repair_order_number,original_line_number)
 WHERE decision IN ('insert','unchanged');
