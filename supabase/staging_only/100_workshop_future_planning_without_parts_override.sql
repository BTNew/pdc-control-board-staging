begin;

-- A future planner booking is a time allocation only. It does not mark Parts
-- ordered, reserve stock, or authorise physical bay entry. The Start RPC keeps
-- the separate administrator-only Parts-incomplete entry override.
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
 v_result:=public.workshop_create_booking(p_vehicle_id,v_code,p_bay_number,p_scheduled_start_at,p_duration_minutes,p_technician_id,
   coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('parts_planning_only',not public.workshop_parts_ready(p_vehicle_id)));
 if not coalesce((v_result->>'ok')::boolean,false) then return v_result; end if;
 v_revision:=public.workshop_bump_revision();
 return v_result||jsonb_build_object('override_id',null,'revision',v_revision,'parts_reserved',false);
end $$;
revoke all on function public.schedule_vehicle_work(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.schedule_vehicle_work(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb) to authenticated;

-- Migration 077's atomic cascade still contains its obsolete planning-time
-- Parts check. Supply a private, non-audited compatibility marker only to that
-- older inner function. schedule_vehicle_work above deliberately ignores the
-- marker and creates no Parts override; physical Start remains unchanged.
create or replace function public.cascade_workshop_schedule(
 p_operation text,p_target_id uuid,p_target_expected_version integer,p_stage_code text,p_bay_number integer,
 p_scheduled_start_at timestamptz,p_duration_minutes integer,p_technician_id uuid default null,
 p_shift_minutes integer default 0,p_override_reason text default null,p_metadata jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare
 v_gate jsonb;
 v_inner_reason text;
begin
 perform public.workshop_require_planner_operator();
 perform public.workshop_require_version(p_target_expected_version);
 if lower(btrim(coalesce(p_operation,'')))='insert' then
  v_gate:=public.workshop_candidate_schedule_gate(p_target_id,p_stage_code,p_scheduled_start_at);
  if not coalesce((v_gate->>'ok')::boolean,false) then return v_gate; end if;
  v_inner_reason:='__future_planning_does_not_reserve_parts__';
 else
  v_inner_reason:=p_override_reason;
 end if;
 return public.cascade_workshop_schedule_pre_087(
  p_operation,p_target_id,p_target_expected_version,p_stage_code,p_bay_number,
  p_scheduled_start_at,p_duration_minutes,p_technician_id,p_shift_minutes,
  v_inner_reason,coalesce(p_metadata,'{}'::jsonb)
 );
end $$;
revoke all on function public.cascade_workshop_schedule(text,uuid,integer,text,integer,timestamptz,integer,uuid,integer,text,jsonb)
  from public,anon,authenticated;
grant execute on function public.cascade_workshop_schedule(text,uuid,integer,text,integer,timestamptz,integer,uuid,integer,text,jsonb)
  to authenticated;

comment on function public.schedule_vehicle_work(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb) is
 'Staging 100: future planning does not reserve Parts or create an entry override; physical Start remains Parts-gated.';
comment on function public.cascade_workshop_schedule(text,uuid,integer,text,integer,timestamptz,integer,uuid,integer,text,jsonb) is
 'Staging 100: atomic future planning permits Parts-incomplete candidates without changing Parts authority.';

commit;
