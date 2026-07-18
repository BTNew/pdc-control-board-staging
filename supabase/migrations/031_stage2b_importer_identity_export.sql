-- Migration 031: Stage 2B C2a importer/admin vehicle identity export.
--
-- This additive migration replaces the workshop legacy importer's broad
-- identity read with a narrow, revision-pinned export. It does not change
-- browser or main-board authority and intentionally leaves transitional
-- authenticated vehicle SELECT access in place.

begin;

create or replace function public.export_workshop_legacy_vehicle_identities(
  p_after_vehicle_id text default null,
  p_page_size integer default 200,
  p_expected_revision bigint default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $export$
declare
  v_role public.pdc_role;
  v_after_vehicle_id uuid;
  v_page_size integer;
  v_export_revision bigint;
  v_result jsonb;
begin
  v_role := public.current_pdc_user_role();
  if v_role is null or v_role not in ('importer', 'administrator') then
    return jsonb_build_object('outcome', 'unauthorized');
  end if;

  if p_after_vehicle_id is not null and btrim(p_after_vehicle_id) <> '' then
    if btrim(p_after_vehicle_id) !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      return jsonb_build_object('outcome', 'invalid_input', 'field', 'after_vehicle_id');
    end if;
    v_after_vehicle_id := btrim(p_after_vehicle_id)::uuid;
  end if;

  if p_page_size is null or p_page_size < 1 then
    return jsonb_build_object('outcome', 'invalid_input', 'field', 'page_size');
  end if;
  v_page_size := greatest(1, least(p_page_size, 500));

  select revision into v_export_revision
  from public.vehicle_lifecycle_resolver_revision
  where singleton;

  if v_export_revision is null then
    return jsonb_build_object('outcome', 'service_unavailable');
  end if;
  if p_expected_revision is not null and p_expected_revision <> v_export_revision then
    return jsonb_build_object(
      'outcome', 'stale_export',
      'expected_revision', p_expected_revision,
      'export_revision', v_export_revision
    );
  end if;

  with all_claims as materialized (
    select
      v.id as vehicle_id,
      'stock_number'::text as identifier_type,
      v.stock_number as value,
      public.normalize_vehicle_stock_number(v.stock_number) as normalized_value,
      null::text as source_system,
      'canonical'::text as origin
    from public.vehicles v
    where public.is_real_vehicle_stock_number(v.stock_number)

    union all
    select v.id, 'vin', v.vin, public.normalize_vehicle_vin(v.vin), null::text, 'canonical'
    from public.vehicles v
    where public.is_valid_vehicle_vin(v.vin)

    union all
    select
      v.id, 'job_card_number', v.job_card_number,
      public.normalize_vehicle_source_identifier(v.job_card_number),
      public.normalize_vehicle_source_system(v.source_system), 'canonical'
    from public.vehicles v
    where public.normalize_vehicle_source_identifier(v.job_card_number) is not null
      and public.normalize_vehicle_source_system(v.source_system) is not null

    union all
    select
      v.id, 'permanent_vehicle_id', v.permanent_vehicle_id,
      public.normalize_vehicle_source_identifier(v.permanent_vehicle_id),
      null::text, 'canonical'
    from public.vehicles v
    where public.normalize_vehicle_source_identifier(v.permanent_vehicle_id) is not null

    union all
    select
      v.id, 'toyota_order_number', v.toyota_order_number,
      public.normalize_vehicle_source_identifier(v.toyota_order_number),
      public.normalize_vehicle_source_system(v.source_system), 'canonical'
    from public.vehicles v
    where public.normalize_vehicle_source_identifier(v.toyota_order_number) is not null
      and public.normalize_vehicle_source_system(v.source_system) is not null

    union all
    select
      v.id, 'source_record_id', v.source_record_id,
      public.normalize_vehicle_source_identifier(v.source_record_id),
      public.normalize_vehicle_source_system(v.source_system), 'canonical'
    from public.vehicles v
    where public.normalize_vehicle_source_identifier(v.source_record_id) is not null
      and public.normalize_vehicle_source_system(v.source_system) is not null

    union all
    select
      sr.vehicle_id, 'source_record_id', sr.source_record_id,
      public.normalize_vehicle_source_identifier(sr.source_record_id),
      public.normalize_vehicle_source_system(sr.source_system), 'source_evidence'
    from public.vehicle_master_source_records sr
    where sr.vehicle_id is not null
      and public.normalize_vehicle_source_identifier(sr.source_record_id) is not null
      and public.normalize_vehicle_source_system(sr.source_system) is not null

    union all
    select
      a.vehicle_id,
      a.alias_type_normalized,
      a.alias_value,
      public.normalize_vehicle_alias_value(a.alias_type, a.alias_value),
      case
        when a.alias_type_normalized in ('job_card_number', 'toyota_order_number', 'source_record_id')
          then a.source_system_normalized
        else null::text
      end,
      'alias'::text
    from public.vehicle_aliases a
    where a.active
      and a.alias_type_normalized in (
        'stock_number', 'vin', 'job_card_number',
        'toyota_order_number', 'source_record_id'
      )
      and a.normalized_alias_value is not null
      and (
        (a.alias_type_normalized = 'stock_number' and public.is_real_vehicle_stock_number(a.alias_value))
        or (a.alias_type_normalized = 'vin' and public.is_valid_vehicle_vin(a.alias_value))
        or (
          a.alias_type_normalized in ('job_card_number', 'toyota_order_number', 'source_record_id')
          and a.source_system_normalized is not null
        )
      )
  ),
  conflict_groups as materialized (
    select
      identifier_type,
      source_system,
      normalized_value,
      array_agg(distinct vehicle_id order by vehicle_id) as vehicle_ids,
      case
        when bool_or(origin = 'canonical') and bool_or(origin = 'alias')
          then 'canonical_alias_conflict'
        when bool_or(origin = 'canonical') and bool_or(origin = 'source_evidence')
          then 'canonical_source_evidence_conflict'
        else 'ambiguous_normalized_identity'
      end as classification
    from all_claims
    group by identifier_type, source_system, normalized_value
    having count(distinct vehicle_id) > 1
  ),
  candidate_page as materialized (
    select v.id, v.version, (v.deleted_at is not null) as is_archived
    from public.vehicles v
    where v_after_vehicle_id is null or v.id > v_after_vehicle_id
    order by v.id
    limit (v_page_size + 1)
  ),
  page_vehicles as materialized (
    select id, version, is_archived
    from candidate_page
    order by id
    limit v_page_size
  ),
  page_items as (
    select
      p.id,
      jsonb_build_object(
        'vehicle_id', p.id,
        'version', p.version,
        'is_archived', p.is_archived,
        'identifiers', coalesce(
          jsonb_agg(
            jsonb_build_object(
              'identifier_type', c.identifier_type,
              'value', c.value,
              'normalized_value', c.normalized_value,
              'source_system', c.source_system,
              'origin', c.origin
            ) order by c.identifier_type, c.source_system nulls first,
                       c.normalized_value, c.origin, c.value
          ) filter (where c.vehicle_id is not null),
          '[]'::jsonb
        )
      ) as item
    from page_vehicles p
    left join all_claims c on c.vehicle_id = p.id
    group by p.id, p.version, p.is_archived
  )
  select jsonb_build_object(
    'outcome', 'exported',
    'export_revision', v_export_revision,
    'page_size', v_page_size,
    'items', coalesce(
      (select jsonb_agg(item order by id) from page_items),
      '[]'::jsonb
    ),
    'conflicts', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'classification', g.classification,
            'identifier_type', g.identifier_type,
            'normalized_value', g.normalized_value,
            'source_system', g.source_system,
            'vehicle_ids', to_jsonb(g.vehicle_ids),
            'candidates', (
              select jsonb_agg(
                jsonb_build_object(
                  'vehicle_id', c.vehicle_id,
                  'origin', c.origin,
                  'value', c.value
                ) order by c.vehicle_id, c.origin, c.value
              )
              from all_claims c
              where c.identifier_type = g.identifier_type
                and c.normalized_value = g.normalized_value
                and c.source_system is not distinct from g.source_system
            )
          ) order by g.identifier_type, g.source_system nulls first, g.normalized_value
        )
        from conflict_groups g
        where exists (
          select 1
          from page_vehicles p
          where p.id = any(g.vehicle_ids)
        )
      ),
      '[]'::jsonb
    ),
    'has_more', (select count(*) > v_page_size from candidate_page),
    'next_cursor', case
      when (select count(*) > v_page_size from candidate_page)
        then (select max(id::text) from page_vehicles)
      else null
    end
  ) into v_result;

  return v_result;
end;
$export$;

revoke all on function public.export_workshop_legacy_vehicle_identities(text, integer, bigint)
  from public, anon, authenticated;
grant execute on function public.export_workshop_legacy_vehicle_identities(text, integer, bigint)
  to authenticated;

commit;
