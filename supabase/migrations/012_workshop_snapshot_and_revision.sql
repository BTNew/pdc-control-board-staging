-- Workshop authoritative snapshot RPC.
-- Frontends must not depend on receiving every individual realtime event.
-- Instead, they subscribe to workshop_revision and, on change, call this
-- function to reload the complete authoritative state and rerender.

begin;

create or replace function public.get_workshop_snapshot(p_date_from date default null, p_date_to date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_from timestamptz := coalesce(p_date_from, current_date - interval '7 days');
  v_to timestamptz := coalesce(p_date_to, current_date + interval '21 days');
begin
  perform public.require_pdc_role('viewer');

  return jsonb_build_object(
    'revision', public.workshop_current_revision(),
    'generated_at', now(),
    'settings', (
      select coalesce(jsonb_object_agg(key, value), '{}'::jsonb)
      from public.workshop_settings
    ),
    'stages', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', id, 'code', code, 'display_name', display_name, 'sort_order', sort_order,
        'is_physical', is_physical, 'is_sublet', is_sublet, 'active', active
      ) order by sort_order), '[]'::jsonb)
      from public.workshop_stages
      where active = true
    ),
    'bays', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', id, 'stage_id', stage_id, 'bay_number', bay_number, 'code', code,
        'display_name', display_name, 'is_active', is_active, 'is_sublet_row', is_sublet_row,
        'default_technician_id', default_technician_id
      ) order by bay_number), '[]'::jsonb)
      from public.workshop_bays
      where is_active = true
    ),
    'technicians', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', id, 'name', name, 'role_type', role_type, 'active', active, 'can_fit_stages', can_fit_stages
      ) order by name), '[]'::jsonb)
      from public.workshop_technicians
      where active = true
    ),
    'bookings', (
      select coalesce(jsonb_agg(public.workshop_booking_snapshot(b.id)), '[]'::jsonb)
      from public.workshop_bookings b
      where b.status <> 'deleted'
        and b.scheduled_start_at < v_to
        and b.scheduled_end_at > v_from
    ),
    'active_stoppages', (
      select coalesce(jsonb_agg(public.workshop_booking_snapshot(b.id)), '[]'::jsonb)
      from public.workshop_bookings b
      where b.status = 'stoppage'
    ),
    'vehicles', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', v.id,
        'permanent_vehicle_id', v.permanent_vehicle_id,
        'stock_number', v.stock_number,
        'job_card_number', v.job_card_number,
        'customer_name', v.customer_name,
        'model', v.model,
        'current_location', v.current_location,
        'pmb_stage', v.pmb_stage,
        'active_workshop_booking_id', v.active_workshop_booking_id,
        'workshop_status', v.workshop_status,
        'version', v.version
      )), '[]'::jsonb)
      from public.vehicles v
      where v.id in (
        select vehicle_id from public.workshop_bookings
        where status <> 'deleted' and scheduled_start_at < v_to and scheduled_end_at > v_from
        union
        select vehicle_id from public.vehicle_parts_updates where parts_stoppage = true
      )
    ),
    'work_items', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'vehicle_id', wi.vehicle_id, 'work_key', wi.work_key, 'required', wi.required,
        'completed', wi.completed, 'completed_at', wi.completed_at
      )), '[]'::jsonb)
      from public.vehicle_work_items wi
      where wi.vehicle_id in (
        select vehicle_id from public.workshop_bookings
        where status <> 'deleted' and scheduled_start_at < v_to and scheduled_end_at > v_from
      )
    ),
    'parts_overrides', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', id, 'vehicle_id', vehicle_id, 'booking_id', booking_id, 'reason', reason,
        'approved_by_email', approved_by_email, 'approved_at', approved_at
      ) order by approved_at desc), '[]'::jsonb)
      from public.workshop_parts_overrides
      where approved_at > v_from
    )
  );
end;
$$;

revoke all on function public.get_workshop_snapshot(date, date) from public, anon;
grant execute on function public.get_workshop_snapshot(date, date) to authenticated;

commit;
