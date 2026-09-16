-- Keep the Control Board's canonical timing data aligned with station snapshots.
-- This read-only DTO change preserves existing authorization, row visibility and ACLs.
-- Historical admin blocks stay available when users pan to earlier dates.
CREATE OR REPLACE FUNCTION public.get_workshop_eligibility_snapshot()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_now timestamptz:=now();
  v_month_start timestamptz:=date_trunc('month',now() at time zone 'Australia/Perth') at time zone 'Australia/Perth';
begin
  perform public.require_pdc_role('viewer');
  return (WITH eligibility AS MATERIALIZED (
    SELECT e.* FROM public.workshop_stages s
    CROSS JOIN LATERAL public.workshop_station_eligibility(s.code) e
    WHERE s.active AND s.planner_enabled AND s.code=e.stage_code
  ), physical_stages AS MATERIALIZED (
    SELECT s.id,s.code,s.display_name,s.sort_order
    FROM public.workshop_stages s
    WHERE s.active AND s.planner_enabled AND s.is_physical AND NOT s.is_sublet
  ), physical_bays AS MATERIALIZED (
    SELECT b.id AS bay_id,b.stage_id,s.code AS stage_code,s.display_name AS stage_name,
      s.sort_order,b.bay_number,b.display_name,b.is_active,b.efficiency_percent,
      t.name AS technician_name
    FROM public.workshop_bays b
    JOIN physical_stages s ON s.id=b.stage_id
    LEFT JOIN public.workshop_technicians t ON t.id=b.default_technician_id
    WHERE NOT b.is_sublet_row
  ) SELECT jsonb_build_object(
    'generated_at',v_now,
    'semantics',jsonb_build_object(
      'count_label','Outstanding requirements',
      'candidate_authority','required canonical work item with completed=false; PMB or Yard Hold, or IT with Kewdale ETA',
      'legacy_pmb_stage_authority',false,
      'pipeline_authority','canonical station eligibility plus authoritative workshop bookings'
    ),
    'stages',(select coalesce(jsonb_agg(jsonb_build_object(
      'code',s.code,'display_name',s.display_name,'work_key',s.work_key,
      'planner_enabled',s.planner_enabled,'revision',public.workshop_current_station_revision(s.code),
      'aliases',(select coalesce(jsonb_agg(a.alias_value order by a.alias_value),'[]'::jsonb)
        from public.workshop_stage_aliases a where a.stage_code=s.code)
    ) order by s.sort_order),'[]'::jsonb)
      from public.workshop_stages s where s.active and s.planner_enabled),
    'candidates',(select coalesce(jsonb_agg(jsonb_build_object(
      'stage_code',e.stage_code,'work_key',e.work_key,
      'existing_booking',e.existing_booking,'schedule_enabled',e.schedule_enabled,'disabled_reason',e.disabled_reason,
      'vehicle',jsonb_build_object(
        'id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,'stock_number',v.stock_number,
        'toyota_order_number',v.toyota_order_number,'job_card_number',v.job_card_number,'key_number',v.key_number,
        'customer_name',v.customer_name,'vehicle_description',v.vehicle_description,'make',v.make,'model',v.model,
        'registration',v.registration,'current_location',coalesce(nullif(v.location_override,''),v.current_location),
      'automatic_location',v.current_location,'location_override',v.location_override,'pmb_stage',v.pmb_stage,
        'pmb_bay_stage',v.pmb_bay_stage,'pmb_bay_number',v.pmb_bay_number,'eta_to_kewdale',v.eta_to_kewdale,
        'active_workshop_booking_id',v.active_workshop_booking_id,'workshop_status',v.workshop_status,'version',v.version),
      'work_items',(select coalesce(jsonb_agg(jsonb_build_object(
        'vehicle_id',wi.vehicle_id,'work_key',wi.work_key,'required',wi.required,
        'completed',wi.completed,'completed_at',wi.completed_at)),'[]'::jsonb)
        from public.vehicle_work_items wi where wi.vehicle_id=v.id
          and public.workshop_stage_code_for_work_key(wi.work_key)=e.stage_code)
    ) order by e.stage_code,v.stock_number,v.id),'[]'::jsonb)
      from public.workshop_stages s
      join eligibility e on e.stage_code=s.code
      join public.vehicles v on v.id=e.vehicle_id and v.lifecycle_state='active' and v.deleted_at is null
      where s.code=e.stage_code and s.active and s.planner_enabled),
    'board',jsonb_build_object(
      'calendar',(SELECT coalesce(jsonb_object_agg(ws.key,ws.value),'{}'::jsonb)
        FROM public.workshop_settings ws
        WHERE ws.key IN ('day_start_time','day_end_time','working_week','closures','break_windows','overtime_windows','scheduling_increment_minutes')),
      'bays',(SELECT coalesce(jsonb_agg(jsonb_build_object(
        'bay_id',b.bay_id,'stage_id',b.stage_id,'stage_code',b.stage_code,
        'stage_name',b.stage_name,'bay_number',b.bay_number,'display_name',b.display_name,
        'is_active',b.is_active,'efficiency_percent',b.efficiency_percent,
        'technician_name',b.technician_name
      ) ORDER BY b.sort_order,b.bay_number NULLS LAST,b.bay_id),'[]'::jsonb)
        FROM physical_bays b),
      'bookings',(SELECT coalesce(jsonb_agg(jsonb_build_object(
        'booking_id',b.id,'vehicle_id',b.vehicle_id,'stage_code',s.code,
        'fitter_progress',pdc_fitter_private.progress(b.id),
        'bay_id',b.bay_id,'bay_number',pb.bay_number,'status',b.status,
        'scheduled_start_at',b.scheduled_start_at,'scheduled_end_at',b.scheduled_end_at,
        'actual_start_at',b.actual_start_at,'actual_end_at',b.actual_end_at,
        'stoppage_started_at',b.stoppage_started_at,
        'default_duration_minutes',b.default_duration_minutes,
        'capacity_base_minutes',coalesce(b.capacity_base_minutes,b.default_duration_minutes::numeric),
        'capacity_efficiency_percent',coalesce(b.capacity_efficiency_percent,100),
        'version',b.version,
        'vehicle',jsonb_build_object(
          'id',v.id,'stock_number',v.stock_number,'key_number',v.key_number,
          'job_card_number',v.job_card_number,'customer_name',v.customer_name,
          'vehicle_description',v.vehicle_description,'make',v.make,'model',v.model,
          'current_location',coalesce(nullif(v.location_override,''),v.current_location)
        )
      ) ORDER BY s.sort_order,pb.bay_number NULLS LAST,b.scheduled_start_at NULLS LAST,b.id),'[]'::jsonb)
        FROM public.workshop_bookings b
        JOIN physical_stages s ON s.id=b.stage_id
        JOIN public.vehicles v ON v.id=b.vehicle_id
          AND v.lifecycle_state='active' AND v.deleted_at IS NULL AND v.visible_on_board
        LEFT JOIN physical_bays pb ON pb.bay_id=b.bay_id AND pb.stage_id=b.stage_id
        WHERE b.deleted_at IS NULL AND b.status IN ('queued','planned','started','stoppage')
          AND (b.bay_id IS NULL OR pb.bay_id IS NOT NULL)),
      'admin_blocks',(SELECT coalesce(jsonb_agg(jsonb_build_object(
        'block_id',a.id,'stage_code',pb.stage_code,'bay_id',a.bay_id,'bay_number',pb.bay_number,
        'block_type',a.block_type,'label',a.label,'scheduled_start_at',a.scheduled_start_at,
        'scheduled_end_at',a.scheduled_end_at,'version',a.version
      ) ORDER BY pb.sort_order,pb.bay_number NULLS LAST,a.scheduled_start_at,a.id),'[]'::jsonb)
        FROM public.workshop_admin_blocks a
        JOIN physical_bays pb ON pb.bay_id=a.bay_id AND pb.stage_id=a.stage_id
        WHERE a.deleted_at IS NULL)
    ),
    'pipeline',(select coalesce(jsonb_agg(jsonb_build_object(
      'stage_code',s.code,
      'it',(select count(*) from eligibility e
        join public.vehicles v on v.id=e.vehicle_id
        where e.stage_code=s.code and e.current_location='IT'),
      'pmb_waiting',(select count(*) from eligibility e
        join public.vehicles v on v.id=e.vehicle_id
        where e.stage_code=s.code and e.current_location='PMB'
          and not exists(
            select 1 from public.workshop_bookings b
            where b.vehicle_id=v.id and b.stage_id=s.id and b.deleted_at is null
              and b.status in ('started','stoppage'))),
      'yard_hold_waiting',(select count(*) from eligibility e
        where e.stage_code=s.code and e.current_location='YH'
          and not exists(select 1 from public.workshop_bookings b
            where b.vehicle_id=e.vehicle_id and b.stage_id=s.id and b.deleted_at is null
              and b.status in ('started','stoppage'))),
      'in_bays',(select count(distinct b.vehicle_id) from public.workshop_bookings b
        join public.vehicles v on v.id=b.vehicle_id
        where b.stage_id=s.id and b.deleted_at is null and b.status='started' and b.bay_id is not null
          and v.lifecycle_state='active' and v.deleted_at is null),
      'average_bay_hours',(select coalesce(round(avg(greatest(0,
          extract(epoch from(v_now-coalesce(b.actual_start_at,b.scheduled_start_at)))/3600.0
          -coalesce(b.stoppage_accumulated_minutes,0)/60.0))::numeric,1),0)
        from public.workshop_bookings b
        join public.vehicles v on v.id=b.vehicle_id
        where b.stage_id=s.id and b.deleted_at is null and b.status='started' and b.bay_id is not null
          and v.lifecycle_state='active' and v.deleted_at is null),
      'stoppage',(select count(distinct b.vehicle_id) from public.workshop_bookings b
        join public.vehicles v on v.id=b.vehicle_id
        where b.stage_id=s.id and b.deleted_at is null and b.status='stoppage'
          and v.lifecycle_state='active' and v.deleted_at is null),
      'completed_mtd',(select count(distinct b.vehicle_id) from public.workshop_bookings b
        join public.vehicles v on v.id=b.vehicle_id
        where b.stage_id=s.id and b.deleted_at is null and b.status='completed'
          and b.actual_end_at>=v_month_start and b.actual_end_at<=v_now and v.deleted_at is null)
    ) order by s.sort_order),'[]'::jsonb)
      from public.workshop_stages s where s.active and s.planner_enabled)
  ));
end;
$function$;

-- Overview viewers already receive these exact revisions in the full DTO.
-- Keep the direct operator-only table RLS untouched; expose only this small,
-- approved-viewer projection for inexpensive missed-event reconciliation.
CREATE OR REPLACE FUNCTION public.get_workshop_overview_revisions()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog,public AS $function$
BEGIN
 PERFORM public.require_pdc_role('viewer');
 RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('stage_code',s.code,'revision',coalesce(r.revision,0)) ORDER BY s.sort_order,s.code),'[]'::jsonb)
  FROM public.workshop_stages s LEFT JOIN public.workshop_station_revision r ON r.stage_code=s.code
  WHERE s.active AND s.planner_enabled);
END $function$;
REVOKE ALL ON FUNCTION public.get_workshop_overview_revisions() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_workshop_overview_revisions() TO authenticated;
