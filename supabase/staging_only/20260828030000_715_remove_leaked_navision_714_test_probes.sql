-- STAGING ONLY 715: remove only the leaked HERMES-TEST probes from 714.
--
-- 714 correctly revoked the hostile members but its public synthetic probes
-- were not included in the schema cleanup. This append-only repair starts at
-- the exact live database head 20260828020000 / 714 and preserves all real and
-- historical Navision definitions. Production is forbidden. No user data or
-- real vehicle is touched; only probe OIDs recorded by 714 may be removed.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='60s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-715-remove-navision-714-probes',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guards$
BEGIN
  IF current_user<>'postgres'
     OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR lower(coalesce(current_setting('app.environment',true),''))='production'
  THEN RAISE EXCEPTION 'PDC_715_STAGING_SENTINEL_OR_ROLE_FAILED' USING errcode='55000'; END IF;
  IF (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260828020000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations
         WHERE version='20260828020000' AND name='714_fail_closed_navision_family_catalog_hardening')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations
               WHERE version~'^[0-9]{14}$' AND version>'20260828020000')
  THEN RAISE EXCEPTION 'PDC_715_EXACT_LIVE_HEAD_REQUIRED' USING errcode='55000'; END IF;
END $guards$;

-- Fail closed if either target no longer exactly matches the OID recorded as a
-- 714 HERMES-TEST post-state probe. This prevents deleting an unrelated
-- same-name routine if the live catalog drifted between successors.
DO $cleanup$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid,
           format('%I.%I(%s)',n.nspname,p.proname,pg_get_function_identity_arguments(p.oid)) AS signature
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND ((p.proname='Reconcile_Navision_Delivery_700'
            AND pg_get_function_identity_arguments(p.oid)='p_backend_record_id uuid')
        OR (p.proname='reconcile_navision_delivery_700'
            AND pg_get_function_identity_arguments(p.oid)='p_backend_record_id uuid, p_probe text'
            AND p.proargdefaults IS NOT NULL))
  LOOP
    IF NOT EXISTS(SELECT 1 FROM public.pdc_navision_function_security_inventory_714 i
                  WHERE i.phase='post' AND i.proc_oid=r.oid
                    AND i.schema_name='public' AND NOT i.is_canonical
                    AND i.function_sha256=encode(extensions.digest(convert_to(pg_get_functiondef(r.oid),'UTF8'),'sha256'),'hex'))
    THEN RAISE EXCEPTION 'PDC_715_PROBE_IDENTITY_GUARD_FAILED:%',r.signature USING errcode='55000'; END IF;
    EXECUTE format('DROP FUNCTION %s',r.signature);
  END LOOP;
END $cleanup$;

DO $postconditions$
DECLARE r record;
BEGIN
  IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='public' AND p.proname='Reconcile_Navision_Delivery_700')
     OR EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
               WHERE n.nspname='public' AND p.proname='reconcile_navision_delivery_700'
                 AND pg_get_function_identity_arguments(p.oid)='p_backend_record_id uuid, p_probe text')
  THEN RAISE EXCEPTION 'PDC_715_SYNTHETIC_PROBE_REMAINS' USING errcode='55000'; END IF;

  IF to_regprocedure('public.reconcile_navision_delivery_700(uuid)') IS NULL
     OR to_regprocedure('public.reconcile_navision_operational_record(uuid,uuid,text)') IS NULL
     OR to_regprocedure('public.process_pdc_monitor_body_location_20260821033000(uuid,uuid,text,uuid,integer,integer,text,text,date,timestamptz,text)') IS NULL
  THEN RAISE EXCEPTION 'PDC_715_CANONICAL_SIGNATURE_MISSING' USING errcode='55000'; END IF;

  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.proname='reconcile_navision_delivery_700')<>1
  THEN RAISE EXCEPTION 'PDC_715_DELIVERY_OVERLOAD_REMAINS' USING errcode='55000'; END IF;

  IF EXISTS(
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname !~ '^pg_' AND n.nspname<>'information_schema'
      AND (lower(p.proname) LIKE 'reconcile_navision_delivery_700%'
       OR lower(p.proname) LIKE 'reconcile_navision_operational_record%'
       OR lower(p.proname) LIKE 'process_pdc_monitor_body_location_20260821033000%')
      AND (has_function_privilege('public',p.oid,'execute')
       OR has_function_privilege('anon',p.oid,'execute')
       OR has_function_privilege('service_role',p.oid,'execute')
       OR has_function_privilege('pdc_email_monitor',p.oid,'execute')))
  THEN RAISE EXCEPTION 'PDC_715_NONCANONICAL_EXECUTE_DRIFT' USING errcode='55000'; END IF;

  PERFORM public.reconcile_navision_delivery_700('00000000-0000-0000-0000-000000000715'::uuid);
END $postconditions$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260828030000','715_remove_leaked_navision_714_test_probes',ARRAY[
  'Exact guard: live database head 20260828020000 / 714; preserve all 700-714 definitions and production untouched',
  'Remove only the two public synthetic routines whose OIDs and definitions were recorded by 714 HERMES-TEST inventory; fail closed on identity drift',
  'Postcondition proves canonical delivery call is no longer ambiguous and all noncanonical family members remain denied for public, anon, service_role and pdc_email_monitor'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
