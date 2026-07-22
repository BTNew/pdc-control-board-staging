begin;

-- Navision imports are bounded, role-scoped backend operations. The default
-- PostgREST statement timeout is too short for a full dealer reconciliation;
-- retain one atomic preview/apply contract while allowing the bounded RPCs to
-- complete. No browser-local apply path is introduced.
alter function public.preview_navision_backend_import(jsonb,text,text,text,timestamptz)
  set statement_timeout = '120s';
alter function public.apply_navision_backend_import(text,jsonb,text,text,text,timestamptz,text,text,bigint)
  set statement_timeout = '120s';

-- Yard Hold is immediately schedulable. In Transit remains fail-closed until
-- ETA and may only be scheduled on/after ETA.
create or replace function public.workshop_enforce_vehicle_eta()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_vehicle public.vehicles%rowtype;
  v_location text;
begin
  select * into v_vehicle from public.vehicles where id = new.vehicle_id;
  v_location := upper(btrim(coalesce(v_vehicle.current_location,'')));
  if v_location = 'IT' then
    if v_vehicle.eta_to_kewdale is null then
      raise exception 'missing_or_invalid_eta' using errcode='23514';
    end if;
    if (new.scheduled_start_at at time zone 'Australia/Perth')::date < v_vehicle.eta_to_kewdale then
      raise exception 'booking_before_eta earliest_permitted_date=%',v_vehicle.eta_to_kewdale using errcode='23514';
    end if;
    new.eta_at_booking := v_vehicle.eta_to_kewdale;
    new.eta_risk_status := 'none';
    new.eta_risk_detected_at := null;
  else
    new.eta_at_booking := null;
    new.eta_risk_status := 'none';
    new.eta_risk_detected_at := null;
  end if;
  return new;
end;
$$;

drop trigger if exists workshop_bookings_enforce_vehicle_eta on public.workshop_bookings;
create trigger workshop_bookings_enforce_vehicle_eta
before insert or update of scheduled_start_at, vehicle_id on public.workshop_bookings
for each row execute function public.workshop_enforce_vehicle_eta();

create or replace function public.workshop_refresh_eta_risk()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_booking public.workshop_bookings%rowtype;
  v_after jsonb;
  v_new_status text;
  v_location text := upper(btrim(coalesce(new.current_location,'')));
  v_actor uuid := coalesce(auth.uid(), new.updated_by, old.updated_by);
begin
  if new.eta_to_kewdale is distinct from old.eta_to_kewdale
     or new.current_location is distinct from old.current_location then
    for v_booking in
      select b.* from public.workshop_bookings b
      where b.vehicle_id=new.id and b.status='planned' and b.deleted_at is null
      for update
    loop
      v_new_status:=case when v_location='IT' and (new.eta_to_kewdale is null or (v_booking.scheduled_start_at at time zone 'Australia/Perth')::date<new.eta_to_kewdale) then 'at_risk' else 'none' end;
      if v_booking.eta_risk_status is distinct from v_new_status then
        update public.workshop_bookings b
        set eta_risk_status=v_new_status,
            eta_risk_detected_at=case when v_new_status='at_risk' then coalesce(b.eta_risk_detected_at,now()) else null end,
            version=b.version+1,
            updated_by=coalesce(v_actor,b.updated_by)
        where b.id=v_booking.id
        returning to_jsonb(b.*) into v_after;
        if v_actor is not null then
          insert into public.workshop_booking_history(booking_id,event_type,before_data,after_data,metadata,actor_user_id,actor_email)
          values(v_booking.id,'eta_risk_changed',to_jsonb(v_booking),v_after,
            jsonb_build_object('vehicle_id',new.id,'previous_eta',old.eta_to_kewdale,'current_eta',new.eta_to_kewdale,'planning_location',v_location),
            v_actor,public.current_actor_email());
        end if;
      end if;
    end loop;
  end if;
  return new;
end;
$$;

