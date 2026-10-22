-- r483 local throwaway DB: shapes of the staging objects the migration touches (never connects to Supabase).
DROP DATABASE IF EXISTS r483;
CREATE DATABASE r483;
\c r483
CREATE SCHEMA pdc_ops;
CREATE TYPE public.audit_action AS ENUM ('insert','update','move','import','delete','restore','rft','role_change','reference_change','rollback');
CREATE TABLE public.workshop_stages(id uuid PRIMARY KEY, code text UNIQUE NOT NULL, display_name text, sort_order int);
CREATE TABLE public.workshop_bays(id uuid PRIMARY KEY, stage_id uuid NOT NULL REFERENCES public.workshop_stages(id), bay_number int, code text UNIQUE,
  display_name text, is_active boolean NOT NULL DEFAULT true, is_sublet_row boolean NOT NULL DEFAULT false, default_technician_id uuid,
  created_at timestamptz DEFAULT now(), updated_at timestamptz DEFAULT now(), created_by uuid, updated_by uuid, version int NOT NULL DEFAULT 1,
  efficiency_percent int, UNIQUE(stage_id,bay_number));
CREATE TABLE public.workshop_bookings(id uuid PRIMARY KEY, stage_id uuid, bay_id uuid REFERENCES public.workshop_bays(id), status text,
  scheduled_start_at timestamptz, scheduled_end_at timestamptz, deleted_at timestamptz, version int);
CREATE TABLE public.audit_events(id uuid PRIMARY KEY DEFAULT gen_random_uuid(), action public.audit_action NOT NULL, table_name text, row_id uuid,
  vehicle_id uuid, actor_id uuid, actor_email text, before_data jsonb, after_data jsonb, metadata jsonb NOT NULL DEFAULT '{}', created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.pdc_staging_environment_sentinel(singleton boolean, project_ref text);
INSERT INTO public.pdc_staging_environment_sentinel VALUES (true,'cdsmnqxtyyoeoznmbidd');
CREATE FUNCTION public.pdc_monitor_staging_guard() RETURNS boolean LANGUAGE sql AS 'select true';
CREATE FUNCTION public.set_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN NEW.updated_at=now(); RETURN NEW; END$$;
CREATE TRIGGER workshop_bays_set_updated_at BEFORE UPDATE ON public.workshop_bays FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TABLE pdc_ops.regression_checks(check_name text PRIMARY KEY, fault_id text NOT NULL, description text NOT NULL, check_sql text NOT NULL,
  enabled boolean NOT NULL DEFAULT true, sort_order int NOT NULL, added_in text NOT NULL);
CREATE FUNCTION pdc_ops.fault_regression_check() RETURNS TABLE(check_name text, ok boolean, detail text) LANGUAGE plpgsql AS $$
DECLARE r record; v_ok boolean; v_d text; BEGIN
 FOR r IN SELECT * FROM pdc_ops.regression_checks c WHERE c.enabled ORDER BY c.sort_order LOOP
  EXECUTE r.check_sql INTO v_ok, v_d; check_name:=r.check_name; ok:=v_ok; detail:=v_d; RETURN NEXT; END LOOP; END $$;
CREATE SCHEMA pdc_bus_private;
CREATE TABLE public.workshop_admin_blocks(id uuid PRIMARY KEY DEFAULT gen_random_uuid(), bay_id uuid REFERENCES public.workshop_bays(id));
CREATE TABLE public.workshop_parts_overrides(id uuid PRIMARY KEY DEFAULT gen_random_uuid(), intended_bay_id uuid REFERENCES public.workshop_bays(id));
CREATE TABLE pdc_bus_private.activity_events(id uuid PRIMARY KEY DEFAULT gen_random_uuid(), bay_id uuid REFERENCES public.workshop_bays(id));
