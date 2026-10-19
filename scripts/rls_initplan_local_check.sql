-- Local-only fixture for 20261019140000_rls_auth_initplan_and_overlapping_policies.
-- Not a replay of the live schema. Creates the five reviewed policies, applies the
-- forward migration, checks access and auth.uid() call counts, rolls back, and
-- checks the original expressions and access again.
-- Run as a superuser against an empty database. Never point this at staging.

\set ON_ERROR_STOP on

CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS karratha135_pdc;

CREATE TABLE IF NOT EXISTS public.rls_probe_counter (
 name text PRIMARY KEY,
 calls bigint NOT NULL DEFAULT 0
);
TRUNCATE public.rls_probe_counter;
INSERT INTO public.rls_probe_counter (name) VALUES
 ('auth.uid'), ('current_pdc_user_role'), ('workshop_is_planner_operator'),
 ('karratha.current_pdc_user_role'), ('karratha.workshop_is_planner_operator'),
 ('is_pdc_role'), ('karratha.is_pdc_role');

CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, public AS $$
BEGIN
 UPDATE public.rls_probe_counter SET calls = calls + 1 WHERE name = 'auth.uid';
 RETURN nullif(current_setting('test.uid', true), '')::uuid;
END $$;

CREATE OR REPLACE FUNCTION public.pdc_monitor_staging_guard() RETURNS boolean
LANGUAGE sql STABLE AS $$ SELECT true $$;

DO $$ BEGIN
 CREATE TYPE public.pdc_role AS ENUM ('viewer','operator','importer','administrator','fitter');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
 CREATE TYPE karratha135_pdc.pdc_role AS ENUM ('viewer','operator','importer','administrator','fitter');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS public.pdc_user_roles (
 auth_user_id uuid,
 active boolean,
 role public.pdc_role
);
CREATE TABLE IF NOT EXISTS public.pdc_online_state_revision (id int PRIMARY KEY);
CREATE TABLE IF NOT EXISTS public.pdc14_parts_coordinator_role_history (id int PRIMARY KEY);
CREATE TABLE IF NOT EXISTS public.navision_backend_revision (id int PRIMARY KEY);
CREATE TABLE IF NOT EXISTS karratha135_pdc.pdc_online_state_revision (id int PRIMARY KEY);
CREATE TABLE IF NOT EXISTS karratha135_pdc.navision_backend_revision (id int PRIMARY KEY);

TRUNCATE public.pdc_user_roles, public.pdc_online_state_revision, public.pdc14_parts_coordinator_role_history,
 public.navision_backend_revision, karratha135_pdc.pdc_online_state_revision, karratha135_pdc.navision_backend_revision;

INSERT INTO public.pdc_user_roles (auth_user_id, active, role) VALUES
 ('11111111-1111-1111-1111-111111111111', true, 'viewer'),
 ('22222222-2222-2222-2222-222222222222', true, 'operator'),
 ('33333333-3333-3333-3333-333333333333', true, 'importer'),
 ('44444444-4444-4444-4444-444444444444', true, 'administrator'),
 ('55555555-5555-5555-5555-555555555555', true, 'fitter'),
 ('66666666-6666-6666-6666-666666666666', true, 'fitter'),
 ('77777777-7777-7777-7777-777777777777', false, 'administrator');

INSERT INTO public.pdc_online_state_revision (id) SELECT g FROM generate_series(1, 2000) g;
INSERT INTO public.pdc14_parts_coordinator_role_history (id) SELECT g FROM generate_series(1, 2000) g;
INSERT INTO public.navision_backend_revision (id) SELECT g FROM generate_series(1, 1000) g;
INSERT INTO karratha135_pdc.pdc_online_state_revision (id) SELECT g FROM generate_series(1, 300) g;
INSERT INTO karratha135_pdc.navision_backend_revision (id) SELECT g FROM generate_series(1, 300) g;

