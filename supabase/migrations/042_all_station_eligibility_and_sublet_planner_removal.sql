-- Canonical all-station eligibility and Sublet planner removal.
-- Staging rollout only. Never changes current_location, pmb_stage or visible_on_board.

alter table public.workshop_stages add column if not exists work_key text;
alter table public.workshop_stages add column if not exists planner_enabled boolean not null default true;
update public.workshop_stages set work_key=case code
 when 'BUS_4X4' then 'bus4x4' when 'TINT' then 'tint' when 'HOIST' then 'hoist'
 when 'FITTING' then 'fitting' when 'FABRICATION' then 'fabrication'
 when 'ELECTRICAL' then 'electrical' when 'TYRE' then 'tyre'
 when 'PIT_INSPECTION' then 'pitInspection' when 'SUBLET' then 'sublet'
 else lower(replace(code,'_','')) end where work_key is null;
update public.workshop_stages set planner_enabled=(code<>'SUBLET');
alter table public.workshop_stages alter column work_key set not null;
create unique index if not exists workshop_stages_work_key_unique on public.workshop_stages(lower(work_key));

create table if not exists public.workshop_stage_aliases(
 alias_normalized text primary key, alias_value text not null,
 stage_code text not null references public.workshop_stages(code) on update cascade on delete restrict,
 created_at timestamptz not null default now()
);
alter table public.workshop_stage_aliases enable row level security;
drop policy if exists workshop_stage_aliases_read on public.workshop_stage_aliases;
create policy workshop_stage_aliases_read on public.workshop_stage_aliases for select to authenticated
using(public.current_pdc_user_role() is not null);

create or replace function public.workshop_normalize_identifier(p_value text)
returns text language sql immutable parallel safe as $$
 select upper(regexp_replace(coalesce(p_value,''),'[^A-Za-z0-9]+','','g'))
$$;

insert into public.workshop_stage_aliases(alias_normalized,alias_value,stage_code) values
 ('BUS4X4','Bus 4x4','BUS_4X4'),('BUSFOURBYFOUR','Bus Four By Four','BUS_4X4'),
 ('TINT','Tint','TINT'),('WINDOWTINT','Window Tint','TINT'),
 ('HOIST','Hoist','HOIST'),('LIFTS','Lifts','HOIST'),
 ('FITTING','Fitting','FITTING'),('FITOUT','Fit Out','FITTING'),
 ('FAB','Fab','FABRICATION'),('FABRICATION','Fabrication','FABRICATION'),
 ('ELEC','Elec','ELECTRICAL'),('ELECTRICAL','Electrical','ELECTRICAL'),
 ('TYRE','Tyre','TYRE'),('TYRES','Tyres','TYRE'),('TYREBAY','Tyre Bay','TYRE'),
 ('PIT','Pit','PIT_INSPECTION'),('PITS','Pits','PIT_INSPECTION'),
 ('PITINSPECTION','Pit Inspection','PIT_INSPECTION'),('PITSHOIST','Pits Hoist','PIT_INSPECTION'),
 ('SUBLET','Sublet','SUBLET'),('OUTSOURCE','Outsource','SUBLET'),('OUTSOURCED','Outsourced','SUBLET')
on conflict(alias_normalized) do update set alias_value=excluded.alias_value,stage_code=excluded.stage_code;

create or replace function public.workshop_canonical_stage_code(p_value text)
returns text language sql stable security definer set search_path=public as $$
 select a.stage_code from public.workshop_stage_aliases a
 where a.alias_normalized=public.workshop_normalize_identifier(p_value) limit 1
$$;
create or replace function public.workshop_stage_code_for_work_key(p_work_key text)
returns text language sql stable security definer set search_path=public as $$
 select public.workshop_canonical_stage_code(p_work_key)
$$;

-- Canonicalise future requirement writes. Existing aliases remain query-compatible;
-- a later controlled data-cleanup may merge legacy duplicate IDs without losing history.
create or replace function public.workshop_canonicalize_work_item_key()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_stage text; v_key text;
begin
 v_stage:=public.workshop_canonical_stage_code(new.work_key);
 if v_stage is not null then
  select work_key into v_key from public.workshop_stages where code=v_stage;
  new.work_key:=v_key;
 end if;
 return new;
end; $$;
drop trigger if exists vehicle_work_items_canonical_key on public.vehicle_work_items;
create trigger vehicle_work_items_canonical_key before insert or update of work_key on public.vehicle_work_items
for each row execute function public.workshop_canonicalize_work_item_key();

create or replace function public.workshop_station_eligibility(p_stage_code text)
returns table(vehicle_id uuid,stage_code text,work_key text,current_location text,
 eta_to_kewdale date,existing_booking boolean,schedule_enabled boolean,disabled_reason text)
