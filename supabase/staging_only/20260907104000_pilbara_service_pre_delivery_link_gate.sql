-- STAGING ONLY: bypass delivery wrappers only while scoped Pilbara activation establishes an unlinked vehicle.
BEGIN;
SET LOCAL lock_timeout='30s';
SET LOCAL statement_timeout='300s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-pilbara-service-pre-delivery-link-gate',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR current_setting('app.environment',true)='production'
     OR NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT (version,name)::text FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1)
        IS DISTINCT FROM '(20260907103000,pilbara_service_delivery_intercept_gate)'
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260907104000')
  THEN RAISE EXCEPTION 'PDC_20260907104000_STAGING_PREDECESSOR_OR_SCOPE_GUARD_FAILED' USING ERRCODE='55000';
  END IF;
END
$guard$;

CREATE OR REPLACE FUNCTION public.reconcile_navision_operational_record(p_backend_record_id uuid, p_actor_id uuid DEFAULT NULL::uuid, p_actor_email text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE b public.navision_backend_records%rowtype; v public.vehicles%rowtype; raw_status text; normalized text;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() THEN RETURN public.navision_backend_response(false,'wrong_environment'); END IF;
  SELECT * INTO b FROM public.navision_backend_records WHERE id=p_backend_record_id;
  IF FOUND THEN
    raw_status:=btrim(coalesce(b.normalized_data->>'toyotaStatus',''));
    normalized:=lower(replace(replace(replace(btrim(raw_status),'–','-'),' ',''),'-',''));
    IF normalized='deliveredatdealer' THEN
      IF b.canonical_vehicle_id IS NULL
         AND EXISTS(SELECT 1 FROM public.navision_board_activations a
           WHERE a.backend_record_id=b.id AND a.active AND a.activation_source='approved_email_build')
         AND public.current_pdc_user_role()::text='viewer'
         AND EXISTS(SELECT 1 FROM public.pdc_email_ai_successor_runtime_identities i
           WHERE i.auth_user_id=auth.uid() AND i.normalized_email=lower(btrim(coalesce(auth.jwt()->>'email','')))
             AND i.environment='staging' AND i.identity_purpose='pdc_email_ai_transaction_successor'
             AND i.active AND i.revoked_at IS NULL)
         AND EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers w
           WHERE w.user_id=auth.uid() AND w.active AND w.revoked_at IS NULL) THEN
        RETURN public.reconcile_navision_operational_record_pre_700(p_backend_record_id,p_actor_id,p_actor_email);
      END IF;
      RETURN public.reconcile_navision_delivery_734(p_backend_record_id,p_actor_id,p_actor_email);
    END IF;
    IF b.canonical_vehicle_id IS NOT NULL THEN
      SELECT * INTO v FROM public.vehicles WHERE id=b.canonical_vehicle_id;
      IF FOUND AND (v.lifecycle_state='completed' OR upper(btrim(coalesce(v.current_location,'')))='COMPLETED') THEN RETURN public.navision_backend_response(false,'protected_completed_lifecycle'); END IF;
      IF FOUND AND (upper(btrim(coalesce(v.current_location,'')))='COLLECTED' OR v.rft_collected_at IS NOT NULL) THEN RETURN public.navision_backend_response(false,'protected_collected_lifecycle'); END IF;
    END IF;
  END IF;
  RETURN public.reconcile_navision_operational_record_pre_734(p_backend_record_id,p_actor_id,p_actor_email);
END
$function$;

REVOKE ALL ON FUNCTION public.reconcile_navision_operational_record(uuid,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
 '20260907104000','pilbara_service_pre_delivery_link_gate',ARRAY[
  'preserve exact delivered-at-dealer reconciliation for existing linked records and every non-scoped path',
  'bypass all delivery wrappers only for the scoped approved-email activation while it establishes an unlinked canonical vehicle'
 ]);
NOTIFY pgrst,'reload schema';
COMMIT;
