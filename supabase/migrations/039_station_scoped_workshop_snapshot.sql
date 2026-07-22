-- Station-scoped Workshop Planner snapshot.
-- Additive only: the existing combined get_workshop_snapshot() RPC remains
-- unchanged for the temporary rollback route.

-- One revision row per station allows a dedicated planner to subscribe to
-- only its own operational changes rather than the legacy global revision.
create table if not exists public.workshop_station_revision (
  stage_code text primary key,
  revision bigint not null default 0,
  updated_at timestamptz not null default now()
);

insert into public.workshop_station_revision(stage_code)
select code from public.workshop_stages
on conflict (stage_code) do nothing;

alter table public.workshop_station_revision enable row level security;
drop policy if exists workshop_station_revision_select_operator on public.workshop_station_revision;
create policy workshop_station_revision_select_operator
on public.workshop_station_revision for select to authenticated
using (public.is_pdc_role('operator'));
grant select on public.workshop_station_revision to authenticated;
revoke insert, update, delete on public.workshop_station_revision from public, anon, authenticated;

create or replace function public.workshop_bump_station_revision(p_stage_code text)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_code text := upper(btrim(coalesce(p_stage_code, ''))); v_revision bigint;
begin
  if v_code = '' or not exists (select 1 from public.workshop_stages where code = v_code) then return null; end if;
  insert into public.workshop_station_revision(stage_code, revision, updated_at)
  values (v_code, 1, now())
  on conflict (stage_code) do update set revision = public.workshop_station_revision.revision + 1, updated_at = now()
  returning revision into v_revision;
  return v_revision;
end;
$$;

create or replace function public.workshop_current_station_revision(p_stage_code text)
returns bigint language sql stable security definer set search_path = public as $$
  select coalesce((select revision from public.workshop_station_revision where stage_code = upper(btrim(p_stage_code))), 0);
$$;

create or replace function public.workshop_stage_code_for_work_key(p_work_key text)
returns text language sql stable security definer set search_path = public as $$
  select code from public.workshop_stages
  where case code when 'BUS_4X4' then 'BUS4X4' when 'PIT_INSPECTION' then 'PITINSPECTION' else replace(code, '_', '') end
    = upper(replace(coalesce(p_work_key, ''), '_', ''))
  limit 1;
$$;

create or replace function public.workshop_station_revision_from_booking()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_old text; v_new text;
begin
  if tg_op <> 'INSERT' then select code into v_old from public.workshop_stages where id = old.stage_id; end if;
  if tg_op <> 'DELETE' then select code into v_new from public.workshop_stages where id = new.stage_id; end if;
  perform public.workshop_bump_station_revision(v_old);
  if v_new is distinct from v_old then perform public.workshop_bump_station_revision(v_new); end if;
  if tg_op = 'DELETE' then return old; else return new; end if;
end;
$$;

create or replace function public.workshop_station_revision_from_vehicle()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_code text; v_vehicle_id uuid;
begin
  v_vehicle_id := case when tg_op = 'DELETE' then old.id else new.id end;
  if tg_op <> 'INSERT' then perform public.workshop_bump_station_revision(old.pmb_stage); end if;
  if tg_op <> 'DELETE' and (tg_op = 'INSERT' or new.pmb_stage is distinct from old.pmb_stage) then
    perform public.workshop_bump_station_revision(new.pmb_stage);
  end if;
  for v_code in
    select distinct s.code from public.workshop_bookings b join public.workshop_stages s on s.id = b.stage_id
    where b.vehicle_id = v_vehicle_id and b.status <> 'deleted'
  loop perform public.workshop_bump_station_revision(v_code); end loop;
  if tg_op = 'DELETE' then return old; else return new; end if;
end;
$$;

create or replace function public.workshop_station_revision_from_work_item()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_old text; v_new text;
begin
  if tg_op <> 'INSERT' then v_old := public.workshop_stage_code_for_work_key(old.work_key); end if;
  if tg_op <> 'DELETE' then v_new := public.workshop_stage_code_for_work_key(new.work_key); end if;
  perform public.workshop_bump_station_revision(v_old);
  if v_new is distinct from v_old then perform public.workshop_bump_station_revision(v_new); end if;
  if tg_op = 'DELETE' then return old; else return new; end if;
end;
$$;

create or replace function public.workshop_station_revision_from_booking_child()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_booking_id uuid; v_code text;
begin
  v_booking_id := case when tg_op = 'DELETE' then old.booking_id else new.booking_id end;
  select s.code into v_code from public.workshop_bookings b join public.workshop_stages s on s.id = b.stage_id where b.id = v_booking_id;
  perform public.workshop_bump_station_revision(v_code);
  if tg_op = 'DELETE' then return old; else return new; end if;
