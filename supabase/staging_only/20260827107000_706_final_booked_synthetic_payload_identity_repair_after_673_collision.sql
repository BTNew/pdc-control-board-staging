-- STAGING ONLY 706: final booked payload synthetic identity repair.
-- The preserved 705 draft collided with an already-applied 673 ledger row at
-- version 20260827106000. This successor preserves that unrelated row and
-- repairs only the effective 700 booking function.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-706-synthetic-payload-identity-repair',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $pre$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260827106000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827106000' AND name='673_authenticated_monitor_execution_attachment_successor')<>1
     OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260827105000' AND name='704_delivery_wrapper_case_safe_normalization_repair')
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260827106000')
     OR to_regprocedure('public.book_rft_transport_700(uuid,integer,uuid)') IS NULL
  THEN RAISE EXCEPTION 'PDC_706_EXACT_LIVE_HEAD_PRESTATE_REQUIRED' USING errcode='55000'; END IF;
END $pre$;
DO $repair$
DECLARE d text; old text:='v.source_batch_id'; new text:='v.stock_number';
BEGIN
 SELECT pg_get_functiondef('public.book_rft_transport_700(uuid,integer,uuid)'::regprocedure) INTO d;
 IF position(old in d)=0 OR length(d)-length(replace(d,old,''))<>length(old) THEN RAISE EXCEPTION 'PDC_706_BOOK_PAYLOAD_ANCHOR_MISSING_OR_AMBIGUOUS' USING errcode='55000'; END IF;
 EXECUTE replace(d,old,new);
END $repair$;
DO $post$
DECLARE d text;
BEGIN
 SELECT pg_get_functiondef('public.book_rft_transport_700(uuid,integer,uuid)'::regprocedure) INTO d;
 IF position('v.stock_number' in d)=0
    OR position('v.source_batch_id' in d)>0
    OR NOT has_function_privilege('authenticated','public.book_rft_transport_700(uuid,integer,uuid)','EXECUTE')
    OR has_function_privilege('anon','public.book_rft_transport_700(uuid,integer,uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'PDC_706_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260827107000','706_final_booked_synthetic_payload_identity_repair_after_673_collision',ARRAY[
 'Consolidates the unapplied 705 draft into the next available append-only staging version because 20260827106000 is already occupied by applied 673',
 'Future final RFT Booked payloads derive synthetic_only from the bounded HERMES-TEST stock identity while dealer scope remains the canonical Navision dealer code',
 'Existing 700/412 immutable receipts, intercepted payloads, RLS, grants and Production remain unchanged'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
