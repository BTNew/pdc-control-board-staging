-- r475 (F88) local harness stubs: a throwaway local PostgreSQL database with just enough of the staging schema for r436 + r475.
-- Never connects to Supabase. Synthetic stock numbers only.
DROP DATABASE IF EXISTS r475;
CREATE DATABASE r475;
\c r475
DO $$BEGIN CREATE ROLE anon; EXCEPTION WHEN duplicate_object THEN NULL; END$$;
DO $$BEGIN CREATE ROLE authenticated; EXCEPTION WHEN duplicate_object THEN NULL; END$$;
DO $$BEGIN CREATE ROLE service_role; EXCEPTION WHEN duplicate_object THEN NULL; END$$;
CREATE SCHEMA pdc_ops; CREATE SCHEMA auth; CREATE SCHEMA pdc_parts_private; CREATE SCHEMA pdc_work_categories_private;
CREATE TYPE public.pdc_role AS ENUM ('viewer','operator','importer','administrator');
CREATE TABLE public.vehicles(id uuid primary key default gen_random_uuid(), stock_number text, deleted_at timestamptz);
CREATE TABLE pdc_parts_private.jobs(id uuid primary key default gen_random_uuid(), vehicle_id uuid, stock_number text, ro_number text, closed_at timestamptz);
CREATE TABLE pdc_ops.expected_function_md5(signature text, prosrc_md5 text, release text, note text, updated_at timestamptz);
CREATE TABLE pdc_ops.regression_checks(check_name text, fault_id text, description text, check_sql text, enabled boolean, sort_order int, added_in text);
CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$select nullif(auth.jwt()->>'sub','')::uuid$$;
CREATE FUNCTION public.current_pdc_user_role() RETURNS public.pdc_role LANGUAGE sql STABLE AS $$select nullif(auth.jwt()->>'pdc_role','')::public.pdc_role$$;
CREATE FUNCTION public.is_pdc_role(r public.pdc_role) RETURNS boolean LANGUAGE sql STABLE AS $$select public.current_pdc_user_role() is not null$$;
CREATE FUNCTION pdc_work_categories_private.before_import_rules_20261017(uuid) RETURNS jsonb LANGUAGE sql STABLE AS $$select '[]'::jsonb$$;
-- Synthetic board: NEW-1 (renumbered from OLD-1, which is no longer on the board) has one open job; TWO-JOBS has two; OLD-2 is only
-- on the board under its previous number.
INSERT INTO public.vehicles(id,stock_number) VALUES
 ('aaaaaaaa-0000-4000-8000-000000000001','NEW-1'),('aaaaaaaa-0000-4000-8000-000000000002','TWO-JOBS'),('aaaaaaaa-0000-4000-8000-000000000003','OLD-2');
INSERT INTO pdc_parts_private.jobs(vehicle_id,stock_number,ro_number) VALUES
 ('aaaaaaaa-0000-4000-8000-000000000001','NEW-1','J100000001'),
 ('aaaaaaaa-0000-4000-8000-000000000002','TWO-JOBS','J100000002'),('aaaaaaaa-0000-4000-8000-000000000002','TWO-JOBS','J100000003'),
 ('aaaaaaaa-0000-4000-8000-000000000003','OLD-2','J100000004');
