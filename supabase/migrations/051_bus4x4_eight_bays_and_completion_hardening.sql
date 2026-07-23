-- 051: Bus 4x4 eight-bay capacity and Workshop completion hardening.
-- Forward-only. Does not move, delete, or rewrite operational bookings.

begin;
set local lock_timeout = '5s';

-- Migration 050 relies on this exact race-safe live-job guard. IF NOT EXISTS
-- alone is insufficient because a same-named but differently-defined index could
-- otherwise pass unnoticed.
do $$
declare
  v_index_definition text;
  v_index_predicate text;
  v_index_unique boolean;
begin
  select pg_get_indexdef(c.oid), pg_get_expr(i.indpred, i.indrelid), i.indisunique
  into v_index_definition, v_index_predicate, v_index_unique
  from pg_catalog.pg_class c
  join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  join pg_catalog.pg_index i on i.indexrelid = c.oid
  where n.nspname = 'public' and c.relname = 'workshop_bookings_one_started_per_bay_uidx' and c.relkind = 'i';

  if v_index_definition is null
     or not coalesce(v_index_unique, false)
     or position('USING btree (bay_id)' in v_index_definition) = 0
     or position('(deleted_at IS NULL)' in coalesce(v_index_predicate, '')) = 0
     or position('(status = ''started''' in coalesce(v_index_predicate, '')) = 0
     or position('(bay_id IS NOT NULL)' in coalesce(v_index_predicate, '')) = 0 then
    raise exception 'Migration 051 blocked: Workshop live-bay index definition is missing or unexpected' using errcode = '23514';
  end if;
end $$;

-- Bus 4x4 must expose exactly eight active physical bays. Existing bay UUIDs are
-- retained. Bays outside 1..8 are deactivated only when they have no active work;
-- active operational work is never moved or hidden to make this migration pass.
do $$
declare
  v_stage_id uuid;
  v_active_count integer;
begin
  select id into v_stage_id
  from public.workshop_stages
  where code = 'BUS_4X4' and active and is_physical
  for update;
  if v_stage_id is null then
    raise exception 'Migration 051 blocked: active physical Bus 4x4 stage not found' using errcode = 'P0002';
  end if;

  if exists (
    select 1
    from public.workshop_bays bay
    join public.workshop_bookings booking on booking.bay_id = bay.id
    where bay.stage_id = v_stage_id
      and bay.is_active
      and (bay.bay_number is null or bay.bay_number > 8)
      and booking.deleted_at is null
      and booking.status in ('queued','planned','started','stoppage')
  ) then
    raise exception 'Migration 051 blocked: Bus 4x4 work exists outside bays 1..8' using errcode = '23514';
  end if;

  update public.workshop_bays
  set is_active = false, updated_at = statement_timestamp()
  where stage_id = v_stage_id
    and is_active
    and (bay_number is null or bay_number > 8);

  insert into public.workshop_bays (stage_id, bay_number, code, display_name, is_active, is_sublet_row)
  select v_stage_id,
         bay_number,
         'BUS_4X4-BAY-' || lpad(bay_number::text, 2, '0'),
         'Bus 4x4 Bay ' || lpad(bay_number::text, 2, '0'),
         true,
         false
  from generate_series(1, 8) as seed(bay_number)
  on conflict (stage_id, bay_number) do update
  set is_active = true,
      is_sublet_row = false,
      updated_at = statement_timestamp();

  select count(*) into v_active_count
  from public.workshop_bays
  where stage_id = v_stage_id and is_active;
  if v_active_count <> 8 then
    raise exception 'Migration 051 blocked: Bus 4x4 active bay count is %, expected 8', v_active_count using errcode = '23514';
  end if;
end $$;

-- Complete is intentionally restricted to live or stopped work. An omitted or
-- explicitly-null browser timestamp is normalized to the database clock, keeping
-- completed rows inside snapshot history and canonical work-item timestamps.
create or replace function public.complete_workshop_work(
  p_booking_id uuid,
  p_expected_version integer,
  p_work_key text default null,
  p_actual_end_at timestamptz default now(),
  p_metadata jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_booking public.workshop_bookings%rowtype;
  v_stage_code text;
  v_stage_work_key text;
  v_requested_stage text;
  v_result jsonb;
  v_revision bigint;
  v_end timestamptz := date_trunc('minute', coalesce(p_actual_end_at, statement_timestamp()));
begin
  perform public.workshop_require_planner_operator();
  perform public.workshop_require_version(p_expected_version);
  perform public.workshop_require_booking_active_vehicle(p_booking_id, false);

  select * into v_booking
  from public.workshop_bookings
  where id = p_booking_id
  for update;
  if not found then
    raise exception 'Workshop booking not found' using errcode = 'P0002';
  end if;
  if v_booking.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'version_conflict');
  end if;
  if v_booking.deleted_at is not null or v_booking.status not in ('started','stoppage') then
    return jsonb_build_object('ok', false, 'error', 'not_completable');
  end if;
  if v_booking.actual_start_at is not null and v_end < v_booking.actual_start_at then
    return jsonb_build_object('ok', false, 'error', 'completion_before_start');
  end if;

  select code, work_key into v_stage_code, v_stage_work_key
  from public.workshop_stages
  where id = v_booking.stage_id;

  if p_work_key is not null and btrim(p_work_key) <> '' then
    v_requested_stage := public.workshop_stage_code_for_work_key(p_work_key);
    if v_requested_stage is distinct from v_stage_code then
      raise exception 'Completion work item does not match booking station' using errcode = '22023';
    end if;
  end if;

  v_result := public.workshop_complete_booking(
    p_booking_id,
    p_expected_version,
    v_end,
    coalesce(p_metadata, '{}'::jsonb) || jsonb_build_object('database_clock_completion', p_actual_end_at is null)
  );
  if not coalesce((v_result->>'ok')::boolean, false) then
    return v_result;
  end if;

  update public.vehicle_work_items
  set completed = true,
      completed_by = auth.uid(),
      completed_at = v_end,
      updated_at = statement_timestamp()
  where vehicle_id = v_booking.vehicle_id
    and required
    and public.workshop_stage_code_for_work_key(work_key) = v_stage_code;

  if not found and v_stage_work_key is not null then
    insert into public.vehicle_work_items (vehicle_id, work_key, required, completed, completed_by, completed_at)
    values (v_booking.vehicle_id, v_stage_work_key, true, true, auth.uid(), v_end)
    on conflict (vehicle_id, work_key) do update
    set required = true,
        completed = true,
        completed_by = auth.uid(),
        completed_at = excluded.completed_at,
        updated_at = statement_timestamp();
  end if;

  v_revision := public.workshop_bump_revision();
  return v_result || jsonb_build_object('revision', v_revision, 'work_item_completed', true);
end $$;

revoke all on function public.complete_workshop_work(uuid,integer,text,timestamptz,jsonb) from public, anon;
grant execute on function public.complete_workshop_work(uuid,integer,text,timestamptz,jsonb) to authenticated;

commit;
