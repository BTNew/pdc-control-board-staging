-- Combined staging completion: dealer-scoped Navision reconciliation and ETA-safe future planning.
-- Staging-only additive migration; no browser-authority cutover.
alter table public.navision_import_batches add column if not exists source_system text;
alter table public.navision_import_batches add column if not exists dealer_code text;
alter table public.navision_backend_records add column if not exists source_system text;
alter table public.navision_backend_records add column if not exists dealer_code text;
alter table public.navision_backend_records add column if not exists record_status text;
update public.navision_import_batches set source_system='microsoft_navision', dealer_code='LEGACY_UNSCOPED' where source_system is null or dealer_code is null;
update public.navision_backend_records set source_system='microsoft_navision', dealer_code='LEGACY_UNSCOPED', record_status=case when is_current then 'current' else 'not_in_latest_batch' end where source_system is null or dealer_code is null or record_status is null;
alter table public.navision_import_batches alter column source_system set not null;
alter table public.navision_import_batches alter column dealer_code set not null;
alter table public.navision_backend_records alter column source_system set not null;
alter table public.navision_backend_records alter column dealer_code set not null;
alter table public.navision_backend_records alter column record_status set not null;
alter table public.navision_import_batches drop constraint if exists navision_import_batches_dealer_code_check;
alter table public.navision_import_batches add constraint navision_import_batches_dealer_code_check check (dealer_code in ('14450','37047','LEGACY_UNSCOPED'));
alter table public.navision_backend_records drop constraint if exists navision_backend_records_dealer_code_check;
alter table public.navision_backend_records add constraint navision_backend_records_dealer_code_check check (dealer_code in ('14450','37047','LEGACY_UNSCOPED'));
alter table public.navision_backend_records drop constraint if exists navision_backend_records_record_status_check;
alter table public.navision_backend_records add constraint navision_backend_records_record_status_check check (record_status in ('current','not_in_latest_batch','inactive'));
alter table public.navision_backend_records drop constraint if exists navision_backend_records_source_record_id_normalized_key;
drop index if exists public.navision_backend_records_source_record_id_normalized_key;
create unique index if not exists navision_backend_records_scope_source_id_uidx on public.navision_backend_records(source_system,dealer_code,source_record_id_normalized);
create index if not exists navision_backend_records_scope_status_idx on public.navision_backend_records(source_system,dealer_code,record_status,source_record_id_normalized);
revoke all on function public.preview_navision_backend_import(jsonb,text,timestamptz) from public,anon,authenticated;
revoke all on function public.apply_navision_backend_import(text,jsonb,text,timestamptz,text,text,bigint) from public,anon,authenticated;