end;
$$;

drop trigger if exists workshop_bookings_station_revision on public.workshop_bookings;
create trigger workshop_bookings_station_revision after insert or update or delete on public.workshop_bookings
for each row execute function public.workshop_station_revision_from_booking();
drop trigger if exists vehicles_station_revision on public.vehicles;
create trigger vehicles_station_revision after insert or update or delete on public.vehicles
for each row execute function public.workshop_station_revision_from_vehicle();
drop trigger if exists vehicle_work_items_station_revision on public.vehicle_work_items;
create trigger vehicle_work_items_station_revision after insert or update or delete on public.vehicle_work_items
for each row execute function public.workshop_station_revision_from_work_item();
drop trigger if exists workshop_assignments_station_revision on public.workshop_booking_assignments;
create trigger workshop_assignments_station_revision after insert or update or delete on public.workshop_booking_assignments
for each row execute function public.workshop_station_revision_from_booking_child();
drop trigger if exists workshop_parts_overrides_station_revision on public.workshop_parts_overrides;
create trigger workshop_parts_overrides_station_revision after insert or update or delete on public.workshop_parts_overrides
for each row execute function public.workshop_station_revision_from_booking_child();

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'workshop_station_revision'
  ) then
    alter publication supabase_realtime add table public.workshop_station_revision;
  end if;
end;
$$;

revoke all on function public.workshop_bump_station_revision(text) from public, anon, authenticated;
revoke all on function public.workshop_current_station_revision(text) from public, anon, authenticated;
revoke all on function public.workshop_stage_code_for_work_key(text) from public, anon, authenticated;
revoke all on function public.workshop_station_revision_from_booking() from public, anon, authenticated;
revoke all on function public.workshop_station_revision_from_vehicle() from public, anon, authenticated;
revoke all on function public.workshop_station_revision_from_work_item() from public, anon, authenticated;
revoke all on function public.workshop_station_revision_from_booking_child() from public, anon, authenticated;

