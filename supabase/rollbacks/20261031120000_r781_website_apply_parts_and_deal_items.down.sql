-- Rollback r781 (F386): stop the worker, restore the KTA normalize body, drop the queue and its functions.
DO $d$
DECLARE v_src text; v_def text; sig regprocedure := 'pdc_sales_private.karratha_sales_accessory_normalize_528(jsonb,jsonb)'::regprocedure;
BEGIN
  PERFORM cron.unschedule('pdc-import-other-781');
  SELECT prosrc INTO v_src FROM pdc_backup_r763_20261031.function_sources WHERE sig = 'pdc_sales_private.karratha_sales_accessory_normalize_528(jsonb,jsonb)@r781pre';
  IF md5(v_src) <> 'ef85e5393c5039ac4e8421f6b058c405' THEN RAISE EXCEPTION 'backup missing'; END IF;
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_src || substring(v_def from '\$[a-zA-Z_]*\$$');
  DELETE FROM pdc_ops.regression_checks WHERE check_name = 'website_apply_other_reports_781';
END $d$;
DROP PROCEDURE pdc_import_620.run_other_781();
DROP FUNCTION public.revolution_upload_other_status_781(uuid);
DROP FUNCTION public.revolution_upload_other_781(text, text, text, jsonb, jsonb);
DROP FUNCTION pdc_import_620.web_upload_781_ok(jsonb);
DROP TABLE pdc_import_620.other_uploads_781;
