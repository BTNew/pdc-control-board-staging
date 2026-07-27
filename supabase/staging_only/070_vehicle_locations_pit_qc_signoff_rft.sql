-- 070_vehicle_locations_pit_qc_signoff_rft.sql
-- Staging-only authority for the Vehicle Locations flow:
--   RFT > QC > PIT > PMB > YARD HOLD > IT > OTHER
-- PIT is a physical location, not a productive workshop stage. QC is an
-- eligibility bucket; one deliberate QC sign-off completes QC and transfers
-- the vehicle to RFT in the same database transaction.
-- Depends on staging-only migration 069 and is intentionally unapplied.

begin;

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists (
       select 1 from public.pdc_staging_environment_sentinel
       where singleton and project_ref = 'cdsmnqxtyyoeoznmbidd'
     ) then
    raise exception 'PDC_STAGING_SENTINEL_MISMATCH';
  end if;
  if to_regclass('public.vehicles') is null
     or to_regclass('public.vehicle_movements') is null
     or to_regclass('public.workshop_bookings') is null
     or to_regprocedure('public.require_pdc_role(public.pdc_role)') is null
     or to_regprocedure('public.audit_pdc_event(public.audit_action,text,uuid,uuid,jsonb,jsonb,jsonb)') is null
     or to_regprocedure('public.pdc_qc_gate_issues(uuid)') is null
     or to_regprocedure('public.qc_complete_vehicle(uuid,integer,text,text)') is null
     or to_regprocedure('public.rft_transfer_vehicle(uuid,integer)') is null then
    raise exception 'PDC_MIGRATION_070_DEPENDENCY_MISSING';
  end if;
end;
$guard$;

-- Reconcile legacy non-booked PIT stage assignments into the PIT location.
-- Migration 069 fails closed before this point if an active PIT planner booking
-- still exists, so no live booking is silently discarded.
insert into public.vehicle_movements (
  vehicle_id, from_location, to_location, from_pmb_stage, to_pmb_stage,
  from_pmb_bay_stage, to_pmb_bay_stage, from_pmb_bay_number, to_pmb_bay_number,
  reason, moved_by
)
select
  v.id, v.current_location, 'PIT', v.pmb_stage, null,
  v.pmb_bay_stage, null, v.pmb_bay_number, null,
  'Migration 070: legacy PIT workshop state converted to PIT vehicle location', auth.uid()
from public.vehicles v
where v.lifecycle_state = 'active'
  and regexp_replace(upper(coalesce(v.pmb_stage, v.pmb_bay_stage, '')), '[^A-Z0-9]+', '_', 'g') in ('PIT', 'PIT_INSPECTION')
  and upper(coalesce(v.current_location, '')) <> 'PIT';

update public.vehicles v
set current_location = 'PIT',
    pmb_stage = null,
    pmb_bay_stage = null,
    pmb_bay_number = null,
    version = version + 1,
    updated_by = auth.uid()
where v.lifecycle_state = 'active'
  and regexp_replace(upper(coalesce(v.pmb_stage, v.pmb_bay_stage, '')), '[^A-Z0-9]+', '_', 'g') in ('PIT', 'PIT_INSPECTION');

