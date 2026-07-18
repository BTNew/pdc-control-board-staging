-- Migration 028: Stage 2B shared vehicle-master foundation.
--
-- This migration is intentionally additive. It preserves every existing
-- operational vehicle field and does not introduce the protected Stage 2B
-- mutation RPCs planned for migration 029. The read-only sanitized core
-- snapshot required for safe consumer cutover is included here.

begin;

-- Canonical comparison helpers. Raw source text remains on the owning row as
-- evidence; these helpers only define deterministic matching/index values.
create or replace function public.normalize_vehicle_stock_number(p_value text)
returns text
language sql
immutable
returns null on null input
parallel safe
as $$
  select nullif(regexp_replace(upper(btrim(p_value)), '[[:space:]-]+', '', 'g'), '');
$$;

create or replace function public.is_real_vehicle_stock_number(p_value text)
returns boolean
language sql
immutable
returns null on null input
parallel safe
as $$
  select coalesce(
    public.normalize_vehicle_stock_number(p_value) <> all (array[
      '0', 'TBA', 'TBD', 'UNKNOWN', 'NA', 'N/A', 'NONE', 'UNASSIGNED'
    ])
    and upper(btrim(p_value)) not like 'NEW-%'
    and upper(btrim(p_value)) not like 'PD-%'
    and upper(btrim(p_value)) not like 'PENDING-%'
    and upper(btrim(p_value)) not like 'TEMP-%',
    false
  );
$$;

create or replace function public.normalize_vehicle_vin(p_value text)
returns text
language sql
immutable
returns null on null input
parallel safe
as $$
  select nullif(regexp_replace(upper(btrim(p_value)), '[[:space:]-]+', '', 'g'), '');
$$;

create or replace function public.is_valid_vehicle_vin(p_value text)
returns boolean
language sql
immutable
returns null on null input
parallel safe
as $$
  select coalesce(public.normalize_vehicle_vin(p_value) ~ '^[A-HJ-NPR-Z0-9]{17}$', false);
$$;

create or replace function public.normalize_vehicle_source_identifier(p_value text)
returns text
language sql
immutable
returns null on null input
parallel safe
as $$
  select nullif(upper(btrim(p_value)), '');
$$;

create or replace function public.normalize_vehicle_source_system(p_value text)
returns text
language sql
immutable
returns null on null input
parallel safe
as $$
  select nullif(lower(btrim(p_value)), '');
$$;

create or replace function public.normalize_vehicle_alias_value(p_alias_type text, p_value text)
returns text
language sql
immutable
parallel safe
as $$
  select case lower(btrim(coalesce(p_alias_type, '')))
    when 'stock_number' then public.normalize_vehicle_stock_number(p_value)
    when 'vin' then public.normalize_vehicle_vin(p_value)
    else public.normalize_vehicle_source_identifier(p_value)
  end;
$$;

-- A stable structured envelope for the SECURITY DEFINER RPCs in migration 029.
-- It is an internal helper, not a browser-callable Stage 2B RPC.
create or replace function public.vehicle_master_response(
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

-- Core identity/master additions only. Existing workflow/lifecycle columns are
-- deliberately untouched.
alter table public.vehicles
  add column if not exists key_number text,
  add column if not exists vehicle_description text,
  add column if not exists salesperson_reference text,
  add column if not exists arrival_reference_date date,
  add column if not exists source_system text,
  add column if not exists source_batch_id text,
  add column if not exists source_record_id text,
  add column if not exists stock_number_normalized text
    generated always as (public.normalize_vehicle_stock_number(stock_number)) stored,
  add column if not exists vin_normalized text
    generated always as (
      case when public.is_valid_vehicle_vin(vin)
        then public.normalize_vehicle_vin(vin)
        else null
      end
    ) stored,
  add column if not exists source_system_normalized text
    generated always as (public.normalize_vehicle_source_system(source_system)) stored,
  add column if not exists source_record_id_normalized text
    generated always as (public.normalize_vehicle_source_identifier(source_record_id)) stored;

-- NOT VALID surfaces legacy invalid values without rolling back this migration.
-- PostgreSQL still enforces these checks for newly inserted/changed rows.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.vehicles'::regclass
      and conname = 'vehicles_master_vin_valid'
  ) then
    alter table public.vehicles
      add constraint vehicles_master_vin_valid
      check (vin_normalized is null or public.is_valid_vehicle_vin(vin_normalized)) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.vehicles'::regclass
      and conname = 'vehicles_master_version_positive'
  ) then
    alter table public.vehicles
      add constraint vehicles_master_version_positive
      check (version > 0) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.vehicles'::regclass
      and conname = 'vehicles_master_source_pair'
  ) then
    alter table public.vehicles
      add constraint vehicles_master_source_pair
      check (
        (source_system_normalized is null and source_record_id_normalized is null)
        or (source_system_normalized is not null and source_record_id_normalized is not null)
      ) not valid;
  end if;
