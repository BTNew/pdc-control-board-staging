-- Staging-only migration 103: restore Pit Inspection as the eighth physical
-- Workshop Planner station while retaining the separate Department of Transport
-- PIT vehicle location. Outstanding Pit work again gates QC/RFT.
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
  if not exists (
       select 1 from supabase_migrations.schema_migrations where version='102'
     )
     or to_regclass('public.workshop_stages') is null
     or to_regclass('public.workshop_bays') is null
     or to_regclass('public.workshop_bookings') is null
     or to_regclass('public.vehicle_work_items') is null
     or to_regprocedure('public.workshop_stage_code_for_work_key(text)') is null
     or to_regprocedure('public.workshop_bump_revision()') is null then
    raise exception 'PDC_MIGRATION_103_DEPENDENCY_MISSING';
  end if;
end;
$guard$;

-- A disabled Pit stage must not have acquired live work through a hidden or legacy
-- writer. Stop rather than silently making unexplained rows operational again.
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
    raise exception 'PDC_MIGRATION_103_ACTIVE_PIT_BOOKING_CONTRADICTION count=%',v_active_count;
  end if;
end;
$preflight$;

update public.workshop_stages
set planner_enabled=true,
    active=true,
    is_physical=true,
    is_sublet=false,
    work_key='pitInspection',
    updated_at=clock_timestamp()
where code='PIT_INSPECTION';

-- Pit is a real required-work gate again. The external PIT location remains a
-- separate current_location value and does not satisfy the PMB/QC gate.
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
    case when (select location from vehicle) not in ('PMB','QC') then 'vehicle_must_be_at_pmb_or_qc_gate' end,
    case when coalesce((select stage from vehicle),'')<>'' then
      'vehicle_still_in_workshop_stage:'||(select stage from vehicle) end,
    case when (select labels from outstanding) is not null then
      'outstanding_required_work:'||(select labels from outstanding) end,
    case when (select labels from active_planner) is not null then
      'active_workshop_booking:'||(select labels from active_planner) end
  ],null::text)
$$;
revoke all on function public.pdc_qc_gate_issues(uuid) from public,anon,authenticated;
grant execute on function public.pdc_qc_gate_issues(uuid) to service_role;
comment on function public.pdc_qc_gate_issues(uuid) is
  'Authoritative QC/RFT gate. Requires PMB/QC, PMB unallocated, no active planner booking, and every required station item including Pit Inspection complete.';

insert into public.workshop_station_revision(stage_code,revision,updated_at)
values('PIT_INSPECTION',1,clock_timestamp())
on conflict(stage_code) do update
set revision=public.workshop_station_revision.revision+1,
    updated_at=clock_timestamp();
select public.workshop_bump_revision();

commit;
