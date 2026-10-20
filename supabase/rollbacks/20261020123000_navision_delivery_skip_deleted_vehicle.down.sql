-- Restore the Delivered - At Dealer hard stop and remove the review list.
-- Rollback for supabase/migrations/20261020123000_navision_delivery_skip_deleted_vehicle.sql
-- Apply by hand on staging project cdsmnqxtyyoeoznmbidd only.

DO $guard$
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'staging_only';
  END IF;
END
$guard$;

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
 result:=public.reconcile_navision_operational_record(v_backend_record_id,auth.uid(),public.current_actor_email());
 SELECT * INTO b FROM public.navision_backend_records WHERE id=v_backend_record_id;
 IF b.canonical_vehicle_id IS NOT NULL AND b.is_current AND b.record_status='current'
 AND lower(regexp_replace(btrim(coalesce(b.normalized_data->>'toyotaStatus','')),'[[:space:]–-]','','g'))='deliveredatdealer'
 AND result->>'ok' IS DISTINCT FROM 'true' THEN
  RAISE EXCEPTION 'navision_dealer_delivery_failed: %',result->>'code';
 END IF;
 RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION pdc_navision_delivery_private.reconcile_link()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
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

DO $unwrap$
BEGIN
  IF to_regprocedure('public.apply_navision_upload_profile(text,text,jsonb,text,timestamp with time zone,text,text,bigint)') IS NOT NULL
     AND EXISTS (
       SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public' AND p.proname = 'apply_navision_upload_profile'
         AND position('attach_import_reviews' in p.prosrc) > 0
     ) THEN
    EXECUTE $sql$
      CREATE OR REPLACE FUNCTION public.apply_navision_upload_profile(p_profile text, p_idempotency_key text, p_rows jsonb, p_source_name text, p_source_timestamp timestamp with time zone, p_source_hash text, p_preview_hash text, p_expected_revision bigint)
      RETURNS jsonb
      LANGUAGE sql
      SECURITY INVOKER
      SET search_path = pg_catalog
      AS $fn$ SELECT pdc_navision_upload_private.apply_profile(p_profile,p_idempotency_key,p_rows,p_source_name,p_source_timestamp,p_source_hash,p_preview_hash,p_expected_revision) $fn$
    $sql$;
  END IF;
  IF to_regprocedure('pdc_navision_delivery_private.apply_navision_combined_import(text,jsonb,text,timestamp with time zone,text,text,bigint)') IS NOT NULL THEN
    DROP FUNCTION IF EXISTS public.apply_navision_combined_import(text,jsonb,text,timestamp with time zone,text,text,bigint);
    ALTER FUNCTION pdc_navision_delivery_private.apply_navision_combined_import(text,jsonb,text,timestamp with time zone,text,text,bigint) SET SCHEMA public;
  END IF;
  IF to_regprocedure('pdc_navision_delivery_private.apply_navision_backend_import(text,jsonb,text,text,text,timestamp with time zone,text,text,bigint)') IS NOT NULL THEN
    DROP FUNCTION IF EXISTS public.apply_navision_backend_import(text,jsonb,text,text,text,timestamp with time zone,text,text,bigint);
    ALTER FUNCTION pdc_navision_delivery_private.apply_navision_backend_import(text,jsonb,text,text,text,timestamp with time zone,text,text,bigint) SET SCHEMA public;
  END IF;
  IF to_regprocedure('pdc_navision_delivery_private.apply_navision_backend_import(text,jsonb,text,timestamp with time zone,text,text,bigint)') IS NOT NULL THEN
    DROP FUNCTION IF EXISTS public.apply_navision_backend_import(text,jsonb,text,timestamp with time zone,text,text,bigint);
    ALTER FUNCTION pdc_navision_delivery_private.apply_navision_backend_import(text,jsonb,text,timestamp with time zone,text,text,bigint) SET SCHEMA public;
  END IF;
END
$unwrap$;

REVOKE USAGE ON SCHEMA pdc_navision_delivery_private FROM authenticated, service_role;
DROP FUNCTION IF EXISTS pdc_navision_delivery_private.attach_import_reviews(jsonb);
DROP FUNCTION IF EXISTS pdc_navision_delivery_private.note_delivery_vehicle_absent(public.navision_backend_records);
DROP FUNCTION IF EXISTS pdc_navision_delivery_private.delivery_vehicle_absent(public.navision_backend_records);
DROP FUNCTION IF EXISTS pdc_navision_delivery_private.delivery_stock(public.navision_backend_records);
DROP TABLE IF EXISTS pdc_navision_delivery_private.import_reviews;

DO $check$
BEGIN
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = 'trigger_reconcile_navision_operational_record')
     IS DISTINCT FROM '59dc9d0ecaa8e1729e23a4d802cc0abe' THEN
    RAISE EXCEPTION 'navision_delivery_skip_rollback_incomplete';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'pdc_navision_delivery_private' AND p.proname = 'reconcile_link')
     IS DISTINCT FROM 'f62e1d8d7e33c0a3822becfef0d59510' THEN
    RAISE EXCEPTION 'navision_delivery_skip_rollback_incomplete';
  END IF;
END
$check$;
