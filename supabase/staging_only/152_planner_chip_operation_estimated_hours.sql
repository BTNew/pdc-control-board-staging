-- Staging-only: planner chip duration follows authoritative operation-line estimates.
-- Removes the original three-hour test/default duration from new unscheduled work.
begin;

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd') then
    raise exception 'PDC_STAGING_SENTINEL_MISMATCH';
  end if;
  if to_regclass('public.pdc_authenticated_email_operation_lines') is null
     or to_regclass('public.vehicle_workshop_line_adjustments') is null then
    raise exception 'PDC_MIGRATION_152_DEPENDENCY_MISSING';
  end if;
end;
$guard$;

create or replace function public.workshop_vehicle_stage_estimated_hours(p_vehicle_id uuid,p_stage_code text)
returns numeric
language sql
stable
security definer
set search_path=pg_catalog,public
as $fn$
  with source_lines as (
    select coalesce(a.stage_code,public.workshop_stage_code_for_work_key(ol.work_key)) stage_code,
           coalesce(a.estimated_hours,ol.estimated_hours) estimated_hours
      from public.pdc_authenticated_email_operation_lines ol
      left join public.vehicle_workshop_line_adjustments a
        on a.vehicle_id=ol.vehicle_id
       and a.line_key='source:'||ol.operation_line_id::text
       and a.active
     where ol.vehicle_id=p_vehicle_id
  ), manual_lines as (
    select a.stage_code,a.estimated_hours
      from public.vehicle_workshop_line_adjustments a
     where a.vehicle_id=p_vehicle_id and a.active and a.source_kind='manual'
  )
  select nullif(round(sum(q.estimated_hours)::numeric,2),0)
    from (select * from source_lines union all select * from manual_lines) q
   where q.stage_code=public.workshop_canonical_stage_code(p_stage_code)
     and q.estimated_hours>0
$fn$;
revoke all on function public.workshop_vehicle_stage_estimated_hours(uuid,text) from public,anon,authenticated;

create or replace function public.workshop_planner_booking_dto(p_booking_id uuid)
returns jsonb language sql stable security definer set search_path=pg_catalog,public as $$
 with aa as(
  select a.booking_id,a.technician_id,t.name technician_name,a.assignment_type
  from public.workshop_booking_assignments a join public.workshop_technicians t on t.id=a.technician_id
  where a.booking_id=p_booking_id and a.released_at is null
  order by case when a.assignment_type='primary' then 0 else 1 end,a.assigned_at desc limit 1)
 select jsonb_build_object(
  'booking_id',b.id,'vehicle_id',b.vehicle_id,
  'stage',jsonb_build_object('id',s.id,'code',s.code,'display_name',s.display_name,'is_physical',s.is_physical,'work_key',s.work_key),
  'bay',case when bay.id is null then null else jsonb_build_object('id',bay.id,'bay_number',bay.bay_number,'code',bay.code,'display_name',bay.display_name) end,
  'status',b.status,'scheduled_start_at',b.scheduled_start_at,'scheduled_end_at',b.scheduled_end_at,
  'default_duration_minutes',b.default_duration_minutes,
  'estimated_operation_hours',public.workshop_vehicle_stage_estimated_hours(b.vehicle_id,s.code),
  'actual_start_at',b.actual_start_at,'actual_end_at',b.actual_end_at,
  'stoppage_reason',b.stoppage_reason,'stoppage_started_at',b.stoppage_started_at,
  'stoppage_accumulated_minutes',b.stoppage_accumulated_minutes,'version',b.version,
  'assignment',case when aa.technician_id is null then null else jsonb_build_object(
    'technician_id',aa.technician_id,'technician_name',aa.technician_name,'assignment_type',aa.assignment_type) end)
 from public.workshop_bookings b
 join public.vehicles v on v.id=b.vehicle_id and v.lifecycle_state='active' and v.deleted_at is null
 join public.workshop_stages s on s.id=b.stage_id
 left join public.workshop_bays bay on bay.id=b.bay_id
 left join aa on aa.booking_id=b.id where b.id=p_booking_id and b.deleted_at is null
