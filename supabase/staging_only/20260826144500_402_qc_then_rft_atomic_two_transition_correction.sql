-- STAGING ONLY 402: preserve the existing QC-then-RFT lifecycle invariant as
-- two audited row transitions inside migration-399's single atomic transaction.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='60s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-402-qc-then-rft-atomic',0));

DO $fix$
DECLARE v_head text; v_definition text; v_corrected text;
DECLARE v_declaration text:='  v_before public.vehicles%rowtype; v_after public.vehicles%rowtype;';
DECLARE v_update text:='  UPDATE public.vehicles SET qc_completed_at=coalesce(qc_completed_at,clock_timestamp()),qc_completed_by=v_actor,lifecycle_state=''rft'',current_location=''RFT'',date_to_rft=coalesce(date_to_rft,(clock_timestamp() at time zone ''Australia/Perth'')::date),rft_transferred_at=coalesce(rft_transferred_at,clock_timestamp()),version=version+1,updated_by=v_actor,updated_at=clock_timestamp() WHERE id=p_vehicle_id RETURNING * INTO v_after;';
DECLARE v_audit text:='to_jsonb(v_before),to_jsonb(v_after),jsonb_build_object(''action'',''finalize_pdc_qc_to_rft_399''';
BEGIN
  SELECT max(version) INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$';
  IF current_user<>'postgres' OR session_user<>'postgres'
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR v_head IS DISTINCT FROM '20260826143000'
    OR to_regprocedure('public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid)') IS NULL
    OR (SELECT count(*) FROM public.vehicle_notifications)<>1 THEN
    RAISE EXCEPTION 'PDC_402_STAGING_HEAD_OR_CONTAINMENT_MISMATCH' USING errcode='55000';
  END IF;
  SELECT pg_get_functiondef('public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid)'::regprocedure) INTO v_definition;
  IF position(v_declaration in v_definition)=0 OR position(v_update in v_definition)=0 OR position(v_audit in v_definition)=0
    OR position('v_after.version<>v_before.version+1' in replace(v_definition,' ',''))=0 THEN
    RAISE EXCEPTION 'PDC_402_QC_RFT_PATCH_ANCHOR_MISSING' USING errcode='55000';
  END IF;
  v_corrected:=replace(v_definition,v_declaration,'  v_before public.vehicles%rowtype; v_signed public.vehicles%rowtype; v_after public.vehicles%rowtype;');
  v_corrected:=replace(v_corrected,v_update,
    '  -- Two audited transitions, one atomic transaction.'||chr(10)||
    '  UPDATE public.vehicles SET qc_completed_at=coalesce(qc_completed_at,clock_timestamp()),qc_completed_by=v_actor,version=version+1,updated_by=v_actor,updated_at=clock_timestamp() WHERE id=p_vehicle_id RETURNING * INTO v_signed;'||chr(10)||
    '  PERFORM public.audit_pdc_event(''qc'',''vehicles'',p_vehicle_id,p_vehicle_id,to_jsonb(v_before),to_jsonb(v_signed),jsonb_build_object(''action'',''finalize_pdc_qc_to_rft_399_qc_signoff'',''photo_receipt_id'',v_photo.photo_receipt_id,''notification_enqueued'',false));'||chr(10)||
    '  UPDATE public.vehicles SET lifecycle_state=''rft'',current_location=''RFT'',date_to_rft=coalesce(date_to_rft,(clock_timestamp() at time zone ''Australia/Perth'')::date),rft_transferred_at=coalesce(rft_transferred_at,clock_timestamp()),version=version+1,updated_by=v_actor,updated_at=clock_timestamp() WHERE id=p_vehicle_id RETURNING * INTO v_after;');
  v_corrected:=replace(v_corrected,v_audit,'to_jsonb(v_signed),to_jsonb(v_after),jsonb_build_object(''action'',''finalize_pdc_qc_to_rft_399''');
  v_corrected:=replace(v_corrected,'v_after.version<>v_before.version+1','v_after.version<>v_before.version+2');
  v_corrected:=replace(v_corrected,'v_after.version <> v_before.version + 1','v_after.version <> v_before.version + 2');
  EXECUTE v_corrected;
END $fix$;

REVOKE ALL ON FUNCTION public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid) TO authenticated;

DO $post$
DECLARE d text:=replace(pg_get_functiondef('public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid)'::regprocedure),' ','');
BEGIN
  IF position('v_signedpublic.vehicles%rowtype' in d)=0
    OR position('finalize_pdc_qc_to_rft_399_qc_signoff' in d)=0
    OR position('v_after.version<>v_before.version+2' in d)=0
    OR position('pdc.hermes_test_wrapper_vehicle_365' in d)=0
    OR has_function_privilege('public','public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid)','EXECUTE')
    OR has_function_privilege('anon','public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid)','EXECUTE')
    OR has_function_privilege('service_role','public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid)','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid)','EXECUTE')
    OR (SELECT count(*) FROM public.vehicle_notifications)<>1 THEN
    RAISE EXCEPTION 'PDC_402_QC_RFT_POSTCONDITION' USING errcode='55000';
  END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826144500','402_qc_then_rft_atomic_two_transition_correction',ARRAY[
  'Preserve the intentional QC sign-off then RFT transfer invariant as two audited updates inside one atomic RPC transaction',
  'Vehicle version advances twice; receipt, outbox, movement and replay remain one finalization contract'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
