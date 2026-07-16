-- Workshop Planner shared-data foundation
-- Shared multi-user workshop controller tables, reference data, settings, and read-only policies.

begin;

create extension if not exists btree_gist;

create type public.workshop_booking_status as enum ('queued', 'planned', 'started', 'stoppage', 'completed', 'deleted');
create type public.workshop_assignment_type as enum ('primary', 'secondary', 'provider');

create table public.workshop_stages (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  display_name text not null,
  sort_order integer not null unique,
  is_physical boolean not null default true,
  is_sublet boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint workshop_stages_code_upper check (code = upper(code))
);

create table public.workshop_technicians (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  role_type text not null,
  active boolean not null default true,
  can_fit_stages text[] not null default '{}'::text[],
  leave_calendar jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint workshop_technicians_role_type_check check (role_type in ('technician', 'provider'))
);

create table public.workshop_bays (
  id uuid primary key default gen_random_uuid(),
  stage_id uuid not null references public.workshop_stages(id) on delete cascade,
  bay_number integer,
  code text not null unique,
  display_name text not null,
  is_active boolean not null default true,
  is_sublet_row boolean not null default false,
  default_technician_id uuid references public.workshop_technicians(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint workshop_bays_number_positive check (bay_number is null or bay_number > 0),
  constraint workshop_bays_stage_number_unique unique (stage_id, bay_number)
);

create table public.workshop_bookings (
  id uuid primary key default gen_random_uuid(),
  vehicle_id uuid not null references public.vehicles(id) on delete cascade,
  stage_id uuid not null references public.workshop_stages(id),
  bay_id uuid references public.workshop_bays(id),
  status public.workshop_booking_status not null default 'planned',
  scheduled_start_at timestamptz not null,
  scheduled_end_at timestamptz not null,
  default_duration_minutes integer not null,
  actual_start_at timestamptz,
  actual_end_at timestamptz,
  actual_duration_minutes integer,
  stoppage_reason text,
  stoppage_started_at timestamptz,
  stoppage_accumulated_minutes integer not null default 0,
  returned_to_queue_at timestamptz,
  deleted_at timestamptz,
  deleted_reason text,
  source text not null default 'planner',
  version integer not null default 1,
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint workshop_bookings_duration_positive check (default_duration_minutes > 0),
  constraint workshop_bookings_schedule_order check (scheduled_end_at > scheduled_start_at)
);

create table public.workshop_booking_assignments (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.workshop_bookings(id) on delete cascade,
  technician_id uuid not null references public.workshop_technicians(id),
  assignment_type public.workshop_assignment_type not null default 'primary',
  assigned_at timestamptz not null default now(),
  assigned_by uuid not null references auth.users(id),
  scheduled_start_at timestamptz not null,
  scheduled_end_at timestamptz not null,
  released_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint workshop_booking_assignments_schedule_order check (scheduled_end_at > scheduled_start_at)
);

create unique index workshop_booking_assignments_one_active_primary_idx
on public.workshop_booking_assignments (booking_id)
where assignment_type = 'primary' and released_at is null;

create table public.workshop_booking_history (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.workshop_bookings(id) on delete cascade,
  event_type text not null,
  before_data jsonb,
  after_data jsonb,
  metadata jsonb not null default '{}'::jsonb,
  actor_user_id uuid not null references auth.users(id),
  actor_email text,
  created_at timestamptz not null default now()
);

create table public.workshop_settings (
  id uuid primary key default gen_random_uuid(),
  key text not null unique,
  value jsonb not null,
  scope text not null default 'global',
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index workshop_stages_active_idx on public.workshop_stages(active, sort_order);
create index workshop_technicians_active_idx on public.workshop_technicians(active, role_type, name);
create index workshop_bays_stage_active_idx on public.workshop_bays(stage_id, is_active, bay_number);
create index workshop_bookings_vehicle_idx on public.workshop_bookings(vehicle_id, created_at desc);
create index workshop_bookings_stage_bay_time_idx on public.workshop_bookings(stage_id, bay_id, scheduled_start_at, scheduled_end_at);
create index workshop_bookings_status_idx on public.workshop_bookings(status, scheduled_start_at);
create index workshop_booking_assignments_technician_time_idx on public.workshop_booking_assignments(technician_id, scheduled_start_at, scheduled_end_at) where released_at is null;
create index workshop_booking_history_booking_idx on public.workshop_booking_history(booking_id, created_at desc);
create index workshop_settings_scope_key_idx on public.workshop_settings(scope, key);

create trigger workshop_stages_set_updated_at
before update on public.workshop_stages
for each row execute function public.set_updated_at();

create trigger workshop_technicians_set_updated_at
before update on public.workshop_technicians
for each row execute function public.set_updated_at();

create trigger workshop_bays_set_updated_at
before update on public.workshop_bays
for each row execute function public.set_updated_at();

create trigger workshop_bookings_set_updated_at
before update on public.workshop_bookings
for each row execute function public.set_updated_at();

create trigger workshop_booking_assignments_set_updated_at
before update on public.workshop_booking_assignments
for each row execute function public.set_updated_at();

create trigger workshop_settings_set_updated_at
before update on public.workshop_settings
for each row execute function public.set_updated_at();

insert into public.workshop_stages (code, display_name, sort_order, is_physical, is_sublet)
values
  ('BUS_4X4', 'Bus 4x4', 1, true, false),
  ('TINT', 'Tint', 2, true, false),
  ('HOIST', 'Hoist', 3, true, false),
  ('FITTING', 'Fitting', 4, true, false),
  ('FABRICATION', 'Fab', 5, true, false),
  ('ELECTRICAL', 'Elec', 6, true, false),
  ('TYRE', 'Tyre', 7, true, false),
  ('PIT_INSPECTION', 'Pit', 8, true, false),
  ('SUBLET', 'Sublet', 9, false, true)
on conflict (code) do update
set display_name = excluded.display_name,
    sort_order = excluded.sort_order,
    is_physical = excluded.is_physical,
    is_sublet = excluded.is_sublet,
    active = true;

with bay_seed(stage_code, bay_total) as (
  values
    ('BUS_4X4', 1),
    ('TINT', 2),
    ('HOIST', 3),
    ('FITTING', 5),
    ('FABRICATION', 13),
    ('ELECTRICAL', 10),
    ('TYRE', 2),
    ('PIT_INSPECTION', 1)
)
insert into public.workshop_bays (stage_id, bay_number, code, display_name, is_active, is_sublet_row)
select s.id,
       gs.bay_number,
       s.code || '-BAY-' || lpad(gs.bay_number::text, 2, '0'),
       s.display_name || ' Bay ' || lpad(gs.bay_number::text, 2, '0'),
       true,
       false
from bay_seed seed
join public.workshop_stages s on s.code = seed.stage_code
cross join lateral generate_series(1, seed.bay_total) as gs(bay_number)
on conflict (stage_id, bay_number) do update
set display_name = excluded.display_name,
    code = excluded.code,
    is_active = true,
    is_sublet_row = false;

insert into public.workshop_bays (stage_id, bay_number, code, display_name, is_active, is_sublet_row)
select s.id, 1, 'SUBLET-ROW', 'Sublet provider row', true, true
from public.workshop_stages s
where s.code = 'SUBLET'
on conflict (stage_id, bay_number) do update
set display_name = excluded.display_name,
    code = excluded.code,
    is_active = true,
    is_sublet_row = true;

insert into public.workshop_settings (key, value, scope)
values
  ('working_week', jsonb_build_array('monday', 'tuesday', 'wednesday', 'thursday', 'friday'), 'global'),
  ('day_start_time', to_jsonb('08:00'::text), 'global'),
  ('day_end_time', to_jsonb('16:00'::text), 'global'),
  ('default_booking_duration_minutes', to_jsonb(180), 'global'),
  ('scheduling_increment_minutes', to_jsonb(15), 'global'),
  ('closures', '[]'::jsonb, 'global'),
  ('overtime_windows', '[]'::jsonb, 'global'),
  ('break_windows', '[]'::jsonb, 'global'),
  ('technician_leave', '[]'::jsonb, 'global')
on conflict (key) do nothing;

alter table public.workshop_stages enable row level security;
alter table public.workshop_technicians enable row level security;
alter table public.workshop_bays enable row level security;
alter table public.workshop_bookings enable row level security;
alter table public.workshop_booking_assignments enable row level security;
alter table public.workshop_booking_history enable row level security;
alter table public.workshop_settings enable row level security;

drop policy if exists workshop_stages_select_approved on public.workshop_stages;
create policy workshop_stages_select_approved
on public.workshop_stages
for select
to authenticated
using (public.is_pdc_role('viewer'));

drop policy if exists workshop_technicians_select_approved on public.workshop_technicians;
create policy workshop_technicians_select_approved
on public.workshop_technicians
for select
to authenticated
using (public.is_pdc_role('viewer'));

drop policy if exists workshop_bays_select_approved on public.workshop_bays;
create policy workshop_bays_select_approved
on public.workshop_bays
for select
to authenticated
using (public.is_pdc_role('viewer'));

drop policy if exists workshop_bookings_select_approved on public.workshop_bookings;
create policy workshop_bookings_select_approved
on public.workshop_bookings
for select
to authenticated
using (public.is_pdc_role('viewer'));

drop policy if exists workshop_booking_assignments_select_approved on public.workshop_booking_assignments;
create policy workshop_booking_assignments_select_approved
on public.workshop_booking_assignments
for select
to authenticated
using (public.is_pdc_role('viewer'));

drop policy if exists workshop_booking_history_select_approved on public.workshop_booking_history;
create policy workshop_booking_history_select_approved
on public.workshop_booking_history
for select
to authenticated
using (public.is_pdc_role('viewer'));

drop policy if exists workshop_settings_select_approved on public.workshop_settings;
create policy workshop_settings_select_approved
on public.workshop_settings
for select
to authenticated
using (public.is_pdc_role('viewer'));

grant select on public.workshop_stages, public.workshop_technicians, public.workshop_bays, public.workshop_bookings, public.workshop_booking_assignments, public.workshop_booking_history, public.workshop_settings to authenticated;

alter publication supabase_realtime add table public.workshop_stages;
alter publication supabase_realtime add table public.workshop_technicians;
alter publication supabase_realtime add table public.workshop_bays;
alter publication supabase_realtime add table public.workshop_bookings;
alter publication supabase_realtime add table public.workshop_booking_assignments;
alter publication supabase_realtime add table public.workshop_booking_history;
alter publication supabase_realtime add table public.workshop_settings;

commit;
