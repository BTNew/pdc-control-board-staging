-- STAGING ONLY 417: deterministic synthetic started-state setup without calendar dependence.
BEGIN; SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-417-synthetic-start-snapshot',0));
DO $repair$
DECLARE d text; h text; old_block text; new_block text;
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR NOT public.pdc_monitor_staging_guard()
   OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260826181000' AND name='416_synthetic_started_stoppage_setup')
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260826181000') THEN RAISE EXCEPTION 'PDC_417_STAGING_HEAD_MISMATCH' USING errcode='55000'; END IF;
 SELECT pg_get_functiondef(p.oid),encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex') INTO d,h FROM pg_proc p WHERE p.oid='public.pdc_hermes_test_create_stoppage_413(text,uuid,integer,uuid,integer,uuid,text)'::regprocedure;
 old_block:='IF b.status::text<>''started'' THEN
  result:=public.start_workshop_work(b.id,b.version,b.scheduled_start_at,jsonb_build_object(''source'',''HERMES-TEST-416'',''idempotency_key'',p_idempotency_key));
  IF NOT coalesce((result->>''ok'')::boolean,false) THEN RAISE EXCEPTION ''PDC_416_SYNTHETIC_START_FAILED:%'',coalesce(result->>''error'',''unknown'') USING errcode=''55000''; END IF;
  SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id FOR UPDATE;
 END IF;';
 new_block:='IF b.status::text<>''started'' THEN
  before_j:=public.workshop_booking_snapshot(b.id);
  UPDATE public.workshop_bookings SET status=''started''::public.workshop_booking_status,actual_start_at=coalesce(actual_start_at,scheduled_start_at),updated_by=uid,updated_at=clock_timestamp(),version=version+1 WHERE id=b.id RETURNING * INTO b;
  after_j:=public.workshop_booking_snapshot(b.id);
  PERFORM public.workshop_write_history(b.id,''started'',before_j,after_j,jsonb_build_object(''source'',''HERMES-TEST-417'',''idempotency_key'',p_idempotency_key));
  PERFORM public.workshop_bump_revision();
 END IF;';
 IF h<>'51b47263e4d4daba60a83710526a5bcaeb8e14b2ed0fbff26de39a0371481a27' OR position(old_block in d)=0 OR position('r record; result jsonb;' in d)=0 THEN RAISE EXCEPTION 'PDC_417_EXACT_PREDECESSOR_MISMATCH' USING errcode='55000'; END IF;
 d:=replace(d,'r record; result jsonb;','r record; result jsonb; before_j jsonb; after_j jsonb;');
 d:=replace(d,old_block,new_block); EXECUTE d;
END $repair$;
DO $post$ DECLARE d text; BEGIN SELECT pg_get_functiondef('public.pdc_hermes_test_create_stoppage_413(text,uuid,integer,uuid,integer,uuid,text)'::regprocedure) INTO d;
 IF position('HERMES-TEST-417' in d)=0 OR position('public.start_workshop_work' in d)<>0 OR position('public.workshop_write_history' in d)=0 THEN RAISE EXCEPTION 'PDC_417_POSTCONDITION_FAILED' USING errcode='55000'; END IF; END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826182000','417_synthetic_started_snapshot_setup',ARRAY[
 'Exact-SHA HERMES-TEST setup records a deterministic started snapshot/history before invoking the canonical stoppage action',
 'Operational start rules and Production data are unchanged; helper remains registry-bound Administrator-only staging acceptance'
]);
NOTIFY pgrst,'reload schema'; COMMIT;
