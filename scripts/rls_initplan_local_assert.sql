-- Applies the forward migration and its rollback against the local fixture.
-- Proves row visibility is unchanged, auth.uid() stops running per row, and
-- the down script restores the previous expressions.
\set ON_ERROR_STOP on

CREATE OR REPLACE FUNCTION public.rls_probe_policies() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
 SELECT coalesce(jsonb_object_agg(key, expr), '{}'::jsonb)
 FROM (
  SELECT n.nspname || '.' || c.relname || '.' || pol.polname AS key,
         pg_get_expr(pol.polqual, pol.polrelid) AS expr
  FROM pg_policy pol
  JOIN pg_class c ON c.oid = pol.polrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname IN ('public','karratha135_pdc')
 ) s;
$$;

CREATE OR REPLACE FUNCTION public.rls_probe_read(p_role name) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SET search_path = pg_catalog, public, karratha135_pdc AS $$
DECLARE
 online int; parts int; nav int; k_online int; k_nav int;
BEGIN
 EXECUTE format('SET LOCAL ROLE %I', p_role);
 SELECT count(*) INTO online FROM public.pdc_online_state_revision;
 SELECT count(*) INTO parts FROM public.pdc14_parts_coordinator_role_history;
 SELECT count(*) INTO nav FROM public.navision_backend_revision;
 SELECT count(*) INTO k_online FROM karratha135_pdc.pdc_online_state_revision;
 SELECT count(*) INTO k_nav FROM karratha135_pdc.navision_backend_revision;
 RESET ROLE;
 RETURN jsonb_build_object('online', online, 'parts', parts, 'nav', nav, 'k_online', k_online, 'k_nav', k_nav);
EXCEPTION WHEN OTHERS THEN
 RESET ROLE;
 RAISE;
END $$;

CREATE OR REPLACE FUNCTION public.rls_probe_matrix() RETURNS jsonb
LANGUAGE plpgsql VOLATILE SET search_path = pg_catalog, public AS $$
DECLARE
 result jsonb := '{}'::jsonb;
 persona record;
