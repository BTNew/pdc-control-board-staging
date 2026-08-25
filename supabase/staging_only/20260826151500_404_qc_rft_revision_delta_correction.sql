-- STAGING ONLY 404: rely on the existing statement-level vehicle revision
-- trigger for each of the two QC/RFT updates; remove the redundant manual bump.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='60s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-404-qc-rft-revision-delta',0));
DO $fix$
DECLARE v_head text; v_definition text; v_corrected text;
DECLARE v_manual text:='  UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;'||chr(10);
BEGIN
  SELECT max(version) INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$';
  IF current_user<>'postgres' OR session_user<>'postgres'
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR v_head IS DISTINCT FROM '20260826150000'
    OR to_regprocedure('public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid)') IS NULL
    OR (SELECT count(*) FROM public.vehicle_notifications)<>1 THEN
    RAISE EXCEPTION 'PDC_404_STAGING_HEAD_OR_CONTAINMENT_MISMATCH' USING errcode='55000';
  END IF;
  SELECT pg_get_functiondef('public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid)'::regprocedure) INTO v_definition;
  IF position(v_manual in v_definition)=0 OR position('v_revision_after-v_revision_before<>1' in replace(v_definition,' ',''))=0 THEN
    RAISE EXCEPTION 'PDC_404_REVISION_PATCH_ANCHOR_MISSING' USING errcode='55000';
  END IF;
  v_corrected:=replace(v_definition,v_manual,'');
  v_corrected:=replace(v_corrected,'v_revision_after-v_revision_before<>1','v_revision_after-v_revision_before<>2');
  v_corrected:=replace(v_corrected,'v_revision_after - v_revision_before <> 1','v_revision_after - v_revision_before <> 2');
  EXECUTE v_corrected;
END $fix$;
REVOKE ALL ON FUNCTION public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid) TO authenticated;
DO $post$
DECLARE d text:=replace(pg_get_functiondef('public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid)'::regprocedure),' ','');
BEGIN
  IF position('UPDATEpublic.pdc_email_vehicle_revisionSETrevision=revision+1' in d)>0
    OR position('v_revision_after-v_revision_before<>2' in d)=0
    OR position('finalize_pdc_qc_to_rft_399_qc_signoff' in d)=0
    OR has_function_privilege('public','public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid)','EXECUTE')
    OR has_function_privilege('anon','public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid)','EXECUTE')
    OR has_function_privilege('service_role','public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid)','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid)','EXECUTE')
    OR (SELECT count(*) FROM public.vehicle_notifications)<>1 THEN
    RAISE EXCEPTION 'PDC_404_REVISION_POSTCONDITION' USING errcode='55000';
  END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826151500','404_qc_rft_revision_delta_correction',ARRAY[
  'Use the existing vehicle revision trigger once per QC and RFT update and remove the redundant manual revision increment',
  'Require the atomic finalization revision delta to equal two'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