create or replace function public.get_station_workshop_snapshot(
  p_stage_code text,
  p_date_from date,
  p_date_to date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_stage_code text := upper(btrim(coalesce(p_stage_code, '')));
  v_stage_id uuid;
  v_work_key text;
  v_from timestamptz;
  v_to timestamptz;
  v_vehicle_ids uuid[] := '{}'::uuid[];
begin
  perform public.require_pdc_role('operator');

  if p_date_from is null or p_date_to is null or p_date_to < p_date_from or p_date_to > p_date_from + 31 then
    raise exception 'Invalid station planner date range' using errcode = '22023';
  end if;

  select id into v_stage_id
  from public.workshop_stages
  where code = v_stage_code and active = true;

  if v_stage_id is null then
    raise exception 'Unknown or inactive workshop station' using errcode = '22023';
  end if;

  v_work_key := case v_stage_code
    when 'BUS_4X4' then 'BUS4X4'
    when 'PIT_INSPECTION' then 'PITINSPECTION'
    else replace(v_stage_code, '_', '')
  end;
  v_from := p_date_from::timestamp at time zone 'Australia/Perth';
  v_to := (p_date_to + 1)::timestamp at time zone 'Australia/Perth';

  select coalesce(array_agg(distinct scoped.vehicle_id), '{}'::uuid[])
  into v_vehicle_ids
  from (
    select b.vehicle_id
    from public.workshop_bookings b
    where b.stage_id = v_stage_id
      and b.status <> 'deleted'
      and (
        (b.status not in ('completed', 'stoppage') and b.scheduled_start_at < v_to and b.scheduled_end_at > v_from)
        or b.status = 'stoppage'
        or (b.status = 'completed' and b.actual_end_at >= v_from and b.actual_end_at < v_to)
      )
    union
    select wi.vehicle_id
    from public.vehicle_work_items wi
    join public.vehicles v on v.id = wi.vehicle_id
    where upper(replace(wi.work_key, '_', '')) = v_work_key
      and wi.required = true
      and wi.completed = false
      and v.lifecycle_state = 'active'
      and v.deleted_at is null
    union
    select v.id
    from public.vehicles v
    where upper(coalesce(v.pmb_stage, '')) = v_stage_code
      and v.lifecycle_state = 'active'
      and v.deleted_at is null
  ) scoped;

  return jsonb_build_object(
    'revision', public.workshop_current_station_revision(v_stage_code),
    'generated_at', now(),
    'scope', jsonb_build_object(
      'stage_code', v_stage_code,
      'date_from', p_date_from,
      'date_to', p_date_to
    ),
    'settings', (
      select coalesce(jsonb_object_agg(key, value), '{}'::jsonb)
      from public.workshop_settings
    ),
    'stages', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', id, 'code', code, 'display_name', display_name, 'sort_order', sort_order,
        'is_physical', is_physical, 'is_sublet', is_sublet, 'active', active
      ) order by sort_order), '[]'::jsonb)
      from public.workshop_stages
      where id = v_stage_id
    ),
    'bays', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', id, 'stage_id', stage_id, 'bay_number', bay_number, 'code', code,
        'display_name', display_name, 'is_active', is_active, 'is_sublet_row', is_sublet_row,
        'default_technician_id', default_technician_id
      ) order by bay_number), '[]'::jsonb)
      from public.workshop_bays
      where stage_id = v_stage_id and is_active = true
    ),
    'technicians', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', t.id, 'name', t.name, 'role_type', t.role_type, 'active', t.active,
        'can_fit_stages', t.can_fit_stages
      ) order by t.name), '[]'::jsonb)
      from public.workshop_technicians t
      where t.active = true
        and (
          v_stage_code = any(t.can_fit_stages)
          or t.id in (select default_technician_id from public.workshop_bays where stage_id = v_stage_id)
          or t.id in (
            select a.technician_id
            from public.workshop_booking_assignments a
            join public.workshop_bookings b on b.id = a.booking_id
            where b.stage_id = v_stage_id and a.released_at is null
          )
        )
    ),
    'bookings', (
      select coalesce(jsonb_agg(public.workshop_booking_snapshot(b.id)), '[]'::jsonb)
      from public.workshop_bookings b
      where b.stage_id = v_stage_id
        and b.status <> 'deleted'
        and (
          (b.status not in ('completed', 'stoppage') and b.scheduled_start_at < v_to and b.scheduled_end_at > v_from)
          or b.status = 'stoppage'
          or (b.status = 'completed' and b.actual_end_at >= v_from and b.actual_end_at < v_to)
        )
    ),
    'active_stoppages', (
      select coalesce(jsonb_agg(public.workshop_booking_snapshot(b.id)), '[]'::jsonb)
      from public.workshop_bookings b
      where b.stage_id = v_stage_id and b.status = 'stoppage'
    ),
    'vehicles', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', v.id,
        'permanent_vehicle_id', v.permanent_vehicle_id,
        'stock_number', v.stock_number,
        'vin', v.vin,
        'toyota_order_number', v.toyota_order_number,
        'job_card_number', v.job_card_number,
        'customer_name', v.customer_name,
        'make', v.make,
        'model', v.model,
        'registration', v.registration,
        'current_location', v.current_location,
        'pmb_stage', v.pmb_stage,
        'pmb_bay_stage', v.pmb_bay_stage,
        'pmb_bay_number', v.pmb_bay_number,
        'eta_to_kewdale', v.eta_to_kewdale,
        'active_workshop_booking_id', v.active_workshop_booking_id,
        'workshop_status', v.workshop_status,
        'version', v.version
      )), '[]'::jsonb)
      from public.vehicles v
      where v.id = any(v_vehicle_ids)
    ),
    'work_items', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'vehicle_id', wi.vehicle_id,
        'work_key', wi.work_key,
        'required', wi.required,
        'completed', wi.completed,
        'completed_at', wi.completed_at
      )), '[]'::jsonb)
      from public.vehicle_work_items wi
      where wi.vehicle_id = any(v_vehicle_ids)
        and upper(replace(wi.work_key, '_', '')) = v_work_key
    ),
    'parts_overrides', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', o.id, 'vehicle_id', o.vehicle_id, 'booking_id', o.booking_id,
        'reason', o.reason, 'approved_by_email', o.approved_by_email,
        'approved_at', o.approved_at
      ) order by o.approved_at desc), '[]'::jsonb)
      from public.workshop_parts_overrides o
      where o.booking_id in (
        select b.id
        from public.workshop_bookings b
        where b.stage_id = v_stage_id
          and b.status <> 'deleted'
          and (
            (b.status not in ('completed', 'stoppage') and b.scheduled_start_at < v_to and b.scheduled_end_at > v_from)
            or b.status = 'stoppage'
            or (b.status = 'completed' and b.actual_end_at >= v_from and b.actual_end_at < v_to)
          )
      )
    )
  );
end;
$$;

revoke all on function public.get_station_workshop_snapshot(text, date, date) from public, anon, authenticated;
grant execute on function public.get_station_workshop_snapshot(text, date, date) to authenticated;

comment on function public.get_station_workshop_snapshot(text, date, date) is
  'Returns one active workshop station, its bays, relevant technicians, date-scoped bookings/completions, active stoppages and awaiting-schedule candidates. Operator+ only.';
