-- STAGING ONLY 714: comprehensive fail-closed Navision family catalog hardening.
--
-- Baseline is the exact live staging source head 7e6bc3c94d173620c9070ff5f63a93f1dcdf9408
-- with tree a44984a27118dd2fb719ca57c715953786b2f850 and database head
-- 20260828010000 / 683_uid514_capability_mint_replay_repair. Preserve and reuse
-- applied 700-713; never rewrite, reapply, reset, or touch production.
-- Live PostgREST configuration read-back at this baseline: public, graphql_public.
-- Hostile probes are HERMES-TEST-only and are removed before COMMIT; any failure
-- rolls back the whole migration and leaves no probe or user-data mutation.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-714-navision-family-catalog-closure',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guards$
DECLARE
  v_head text;
  v_delivery_hash text;
  v_wrapper_hash text;
  v_body_hash text;
BEGIN
  IF current_user<>'postgres'
     OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR lower(coalesce(current_setting('app.environment',true),''))='production'
  THEN RAISE EXCEPTION 'PDC_714_STAGING_SENTINEL_OR_ROLE_FAILED' USING errcode='55000'; END IF;

  SELECT max(version) INTO v_head
  FROM supabase_migrations.schema_migrations
  WHERE version~'^[0-9]{14}$';
  IF v_head<>'20260828010000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations
         WHERE version='20260828010000' AND name='683_uid514_capability_mint_replay_repair')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations
               WHERE version~'^[0-9]{14}$' AND version>'20260828010000')
  THEN RAISE EXCEPTION 'PDC_714_EXACT_LIVE_HEAD_REQUIRED' USING errcode='55000'; END IF;

  IF (SELECT count(*) FROM (VALUES
      ('20260827101000','700_final_authoritative_pdc_lifecycle'),
      ('20260827102000','701_final_qc_two_transition_repair'),
      ('20260827103000','702_final_collected_workshop_status_repair'),
      ('20260827104000','703_delivery_wrapper_global_normalization_repair'),
      ('20260827105000','704_delivery_wrapper_case_safe_normalization_repair'),
      ('20260827106000','673_authenticated_monitor_execution_attachment_successor'),
      ('20260827107000','706_final_booked_synthetic_payload_identity_repair_after_673_collision'),
      ('20260827108000','674_authenticated_monitor_mailbox_activation_transition'),
      ('20260827109000','675_authenticated_monitor_enqueue_trigger_compatibility'),
      ('20260827109100','707_navision_delivery_monitor_identity_security_successor'),
      ('20260827110000','676_authenticated_monitor_rollback_control_repair'),
      ('20260827110100','708_navision_delivery_scope_674_alignment_successor'),
      ('20260827113000','709_close_navision_delivery_overloads_and_body_location_bypass'),
      ('20260827115000','710_body_location_intake_alias_repair'),
      ('20260827116000','711_body_location_canonical_delivery_eligibility'),
      ('20260827117000','712_body_location_collected_visibility_eligibility'),
      ('20260827118000','713_close_navision_prefixed_family_acl_bypass')
    ) AS expected(version,name)
    WHERE NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations m
                      WHERE m.version=expected.version AND m.name=expected.name))<>0
  THEN RAISE EXCEPTION 'PDC_714_PRESERVED_SUCCESSOR_CHAIN_REQUIRED' USING errcode='55000'; END IF;

  IF to_regprocedure('public.reconcile_navision_delivery_700(uuid)') IS NULL
     OR to_regprocedure('public.reconcile_navision_operational_record(uuid,uuid,text)') IS NULL
     OR to_regprocedure('public.process_pdc_monitor_body_location_20260821033000(uuid,uuid,text,uuid,integer,integer,text,text,date,timestamptz,text)') IS NULL
     OR to_regclass('public.pdc_full_inbox_location_receipts_20260821033000') IS NULL
     OR to_regclass('public.pdc_final_pdc_lifecycle_receipts_700') IS NULL
  THEN RAISE EXCEPTION 'PDC_714_REQUIRED_LIVE_OBJECT_MISSING' USING errcode='55000'; END IF;

  SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.reconcile_navision_delivery_700(uuid)'::regprocedure),'UTF8'),'sha256'),'hex') INTO v_delivery_hash;
  SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.reconcile_navision_operational_record(uuid,uuid,text)'::regprocedure),'UTF8'),'sha256'),'hex') INTO v_wrapper_hash;
  SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.process_pdc_monitor_body_location_20260821033000(uuid,uuid,text,uuid,integer,integer,text,text,date,timestamptz,text)'::regprocedure),'UTF8'),'sha256'),'hex') INTO v_body_hash;
  IF v_delivery_hash<>'3b84fa28b6f698f964e85177dde20af1d4c8b11fe25d74ee3d6aa7adc59837fb'
     OR v_wrapper_hash<>'6159ed3eb28fd4222321a80951edfb30c687e7c196a2ee20fce2679e7444826a'
     OR v_body_hash<>'f703c7f95b29bb75f2208411f987ab81ee6aaa8c7e42a2630b3cd85fd9eeaf08'
  THEN RAISE EXCEPTION 'PDC_714_PREDECESSOR_FUNCTION_HASH_MISMATCH' USING errcode='55000'; END IF;
