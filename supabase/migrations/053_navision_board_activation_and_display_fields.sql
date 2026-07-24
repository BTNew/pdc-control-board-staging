-- Durable, review-gated Vehicle Location Board activation for shared Navision rows.
-- Staging-first and additive. Imports remain Back End Data until this activation
-- authority is set manually or by a staff-approved email/PD Document review.

begin;

create table if not exists public.navision_board_activations (
  backend_record_id uuid primary key references public.navision_backend_records(id) on delete cascade,
  activation_source text not null check (activation_source in ('manual', 'approved_email_build', 'approved_pd_document')),
  activated_stock_number text not null,
  activated_at timestamptz not null default now(),
  activated_by uuid references auth.users(id) on delete set null,
  activated_by_email text,
  updated_at timestamptz not null default now()
);

alter table public.navision_board_activations enable row level security;
revoke all on table public.navision_board_activations from public, anon, authenticated;

-- Extend the existing idempotency/audit vocabularies without replacing history.
alter table public.navision_operation_receipts
  drop constraint if exists navision_operation_receipts_operation_kind_check;
alter table public.navision_operation_receipts
  add constraint navision_operation_receipts_operation_kind_check
  check (operation_kind in ('apply', 'rollback', 'link', 'board_activate'));

alter table public.navision_backend_audit
  drop constraint if exists navision_backend_audit_action_check;
alter table public.navision_backend_audit
  add constraint navision_backend_audit_action_check
  check (action in ('import_apply', 'import_rollback', 'canonical_link', 'canonical_unlink', 'board_activate'));

