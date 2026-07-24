-- Migration 052: concurrency-safe Bus 4x4 eight-bay reconciliation.
-- This supersedes migration 051's bay-capacity reconciliation by locking
-- booking DML for the bounded transaction before checking or changing bay
-- visibility. It never moves, rewrites, deletes, or rebooks operational work.
begin;

lock table public.workshop_bookings in share row exclusive mode;

do $$
declare
  v_stage_id uuid;
  v_active_count integer;
  v_hidden_active_count integer;
begin
  select id into v_stage_id
  from public.workshop_stages
  where code = 'BUS_4X4'
  for update;

  if v_stage_id is null then
    raise exception 'BUS_4X4 stage not found; migration 052 aborted';
  end if;

  -- Lock every current Bus 4x4 bay row after booking DML is blocked.
  perform 1
  from public.workshop_bays
  where stage_id = v_stage_id
  for update;

  -- Fail closed if any active operational booking is attached to an inactive
  -- Bus 4x4 bay or a bay outside the approved physical range 1..8.
  select count(*) into v_hidden_active_count
  from public.workshop_bookings wb
  join public.workshop_bays bay on bay.id = wb.bay_id
  where bay.stage_id = v_stage_id
    and wb.deleted_at is null
    and wb.status in ('queued', 'planned', 'started', 'stoppage')
    and (bay.is_active is not true or bay.bay_number not between 1 and 8);

  if v_hidden_active_count <> 0 then
    raise exception 'Migration 052 aborted: % active Bus 4x4 booking(s) would be hidden outside active bays 1..8', v_hidden_active_count;
  end if;

  insert into public.workshop_bays(stage_id, bay_number, code, display_name, is_active, is_sublet_row)
  select
    v_stage_id,
    n,
    'BUS_4X4-BAY-' || lpad(n::text, 2, '0'),
    'Bus 4x4 Bay ' || lpad(n::text, 2, '0'),
    true,
    false
  from generate_series(1, 8) n
  on conflict (stage_id, bay_number) do update
    set is_active = true,
        is_sublet_row = false,
        updated_at = statement_timestamp();

  update public.workshop_bays
  set is_active = false,
      updated_at = now()
  where stage_id = v_stage_id
    and bay_number not between 1 and 8
    and is_active is true;

  select count(*) into v_active_count
  from public.workshop_bays
  where stage_id = v_stage_id
    and is_active;

  if v_active_count <> 8 then
    raise exception 'Migration 052 expected exactly 8 active Bus 4x4 bays, found %', v_active_count;
  end if;

  -- Recheck while the booking DML lock is still held.
  select count(*) into v_hidden_active_count
  from public.workshop_bookings wb
  join public.workshop_bays bay on bay.id = wb.bay_id
  where bay.stage_id = v_stage_id
    and wb.deleted_at is null
    and wb.status in ('queued', 'planned', 'started', 'stoppage')
    and (bay.is_active is not true or bay.bay_number not between 1 and 8);

  if v_hidden_active_count <> 0 then
    raise exception 'Migration 052 postcondition failed: % active Bus 4x4 booking(s) are hidden', v_hidden_active_count;
  end if;
end
$$;

commit;