END $guards$;

-- Rollback-contained hostile catalog probes exercise lower(proname), quoted
-- mixed-case identifiers, same-name overloads with defaults, alternate schemas,
-- prefixed family members, and ACL grant-option authority.
CREATE SCHEMA pdc_hermes_security_probe_714;
CREATE FUNCTION public."Reconcile_Navision_Delivery_700"(p_backend_record_id uuid)
RETURNS jsonb LANGUAGE sql AS $fn$SELECT jsonb_build_object('probe',true)$fn$;
CREATE FUNCTION public.reconcile_navision_delivery_700(
  p_backend_record_id uuid,
  p_probe text DEFAULT 'HERMES-TEST-714')
RETURNS jsonb LANGUAGE sql AS $fn$SELECT jsonb_build_object('probe',true)$fn$;
CREATE FUNCTION pdc_hermes_security_probe_714.reconcile_navision_operational_record(
  p_backend_record_id uuid,
  p_actor_id uuid,
  p_actor_email text DEFAULT 'HERMES-TEST-714')
RETURNS jsonb LANGUAGE sql AS $fn$SELECT jsonb_build_object('probe',true)$fn$;
CREATE FUNCTION pdc_hermes_security_probe_714.process_pdc_monitor_body_location_20260821033000_probe(
  p_intake_id uuid)
RETURNS jsonb LANGUAGE sql AS $fn$SELECT jsonb_build_object('probe',true)$fn$;
GRANT EXECUTE ON FUNCTION public."Reconcile_Navision_Delivery_700"(uuid) TO service_role WITH GRANT OPTION;
GRANT EXECUTE ON FUNCTION public.reconcile_navision_delivery_700(uuid,text) TO service_role WITH GRANT OPTION;
GRANT EXECUTE ON FUNCTION pdc_hermes_security_probe_714.reconcile_navision_operational_record(uuid,uuid,text) TO service_role WITH GRANT OPTION;
GRANT EXECUTE ON FUNCTION pdc_hermes_security_probe_714.process_pdc_monitor_body_location_20260821033000_probe(uuid) TO service_role WITH GRANT OPTION;

