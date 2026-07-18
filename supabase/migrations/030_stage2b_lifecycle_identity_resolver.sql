-- Migration 030: Stage 2B C1 narrow lifecycle identity resolver.
--
-- Additive staging-first contract. This migration does not retire the
-- transitional authenticated SELECT on public.vehicles, does not change any
-- browser/localStorage authority, and does not mutate vehicle data.

begin;

create table if not exists public.vehicle_lifecycle_resolver_revision (
  singleton boolean primary key default true check (singleton),
  revision bigint not null default 1 check (revision > 0),
  updated_at timestamptz not null default now()
);

insert into public.vehicle_lifecycle_resolver_revision (singleton, revision)
values (true, 1)
on conflict (singleton) do nothing;

create or replace function public.bump_vehicle_lifecycle_resolver_revision()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_changed boolean := true;
begin
  if tg_table_name = 'vehicles' and tg_op = 'UPDATE' then
    v_changed :=
      old.id is distinct from new.id
      or old.permanent_vehicle_id is distinct from new.permanent_vehicle_id
      or old.stock_number is distinct from new.stock_number
      or old.vin is distinct from new.vin
      or old.toyota_order_number is distinct from new.toyota_order_number
      or old.job_card_number is distinct from new.job_card_number
      or old.source_system is distinct from new.source_system
      or old.source_record_id is distinct from new.source_record_id
      or old.version is distinct from new.version
      or old.qc_completed_at is distinct from new.qc_completed_at
      or old.lifecycle_state is distinct from new.lifecycle_state
      or old.deleted_at is distinct from new.deleted_at;
  end if;

  if v_changed then
    update public.vehicle_lifecycle_resolver_revision
    set revision = revision + 1,
        updated_at = now()
    where singleton;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

-- Trigger entrypoints are internal even though PostgreSQL does not normally
-- permit direct invocation of a trigger-returning function.
revoke all on function public.bump_vehicle_lifecycle_resolver_revision()
from public, anon, authenticated;

drop trigger if exists vehicles_bump_lifecycle_resolver_revision on public.vehicles;
create trigger vehicles_bump_lifecycle_resolver_revision
after insert or update or delete on public.vehicles
for each row execute function public.bump_vehicle_lifecycle_resolver_revision();

drop trigger if exists vehicle_aliases_bump_lifecycle_resolver_revision on public.vehicle_aliases;
create trigger vehicle_aliases_bump_lifecycle_resolver_revision
after insert or update or delete on public.vehicle_aliases
for each row execute function public.bump_vehicle_lifecycle_resolver_revision();

drop trigger if exists vehicle_source_records_bump_lifecycle_resolver_revision on public.vehicle_master_source_records;
create trigger vehicle_source_records_bump_lifecycle_resolver_revision
after insert or update or delete on public.vehicle_master_source_records
for each row execute function public.bump_vehicle_lifecycle_resolver_revision();

