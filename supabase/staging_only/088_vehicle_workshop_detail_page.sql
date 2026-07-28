-- Staging-only viewer-readable Vehicle Detail work-and-booking projection.
-- Returns only canonical requirement and scheduling fields for one active vehicle.

begin;

create or replace function public.get_vehicle_workshop_detail(p_vehicle_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_vehicle_version bigint;
begin
  perform public.require_pdc_role('viewer');

  select v.version
    into v_vehicle_version
    from public.vehicles v
   where v.id = p_vehicle_id
     and v.lifecycle_state = 'active'
     and v.deleted_at is null;

  if not found then
    raise exception 'vehicle_not_found' using errcode = 'P0001';
  end if;

  return jsonb_build_object(
    'vehicle_id', p_vehicle_id,
    'vehicle_version', v_vehicle_version,
    'generated_at', now(),
    'requirements', coalesce((
      select jsonb_agg(jsonb_build_object(
        'work_item_id', wi.id,
        'work_key', wi.work_key,
        'stage_code', coalesce(
          public.workshop_stage_code_for_work_key(wi.work_key),
          case lower(btrim(wi.work_key))
            when 'parts' then 'PARTS'
            when 'sublet' then 'SUBLET'
            else upper(regexp_replace(btrim(wi.work_key), '[^a-zA-Z0-9]+', '_', 'g'))
          end
        ),
        'required', wi.required,
        'completed', wi.completed,
        'completed_at', wi.completed_at
      ) order by coalesce(s.sort_order, 999), wi.work_key, wi.id)
      from public.vehicle_work_items wi
      left join public.workshop_stages s
        on s.code = public.workshop_stage_code_for_work_key(wi.work_key)
      where wi.vehicle_id = p_vehicle_id
        and wi.required
    ), '[]'::jsonb),
    'bookings', coalesce((
      select jsonb_agg(jsonb_build_object(
        'booking_id', b.id,
        'booking_version', b.version,
        'stage_code', s.code,
        'stage_name', s.display_name,
        'bay_number', bay.bay_number,
        'bay_name', bay.display_name,
        'status', b.status,
        'scheduled_start_at', b.scheduled_start_at,
        'scheduled_end_at', b.scheduled_end_at,
        'default_duration_minutes', b.default_duration_minutes,
        'actual_start_at', b.actual_start_at,
        'actual_end_at', b.actual_end_at
      ) order by s.sort_order, b.scheduled_start_at, b.id)
      from public.workshop_bookings b
      join public.workshop_stages s on s.id = b.stage_id
      left join public.workshop_bays bay on bay.id = b.bay_id
      where b.vehicle_id = p_vehicle_id
        and b.deleted_at is null
        and b.status in ('queued', 'planned', 'started', 'stoppage', 'completed')
    ), '[]'::jsonb)
  );
end $function$;

revoke all on function public.get_vehicle_workshop_detail(uuid) from public, anon, authenticated;
grant execute on function public.get_vehicle_workshop_detail(uuid) to authenticated, service_role;

comment on function public.get_vehicle_workshop_detail(uuid) is
  'Viewer-readable narrow projection of one active vehicle canonical requirements and workshop booking times for Vehicle Detail; no customer or free-text notes.';

commit;