CREATE TABLE public.pdc_navision_postgrest_schema_inventory_714(
  migration_version text NOT NULL,
  schema_name name PRIMARY KEY,
  postgrest_exposed boolean NOT NULL,
  exposure_source text NOT NULL,
  live_config_value text NOT NULL,
  captured_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_navision_postgrest_schema_inventory_714 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_navision_postgrest_schema_inventory_714 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_navision_postgrest_schema_inventory_714 FROM public,anon,authenticated,service_role,pdc_email_monitor;

-- This is intentionally a separate all-non-system-schema classification. The
-- live PostgREST read-back independently established exactly public and
-- graphql_public as exposed; every other catalog schema is explicitly marked
-- not exposed rather than being silently treated as public.
INSERT INTO public.pdc_navision_postgrest_schema_inventory_714(
  migration_version,schema_name,postgrest_exposed,exposure_source,live_config_value)
SELECT '20260828020000',n.nspname,n.nspname IN ('public','graphql_public' ),
  CASE WHEN n.nspname IN ('public','graphql_public') THEN 'live_postgrest_config' ELSE 'live_postgrest_config_not_exposed' END,
  'public, graphql_public'
FROM pg_namespace n
WHERE n.nspname !~ '^pg_' AND n.nspname<>'information_schema';

CREATE TABLE public.pdc_navision_function_security_inventory_714(
  migration_version text NOT NULL,
  phase text NOT NULL CHECK(phase IN('pre','post')),
  proc_oid oid NOT NULL,
  schema_name name NOT NULL,
  proname name NOT NULL,
  signature text NOT NULL,
  identity_arguments text NOT NULL,
  arguments text NOT NULL,
  has_defaults boolean NOT NULL,
  owner_name name NOT NULL,
  prokind "char" NOT NULL,
  security_definer boolean NOT NULL,
  volatility "char" NOT NULL,
  proconfig text[] NOT NULL,
  acl_entries jsonb NOT NULL,
  execute_public boolean NOT NULL,
  execute_anon boolean NOT NULL,
  execute_authenticated boolean NOT NULL,
  execute_service_role boolean NOT NULL,
  execute_pdc_email_monitor boolean NOT NULL,
  postgrest_exposed boolean NOT NULL,
  is_canonical boolean NOT NULL,
  function_sha256 text NOT NULL CHECK(function_sha256~'^[a-f0-9]{64}$'),
  captured_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(phase,proc_oid)
);
ALTER TABLE public.pdc_navision_function_security_inventory_714 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_navision_function_security_inventory_714 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_navision_function_security_inventory_714 FROM public,anon,authenticated,service_role,pdc_email_monitor;

INSERT INTO public.pdc_navision_function_security_inventory_714(
  migration_version,phase,proc_oid,schema_name,proname,signature,identity_arguments,
  arguments,has_defaults,owner_name,prokind,security_definer,volatility,proconfig,
  acl_entries,execute_public,execute_anon,execute_authenticated,execute_service_role,
  execute_pdc_email_monitor,postgrest_exposed,is_canonical,function_sha256)
SELECT '20260828020000','pre',p.oid,n.nspname,p.proname,
  format('%I.%I(%s)',n.nspname,p.proname,pg_get_function_identity_arguments(p.oid)),
  pg_get_function_identity_arguments(p.oid),pg_get_function_arguments(p.oid),
  p.proargdefaults IS NOT NULL,r.rolname,p.prokind,p.prosecdef,p.provolatile,
  coalesce(p.proconfig,'{}'::text[]),
  coalesce((SELECT jsonb_agg(jsonb_build_object(
      'grantor',q.grantor_name,'grantee',q.grantee_name,'privilege',q.privilege_type,
      'grant_option',q.is_grantable)
      ORDER BY q.grantor_name,q.grantee_name,q.privilege_type,q.is_grantable)
    FROM (SELECT CASE WHEN x.grantor=0 THEN 'PUBLIC' ELSE pg_get_userbyid(x.grantor) END AS grantor_name,
                 CASE WHEN x.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(x.grantee) END AS grantee_name,
                 x.privilege_type,x.is_grantable
          FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) x) q),'[]'::jsonb),
  has_function_privilege('public',p.oid,'execute'),has_function_privilege('anon',p.oid,'execute'),
  has_function_privilege('authenticated',p.oid,'execute'),has_function_privilege('service_role',p.oid,'execute'),
  has_function_privilege('pdc_email_monitor',p.oid,'execute'),coalesce(s.postgrest_exposed,false),
  p.oid IN (
    'public.reconcile_navision_delivery_700(uuid)'::regprocedure,
    'public.reconcile_navision_operational_record(uuid,uuid,text)'::regprocedure,
    'public.process_pdc_monitor_body_location_20260821033000(uuid,uuid,text,uuid,integer,integer,text,text,date,timestamp with time zone,text)'::regprocedure),
  encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex')
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
JOIN pg_roles r ON r.oid=p.proowner
LEFT JOIN public.pdc_navision_postgrest_schema_inventory_714 s ON s.schema_name=n.nspname
WHERE n.nspname !~ '^pg_' AND n.nspname<>'information_schema'
  AND p.prokind IN ('f','p')
  AND (lower(p.proname) LIKE 'reconcile_navision_delivery_700%'
       OR lower(p.proname) LIKE 'reconcile_navision_operational_record%'
       OR lower(p.proname) LIKE 'process_pdc_monitor_body_location_20260821033000%');

