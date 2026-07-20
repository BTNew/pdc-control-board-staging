-- Close the remaining viewer bypass through the broad legacy vehicle-master
-- SECURITY DEFINER snapshot. Keep that contract for operator/importer/admin
-- consumers while viewers use only the restricted six-field pilot RPC.

begin;

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

comment on function public.get_vehicle_core_snapshot() is
  'Broad legacy vehicle snapshot restricted to operator/importer/administrator roles; viewers must use the restricted pilot contract.';

commit;
