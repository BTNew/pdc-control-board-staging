-- r484 (F97) local harness stubs: a throwaway local PostgreSQL database with just enough of staging for the Revolution report
-- sign-in check, its pin, the regression check table and the parts import gate. Never connects to Supabase. Synthetic data only.
DROP DATABASE IF EXISTS r484h;
CREATE DATABASE r484h;
\c r484h
DO $$BEGIN CREATE ROLE anon; EXCEPTION WHEN duplicate_object THEN NULL; END$$;
DO $$BEGIN CREATE ROLE authenticated; EXCEPTION WHEN duplicate_object THEN NULL; END$$;
DO $$BEGIN CREATE ROLE service_role; EXCEPTION WHEN duplicate_object THEN NULL; END$$;
CREATE SCHEMA pdc_ops; CREATE SCHEMA pdc_codex_intake_private; CREATE SCHEMA pdc_parts_private; CREATE SCHEMA extensions;
CREATE TABLE pdc_ops.expected_function_md5(signature text PRIMARY KEY, prosrc_md5 text NOT NULL CHECK (prosrc_md5 ~ '^[0-9a-f]{32}$'), release text, note text, updated_at timestamptz);
CREATE TABLE pdc_ops.regression_checks(check_name text PRIMARY KEY CHECK (check_name ~ '^[a-z0-9_]+$'), fault_id text NOT NULL, description text NOT NULL,
  check_sql text NOT NULL, enabled boolean NOT NULL DEFAULT true, sort_order integer NOT NULL, added_in text NOT NULL);
CREATE TABLE public.pdc_staging_environment_sentinel(singleton boolean NOT NULL DEFAULT true, project_ref text NOT NULL, installed_at timestamptz NOT NULL DEFAULT now());
INSERT INTO public.pdc_staging_environment_sentinel(project_ref) VALUES ('cdsmnqxtyyoeoznmbidd');
CREATE FUNCTION public.pdc_monitor_staging_guard() RETURNS boolean LANGUAGE sql STABLE AS $$select true$$;
CREATE FUNCTION pdc_codex_intake_private.management_connection() RETURNS boolean LANGUAGE sql STABLE AS $$select true$$;
CREATE FUNCTION public.workshop_clock_tick(boolean, timestamptz) RETURNS void LANGUAGE sql AS $$select$$;
CREATE FUNCTION pdc_ops.fault_regression_check() RETURNS void LANGUAGE sql AS $$select$$;
INSERT INTO pdc_ops.expected_function_md5(signature,prosrc_md5,release) SELECT 'public.workshop_clock_tick(boolean,timestamp with time zone)',md5(prosrc),'stub' FROM pg_proc WHERE proname='workshop_clock_tick';
-- The live pin check (verbatim from staging) so the harness can prove the new pin is consistent.
INSERT INTO pdc_ops.regression_checks(check_name,fault_id,description,check_sql,sort_order,added_in) VALUES ('protected_function_md5s','GENERAL','pins',
$c$WITH x AS (SELECT e.signature, e.prosrc_md5, (SELECT md5(p.prosrc) FROM pg_proc p WHERE p.oid=to_regprocedure(e.signature)) live FROM pdc_ops.expected_function_md5 e)
SELECT count(*) FILTER (WHERE live IS DISTINCT FROM prosrc_md5)=0 AS ok,
 count(*)||' pinned, '||count(*) FILTER (WHERE live IS DISTINCT FROM prosrc_md5)||' changed'||coalesce(': '||string_agg(signature||' '||coalesce(left(live,8),'MISSING'),'; ') FILTER (WHERE live IS DISTINCT FROM prosrc_md5),'') AS detail FROM x$c$,900,'r399');
-- Tables the parts import declares (%rowtype); the harness only drives its envelope gate, which returns before touching them.
CREATE TABLE pdc_parts_private.receipts(id uuid, request_hash text, response jsonb);
CREATE TABLE pdc_parts_private.jobs(id uuid);