-- VOLATILE on purpose so a counter can prove per-row evaluation.
-- The live helpers are STABLE. This fixture measures the policy shape, not those function bodies.
CREATE OR REPLACE FUNCTION public.is_pdc_role(requested public.pdc_role) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
 UPDATE public.rls_probe_counter SET calls = calls + 1 WHERE name = 'is_pdc_role';
 RETURN requested = 'viewer'::public.pdc_role
  AND current_setting('test.role', true) IN ('viewer','operator','importer','administrator');
END $$;

CREATE OR REPLACE FUNCTION public.current_pdc_user_role() RETURNS public.pdc_role
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
 UPDATE public.rls_probe_counter SET calls = calls + 1 WHERE name = 'current_pdc_user_role';
 RETURN nullif(current_setting('test.role', true), '')::public.pdc_role;
END $$;

CREATE OR REPLACE FUNCTION public.workshop_is_planner_operator() RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
 UPDATE public.rls_probe_counter SET calls = calls + 1 WHERE name = 'workshop_is_planner_operator';
 RETURN current_setting('test.role', true) IN ('operator','administrator')
  OR (current_setting('test.role', true) = 'fitter' AND current_setting('test.authorized', true) = 'true');
END $$;

CREATE OR REPLACE FUNCTION karratha135_pdc.is_pdc_role(requested karratha135_pdc.pdc_role) RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
 UPDATE public.rls_probe_counter SET calls = calls + 1 WHERE name = 'karratha.is_pdc_role';
 RETURN requested = 'viewer'::karratha135_pdc.pdc_role
  AND current_setting('test.role', true) IN ('viewer','operator','importer','administrator');
END $$;

CREATE OR REPLACE FUNCTION karratha135_pdc.current_pdc_user_role() RETURNS karratha135_pdc.pdc_role
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
 UPDATE public.rls_probe_counter SET calls = calls + 1 WHERE name = 'karratha.current_pdc_user_role';
 RETURN nullif(current_setting('test.role', true), '')::karratha135_pdc.pdc_role;
END $$;

CREATE OR REPLACE FUNCTION karratha135_pdc.workshop_is_planner_operator() RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
 UPDATE public.rls_probe_counter SET calls = calls + 1 WHERE name = 'karratha.workshop_is_planner_operator';
 RETURN current_setting('test.role', true) IN ('operator','administrator')
  OR (current_setting('test.role', true) = 'fitter' AND current_setting('test.authorized', true) = 'true');
END $$;

CREATE OR REPLACE FUNCTION karratha135_pdc.require_active_session_135() RETURNS uuid
LANGUAGE sql STABLE AS $$
 SELECT nullif(current_setting('test.k135_session', true), '')::uuid
$$;

DO $$ BEGIN
 CREATE ROLE authenticated NOLOGIN NOSUPERUSER NOBYPASSRLS;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
 CREATE ROLE anon NOLOGIN NOSUPERUSER NOBYPASSRLS;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

GRANT USAGE ON SCHEMA public, auth, karratha135_pdc TO authenticated, anon;
GRANT SELECT ON public.pdc_online_state_revision, public.pdc14_parts_coordinator_role_history,
 public.navision_backend_revision, public.pdc_user_roles, karratha135_pdc.pdc_online_state_revision,
 karratha135_pdc.navision_backend_revision TO authenticated, anon;
GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated, anon;

