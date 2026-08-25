-- STAGING ONLY 423: qualify STOPPAGE actor email variables.
BEGIN;
SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-423-stoppage-actor-email',0));
DO $repair$
DECLARE item record; d text; h text; repaired text;
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR NOT public.pdc_monitor_staging_guard()
   OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260826193000' AND name='422_targeted_stoppage_paths')
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260826193000') THEN
  RAISE EXCEPTION 'PDC_423_STAGING_HEAD_MISMATCH' USING errcode='55000'; END IF;
 FOR item IN SELECT * FROM (VALUES
   ('public.set_pmb_stoppage_422(uuid,integer,text,text,uuid)'::regprocedure,'5e9d050b428b5299fc480fbbbe247f6db47d0ca3e382267e8a06efda46fa546d'),
   ('public.clear_vehicle_stoppage_422(uuid,integer,text,uuid,integer,text,uuid)'::regprocedure,'9c92e37350156a9c69f0ad4f51f1f8be89305d2b474f243c8d431cf6b8cbf70d')
 ) v(fn,expected_sha) LOOP
  SELECT pg_get_functiondef(item.fn),encode(extensions.digest(convert_to(pg_get_functiondef(item.fn),'UTF8'),'sha256'),'hex') INTO d,h;
  IF h<>item.expected_sha THEN RAISE EXCEPTION 'PDC_423_EXACT_FUNCTION_MISMATCH:%',item.fn USING errcode='55000'; END IF;
  repaired:=replace(d,'email text:=lower(btrim(coalesce(auth.jwt()->>''email'','''')))','actor_email text:=lower(btrim(coalesce(auth.jwt()->>''email'','''')))');
  repaired:=replace(repaired,'lower(r.email)=email','lower(r.email)=actor_email');
  repaired:=replace(repaired,',uid,email,reason,',',uid,actor_email,reason,');
  repaired:=replace(repaired,',uid,email,p_idempotency_key,',',uid,actor_email,p_idempotency_key,');
  IF repaired=d OR position('lower(r.email)=email' in repaired)>0 OR position(' email text:=' in repaired)>0 THEN RAISE EXCEPTION 'PDC_423_REPAIR_NOT_EXACT:%',item.fn USING errcode='55000'; END IF;
  EXECUTE repaired;
 END LOOP;
END $repair$;
DO $post$
DECLARE d text;
BEGIN
 SELECT pg_get_functiondef('public.set_pmb_stoppage_422(uuid,integer,text,text,uuid)'::regprocedure) INTO d;
 IF position('actor_email text:=' in d)=0 OR position('lower(r.email)=actor_email' in d)=0 OR position('lower(r.email)=email' in d)>0 THEN RAISE EXCEPTION 'PDC_423_SET_POSTCONDITION' USING errcode='55000'; END IF;
 SELECT pg_get_functiondef('public.clear_vehicle_stoppage_422(uuid,integer,text,uuid,integer,text,uuid)'::regprocedure) INTO d;
 IF position('actor_email text:=' in d)=0 OR position('lower(r.email)=actor_email' in d)=0 OR position('lower(r.email)=email' in d)>0 THEN RAISE EXCEPTION 'PDC_423_CLEAR_POSTCONDITION' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826194000','423_stoppage_actor_email_qualification',ARRAY[
 'Exact-SHA repair qualifies actor email variables in PMB set/clear and targeted clear authorization checks',
 'No grants, receipt history, vehicle data or Production state changed'
]);
NOTIFY pgrst,'reload schema'; COMMIT;
