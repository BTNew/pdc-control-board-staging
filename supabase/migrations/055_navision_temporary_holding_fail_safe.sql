-- Navision import fail-safe: suspicious full-snapshot replacements fail closed,
-- omitted vehicles remain in temporary holding, and only Operator/Administrator
-- users may soft-archive a held record with an audited reason.
-- No vehicle or Navision source row is hard-deleted by this migration.

begin;

-- Extend the existing idempotency and audit vocabularies without replacing history.
alter table public.navision_operation_receipts
  drop constraint if exists navision_operation_receipts_operation_kind_check;
alter table public.navision_operation_receipts
  add constraint navision_operation_receipts_operation_kind_check
  check (operation_kind in ('apply', 'rollback', 'link', 'board_activate', 'holding_archive'));

alter table public.navision_backend_audit
  drop constraint if exists navision_backend_audit_action_check;
alter table public.navision_backend_audit
  add constraint navision_backend_audit_action_check
  check (action in ('import_apply', 'import_rollback', 'canonical_link', 'canonical_unlink', 'board_activate', 'holding_archive'));

-- Keep the pre-fail-safe entry points private. Guarded renames make this
-- migration safe to rehearse or re-run without renaming its own wrappers.
do $rename$
begin
  if to_regprocedure('public.preview_navision_backend_import_preholding_055(jsonb,text,text,text,timestamp with time zone)') is null then
    alter function public.preview_navision_backend_import(jsonb,text,text,text,timestamptz)
      rename to preview_navision_backend_import_preholding_055;
  end if;
  if to_regprocedure('public.apply_navision_backend_import_preholding_055(text,jsonb,text,text,text,timestamp with time zone,text,text,bigint)') is null then
    alter function public.apply_navision_backend_import(text,jsonb,text,text,text,timestamptz,text,text,bigint)
      rename to apply_navision_backend_import_preholding_055;
  end if;
  if to_regprocedure('public.rollback_navision_backend_import_preholding_055(text,text,bigint)') is null then
    alter function public.rollback_navision_backend_import(text,text,bigint)
      rename to rollback_navision_backend_import_preholding_055;
  end if;
end;
$rename$;

revoke all on function public.preview_navision_backend_import_preholding_055(jsonb,text,text,text,timestamptz)
  from public, anon, authenticated;
revoke all on function public.apply_navision_backend_import_preholding_055(text,jsonb,text,text,text,timestamptz,text,text,bigint)
  from public, anon, authenticated;
revoke all on function public.rollback_navision_backend_import_preholding_055(text,text,bigint)
  from public, anon, authenticated;