$$;
revoke all on function public.workshop_planner_booking_dto(uuid) from public,anon,authenticated;

create or replace function public.get_station_workshop_snapshot(p_stage_code text,p_date_from date,p_date_to date)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare v_stage text; v_stage_id uuid; v_from timestamptz; v_to timestamptz; v_ids uuid[];
begin
 perform public.workshop_require_planner_operator();
 v_stage:=public.workshop_canonical_stage_code(p_stage_code);
 select id into v_stage_id from public.workshop_stages where code=v_stage and active and planner_enabled;
 if v_stage_id is null then raise exception 'Unknown, inactive or planner-disabled workshop station' using errcode='22023'; end if;
 if p_date_from is null or p_date_to is null or p_date_to<p_date_from or p_date_to>p_date_from+31 then raise exception 'Invalid station planner date range' using errcode='22023'; end if;
 v_from:=p_date_from::timestamp at time zone 'Australia/Perth'; v_to:=(p_date_to+1)::timestamp at time zone 'Australia/Perth';
 select coalesce(array_agg(distinct q.vehicle_id),'{}'::uuid[]) into v_ids from(
  select e.vehicle_id from public.workshop_station_eligibility(v_stage)e
  union
  select b.vehicle_id from public.workshop_bookings b join public.vehicles v on v.id=b.vehicle_id and v.lifecycle_state='active' and v.deleted_at is null
  where b.stage_id=v_stage_id and b.deleted_at is null and b.status in('queued','planned','started','stoppage','completed')
   and((b.status in('queued','planned') and b.scheduled_start_at<v_to and b.scheduled_end_at>v_from)
    or(b.status in('started','stoppage') and b.scheduled_start_at<v_to)
    or(b.status='completed' and b.actual_end_at>=v_from and b.actual_end_at<v_to))
 )q;
 return jsonb_build_object(
  'revision',public.workshop_current_station_revision(v_stage),'generated_at',now(),
  'semantics',jsonb_build_object('outstanding_candidates','required canonical work items not completed and location-visible','unscheduled_candidates','outstanding candidates without any active booking','selected_date_bookings','scheduled rows intersecting the date plus started or stopped work carried forward until resolved'),
  'scope',jsonb_build_object('stage_code',v_stage,'date_from',p_date_from,'date_to',p_date_to),
  'counts',jsonb_build_object(
   'outstanding_candidates',(select count(*) from public.workshop_station_eligibility(v_stage)),
   'unscheduled_candidates',(select count(*) from public.workshop_station_eligibility(v_stage)e where not e.existing_booking),
   'selected_date_bookings',(select count(*) from public.workshop_bookings b join public.vehicles v on v.id=b.vehicle_id and v.lifecycle_state='active' and v.deleted_at is null where b.stage_id=v_stage_id and b.deleted_at is null and b.status in('queued','planned','started','stoppage','completed') and((b.status in('queued','planned') and b.scheduled_start_at<v_to and b.scheduled_end_at>v_from)or(b.status in('started','stoppage') and b.scheduled_start_at<v_to)or(b.status='completed' and b.actual_end_at>=v_from and b.actual_end_at<v_to)))),
  'stages',(select jsonb_agg(jsonb_build_object('id',s.id,'code',s.code,'display_name',s.display_name,'is_physical',s.is_physical,'work_key',s.work_key)) from public.workshop_stages s where s.id=v_stage_id),
  'bays',(select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'bay_number',b.bay_number,'code',b.code,'display_name',b.display_name) order by b.bay_number),'[]'::jsonb) from public.workshop_bays b where b.stage_id=v_stage_id and b.is_active),
  'outstanding_candidates',(select coalesce(jsonb_agg(jsonb_build_object('vehicle_id',e.vehicle_id,'existing_booking',e.existing_booking,'schedule_enabled',e.schedule_enabled,'disabled_reason',e.disabled_reason,'estimated_hours',public.workshop_vehicle_stage_estimated_hours(e.vehicle_id,v_stage),'requirements',(select coalesce(jsonb_agg(jsonb_build_object('vehicle_id',wi.vehicle_id,'work_key',wi.work_key,'required',wi.required,'completed',wi.completed,'completed_at',wi.completed_at) order by wi.work_key),'[]'::jsonb) from public.vehicle_work_items wi where wi.vehicle_id=e.vehicle_id and wi.required and not wi.completed)) order by e.vehicle_id),'[]'::jsonb) from public.workshop_station_eligibility(v_stage)e),
  'bookings',(select coalesce(jsonb_agg(public.workshop_planner_booking_dto(b.id) order by b.scheduled_start_at,b.id),'[]'::jsonb) from public.workshop_bookings b join public.vehicles v on v.id=b.vehicle_id and v.lifecycle_state='active' and v.deleted_at is null where b.stage_id=v_stage_id and b.vehicle_id=any(v_ids) and b.deleted_at is null and b.status in('queued','planned','started','stoppage','completed') and((b.status in('queued','planned') and b.scheduled_start_at<v_to and b.scheduled_end_at>v_from)or(b.status in('started','stoppage') and b.scheduled_start_at<v_to)or(b.status='completed' and b.actual_end_at>=v_from and b.actual_end_at<v_to))),
  'vehicles',(select coalesce(jsonb_agg(jsonb_build_object('id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,'stock_number',v.stock_number,'toyota_order_number',v.toyota_order_number,'job_card_number',v.job_card_number,'customer_name',v.customer_name,'make',v.make,'model',v.model,'registration',v.registration,'current_location',v.current_location,'pmb_stage',v.pmb_stage,'pmb_bay_stage',v.pmb_bay_stage,'pmb_bay_number',v.pmb_bay_number,'eta_to_kewdale',v.eta_to_kewdale,'active_workshop_booking_id',v.active_workshop_booking_id,'workshop_status',v.workshop_status,'version',v.version,'workshop_estimated_hours_by_stage',jsonb_build_object(v_stage,public.workshop_vehicle_stage_estimated_hours(v.id,v_stage))) order by v.stock_number nulls last,v.id),'[]'::jsonb) from public.vehicles v where v.id=any(v_ids) and v.lifecycle_state='active' and v.deleted_at is null),
  'work_items',(select coalesce(jsonb_agg(jsonb_build_object('vehicle_id',wi.vehicle_id,'work_key',wi.work_key,'required',wi.required,'completed',wi.completed,'completed_at',wi.completed_at) order by wi.vehicle_id,wi.work_key),'[]'::jsonb) from public.vehicle_work_items wi where wi.vehicle_id=any(v_ids) and public.workshop_stage_code_for_work_key(wi.work_key)=v_stage)
 );
end $$;
revoke all on function public.get_station_workshop_snapshot(text,date,date) from public,anon,authenticated;
grant execute on function public.get_station_workshop_snapshot(text,date,date) to authenticated;

do $settings$
declare
  v_before public.workshop_settings%rowtype;
  v_after public.workshop_settings%rowtype;
begin
  select * into v_before from public.workshop_settings
   where key='default_booking_duration_minutes' for update;
  if found and v_before.value=to_jsonb(180) then
    update public.workshop_settings
       set value=to_jsonb(60),updated_at=clock_timestamp()
     where id=v_before.id
     returning * into v_after;
    insert into public.audit_events(action,table_name,row_id,before_data,after_data,metadata)
    values('update','workshop_settings',v_after.id,to_jsonb(v_before),to_jsonb(v_after),
      jsonb_build_object('source','migration_152_operation_estimate_chips','reason','Remove three-hour test default; operation estimates are authoritative'));
  end if;
end;
$settings$;

commit;
