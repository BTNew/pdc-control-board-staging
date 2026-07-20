-- Restricted live-pilot account-plan remediation.
-- Keep broad vehicle rows available to operator/importer/administrator roles,
-- while viewers use a security-definer contract that exposes only the six
-- approved lifecycle fields for the exact retained pilot source batch.

begin;

-- The authenticated database role retains SELECT because operators and higher
-- roles require direct vehicle reads. RLS now denies all direct rows to viewers.
drop policy if exists vehicles_select_approved on public.vehicles;
drop policy if exists vehicles_select_operator on public.vehicles;
create policy vehicles_select_operator
on public.vehicles
for select
to authenticated
using (public.is_pdc_role('operator'));

create or replace function public.get_restricted_pilot_vehicle_snapshot(
  p_vehicle_id uuid default null
)
returns table (
  id uuid,
  version integer,
  current_location text,
  lifecycle_state public.vehicle_lifecycle_state,
  workshop_status text,
  active_workshop_booking_id uuid
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.require_pdc_role('viewer');

  return query
  select
    v.id,
    v.version,
    v.current_location,
    v.lifecycle_state,
    v.workshop_status,
    v.active_workshop_booking_id
  from public.vehicles v
  where v.source_system = 'browser_local_c4'
    and v.source_batch_id = 'C6-REAL-PILOT-7D862ABBE37B'
    and (p_vehicle_id is null or v.id = p_vehicle_id)
  order by v.id;
end;
$$;

revoke all on function public.get_restricted_pilot_vehicle_snapshot(uuid) from public, anon, authenticated;
grant execute on function public.get_restricted_pilot_vehicle_snapshot(uuid) to authenticated;

comment on function public.get_restricted_pilot_vehicle_snapshot(uuid) is
  'Restricted staging pilot: authenticated approved users receive only six lifecycle fields from the exact retained 25-vehicle source batch.';

commit;
