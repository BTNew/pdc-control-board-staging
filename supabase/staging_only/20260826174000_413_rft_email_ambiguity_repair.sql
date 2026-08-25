-- STAGING ONLY 413: exact ambiguity repair plus synthetic stoppage acceptance facade.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-413-rft-email-ambiguity-repair',0));
DO $pre$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR NOT public.pdc_monitor_staging_guard()
   OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260826173000' AND name='412_stoppage_rft_transport_workflow')
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260826173000') THEN
  RAISE EXCEPTION 'PDC_413_STAGING_HEAD_MISMATCH' USING errcode='55000'; END IF;
END $pre$;

DO $repair$
DECLARE d text; h text; item record;
BEGIN
 FOR item IN SELECT * FROM (VALUES
  ('clear_vehicle_stoppage_412','uuid, integer, text, uuid','807c4ba404afdc527c6eb8b32d5f77870aaf1010c5f3c27c9ac45b9aef89cd2c'),
  ('book_rft_transport_412','uuid, integer, uuid','d2ebccfb8927d6a484d5048b003f35dfd7f3deb5657ae39bef65be448fbd729c'),
  ('collect_rft_transport_412','uuid, integer, uuid','1b4a4168fca2a1db527207e4786e50e0ae8679480e5c77064729b76dea348360')
 ) x(fn,args,expected_sha) LOOP
  SELECT pg_get_functiondef(p.oid),encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex') INTO d,h
  FROM pg_proc p WHERE p.oid=to_regprocedure('public.'||item.fn||'('||item.args||')');
  IF d IS NULL OR h<>item.expected_sha
    OR position('uid uuid:=auth.uid(); email text:=' in d)=0
    OR position('lower(r.email)=email' in d)=0
    OR position(',uid,email,p_idempotency_key' in d)=0 THEN
   RAISE EXCEPTION 'PDC_413_EXACT_FUNCTION_PREDECESSOR_MISMATCH:%',item.fn USING errcode='55000'; END IF;
  d:=replace(d,'uid uuid:=auth.uid(); email text:=','uid uuid:=auth.uid(); actor_email text:=');
  d:=replace(d,'lower(r.email)=email','lower(r.email)=actor_email');
  d:=replace(d,',uid,email,p_idempotency_key',',uid,actor_email,p_idempotency_key');
  EXECUTE d;
 END LOOP;
END $repair$;

CREATE FUNCTION public.pdc_hermes_test_create_stoppage_413(
 p_run_id text,p_vehicle_id uuid,p_expected_vehicle_version integer,p_booking_id uuid,p_expected_booking_version integer,p_idempotency_key uuid,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE uid uuid:=auth.uid(); actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); v public.vehicles%rowtype; b public.workshop_bookings%rowtype; r record; result jsonb;
BEGIN
 IF p_run_id<>'HERMES-TEST-RUN-20260824' OR p_idempotency_key IS NULL OR length(btrim(coalesce(p_reason,''))) NOT BETWEEN 3 AND 240 OR p_reason!~'^HERMES-TEST' THEN
  RAISE EXCEPTION 'PDC_413_SYNTHETIC_INPUT_INVALID' USING errcode='22023'; END IF;
 SELECT * INTO r FROM public.pdc_overnight_synthetic_fleet_registry_363 WHERE run_id=p_run_id AND vehicle_id=p_vehicle_id AND actor_id=uid AND actor_email=actor_email FOR SHARE;
 IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM public.pdc_user_roles x WHERE x.auth_user_id=uid AND lower(x.email)=actor_email AND x.active AND x.account_status='approved' AND x.role='administrator') THEN
  RAISE EXCEPTION 'PDC_413_SYNTHETIC_SCOPE_DENIED' USING errcode='42501'; END IF;
 SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
 SELECT * INTO b FROM public.workshop_bookings WHERE id=p_booking_id AND vehicle_id=p_vehicle_id FOR UPDATE;
 IF NOT FOUND OR v.version<>p_expected_vehicle_version OR b.version<>p_expected_booking_version OR b.status::text IN('completed','deleted','cancelled','started') THEN
  RETURN jsonb_build_object('ok',false,'code','synthetic_version_or_status_conflict'); END IF;
 PERFORM set_config('pdc.hermes_test_wrapper_vehicle_365',p_vehicle_id::text,true);
 result:=public.return_work_to_queue(b.id,b.version,btrim(p_reason),jsonb_build_object('source','HERMES-TEST-413','idempotency_key',p_idempotency_key));
 IF NOT coalesce((result->>'ok')::boolean,false) OR result#>>'{booking,status}'<>'stoppage' OR nullif(result#>>'{booking,bay_id}','') IS NOT NULL THEN
  RAISE EXCEPTION 'PDC_413_SYNTHETIC_STOPPAGE_POSTCONDITION' USING errcode='55000'; END IF;
 RETURN result||jsonb_build_object('code','synthetic_unallocated_stoppage_created','vehicle_id',p_vehicle_id,'idempotency_key',p_idempotency_key);
END $$;
REVOKE ALL ON FUNCTION public.pdc_hermes_test_create_stoppage_413(text,uuid,integer,uuid,integer,uuid,text) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.pdc_hermes_test_create_stoppage_413(text,uuid,integer,uuid,integer,uuid,text) TO authenticated;

DO $post$
DECLARE d text;
BEGIN
 SELECT pg_get_functiondef('public.book_rft_transport_412(uuid,integer,uuid)'::regprocedure) INTO d;
 IF position('actor_email text:=' in d)=0 OR position('lower(r.email)=actor_email' in d)=0 OR position(',uid,actor_email,p_idempotency_key' in d)=0
  OR NOT has_function_privilege('authenticated','public.pdc_hermes_test_create_stoppage_413(text,uuid,integer,uuid,integer,uuid,text)','EXECUTE')
  OR has_function_privilege('anon','public.pdc_hermes_test_create_stoppage_413(text,uuid,integer,uuid,integer,uuid,text)','EXECUTE') THEN
  RAISE EXCEPTION 'PDC_413_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826174000','413_rft_email_ambiguity_repair',ARRAY[
 'Exact-SHA repair renames the PL/pgSQL email variable in all migration-412 RPCs so approved-role checks are unambiguous',
 'Narrow Administrator-only HERMES-TEST facade creates an auditable unallocated booking stoppage for live clear-stoppage acceptance',
 'Production sentinel exclusion, exact predecessor head/SHA markers and narrow authenticated grant preserved'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
