-- The Pilbara upload moves stock 13045140 from Delivered - At Body Builder
-- to Delivered - At Dealer. Its vehicle was soft-deleted on 19 Oct 2026.
LOAD 'safeupdate';
SET ROLE authenticated;
DO $case$
DECLARE result jsonb;
BEGIN
  result := public.apply_navision_upload_profile(
    'pilbara', 'idem-13045140', '[]'::jsonb, 'pilbara.txt', NULL, 'source', 'preview', 1);
  IF result->>'ok' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'upload aborted: %', result;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(result->'data'->'delivery_reviews') review
    WHERE review->>'stock_number' = '13045140'
      AND review->>'reason' = 'delivery_vehicle_not_found'
      AND review->>'detail' = 'linked vehicle is soft-deleted'
  ) THEN
    RAISE EXCEPTION 'stock 13045140 was not flagged on the upload result: %', result;
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(result->'data'->'delivery_reviews') review
    WHERE review->>'stock_number' = 'QA-KEEP-1'
  ) THEN
    RAISE EXCEPTION 'the kept row was flagged: %', result;
  END IF;
END
$case$;
RESET ROLE;

DO $saved$
BEGIN
  IF (SELECT normalized_data->>'toyotaStatus' FROM public.navision_backend_records
      WHERE id = '6906a7ff-a37f-4bd7-a177-131569874804') IS DISTINCT FROM 'Delivered - At Dealer' THEN
    RAISE EXCEPTION 'stock 13045140 status was not saved';
  END IF;
  IF (SELECT normalized_data->>'order' FROM public.navision_backend_records
      WHERE id = '6906a7ff-a37f-4bd7-a177-131569874804') IS DISTINCT FROM '260021806' THEN
    RAISE EXCEPTION 'order 260021806 was not kept';
  END IF;
  IF (SELECT dealer_code FROM public.navision_backend_records
      WHERE id = '6906a7ff-a37f-4bd7-a177-131569874804') IS DISTINCT FROM '14450' THEN
    RAISE EXCEPTION 'dealer 14450 was not kept';
  END IF;
  IF (SELECT deleted_at FROM public.vehicles WHERE id = 'f63ee01e-091c-4f67-95a2-5013ceb0c3f8')
     IS DISTINCT FROM '2026-10-19 07:25:52.425943+00' THEN
    RAISE EXCEPTION 'soft-deleted vehicle was restored or changed';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.delivery_reconcile_calls
    WHERE backend_record_id = '6906a7ff-a37f-4bd7-a177-131569874804'
  ) THEN
    RAISE EXCEPTION 'delivery reconcile ran for the soft-deleted vehicle';
  END IF;
  IF (SELECT normalized_data->>'upload_kept' FROM public.navision_backend_records
      WHERE id = '22222222-2222-4222-8222-222222222222') IS DISTINCT FROM 'yes' THEN
    RAISE EXCEPTION 'the rest of the upload did not commit';
  END IF;
  IF (SELECT reason FROM public.navision_import_items
      WHERE backend_record_id = '6906a7ff-a37f-4bd7-a177-131569874804')
     IS DISTINCT FROM 'delivery_vehicle_not_found' THEN
    RAISE EXCEPTION 'import item was not flagged';
  END IF;
  IF (SELECT reason FROM public.navision_import_items
      WHERE backend_record_id = '22222222-2222-4222-8222-222222222222') IS NOT NULL THEN
    RAISE EXCEPTION 'kept import item was flagged';
  END IF;
END
$saved$;

SET ROLE authenticated;
DO $hard$
BEGIN
  PERFORM set_config('pdc.delivery_ok', 'false', true);
  PERFORM set_config('pdc.delivery_code', 'delivery_wrong_dealer_scope', true);
  UPDATE public.navision_backend_records
  SET normalized_data = normalized_data || jsonb_build_object('toyotaStatus', 'Delivered - At Dealer')
  WHERE id = '22222222-2222-4222-8222-222222222222';
  RAISE EXCEPTION 'other delivery failure was swallowed';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%navision_dealer_delivery_failed: delivery_wrong_dealer_scope (stock QA-KEEP-1)%' THEN
      RAISE EXCEPTION 'hard delivery error did not name the stock: %', SQLERRM;
    END IF;
END
$hard$;

INSERT INTO public.navision_backend_records (id, dealer_code, is_current, record_status, canonical_vehicle_id, normalized_data)
VALUES (
  '44444444-4444-4444-8444-444444444444', '14450', true, 'current',
  '55555555-5555-4555-8555-555555555555',
  jsonb_build_object('batch', 'QA-MISSING-1', 'stock', 'QA-MISSING-1', 'toyotaStatus', 'Delivered - At Body Builder')
);
UPDATE public.navision_backend_records
SET normalized_data = normalized_data || jsonb_build_object('toyotaStatus', 'Delivered - At Dealer')
WHERE id = '44444444-4444-4444-8444-444444444444';