language sql stable security definer set search_path=public as $$
 with station as(
  select s.code,s.work_key from public.workshop_stages s
  where s.code=public.workshop_canonical_stage_code(p_stage_code) and s.active and s.planner_enabled
 ), outstanding as(
  select wi.vehicle_id,st.code,st.work_key from public.vehicle_work_items wi cross join station st
  where public.workshop_stage_code_for_work_key(wi.work_key)=st.code and wi.required and not wi.completed
  group by wi.vehicle_id,st.code,st.work_key
 ), active_booking as(
  select distinct b.vehicle_id,st.code,st.work_key from public.workshop_bookings b
  join public.workshop_stages s on s.id=b.stage_id join station st on st.code=s.code
  where b.status in('queued','planned','started','stoppage')
 ), scoped as(select * from outstanding union select * from active_booking)
 select v.id,sc.code,sc.work_key,upper(btrim(coalesce(v.current_location,''))),v.eta_to_kewdale,
  (ab.vehicle_id is not null),
  case when upper(btrim(coalesce(v.current_location,''))) in('PMB','YH') then true
       when upper(btrim(coalesce(v.current_location,'')))='IT' and v.eta_to_kewdale is not null then true else false end,
  case when upper(btrim(coalesce(v.current_location,'')))='IT' and v.eta_to_kewdale is null then 'missing_eta'
       when upper(btrim(coalesce(v.current_location,''))) not in('PMB','YH','IT') and ab.vehicle_id is not null then 'existing_booking_location_review'
       when upper(btrim(coalesce(v.current_location,''))) not in('PMB','YH','IT') then 'location_ineligible' else null end
 from scoped sc join public.vehicles v on v.id=sc.vehicle_id
 left join active_booking ab on ab.vehicle_id=v.id and ab.code=sc.code
 where v.lifecycle_state='active' and v.deleted_at is null
  and(upper(btrim(coalesce(v.current_location,''))) in('PMB','YH','IT') or ab.vehicle_id is not null)
$$;

-- Preserve the reviewed 039 shell, then replace its candidate arrays with the canonical relation.
do $$ begin
 if to_regprocedure('public.get_station_workshop_snapshot_legacy(text,date,date)') is null then
  alter function public.get_station_workshop_snapshot(text,date,date) rename to get_station_workshop_snapshot_legacy;
 end if;
end $$;

create or replace function public.get_station_workshop_snapshot(p_stage_code text,p_date_from date,p_date_to date)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_stage text; v_stage_id uuid; v_from timestamptz; v_to timestamptz; v_base jsonb; v_ids uuid[];
begin
 perform public.require_pdc_role('operator');
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
  'revision',public.workshop_current_station_revision(v_stage),
  'scope',jsonb_build_object('stage_code',v_stage,'date_from',p_date_from,'date_to',p_date_to),
  'stages',(select jsonb_agg(jsonb_build_object('id',s.id,'code',s.code,'display_name',s.display_name,
   'sort_order',s.sort_order,'is_physical',s.is_physical,'is_sublet',s.is_sublet,'active',s.active,
   'work_key',s.work_key,'planner_enabled',s.planner_enabled,
   'aliases',(select coalesce(jsonb_agg(a.alias_value order by a.alias_value),'[]'::jsonb) from public.workshop_stage_aliases a where a.stage_code=s.code)))
   from public.workshop_stages s where s.id=v_stage_id),
  'bookings',(select coalesce(jsonb_agg(public.workshop_booking_snapshot(b.id)),'[]'::jsonb)
   from public.workshop_bookings b where b.stage_id=v_stage_id and b.status<>'deleted' and(
    b.status in('queued','planned','started','stoppage') or(b.status='completed' and b.actual_end_at>=v_from and b.actual_end_at<v_to))),
  'vehicles',(select coalesce(jsonb_agg(jsonb_build_object(
   'id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,'stock_number',v.stock_number,'vin',v.vin,
   'toyota_order_number',v.toyota_order_number,'job_card_number',v.job_card_number,'customer_name',v.customer_name,
   'make',v.make,'model',v.model,'registration',v.registration,'current_location',v.current_location,
   'pmb_stage',v.pmb_stage,'pmb_bay_stage',v.pmb_bay_stage,'pmb_bay_number',v.pmb_bay_number,
   'eta_to_kewdale',v.eta_to_kewdale,'active_workshop_booking_id',v.active_workshop_booking_id,
   'workshop_status',v.workshop_status,'version',v.version)),'[]'::jsonb) from public.vehicles v where v.id=any(v_ids)),
  'work_items',(select coalesce(jsonb_agg(jsonb_build_object('vehicle_id',wi.vehicle_id,'work_key',wi.work_key,
   'required',wi.required,'completed',wi.completed,'completed_at',wi.completed_at)),'[]'::jsonb)
   from public.vehicle_work_items wi where wi.vehicle_id=any(v_ids) and public.workshop_stage_code_for_work_key(wi.work_key)=v_stage)
 );
