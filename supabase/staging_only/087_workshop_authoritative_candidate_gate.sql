begin;

-- The station snapshot deliberately includes blocked candidates so staff can
-- see why work is not schedulable. Every browser action and every insert path
-- must therefore consume schedule_enabled, not merely row existence.
create or replace function public.workshop_candidate_schedule_gate(
  p_vehicle_id uuid,
  p_stage_code text,
  p_scheduled_start_at timestamptz
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,public
as $$
declare
  v_stage_code text;
  v_candidate record;
begin
  v_stage_code:=public.workshop_canonical_stage_code(p_stage_code);

  select e.* into v_candidate
  from public.workshop_station_eligibility(v_stage_code) e
  where e.vehicle_id=p_vehicle_id;

  if not found then
    return jsonb_build_object('ok',false,'error','vehicle_not_eligible_for_station');
  end if;
  if coalesce(v_candidate.existing_booking,false) then
    return jsonb_build_object('ok',false,'error','active_booking_exists');
  end if;
  if not coalesce(v_candidate.schedule_enabled,false) then
    return jsonb_build_object(
      'ok',false,
      'error',case
        when v_candidate.disabled_reason='missing_eta' then 'missing_eta'
        when v_candidate.disabled_reason='location_ineligible' then 'location_ineligible'
        else 'vehicle_not_eligible_for_station'
      end
    );
  end if;
  if v_candidate.current_location='IT'
     and v_candidate.eta_to_kewdale is not null
     and (p_scheduled_start_at at time zone 'Australia/Perth')::date<v_candidate.eta_to_kewdale then
    return jsonb_build_object('ok',false,'error','it_before_eta');
  end if;
  return jsonb_build_object('ok',true);
end $$;
revoke all on function public.workshop_candidate_schedule_gate(uuid,text,timestamptz) from public,anon,authenticated;

create or replace function public.schedule_vehicle_work(
 p_vehicle_id uuid,p_vehicle_expected_version integer,p_stage_code text,p_bay_number integer,
 p_scheduled_start_at timestamptz,p_duration_minutes integer default 180,p_technician_id uuid default null,
 p_override_reason text default null,p_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions as $$
declare
 v_vehicle public.vehicles%rowtype;
 v_stage public.workshop_stages%rowtype;
 v_result jsonb;
 v_gate jsonb;
 v_override_id uuid;
 v_revision bigint;
 v_code text;
begin
 perform public.workshop_require_planner_operator();
 perform public.workshop_require_version(p_vehicle_expected_version);
 select * into v_vehicle from public.vehicles where id=p_vehicle_id for update;
 if not found then raise exception 'Vehicle not found' using errcode='P0002'; end if;
 if v_vehicle.version<>p_vehicle_expected_version then return jsonb_build_object('ok',false,'error','vehicle_version_conflict'); end if;
 v_code:=public.workshop_canonical_stage_code(p_stage_code);
 select * into v_stage from public.workshop_stages where code=v_code and active and planner_enabled;
 if not found then raise exception 'Unknown or planner-disabled workshop station' using errcode='22023'; end if;

 v_gate:=public.workshop_candidate_schedule_gate(p_vehicle_id,v_code,p_scheduled_start_at);
 if not coalesce((v_gate->>'ok')::boolean,false) then return v_gate; end if;

 if v_stage.is_physical and not public.workshop_parts_ready(p_vehicle_id) then
  if p_override_reason is null or btrim(p_override_reason)='' then return jsonb_build_object('ok',false,'error','parts_incomplete'); end if;
  perform public.require_pdc_role('administrator');
 end if;
 v_result:=public.workshop_create_booking(p_vehicle_id,v_code,p_bay_number,p_scheduled_start_at,p_duration_minutes,p_technician_id,p_metadata);
 if not (v_result->>'ok')::boolean then return v_result; end if;
 if p_override_reason is not null and btrim(p_override_reason)<>'' then
  insert into public.workshop_parts_overrides(vehicle_id,booking_id,work_key,intended_stage_id,reason,previous_state,resulting_state,approved_by,approved_by_email)
  values(p_vehicle_id,(v_result->'booking'->>'booking_id')::uuid,'PARTS',v_stage.id,btrim(p_override_reason),
   jsonb_build_object('vehicle_id',p_vehicle_id,'version',v_vehicle.version),
   jsonb_build_object('vehicle_id',p_vehicle_id,'version',v_vehicle.version),auth.uid(),public.current_actor_email()) returning id into v_override_id;
 end if;
 v_revision:=public.workshop_bump_revision();
 return v_result||jsonb_build_object('override_id',v_override_id,'revision',v_revision);
end $$;
revoke all on function public.schedule_vehicle_work(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.schedule_vehicle_work(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb) to authenticated;

alter function public.cascade_workshop_schedule(text,uuid,integer,text,integer,timestamptz,integer,uuid,integer,text,jsonb)
  rename to cascade_workshop_schedule_pre_087;
revoke all on function public.cascade_workshop_schedule_pre_087(text,uuid,integer,text,integer,timestamptz,integer,uuid,integer,text,jsonb)
  from public,anon,authenticated;

create or replace function public.cascade_workshop_schedule(
 p_operation text,p_target_id uuid,p_target_expected_version integer,p_stage_code text,p_bay_number integer,
 p_scheduled_start_at timestamptz,p_duration_minutes integer,p_technician_id uuid default null,
 p_shift_minutes integer default 0,p_override_reason text default null,p_metadata jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare v_gate jsonb;
begin
 perform public.workshop_require_planner_operator();
 perform public.workshop_require_version(p_target_expected_version);
 if lower(btrim(coalesce(p_operation,'')))='insert' then
  v_gate:=public.workshop_candidate_schedule_gate(p_target_id,p_stage_code,p_scheduled_start_at);
  if not coalesce((v_gate->>'ok')::boolean,false) then return v_gate; end if;
 end if;
 return public.cascade_workshop_schedule_pre_087(
  p_operation,p_target_id,p_target_expected_version,p_stage_code,p_bay_number,
  p_scheduled_start_at,p_duration_minutes,p_technician_id,p_shift_minutes,
  p_override_reason,coalesce(p_metadata,'{}'::jsonb)
 );
end $$;
revoke all on function public.cascade_workshop_schedule(text,uuid,integer,text,integer,timestamptz,integer,uuid,integer,text,jsonb)
  from public,anon,authenticated;
grant execute on function public.cascade_workshop_schedule(text,uuid,integer,text,integer,timestamptz,integer,uuid,integer,text,jsonb)
  to authenticated;

-- Cascade insert now checks the same candidate gate before Parts handling, and
-- schedule_vehicle_work checks it again under the authoritative vehicle lock.

comment on function public.workshop_candidate_schedule_gate(uuid,text,timestamptz) is
  'Staging 087: canonical fail-closed preflight for station snapshot candidates.';
comment on function public.schedule_vehicle_work(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb) is
  'Staging 087: schedule insert uses authoritative candidate schedule_enabled and ETA gate before Parts override or booking DML.';

commit;