DO $safe$
BEGIN
  DELETE FROM public.safeupdate_probe;
  RAISE EXCEPTION 'safeupdate did not reject a bare delete';
EXCEPTION
  WHEN cardinality_violation THEN
    IF SQLERRM NOT LIKE '%WHERE clause%' THEN
      RAISE EXCEPTION 'unexpected safeupdate error: %', SQLERRM;
    END IF;
END
$safe$;
RESET ROLE;

DO $missing$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pdc_navision_delivery_private.import_reviews
    WHERE stock_number = 'QA-MISSING-1'
      AND reason = 'delivery_vehicle_not_found'
      AND detail = 'linked vehicle is missing'
  ) THEN
    RAISE EXCEPTION 'missing linked vehicle was not flagged';
  END IF;
  IF EXISTS (SELECT 1 FROM public.vehicles WHERE id = '55555555-5555-4555-8555-555555555555') THEN
    RAISE EXCEPTION 'missing vehicle was created';
  END IF;
  IF (SELECT count(*) FROM public.delivery_reconcile_calls
      WHERE backend_record_id = '44444444-4444-4444-8444-444444444444') IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'delivery reconcile ran when the missing vehicle moved to Delivered - At Dealer';
  END IF;
  IF (SELECT normalized_data->>'toyotaStatus' FROM public.navision_backend_records
      WHERE id = '22222222-2222-4222-8222-222222222222') IS DISTINCT FROM 'At Yard' THEN
    RAISE EXCEPTION 'hard delivery error changed the kept row';
  END IF;
  IF (SELECT normalized_data->>'upload_kept' FROM public.navision_backend_records
      WHERE id = '22222222-2222-4222-8222-222222222222') IS DISTINCT FROM 'yes' THEN
    RAISE EXCEPTION 'hard delivery error rolled back the earlier upload';
  END IF;
END
$missing$;

CREATE FUNCTION public.apply_navision_combined_import(
  p_idempotency_key text, p_rows jsonb, p_source_name text,
  p_source_timestamp timestamp with time zone, p_source_hash text, p_preview_hash text, p_expected_revision bigint)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog
AS $probe$
  SELECT public.navision_backend_response(true, 'applied', jsonb_build_object('probe', true));
$probe$;

DO $wrap$
DECLARE
  arg_names text := 'p_idempotency_key text, p_rows jsonb, p_source_name text, p_source_timestamp timestamp with time zone, p_source_hash text, p_preview_hash text, p_expected_revision bigint';
  type_names text;
  call_names text;
  result jsonb;
BEGIN
  IF to_regprocedure('public.apply_navision_combined_import(text,jsonb,text,timestamp with time zone,text,text,bigint)') IS NULL THEN
    RAISE EXCEPTION 'combined import signature was not visible to the wrapper';
  END IF;
  type_names := regexp_replace(arg_names, '(^|, )[a-z0-9_]+ ', '\1', 'g');
  IF type_names IS DISTINCT FROM 'text, jsonb, text, timestamp with time zone, text, text, bigint' THEN
    RAISE EXCEPTION 'wrapper type list changed: %', type_names;
  END IF;
  SELECT string_agg(split_part(trim(arg), ' ', 1), ', ' ORDER BY ord)
  INTO call_names
  FROM unnest(string_to_array(arg_names, ',')) WITH ORDINALITY AS args(arg, ord);
  IF call_names IS DISTINCT FROM 'p_idempotency_key, p_rows, p_source_name, p_source_timestamp, p_source_hash, p_preview_hash, p_expected_revision' THEN
    RAISE EXCEPTION 'wrapper argument order changed: %', call_names;
  END IF;
  EXECUTE 'ALTER FUNCTION public.apply_navision_combined_import(text,jsonb,text,timestamp with time zone,text,text,bigint) SET SCHEMA pdc_navision_delivery_private';
  EXECUTE format($fmt$
    CREATE FUNCTION public.apply_navision_combined_import(%s)
    RETURNS jsonb
    LANGUAGE sql
    SECURITY INVOKER
    SET search_path = pg_catalog
    AS $fn$
      SELECT pdc_navision_delivery_private.attach_import_reviews(
        pdc_navision_delivery_private.apply_navision_combined_import(%s))
    $fn$
  $fmt$, arg_names, call_names);
  EXECUTE format('REVOKE ALL ON FUNCTION public.apply_navision_combined_import(%s) FROM PUBLIC', type_names);
  EXECUTE format('GRANT EXECUTE ON FUNCTION public.apply_navision_combined_import(%s) TO authenticated, service_role', type_names);
  BEGIN
    SET ROLE authenticated;
    result := public.apply_navision_combined_import('idem', '[]'::jsonb, 'probe.txt', NULL, 'source', 'preview', 1);
    RESET ROLE;
  EXCEPTION
    WHEN OTHERS THEN
      RESET ROLE;
      RAISE;
  END;
  IF result->>'ok' IS DISTINCT FROM 'true' OR result #>> '{data,probe}' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'combined import wrapper did not return the inner result: %', result;
  END IF;
END
$wrap$;
