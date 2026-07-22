-- Corrective closure for the applied 040 -> 042 all-station release.
-- Additive only: fixes effective scheduling, alias, role and Realtime contracts.

insert into public.workshop_stage_aliases(alias_normalized,alias_value,stage_code)
select v.alias_normalized,v.alias_normalized,v.stage_code from (values
 ('BUS4X4','BUS_4X4'),('4X4BUS','BUS_4X4'),('DEPARTMENT138','BUS_4X4'),('DEPT138','BUS_4X4'),
 ('TINT','TINT'),('TINTING','TINT'),('WINDOWTINT','TINT'),
 ('HOIST','HOIST'),('PITSHOIST','HOIST'),('PITHOIST','HOIST'),('EXPRESSHOIST','HOIST'),
 ('FITTING','FITTING'),('FITMENT','FITTING'),('FITOUT','FITTING'),('EXPRESSFITOUT','FITTING'),
 ('FABRICATION','FABRICATION'),('FAB','FABRICATION'),('FABRICATING','FABRICATION'),
 ('ELECTRICAL','ELECTRICAL'),('ELEC','ELECTRICAL'),('AUTOELECTRICAL','ELECTRICAL'),('AUTOELEC','ELECTRICAL'),
 ('TYRE','TYRE'),('TYRES','TYRE'),('TYREBAY','TYRE'),('TIRE','TYRE'),('TIREBAY','TYRE'),
 ('PITINSPECTION','PIT_INSPECTION'),('PIT','PIT_INSPECTION'),('PITS','PIT_INSPECTION'),('INSPECTION','PIT_INSPECTION'),
 ('SUBLET','SUBLET'),('OUTSOURCE','SUBLET'),('OUTSOURCED','SUBLET'),('EXTERNAL','SUBLET')
) as v(alias_normalized,stage_code)
on conflict(alias_normalized) do update set alias_value=excluded.alias_value,stage_code=excluded.stage_code;

create or replace function public.workshop_require_planner_operator()
returns void language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare v_role text:=coalesce(public.current_pdc_user_role()::text,'');
begin
 if v_role not in ('operator','administrator') then
  raise exception 'Operator or administrator role required' using errcode='42501';
 end if;
end $$;
revoke all on function public.workshop_require_planner_operator() from public,anon,authenticated;

create or replace function public.workshop_require_planner_booking_mutation()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
declare
 v_stage_id uuid;
 v_stage_code text;
 v_planner_enabled boolean;
begin
 if auth.uid() is not null then
  -- Importer-authorized ETA changes invoke the retained vehicle ETA-risk trigger,
  -- which may update only booking ETA-risk metadata as a nested trigger action.
  if tg_op='UPDATE' and pg_trigger_depth()>1
     and (to_jsonb(new)-array['eta_at_booking','eta_risk_status','eta_risk_detected_at','version','updated_by'])
         is not distinct from
         (to_jsonb(old)-array['eta_at_booking','eta_risk_status','eta_risk_detected_at','version','updated_by']) then
   return new;
  end if;
  perform public.workshop_require_planner_operator();
 end if;

 v_stage_id:=case when tg_op='DELETE' then old.stage_id else new.stage_id end;
 select s.code,coalesce(s.planner_enabled,false) into v_stage_code,v_planner_enabled
 from public.workshop_stages s where s.id=v_stage_id;
 if coalesce(v_planner_enabled,false)=false then
  -- Historical Sublet completion is retained, but no disabled planner booking
  -- may be created, started, stopped, resumed, reassigned, returned, restored,
  -- moved, resized or deleted through either current or legacy RPCs.
  if tg_op='UPDATE' and new.status='completed' and old.status is distinct from 'completed'
     and (to_jsonb(new)-array['status','actual_start_at','actual_end_at','actual_duration_minutes','stoppage_started_at','stoppage_accumulated_minutes','updated_by','updated_at','version'])
         is not distinct from
         (to_jsonb(old)-array['status','actual_start_at','actual_end_at','actual_duration_minutes','stoppage_started_at','stoppage_accumulated_minutes','updated_by','updated_at','version']) then
   return new;
  end if;
  raise exception 'planner_disabled stage=%',coalesce(v_stage_code,'unknown') using errcode='22023';
 end if;
 if tg_op='DELETE' then return old; end if;
 return new;
