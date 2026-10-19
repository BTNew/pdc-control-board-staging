-- Local clock fixture. Calendar predicates whose original CREATE predates this
-- repo are pinned to the live staging body. Every other clock function is
-- installed from supabase/migrations by scripts/run_workshop_clock_skip_local.js.
CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS pdc_bus_private;

CREATE FUNCTION public.pdc_monitor_staging_guard() RETURNS boolean
LANGUAGE sql AS $g$ SELECT true $g$;

CREATE FUNCTION auth.uid() RETURNS uuid
LANGUAGE sql STABLE AS $g$ SELECT '50000000-0000-4000-8000-0000000000aa'::uuid $g$;

CREATE TABLE public.pdc_staging_environment_sentinel (
  singleton boolean PRIMARY KEY CHECK (singleton),
  project_ref text NOT NULL
);
INSERT INTO public.pdc_staging_environment_sentinel VALUES (true, 'cdsmnqxtyyoeoznmbidd');

CREATE TABLE public.workshop_settings (key text PRIMARY KEY, value jsonb NOT NULL);
INSERT INTO public.workshop_settings(key, value) VALUES
 ('day_start_time', '"06:00"'::jsonb),
 ('day_end_time', '"16:30"'::jsonb),
 ('working_week', '["monday","tuesday","wednesday","thursday","friday"]'::jsonb),
 ('closures', '[]'::jsonb),
 ('break_windows', '[]'::jsonb),
 ('overtime_windows', '[]'::jsonb);

CREATE TABLE public.workshop_stages (
  id uuid PRIMARY KEY, code text NOT NULL, active boolean NOT NULL, planner_enabled boolean NOT NULL
);
CREATE TABLE public.workshop_bays (
  id uuid PRIMARY KEY, stage_id uuid NOT NULL, is_active boolean NOT NULL, bay_number integer NOT NULL
);
CREATE TABLE public.vehicles (
  id uuid PRIMARY KEY, location_override text, current_location text, eta_to_kewdale date
);
CREATE TABLE public.workshop_bookings (
  id uuid PRIMARY KEY,
  vehicle_id uuid NOT NULL,
  bay_id uuid,
  stage_id uuid NOT NULL,
  status text NOT NULL,
  actual_start_at timestamptz,
  scheduled_start_at timestamptz NOT NULL,
  scheduled_end_at timestamptz NOT NULL,
  default_duration_minutes integer NOT NULL,
  version integer NOT NULL,
  deleted_at timestamptz,
  updated_at timestamptz,
  updated_by uuid,
  bus_calendar_version integer
);
CREATE TABLE public.workshop_booking_assignments (
  id uuid PRIMARY KEY,
  booking_id uuid NOT NULL,
  technician_id uuid,
  released_at timestamptz,
  scheduled_start_at timestamptz,
  scheduled_end_at timestamptz,
  updated_at timestamptz
);
CREATE TABLE public.workshop_admin_blocks (
  id uuid PRIMARY KEY,
  bay_id uuid,
  deleted_at timestamptz,
  scheduled_start_at timestamptz,
  scheduled_end_at timestamptz
);
CREATE TABLE public.workshop_clock_watermarks (
  booking_id uuid PRIMARY KEY,
  accounted_through timestamptz NOT NULL,
  updated_at timestamptz
);
CREATE TABLE public.workshop_clock_status (
  bay_id uuid PRIMARY KEY,
  last_checked_at timestamptz,
  last_success_at timestamptz,
  moved_count integer,
  error_code text,
  error_detail text
);
CREATE TABLE public.workshop_clock_history (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  booking_id uuid,
  bay_id uuid,
  clock_at timestamptz,
  before_data jsonb,
  after_data jsonb
);
CREATE TABLE public.probe_result (
  phase text NOT NULL,
  scenario text NOT NULL,
  payload jsonb NOT NULL,
  state jsonb NOT NULL,
  plan_calls bigint,
  effective_calls bigint,
  capacity_calls bigint,
  PRIMARY KEY (phase, scenario)
);
CREATE TABLE public.probe_timing (
  phase text NOT NULL,
  kind text NOT NULL,
  avg_ms numeric NOT NULL,
  samples integer NOT NULL,
  PRIMARY KEY (phase, kind)
);

