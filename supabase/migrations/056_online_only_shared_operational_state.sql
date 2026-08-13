-- Online-only shared operational state for the PDC staging board.
-- Replaces browser-persisted operational authority with audited, revisioned,
-- authenticated Supabase state. Browser storage remains neither a source nor a
-- fallback when this contract is enabled.

begin;

create table if not exists public.pdc_online_state_revision (
  singleton boolean primary key default true check (singleton),
  revision bigint not null default 1,
  updated_at timestamptz not null default now()
);
insert into public.pdc_online_state_revision(singleton, revision)
values (true, 1) on conflict (singleton) do nothing;

create table if not exists public.pdc_online_operational_state (
  state_key text primary key,
  payload jsonb not null,
  version bigint not null default 1 check (version >= 1),
  updated_by uuid references auth.users(id) on delete set null,
  updated_by_email text,
  updated_at timestamptz not null default now(),
  constraint pdc_online_state_key_nonblank check (btrim(state_key) <> ''),
  constraint pdc_online_state_payload_size check (octet_length(payload::text) <= 8388608)
);

create table if not exists public.pdc_online_state_receipts (
  idempotency_key text primary key,
  state_key text not null,
  request_hash text not null,
  response jsonb not null,
  actor_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

alter table public.pdc_online_state_revision enable row level security;
alter table public.pdc_online_operational_state enable row level security;
alter table public.pdc_online_state_receipts enable row level security;
revoke all on table public.pdc_online_state_revision,
  public.pdc_online_operational_state,
  public.pdc_online_state_receipts from public, anon, authenticated;

create or replace function public.pdc_online_state_key_allowed(p_key text)
returns boolean
language sql
immutable
parallel safe
set search_path = pg_catalog, public
as $key$
  select p_key = any(array[
    'vehicleTrackingCoreNavisionOnlyEdits:v1',
    'vehicleTrackingCoreNavisionOnlyVehicles:v1',
    'vehicleTrackingCoreNavisionOnlyPoTasks:v1',
    'vehicleTrackingCoreNavisionOnlyPoFiles:v1',
    'vehicleTrackingCoreNavisionOnlyDeleted:v1',
    'vehicleTrackingCoreNavisionOnlyAutocareDispatch:v1',
    'vehicleTrackingCoreNavisionOnlyImport:v1',
    'vehicleTrackingCoreNavisionOnlyAuditLog:v1',
    'vehicleTrackingCoreOperationalHealth:v1',
    'vehicleTrackingCoreEmailReviewDecisions:v1',
    'vehicleTrackingCoreAiFileAssistantReviews:v1'
  ]) or p_key ~ '^vehicleTrackingCoreNotes:[A-Za-z0-9_.:@-]{1,160}$';
$key$;

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
  return jsonb_build_object(
    'ok', true,
    'revision', v_revision,
    'documents', v_documents,
    'authority', 'supabase_online_only'
  );
end;
$snapshot$;

create or replace function public.save_pdc_online_state(
  p_state_key text,
  p_payload jsonb,
  p_expected_version bigint,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $save$
declare
  v_key text := btrim(coalesce(p_state_key, ''));
  v_idempotency text := lower(btrim(coalesce(p_idempotency_key, '')));
  v_actor uuid := auth.uid();
  v_role text := public.current_pdc_user_role()::text;
  v_request_hash text;
  v_existing public.pdc_online_state_receipts%rowtype;
  v_row public.pdc_online_operational_state%rowtype;
  v_old_payload jsonb := '[]'::jsonb;
  v_payload jsonb := p_payload;
  v_item jsonb;
  v_normalized jsonb := '[]'::jsonb;
  v_manual_id text;
  v_permanent_id text;
  v_vehicle public.vehicles%rowtype;
  v_old_item jsonb;
  v_old_manual_id text;
  v_new_ids text[] := '{}'::text[];
  v_revision bigint;
  v_response jsonb;
begin
  if v_actor is null or v_role not in ('operator', 'importer', 'administrator') then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if not public.pdc_online_state_key_allowed(v_key) then
    return jsonb_build_object('ok', false, 'error', 'invalid_state_key');
  end if;
  if v_payload is null or octet_length(v_payload::text) > 8388608 then
    return jsonb_build_object('ok', false, 'error', 'invalid_payload');
  end if;
  if p_expected_version is null or p_expected_version < 0 then
    return jsonb_build_object('ok', false, 'error', 'expected_version_required');
  end if;
  if v_idempotency !~ '^pdc-online-[a-f0-9]{32}$' then
    return jsonb_build_object('ok', false, 'error', 'invalid_idempotency_key');
  end if;

  v_request_hash := encode(extensions.digest(jsonb_build_object(
    'contract_version', 1,
    'environment', 'staging',
    'project_ref', 'cdsmnqxtyyoeoznmbidd',
    'state_key', v_key,
    'payload', v_payload,
    'expected_version', p_expected_version,
    'actor_id', v_actor
  )::text, 'sha256'), 'hex');

  perform pg_advisory_xact_lock(hashtextextended('pdc-online-state:' || v_key, 0));
  select * into v_existing from public.pdc_online_state_receipts
  where idempotency_key = v_idempotency;
  if found then
    if v_existing.request_hash <> v_request_hash then
      return jsonb_build_object('ok', false, 'error', 'idempotency_conflict');
    end if;
    return v_existing.response;
  end if;

  select * into v_row from public.pdc_online_operational_state
  where state_key = v_key for update;
  if found then
    if v_row.version <> p_expected_version then
      return jsonb_build_object('ok', false, 'error', 'version_conflict', 'current_version', v_row.version);
    end if;
    v_old_payload := v_row.payload;
  elsif p_expected_version <> 0 then
    return jsonb_build_object('ok', false, 'error', 'version_conflict', 'current_version', 0);
  end if;

  -- Manual browser-created rows become canonical shared vehicles in the same
  -- transaction. Their server UUID/version is written back into the stored
  -- document so Workshop/QC/RFT actions resolve the exact online vehicle.
  if v_key = 'vehicleTrackingCoreNavisionOnlyVehicles:v1' then
    if jsonb_typeof(v_payload) <> 'array' or jsonb_array_length(v_payload) > 10000 then
      return jsonb_build_object('ok', false, 'error', 'invalid_vehicle_array');
    end if;
    for v_item in select value from jsonb_array_elements(v_payload)
    loop
      if jsonb_typeof(v_item) <> 'object' then
        return jsonb_build_object('ok', false, 'error', 'invalid_vehicle_row');
      end if;
      v_manual_id := btrim(coalesce(v_item->>'id', ''));
      if v_manual_id !~ '^(manual|qa)-[A-Za-z0-9_.:-]{1,120}$' then
        return jsonb_build_object('ok', false, 'error', 'invalid_manual_vehicle_id');
      end if;
      v_permanent_id := 'ONLINE:' || v_manual_id;
      v_new_ids := array_append(v_new_ids, v_manual_id);
      select * into v_vehicle
      from public.vehicles
      where permanent_vehicle_id = v_permanent_id
      for update;
      if found then
        update public.vehicles set
          stock_number = nullif(btrim(v_item->>'stock'), ''),
          vin = nullif(btrim(coalesce(v_item->>'vin', v_item->>'VIN')), ''),
          toyota_order_number = nullif(btrim(coalesce(v_item->>'orderNumber', v_item->>'toyotaOrderNumber')), ''),
          job_card_number = nullif(btrim(coalesce(v_item->>'pdcJobcard', v_item->>'jobCardNumber')), ''),
          customer_name = nullif(btrim(coalesce(v_item->>'client', v_item->>'customerName')), ''),
          make = nullif(btrim(v_item->>'make'), ''),
          model = nullif(btrim(coalesce(v_item->>'vehicle', v_item->>'model')), ''),
          lifecycle_state = 'active',
          visible_on_board = true,
          deleted_at = null,
          deleted_reason = null,
          source_payload = v_item || jsonb_build_object('online_state_key', v_key),
          version = version + 1,
          updated_by = v_actor
        where id = v_vehicle.id
        returning * into v_vehicle;
      else
        insert into public.vehicles (
          permanent_vehicle_id, stock_number, vin, toyota_order_number,
          job_card_number, customer_name, make, model, lifecycle_state,
          visible_on_board, current_location, pmb_stage, source_payload,
          created_by, updated_by
        ) values (
          v_permanent_id,
          nullif(btrim(v_item->>'stock'), ''),
          nullif(btrim(coalesce(v_item->>'vin', v_item->>'VIN')), ''),
          nullif(btrim(coalesce(v_item->>'orderNumber', v_item->>'toyotaOrderNumber')), ''),
          nullif(btrim(coalesce(v_item->>'pdcJobcard', v_item->>'jobCardNumber')), ''),
          nullif(btrim(coalesce(v_item->>'client', v_item->>'customerName')), ''),
          nullif(btrim(v_item->>'make'), ''),
          nullif(btrim(coalesce(v_item->>'vehicle', v_item->>'model')), ''),
          'active', true,
          case upper(btrim(coalesce(v_item->>'pdcLocation', v_item->>'manualLocation', '')))
            when 'YH' then 'YH' when 'PMB' then 'PMB' when 'RFT' then 'RFT' else null end,
          nullif(upper(btrim(coalesce(v_item->>'pmbStage', ''))), ''),
          v_item || jsonb_build_object('online_state_key', v_key),
          v_actor, v_actor
        ) returning * into v_vehicle;
      end if;
      v_normalized := v_normalized || jsonb_build_array(v_item || jsonb_build_object(
        'sharedVehicleId', v_vehicle.id,
        'shared_vehicle_id', v_vehicle.id,
        'permanentVehicleId', v_vehicle.permanent_vehicle_id,
        'sharedVehicleVersion', v_vehicle.version,
        'sourceSystem', 'pdc_online_manual',
        'sourceRecordId', v_manual_id
      ));
    end loop;
    for v_old_item in select value from jsonb_array_elements(
      case when jsonb_typeof(v_old_payload) = 'array' then v_old_payload else '[]'::jsonb end
    ) loop
      v_old_manual_id := btrim(coalesce(v_old_item->>'id', ''));
      if v_old_manual_id ~ '^(manual|qa)-[A-Za-z0-9_.:-]{1,120}$'
         and not (v_old_manual_id = any(v_new_ids)) then
        update public.vehicles set lifecycle_state = 'deleted', visible_on_board = false,
          deleted_at = now(), deleted_reason = 'Removed from online Vehicle Locations',
          version = version + 1, updated_by = v_actor
        where permanent_vehicle_id = 'ONLINE:' || v_old_manual_id
          and lifecycle_state <> 'deleted';
      end if;
    end loop;
    v_payload := v_normalized;
  end if;

  insert into public.pdc_online_operational_state(
    state_key, payload, version, updated_by, updated_by_email
  ) values (v_key, v_payload, 1, v_actor, public.current_actor_email())
  on conflict (state_key) do update set
    payload = excluded.payload,
    version = public.pdc_online_operational_state.version + 1,
    updated_by = v_actor,
    updated_by_email = public.current_actor_email(),
    updated_at = now()
  returning * into v_row;

  update public.pdc_online_state_revision
  set revision = revision + 1, updated_at = now()
  where singleton returning revision into v_revision;

  perform public.audit_pdc_event(
    'reference_change',
    'pdc_online_operational_state',
    null,
    null,
    jsonb_build_object('state_key', v_key, 'version', p_expected_version),
    jsonb_build_object('state_key', v_key, 'version', v_row.version),
    jsonb_build_object('authority', 'supabase_online_only', 'revision', v_revision)
  );

  v_response := jsonb_build_object(
    'ok', true,
    'state_key', v_key,
    'payload', v_payload,
    'version', v_row.version,
    'revision', v_revision,
    'authority', 'supabase_online_only'
  );
  insert into public.pdc_online_state_receipts(
    idempotency_key, state_key, request_hash, response, actor_id
  ) values (v_idempotency, v_key, v_request_hash, v_response, v_actor);
  return v_response;
end;
$save$;

revoke all on function public.get_pdc_online_state_snapshot() from public, anon, authenticated;
grant execute on function public.get_pdc_online_state_snapshot() to authenticated;
revoke all on function public.save_pdc_online_state(text,jsonb,bigint,text) from public, anon, authenticated;
grant execute on function public.save_pdc_online_state(text,jsonb,bigint,text) to authenticated;

comment on function public.get_pdc_online_state_snapshot() is
  'Authenticated online-only operational state snapshot. No browser fallback.';
comment on function public.save_pdc_online_state(text,jsonb,bigint,text) is
  'Optimistic, idempotent, audited online-only operational state update; manual vehicles are canonicalized atomically.';

do $publication$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename = 'pdc_online_state_revision'
  ) then
    alter publication supabase_realtime add table public.pdc_online_state_revision;
  end if;
end;
$publication$;

commit;