end $$;
revoke all on function public.workshop_require_planner_booking_mutation() from public,anon,authenticated;
drop trigger if exists workshop_bookings_require_planner_operator on public.workshop_bookings;
create trigger workshop_bookings_require_planner_operator before insert or update or delete on public.workshop_bookings
for each row execute function public.workshop_require_planner_booking_mutation();

-- The browser uses the audited high-level action layer. Remove obsolete direct
-- low-level mutation entry points while retaining historical completion.
revoke execute on function public.workshop_create_booking(uuid,text,integer,timestamptz,integer,uuid,jsonb) from authenticated;
revoke execute on function public.workshop_move_booking(uuid,integer,text,integer,timestamptz,integer,jsonb) from authenticated;
revoke execute on function public.workshop_resize_booking(uuid,integer,integer,jsonb) from authenticated;
revoke execute on function public.workshop_reassign_booking(uuid,integer,uuid,jsonb) from authenticated;
revoke execute on function public.workshop_start_booking(uuid,integer,timestamptz,jsonb) from authenticated;
revoke execute on function public.workshop_record_stoppage(uuid,integer,text,jsonb) from authenticated;
revoke execute on function public.workshop_resume_booking(uuid,integer,jsonb) from authenticated;
revoke execute on function public.workshop_return_booking_to_queue(uuid,integer,text,jsonb) from authenticated;
revoke execute on function public.workshop_delete_booking(uuid,integer,text,jsonb) from authenticated;
revoke execute on function public.workshop_restore_booking(uuid,integer,jsonb) from authenticated;

create or replace function public.workshop_enforce_vehicle_eta()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,extensions as $$
declare v_vehicle public.vehicles%rowtype; v_location text;
begin
 select * into v_vehicle from public.vehicles where id=new.vehicle_id;
 v_location:=upper(btrim(coalesce(v_vehicle.current_location,'')));
 if v_location='IT' then
  if v_vehicle.eta_to_kewdale is null then raise exception 'missing_or_invalid_eta' using errcode='23514'; end if;
  if (new.scheduled_start_at at time zone 'Australia/Perth')::date<v_vehicle.eta_to_kewdale then
   raise exception 'booking_before_eta earliest_permitted_date=%',v_vehicle.eta_to_kewdale using errcode='23514';
  end if;
  new.eta_at_booking:=v_vehicle.eta_to_kewdale;
  new.eta_risk_status:='none'; new.eta_risk_detected_at:=null;
 else
  new.eta_at_booking:=null; new.eta_risk_status:='none'; new.eta_risk_detected_at:=null;
 end if;
 return new;
end $$;
revoke all on function public.workshop_enforce_vehicle_eta() from public,anon,authenticated;

drop trigger if exists workshop_bookings_enforce_vehicle_eta on public.workshop_bookings;
create trigger workshop_bookings_enforce_vehicle_eta before insert or update of scheduled_start_at,vehicle_id
on public.workshop_bookings for each row execute function public.workshop_enforce_vehicle_eta();