INSERT INTO public.workshop_stages(id, code, active, planner_enabled) VALUES
 ('10000000-0000-4000-8000-000000000001', 'FITTING', true, true),
 ('10000000-0000-4000-8000-000000000002', 'BUS_4X4', true, true);
INSERT INTO public.workshop_bays(id, stage_id, is_active, bay_number) VALUES
 ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', true, 1),
 ('20000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001', true, 2),
 ('20000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000001', true, 3),
 ('20000000-0000-4000-8000-000000000004', '10000000-0000-4000-8000-000000000001', true, 4),
 ('20000000-0000-4000-8000-000000000005', '10000000-0000-4000-8000-000000000001', true, 5),
 ('20000000-0000-4000-8000-000000000006', '10000000-0000-4000-8000-000000000001', true, 6),
 ('20000000-0000-4000-8000-000000000007', '10000000-0000-4000-8000-000000000001', true, 7),
 ('20000000-0000-4000-8000-000000000008', '10000000-0000-4000-8000-000000000002', true, 1),
 ('20000000-0000-4000-8000-000000000009', '10000000-0000-4000-8000-000000000002', true, 2),
 ('20000000-0000-4000-8000-00000000000a', '10000000-0000-4000-8000-000000000001', false, 11);
INSERT INTO public.vehicles(id, location_override, current_location) VALUES
 ('30000000-0000-4000-8000-000000000001', NULL, 'PMB'),
 ('30000000-0000-4000-8000-000000000002', NULL, 'PMB'),
 ('30000000-0000-4000-8000-000000000003', NULL, 'PMB'),
 ('30000000-0000-4000-8000-000000000004', NULL, 'PMB'),
 ('30000000-0000-4000-8000-000000000005', NULL, 'PMB'),
 ('30000000-0000-4000-8000-000000000006', NULL, 'PMB'),
 ('30000000-0000-4000-8000-000000000007', NULL, 'PMB');

CREATE FUNCTION public.workshop_future_only_schedule_enabled() RETURNS boolean
LANGUAGE sql STABLE AS $g$ SELECT true $g$;
CREATE FUNCTION public.workshop_location_code(p_location text) RETURNS text
LANGUAGE sql STABLE AS $g$ SELECT 'PMB'::text $g$;
CREATE FUNCTION public.workshop_lock_resources(p_bay uuid, p_technician uuid) RETURNS void
LANGUAGE sql AS $g$ SELECT NULL::void $g$;
CREATE FUNCTION public.pdc_sublet_away_on_date(p_vehicle uuid, p_date date) RETURNS boolean
LANGUAGE sql STABLE AS $g$ SELECT false $g$;
CREATE FUNCTION public.workshop_technician_leave_date(p_technician uuid, p_start timestamptz, p_end timestamptz) RETURNS date
LANGUAGE sql STABLE AS $g$ SELECT NULL::date $g$;
CREATE FUNCTION public.workshop_bump_revision() RETURNS void
LANGUAGE sql AS $g$ SELECT NULL::void $g$;
CREATE FUNCTION public.workshop_booking_capacity_duration_minutes(p_booking uuid, p_vehicle uuid, p_stage uuid, p_bay uuid)
RETURNS integer LANGUAGE plpgsql STABLE AS $g$
BEGIN
 RETURN (SELECT default_duration_minutes FROM public.workshop_bookings WHERE id = p_booking);
END $g$;
CREATE FUNCTION public.workshop_booking_effective_duration_minutes(p_booking uuid) RETURNS integer
LANGUAGE sql STABLE AS $g$
 SELECT default_duration_minutes FROM public.workshop_bookings WHERE id = p_booking $g$;
CREATE FUNCTION public.workshop_booking_effective_end_before_bus_20260921(p_booking uuid) RETURNS timestamptz
LANGUAGE sql STABLE AS $g$
 SELECT scheduled_end_at FROM public.workshop_bookings WHERE id = p_booking $g$;
