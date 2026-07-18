-- Stage 2B protected vehicle-master operations.
-- Additive only: this migration does not import real vehicles, change browser
-- authority, retire authenticated table SELECT, or alter existing consumers.

begin;

create table if not exists public.vehicle_master_operation_receipts (
  id uuid primary key default gen_random_uuid(),
  operation_kind text not null check (operation_kind in ('import_apply', 'manual_edit')),
  scope_key text not null,
  idempotency_key text not null,
  request_hash text not null,
  vehicle_id uuid references public.vehicles(id) on delete set null,
  response jsonb not null,
  actor_id uuid references auth.users(id) on delete set null,
  actor_email text,
  created_at timestamptz not null default now(),
  unique (operation_kind, scope_key, idempotency_key)
);

create index if not exists vehicle_master_operation_receipts_vehicle_idx
  on public.vehicle_master_operation_receipts (vehicle_id, created_at desc);

alter table public.vehicle_master_operation_receipts enable row level security;
revoke all on table public.vehicle_master_operation_receipts from public, anon, authenticated;

create or replace function public.sanitize_vehicle_master_changes(p_payload jsonb)
returns jsonb
language plpgsql
immutable
set search_path = public
as $$
declare
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_allowed constant text[] := array[
    'permanent_vehicle_id', 'stock_number', 'vin', 'toyota_order_number',
    'job_card_number', 'key_number', 'customer_name', 'vehicle_description',
    'salesperson_id', 'salesperson_reference', 'make', 'model', 'registration',
    'eta_to_kewdale', 'arrival_reference_date'
  ];
  v_unknown text[];
  v_result jsonb := '{}'::jsonb;
begin
  if jsonb_typeof(v_payload) <> 'object' then
    raise exception 'vehicle payload must be a JSON object' using errcode = '22023';
  end if;

  select coalesce(array_agg(key order by key), '{}'::text[])
  into v_unknown
  from jsonb_object_keys(v_payload) key
  where not (key = any(v_allowed));

  if cardinality(v_unknown) > 0 then
    raise exception 'unsupported vehicle fields: %', array_to_string(v_unknown, ', ')
      using errcode = '22023';
  end if;

  if v_payload ? 'permanent_vehicle_id' then
    v_result := v_result || jsonb_build_object('permanent_vehicle_id', nullif(btrim(v_payload ->> 'permanent_vehicle_id'), ''));
  end if;
  if v_payload ? 'stock_number' then
    v_result := v_result || jsonb_build_object('stock_number', nullif(btrim(v_payload ->> 'stock_number'), ''));
  end if;
  if v_payload ? 'vin' then
    v_result := v_result || jsonb_build_object('vin', nullif(upper(btrim(v_payload ->> 'vin')), ''));
  end if;
  if v_payload ? 'toyota_order_number' then
    v_result := v_result || jsonb_build_object('toyota_order_number', nullif(btrim(v_payload ->> 'toyota_order_number'), ''));
  end if;
  if v_payload ? 'job_card_number' then
    v_result := v_result || jsonb_build_object('job_card_number', nullif(btrim(v_payload ->> 'job_card_number'), ''));
  end if;
  if v_payload ? 'key_number' then
    v_result := v_result || jsonb_build_object('key_number', nullif(btrim(v_payload ->> 'key_number'), ''));
  end if;
  if v_payload ? 'customer_name' then
    v_result := v_result || jsonb_build_object('customer_name', nullif(btrim(v_payload ->> 'customer_name'), ''));
  end if;
  if v_payload ? 'vehicle_description' then
    v_result := v_result || jsonb_build_object('vehicle_description', nullif(btrim(v_payload ->> 'vehicle_description'), ''));
  end if;
  if v_payload ? 'salesperson_id' then
    v_result := v_result || jsonb_build_object(
      'salesperson_id', case when nullif(btrim(v_payload ->> 'salesperson_id'), '') is null
        then null else (btrim(v_payload ->> 'salesperson_id'))::uuid end
    );
  end if;
  if v_payload ? 'salesperson_reference' then
    v_result := v_result || jsonb_build_object('salesperson_reference', nullif(btrim(v_payload ->> 'salesperson_reference'), ''));
  end if;
  if v_payload ? 'make' then
    v_result := v_result || jsonb_build_object('make', nullif(btrim(v_payload ->> 'make'), ''));
  end if;
  if v_payload ? 'model' then
    v_result := v_result || jsonb_build_object('model', nullif(btrim(v_payload ->> 'model'), ''));
  end if;
  if v_payload ? 'registration' then
    v_result := v_result || jsonb_build_object('registration', nullif(upper(btrim(v_payload ->> 'registration')), ''));
  end if;
  if v_payload ? 'eta_to_kewdale' then
    v_result := v_result || jsonb_build_object(
      'eta_to_kewdale', case when nullif(btrim(v_payload ->> 'eta_to_kewdale'), '') is null
        then null else (btrim(v_payload ->> 'eta_to_kewdale'))::date end
    );
  end if;
  if v_payload ? 'arrival_reference_date' then
    v_result := v_result || jsonb_build_object(
      'arrival_reference_date', case when nullif(btrim(v_payload ->> 'arrival_reference_date'), '') is null
        then null else (btrim(v_payload ->> 'arrival_reference_date'))::date end
    );
  end if;

  return v_result;
