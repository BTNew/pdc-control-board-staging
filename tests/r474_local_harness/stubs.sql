-- r474 (F87) local harness stubs: a throwaway local PostgreSQL database (never Supabase). Synthetic rows only.
-- yard_hold_stage_rank, fault_regression_check, pdc_monitor_staging_guard and navision_original_column_value are copied
-- from staging (read-only pg_get_functiondef, 22 Oct) so the release guards see the same md5s.
DROP DATABASE IF EXISTS r474;
CREATE DATABASE r474;
\c r474
DO $$BEGIN CREATE ROLE anon; EXCEPTION WHEN duplicate_object THEN NULL; END$$;
DO $$BEGIN CREATE ROLE authenticated; EXCEPTION WHEN duplicate_object THEN NULL; END$$;
DO $$BEGIN CREATE ROLE service_role; EXCEPTION WHEN duplicate_object THEN NULL; END$$;
CREATE SCHEMA pdc_ops; CREATE SCHEMA pdc_sales_private; CREATE SCHEMA auth;
CREATE FUNCTION auth.role() RETURNS text LANGUAGE sql AS $$select null::text$$;
CREATE FUNCTION public.current_pdc_user_role() RETURNS text LANGUAGE sql AS $$select null::text$$;
CREATE TABLE public.pdc_staging_environment_sentinel(singleton boolean, project_ref text);
INSERT INTO public.pdc_staging_environment_sentinel VALUES (true,'cdsmnqxtyyoeoznmbidd');
CREATE TABLE pdc_ops.expected_function_md5(signature text primary key, prosrc_md5 text, release text, note text, updated_at timestamptz);
CREATE TABLE pdc_ops.regression_checks(check_name text primary key, fault_id text, description text, check_sql text, enabled boolean, sort_order int, added_in text);
CREATE FUNCTION public.workshop_clock_tick(p_apply boolean, p_now timestamptz) RETURNS jsonb LANGUAGE sql AS $$select '{}'::jsonb$$;
INSERT INTO pdc_ops.expected_function_md5 SELECT 'public.workshop_clock_tick(boolean,timestamp with time zone)',md5(prosrc),'stub','local stub',now() FROM pg_proc WHERE proname='workshop_clock_tick';
INSERT INTO pdc_ops.expected_function_md5 VALUES ('stub.other(int)','00000000000000000000000000000000','stub','another pin so the count is not 1',now());
CREATE TABLE public.navision_import_batches(id uuid primary key default gen_random_uuid(), source_system text, dealer_code text, status text, rolled_back_at timestamptz, result_revision int, applied_at timestamptz);
CREATE TABLE public.vehicles(id uuid primary key default gen_random_uuid(), stock_number text, deleted_at timestamptz);
CREATE TABLE public.navision_backend_records(id uuid primary key default gen_random_uuid(), normalized_data jsonb, last_seen_batch_id uuid, canonical_vehicle_id uuid, dealer_code text, is_current boolean, record_status text);
CREATE TABLE pdc_sales_private.autocare_dispatches(dealer_code text, order_key text, dispatched boolean);
CREATE OR REPLACE FUNCTION public.pdc_monitor_staging_guard()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
  select exists (
    select 1 from public.pdc_staging_environment_sentinel
    where singleton and project_ref = 'cdsmnqxtyyoeoznmbidd'
  );
$function$;

CREATE OR REPLACE FUNCTION public.navision_original_column_value(p_normalized_data jsonb, p_header text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE PARALLEL SAFE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
  select nullif(btrim(cell ->> 'value'), '')
  from jsonb_array_elements(
    case
      when jsonb_typeof(p_normalized_data #> '{navisionRawEvidence,columns}') = 'array'
        then p_normalized_data #> '{navisionRawEvidence,columns}'
      else '[]'::jsonb
    end
  ) as cell
  where lower(regexp_replace(coalesce(cell ->> 'header', ''), '[^a-z0-9]+', '', 'g')) =
        lower(regexp_replace(coalesce(p_header, ''), '[^a-z0-9]+', '', 'g'))
  order by cell ->> 'header'
  limit 1;
$function$;

CREATE OR REPLACE FUNCTION pdc_sales_private.yard_hold_stage_rank(p_location_status text, p_toyota_status text)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
  SELECT greatest(CASE WHEN x.code='' THEN 0 WHEN x.code='IT' THEN 1 WHEN x.code ~ '^Y[A-Z]$' THEN 2 WHEN x.code ~ '^O[A-Z]$' THEN 3 ELSE 0 END,
    CASE WHEN x.s ~ '(delivered|at dealer|body builder|consignment|ready for transport|ready for despatch|ready for dispatch|despatch|dispatch)' THEN 3
         WHEN x.s ~ '(yard hold|waiting pd|waiting for wholesale|\myh\M)' THEN 2
         WHEN x.s ~ '(in transit|wharf|shipment)' THEN 1 ELSE 0 END)
  FROM (SELECT upper(btrim(coalesce(p_location_status,''))) code, lower(coalesce(p_toyota_status,'')) s) x
$function$;

CREATE OR REPLACE FUNCTION pdc_ops.fault_regression_check()
 RETURNS TABLE(check_name text, ok boolean, detail text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET statement_timeout TO '120s'
AS $function$
DECLARE c record; r record;
BEGIN
 -- Service role, a PDC administrator, or a direct database session (SQL editor / routine). Read-only: STABLE refuses writes.
 IF NOT (coalesce(auth.role(),'')='service_role'
   OR coalesce(public.current_pdc_user_role()::text,'')='administrator'
   OR (session_user IN ('postgres','supabase_admin') AND coalesce(auth.role(),'') NOT IN ('authenticated','anon'))) THEN
  RAISE EXCEPTION 'Administrator or service role required' USING ERRCODE='42501';
 END IF;
 FOR c IN SELECT * FROM pdc_ops.regression_checks rc WHERE rc.enabled ORDER BY rc.sort_order, rc.check_name LOOP
  check_name:=c.check_name;
  BEGIN
   EXECUTE c.check_sql INTO r;
   ok:=coalesce(r.ok,false); detail:=coalesce(r.detail,'');
  EXCEPTION WHEN OTHERS THEN ok:=false; detail:='check failed to run: '||SQLSTATE||' '||SQLERRM;
  END;
  RETURN NEXT;
 END LOOP;
END $function$;
