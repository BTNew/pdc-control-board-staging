-- Staging-only viewer read access for authoritative Workshop snapshots.
-- Mutation RPCs remain operator/administrator gated.

begin;

CREATE OR REPLACE FUNCTION public.get_workshop_eligibility_snapshot()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
begin
 perform public.require_pdc_role('viewer');
 return jsonb_build_object('generated_at',now(),
  'semantics',jsonb_build_object(
    'count_label','Outstanding requirements',
    'candidate_authority','required canonical work item with completed=false',
    'legacy_pmb_stage_authority',false),
  'stages',(select coalesce(jsonb_agg(jsonb_build_object('code',s.code,'display_name',s.display_name,
   'work_key',s.work_key,'planner_enabled',s.planner_enabled,'revision',public.workshop_current_station_revision(s.code),
   'aliases',(select coalesce(jsonb_agg(a.alias_value order by a.alias_value),'[]'::jsonb)
    from public.workshop_stage_aliases a where a.stage_code=s.code)) order by s.sort_order),'[]'::jsonb)
   from public.workshop_stages s where s.active and s.planner_enabled),
  'candidates',(select coalesce(jsonb_agg(jsonb_build_object('stage_code',e.stage_code,'work_key',e.work_key,
   'existing_booking',e.existing_booking,'schedule_enabled',e.schedule_enabled,'disabled_reason',e.disabled_reason,
   'vehicle',jsonb_build_object('id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,'stock_number',v.stock_number,
    'toyota_order_number',v.toyota_order_number,'job_card_number',v.job_card_number,'make',v.make,'model',v.model,
    'registration',v.registration,'current_location',v.current_location,'pmb_stage',v.pmb_stage,
    'pmb_bay_stage',v.pmb_bay_stage,'pmb_bay_number',v.pmb_bay_number,'eta_to_kewdale',v.eta_to_kewdale,
    'active_workshop_booking_id',v.active_workshop_booking_id,'workshop_status',v.workshop_status,'version',v.version),
   'work_items',(select coalesce(jsonb_agg(jsonb_build_object('vehicle_id',wi.vehicle_id,'work_key',wi.work_key,
    'required',wi.required,'completed',wi.completed,'completed_at',wi.completed_at)),'[]'::jsonb)
    from public.vehicle_work_items wi where wi.vehicle_id=v.id
     and public.workshop_stage_code_for_work_key(wi.work_key)=e.stage_code))
   order by e.stage_code,v.stock_number,v.id),'[]'::jsonb)
   from public.workshop_stages s cross join lateral public.workshop_station_eligibility(s.code)e
   join public.vehicles v on v.id=e.vehicle_id and v.lifecycle_state='active' and v.deleted_at is null
   where s.code=e.stage_code and s.active and s.planner_enabled));
end $function$;


CREATE OR REPLACE FUNCTION public.get_station_workshop_snapshot(p_stage_code text, p_date_from date, p_date_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare v_stage text; v_stage_id uuid; v_from timestamptz; v_to timestamptz; v_ids uuid[];
begin
 perform public.require_pdc_role('viewer');
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
  'outstanding_candidates',(select coalesce(jsonb_agg(jsonb_build_object('vehicle_id',e.vehicle_id,'existing_booking',e.existing_booking,'schedule_enabled',e.schedule_enabled,'disabled_reason',e.disabled_reason,'requirements',(select coalesce(jsonb_agg(jsonb_build_object('vehicle_id',wi.vehicle_id,'work_key',wi.work_key,'required',wi.required,'completed',wi.completed,'completed_at',wi.completed_at) order by wi.work_key),'[]'::jsonb) from public.vehicle_work_items wi where wi.vehicle_id=e.vehicle_id and wi.required and not wi.completed)) order by e.vehicle_id),'[]'::jsonb) from public.workshop_station_eligibility(v_stage)e),
  'bookings',(select coalesce(jsonb_agg(public.workshop_planner_booking_dto(b.id) order by b.scheduled_start_at,b.id),'[]'::jsonb) from public.workshop_bookings b join public.vehicles v on v.id=b.vehicle_id and v.lifecycle_state='active' and v.deleted_at is null where b.stage_id=v_stage_id and b.vehicle_id=any(v_ids) and b.deleted_at is null and b.status in('queued','planned','started','stoppage','completed') and((b.status in('queued','planned') and b.scheduled_start_at<v_to and b.scheduled_end_at>v_from)or(b.status in('started','stoppage') and b.scheduled_start_at<v_to)or(b.status='completed' and b.actual_end_at>=v_from and b.actual_end_at<v_to))),
  'vehicles',(select coalesce(jsonb_agg(jsonb_build_object('id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,'stock_number',v.stock_number,'toyota_order_number',v.toyota_order_number,'job_card_number',v.job_card_number,'customer_name',v.customer_name,'make',v.make,'model',v.model,'registration',v.registration,'current_location',v.current_location,'pmb_stage',v.pmb_stage,'pmb_bay_stage',v.pmb_bay_stage,'pmb_bay_number',v.pmb_bay_number,'eta_to_kewdale',v.eta_to_kewdale,'active_workshop_booking_id',v.active_workshop_booking_id,'workshop_status',v.workshop_status,'version',v.version) order by v.stock_number nulls last,v.id),'[]'::jsonb) from public.vehicles v where v.id=any(v_ids) and v.lifecycle_state='active' and v.deleted_at is null),
  'work_items',(select coalesce(jsonb_agg(jsonb_build_object('vehicle_id',wi.vehicle_id,'work_key',wi.work_key,'required',wi.required,'completed',wi.completed,'completed_at',wi.completed_at) order by wi.vehicle_id,wi.work_key),'[]'::jsonb) from public.vehicle_work_items wi where wi.vehicle_id=any(v_ids) and public.workshop_stage_code_for_work_key(wi.work_key)=v_stage)
 );
end $function$;

revoke all on function public.get_workshop_eligibility_snapshot() from public, anon;
grant execute on function public.get_workshop_eligibility_snapshot() to authenticated, service_role;
revoke all on function public.get_station_workshop_snapshot(text,date,date) from public, anon;
grant execute on function public.get_station_workshop_snapshot(text,date,date) to authenticated, service_role;

commit;
