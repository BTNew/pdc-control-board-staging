-- Skip Delivered - At Dealer reconciliation when the linked vehicle is
-- soft-deleted or missing. The row stays in the upload, is listed for review
-- with its stock number, and is shown on the upload result. Every other
-- delivery failure still aborts the upload, and the error names the stock.
-- Deleted vehicles are not restored. Receipt and scheduling authority are unchanged.
-- Rollback: supabase/rollbacks/20261020123000_navision_delivery_skip_deleted_vehicle.down.sql
-- Apply by hand on staging project cdsmnqxtyyoeoznmbidd only.

DO $guard$
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'staging_only';
  END IF;
  IF to_regprocedure('public.trigger_reconcile_navision_operational_record()') IS NULL
     OR to_regprocedure('pdc_navision_delivery_private.reconcile_link()') IS NULL THEN
    RAISE EXCEPTION 'navision_delivery_skip_trigger_missing';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'trigger_reconcile_navision_operational_record')
     IS DISTINCT FROM '59dc9d0ecaa8e1729e23a4d802cc0abe' THEN
    RAISE EXCEPTION 'navision_delivery_skip_trigger_changed';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_navision_delivery_private' AND p.proname = 'reconcile_link')
     IS DISTINCT FROM 'f62e1d8d7e33c0a3822becfef0d59510' THEN
    RAISE EXCEPTION 'navision_delivery_skip_link_changed';
  END IF;
END
$guard$;

CREATE SCHEMA IF NOT EXISTS pdc_navision_delivery_private;
REVOKE ALL ON SCHEMA pdc_navision_delivery_private FROM PUBLIC;

CREATE TABLE pdc_navision_delivery_private.import_reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  transaction_id bigint NOT NULL,
  batch_id uuid,
  backend_record_id uuid NOT NULL,
  stock_number text NOT NULL,
  reason text NOT NULL,
  detail text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT import_reviews_reason_check CHECK (reason = 'delivery_vehicle_not_found'),
  CONSTRAINT import_reviews_transaction_record_key UNIQUE (transaction_id, backend_record_id)
);
REVOKE ALL ON TABLE pdc_navision_delivery_private.import_reviews FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION pdc_navision_delivery_private.delivery_stock(p_record public.navision_backend_records)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $stock$
  SELECT coalesce(
    nullif(btrim(coalesce(p_record.normalized_data->>'batch', '')), ''),
    nullif(btrim(coalesce(p_record.normalized_data->>'stock', '')), ''),
    (SELECT nullif(btrim(v.stock_number), '') FROM public.vehicles v WHERE v.id = p_record.canonical_vehicle_id),
    'unknown');
$stock$;

CREATE FUNCTION pdc_navision_delivery_private.delivery_vehicle_absent(p_record public.navision_backend_records)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $absent$
  SELECT p_record.canonical_vehicle_id IS NOT NULL
    AND p_record.is_current
    AND p_record.record_status = 'current'
    AND lower(regexp_replace(btrim(coalesce(p_record.normalized_data->>'toyotaStatus', '')), '[[:space:]–-]', '', 'g')) = 'deliveredatdealer'
    AND NOT EXISTS (
      SELECT 1 FROM public.vehicles v
      WHERE v.id = p_record.canonical_vehicle_id AND v.deleted_at IS NULL
    );
$absent$;

CREATE FUNCTION pdc_navision_delivery_private.note_delivery_vehicle_absent(p_record public.navision_backend_records)
RETURNS void
LANGUAGE sql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $note$
  INSERT INTO pdc_navision_delivery_private.import_reviews (
    transaction_id, batch_id, backend_record_id, stock_number, reason, detail
  )
  SELECT txid_current(), p_record.last_seen_batch_id, p_record.id,
    pdc_navision_delivery_private.delivery_stock(p_record),
    'delivery_vehicle_not_found',
    CASE
      WHEN EXISTS (SELECT 1 FROM public.vehicles v WHERE v.id = p_record.canonical_vehicle_id)
        THEN 'linked vehicle is soft-deleted'
      ELSE 'linked vehicle is missing'
    END
  ON CONFLICT (transaction_id, backend_record_id) DO NOTHING;
$note$;

