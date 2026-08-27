-- STAGING ONLY 716: close every raw ACL grantee in the Navision routine families.
--
-- This is an append-only successor to the exact approved candidate
-- 5d60baa07f32d696e3d494fad8be00dcb579fff4 / tree
-- 45932e116e25d06f64f7df8c265bf43f223b671d. Preserve 700-715, and never
-- rewrite, reapply, reset, or touch production. The 715 source digest is
-- 1df478da87e0c5ddb3735ce5489246251f91fc877ebc7700403630e62fca461d.
-- Every raw ACL entry is inventoried by aclexplode. Explicit grantees are
-- revoked dynamically by safely quoted role name; only the owner and the
-- exact canonical authenticated grant are restored. Hostile role probes are
-- transaction-contained and must leave no role or ACL residue.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-716-close-all-raw-navision-acl-grantees',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guards$
DECLARE
  v_delivery_hash text;
  v_wrapper_hash text;
  v_body_hash text;
BEGIN
  IF current_user<>'postgres'
     OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR lower(coalesce(current_setting('app.environment',true),''))='production'
  THEN RAISE EXCEPTION 'PDC_716_STAGING_SENTINEL_OR_ROLE_FAILED' USING errcode='55000'; END IF;

  IF (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260828030000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations
         WHERE version='20260828030000' AND name='715_remove_leaked_navision_714_test_probes')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations
               WHERE version~'^[0-9]{14}$' AND version>'20260828030000')
  THEN RAISE EXCEPTION 'PDC_716_EXACT_LIVE_HEAD_REQUIRED' USING errcode='55000'; END IF;

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
      ('20260827118000','713_close_navision_prefixed_family_acl_bypass'),
      ('20260828000000','682_uid514_capability_consumption_repair'),
      ('20260828010000','683_uid514_capability_mint_replay_repair'),
      ('20260828020000','714_fail_closed_navision_family_catalog_hardening'),
      ('20260828030000','715_remove_leaked_navision_714_test_probes')
    ) AS expected(version,name)
    WHERE NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations m
                      WHERE m.version=expected.version AND m.name=expected.name))<>0
  THEN RAISE EXCEPTION 'PDC_716_PRESERVED_700_715_CHAIN_REQUIRED' USING errcode='55000'; END IF;

  IF to_regprocedure('public.reconcile_navision_delivery_700(uuid)') IS NULL
     OR to_regprocedure('public.reconcile_navision_operational_record(uuid,uuid,text)') IS NULL
     OR to_regprocedure('public.process_pdc_monitor_body_location_20260821033000(uuid,uuid,text,uuid,integer,integer,text,text,date,timestamptz,text)') IS NULL
  THEN RAISE EXCEPTION 'PDC_716_REQUIRED_CANONICAL_ROUTINE_MISSING' USING errcode='55000'; END IF;

  SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.reconcile_navision_delivery_700(uuid)'::regprocedure),'UTF8'),'sha256'),'hex') INTO v_delivery_hash;
  SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.reconcile_navision_operational_record(uuid,uuid,text)'::regprocedure),'UTF8'),'sha256'),'hex') INTO v_wrapper_hash;
  SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.process_pdc_monitor_body_location_20260821033000(uuid,uuid,text,uuid,integer,integer,text,text,date,timestamptz,text)'::regprocedure),'UTF8'),'sha256'),'hex') INTO v_body_hash;
  IF v_delivery_hash<>'3b84fa28b6f698f964e85177dde20af1d4c8b11fe25d74ee3d6aa7adc59837fb'
     OR v_wrapper_hash<>'6159ed3eb28fd4222321a80951edfb30c687e7c196a2ee20fce2679e7444826a'
     OR v_body_hash<>'f703c7f95b29bb75f2208411f987ab81ee6aaa8c7e42a2630b3cd85fd9eeaf08'
  THEN RAISE EXCEPTION 'PDC_716_CANONICAL_FUNCTION_HASH_MISMATCH' USING errcode='55000'; END IF;
END $guards$;

CREATE TEMP TABLE pdc_716_targets(
  proc_oid oid PRIMARY KEY,
  signature text NOT NULL,
  schema_name name NOT NULL,
  proname name NOT NULL,
  is_canonical boolean NOT NULL
) ON COMMIT DROP;

INSERT INTO pdc_716_targets(proc_oid,signature,schema_name,proname,is_canonical)
SELECT p.oid,
  format('%I.%I(%s)',n.nspname,p.proname,pg_get_function_identity_arguments(p.oid)),
  n.nspname,p.proname,
  p.oid IN (
    'public.reconcile_navision_delivery_700(uuid)'::regprocedure,
    'public.reconcile_navision_operational_record(uuid,uuid,text)'::regprocedure,
    'public.process_pdc_monitor_body_location_20260821033000(uuid,uuid,text,uuid,integer,integer,text,text,date,timestamp with time zone,text)'::regprocedure)
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname !~ '^pg_' AND n.nspname<>'information_schema'
  AND lower(p.proname) LIKE ANY(ARRAY[
    'reconcile_navision_delivery_700%',
    'reconcile_navision_operational_record%',
    'process_pdc_monitor_body_location_20260821033000%']);

