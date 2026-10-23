-- r516 (F130) local harness. Throwaway database only. Never connects to Supabase.
DROP DATABASE IF EXISTS r516;
CREATE DATABASE r516;
\c r516
DO $$BEGIN CREATE ROLE anon; EXCEPTION WHEN duplicate_object THEN NULL; END$$;
DO $$BEGIN CREATE ROLE authenticated; EXCEPTION WHEN duplicate_object THEN NULL; END$$;
DO $$BEGIN CREATE ROLE service_role; EXCEPTION WHEN duplicate_object THEN NULL; END$$;
CREATE SCHEMA pdc_ops;
CREATE SCHEMA auth;
CREATE TYPE public.pdc_role AS ENUM ('viewer','operator','importer','administrator','salesperson','fitter');
CREATE TABLE public.vehicles(
  id uuid PRIMARY KEY,
  stock_number text,
  deleted_at timestamptz,
  board_purged_at timestamptz);
CREATE TABLE public.pdc_parts_eta(id uuid);
CREATE TABLE public.pdc_staging_environment_sentinel(
  singleton boolean PRIMARY KEY DEFAULT true,
  project_ref text NOT NULL);
INSERT INTO public.pdc_staging_environment_sentinel(singleton, project_ref)
VALUES (true, 'cdsmnqxtyyoeoznmbidd');
CREATE TABLE pdc_ops.expected_function_md5(
  signature text PRIMARY KEY,
  prosrc_md5 text NOT NULL CHECK (prosrc_md5 ~ '^[0-9a-f]{32}$'),
  release text NOT NULL,
  note text,
  updated_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE pdc_ops.regression_checks(
  check_name text PRIMARY KEY,
  fault_id text NOT NULL,
  description text NOT NULL,
  check_sql text NOT NULL,
  enabled boolean NOT NULL DEFAULT true,
  sort_order integer NOT NULL,
  added_in text NOT NULL);
CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb
$$;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT nullif(auth.jwt()->>'sub', '')::uuid
$$;
CREATE FUNCTION public.current_pdc_user_role() RETURNS public.pdc_role LANGUAGE sql STABLE AS $$
  SELECT nullif(auth.jwt()->>'pdc_role', '')::public.pdc_role
$$;
CREATE FUNCTION public.is_pdc_role(required_role public.pdc_role) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT CASE
    WHEN public.current_pdc_user_role() = 'administrator' THEN true
    WHEN required_role = 'viewer' AND public.current_pdc_user_role() IN ('viewer','operator','importer','administrator') THEN true
    WHEN required_role = 'operator' AND public.current_pdc_user_role() IN ('operator','administrator') THEN true
    WHEN required_role = 'importer' AND public.current_pdc_user_role() IN ('importer','administrator') THEN true
    WHEN required_role = 'administrator' AND public.current_pdc_user_role() = 'administrator' THEN true
    ELSE false
  END
$$;
CREATE FUNCTION public.pdc_monitor_staging_guard() RETURNS boolean LANGUAGE sql STABLE AS $$ SELECT true $$;
CREATE FUNCTION public.workshop_clock_tick(p_apply boolean DEFAULT true, p_now timestamptz DEFAULT clock_timestamp())
RETURNS void LANGUAGE plpgsql AS $$BEGIN NULL; END$$;
CREATE FUNCTION pdc_ops.fault_regression_check()
RETURNS TABLE(check_name text, ok boolean, detail text)
LANGUAGE plpgsql STABLE AS $$BEGIN RETURN; END$$;
INSERT INTO pdc_ops.expected_function_md5(signature, prosrc_md5, release, note)
SELECT 'public.workshop_clock_tick(boolean,timestamp with time zone)', md5(prosrc), 'stub', 'local harness'
FROM pg_proc WHERE oid = 'public.workshop_clock_tick(boolean,timestamptz)'::regprocedure;
INSERT INTO public.vehicles(id, stock_number) VALUES
 ('13102912-0000-4000-8000-000000000001', '13102912'),
 ('aaaaaaaa-0000-4000-8000-000000000010', 'KEEPME');
INSERT INTO public.vehicles(id, stock_number, deleted_at) VALUES
 ('bbbbbbbb-0000-4000-8000-000000000002', 'DELETED1', now());
INSERT INTO public.vehicles(id, stock_number, board_purged_at) VALUES
 ('cccccccc-0000-4000-8000-000000000003', 'PURGED01', now());
INSERT INTO public.vehicles(id, stock_number) VALUES
 ('dddddddd-0000-4000-8000-000000000004', 'TWICE'),
 ('eeeeeeee-0000-4000-8000-000000000005', 'twice');