create or replace function public.schedule_vehicle_work(
 p_vehicle_id uuid,p_vehicle_expected_version integer,p_stage_code text,p_bay_number integer,
 p_scheduled_start_at timestamptz,p_duration_minutes integer default 180,p_technician_id uuid default null,
 p_override_reason text default null,p_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions as $$
declare
 v_vehicle public.vehicles%rowtype; v_stage public.workshop_stages%rowtype; v_booking jsonb;
 v_override_id uuid; v_before_vehicle jsonb; v_after_vehicle jsonb; v_revision bigint; v_stage_code text;
begin
 perform public.workshop_require_planner_operator();
 perform public.workshop_require_version(p_vehicle_expected_version);
 select * into v_vehicle from public.vehicles where id=p_vehicle_id for update;
 if not found then raise exception 'Vehicle not found' using errcode='P0002'; end if;
 if v_vehicle.version<>p_vehicle_expected_version then return jsonb_build_object('ok',false,'error','vehicle_version_conflict'); end if;
 v_stage_code:=public.workshop_canonical_stage_code(p_stage_code);
 select * into v_stage from public.workshop_stages where code=v_stage_code and active=true and planner_enabled=true;
 if not found then raise exception 'Workshop stage % is not planner-enabled',p_stage_code using errcode='22023'; end if;
 if v_stage.is_physical and not public.workshop_parts_ready(p_vehicle_id) then
  if p_override_reason is null or btrim(p_override_reason)='' then return jsonb_build_object('ok',false,'error','parts_incomplete'); end if;
  perform public.require_pdc_role('administrator');
 end if;
 v_before_vehicle:=to_jsonb(v_vehicle);
 v_booking:=public.workshop_create_booking(p_vehicle_id,v_stage.code,p_bay_number,p_scheduled_start_at,p_duration_minutes,p_technician_id,p_metadata);
 if not (v_booking->>'ok')::boolean then return v_booking; end if;
 update public.vehicles set
  active_workshop_booking_id=(v_booking->'booking'->>'booking_id')::uuid,
  workshop_status='scheduled',workshop_status_updated_at=now(),workshop_status_updated_by=auth.uid(),
  version=version+1,updated_by=auth.uid()
 where id=p_vehicle_id returning to_jsonb(vehicles.*) into v_after_vehicle;
 if p_override_reason is not null and btrim(p_override_reason)<>'' then
  insert into public.workshop_parts_overrides(vehicle_id,booking_id,work_key,intended_stage_id,reason,previous_state,resulting_state,approved_by,approved_by_email)
  values(p_vehicle_id,(v_booking->'booking'->>'booking_id')::uuid,'PARTS',v_stage.id,btrim(p_override_reason),v_before_vehicle,v_after_vehicle,auth.uid(),public.current_actor_email())
  returning id into v_override_id;
 end if;
 perform public.audit_pdc_event('update','vehicles',p_vehicle_id,p_vehicle_id,v_before_vehicle,v_after_vehicle,
  jsonb_build_object('action','schedule_vehicle_work','override_id',v_override_id,'planning_location',v_vehicle.current_location,'eta_at_booking',v_vehicle.eta_to_kewdale));
 v_revision:=public.workshop_bump_revision();
 return jsonb_build_object('ok',true,'booking',v_booking->'booking','vehicle',v_after_vehicle,'override_id',v_override_id,'revision',v_revision);
end $$;
revoke all on function public.schedule_vehicle_work(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb) from public,anon;
grant execute on function public.schedule_vehicle_work(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb) to authenticated;

-- A booking move is scheduling metadata only. The retained migration-010
-- wrapper wrote the destination into vehicles.pmb_stage, which incorrectly
-- promoted a planner move into workflow-stage authority.
create or replace function public.move_workshop_booking(
 p_booking_id uuid,p_expected_version integer,p_stage_code text,p_bay_number integer,
 p_scheduled_start_at timestamptz,p_duration_minutes integer default null,
 p_override_reason text default null,p_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions as $$
declare
 v_booking_before public.workshop_bookings%rowtype; v_stage public.workshop_stages%rowtype;
 v_result jsonb; v_override_id uuid; v_revision bigint; v_stage_code text;
begin
 perform public.workshop_require_planner_operator();
 perform public.workshop_require_version(p_expected_version);
 select * into v_booking_before from public.workshop_bookings where id=p_booking_id for update;
 if not found then raise exception 'Workshop booking not found' using errcode='P0002'; end if;
 v_stage_code:=public.workshop_canonical_stage_code(p_stage_code);
 select * into v_stage from public.workshop_stages where code=v_stage_code and active=true and planner_enabled=true;
 if not found then raise exception 'Workshop stage % is not planner-enabled',p_stage_code using errcode='22023'; end if;
 if v_stage.is_physical and not public.workshop_parts_ready(v_booking_before.vehicle_id) then
  if p_override_reason is null or btrim(p_override_reason)='' then return jsonb_build_object('ok',false,'error','parts_incomplete'); end if;
  perform public.require_pdc_role('administrator');
 end if;
 v_result:=public.workshop_move_booking(p_booking_id,p_expected_version,v_stage.code,p_bay_number,
  p_scheduled_start_at,p_duration_minutes,p_metadata);
 if not (v_result->>'ok')::boolean then return v_result; end if;
 if p_override_reason is not null and btrim(p_override_reason)<>'' then
  insert into public.workshop_parts_overrides(
   vehicle_id,booking_id,work_key,intended_stage_id,reason,previous_state,resulting_state,approved_by,approved_by_email)
  values(v_booking_before.vehicle_id,p_booking_id,'PARTS',v_stage.id,btrim(p_override_reason),
   to_jsonb(v_booking_before),v_result->'booking',auth.uid(),public.current_actor_email()) returning id into v_override_id;
 end if;
 v_revision:=public.workshop_bump_revision();
 return v_result||jsonb_build_object('override_id',v_override_id,'revision',v_revision);
end $$;
revoke all on function public.move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb) from public,anon;
grant execute on function public.move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb) to authenticated;

