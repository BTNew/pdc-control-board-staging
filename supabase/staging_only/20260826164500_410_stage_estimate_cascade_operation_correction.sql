-- STAGING ONLY 410: the canonical cascade contract uses `extend` for both
-- growth and shrinkage; duration/shift parameters define the exact result.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='60s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-410-stage-estimate-cascade-operation',0));
DO $fix$
DECLARE v_head text; d text; corrected text;
BEGIN
 SELECT max(version) INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$';
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  OR v_head IS DISTINCT FROM '20260826163000'
  OR to_regprocedure('public.set_workshop_stage_estimated_minutes_407(uuid,integer,uuid,integer,text,integer,uuid)') IS NULL
  OR (SELECT count(*) FROM public.vehicle_notifications)<>1 THEN RAISE EXCEPTION 'PDC_410_STAGING_HEAD_OR_CONTAINMENT_MISMATCH' USING errcode='55000'; END IF;
 SELECT pg_get_functiondef('public.set_workshop_stage_estimated_minutes_407(uuid,integer,uuid,integer,text,integer,uuid)'::regprocedure) INTO d;
 corrected:=replace(d,'CASE WHEN p_total_minutes>v_booking.default_duration_minutes THEN ''extend'' ELSE ''resize'' END,','''extend'',');
 corrected:=replace(corrected,'CASE WHEN p_total_minutes > v_booking.default_duration_minutes THEN ''extend'' ELSE ''resize'' END,','''extend'',');
 IF corrected=d OR position('ELSE ''resize''' in corrected)>0 THEN RAISE EXCEPTION 'PDC_410_PATCH_ANCHOR_MISSING' USING errcode='55000'; END IF;
 EXECUTE corrected;
END $fix$;
REVOKE ALL ON FUNCTION public.set_workshop_stage_estimated_minutes_407(uuid,integer,uuid,integer,text,integer,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.set_workshop_stage_estimated_minutes_407(uuid,integer,uuid,integer,text,integer,uuid) TO authenticated;
DO $post$
DECLARE d text:=pg_get_functiondef('public.set_workshop_stage_estimated_minutes_407(uuid,integer,uuid,integer,text,integer,uuid)'::regprocedure);
BEGIN
 IF position('ELSE ''resize''' in d)>0 OR position('v_cascade:=public.cascade_workshop_schedule(' in replace(d,' ',''))=0
  OR has_function_privilege('public','public.set_workshop_stage_estimated_minutes_407(uuid,integer,uuid,integer,text,integer,uuid)','EXECUTE')
  OR has_function_privilege('anon','public.set_workshop_stage_estimated_minutes_407(uuid,integer,uuid,integer,text,integer,uuid)','EXECUTE')
  OR has_function_privilege('service_role','public.set_workshop_stage_estimated_minutes_407(uuid,integer,uuid,integer,text,integer,uuid)','EXECUTE')
  OR NOT has_function_privilege('authenticated','public.set_workshop_stage_estimated_minutes_407(uuid,integer,uuid,integer,text,integer,uuid)','EXECUTE')
  OR (SELECT count(*) FROM public.vehicle_notifications)<>1 THEN RAISE EXCEPTION 'PDC_410_POSTCONDITION' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826164500','410_stage_estimate_cascade_operation_correction',ARRAY['Use canonical cascade extend operation for both increased and reduced exact stage durations','No operational row mutation in this migration']);
NOTIFY pgrst,'reload schema';
COMMIT;