BEGIN
 FOR persona IN
  SELECT * FROM (VALUES
   ('viewer', 'viewer', '11111111-1111-1111-1111-111111111111', 'false', ''),
   ('operator', 'operator', '22222222-2222-2222-2222-222222222222', 'false', ''),
   ('importer', 'importer', '33333333-3333-3333-3333-333333333333', 'false', ''),
   ('administrator', 'administrator', '44444444-4444-4444-4444-444444444444', 'false', ''),
   ('fitter_authorized', 'fitter', '55555555-5555-5555-5555-555555555555', 'true', ''),
   ('fitter_denied', 'fitter', '66666666-6666-6666-6666-666666666666', 'false', ''),
   ('inactive_administrator', 'administrator', '77777777-7777-7777-7777-777777777777', 'false', ''),
   ('viewer_without_uid', 'viewer', '', 'false', ''),
   ('viewer_k135_session', 'viewer', '11111111-1111-1111-1111-111111111111', 'false', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
   ('fitter_authorized_k135_session', 'fitter', '55555555-5555-5555-5555-555555555555', 'true', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
   ('administrator_k135_session', 'administrator', '44444444-4444-4444-4444-444444444444', 'false', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
  ) AS v(name, role, uid, authorized, session)
 LOOP
  PERFORM set_config('test.role', persona.role, true);
  PERFORM set_config('test.uid', persona.uid, true);
  PERFORM set_config('test.authorized', persona.authorized, true);
  PERFORM set_config('test.k135_session', persona.session, true);
  UPDATE public.rls_probe_counter SET calls = 0;
  result := result || jsonb_build_object(persona.name, public.rls_probe_read('authenticated'));
 END LOOP;
 PERFORM set_config('test.role', 'administrator', true);
 PERFORM set_config('test.uid', '44444444-4444-4444-4444-444444444444', true);
 result := result || jsonb_build_object('anon_with_admin_claims', public.rls_probe_read('anon'));
 RETURN result;
END $$;

CREATE OR REPLACE FUNCTION public.rls_probe_expect_matrix(actual jsonb) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
 totals jsonb;
 expected jsonb;
 name text;
BEGIN
 SELECT jsonb_build_object(
  'online', (SELECT count(*) FROM public.pdc_online_state_revision),
  'parts', (SELECT count(*) FROM public.pdc14_parts_coordinator_role_history),
  'nav', (SELECT count(*) FROM public.navision_backend_revision),
  'k_online', (SELECT count(*) FROM karratha135_pdc.pdc_online_state_revision),
  'k_nav', (SELECT count(*) FROM karratha135_pdc.navision_backend_revision)
 ) INTO totals;
 expected := jsonb_build_object(
  'viewer', jsonb_build_object('online', totals->'online', 'parts', to_jsonb(0), 'nav', totals->'nav', 'k_online', to_jsonb(0), 'k_nav', to_jsonb(0)),
  'operator', jsonb_build_object('online', totals->'online', 'parts', to_jsonb(0), 'nav', totals->'nav', 'k_online', to_jsonb(0), 'k_nav', to_jsonb(0)),
  'importer', jsonb_build_object('online', totals->'online', 'parts', to_jsonb(0), 'nav', totals->'nav', 'k_online', to_jsonb(0), 'k_nav', to_jsonb(0)),
  'administrator', jsonb_build_object('online', totals->'online', 'parts', totals->'parts', 'nav', totals->'nav', 'k_online', to_jsonb(0), 'k_nav', to_jsonb(0)),
  'fitter_authorized', jsonb_build_object('online', to_jsonb(0), 'parts', to_jsonb(0), 'nav', totals->'nav', 'k_online', to_jsonb(0), 'k_nav', to_jsonb(0)),
  'fitter_denied', jsonb_build_object('online', to_jsonb(0), 'parts', to_jsonb(0), 'nav', to_jsonb(0), 'k_online', to_jsonb(0), 'k_nav', to_jsonb(0)),
  'inactive_administrator', jsonb_build_object('online', totals->'online', 'parts', to_jsonb(0), 'nav', totals->'nav', 'k_online', to_jsonb(0), 'k_nav', to_jsonb(0)),
  'viewer_without_uid', jsonb_build_object('online', to_jsonb(0), 'parts', to_jsonb(0), 'nav', totals->'nav', 'k_online', to_jsonb(0), 'k_nav', to_jsonb(0)),
  'viewer_k135_session', jsonb_build_object('online', totals->'online', 'parts', to_jsonb(0), 'nav', totals->'nav', 'k_online', totals->'k_online', 'k_nav', totals->'k_nav'),
  'fitter_authorized_k135_session', jsonb_build_object('online', to_jsonb(0), 'parts', to_jsonb(0), 'nav', totals->'nav', 'k_online', to_jsonb(0), 'k_nav', totals->'k_nav'),
  'administrator_k135_session', jsonb_build_object('online', totals->'online', 'parts', totals->'parts', 'nav', totals->'nav', 'k_online', totals->'k_online', 'k_nav', totals->'k_nav'),
  'anon_with_admin_claims', jsonb_build_object('online', to_jsonb(0), 'parts', to_jsonb(0), 'nav', to_jsonb(0), 'k_online', to_jsonb(0), 'k_nav', to_jsonb(0))
 );
 FOR name IN SELECT jsonb_object_keys(expected) LOOP
  IF (actual->name)::jsonb IS DISTINCT FROM (expected->name)::jsonb THEN
   RAISE EXCEPTION 'access mismatch for %: actual % expected %', name, actual->name, expected->name;
  END IF;
 END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.rls_probe_plan(p_sql text) RETURNS text
LANGUAGE plpgsql VOLATILE SET search_path = pg_catalog, public AS $$
DECLARE
 line text;
 plan text := '';
BEGIN
 PERFORM set_config('test.role', 'administrator', true);
 PERFORM set_config('test.uid', '44444444-4444-4444-4444-444444444444', true);
 PERFORM set_config('test.authorized', 'false', true);
 PERFORM set_config('test.k135_session', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', true);
 SET LOCAL ROLE authenticated;
 FOR line IN EXECUTE 'EXPLAIN ' || p_sql LOOP
  plan := plan || line || E'\n';
 END LOOP;
 RESET ROLE;
 RETURN plan;
EXCEPTION WHEN OTHERS THEN
 RESET ROLE;
 RAISE;
END $$;

CREATE OR REPLACE FUNCTION public.rls_probe_timed(p_sql text, p_counter text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SET search_path = pg_catalog, public AS $$
DECLARE
 started timestamptz;
 calls bigint;
 seen bigint;
BEGIN
 UPDATE public.rls_probe_counter SET calls = 0;
 PERFORM set_config('test.role', 'administrator', true);
 PERFORM set_config('test.uid', '44444444-4444-4444-4444-444444444444', true);
 PERFORM set_config('test.authorized', 'false', true);
 PERFORM set_config('test.k135_session', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', true);
 SET LOCAL ROLE authenticated;
 started := clock_timestamp();
 EXECUTE 'SELECT count(*) FROM (' || p_sql || ') probe_rows' INTO seen;
 RESET ROLE;
 SELECT c.calls INTO calls FROM public.rls_probe_counter c WHERE c.name = p_counter;
 RETURN jsonb_build_object('rows', seen, 'calls', calls, 'ms', round(extract(epoch FROM clock_timestamp() - started) * 1000, 3));
EXCEPTION WHEN OTHERS THEN
 RESET ROLE;
 RAISE;
END $$;

CREATE TABLE IF NOT EXISTS public.rls_probe_saved (id text PRIMARY KEY, payload jsonb);
TRUNCATE public.rls_probe_saved;

INSERT INTO public.rls_probe_saved VALUES ('before_matrix', public.rls_probe_matrix());
SELECT public.rls_probe_expect_matrix((SELECT payload FROM public.rls_probe_saved WHERE id = 'before_matrix'));
INSERT INTO public.rls_probe_saved VALUES
 ('before_online', public.rls_probe_timed('SELECT 1 FROM public.pdc_online_state_revision', 'auth.uid')),
 ('before_parts', public.rls_probe_timed('SELECT 1 FROM public.pdc14_parts_coordinator_role_history', 'auth.uid')),
 ('before_nav_role', public.rls_probe_timed('SELECT 1 FROM public.navision_backend_revision', 'current_pdc_user_role')),
 ('before_nav_planner', public.rls_probe_timed('SELECT 1 FROM public.navision_backend_revision', 'workshop_is_planner_operator')),
 ('before_k_online', public.rls_probe_timed('SELECT 1 FROM karratha135_pdc.pdc_online_state_revision', 'auth.uid'));
INSERT INTO public.rls_probe_saved VALUES ('before_policies', public.rls_probe_policies());
INSERT INTO public.rls_probe_saved VALUES ('before_online_plan', to_jsonb(public.rls_probe_plan('SELECT count(*) FROM public.pdc_online_state_revision')));

\echo '--- forward must refuse a production sentinel ---'
CREATE TABLE public.pdc_production_environment_sentinel (id int);
\set ON_ERROR_STOP off
\i :forward
\if :ERROR
 \echo sentinel refusal ok
\else
 \echo sentinel refusal failed
 \quit 1
\endif
\set ON_ERROR_STOP on
DROP TABLE public.pdc_production_environment_sentinel;
DO $$
BEGIN
 IF (SELECT payload FROM public.rls_probe_saved WHERE id = 'before_policies')
    IS DISTINCT FROM public.rls_probe_policies() THEN
  RAISE EXCEPTION 'refused migration changed policies';
 END IF;
END $$;

\echo '--- forward must refuse when the staging guard is false ---'
CREATE OR REPLACE FUNCTION public.pdc_monitor_staging_guard() RETURNS boolean
LANGUAGE sql STABLE AS $$ SELECT false $$;
\set ON_ERROR_STOP off
\i :forward
\if :ERROR
 \echo guard refusal ok
\else
 \echo guard refusal failed
 \quit 1
\endif
\set ON_ERROR_STOP on
CREATE OR REPLACE FUNCTION public.pdc_monitor_staging_guard() RETURNS boolean
LANGUAGE sql STABLE AS $$ SELECT true $$;

\echo '--- forward ---'
\i :forward

SELECT public.rls_probe_expect_matrix(public.rls_probe_matrix());
DO $$
DECLARE
 after jsonb := public.rls_probe_matrix();
 before jsonb := (SELECT payload FROM public.rls_probe_saved WHERE id = 'before_matrix');
 name text;
BEGIN
 FOR name IN SELECT jsonb_object_keys(before) LOOP
  IF after->name IS DISTINCT FROM before->name THEN
   RAISE EXCEPTION 'forward changed access for % before % after %', name, before->name, after->name;
  END IF;
 END LOOP;
END $$;

INSERT INTO public.rls_probe_saved VALUES
 ('after_online', public.rls_probe_timed('SELECT 1 FROM public.pdc_online_state_revision', 'auth.uid')),
 ('after_parts', public.rls_probe_timed('SELECT 1 FROM public.pdc14_parts_coordinator_role_history', 'auth.uid')),
 ('after_nav_role', public.rls_probe_timed('SELECT 1 FROM public.navision_backend_revision', 'current_pdc_user_role')),
 ('after_nav_planner', public.rls_probe_timed('SELECT 1 FROM public.navision_backend_revision', 'workshop_is_planner_operator')),
 ('after_k_online', public.rls_probe_timed('SELECT 1 FROM karratha135_pdc.pdc_online_state_revision', 'auth.uid'));
INSERT INTO public.rls_probe_saved VALUES ('after_online_plan', to_jsonb(public.rls_probe_plan('SELECT count(*) FROM public.pdc_online_state_revision')));
INSERT INTO public.rls_probe_saved VALUES ('after_policies', public.rls_probe_policies());

DO $$
DECLARE
 before_online jsonb := (SELECT payload FROM public.rls_probe_saved WHERE id = 'before_online');
 after_online jsonb := (SELECT payload FROM public.rls_probe_saved WHERE id = 'after_online');
 before_k jsonb := (SELECT payload FROM public.rls_probe_saved WHERE id = 'before_k_online');
 after_k jsonb := (SELECT payload FROM public.rls_probe_saved WHERE id = 'after_k_online');
 before_nav_planner jsonb := (SELECT payload FROM public.rls_probe_saved WHERE id = 'before_nav_planner');
 after_nav_planner jsonb := (SELECT payload FROM public.rls_probe_saved WHERE id = 'after_nav_planner');
 plan text := (SELECT payload #>> '{}' FROM public.rls_probe_saved WHERE id = 'after_online_plan');
 policies jsonb := public.rls_probe_policies();
BEGIN
 IF (before_online->>'calls')::bigint < 500 THEN
  RAISE EXCEPTION 'fixture did not evaluate auth.uid per row before migration: %', before_online;
 END IF;
 IF (after_online->>'calls')::bigint > 5 THEN
  RAISE EXCEPTION 'auth.uid still evaluated per row after migration: %', after_online;
 END IF;
 IF (before_k->>'calls')::bigint < 100 OR (after_k->>'calls')::bigint > 5 THEN
  RAISE EXCEPTION 'karratha auth.uid calls before % after %', before_k, after_k;
 END IF;
 IF (after_online->>'rows')::bigint <> (before_online->>'rows')::bigint THEN
  RAISE EXCEPTION 'online row count changed';
 END IF;
 IF position('InitPlan' in plan) = 0 OR position('$0 IS NOT NULL' in plan) = 0 THEN
  RAISE EXCEPTION 'online plan has no auth.uid InitPlan: %', plan;
 END IF;
 IF policies ? 'public.navision_backend_revision.navision_backend_revision_planner_operator_select'
    OR policies ? 'karratha135_pdc.navision_backend_revision.navision_backend_revision_planner_operator_select' THEN
  RAISE EXCEPTION 'overlapping policy still present: %', policies;
 END IF;
 IF position('workshop_is_planner_operator()' in (policies->>'public.navision_backend_revision.navision_backend_revision_approved_read')) = 0 THEN
  RAISE EXCEPTION 'combined public policy lost the planner predicate';
 END IF;
 IF position('karratha135_pdc.workshop_is_planner_operator()' in (policies->>'karratha135_pdc.navision_backend_revision.navision_backend_revision_approved_read')) = 0 THEN
  RAISE EXCEPTION 'combined karratha policy lost the planner predicate';
 END IF;
 IF position('SELECT auth.uid()' in (policies->>'public.pdc_online_state_revision.pdc_online_state_revision_read')) = 0
    OR position('SELECT auth.uid()' in (policies->>'public.pdc14_parts_coordinator_role_history.PDC administrators can read role history')) = 0
    OR position('SELECT auth.uid()' in (policies->>'karratha135_pdc.pdc_online_state_revision.pdc_online_state_revision_read')) = 0 THEN
  RAISE EXCEPTION 'auth.uid was not wrapped: %', policies;
 END IF;
 IF NOT policies ? 'karratha135_pdc.navision_backend_revision.k135_verified_department_scope'
    OR NOT policies ? 'karratha135_pdc.pdc_online_state_revision.k135_verified_department_scope' THEN
  RAISE EXCEPTION 'restrictive karratha policy missing';
 END IF;
 IF (after_nav_planner->>'calls')::bigint > (before_nav_planner->>'calls')::bigint THEN
  RAISE EXCEPTION 'planner-operator calls increased before % after %', before_nav_planner, after_nav_planner;
 END IF;
 RAISE NOTICE 'timing online before % after %', before_online, after_online;
 RAISE NOTICE 'timing parts before % after %',
  (SELECT payload FROM public.rls_probe_saved WHERE id = 'before_parts'),
  (SELECT payload FROM public.rls_probe_saved WHERE id = 'after_parts');
 RAISE NOTICE 'timing nav role before % after %',
  (SELECT payload FROM public.rls_probe_saved WHERE id = 'before_nav_role'),
  (SELECT payload FROM public.rls_probe_saved WHERE id = 'after_nav_role');
 RAISE NOTICE 'timing nav planner before % after %', before_nav_planner, after_nav_planner;
 RAISE NOTICE 'timing karratha online before % after %', before_k, after_k;
END $$;

\echo '--- second forward must stop because the reviewed expressions changed ---'
\set ON_ERROR_STOP off
\i :forward
\if :ERROR
 \echo second forward refusal ok
\else
 \echo second forward unexpectedly applied
 \quit 1
\endif
\set ON_ERROR_STOP on
DO $$
BEGIN
 IF public.rls_probe_policies() IS DISTINCT FROM (SELECT payload FROM public.rls_probe_saved WHERE id = 'after_policies') THEN
  RAISE EXCEPTION 'rejected re-apply changed policies';
 END IF;
END $$;

\echo '--- rollback ---'
\i :down
SELECT public.rls_probe_expect_matrix(public.rls_probe_matrix());
DO $$
DECLARE
 policies jsonb := public.rls_probe_policies();
 before jsonb := (SELECT payload FROM public.rls_probe_saved WHERE id = 'before_policies');
 key text;
BEGIN
 FOREACH key IN ARRAY ARRAY[
  'public.pdc_online_state_revision.pdc_online_state_revision_read',
  'public.pdc14_parts_coordinator_role_history.PDC administrators can read role history',
  'karratha135_pdc.pdc_online_state_revision.pdc_online_state_revision_read',
  'public.navision_backend_revision.navision_backend_revision_approved_read',
  'public.navision_backend_revision.navision_backend_revision_planner_operator_select',
  'karratha135_pdc.navision_backend_revision.navision_backend_revision_approved_read',
  'karratha135_pdc.navision_backend_revision.navision_backend_revision_planner_operator_select'
 ] LOOP
  IF policies->>key IS DISTINCT FROM before->>key THEN
   RAISE EXCEPTION 'rollback expression for % is % expected %', key, policies->>key, before->>key;
  END IF;
 END LOOP;
 IF NOT policies ? 'karratha135_pdc.navision_backend_revision.k135_verified_department_scope' THEN
  RAISE EXCEPTION 'rollback dropped the restrictive policy';
 END IF;
END $$;

\echo '--- forward again after rollback ---'
\i :forward
SELECT public.rls_probe_expect_matrix(public.rls_probe_matrix());
INSERT INTO public.rls_probe_saved VALUES
 ('reapplied_online', public.rls_probe_timed('SELECT 1 FROM public.pdc_online_state_revision', 'auth.uid'));
DO $$
BEGIN
 IF ((SELECT payload->>'calls' FROM public.rls_probe_saved WHERE id = 'reapplied_online')::bigint) > 5 THEN
  RAISE EXCEPTION 'reapplied migration did not keep the initplan';
 END IF;
END $$;

\echo 'RLS initplan local check passed'
SELECT id, payload FROM public.rls_probe_saved WHERE id LIKE '%online' OR id LIKE 'before_nav%' OR id LIKE 'after_nav%' ORDER BY id;
