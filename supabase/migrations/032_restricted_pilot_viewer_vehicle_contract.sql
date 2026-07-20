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

-- The pre-cutover core snapshot is intentionally broad and SECURITY DEFINER,
-- so RLS alone cannot protect it. Keep that contract for operator/importer/
-- administrator consumers, but refuse viewers before reading vehicle rows.
create or replace function public.get_vehicle_core_snapshot()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_role public.pdc_role;
  v_revision bigint;
  v_vehicles jsonb;
begin
  v_role := public.current_pdc_user_role();
  if v_role is null or not public.is_pdc_role('operator') then
    return public.vehicle_master_response(false, 'permission_denied', '{}'::jsonb);
  end if;

  select revision into v_revision
  from public.vehicle_master_revision
  where singleton;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', v.id,
      'permanent_vehicle_id', v.permanent_vehicle_id,
      'stock_number', v.stock_number,
      'vin', v.vin,
      'toyota_order_number', v.toyota_order_number,
      'job_card_number', v.job_card_number,
      'key_number', v.key_number,
      'customer_name', v.customer_name,
      'vehicle_description', v.vehicle_description,
      'salesperson_id', v.salesperson_id,
      'salesperson_reference', v.salesperson_reference,
      'make', v.make,
      'model', v.model,
      'registration', v.registration,
      'eta_to_kewdale', v.eta_to_kewdale,
      'arrival_reference_date', v.arrival_reference_date,
      'source_system', v.source_system,
      'source_batch_id', v.source_batch_id,
      'source_record_id', v.source_record_id,
      'version', v.version,
      'created_at', v.created_at,
      'updated_at', v.updated_at,
      'is_archived', (v.deleted_at is not null)
    ) order by coalesce(v.stock_number, v.permanent_vehicle_id), v.id
  ), '[]'::jsonb)
  into v_vehicles
  from public.vehicles v;

  return public.vehicle_master_response(true, 'ok', jsonb_build_object(
    'revision', coalesce(v_revision, 1),
    'caller_role', v_role,
    'capabilities', jsonb_build_object(
      'can_edit', public.is_pdc_role('operator'),
      'can_import', public.is_pdc_role('importer'),
      'can_administer', public.is_pdc_role('administrator')
    ),
    'vehicles', v_vehicles
  ));
end;
$$;

revoke all on function public.get_vehicle_core_snapshot() from public, anon, authenticated;
grant execute on function public.get_vehicle_core_snapshot() to authenticated;

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