drop trigger if exists vehicles_refresh_workshop_eta_risk on public.vehicles;
create trigger vehicles_refresh_workshop_eta_risk
after update of eta_to_kewdale, current_location on public.vehicles
for each row execute function public.workshop_refresh_eta_risk();

-- Scheduling updates scheduling metadata only. It must never move a vehicle or
-- make a location decision as a side effect.
create or replace function public.schedule_vehicle_work(
  p_vehicle_id uuid,
  p_vehicle_expected_version integer,
  p_stage_code text,
  p_bay_number integer,
  p_scheduled_start_at timestamptz,
  p_duration_minutes integer default 180,
  p_technician_id uuid default null,
  p_override_reason text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_vehicle public.vehicles%rowtype;
  v_stage public.workshop_stages%rowtype;
  v_booking jsonb;
  v_override_id uuid;
  v_before_vehicle jsonb;
  v_after_vehicle jsonb;
  v_revision bigint;
begin
  perform public.require_pdc_role('operator');
  perform public.workshop_require_version(p_vehicle_expected_version);
  select * into v_vehicle from public.vehicles where id = p_vehicle_id for update;
  if not found then raise exception 'Vehicle not found' using errcode = 'P0002'; end if;
  if v_vehicle.version <> p_vehicle_expected_version then
    return jsonb_build_object('ok', false, 'error', 'vehicle_version_conflict');
  end if;
  select * into v_stage from public.workshop_stages where code = upper(trim(coalesce(p_stage_code, ''))) and active = true;
  if not found then raise exception 'Workshop stage % not found', p_stage_code using errcode = 'P0002'; end if;
  if v_stage.is_physical and not public.workshop_parts_ready(p_vehicle_id) then
    if p_override_reason is null or trim(p_override_reason) = '' then
      return jsonb_build_object('ok', false, 'error', 'parts_incomplete');
    end if;
    perform public.require_pdc_role('administrator');
  end if;
  v_before_vehicle := to_jsonb(v_vehicle);
  v_booking := public.workshop_create_booking(
    p_vehicle_id, p_stage_code, p_bay_number, p_scheduled_start_at,
    p_duration_minutes, p_technician_id, p_metadata
  );
  if not (v_booking->>'ok')::boolean then return v_booking; end if;
  update public.vehicles
  set active_workshop_booking_id = (v_booking->'booking'->>'booking_id')::uuid,
      workshop_status = 'scheduled',
      workshop_status_updated_at = now(),
      workshop_status_updated_by = auth.uid(),
      version = version + 1,
      updated_by = auth.uid()
  where id = p_vehicle_id
  returning to_jsonb(vehicles.*) into v_after_vehicle;
  if p_override_reason is not null and trim(p_override_reason) <> '' then
    insert into public.workshop_parts_overrides (
      vehicle_id, booking_id, work_key, intended_stage_id, reason,
      previous_state, resulting_state, approved_by, approved_by_email
    ) values (
      p_vehicle_id, (v_booking->'booking'->>'booking_id')::uuid, 'PARTS', v_stage.id,
      trim(p_override_reason), v_before_vehicle, v_after_vehicle, auth.uid(), public.current_actor_email()
    ) returning id into v_override_id;
  end if;
  perform public.audit_pdc_event('move', 'vehicles', p_vehicle_id, p_vehicle_id, v_before_vehicle, v_after_vehicle,
    jsonb_build_object('action','schedule_vehicle_work','override_id',v_override_id,'planning_location',v_vehicle.current_location,'eta_at_booking',v_vehicle.eta_to_kewdale));
  v_revision := public.workshop_bump_revision();
  return jsonb_build_object('ok', true, 'booking', v_booking->'booking', 'vehicle', v_after_vehicle,
    'override_id', v_override_id, 'revision', v_revision);
end;
$$;

revoke all on function public.workshop_enforce_vehicle_eta() from public,anon,authenticated;
revoke all on function public.workshop_refresh_eta_risk() from public,anon,authenticated;
revoke all on function public.schedule_vehicle_work(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb) from public,anon;
grant execute on function public.schedule_vehicle_work(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb) to authenticated;

commit;