create or replace function public.get_workshop_eligibility_snapshot()
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
 perform public.workshop_require_planner_operator();
 return jsonb_build_object('generated_at',now(),
  'stages',(select coalesce(jsonb_agg(jsonb_build_object('code',s.code,'display_name',s.display_name,
   'work_key',s.work_key,'planner_enabled',s.planner_enabled,'revision',public.workshop_current_station_revision(s.code),
   'aliases',(select coalesce(jsonb_agg(a.alias_value order by a.alias_value),'[]'::jsonb) from public.workshop_stage_aliases a where a.stage_code=s.code)) order by s.sort_order),'[]'::jsonb)
   from public.workshop_stages s where s.active and s.planner_enabled),
  'candidates',(select coalesce(jsonb_agg(jsonb_build_object('stage_code',e.stage_code,'work_key',e.work_key,
   'existing_booking',e.existing_booking,'schedule_enabled',e.schedule_enabled,'disabled_reason',e.disabled_reason,
   'vehicle',jsonb_build_object('id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,'stock_number',v.stock_number,
    'vin',v.vin,'toyota_order_number',v.toyota_order_number,'job_card_number',v.job_card_number,
    'customer_name',v.customer_name,'make',v.make,'model',v.model,'registration',v.registration,
    'current_location',v.current_location,'pmb_stage',v.pmb_stage,'pmb_bay_stage',v.pmb_bay_stage,
    'pmb_bay_number',v.pmb_bay_number,'eta_to_kewdale',v.eta_to_kewdale,
    'active_workshop_booking_id',v.active_workshop_booking_id,'workshop_status',v.workshop_status,'version',v.version),
   'work_items',(select coalesce(jsonb_agg(jsonb_build_object('vehicle_id',wi.vehicle_id,'work_key',wi.work_key,
    'required',wi.required,'completed',wi.completed,'completed_at',wi.completed_at)),'[]'::jsonb)
    from public.vehicle_work_items wi where wi.vehicle_id=v.id and public.workshop_stage_code_for_work_key(wi.work_key)=e.stage_code)
  ) order by e.stage_code,v.stock_number,v.id),'[]'::jsonb)
  from public.workshop_stages s cross join lateral public.workshop_station_eligibility(s.code)e
  join public.vehicles v on v.id=e.vehicle_id where s.code=e.stage_code and s.active and s.planner_enabled));
end $$;