DO $inventory_guard$
BEGIN
  IF EXISTS(
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname !~ '^pg_' AND n.nspname<>'information_schema'
      AND (lower(p.proname) LIKE 'reconcile_navision_delivery_700%'
       OR lower(p.proname) LIKE 'reconcile_navision_operational_record%'
       OR lower(p.proname) LIKE 'process_pdc_monitor_body_location_20260821033000%')
      AND p.prokind NOT IN ('f','p'))
  THEN RAISE EXCEPTION 'PDC_714_UNSUPPORTED_PROKIND_FAMILY_MEMBER' USING errcode='55000'; END IF;
END $inventory_guard$;

-- Normalize ownership first so a hostile noncanonical owner cannot retain
-- implicit execution after the explicit ACL revocation.
DO $revoke$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT format('%I.%I(%s)',n.nspname,p.proname,pg_get_function_identity_arguments(p.oid)) AS signature
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname !~ '^pg_' AND n.nspname<>'information_schema'
      AND p.prokind IN ('f','p')
      AND (lower(p.proname) LIKE 'reconcile_navision_delivery_700%'
       OR lower(p.proname) LIKE 'reconcile_navision_operational_record%'
       OR lower(p.proname) LIKE 'process_pdc_monitor_body_location_20260821033000%')
  LOOP
    EXECUTE format('ALTER ROUTINE %s OWNER TO postgres',r.signature);
    EXECUTE format('REVOKE ALL ON ROUTINE %s FROM PUBLIC,anon,authenticated,service_role,pdc_email_monitor',r.signature);
  END LOOP;
END $revoke$;

