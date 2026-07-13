-- PDC Control Board protected RPC functions
-- Apply after 001_initial_schema.sql and 002_rls_policies.sql.

create or replace function public.require_pdc_role(required_role public.pdc_role)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_pdc_role(required_role) then
    raise exception 'PDC role % required', required_role using errcode = '42501';
  end if;
end;
$$;

create or replace function public.audit_pdc_event(
  p_action public.audit_action,
  p_table_name text default null,
  p_row_id uuid default null,
  p_vehicle_id uuid default null,
  p_before jsonb default null,
  p_after jsonb default null,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_audit_id uuid;
begin
  insert into public.audit_events (
    action,
    table_name,
    row_id,
    vehicle_id,
    actor_id,
    actor_email,
    before_data,
    after_data,
    metadata
  ) values (
    p_action,
    p_table_name,
    p_row_id,
    p_vehicle_id,
    auth.uid(),
    public.current_actor_email(),
    p_before,
    p_after,
    coalesce(p_metadata, '{}'::jsonb)
  ) returning id into v_audit_id;

  return v_audit_id;
end;
$$;

create or replace function public.move_vehicle(
  p_vehicle_id uuid,
  p_expected_version integer,
  p_to_location text default null,
  p_to_pmb_stage text default null,
  p_to_pmb_bay_stage text default null,
  p_to_pmb_bay_number text default null,
  p_reason text default null
)
returns public.vehicles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_before public.vehicles%rowtype;
  v_after public.vehicles%rowtype;
begin
  perform public.require_pdc_role('operator');

  select * into v_before
  from public.vehicles
  where id = p_vehicle_id
  for update;

  if not found then
    raise exception 'Vehicle not found' using errcode = 'P0002';
  end if;

  if v_before.version <> p_expected_version then
    raise exception 'Vehicle version conflict: expected %, current %', p_expected_version, v_before.version using errcode = '40001';
  end if;

  update public.vehicles
  set current_location = coalesce(p_to_location, current_location),
      pmb_stage = p_to_pmb_stage,
      pmb_bay_stage = p_to_pmb_bay_stage,
      pmb_bay_number = p_to_pmb_bay_number,
      visible_on_board = true,
      version = version + 1,
      updated_by = auth.uid()
  where id = p_vehicle_id
  returning * into v_after;

  insert into public.vehicle_movements (
    vehicle_id,
    from_location,
    to_location,
    from_pmb_stage,
    to_pmb_stage,
    from_pmb_bay_stage,
    to_pmb_bay_stage,
    from_pmb_bay_number,
    to_pmb_bay_number,
    reason,
    moved_by
  ) values (
    p_vehicle_id,
    v_before.current_location,
    v_after.current_location,
    v_before.pmb_stage,
    v_after.pmb_stage,
    v_before.pmb_bay_stage,
    v_after.pmb_bay_stage,
    v_before.pmb_bay_number,
    v_after.pmb_bay_number,
    p_reason,
    auth.uid()
  );

  perform public.audit_pdc_event(
    'move',
    'vehicles',
    p_vehicle_id,
    p_vehicle_id,
    to_jsonb(v_before),
    to_jsonb(v_after),
    jsonb_build_object('reason', p_reason)
  );

  return v_after;
end;
$$;

create or replace function public.mark_vehicle_deleted(
  p_vehicle_id uuid,
  p_expected_version integer,
  p_reason text default null
)
returns public.vehicles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_before public.vehicles%rowtype;
  v_after public.vehicles%rowtype;
begin
  perform public.require_pdc_role('operator');

  select * into v_before
  from public.vehicles
  where id = p_vehicle_id
  for update;

  if not found then
    raise exception 'Vehicle not found' using errcode = 'P0002';
  end if;

  if v_before.version <> p_expected_version then
    raise exception 'Vehicle version conflict: expected %, current %', p_expected_version, v_before.version using errcode = '40001';
  end if;

  update public.vehicles
  set lifecycle_state = 'deleted',
      visible_on_board = false,
      deleted_at = now(),
      deleted_reason = p_reason,
      version = version + 1,
      updated_by = auth.uid()
  where id = p_vehicle_id
  returning * into v_after;

  insert into public.deleted_completed_vehicles (
    vehicle_id,
    final_state,
    snapshot,
    reason,
    acted_by
  ) values (
    p_vehicle_id,
    'deleted',
    to_jsonb(v_after),
    p_reason,
    auth.uid()
  );

  perform public.audit_pdc_event('delete', 'vehicles', p_vehicle_id, p_vehicle_id, to_jsonb(v_before), to_jsonb(v_after), jsonb_build_object('reason', p_reason));
  return v_after;
end;
$$;

create or replace function public.restore_vehicle(
  p_vehicle_id uuid,
  p_expected_version integer,
  p_reason text default null
)
returns public.vehicles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_before public.vehicles%rowtype;
  v_after public.vehicles%rowtype;
begin
  perform public.require_pdc_role('importer');

  select * into v_before
  from public.vehicles
  where id = p_vehicle_id
  for update;

  if not found then
    raise exception 'Vehicle not found' using errcode = 'P0002';
  end if;

  if v_before.version <> p_expected_version then
    raise exception 'Vehicle version conflict: expected %, current %', p_expected_version, v_before.version using errcode = '40001';
  end if;

  update public.vehicles
  set lifecycle_state = 'active',
      visible_on_board = true,
      deleted_at = null,
      deleted_reason = null,
      version = version + 1,
      updated_by = auth.uid()
  where id = p_vehicle_id
  returning * into v_after;

  perform public.audit_pdc_event('restore', 'vehicles', p_vehicle_id, p_vehicle_id, to_jsonb(v_before), to_jsonb(v_after), jsonb_build_object('reason', p_reason));
  return v_after;
end;
$$;

create or replace function public.record_import_run(
  p_import_type public.import_type,
  p_source_file_name text,
  p_source_hash text,
  p_summary jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_import_id uuid;
begin
  perform public.require_pdc_role('importer');

  insert into public.import_runs (
    import_type,
    source_file_name,
    source_hash,
    status,
    summary,
    run_by,
    completed_at
  ) values (
    p_import_type,
    p_source_file_name,
    p_source_hash,
    'completed',
    coalesce(p_summary, '{}'::jsonb),
    auth.uid(),
    now()
  ) returning id into v_import_id;

  perform public.audit_pdc_event('import', 'import_runs', v_import_id, null, null, p_summary, jsonb_build_object('import_type', p_import_type));
  return v_import_id;
end;
$$;