create or replace function public.get_station_workshop_snapshot(p_stage_code text,p_date_from date,p_date_to date)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_stage text; v_stage_id uuid; v_from timestamptz; v_to timestamptz; v_base jsonb; v_ids uuid[];
begin
 perform public.workshop_require_planner_operator();
 v_stage:=public.workshop_canonical_stage_code(p_stage_code);
 select id into v_stage_id from public.workshop_stages where code=v_stage and active and planner_enabled;
 if v_stage_id is null then raise exception 'Unknown, inactive or planner-disabled workshop station' using errcode='22023'; end if;
 if p_date_from is null or p_date_to is null or p_date_to<p_date_from or p_date_to>p_date_from+31 then
  raise exception 'Invalid station planner date range' using errcode='22023'; end if;
 v_from:=p_date_from::timestamp at time zone 'Australia/Perth';
 v_to:=(p_date_to+1)::timestamp at time zone 'Australia/Perth';
 v_base:=public.get_station_workshop_snapshot_legacy(v_stage,p_date_from,p_date_to);
 select coalesce(array_agg(distinct x.vehicle_id),'{}'::uuid[]) into v_ids from(
  select e.vehicle_id from public.workshop_station_eligibility(v_stage)e
  union select b.vehicle_id from public.workshop_bookings b where b.stage_id=v_stage_id and b.status='completed'
   and b.actual_end_at>=v_from and b.actual_end_at<v_to) x;
 return v_base||jsonb_build_object(
  'stage',v_stage,'revision',public.workshop_current_station_revision(v_stage),
  'scope',jsonb_build_object('stage_code',v_stage,'date_from',p_date_from,'date_to',p_date_to),
  'stages',(select jsonb_agg(jsonb_build_object('id',s.id,'code',s.code,'display_name',s.display_name,
   'sort_order',s.sort_order,'is_physical',s.is_physical,'is_sublet',s.is_sublet,'active',s.active,
   'work_key',s.work_key,'planner_enabled',s.planner_enabled,
   'aliases',(select coalesce(jsonb_agg(a.alias_value order by a.alias_value),'[]'::jsonb) from public.workshop_stage_aliases a where a.stage_code=s.code)))
   from public.workshop_stages s where s.id=v_stage_id),
  'bookings',(select coalesce(jsonb_agg(public.workshop_booking_snapshot(b.id) order by b.scheduled_start_at,b.id),'[]'::jsonb)
   from public.workshop_bookings b where b.stage_id=v_stage_id and b.status<>'deleted' and(
    b.status in('queued','planned','started','stoppage') or(b.status='completed' and b.actual_end_at>=v_from and b.actual_end_at<v_to))),
  'vehicles',(select coalesce(jsonb_agg(jsonb_build_object(
   'id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,'stock_number',v.stock_number,'vin',v.vin,
   'toyota_order_number',v.toyota_order_number,'job_card_number',v.job_card_number,'customer_name',v.customer_name,
   'make',v.make,'model',v.model,'registration',v.registration,'current_location',v.current_location,
   'pmb_stage',v.pmb_stage,'pmb_bay_stage',v.pmb_bay_stage,'pmb_bay_number',v.pmb_bay_number,
   'eta_to_kewdale',v.eta_to_kewdale,'active_workshop_booking_id',v.active_workshop_booking_id,
   'workshop_status',v.workshop_status,'version',v.version) order by v.stock_number nulls last,v.id),'[]'::jsonb)
   from public.vehicles v where v.id=any(v_ids)),
  'work_items',(select coalesce(jsonb_agg(jsonb_build_object('vehicle_id',wi.vehicle_id,'work_key',wi.work_key,
   'required',wi.required,'completed',wi.completed,'completed_at',wi.completed_at) order by wi.vehicle_id,wi.work_key),'[]'::jsonb)
   from public.vehicle_work_items wi where wi.vehicle_id=any(v_ids) and public.workshop_stage_code_for_work_key(wi.work_key)=v_stage)
 );
end $$;
revoke all on function public.get_workshop_eligibility_snapshot() from public,anon,authenticated;
revoke all on function public.get_station_workshop_snapshot(text,date,date) from public,anon,authenticated;
grant execute on function public.get_workshop_eligibility_snapshot() to authenticated;
grant execute on function public.get_station_workshop_snapshot(text,date,date) to authenticated;

create or replace function public.workshop_bump_all_station_revisions()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 -- Existing revision rows include stations that have just been disabled or deleted;
 -- bump them first so their scoped subscribers refetch and observe rejection.
 update public.workshop_station_revision
 set revision=revision+1,updated_at=now();
 -- Then add revision authority for newly inserted stages.
 insert into public.workshop_station_revision(stage_code,revision,updated_at)
 select code,1,now() from public.workshop_stages
 on conflict(stage_code) do nothing;
 return null;
end $$;
revoke all on function public.workshop_bump_all_station_revisions() from public,anon,authenticated;

do $$ declare v_table text; begin
 foreach v_table in array array['workshop_stages','workshop_stage_aliases','workshop_bays','workshop_technicians','workshop_settings'] loop
  execute format('drop trigger if exists %I on public.%I','workshop_all_station_revision_config',v_table);
  execute format('create trigger %I after insert or update or delete on public.%I for each statement execute function public.workshop_bump_all_station_revisions()','workshop_all_station_revision_config',v_table);
 end loop;
end $$;

select public.workshop_bump_revision();
insert into public.workshop_station_revision(stage_code,revision,updated_at)
select code,1,now() from public.workshop_stages where active and planner_enabled
on conflict(stage_code) do update set revision=public.workshop_station_revision.revision+1,updated_at=now();
