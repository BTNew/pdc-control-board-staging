-- STAGING ONLY 403: use the existing audit_action enum value `update` for the
-- QC sign-off phase audit emitted by migration 399.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='60s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-403-qc-signoff-audit-action',0));
DO $fix$
DECLARE v_head text; v_definition text; v_corrected text;
BEGIN
  SELECT max(version) INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$';
  IF current_user<>'postgres' OR session_user<>'postgres'
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR v_head IS DISTINCT FROM '20260826144500'
    OR to_regprocedure('public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid)') IS NULL
    OR (SELECT count(*) FROM public.vehicle_notifications)<>1 THEN
    RAISE EXCEPTION 'PDC_403_STAGING_HEAD_OR_CONTAINMENT_MISMATCH' USING errcode='55000';
  END IF;
  SELECT pg_get_functiondef('public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid)'::regprocedure) INTO v_definition;
  v_corrected:=replace(v_definition,'public.audit_pdc_event(''qc'',''vehicles''','public.audit_pdc_event(''update'',''vehicles''');
  IF v_corrected=v_definition OR position('public.audit_pdc_event(''qc'',''vehicles''' in v_corrected)>0 THEN
    RAISE EXCEPTION 'PDC_403_AUDIT_ACTION_PATCH_ANCHOR_MISSING' USING errcode='55000';
  END IF;
  EXECUTE v_corrected;
END $fix$;
REVOKE ALL ON FUNCTION public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid) TO authenticated;
DO $post$
DECLARE d text:=pg_get_functiondef('public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid)'::regprocedure);
BEGIN
  IF position('public.audit_pdc_event(''update'',''vehicles''' in d)=0
    OR position('finalize_pdc_qc_to_rft_399_qc_signoff' in d)=0
    OR has_function_privilege('public','public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid)','EXECUTE')
    OR has_function_privilege('anon','public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid)','EXECUTE')
    OR has_function_privilege('service_role','public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid)','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid)','EXECUTE')
    OR (SELECT count(*) FROM public.vehicle_notifications)<>1 THEN
    RAISE EXCEPTION 'PDC_403_AUDIT_ACTION_POSTCONDITION' USING errcode='55000';
  END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826150000','403_qc_signoff_audit_action_enum_correction',ARRAY[
  'Record the QC sign-off phase using the existing audit_action update enum while retaining explicit metadata action finalize_pdc_qc_to_rft_399_qc_signoff',
  'No operational row mutation in this migration'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
