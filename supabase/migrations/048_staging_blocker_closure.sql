-- 048: staging blocker closure -- optimize Navision identity matching and carry unfinished live Workshop work forward.
-- Depends on 045 and is intentionally limited to shared staging paths.

begin;
set local lock_timeout = '3s';

create index if not exists vehicles_toyota_order_normalized_idx
on public.vehicles ((public.normalize_vehicle_source_identifier(toyota_order_number)))
where toyota_order_number is not null;

create or replace function public.navision_backend_candidate_vehicle_ids(p_row jsonb)
returns uuid[] language sql stable security definer set search_path=pg_catalog,public,extensions as $$
 with input as (
  select public.normalize_vehicle_vin(p_row->>'vin') vin,
         public.is_valid_vehicle_vin(p_row->>'vin') vin_valid,
         public.normalize_vehicle_stock_number(coalesce(p_row->>'stock',p_row->>'stock_number')) stock_number,
         public.is_real_vehicle_stock_number(coalesce(p_row->>'stock',p_row->>'stock_number')) stock_valid,
         public.normalize_vehicle_source_identifier(coalesce(p_row->>'order',p_row->>'toyota_order_number')) toyota_order_number
 ), candidates as (
  select v.id from input i join public.vehicles v on i.vin_valid and i.vin is not null and v.vin_normalized=i.vin
  union select v.id from input i join public.vehicles v on i.stock_valid and i.stock_number is not null and v.stock_number_normalized=i.stock_number
  union select v.id from input i join public.vehicles v on i.toyota_order_number is not null and public.normalize_vehicle_source_identifier(v.toyota_order_number)=i.toyota_order_number
  union select a.vehicle_id from input i join public.vehicle_aliases a on i.vin_valid and i.vin is not null and a.active and a.alias_type_normalized='vin' and a.normalized_alias_value=i.vin
  union select a.vehicle_id from input i join public.vehicle_aliases a on i.stock_valid and i.stock_number is not null and a.active and a.alias_type_normalized='stock_number' and a.normalized_alias_value=i.stock_number
  union select a.vehicle_id from input i join public.vehicle_aliases a on i.toyota_order_number is not null and a.active and a.alias_type_normalized='toyota_order_number' and a.normalized_alias_value=i.toyota_order_number and a.source_system_normalized in('navision','microsoft-navision')
 )
 select coalesce(array_agg(distinct id order by id),'{}'::uuid[]) from candidates
$$;
revoke all on function public.navision_backend_candidate_vehicle_ids(jsonb) from public,anon,authenticated;

create or replace function public.workshop_block_legacy_ambiguous_booking_mutation()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
begin
  if old.deleted_at is null and old.status in ('queued','planned','started','stoppage')
     and exists(select 1 from public.workshop_stages stage where stage.id=old.stage_id and stage.code='HOIST')
     and (
       old.actual_end_at is not null
       or exists (
         select 1 from public.workshop_bookings other
         where other.id<>old.id
           and other.vehicle_id=old.vehicle_id
           and other.stage_id=old.stage_id
           and other.deleted_at is null
           and other.status in ('queued','planned','started','stoppage')
       )
     ) then
    raise exception 'legacy_ambiguity_blocked' using errcode='23514';
  end if;
  return new;
end $$;
revoke all on function public.workshop_block_legacy_ambiguous_booking_mutation() from public,anon,authenticated;

drop trigger if exists workshop_booking_048_legacy_ambiguity_guard on public.workshop_bookings;
create trigger workshop_booking_048_legacy_ambiguity_guard
before update of vehicle_id,stage_id,bay_id,status,scheduled_start_at,scheduled_end_at,default_duration_minutes,deleted_at
on public.workshop_bookings
for each row execute function public.workshop_block_legacy_ambiguous_booking_mutation();