CREATE FUNCTION pdc_navision_delivery_private.attach_import_reviews(p_result jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $attach$
DECLARE
  reviews jsonb;
  result jsonb;
BEGIN
  IF p_result IS NULL OR p_result->>'ok' IS DISTINCT FROM 'true' THEN
    RETURN p_result;
  END IF;
  IF p_result #> '{data,delivery_reviews}' IS NOT NULL THEN
    RETURN p_result;
  END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'backend_record_id', review.backend_record_id,
    'batch_id', review.batch_id,
    'stock_number', review.stock_number,
    'reason', review.reason,
    'detail', review.detail
  ) ORDER BY review.stock_number, review.backend_record_id), '[]'::jsonb)
  INTO reviews
  FROM pdc_navision_delivery_private.import_reviews AS review
  WHERE review.transaction_id = txid_current();
  IF reviews = '[]'::jsonb THEN
    RETURN p_result;
  END IF;
  IF to_regclass('public.navision_import_items') IS NOT NULL THEN
    UPDATE public.navision_import_items AS item
    SET reason = review.reason
    FROM pdc_navision_delivery_private.import_reviews AS review
    WHERE review.transaction_id = txid_current()
      AND item.batch_id = review.batch_id
      AND item.backend_record_id = review.backend_record_id
      AND item.reason IS NULL;
  END IF;
  result := jsonb_set(p_result, '{data,delivery_reviews}', reviews, true);
  IF to_regclass('public.navision_import_batches') IS NOT NULL THEN
    UPDATE public.navision_import_batches AS batch
    SET receipt = result
    WHERE batch.receipt = p_result
      AND batch.id IN (
        SELECT review.batch_id
        FROM pdc_navision_delivery_private.import_reviews AS review
        WHERE review.transaction_id = txid_current()
      );
  END IF;
  IF to_regclass('public.navision_operation_receipts') IS NOT NULL THEN
    UPDATE public.navision_operation_receipts AS receipt
    SET response = result
    WHERE receipt.response = p_result
      AND receipt.batch_id IN (
        SELECT review.batch_id
        FROM pdc_navision_delivery_private.import_reviews AS review
        WHERE review.transaction_id = txid_current()
      );
  END IF;
  IF to_regclass('pdc_navision_combined_private.receipts') IS NOT NULL THEN
    UPDATE pdc_navision_combined_private.receipts AS receipt
    SET response = result
    WHERE receipt.response = p_result
      AND receipt.actor_id IS NOT DISTINCT FROM auth.uid();
  END IF;
  RETURN result;
END
$attach$;

REVOKE ALL ON FUNCTION pdc_navision_delivery_private.delivery_stock(public.navision_backend_records) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION pdc_navision_delivery_private.delivery_vehicle_absent(public.navision_backend_records) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION pdc_navision_delivery_private.note_delivery_vehicle_absent(public.navision_backend_records) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION pdc_navision_delivery_private.attach_import_reviews(jsonb) FROM PUBLIC, anon, authenticated, service_role;
GRANT USAGE ON SCHEMA pdc_navision_delivery_private TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION pdc_navision_delivery_private.attach_import_reviews(jsonb) TO authenticated, service_role;
ALTER TABLE pdc_navision_delivery_private.import_reviews ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.trigger_reconcile_navision_operational_record()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE v_backend_record_id uuid; result jsonb; b public.navision_backend_records%rowtype;
BEGIN
 IF pg_trigger_depth()>1 THEN RETURN NEW; END IF;
 IF TG_TABLE_NAME='navision_board_activations' THEN
  v_backend_record_id:=NEW.backend_record_id;
 ELSE
  v_backend_record_id:=NEW.id;
 END IF;
 SELECT * INTO b FROM public.navision_backend_records WHERE id=v_backend_record_id;
 IF pdc_navision_delivery_private.delivery_vehicle_absent(b) THEN
  PERFORM pdc_navision_delivery_private.note_delivery_vehicle_absent(b);
  RETURN NEW;
 END IF;
 result:=public.reconcile_navision_operational_record(v_backend_record_id,auth.uid(),public.current_actor_email());
 IF b.canonical_vehicle_id IS NOT NULL AND b.is_current AND b.record_status='current'
 AND lower(regexp_replace(btrim(coalesce(b.normalized_data->>'toyotaStatus','')),'[[:space:]–-]','','g'))='deliveredatdealer'
 AND result->>'ok' IS DISTINCT FROM 'true' THEN
  RAISE EXCEPTION 'navision_dealer_delivery_failed: % (stock %)', result->>'code', pdc_navision_delivery_private.delivery_stock(b);
 END IF;
 RETURN NEW;
END
$function$;

CREATE OR REPLACE FUNCTION pdc_navision_delivery_private.reconcile_link()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE result jsonb;
BEGIN
 IF pdc_navision_delivery_private.delivery_vehicle_absent(NEW::public.navision_backend_records) THEN
  PERFORM pdc_navision_delivery_private.note_delivery_vehicle_absent(NEW::public.navision_backend_records);
  RETURN NEW;
 END IF;
 IF NEW.canonical_vehicle_id IS NOT NULL AND NEW.is_current AND NEW.record_status='current'
 AND lower(regexp_replace(btrim(coalesce(NEW.normalized_data->>'toyotaStatus','')),'[[:space:]–-]','','g'))='deliveredatdealer' THEN
  result:=public.reconcile_navision_delivery_734(NEW.id,auth.uid(),public.current_actor_email());
  IF result->>'ok' IS DISTINCT FROM 'true' THEN
   RAISE EXCEPTION 'navision_dealer_delivery_failed: % (stock %)', result->>'code', pdc_navision_delivery_private.delivery_stock(NEW::public.navision_backend_records);
  END IF;
 END IF;
 RETURN NEW;
END
$function$;

DO $wrap$
DECLARE
  upload_md5 text;
