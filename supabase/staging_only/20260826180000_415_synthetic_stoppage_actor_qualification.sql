-- STAGING ONLY 415: qualify the synthetic registry actor email.
BEGIN;
SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-415-synthetic-stoppage-actor',0));
DO $repair$
DECLARE d text; h text;
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR NOT public.pdc_monitor_staging_guard()
   OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260826175000' AND name='414_collected_workshop_status')
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260826175000') THEN
  RAISE EXCEPTION 'PDC_415_STAGING_HEAD_MISMATCH' USING errcode='55000'; END IF;
 SELECT pg_get_functiondef(p.oid),encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex') INTO d,h
 FROM pg_proc p WHERE p.oid='public.pdc_hermes_test_create_stoppage_413(text,uuid,integer,uuid,integer,uuid,text)'::regprocedure;
 IF h<>'93fccb7b3abcb38dbd3502740341407b00f7a27c95e3cf42ce6aca1b40084a26'
   OR position('actor_email text:=' in d)=0 OR position('AND actor_email=actor_email FOR SHARE' in d)=0 THEN
  RAISE EXCEPTION 'PDC_415_EXACT_PREDECESSOR_MISMATCH' USING errcode='55000'; END IF;
 d:=replace(d,'actor_email text:=','v_actor_email text:=');
 d:=replace(d,'FROM public.pdc_overnight_synthetic_fleet_registry_363 WHERE run_id=p_run_id AND vehicle_id=p_vehicle_id AND actor_id=uid AND actor_email=actor_email FOR SHARE',
   'FROM public.pdc_overnight_synthetic_fleet_registry_363 registry WHERE registry.run_id=p_run_id AND registry.vehicle_id=p_vehicle_id AND registry.actor_id=uid AND registry.actor_email=v_actor_email FOR SHARE');
 d:=replace(d,'lower(x.email)=actor_email','lower(x.email)=v_actor_email');
 EXECUTE d;
END $repair$;
DO $post$
DECLARE d text;
BEGIN SELECT pg_get_functiondef('public.pdc_hermes_test_create_stoppage_413(text,uuid,integer,uuid,integer,uuid,text)'::regprocedure) INTO d;
 IF position('registry.actor_email=v_actor_email' in d)=0 OR position('actor_email=actor_email' in d)<>0 THEN RAISE EXCEPTION 'PDC_415_POSTCONDITION_FAILED' USING errcode='55000'; END IF; END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826180000','415_synthetic_stoppage_actor_qualification',ARRAY[
 'Exact-SHA repair qualifies the synthetic registry actor_email column against v_actor_email',
 'No operational RPC, Production target, broad grant or protected data changed'
]);
NOTIFY pgrst,'reload schema'; COMMIT;