create or replace function public.navision_backend_preview_internal(
  p_rows jsonb,
  p_source_system text,
  p_dealer_code text,
  p_source_name text,
  p_source_timestamp timestamptz
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, extensions
as $preview$
declare
  v_revision bigint;
  v_destination_hash text;
  v_source_hash text;
  v_items jsonb;
  v_missing jsonb;
  v_counts jsonb;
  v_preview_hash text;
  v_source_system text := lower(btrim(coalesce(p_source_system, '')));
  v_dealer_code text := btrim(coalesce(p_dealer_code, ''));
  v_role text := public.current_pdc_user_role();
begin
  if v_source_system <> 'microsoft_navision' then return public.navision_backend_response(false, 'invalid_input', jsonb_build_object('field', 'source_system')); end if;
  if v_dealer_code not in ('14450', '37047') then return public.navision_backend_response(false, 'invalid_input', jsonb_build_object('field', 'dealer_code')); end if;
  if jsonb_typeof(p_rows) is distinct from 'array' then
    return public.navision_backend_response(false, 'invalid_input', jsonb_build_object('field', 'rows'));
  end if;
  if jsonb_array_length(p_rows) > 5000 then
    return public.navision_backend_response(false, 'input_too_large', jsonb_build_object('max_rows', 5000));
  end if;
  if nullif(btrim(p_source_name), '') is null or length(p_source_name) > 255 then
    return public.navision_backend_response(false, 'invalid_input', jsonb_build_object('field', 'source_name'));
  end if;
  if octet_length(p_rows::text) > 25000000 then
    return public.navision_backend_response(false, 'input_too_large', jsonb_build_object('max_bytes', 25000000));
  end if;

  select revision into v_revision from public.navision_backend_revision where singleton;
  if v_revision is null then
    return public.navision_backend_response(false, 'service_unavailable');
  end if;

  select encode(extensions.digest(coalesce(jsonb_agg(jsonb_build_object(
      'id', r.id,
      'row_hash', r.row_hash,
      'current', r.is_current,
      'canonical_vehicle_id', r.canonical_vehicle_id,
      'version', r.version
    ) order by r.source_record_id_normalized), '[]'::jsonb)::text, 'sha256'), 'hex')
  into v_destination_hash
  from public.navision_backend_records r
  where r.source_system = v_source_system and r.dealer_code = v_dealer_code;

  with rows as materialized (
    select e.ordinality::integer as row_index, e.value as raw_row,
      public.navision_backend_normalize_row(e.value) as normalized,
      public.navision_backend_source_record_id(e.value) as source_record_id,
      public.navision_backend_row_hash(e.value) as row_hash,
      public.navision_backend_row_has_forbidden_fields(e.value) as forbidden
    from jsonb_array_elements(p_rows) with ordinality e(value, ordinality)
  )
  select encode(extensions.digest(coalesce(jsonb_agg(jsonb_build_object(
      'row_index', row_index, 'source_record_id', source_record_id,
      'row_hash', row_hash, 'forbidden', forbidden
    ) order by row_index), '[]'::jsonb)::text, 'sha256'), 'hex')
  into v_source_hash from rows;

  with rows as materialized (
    select e.ordinality::integer as row_index, e.value as raw_row,
      public.navision_backend_source_record_id(e.value) as source_record_id,
      public.navision_backend_row_hash(e.value) as row_hash,
      public.navision_backend_row_has_forbidden_fields(e.value) as forbidden
    from jsonb_array_elements(p_rows) with ordinality e(value, ordinality)
  ), classified as materialized (
    select r.*,
      count(*) over (partition by r.source_record_id) as identity_count,
      b.id as backend_record_id,
      b.dealer_code as existing_dealer_code,
      b.row_hash as existing_hash,
      b.canonical_vehicle_id,
      public.navision_backend_candidate_vehicle_ids(r.raw_row) as candidates
    from rows r
    left join lateral (
      select candidate.*
      from public.navision_backend_records candidate
      where candidate.source_system = v_source_system
        and candidate.source_record_id_normalized = r.source_record_id
        and candidate.dealer_code in (v_dealer_code, 'LEGACY_UNSCOPED')
      order by case when candidate.dealer_code = v_dealer_code then 0 else 1 end
      limit 1
    ) b on true
  ), item_rows as (
    select row_index, source_record_id, row_hash, backend_record_id,
      case
        when jsonb_typeof(raw_row) <> 'object' or source_record_id is null or forbidden then 'invalid'
        when identity_count > 1 or cardinality(candidates) > 1 then 'conflict'
        when existing_dealer_code = 'LEGACY_UNSCOPED' and v_role is distinct from 'administrator' then 'conflict'
        when backend_record_id is null then 'new'
        when existing_hash = row_hash then 'unchanged'
        else 'changed'
      end as classification,
      case
        when jsonb_typeof(raw_row) <> 'object' then 'row_not_object'
        when source_record_id is null then 'missing_source_record_id'
        when forbidden then 'forbidden_operational_field'
        when identity_count > 1 then 'duplicate_source_record_id'
        when cardinality(candidates) > 1 then 'ambiguous_canonical_identity'
        when existing_dealer_code = 'LEGACY_UNSCOPED' and v_role is distinct from 'administrator' then 'legacy_claim_requires_administrator'
        else null
      end as reason,
      candidates,
      case when cardinality(candidates) = 1 then candidates[1] else null end as proposed_vehicle_id,
      canonical_vehicle_id
    from classified
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'row_index', row_index,
    'source_record_id', source_record_id,
    'row_hash', row_hash,
    'backend_record_id', backend_record_id,
    'classification', classification,
    'reason', reason,
    'candidate_vehicle_ids', to_jsonb(candidates),
    'proposed_vehicle_id', proposed_vehicle_id,
    'existing_canonical_vehicle_id', canonical_vehicle_id,
    'operational_mutations', 0
  ) order by row_index), '[]'::jsonb)
  into v_items from item_rows;

  with incoming as (
    select public.navision_backend_source_record_id(value) source_record_id
    from jsonb_array_elements(p_rows)
    where jsonb_typeof(value) = 'object'
      and not public.navision_backend_row_has_forbidden_fields(value)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'backend_record_id', b.id,
    'source_record_id', b.source_record_id,
    'row_hash', b.row_hash,
    'canonical_vehicle_id', b.canonical_vehicle_id,
    'classification', 'missing',
    'operational_mutations', 0
  ) order by b.source_record_id_normalized), '[]'::jsonb)
  into v_missing
  from public.navision_backend_records b
  where b.source_system = v_source_system and b.dealer_code = v_dealer_code
    and b.is_current
    and not exists (select 1 from incoming i where i.source_record_id = b.source_record_id_normalized);

  select jsonb_build_object(
    'total', jsonb_array_length(v_items),
    'new', count(*) filter (where item ->> 'classification' = 'new'),
    'changed', count(*) filter (where item ->> 'classification' = 'changed'),
    'unchanged', count(*) filter (where item ->> 'classification' = 'unchanged'),
    'invalid', count(*) filter (where item ->> 'classification' = 'invalid'),
    'conflict', count(*) filter (where item ->> 'classification' = 'conflict'),
    'missing', jsonb_array_length(v_missing),
    'proposed_links', count(*) filter (where item ->> 'proposed_vehicle_id' is not null),
    'operational_mutations', 0
  ) into v_counts
  from jsonb_array_elements(v_items) item;

  v_preview_hash := encode(extensions.digest(jsonb_build_object(
    'contract_version', 2,
    'source_system', v_source_system,
    'dealer_code', v_dealer_code,
    'source_name', btrim(p_source_name),
    'source_timestamp', p_source_timestamp,
    'source_hash', v_source_hash,
    'base_revision', v_revision,
    'destination_hash', v_destination_hash,
    'items', v_items,
    'missing', v_missing
  )::text, 'sha256'), 'hex');

  return public.navision_backend_response(true, 'preview_ready', jsonb_build_object(
    'contract_version', 2,
    'source_system', v_source_system,
    'dealer_code', v_dealer_code,
    'source_name', btrim(p_source_name),
    'source_timestamp', p_source_timestamp,
    'source_hash', v_source_hash,
    'preview_hash', v_preview_hash,
    'base_revision', v_revision,
    'destination_hash', v_destination_hash,
    'counts', v_counts,
    'items', v_items,
    'missing_records', v_missing,
    'blocking', ((v_counts ->> 'invalid')::integer + (v_counts ->> 'conflict')::integer) > 0,
    'authority', 'shared_navision_backend_only',
    'operational_mutations', 0
  ));
