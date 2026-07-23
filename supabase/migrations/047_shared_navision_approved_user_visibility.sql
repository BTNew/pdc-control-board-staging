-- Shared Navision approved-user visibility.
-- Additive, read-only projection: imported source data remains backend-only and
-- does not become operational vehicle/workshop authority.

begin;

-- The revision row contains only a monotonically increasing number. Allow every
-- approved signed-in role to receive the Realtime refresh signal.
drop policy if exists navision_backend_revision_operator_read on public.navision_backend_revision;
drop policy if exists navision_backend_revision_approved_read on public.navision_backend_revision;
create policy navision_backend_revision_approved_read
on public.navision_backend_revision
for select
to authenticated
using (
  coalesce(
    public.current_pdc_user_role()::text = any(array['viewer','operator','importer','administrator']),
    false
  )
);

-- Deliberately restricted projection for cross-browser visibility. It returns
-- only display-safe operational identifiers/status fields, never the complete
-- normalized source row or raw source evidence.
create or replace function public.get_navision_visible_snapshot(
  p_source_system text,
  p_dealer_code text,
  p_after_record_id uuid default null,
  p_page_size integer default 200,
  p_expected_revision bigint default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, extensions
as $visible$
declare
  v_role text := public.current_pdc_user_role()::text;
  v_source_system text := lower(btrim(coalesce(p_source_system, '')));
  v_dealer_code text := btrim(coalesce(p_dealer_code, ''));
  v_page_size integer;
  v_revision bigint;
  v_result jsonb;
begin
  if not coalesce(v_role = any(array['viewer','operator','importer','administrator']), false) then
    return public.navision_backend_response(false, 'unauthorized');
  end if;
  -- Approved PDC staff accounts are globally entitled to the restricted shared
  -- import view; there is no per-user dealership partition in pdc_user_roles.
  -- Dealer scope remains exact and caller-selected only within this fixed allowlist.
  if v_source_system <> 'microsoft_navision' or v_dealer_code not in ('14450','37047') then
    return public.navision_backend_response(false, 'invalid_input', jsonb_build_object('field', 'scope'));
  end if;
  if p_page_size is null or p_page_size < 1 then
    return public.navision_backend_response(false, 'invalid_input', jsonb_build_object('field', 'page_size'));
  end if;

  v_page_size := least(p_page_size, 500);
  select revision into v_revision
  from public.navision_backend_revision
  where singleton;

  if p_expected_revision is not null and p_expected_revision <> v_revision then
    return public.navision_backend_response(
      false,
      'stale_revision',
      jsonb_build_object('current_revision', v_revision)
    );
  end if;

  with page as materialized (
    select r.*
    from public.navision_backend_records r
    where r.source_system = v_source_system
      and r.dealer_code = v_dealer_code
      and (p_after_record_id is null or r.id > p_after_record_id)
    order by r.id
    limit v_page_size + 1
  ), selected as materialized (
    select * from page order by id limit v_page_size
  )
  select public.navision_backend_response(true, 'visible_snapshot', jsonb_build_object(
    'revision', v_revision,
    'source_system', v_source_system,
    'dealer_code', v_dealer_code,
    'page_size', v_page_size,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id,
        'dealer_code', dealer_code,
        'record_status', record_status,
        'is_current', is_current,
        'updated_at', updated_at,
        'stock_number', coalesce(nullif(normalized_data ->> 'stock', ''), nullif(normalized_data ->> 'batch', '')),
        'toyota_order_number', nullif(normalized_data ->> 'order', ''),
        'model', coalesce(nullif(normalized_data ->> 'vehicle', ''), nullif(normalized_data ->> 'modelDescription', ''), nullif(normalized_data ->> 'toyotaVehicle', '')),
        'colour', coalesce(nullif(normalized_data ->> 'colourDescription', ''), nullif(normalized_data ->> 'colour', '')),
        'vehicle_status', coalesce(nullif(normalized_data ->> 'toyotaStatus', ''), nullif(normalized_data ->> 'navisionLocationStatus', ''), nullif(normalized_data ->> 'internalStatus', '')),
        'eta_to_kewdale', coalesce(nullif(normalized_data ->> 'navisionKewdaleEta', ''), nullif(normalized_data ->> 'etaAtDealer', ''))
      ) order by id)
      from selected
    ), '[]'::jsonb),
    'has_more', (select count(*) > v_page_size from page),
    'next_record_id', case when (select count(*) > v_page_size from page)
      then (select id from selected order by id desc limit 1)
      else null
    end,
    'authority', 'shared_navision_backend_read_only',
    'data_access', 'restricted_display'
  )) into v_result;

  return v_result;
end;
$visible$;

revoke all on function public.get_navision_visible_snapshot(text, text, uuid, integer, bigint)
from public, anon, authenticated;
grant execute on function public.get_navision_visible_snapshot(text, text, uuid, integer, bigint)
to authenticated;

comment on function public.get_navision_visible_snapshot(text,text,uuid,integer,bigint) is
  'Read-only restricted Navision display projection for every approved signed-in PDC role; does not expose full source payloads or mutate operational vehicles.';

commit;
