-- Migration 025: Stage 2A independent-review remediation -- grants,
-- RLS, inactive-technician-as-default handling, workshop-settings
-- validation hardening, and case-insensitive uniqueness.
--
-- Addresses findings 4, 9, 10, 11, 12, 13 from
-- PDC-Stage-2A-Independent-Review-Report.md.

-- =====================================================================
-- Finding 9: anon EXECUTE on every Stage 2A RPC (live grants snapshot
-- showed anon has EXECUTE despite migration 023's `revoke all ...
-- from public`; PostgREST/Supabase's default schema-level grant to
-- anon is a separate grant that a `from public` revoke does not
-- touch). Explicitly revoke from both public and anon on every
-- Stage 2A RPC, matching the pattern already used elsewhere in this
-- project (Stage 6/7 privilege hardening).
-- =====================================================================
revoke all on function public.list_technicians(boolean) from public, anon;
revoke all on function public.add_technician(text, text, text, text[]) from public, anon;
revoke all on function public.edit_technician(uuid, integer, text, text, text, text[]) from public, anon;
revoke all on function public.set_technician_active(uuid, integer, boolean) from public, anon;
revoke all on function public.list_salespeople(boolean) from public, anon;
revoke all on function public.add_salesperson(text, text, text) from public, anon;
revoke all on function public.edit_salesperson(uuid, integer, text, text, text) from public, anon;
revoke all on function public.set_salesperson_active(uuid, integer, boolean) from public, anon;
revoke all on function public.list_sublet_providers(boolean) from public, anon;
revoke all on function public.add_sublet_provider(text, text, text) from public, anon;
revoke all on function public.edit_sublet_provider(uuid, integer, text, text, text) from public, anon;
revoke all on function public.set_sublet_provider_active(uuid, integer, boolean) from public, anon;
revoke all on function public.list_workshop_bays(boolean) from public, anon;
revoke all on function public.set_workshop_bay_active(uuid, integer, boolean) from public, anon;
revoke all on function public.set_bay_default_technician(uuid, integer, uuid) from public, anon;
revoke all on function public.get_workshop_configuration() from public, anon;
revoke all on function public.update_workshop_configuration(text, integer, jsonb) from public, anon;

-- Re-grant to authenticated only (this is idempotent -- it was
-- already granted by migration 023, this just re-confirms it after
-- the explicit anon revoke above so the net effect is unambiguous).
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

-- =====================================================================
-- Finding 10: dormant direct-write RLS policies (salespeople_admin_write,
-- sublet_providers_admin_write) remain even though direct table write
-- grants were revoked in migration 022. Drop them so a future
-- accidental table grant cannot silently reactivate direct writes.
-- =====================================================================
drop policy if exists salespeople_admin_write on public.salespeople;
drop policy if exists sublet_providers_admin_write on public.sublet_providers;

-- =====================================================================
-- Finding 11: every list RPC allowed a 'viewer' to pass
-- p_include_inactive = true and receive inactive rows -- the approved
-- Stage 2A brief said viewers should see active permitted lookup data
-- only, while operator ("controller")/administrator may see inactive
-- records. Enforce this INSIDE the RPC (the actual data gate), not
-- only by relying on the frontend never passing true for a viewer.
-- =====================================================================
create or replace function public.list_technicians(p_include_inactive boolean default false)
returns setof public.workshop_technicians
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_pdc_role('viewer');
  if p_include_inactive and not public.is_pdc_role('operator') then
    p_include_inactive := false;
  end if;
  if p_include_inactive then
    return query select * from public.workshop_technicians order by sort_order, name;
  else
    return query select * from public.workshop_technicians where active order by sort_order, name;
  end if;
end;
$$;

create or replace function public.list_salespeople(p_include_inactive boolean default false)
returns setof public.salespeople
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_pdc_role('viewer');
  if p_include_inactive and not public.is_pdc_role('operator') then
    p_include_inactive := false;
  end if;
  if p_include_inactive then
    return query select * from public.salespeople order by sort_order, name;
  else
    return query select * from public.salespeople where active order by sort_order, name;
  end if;
end;
$$;

create or replace function public.list_sublet_providers(p_include_inactive boolean default false)
returns setof public.sublet_providers
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_pdc_role('viewer');
  if p_include_inactive and not public.is_pdc_role('operator') then
    p_include_inactive := false;
  end if;
  if p_include_inactive then
    return query select * from public.sublet_providers order by sort_order, name;
  else
    return query select * from public.sublet_providers where active order by sort_order, name;
  end if;
end;
$$;

create or replace function public.list_workshop_bays(p_include_inactive boolean default false)
returns setof public.workshop_bays
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_pdc_role('viewer');
  if p_include_inactive and not public.is_pdc_role('operator') then
    p_include_inactive := false;
  end if;
  if p_include_inactive then
    return query select * from public.workshop_bays order by bay_number;
  else
    return query select * from public.workshop_bays where is_active order by bay_number;
  end if;
end;
$$;

grant execute on function public.list_technicians(boolean) to authenticated;
grant execute on function public.list_salespeople(boolean) to authenticated;
grant execute on function public.list_sublet_providers(boolean) to authenticated;
grant execute on function public.list_workshop_bays(boolean) to authenticated;

-- =====================================================================
-- Finding 13: case-insensitive duplicate prevention was checked in
-- the RPC (`exists(lower(name) = lower(...))`) but not backed by a
-- database-level case-insensitive unique constraint, so two
-- concurrent requests can both pass the existence check and both
-- insert. Add functional unique indexes on lower(name)/lower(code)
-- so the database is the final authority, and the RPCs below catch
-- unique_violation and return a structured duplicate error instead of
-- a raw exception.
-- =====================================================================
create unique index if not exists workshop_technicians_name_ci_key on public.workshop_technicians (lower(name));
create unique index if not exists workshop_technicians_code_ci_key on public.workshop_technicians (lower(code)) where code is not null;
create unique index if not exists salespeople_name_ci_key on public.salespeople (lower(name));
create unique index if not exists salespeople_code_ci_key on public.salespeople (lower(code)) where code is not null;
create unique index if not exists salespeople_email_ci_key on public.salespeople (lower(email)) where email is not null;
create unique index if not exists sublet_providers_name_ci_key on public.sublet_providers (lower(name));

-- The pre-existing case-SENSITIVE unique indexes/constraints added in
-- earlier migrations (workshop_technicians_name_key,
-- workshop_technicians_code_key, salespeople_name_key,
-- salespeople_code_key, sublet_providers_name_key) are now redundant
-- given the case-insensitive indexes above are strictly stronger, but
-- are left in place -- dropping a pre-existing unique constraint is a
-- higher-risk change than adding a new one, and the case-sensitive
-- indexes cause no harm (they can never trigger before the
-- case-insensitive ones do, since exact-case equality implies
-- lower-case equality).

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
  v_row public.workshop_technicians%rowtype;
  v_sort_order integer;
begin
  perform public.require_pdc_role('administrator');
  if p_name is null or btrim(p_name) = '' then
    return jsonb_build_object('ok', false, 'error', 'name_required');
  end if;

  select coalesce(max(sort_order), 0) + 1 into v_sort_order from public.workshop_technicians;

  begin
    insert into public.workshop_technicians (name, code, role_type, can_fit_stages, sort_order, created_by, updated_by)
    values (btrim(p_name), p_code, coalesce(p_role_type, 'technician'), coalesce(p_can_fit_stages, '{}'::text[]), v_sort_order, auth.uid(), auth.uid())
    returning * into v_row;
  exception when unique_violation then
    return jsonb_build_object('ok', false, 'error', 'duplicate_name');
  end;

  perform public.audit_pdc_event('reference_change', 'workshop_technicians', v_row.id, null, null, to_jsonb(v_row),
    jsonb_build_object('action', 'add_technician'));

  return jsonb_build_object('ok', true, 'technician', to_jsonb(v_row));
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
  v_row public.salespeople%rowtype;
  v_sort_order integer;
begin
  perform public.require_pdc_role('administrator');
  if p_name is null or btrim(p_name) = '' then
    return jsonb_build_object('ok', false, 'error', 'name_required');
  end if;

  select coalesce(max(sort_order), 0) + 1 into v_sort_order from public.salespeople;

  begin
    insert into public.salespeople (name, code, email, sort_order, created_by, updated_by)
    values (btrim(p_name), p_code, p_email, v_sort_order, auth.uid(), auth.uid())
    returning * into v_row;
  exception when unique_violation then
    return jsonb_build_object('ok', false, 'error', 'duplicate_name');
  end;

  perform public.audit_pdc_event('reference_change', 'salespeople', v_row.id, null, null, to_jsonb(v_row),
    jsonb_build_object('action', 'add_salesperson'));

  return jsonb_build_object('ok', true, 'salesperson', to_jsonb(v_row));
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
  v_row public.sublet_providers%rowtype;
  v_sort_order integer;
begin
  perform public.require_pdc_role('administrator');
  if p_name is null or btrim(p_name) = '' then
    return jsonb_build_object('ok', false, 'error', 'name_required');
  end if;

  select coalesce(max(sort_order), 0) + 1 into v_sort_order from public.sublet_providers;

  begin
    insert into public.sublet_providers (name, email, phone, sort_order, created_by, updated_by)
    values (btrim(p_name), p_email, p_phone, v_sort_order, auth.uid(), auth.uid())
    returning * into v_row;
  exception when unique_violation then
    return jsonb_build_object('ok', false, 'error', 'duplicate_name');
  end;

  perform public.audit_pdc_event('reference_change', 'sublet_providers', v_row.id, null, null, to_jsonb(v_row),
    jsonb_build_object('action', 'add_sublet_provider'));

  return jsonb_build_object('ok', true, 'provider', to_jsonb(v_row));
end;
$$;

grant execute on function public.add_technician(text, text, text, text[]) to authenticated;
grant execute on function public.add_salesperson(text, text, text) to authenticated;
grant execute on function public.add_sublet_provider(text, text, text) to authenticated;

-- =====================================================================
-- Finding 4: an inactive technician could remain (and be re-selected
-- as) a bay default. Policy chosen (documented per the review's
-- required either/or): B -- atomically clear the default on every bay
-- that referenced this technician as its default when the technician
-- is deactivated, and audit each affected bay. This was chosen over
-- policy A (block deactivation while used as a default) because
-- technician deactivation is a personnel event that must always be
-- able to proceed (e.g. someone leaves), and a bay simply reverting to
-- "no default" is a safe, low-friction consequence -- whereas blocking
-- deactivation would force an administrator to first hunt down and
-- clear every bay default before they could deactivate a technician
-- who has left, which is a worse operational outcome for a routine
-- HR event.
-- =====================================================================
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
  v_bay record;
  v_cleared_bays jsonb := '[]'::jsonb;
begin
  perform public.require_pdc_role('administrator');

  select * into v_before from public.workshop_technicians where id = p_technician_id for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  if v_before.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'version_conflict', 'current', to_jsonb(v_before));
  end if;

  update public.workshop_technicians
  set active = p_active,
      version = version + 1,
      updated_by = auth.uid(),
      updated_at = now()
  where id = p_technician_id
  returning * into v_after;

  -- Deactivation: atomically clear this technician as the default on
  -- every bay that currently references them, auditing each bay
  -- individually so the change is fully traceable.
  if v_before.active and not p_active then
    for v_bay in
      select * from public.workshop_bays where default_technician_id = p_technician_id for update
    loop
      update public.workshop_bays
      set default_technician_id = null,
          version = version + 1,
          updated_by = auth.uid(),
          updated_at = now()
      where id = v_bay.id;

      perform public.audit_pdc_event('reference_change', 'workshop_bays', v_bay.id, null, to_jsonb(v_bay),
        jsonb_build_object('id', v_bay.id, 'default_technician_id', null, 'version', v_bay.version + 1),
        jsonb_build_object('action', 'clear_bay_default_technician_on_deactivation', 'technician_id', p_technician_id));

      v_cleared_bays := v_cleared_bays || jsonb_build_object('bay_id', v_bay.id, 'code', v_bay.code);
    end loop;
  end if;

  perform public.audit_pdc_event('reference_change', 'workshop_technicians', v_after.id, null, to_jsonb(v_before), to_jsonb(v_after),
    jsonb_build_object('action', 'set_technician_active'));

  return jsonb_build_object('ok', true, 'technician', to_jsonb(v_after), 'cleared_bay_defaults', v_cleared_bays);
end;
$$;

grant execute on function public.set_technician_active(uuid, integer, boolean) to authenticated;

-- set_bay_default_technician must also reject setting an INACTIVE
-- technician as a new default (the review's "also" requirement).
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
  v_technician public.workshop_technicians%rowtype;
begin
  perform public.require_pdc_role('administrator');

  if p_technician_id is not null then
    select * into v_technician from public.workshop_technicians where id = p_technician_id;
    if not found then
      return jsonb_build_object('ok', false, 'error', 'technician_not_found');
    end if;
    if not v_technician.active then
      return jsonb_build_object('ok', false, 'error', 'technician_inactive');
    end if;
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

grant execute on function public.set_bay_default_technician(uuid, integer, uuid) to authenticated;
revoke all on function public.set_bay_default_technician(uuid, integer, uuid) from public, anon;

-- =====================================================================
-- Finding 12: workshop-setting validation was too weak (only checked
-- JSON type, not real shape/range/relational constraints -- accepted
-- "banana" for a time, negative durations, malformed arrays, etc).
-- Add strict per-key validation with structured error codes.
-- =====================================================================
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
  v_allowed_days text[] := array['monday','tuesday','wednesday','thursday','friday','saturday','sunday'];
  v_elem jsonb;
  v_seen text[] := array[]::text[];
  v_day text;
  v_start_minutes integer;
  v_end_minutes integer;
begin
  perform public.require_pdc_role('administrator');

  if p_key is null or not (p_key = any(v_allowed_keys)) then
    return jsonb_build_object('ok', false, 'error', 'unknown_setting_key', 'allowed_keys', to_jsonb(v_allowed_keys));
  end if;

  -- HH:MM string validation (day_start_time / day_end_time), and
  -- start-before-end cross-check against the OTHER stored time value.
  if p_key in ('day_start_time', 'day_end_time') then
    if jsonb_typeof(p_value) <> 'string' then
      return jsonb_build_object('ok', false, 'error', 'invalid_value_shape', 'expected', 'string (HH:MM)');
    end if;
    if not (trim(both '"' from p_value::text) ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$') then
      return jsonb_build_object('ok', false, 'error', 'invalid_time_format', 'expected', 'HH:MM 24-hour, 00:00-23:59');
    end if;
    v_start_minutes := case when p_key = 'day_start_time'
      then (split_part(trim(both '"' from p_value::text), ':', 1)::integer * 60 + split_part(trim(both '"' from p_value::text), ':', 2)::integer)
      else (select (split_part(trim(both '"' from value::text), ':', 1)::integer * 60 + split_part(trim(both '"' from value::text), ':', 2)::integer) from public.workshop_settings where key = 'day_start_time')
    end;
    v_end_minutes := case when p_key = 'day_end_time'
      then (split_part(trim(both '"' from p_value::text), ':', 1)::integer * 60 + split_part(trim(both '"' from p_value::text), ':', 2)::integer)
      else (select (split_part(trim(both '"' from value::text), ':', 1)::integer * 60 + split_part(trim(both '"' from value::text), ':', 2)::integer) from public.workshop_settings where key = 'day_end_time')
    end;
    if v_start_minutes is not null and v_end_minutes is not null and v_start_minutes >= v_end_minutes then
      return jsonb_build_object('ok', false, 'error', 'start_time_not_before_end_time', 'day_start_time', v_start_minutes, 'day_end_time', v_end_minutes);
    end if;
  end if;

  -- Positive, bounded integer minutes (scheduling_increment_minutes,
  -- default_booking_duration_minutes).
  if p_key in ('scheduling_increment_minutes', 'default_booking_duration_minutes') then
    if jsonb_typeof(p_value) <> 'number' then
      return jsonb_build_object('ok', false, 'error', 'invalid_value_shape', 'expected', 'number (minutes)');
    end if;
    if (p_value::text)::numeric <> floor((p_value::text)::numeric) then
      return jsonb_build_object('ok', false, 'error', 'invalid_value', 'reason', 'must_be_integer');
    end if;
    if (p_value::text)::integer <= 0 then
      return jsonb_build_object('ok', false, 'error', 'invalid_value', 'reason', 'must_be_positive');
    end if;
    if p_key = 'scheduling_increment_minutes' and (p_value::text)::integer > 240 then
      return jsonb_build_object('ok', false, 'error', 'invalid_value', 'reason', 'exceeds_max_240_minutes');
    end if;
    if p_key = 'default_booking_duration_minutes' and (p_value::text)::integer > 1440 then
      return jsonb_build_object('ok', false, 'error', 'invalid_value', 'reason', 'exceeds_max_1440_minutes');
    end if;
  end if;

  -- working_week: array of allowed day names, no duplicates, at least
  -- one day.
  if p_key = 'working_week' then
    if jsonb_typeof(p_value) <> 'array' then
      return jsonb_build_object('ok', false, 'error', 'invalid_value_shape', 'expected', 'array');
    end if;
    if jsonb_array_length(p_value) = 0 then
      return jsonb_build_object('ok', false, 'error', 'invalid_value', 'reason', 'must_have_at_least_one_day');
    end if;
    for v_elem in select * from jsonb_array_elements(p_value)
    loop
      if jsonb_typeof(v_elem) <> 'string' then
        return jsonb_build_object('ok', false, 'error', 'invalid_value', 'reason', 'day_must_be_string');
      end if;
      v_day := lower(trim(both '"' from v_elem::text));
      if not (v_day = any(v_allowed_days)) then
        return jsonb_build_object('ok', false, 'error', 'invalid_value', 'reason', 'unknown_day_name', 'value', v_day, 'allowed', to_jsonb(v_allowed_days));
      end if;
      if v_day = any(v_seen) then
        return jsonb_build_object('ok', false, 'error', 'invalid_value', 'reason', 'duplicate_day', 'value', v_day);
      end if;
      v_seen := v_seen || v_day;
    end loop;
  end if;

  -- closures: array of objects, each must have a valid 'date' field
  -- (ISO date), rejects malformed entries.
  if p_key = 'closures' then
    if jsonb_typeof(p_value) <> 'array' then
      return jsonb_build_object('ok', false, 'error', 'invalid_value_shape', 'expected', 'array');
    end if;
    for v_elem in select * from jsonb_array_elements(p_value)
    loop
      if jsonb_typeof(v_elem) <> 'object' then
        return jsonb_build_object('ok', false, 'error', 'invalid_value', 'reason', 'closure_must_be_object');
      end if;
      if not (v_elem ? 'date') or jsonb_typeof(v_elem->'date') <> 'string' then
        return jsonb_build_object('ok', false, 'error', 'invalid_value', 'reason', 'closure_missing_date');
      end if;
      begin
        perform (trim(both '"' from (v_elem->'date')::text))::date;
      exception when others then
        return jsonb_build_object('ok', false, 'error', 'invalid_value', 'reason', 'closure_date_not_valid_iso_date', 'value', v_elem->'date');
      end;
    end loop;
  end if;

  -- break_windows / overtime_windows: array of objects, each must
  -- have valid HH:MM 'start' and 'end' with start < end.
  if p_key in ('break_windows', 'overtime_windows') then
    if jsonb_typeof(p_value) <> 'array' then
      return jsonb_build_object('ok', false, 'error', 'invalid_value_shape', 'expected', 'array');
    end if;
    for v_elem in select * from jsonb_array_elements(p_value)
    loop
      if jsonb_typeof(v_elem) <> 'object'
         or not (v_elem ? 'start') or jsonb_typeof(v_elem->'start') <> 'string'
         or not (v_elem ? 'end') or jsonb_typeof(v_elem->'end') <> 'string' then
        return jsonb_build_object('ok', false, 'error', 'invalid_value', 'reason', 'window_missing_start_or_end');
      end if;
      if not (trim(both '"' from (v_elem->'start')::text) ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$')
         or not (trim(both '"' from (v_elem->'end')::text) ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$') then
        return jsonb_build_object('ok', false, 'error', 'invalid_value', 'reason', 'window_time_not_hhmm');
      end if;
      if (split_part(trim(both '"' from (v_elem->'start')::text), ':', 1)::integer * 60 + split_part(trim(both '"' from (v_elem->'start')::text), ':', 2)::integer)
         >= (split_part(trim(both '"' from (v_elem->'end')::text), ':', 1)::integer * 60 + split_part(trim(both '"' from (v_elem->'end')::text), ':', 2)::integer) then
        return jsonb_build_object('ok', false, 'error', 'invalid_value', 'reason', 'window_start_not_before_end');
      end if;
    end loop;
  end if;

  -- technician_leave: array of objects, each must reference an
  -- existing technician_id and a valid ISO date.
  if p_key = 'technician_leave' then
    if jsonb_typeof(p_value) <> 'array' then
      return jsonb_build_object('ok', false, 'error', 'invalid_value_shape', 'expected', 'array');
    end if;
    for v_elem in select * from jsonb_array_elements(p_value)
    loop
      if jsonb_typeof(v_elem) <> 'object'
         or not (v_elem ? 'technician_id') or jsonb_typeof(v_elem->'technician_id') <> 'string'
         or not (v_elem ? 'date') or jsonb_typeof(v_elem->'date') <> 'string' then
        return jsonb_build_object('ok', false, 'error', 'invalid_value', 'reason', 'leave_missing_technician_id_or_date');
      end if;
      begin
        perform (trim(both '"' from (v_elem->'date')::text))::date;
      exception when others then
        return jsonb_build_object('ok', false, 'error', 'invalid_value', 'reason', 'leave_date_not_valid_iso_date');
      end;
      if not exists (
        select 1 from public.workshop_technicians
        where id = (trim(both '"' from (v_elem->'technician_id')::text))::uuid
      ) then
        return jsonb_build_object('ok', false, 'error', 'invalid_value', 'reason', 'leave_technician_not_found', 'technician_id', v_elem->'technician_id');
      end if;
    end loop;
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

grant execute on function public.update_workshop_configuration(text, integer, jsonb) to authenticated;
revoke all on function public.update_workshop_configuration(text, integer, jsonb) from public, anon;

comment on function public.update_workshop_configuration(text, integer, jsonb) is
  'Stage 2A independent-review remediation: full per-key shape/range/relational validation (HH:MM format, start<end, positive bounded durations, allowed day names with no duplicates, closure/break/overtime/leave object shape and date validity, leave technician_id existence) -- previously validated only the top-level JSON type.';
