-- Staging-only migration 108: Pit inspection remains a workflow/status requirement,
-- but it is not a schedulable Workshop Planner bay.
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
     or to_regclass('public.workshop_bays') is null
     or to_regclass('public.workshop_bookings') is null then
    raise exception 'PDC_MIGRATION_108_DEPENDENCY_MISSING';
  end if;
  if exists (
    select 1
    from public.workshop_bookings booking
    join public.workshop_stages stage on stage.id=booking.stage_id
    where stage.code='PIT_INSPECTION'
      and booking.deleted_at is null
      and booking.status in ('queued','planned','started','stoppage')
  ) then
    raise exception 'PDC_MIGRATION_108_ACTIVE_PIT_BOOKINGS_REQUIRE_REVIEW';
  end if;
end;
$guard$;

update public.workshop_stages
set planner_enabled=false,
    updated_at=clock_timestamp()
where code='PIT_INSPECTION'
  and planner_enabled;

update public.workshop_bays
set is_active=false,
    updated_at=clock_timestamp()
where stage_id=(select id from public.workshop_stages where code='PIT_INSPECTION')
  and is_active;

update public.workshop_station_revision
set revision=revision+1,
    updated_at=clock_timestamp()
where stage_code='PIT_INSPECTION';

select public.workshop_bump_revision();

comment on column public.workshop_stages.planner_enabled is
  'Whether the stage owns a schedulable Workshop Planner.';

-- Pit inspection remains workflow/status-only and has no Workshop bay.

commit;
