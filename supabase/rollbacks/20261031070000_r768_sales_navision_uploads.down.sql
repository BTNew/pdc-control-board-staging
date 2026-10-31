-- Rollback r768 (F430): removes the Sales Navision upload RPCs and check. The upload log table is kept (history).
DROP FUNCTION IF EXISTS public.sales_navision_upload_768(boolean, jsonb, text, text, text, text, bigint);
DROP FUNCTION IF EXISTS public.sales_navision_last_upload_768();
DELETE FROM pdc_ops.regression_checks WHERE added_in = 'r768';
