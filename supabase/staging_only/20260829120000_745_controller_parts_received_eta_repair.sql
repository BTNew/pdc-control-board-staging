-- STAGING ONLY 745: append-only repair for the one-time controller Parts
-- receipt wrapper. It preserves an authoritative Parts ETA when no active
-- stoppage is being cleared; migration 738 and controller authorization 742
-- are not rewritten. This satisfies the existing PDC_PARTS_ETA_REQUIRED
-- trigger without changing the intended received/stoppage semantics.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-installation',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR NOT EXISTS(SELECT 1 FROM public.pdc_staging_environment_sentinel
                   WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT max(version) FROM supabase_migrations.schema_migrations
         WHERE version~'^[0-9]{14}$')<>'20260829110000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations
         WHERE version='20260829110000'
           AND name='744_reactivate_exact_email_monitor_mailbox')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations
         WHERE version='20260829090000'
           AND name='742_controller_parts_received_correction')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations
               WHERE version='20260829120000')
     OR to_regprocedure('public.apply_pdc_staging_parts_received_correction_742(uuid,integer,text,uuid)') IS NULL
     OR to_regclass('public.pdc_staging_parts_received_correction_authorizations_742') IS NULL
     OR to_regclass('public.pdc_staging_parts_received_correction_receipts_742') IS NULL
  THEN RAISE EXCEPTION 'PDC_744_EXACT_STAGING_DEPENDENCY_MISMATCH' USING errcode='55000';
  END IF;
END $guard$;

DO $repair$
DECLARE
  v_definition text;
  v_patched text;
BEGIN
  SELECT pg_get_functiondef(
    'public.apply_pdc_staging_parts_received_correction_742(uuid,integer,text,uuid)'::regprocedure)
    INTO v_definition;
  v_patched:=replace(v_definition,
    'VALUES(p_vehicle_id,true,true,true,false,NULL,NULL,v_actor,clock_timestamp())',
    'VALUES(p_vehicle_id,true,true,true,false,case when coalesce(v_parts_before.parts_stoppage,false) then null else v_parts_before.parts_stoppage_reason end,case when coalesce(v_parts_before.parts_stoppage,false) then null else v_parts_before.worst_eta end,v_actor,clock_timestamp())');
  IF v_definition IS NULL OR v_patched=v_definition
     OR position('case when coalesce(v_parts_before.parts_stoppage,false) then null else v_parts_before.worst_eta end' IN v_patched)=0
  THEN RAISE EXCEPTION 'PDC_744_CONTROLLER_ETA_REPAIR_FAILED' USING errcode='55000';
  END IF;
  EXECUTE v_patched;
END $repair$;

DO $post$
DECLARE
  v_definition text;
BEGIN
  SELECT pg_get_functiondef(
    'public.apply_pdc_staging_parts_received_correction_742(uuid,integer,text,uuid)'::regprocedure)
    INTO v_definition;
  IF position('case when coalesce(v_parts_before.parts_stoppage,false) then null else v_parts_before.worst_eta end' IN v_definition)=0
  THEN RAISE EXCEPTION 'PDC_744_CONTROLLER_ETA_REPAIR_POSTCONDITION_FAILED' USING errcode='55000';
  END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
  '20260829120000','745_controller_parts_received_eta_repair',ARRAY[
    'Append-only repair of controller Parts wrapper to preserve required ordered Parts ETA when no active stoppage exists',
    'Retain exact one-time Craig authorization, immutable receipt consumption, audit, version and no-cross-dealer controller boundary',
    'No vehicle, Parts, work-item, receipt, audit, revision, Auditor scope or Production data is changed by installation'
  ]);
NOTIFY pgrst,'reload schema';
COMMIT;
