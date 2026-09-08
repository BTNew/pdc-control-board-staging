CREATE OR REPLACE FUNCTION public.get_vehicle_workshop_detail(p_vehicle_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare v_vehicle_version bigint;
begin
  perform public.require_pdc_role('viewer');
  select v.version into v_vehicle_version from public.vehicles v
   where v.id=p_vehicle_id and v.lifecycle_state IN('active','rft','completed') and v.deleted_at is null;
  if not found then raise exception 'vehicle_not_found' using errcode='P0001'; end if;
  return jsonb_build_object(
    'vehicle_id',p_vehicle_id,'vehicle_version',v_vehicle_version,'generated_at',now(),
    'requirements',coalesce((select jsonb_agg(jsonb_build_object(
      'work_item_id',wi.id,'work_key',wi.work_key,
      'stage_code',coalesce(public.workshop_stage_code_for_work_key(wi.work_key),case lower(btrim(wi.work_key)) when 'parts' then 'PARTS' when 'sublet' then 'SUBLET' else upper(regexp_replace(btrim(wi.work_key),'[^a-zA-Z0-9]+','_','g')) end),
      'required',wi.required,'completed',wi.completed,'completed_at',wi.completed_at)
      order by coalesce(s.sort_order,999),wi.work_key,wi.id)
      from public.vehicle_work_items wi left join public.workshop_stages s on s.code=public.workshop_stage_code_for_work_key(wi.work_key)
      where wi.vehicle_id=p_vehicle_id and wi.required),'[]'::jsonb),
    'bookings',coalesce((select jsonb_agg(jsonb_build_object(
      'booking_id',b.id,'booking_version',b.version,'stage_code',s.code,'stage_name',s.display_name,
      'bay_number',bay.bay_number,'bay_name',bay.display_name,'status',b.status,
      'scheduled_start_at',b.scheduled_start_at,'scheduled_end_at',b.scheduled_end_at,
      'default_duration_minutes',b.default_duration_minutes,'actual_start_at',b.actual_start_at,'actual_end_at',b.actual_end_at)
      order by s.sort_order,b.scheduled_start_at,b.id)
      from public.workshop_bookings b join public.workshop_stages s on s.id=b.stage_id left join public.workshop_bays bay on bay.id=b.bay_id
      where b.vehicle_id=p_vehicle_id and b.deleted_at is null and b.status in ('queued','planned','started','stoppage','completed')),'[]'::jsonb),
    'line_adjustments',coalesce((select jsonb_agg(jsonb_build_object(
      'adjustment_id',a.adjustment_id,'line_key',a.line_key,'source_kind',a.source_kind,'stage_code',a.stage_code,
      'description',a.description,'estimated_hours',a.estimated_hours,'correction_origin',a.correction_origin,'manual_assignment_locked',a.manual_assignment_locked,'version',a.version,'created_at',a.created_at,'updated_at',a.updated_at)
      order by a.created_at,a.adjustment_id) from public.vehicle_workshop_line_adjustments a where a.vehicle_id=p_vehicle_id and a.active),'[]'::jsonb)
  );
end;
$function$
