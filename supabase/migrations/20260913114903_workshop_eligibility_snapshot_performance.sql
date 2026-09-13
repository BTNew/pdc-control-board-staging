-- STAGING ONLY: share one eligibility result per station and retain Yard Hold candidates.
-- No operational data or booking rules change. Existing reader permissions are retained.
DO $guard$ BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 OR NOT EXISTS(SELECT 1 FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')
 THEN RAISE EXCEPTION 'Staging required'; END IF;
 IF md5(pg_get_functiondef('public.get_workshop_eligibility_snapshot()'::regprocedure))<>'4d7bc301ef4c979ad6ce4841808f92f1'
 OR md5(pg_get_functiondef('public.workshop_station_eligibility(text)'::regprocedure))<>'c6eb07482c069125619b3ced7197327f'
 THEN RAISE EXCEPTION 'Eligibility functions changed since reviewed'; END IF;
END $guard$;
CREATE OR REPLACE FUNCTION public.workshop_station_eligibility(p_stage_code text)
 RETURNS TABLE(vehicle_id uuid, stage_code text, work_key text, current_location text, eta_to_kewdale date, existing_booking boolean, schedule_enabled boolean, disabled_reason text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
 WITH station AS(
  SELECT s.id,s.code,s.work_key FROM public.workshop_stages s
  WHERE s.code=public.workshop_canonical_stage_code(p_stage_code) AND s.active AND s.planner_enabled
 ),outstanding AS(
  SELECT wi.vehicle_id,st.id stage_id,st.code,st.work_key
  FROM public.vehicle_work_items wi CROSS JOIN station st
  WHERE public.workshop_stage_code_for_work_key(wi.work_key)=st.code AND wi.required AND NOT wi.completed
  GROUP BY wi.vehicle_id,st.id,st.code,st.work_key
 ),active_booking AS(
  SELECT DISTINCT b.vehicle_id,st.code FROM public.workshop_bookings b
  JOIN public.workshop_stages s ON s.id=b.stage_id JOIN station st ON st.code=s.code
  WHERE b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage')
 ),eligible AS MATERIALIZED (
 SELECT v.id,o.code,o.work_key,public.workshop_location_code(v.current_location) current_location,v.eta_to_kewdale,
  (ab.vehicle_id IS NOT NULL) existing_booking,o.stage_id
 FROM outstanding o JOIN public.vehicles v ON v.id=o.vehicle_id
 LEFT JOIN active_booking ab ON ab.vehicle_id=v.id AND ab.code=o.code
 WHERE v.lifecycle_state='active' AND v.deleted_at IS NULL AND v.visible_on_board
   AND public.workshop_location_code(v.current_location) IN('PMB','YH','IT')
   AND (public.workshop_location_code(v.current_location)<>'IT' OR v.eta_to_kewdale IS NOT NULL)
 ),estimated AS MATERIALIZED (
 SELECT e.*,public.workshop_vehicle_stage_estimated_duration_minutes(e.id,e.stage_id) duration_minutes
 FROM eligible e
 )
 SELECT e.id,e.code,e.work_key,e.current_location,e.eta_to_kewdale,e.existing_booking,
   e.duration_minutes IS NOT NULL,
   CASE WHEN e.duration_minutes IS NULL THEN 'estimated_duration_missing' ELSE NULL::text END
 FROM estimated e
$function$
;

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
        'toyota_order_number',v.toyota_order_number,'job_card_number',v.job_card_number,
        'customer_name',v.customer_name,'vehicle_description',v.vehicle_description,'make',v.make,'model',v.model,
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
      join eligibility e on e.stage_code=s.code
      join public.vehicles v on v.id=e.vehicle_id and v.lifecycle_state='active' and v.deleted_at is null
      where s.code=e.stage_code and s.active and s.planner_enabled),
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
$function$
;