create or replace function public.get_station_workshop_snapshot(p_stage_code text,p_date_from date,p_date_to date)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare v_stage text; v_stage_id uuid; v_from timestamptz; v_to timestamptz; v_ids uuid[];
begin
 perform public.workshop_require_planner_operator();
 v_stage:=public.workshop_canonical_stage_code(p_stage_code);
 select id into v_stage_id from public.workshop_stages where code=v_stage and active and planner_enabled;
 if v_stage_id is null then raise exception 'Unknown, inactive or planner-disabled workshop station' using errcode='22023'; end if;
 if p_date_from is null or p_date_to is null or p_date_to<p_date_from or p_date_to>p_date_from+31 then
  raise exception 'Invalid station planner date range' using errcode='22023'; end if;
 v_from:=p_date_from::timestamp at time zone 'Australia/Perth';
 v_to:=(p_date_to+1)::timestamp at time zone 'Australia/Perth';
 select coalesce(array_agg(distinct q.vehicle_id),'{}'::uuid[]) into v_ids from(
  select e.vehicle_id from public.workshop_station_eligibility(v_stage)e
  union
  select b.vehicle_id from public.workshop_bookings b
   join public.vehicles v on v.id=b.vehicle_id and v.lifecycle_state='active' and v.deleted_at is null
   where b.stage_id=v_stage_id and b.deleted_at is null and b.status in('queued','planned','started','stoppage','completed')
   and ((b.status in('queued','planned') and b.scheduled_start_at<v_to and b.scheduled_end_at>v_from)
        or (b.status in('started','stoppage') and b.scheduled_start_at<v_to)
        or (b.status='completed' and b.actual_end_at>=v_from and b.actual_end_at<v_to))
 )q;
 return jsonb_build_object(
  'revision',public.workshop_current_station_revision(v_stage),'generated_at',now(),
  'semantics',jsonb_build_object(
    'outstanding_candidates','required canonical work items not completed and location-visible',
    'unscheduled_candidates','outstanding candidates without any active booking',
    'selected_date_bookings','scheduled rows intersecting the date plus started or stopped work carried forward until resolved'),
  'scope',jsonb_build_object('stage_code',v_stage,'date_from',p_date_from,'date_to',p_date_to),
  'counts',jsonb_build_object(
    'outstanding_candidates',(select count(*) from public.workshop_station_eligibility(v_stage)),
    'unscheduled_candidates',(select count(*) from public.workshop_station_eligibility(v_stage)e where not e.existing_booking),
    'selected_date_bookings',(select count(*) from public.workshop_bookings b
      join public.vehicles v on v.id=b.vehicle_id and v.lifecycle_state='active' and v.deleted_at is null
      where b.stage_id=v_stage_id and b.deleted_at is null and b.status in('queued','planned','started','stoppage','completed')
      and ((b.status in('queued','planned') and b.scheduled_start_at<v_to and b.scheduled_end_at>v_from)
        or (b.status in('started','stoppage') and b.scheduled_start_at<v_to)
        or (b.status='completed' and b.actual_end_at>=v_from and b.actual_end_at<v_to)))),
  'stages',(select jsonb_agg(jsonb_build_object('id',s.id,'code',s.code,'display_name',s.display_name,
   'is_physical',s.is_physical,'work_key',s.work_key)) from public.workshop_stages s where s.id=v_stage_id),
  'bays',(select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'bay_number',b.bay_number,
   'code',b.code,'display_name',b.display_name) order by b.bay_number),'[]'::jsonb)
   from public.workshop_bays b where b.stage_id=v_stage_id and b.is_active),
  'outstanding_candidates',(select coalesce(jsonb_agg(jsonb_build_object(
    'vehicle_id',e.vehicle_id,'existing_booking',e.existing_booking,'schedule_enabled',e.schedule_enabled,
    'disabled_reason',e.disabled_reason,
    'requirements',(select coalesce(jsonb_agg(jsonb_build_object(
      'vehicle_id',wi.vehicle_id,'work_key',wi.work_key,'required',wi.required,
      'completed',wi.completed,'completed_at',wi.completed_at) order by wi.work_key),'[]'::jsonb)
      from public.vehicle_work_items wi
      where wi.vehicle_id=e.vehicle_id and wi.required and not wi.completed)
    ) order by e.vehicle_id),'[]'::jsonb)
    from public.workshop_station_eligibility(v_stage)e),
  'bookings',(select coalesce(jsonb_agg(public.workshop_planner_booking_dto(b.id) order by b.scheduled_start_at,b.id),'[]'::jsonb)
   from public.workshop_bookings b join public.vehicles v on v.id=b.vehicle_id and v.lifecycle_state='active' and v.deleted_at is null
   where b.stage_id=v_stage_id and b.vehicle_id=any(v_ids) and b.deleted_at is null and b.status in('queued','planned','started','stoppage','completed')
   and ((b.status in('queued','planned') and b.scheduled_start_at<v_to and b.scheduled_end_at>v_from)
        or (b.status in('started','stoppage') and b.scheduled_start_at<v_to)
        or (b.status='completed' and b.actual_end_at>=v_from and b.actual_end_at<v_to))),
  'vehicles',(select coalesce(jsonb_agg(jsonb_build_object(
   'id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,'stock_number',v.stock_number,
   'toyota_order_number',v.toyota_order_number,'job_card_number',v.job_card_number,
   'make',v.make,'model',v.model,'registration',v.registration,'current_location',v.current_location,
   'pmb_stage',v.pmb_stage,'pmb_bay_stage',v.pmb_bay_stage,'pmb_bay_number',v.pmb_bay_number,
   'eta_to_kewdale',v.eta_to_kewdale,'active_workshop_booking_id',v.active_workshop_booking_id,
   'workshop_status',v.workshop_status,'version',v.version) order by v.stock_number nulls last,v.id),'[]'::jsonb)
   from public.vehicles v where v.id=any(v_ids) and v.lifecycle_state='active' and v.deleted_at is null),
  'work_items',(select coalesce(jsonb_agg(jsonb_build_object('vehicle_id',wi.vehicle_id,'work_key',wi.work_key,
   'required',wi.required,'completed',wi.completed,'completed_at',wi.completed_at) order by wi.vehicle_id,wi.work_key),'[]'::jsonb)
   from public.vehicle_work_items wi where wi.vehicle_id=any(v_ids)
    and public.workshop_stage_code_for_work_key(wi.work_key)=v_stage
  )
 );
end $$;
revoke all on function public.get_station_workshop_snapshot(text,date,date) from public,anon,authenticated;
grant execute on function public.get_station_workshop_snapshot(text,date,date) to authenticated;
comment on function public.get_station_workshop_snapshot(text,date,date) is
 'Operator/admin-only station DTO. Outstanding candidates remain date-independent; started/stopped work carries forward readably without duplicating bookings.';

commit;