end; $$;

create or replace function public.get_workshop_eligibility_snapshot()
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
 perform public.require_pdc_role('operator');
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
end; $$;

-- A location change must invalidate every outstanding-requirement station, not just pmb_stage.
create or replace function public.workshop_station_revision_from_vehicle()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_vehicle_id uuid; v_code text;
begin
 v_vehicle_id:=case when tg_op='DELETE' then old.id else new.id end;
 if tg_op<>'INSERT' then perform public.workshop_bump_station_revision(public.workshop_canonical_stage_code(old.pmb_stage)); end if;
 if tg_op<>'DELETE' then perform public.workshop_bump_station_revision(public.workshop_canonical_stage_code(new.pmb_stage)); end if;
 for v_code in
  select distinct public.workshop_stage_code_for_work_key(wi.work_key) from public.vehicle_work_items wi
   where wi.vehicle_id=v_vehicle_id and wi.required and not wi.completed
  union select distinct s.code from public.workshop_bookings b join public.workshop_stages s on s.id=b.stage_id
   where b.vehicle_id=v_vehicle_id and b.status<>'deleted'
 loop perform public.workshop_bump_station_revision(v_code); end loop;
 if tg_op='DELETE' then return old; else return new; end if;
end; $$;

-- Hidden/legacy clients cannot create, move or resize a Sublet booking.
-- Status/completion updates on historical Sublet rows remain allowed.
create or replace function public.workshop_prevent_disabled_planner_booking_mutation()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_enabled boolean; v_mutating boolean; v_location text; v_eta date;
begin
 v_mutating:=tg_op='INSERT';
 if tg_op='UPDATE' then
  v_mutating:=old.stage_id is distinct from new.stage_id
   or old.bay_id is distinct from new.bay_id
   or old.scheduled_start_at is distinct from new.scheduled_start_at
   or old.scheduled_end_at is distinct from new.scheduled_end_at
   or old.default_duration_minutes is distinct from new.default_duration_minutes;
 end if;
 if v_mutating then
  select planner_enabled into v_enabled from public.workshop_stages where id=new.stage_id;
  if coalesce(v_enabled,false)=false then
   raise exception 'This work type does not have a Workshop Planner' using errcode='22023';
  end if;
  select upper(btrim(coalesce(current_location,''))),eta_to_kewdale into v_location,v_eta
  from public.vehicles where id=new.vehicle_id;
  if v_location not in('PMB','YH','IT') then
   raise exception 'Vehicle location is not eligible for Workshop Planner scheduling' using errcode='22023';
  end if;
  if v_location='IT' and v_eta is null then
   raise exception 'ETA to Kewdale is required before scheduling an in-transit vehicle' using errcode='22023';
  end if;
  if v_location='IT' and (new.scheduled_start_at at time zone 'Australia/Perth')::date<v_eta then
   raise exception 'In-transit vehicle cannot be scheduled before ETA to Kewdale' using errcode='22023';
  end if;
 end if;
 return new;
end; $$;
drop trigger if exists workshop_bookings_planner_enabled_guard on public.workshop_bookings;
create trigger workshop_bookings_planner_enabled_guard before insert or update on public.workshop_bookings
for each row execute function public.workshop_prevent_disabled_planner_booking_mutation();

revoke all on function public.workshop_normalize_identifier(text) from public,anon,authenticated;
revoke all on function public.workshop_canonical_stage_code(text) from public,anon,authenticated;
revoke all on function public.workshop_stage_code_for_work_key(text) from public,anon,authenticated;
revoke all on function public.workshop_canonicalize_work_item_key() from public,anon,authenticated;
revoke all on function public.workshop_station_eligibility(text) from public,anon,authenticated;
revoke all on function public.get_station_workshop_snapshot_legacy(text,date,date) from public,anon,authenticated;
revoke all on function public.get_station_workshop_snapshot(text,date,date) from public,anon,authenticated;
revoke all on function public.get_workshop_eligibility_snapshot() from public,anon,authenticated;
revoke all on function public.workshop_station_revision_from_vehicle() from public,anon,authenticated;
revoke all on function public.workshop_prevent_disabled_planner_booking_mutation() from public,anon,authenticated;
grant execute on function public.get_station_workshop_snapshot(text,date,date) to authenticated;
grant execute on function public.get_workshop_eligibility_snapshot() to authenticated;

comment on function public.get_station_workshop_snapshot(text,date,date) is
 'Canonical station snapshot. Shares workshop_station_eligibility with Control Board and rejects planner-disabled Sublet.';
comment on function public.get_workshop_eligibility_snapshot() is
 'Operator-only canonical Control Board counts/candidates shared with dedicated station planners.';
