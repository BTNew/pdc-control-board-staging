-- PDC Control Board Supabase pilot schema
-- Safe to run in the Supabase SQL editor for project vjdtsswhroyguxyfjdkt.
-- No secrets are required in this file.

create extension if not exists pgcrypto;

create type public.pdc_role as enum ('viewer', 'operator', 'importer', 'administrator');
create type public.vehicle_lifecycle_state as enum ('active', 'rft', 'completed', 'deleted');
create type public.import_type as enum ('navision', 'purchase_order', 'job_card', 'backup_baseline', 'manual');
create type public.audit_action as enum (
  'insert',
  'update',
  'move',
  'import',
  'delete',
  'restore',
  'rft',
  'role_change',
  'reference_change'
);

create table public.pdc_user_roles (
  id uuid primary key default gen_random_uuid(),
  email text not null unique,
  display_name text,
  role public.pdc_role not null default 'viewer',
  active boolean not null default true,
  approved_by uuid references public.pdc_user_roles(id),
  approved_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pdc_user_roles_email_lowercase check (email = lower(email))
);

create table public.vehicles (
  id uuid primary key default gen_random_uuid(),
  permanent_vehicle_id text not null unique,
  stock_number text,
  vin text,
  toyota_order_number text,
  job_card_number text,
  customer_name text,
  salesperson_id uuid,
  make text,
  model text,
  registration text,
  lifecycle_state public.vehicle_lifecycle_state not null default 'active',
  visible_on_board boolean not null default false,
  current_location text,
  pmb_stage text,
  pmb_bay_stage text,
  pmb_bay_number text,
  pmb_key_tag text,
  eta_to_kewdale date,
  rft_transferred_at timestamptz,
  rft_collected_at timestamptz,
  deleted_at timestamptz,
  deleted_reason text,
  source_payload jsonb not null default '{}'::jsonb,
  version integer not null default 1,
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.vehicle_aliases (
  id uuid primary key default gen_random_uuid(),
  vehicle_id uuid not null references public.vehicles(id) on delete cascade,
  alias_type text not null,
  alias_value text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (alias_type, alias_value)
);

create table public.vehicle_work_items (
  id uuid primary key default gen_random_uuid(),
  vehicle_id uuid not null references public.vehicles(id) on delete cascade,
  work_key text not null,
  required boolean not null default false,
  completed boolean not null default false,
  completed_by uuid references auth.users(id),
  completed_at timestamptz,
  notes text,
  updated_at timestamptz not null default now(),
  unique (vehicle_id, work_key)
);

create table public.vehicle_movements (
  id uuid primary key default gen_random_uuid(),
  vehicle_id uuid not null references public.vehicles(id) on delete cascade,
  from_location text,
  to_location text,
  from_pmb_stage text,
  to_pmb_stage text,
  from_pmb_bay_stage text,
  to_pmb_bay_stage text,
  from_pmb_bay_number text,
  to_pmb_bay_number text,
  reason text,
  moved_by uuid not null references auth.users(id),
  moved_at timestamptz not null default now()
);

create table public.vehicle_parts_updates (
  id uuid primary key default gen_random_uuid(),
  vehicle_id uuid not null references public.vehicles(id) on delete cascade,
  parts_required boolean not null default false,
  parts_ordered boolean not null default false,
  parts_received boolean not null default false,
  parts_stoppage boolean not null default false,
  parts_stoppage_reason text,
  worst_eta date,
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now()
);

create table public.import_runs (
  id uuid primary key default gen_random_uuid(),
  import_type public.import_type not null,
  source_file_name text,
  source_storage_path text,
  source_hash text,
  status text not null default 'pending',
  total_rows integer not null default 0,
  inserted_count integer not null default 0,
  updated_count integer not null default 0,
  skipped_count integer not null default 0,
  error_count integer not null default 0,
  summary jsonb not null default '{}'::jsonb,
  run_by uuid not null references auth.users(id),
  started_at timestamptz not null default now(),
  completed_at timestamptz
);

create table public.salespeople (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  email text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.vehicles
  add constraint vehicles_salesperson_fk
  foreign key (salesperson_id) references public.salespeople(id);

create table public.sublet_providers (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  email text,
  phone text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.deleted_completed_vehicles (
  id uuid primary key default gen_random_uuid(),
  vehicle_id uuid not null references public.vehicles(id) on delete cascade,
  final_state public.vehicle_lifecycle_state not null,
  snapshot jsonb not null,
  reason text,
  acted_by uuid not null references auth.users(id),
  acted_at timestamptz not null default now()
);

create table public.audit_events (
  id uuid primary key default gen_random_uuid(),
  action public.audit_action not null,
  table_name text,
  row_id uuid,
  vehicle_id uuid references public.vehicles(id) on delete set null,
  actor_id uuid references auth.users(id),
  actor_email text,
  before_data jsonb,
  after_data jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index vehicles_lifecycle_idx on public.vehicles(lifecycle_state);
create index vehicles_visible_idx on public.vehicles(visible_on_board) where visible_on_board = true;
create index vehicles_stock_idx on public.vehicles(stock_number);
create index vehicles_vin_idx on public.vehicles(vin);
create index vehicles_order_idx on public.vehicles(toyota_order_number);
create index vehicle_aliases_vehicle_idx on public.vehicle_aliases(vehicle_id);
create index work_items_vehicle_idx on public.vehicle_work_items(vehicle_id);
create index movements_vehicle_idx on public.vehicle_movements(vehicle_id, moved_at desc);
create index audit_vehicle_idx on public.audit_events(vehicle_id, created_at desc);
create index audit_actor_idx on public.audit_events(actor_id, created_at desc);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger pdc_user_roles_set_updated_at
before update on public.pdc_user_roles
for each row execute function public.set_updated_at();

create trigger vehicles_set_updated_at
before update on public.vehicles
for each row execute function public.set_updated_at();

create trigger salespeople_set_updated_at
before update on public.salespeople
for each row execute function public.set_updated_at();

create trigger sublet_providers_set_updated_at
before update on public.sublet_providers
for each row execute function public.set_updated_at();

alter publication supabase_realtime add table public.vehicles;
alter publication supabase_realtime add table public.vehicle_work_items;
alter publication supabase_realtime add table public.vehicle_parts_updates;
alter publication supabase_realtime add table public.vehicle_movements;