create or replace function public.resolve_vehicle_lifecycle_identity(
  p_vehicle_id text default null,
  p_stock_number text default null,
  p_vin text default null,
  p_job_card_number text default null,
  p_permanent_vehicle_id text default null,
  p_toyota_order_number text default null,
  p_source_system text default null,
  p_source_record_id text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_role public.pdc_role;
  v_uuid uuid;
  v_stock text;
  v_vin text;
  v_job text;
  v_permanent text;
  v_order text;
  v_source text;
  v_source_record text;
  v_has_input boolean := false;
  v_uuid_candidates uuid[] := '{}'::uuid[];
  v_stock_canonical uuid[] := '{}'::uuid[];
  v_stock_alias uuid[] := '{}'::uuid[];
  v_stock_candidates uuid[] := '{}'::uuid[];
  v_vin_canonical uuid[] := '{}'::uuid[];
  v_vin_alias uuid[] := '{}'::uuid[];
  v_vin_candidates uuid[] := '{}'::uuid[];
  v_job_canonical uuid[] := '{}'::uuid[];
  v_job_alias uuid[] := '{}'::uuid[];
  v_job_candidates uuid[] := '{}'::uuid[];
  v_permanent_candidates uuid[] := '{}'::uuid[];
  v_order_canonical uuid[] := '{}'::uuid[];
  v_order_alias uuid[] := '{}'::uuid[];
  v_order_candidates uuid[] := '{}'::uuid[];
  v_source_canonical uuid[] := '{}'::uuid[];
  v_source_alias uuid[] := '{}'::uuid[];
  v_source_evidence uuid[] := '{}'::uuid[];
  v_source_candidates uuid[] := '{}'::uuid[];
  v_all_candidates uuid[] := '{}'::uuid[];
  v_matched_by text[] := '{}'::text[];
  v_resolved_id uuid;
  v_revision bigint;
  v_vehicle record;
  v_candidate_count integer;
begin
  v_role := public.current_pdc_user_role();
  if v_role is null or not public.is_pdc_role('viewer') then
    return jsonb_build_object('outcome', 'unauthorized');
  end if;

  if nullif(btrim(p_vehicle_id), '') is not null then
    v_has_input := true;
    if btrim(p_vehicle_id) !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      return jsonb_build_object('outcome', 'invalid_input', 'field', 'vehicle_id');
    end if;
    begin
      v_uuid := btrim(p_vehicle_id)::uuid;
    exception when invalid_text_representation then
      return jsonb_build_object('outcome', 'invalid_input', 'field', 'vehicle_id');
    end;
    select coalesce(array_agg(v.id order by v.id), '{}'::uuid[])
    into v_uuid_candidates
    from public.vehicles v where v.id = v_uuid;
  end if;

  if nullif(btrim(p_stock_number), '') is not null then
    v_has_input := true;
    if not public.is_real_vehicle_stock_number(p_stock_number) then
      return jsonb_build_object('outcome', 'invalid_input', 'field', 'stock_number');
    end if;
    v_stock := public.normalize_vehicle_stock_number(p_stock_number);
    select coalesce(array_agg(v.id order by v.id), '{}'::uuid[])
    into v_stock_canonical
    from public.vehicles v
    where public.is_real_vehicle_stock_number(v.stock_number)
      and v.stock_number_normalized = v_stock;
    select coalesce(array_agg(distinct a.vehicle_id order by a.vehicle_id), '{}'::uuid[])
    into v_stock_alias
    from public.vehicle_aliases a
    where a.active and a.alias_type_normalized = 'stock_number'
      and public.is_real_vehicle_stock_number(a.alias_value)
      and a.normalized_alias_value = v_stock;
    select coalesce(array_agg(distinct x order by x), '{}'::uuid[])
    into v_stock_candidates from unnest(v_stock_canonical || v_stock_alias) x;
  end if;

  if nullif(btrim(p_vin), '') is not null then
    v_has_input := true;
    if not public.is_valid_vehicle_vin(p_vin) then
      return jsonb_build_object('outcome', 'invalid_input', 'field', 'vin');
    end if;
    v_vin := public.normalize_vehicle_vin(p_vin);
    select coalesce(array_agg(v.id order by v.id), '{}'::uuid[])
    into v_vin_canonical
    from public.vehicles v
    where public.is_valid_vehicle_vin(v.vin) and v.vin_normalized = v_vin;
    select coalesce(array_agg(distinct a.vehicle_id order by a.vehicle_id), '{}'::uuid[])
    into v_vin_alias
    from public.vehicle_aliases a
    where a.active and a.alias_type_normalized = 'vin'
      and a.normalized_alias_value = v_vin;
    select coalesce(array_agg(distinct x order by x), '{}'::uuid[])
    into v_vin_candidates from unnest(v_vin_canonical || v_vin_alias) x;
  end if;

  v_source := public.normalize_vehicle_source_system(p_source_system);
  v_source_record := public.normalize_vehicle_source_identifier(p_source_record_id);
  if v_source_record is not null and v_source is null then
    return jsonb_build_object('outcome', 'invalid_input', 'field', 'source_identity');
  end if;
  if v_source_record is not null then
    v_has_input := true;
    select coalesce(array_agg(v.id order by v.id), '{}'::uuid[])
    into v_source_canonical
    from public.vehicles v
    where v.source_system_normalized = v_source
      and v.source_record_id_normalized = v_source_record;
    select coalesce(array_agg(distinct a.vehicle_id order by a.vehicle_id), '{}'::uuid[])
    into v_source_alias
    from public.vehicle_aliases a
    where a.active and a.source_system_normalized = v_source
      and a.alias_type_normalized = 'source_record_id'
      and a.normalized_alias_value = v_source_record;
    select coalesce(array_agg(distinct sr.vehicle_id order by sr.vehicle_id), '{}'::uuid[])
    into v_source_evidence
    from public.vehicle_master_source_records sr
    where sr.vehicle_id is not null
      and public.normalize_vehicle_source_system(sr.source_system) = v_source
      and public.normalize_vehicle_source_identifier(sr.source_record_id) = v_source_record;
    select coalesce(array_agg(distinct x order by x), '{}'::uuid[])
    into v_source_candidates
    from unnest(v_source_canonical || v_source_alias || v_source_evidence) x;
  end if;

  if nullif(btrim(p_job_card_number), '') is not null then
    v_has_input := true;
    if v_source is null then
      return jsonb_build_object('outcome', 'invalid_input', 'field', 'job_card_source_system');
    end if;
    v_job := public.normalize_vehicle_source_identifier(p_job_card_number);
    select coalesce(array_agg(v.id order by v.id), '{}'::uuid[])
    into v_job_canonical
    from public.vehicles v
    where v.source_system_normalized = v_source
      and public.normalize_vehicle_source_identifier(v.job_card_number) = v_job;
    select coalesce(array_agg(distinct a.vehicle_id order by a.vehicle_id), '{}'::uuid[])
    into v_job_alias
    from public.vehicle_aliases a
    where a.active and a.source_system_normalized = v_source
      and a.alias_type_normalized = 'job_card_number'
      and a.normalized_alias_value = v_job;
    select coalesce(array_agg(distinct x order by x), '{}'::uuid[])
    into v_job_candidates from unnest(v_job_canonical || v_job_alias) x;
  end if;

  if nullif(btrim(p_toyota_order_number), '') is not null then
    v_has_input := true;
    if v_source is null then
      return jsonb_build_object('outcome', 'invalid_input', 'field', 'toyota_order_source_system');
    end if;
    v_order := public.normalize_vehicle_source_identifier(p_toyota_order_number);
    select coalesce(array_agg(v.id order by v.id), '{}'::uuid[])
    into v_order_canonical
    from public.vehicles v
    where v.source_system_normalized = v_source
      and public.normalize_vehicle_source_identifier(v.toyota_order_number) = v_order;
    select coalesce(array_agg(distinct a.vehicle_id order by a.vehicle_id), '{}'::uuid[])
    into v_order_alias
    from public.vehicle_aliases a
    where a.active and a.source_system_normalized = v_source
      and a.alias_type_normalized = 'toyota_order_number'
      and a.normalized_alias_value = v_order;
    select coalesce(array_agg(distinct x order by x), '{}'::uuid[])
    into v_order_candidates from unnest(v_order_canonical || v_order_alias) x;
  end if;

  if nullif(btrim(p_permanent_vehicle_id), '') is not null then
    v_has_input := true;
    v_permanent := public.normalize_vehicle_source_identifier(p_permanent_vehicle_id);
    select coalesce(array_agg(v.id order by v.id), '{}'::uuid[])
    into v_permanent_candidates
    from public.vehicles v
    where public.normalize_vehicle_source_identifier(v.permanent_vehicle_id) = v_permanent;
  end if;

  if not v_has_input then
    return jsonb_build_object('outcome', 'invalid_input', 'field', 'identity');
  end if;

  -- An explicit UUID is the highest-precedence identity. If it does not exist,
  -- another identifier is not allowed to silently replace it.
  if v_uuid is not null and cardinality(v_uuid_candidates) = 0 then
    select coalesce(array_agg(distinct x order by x), '{}'::uuid[])
    into v_all_candidates
    from unnest(v_stock_candidates || v_vin_candidates || v_job_candidates ||
      v_permanent_candidates || v_order_candidates || v_source_candidates) x;
    if cardinality(v_all_candidates) > 0 then
      return jsonb_build_object('outcome', 'conflict', 'reason', 'conflicting_identifiers',
        'candidate_count', cardinality(v_all_candidates));
    end if;
    return jsonb_build_object('outcome', 'not_found');
  end if;

  -- A canonical row and an alias/source-evidence row for the same typed input
  -- must never disagree. This is a conflict, not a precedence choice.
  if cardinality(v_stock_candidates) > 1
     and cardinality(v_stock_canonical) > 0 and cardinality(v_stock_alias) > 0
     and not (v_stock_canonical <@ v_stock_alias and v_stock_alias <@ v_stock_canonical) then
    return jsonb_build_object('outcome', 'conflict', 'reason', 'canonical_alias_conflict',
      'identifier', 'stock_number', 'candidate_count', cardinality(v_stock_candidates));
  end if;
  if cardinality(v_vin_candidates) > 1
     and cardinality(v_vin_canonical) > 0 and cardinality(v_vin_alias) > 0
     and not (v_vin_canonical <@ v_vin_alias and v_vin_alias <@ v_vin_canonical) then
    return jsonb_build_object('outcome', 'conflict', 'reason', 'canonical_alias_conflict',
      'identifier', 'vin', 'candidate_count', cardinality(v_vin_candidates));
  end if;
  if cardinality(v_job_candidates) > 1
     and cardinality(v_job_canonical) > 0 and cardinality(v_job_alias) > 0
     and not (v_job_canonical <@ v_job_alias and v_job_alias <@ v_job_canonical) then
    return jsonb_build_object('outcome', 'conflict', 'reason', 'canonical_alias_conflict',
      'identifier', 'job_card_number', 'candidate_count', cardinality(v_job_candidates));
  end if;
  if cardinality(v_order_candidates) > 1
     and cardinality(v_order_canonical) > 0 and cardinality(v_order_alias) > 0
     and not (v_order_canonical <@ v_order_alias and v_order_alias <@ v_order_canonical) then
    return jsonb_build_object('outcome', 'conflict', 'reason', 'canonical_alias_conflict',
      'identifier', 'toyota_order_number', 'candidate_count', cardinality(v_order_candidates));
  end if;
  if cardinality(v_source_candidates) > 1
     and (
       (cardinality(v_source_canonical) > 0 and cardinality(v_source_alias) > 0
         and not (v_source_canonical <@ v_source_alias and v_source_alias <@ v_source_canonical))
       or (cardinality(v_source_canonical) > 0 and cardinality(v_source_evidence) > 0
         and not (v_source_canonical <@ v_source_evidence and v_source_evidence <@ v_source_canonical))
       or (cardinality(v_source_alias) > 0 and cardinality(v_source_evidence) > 0
         and not (v_source_alias <@ v_source_evidence and v_source_evidence <@ v_source_alias))
     ) then
    return jsonb_build_object('outcome', 'conflict', 'reason', 'canonical_alias_conflict',
      'identifier', 'source_record_id', 'candidate_count', cardinality(v_source_candidates));
  end if;

  foreach v_candidate_count in array array[
    cardinality(v_uuid_candidates), cardinality(v_stock_candidates),
    cardinality(v_vin_candidates), cardinality(v_job_candidates),
    cardinality(v_permanent_candidates), cardinality(v_order_candidates),
    cardinality(v_source_candidates)
  ] loop
    if v_candidate_count > 1 then
      return jsonb_build_object('outcome', 'ambiguous', 'reason', 'multiple_normalized_matches',
        'candidate_count', v_candidate_count);
    end if;
  end loop;

  select coalesce(array_agg(distinct x order by x), '{}'::uuid[])
  into v_all_candidates
  from unnest(
    v_uuid_candidates || v_stock_candidates || v_vin_candidates ||
    v_job_candidates || v_permanent_candidates || v_order_candidates ||
    v_source_candidates
  ) x;

  if cardinality(v_all_candidates) = 0 then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  if cardinality(v_all_candidates) > 1 then
    return jsonb_build_object('outcome', 'conflict', 'reason', 'conflicting_identifiers',
      'candidate_count', cardinality(v_all_candidates));
  end if;

  v_resolved_id := v_all_candidates[1];
  if cardinality(v_uuid_candidates) = 1 then v_matched_by := array_append(v_matched_by, 'vehicle_id'); end if;
  if cardinality(v_stock_candidates) = 1 then v_matched_by := array_append(v_matched_by, 'stock_number'); end if;
  if cardinality(v_vin_candidates) = 1 then v_matched_by := array_append(v_matched_by, 'vin'); end if;
  if cardinality(v_job_candidates) = 1 then v_matched_by := array_append(v_matched_by, 'job_card_number'); end if;
  if cardinality(v_permanent_candidates) = 1 then v_matched_by := array_append(v_matched_by, 'permanent_vehicle_id'); end if;
  if cardinality(v_order_candidates) = 1 then v_matched_by := array_append(v_matched_by, 'toyota_order_number'); end if;
  if cardinality(v_source_candidates) = 1 then v_matched_by := array_append(v_matched_by, 'source_record_id'); end if;

  select v.id, v.version, v.qc_completed_at, v.lifecycle_state, (v.deleted_at is not null) as is_archived
  into v_vehicle
  from public.vehicles v
  where v.id = v_resolved_id;

  if not found then
    return jsonb_build_object('outcome', 'not_found');
  end if;

  select revision into v_revision
  from public.vehicle_lifecycle_resolver_revision
  where singleton;

  return jsonb_build_object(
    'outcome', 'resolved',
    'vehicle_id', v_vehicle.id,
    'version', v_vehicle.version,
    'qc_completed_at', v_vehicle.qc_completed_at,
    'lifecycle_state', v_vehicle.lifecycle_state,
    'is_archived', v_vehicle.is_archived,
    'resolver_revision', coalesce(v_revision, 1),
    'matched_by', to_jsonb(v_matched_by)
  );
end;
$$;

alter table public.vehicle_lifecycle_resolver_revision enable row level security;

drop policy if exists vehicle_lifecycle_resolver_revision_select_approved
  on public.vehicle_lifecycle_resolver_revision;
create policy vehicle_lifecycle_resolver_revision_select_approved
  on public.vehicle_lifecycle_resolver_revision
  for select to authenticated
  using (public.is_pdc_role('viewer'));

revoke all on table public.vehicle_lifecycle_resolver_revision from public, anon, authenticated;
grant select on table public.vehicle_lifecycle_resolver_revision to authenticated;

revoke all on function public.bump_vehicle_lifecycle_resolver_revision() from public, anon, authenticated;
revoke all on function public.resolve_vehicle_lifecycle_identity(text, text, text, text, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.resolve_vehicle_lifecycle_identity(text, text, text, text, text, text, text, text)
  to authenticated;

alter table public.vehicle_lifecycle_resolver_revision replica identity full;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'vehicle_lifecycle_resolver_revision'
  ) then
    alter publication supabase_realtime add table public.vehicle_lifecycle_resolver_revision;
  end if;
end;
$$;

-- The broad authenticated vehicle SELECT and its RLS policy deliberately remain
-- transitional. C1 replaces only the lifecycle consumer's first-match query.

commit;