end;
$$;

-- Alias evidence and optimistic metadata. The original alias_value and the
-- original unique constraint remain intact for backward compatibility.
alter table public.vehicle_aliases
  add column if not exists alias_type_normalized text
    generated always as (lower(btrim(alias_type))) stored,
  add column if not exists normalized_alias_value text
    generated always as (public.normalize_vehicle_alias_value(alias_type, alias_value)) stored,
  add column if not exists source_system text,
  add column if not exists source_system_normalized text
    generated always as (public.normalize_vehicle_source_system(source_system)) stored,
  add column if not exists source_batch_id text,
  add column if not exists version integer not null default 1,
  add column if not exists created_by uuid references auth.users(id),
  add column if not exists updated_by uuid references auth.users(id),
  add column if not exists updated_at timestamptz not null default now();

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.vehicle_aliases'::regclass
      and conname = 'vehicle_aliases_master_version_positive'
  ) then
    alter table public.vehicle_aliases
      add constraint vehicle_aliases_master_version_positive
      check (version > 0) not valid;
  end if;
end;
$$;

-- Restore order: vehicles before vehicle_aliases, vehicle_master_history and
-- vehicle_master_identity_conflicts. History keeps its audit row if a vehicle
-- is later removed; aliases retain their existing vehicle FK semantics.
create table if not exists public.vehicle_master_revision (
  singleton boolean primary key default true check (singleton),
  revision bigint not null default 1 check (revision > 0),
  updated_at timestamptz not null default now()
);

insert into public.vehicle_master_revision (singleton, revision)
values (true, 1)
on conflict (singleton) do nothing;

