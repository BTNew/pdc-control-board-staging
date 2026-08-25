-- STAGING ONLY 414: preserve the non-null completed vehicle workshop status.
BEGIN;
SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-414-collected-workshop-status',0));
DO $repair$
DECLARE d text; h text;
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR NOT public.pdc_monitor_staging_guard()
   OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260826174000' AND name='413_rft_email_ambiguity_repair')
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260826174000') THEN
  RAISE EXCEPTION 'PDC_414_STAGING_HEAD_MISMATCH' USING errcode='55000'; END IF;
 SELECT pg_get_functiondef(p.oid),encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex') INTO d,h
 FROM pg_proc p WHERE p.oid='public.collect_rft_transport_412(uuid,integer,uuid)'::regprocedure;
 IF h<>'092db68389f66f12faa829e98719271e1ac33087ad7e5786fad506f4da7218b3' OR position('workshop_status=NULL' in d)=0 THEN
  RAISE EXCEPTION 'PDC_414_EXACT_PREDECESSOR_MISMATCH' USING errcode='55000'; END IF;
 d:=replace(d,'workshop_status=NULL','workshop_status=''queued'''); EXECUTE d;
END $repair$;
DO $post$
DECLARE d text;
BEGIN
 SELECT pg_get_functiondef('public.collect_rft_transport_412(uuid,integer,uuid)'::regprocedure) INTO d;
 IF position('workshop_status=''queued''' in d)=0 OR position('workshop_status=NULL' in d)<>0 THEN RAISE EXCEPTION 'PDC_414_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826175000','414_collected_workshop_status',ARRAY[
 'Exact-SHA repair keeps the required vehicles.workshop_status at queued while collection clears active booking and bay authority',
 'Staging sentinel, exact predecessor head and Production exclusion preserved'
]);
NOTIFY pgrst,'reload schema'; COMMIT;
