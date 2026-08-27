-- STAGING ONLY 703: route normalized Delivered - At Dealer values to the
-- final delivery successor. The 700 wrapper's first repair used a PostgreSQL
-- regexp_replace without the global flag, so a valid exact literal containing
-- multiple separators fell through to the legacy 169/481 reconciler.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-703-delivery-wrapper-normalization-repair',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $pre$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260827103000'
     OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260827103000' AND name='702_final_collected_workshop_status_repair')
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260827103000')
     OR to_regprocedure('public.reconcile_navision_operational_record(uuid,uuid,text)') IS NULL
     OR to_regprocedure('public.reconcile_navision_delivery_700(uuid,uuid,text)') IS NULL
  THEN RAISE EXCEPTION 'PDC_703_EXACT_702_PRESTATE_REQUIRED' USING errcode='55000'; END IF;
END $pre$;

CREATE OR REPLACE FUNCTION public.reconcile_navision_operational_record(p_backend_record_id uuid,p_actor_id uuid DEFAULT NULL,p_actor_email text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,extensions AS $wrapper$
DECLARE b public.navision_backend_records%rowtype; raw_status text; normalized text;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() THEN RETURN public.navision_backend_response(false,'wrong_environment'); END IF;
  SELECT * INTO b FROM public.navision_backend_records WHERE id=p_backend_record_id;
  IF FOUND THEN
    raw_status:=coalesce(b.normalized_data->>'toyotaStatus',b.normalized_data->>'navisionSubLocationDescription',b.normalized_data->>'vehicleStatus',b.normalized_data->>'navisionLocationStatus','');
    normalized:=lower(regexp_replace(btrim(raw_status),'[^a-z0-9]+','','g'));
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
 IF position('regexp_replace(btrim(raw_status),''[^a-z0-9]+'','''',''g'')' in d)=0 OR NOT has_function_privilege('authenticated','public.reconcile_navision_operational_record(uuid,uuid,text)','EXECUTE') OR has_function_privilege('anon','public.reconcile_navision_operational_record(uuid,uuid,text)','EXECUTE') THEN RAISE EXCEPTION 'PDC_703_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260827104000','703_delivery_wrapper_global_normalization_repair',ARRAY['Append-only repair adds global normalization when routing Toyota/Navision status strings to the exact Delivered - At Dealer successor','Near misses still fail closed in 700 while the exact literal routes to the open booked/collected interval and replay returns the original immutable receipt','Applied 169/399/412/428/429/481/700/701/702 history and Production remain untouched']);
NOTIFY pgrst,'reload schema';
COMMIT;
