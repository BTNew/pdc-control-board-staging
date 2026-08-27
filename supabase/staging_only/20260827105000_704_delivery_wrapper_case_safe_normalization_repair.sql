-- STAGING ONLY 704: case-safe exact-status routing repair.
-- PostgreSQL regex character classes are case-sensitive; lower the input
-- before removing separators so Delivered - At Dealer reaches the 700 RPC.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-704-delivery-wrapper-case-repair',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $pre$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260827104000'
     OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260827104000' AND name='703_delivery_wrapper_global_normalization_repair')
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260827104000')
     OR to_regprocedure('public.reconcile_navision_operational_record(uuid,uuid,text)') IS NULL
     OR to_regprocedure('public.reconcile_navision_delivery_700(uuid,uuid,text)') IS NULL
  THEN RAISE EXCEPTION 'PDC_704_EXACT_703_PRESTATE_REQUIRED' USING errcode='55000'; END IF;
END $pre$;
CREATE OR REPLACE FUNCTION public.reconcile_navision_operational_record(p_backend_record_id uuid,p_actor_id uuid DEFAULT NULL,p_actor_email text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,extensions AS $wrapper$
DECLARE b public.navision_backend_records%rowtype; raw_status text; normalized text;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() THEN RETURN public.navision_backend_response(false,'wrong_environment'); END IF;
  SELECT * INTO b FROM public.navision_backend_records WHERE id=p_backend_record_id;
  IF FOUND THEN
    raw_status:=coalesce(b.normalized_data->>'toyotaStatus',b.normalized_data->>'navisionSubLocationDescription',b.normalized_data->>'vehicleStatus',b.normalized_data->>'navisionLocationStatus','');
    normalized:=regexp_replace(lower(btrim(raw_status)),'[^a-z0-9]+','','g');
    IF normalized='deliveredatdealer' THEN RETURN public.reconcile_navision_delivery_700(p_backend_record_id,p_actor_id,p_actor_email); END IF;
  END IF;
  RETURN public.reconcile_navision_operational_record_pre_700(p_backend_record_id,p_actor_id,p_actor_email);
END $wrapper$;
REVOKE ALL ON FUNCTION public.reconcile_navision_operational_record(uuid,uuid,text) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.reconcile_navision_operational_record(uuid,uuid,text) TO authenticated,service_role;
DO $post$
DECLARE d text;
BEGIN
 SELECT pg_get_functiondef('public.reconcile_navision_operational_record(uuid,uuid,text)'::regprocedure) INTO d;
 IF position('regexp_replace(lower(btrim(raw_status)),''[^a-z0-9]+'','''',''g'')' in d)=0 OR NOT has_function_privilege('authenticated','public.reconcile_navision_operational_record(uuid,uuid,text)','EXECUTE') OR has_function_privilege('anon','public.reconcile_navision_operational_record(uuid,uuid,text)','EXECUTE') THEN RAISE EXCEPTION 'PDC_704_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260827105000','704_delivery_wrapper_case_safe_normalization_repair',ARRAY['Case-safe global normalization routes exact Delivered - At Dealer to the final 700 delivery RPC while near misses remain fail-closed','Applied 703 and all earlier lifecycle history remains append-only; Production untouched']);
NOTIFY pgrst,'reload schema';
COMMIT;
