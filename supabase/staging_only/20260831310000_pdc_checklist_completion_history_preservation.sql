-- STAGING ONLY: checklist completion history successor after the independent
-- Email AI head 3000. This does not alter any Email Monitor function or state.
-- A preserved Workshop booking must not be labelled as purged in history.
BEGIN;
SET LOCAL lock_timeout='30s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-checklist-completion-history-20260831',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260831300000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260831300000' AND name='pdc_email_ai_transaction_successor')<>1
     OR to_regprocedure('public.complete_pdc_vehicle_department_772(uuid,text,integer,uuid,integer,text,text,text)') IS NULL
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260831310000')
  THEN RAISE EXCEPTION 'PDC_CHECKLIST_3100_EXACT_STAGING_3000_PREDECESSOR_REQUIRED' USING errcode='55000'; END IF;
END $guard$;

DO $repair$
DECLARE
  definition text;
  patched text;
BEGIN
  SELECT pg_get_functiondef('public.complete_pdc_vehicle_department_772(uuid,text,integer,uuid,integer,text,text,text)'::regprocedure) INTO definition;
  patched:=replace(definition,
    'jsonb_build_object(''contract'',''department-complete-772'',''work_key'',key,''reason'',btrim(p_reason),''preserve_actual_elapsed_work'',true),actor,email,v.id,b.id);',
    'jsonb_build_object(''contract'',''department-complete-772'',''work_key'',key,''reason'',btrim(p_reason),''booking_preserved'',true,''preserve_actual_elapsed_work'',true),actor,email,v.id,NULL);');
  IF definition IS NULL OR patched=definition
     OR position('booking_preserved' IN patched)=0
     OR position('actor,email,v.id,NULL)' IN patched)=0
  THEN RAISE EXCEPTION 'PDC_CHECKLIST_3100_PRESERVED_BOOKING_HISTORY_REPAIR_FAILED' USING errcode='55000'; END IF;
  EXECUTE patched;
END $repair$;

DO $post$
DECLARE
  definition text;
  owner_name text;
  acl text;
  security_definer boolean;
BEGIN
  SELECT pg_get_functiondef('public.complete_pdc_vehicle_department_772(uuid,text,integer,uuid,integer,text,text,text)'::regprocedure),
         p.proowner::regrole::text,p.proacl::text,p.prosecdef
    INTO definition,owner_name,acl,security_definer
    FROM pg_proc p
    WHERE p.oid='public.complete_pdc_vehicle_department_772(uuid,text,integer,uuid,integer,text,text,text)'::regprocedure;
  IF position('booking_preserved' IN coalesce(definition,''))=0
     OR position('actor,email,v.id,NULL)' IN coalesce(definition,''))=0
     OR position('pg_advisory_xact_lock' IN coalesce(definition,''))=0
     OR position('pdc_vehicle_department_completion_receipts_772' IN coalesce(definition,''))=0
     OR owner_name<>'postgres' OR NOT security_definer
     OR acl LIKE '%public%' OR acl LIKE '%anon%' OR acl LIKE '%service_role%'
     OR NOT has_function_privilege('authenticated','public.complete_pdc_vehicle_department_772(uuid,text,integer,uuid,integer,text,text,text)','execute')
  THEN RAISE EXCEPTION 'PDC_CHECKLIST_3100_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
  '20260831310000','pdc_checklist_completion_history_preservation',ARRAY[
    'Preserved Workshop booking completion history uses purged_booking_id NULL and booking_preserved=true; it cannot imply that a retained planner booking was purged',
    'Exact completion function identity remains PostgreSQL-owned SECURITY DEFINER with authenticated-only execute and no public/anon/service_role execute',
    'Existing advisory lock, immutable idempotency receipt, expected vehicle/booking versions, audit, Realtime revision and atomic rollback behavior remain in force',
    'Append-only successor after independent staging head 20260831300000/pdc_email_ai_transaction_successor; Email Monitor functions/state and Production remain untouched'
  ]);
NOTIFY pgrst,'reload schema';
COMMIT;
