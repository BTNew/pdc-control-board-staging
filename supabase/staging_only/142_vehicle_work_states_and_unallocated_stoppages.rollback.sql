-- Guarded rollback for 142_vehicle_work_states_and_unallocated_stoppages.sql.
begin;

do $guard$
begin
  if not exists (
    select 1 from public.pdc_staging_environment_sentinel
    where singleton and project_ref='cdsmnqxtyyoeoznmbidd'
  ) or to_regclass('public.pdc_production_environment_sentinel') is not null then
    raise exception 'Migration 142 rollback is staging-only';
  end if;
  if not exists (
    select 1 from supabase_migrations.schema_migrations
    where version='142' and name='vehicle_work_states_and_unallocated_stoppages'
  ) or exists (
    select 1 from supabase_migrations.schema_migrations
    where version~'^[0-9]+$' and version::numeric>142
  ) then
    raise exception 'Migration 142 rollback ledger guard failed';
  end if;
end;
$guard$;

-- The previous validator cannot represent an unallocated stoppage. Return any
-- such row to queued through a transaction-scoped lifecycle authorization.
do $$
declare
  r record;
  v_actor uuid;
begin
  select auth_user_id into v_actor
  from public.pdc_user_roles
  where active is true and account_status = 'approved' and role = 'administrator' and auth_user_id is not null
  order by approved_at nulls last, auth_user_id
  limit 1;
  if v_actor is null then
    raise exception 'Rollback requires an approved administrator identity' using errcode='42501';
  end if;

  for r in
    select id, version
    from public.workshop_bookings
    where status = 'stoppage'::public.workshop_booking_status
      and bay_id is null
    for update
  loop
    insert into public.workshop_transition_authorizations(txid,booking_id,transition,authorized_by)
    values(txid_current(),r.id,'return_to_queue',v_actor)
    on conflict do nothing;

    update public.workshop_bookings
    set status = 'queued'::public.workshop_booking_status,
        stoppage_reason = null,
        stoppage_started_at = null,
        returned_to_queue_at = clock_timestamp(),
        updated_by = v_actor,
        version = version + 1
    where id = r.id and version = r.version;
    if not found then
      raise exception 'Rollback booking version conflict: %', r.id using errcode='40001';
    end if;
  end loop;
end;
$$;

revoke all on function public.set_pdc_vehicle_work_states(uuid,integer,jsonb) from public,anon,authenticated;
drop function if exists public.set_pdc_vehicle_work_states(uuid,integer,jsonb);
drop function if exists public.workshop_return_booking_to_queue(uuid,integer,text);

create or replace function public.workshop_return_booking_to_queue(
  p_booking_id uuid,
  p_expected_version integer,
  p_reason text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking public.workshop_bookings%rowtype;
  v_before_snapshot jsonb;
  v_after_snapshot jsonb;
  v_history_id uuid;
begin
  perform public.require_pdc_role('operator');
  select * into v_booking from public.workshop_bookings where id = p_booking_id for update;
  if not found then
    raise exception 'Workshop booking not found' using errcode = 'P0002';
  end if;
  if v_booking.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'version_conflict', 'conflict', public.workshop_conflict_payload(v_booking.id, 'version_conflict'));
  end if;

  v_before_snapshot := public.workshop_booking_snapshot(p_booking_id);

  update public.workshop_bookings
  set status = 'queued',
      bay_id = null,
      returned_to_queue_at = now(),
      stoppage_reason = coalesce(nullif(trim(coalesce(p_reason, '')), ''), stoppage_reason),
      updated_by = auth.uid(),
      version = version + 1
  where id = p_booking_id;

  update public.workshop_booking_assignments
  set released_at = coalesce(released_at, now()),
      updated_at = now()
  where booking_id = p_booking_id and released_at is null;

  v_after_snapshot := public.workshop_booking_snapshot(p_booking_id);
  v_history_id := public.workshop_write_history(p_booking_id, 'returned_to_queue', v_before_snapshot, v_after_snapshot, coalesce(p_metadata, '{}'::jsonb));
  return jsonb_build_object('ok', true, 'booking', v_after_snapshot, 'history_id', v_history_id);
end;
$$;

create or replace function public.workshop_enforce_booking_lifecycle()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare v_allowed boolean:=false;
begin
  if tg_op='INSERT' or new.status=old.status then return new; end if;
  v_allowed :=
    (old.status in ('queued','planned') and new.status='started') or
    (old.status='started' and new.status='stoppage') or
    (old.status='stoppage' and new.status='started') or
    (old.status in ('started','stoppage') and new.status='completed') or
    (old.status in ('queued','planned','stoppage') and new.status='deleted');
  if old.status='completed' and new.status='queued' then
    v_allowed:=public.workshop_consume_transition_authorization(old.id,'reopen_completed');
  elsif old.status='deleted' and new.status='queued' then
    v_allowed:=public.workshop_consume_transition_authorization(old.id,'restore');
  elsif old.status in ('started','stoppage') and new.status='queued' then
    v_allowed:=public.workshop_consume_transition_authorization(old.id,'return_to_queue');
  end if;
  if not v_allowed then
    raise exception 'Invalid Workshop Planner lifecycle transition: % -> %',old.status,new.status using errcode='22023';
  end if;
  return new;
end $$;

create or replace function public.workshop_enforce_booking_validation()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare
  v_result jsonb;
  v_technician uuid;
  v_allow_unchanged_past boolean:=false;
begin
  if new.deleted_at is not null or new.status not in ('queued','planned','started','stoppage') then return new; end if;
  perform pg_advisory_xact_lock(hashtextextended('workshop:vehicle:'||new.vehicle_id::text,0));
  select a.technician_id into v_technician from public.workshop_booking_assignments a
  where a.booking_id=new.id and a.released_at is null
  order by case when a.assignment_type='primary' then 0 else 1 end,a.assigned_at desc limit 1;
  if tg_op='UPDATE'
     and new.scheduled_start_at is not distinct from old.scheduled_start_at
     and new.scheduled_end_at is not distinct from old.scheduled_end_at then
    v_allow_unchanged_past:=true;
  end if;
  v_result:=public.workshop_validate_booking(new.id,new.vehicle_id,new.stage_id,new.bay_id,new.scheduled_start_at,
    new.scheduled_end_at,new.default_duration_minutes,new.status,v_technician,v_allow_unchanged_past);
  if not coalesce((v_result->>'ok')::boolean,false) then
    raise exception 'Workshop Planner validation rejected booking: %',v_result::text using errcode='22023';
  end if;
  return new;
end $$;

delete from supabase_migrations.schema_migrations
where version='142' and name='vehicle_work_states_and_unallocated_stoppages';

do $postcondition$
begin
  if exists(select 1 from supabase_migrations.schema_migrations where version='142') then
    raise exception 'Migration 142 rollback ledger delete failed';
  end if;
end;
$postcondition$;

commit;
