-- STAGING ONLY 425: qualify the hidden acceptance actor email variable.
BEGIN; SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-425-hidden-actor-email',0));
DO $repair$ DECLARE d text; h text; repaired text; BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR NOT public.pdc_monitor_staging_guard()
  OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260826195000' AND name='424_hidden_targeted_stoppage_acceptance')
  OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260826195000') THEN RAISE EXCEPTION 'PDC_425_STAGING_HEAD_MISMATCH' USING errcode='55000'; END IF;
 SELECT pg_get_functiondef('public.pdc_hermes_test_clear_booking_stoppage_424(text,uuid,integer,uuid,integer,text,uuid)'::regprocedure),encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_hermes_test_clear_booking_stoppage_424(text,uuid,integer,uuid,integer,text,uuid)'::regprocedure),'UTF8'),'sha256'),'hex') INTO d,h;
 IF h<>'86abe658b113bf2942fc47166857179e54135a448e190aff017a2878e2b32299' THEN RAISE EXCEPTION 'PDC_425_EXACT_FUNCTION_MISMATCH' USING errcode='55000'; END IF;
 repaired:=replace(d,'actor_email text:=','v_actor_email text:=');
 repaired:=replace(repaired,'r.actor_email=actor_email','r.actor_email=v_actor_email');
 repaired:=replace(repaired,'lower(x.email)=actor_email','lower(x.email)=v_actor_email');
 IF repaired=d OR position('r.actor_email=actor_email' in repaired)>0 OR position(' actor_email text:=' in repaired)>0 THEN RAISE EXCEPTION 'PDC_425_REPAIR_NOT_EXACT' USING errcode='55000'; END IF;
 EXECUTE repaired;
END $repair$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826200000','425_hidden_acceptance_actor_email_qualification',ARRAY[
 'Exact-SHA qualification of the registry-bound hidden acceptance actor email variable',
 'No business function, grant, vehicle data, notification or Production state changed'
]);
NOTIFY pgrst,'reload schema'; COMMIT;
