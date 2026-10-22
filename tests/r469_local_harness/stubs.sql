DROP DATABASE IF EXISTS r469;
CREATE DATABASE r469;
\c r469
DO $$BEGIN CREATE ROLE anon; EXCEPTION WHEN duplicate_object THEN NULL; END$$;
DO $$BEGIN CREATE ROLE authenticated; EXCEPTION WHEN duplicate_object THEN NULL; END$$;
DO $$BEGIN CREATE ROLE service_role; EXCEPTION WHEN duplicate_object THEN NULL; END$$;
CREATE SCHEMA pdc_ops; CREATE SCHEMA pdc_bus_private; CREATE SCHEMA auth;
CREATE TYPE public.workshop_booking_status AS ENUM ('queued','planned','started','stoppage','completed','cancelled');
CREATE TABLE public.workshop_stages(id uuid primary key default gen_random_uuid(), code text, display_name text, sort_order int, is_physical boolean default true, is_sublet boolean default false, active boolean default true, planner_enabled boolean default true);
CREATE TABLE public.workshop_bays(id uuid primary key default gen_random_uuid(), stage_id uuid, bay_number int, code text, display_name text, is_active boolean default true, is_sublet_row boolean default false);
CREATE TABLE public.vehicles(id uuid primary key default gen_random_uuid(), version int default 1, stock_number text);
CREATE TABLE public.workshop_bookings(id uuid primary key default gen_random_uuid(), vehicle_id uuid, stage_id uuid, bay_id uuid, status public.workshop_booking_status, scheduled_start_at timestamptz, scheduled_end_at timestamptz, default_duration_minutes int, deleted_at timestamptz, version int default 1, updated_by uuid);
CREATE TABLE public.workshop_booking_assignments(booking_id uuid, technician_id uuid, released_at timestamptz, assignment_type text, assigned_at timestamptz);
CREATE TABLE pdc_ops.expected_function_md5(signature text, prosrc_md5 text, release text, note text, updated_at timestamptz);
CREATE TABLE pdc_ops.regression_checks(check_name text, fault_id text, description text, check_sql text, enabled boolean, sort_order int, added_in text);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql AS $$select null::uuid$$;
-- simple calendar: every minute is working time
CREATE FUNCTION public.workshop_add_operational_minutes(t timestamptz, m int) RETURNS timestamptz LANGUAGE sql STABLE AS $$select t + make_interval(mins=>m)$$;
CREATE FUNCTION public.workshop_next_calendar_window(t timestamptz, m int) RETURNS timestamptz LANGUAGE sql STABLE AS $$select t$$;
CREATE FUNCTION public.workshop_operational_minutes_between(a timestamptz, b timestamptz) RETURNS int LANGUAGE sql STABLE AS $$select (extract(epoch from b-a)/60)::int$$;
CREATE FUNCTION public.workshop_booking_effective_end_at(p uuid) RETURNS timestamptz LANGUAGE sql STABLE AS $$select scheduled_end_at from public.workshop_bookings where id=p$$;
CREATE FUNCTION pdc_bus_private.active_vehicle(uuid) RETURNS boolean LANGUAGE sql STABLE AS $$select false$$;
CREATE FUNCTION pdc_bus_private.add_minutes(timestamptz,int,uuid) RETURNS timestamptz LANGUAGE sql STABLE AS $$select $1$$;
CREATE FUNCTION public.workshop_booking_snapshot(p uuid) RETURNS jsonb LANGUAGE sql STABLE AS $$select to_jsonb(b) || jsonb_build_object('booking_id',b.id) from public.workshop_bookings b where id=p$$;
CREATE FUNCTION public.workshop_conflict_payload(p uuid, t text) RETURNS jsonb LANGUAGE sql STABLE AS $$select jsonb_build_object('conflict_type',t,'existing_booking',public.workshop_booking_snapshot(p))$$;
