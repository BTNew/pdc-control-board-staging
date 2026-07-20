-- Migration 037: staging-first shared Navision backend store.
--
-- Additive only. This migration does not import source rows, change browser-local
-- authority, activate vehicles, or mutate any operational vehicle/workflow field.

create table if not exists public.navision_backend_revision (
  singleton boolean primary key default true check (singleton),
  revision bigint not null default 1 check (revision > 0),
  updated_at timestamptz not null default now()
);

insert into public.navision_backend_revision (singleton, revision)
values (true, 1)
on conflict (singleton) do nothing;

create table if not exists public.navision_import_batches (
  id uuid primary key default gen_random_uuid(),
  idempotency_key text not null unique,
  request_hash text not null,
  source_name text not null,
  source_timestamp timestamptz,
  source_hash text not null,
  preview_hash text not null,
  base_revision bigint not null check (base_revision > 0),
  result_revision bigint not null check (result_revision > 0),
  status text not null default 'applied' check (status in ('applied', 'rolled_back')),
  total_rows integer not null check (total_rows >= 0),
  new_count integer not null default 0 check (new_count >= 0),
  changed_count integer not null default 0 check (changed_count >= 0),
  unchanged_count integer not null default 0 check (unchanged_count >= 0),
  missing_count integer not null default 0 check (missing_count >= 0),
  invalid_count integer not null default 0 check (invalid_count >= 0),
  conflict_count integer not null default 0 check (conflict_count >= 0),
  receipt jsonb not null default '{}'::jsonb,
  actor_id uuid references auth.users(id) on delete set null,
  actor_email text,
  applied_at timestamptz not null default now(),
  rolled_back_at timestamptz,
  rolled_back_by uuid references auth.users(id) on delete set null,
  check (source_hash ~ '^[0-9a-f]{64}$'),
  check (preview_hash ~ '^[0-9a-f]{64}$'),
  check (request_hash ~ '^[0-9a-f]{64}$')
);

