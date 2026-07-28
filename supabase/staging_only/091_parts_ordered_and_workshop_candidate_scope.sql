-- Staging-only migration 091: authoritative Parts Mark Ordered and narrow Workshop candidates.
-- An explicit "at PMB" action is canonical only after it writes vehicles.current_location='PMB'.
begin;

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd') then
    raise exception 'PDC_STAGING_SENTINEL_MISMATCH';
  end if;
  if to_regclass('public.vehicle_parts_updates') is null
     or to_regprocedure('public.workshop_station_eligibility(text)') is null
     or to_regprocedure('public.workshop_candidate_schedule_gate(uuid,text,timestamp with time zone)') is null then
    raise exception 'PDC_MIGRATION_091_DEPENDENCY_MISSING';
  end if;
end;
$guard$;

create or replace function public.mark_pdc_parts_ordered(
  p_vehicle_id uuid,
  p_expected_version integer
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare
  v_vehicle_before public.vehicles%rowtype;
  v_vehicle_after public.vehicles%rowtype;
  v_parts_before public.vehicle_parts_updates%rowtype;
  v_parts_after public.vehicle_parts_updates%rowtype;
begin
  perform public.require_pdc_role('operator');
  select * into v_vehicle_before from public.vehicles where id=p_vehicle_id for update;
  if not found then return jsonb_build_object('ok',false,'error','vehicle_not_found'); end if;
  if p_expected_version is null then return jsonb_build_object('ok',false,'error','missing_expected_version'); end if;
  if v_vehicle_before.version<>p_expected_version then return jsonb_build_object('ok',false,'error','vehicle_version_conflict'); end if;
  if v_vehicle_before.lifecycle_state<>'active' or v_vehicle_before.deleted_at is not null then
    return jsonb_build_object('ok',false,'error','not_in_active_lifecycle');
  end if;

  select * into v_parts_before from public.vehicle_parts_updates
  where vehicle_id=p_vehicle_id order by updated_at desc,id desc limit 1;
  if coalesce(v_parts_before.parts_ordered,false) then
    return jsonb_build_object('ok',false,'error','parts_already_ordered');
  end if;

  insert into public.vehicle_parts_updates(
    vehicle_id,parts_required,parts_ordered,parts_received,parts_stoppage,
    parts_stoppage_reason,worst_eta,updated_by,updated_at
  ) values(
    p_vehicle_id,true,true,coalesce(v_parts_before.parts_received,false),
    coalesce(v_parts_before.parts_stoppage,false),v_parts_before.parts_stoppage_reason,
    v_parts_before.worst_eta,auth.uid(),clock_timestamp()
  ) returning * into v_parts_after;
  if not v_parts_after.parts_ordered then raise exception 'PARTS_ORDERED_WRITE_FAILED'; end if;

  update public.vehicles set version=version+1,updated_by=auth.uid()
  where id=p_vehicle_id returning * into v_vehicle_after;
  perform public.audit_pdc_event(
    'insert','vehicle_parts_updates',v_parts_after.id,p_vehicle_id,
    case when v_parts_before.id is null then null else to_jsonb(v_parts_before) end,
    to_jsonb(v_parts_after),jsonb_build_object('action','mark_pdc_parts_ordered')
  );
  return jsonb_build_object('ok',true,'vehicle',to_jsonb(v_vehicle_after),'parts_update',to_jsonb(v_parts_after));
end;
$$;
revoke all on function public.mark_pdc_parts_ordered(uuid,integer) from public,anon,authenticated;
grant execute on function public.mark_pdc_parts_ordered(uuid,integer) to authenticated;

create or replace function public.workshop_station_eligibility(p_stage_code text)
returns table(vehicle_id uuid,stage_code text,work_key text,current_location text,
 eta_to_kewdale date,existing_booking boolean,schedule_enabled boolean,disabled_reason text)
language sql stable security definer set search_path=pg_catalog,public as $$
 with station as(
  select s.code,s.work_key from public.workshop_stages s
  where s.code=public.workshop_canonical_stage_code(p_stage_code) and s.active and s.planner_enabled
 ), outstanding as(
  select wi.vehicle_id,st.code,st.work_key from public.vehicle_work_items wi cross join station st
  where public.workshop_stage_code_for_work_key(wi.work_key)=st.code and wi.required and not wi.completed
  group by wi.vehicle_id,st.code,st.work_key
 ), active_booking as(
  select distinct b.vehicle_id,st.code from public.workshop_bookings b
  join public.workshop_stages s on s.id=b.stage_id join station st on st.code=s.code
  where b.deleted_at is null and b.status in('queued','planned','started','stoppage')
 )
 select v.id,o.code,o.work_key,upper(btrim(coalesce(v.current_location,''))),v.eta_to_kewdale,
  (ab.vehicle_id is not null),true,null::text
 from outstanding o join public.vehicles v on v.id=o.vehicle_id
 left join active_booking ab on ab.vehicle_id=v.id and ab.code=o.code
 where v.lifecycle_state='active' and v.deleted_at is null
   and upper(btrim(coalesce(v.current_location,''))) in ('PMB','IT')
   and (upper(btrim(coalesce(v.current_location,'')))='PMB' or v.eta_to_kewdale is not null)
$$;
revoke all on function public.workshop_station_eligibility(text) from public,anon,authenticated;
comment on function public.workshop_station_eligibility(text) is
 'Candidate rows are outstanding exact-station work at PMB, or IT with a valid ETA to Kewdale. YH, Other and IT without ETA are omitted.';

create or replace function public.workshop_candidate_schedule_gate(
  p_vehicle_id uuid,p_stage_code text,p_scheduled_start_at timestamptz
)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare v_stage_code text; v_candidate record;
begin
  v_stage_code:=public.workshop_canonical_stage_code(p_stage_code);
  select e.* into v_candidate from public.workshop_station_eligibility(v_stage_code)e where e.vehicle_id=p_vehicle_id;
  if not found then return jsonb_build_object('ok',false,'error','vehicle_not_eligible_for_station'); end if;
  if coalesce(v_candidate.existing_booking,false) then return jsonb_build_object('ok',false,'error','active_booking_exists'); end if;
  if v_candidate.current_location='IT' and v_candidate.eta_to_kewdale is not null
     and (p_scheduled_start_at at time zone 'Australia/Perth')::date<v_candidate.eta_to_kewdale then
    return jsonb_build_object('ok',false,'error','it_before_eta');
  end if;
  return jsonb_build_object('ok',true);
end;
$$;
revoke all on function public.workshop_candidate_schedule_gate(uuid,text,timestamptz) from public,anon,authenticated;

create or replace function public.get_workshop_eligibility_snapshot()
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $$
begin
 perform public.require_pdc_role('viewer');
 return jsonb_build_object('generated_at',now(),
  'semantics',jsonb_build_object('count_label','Eligible outstanding requirements','candidate_authority','required canonical work item incomplete at PMB, or IT with ETA','legacy_pmb_stage_authority',false),
  'stages',(select coalesce(jsonb_agg(jsonb_build_object('code',s.code,'display_name',s.display_name,
   'work_key',s.work_key,'planner_enabled',s.planner_enabled,'revision',public.workshop_current_station_revision(s.code),
   'aliases',(select coalesce(jsonb_agg(a.alias_value order by a.alias_value),'[]'::jsonb)
    from public.workshop_stage_aliases a where a.stage_code=s.code)) order by s.sort_order),'[]'::jsonb)
   from public.workshop_stages s where s.active and s.planner_enabled),
  'candidates',(select coalesce(jsonb_agg(jsonb_build_object('stage_code',e.stage_code,'work_key',e.work_key,
   'existing_booking',e.existing_booking,'schedule_enabled',e.schedule_enabled,'disabled_reason',e.disabled_reason,
   'vehicle',jsonb_build_object('id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,'stock_number',v.stock_number,
    'toyota_order_number',v.toyota_order_number,'job_card_number',v.job_card_number,'customer_name',v.customer_name,
    'make',v.make,'model',v.model,'registration',v.registration,'current_location',v.current_location,'pmb_stage',v.pmb_stage,
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
end;
$$;
revoke all on function public.get_workshop_eligibility_snapshot() from public,anon;
grant execute on function public.get_workshop_eligibility_snapshot() to authenticated,service_role;

update public.workshop_station_revision set revision=revision+1,updated_at=clock_timestamp();
commit;