end;
$$;

create or replace function public.vehicle_master_operation_hash(
  p_operation text,
  p_scope text,
  p_source_batch_id text,
  p_source_record_id text,
  p_payload jsonb,
  p_expected_version integer
)
returns text
language sql
immutable
parallel safe
as $$
  select encode(extensions.digest(jsonb_build_object(
    'operation', coalesce(p_operation, ''),
    'scope', coalesce(p_scope, ''),
    'source_batch_id', nullif(btrim(p_source_batch_id), ''),
    'source_record_id', nullif(btrim(p_source_record_id), ''),
    'payload', coalesce(p_payload, '{}'::jsonb),
    'expected_version', p_expected_version
  )::text, 'sha256'), 'hex');
$$;

create or replace function public.vehicle_master_import_match(
  p_source_system text,
  p_source_record_id text,
  p_payload jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_source text := public.normalize_vehicle_source_system(p_source_system);
  v_record text := public.normalize_vehicle_source_identifier(p_source_record_id);
  v_changes jsonb;
  v_vin text;
  v_stock text;
  v_job text;
  v_order text;
  v_permanent text;
  v_vin_candidates uuid[] := '{}'::uuid[];
  v_stock_candidates uuid[] := '{}'::uuid[];
  v_source_candidates uuid[] := '{}'::uuid[];
  v_job_candidates uuid[] := '{}'::uuid[];
  v_order_candidates uuid[] := '{}'::uuid[];
  v_permanent_candidates uuid[] := '{}'::uuid[];
  v_all_candidates uuid[] := '{}'::uuid[];
  v_vehicle_id uuid;
  v_before jsonb;
  v_proposed jsonb;
  v_action text;
  v_changed boolean := false;
  v_generated_permanent text;
  v_orphaned_source_evidence integer := 0;
begin
  if v_source is null or v_record is null then
    return public.vehicle_master_response(false, 'invalid_source', jsonb_build_object(
      'fields', jsonb_build_array('source_system', 'source_record_id')
    ));
  end if;

  begin
    v_changes := public.sanitize_vehicle_master_changes(p_payload);
  exception when others then
    return public.vehicle_master_response(false, 'invalid_payload', jsonb_build_object('message', sqlerrm));
  end;

  v_vin := nullif(v_changes ->> 'vin', '');
  if v_vin is not null and not public.is_valid_vehicle_vin(v_vin) then
    return public.vehicle_master_response(false, 'invalid_value', jsonb_build_object('field', 'vin'));
  end if;

  select count(*) into v_orphaned_source_evidence
  from public.vehicle_master_source_records sr
  where sr.vehicle_id is null
    and public.normalize_vehicle_source_system(sr.source_system) = v_source
    and public.normalize_vehicle_source_identifier(sr.source_record_id) = v_record;
  if v_orphaned_source_evidence > 0 then
    return public.vehicle_master_response(false, 'unlinked_source_evidence', jsonb_build_object(
      'source_system', v_source,
      'source_record_id', v_record,
      'evidence_count', v_orphaned_source_evidence
    ));
  end if;

  if v_vin is not null then
    v_vin := public.normalize_vehicle_vin(v_vin);
    select coalesce(array_agg(distinct id order by id), '{}'::uuid[]) into v_vin_candidates
    from (
      select v.id
      from public.vehicles v
      where public.is_valid_vehicle_vin(v.vin) and v.vin_normalized = v_vin
      union
      select a.vehicle_id
      from public.vehicle_aliases a
      where a.active and a.alias_type_normalized = 'vin' and a.normalized_alias_value = v_vin
    ) matches;
  end if;

  v_stock := public.normalize_vehicle_stock_number(v_changes ->> 'stock_number');
  if v_stock is not null and public.is_real_vehicle_stock_number(v_changes ->> 'stock_number') then
    select coalesce(array_agg(distinct id order by id), '{}'::uuid[]) into v_stock_candidates
    from (
      select v.id from public.vehicles v where v.stock_number_normalized = v_stock
      union
      select a.vehicle_id from public.vehicle_aliases a
      where a.active and a.alias_type_normalized = 'stock_number' and a.normalized_alias_value = v_stock
    ) matches;
  end if;

  select coalesce(array_agg(distinct id order by id), '{}'::uuid[]) into v_source_candidates
  from (
    select v.id from public.vehicles v
    where v.source_system_normalized = v_source and v.source_record_id_normalized = v_record
    union
    select a.vehicle_id from public.vehicle_aliases a
    where a.active and a.source_system_normalized = v_source
      and a.alias_type_normalized = 'source_record_id' and a.normalized_alias_value = v_record
    union
    select sr.vehicle_id from public.vehicle_master_source_records sr
    where sr.vehicle_id is not null
      and public.normalize_vehicle_source_system(sr.source_system) = v_source
      and public.normalize_vehicle_source_identifier(sr.source_record_id) = v_record
  ) matches;

  v_job := public.normalize_vehicle_source_identifier(v_changes ->> 'job_card_number');
  if v_job is not null then
    select coalesce(array_agg(distinct id order by id), '{}'::uuid[]) into v_job_candidates
    from (
      select v.id from public.vehicles v
      where v.source_system_normalized = v_source
        and public.normalize_vehicle_source_identifier(v.job_card_number) = v_job
      union
      select a.vehicle_id from public.vehicle_aliases a
      where a.active and a.source_system_normalized = v_source
        and a.alias_type_normalized = 'job_card_number' and a.normalized_alias_value = v_job
    ) matches;
  end if;

  v_order := public.normalize_vehicle_source_identifier(v_changes ->> 'toyota_order_number');
  if v_order is not null then
    select coalesce(array_agg(distinct id order by id), '{}'::uuid[]) into v_order_candidates
    from (
      select v.id from public.vehicles v
      where v.source_system_normalized = v_source
        and public.normalize_vehicle_source_identifier(v.toyota_order_number) = v_order
      union
      select a.vehicle_id from public.vehicle_aliases a
      where a.active and a.source_system_normalized = v_source
        and a.alias_type_normalized = 'toyota_order_number' and a.normalized_alias_value = v_order
    ) matches;
  end if;

  v_permanent := public.normalize_vehicle_source_identifier(v_changes ->> 'permanent_vehicle_id');
  if v_permanent is not null then
    select coalesce(array_agg(v.id order by v.id), '{}'::uuid[]) into v_permanent_candidates
    from public.vehicles v
    where public.normalize_vehicle_source_identifier(v.permanent_vehicle_id) = v_permanent;
  end if;

  if cardinality(v_vin_candidates) > 1
     or cardinality(v_stock_candidates) > 1
     or cardinality(v_source_candidates) > 1
     or cardinality(v_job_candidates) > 1
     or cardinality(v_order_candidates) > 1
     or cardinality(v_permanent_candidates) > 1 then
    return public.vehicle_master_response(false, 'ambiguous_match', jsonb_build_object(
      'candidate_sets', jsonb_build_object(
        'vin', to_jsonb(v_vin_candidates), 'stock_number', to_jsonb(v_stock_candidates),
        'source_record_id', to_jsonb(v_source_candidates), 'job_card_number', to_jsonb(v_job_candidates),
        'toyota_order_number', to_jsonb(v_order_candidates), 'permanent_vehicle_id', to_jsonb(v_permanent_candidates)
      )
    ));
  end if;

  select coalesce(array_agg(distinct id order by id), '{}'::uuid[]) into v_all_candidates
  from unnest(
    v_vin_candidates || v_stock_candidates || v_source_candidates ||
    v_job_candidates || v_order_candidates || v_permanent_candidates
  ) id;

  if cardinality(v_all_candidates) > 1 then
    return public.vehicle_master_response(false, 'conflicting_match', jsonb_build_object(
      'candidate_ids', to_jsonb(v_all_candidates),
      'candidate_sets', jsonb_build_object(
        'vin', to_jsonb(v_vin_candidates), 'stock_number', to_jsonb(v_stock_candidates),
        'source_record_id', to_jsonb(v_source_candidates), 'job_card_number', to_jsonb(v_job_candidates),
        'toyota_order_number', to_jsonb(v_order_candidates), 'permanent_vehicle_id', to_jsonb(v_permanent_candidates)
      )
    ));
  end if;

  if cardinality(v_all_candidates) = 0 then
    v_vehicle_id := (
      substr(md5('stage2b-vehicle:' || v_source || ':' || v_record), 1, 8) || '-' ||
      substr(md5('stage2b-vehicle:' || v_source || ':' || v_record), 9, 4) || '-4' ||
      substr(md5('stage2b-vehicle:' || v_source || ':' || v_record), 14, 3) || '-a' ||
      substr(md5('stage2b-vehicle:' || v_source || ':' || v_record), 18, 3) || '-' ||
      substr(md5('stage2b-vehicle:' || v_source || ':' || v_record), 21, 12)
    )::uuid;
    v_generated_permanent := coalesce(
      nullif(v_changes ->> 'permanent_vehicle_id', ''),
      'S2B:' || upper(v_source) || ':' || v_record
    );
    v_proposed := jsonb_build_object(
      'id', v_vehicle_id,
      'permanent_vehicle_id', v_generated_permanent,
      'source_system', nullif(btrim(p_source_system), ''),
      'source_record_id', nullif(btrim(p_source_record_id), ''),
      'version', 1
    ) || v_changes;
    v_action := 'insert';
  else
    v_vehicle_id := v_all_candidates[1];
    select public.vehicle_master_core_audit_json(v) into v_before
    from public.vehicles v where v.id = v_vehicle_id;

    select exists (
      select 1 from jsonb_each(v_changes) change
      where v_before -> change.key is distinct from change.value
    ) into v_changed;

    v_action := case when v_changed then 'update' else 'no_change' end;
    v_proposed := v_before || v_changes || jsonb_build_object(
      'version', case when v_changed then (v_before ->> 'version')::integer + 1 else (v_before ->> 'version')::integer end
    );
  end if;

  return public.vehicle_master_response(true, 'ok', jsonb_build_object(
    'action', v_action,
    'vehicle_id', v_vehicle_id,
    'expected_version', case when v_before is null then null else (v_before ->> 'version')::integer end,
    'before', v_before,
    'proposed', v_proposed,
    'changes', v_changes,
    'normalized_source_system', v_source,
    'normalized_source_record_id', v_record,
    'candidate_ids', to_jsonb(v_all_candidates),
    'candidate_sets', jsonb_build_object(
      'vin', to_jsonb(v_vin_candidates), 'stock_number', to_jsonb(v_stock_candidates),
      'source_record_id', to_jsonb(v_source_candidates), 'job_card_number', to_jsonb(v_job_candidates),
      'toyota_order_number', to_jsonb(v_order_candidates), 'permanent_vehicle_id', to_jsonb(v_permanent_candidates)
    )
  ));
end;
$$;

create or replace function public.ensure_vehicle_master_alias(
  p_vehicle_id uuid,
  p_alias_type text,
  p_alias_value text,
  p_source_system text default null,
  p_source_batch_id text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_type text := lower(nullif(btrim(p_alias_type), ''));
  v_value text := public.normalize_vehicle_alias_value(p_alias_type, p_alias_value);
  v_source text := public.normalize_vehicle_source_system(p_source_system);
  v_alias_id uuid;
begin
  if p_vehicle_id is null or v_type is null or v_value is null then
    return null;
  end if;

  select a.id into v_alias_id
  from public.vehicle_aliases a
  where a.vehicle_id = p_vehicle_id and a.active
    and a.alias_type_normalized = v_type
    and a.normalized_alias_value = v_value
    and (v_type in ('vin', 'stock_number') or a.source_system_normalized is not distinct from v_source)
  order by a.created_at, a.id;

  if v_alias_id is not null then
    return v_alias_id;
  end if;

  insert into public.vehicle_aliases (
    vehicle_id, alias_type, alias_value, active, source_system, source_batch_id,
    created_by, updated_by
  ) values (
    p_vehicle_id, v_type, nullif(btrim(p_alias_value), ''), true,
    nullif(btrim(p_source_system), ''), nullif(btrim(p_source_batch_id), ''),
    auth.uid(), auth.uid()
  ) returning id into v_alias_id;

  return v_alias_id;
end;
$$;

create or replace function public.retain_vehicle_master_source_record(
  p_vehicle_id uuid,
  p_source_system text,
  p_source_batch_id text,
  p_source_record_id text,
  p_source_metadata jsonb,
  p_original_evidence jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_source text := public.normalize_vehicle_source_system(p_source_system);
  v_record text := public.normalize_vehicle_source_identifier(p_source_record_id);
  v_id uuid;
  v_other_vehicle uuid;
begin
  if v_source is null or v_record is null then
    raise exception 'source system and record id are required' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('vehicle-master:source-evidence:' || v_source || ':' || v_record, 0));

  select sr.vehicle_id into v_other_vehicle
  from public.vehicle_master_source_records sr
  where public.normalize_vehicle_source_system(sr.source_system) = v_source
    and public.normalize_vehicle_source_identifier(sr.source_record_id) = v_record
    and sr.vehicle_id is not null and sr.vehicle_id <> p_vehicle_id
  order by sr.created_at
  limit 1;

  if v_other_vehicle is not null then
    raise exception 'source record belongs to another vehicle'
      using errcode = '23505', detail = public.vehicle_master_response(
        false, 'conflicting_match', jsonb_build_object('vehicle_id', v_other_vehicle)
      )::text;
  end if;

  select sr.id into v_id
  from public.vehicle_master_source_records sr
  where sr.vehicle_id = p_vehicle_id
    and public.normalize_vehicle_source_system(sr.source_system) = v_source
    and public.normalize_vehicle_source_identifier(sr.source_record_id) = v_record
  order by sr.created_at
  limit 1
  for update;

  if v_id is null then
    insert into public.vehicle_master_source_records (
      vehicle_id, source_system, source_batch_id, source_record_id,
      source_metadata, original_evidence, created_by, updated_by
    ) values (
      p_vehicle_id, nullif(btrim(p_source_system), ''), nullif(btrim(p_source_batch_id), ''),
      nullif(btrim(p_source_record_id), ''), coalesce(p_source_metadata, '{}'::jsonb),
      coalesce(p_original_evidence, '{}'::jsonb), auth.uid(), auth.uid()
    ) returning id into v_id;
  else
    update public.vehicle_master_source_records
    set source_batch_id = coalesce(nullif(btrim(p_source_batch_id), ''), source_batch_id),
        source_metadata = source_metadata || coalesce(p_source_metadata, '{}'::jsonb)
          || jsonb_build_object('latest_evidence', coalesce(p_original_evidence, '{}'::jsonb)),
        version = version + 1,
        updated_by = auth.uid()
    where id = v_id
      and (
        source_batch_id is distinct from coalesce(nullif(btrim(p_source_batch_id), ''), source_batch_id)
        or not (source_metadata @> coalesce(p_source_metadata, '{}'::jsonb))
        or source_metadata -> 'latest_evidence' is distinct from coalesce(p_original_evidence, '{}'::jsonb)
      );
  end if;

  return v_id;
end;
$$;

create or replace function public.preview_vehicle_master_import(
  p_source_system text,
  p_source_batch_id text,
  p_source_record_id text,
  p_payload jsonb,
  p_expected_version integer default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_match jsonb;
  v_current_version integer;
  v_hash text;
begin
  perform public.require_pdc_role('importer');

  v_match := public.vehicle_master_import_match(p_source_system, p_source_record_id, p_payload);
  if not coalesce((v_match ->> 'ok')::boolean, false) then
    return v_match;
  end if;

  v_current_version := nullif(v_match #>> '{data,expected_version}', '')::integer;
  if v_current_version is not null and p_expected_version is not null and p_expected_version <> v_current_version then
    return public.vehicle_master_response(false, 'stale_version', jsonb_build_object(
      'expected_version', p_expected_version,
      'current_version', v_current_version,
      'vehicle_id', v_match #>> '{data,vehicle_id}'
    ));
  end if;

  v_hash := public.vehicle_master_operation_hash(
    'import_apply', public.normalize_vehicle_source_system(p_source_system),
    p_source_batch_id, p_source_record_id, p_payload, p_expected_version
  );

  return jsonb_set(v_match, '{data,request_fingerprint}', to_jsonb(v_hash), true);
end;
$$;

create or replace function public.upsert_vehicle_master_import(
  p_source_system text,
  p_source_batch_id text,
  p_source_record_id text,
  p_payload jsonb,
  p_expected_version integer,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_scope text := public.normalize_vehicle_source_system(p_source_system);
  v_key text := nullif(btrim(p_idempotency_key), '');
  v_hash text;
  v_receipt public.vehicle_master_operation_receipts%rowtype;
  v_preview jsonb;
  v_data jsonb;
  v_changes jsonb;
  v_action text;
  v_vehicle_id uuid;
  v_before public.vehicles%rowtype;
  v_after public.vehicles%rowtype;
  v_old_stock text;
  v_old_vin text;
  v_old_job text;
  v_old_order text;
  v_response jsonb;
begin
  perform public.require_pdc_role('importer');

  if v_scope is null or public.normalize_vehicle_source_identifier(p_source_record_id) is null or v_key is null then
    return public.vehicle_master_response(false, 'invalid_request', jsonb_build_object(
      'required', jsonb_build_array('source_system', 'source_record_id', 'idempotency_key')
    ));
  end if;

  v_hash := public.vehicle_master_operation_hash(
    'import_apply', v_scope, p_source_batch_id, p_source_record_id, p_payload, p_expected_version
  );
  perform pg_advisory_xact_lock(hashtextextended('vehicle-master:receipt:import_apply:' || v_scope || ':' || v_key, 0));

  select * into v_receipt
  from public.vehicle_master_operation_receipts
  where operation_kind = 'import_apply' and scope_key = v_scope and idempotency_key = v_key;

  if found then
    if v_receipt.request_hash <> v_hash then
      return public.vehicle_master_response(false, 'idempotency_conflict', jsonb_build_object(
        'receipt_id', v_receipt.id, 'vehicle_id', v_receipt.vehicle_id
      ));
    end if;
    return v_receipt.response;
  end if;

  v_preview := public.preview_vehicle_master_import(
    p_source_system, p_source_batch_id, p_source_record_id, p_payload, p_expected_version
  );
  if not coalesce((v_preview ->> 'ok')::boolean, false) then
    return v_preview;
  end if;

  v_data := v_preview -> 'data';
  v_changes := v_data -> 'changes';
  v_action := v_data ->> 'action';
  v_vehicle_id := (v_data ->> 'vehicle_id')::uuid;

  if v_action = 'insert' then
    insert into public.vehicles (
      id, permanent_vehicle_id, stock_number, vin, toyota_order_number,
      job_card_number, key_number, customer_name, vehicle_description,
      salesperson_id, salesperson_reference, make, model, registration,
      eta_to_kewdale, arrival_reference_date,
      source_system, source_batch_id, source_record_id, created_by, updated_by
    ) values (
      v_vehicle_id,
      coalesce(nullif(v_changes ->> 'permanent_vehicle_id', ''), v_data #>> '{proposed,permanent_vehicle_id}'),
      v_changes ->> 'stock_number', v_changes ->> 'vin', v_changes ->> 'toyota_order_number',
      v_changes ->> 'job_card_number', v_changes ->> 'key_number', v_changes ->> 'customer_name',
      v_changes ->> 'vehicle_description', nullif(v_changes ->> 'salesperson_id', '')::uuid,
      v_changes ->> 'salesperson_reference', v_changes ->> 'make', v_changes ->> 'model',
      v_changes ->> 'registration', nullif(v_changes ->> 'eta_to_kewdale', '')::date,
      nullif(v_changes ->> 'arrival_reference_date', '')::date,
      nullif(btrim(p_source_system), ''), nullif(btrim(p_source_batch_id), ''),
      nullif(btrim(p_source_record_id), ''), auth.uid(), auth.uid()
    ) returning * into v_after;
  else
    select * into v_before from public.vehicles where id = v_vehicle_id for update;
    if not found or p_expected_version is null or v_before.version <> p_expected_version then
      return public.vehicle_master_response(false, 'stale_version', jsonb_build_object(
        'vehicle_id', v_vehicle_id, 'expected_version', p_expected_version,
        'current_version', case when v_before.id is null then null else v_before.version end
      ));
    end if;

    if v_action = 'update' then
      v_old_stock := v_before.stock_number;
      v_old_vin := v_before.vin;
      v_old_job := v_before.job_card_number;
      v_old_order := v_before.toyota_order_number;

      update public.vehicles set
        permanent_vehicle_id = case when v_changes ? 'permanent_vehicle_id' then v_changes ->> 'permanent_vehicle_id' else permanent_vehicle_id end,
        stock_number = case when v_changes ? 'stock_number' then v_changes ->> 'stock_number' else stock_number end,
        vin = case when v_changes ? 'vin' then v_changes ->> 'vin' else vin end,
        toyota_order_number = case when v_changes ? 'toyota_order_number' then v_changes ->> 'toyota_order_number' else toyota_order_number end,
        job_card_number = case when v_changes ? 'job_card_number' then v_changes ->> 'job_card_number' else job_card_number end,
        key_number = case when v_changes ? 'key_number' then v_changes ->> 'key_number' else key_number end,
        customer_name = case when v_changes ? 'customer_name' then v_changes ->> 'customer_name' else customer_name end,
        vehicle_description = case when v_changes ? 'vehicle_description' then v_changes ->> 'vehicle_description' else vehicle_description end,
        salesperson_id = case when v_changes ? 'salesperson_id' then nullif(v_changes ->> 'salesperson_id', '')::uuid else salesperson_id end,
        salesperson_reference = case when v_changes ? 'salesperson_reference' then v_changes ->> 'salesperson_reference' else salesperson_reference end,
        make = case when v_changes ? 'make' then v_changes ->> 'make' else make end,
        model = case when v_changes ? 'model' then v_changes ->> 'model' else model end,
        registration = case when v_changes ? 'registration' then v_changes ->> 'registration' else registration end,
        eta_to_kewdale = case when v_changes ? 'eta_to_kewdale' then nullif(v_changes ->> 'eta_to_kewdale', '')::date else eta_to_kewdale end,
        arrival_reference_date = case when v_changes ? 'arrival_reference_date' then nullif(v_changes ->> 'arrival_reference_date', '')::date else arrival_reference_date end,
        version = version + 1,
        updated_by = auth.uid()
      where id = v_vehicle_id and version = p_expected_version
      returning * into v_after;

      if not found then
        return public.vehicle_master_response(false, 'stale_version', jsonb_build_object('vehicle_id', v_vehicle_id));
      end if;

      if v_old_stock is distinct from v_after.stock_number then
        perform public.ensure_vehicle_master_alias(v_vehicle_id, 'stock_number', v_old_stock, p_source_system, p_source_batch_id);
      end if;
      if v_old_vin is distinct from v_after.vin then
        perform public.ensure_vehicle_master_alias(v_vehicle_id, 'vin', v_old_vin, p_source_system, p_source_batch_id);
      end if;
      if v_old_job is distinct from v_after.job_card_number then
        perform public.ensure_vehicle_master_alias(v_vehicle_id, 'job_card_number', v_old_job, p_source_system, p_source_batch_id);
      end if;
      if v_old_order is distinct from v_after.toyota_order_number then
        perform public.ensure_vehicle_master_alias(v_vehicle_id, 'toyota_order_number', v_old_order, p_source_system, p_source_batch_id);
      end if;
    else
      v_after := v_before;
    end if;
  end if;

  perform public.ensure_vehicle_master_alias(v_vehicle_id, 'source_record_id', p_source_record_id, p_source_system, p_source_batch_id);
  perform public.ensure_vehicle_master_alias(v_vehicle_id, 'job_card_number', v_changes ->> 'job_card_number', p_source_system, p_source_batch_id);
  perform public.ensure_vehicle_master_alias(v_vehicle_id, 'toyota_order_number', v_changes ->> 'toyota_order_number', p_source_system, p_source_batch_id);

  perform public.retain_vehicle_master_source_record(
    v_vehicle_id, p_source_system, p_source_batch_id, p_source_record_id,
    jsonb_build_object('operation', 'import_apply', 'idempotency_key', v_key, 'request_hash', v_hash),
    coalesce(p_payload, '{}'::jsonb)
  );

  perform public.audit_pdc_event(
    'import', 'vehicles', v_vehicle_id, v_vehicle_id,
    case when v_before.id is null then null else public.vehicle_master_core_audit_json(v_before) end,
    public.vehicle_master_core_audit_json(v_after),
    jsonb_build_object(
      'stage', 'stage2b_029', 'source_system', v_scope,
      'source_record_id', public.normalize_vehicle_source_identifier(p_source_record_id),
      'idempotency_key', v_key, 'request_hash', v_hash, 'action', v_action
    )
  );

  v_response := public.vehicle_master_response(true, 'applied', jsonb_build_object(
    'action', v_action,
    'vehicle_id', v_vehicle_id,
    'version', v_after.version,
    'request_fingerprint', v_hash,
    'preview', v_data,
    'vehicle', public.vehicle_master_core_audit_json(v_after)
  ));

  insert into public.vehicle_master_operation_receipts (
    operation_kind, scope_key, idempotency_key, request_hash,
    vehicle_id, response, actor_id, actor_email
  ) values (
    'import_apply', v_scope, v_key, v_hash,
    v_vehicle_id, v_response, auth.uid(), public.current_actor_email()
  );

  return v_response;
exception
  when unique_violation then
    return public.vehicle_master_response(false, 'identifier_conflict', jsonb_build_object('message', sqlerrm));
  when check_violation or invalid_text_representation or datetime_field_overflow then
    return public.vehicle_master_response(false, 'invalid_value', jsonb_build_object('message', sqlerrm));
end;
$$;

create or replace function public.apply_vehicle_master_import(
  p_source_system text,
  p_source_batch_id text,
  p_source_record_id text,
  p_payload jsonb,
  p_expected_version integer,
  p_idempotency_key text
)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select public.upsert_vehicle_master_import(
    p_source_system, p_source_batch_id, p_source_record_id,
    p_payload, p_expected_version, p_idempotency_key
  );
$$;

create or replace function public.edit_vehicle_master(
  p_vehicle_id uuid,
  p_expected_version integer,
  p_changes jsonb,
  p_reason text,
  p_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_scope text := p_vehicle_id::text;
  v_key text := nullif(btrim(p_idempotency_key), '');
  v_hash text;
  v_receipt public.vehicle_master_operation_receipts%rowtype;
  v_changes jsonb;
  v_before public.vehicles%rowtype;
  v_after public.vehicles%rowtype;
  v_old_stock text;
  v_old_vin text;
  v_old_job text;
  v_old_order text;
  v_changed boolean;
  v_response jsonb;
begin
  perform public.require_pdc_role('operator');

  if p_vehicle_id is null or p_expected_version is null or v_key is null or nullif(btrim(p_reason), '') is null then
    return public.vehicle_master_response(false, 'invalid_request', jsonb_build_object(
      'required', jsonb_build_array('vehicle_id', 'expected_version', 'reason', 'idempotency_key')
    ));
  end if;

  begin
    v_changes := public.sanitize_vehicle_master_changes(p_changes);
  exception when others then
    return public.vehicle_master_response(false, 'invalid_payload', jsonb_build_object('message', sqlerrm));
  end;

  if nullif(v_changes ->> 'vin', '') is not null and not public.is_valid_vehicle_vin(v_changes ->> 'vin') then
    return public.vehicle_master_response(false, 'invalid_value', jsonb_build_object('field', 'vin'));
  end if;

  v_hash := public.vehicle_master_operation_hash(
    'manual_edit', v_scope, null, v_key,
    jsonb_build_object('changes', v_changes, 'reason', btrim(p_reason)), p_expected_version
  );
  perform pg_advisory_xact_lock(hashtextextended('vehicle-master:receipt:manual_edit:' || v_scope || ':' || v_key, 0));

  select * into v_receipt from public.vehicle_master_operation_receipts
  where operation_kind = 'manual_edit' and scope_key = v_scope and idempotency_key = v_key;

  if found then
    if v_receipt.request_hash <> v_hash then
      return public.vehicle_master_response(false, 'idempotency_conflict', jsonb_build_object(
        'receipt_id', v_receipt.id, 'vehicle_id', v_receipt.vehicle_id
      ));
    end if;
    return v_receipt.response;
  end if;

  select * into v_before from public.vehicles where id = p_vehicle_id for update;
  if not found then
    return public.vehicle_master_response(false, 'not_found', jsonb_build_object('vehicle_id', p_vehicle_id));
  end if;
  if v_before.version <> p_expected_version then
    return public.vehicle_master_response(false, 'stale_version', jsonb_build_object(
      'vehicle_id', p_vehicle_id, 'expected_version', p_expected_version, 'current_version', v_before.version
    ));
  end if;

  select exists (
    select 1 from jsonb_each(v_changes) change
    where public.vehicle_master_core_audit_json(v_before) -> change.key is distinct from change.value
  ) into v_changed;

  if v_changed then
    v_old_stock := v_before.stock_number;
    v_old_vin := v_before.vin;
    v_old_job := v_before.job_card_number;
    v_old_order := v_before.toyota_order_number;

    update public.vehicles set
      permanent_vehicle_id = case when v_changes ? 'permanent_vehicle_id' then v_changes ->> 'permanent_vehicle_id' else permanent_vehicle_id end,
      stock_number = case when v_changes ? 'stock_number' then v_changes ->> 'stock_number' else stock_number end,
      vin = case when v_changes ? 'vin' then v_changes ->> 'vin' else vin end,
      toyota_order_number = case when v_changes ? 'toyota_order_number' then v_changes ->> 'toyota_order_number' else toyota_order_number end,
      job_card_number = case when v_changes ? 'job_card_number' then v_changes ->> 'job_card_number' else job_card_number end,
      key_number = case when v_changes ? 'key_number' then v_changes ->> 'key_number' else key_number end,
      customer_name = case when v_changes ? 'customer_name' then v_changes ->> 'customer_name' else customer_name end,
      vehicle_description = case when v_changes ? 'vehicle_description' then v_changes ->> 'vehicle_description' else vehicle_description end,
      salesperson_id = case when v_changes ? 'salesperson_id' then nullif(v_changes ->> 'salesperson_id', '')::uuid else salesperson_id end,
      salesperson_reference = case when v_changes ? 'salesperson_reference' then v_changes ->> 'salesperson_reference' else salesperson_reference end,
      make = case when v_changes ? 'make' then v_changes ->> 'make' else make end,
      model = case when v_changes ? 'model' then v_changes ->> 'model' else model end,
      registration = case when v_changes ? 'registration' then v_changes ->> 'registration' else registration end,
      eta_to_kewdale = case when v_changes ? 'eta_to_kewdale' then nullif(v_changes ->> 'eta_to_kewdale', '')::date else eta_to_kewdale end,
      arrival_reference_date = case when v_changes ? 'arrival_reference_date' then nullif(v_changes ->> 'arrival_reference_date', '')::date else arrival_reference_date end,
      version = version + 1,
      updated_by = auth.uid()
    where id = p_vehicle_id and version = p_expected_version
    returning * into v_after;

    if not found then
      return public.vehicle_master_response(false, 'stale_version', jsonb_build_object('vehicle_id', p_vehicle_id));
    end if;

    if v_old_stock is distinct from v_after.stock_number then
      perform public.ensure_vehicle_master_alias(p_vehicle_id, 'stock_number', v_old_stock, 'manual_edit', null);
    end if;
    if v_old_vin is distinct from v_after.vin then
      perform public.ensure_vehicle_master_alias(p_vehicle_id, 'vin', v_old_vin, 'manual_edit', null);
    end if;
    if v_old_job is distinct from v_after.job_card_number then
      perform public.ensure_vehicle_master_alias(p_vehicle_id, 'job_card_number', v_old_job, 'manual_edit', null);
    end if;
    if v_old_order is distinct from v_after.toyota_order_number then
      perform public.ensure_vehicle_master_alias(p_vehicle_id, 'toyota_order_number', v_old_order, 'manual_edit', null);
    end if;
  else
    v_after := v_before;
  end if;

  perform public.retain_vehicle_master_source_record(
    p_vehicle_id, 'manual_edit', null, v_key,
    jsonb_build_object(
      'operation', 'manual_edit', 'reason', btrim(p_reason),
      'actor_email', public.current_actor_email(), 'request_hash', v_hash
    ),
    jsonb_build_object(
      'changes', v_changes,
      'before', public.vehicle_master_core_audit_json(v_before)
    )
  );

  perform public.audit_pdc_event(
    'update', 'vehicles', p_vehicle_id, p_vehicle_id,
    public.vehicle_master_core_audit_json(v_before), public.vehicle_master_core_audit_json(v_after),
    jsonb_build_object(
      'stage', 'stage2b_029', 'operation', 'manual_edit',
      'reason', btrim(p_reason), 'idempotency_key', v_key,
      'request_hash', v_hash, 'changed', v_changed
    )
  );

  v_response := public.vehicle_master_response(true, case when v_changed then 'updated' else 'no_change' end, jsonb_build_object(
    'vehicle_id', p_vehicle_id,
    'version', v_after.version,
    'request_fingerprint', v_hash,
    'changed', v_changed,
    'vehicle', public.vehicle_master_core_audit_json(v_after)
  ));

  insert into public.vehicle_master_operation_receipts (
    operation_kind, scope_key, idempotency_key, request_hash,
    vehicle_id, response, actor_id, actor_email
  ) values (
    'manual_edit', v_scope, v_key, v_hash,
    p_vehicle_id, v_response, auth.uid(), public.current_actor_email()
  );

  return v_response;
exception
  when unique_violation then
    return public.vehicle_master_response(false, 'identifier_conflict', jsonb_build_object('message', sqlerrm));
  when check_violation or invalid_text_representation or datetime_field_overflow then
    return public.vehicle_master_response(false, 'invalid_value', jsonb_build_object('message', sqlerrm));
end;
$$;

revoke all on function public.sanitize_vehicle_master_changes(jsonb) from public, anon, authenticated;
revoke all on function public.vehicle_master_operation_hash(text, text, text, text, jsonb, integer) from public, anon, authenticated;
revoke all on function public.vehicle_master_import_match(text, text, jsonb) from public, anon, authenticated;
revoke all on function public.ensure_vehicle_master_alias(uuid, text, text, text, text) from public, anon, authenticated;
revoke all on function public.retain_vehicle_master_source_record(uuid, text, text, text, jsonb, jsonb) from public, anon, authenticated;
revoke all on function public.preview_vehicle_master_import(text, text, text, jsonb, integer) from public, anon, authenticated;
revoke all on function public.upsert_vehicle_master_import(text, text, text, jsonb, integer, text) from public, anon, authenticated;
revoke all on function public.apply_vehicle_master_import(text, text, text, jsonb, integer, text) from public, anon, authenticated;
revoke all on function public.edit_vehicle_master(uuid, integer, jsonb, text, text) from public, anon, authenticated;

grant execute on function public.preview_vehicle_master_import(text, text, text, jsonb, integer) to authenticated;
grant execute on function public.upsert_vehicle_master_import(text, text, text, jsonb, integer, text) to authenticated;
grant execute on function public.apply_vehicle_master_import(text, text, text, jsonb, integer, text) to authenticated;
grant execute on function public.edit_vehicle_master(uuid, integer, jsonb, text, text) to authenticated;

commit;
