-- STAGING ONLY: correct owner-document Navision identity boundary.
-- Navision is authoritative for unique Stock identity; the exact Job Card is
-- authoritative evidence from Craig's supplied PDF because Navision has no
-- Job Card field for this planned-for-production vehicle.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-owner-document-navision-identity-correction',0));

DO $pre$
DECLARE v_head text;
BEGIN
  SELECT max(version) INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$';
  IF current_user<>'postgres' OR session_user<>'postgres'
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR NOT public.pdc_monitor_staging_guard()
    OR v_head IS DISTINCT FROM '20260826120000'
    OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260826120000' AND name='396_owner_supplied_document_jobcard_intake')<>1
    OR (SELECT count(*) FROM public.pdc_owner_supplied_document_receipts_396)<>0
    OR (SELECT count(*) FROM public.vehicles WHERE stock_number='13080553' AND deleted_at IS NULL)<>0
    OR (SELECT count(*) FROM public.navision_backend_records r
        WHERE r.source_system='microsoft_navision' AND r.dealer_code IN('14450','37047')
          AND r.is_current AND r.record_status='current'
          AND public.normalize_vehicle_stock_number(coalesce(r.normalized_data->>'batch',r.normalized_data->>'stock_number'))='13080553')<>1
    OR (SELECT count(*) FROM public.vehicle_notifications)<>1 THEN
    RAISE EXCEPTION 'PDC_OWNER_DOCUMENT_IDENTITY_CORRECTION_GATE' USING errcode='55000';
  END IF;
END $pre$;

DO $patch$
DECLARE v_definition text; v_patched text;
BEGIN
  SELECT pg_get_functiondef('public.process_pdc_owner_supplied_document_jobcard_396(text,text,text,jsonb,jsonb,jsonb)'::regprocedure)
    INTO v_definition;
  v_patched:=replace(v_definition,
    '     AND upper(btrim(coalesce(r.normalized_data->>''job_card_number'',r.normalized_data->>''jobcard_number'',r.normalized_data->>''job_card'',r.normalized_data->>''jobCardNumber'','''')))=v_job;',
    ';');
  v_patched:=replace(v_patched,
    '        AND upper(btrim(coalesce(r.normalized_data->>''job_card_number'',r.normalized_data->>''jobcard_number'',r.normalized_data->>''job_card'',r.normalized_data->>''jobCardNumber'','''')))=v_job)<>1 THEN',
    '      )<>1 THEN');
  v_patched:=replace(v_patched,
    '  SELECT * INTO v_vehicle FROM public.vehicles WHERE id=v_vehicle_id FOR UPDATE;',
    '  UPDATE public.vehicles SET job_card_number=v_job,updated_by=v_actor,updated_at=v_now WHERE id=v_vehicle_id AND nullif(btrim(coalesce(job_card_number,'''')),'''') IS NULL;'||chr(10)||
    '  SELECT * INTO v_vehicle FROM public.vehicles WHERE id=v_vehicle_id FOR UPDATE;');
  IF v_patched=v_definition
    OR position('job_card_number=v_job' in v_patched)=0
    OR position(')=v_job;' in v_patched)>0
    OR position(')=v_job)<>1 THEN' in v_patched)>0 THEN
    RAISE EXCEPTION 'PDC_OWNER_DOCUMENT_IDENTITY_CORRECTION_ANCHOR' USING errcode='55000';
  END IF;
  EXECUTE v_patched;
END $patch$;

DO $post$
DECLARE v_definition text;
BEGIN
  SELECT pg_get_functiondef('public.process_pdc_owner_supplied_document_jobcard_396(text,text,text,jsonb,jsonb,jsonb)'::regprocedure)
    INTO v_definition;
  IF position('job_card_number=v_job' in v_definition)=0
    OR position(')=v_job;' in v_definition)>0
    OR position(')=v_job)<>1 THEN' in v_definition)>0
    OR has_function_privilege('public','public.process_pdc_owner_supplied_document_jobcard_396(text,text,text,jsonb,jsonb,jsonb)','EXECUTE')
    OR has_function_privilege('anon','public.process_pdc_owner_supplied_document_jobcard_396(text,text,text,jsonb,jsonb,jsonb)','EXECUTE')
    OR has_function_privilege('service_role','public.process_pdc_owner_supplied_document_jobcard_396(text,text,text,jsonb,jsonb,jsonb)','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.process_pdc_owner_supplied_document_jobcard_396(text,text,text,jsonb,jsonb,jsonb)','EXECUTE')
    OR (SELECT count(*) FROM public.vehicle_notifications)<>1 THEN
    RAISE EXCEPTION 'PDC_OWNER_DOCUMENT_IDENTITY_CORRECTION_POSTCONDITION' USING errcode='55000';
  END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826123000','396_owner_document_navision_identity_correction',ARRAY[
  'Unique exact current Navision Stock remains the vehicle identity authority',
  'Exact Job Card J139125519 is accepted only from Craig task t_3ff7139c supplied PDF contract',
  'A blank canonical Job Card is populated before the existing exact postcondition; conflicting nonblank values still fail closed',
  'Provider-email authentication, RLS, receipt, audit, idempotency and notification protections remain unchanged'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