create table if not exists public.navision_backend_records (
  id uuid primary key default gen_random_uuid(),
  source_record_id text not null,
  source_record_id_normalized text generated always as
    (public.normalize_vehicle_source_identifier(source_record_id)) stored,
  row_hash text not null check (row_hash ~ '^[0-9a-f]{64}$'),
  normalized_data jsonb not null,
  raw_evidence jsonb not null,
  canonical_vehicle_id uuid references public.vehicles(id) on delete set null,
  first_seen_batch_id uuid not null references public.navision_import_batches(id),
  last_seen_batch_id uuid not null references public.navision_import_batches(id),
  missing_since_batch_id uuid references public.navision_import_batches(id),
  is_current boolean not null default true,
  version integer not null default 1 check (version > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (source_record_id_normalized),
  check (jsonb_typeof(normalized_data) = 'object'),
  check (jsonb_typeof(raw_evidence) = 'object'),
  check ((is_current and missing_since_batch_id is null) or (not is_current and missing_since_batch_id is not null))
);

create table if not exists public.navision_import_items (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.navision_import_batches(id) on delete restrict,
  row_index integer,
  backend_record_id uuid,
  source_record_id text,
  row_hash text,
  classification text not null check (classification in ('new', 'changed', 'unchanged', 'missing', 'invalid', 'conflict')),
  normalized_evidence jsonb,
  raw_evidence jsonb,
  candidate_vehicle_ids uuid[] not null default '{}'::uuid[],
  proposed_vehicle_id uuid references public.vehicles(id) on delete set null,
  before_record jsonb,
  after_record jsonb,
  reason text,
  created_at timestamptz not null default now(),
  unique (batch_id, row_index),
  check (row_index is null or row_index > 0),
  check (row_hash is null or row_hash ~ '^[0-9a-f]{64}$')
);

create table if not exists public.navision_operation_receipts (
  id uuid primary key default gen_random_uuid(),
  operation_kind text not null check (operation_kind in ('apply', 'rollback', 'link')),
  idempotency_key text not null,
  request_hash text not null check (request_hash ~ '^[0-9a-f]{64}$'),
  batch_id uuid references public.navision_import_batches(id) on delete restrict,
  response jsonb not null,
  actor_id uuid references auth.users(id) on delete set null,
  actor_email text,
  created_at timestamptz not null default now(),
  unique (operation_kind, idempotency_key)
);

create table if not exists public.navision_rollback_items (
  id uuid primary key default gen_random_uuid(),
  receipt_id uuid not null references public.navision_operation_receipts(id) on delete restrict,
  target_batch_id uuid not null references public.navision_import_batches(id) on delete restrict,
  backend_record_id uuid not null,
  action text not null check (action in ('deleted_new', 'restored')),
  before_rollback jsonb,
  after_rollback jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.navision_backend_audit (
  id uuid primary key default gen_random_uuid(),
  action text not null check (action in ('import_apply', 'import_rollback', 'canonical_link', 'canonical_unlink')),
  batch_id uuid references public.navision_import_batches(id) on delete restrict,
  backend_record_id uuid,
  canonical_vehicle_id uuid references public.vehicles(id) on delete set null,
  revision bigint not null check (revision > 0),
  evidence jsonb not null default '{}'::jsonb,
  actor_id uuid references auth.users(id) on delete set null,
  actor_email text,
  created_at timestamptz not null default now()
);

create index if not exists navision_import_batches_applied_idx
  on public.navision_import_batches (applied_at desc, id);
create index if not exists navision_backend_records_current_idx
  on public.navision_backend_records (is_current, source_record_id_normalized);
create index if not exists navision_backend_records_vehicle_idx
  on public.navision_backend_records (canonical_vehicle_id) where canonical_vehicle_id is not null;
create index if not exists navision_backend_records_last_batch_idx
  on public.navision_backend_records (last_seen_batch_id);
create index if not exists navision_import_items_batch_idx
  on public.navision_import_items (batch_id, classification, row_index);
create index if not exists navision_operation_receipts_batch_idx
  on public.navision_operation_receipts (batch_id, created_at desc);
create index if not exists navision_rollback_items_batch_idx
  on public.navision_rollback_items (target_batch_id, created_at desc);
create index if not exists navision_backend_audit_batch_idx
  on public.navision_backend_audit (batch_id, created_at desc);
create index if not exists navision_backend_audit_record_idx
  on public.navision_backend_audit (backend_record_id, created_at desc);

alter table public.navision_backend_revision enable row level security;
alter table public.navision_import_batches enable row level security;
alter table public.navision_backend_records enable row level security;
alter table public.navision_import_items enable row level security;
alter table public.navision_operation_receipts enable row level security;
alter table public.navision_rollback_items enable row level security;
alter table public.navision_backend_audit enable row level security;

revoke all on table public.navision_backend_revision from public, anon, authenticated;
revoke all on table public.navision_import_batches from public, anon, authenticated;
revoke all on table public.navision_backend_records from public, anon, authenticated;
revoke all on table public.navision_import_items from public, anon, authenticated;
revoke all on table public.navision_operation_receipts from public, anon, authenticated;
revoke all on table public.navision_rollback_items from public, anon, authenticated;
revoke all on table public.navision_backend_audit from public, anon, authenticated;

drop policy if exists navision_backend_revision_operator_read on public.navision_backend_revision;
create policy navision_backend_revision_operator_read
on public.navision_backend_revision for select to authenticated
using (coalesce(public.current_pdc_user_role()::text = any (array['operator', 'importer', 'administrator']), false));
grant select on table public.navision_backend_revision to authenticated;

create or replace function public.navision_backend_response(
  p_ok boolean,
  p_code text,
  p_data jsonb default '{}'::jsonb
)
returns jsonb
language sql
immutable
parallel safe
as $$
  select jsonb_build_object(
    'ok', coalesce(p_ok, false),
    'code', coalesce(nullif(btrim(p_code), ''), 'unknown'),
    'data', coalesce(p_data, '{}'::jsonb)
  );
$$;

create or replace function public.navision_backend_normalize_row(p_row jsonb)
returns jsonb
language sql
immutable
parallel safe
as $$
  select case when jsonb_typeof(p_row) = 'object' then coalesce((
    select jsonb_object_agg(key, case
      when jsonb_typeof(value) = 'string'
        then to_jsonb(nullif(btrim(value #>> '{}'), ''))
      else value
    end order by key)
    from jsonb_each(p_row)
  ), '{}'::jsonb) else null end;
$$;

create or replace function public.navision_backend_source_record_id(p_row jsonb)
returns text
language sql
immutable
parallel safe
as $$
  select public.normalize_vehicle_source_identifier(coalesce(
    nullif(btrim(p_row ->> 'id'), ''),
    nullif(btrim(p_row ->> 'source_record_id'), ''),
    nullif(btrim(p_row ->> 'sourceRecordId'), '')
  ));
$$;

create or replace function public.navision_backend_row_has_forbidden_fields(p_row jsonb)
returns boolean
language sql
immutable
parallel safe
as $$
  select jsonb_typeof(p_row) <> 'object';
$$;

create or replace function public.navision_backend_row_hash(p_row jsonb)
returns text
language sql
immutable
parallel safe
as $$
  select encode(extensions.digest(coalesce(public.navision_backend_normalize_row(p_row), 'null'::jsonb)::text, 'sha256'), 'hex');
$$;

create or replace function public.navision_backend_candidate_vehicle_ids(p_row jsonb)
returns uuid[]
language sql
stable
security definer
set search_path = pg_catalog, public, extensions
as $$
  with input as (
    select
      public.normalize_vehicle_vin(p_row ->> 'vin') as vin,
      public.normalize_vehicle_stock_number(coalesce(p_row ->> 'stock', p_row ->> 'stock_number')) as stock,
      public.normalize_vehicle_source_identifier(coalesce(p_row ->> 'order', p_row ->> 'toyota_order_number')) as order_no
  ), candidates as (
    select v.id
    from public.vehicles v, input i
    where (i.vin is not null and public.is_valid_vehicle_vin(p_row ->> 'vin') and v.vin_normalized = i.vin)
       or (i.stock is not null and public.is_real_vehicle_stock_number(coalesce(p_row ->> 'stock', p_row ->> 'stock_number')) and v.stock_number_normalized = i.stock)
       or (i.order_no is not null and public.normalize_vehicle_source_identifier(v.toyota_order_number) = i.order_no)
    union
    select a.vehicle_id
    from public.vehicle_aliases a, input i
    where a.active and (
      (i.vin is not null and a.alias_type_normalized = 'vin' and a.normalized_alias_value = i.vin)
      or (i.stock is not null and a.alias_type_normalized = 'stock_number' and a.normalized_alias_value = i.stock)
      or (i.order_no is not null and a.alias_type_normalized = 'toyota_order_number'
          and a.normalized_alias_value = i.order_no
          and a.source_system_normalized in ('navision', 'microsoft-navision'))
    )
  )
  select coalesce(array_agg(distinct id order by id), '{}'::uuid[]) from candidates;
$$;

create or replace function public.navision_backend_preview_internal(
  p_rows jsonb,
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
begin
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
  from public.navision_backend_records r;

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
      b.row_hash as existing_hash,
      b.canonical_vehicle_id,
      public.navision_backend_candidate_vehicle_ids(r.raw_row) as candidates
    from rows r
    left join public.navision_backend_records b
      on b.source_record_id_normalized = r.source_record_id
  ), item_rows as (
    select row_index, source_record_id, row_hash, backend_record_id,
      case
        when jsonb_typeof(raw_row) <> 'object' or source_record_id is null or forbidden then 'invalid'
        when identity_count > 1 or cardinality(candidates) > 1 then 'conflict'
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
  where b.is_current
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
    'contract_version', 1,
    'source_name', btrim(p_source_name),
    'source_timestamp', p_source_timestamp,
    'source_hash', v_source_hash,
    'base_revision', v_revision,
    'destination_hash', v_destination_hash,
    'items', v_items,
    'missing', v_missing
  )::text, 'sha256'), 'hex');

  return public.navision_backend_response(true, 'preview_ready', jsonb_build_object(
    'contract_version', 1,
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
  return public.navision_backend_preview_internal(p_rows, p_source_name, p_source_timestamp);
end;
$$;

create or replace function public.apply_navision_backend_import(
  p_idempotency_key text,
  p_rows jsonb,
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
    'contract_version', 1,
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

  v_preview := public.navision_backend_preview_internal(p_rows, p_source_name, p_source_timestamp);
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
    id, idempotency_key, request_hash, source_name, source_timestamp, source_hash,
    preview_hash, base_revision, result_revision, total_rows, new_count,
    changed_count, unchanged_count, missing_count, invalid_count, conflict_count,
    actor_id, actor_email
  ) values (
    v_batch_id, btrim(p_idempotency_key), v_request_hash, btrim(p_source_name),
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
    where source_record_id_normalized = v_source_record_id for update;
    if found then
      v_before := to_jsonb(v_record);
      update public.navision_backend_records
      set source_record_id = coalesce(nullif(btrim(v_row ->> 'id'), ''), v_source_record_id),
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
        source_record_id, row_hash, normalized_data, raw_evidence,
        first_seen_batch_id, last_seen_batch_id
      ) values (
        coalesce(nullif(btrim(v_row ->> 'id'), ''), v_source_record_id),
        v_row_hash, v_normalized, v_row, v_batch_id, v_batch_id
      ) returning * into v_record;
      v_before := null;
    end if;
    select * into v_record from public.navision_backend_records
      where source_record_id_normalized = v_source_record_id;
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
    set is_current = false, missing_since_batch_id = v_batch_id,
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
    jsonb_build_object('source_hash', v_data ->> 'source_hash', 'counts', v_counts, 'operational_mutations', 0),
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
        id, source_record_id, row_hash, normalized_data, raw_evidence,
        canonical_vehicle_id, first_seen_batch_id, last_seen_batch_id,
        missing_since_batch_id, is_current, version, created_at, updated_at
      ) values (
        v_restored.id, v_restored.source_record_id, v_restored.row_hash,
        v_restored.normalized_data, v_restored.raw_evidence,
        v_restored.canonical_vehicle_id, v_restored.first_seen_batch_id,
        v_restored.last_seen_batch_id, v_restored.missing_since_batch_id,
        v_restored.is_current, v_restored.version, v_restored.created_at,
        v_restored.updated_at
      ) on conflict (id) do update set
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

create or replace function public.link_navision_backend_record(
  p_idempotency_key text,
  p_backend_record_id text,
  p_canonical_vehicle_id text,
  p_expected_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $link$
declare
  v_record_id uuid;
  v_vehicle_id uuid;
  v_request_hash text;
  v_existing public.navision_operation_receipts%rowtype;
  v_record public.navision_backend_records%rowtype;
  v_revision bigint;
  v_response jsonb;
  v_action text;
begin
  if public.current_pdc_user_role() is distinct from 'administrator' then
    return public.navision_backend_response(false, 'unauthorized');
  end if;
  if coalesce(p_backend_record_id, '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    return public.navision_backend_response(false, 'invalid_input', jsonb_build_object('field', 'backend_record_id'));
  end if;
  v_record_id := btrim(p_backend_record_id)::uuid;
  if nullif(btrim(coalesce(p_canonical_vehicle_id, '')), '') is not null then
    if p_canonical_vehicle_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      return public.navision_backend_response(false, 'invalid_input', jsonb_build_object('field', 'canonical_vehicle_id'));
    end if;
    v_vehicle_id := btrim(p_canonical_vehicle_id)::uuid;
  end if;
  if nullif(btrim(p_idempotency_key), '') is null or length(p_idempotency_key) > 200 then
    return public.navision_backend_response(false, 'invalid_input', jsonb_build_object('field', 'idempotency_key'));
  end if;
  v_request_hash := encode(extensions.digest(jsonb_build_object(
    'contract_version', 1, 'idempotency_key', btrim(p_idempotency_key),
    'backend_record_id', v_record_id, 'canonical_vehicle_id', v_vehicle_id,
    'expected_revision', p_expected_revision
  )::text, 'sha256'), 'hex');

  perform pg_advisory_xact_lock(hashtextextended('navision-link:' || btrim(p_idempotency_key), 0));
  select * into v_existing from public.navision_operation_receipts
    where operation_kind = 'link' and idempotency_key = btrim(p_idempotency_key);
  if found then
    if v_existing.request_hash <> v_request_hash then return public.navision_backend_response(false, 'idempotency_conflict'); end if;
    return v_existing.response;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('navision-backend-store', 0));
  select revision into v_revision from public.navision_backend_revision where singleton for update;
  if v_revision is distinct from p_expected_revision then
    return public.navision_backend_response(false, 'stale_revision', jsonb_build_object('current_revision', v_revision));
  end if;
  select * into v_record from public.navision_backend_records where id = v_record_id for update;
  if not found then return public.navision_backend_response(false, 'record_not_found'); end if;
  if v_vehicle_id is not null and not exists (select 1 from public.vehicles where id = v_vehicle_id) then
    return public.navision_backend_response(false, 'vehicle_not_found');
  end if;
  if v_record.canonical_vehicle_id is not distinct from v_vehicle_id then
    v_action := case when v_vehicle_id is null then 'canonical_unlink' else 'canonical_link' end;
  else
    update public.navision_backend_records
    set canonical_vehicle_id = v_vehicle_id, version = version + 1, updated_at = now()
    where id = v_record_id;
    update public.navision_backend_revision set revision = v_revision + 1, updated_at = now() where singleton;
    v_revision := v_revision + 1;
    v_action := case when v_vehicle_id is null then 'canonical_unlink' else 'canonical_link' end;
  end if;
  v_response := public.navision_backend_response(true, 'linked', jsonb_build_object(
    'backend_record_id', v_record_id, 'canonical_vehicle_id', v_vehicle_id,
    'result_revision', v_revision, 'operational_mutations', 0
  ));
  insert into public.navision_operation_receipts (
    operation_kind, idempotency_key, request_hash, response, actor_id, actor_email
  ) values ('link', btrim(p_idempotency_key), v_request_hash, v_response, auth.uid(), public.current_actor_email());
  insert into public.navision_backend_audit (
    action, backend_record_id, canonical_vehicle_id, revision, evidence, actor_id, actor_email
  ) values (v_action, v_record_id, v_vehicle_id, v_revision,
    jsonb_build_object('operational_mutations', 0), auth.uid(), public.current_actor_email());
  return v_response;
end;
$link$;

create or replace function public.get_navision_backend_snapshot(
  p_after_source_record_id text default null,
  p_page_size integer default 200,
  p_expected_revision bigint default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_role text;
  v_revision bigint;
  v_page_size integer;
  v_result jsonb;
begin
  v_role := public.current_pdc_user_role();
  if not coalesce(v_role::text = any (array['operator', 'importer', 'administrator']), false) then
    return public.navision_backend_response(false, 'unauthorized');
  end if;
  if p_page_size is null or p_page_size < 1 then
    return public.navision_backend_response(false, 'invalid_input', jsonb_build_object('field', 'page_size'));
  end if;
  v_page_size := least(p_page_size, 500);
  select revision into v_revision from public.navision_backend_revision where singleton;
  if p_expected_revision is not null and p_expected_revision <> v_revision then
    return public.navision_backend_response(false, 'stale_revision', jsonb_build_object('current_revision', v_revision));
  end if;
  with page as (
    select r.* from public.navision_backend_records r
    where p_after_source_record_id is null or r.source_record_id_normalized > public.normalize_vehicle_source_identifier(p_after_source_record_id)
    order by r.source_record_id_normalized limit v_page_size + 1
  ), selected as (
    select * from page order by source_record_id_normalized limit v_page_size
  )
  select public.navision_backend_response(true, 'snapshot', jsonb_build_object(
    'revision', v_revision,
    'page_size', v_page_size,
    'items', coalesce(jsonb_agg(jsonb_build_object(
      'id', id, 'source_record_id', source_record_id, 'row_hash', row_hash,
      'canonical_vehicle_id', canonical_vehicle_id,
      'is_current', is_current, 'version', version,
      'first_seen_batch_id', first_seen_batch_id, 'last_seen_batch_id', last_seen_batch_id,
      'missing_since_batch_id', missing_since_batch_id, 'updated_at', updated_at
    ) || case when v_role::text = any (array['importer', 'administrator'])
      then jsonb_build_object('normalized_data', normalized_data)
      else '{}'::jsonb end order by source_record_id_normalized), '[]'::jsonb),
    'has_more', (select count(*) > v_page_size from page),
    'next_cursor', case when (select count(*) > v_page_size from page)
      then (select max(source_record_id_normalized) from selected) else null end,
    'authority', 'shared_navision_backend_only',
    'data_access', case when v_role::text = any (array['importer', 'administrator']) then 'normalized' else 'metadata_only' end
  )) into v_result from selected;
  return v_result;
end;
$$;

create or replace function public.export_navision_backend_records(
  p_after_source_record_id text default null,
  p_page_size integer default 200,
  p_expected_revision bigint default null
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
  return public.get_navision_backend_snapshot(p_after_source_record_id, least(coalesce(p_page_size, 200), 500), p_expected_revision);
end;
$$;

create or replace function public.get_navision_reconciliation_report(
  p_batch_id text,
  p_after_row_index integer default 0,
  p_page_size integer default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_batch uuid;
  v_page_size integer;
  v_result jsonb;
begin
  if not coalesce(public.current_pdc_user_role()::text = any (array['importer', 'administrator']), false) then
    return public.navision_backend_response(false, 'unauthorized');
  end if;
  if coalesce(p_batch_id, '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    return public.navision_backend_response(false, 'invalid_input', jsonb_build_object('field', 'batch_id'));
  end if;
  v_batch := btrim(p_batch_id)::uuid;
  v_page_size := greatest(1, least(coalesce(p_page_size, 200), 500));
  if not exists (select 1 from public.navision_import_batches where id = v_batch) then
    return public.navision_backend_response(false, 'batch_not_found');
  end if;
  with page as (
    select i.* from public.navision_import_items i
    where i.batch_id = v_batch and coalesce(i.row_index, 2147483647) > coalesce(p_after_row_index, 0)
    order by coalesce(i.row_index, 2147483647), i.id limit v_page_size + 1
  ), selected as (
    select * from page order by coalesce(row_index, 2147483647), id limit v_page_size
  )
  select public.navision_backend_response(true, 'reconciliation', jsonb_build_object(
    'batch_id', v_batch,
    'batch', (select jsonb_build_object(
      'source_name', b.source_name, 'source_timestamp', b.source_timestamp,
      'source_hash', b.source_hash, 'preview_hash', b.preview_hash,
      'base_revision', b.base_revision, 'result_revision', b.result_revision,
      'status', b.status,
      'counts', jsonb_build_object('total', b.total_rows, 'new', b.new_count,
        'changed', b.changed_count, 'unchanged', b.unchanged_count,
        'missing', b.missing_count, 'invalid', b.invalid_count, 'conflict', b.conflict_count)
      ) from public.navision_import_batches b where b.id = v_batch),
    'items', coalesce(jsonb_agg(jsonb_build_object(
      'row_index', row_index, 'backend_record_id', backend_record_id,
      'source_record_id', source_record_id, 'row_hash', row_hash,
      'classification', classification, 'candidate_vehicle_ids', candidate_vehicle_ids,
      'proposed_vehicle_id', proposed_vehicle_id, 'reason', reason
    ) order by coalesce(row_index, 2147483647), id), '[]'::jsonb),
    'has_more', (select count(*) > v_page_size from page),
    'next_row_index', case when (select count(*) > v_page_size from page)
      then (select max(coalesce(row_index, 2147483647)) from selected) else null end
  )) into v_result from selected;
  return v_result;
end;
$$;

-- No function is executable by default. Internal helpers remain owner-only;
-- browser contracts receive explicit authenticated EXECUTE and enforce exact
-- business roles inside SECURITY DEFINER code.
revoke all on function public.navision_backend_response(boolean, text, jsonb) from public, anon, authenticated;
revoke all on function public.navision_backend_normalize_row(jsonb) from public, anon, authenticated;
revoke all on function public.navision_backend_source_record_id(jsonb) from public, anon, authenticated;
revoke all on function public.navision_backend_row_has_forbidden_fields(jsonb) from public, anon, authenticated;
revoke all on function public.navision_backend_row_hash(jsonb) from public, anon, authenticated;
revoke all on function public.navision_backend_candidate_vehicle_ids(jsonb) from public, anon, authenticated;
revoke all on function public.navision_backend_preview_internal(jsonb, text, timestamptz) from public, anon, authenticated;
revoke all on function public.preview_navision_backend_import(jsonb, text, timestamptz) from public, anon, authenticated;
revoke all on function public.apply_navision_backend_import(text, jsonb, text, timestamptz, text, text, bigint) from public, anon, authenticated;
revoke all on function public.rollback_navision_backend_import(text, text, bigint) from public, anon, authenticated;
revoke all on function public.link_navision_backend_record(text, text, text, bigint) from public, anon, authenticated;
revoke all on function public.get_navision_backend_snapshot(text, integer, bigint) from public, anon, authenticated;
revoke all on function public.export_navision_backend_records(text, integer, bigint) from public, anon, authenticated;
revoke all on function public.get_navision_reconciliation_report(text, integer, integer) from public, anon, authenticated;

grant execute on function public.preview_navision_backend_import(jsonb, text, timestamptz) to authenticated;
grant execute on function public.apply_navision_backend_import(text, jsonb, text, timestamptz, text, text, bigint) to authenticated;
grant execute on function public.rollback_navision_backend_import(text, text, bigint) to authenticated;
grant execute on function public.link_navision_backend_record(text, text, text, bigint) to authenticated;
grant execute on function public.get_navision_backend_snapshot(text, integer, bigint) to authenticated;
grant execute on function public.export_navision_backend_records(text, integer, bigint) to authenticated;
grant execute on function public.get_navision_reconciliation_report(text, integer, integer) to authenticated;

-- Realtime publishes only the narrow revision signal. Backend rows, source
-- evidence, receipts and audit records are never published or directly readable.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename = 'navision_backend_revision'
  ) then
    alter publication supabase_realtime add table public.navision_backend_revision;
  end if;
end;
$$;
