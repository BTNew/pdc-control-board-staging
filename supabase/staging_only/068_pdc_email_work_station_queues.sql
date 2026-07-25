-- Staging-only migration 068: show PD/job-card requirements in their station queues.
--
-- Required canonical work is visible in the matching station queue immediately,
-- including new email-created vehicles whose location is still Other. Location and
-- ETA safety gates remain in force: an ineligible card is visible but cannot be
-- scheduled into a physical bay/time until those gates pass.
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
  if to_regprocedure('public.workshop_station_eligibility(text)') is null
     or to_regclass('public.vehicle_work_items') is null
     or to_regclass('public.workshop_stages') is null then
    raise exception 'PDC_MIGRATION_068_DEPENDENCY_MISSING';
  end if;
end;
$guard$;

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
  (ab.vehicle_id is not null),
  case when upper(btrim(coalesce(v.current_location,''))) in('PMB','YH') then true
       when upper(btrim(coalesce(v.current_location,'')))='IT' and v.eta_to_kewdale is not null then true else false end,
  case when upper(btrim(coalesce(v.current_location,'')))='IT' and v.eta_to_kewdale is null then 'missing_eta'
       when upper(btrim(coalesce(v.current_location,''))) not in('PMB','YH','IT') then 'location_ineligible' else null end
 from outstanding o join public.vehicles v on v.id=o.vehicle_id
 left join active_booking ab on ab.vehicle_id=v.id and ab.code=o.code
 where v.lifecycle_state='active' and v.deleted_at is null
$$;
revoke all on function public.workshop_station_eligibility(text) from public,anon,authenticated;

comment on function public.workshop_station_eligibility(text) is
  'Station queue candidates come from outstanding canonical work. Other/ineligible locations remain visible with schedule_enabled=false until location/ETA gates pass.';

-- Force every open station planner to refetch the expanded unscheduled queue.
update public.workshop_station_revision
set revision=revision+1,updated_at=clock_timestamp()
where stage_code in ('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','PIT_INSPECTION');

commit;
