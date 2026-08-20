-- Staging only: one-dashboard Sales view backed by the canonical vehicle row.
-- Production is intentionally untouched.

alter table public.vehicles
  add column if not exists sales_tint_raised boolean not null default false,
  add column if not exists sales_build_po_raised boolean not null default false,
  add column if not exists sales_build_complete boolean not null default false,
  add column if not exists sales_tray_ordered boolean not null default false,
  add column if not exists sales_tray_complete boolean not null default false,
  add column if not exists sales_preparation_updated_at timestamptz,
  add column if not exists sales_preparation_updated_by uuid references auth.users(id);

create or replace function public.pdc_vehicle_sales_dashboard_json(p_vehicle_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  select coalesce((
    select jsonb_build_object(
      'salesperson_code', coalesce(nullif(s.code, ''), nullif(v.salesperson_reference, ''), ''),
      'salesperson_name', coalesce(nullif(s.name, ''), nullif(v.salesperson_reference, ''), ''),
      'sales_preparation', jsonb_build_object(
        'tint_raised', v.sales_tint_raised,
        'build_po_raised', v.sales_build_po_raised,
        'build_complete', v.sales_build_complete,
        'tray_ordered', v.sales_tray_ordered,
        'tray_complete', v.sales_tray_complete,
        'updated_at', v.sales_preparation_updated_at,
        'updated_by', v.sales_preparation_updated_by
      ),
      'workshop_bookings', coalesce((
        select jsonb_agg(jsonb_build_object(
          'booking_id', b.id,
          'stage_code', st.code,
          'stage_name', st.display_name,
          'bay_name', bay.display_name,
          'status', b.status,
          'scheduled_start_at', b.scheduled_start_at,
          'scheduled_end_at', b.scheduled_end_at,
          'actual_start_at', b.actual_start_at,
          'actual_end_at', b.actual_end_at,
          'stoppage_reason', b.stoppage_reason,
          'updated_at', b.updated_at
        ) order by coalesce(b.actual_start_at, b.scheduled_start_at), st.sort_order, b.id)
        from public.workshop_bookings b
        join public.workshop_stages st on st.id = b.stage_id
        left join public.workshop_bays bay on bay.id = b.bay_id
        where b.vehicle_id = v.id and b.deleted_at is null
      ), '[]'::jsonb)
    )
    from public.vehicles v
    left join public.salespeople s on s.id = v.salesperson_id
    where v.id = p_vehicle_id
  ), '{}'::jsonb)
$function$;

revoke all on function public.pdc_vehicle_sales_dashboard_json(uuid) from public, anon, authenticated;

-- Preserve the exact pre-sales snapshot so the public RPC remains a single,
-- composable projection over the canonical vehicles table.
create or replace function public.get_pdc_email_vehicle_location_snapshot_pre_310()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  r jsonb;
  rows jsonb;
begin
  r := public.get_pdc_email_vehicle_location_snapshot_pre_174();
  if not coalesce((r->>'ok')::boolean, false) then return r; end if;
  select coalesce(jsonb_agg(
    x
    || public.pdc_vehicle_key_number_json((x->>'id')::uuid)
    || public.pdc_vehicle_operational_json((x->>'id')::uuid)
  ), '[]'::jsonb)
  into rows
  from jsonb_array_elements(coalesce(r#>'{data,vehicles}', '[]'::jsonb)) x;
  return jsonb_set(r, '{data,vehicles}', rows, true);
end
$function$;

revoke all on function public.get_pdc_email_vehicle_location_snapshot_pre_310() from public, anon, authenticated;

create or replace function public.get_pdc_email_vehicle_location_snapshot()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  r jsonb;
  rows jsonb;
begin
  r := public.get_pdc_email_vehicle_location_snapshot_pre_310();
  if not coalesce((r->>'ok')::boolean, false) then return r; end if;
  select coalesce(jsonb_agg(
    x || public.pdc_vehicle_sales_dashboard_json((x->>'id')::uuid)
  ), '[]'::jsonb)
  into rows
  from jsonb_array_elements(coalesce(r#>'{data,vehicles}', '[]'::jsonb)) x;
  return jsonb_set(r, '{data,vehicles}', rows, true);
end
$function$;

revoke all on function public.get_pdc_email_vehicle_location_snapshot() from public, anon;
grant execute on function public.get_pdc_email_vehicle_location_snapshot() to authenticated;

create or replace function public.update_pdc_vehicle_sales_preparation(
  p_vehicle_id uuid,
  p_expected_version integer,
  p_field text,
  p_value boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_role text := coalesce(public.current_pdc_user_role()::text, '');
  v_actor uuid := auth.uid();
  v_actor_email text;
  v_before public.vehicles%rowtype;
  v_after public.vehicles%rowtype;
  v_field text := lower(btrim(coalesce(p_field, '')));
begin
  if v_actor is null or v_role not in ('viewer', 'operator', 'administrator') then
    return jsonb_build_object('ok', false, 'code', 'not_authorized');
  end if;
  if v_field not in ('tint_raised', 'build_po_raised', 'build_complete', 'tray_ordered', 'tray_complete') then
    return jsonb_build_object('ok', false, 'code', 'invalid_field');
  end if;

  select * into v_before from public.vehicles where id = p_vehicle_id for update;
  if not found or v_before.deleted_at is not null then
    return jsonb_build_object('ok', false, 'code', 'vehicle_not_found');
  end if;
  if v_before.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'code', 'version_conflict', 'data',
      jsonb_build_object('vehicle_id', v_before.id, 'vehicle_version', v_before.version));
  end if;

  update public.vehicles
  set sales_tint_raised = case when v_field = 'tint_raised' then p_value else sales_tint_raised end,
      sales_build_po_raised = case when v_field = 'build_po_raised' then p_value else sales_build_po_raised end,
      sales_build_complete = case when v_field = 'build_complete' then p_value else sales_build_complete end,
      sales_tray_ordered = case when v_field = 'tray_ordered' then p_value else sales_tray_ordered end,
      sales_tray_complete = case when v_field = 'tray_complete' then p_value else sales_tray_complete end,
      sales_preparation_updated_at = clock_timestamp(),
      sales_preparation_updated_by = v_actor,
      updated_at = clock_timestamp(),
      updated_by = v_actor,
      version = version + 1
  where id = p_vehicle_id
  returning * into v_after;

  select email into v_actor_email
  from public.pdc_user_roles
  where auth_user_id = v_actor and active and account_status::text = 'approved'
  order by updated_at desc limit 1;

  insert into public.audit_events(
    action, table_name, row_id, vehicle_id, actor_id, actor_email,
    before_data, after_data, metadata
  ) values (
    'sales_preparation_updated', 'vehicles', v_after.id, v_after.id, v_actor, v_actor_email,
    jsonb_build_object('field', v_field, 'value', case v_field
      when 'tint_raised' then v_before.sales_tint_raised
      when 'build_po_raised' then v_before.sales_build_po_raised
      when 'build_complete' then v_before.sales_build_complete
      when 'tray_ordered' then v_before.sales_tray_ordered
      else v_before.sales_tray_complete end),
    jsonb_build_object('field', v_field, 'value', p_value),
    jsonb_build_object('scope', 'staging_sales_dashboard')
  );

  return jsonb_build_object(
    'ok', true,
    'code', 'sales_preparation_updated',
    'data', jsonb_build_object(
      'vehicle_id', v_after.id,
      'vehicle_version', v_after.version,
      'sales_preparation', public.pdc_vehicle_sales_dashboard_json(v_after.id)->'sales_preparation'
    )
  );
end
$function$;

revoke all on function public.update_pdc_vehicle_sales_preparation(uuid, integer, text, boolean) from public, anon;
grant execute on function public.update_pdc_vehicle_sales_preparation(uuid, integer, text, boolean) to authenticated;