ALTER TABLE public.pdc_online_state_revision ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc14_parts_coordinator_role_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.navision_backend_revision ENABLE ROW LEVEL SECURITY;
ALTER TABLE karratha135_pdc.pdc_online_state_revision ENABLE ROW LEVEL SECURITY;
ALTER TABLE karratha135_pdc.navision_backend_revision ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_online_state_revision FORCE ROW LEVEL SECURITY;
ALTER TABLE public.pdc14_parts_coordinator_role_history FORCE ROW LEVEL SECURITY;
ALTER TABLE public.navision_backend_revision FORCE ROW LEVEL SECURITY;
ALTER TABLE karratha135_pdc.pdc_online_state_revision FORCE ROW LEVEL SECURITY;
ALTER TABLE karratha135_pdc.navision_backend_revision FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pdc_online_state_revision_read ON public.pdc_online_state_revision;
CREATE POLICY pdc_online_state_revision_read ON public.pdc_online_state_revision
 AS PERMISSIVE FOR SELECT TO authenticated
 USING (((auth.uid() IS NOT NULL) AND is_pdc_role('viewer'::pdc_role)));

DROP POLICY IF EXISTS "PDC administrators can read role history" ON public.pdc14_parts_coordinator_role_history;
CREATE POLICY "PDC administrators can read role history" ON public.pdc14_parts_coordinator_role_history
 AS PERMISSIVE FOR SELECT TO authenticated
 USING (EXISTS ( SELECT 1
  FROM pdc_user_roles r
 WHERE ((r.auth_user_id = auth.uid()) AND r.active AND (lower((r.role)::text) = 'administrator'::text))));

DROP POLICY IF EXISTS pdc_online_state_revision_read ON karratha135_pdc.pdc_online_state_revision;
CREATE POLICY pdc_online_state_revision_read ON karratha135_pdc.pdc_online_state_revision
 AS PERMISSIVE FOR SELECT TO authenticated
 USING (((auth.uid() IS NOT NULL) AND karratha135_pdc.is_pdc_role('viewer'::karratha135_pdc.pdc_role)));

DROP POLICY IF EXISTS navision_backend_revision_approved_read ON public.navision_backend_revision;
DROP POLICY IF EXISTS navision_backend_revision_planner_operator_select ON public.navision_backend_revision;
CREATE POLICY navision_backend_revision_approved_read ON public.navision_backend_revision
 AS PERMISSIVE FOR SELECT TO authenticated
 USING (COALESCE(((current_pdc_user_role())::text = ANY (ARRAY['viewer'::text, 'operator'::text, 'importer'::text, 'administrator'::text])), false));
CREATE POLICY navision_backend_revision_planner_operator_select ON public.navision_backend_revision
 AS PERMISSIVE FOR SELECT TO authenticated
 USING (workshop_is_planner_operator());

DROP POLICY IF EXISTS navision_backend_revision_approved_read ON karratha135_pdc.navision_backend_revision;
DROP POLICY IF EXISTS navision_backend_revision_planner_operator_select ON karratha135_pdc.navision_backend_revision;
CREATE POLICY navision_backend_revision_approved_read ON karratha135_pdc.navision_backend_revision
 AS PERMISSIVE FOR SELECT TO authenticated
 USING (COALESCE(((karratha135_pdc.current_pdc_user_role())::text = ANY (ARRAY['viewer'::text, 'operator'::text, 'importer'::text, 'administrator'::text])), false));
CREATE POLICY navision_backend_revision_planner_operator_select ON karratha135_pdc.navision_backend_revision
 AS PERMISSIVE FOR SELECT TO authenticated
 USING (karratha135_pdc.workshop_is_planner_operator());

DROP POLICY IF EXISTS k135_verified_department_scope ON karratha135_pdc.navision_backend_revision;
CREATE POLICY k135_verified_department_scope ON karratha135_pdc.navision_backend_revision
 AS RESTRICTIVE FOR SELECT TO authenticated
 USING (karratha135_pdc.require_active_session_135() IS NOT NULL);
DROP POLICY IF EXISTS k135_verified_department_scope ON karratha135_pdc.pdc_online_state_revision;
CREATE POLICY k135_verified_department_scope ON karratha135_pdc.pdc_online_state_revision
 AS RESTRICTIVE FOR SELECT TO authenticated
 USING (karratha135_pdc.require_active_session_135() IS NOT NULL);