DO $target_guard$
BEGIN
  IF (SELECT count(*) FROM pdc_716_targets)<>
       (SELECT count(*) FROM pdc_716_targets WHERE is_canonical)+7
     OR (SELECT count(*) FROM pdc_716_targets WHERE is_canonical)<>3
     OR EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
               WHERE n.nspname !~ '^pg_' AND n.nspname<>'information_schema'
                 AND lower(p.proname) LIKE ANY(ARRAY[
                   'reconcile_navision_delivery_700%',
                   'reconcile_navision_operational_record%',
                   'process_pdc_monitor_body_location_20260821033000%'])
                 AND p.prokind NOT IN ('f','p'))
  THEN RAISE EXCEPTION 'PDC_716_TARGET_FAMILY_OR_PROKIND_UNKNOWN' USING errcode='55000'; END IF;
END $target_guard$;

-- A quoted arbitrary role gets direct EXECUTE plus grant option on both sides
-- of the canonical boundary before the pre-inventory. The successor must
-- remove it dynamically, not merely revoke the five well-known roles.
CREATE ROLE "HERMES-TEST-716-ACL" NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
DO $hostile_grant$
DECLARE
  v_noncanonical text;
BEGIN
  SELECT signature INTO v_noncanonical FROM pdc_716_targets WHERE NOT is_canonical ORDER BY proc_oid LIMIT 1;
  IF v_noncanonical IS NULL THEN RAISE EXCEPTION 'PDC_716_HOSTILE_NONCANONICAL_TARGET_MISSING' USING errcode='55000'; END IF;
  EXECUTE 'GRANT EXECUTE ON ROUTINE public.reconcile_navision_delivery_700(uuid) TO "HERMES-TEST-716-ACL" WITH GRANT OPTION';
  EXECUTE format('GRANT EXECUTE ON ROUTINE %s TO "HERMES-TEST-716-ACL" WITH GRANT OPTION',v_noncanonical);
END $hostile_grant$;

CREATE TABLE public.pdc_navision_raw_acl_inventory_716(
  migration_version text NOT NULL,
  phase text NOT NULL CHECK(phase IN('pre','post')),
  proc_oid oid NOT NULL,
  schema_name name NOT NULL,
  proname name NOT NULL,
  signature text NOT NULL,
  is_canonical boolean NOT NULL,
  owner_name name NOT NULL,
  prokind "char" NOT NULL,
  security_definer boolean NOT NULL,
  volatility "char" NOT NULL,
  has_defaults boolean NOT NULL,
  proconfig text[] NOT NULL,
  raw_acl text NOT NULL,
  acl_grantor oid NOT NULL,
  acl_grantee oid NOT NULL,
  acl_grantor_name name NOT NULL,
  acl_grantee_name name NOT NULL,
  privilege_type text NOT NULL,
  is_grantable boolean NOT NULL,
  captured_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(phase,proc_oid,acl_grantor,acl_grantee,privilege_type,is_grantable)
);
ALTER TABLE public.pdc_navision_raw_acl_inventory_716 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_navision_raw_acl_inventory_716 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_navision_raw_acl_inventory_716 FROM public,anon,authenticated,service_role,pdc_email_monitor;

INSERT INTO public.pdc_navision_raw_acl_inventory_716(
  migration_version,phase,proc_oid,schema_name,proname,signature,is_canonical,
  owner_name,prokind,security_definer,volatility,has_defaults,proconfig,raw_acl,
  acl_grantor,acl_grantee,acl_grantor_name,acl_grantee_name,privilege_type,is_grantable)
SELECT '20260828040000','pre',t.proc_oid,t.schema_name,t.proname,t.signature,t.is_canonical,
  r.rolname,p.prokind,p.prosecdef,p.provolatile,p.proargdefaults IS NOT NULL,
  coalesce(p.proconfig,'{}'::text[]),coalesce(p.proacl,acldefault('f',p.proowner))::text,
  a.grantor,a.grantee,
  CASE WHEN a.grantor=0 THEN 'PUBLIC'::name ELSE pg_get_userbyid(a.grantor) END,
  CASE WHEN a.grantee=0 THEN 'PUBLIC'::name ELSE pg_get_userbyid(a.grantee) END,
  a.privilege_type,a.is_grantable
FROM pdc_716_targets t
JOIN pg_proc p ON p.oid=t.proc_oid
JOIN pg_roles r ON r.oid=p.proowner
CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a;

