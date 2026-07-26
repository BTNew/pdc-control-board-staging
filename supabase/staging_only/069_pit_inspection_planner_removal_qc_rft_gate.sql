-- Staging-only migration 069: Pit Inspection is external registration transport,
-- not workshop production. Remove its planner/bay capability while preserving the
-- canonical requirement/history, and make the QC -> RFT sequence authoritative.
begin;

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists (
       select 1 from public.pdc_staging_environment_sentinel
       where singleton and project_ref='cdsmnqxtyyoeoznmbidd'
     ) then
    raise exception 'PDC_STAGING_SENTINEL_MISMATCH';
  end if;
  if to_regclass('public.workshop_stages') is null
     or to_regclass('public.workshop_bookings') is null
     or to_regclass('public.workshop_booking_assignments') is null
     or to_regclass('public.vehicle_work_items') is null
     or to_regprocedure('public.workshop_stage_code_for_work_key(text)') is null then
    raise exception 'PDC_MIGRATION_069_DEPENDENCY_MISSING';
  end if;
end;
$guard$;

-- Lock and disable the stage first. Concurrent booking writers either finish before
-- this update and are caught below, or wait and then see planner-disabled after commit.
update public.workshop_stages
set planner_enabled=false,
    updated_at=clock_timestamp()
where code='PIT_INSPECTION'
  and planner_enabled is distinct from false;

-- Do not strand live work in an inaccessible planner. Active Pit rows must be
-- reconciled explicitly and audibly before this capability-removal migration.
do $preflight$
declare v_active_count integer;
begin
  select count(*) into v_active_count
  from public.workshop_bookings b
  join public.workshop_stages s on s.id=b.stage_id
  where s.code='PIT_INSPECTION'
    and b.deleted_at is null
    and b.status::text not in ('completed','deleted','cancelled');
  if v_active_count<>0 then
    raise exception 'PDC_MIGRATION_069_ACTIVE_PIT_BOOKINGS count=%; reconcile before planner removal',v_active_count;
  end if;
end;
$preflight$;

-- Preserve historical Pit bookings and assignments as immutable records. New,
-- restored, rescheduled, lifecycle and assignment mutations already pass through
-- these guards; the disabled stage now fails closed at the database boundary.
create or replace function public.workshop_require_planner_assignment_mutation()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_booking_id uuid; v_stage_code text; v_planner_enabled boolean;
begin
  if auth.uid() is not null then perform public.workshop_require_planner_operator(); end if;
  v_booking_id:=case when tg_op='DELETE' then old.booking_id else new.booking_id end;
  select s.code,coalesce(s.planner_enabled,false)
    into v_stage_code,v_planner_enabled
  from public.workshop_bookings b
  join public.workshop_stages s on s.id=b.stage_id
  where b.id=v_booking_id;
  if not found or not coalesce(v_planner_enabled,false) then
    raise exception 'planner_disabled stage=%',coalesce(v_stage_code,'unknown') using errcode='22023';
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end $$;
revoke all on function public.workshop_require_planner_assignment_mutation() from public,anon,authenticated;

