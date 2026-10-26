-- SECURITY ROLLBACK: restores the prior anonymous/authenticated access exposure.
-- Use only if explicitly required; ordinary performance rollback should retain this restriction.
-- Restrict only two verified SQL deployment helpers. Staging cdsmnqxtyyoeoznmbidd only.
-- No rows, policies, defaults, table ownership or postgres/service_role access are changed.
-- Guarded by exact reviewed table shape, ACL set and absence of application dependencies.
-- ACL array order is immaterial; restoration preserves the exact privilege/grantor set.
SET LOCAL lock_timeout='2s';
SET LOCAL statement_timeout='10s';
DO $helper_access$
DECLARE
 v_name text;
 v_rel pg_catalog.pg_class%ROWTYPE;
 v_expected_before aclitem[] := '{postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}'::aclitem[];
 v_expected_after aclitem[] := '{postgres=arwdDxtm/postgres,anon=arwdDxtm/postgres,authenticated=arwdDxtm/postgres,service_role=arwdDxtm/postgres}'::aclitem[];
 v_shape jsonb;
 v_acl aclitem[];
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE
 OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
  RAISE EXCEPTION 'r551 helper access: staging only';
 END IF;
 -- Validate BOTH objects before changing either ACL. The encompassing DO is atomic.
 FOREACH v_name IN ARRAY ARRAY['_r551_file','_r551_stmt'] LOOP
  EXECUTE format('LOCK TABLE public.%I IN ACCESS SHARE MODE',v_name);
  SELECT * INTO STRICT v_rel FROM pg_catalog.pg_class WHERE oid=to_regclass('public.'||v_name);
  IF pg_get_userbyid(v_rel.relowner)<>'postgres' OR v_rel.relkind<>'r' OR v_rel.relpersistence<>'p'
   OR v_rel.relrowsecurity OR v_rel.relforcerowsecurity
   OR v_rel.relacl IS NULL OR NOT(v_rel.relacl @> v_expected_before AND v_rel.relacl <@ v_expected_before) THEN
   RAISE EXCEPTION USING ERRCODE='PDC01',MESSAGE='r551 helper access: reviewed owner/type/RLS/ACL changed: '||v_name;
  END IF;
  SELECT jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull) ORDER BY a.attnum)
   INTO v_shape FROM pg_attribute a WHERE a.attrelid=v_rel.oid AND a.attnum>0 AND NOT a.attisdropped;
  IF v_shape IS DISTINCT FROM '[{"name":"n","type":"integer","not_null":true},{"name":"b64","type":"text","not_null":true}]'::jsonb
   OR EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid=v_rel.oid AND a.attnum>0 AND (a.attisdropped OR a.attacl IS NOT NULL OR a.atthasdef OR a.attidentity<>'' OR a.attgenerated<>''))
   OR (SELECT count(*) FROM pg_constraint k WHERE k.conrelid=v_rel.oid)<>1
   OR NOT EXISTS(SELECT 1 FROM pg_constraint k WHERE k.conrelid=v_rel.oid AND k.contype='p' AND pg_get_constraintdef(k.oid)='PRIMARY KEY (n)') THEN
   RAISE EXCEPTION USING ERRCODE='PDC02',MESSAGE='r551 helper access: reviewed columns/constraints changed: '||v_name;
  END IF;
  IF EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid=v_rel.oid)
   OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid=v_rel.oid)
   OR EXISTS(SELECT 1 FROM pg_inherits WHERE inhrelid=v_rel.oid OR inhparent=v_rel.oid)
   OR EXISTS(
    SELECT 1 FROM pg_depend d WHERE d.refclassid='pg_class'::regclass AND d.refobjid=v_rel.oid
    AND NOT (d.deptype='i' AND d.classid IN ('pg_type'::regclass,'pg_class'::regclass))
    AND NOT (d.deptype='a' AND d.classid='pg_constraint'::regclass AND EXISTS(SELECT 1 FROM pg_constraint k WHERE k.oid=d.objid AND k.conrelid=v_rel.oid AND k.contype='p'))
   )
   OR EXISTS(SELECT 1 FROM pg_proc p WHERE position(v_name IN p.prosrc)>0) THEN
   RAISE EXCEPTION USING ERRCODE='PDC03',MESSAGE='r551 helper access: unexpected dependency or policy: '||v_name;
  END IF;
 END LOOP;
 FOREACH v_name IN ARRAY ARRAY['_r551_file','_r551_stmt'] LOOP
  EXECUTE format('GRANT ALL PRIVILEGES ON TABLE public.%I TO anon, authenticated',v_name);
  SELECT relacl INTO STRICT v_acl FROM pg_class WHERE oid=to_regclass('public.'||v_name);
  IF v_acl IS NULL OR NOT(v_acl @> v_expected_after AND v_acl <@ v_expected_after) THEN
   RAISE EXCEPTION 'r551 helper access: ACL verification failed: %',v_name;
  END IF;
 END LOOP;
END
$helper_access$;