create or replace function public.navision_original_column_value(
  p_normalized_data jsonb,
  p_header text
)
returns text
language sql
immutable
parallel safe
set search_path = pg_catalog, public
as $column$
  select nullif(btrim(cell ->> 'value'), '')
  from jsonb_array_elements(
    case
      when jsonb_typeof(p_normalized_data #> '{navisionRawEvidence,columns}') = 'array'
        then p_normalized_data #> '{navisionRawEvidence,columns}'
      else '[]'::jsonb
    end
  ) as cell
  where lower(regexp_replace(coalesce(cell ->> 'header', ''), '[^a-z0-9]+', '', 'g')) =
        lower(regexp_replace(coalesce(p_header, ''), '[^a-z0-9]+', '', 'g'))
  order by cell ->> 'header'
  limit 1;
$column$;

create or replace function public.activate_navision_backend_record(
  p_idempotency_key text,
  p_backend_record_id uuid,
  p_expected_revision bigint,
  p_activation_source text default 'manual'
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $activate$
declare
  v_role text := public.current_pdc_user_role()::text;
  v_source text := lower(btrim(coalesce(p_activation_source, '')));
  v_key text := btrim(coalesce(p_idempotency_key, ''));
  v_request_hash text;
  v_existing public.navision_operation_receipts%rowtype;
  v_record public.navision_backend_records%rowtype;
  v_stock_number text;
  v_revision bigint;
  v_result_revision bigint;
  v_response jsonb;
begin
  if not coalesce(v_role = any(array['operator','importer','administrator']), false) then
    return public.navision_backend_response(false, 'unauthorized');
  end if;
  if p_backend_record_id is null then
    return public.navision_backend_response(false, 'invalid_input', jsonb_build_object('field', 'backend_record_id'));
  end if;
  if v_key = '' or length(v_key) > 200 then
    return public.navision_backend_response(false, 'invalid_input', jsonb_build_object('field', 'idempotency_key'));
  end if;
  if p_expected_revision is null or p_expected_revision < 1 then
    return public.navision_backend_response(false, 'invalid_input', jsonb_build_object('field', 'expected_revision'));
  end if;
  if v_source not in ('manual', 'approved_email_build', 'approved_pd_document') then
    return public.navision_backend_response(false, 'invalid_input', jsonb_build_object('field', 'activation_source'));
  end if;

  v_request_hash := encode(extensions.digest(jsonb_build_object(
    'contract_version', 1,
    'idempotency_key', v_key,
    'backend_record_id', p_backend_record_id,
    'expected_revision', p_expected_revision,
    'activation_source', v_source
  )::text, 'sha256'), 'hex');

  perform pg_advisory_xact_lock(hashtextextended('navision-board-activate:' || v_key, 0));
  select * into v_existing
  from public.navision_operation_receipts
  where operation_kind = 'board_activate' and idempotency_key = v_key;
  if found then
    if v_existing.request_hash <> v_request_hash then
      return public.navision_backend_response(false, 'idempotency_conflict');
    end if;
    return v_existing.response;
  end if;

  perform pg_advisory_xact_lock(hashtextextended('navision-backend-store', 0));
  select revision into v_revision
  from public.navision_backend_revision
  where singleton
  for update;
  if v_revision <> p_expected_revision then
    return public.navision_backend_response(false, 'stale_revision', jsonb_build_object('current_revision', v_revision));
  end if;

  select * into v_record
  from public.navision_backend_records
  where id = p_backend_record_id
  for update;
  if not found then
    return public.navision_backend_response(false, 'not_found');
  end if;
  if not v_record.is_current or v_record.record_status <> 'current' then
    return public.navision_backend_response(false, 'record_not_current');
  end if;

  v_stock_number := nullif(btrim(coalesce(v_record.normalized_data ->> 'batch', '')), '');
  if v_stock_number is null then
    return public.navision_backend_response(false, 'stock_required');
  end if;

  if exists (
    select 1 from public.navision_board_activations
    where backend_record_id = p_backend_record_id
      and activated_stock_number = v_stock_number
  ) then
    v_response := public.navision_backend_response(true, 'already_activated', jsonb_build_object(
      'backend_record_id', p_backend_record_id,
      'result_revision', v_revision,
      'activated', true
    ));
  else
    insert into public.navision_board_activations (
      backend_record_id, activation_source, activated_stock_number, activated_by, activated_by_email
    ) values (
      p_backend_record_id, v_source, v_stock_number, auth.uid(), public.current_actor_email()
    )
    on conflict (backend_record_id) do update
      set activation_source = excluded.activation_source,
          activated_stock_number = excluded.activated_stock_number,
          activated_at = now(),
          activated_by = excluded.activated_by,
          activated_by_email = excluded.activated_by_email,
          updated_at = now();
    v_result_revision := v_revision + 1;
    update public.navision_backend_revision
    set revision = v_result_revision, updated_at = now()
    where singleton;
    insert into public.navision_backend_audit (
      action, backend_record_id, revision, evidence, actor_id, actor_email
    ) values (
      'board_activate', p_backend_record_id, v_result_revision,
      jsonb_build_object('activation_source', v_source, 'stock_number', v_stock_number),
      auth.uid(), public.current_actor_email()
    );
    v_response := public.navision_backend_response(true, 'board_activated', jsonb_build_object(
      'backend_record_id', p_backend_record_id,
      'result_revision', v_result_revision,
      'activated', true,
      'activation_source', v_source,
      'stock_number', v_stock_number
    ));
  end if;

  insert into public.navision_operation_receipts (
    operation_kind, idempotency_key, request_hash, response, actor_id, actor_email
  ) values (
    'board_activate', v_key, v_request_hash, v_response, auth.uid(), public.current_actor_email()
  );
  return v_response;
end;
$activate$;

revoke all on function public.activate_navision_backend_record(text, uuid, bigint, text)
from public, anon, authenticated;
grant execute on function public.activate_navision_backend_record(text, uuid, bigint, text)
to authenticated;

comment on function public.activate_navision_backend_record(text,uuid,bigint,text) is
  'Durably activates one current shared Navision record for Vehicle Locations after manual action or a staff-approved email/PD Document review.';

-- Replace only the approved-user display projection. The complete source row and
-- raw evidence remain inaccessible. Batch is explicitly the Stock authority.
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
  if v_source_system <> 'microsoft_navision' or v_dealer_code not in ('14450','37047') then
    return public.navision_backend_response(false, 'invalid_input', jsonb_build_object('field', 'scope'));
  end if;
  if p_page_size is null or p_page_size < 1 then
    return public.navision_backend_response(false, 'invalid_input', jsonb_build_object('field', 'page_size'));
  end if;

  v_page_size := least(p_page_size, 500);
  select revision into v_revision from public.navision_backend_revision where singleton;
  if p_expected_revision is not null and p_expected_revision <> v_revision then
    return public.navision_backend_response(false, 'stale_revision', jsonb_build_object('current_revision', v_revision));
  end if;

  with page as materialized (
    select r.*, a.activation_source, a.activated_stock_number, a.activated_at, a.activated_by
    from public.navision_backend_records r
    left join public.navision_board_activations a on a.backend_record_id = r.id
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
        'stock_number', nullif(normalized_data ->> 'batch', ''),

        'customer_name', coalesce(nullif(normalized_data ->> 'client', ''), nullif(normalized_data ->> 'customerSurname', ''), nullif(normalized_data ->> 'dealerCustomerName', ''), nullif(normalized_data ->> 'toyotaCustomer', '')),
        'salesperson', coalesce(public.navision_original_column_value(normalized_data, 'Salesperson'), nullif(normalized_data ->> 'salesperson', ''), nullif(normalized_data ->> 'consultant', ''), nullif(normalized_data ->> 'owner', '')),
        'model', coalesce(nullif(normalized_data ->> 'modelDescription', ''), nullif(normalized_data ->> 'toyotaVehicle', ''), nullif(normalized_data ->> 'vehicle', '')),
        'colour', coalesce(nullif(normalized_data ->> 'colourDescription', ''), nullif(normalized_data ->> 'colour', '')),
        'vehicle_status', coalesce(nullif(normalized_data ->> 'toyotaStatus', ''), nullif(normalized_data ->> 'navisionLocationStatus', ''), nullif(normalized_data ->> 'internalStatus', '')),
        'eta_to_kewdale', coalesce(nullif(normalized_data ->> 'navisionKewdaleEta', ''), nullif(normalized_data ->> 'etaAtDealer', '')),
        'board_activated', activation_source is not null
          and activated_stock_number = nullif(btrim(coalesce(normalized_data ->> 'batch', '')), ''),
        'activation_source', activation_source,
        'activated_at', activated_at
      ) order by id) from selected
    ), '[]'::jsonb),
    'has_more', (select count(*) > v_page_size from page),
    'next_record_id', case when (select count(*) > v_page_size from page)
      then (select id from selected order by id desc limit 1)
      else null
    end,
    'authority', 'shared_navision_backend_read_only_with_activation',
    'data_access', 'approved_staff_display'
  )) into v_result;
  return v_result;
end;
$visible$;

revoke all on function public.get_navision_visible_snapshot(text, text, uuid, integer, bigint)
from public, anon, authenticated;
grant execute on function public.get_navision_visible_snapshot(text, text, uuid, integer, bigint)
to authenticated;

commit;
