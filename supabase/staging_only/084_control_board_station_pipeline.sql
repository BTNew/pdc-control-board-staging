-- Staging-only authoritative per-station Control Board pipeline metrics.
-- The existing eligibility candidates remain unchanged. Metrics are derived
-- from shared vehicles, canonical eligibility, and workshop bookings.

begin;

create or replace function public.get_workshop_eligibility_snapshot()
returns jsonb
language plpgsql
stable security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_now timestamptz := now();
  v_month_start timestamptz := date_trunc('month', now() at time zone 'Australia/Perth') at time zone 'Australia/Perth';
begin
  perform public.require_pdc_role('viewer');
  return jsonb_build_object(
    'generated_at',v_now,
    'semantics',jsonb_build_object(
      'count_label','Outstanding requirements',
      'candidate_authority','required canonical work item with completed=false',
      'legacy_pmb_stage_authority',false,
      'pipeline',jsonb_build_object(
        'it','outstanding canonical station work where current_location=IT',
        'pmb_waiting','outstanding canonical station work at PMB without started or stopped work in that station',
        'in_bays','active started station bookings assigned to a bay',
        'average_bay_hours','average elapsed started-booking hours excluding accumulated stoppage minutes',
        'stoppage','active station bookings with status=stoppage',
        'completed_mtd','distinct vehicles with a completed station booking during the current Australia/Perth month')),
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
        'toyota_order_number',v.toyota_order_number,'job_card_number',v.job_card_number,'make',v.make,'model',v.model,
        'registration',v.registration,'current_location',v.current_location,'pmb_stage',v.pmb_stage,
        'pmb_bay_stage',v.pmb_bay_stage,'pmb_bay_number',v.pmb_bay_number,'eta_to_kewdale',v.eta_to_kewdale,
        'active_workshop_booking_id',v.active_workshop_booking_id,'workshop_status',v.workshop_status,'version',v.version),
      'work_items',(select coalesce(jsonb_agg(jsonb_build_object(
        'vehicle_id',wi.vehicle_id,'work_key',wi.work_key,'required',wi.required,
        'completed',wi.completed,'completed_at',wi.completed_at)),'[]'::jsonb)
        from public.vehicle_work_items wi where wi.vehicle_id=v.id
          and public.workshop_stage_code_for_work_key(wi.work_key)=e.stage_code)
    ) order by e.stage_code,v.stock_number,v.id),'[]'::jsonb)
      from public.workshop_stages s
      cross join lateral public.workshop_station_eligibility(s.code)e
      join public.vehicles v on v.id=e.vehicle_id and v.lifecycle_state='active' and v.deleted_at is null
      where s.code=e.stage_code and s.active and s.planner_enabled),
    'pipeline',(select coalesce(jsonb_agg(jsonb_build_object(
      'stage_code',s.code,
      'it',(select count(*) from public.workshop_station_eligibility(s.code)e
        join public.vehicles v on v.id=e.vehicle_id
        where v.lifecycle_state='active' and v.deleted_at is null and upper(btrim(coalesce(v.current_location,'')))='IT'),
      'pmb_waiting',(select count(*) from public.workshop_station_eligibility(s.code)e
        join public.vehicles v on v.id=e.vehicle_id
        where v.lifecycle_state='active' and v.deleted_at is null
          and upper(btrim(coalesce(v.current_location,'')))='PMB'
          and not exists (
            select 1 from public.workshop_bookings b
            where b.vehicle_id=v.id and b.stage_id=s.id and b.deleted_at is null
              and b.status in ('started','stoppage'))),
      'in_bays',(select count(distinct b.vehicle_id) from public.workshop_bookings b
        join public.vehicles v on v.id=b.vehicle_id
        where b.stage_id=s.id and b.deleted_at is null and b.status='started' and b.bay_id is not null
          and v.lifecycle_state='active' and v.deleted_at is null),
      'average_bay_hours',(select coalesce(round(avg(greatest(0,
          extract(epoch from (v_now-coalesce(b.actual_start_at,b.scheduled_start_at)))/3600.0
          - coalesce(b.stoppage_accumulated_minutes,0)/60.0))::numeric,1),0)
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
          and b.actual_end_at>=v_month_start and b.actual_end_at<=v_now
          and v.deleted_at is null)
    ) order by s.sort_order),'[]'::jsonb)
      from public.workshop_stages s where s.active and s.planner_enabled)
  );
end $function$;

revoke all on function public.get_workshop_eligibility_snapshot() from public, anon;
grant execute on function public.get_workshop_eligibility_snapshot() to authenticated, service_role;

comment on function public.get_workshop_eligibility_snapshot() is
  'Viewer-readable canonical all-station eligibility plus authoritative Control Board pipeline metrics; mutations remain separately role-gated.';

commit;