create or replace function public.pit_transfer_vehicle(
  p_vehicle_id uuid,
  p_expected_version integer,
  p_direction text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_before public.vehicles%rowtype;
  v_after public.vehicles%rowtype;
  v_direction text := lower(trim(coalesce(p_direction, '')));
  v_target text;
begin
  perform public.require_pdc_role('operator');

  if v_direction not in ('to_pit', 'to_pmb') then
    return jsonb_build_object('ok', false, 'error', 'invalid_pit_direction');
  end if;

  select * into v_before from public.vehicles where id = p_vehicle_id for update;
  if not found then
    raise exception 'Vehicle not found' using errcode = 'P0002';
  end if;
  if p_expected_version is null then
    return jsonb_build_object('ok', false, 'error', 'missing_expected_version');
  end if;
  if v_before.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'vehicle_version_conflict');
  end if;
  if v_before.lifecycle_state <> 'active' then
    return jsonb_build_object('ok', false, 'error', 'not_in_active_lifecycle');
  end if;

  if v_direction = 'to_pit' then
    if upper(coalesce(v_before.current_location, '')) <> 'PMB'
       or nullif(trim(coalesce(v_before.pmb_stage, '')), '') is not null
       or nullif(trim(coalesce(v_before.pmb_bay_stage, '')), '') is not null
       or nullif(trim(coalesce(v_before.pmb_bay_number, '')), '') is not null
       or exists (
         select 1 from public.workshop_bookings b
         where b.vehicle_id = p_vehicle_id
           and b.status::text not in ('completed', 'deleted', 'cancelled')
       ) then
      return jsonb_build_object('ok', false, 'error', 'pit_requires_pmb_unallocated');
    end if;
    if v_before.qc_completed_at is not null then
      return jsonb_build_object('ok', false, 'error', 'already_qc_complete');
    end if;
    v_target := 'PIT';
  else
    if upper(coalesce(v_before.current_location, '')) <> 'PIT' then
      return jsonb_build_object('ok', false, 'error', 'not_in_pit');
    end if;
    v_target := 'PMB';
  end if;

  update public.vehicles
  set current_location = v_target,
      pmb_stage = null,
      pmb_bay_stage = null,
      pmb_bay_number = null,
      version = version + 1,
      updated_by = auth.uid()
  where id = p_vehicle_id
  returning * into v_after;

  insert into public.vehicle_movements (
    vehicle_id, from_location, to_location, from_pmb_stage, to_pmb_stage,
    from_pmb_bay_stage, to_pmb_bay_stage, from_pmb_bay_number, to_pmb_bay_number,
    reason, moved_by
  ) values (
    p_vehicle_id, v_before.current_location, v_target, v_before.pmb_stage, null,
    v_before.pmb_bay_stage, null, v_before.pmb_bay_number, null,
    case when v_direction = 'to_pit'
      then 'Transferred to PIT for Department of Transport inspection'
      else 'Returned from PIT to PMB Unallocated'
    end,
    auth.uid()
  );

  perform public.audit_pdc_event(
    'move', 'vehicles', p_vehicle_id, p_vehicle_id,
    to_jsonb(v_before), to_jsonb(v_after),
    jsonb_build_object('action', 'pit_transfer_vehicle', 'direction', v_direction)
  );

  return jsonb_build_object('ok', true, 'vehicle', to_jsonb(v_after));
end;
$$;

-- One UI sign-off, two existing audited state changes, one transaction.
-- Any unexpected RFT failure raises and rolls the QC update back atomically.
create or replace function public.qc_signoff_to_rft(
  p_vehicle_id uuid,
  p_expected_version integer,
  p_work_item_key text default 'QC',
  p_completed_summary text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_before public.vehicles%rowtype;
  v_issues text[];
  v_qc jsonb;
  v_rft jsonb;
begin
  perform public.require_pdc_role('operator');

  select * into v_before from public.vehicles where id = p_vehicle_id for update;
  if not found then
    raise exception 'Vehicle not found' using errcode = 'P0002';
  end if;
  if p_expected_version is null then
    return jsonb_build_object('ok', false, 'error', 'missing_expected_version');
  end if;
  if v_before.version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'vehicle_version_conflict');
  end if;
  if v_before.qc_completed_at is not null then
    return jsonb_build_object('ok', false, 'error', 'already_qc_complete');
  end if;

  v_issues := public.pdc_qc_gate_issues(p_vehicle_id);
  if coalesce(array_length(v_issues, 1), 0) > 0 then
    return jsonb_build_object('ok', false, 'error', 'qc_gate_blocked', 'issues', to_jsonb(v_issues));
  end if;

  v_qc := public.qc_complete_vehicle(
    p_vehicle_id,
    p_expected_version,
    p_work_item_key,
    p_completed_summary
  );
  if coalesce((v_qc ->> 'ok')::boolean, false) is not true then
    return v_qc;
  end if;

  v_rft := public.rft_transfer_vehicle(p_vehicle_id, p_expected_version + 1);
  if coalesce((v_rft ->> 'ok')::boolean, false) is not true then
    raise exception 'PDC_QC_SIGNOFF_TO_RFT_ATOMIC_FAILED: %', coalesce(v_rft ->> 'error', 'unknown');
  end if;

  return v_rft || jsonb_build_object(
    'notification_id', v_qc -> 'notification_id',
    'notification_has_recipient', v_qc -> 'notification_has_recipient',
    'qc_signed_off', true,
    'rft_transferred', true
  );
end;
$$;

revoke all on function public.pit_transfer_vehicle(uuid, integer, text) from public;
revoke all on function public.qc_signoff_to_rft(uuid, integer, text, text) from public;
grant execute on function public.pit_transfer_vehicle(uuid, integer, text) to authenticated;
grant execute on function public.qc_signoff_to_rft(uuid, integer, text, text) to authenticated;

commit;
