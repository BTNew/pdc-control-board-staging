-- Staging-only migration 234: remove stale open-ended Sublet conflicts while preserving atomic overlap prevention.
begin;
set local lock_timeout='20s';
set local statement_timeout='180s';

-- Apply only after the attachment-atomic successor reserved as migration 233.
do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or not exists(select 1 from supabase_migrations.schema_migrations where version='233')
     or exists(select 1 from supabase_migrations.schema_migrations where version='234') then
    raise exception 'PDC_234_STAGING_OR_PREDECESSOR_MISMATCH' using errcode='55000';
  end if;
end
$guard$;

create or replace function public.pdc_sublet_effective_end_exclusive(
  p_status text,
  p_expected_return_date date,
  p_returned_at timestamptz
) returns date
language sql immutable
set search_path=pg_catalog
as $end_date$
  select case
    when p_status='returned' and p_returned_at is not null
      then (p_returned_at at time zone 'Australia/Perth')::date
    when p_status='active' and p_expected_return_date is not null
      then p_expected_return_date+1
    else null
  end
$end_date$;
revoke all on function public.pdc_sublet_effective_end_exclusive(text,date,timestamptz) from public,anon,authenticated,service_role;

create or replace function public.pdc_sublet_away_on_date(p_vehicle_id uuid,p_workshop_date date)
returns boolean language sql stable security definer set search_path=pg_catalog,public as $canonical_away$
  select exists(
    select 1
    from public.pdc_sublet_booking_instances i
    where i.vehicle_id=p_vehicle_id
      and i.status in('active','returned')
      and p_workshop_date>=i.out_date
      and (
        public.pdc_sublet_effective_end_exclusive(i.status,i.expected_return_date,i.returned_at) is null
        or p_workshop_date<public.pdc_sublet_effective_end_exclusive(i.status,i.expected_return_date,i.returned_at)
      )
  );
$canonical_away$;
revoke all on function public.pdc_sublet_away_on_date(uuid,date) from public,anon,authenticated,service_role;

create or replace function public.pdc_canonical_sublet_workshop_overlap_guard()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $canonical_overlap$
declare
  v_end_exclusive date;
  v_conflict record;
begin
  perform public.pdc_lock_canonical_sublet_vehicle(new.vehicle_id);
  if new.status='cancelled' then return new; end if;
  v_end_exclusive:=public.pdc_sublet_effective_end_exclusive(new.status,new.expected_return_date,new.returned_at);
  select b.id,
         (b.scheduled_start_at at time zone 'Australia/Perth')::date as start_date,
         ((public.workshop_booking_effective_end_at(b.id)-interval '1 microsecond') at time zone 'Australia/Perth')::date as end_date,
         b.status::text as booking_status
    into v_conflict
  from public.workshop_bookings b
  where b.vehicle_id=new.vehicle_id
    and b.deleted_at is null
    and b.status in('queued','planned','started','stoppage')
    and daterange(new.out_date,v_end_exclusive,'[)') && daterange(
      (b.scheduled_start_at at time zone 'Australia/Perth')::date,
      ((public.workshop_booking_effective_end_at(b.id)-interval '1 microsecond') at time zone 'Australia/Perth')::date+1,
      '[)')
  order by b.scheduled_start_at,b.id
  limit 1;
  if found then
    raise exception '%',jsonb_build_object(
      'error','workshop_booking_conflict','vehicle_id',new.vehicle_id,
      'workshop_booking_id',v_conflict.id,'workshop_status',v_conflict.booking_status,
      'workshop_start_date_perth',v_conflict.start_date,'workshop_end_date_perth',v_conflict.end_date,
      'sublet_out_date',new.out_date,'sublet_end_exclusive',v_end_exclusive
    )::text using errcode='23514';
  end if;
  return new;
end
$canonical_overlap$;
revoke all on function public.pdc_canonical_sublet_workshop_overlap_guard() from public,anon,authenticated,service_role;

-- Retained legacy path: actual return wins, otherwise expected return bounds the
-- interval through the expected-return day. With neither, the interval is open.
create or replace function public.pdc_sublet_booking_workshop_overlap_guard()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $legacy_overlap$
declare
  v_end_exclusive date;
  v_conflict record;
begin
  if new.booking_date is null and (new.expected_return_date is not null or new.actual_return_date is not null) then
    raise exception '%',jsonb_build_object('error','invalid_date_order','reason','booking_date_required','vehicle_id',new.vehicle_id)::text using errcode='23514';
  end if;
  if new.expected_return_date is not null and new.expected_return_date<new.booking_date then
    raise exception '%',jsonb_build_object('error','invalid_date_order','reason','expected_before_booking','vehicle_id',new.vehicle_id)::text using errcode='23514';
  end if;
  if new.actual_return_date is not null and new.actual_return_date<new.booking_date then
    raise exception '%',jsonb_build_object('error','invalid_date_order','reason','actual_before_booking','vehicle_id',new.vehicle_id)::text using errcode='23514';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('pdc-sublet-workshop:'||new.vehicle_id::text,0));
  if new.booking_date is null then return new; end if;
  v_end_exclusive:=case
    when new.actual_return_date is not null then new.actual_return_date
    when new.expected_return_date is not null then new.expected_return_date+1
    else null
  end;
  select b.id,
         (b.scheduled_start_at at time zone 'Australia/Perth')::date as start_date,
         ((public.workshop_booking_effective_end_at(b.id)-interval '1 microsecond') at time zone 'Australia/Perth')::date as end_date,
         b.status::text as booking_status
    into v_conflict
  from public.workshop_bookings b
  where b.vehicle_id=new.vehicle_id and b.deleted_at is null
    and b.status::text in('queued','planned','started','stoppage')
    and daterange(new.booking_date,v_end_exclusive,'[)') && daterange(
      (b.scheduled_start_at at time zone 'Australia/Perth')::date,
      ((public.workshop_booking_effective_end_at(b.id)-interval '1 microsecond') at time zone 'Australia/Perth')::date+1,'[)')
  order by b.scheduled_start_at,b.id limit 1;
  if found then
    raise exception '%',jsonb_build_object(
      'error','workshop_booking_conflict','vehicle_id',new.vehicle_id,
      'workshop_booking_id',v_conflict.id,'workshop_status',v_conflict.booking_status,
      'workshop_start_date_perth',v_conflict.start_date,'workshop_end_date_perth',v_conflict.end_date,
      'sublet_out_date',new.booking_date,'sublet_end_exclusive',v_end_exclusive
    )::text using errcode='23514';
  end if;
  return new;
end
$legacy_overlap$;
revoke all on function public.pdc_sublet_booking_workshop_overlap_guard() from public,anon,authenticated,service_role;

commit;
