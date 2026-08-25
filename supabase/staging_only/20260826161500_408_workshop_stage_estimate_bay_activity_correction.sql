-- STAGING ONLY 408: correct canonical bay activity column in migration 407.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='60s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-408-stage-estimate-bay-activity',0));
DO $fix$
DECLARE v_head text; d text; corrected text;
BEGIN
  SELECT max(version) INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$';
  IF current_user<>'postgres' OR session_user<>'postgres'
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR v_head IS DISTINCT FROM '20260826160000'
    OR to_regprocedure('public.set_workshop_stage_estimated_minutes_407(uuid,integer,uuid,integer,text,integer,uuid)') IS NULL
    OR (SELECT count(*) FROM public.vehicle_notifications)<>1 THEN RAISE EXCEPTION 'PDC_408_STAGING_HEAD_OR_CONTAINMENT_MISMATCH' USING errcode='55000'; END IF;
  SELECT pg_get_functiondef('public.set_workshop_stage_estimated_minutes_407(uuid,integer,uuid,integer,text,integer,uuid)'::regprocedure) INTO d;
  corrected:=replace(d,'WHERE id=v_booking.bay_id AND active FOR SHARE','WHERE id=v_booking.bay_id AND is_active FOR SHARE');
  IF corrected=d OR position('WHERE id=v_booking.bay_id AND active FOR SHARE' in corrected)>0 THEN RAISE EXCEPTION 'PDC_408_PATCH_ANCHOR_MISSING' USING errcode='55000'; END IF;
  EXECUTE corrected;
END $fix$;
REVOKE ALL ON FUNCTION public.set_workshop_stage_estimated_minutes_407(uuid,integer,uuid,integer,text,integer,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.set_workshop_stage_estimated_minutes_407(uuid,integer,uuid,integer,text,integer,uuid) TO authenticated;
DO $post$
DECLARE d text:=pg_get_functiondef('public.set_workshop_stage_estimated_minutes_407(uuid,integer,uuid,integer,text,integer,uuid)'::regprocedure);
BEGIN
 IF position('WHERE id=v_booking.bay_id AND is_active FOR SHARE' in d)=0
   OR has_function_privilege('public','public.set_workshop_stage_estimated_minutes_407(uuid,integer,uuid,integer,text,integer,uuid)','EXECUTE')
   OR has_function_privilege('anon','public.set_workshop_stage_estimated_minutes_407(uuid,integer,uuid,integer,text,integer,uuid)','EXECUTE')
   OR has_function_privilege('service_role','public.set_workshop_stage_estimated_minutes_407(uuid,integer,uuid,integer,text,integer,uuid)','EXECUTE')
   OR NOT has_function_privilege('authenticated','public.set_workshop_stage_estimated_minutes_407(uuid,integer,uuid,integer,text,integer,uuid)','EXECUTE')
   OR (SELECT count(*) FROM public.vehicle_notifications)<>1 THEN RAISE EXCEPTION 'PDC_408_POSTCONDITION' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826161500','408_workshop_stage_estimate_bay_activity_correction',ARRAY['Use workshop_bays.is_active in whole-minute stage estimate booking validation','No operational row mutation in this migration']);
NOTIFY pgrst,'reload schema';
COMMIT;