end;
$preview$;

create or replace function public.preview_navision_backend_import(
  p_rows jsonb,
  p_source_system text,
  p_dealer_code text,
  p_source_name text,
  p_source_timestamp timestamptz default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  if not coalesce(public.current_pdc_user_role()::text = any (array['importer', 'administrator']), false) then
    return public.navision_backend_response(false, 'unauthorized');
  end if;
  return public.navision_backend_preview_internal(p_rows, p_source_system, p_dealer_code, p_source_name, p_source_timestamp);
end;
$$;

create or replace function public.apply_navision_backend_import(
  p_idempotency_key text,
  p_rows jsonb,
  p_source_system text,
  p_dealer_code text,
  p_source_name text,
  p_source_timestamp timestamptz,
  p_source_hash text,
  p_preview_hash text,
  p_expected_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $apply$
declare
  v_role public.pdc_role;
  v_request_hash text;
  v_existing public.navision_operation_receipts%rowtype;
  v_preview jsonb;
  v_data jsonb;
  v_counts jsonb;
  v_revision bigint;
  v_batch_id uuid := gen_random_uuid();
  v_result_revision bigint;
  v_response jsonb;
  v_row jsonb;
  v_index bigint;
  v_source_record_id text;
  v_row_hash text;
  v_normalized jsonb;
  v_classification text;
  v_candidates uuid[];
  v_record public.navision_backend_records%rowtype;
  v_before jsonb;
  v_after jsonb;
  v_item jsonb;
  v_missing jsonb;
  v_missing_index integer := 0;
begin
  v_role := public.current_pdc_user_role();
  if not coalesce(v_role::text = any (array['importer', 'administrator']), false) then
    return public.navision_backend_response(false, 'unauthorized');
  end if;
  if nullif(btrim(p_idempotency_key), '') is null or length(p_idempotency_key) > 200 then
    return public.navision_backend_response(false, 'invalid_input', jsonb_build_object('field', 'idempotency_key'));
  end if;
  if p_expected_revision is null or p_expected_revision < 1 then
    return public.navision_backend_response(false, 'invalid_input', jsonb_build_object('field', 'expected_revision'));
  end if;

  v_request_hash := encode(extensions.digest(jsonb_build_object(
    'contract_version', 2,
    'source_system', lower(btrim(coalesce(p_source_system, ''))),
    'dealer_code', btrim(coalesce(p_dealer_code, '')),
    'idempotency_key', btrim(p_idempotency_key),
    'rows', p_rows,
    'source_name', btrim(p_source_name),
    'source_timestamp', p_source_timestamp,
    'source_hash', lower(coalesce(p_source_hash, '')),
    'preview_hash', lower(coalesce(p_preview_hash, '')),
    'expected_revision', p_expected_revision
  )::text, 'sha256'), 'hex');

  perform pg_advisory_xact_lock(hashtextextended('navision-apply:' || btrim(p_idempotency_key), 0));
  select * into v_existing from public.navision_operation_receipts
  where operation_kind = 'apply' and idempotency_key = btrim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_request_hash then
      return public.navision_backend_response(false, 'idempotency_conflict');
    end if;
    return v_existing.response;
  end if;

  v_preview := public.navision_backend_preview_internal(p_rows, p_source_system, p_dealer_code, p_source_name, p_source_timestamp);
  if not coalesce((v_preview ->> 'ok')::boolean, false) then return v_preview; end if;
  v_data := v_preview -> 'data';
  v_counts := v_data -> 'counts';
  if lower(coalesce(p_source_hash, '')) <> v_data ->> 'source_hash' then
    return public.navision_backend_response(false, 'source_changed');
  end if;
  if lower(coalesce(p_preview_hash, '')) <> v_data ->> 'preview_hash' then
    return public.navision_backend_response(false, 'preview_changed');
  end if;
  if p_expected_revision <> (v_data ->> 'base_revision')::bigint then
    return public.navision_backend_response(false, 'stale_revision', jsonb_build_object('current_revision', (v_data ->> 'base_revision')::bigint));
  end if;
  if coalesce((v_data ->> 'blocking')::boolean, true) then
    return public.navision_backend_response(false, 'blocking_reconciliation', jsonb_build_object('counts', v_counts));
  end if;

  perform pg_advisory_xact_lock(hashtextextended('navision-backend-store', 0));
  select revision into v_revision from public.navision_backend_revision where singleton for update;
  if v_revision <> p_expected_revision then
    return public.navision_backend_response(false, 'stale_revision', jsonb_build_object('current_revision', v_revision));
  end if;
  v_result_revision := v_revision + 1;

  insert into public.navision_import_batches (
    id, idempotency_key, request_hash, source_system, dealer_code, source_name, source_timestamp, source_hash,
    preview_hash, base_revision, result_revision, total_rows, new_count,
    changed_count, unchanged_count, missing_count, invalid_count, conflict_count,
    actor_id, actor_email
  ) values (
    v_batch_id, btrim(p_idempotency_key), v_request_hash, lower(btrim(p_source_system)), btrim(p_dealer_code), btrim(p_source_name),
    p_source_timestamp, v_data ->> 'source_hash', v_data ->> 'preview_hash',
    v_revision, v_result_revision, (v_counts ->> 'total')::integer,
    (v_counts ->> 'new')::integer, (v_counts ->> 'changed')::integer,
    (v_counts ->> 'unchanged')::integer, (v_counts ->> 'missing')::integer,
    (v_counts ->> 'invalid')::integer, (v_counts ->> 'conflict')::integer,
    auth.uid(), public.current_actor_email()
  );

  for v_row, v_index in
    select value, ordinality from jsonb_array_elements(p_rows) with ordinality
  loop
    v_item := v_data -> 'items' -> ((v_index - 1)::integer);
    v_classification := v_item ->> 'classification';
    v_source_record_id := public.navision_backend_source_record_id(v_row);
    v_row_hash := public.navision_backend_row_hash(v_row);
    v_normalized := public.navision_backend_normalize_row(v_row);
    select coalesce(array_agg(value::text::uuid order by value::text), '{}'::uuid[])
      into v_candidates
    from jsonb_array_elements_text(coalesce(v_item -> 'candidate_vehicle_ids', '[]'::jsonb));

    select * into v_record from public.navision_backend_records
    where source_system = lower(btrim(p_source_system))
      and dealer_code in (btrim(p_dealer_code), 'LEGACY_UNSCOPED')
      and source_record_id_normalized = v_source_record_id
    order by case when dealer_code = btrim(p_dealer_code) then 0 else 1 end
    limit 1 for update;
    if found then
      v_before := to_jsonb(v_record);
      update public.navision_backend_records
      set source_system = lower(btrim(p_source_system)), dealer_code = btrim(p_dealer_code), record_status = 'current',
          source_record_id = coalesce(nullif(btrim(v_row ->> 'id'), ''), v_source_record_id),
          row_hash = v_row_hash,
          normalized_data = v_normalized,
          raw_evidence = v_row,
          last_seen_batch_id = v_batch_id,
          missing_since_batch_id = null,
          is_current = true,
          version = case when row_hash is distinct from v_row_hash or not is_current then version + 1 else version end,
          updated_at = now()
      where id = v_record.id;
    else
      insert into public.navision_backend_records (
        source_system, dealer_code, record_status, source_record_id, row_hash, normalized_data, raw_evidence,
        first_seen_batch_id, last_seen_batch_id
      ) values (
        lower(btrim(p_source_system)), btrim(p_dealer_code), 'current',
        coalesce(nullif(btrim(v_row ->> 'id'), ''), v_source_record_id), v_row_hash, v_normalized, v_row, v_batch_id, v_batch_id
      ) returning * into v_record;
      v_before := null;
    end if;
    select * into v_record from public.navision_backend_records
      where source_system = lower(btrim(p_source_system)) and dealer_code = btrim(p_dealer_code)
        and source_record_id_normalized = v_source_record_id;
    v_after := to_jsonb(v_record);

    insert into public.navision_import_items (
      batch_id, row_index, backend_record_id, source_record_id, row_hash,
      classification, normalized_evidence, raw_evidence, candidate_vehicle_ids,
      proposed_vehicle_id, before_record, after_record
    ) values (
      v_batch_id, v_index::integer, v_record.id, v_source_record_id, v_row_hash,
      v_classification, v_normalized, v_row, v_candidates,
      nullif(v_item ->> 'proposed_vehicle_id', '')::uuid, v_before, v_after
    );
  end loop;

  for v_missing in select value from jsonb_array_elements(v_data -> 'missing_records')
  loop
    v_missing_index := v_missing_index + 1;
    select * into v_record from public.navision_backend_records
      where id = (v_missing ->> 'backend_record_id')::uuid for update;
    v_before := to_jsonb(v_record);
    update public.navision_backend_records
    set is_current = false, record_status = 'not_in_latest_batch', missing_since_batch_id = v_batch_id,
        version = version + 1, updated_at = now()
    where id = v_record.id;
    select * into v_record from public.navision_backend_records where id = v_record.id;
    v_after := to_jsonb(v_record);
    insert into public.navision_import_items (
      batch_id, row_index, backend_record_id, source_record_id, row_hash, classification,
      candidate_vehicle_ids, proposed_vehicle_id, before_record, after_record
    ) values (
      v_batch_id, (v_counts ->> 'total')::integer + v_missing_index,
      v_record.id, v_record.source_record_id, v_record.row_hash,
      'missing', '{}'::uuid[], v_record.canonical_vehicle_id, v_before, v_after
    );
  end loop;

  update public.navision_backend_revision
  set revision = v_result_revision, updated_at = now() where singleton;

  v_response := public.navision_backend_response(true, 'applied', jsonb_build_object(
    'batch_id', v_batch_id,
    'source_system', lower(btrim(p_source_system)), 'dealer_code', btrim(p_dealer_code),
    'idempotency_key', btrim(p_idempotency_key),
    'source_hash', v_data ->> 'source_hash',
    'preview_hash', v_data ->> 'preview_hash',
    'base_revision', v_revision,
    'result_revision', v_result_revision,
    'counts', v_counts,
    'authority', 'shared_navision_backend_only',
    'operational_mutations', 0
  ));

  update public.navision_import_batches set receipt = v_response where id = v_batch_id;
  insert into public.navision_operation_receipts (
    operation_kind, idempotency_key, request_hash, batch_id, response,
    actor_id, actor_email
  ) values (
    'apply', btrim(p_idempotency_key), v_request_hash, v_batch_id, v_response,
    auth.uid(), public.current_actor_email()
  );
  insert into public.navision_backend_audit (
    action, batch_id, revision, evidence, actor_id, actor_email
  ) values (
    'import_apply', v_batch_id, v_result_revision,
    jsonb_build_object('source_system', lower(btrim(p_source_system)), 'dealer_code', btrim(p_dealer_code), 'source_hash', v_data ->> 'source_hash', 'counts', v_counts, 'operational_mutations', 0),
    auth.uid(), public.current_actor_email()
  );
  return v_response;
end;
$apply$;

create or replace function public.rollback_navision_backend_import(
  p_idempotency_key text,
  p_target_batch_id text,
  p_expected_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $rollback$
declare
  v_batch_id uuid;
  v_request_hash text;
  v_existing public.navision_operation_receipts%rowtype;
  v_batch public.navision_import_batches%rowtype;
  v_revision bigint;
  v_result_revision bigint;
  v_response jsonb;
  v_receipt_id uuid;
  v_item public.navision_import_items%rowtype;
  v_current jsonb;
  v_after jsonb;
  v_restored public.navision_backend_records%rowtype;
begin
  if public.current_pdc_user_role() is distinct from 'administrator' then
    return public.navision_backend_response(false, 'unauthorized');
  end if;
  if nullif(btrim(p_idempotency_key), '') is null or length(p_idempotency_key) > 200 then
    return public.navision_backend_response(false, 'invalid_input', jsonb_build_object('field', 'idempotency_key'));
  end if;
  if coalesce(p_target_batch_id, '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    return public.navision_backend_response(false, 'invalid_input', jsonb_build_object('field', 'target_batch_id'));
  end if;
  v_batch_id := btrim(p_target_batch_id)::uuid;
  v_request_hash := encode(extensions.digest(jsonb_build_object(
    'contract_version', 1, 'idempotency_key', btrim(p_idempotency_key),
    'target_batch_id', v_batch_id, 'expected_revision', p_expected_revision
  )::text, 'sha256'), 'hex');

  perform pg_advisory_xact_lock(hashtextextended('navision-rollback:' || btrim(p_idempotency_key), 0));
  select * into v_existing from public.navision_operation_receipts
    where operation_kind = 'rollback' and idempotency_key = btrim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_request_hash then
      return public.navision_backend_response(false, 'idempotency_conflict');
    end if;
    return v_existing.response;
  end if;

  perform pg_advisory_xact_lock(hashtextextended('navision-backend-store', 0));
  select revision into v_revision from public.navision_backend_revision where singleton for update;
  if v_revision is distinct from p_expected_revision then
    return public.navision_backend_response(false, 'stale_revision', jsonb_build_object('current_revision', v_revision));
  end if;
  select * into v_batch from public.navision_import_batches where id = v_batch_id for update;
  if not found then return public.navision_backend_response(false, 'batch_not_found'); end if;
  if v_batch.status <> 'applied' then return public.navision_backend_response(false, 'batch_not_applied'); end if;
  if v_batch.result_revision <> v_revision then
    return public.navision_backend_response(false, 'revision_conflict', jsonb_build_object('current_revision', v_revision, 'batch_revision', v_batch.result_revision));
  end if;
  v_result_revision := v_revision + 1;

  -- Fail closed if anything bypassed the revision contract after apply.  The
  -- rollback must only replace the exact after-image written by this batch.
  for v_item in
    select * from public.navision_import_items where batch_id = v_batch_id
    order by row_index desc nulls last, id desc
  loop
    select to_jsonb(r) into v_current
    from public.navision_backend_records r
    where r.id = v_item.backend_record_id
    for update;
    if v_current is distinct from v_item.after_record then
      return public.navision_backend_response(false, 'rollback_state_drift', jsonb_build_object(
        'backend_record_id', v_item.backend_record_id,
        'target_batch_id', v_batch_id
      ));
    end if;
  end loop;

  v_response := public.navision_backend_response(true, 'rolled_back', jsonb_build_object(
    'target_batch_id', v_batch_id,
    'base_revision', v_revision,
    'result_revision', v_result_revision,
    'authority', 'shared_navision_backend_only',
    'operational_mutations', 0
  ));
  insert into public.navision_operation_receipts (
    operation_kind, idempotency_key, request_hash, batch_id, response, actor_id, actor_email
  ) values (
    'rollback', btrim(p_idempotency_key), v_request_hash, v_batch_id, v_response,
    auth.uid(), public.current_actor_email()
  ) returning id into v_receipt_id;

  for v_item in
    select * from public.navision_import_items where batch_id = v_batch_id
    order by row_index desc nulls last, id desc
  loop
    select to_jsonb(r) into v_current from public.navision_backend_records r where r.id = v_item.backend_record_id for update;
    if v_item.before_record is null then
      delete from public.navision_backend_records where id = v_item.backend_record_id;
      v_after := null;
      insert into public.navision_rollback_items (
        receipt_id, target_batch_id, backend_record_id, action, before_rollback, after_rollback
      ) values (v_receipt_id, v_batch_id, v_item.backend_record_id, 'deleted_new', v_current, null);
    else
      v_restored := jsonb_populate_record(null::public.navision_backend_records, v_item.before_record);
      insert into public.navision_backend_records (
        id, source_system, dealer_code, record_status, source_record_id, row_hash, normalized_data, raw_evidence,
        canonical_vehicle_id, first_seen_batch_id, last_seen_batch_id,
        missing_since_batch_id, is_current, version, created_at, updated_at
      ) values (
        v_restored.id, v_restored.source_system, v_restored.dealer_code, v_restored.record_status, v_restored.source_record_id, v_restored.row_hash,
        v_restored.normalized_data, v_restored.raw_evidence,
        v_restored.canonical_vehicle_id, v_restored.first_seen_batch_id,
        v_restored.last_seen_batch_id, v_restored.missing_since_batch_id,
        v_restored.is_current, v_restored.version, v_restored.created_at,
        v_restored.updated_at
      ) on conflict (id) do update set
        source_system = excluded.source_system, dealer_code = excluded.dealer_code, record_status = excluded.record_status,
        source_record_id = excluded.source_record_id,
        row_hash = excluded.row_hash,
        normalized_data = excluded.normalized_data,
        raw_evidence = excluded.raw_evidence,
        canonical_vehicle_id = excluded.canonical_vehicle_id,
        first_seen_batch_id = excluded.first_seen_batch_id,
        last_seen_batch_id = excluded.last_seen_batch_id,
        missing_since_batch_id = excluded.missing_since_batch_id,
        is_current = excluded.is_current,
        version = excluded.version,
        created_at = excluded.created_at,
        updated_at = excluded.updated_at;
      select to_jsonb(r) into v_after from public.navision_backend_records r where r.id = v_item.backend_record_id;
      insert into public.navision_rollback_items (
        receipt_id, target_batch_id, backend_record_id, action, before_rollback, after_rollback
      ) values (v_receipt_id, v_batch_id, v_item.backend_record_id, 'restored', v_current, v_after);
    end if;
  end loop;

  update public.navision_import_batches
  set status = 'rolled_back', rolled_back_at = now(), rolled_back_by = auth.uid()
  where id = v_batch_id;
  update public.navision_backend_revision set revision = v_result_revision, updated_at = now() where singleton;
  insert into public.navision_backend_audit (
    action, batch_id, revision, evidence, actor_id, actor_email
  ) values (
    'import_rollback', v_batch_id, v_result_revision,
    jsonb_build_object('target_batch_id', v_batch_id, 'operational_mutations', 0),
    auth.uid(), public.current_actor_email()
  );
  return v_response;
end;
$rollback$;

-- Dealer-scoped snapshot/export replaces the unscoped migration-037 contract.
-- The UUID tie-breaker prevents duplicate source IDs in different scopes from
-- being skipped at a page boundary.
create or replace function public.get_navision_backend_snapshot(
  p_source_system text,
  p_dealer_code text,
  p_after_source_record_id text default null,
  p_after_record_id uuid default null,
  p_page_size integer default 200,
  p_expected_revision bigint default null
)
returns jsonb language plpgsql stable security definer
set search_path = pg_catalog, public, extensions
as $snapshot$
declare
  v_role text := public.current_pdc_user_role();
  v_revision bigint;
  v_page_size integer;
  v_result jsonb;
  v_source_system text := lower(btrim(coalesce(p_source_system,'')));
  v_dealer_code text := btrim(coalesce(p_dealer_code,''));
begin
  if not coalesce(v_role = any(array['importer','administrator']),false) then
    return public.navision_backend_response(false,'unauthorized');
  end if;
  if v_source_system <> 'microsoft_navision' or v_dealer_code not in ('14450','37047') then
    return public.navision_backend_response(false,'invalid_input',jsonb_build_object('field','scope'));
  end if;
  if (p_after_source_record_id is null) <> (p_after_record_id is null) then
    return public.navision_backend_response(false,'invalid_input',jsonb_build_object('field','cursor'));
  end if;
  if p_page_size is null or p_page_size < 1 then
    return public.navision_backend_response(false,'invalid_input',jsonb_build_object('field','page_size'));
  end if;
  v_page_size := least(p_page_size,500);
  select revision into v_revision from public.navision_backend_revision where singleton;
  if p_expected_revision is not null and p_expected_revision <> v_revision then
    return public.navision_backend_response(false,'stale_revision',jsonb_build_object('current_revision',v_revision));
  end if;
  with page as materialized (
    select r.* from public.navision_backend_records r
    where r.source_system=v_source_system and r.dealer_code=v_dealer_code
      and (p_after_source_record_id is null or
        (r.source_record_id_normalized,r.id) >
        (public.normalize_vehicle_source_identifier(p_after_source_record_id),p_after_record_id))
    order by r.source_record_id_normalized,r.id limit v_page_size+1
  ), selected as materialized (
    select * from page order by source_record_id_normalized,id limit v_page_size
  ), last_selected as (
    select source_record_id_normalized,id from selected order by source_record_id_normalized desc,id desc limit 1
  )
  select public.navision_backend_response(true,'snapshot',jsonb_build_object(
    'revision',v_revision,'source_system',v_source_system,'dealer_code',v_dealer_code,'page_size',v_page_size,
    'items',coalesce((select jsonb_agg(jsonb_build_object(
      'id',id,'source_system',source_system,'dealer_code',dealer_code,'record_status',record_status,
      'source_record_id',source_record_id,'row_hash',row_hash,'canonical_vehicle_id',canonical_vehicle_id,
      'is_current',is_current,'version',version,'first_seen_batch_id',first_seen_batch_id,
      'last_seen_batch_id',last_seen_batch_id,'missing_since_batch_id',missing_since_batch_id,
      'updated_at',updated_at,'normalized_data',normalized_data
    ) order by source_record_id_normalized,id) from selected),'[]'::jsonb),
    'has_more',(select count(*)>v_page_size from page),
    'next_source_record_id',case when (select count(*)>v_page_size from page) then (select source_record_id_normalized from last_selected) end,
    'next_record_id',case when (select count(*)>v_page_size from page) then (select id from last_selected) end,
    'authority','shared_navision_backend_only','data_access','normalized'
  )) into v_result;
  return v_result;
end;
$snapshot$;

create or replace function public.export_navision_backend_records(
  p_source_system text,
  p_dealer_code text,
  p_after_source_record_id text default null,
  p_after_record_id uuid default null,
  p_page_size integer default 200,
  p_expected_revision bigint default null
)
returns jsonb language plpgsql stable security definer
set search_path = pg_catalog, public, extensions
as $export$
begin
  if not coalesce(public.current_pdc_user_role()::text = any(array['importer','administrator']),false) then
    return public.navision_backend_response(false,'unauthorized');
  end if;
  return public.get_navision_backend_snapshot(p_source_system,p_dealer_code,p_after_source_record_id,p_after_record_id,least(coalesce(p_page_size,200),500),p_expected_revision);
end;
$export$;


alter table public.workshop_bookings add column if not exists eta_at_booking date;
alter table public.workshop_bookings add column if not exists eta_risk_status text not null default 'none';
alter table public.workshop_bookings add column if not exists eta_risk_detected_at timestamptz;
alter table public.workshop_bookings drop constraint if exists workshop_bookings_eta_risk_status_check;
alter table public.workshop_bookings add constraint workshop_bookings_eta_risk_status_check check (eta_risk_status in ('none','at_risk'));
create or replace function public.workshop_enforce_vehicle_eta() returns trigger language plpgsql security definer set search_path=pg_catalog, public, extensions as $$
declare v_vehicle public.vehicles%rowtype; v_location text;
begin
 select * into v_vehicle from public.vehicles where id=new.vehicle_id;
 v_location:=upper(btrim(coalesce(v_vehicle.current_location,'')));
 if v_location in ('YH','IT') then
  if v_vehicle.eta_to_kewdale is null then raise exception 'missing_or_invalid_eta' using errcode='23514'; end if;
  if (new.scheduled_start_at at time zone 'Australia/Perth')::date < v_vehicle.eta_to_kewdale then raise exception 'booking_before_eta earliest_permitted_date=%',v_vehicle.eta_to_kewdale using errcode='23514'; end if;
  new.eta_at_booking:=v_vehicle.eta_to_kewdale; new.eta_risk_status:='none'; new.eta_risk_detected_at:=null;
 end if; return new;
end; $$;
drop trigger if exists workshop_bookings_enforce_vehicle_eta on public.workshop_bookings;
create trigger workshop_bookings_enforce_vehicle_eta before insert or update of scheduled_start_at, vehicle_id on public.workshop_bookings for each row execute function public.workshop_enforce_vehicle_eta();
create or replace function public.workshop_refresh_eta_risk() returns trigger language plpgsql security definer set search_path=pg_catalog, public, extensions as $$
declare
 v_booking public.workshop_bookings%rowtype;
 v_after jsonb;
 v_new_status text;
 v_actor uuid := coalesce(auth.uid(), new.updated_by, old.updated_by);
begin
 if new.eta_to_kewdale is distinct from old.eta_to_kewdale then
  for v_booking in
   select b.* from public.workshop_bookings b
   where b.vehicle_id=new.id and b.status='planned' and b.deleted_at is null
   for update
  loop
   v_new_status:=case when new.eta_to_kewdale is null or (v_booking.scheduled_start_at at time zone 'Australia/Perth')::date<new.eta_to_kewdale then 'at_risk' else 'none' end;
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
       jsonb_build_object('vehicle_id',new.id,'previous_eta',old.eta_to_kewdale,'current_eta',new.eta_to_kewdale),
       v_actor,public.current_actor_email());
    end if;
   end if;
  end loop;
 end if;
 return new;
end; $$;
drop trigger if exists vehicles_refresh_workshop_eta_risk on public.vehicles;
create trigger vehicles_refresh_workshop_eta_risk after update of eta_to_kewdale on public.vehicles for each row execute function public.workshop_refresh_eta_risk();
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
  v_result jsonb;
  v_booking jsonb;
  v_override_id uuid;
  v_before_vehicle jsonb;
  v_after_vehicle jsonb;
  v_revision bigint;
begin
  perform public.require_pdc_role('operator');
  perform public.workshop_require_version(p_vehicle_expected_version);

  select * into v_vehicle from public.vehicles where id = p_vehicle_id for update;
  if not found then
    raise exception 'Vehicle not found' using errcode = 'P0002';
  end if;
  if v_vehicle.version <> p_vehicle_expected_version then
    return jsonb_build_object('ok', false, 'error', 'vehicle_version_conflict');
  end if;

  select * into v_stage from public.workshop_stages where code = upper(trim(coalesce(p_stage_code, ''))) and active = true;
  if not found then
    raise exception 'Workshop stage % not found', p_stage_code using errcode = 'P0002';
  end if;

  -- Parts gate: a vehicle must not enter a Parts-protected physical
  -- production bay when Parts work is incomplete unless an explicit,
  -- audited override is supplied by an authorised operator/administrator.
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
  if not (v_booking->>'ok')::boolean then
    return v_booking;
  end if;

  update public.vehicles
  set active_workshop_booking_id = (v_booking->'booking'->>'booking_id')::uuid,
      workshop_status = 'scheduled',
      workshop_status_updated_at = now(),
      workshop_status_updated_by = auth.uid(),
      current_location = case when upper(btrim(coalesce(v_vehicle.current_location,''))) in ('YH','IT') then v_vehicle.current_location else coalesce(v_vehicle.current_location,'PMB') end,
      pmb_stage = case when upper(btrim(coalesce(v_vehicle.current_location,''))) in ('YH','IT') then v_vehicle.pmb_stage else p_stage_code end,
      visible_on_board = case when upper(btrim(coalesce(v_vehicle.current_location,''))) in ('YH','IT') then v_vehicle.visible_on_board else true end,
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


revoke all on function public.navision_backend_preview_internal(jsonb,text,text,text,timestamptz) from public,anon,authenticated;
revoke all on function public.preview_navision_backend_import(jsonb,text,text,text,timestamptz) from public,anon,authenticated;
revoke all on function public.apply_navision_backend_import(text,jsonb,text,text,text,timestamptz,text,text,bigint) from public,anon,authenticated;
revoke all on function public.get_navision_backend_snapshot(text,integer,bigint) from public,anon,authenticated;
revoke all on function public.export_navision_backend_records(text,integer,bigint) from public,anon,authenticated;
revoke all on function public.get_navision_backend_snapshot(text,text,text,uuid,integer,bigint) from public,anon,authenticated;
revoke all on function public.export_navision_backend_records(text,text,text,uuid,integer,bigint) from public,anon,authenticated;
grant execute on function public.preview_navision_backend_import(jsonb,text,text,text,timestamptz) to authenticated;
grant execute on function public.apply_navision_backend_import(text,jsonb,text,text,text,timestamptz,text,text,bigint) to authenticated;
grant execute on function public.get_navision_backend_snapshot(text,text,text,uuid,integer,bigint) to authenticated;
grant execute on function public.export_navision_backend_records(text,text,text,uuid,integer,bigint) to authenticated;
revoke all on function public.workshop_enforce_vehicle_eta() from public,anon,authenticated;
revoke all on function public.workshop_refresh_eta_risk() from public,anon,authenticated;
revoke all on function public.schedule_vehicle_work(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb) from public,anon;
grant execute on function public.schedule_vehicle_work(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb) to authenticated;