CREATE FUNCTION pdc_bus_private.public_holiday_dates() RETURNS date[]
LANGUAGE sql STABLE AS $g$ SELECT ARRAY[]::date[] $g$;
CREATE FUNCTION pdc_bus_private.active_vehicle(p_vehicle uuid) RETURNS boolean
LANGUAGE sql STABLE AS $g$ SELECT p_vehicle = '30000000-0000-4000-8000-000000000006'::uuid $g$;
CREATE FUNCTION pdc_bus_private.booking_rule(p_vehicle uuid, p_bay uuid, p_booking uuid) RETURNS jsonb
LANGUAGE sql STABLE AS $g$ SELECT '{"ok":true}'::jsonb $g$;

-- Live staging body, md5 6b53f98e01026e379d5498d668ec6cbd. The repo only has the
-- later settings-read patch, not the original CREATE.
CREATE FUNCTION public.workshop_calendar_minute_available(p_at timestamptz)
RETURNS boolean LANGUAGE plpgsql STABLE SET search_path TO 'pg_catalog', 'public'
AS $cal$
declare
  v_local timestamp := p_at at time zone 'Australia/Perth';
  v_date date := v_local::date;
  v_clock time := v_local::time;
  v_day text := lower(to_char(v_local,'FMDay'));
  v_settings jsonb;
  v_start time;
  v_end time;
  v_working_week jsonb;
  v_closures jsonb;
  v_breaks jsonb;
  v_overtime jsonb;
  v_workday boolean;
  v_regular boolean;
  v_overtime_ok boolean;
  v_break boolean;
begin
  select jsonb_object_agg(key,value) into v_settings from public.workshop_settings
  where key in('day_start_time','day_end_time','working_week','closures','break_windows','overtime_windows');
  v_start:=(v_settings->>'day_start_time')::time;
  v_end:=(v_settings->>'day_end_time')::time;
  v_working_week:=v_settings->'working_week';
  v_closures:=v_settings->'closures';
  v_breaks:=v_settings->'break_windows';
  v_overtime:=v_settings->'overtime_windows';
  if v_start is null or v_end is null or v_start>=v_end
     or jsonb_typeof(v_working_week)<>'array' or jsonb_typeof(v_closures)<>'array'
     or jsonb_typeof(v_breaks)<>'array' or jsonb_typeof(v_overtime)<>'array' then
    return false;
  end if;
  select exists(select 1 from jsonb_array_elements_text(v_working_week) d where lower(d)=v_day) into v_workday;
  if not v_workday or exists(
    select 1 from jsonb_array_elements(v_closures) c where c->>'date'=v_date::text
  ) then return false; end if;
  v_regular := v_clock>=v_start and v_clock<v_end;
  select exists(
    select 1 from jsonb_array_elements(v_overtime) w
    where v_clock >= (w->>'start')::time and v_clock < (w->>'end')::time
      and ((w ? 'date' and w->>'date'=v_date::text)
        or (not (w ? 'date') and lower(coalesce(w->>'scope',w->>'day','global')) in ('global','working_day',v_day)))
  ) into v_overtime_ok;
  select exists(
    select 1 from jsonb_array_elements(v_breaks) w
    where v_clock >= (w->>'start')::time and v_clock < (w->>'end')::time
      and ((w ? 'date' and w->>'date'=v_date::text)
        or (not (w ? 'date') and lower(coalesce(w->>'scope',w->>'day','global')) in ('global','working_day',v_day)))
  ) into v_break;
  return (v_regular or v_overtime_ok) and not v_break;
exception when others then
  return false;
end $cal$;

-- Live staging body, md5 6849b6c6eb2360f04a7f66a3828a351a.
CREATE FUNCTION public.workshop_clock_next_minute(p_at timestamptz)
RETURNS timestamptz LANGUAGE plpgsql STABLE SET search_path TO 'pg_catalog', 'public'
AS $clk$
DECLARE t timestamptz:=date_trunc('minute',p_at); limit_at timestamptz:=p_at+interval '90 days';
BEGIN
 IF t<p_at THEN t:=t+interval '1 minute'; END IF;
 WHILE NOT public.workshop_calendar_minute_available(t) LOOP
  t:=t+interval '1 minute';
  IF t>limit_at THEN RAISE EXCEPTION 'No workshop opening within 90 days' USING errcode='22023'; END IF;
 END LOOP;
 RETURN t;
END $clk$;
