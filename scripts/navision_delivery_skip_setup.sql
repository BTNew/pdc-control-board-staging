-- Reproduce stock 13045140, order 260021806, dealer 14450 (source file 014450).
-- The linked vehicle was soft-deleted on 19 Oct 2026. The upload changes
-- Delivered - At Body Builder to Delivered - At Dealer. That row is flagged
-- and the rest of the upload commits. The customer export is not stored here.
CREATE SCHEMA IF NOT EXISTS auth;
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT '00000000-0000-4000-8000-0000000000a1'::uuid $$;
CREATE OR REPLACE FUNCTION public.current_actor_email() RETURNS text LANGUAGE sql STABLE AS $$ SELECT 'importer@staging.invalid' $$;
CREATE OR REPLACE FUNCTION public.pdc_monitor_staging_guard() RETURNS boolean LANGUAGE sql STABLE AS $$ SELECT true $$;
CREATE OR REPLACE FUNCTION public.navision_backend_response(ok boolean, code text, data jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_build_object('ok', ok, 'code', code, 'data', coalesce(data, '{}'::jsonb));
$$;

CREATE TABLE public.vehicles (
  id uuid PRIMARY KEY,
  deleted_at timestamptz,
  stock_number text,
  source_batch_id text
);
CREATE TABLE public.navision_backend_records (
  id uuid PRIMARY KEY,
  dealer_code text NOT NULL,
  is_current boolean NOT NULL,
  record_status text NOT NULL,
  canonical_vehicle_id uuid,
  normalized_data jsonb NOT NULL,
  last_seen_batch_id uuid
);
CREATE TABLE public.navision_import_batches (
  id uuid PRIMARY KEY,
  receipt jsonb,
  actor_id uuid
);
CREATE TABLE public.navision_import_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id uuid NOT NULL,
  backend_record_id uuid NOT NULL,
  row_index integer NOT NULL,
  source_record_id text,
  classification text,
  reason text
);
CREATE TABLE public.delivery_reconcile_calls (
  backend_record_id uuid NOT NULL,
  called_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE public.safeupdate_probe (id integer PRIMARY KEY);

CREATE FUNCTION public.reconcile_navision_operational_record(p_backend_record_id uuid, p_actor_id uuid DEFAULT NULL, p_actor_email text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE b public.navision_backend_records%rowtype; v public.vehicles%rowtype;
BEGIN
  INSERT INTO public.delivery_reconcile_calls (backend_record_id) VALUES (p_backend_record_id);
  SELECT * INTO b FROM public.navision_backend_records WHERE id = p_backend_record_id;
  SELECT * INTO v FROM public.vehicles WHERE id = b.canonical_vehicle_id;
  IF lower(regexp_replace(btrim(coalesce(b.normalized_data->>'toyotaStatus', '')), '[[:space:]–-]', '', 'g')) = 'deliveredatdealer'
     AND (NOT FOUND OR v.deleted_at IS NOT NULL) THEN
    RETURN public.navision_backend_response(false, 'delivery_vehicle_not_found');
  END IF;
  RETURN public.navision_backend_response(
    coalesce(current_setting('pdc.delivery_ok', true), 'true') = 'true',
    coalesce(nullif(current_setting('pdc.delivery_code', true), ''), 'delivered_at_dealer_completed'));
END $$;

CREATE FUNCTION public.reconcile_navision_delivery_734(p_backend_record_id uuid, p_actor_id uuid DEFAULT NULL, p_actor_email text DEFAULT NULL)
RETURNS jsonb LANGUAGE sql AS $$
  SELECT public.reconcile_navision_operational_record(p_backend_record_id, p_actor_id, p_actor_email);
$$;

CREATE SCHEMA pdc_navision_delivery_private;
CREATE FUNCTION public.trigger_reconcile_navision_operational_record()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
AS $function$
DECLARE v_backend_record_id uuid; result jsonb; b public.navision_backend_records%rowtype;
BEGIN
 IF pg_trigger_depth()>1 THEN RETURN NEW; END IF;
 IF TG_TABLE_NAME='navision_board_activations' THEN
  v_backend_record_id:=NEW.backend_record_id;
 ELSE
  v_backend_record_id:=NEW.id;
 END IF;
 result:=public.reconcile_navision_operational_record(v_backend_record_id,auth.uid(),public.current_actor_email());
 SELECT * INTO b FROM public.navision_backend_records WHERE id=v_backend_record_id;
 IF b.canonical_vehicle_id IS NOT NULL AND b.is_current AND b.record_status='current'
 AND lower(regexp_replace(btrim(coalesce(b.normalized_data->>'toyotaStatus','')),'[[:space:]–-]','','g'))='deliveredatdealer'
 AND result->>'ok' IS DISTINCT FROM 'true' THEN
  RAISE EXCEPTION 'navision_dealer_delivery_failed: %',result->>'code';
 END IF;
 RETURN NEW;
END $function$;
CREATE FUNCTION pdc_navision_delivery_private.reconcile_link()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $function$
DECLARE result jsonb;
BEGIN
 IF NEW.canonical_vehicle_id IS NOT NULL AND NEW.is_current AND NEW.record_status='current'
 AND lower(regexp_replace(btrim(coalesce(NEW.normalized_data->>'toyotaStatus','')),'[[:space:]–-]','','g'))='deliveredatdealer' THEN
  result:=public.reconcile_navision_delivery_734(NEW.id,auth.uid(),public.current_actor_email());
  IF result->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'navision_dealer_delivery_failed: %',result->>'code'; END IF;
 END IF;
 RETURN NEW;
END $function$;

CREATE TRIGGER navision_record_operational_reconcile
AFTER INSERT OR UPDATE OF normalized_data, is_current, record_status
ON public.navision_backend_records
FOR EACH ROW EXECUTE FUNCTION public.trigger_reconcile_navision_operational_record();

CREATE SCHEMA pdc_navision_upload_private;
CREATE FUNCTION pdc_navision_upload_private.apply_profile(
  p_profile text, p_idempotency_key text, p_rows jsonb, p_source_name text,
  p_source_timestamp timestamptz, p_source_hash text, p_preview_hash text, p_expected_revision bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $apply$
DECLARE
  batch_id uuid := '11111111-1111-4111-8111-111111111111';
  kept_id uuid := '22222222-2222-4222-8222-222222222222';
BEGIN
  INSERT INTO public.navision_import_batches (id) VALUES (batch_id);
  UPDATE public.navision_backend_records
  SET normalized_data = normalized_data || jsonb_build_object('toyotaStatus', 'Delivered - At Dealer'),
      last_seen_batch_id = batch_id
  WHERE id = '6906a7ff-a37f-4bd7-a177-131569874804';
  UPDATE public.navision_backend_records
  SET normalized_data = normalized_data || jsonb_build_object('upload_kept', 'yes'),
      last_seen_batch_id = batch_id
  WHERE id = kept_id;
  INSERT INTO public.navision_import_items (batch_id, backend_record_id, row_index, source_record_id, classification)
  VALUES
    (batch_id, '6906a7ff-a37f-4bd7-a177-131569874804', 839, '260021806', 'changed'),
    (batch_id, kept_id, 2, 'QA-KEEP-ORDER', 'changed');
  RETURN public.navision_backend_response(true, 'applied', jsonb_build_object('batch_id', batch_id, 'kept_stock', 'QA-KEEP-1'));
END $apply$;

CREATE FUNCTION public.apply_navision_upload_profile(
  p_profile text, p_idempotency_key text, p_rows jsonb, p_source_name text,
  p_source_timestamp timestamp with time zone, p_source_hash text, p_preview_hash text, p_expected_revision bigint)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path = pg_catalog
AS $fn$ SELECT pdc_navision_upload_private.apply_profile(p_profile,p_idempotency_key,p_rows,p_source_name,p_source_timestamp,p_source_hash,p_preview_hash,p_expected_revision) $fn$;

INSERT INTO public.vehicles (id, deleted_at, stock_number, source_batch_id)
VALUES ('f63ee01e-091c-4f67-95a2-5013ceb0c3f8', '2026-10-19 07:25:52.425943+00', NULL, '14450');
INSERT INTO public.navision_backend_records (id, dealer_code, is_current, record_status, canonical_vehicle_id, normalized_data)
VALUES (
  '6906a7ff-a37f-4bd7-a177-131569874804',
  '14450', true, 'current',
  'f63ee01e-091c-4f67-95a2-5013ceb0c3f8',
  jsonb_build_object('batch', '13045140', 'stock', '13045140', 'order', '260021806', 'toyotaStatus', 'Delivered - At Body Builder')
);
INSERT INTO public.vehicles (id, deleted_at, stock_number, source_batch_id)
VALUES ('33333333-3333-4333-8333-333333333333', NULL, 'QA-KEEP-1', '14450');
INSERT INTO public.navision_backend_records (id, dealer_code, is_current, record_status, canonical_vehicle_id, normalized_data)
VALUES (
  '22222222-2222-4222-8222-222222222222',
  '14450', true, 'current',
  '33333333-3333-4333-8333-333333333333',
  jsonb_build_object('batch', 'QA-KEEP-1', 'stock', 'QA-KEEP-1', 'order', 'QA-KEEP-ORDER', 'toyotaStatus', 'At Yard')
);
DELETE FROM public.delivery_reconcile_calls;
INSERT INTO public.safeupdate_probe VALUES (1);

GRANT USAGE ON SCHEMA public, pdc_navision_upload_private TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.vehicles, public.navision_backend_records, public.navision_import_batches, public.navision_import_items, public.delivery_reconcile_calls, public.safeupdate_probe TO authenticated;
GRANT EXECUTE ON FUNCTION public.apply_navision_upload_profile(text,text,jsonb,text,timestamp with time zone,text,text,bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION pdc_navision_upload_private.apply_profile(text,text,jsonb,text,timestamp with time zone,text,text,bigint) TO authenticated;
