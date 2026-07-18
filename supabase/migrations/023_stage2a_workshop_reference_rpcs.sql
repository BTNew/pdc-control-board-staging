-- Migration 023: Stage 2A -- protected RPCs for shared workshop
-- lookup/configuration data (mechanics, salespeople, sublet
-- providers, workshop bays, workshop configuration).
--
-- Independent-review remediation, Stage 2A. Every RPC below follows
-- the exact pattern already proven throughout this project's earlier
-- migrated actions (move_vehicle, mark_vehicle_deleted,
-- qc_complete_vehicle, the workshop planner's shared-action bridge):
-- perform public.require_pdc_role(...) first, validate inputs
-- explicitly, use p_expected_version optimistic locking on every
-- edit, return {ok, error, ...} on an expected conflict rather than
-- throwing, and call public.audit_pdc_event() on every successful
-- write. There is deliberately NO single generic
-- "update_reference_record" RPC -- one narrow RPC per real business
-- action, per the explicit instruction.
--
-- Role mapping used throughout (confirmed against the deployed
-- pdc_role enum {viewer,operator,importer,administrator} and this
-- project's own docs, which state operator = "controller" in the
-- business-facing role names used in the task brief):
--   viewer         -> read permitted active lookup data only
--   operator       -> read all lookup data; may assign an existing
--                      active technician/provider during normal
--                      operational workflows (already implemented by
--                      the pre-existing assign_booking_technician/
--                      change_booking_bay RPCs -- NOT re-implemented
--                      here) but may NOT add/edit/deactivate any
--                      lookup/configuration record
--   administrator  -> full add/edit/deactivate/configure authority

-- =====================================================================
-- Mechanics / technicians
-- =====================================================================

create or replace function public.list_technicians(p_include_inactive boolean default false)
returns setof public.workshop_technicians
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_pdc_role('viewer');
  if p_include_inactive then
    return query select * from public.workshop_technicians order by sort_order, name;
  else
    return query select * from public.workshop_technicians where active order by sort_order, name;
  end if;
end;
$$;

create or replace function public.add_technician(
  p_name text,
  p_role_type text default 'technician',
  p_code text default null,
  p_can_fit_stages text[] default '{}'::text[]
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
  v_code text;
  v_row public.workshop_technicians%rowtype;
  v_next_sort integer;
begin
  perform public.require_pdc_role('administrator');

  v_name := trim(coalesce(p_name, ''));
  if v_name = '' then
    return jsonb_build_object('ok', false, 'error', 'name_required');
  end if;

  v_code := nullif(trim(coalesce(p_code, '')), '');

  if exists (select 1 from public.workshop_technicians where lower(name) = lower(v_name)) then
    return jsonb_build_object('ok', false, 'error', 'duplicate_name');
  end if;
  if v_code is not null and exists (select 1 from public.workshop_technicians where lower(code) = lower(v_code)) then
    return jsonb_build_object('ok', false, 'error', 'duplicate_code');
  end if;

  select coalesce(max(sort_order), 0) + 1 into v_next_sort from public.workshop_technicians;

  insert into public.workshop_technicians (name, role_type, code, can_fit_stages, sort_order, created_by, updated_by)
  values (v_name, coalesce(p_role_type, 'technician'), v_code, coalesce(p_can_fit_stages, '{}'::text[]), v_next_sort, auth.uid(), auth.uid())
  returning * into v_row;

  perform public.audit_pdc_event('reference_change', 'workshop_technicians', v_row.id, null, null, to_jsonb(v_row),
    jsonb_build_object('action', 'add_technician'));

  return jsonb_build_object('ok', true, 'technician', to_jsonb(v_row));
end;
$$;

create or replace function public.edit_technician(
  p_technician_id uuid,
  p_expected_version integer,
  p_name text default null,
  p_role_type text default null,
  p_code text default null,
  p_can_fit_stages text[] default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_before public.workshop_technicians%rowtype;
  v_after public.workshop_technicians%rowtype;
  v_name text;
  v_code text;
begin
  perform public.require_pdc_role('administrator');

  select * into v_before from public.workshop_technicians where id = p_technician_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if v_before.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'version_conflict', 'current', to_jsonb(v_before));
  end if;

  v_name := case when p_name is not null then trim(p_name) else v_before.name end;
  if v_name = '' then
    return jsonb_build_object('ok', false, 'error', 'name_required');
  end if;
  if p_name is not null and lower(v_name) <> lower(v_before.name)
     and exists (select 1 from public.workshop_technicians where lower(name) = lower(v_name) and id <> p_technician_id) then
    return jsonb_build_object('ok', false, 'error', 'duplicate_name');
  end if;

  v_code := case when p_code is not null then nullif(trim(p_code), '') else v_before.code end;
  if v_code is not null and (p_code is not null) and lower(coalesce(v_code,'')) <> lower(coalesce(v_before.code,''))
     and exists (select 1 from public.workshop_technicians where lower(code) = lower(v_code) and id <> p_technician_id) then
    return jsonb_build_object('ok', false, 'error', 'duplicate_code');
  end if;

  update public.workshop_technicians
  set name = v_name,
      role_type = coalesce(p_role_type, role_type),
      code = v_code,
      can_fit_stages = coalesce(p_can_fit_stages, can_fit_stages),
      version = version + 1,
      updated_by = auth.uid(),
      updated_at = now()
  where id = p_technician_id
  returning * into v_after;

  perform public.audit_pdc_event('reference_change', 'workshop_technicians', v_after.id, null, to_jsonb(v_before), to_jsonb(v_after),
    jsonb_build_object('action', 'edit_technician'));

  return jsonb_build_object('ok', true, 'technician', to_jsonb(v_after));
end;
$$;

create or replace function public.set_technician_active(
  p_technician_id uuid,
  p_expected_version integer,
  p_active boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_before public.workshop_technicians%rowtype;
  v_after public.workshop_technicians%rowtype;
begin
  perform public.require_pdc_role('administrator');

  select * into v_before from public.workshop_technicians where id = p_technician_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if v_before.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'version_conflict', 'current', to_jsonb(v_before));
  end if;
  if v_before.active = p_active then
    return jsonb_build_object('ok', true, 'technician', to_jsonb(v_before), 'unchanged', true);
  end if;

  -- Deactivation must never disconnect historical references: no FK
  -- from workshop_booking_assignments/workshop_bookings is dropped or
  -- nulled here -- the row simply stops being returned by
  -- list_technicians(false) and stops being offered for NEW
  -- assignments, while every historical row that already points at
  -- this technician_id keeps pointing at the same real row, name and
  -- all, exactly as it did at the time of assignment.
  update public.workshop_technicians
  set active = p_active,
      version = version + 1,
      updated_by = auth.uid(),
      updated_at = now()
  where id = p_technician_id
  returning * into v_after;

  perform public.audit_pdc_event('reference_change', 'workshop_technicians', v_after.id, null, to_jsonb(v_before), to_jsonb(v_after),
    jsonb_build_object('action', case when p_active then 'activate_technician' else 'deactivate_technician' end));

  return jsonb_build_object('ok', true, 'technician', to_jsonb(v_after));
end;
$$;

-- =====================================================================
-- Salespeople
-- =====================================================================

create or replace function public.list_salespeople(p_include_inactive boolean default false)
returns setof public.salespeople
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_pdc_role('viewer');
  if p_include_inactive then
    return query select * from public.salespeople order by sort_order, name;
  else
    return query select * from public.salespeople where active order by sort_order, name;
  end if;
end;
$$;

create or replace function public.add_salesperson(
  p_name text,
  p_email text default null,
  p_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
  v_email text;
  v_code text;
  v_row public.salespeople%rowtype;
  v_next_sort integer;
begin
  perform public.require_pdc_role('administrator');

  v_name := trim(coalesce(p_name, ''));
  if v_name = '' then
    return jsonb_build_object('ok', false, 'error', 'name_required');
  end if;

  v_email := lower(nullif(trim(coalesce(p_email, '')), ''));
  if v_email is not null and v_email not like '%@%' then
    return jsonb_build_object('ok', false, 'error', 'invalid_email');
  end if;

  v_code := nullif(upper(trim(coalesce(p_code, ''))), '');

  if exists (select 1 from public.salespeople where lower(name) = lower(v_name)) then
    return jsonb_build_object('ok', false, 'error', 'duplicate_name');
  end if;
  if v_code is not null and exists (select 1 from public.salespeople where upper(code) = v_code) then
    return jsonb_build_object('ok', false, 'error', 'duplicate_code');
  end if;

  select coalesce(max(sort_order), 0) + 1 into v_next_sort from public.salespeople;

  insert into public.salespeople (name, email, code, sort_order, created_by, updated_by)
  values (v_name, v_email, v_code, v_next_sort, auth.uid(), auth.uid())
  returning * into v_row;

  perform public.audit_pdc_event('reference_change', 'salespeople', v_row.id, null, null, to_jsonb(v_row),
    jsonb_build_object('action', 'add_salesperson'));

  return jsonb_build_object('ok', true, 'salesperson', to_jsonb(v_row));
end;
$$;

create or replace function public.edit_salesperson(
  p_salesperson_id uuid,
  p_expected_version integer,
  p_name text default null,
  p_email text default null,
  p_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_before public.salespeople%rowtype;
  v_after public.salespeople%rowtype;
  v_name text;
  v_email text;
  v_code text;
begin
  perform public.require_pdc_role('administrator');

  select * into v_before from public.salespeople where id = p_salesperson_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if v_before.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'version_conflict', 'current', to_jsonb(v_before));
  end if;

  v_name := case when p_name is not null then trim(p_name) else v_before.name end;
  if v_name = '' then
    return jsonb_build_object('ok', false, 'error', 'name_required');
  end if;
  if p_name is not null and lower(v_name) <> lower(v_before.name)
     and exists (select 1 from public.salespeople where lower(name) = lower(v_name) and id <> p_salesperson_id) then
    return jsonb_build_object('ok', false, 'error', 'duplicate_name');
  end if;

  v_email := case when p_email is not null then lower(nullif(trim(p_email), '')) else v_before.email end;
  if v_email is not null and v_email not like '%@%' then
    return jsonb_build_object('ok', false, 'error', 'invalid_email');
  end if;

  v_code := case when p_code is not null then nullif(upper(trim(p_code)), '') else v_before.code end;
  if p_code is not null and coalesce(v_code,'') <> coalesce(v_before.code,'')
     and v_code is not null and exists (select 1 from public.salespeople where upper(code) = v_code and id <> p_salesperson_id) then
    return jsonb_build_object('ok', false, 'error', 'duplicate_code');
  end if;

  update public.salespeople
  set name = v_name,
      email = v_email,
      code = v_code,
      version = version + 1,
      updated_by = auth.uid(),
      updated_at = now()
  where id = p_salesperson_id
  returning * into v_after;

  perform public.audit_pdc_event('reference_change', 'salespeople', v_after.id, null, to_jsonb(v_before), to_jsonb(v_after),
    jsonb_build_object('action', 'edit_salesperson'));

  return jsonb_build_object('ok', true, 'salesperson', to_jsonb(v_after));
end;
$$;

create or replace function public.set_salesperson_active(
  p_salesperson_id uuid,
  p_expected_version integer,
  p_active boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_before public.salespeople%rowtype;
  v_after public.salespeople%rowtype;
begin
  perform public.require_pdc_role('administrator');

  select * into v_before from public.salespeople where id = p_salesperson_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if v_before.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'version_conflict', 'current', to_jsonb(v_before));
  end if;
  if v_before.active = p_active then
    return jsonb_build_object('ok', true, 'salesperson', to_jsonb(v_before), 'unchanged', true);
  end if;

  -- Deactivation never disconnects vehicles.salesperson_id -- the FK
  -- is preserved; the row simply stops appearing in
  -- list_salespeople(false).
  update public.salespeople
  set active = p_active,
      version = version + 1,
      updated_by = auth.uid(),
      updated_at = now()
  where id = p_salesperson_id
  returning * into v_after;

  perform public.audit_pdc_event('reference_change', 'salespeople', v_after.id, null, to_jsonb(v_before), to_jsonb(v_after),
    jsonb_build_object('action', case when p_active then 'activate_salesperson' else 'deactivate_salesperson' end));

  return jsonb_build_object('ok', true, 'salesperson', to_jsonb(v_after));
end;
$$;

-- =====================================================================
-- Sublet providers
-- =====================================================================

create or replace function public.list_sublet_providers(p_include_inactive boolean default false)
returns setof public.sublet_providers
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_pdc_role('viewer');
  if p_include_inactive then
    return query select * from public.sublet_providers order by sort_order, name;
  else
    return query select * from public.sublet_providers where active order by sort_order, name;
  end if;
end;
$$;

create or replace function public.add_sublet_provider(
  p_name text,
  p_email text default null,
  p_phone text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
  v_email text;
  v_row public.sublet_providers%rowtype;
  v_next_sort integer;
begin
  perform public.require_pdc_role('administrator');

  v_name := trim(coalesce(p_name, ''));
  if v_name = '' then
    return jsonb_build_object('ok', false, 'error', 'name_required');
  end if;

  v_email := lower(nullif(trim(coalesce(p_email, '')), ''));
  if v_email is not null and v_email not like '%@%' then
    return jsonb_build_object('ok', false, 'error', 'invalid_email');
  end if;

  if exists (select 1 from public.sublet_providers where lower(name) = lower(v_name)) then
    return jsonb_build_object('ok', false, 'error', 'duplicate_name');
  end if;

  select coalesce(max(sort_order), 0) + 1 into v_next_sort from public.sublet_providers;

  insert into public.sublet_providers (name, email, phone, sort_order, created_by, updated_by)
  values (v_name, v_email, nullif(trim(coalesce(p_phone, '')), ''), v_next_sort, auth.uid(), auth.uid())
  returning * into v_row;

  perform public.audit_pdc_event('reference_change', 'sublet_providers', v_row.id, null, null, to_jsonb(v_row),
    jsonb_build_object('action', 'add_sublet_provider'));

  return jsonb_build_object('ok', true, 'provider', to_jsonb(v_row));
end;
$$;

create or replace function public.edit_sublet_provider(
  p_provider_id uuid,
  p_expected_version integer,
  p_name text default null,
  p_email text default null,
  p_phone text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_before public.sublet_providers%rowtype;
  v_after public.sublet_providers%rowtype;
  v_name text;
  v_email text;
begin
  perform public.require_pdc_role('administrator');

  select * into v_before from public.sublet_providers where id = p_provider_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if v_before.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'version_conflict', 'current', to_jsonb(v_before));
  end if;

  v_name := case when p_name is not null then trim(p_name) else v_before.name end;
  if v_name = '' then
    return jsonb_build_object('ok', false, 'error', 'name_required');
  end if;
  if p_name is not null and lower(v_name) <> lower(v_before.name)
     and exists (select 1 from public.sublet_providers where lower(name) = lower(v_name) and id <> p_provider_id) then
    return jsonb_build_object('ok', false, 'error', 'duplicate_name');
  end if;

  v_email := case when p_email is not null then lower(nullif(trim(p_email), '')) else v_before.email end;
  if v_email is not null and v_email not like '%@%' then
    return jsonb_build_object('ok', false, 'error', 'invalid_email');
  end if;

  update public.sublet_providers
  set name = v_name,
      email = v_email,
      phone = case when p_phone is not null then nullif(trim(p_phone), '') else phone end,
      version = version + 1,
      updated_by = auth.uid(),
      updated_at = now()
  where id = p_provider_id
  returning * into v_after;

  perform public.audit_pdc_event('reference_change', 'sublet_providers', v_after.id, null, to_jsonb(v_before), to_jsonb(v_after),
    jsonb_build_object('action', 'edit_sublet_provider'));

  return jsonb_build_object('ok', true, 'provider', to_jsonb(v_after));
end;
$$;

create or replace function public.set_sublet_provider_active(
  p_provider_id uuid,
  p_expected_version integer,
  p_active boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_before public.sublet_providers%rowtype;
  v_after public.sublet_providers%rowtype;
begin
  perform public.require_pdc_role('administrator');

  select * into v_before from public.sublet_providers where id = p_provider_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if v_before.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'version_conflict', 'current', to_jsonb(v_before));
  end if;
  if v_before.active = p_active then
    return jsonb_build_object('ok', true, 'provider', to_jsonb(v_before), 'unchanged', true);
  end if;

  update public.sublet_providers
  set active = p_active,
      version = version + 1,
      updated_by = auth.uid(),
      updated_at = now()
  where id = p_provider_id
  returning * into v_after;

  perform public.audit_pdc_event('reference_change', 'sublet_providers', v_after.id, null, to_jsonb(v_before), to_jsonb(v_after),
    jsonb_build_object('action', case when p_active then 'activate_sublet_provider' else 'deactivate_sublet_provider' end));

  return jsonb_build_object('ok', true, 'provider', to_jsonb(v_after));
end;
$$;

-- =====================================================================
-- Workshop bays
-- =====================================================================

create or replace function public.list_workshop_bays(p_include_inactive boolean default false)
returns setof public.workshop_bays
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_pdc_role('viewer');
  if p_include_inactive then
    return query select * from public.workshop_bays order by stage_id, bay_number;
  else
    return query select * from public.workshop_bays where is_active order by stage_id, bay_number;
  end if;
end;
$$;

create or replace function public.set_workshop_bay_active(
  p_bay_id uuid,
  p_expected_version integer,
  p_active boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_before public.workshop_bays%rowtype;
  v_after public.workshop_bays%rowtype;
begin
  -- Deactivating/reactivating an existing bay is permitted;
  -- creating/deleting a physical bay is intentionally NOT exposed
  -- here (bays correspond to real physical workshop space, unlike
  -- mechanics/salespeople/providers -- adding or removing one is a
  -- facilities decision out of scope for Stage 2A per the task's own
  -- "add/edit/deactivate bay where permitted" wording, which this
  -- migration reads as "activation state only" until a real business
  -- need for creating new bays via the UI is confirmed).
  perform public.require_pdc_role('administrator');

  select * into v_before from public.workshop_bays where id = p_bay_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if v_before.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'version_conflict', 'current', to_jsonb(v_before));
  end if;
  if v_before.is_active = p_active then
    return jsonb_build_object('ok', true, 'bay', to_jsonb(v_before), 'unchanged', true);
  end if;

  update public.workshop_bays
  set is_active = p_active,
      version = version + 1,
      updated_by = auth.uid(),
      updated_at = now()
  where id = p_bay_id
  returning * into v_after;

  perform public.audit_pdc_event('reference_change', 'workshop_bays', v_after.id, null, to_jsonb(v_before), to_jsonb(v_after),
    jsonb_build_object('action', case when p_active then 'activate_workshop_bay' else 'deactivate_workshop_bay' end));

  return jsonb_build_object('ok', true, 'bay', to_jsonb(v_after));
end;
$$;

create or replace function public.set_bay_default_technician(
  p_bay_id uuid,
  p_expected_version integer,
  p_technician_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_before public.workshop_bays%rowtype;
  v_after public.workshop_bays%rowtype;
begin
  perform public.require_pdc_role('administrator');

  if p_technician_id is not null and not exists (select 1 from public.workshop_technicians where id = p_technician_id) then
    return jsonb_build_object('ok', false, 'error', 'technician_not_found');
  end if;

  select * into v_before from public.workshop_bays where id = p_bay_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if v_before.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'version_conflict', 'current', to_jsonb(v_before));
  end if;

  update public.workshop_bays
  set default_technician_id = p_technician_id,
      version = version + 1,
      updated_by = auth.uid(),
      updated_at = now()
  where id = p_bay_id
  returning * into v_after;

  perform public.audit_pdc_event('reference_change', 'workshop_bays', v_after.id, null, to_jsonb(v_before), to_jsonb(v_after),
    jsonb_build_object('action', 'set_bay_default_technician'));

  return jsonb_build_object('ok', true, 'bay', to_jsonb(v_after));
end;
$$;

-- =====================================================================
-- Workshop configuration (operating hours/days, minimum booking
-- duration, closures) -- reads/writes the existing
-- public.workshop_settings entity-attribute-value rows.
-- =====================================================================

create or replace function public.get_workshop_configuration()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  perform public.require_pdc_role('viewer');
  select jsonb_object_agg(key, jsonb_build_object('value', value, 'version', version, 'updated_at', updated_at))
  into v_result
  from public.workshop_settings;
  return coalesce(v_result, '{}'::jsonb);
end;
$$;

-- Fixed, known set of configuration keys that may ever be written --
-- an unknown key is rejected outright, never silently created. This
-- is the deliberate alternative to a generic "write any settings key"
-- RPC.
create or replace function public.update_workshop_configuration(
  p_key text,
  p_expected_version integer,
  p_value jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_before public.workshop_settings%rowtype;
  v_after public.workshop_settings%rowtype;
  v_allowed_keys text[] := array[
    'day_start_time', 'day_end_time', 'scheduling_increment_minutes',
    'default_booking_duration_minutes', 'working_week', 'closures',
    'break_windows', 'overtime_windows', 'technician_leave'
  ];
begin
  perform public.require_pdc_role('administrator');

  if p_key is null or not (p_key = any(v_allowed_keys)) then
    return jsonb_build_object('ok', false, 'error', 'unknown_setting_key', 'allowed_keys', to_jsonb(v_allowed_keys));
  end if;

  -- Minimal per-key shape validation -- rejects an obviously wrong
  -- value type rather than accepting any JSON for any key.
  if p_key in ('day_start_time', 'day_end_time') and jsonb_typeof(p_value) <> 'string' then
    return jsonb_build_object('ok', false, 'error', 'invalid_value_shape', 'expected', 'string (HH:MM)');
  end if;
  if p_key in ('scheduling_increment_minutes', 'default_booking_duration_minutes') and jsonb_typeof(p_value) <> 'number' then
    return jsonb_build_object('ok', false, 'error', 'invalid_value_shape', 'expected', 'number (minutes)');
  end if;
  if p_key in ('working_week', 'closures', 'break_windows', 'overtime_windows', 'technician_leave') and jsonb_typeof(p_value) <> 'array' then
    return jsonb_build_object('ok', false, 'error', 'invalid_value_shape', 'expected', 'array');
  end if;

  select * into v_before from public.workshop_settings where key = p_key for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if v_before.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'version_conflict', 'current', to_jsonb(v_before));
  end if;

  update public.workshop_settings
  set value = p_value,
      version = version + 1,
      updated_by = auth.uid(),
      updated_at = now()
  where key = p_key
  returning * into v_after;

  perform public.audit_pdc_event('reference_change', 'workshop_settings', v_after.id, null, to_jsonb(v_before), to_jsonb(v_after),
    jsonb_build_object('action', 'update_workshop_configuration', 'key', p_key));

  return jsonb_build_object('ok', true, 'setting', to_jsonb(v_after));
end;
$$;

-- =====================================================================
-- Execute grants. Every function above is SECURITY DEFINER and
-- already enforces its own role check internally via
-- require_pdc_role() -- but per this project's Stage 6/Stage 7
-- remediation convention, execute is still explicitly limited to
-- 'authenticated' (never 'anon' or 'public') as defence in depth, and
-- direct table writes remain fully revoked for every table these
-- functions touch (confirmed in migration 022 / earlier migration
-- 021 for salespeople/sublet_providers).
-- =====================================================================

revoke all on function public.list_technicians(boolean) from public;
revoke all on function public.add_technician(text, text, text, text[]) from public;
revoke all on function public.edit_technician(uuid, integer, text, text, text, text[]) from public;
revoke all on function public.set_technician_active(uuid, integer, boolean) from public;
revoke all on function public.list_salespeople(boolean) from public;
revoke all on function public.add_salesperson(text, text, text) from public;
revoke all on function public.edit_salesperson(uuid, integer, text, text, text) from public;
revoke all on function public.set_salesperson_active(uuid, integer, boolean) from public;
revoke all on function public.list_sublet_providers(boolean) from public;
revoke all on function public.add_sublet_provider(text, text, text) from public;
revoke all on function public.edit_sublet_provider(uuid, integer, text, text, text) from public;
revoke all on function public.set_sublet_provider_active(uuid, integer, boolean) from public;
revoke all on function public.list_workshop_bays(boolean) from public;
revoke all on function public.set_workshop_bay_active(uuid, integer, boolean) from public;
revoke all on function public.set_bay_default_technician(uuid, integer, uuid) from public;
revoke all on function public.get_workshop_configuration() from public;
revoke all on function public.update_workshop_configuration(text, integer, jsonb) from public;

grant execute on function public.list_technicians(boolean) to authenticated;
grant execute on function public.add_technician(text, text, text, text[]) to authenticated;
grant execute on function public.edit_technician(uuid, integer, text, text, text, text[]) to authenticated;
grant execute on function public.set_technician_active(uuid, integer, boolean) to authenticated;
grant execute on function public.list_salespeople(boolean) to authenticated;
grant execute on function public.add_salesperson(text, text, text) to authenticated;
grant execute on function public.edit_salesperson(uuid, integer, text, text, text) to authenticated;
grant execute on function public.set_salesperson_active(uuid, integer, boolean) to authenticated;
grant execute on function public.list_sublet_providers(boolean) to authenticated;
grant execute on function public.add_sublet_provider(text, text, text) to authenticated;
grant execute on function public.edit_sublet_provider(uuid, integer, text, text, text) to authenticated;
grant execute on function public.set_sublet_provider_active(uuid, integer, boolean) to authenticated;
grant execute on function public.list_workshop_bays(boolean) to authenticated;
grant execute on function public.set_workshop_bay_active(uuid, integer, boolean) to authenticated;
grant execute on function public.set_bay_default_technician(uuid, integer, uuid) to authenticated;
grant execute on function public.get_workshop_configuration() to authenticated;
grant execute on function public.update_workshop_configuration(text, integer, jsonb) to authenticated;