BEGIN
  SELECT md5(p.prosrc) INTO upload_md5
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'apply_navision_upload_profile'
    AND pg_get_function_identity_arguments(p.oid) = 'p_profile text, p_idempotency_key text, p_rows jsonb, p_source_name text, p_source_timestamp timestamp with time zone, p_source_hash text, p_preview_hash text, p_expected_revision bigint';
  IF upload_md5 IS NULL THEN
    NULL;
  ELSIF upload_md5 IS DISTINCT FROM '7ba707a0cf564840cd6aaaa9f49a6aec' THEN
    RAISE EXCEPTION 'navision_delivery_review_apply_changed: apply_navision_upload_profile';
  ELSE
    EXECUTE $sql$
      CREATE OR REPLACE FUNCTION public.apply_navision_upload_profile(p_profile text, p_idempotency_key text, p_rows jsonb, p_source_name text, p_source_timestamp timestamp with time zone, p_source_hash text, p_preview_hash text, p_expected_revision bigint)
      RETURNS jsonb
      LANGUAGE sql
      SECURITY INVOKER
      SET search_path = pg_catalog
      AS $fn$
        SELECT pdc_navision_delivery_private.attach_import_reviews(
          pdc_navision_upload_private.apply_profile(p_profile, p_idempotency_key, p_rows, p_source_name, p_source_timestamp, p_source_hash, p_preview_hash, p_expected_revision))
      $fn$
    $sql$;
    EXECUTE 'REVOKE ALL ON FUNCTION public.apply_navision_upload_profile(text,text,jsonb,text,timestamp with time zone,text,text,bigint) FROM PUBLIC';
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.apply_navision_upload_profile(text,text,jsonb,text,timestamp with time zone,text,text,bigint) TO authenticated';
  END IF;
END
$wrap$;

DO $move$
DECLARE
  spec record;
  current_md5 text;
BEGIN
  FOR spec IN
    SELECT *
    FROM (VALUES
      ('public.apply_navision_combined_import(text,jsonb,text,timestamp with time zone,text,text,bigint)',
       '3c4206168cd87fa2db86180f09208fae',
       'p_idempotency_key text, p_rows jsonb, p_source_name text, p_source_timestamp timestamp with time zone, p_source_hash text, p_preview_hash text, p_expected_revision bigint',
       'apply_navision_combined_import',
       'authenticated, service_role'),
      ('public.apply_navision_backend_import(text,jsonb,text,text,text,timestamp with time zone,text,text,bigint)',
       'c27ba8aa29cbb714e210c0a0bfad0b0b',
       'p_idempotency_key text, p_rows jsonb, p_source_system text, p_dealer_code text, p_source_name text, p_source_timestamp timestamp with time zone, p_source_hash text, p_preview_hash text, p_expected_revision bigint',
       'apply_navision_backend_import',
       'authenticated'),
      ('public.apply_navision_backend_import(text,jsonb,text,timestamp with time zone,text,text,bigint)',
       'c0a9e340257b133019ff363871909fec',
       'p_idempotency_key text, p_rows jsonb, p_source_name text, p_source_timestamp timestamp with time zone, p_source_hash text, p_preview_hash text, p_expected_revision bigint',
       'apply_navision_backend_import',
       'service_role')
    ) AS listed(regsignature, expected_md5, arg_names, func_name, grantees)
  LOOP
    IF to_regprocedure(spec.regsignature) IS NULL THEN
      CONTINUE;
    END IF;
    SELECT md5(p.prosrc) INTO current_md5 FROM pg_proc p WHERE p.oid = to_regprocedure(spec.regsignature);
    IF current_md5 IS DISTINCT FROM spec.expected_md5 THEN
      RAISE EXCEPTION 'navision_delivery_review_apply_changed: %', spec.regsignature;
    END IF;
    EXECUTE format('ALTER FUNCTION %s SET SCHEMA pdc_navision_delivery_private', spec.regsignature);
    EXECUTE format($fmt$
      CREATE FUNCTION public.%I(%s)
      RETURNS jsonb
      LANGUAGE sql
      SECURITY INVOKER
      SET search_path = pg_catalog
      AS $fn$
        SELECT pdc_navision_delivery_private.attach_import_reviews(
          pdc_navision_delivery_private.%I(%s))
      $fn$
    $fmt$, spec.func_name, spec.arg_names, spec.func_name,
      (SELECT string_agg(split_part(trim(arg), ' ', 1), ', ' ORDER BY ord)
       FROM unnest(string_to_array(spec.arg_names, ',')) WITH ORDINALITY AS args(arg, ord)));
    EXECUTE format('REVOKE ALL ON FUNCTION public.%I(%s) FROM PUBLIC', spec.func_name,
      regexp_replace(spec.arg_names, '(^|, )[a-z0-9_]+ ', '\1', 'g'));
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.%I(%s) TO %s', spec.func_name,
      regexp_replace(spec.arg_names, '(^|, )[a-z0-9_]+ ', '\1', 'g'), spec.grantees);
  END LOOP;
END
$move$;
