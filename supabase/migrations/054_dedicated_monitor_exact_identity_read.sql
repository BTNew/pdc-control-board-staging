-- Dedicated PDC Monitor exact-identity reader.
-- Read-only, staging-first boundary: the monitor keeps its Viewer role and gains
-- only a hash/identity comparison result for one Stock+VIN pair. It receives no
-- operator, importer, table-write, activation, or service-role capability.

begin;

create table if not exists public.pdc_monitor_vehicle_identity_readers (
  user_id uuid primary key references auth.users(id) on delete cascade,
  active boolean not null default true,
  reason text not null,
  granted_by uuid references auth.users(id) on delete set null,
  granted_at timestamptz not null default now(),
  revoked_at timestamptz
);

alter table public.pdc_monitor_vehicle_identity_readers enable row level security;
revoke all on table public.pdc_monitor_vehicle_identity_readers from public, anon, authenticated;

create or replace function public.get_pdc_monitor_navision_identity_match(
  p_stock_number text,
  p_vin text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $match$
declare
  v_user_id uuid := auth.uid();
  v_stock text;
  v_vin text;
  v_stock_ids uuid[] := '{}'::uuid[];
  v_vin_ids uuid[] := '{}'::uuid[];
  v_operational_stock_ids uuid[] := '{}'::uuid[];
  v_operational_vin_ids uuid[] := '{}'::uuid[];
  v_record_id uuid;
  v_record public.navision_backend_records%rowtype;
  v_vehicle record;
  v_operational_identity jsonb;
  v_revision bigint;
  v_board_activated boolean := false;
begin
  -- A dedicated grant is necessary but deliberately not sufficient: the
  -- credential must remain an approved Viewer. Escalating it to any writable
  -- application role makes this function fail closed.
  if v_user_id is null
     or public.current_pdc_user_role() is distinct from 'viewer'::public.pdc_role
     or not exists (
       select 1
       from public.pdc_monitor_vehicle_identity_readers g
       where g.user_id = v_user_id
         and g.active
         and g.revoked_at is null
     ) then
    return jsonb_build_object('outcome', 'unauthorized');
  end if;

  if nullif(btrim(coalesce(p_stock_number, '')), '') is null
     or not public.is_real_vehicle_stock_number(p_stock_number) then
    return jsonb_build_object('outcome', 'invalid_input', 'field', 'stock_number');
  end if;
  if nullif(btrim(coalesce(p_vin, '')), '') is null
     or not public.is_valid_vehicle_vin(p_vin) then
    return jsonb_build_object('outcome', 'invalid_input', 'field', 'vin');
  end if;

  v_stock := public.normalize_vehicle_stock_number(p_stock_number);
  v_vin := public.normalize_vehicle_vin(p_vin);

  select coalesce(array_agg(r.id order by r.id), '{}'::uuid[])
  into v_stock_ids
  from public.navision_backend_records r
  where r.source_system = 'microsoft_navision'
    and r.dealer_code in ('14450', '37047')
    and r.is_current
    and r.record_status = 'current'
    and public.is_real_vehicle_stock_number(r.normalized_data ->> 'batch')
    and public.normalize_vehicle_stock_number(r.normalized_data ->> 'batch') = v_stock;

  select coalesce(array_agg(r.id order by r.id), '{}'::uuid[])
  into v_vin_ids
  from public.navision_backend_records r
  where r.source_system = 'microsoft_navision'
    and r.dealer_code in ('14450', '37047')
    and r.is_current
    and r.record_status = 'current'
    and public.is_valid_vehicle_vin(r.normalized_data ->> 'vin')
    and public.normalize_vehicle_vin(r.normalized_data ->> 'vin') = v_vin;

  select revision into v_revision
  from public.navision_backend_revision
  where singleton;

  -- Independently compare the exact pair with operational vehicles before any
  -- Navision outcome is returned. This makes a backend-absent intake option safe:
  -- an existing/conflicting operational identity still fails closed.
  select coalesce(array_agg(distinct candidate_id order by candidate_id), '{}'::uuid[])
  into v_operational_stock_ids
  from (
    select v.id as candidate_id
    from public.vehicles v
    where public.is_real_vehicle_stock_number(v.stock_number)
      and v.stock_number_normalized = v_stock
    union
    select a.vehicle_id
    from public.vehicle_aliases a
    where a.active
      and a.alias_type_normalized = 'stock_number'
      and public.is_real_vehicle_stock_number(a.alias_value)
      and a.normalized_alias_value = v_stock
  ) stock_candidates;

  select coalesce(array_agg(distinct candidate_id order by candidate_id), '{}'::uuid[])
  into v_operational_vin_ids
  from (
    select v.id as candidate_id
    from public.vehicles v
    where public.is_valid_vehicle_vin(v.vin)
      and v.vin_normalized = v_vin
    union
    select a.vehicle_id
    from public.vehicle_aliases a
    where a.active
      and a.alias_type_normalized = 'vin'
      and public.is_valid_vehicle_vin(a.alias_value)
      and a.normalized_alias_value = v_vin
  ) vin_candidates;

  if cardinality(v_operational_stock_ids) > 1
     or cardinality(v_operational_vin_ids) > 1 then
    v_operational_identity := jsonb_build_object(
      'outcome', 'ambiguous',
      'reason', 'multiple_operational_matches',
      'stock_match_count', cardinality(v_operational_stock_ids),
      'vin_match_count', cardinality(v_operational_vin_ids)
    );
  elsif cardinality(v_operational_stock_ids) = 0
        and cardinality(v_operational_vin_ids) = 0 then
    v_operational_identity := jsonb_build_object('outcome', 'not_found');
  elsif cardinality(v_operational_stock_ids) <> 1
        or cardinality(v_operational_vin_ids) <> 1
        or v_operational_stock_ids[1] <> v_operational_vin_ids[1] then
    v_operational_identity := jsonb_build_object(
      'outcome', 'conflict',
      'reason', 'operational_stock_vin_disagreement',
      'stock_match_count', cardinality(v_operational_stock_ids),
      'vin_match_count', cardinality(v_operational_vin_ids)
    );
  else
    select v.id, v.version, v.lifecycle_state, v.visible_on_board,
           (v.deleted_at is not null) as is_archived
    into v_vehicle
    from public.vehicles v
    where v.id = v_operational_stock_ids[1];
    if not found then
      v_operational_identity := jsonb_build_object('outcome', 'not_found');
    else
      v_operational_identity := jsonb_build_object(
        'outcome', 'resolved',
        'vehicle_id', v_vehicle.id,
        'version', v_vehicle.version,
        'lifecycle_state', v_vehicle.lifecycle_state,
        'visible_on_board', v_vehicle.visible_on_board,
        'is_archived', v_vehicle.is_archived,
        'matched_by', jsonb_build_array('stock_number', 'vin')
      );
    end if;
  end if;

  if cardinality(v_stock_ids) > 1 or cardinality(v_vin_ids) > 1 then
    return jsonb_build_object(
      'outcome', 'ambiguous',
      'reason', 'multiple_current_navision_matches',
      'stock_match_count', cardinality(v_stock_ids),
      'vin_match_count', cardinality(v_vin_ids),
      'navision_revision', v_revision,
      'operational_identity', v_operational_identity,
      'authority', 'dedicated_monitor_read_only_exact_identity'
    );
  end if;

  if cardinality(v_stock_ids) = 0 and cardinality(v_vin_ids) = 0 then
    return jsonb_build_object(
      'outcome', 'not_found',
      'stock_match_count', 0,
      'vin_match_count', 0,
      'navision_revision', v_revision,
      'operational_identity', v_operational_identity,
      'authority', 'dedicated_monitor_read_only_exact_identity'
    );
  end if;

  if cardinality(v_stock_ids) <> 1
     or cardinality(v_vin_ids) <> 1
     or v_stock_ids[1] <> v_vin_ids[1] then
    return jsonb_build_object(
      'outcome', 'conflict',
      'reason', 'stock_vin_disagreement',
      'stock_match_count', cardinality(v_stock_ids),
      'vin_match_count', cardinality(v_vin_ids),
      'navision_revision', v_revision,
      'operational_identity', v_operational_identity,
      'authority', 'dedicated_monitor_read_only_exact_identity'
    );
  end if;

  v_record_id := v_stock_ids[1];
  select * into v_record
  from public.navision_backend_records
  where id = v_record_id;

  select exists (
    select 1
    from public.navision_board_activations a
    where a.backend_record_id = v_record_id
      and a.activated_stock_number = nullif(btrim(v_record.normalized_data ->> 'batch'), '')
  ) into v_board_activated;

  return jsonb_build_object(
    'outcome', 'resolved',
    'backend_record_id', v_record_id,
    'dealer_code', v_record.dealer_code,
    'record_status', v_record.record_status,
    'is_current', v_record.is_current,
    'board_activated', v_board_activated,
    'navision_revision', v_revision,
    'operational_identity', v_operational_identity,
    'matched_by', jsonb_build_array('stock_number', 'vin'),
    'authority', 'dedicated_monitor_read_only_exact_identity'
  );
end;
$match$;

revoke all on function public.get_pdc_monitor_navision_identity_match(text, text)
from public, anon, authenticated;
grant execute on function public.get_pdc_monitor_navision_identity_match(text, text)
to authenticated;

comment on function public.get_pdc_monitor_navision_identity_match(text,text) is
  'Read-only exact Stock+VIN comparison for an explicitly granted Viewer account; returns no raw VIN/source payload and grants no mutation capability.';

commit;