create or replace function public.navision_import_safety_assessment(
  p_rows jsonb,
  p_source_system text,
  p_dealer_code text,
  p_source_name text,
  p_preview_data jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, extensions
as $safety$
declare
  v_source_system text := lower(btrim(coalesce(p_source_system, '')));
  v_dealer_code text := btrim(coalesce(p_dealer_code, ''));
  v_source_name text := btrim(coalesce(p_source_name, ''));
  v_current_count integer := 0;
  v_incoming_count integer := 0;
  v_missing_count integer := 0;
  v_cross_dealer_matches integer := 0;
  v_selected_identity_matches integer := 0;
  v_filename_scope_match boolean := false;
  v_filename_scope_mismatch boolean := false;
  v_partial_snapshot boolean := false;
  v_reason text := null;
begin
  if v_source_system <> 'microsoft_navision'
     or v_dealer_code not in ('14450', '37047')
     or jsonb_typeof(p_rows) is distinct from 'array' then
    return jsonb_build_object(
      'blocking', true,
      'reason', 'invalid_scope_or_rows',
      'authority', 'navision_import_fail_safe_v1'
    );
  end if;

  select count(*)::integer
  into v_current_count
  from public.navision_backend_records r
  where r.source_system = v_source_system
    and r.dealer_code = v_dealer_code
    and r.is_current
    and r.record_status = 'current';

  v_missing_count := greatest(0, coalesce((p_preview_data #>> '{counts,missing}')::integer, 0));
  v_incoming_count := greatest(0,
    coalesce((p_preview_data #>> '{counts,total}')::integer, 0)
    - coalesce((p_preview_data #>> '{counts,invalid}')::integer, 0)
    - coalesce((p_preview_data #>> '{counts,conflict}')::integer, 0)
  );

  with incoming as materialized (
    select distinct
      public.normalize_vehicle_source_identifier(public.navision_backend_source_record_id(e.value)) as source_record_id_normalized
    from jsonb_array_elements(p_rows) e(value)
    where jsonb_typeof(e.value) = 'object'
      and not public.navision_backend_row_has_forbidden_fields(e.value)
      and public.navision_backend_source_record_id(e.value) is not null
  ), matches as materialized (
    select distinct i.source_record_id_normalized, r.dealer_code
    from incoming i
    join public.navision_backend_records r
      on r.source_system = v_source_system
     and r.source_record_id_normalized = i.source_record_id_normalized
  )
  select
    count(distinct source_record_id_normalized) filter (
      where dealer_code <> v_dealer_code and dealer_code <> 'LEGACY_UNSCOPED'
    )::integer,
    count(distinct source_record_id_normalized) filter (
      where dealer_code = v_dealer_code
    )::integer
  into v_cross_dealer_matches, v_selected_identity_matches
  from matches;

  v_filename_scope_match :=
    (v_dealer_code = '14450' and v_source_name ~ '(^|[^0-9])14450([^0-9]|$)')
    or (v_dealer_code = '37047' and v_source_name ~ '(^|[^0-9])37047([^0-9]|$)');

  -- A filename containing the other known dealer code is direct contrary scope evidence.
  v_filename_scope_mismatch :=
    (v_dealer_code = '14450' and v_source_name ~ '(^|[^0-9])37047([^0-9]|$)')
    or (v_dealer_code = '37047' and v_source_name ~ '(^|[^0-9])14450([^0-9]|$)');

  -- Navision imports are full dealer snapshots. A zero-row/invalid-only file, a
  -- one-row replacement of a multi-row scope, a complete scope replacement, or
  -- a drop of at least two rows and 25% of the current scope is suspicious.
  v_partial_snapshot :=
    v_incoming_count = 0
    or (
      v_missing_count > 0
      and v_current_count > 0
      and (
        v_missing_count = v_current_count
        or (v_current_count >= 2 and v_incoming_count <= 1)
        or (v_missing_count >= 2 and (v_missing_count * 4) >= v_current_count)
      )
    );

  if v_filename_scope_mismatch then
    v_reason := 'source_name_dealer_scope_mismatch';
  elsif v_cross_dealer_matches > 0 then
    v_reason := 'cross_dealer_identity_overlap';
  elsif v_incoming_count = 0 then
    v_reason := 'suspicious_partial_snapshot';
  elsif v_current_count = 0
        and v_selected_identity_matches = 0 then
    -- An empty destination scope has no authoritative baseline. Filename text
    -- and legacy-unscoped overlap are operator-controlled hints, not proof that
    -- unseen rows belong to the selected dealer. A first-time scope therefore
    -- needs a separately verified dealer binding before this import path can
    -- reconcile any rows.
    v_reason := 'unproven_empty_dealer_scope';
  elsif v_partial_snapshot then
    v_reason := 'suspicious_partial_snapshot';
  end if;

  return jsonb_build_object(
    'blocking', v_reason is not null,
    'reason', v_reason,
    'authority', 'navision_import_fail_safe_v1',
    'selected_dealer_code', v_dealer_code,
    'current_count', v_current_count,
    'incoming_valid_count', v_incoming_count,
    'missing_count', v_missing_count,
    'cross_dealer_matches', v_cross_dealer_matches,
    'selected_identity_matches', v_selected_identity_matches,
    'filename_scope_match', v_filename_scope_match,
    'policy', jsonb_build_object(
      'snapshot_type', 'full_dealer_snapshot',
      'missing_destination', 'temporary_holding',
      'hard_delete', false
    )
  );
end;
$safety$;

revoke all on function public.navision_import_safety_assessment(jsonb,text,text,text,jsonb)
  from public, anon, authenticated;

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
as $preview$
declare
  v_result jsonb;
  v_data jsonb;
  v_safety jsonb;
begin
  if not coalesce(public.current_pdc_user_role()::text = any (array['importer', 'administrator']), false) then
    return public.navision_backend_response(false, 'unauthorized');
  end if;

  v_result := public.navision_backend_preview_internal(
    p_rows, p_source_system, p_dealer_code, p_source_name, p_source_timestamp
  );
  if coalesce((v_result ->> 'ok')::boolean, false) is not true then
    return v_result;
  end if;

  v_data := coalesce(v_result -> 'data', '{}'::jsonb);
  v_safety := public.navision_import_safety_assessment(
    p_rows, p_source_system, p_dealer_code, p_source_name, v_data
  );
  v_data := v_data || jsonb_build_object(
    'safety', v_safety,
    'blocking', coalesce((v_data ->> 'blocking')::boolean, false)
      or coalesce((v_safety ->> 'blocking')::boolean, true),
    'missing_destination', 'temporary_holding'
  );
  return jsonb_set(v_result, '{data}', v_data, true);
end;
$preview$;

revoke all on function public.preview_navision_backend_import(jsonb,text,text,text,timestamptz)
  from public, anon, authenticated;
grant execute on function public.preview_navision_backend_import(jsonb,text,text,text,timestamptz)
  to authenticated;

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
  v_preview jsonb;
  v_safety jsonb;
begin
  if not coalesce(public.current_pdc_user_role()::text = any (array['importer', 'administrator']), false) then
    return public.navision_backend_response(false, 'unauthorized');
  end if;

  -- Recompute the preview and the independent safety assessment inside the
  -- mutation transaction. A browser cannot bypass this gate by editing preview data.
  v_preview := public.navision_backend_preview_internal(
    p_rows, p_source_system, p_dealer_code, p_source_name, p_source_timestamp
  );
  if coalesce((v_preview ->> 'ok')::boolean, false) is not true then
    return v_preview;
  end if;
  v_safety := public.navision_import_safety_assessment(
    p_rows, p_source_system, p_dealer_code, p_source_name, v_preview -> 'data'
  );
  if coalesce((v_safety ->> 'blocking')::boolean, true) then
    return public.navision_backend_response(false, 'suspicious_import_blocked', jsonb_build_object(
      'safety', v_safety,
      'message', 'No Navision records changed. Check the full file and selected dealer scope.'
    ));
  end if;

  return public.apply_navision_backend_import_preholding_055(
    p_idempotency_key,
    p_rows,
    p_source_system,
    p_dealer_code,
    p_source_name,
    p_source_timestamp,
    p_source_hash,
    p_preview_hash,
    p_expected_revision
  );
end;
$apply$;

revoke all on function public.apply_navision_backend_import(text,jsonb,text,text,text,timestamptz,text,text,bigint)
  from public, anon, authenticated;
grant execute on function public.apply_navision_backend_import(text,jsonb,text,text,text,timestamptz,text,text,bigint)
  to authenticated;

-- Batch rollback previously hard-deleted rows created by an import. It remains
-- unavailable through the authenticated API; recovery now uses holding,
-- re-import, or audited soft archive.
create or replace function public.rollback_navision_backend_import(
  p_idempotency_key text,
  p_target_batch_id text,
  p_expected_revision bigint
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, extensions
as $rollback_disabled$
begin
  if public.current_pdc_user_role() is distinct from 'administrator' then
    return public.navision_backend_response(false, 'unauthorized');
  end if;
  return public.navision_backend_response(false, 'rollback_disabled_use_temporary_holding', jsonb_build_object(
    'hard_delete', false,
    'message', 'Batch rollback is disabled. Use a corrected full import or audited Temporary Holding archive.'
  ));
end;
$rollback_disabled$;

revoke all on function public.rollback_navision_backend_import(text,text,bigint)
  from public, anon, authenticated;
grant execute on function public.rollback_navision_backend_import(text,text,bigint)
  to authenticated;

create or replace function public.archive_navision_holding_record(
  p_idempotency_key text,
  p_backend_record_id uuid,
  p_expected_record_version bigint,
  p_expected_revision bigint,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $archive$
declare
  v_role public.pdc_role;
  v_key text := btrim(coalesce(p_idempotency_key, ''));
  v_reason text := btrim(coalesce(p_reason, ''));
  v_request_hash text;
  v_existing public.navision_operation_receipts%rowtype;
  v_record public.navision_backend_records%rowtype;
  v_revision bigint;
  v_result_revision bigint;
  v_response jsonb;
  v_board_activated boolean := false;
begin
  v_role := public.current_pdc_user_role();
  if v_role is null or v_role::text <> 'administrator' then
    return public.navision_backend_response(false, 'unauthorized');
  end if;
  if length(v_key) < 8 or length(v_key) > 200 then
    return public.navision_backend_response(false, 'invalid_input', jsonb_build_object('field', 'idempotency_key'));
  end if;
  if p_backend_record_id is null or p_expected_record_version is null or p_expected_record_version < 1
     or p_expected_revision is null or p_expected_revision < 1 then
    return public.navision_backend_response(false, 'invalid_input', jsonb_build_object('field', 'identity_or_revision'));
  end if;
  if length(v_reason) < 10 or length(v_reason) > 500 then
    return public.navision_backend_response(false, 'invalid_input', jsonb_build_object('field', 'reason'));
  end if;

  v_request_hash := encode(extensions.digest(jsonb_build_object(
    'operation', 'holding_archive',
    'record_id', p_backend_record_id,
    'expected_record_version', p_expected_record_version,
    'expected_revision', p_expected_revision,
    'reason', v_reason
  )::text, 'sha256'), 'hex');

  perform pg_advisory_xact_lock(hashtextextended('navision-holding-archive:' || v_key, 0));
  select * into v_existing
  from public.navision_operation_receipts
  where operation_kind = 'holding_archive' and idempotency_key = v_key;
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
  if v_revision is null or v_revision <> p_expected_revision then
    return public.navision_backend_response(false, 'stale_revision', jsonb_build_object('current_revision', v_revision));
  end if;

  select * into v_record
  from public.navision_backend_records
  where id = p_backend_record_id
  for update;
  if not found then
    return public.navision_backend_response(false, 'not_found');
  end if;
  if v_record.version <> p_expected_record_version then
    return public.navision_backend_response(false, 'stale_record', jsonb_build_object('current_version', v_record.version));
  end if;
  if v_record.is_current or v_record.record_status <> 'not_in_latest_batch' then
    return public.navision_backend_response(false, 'record_not_in_holding');
  end if;

  select exists (
    select 1 from public.navision_board_activations a
    where a.backend_record_id = v_record.id
      and a.activated_stock_number = nullif(btrim(coalesce(v_record.normalized_data ->> 'batch', '')), '')
  ) into v_board_activated;

  update public.navision_backend_records
  set record_status = 'inactive',
      version = version + 1,
      updated_at = now()
  where id = v_record.id;

  v_result_revision := v_revision + 1;
  update public.navision_backend_revision
  set revision = v_result_revision, updated_at = now()
  where singleton;

  insert into public.navision_backend_audit (
    action, backend_record_id, revision, evidence, actor_id, actor_email
  ) values (
    'holding_archive', v_record.id, v_result_revision,
    jsonb_build_object(
      'reason', v_reason,
      'dealer_code', v_record.dealer_code,
      'prior_status', v_record.record_status,
      'prior_version', v_record.version,
      'result_status', 'inactive',
      'result_version', v_record.version + 1,
      'actor_role', v_role::text,
      'board_activated', v_board_activated,
      'hard_delete', false
    ),
    auth.uid(), public.current_actor_email()
  );

  v_response := public.navision_backend_response(true, 'holding_record_archived', jsonb_build_object(
    'backend_record_id', v_record.id,
    'result_revision', v_result_revision,
    'record_version', v_record.version + 1,
    'record_status', 'inactive',
    'board_activated', v_board_activated,
    'hard_delete', false
  ));

  insert into public.navision_operation_receipts (
    operation_kind, idempotency_key, request_hash, response, actor_id, actor_email
  ) values (
    'holding_archive', v_key, v_request_hash, v_response, auth.uid(), public.current_actor_email()
  );
  return v_response;
end;
$archive$;

revoke all on function public.archive_navision_holding_record(text,uuid,bigint,bigint,text)
  from public, anon, authenticated;
grant execute on function public.archive_navision_holding_record(text,uuid,bigint,bigint,text)
  to authenticated;

comment on function public.archive_navision_holding_record(text,uuid,bigint,bigint,text) is
  'Administrator-only audited soft archive for one non-current Navision record in Temporary Holding. Never hard-deletes source or operational vehicle data.';

-- Extend the already-approved minimized staff projection with optimistic version
-- data required by the holding archive RPC. Raw VIN/source payload remains hidden.
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
      and r.record_status <> 'inactive'
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
        'version', version,
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
    'authority', 'shared_navision_backend_read_only_with_activation_and_holding',
    'data_access', 'approved_staff_display'
  )) into v_result;
  return v_result;
end;
$visible$;

revoke all on function public.get_navision_visible_snapshot(text,text,uuid,integer,bigint)
  from public, anon, authenticated;
grant execute on function public.get_navision_visible_snapshot(text,text,uuid,integer,bigint)
  to authenticated;

commit;
