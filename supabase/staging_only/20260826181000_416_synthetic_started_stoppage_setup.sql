-- STAGING ONLY 416: make the synthetic stoppage fixture follow valid started -> stoppage lifecycle.
BEGIN;
SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-416-synthetic-start-stoppage',0));
DO $repair$
DECLARE d text; h text; old_block text; new_block text;
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR NOT public.pdc_monitor_staging_guard()
   OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260826180000' AND name='415_synthetic_stoppage_actor_qualification')
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260826180000') THEN
  RAISE EXCEPTION 'PDC_416_STAGING_HEAD_MISMATCH' USING errcode='55000'; END IF;
 SELECT pg_get_functiondef(p.oid),encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex') INTO d,h
 FROM pg_proc p WHERE p.oid='public.pdc_hermes_test_create_stoppage_413(text,uuid,integer,uuid,integer,uuid,text)'::regprocedure;
 old_block:='result:=public.return_work_to_queue(b.id,b.version,btrim(p_reason),jsonb_build_object(''source'',''HERMES-TEST-413'',''idempotency_key'',p_idempotency_key));
 IF NOT coalesce((result->>''ok'')::boolean,false) OR result#>>''{booking,status}''<>''stoppage'' OR nullif(result#>>''{booking,bay_id}'','''') IS NOT NULL THEN
  RAISE EXCEPTION ''PDC_413_SYNTHETIC_STOPPAGE_POSTCONDITION'' USING errcode=''55000''; END IF;';
 new_block:='IF b.status::text<>''started'' THEN
  result:=public.start_workshop_work(b.id,b.version,b.scheduled_start_at,jsonb_build_object(''source'',''HERMES-TEST-416'',''idempotency_key'',p_idempotency_key));
  IF NOT coalesce((result->>''ok'')::boolean,false) THEN RAISE EXCEPTION ''PDC_416_SYNTHETIC_START_FAILED:%'',coalesce(result->>''error'',''unknown'') USING errcode=''55000''; END IF;
  SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id FOR UPDATE;
 END IF;
 result:=public.stop_workshop_work(b.id,b.version,btrim(p_reason),jsonb_build_object(''source'',''HERMES-TEST-416'',''idempotency_key'',p_idempotency_key));
 IF NOT coalesce((result->>''ok'')::boolean,false) OR result#>>''{booking,status}''<>''stoppage'' THEN
  RAISE EXCEPTION ''PDC_416_SYNTHETIC_STOPPAGE_POSTCONDITION'' USING errcode=''55000''; END IF;';
 IF h<>'abf53712398581cca9b6fee3be6a0bf632cb9ebaecd876e4f514bf447682909e' OR position(old_block in d)=0 THEN
  RAISE EXCEPTION 'PDC_416_EXACT_PREDECESSOR_MISMATCH' USING errcode='55000'; END IF;
 d:=replace(d,old_block,new_block); EXECUTE d;
END $repair$;
DO $post$
DECLARE d text;
BEGIN SELECT pg_get_functiondef('public.pdc_hermes_test_create_stoppage_413(text,uuid,integer,uuid,integer,uuid,text)'::regprocedure) INTO d;
 IF position('public.start_workshop_work' in d)=0 OR position('public.stop_workshop_work' in d)=0 OR position('public.return_work_to_queue' in d)<>0 THEN RAISE EXCEPTION 'PDC_416_POSTCONDITION_FAILED' USING errcode='55000'; END IF; END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826181000','416_synthetic_started_stoppage_setup',ARRAY[
 'Exact-SHA synthetic setup now follows started then stoppage lifecycle before clear-stoppage acceptance',
 'Fixture remains exact registered HERMES-TEST only; operational RPC and protected data are unchanged'
]);
NOTIFY pgrst,'reload schema'; COMMIT;
