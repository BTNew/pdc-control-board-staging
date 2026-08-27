-- STAGING ONLY 713: close legacy prefixed Navision reconciliation paths.
--
-- This append-only successor follows the observed live head
-- 20260827117000 / 712_body_location_collected_visibility_eligibility. It
-- preserves all 700-712 bodies and only removes stale ACL reachability from
-- historical prefixed predecessors, especially the legacy 169 path.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-713-navision-prefixed-family-acl-closure',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $pre$
DECLARE v_head text; v_delivery_hash text; v_wrapper_hash text; v_body_hash text;
BEGIN
  IF current_user<>'postgres'
     OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR lower(coalesce(current_setting('app.environment',true),''))='production'
  THEN RAISE EXCEPTION 'PDC_713_STAGING_SENTINEL_OR_ROLE_FAILED' USING errcode='55000'; END IF;
  SELECT max(version) INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$';
  IF v_head<>'20260827117000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827117000' AND name='712_body_location_collected_visibility_eligibility')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260827117000')
  THEN RAISE EXCEPTION 'PDC_713_EXACT_LIVE_HEAD_REQUIRED' USING errcode='55000'; END IF;
  SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.reconcile_navision_delivery_700(uuid)'::regprocedure),'UTF8'),'sha256'),'hex') INTO v_delivery_hash;
  SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.reconcile_navision_operational_record(uuid,uuid,text)'::regprocedure),'UTF8'),'sha256'),'hex') INTO v_wrapper_hash;
  SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.process_pdc_monitor_body_location_20260821033000(uuid,uuid,text,uuid,integer,integer,text,text,date,timestamptz,text)'::regprocedure),'UTF8'),'sha256'),'hex') INTO v_body_hash;
  IF v_delivery_hash<>'3b84fa28b6f698f964e85177dde20af1d4c8b11fe25d74ee3d6aa7adc59837fb'
     OR v_wrapper_hash<>'6159ed3eb28fd4222321a80951edfb30c687e7c196a2ee20fce2679e7444826a'
     OR v_body_hash<>'f703c7f95b29bb75f2208411f987ab81ee6aaa8c7e42a2630b3cd85fd9eeaf08'
  THEN RAISE EXCEPTION 'PDC_713_PREDECESSOR_FUNCTION_HASH_MISMATCH' USING errcode='55000'; END IF;
END $pre$;

CREATE TABLE public.pdc_navision_delivery_prefixed_family_inventory_713(
  migration_version text NOT NULL,
  phase text NOT NULL CHECK(phase IN('pre','post')),
  proc_oid oid NOT NULL,
  schema_name name NOT NULL,
  proname name NOT NULL,
  signature text NOT NULL,
  identity_arguments text NOT NULL,
  arguments text NOT NULL,
  has_defaults boolean NOT NULL,
  security_definer boolean NOT NULL,
  execute_public boolean NOT NULL,
  execute_anon boolean NOT NULL,
  execute_authenticated boolean NOT NULL,
  execute_service_role boolean NOT NULL,
  execute_pdc_email_monitor boolean NOT NULL,
  function_sha256 text NOT NULL CHECK(function_sha256~'^[a-f0-9]{64}$'),
  captured_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(phase,proc_oid)
);
ALTER TABLE public.pdc_navision_delivery_prefixed_family_inventory_713 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_navision_delivery_prefixed_family_inventory_713 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_navision_delivery_prefixed_family_inventory_713 FROM public,anon,authenticated,service_role,pdc_email_monitor;

INSERT INTO public.pdc_navision_delivery_prefixed_family_inventory_713(
  migration_version,phase,proc_oid,schema_name,proname,signature,identity_arguments,
  arguments,has_defaults,security_definer,execute_public,execute_anon,
  execute_authenticated,execute_service_role,execute_pdc_email_monitor,function_sha256)
SELECT '20260827118000','pre',p.oid,n.nspname,p.proname,
  format('%I.%s',n.nspname,p.oid::regprocedure::text),
  pg_get_function_identity_arguments(p.oid),pg_get_function_arguments(p.oid),
  p.proargdefaults IS NOT NULL,p.prosecdef,
  has_function_privilege('public',p.oid,'execute'),
  has_function_privilege('anon',p.oid,'execute'),
  has_function_privilege('authenticated',p.oid,'execute'),
  has_function_privilege('service_role',p.oid,'execute'),
  has_function_privilege('pdc_email_monitor',p.oid,'execute'),
  encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex')
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.prokind='f'
  AND (p.proname LIKE 'reconcile_navision_delivery_700%'
       OR p.proname LIKE 'reconcile_navision_operational_record%');

