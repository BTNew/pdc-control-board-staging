-- PDC Control Board Row Level Security policies
-- Apply after 001_initial_schema.sql.

create or replace function public.current_pdc_user_role()
returns public.pdc_role
language sql
stable
security definer
set search_path = public
as $$
  select role
  from public.pdc_user_roles
  where email = lower(coalesce(auth.jwt() ->> 'email', ''))
    and active = true
  limit 1;
$$;

create or replace function public.is_pdc_role(required_role public.pdc_role)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when public.current_pdc_user_role() = 'administrator' then true
    when required_role = 'viewer' and public.current_pdc_user_role() in ('viewer', 'operator', 'importer', 'administrator') then true
    when required_role = 'operator' and public.current_pdc_user_role() in ('operator', 'importer', 'administrator') then true
    when required_role = 'importer' and public.current_pdc_user_role() in ('importer', 'administrator') then true
    when required_role = 'administrator' and public.current_pdc_user_role() = 'administrator' then true
    else false
  end;
$$;

create or replace function public.current_actor_email()
returns text
language sql
stable
as $$
  select lower(coalesce(auth.jwt() ->> 'email', ''));
$$;

alter table public.pdc_user_roles enable row level security;
alter table public.vehicles enable row level security;
alter table public.vehicle_aliases enable row level security;
alter table public.vehicle_work_items enable row level security;
alter table public.vehicle_movements enable row level security;
alter table public.vehicle_parts_updates enable row level security;
alter table public.import_runs enable row level security;
alter table public.salespeople enable row level security;
alter table public.sublet_providers enable row level security;
alter table public.deleted_completed_vehicles enable row level security;
alter table public.audit_events enable row level security;

-- Approved users may see their own role row. Administrators may manage all role rows.
create policy pdc_user_roles_select_self_or_admin
on public.pdc_user_roles
for select
to authenticated
using (email = public.current_actor_email() or public.is_pdc_role('administrator'));

create policy pdc_user_roles_admin_insert
on public.pdc_user_roles
for insert
to authenticated
with check (public.is_pdc_role('administrator'));

create policy pdc_user_roles_admin_update
on public.pdc_user_roles
for update
to authenticated
using (public.is_pdc_role('administrator'))
with check (public.is_pdc_role('administrator'));

-- Vehicle data is hidden from signed-out and unapproved users.
create policy vehicles_select_approved
on public.vehicles
for select
to authenticated
using (public.is_pdc_role('viewer'));

create policy vehicles_operator_insert
on public.vehicles
for insert
to authenticated
with check (public.is_pdc_role('operator'));

create policy vehicles_operator_update
on public.vehicles
for update
to authenticated
using (public.is_pdc_role('operator'))
with check (public.is_pdc_role('operator'));

-- No direct deletes from browser. Use protected RPC to mark deleted/restored.

create policy vehicle_aliases_select_approved
on public.vehicle_aliases
for select
to authenticated
using (public.is_pdc_role('viewer'));

create policy vehicle_aliases_importer_write
on public.vehicle_aliases
for all
to authenticated
using (public.is_pdc_role('importer'))
with check (public.is_pdc_role('importer'));

create policy work_items_select_approved
on public.vehicle_work_items
for select
to authenticated
using (public.is_pdc_role('viewer'));

create policy work_items_operator_write
on public.vehicle_work_items
for all
to authenticated
using (public.is_pdc_role('operator'))
with check (public.is_pdc_role('operator'));

create policy movements_select_approved
on public.vehicle_movements
for select
to authenticated
using (public.is_pdc_role('viewer'));

create policy movements_operator_insert
on public.vehicle_movements
for insert
to authenticated
with check (public.is_pdc_role('operator'));

create policy parts_select_approved
on public.vehicle_parts_updates
for select
to authenticated
using (public.is_pdc_role('viewer'));

create policy parts_operator_write
on public.vehicle_parts_updates
for all
to authenticated
using (public.is_pdc_role('operator'))
with check (public.is_pdc_role('operator'));

create policy import_runs_select_approved
on public.import_runs
for select
to authenticated
using (public.is_pdc_role('viewer'));

create policy import_runs_importer_write
on public.import_runs
for all
to authenticated
using (public.is_pdc_role('importer'))
with check (public.is_pdc_role('importer'));

create policy salespeople_select_approved
on public.salespeople
for select
to authenticated
using (public.is_pdc_role('viewer'));

create policy salespeople_admin_write
on public.salespeople
for all
to authenticated
using (public.is_pdc_role('administrator'))
with check (public.is_pdc_role('administrator'));

create policy sublet_providers_select_approved
on public.sublet_providers
for select
to authenticated
using (public.is_pdc_role('viewer'));

create policy sublet_providers_admin_write
on public.sublet_providers
for all
to authenticated
using (public.is_pdc_role('administrator'))
with check (public.is_pdc_role('administrator'));

create policy deleted_completed_select_approved
on public.deleted_completed_vehicles
for select
to authenticated
using (public.is_pdc_role('viewer'));

create policy deleted_completed_operator_insert
on public.deleted_completed_vehicles
for insert
to authenticated
with check (public.is_pdc_role('operator'));

create policy audit_events_select_approved
on public.audit_events
for select
to authenticated
using (public.is_pdc_role('viewer'));

create policy audit_events_insert_approved
on public.audit_events
for insert
to authenticated
with check (public.is_pdc_role('operator'));
