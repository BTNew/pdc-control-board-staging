-- Keep online Vehicle Locations synchronized with canonical vehicle/workshop
-- lifecycle changes, including changes initiated from another signed-in browser.
begin;

create or replace function public.pdc_online_vehicle_change_bump_revision()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $bump$
begin
  update public.pdc_online_state_revision
  set revision = revision + 1, updated_at = clock_timestamp()
  where singleton;
  return new;
end;
$bump$;

revoke all on function public.pdc_online_vehicle_change_bump_revision() from public, anon, authenticated;

drop trigger if exists trg_pdc_online_vehicle_change_revision on public.vehicles;
create trigger trg_pdc_online_vehicle_change_revision
after update of current_location, pmb_stage, pmb_bay_stage, pmb_bay_number,
  lifecycle_state, visible_on_board, version, active_workshop_booking_id,
  workshop_status, qc_completed_at, rft_transferred_at, rft_collected_at
on public.vehicles
for each statement execute function public.pdc_online_vehicle_change_bump_revision();

create or replace function public.get_pdc_online_state_snapshot()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $snapshot$
declare
  v_revision bigint;
  v_documents jsonb;
  v_added_key constant text := 'vehicleTrackingCoreNavisionOnlyVehicles:v1';
  v_added_document jsonb;
  v_projected jsonb;
begin
  if auth.uid() is null or not public.is_pdc_role('viewer') then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;

  select revision into v_revision
  from public.pdc_online_state_revision where singleton;

  select coalesce(jsonb_object_agg(s.state_key, jsonb_build_object(
    'payload', s.payload,
    'version', s.version,
    'updated_at', s.updated_at
  )), '{}'::jsonb)
  into v_documents
  from public.pdc_online_operational_state s;

  v_added_document := v_documents->v_added_key;
  if jsonb_typeof(v_added_document->'payload') = 'array' then
    select coalesce(jsonb_agg(
      case when v.id is null then item.value else
        item.value || jsonb_build_object(
          'sharedVehicleId', v.id,
          'permanentVehicleId', v.permanent_vehicle_id,
          'canonicalVersion', v.version,
          'pdcLocation', coalesce(v.current_location, item.value->>'pdcLocation', ''),
          'pmbStage', coalesce(v.pmb_stage, item.value->>'pmbStage', ''),
          'pmbBayStage', coalesce(v.pmb_bay_stage, item.value->>'pmbBayStage', ''),
          'pmbBayNumber', coalesce(v.pmb_bay_number, item.value->>'pmbBayNumber', ''),
          'workshopStatus', v.workshop_status,
          'activeWorkshopBookingId', v.active_workshop_booking_id,
          'qcCompletedAt', v.qc_completed_at,
          'rftTransferredAt', v.rft_transferred_at,
          'lifecycleState', v.lifecycle_state,
          'visibleOnBoard', v.visible_on_board
        )
      end order by item.ordinality
    ), '[]'::jsonb)
    into v_projected
    from jsonb_array_elements(v_added_document->'payload') with ordinality as item(value, ordinality)
    left join public.vehicles v on v.id::text = item.value->>'sharedVehicleId'
    where v.id is null or v.lifecycle_state <> 'deleted';

    v_documents := jsonb_set(v_documents, array[v_added_key, 'payload'], v_projected, true);
  end if;

  return jsonb_build_object(
    'ok', true,
    'revision', v_revision,
    'documents', v_documents,
    'authority', 'supabase_online_only'
  );
end;
$snapshot$;

revoke all on function public.get_pdc_online_state_snapshot() from public, anon, authenticated;
grant execute on function public.get_pdc_online_state_snapshot() to authenticated;

comment on function public.get_pdc_online_state_snapshot() is
  'Authenticated online-only document snapshot with canonical vehicle lifecycle fields overlaid server-side.';

commit;