-- Only these exact lowercase public signatures are execution-capable. All
-- historical definitions remain present in the catalog and inventory but are
-- private, including old defaults, mixed-case names, overloads, and alternate schemas.
GRANT EXECUTE ON FUNCTION public.reconcile_navision_delivery_700(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reconcile_navision_operational_record(uuid,uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.process_pdc_monitor_body_location_20260821033000(uuid,uuid,text,uuid,integer,integer,text,text,date,timestamptz,text) TO authenticated;

INSERT INTO public.pdc_navision_function_security_inventory_714(
  migration_version,phase,proc_oid,schema_name,proname,signature,identity_arguments,
  arguments,has_defaults,owner_name,prokind,security_definer,volatility,proconfig,
  acl_entries,execute_public,execute_anon,execute_authenticated,execute_service_role,
  execute_pdc_email_monitor,postgrest_exposed,is_canonical,function_sha256)
SELECT '20260828020000','post',p.oid,n.nspname,p.proname,
  format('%I.%I(%s)',n.nspname,p.proname,pg_get_function_identity_arguments(p.oid)),
  pg_get_function_identity_arguments(p.oid),pg_get_function_arguments(p.oid),
  p.proargdefaults IS NOT NULL,r.rolname,p.prokind,p.prosecdef,p.provolatile,
  coalesce(p.proconfig,'{}'::text[]),
  coalesce((SELECT jsonb_agg(jsonb_build_object(
      'grantor',q.grantor_name,'grantee',q.grantee_name,'privilege',q.privilege_type,
      'grant_option',q.is_grantable)
      ORDER BY q.grantor_name,q.grantee_name,q.privilege_type,q.is_grantable)
    FROM (SELECT CASE WHEN x.grantor=0 THEN 'PUBLIC' ELSE pg_get_userbyid(x.grantor) END AS grantor_name,
                 CASE WHEN x.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(x.grantee) END AS grantee_name,
                 x.privilege_type,x.is_grantable
          FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) x) q),'[]'::jsonb),
  has_function_privilege('public',p.oid,'execute'),has_function_privilege('anon',p.oid,'execute'),
  has_function_privilege('authenticated',p.oid,'execute'),has_function_privilege('service_role',p.oid,'execute'),
  has_function_privilege('pdc_email_monitor',p.oid,'execute'),coalesce(s.postgrest_exposed,false),
  p.oid IN (
    'public.reconcile_navision_delivery_700(uuid)'::regprocedure,
    'public.reconcile_navision_operational_record(uuid,uuid,text)'::regprocedure,
    'public.process_pdc_monitor_body_location_20260821033000(uuid,uuid,text,uuid,integer,integer,text,text,date,timestamp with time zone,text)'::regprocedure),
  encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex')
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
JOIN pg_roles r ON r.oid=p.proowner
LEFT JOIN public.pdc_navision_postgrest_schema_inventory_714 s ON s.schema_name=n.nspname
WHERE n.nspname !~ '^pg_' AND n.nspname<>'information_schema'
  AND p.prokind IN ('f','p')
  AND (lower(p.proname) LIKE 'reconcile_navision_delivery_700%'
       OR lower(p.proname) LIKE 'reconcile_navision_operational_record%'
       OR lower(p.proname) LIKE 'process_pdc_monitor_body_location_20260821033000%');

DO $postconditions$
DECLARE
  expected_acl jsonb := '[
    {"grantor":"postgres","grantee":"authenticated","privilege":"EXECUTE","grant_option":false},
    {"grantor":"postgres","grantee":"postgres","privilege":"EXECUTE","grant_option":false}
  ]'::jsonb;