DO $revoke$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure::text AS signature
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.prokind='f'
      AND (p.proname LIKE 'reconcile_navision_delivery_700%'
           OR p.proname LIKE 'reconcile_navision_operational_record%')
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM public,anon,authenticated,service_role,pdc_email_monitor',r.signature);
  END LOOP;
END $revoke$;

REVOKE ALL ON FUNCTION public.reconcile_navision_delivery_700(uuid) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.reconcile_navision_delivery_700(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.reconcile_navision_operational_record(uuid,uuid,text) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.reconcile_navision_operational_record(uuid,uuid,text) TO authenticated;

INSERT INTO public.pdc_navision_delivery_prefixed_family_inventory_713(
  migration_version,phase,proc_oid,schema_name,proname,signature,identity_arguments,
  arguments,has_defaults,security_definer,execute_public,execute_anon,
  execute_authenticated,execute_service_role,execute_pdc_email_monitor,function_sha256)
SELECT '20260827118000','post',p.oid,n.nspname,p.proname,
  format('%I.%s',n.nspname,p.oid::regprocedure::text),
  pg_get_function_identity_arguments(p.oid),pg_get_function_arguments(p.oid),
  p.proargdefaults IS NOT NULL,p.prosecdef,
  has_function_privilege('public',p.oid,'execute'),
  has_function_privilege('anon',p.oid,'execute'),
  has_function_privilege('authenticated',p.oid,'execute'),
  has_function_privilege('service_role',p.oid,'execute'),
  has_function_privilege('pdc_email_monitor',p.oid,'execute'),
  encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex')
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.prokind='f'
  AND (p.proname LIKE 'reconcile_navision_delivery_700%'
       OR p.proname LIKE 'reconcile_navision_operational_record%');

DO $post$
DECLARE r record;
BEGIN
  IF (SELECT count(*) FROM public.pdc_navision_delivery_prefixed_family_inventory_713 WHERE phase='pre')<1
     OR (SELECT count(*) FROM public.pdc_navision_delivery_prefixed_family_inventory_713 WHERE phase='post')<1
     OR NOT EXISTS(SELECT 1 FROM public.pdc_navision_delivery_prefixed_family_inventory_713 WHERE phase='pre' AND proname='reconcile_navision_operational_record_pre134' AND execute_service_role)
     OR to_regprocedure('public.reconcile_navision_delivery_700(uuid)') IS NULL
     OR to_regprocedure('public.reconcile_navision_operational_record(uuid,uuid,text)') IS NULL
  THEN RAISE EXCEPTION 'PDC_713_PREFIXED_FAMILY_PRESTATE_FAILED' USING errcode='55000'; END IF;
  FOR r IN
    SELECT p.oid::regprocedure::text AS signature,
           p.proargdefaults IS NOT NULL AS has_defaults,
           has_function_privilege('public',p.oid,'execute') AS x_public,
           has_function_privilege('anon',p.oid,'execute') AS x_anon,
           has_function_privilege('authenticated',p.oid,'execute') AS x_authenticated,
           has_function_privilege('service_role',p.oid,'execute') AS x_service,
           has_function_privilege('pdc_email_monitor',p.oid,'execute') AS x_monitor
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.prokind='f'
      AND (p.proname LIKE 'reconcile_navision_delivery_700%'
           OR p.proname LIKE 'reconcile_navision_operational_record%')
  LOOP
    IF r.signature='reconcile_navision_delivery_700(uuid)'
       OR r.signature='reconcile_navision_operational_record(uuid,uuid,text)' THEN
      IF r.has_defaults OR r.x_public OR r.x_anon OR NOT r.x_authenticated OR r.x_service OR r.x_monitor THEN
        RAISE EXCEPTION 'PDC_713_CANONICAL_FAMILY_ACL_FAILED:%',r.signature USING errcode='55000';
      END IF;
    ELSIF r.x_public OR r.x_anon OR r.x_authenticated OR r.x_service OR r.x_monitor THEN
      RAISE EXCEPTION 'PDC_713_LEGACY_PREFIX_CALLABLE:%',r.signature USING errcode='55000';
    END IF;
  END LOOP;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260827118000','713_close_navision_prefixed_family_acl_bypass',ARRAY[
  'Exact live-head guard: 20260827117000 / 712_body_location_collected_visibility_eligibility; preserve 709-712 and 700-708 append-only',
  'Inventory every public pg_proc/pg_namespace function whose name begins reconcile_navision_delivery_700 or reconcile_navision_operational_record, including legacy 169/pre134/pre171 predecessors and defaults',
  'Revoke public, anon, authenticated, service_role and pdc_email_monitor from every prefixed predecessor and restore only the exact canonical authenticated delivery UUID and exact three-argument wrapper',
  'Close the observed service_role pre134 alternate completion path without changing non-delivery body-location processing or canonical 700/707/708 logic; Production untouched'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
