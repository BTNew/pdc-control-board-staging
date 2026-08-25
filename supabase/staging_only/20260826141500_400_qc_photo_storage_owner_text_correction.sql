-- STAGING ONLY 400: correct storage.objects.owner_id text comparison in the
-- migration-399 QC photo evidence RPC. No operational rows are mutated.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='60s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-400-qc-photo-owner-type',0));

DO $fix$
DECLARE v_head text; v_definition text; v_corrected text;
BEGIN
  SELECT max(version) INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$';
  IF current_user<>'postgres' OR session_user<>'postgres'
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR v_head IS DISTINCT FROM '20260826140000'
    OR to_regprocedure('public.record_pdc_qc_photo_evidence_399(uuid,integer,text,text,text,integer,integer,integer,integer,text,text,uuid)') IS NULL
    OR (SELECT count(*) FROM information_schema.columns WHERE table_schema='storage' AND table_name='objects' AND column_name='owner_id' AND data_type='text')<>1
    OR (SELECT count(*) FROM public.vehicle_notifications)<>1 THEN
    RAISE EXCEPTION 'PDC_400_STAGING_HEAD_OR_CONTAINMENT_MISMATCH' USING errcode='55000';
  END IF;

  SELECT pg_get_functiondef('public.record_pdc_qc_photo_evidence_399(uuid,integer,text,text,text,integer,integer,integer,integer,text,text,uuid)'::regprocedure)
    INTO v_definition;
  v_corrected:=replace(v_definition,'o.owner_id=v_actor','o.owner_id=v_actor::text');
  v_corrected:=replace(v_corrected,'o.owner_id = v_actor','o.owner_id = v_actor::text');
  IF v_corrected=v_definition OR position('owner_id=v_actor::text' in replace(v_corrected,' ',''))=0 THEN
    RAISE EXCEPTION 'PDC_400_OWNER_TYPE_PATCH_ANCHOR_MISSING' USING errcode='55000';
  END IF;
  EXECUTE v_corrected;
END $fix$;

REVOKE ALL ON FUNCTION public.record_pdc_qc_photo_evidence_399(uuid,integer,text,text,text,integer,integer,integer,integer,text,text,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.record_pdc_qc_photo_evidence_399(uuid,integer,text,text,text,integer,integer,integer,integer,text,text,uuid) TO authenticated;

DO $post$
BEGIN
  IF position('owner_id=v_actor::text' in replace(pg_get_functiondef('public.record_pdc_qc_photo_evidence_399(uuid,integer,text,text,text,integer,integer,integer,integer,text,text,uuid)'::regprocedure),' ',''))=0
    OR has_function_privilege('public','public.record_pdc_qc_photo_evidence_399(uuid,integer,text,text,text,integer,integer,integer,integer,text,text,uuid)','EXECUTE')
    OR has_function_privilege('anon','public.record_pdc_qc_photo_evidence_399(uuid,integer,text,text,text,integer,integer,integer,integer,text,text,uuid)','EXECUTE')
    OR has_function_privilege('service_role','public.record_pdc_qc_photo_evidence_399(uuid,integer,text,text,text,integer,integer,integer,integer,text,text,uuid)','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.record_pdc_qc_photo_evidence_399(uuid,integer,text,text,text,integer,integer,integer,integer,text,text,uuid)','EXECUTE')
    OR (SELECT count(*) FROM public.vehicle_notifications)<>1 THEN
    RAISE EXCEPTION 'PDC_400_OWNER_TYPE_POSTCONDITION' USING errcode='55000';
  END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826141500','400_qc_photo_storage_owner_text_correction',ARRAY[
  'Correct storage.objects.owner_id comparison from uuid to text without changing identity or ACL boundaries',
  'No vehicle, booking, receipt, outbox or notification row is mutated'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