DO $pre_guard$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM public.pdc_navision_raw_acl_inventory_716
                WHERE phase='pre' AND acl_grantee_name='HERMES-TEST-716-ACL'
                  AND privilege_type='EXECUTE' AND is_grantable)
  THEN RAISE EXCEPTION 'PDC_716_HOSTILE_RAW_GRANT_NOT_CAPTURED' USING errcode='55000'; END IF;
END $pre_guard$;

-- Revoke every explicit grantee found in the raw ACL, not a fixed role list.
-- Owner rights remain intrinsic. The role identifier is passed through %I so
-- quoted/arbitrary role names cannot become SQL text.
DO $revoke_every_raw_grantee$
DECLARE
  t record;
  a record;
BEGIN
  FOR t IN SELECT * FROM pdc_716_targets ORDER BY proc_oid LOOP
    EXECUTE format('ALTER ROUTINE %s OWNER TO postgres',t.signature);
    FOR a IN
      SELECT x.grantee,
             CASE WHEN x.grantee=0 THEN 'PUBLIC'::name ELSE pg_get_userbyid(x.grantee) END AS grantee_name
      FROM pg_proc p
      CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) x
      WHERE p.oid=t.proc_oid AND x.grantee<>p.proowner
    LOOP
      IF a.grantee<>0 AND a.grantee_name IS NULL
      THEN RAISE EXCEPTION 'PDC_716_UNKNOWN_RAW_ACL_GRANTEE:%',t.signature USING errcode='55000'; END IF;
      IF a.grantee=0 THEN
        EXECUTE format('REVOKE ALL ON ROUTINE %s FROM PUBLIC',t.signature);
      ELSE
        EXECUTE format('REVOKE ALL ON ROUTINE %s FROM %I',t.signature,a.grantee_name);
      END IF;
    END LOOP;
  END LOOP;
END $revoke_every_raw_grantee$;