-- Raw import/source evidence is deliberately separated from vehicles and
-- vehicle_aliases. Those two legacy tables must retain their existing broad
-- read compatibility until every frontend consumer uses the sanitized RPC;
-- adding raw JSON columns to either would silently expand viewer exposure.
create table if not exists public.vehicle_master_source_records (
  id uuid primary key default gen_random_uuid(),
  vehicle_id uuid not null references public.vehicles(id) on delete cascade,
  alias_id uuid references public.vehicle_aliases(id) on delete set null,
  source_system text not null,
  source_batch_id text,
  source_record_id text,
  source_metadata jsonb not null default '{}'::jsonb,
  original_evidence jsonb not null default '{}'::jsonb,
  version integer not null default 1 check (version > 0),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists vehicle_master_source_records_vehicle_idx
  on public.vehicle_master_source_records (vehicle_id, created_at desc);
create index if not exists vehicle_master_source_records_source_idx
  on public.vehicle_master_source_records (
    public.normalize_vehicle_source_system(source_system),
    public.normalize_vehicle_source_identifier(source_record_id)
  ) where public.normalize_vehicle_source_identifier(source_record_id) is not null;

create table if not exists public.vehicle_master_history (
  id uuid primary key default gen_random_uuid(),
  vehicle_id uuid references public.vehicles(id) on delete set null,
  entity_type text not null check (entity_type in ('vehicle', 'alias')),
  entity_id uuid not null,
  action text not null check (action in ('insert', 'update', 'delete', 'import')),
  expected_version integer,
  resulting_version integer,
  master_revision bigint not null,
  before_data jsonb,
  after_data jsonb,
  actor_id uuid references auth.users(id) on delete set null,
  actor_email text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists vehicle_master_history_vehicle_idx
  on public.vehicle_master_history (vehicle_id, created_at desc);
create index if not exists vehicle_master_history_entity_idx
  on public.vehicle_master_history (entity_type, entity_id, created_at desc);

-- Legacy duplicates are durable review evidence, not an unhelpful migration
-- exception. Re-running 028 refreshes last_seen_at/count/IDs. Once conflicts
-- are resolved, a rerun creates the corresponding unique indexes below.
create table if not exists public.vehicle_master_identity_conflicts (
  id uuid primary key default gen_random_uuid(),
  conflict_kind text not null,
  scope_key text not null default 'global',
  normalized_value text not null,
  vehicle_ids uuid[] not null default '{}'::uuid[],
  occurrence_count integer not null check (occurrence_count > 1),
  evidence jsonb not null default '{}'::jsonb,
  detected_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  resolved_at timestamptz,
  unique (conflict_kind, scope_key, normalized_value)
);

-- Mark the previous scan stale before refreshing current conflicts. This keeps
-- the evidence append-safe while making a rerun an accurate cleanup report.
update public.vehicle_master_identity_conflicts
set resolved_at = coalesce(resolved_at, now())
where conflict_kind in (
  'duplicate_vehicle_vin',
  'duplicate_vehicle_stock',
  'duplicate_vehicle_source_record',
  'duplicate_global_alias',
  'duplicate_source_alias'
);

insert into public.vehicle_master_identity_conflicts (
  conflict_kind, scope_key, normalized_value, vehicle_ids, occurrence_count, evidence
)
select
  'duplicate_vehicle_vin', 'global', vin_normalized,
  array_agg(id order by id), count(*)::integer,
  jsonb_build_object('raw_values', jsonb_agg(vin order by id))
from public.vehicles
where public.is_valid_vehicle_vin(vin)
group by vin_normalized
having count(*) > 1
on conflict (conflict_kind, scope_key, normalized_value) do update
set vehicle_ids = excluded.vehicle_ids,
    occurrence_count = excluded.occurrence_count,
    evidence = excluded.evidence,
    last_seen_at = now(),
    resolved_at = null;

insert into public.vehicle_master_identity_conflicts (
  conflict_kind, scope_key, normalized_value, vehicle_ids, occurrence_count, evidence
)
select
  'duplicate_vehicle_stock', 'global', stock_number_normalized,
  array_agg(id order by id), count(*)::integer,
  jsonb_build_object('raw_values', jsonb_agg(stock_number order by id))
from public.vehicles
where public.is_real_vehicle_stock_number(stock_number)
group by stock_number_normalized
having count(*) > 1
on conflict (conflict_kind, scope_key, normalized_value) do update
set vehicle_ids = excluded.vehicle_ids,
    occurrence_count = excluded.occurrence_count,
    evidence = excluded.evidence,
    last_seen_at = now(),
    resolved_at = null;

insert into public.vehicle_master_identity_conflicts (
  conflict_kind, scope_key, normalized_value, vehicle_ids, occurrence_count, evidence
)
select
  'duplicate_vehicle_source_record', source_system_normalized, source_record_id_normalized,
  array_agg(id order by id), count(*)::integer,
  jsonb_build_object('source_system', source_system_normalized)
from public.vehicles
where source_system_normalized is not null and source_record_id_normalized is not null
group by source_system_normalized, source_record_id_normalized
having count(*) > 1
on conflict (conflict_kind, scope_key, normalized_value) do update
set vehicle_ids = excluded.vehicle_ids,
    occurrence_count = excluded.occurrence_count,
    evidence = excluded.evidence,
    last_seen_at = now(),
    resolved_at = null;

insert into public.vehicle_master_identity_conflicts (
  conflict_kind, scope_key, normalized_value, vehicle_ids, occurrence_count, evidence
)
select
  'duplicate_global_alias', lower(btrim(alias_type)), normalized_alias_value,
  array_agg(distinct vehicle_id order by vehicle_id), count(*)::integer,
  jsonb_build_object('alias_ids', jsonb_agg(id order by id))
from public.vehicle_aliases
where active
  and lower(btrim(alias_type)) in ('vin', 'stock_number')
  and (
    (lower(btrim(alias_type)) = 'vin' and public.is_valid_vehicle_vin(alias_value))
    or (lower(btrim(alias_type)) = 'stock_number' and public.is_real_vehicle_stock_number(alias_value))
  )
group by lower(btrim(alias_type)), normalized_alias_value
having count(*) > 1
on conflict (conflict_kind, scope_key, normalized_value) do update
set vehicle_ids = excluded.vehicle_ids,
    occurrence_count = excluded.occurrence_count,
    evidence = excluded.evidence,
    last_seen_at = now(),
    resolved_at = null;

insert into public.vehicle_master_identity_conflicts (
  conflict_kind, scope_key, normalized_value, vehicle_ids, occurrence_count, evidence
)
select
  'duplicate_source_alias', source_system_normalized || ':' || lower(btrim(alias_type)), normalized_alias_value,
  array_agg(distinct vehicle_id order by vehicle_id), count(*)::integer,
  jsonb_build_object('alias_ids', jsonb_agg(id order by id))
from public.vehicle_aliases
where active
  and source_system_normalized is not null
  and normalized_alias_value is not null
  and lower(btrim(alias_type)) in ('source_record_id', 'toyota_order_number', 'job_card_number')
group by source_system_normalized, lower(btrim(alias_type)), normalized_alias_value
having count(*) > 1
on conflict (conflict_kind, scope_key, normalized_value) do update
set vehicle_ids = excluded.vehicle_ids,
    occurrence_count = excluded.occurrence_count,
    evidence = excluded.evidence,
    last_seen_at = now(),
    resolved_at = null;

-- Create each deterministic index only when its legacy data is clean. This is
-- deliberately conditional: existing duplicates are committed to the review
-- table instead of causing the entire migration (and its evidence) to abort.
do $$
begin
  if not exists (
    select 1 from public.vehicles
    where public.is_valid_vehicle_vin(vin)
    group by vin_normalized having count(*) > 1
  ) and not exists (
    select 1 from pg_indexes where schemaname = 'public' and indexname = 'vehicles_master_vin_unique_idx'
  ) then
    execute $index$create unique index vehicles_master_vin_unique_idx
      on public.vehicles (vin_normalized)
      where public.is_valid_vehicle_vin(vin)$index$;
  end if;

  if not exists (
    select 1 from public.vehicles
    where public.is_real_vehicle_stock_number(stock_number)
    group by stock_number_normalized having count(*) > 1
  ) and not exists (
    select 1 from pg_indexes where schemaname = 'public' and indexname = 'vehicles_master_stock_unique_idx'
  ) then
    execute $index$create unique index vehicles_master_stock_unique_idx
      on public.vehicles (stock_number_normalized)
      where public.is_real_vehicle_stock_number(stock_number)$index$;
  end if;

  if not exists (
    select 1 from public.vehicles
    where source_system_normalized is not null and source_record_id_normalized is not null
    group by source_system_normalized, source_record_id_normalized having count(*) > 1
  ) and not exists (
    select 1 from pg_indexes where schemaname = 'public' and indexname = 'vehicles_master_source_unique_idx'
  ) then
    execute $index$create unique index vehicles_master_source_unique_idx
      on public.vehicles (source_system_normalized, source_record_id_normalized)
      where source_system_normalized is not null and source_record_id_normalized is not null$index$;
  end if;

  if not exists (
    select 1 from public.vehicle_aliases
    where active
      and alias_type_normalized in ('vin', 'stock_number')
      and (
        (alias_type_normalized = 'vin' and public.is_valid_vehicle_vin(alias_value))
        or (alias_type_normalized = 'stock_number' and public.is_real_vehicle_stock_number(alias_value))
      )
    group by alias_type_normalized, normalized_alias_value having count(*) > 1
  ) and not exists (
    select 1 from pg_indexes where schemaname = 'public' and indexname = 'vehicle_aliases_master_global_unique_idx'
  ) then
    execute $index$create unique index vehicle_aliases_master_global_unique_idx
      on public.vehicle_aliases (alias_type_normalized, normalized_alias_value)
      where active
        and alias_type_normalized in ('vin', 'stock_number')
        and (
          (alias_type_normalized = 'vin' and public.is_valid_vehicle_vin(alias_value))
          or (alias_type_normalized = 'stock_number' and public.is_real_vehicle_stock_number(alias_value))
        )$index$;
  end if;

  if not exists (
    select 1 from public.vehicle_aliases
    where active
      and source_system_normalized is not null
      and normalized_alias_value is not null
      and alias_type_normalized in ('source_record_id', 'toyota_order_number', 'job_card_number')
    group by source_system_normalized, alias_type_normalized, normalized_alias_value having count(*) > 1
  ) and not exists (
    select 1 from pg_indexes where schemaname = 'public' and indexname = 'vehicle_aliases_master_source_unique_idx'
  ) then
    execute $index$create unique index vehicle_aliases_master_source_unique_idx
      on public.vehicle_aliases (source_system_normalized, alias_type_normalized, normalized_alias_value)
      where active
        and source_system_normalized is not null
        and normalized_alias_value is not null
        and alias_type_normalized in ('source_record_id', 'toyota_order_number', 'job_card_number')$index$;
  end if;
end;
$$;

-- When a legacy conflict prevented an index from being created, these guards
-- still prevent new or changed rows from introducing another deterministic
-- identity collision. They are scoped to identity columns, so unrelated
-- operational updates on legacy-conflicted vehicles remain possible.
create or replace function public.enforce_vehicle_master_identity_uniqueness()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.is_valid_vehicle_vin(new.vin) then
    perform pg_advisory_xact_lock(hashtextextended(
      'vehicle-master:vin:' || public.normalize_vehicle_vin(new.vin), 0
    ));
    if exists (
      select 1 from public.vehicles v
      where v.id <> new.id
        and public.is_valid_vehicle_vin(v.vin)
        and v.vin_normalized = public.normalize_vehicle_vin(new.vin)
    ) then
      raise exception 'duplicate canonical VIN'
        using errcode = '23505',
              detail = public.vehicle_master_response(false, 'duplicate_candidate', jsonb_build_object('field', 'vin'))::text;
    end if;
  end if;

  if public.is_real_vehicle_stock_number(new.stock_number) then
    perform pg_advisory_xact_lock(hashtextextended(
      'vehicle-master:stock:' || public.normalize_vehicle_stock_number(new.stock_number), 0
    ));
    if exists (
      select 1 from public.vehicles v
      where v.id <> new.id
        and public.is_real_vehicle_stock_number(v.stock_number)
        and v.stock_number_normalized = public.normalize_vehicle_stock_number(new.stock_number)
    ) then
      raise exception 'duplicate canonical stock number'
        using errcode = '23505',
              detail = public.vehicle_master_response(false, 'duplicate_candidate', jsonb_build_object('field', 'stock_number'))::text;
    end if;
  end if;

  if public.normalize_vehicle_source_system(new.source_system) is not null
     and public.normalize_vehicle_source_identifier(new.source_record_id) is not null then
    perform pg_advisory_xact_lock(hashtextextended(
      'vehicle-master:source:' || public.normalize_vehicle_source_system(new.source_system)
        || ':' || public.normalize_vehicle_source_identifier(new.source_record_id), 0
    ));
    if exists (
      select 1 from public.vehicles v
      where v.id <> new.id
        and v.source_system_normalized = public.normalize_vehicle_source_system(new.source_system)
        and v.source_record_id_normalized = public.normalize_vehicle_source_identifier(new.source_record_id)
    ) then
      raise exception 'duplicate source-scoped vehicle identifier'
        using errcode = '23505',
              detail = public.vehicle_master_response(false, 'duplicate_candidate', jsonb_build_object('field', 'source_record_id'))::text;
    end if;
  end if;

  return new;
end;
$$;

create or replace function public.enforce_vehicle_alias_identity_uniqueness()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_type text := lower(btrim(new.alias_type));
  v_value text := public.normalize_vehicle_alias_value(new.alias_type, new.alias_value);
  v_source text := public.normalize_vehicle_source_system(new.source_system);
begin
  if new.active and (
    (v_type = 'vin' and public.is_valid_vehicle_vin(new.alias_value))
    or (v_type = 'stock_number' and public.is_real_vehicle_stock_number(new.alias_value))
  ) then
    perform pg_advisory_xact_lock(hashtextextended(
      'vehicle-master:alias:' || v_type || ':' || v_value, 0
    ));
    if exists (
      select 1 from public.vehicle_aliases a
      where a.id <> new.id
        and a.active
        and a.alias_type_normalized = v_type
        and a.normalized_alias_value = v_value
    ) then
      raise exception 'duplicate global vehicle alias'
        using errcode = '23505',
              detail = public.vehicle_master_response(false, 'duplicate_candidate', jsonb_build_object('field', v_type))::text;
    end if;
  end if;

  if new.active
     and v_type in ('source_record_id', 'toyota_order_number', 'job_card_number')
     and v_source is not null
     and v_value is not null then
    perform pg_advisory_xact_lock(hashtextextended(
      'vehicle-master:source-alias:' || v_source || ':' || v_type || ':' || v_value, 0
    ));
    if exists (
      select 1 from public.vehicle_aliases a
      where a.id <> new.id
        and a.active
        and a.source_system_normalized = v_source
        and a.alias_type_normalized = v_type
        and a.normalized_alias_value = v_value
    ) then
      raise exception 'duplicate source-scoped vehicle alias'
        using errcode = '23505',
              detail = public.vehicle_master_response(false, 'duplicate_candidate', jsonb_build_object('field', v_type, 'source_system', v_source))::text;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists vehicles_enforce_master_identity_uniqueness on public.vehicles;
create trigger vehicles_enforce_master_identity_uniqueness
before insert or update of stock_number, vin, source_system, source_record_id on public.vehicles
for each row execute function public.enforce_vehicle_master_identity_uniqueness();

drop trigger if exists vehicle_aliases_enforce_master_identity_uniqueness on public.vehicle_aliases;
create trigger vehicle_aliases_enforce_master_identity_uniqueness
before insert or update of alias_type, alias_value, active, source_system on public.vehicle_aliases
for each row execute function public.enforce_vehicle_alias_identity_uniqueness();

-- Only core vehicle changes advance the destination race token. Existing
-- movement/workshop/lifecycle RPCs can continue changing operational columns
-- without manufacturing a vehicle-master race.
create or replace function public.bump_vehicle_master_revision()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_master_change boolean := true;
begin
  if tg_table_name = 'vehicles' and tg_op = 'UPDATE' then
    v_is_master_change :=
      old.permanent_vehicle_id is distinct from new.permanent_vehicle_id
      or old.stock_number is distinct from new.stock_number
      or old.vin is distinct from new.vin
      or old.toyota_order_number is distinct from new.toyota_order_number
      or old.job_card_number is distinct from new.job_card_number
      or old.key_number is distinct from new.key_number
      or old.customer_name is distinct from new.customer_name
      or old.vehicle_description is distinct from new.vehicle_description
      or old.salesperson_id is distinct from new.salesperson_id
      or old.salesperson_reference is distinct from new.salesperson_reference
      or old.make is distinct from new.make
      or old.model is distinct from new.model
      or old.registration is distinct from new.registration
      or old.eta_to_kewdale is distinct from new.eta_to_kewdale
      or old.arrival_reference_date is distinct from new.arrival_reference_date
      or old.source_system is distinct from new.source_system
      or old.source_batch_id is distinct from new.source_batch_id
      or old.source_record_id is distinct from new.source_record_id;
  end if;

  if v_is_master_change then
    update public.vehicle_master_revision
    set revision = revision + 1,
        updated_at = now()
    where singleton;
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

drop trigger if exists vehicles_bump_master_revision on public.vehicles;
create trigger vehicles_bump_master_revision
after insert or update or delete on public.vehicles
for each row execute function public.bump_vehicle_master_revision();

drop trigger if exists vehicle_aliases_bump_master_revision on public.vehicle_aliases;
create trigger vehicle_aliases_bump_master_revision
after insert or update or delete on public.vehicle_aliases
for each row execute function public.bump_vehicle_master_revision();

create or replace function public.vehicle_master_core_audit_json(p_vehicle public.vehicles)
returns jsonb
language sql
stable
as $$
  select case when p_vehicle is null then null else jsonb_build_object(
    'id', p_vehicle.id,
    'permanent_vehicle_id', p_vehicle.permanent_vehicle_id,
    'stock_number', p_vehicle.stock_number,
    'vin', p_vehicle.vin,
    'toyota_order_number', p_vehicle.toyota_order_number,
    'job_card_number', p_vehicle.job_card_number,
    'key_number', p_vehicle.key_number,
    'customer_name', p_vehicle.customer_name,
    'vehicle_description', p_vehicle.vehicle_description,
    'salesperson_id', p_vehicle.salesperson_id,
    'salesperson_reference', p_vehicle.salesperson_reference,
    'make', p_vehicle.make,
    'model', p_vehicle.model,
    'registration', p_vehicle.registration,
    'eta_to_kewdale', p_vehicle.eta_to_kewdale,
    'arrival_reference_date', p_vehicle.arrival_reference_date,
    'source_system', p_vehicle.source_system,
    'source_batch_id', p_vehicle.source_batch_id,
    'source_record_id', p_vehicle.source_record_id,
    'version', p_vehicle.version,
    'is_archived', (p_vehicle.deleted_at is not null)
  ) end;
$$;

create or replace function public.vehicle_alias_audit_json(p_alias public.vehicle_aliases)
returns jsonb
language sql
stable
as $$
  select case when p_alias is null then null else jsonb_build_object(
    'id', p_alias.id,
    'vehicle_id', p_alias.vehicle_id,
    'alias_type', p_alias.alias_type,
    'alias_value', p_alias.alias_value,
    'active', p_alias.active,
    'source_system', p_alias.source_system,
    'source_batch_id', p_alias.source_batch_id,
    'version', p_alias.version
  ) end;
$$;

create or replace function public.record_vehicle_master_history()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_before jsonb;
  v_after jsonb;
  v_vehicle_id uuid;
  v_entity_id uuid;
  v_entity_type text;
  v_expected_version integer;
  v_resulting_version integer;
  v_master_revision bigint;
begin
  if tg_table_name = 'vehicles' then
    v_entity_type := 'vehicle';
    if tg_op <> 'INSERT' then
      v_before := public.vehicle_master_core_audit_json(old);
      v_entity_id := old.id;
      v_expected_version := old.version;
    end if;
    if tg_op <> 'DELETE' then
      v_after := public.vehicle_master_core_audit_json(new);
      v_entity_id := new.id;
      v_vehicle_id := new.id;
      v_resulting_version := new.version;
    end if;
  else
    v_entity_type := 'alias';
    if tg_op <> 'INSERT' then
      v_before := public.vehicle_alias_audit_json(old);
      v_entity_id := old.id;
      v_expected_version := old.version;
      v_vehicle_id := old.vehicle_id;
    end if;
    if tg_op <> 'DELETE' then
      v_after := public.vehicle_alias_audit_json(new);
      v_entity_id := new.id;
      v_vehicle_id := new.vehicle_id;
      v_resulting_version := new.version;
    elsif not exists (select 1 from public.vehicles where id = v_vehicle_id) then
      v_vehicle_id := null;
    end if;
  end if;

  if tg_op = 'UPDATE' and v_before is not distinct from v_after then
    return new;
  end if;

  select revision into v_master_revision
  from public.vehicle_master_revision
  where singleton;

  insert into public.vehicle_master_history (
    vehicle_id, entity_type, entity_id, action,
    expected_version, resulting_version, master_revision,
    before_data, after_data, actor_id, actor_email, metadata
  ) values (
    v_vehicle_id, v_entity_type, v_entity_id, lower(tg_op),
    v_expected_version, v_resulting_version, v_master_revision,
    v_before, v_after, auth.uid(), public.current_actor_email(),
    jsonb_build_object('source', 'vehicle_master_trigger')
  );

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

-- PostgreSQL fires same-kind triggers alphabetically, so the existing
-- *_bump_master_revision trigger advances the token before these history
-- triggers capture it.
drop trigger if exists vehicles_record_master_history on public.vehicles;
create trigger vehicles_record_master_history
after insert or update or delete on public.vehicles
for each row execute function public.record_vehicle_master_history();

drop trigger if exists vehicle_aliases_record_master_history on public.vehicle_aliases;
create trigger vehicle_aliases_record_master_history
after insert or update or delete on public.vehicle_aliases
for each row execute function public.record_vehicle_master_history();

drop trigger if exists vehicle_aliases_set_updated_at on public.vehicle_aliases;
create trigger vehicle_aliases_set_updated_at
before update on public.vehicle_aliases
for each row execute function public.set_updated_at();

drop trigger if exists vehicle_master_source_records_set_updated_at on public.vehicle_master_source_records;
create trigger vehicle_master_source_records_set_updated_at
before update on public.vehicle_master_source_records
for each row execute function public.set_updated_at();

-- Safe read contract for the vehicle-master cutover. This is an explicit
-- allowlist; raw source evidence and every workflow/operational field remain
-- outside the payload. Archived rows stay addressable by stable UUID and are
-- identified only by a derived flag, without exposing deletion metadata.
create or replace function public.get_vehicle_core_snapshot()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_role public.pdc_role;
  v_revision bigint;
  v_vehicles jsonb;
begin
  v_role := public.current_pdc_user_role();
  if v_role is null or not public.is_pdc_role('viewer') then
    return public.vehicle_master_response(false, 'permission_denied', '{}'::jsonb);
  end if;

  select revision into v_revision
  from public.vehicle_master_revision
  where singleton;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', v.id,
      'permanent_vehicle_id', v.permanent_vehicle_id,
      'stock_number', v.stock_number,
      'vin', v.vin,
      'toyota_order_number', v.toyota_order_number,
      'job_card_number', v.job_card_number,
      'key_number', v.key_number,
      'customer_name', v.customer_name,
      'vehicle_description', v.vehicle_description,
      'salesperson_id', v.salesperson_id,
      'salesperson_reference', v.salesperson_reference,
      'make', v.make,
      'model', v.model,
      'registration', v.registration,
      'eta_to_kewdale', v.eta_to_kewdale,
      'arrival_reference_date', v.arrival_reference_date,
      'source_system', v.source_system,
      'source_batch_id', v.source_batch_id,
      'source_record_id', v.source_record_id,
      'version', v.version,
      'created_at', v.created_at,
      'updated_at', v.updated_at,
      'is_archived', (v.deleted_at is not null)
    ) order by coalesce(v.stock_number, v.permanent_vehicle_id), v.id
  ), '[]'::jsonb)
  into v_vehicles
  from public.vehicles v;

  return public.vehicle_master_response(true, 'ok', jsonb_build_object(
    'revision', coalesce(v_revision, 1),
    'caller_role', v_role,
    'capabilities', jsonb_build_object(
      'can_edit', public.is_pdc_role('operator'),
      'can_import', public.is_pdc_role('importer'),
      'can_administer', public.is_pdc_role('administrator')
    ),
    'vehicles', v_vehicles
  ));
