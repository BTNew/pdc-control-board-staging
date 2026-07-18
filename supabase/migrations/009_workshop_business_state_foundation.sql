-- Workshop business-state foundation
-- Adds the authoritative shared-revision mechanism, vehicle-side authoritative
-- workshop pointers, and the Parts-incomplete override audit table.
-- Depends on 001-008. Supersedes nothing from 006/007/008; only adds columns/tables.

begin;

create table public.workshop_revision (
  id smallint primary key default 1,
  revision bigint not null default 0,
  updated_at timestamptz not null default now(),
  constraint workshop_revision_single_row check (id = 1)
);

insert into public.workshop_revision (id, revision) values (1, 0)
on conflict (id) do nothing;

create or replace function public.workshop_bump_revision()
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_revision bigint;
begin
  update public.workshop_revision
  set revision = revision + 1,
      updated_at = now()
  where id = 1
  returning revision into v_revision;

  if v_revision is null then
    insert into public.workshop_revision (id, revision) values (1, 1)
    returning revision into v_revision;
  end if;

  perform pg_notify('workshop_revision_changed', v_revision::text);
  return v_revision;
end;
$$;

create or replace function public.workshop_current_revision()
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select revision from public.workshop_revision where id = 1;
$$;

-- Authoritative vehicle-side workshop pointers. One row per vehicle keeps
-- the single source of truth for current bay / status / active booking,
-- instead of letting bookings and vehicle fields disagree.
alter table public.vehicles
  add column if not exists active_workshop_booking_id uuid references public.workshop_bookings(id) on delete set null,
  add column if not exists workshop_status text not null default 'queued',
  add column if not exists workshop_status_updated_at timestamptz,
  add column if not exists workshop_status_updated_by uuid references auth.users(id);

alter table public.vehicles
  add constraint vehicles_workshop_status_check
  check (workshop_status in ('queued', 'scheduled', 'in_progress', 'stoppage', 'completed'));

create index if not exists vehicles_active_booking_idx on public.vehicles(active_workshop_booking_id);
create index if not exists vehicles_workshop_status_idx on public.vehicles(workshop_status);

-- Parts-incomplete override audit. Every override must be permanently
-- recorded with reason, approver, vehicle, work item, intended bay, and
-- before/after state. Overrides are never editable/deletable by clients.
create table public.workshop_parts_overrides (
  id uuid primary key default gen_random_uuid(),
  vehicle_id uuid not null references public.vehicles(id) on delete cascade,
  booking_id uuid references public.workshop_bookings(id) on delete set null,
  work_key text not null default 'PARTS',
  intended_stage_id uuid references public.workshop_stages(id),
  intended_bay_id uuid references public.workshop_bays(id),
  reason text not null,
  previous_state jsonb not null,
  resulting_state jsonb not null,
  approved_by uuid not null references auth.users(id),
  approved_by_email text,
  approved_at timestamptz not null default now(),
  constraint workshop_parts_overrides_reason_not_blank check (trim(reason) <> '')
);

create index workshop_parts_overrides_vehicle_idx on public.workshop_parts_overrides(vehicle_id, approved_at desc);

alter table public.workshop_revision enable row level security;
alter table public.workshop_parts_overrides enable row level security;

drop policy if exists workshop_revision_select_approved on public.workshop_revision;
create policy workshop_revision_select_approved
on public.workshop_revision
for select
to authenticated
using (public.is_pdc_role('viewer'));

drop policy if exists workshop_parts_overrides_select_approved on public.workshop_parts_overrides;
create policy workshop_parts_overrides_select_approved
on public.workshop_parts_overrides
for select
to authenticated
using (public.is_pdc_role('viewer'));

-- No insert/update/delete policy for authenticated clients: overrides are
-- written only by the security-definer RPC in migration 010.

grant select on public.workshop_revision, public.workshop_parts_overrides to authenticated;

revoke insert, update, delete on table public.workshop_revision, public.workshop_parts_overrides from anon, authenticated;

alter publication supabase_realtime add table public.workshop_revision;

-- Helper: does the vehicle currently satisfy the Parts-required gate for a
-- physical, Parts-protected stage? Returns true when Parts are not required
-- or are already complete/received.
create or replace function public.workshop_parts_ready(p_vehicle_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select (not p.parts_required) or p.parts_received or
             exists (
               select 1 from public.vehicle_work_items wi
               where wi.vehicle_id = p_vehicle_id
                 and wi.work_key = 'PARTS'
                 and wi.completed = true
             )
      from public.vehicle_parts_updates p
      where p.vehicle_id = p_vehicle_id
      order by p.updated_at desc
      limit 1
    ),
    true
  );
$$;

commit;
