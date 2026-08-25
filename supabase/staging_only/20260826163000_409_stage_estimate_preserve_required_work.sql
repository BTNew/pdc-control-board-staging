-- STAGING ONLY 409: keep the already-approved required station work stable
-- while migration 407 changes only its manual duration delta.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='60s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-409-stage-estimate-required-work',0));
DO $guard$
DECLARE v_head text;
BEGIN
 SELECT max(version) INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$';
 IF current_user<>'postgres' OR session_user<>'postgres'
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR v_head IS DISTINCT FROM '20260826161500'
   OR to_regprocedure('public.set_workshop_stage_estimated_minutes_407(uuid,integer,uuid,integer,text,integer,uuid)') IS NULL
   OR to_regprocedure('public.pdc_reconcile_required_work_after_adjustment_322()') IS NULL
   OR (SELECT count(*) FROM public.vehicle_notifications)<>1 THEN RAISE EXCEPTION 'PDC_409_STAGING_HEAD_OR_CONTAINMENT_MISMATCH' USING errcode='55000'; END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.pdc_reconcile_required_work_after_adjustment_322()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $required$
BEGIN
  IF current_setting('pdc.defer_workshop_required_work_reconcile',true)='407' THEN RETURN NULL; END IF;
  IF tg_op IN('UPDATE','DELETE') THEN PERFORM public.pdc_auditor_recalculate_required_work_226(ARRAY[old.vehicle_id]); END IF;
  IF tg_op IN('INSERT','UPDATE') AND (tg_op='INSERT' OR new.vehicle_id IS DISTINCT FROM old.vehicle_id OR new.stage_code IS DISTINCT FROM old.stage_code OR new.active IS DISTINCT FROM old.active) THEN
    PERFORM public.pdc_auditor_recalculate_required_work_226(ARRAY[new.vehicle_id]);
  END IF;
  RETURN NULL;
END $required$;
REVOKE ALL ON FUNCTION public.pdc_reconcile_required_work_after_adjustment_322() FROM public,anon,authenticated,service_role;

DO $fix$
DECLARE d text; corrected text;
BEGIN
 SELECT pg_get_functiondef('public.set_workshop_stage_estimated_minutes_407(uuid,integer,uuid,integer,text,integer,uuid)'::regprocedure) INTO d;
 corrected:=replace(d,
   'PERFORM set_config(''pdc.defer_workshop_adjustment_reconcile'',''407'',true);',
   'PERFORM set_config(''pdc.defer_workshop_adjustment_reconcile'',''407'',true);'||chr(10)||'  PERFORM set_config(''pdc.defer_workshop_required_work_reconcile'',''407'',true);');
 corrected:=replace(corrected,
   'PERFORM set_config(''pdc.defer_workshop_adjustment_reconcile'','''',true);',
   'PERFORM set_config(''pdc.defer_workshop_adjustment_reconcile'','''',true);'||chr(10)||'  PERFORM set_config(''pdc.defer_workshop_required_work_reconcile'','''',true);');
 IF corrected=d OR position('pdc.defer_workshop_required_work_reconcile' in corrected)=0 THEN RAISE EXCEPTION 'PDC_409_PATCH_ANCHOR_MISSING' USING errcode='55000'; END IF;
 EXECUTE corrected;
END $fix$;
REVOKE ALL ON FUNCTION public.set_workshop_stage_estimated_minutes_407(uuid,integer,uuid,integer,text,integer,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.set_workshop_stage_estimated_minutes_407(uuid,integer,uuid,integer,text,integer,uuid) TO authenticated;

DO $post$
DECLARE d text:=pg_get_functiondef('public.set_workshop_stage_estimated_minutes_407(uuid,integer,uuid,integer,text,integer,uuid)'::regprocedure); t text:=pg_get_functiondef('public.pdc_reconcile_required_work_after_adjustment_322()'::regprocedure);
BEGIN
 IF position('pdc.defer_workshop_required_work_reconcile' in d)=0 OR position('pdc.defer_workshop_required_work_reconcile' in t)=0
   OR has_function_privilege('public','public.set_workshop_stage_estimated_minutes_407(uuid,integer,uuid,integer,text,integer,uuid)','EXECUTE')
   OR has_function_privilege('anon','public.set_workshop_stage_estimated_minutes_407(uuid,integer,uuid,integer,text,integer,uuid)','EXECUTE')
   OR has_function_privilege('service_role','public.set_workshop_stage_estimated_minutes_407(uuid,integer,uuid,integer,text,integer,uuid)','EXECUTE')
   OR NOT has_function_privilege('authenticated','public.set_workshop_stage_estimated_minutes_407(uuid,integer,uuid,integer,text,integer,uuid)','EXECUTE')
   OR (SELECT count(*) FROM public.vehicle_notifications)<>1 THEN RAISE EXCEPTION 'PDC_409_POSTCONDITION' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826163000','409_stage_estimate_preserve_required_work',ARRAY['Defer required-work recalculation only inside the exact atomic stage-duration transaction','Preserve the existing outstanding station requirement and all source operation evidence']);
NOTIFY pgrst,'reload schema';
COMMIT;