end;
$$;

-- Viewer+ reads, protected writes only. No INSERT/UPDATE/DELETE browser policy
-- is created for any vehicle-master table.
alter table public.vehicles enable row level security;
alter table public.vehicle_aliases enable row level security;
alter table public.vehicle_master_revision enable row level security;
alter table public.vehicle_master_history enable row level security;
alter table public.vehicle_master_identity_conflicts enable row level security;
alter table public.vehicle_master_source_records enable row level security;

drop policy if exists vehicles_select_approved on public.vehicles;
create policy vehicles_select_approved on public.vehicles
  for select to authenticated
  using (public.is_pdc_role('viewer'));

drop policy if exists vehicle_aliases_select_approved on public.vehicle_aliases;
create policy vehicle_aliases_select_approved on public.vehicle_aliases
  for select to authenticated
  using (public.is_pdc_role('viewer'));

drop policy if exists vehicle_master_revision_select_approved on public.vehicle_master_revision;
create policy vehicle_master_revision_select_approved on public.vehicle_master_revision
  for select to authenticated
  using (public.is_pdc_role('viewer'));

revoke all on table
  public.vehicles,
  public.vehicle_aliases,
  public.vehicle_master_revision,
  public.vehicle_master_history,
  public.vehicle_master_identity_conflicts,
  public.vehicle_master_source_records