BEGIN
  IF (SELECT count(*) FROM public.pdc_navision_function_security_inventory_714 WHERE phase='pre')<4
     OR (SELECT count(*) FROM public.pdc_navision_function_security_inventory_714 WHERE phase='post')<4
     OR (SELECT count(*) FROM public.pdc_navision_function_security_inventory_714 WHERE phase='post' AND is_canonical)<>3
  THEN RAISE EXCEPTION 'PDC_714_HOSTILE_PROBE_INVENTORY_FAILED' USING errcode='55000'; END IF;

  IF EXISTS(SELECT 1 FROM public.pdc_navision_postgrest_schema_inventory_714
            WHERE schema_name IN ('public','graphql_public') AND NOT postgrest_exposed)
     OR (SELECT count(*) FROM public.pdc_navision_postgrest_schema_inventory_714
         WHERE postgrest_exposed AND schema_name IN ('public','graphql_public'))<>2
     OR EXISTS(SELECT 1 FROM public.pdc_navision_postgrest_schema_inventory_714
               WHERE schema_name NOT IN ('public','graphql_public') AND postgrest_exposed)
  THEN RAISE EXCEPTION 'PDC_714_POSTGREST_SCHEMA_CLASSIFICATION_FAILED' USING errcode='55000'; END IF;

  IF EXISTS(
    SELECT 1 FROM public.pdc_navision_function_security_inventory_714 i
    WHERE i.phase='post' AND i.is_canonical
      AND (i.schema_name<>'public' OR i.owner_name<>'postgres' OR i.prokind<>'f'
       OR NOT i.security_definer OR i.volatility<>'v' OR i.has_defaults
       OR (i.proname='reconcile_navision_delivery_700' AND i.proconfig<>
            ARRAY['search_path=pg_catalog, public, auth, extensions','statement_timeout=120s'])
       OR (i.proname='reconcile_navision_operational_record' AND i.proconfig<>
            ARRAY['search_path=pg_catalog, public, auth, extensions'])
       OR (i.proname='process_pdc_monitor_body_location_20260821033000' AND i.proconfig<>
            ARRAY['search_path=pg_catalog, public, extensions, auth'])
       OR i.acl_entries<>expected_acl OR i.execute_public OR i.execute_anon
       OR NOT i.execute_authenticated OR i.execute_service_role OR i.execute_pdc_email_monitor
       OR NOT i.postgrest_exposed))
  THEN RAISE EXCEPTION 'PDC_714_CANONICAL_METADATA_FAILED' USING errcode='55000'; END IF;

  IF EXISTS(
    SELECT 1 FROM public.pdc_navision_function_security_inventory_714 i
    WHERE i.phase='post' AND NOT i.is_canonical
      AND (i.execute_public OR i.execute_anon OR i.execute_authenticated
       OR i.execute_service_role OR i.execute_pdc_email_monitor))
  THEN RAISE EXCEPTION 'PDC_714_UNEXPECTED_CALLABLE_FAMILY_MEMBER' USING errcode='55000'; END IF;

  IF EXISTS(
    SELECT 1 FROM public.pdc_navision_function_security_inventory_714 i
    WHERE i.phase='post' AND (i.owner_name<>'postgres'
       OR i.acl_entries @> '[{"grant_option":true}]'::jsonb
       OR i.execute_public))
  THEN RAISE EXCEPTION 'PDC_714_ACL_OR_OWNER_DRIFT' USING errcode='55000'; END IF;

  IF NOT EXISTS(SELECT 1 FROM public.pdc_navision_function_security_inventory_714
                WHERE phase='post' AND proname='Reconcile_Navision_Delivery_700'
                  AND schema_name='public' AND NOT is_canonical
                  AND NOT execute_public AND NOT execute_service_role)
     OR NOT EXISTS(SELECT 1 FROM public.pdc_navision_function_security_inventory_714
                WHERE phase='post' AND schema_name='pdc_hermes_security_probe_714'
                  AND lower(proname) LIKE 'reconcile_navision_operational_record%'
                  AND NOT execute_authenticated AND NOT execute_service_role)
     OR NOT EXISTS(SELECT 1 FROM public.pdc_navision_function_security_inventory_714
                WHERE phase='post' AND schema_name='public'
                  AND lower(proname) LIKE 'reconcile_navision_delivery_700%'
                  AND has_defaults AND NOT execute_authenticated)
  THEN RAISE EXCEPTION 'PDC_714_HOSTILE_PROBE_FAILED' USING errcode='55000'; END IF;
END $postconditions$;

-- The probe schema and all synthetic routines are transaction-local test
-- material. Persistent inventory retains the pre/post evidence; no user row
-- or real vehicle was created or mutated.
-- public probes are also transaction-local test material and must not survive.
DROP FUNCTION public."Reconcile_Navision_Delivery_700"(uuid);
DROP FUNCTION public.reconcile_navision_delivery_700(uuid,text);
DROP SCHEMA pdc_hermes_security_probe_714 CASCADE;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260828020000','714_fail_closed_navision_family_catalog_hardening',ARRAY[
  'Exact guard: source commit 7e6bc3c94d173620c9070ff5f63a93f1dcdf9408 and tree a44984a27118dd2fb719ca57c715953786b2f850; live database head 683; preserve 700-713',
  'Inventory pg_proc across every non-system schema using lower(proname) for exact and prefixed delivery, operational, and body-location families',
  'Classify live PostgREST schemas public and graphql_public separately from all other non-system schemas; capture owner, prokind, prosecdef, volatility, proconfig, defaults, identity args, and exact ACL grantor/grantee/privilege/grant-option set',
  'Normalize routine owners, revoke PUBLIC/anon/authenticated/service_role/pdc_email_monitor from every noncanonical member, and restore only exact lowercase public canonical signatures',
  'Rollback-contained HERMES-TEST probes cover quoted mixed-case, overload/default, prefixed, alternate-schema, grant-option, named/default, and PostgREST exposure closure; production untouched'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