-- One canonical gate is consumed by both QC sign-off and the subsequent RFT
-- transition. PIT_INSPECTION is intentionally excluded; QC itself is also not a
-- staging requirement. Parts and every other required work item remain gates.
create or replace function public.pdc_qc_gate_issues(p_vehicle_id uuid)
returns text[] language sql stable security definer set search_path=pg_catalog,public as $$
  with vehicle as (
    select id,upper(btrim(coalesce(current_location,''))) location,
           upper(regexp_replace(btrim(coalesce(pmb_stage,'')),'[^A-Z0-9]+','','g')) stage
    from public.vehicles where id=p_vehicle_id and lifecycle_state='active' and deleted_at is null
  ), outstanding as (
    select string_agg(distinct upper(btrim(wi.work_key)),', ' order by upper(btrim(wi.work_key))) labels
    from public.vehicle_work_items wi
    where wi.vehicle_id=p_vehicle_id and wi.required and not wi.completed
      and upper(regexp_replace(btrim(coalesce(wi.work_key,'')),'[^A-Z0-9]+','','g'))<>'QC'
      and public.workshop_stage_code_for_work_key(wi.work_key) is distinct from 'PIT_INSPECTION'
  ), active_planner as (
    select string_agg(distinct s.code,', ' order by s.code) labels
    from public.workshop_bookings b
    join public.workshop_stages s on s.id=b.stage_id
    where b.vehicle_id=p_vehicle_id and b.deleted_at is null
      and b.status in ('queued','planned','started','stoppage')
      and s.planner_enabled
  )
  select array_remove(array[
    case when not exists(select 1 from vehicle) then 'active_vehicle_required' end,
    case when (select location from vehicle)<>'PMB' then 'vehicle_must_be_at_pmb' end,
    case when coalesce((select stage from vehicle),'') not in ('','PITINSPECTION','PIT','PITS') then
      'vehicle_still_in_workshop_stage:'||(select stage from vehicle) end,
    case when (select labels from outstanding) is not null then
      'outstanding_required_work:'||(select labels from outstanding) end,
    case when (select labels from active_planner) is not null then
      'active_workshop_booking:'||(select labels from active_planner) end
  ],null::text)
$$;
revoke all on function public.pdc_qc_gate_issues(uuid) from public,anon,authenticated;
comment on function public.pdc_qc_gate_issues(uuid) is
  'Authoritative QC/RFT gate. Requires PMB, no active workshop stage/booking and all required work complete except QC and separately tracked Pit Inspection.';

create or replace function public.pdc_enforce_qc_then_rft()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_issues text[];
begin
  if (upper(btrim(coalesce(new.current_location,'')))='RFT'
      or lower(btrim(coalesce(new.lifecycle_state,'')))='rft')
     and new.qc_completed_at is null then
    raise exception 'RFT vehicles must retain a prior QC sign-off' using errcode='22023';
  end if;

  if old.qc_completed_at is null and new.qc_completed_at is not null then
    if upper(btrim(coalesce(new.current_location,'')))='RFT'
       or lower(btrim(coalesce(new.lifecycle_state,'')))='rft' then
      raise exception 'QC sign-off and RFT transfer must be separate audited transitions' using errcode='22023';
    end if;
    v_issues:=public.pdc_qc_gate_issues(old.id);
    if coalesce(array_length(v_issues,1),0)>0 then
      raise exception 'QC gate failed: %',array_to_string(v_issues,'; ') using errcode='22023';
    end if;
  end if;

  if (upper(btrim(coalesce(old.current_location,''))) is distinct from 'RFT'
      and upper(btrim(coalesce(new.current_location,'')))='RFT')
     or (lower(btrim(coalesce(old.lifecycle_state,''))) is distinct from 'rft'
      and lower(btrim(coalesce(new.lifecycle_state,'')))='rft') then
    if old.qc_completed_at is null then
      raise exception 'QC sign-off must be completed before RFT transfer' using errcode='22023';
    end if;
    v_issues:=public.pdc_qc_gate_issues(old.id);
    if coalesce(array_length(v_issues,1),0)>0 then
      raise exception 'RFT gate failed: %',array_to_string(v_issues,'; ') using errcode='22023';
    end if;
  end if;
  return new;
end $$;
revoke all on function public.pdc_enforce_qc_then_rft() from public,anon,authenticated;

drop trigger if exists vehicles_enforce_qc_then_rft on public.vehicles;
create trigger vehicles_enforce_qc_then_rft
before update of qc_completed_at,current_location,lifecycle_state on public.vehicles
for each row execute function public.pdc_enforce_qc_then_rft();

-- Invalidate the removed station route and the aggregate Control Board snapshot.
update public.workshop_station_revision
set revision=revision+1,updated_at=clock_timestamp()
where stage_code='PIT_INSPECTION';

commit;