GRANT EXECUTE ON FUNCTION public.reconcile_navision_delivery_700(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reconcile_navision_operational_record(uuid,uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.process_pdc_monitor_body_location_20260821033000(uuid,uuid,text,uuid,integer,integer,text,text,date,timestamptz,text) TO authenticated;

INSERT INTO public.pdc_navision_raw_acl_inventory_716(
  migration_version,phase,proc_oid,schema_name,proname,signature,is_canonical,
  owner_name,prokind,security_definer,volatility,has_defaults,proconfig,raw_acl,
  acl_grantor,acl_grantee,acl_grantor_name,acl_grantee_name,privilege_type,is_grantable)
SELECT '20260828040000','post',t.proc_oid,t.schema_name,t.proname,t.signature,t.is_canonical,
  r.rolname,p.prokind,p.prosecdef,p.provolatile,p.proargdefaults IS NOT NULL,
  coalesce(p.proconfig,'{}'::text[]),coalesce(p.proacl,acldefault('f',p.proowner))::text,
  a.grantor,a.grantee,
  CASE WHEN a.grantor=0 THEN 'PUBLIC'::name ELSE pg_get_userbyid(a.grantor) END,
  CASE WHEN a.grantee=0 THEN 'PUBLIC'::name ELSE pg_get_userbyid(a.grantee) END,
  a.privilege_type,a.is_grantable
FROM pdc_716_targets t
JOIN pg_proc p ON p.oid=t.proc_oid
JOIN pg_roles r ON r.oid=p.proowner
CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a;

DO $postconditions$
BEGIN
  IF (SELECT count(DISTINCT proc_oid) FROM public.pdc_navision_raw_acl_inventory_716 WHERE phase='pre')<>(SELECT count(*) FROM pdc_716_targets)
     OR (SELECT count(DISTINCT proc_oid) FROM public.pdc_navision_raw_acl_inventory_716 WHERE phase='post')<>(SELECT count(*) FROM pdc_716_targets)
  THEN RAISE EXCEPTION 'PDC_716_COMPLETE_RAW_ACL_INVENTORY_FAILED' USING errcode='55000'; END IF;

  IF EXISTS(SELECT 1 FROM public.pdc_navision_raw_acl_inventory_716
            WHERE phase='post' AND (owner_name<>'postgres' OR acl_grantor_name<>'postgres' OR is_grantable
               OR (is_canonical AND acl_grantee_name NOT IN ('postgres','authenticated'))
               OR (NOT is_canonical AND acl_grantee_name<>'postgres')))
  THEN RAISE EXCEPTION 'PDC_716_UNKNOWN_OR_GRANTABLE_RAW_ACL_ENTRY' USING errcode='55000'; END IF;

  IF EXISTS(SELECT 1 FROM public.pdc_navision_raw_acl_inventory_716
            WHERE phase='post' AND is_canonical AND NOT
              ((acl_grantee_name='postgres' AND privilege_type='EXECUTE' AND NOT is_grantable)
               OR (acl_grantee_name='authenticated' AND privilege_type='EXECUTE' AND NOT is_grantable)))
     OR EXISTS(SELECT 1 FROM public.pdc_navision_raw_acl_inventory_716
               WHERE phase='post' AND NOT is_canonical AND NOT
                 (acl_grantee_name='postgres' AND privilege_type='EXECUTE' AND NOT is_grantable))
  THEN RAISE EXCEPTION 'PDC_716_RAW_ACL_NORMALIZATION_FAILED' USING errcode='55000'; END IF;

  IF EXISTS(SELECT 1 FROM pdc_716_targets t
            WHERE (SELECT count(*) FROM public.pdc_navision_raw_acl_inventory_716 i
                   WHERE i.phase='post' AND i.proc_oid=t.proc_oid)
                  <>CASE WHEN t.is_canonical THEN 2 ELSE 1 END)
     OR (SELECT count(*) FROM public.pdc_navision_raw_acl_inventory_716
         WHERE phase='post' AND is_canonical)<>6
  THEN RAISE EXCEPTION 'PDC_716_RAW_ACL_CARDINALITY_FAILED' USING errcode='55000'; END IF;

  IF EXISTS(SELECT 1 FROM public.pdc_navision_raw_acl_inventory_716
            WHERE phase='post' AND acl_grantee_name='HERMES-TEST-716-ACL')
     OR EXISTS(SELECT 1 FROM pdc_716_targets t
               WHERE has_function_privilege('HERMES-TEST-716-ACL',t.proc_oid,'execute'))
  THEN RAISE EXCEPTION 'PDC_716_ARBITRARY_ROLE_EXECUTE_SURVIVED' USING errcode='55000'; END IF;

  IF EXISTS(SELECT 1 FROM public.pdc_navision_raw_acl_inventory_716
            WHERE phase='post' AND is_canonical
              AND (schema_name<>'public' OR owner_name<>'postgres' OR prokind<>'f'
                   OR NOT security_definer OR volatility<>'v' OR has_defaults
                   OR (proname='reconcile_navision_delivery_700' AND proconfig<>
                       ARRAY['search_path=pg_catalog, public, auth, extensions','statement_timeout=120s'])
                   OR (proname='reconcile_navision_operational_record' AND proconfig<>
                       ARRAY['search_path=pg_catalog, public, auth, extensions'])
                   OR (proname='process_pdc_monitor_body_location_20260821033000' AND proconfig<>
                       ARRAY['search_path=pg_catalog, public, extensions, auth'])))
  THEN RAISE EXCEPTION 'PDC_716_CANONICAL_SCHEMA_DEFAULT_CONFIG_OWNER_DRIFT' USING errcode='55000'; END IF;

  IF (SELECT count(*) FROM pdc_716_targets WHERE is_canonical)<>3
     OR (SELECT count(*) FROM public.pdc_navision_raw_acl_inventory_716 WHERE phase='post' AND is_canonical)<>6
     OR EXISTS(SELECT 1 FROM public.pdc_navision_raw_acl_inventory_716
               WHERE phase='post' AND NOT is_canonical
                 AND (acl_grantee_name<>'postgres' OR privilege_type<>'EXECUTE' OR is_grantable))
  THEN RAISE EXCEPTION 'PDC_716_ALTERNATE_MIXED_CASE_OVERLOAD_DEFAULT_CLOSED_FAILED' USING errcode='55000'; END IF;
END $postconditions$;

-- The hostile quoted role existed long enough to be captured in pre, had
-- EXECUTE+grant-option direct ACLs removed, and is now transaction-clean.
DROP ROLE "HERMES-TEST-716-ACL";
DO $cleanup_guard$
BEGIN
  IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='HERMES-TEST-716-ACL')
  THEN RAISE EXCEPTION 'PDC_716_HOSTILE_ROLE_RESIDUE' USING errcode='55000'; END IF;
END $cleanup_guard$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260828040000','716_close_all_raw_navision_acl_grantees',ARRAY[
  'Exact source guard: approved candidate commit 5d60baa07f32d696e3d494fad8be00dcb579fff4 / tree 45932e116e25d06f64f7df8c265bf43f223b671d; preserve 700-715',
  'Exact live head guard: 20260828030000 / 715_remove_leaked_navision_714_test_probes plus canonical function SHA-256 guards',
  'Inventory every aclexplode raw ACL entry for every case-insensitive family routine across every non-system schema',
  'Dynamically and safely revoke ALL from every explicit grantee except owner, remove grant options, restore only exact canonical authenticated EXECUTE, and normalize raw ACL cardinality',
  'Quoted arbitrary-role EXECUTE/grant-option hostile probe is captured pre, removed post, denied, and dropped before commit; no vehicle or user-data mutation'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