from public, anon, authenticated;

revoke insert, update, delete, truncate on table
  public.vehicles,
  public.vehicle_aliases,
  public.vehicle_master_revision,
  public.vehicle_master_history,
  public.vehicle_master_identity_conflicts,
  public.vehicle_master_source_records
from public, anon, authenticated;

-- Preserve the pre-cutover direct read surface for current consumers, but do
-- not broaden it to history/conflict/raw-evidence tables. The revision token
-- is non-sensitive and needs viewer SELECT for RLS-authorized Realtime.
grant select on table public.vehicles, public.vehicle_aliases to authenticated;
grant select on table public.vehicle_master_revision to authenticated;

revoke all on function public.normalize_vehicle_stock_number(text) from public, anon, authenticated;
revoke all on function public.is_real_vehicle_stock_number(text) from public, anon, authenticated;
revoke all on function public.normalize_vehicle_vin(text) from public, anon, authenticated;
revoke all on function public.is_valid_vehicle_vin(text) from public, anon, authenticated;
revoke all on function public.normalize_vehicle_source_identifier(text) from public, anon, authenticated;
revoke all on function public.normalize_vehicle_source_system(text) from public, anon, authenticated;
revoke all on function public.normalize_vehicle_alias_value(text, text) from public, anon, authenticated;
revoke all on function public.vehicle_master_response(boolean, text, jsonb) from public, anon, authenticated;
revoke all on function public.enforce_vehicle_master_identity_uniqueness() from public, anon, authenticated;
revoke all on function public.enforce_vehicle_alias_identity_uniqueness() from public, anon, authenticated;
revoke all on function public.bump_vehicle_master_revision() from public, anon, authenticated;
revoke all on function public.vehicle_master_core_audit_json(public.vehicles) from public, anon, authenticated;
revoke all on function public.vehicle_alias_audit_json(public.vehicle_aliases) from public, anon, authenticated;
revoke all on function public.record_vehicle_master_history() from public, anon, authenticated;
revoke all on function public.get_vehicle_core_snapshot() from public, anon, authenticated;
grant execute on function public.get_vehicle_core_snapshot() to authenticated;

-- Complete old-row data for Realtime consumers and idempotent publication of
-- every table needed to refresh the sanitized snapshot.
alter table public.vehicles replica identity full;
alter table public.vehicle_aliases replica identity full;
alter table public.vehicle_master_revision replica identity full;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'vehicles'
  ) then
    alter publication supabase_realtime add table public.vehicles;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'vehicle_aliases'
  ) then
    alter publication supabase_realtime add table public.vehicle_aliases;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'vehicle_master_revision'
  ) then
    alter publication supabase_realtime add table public.vehicle_master_revision;
  end if;
end;
$$;

commit;
