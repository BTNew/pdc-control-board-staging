-- Keep the existing public contract, authorization, exact-preview hashes,
-- dealer scope, retention, audit and all-or-nothing save. Avoid normalizing
-- each source row three times per preview, then re-hashing it during apply.
DO $$ BEGIN IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'wrong_environment'; END IF; END $$;

-- Prevent imports from changing the destination between equivalence checks.
SELECT pg_advisory_xact_lock(hashtextextended('navision-backend-store',0));
CREATE TEMP TABLE pdc_upload_preview_equivalence ON COMMIT DROP AS
SELECT dealer_code,jsonb_agg(raw_evidence ORDER BY id) AS rows,
 public.navision_backend_preview_internal(jsonb_agg(raw_evidence ORDER BY id),'microsoft_navision',dealer_code,'migration-equivalence.tsv',NULL) AS before_result
FROM public.navision_backend_records WHERE source_system='microsoft_navision' AND is_current AND record_status='current'
AND dealer_code IN('14450','37047','001234','002345') GROUP BY dealer_code;

CREATE OR REPLACE FUNCTION public.navision_backend_preview_internal(p_rows jsonb, p_source_system text, p_dealer_code text, p_source_name text, p_source_timestamp timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
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
  if v_dealer_code not in ('14450', '37047','002345','001234') then return public.navision_backend_response(false, 'invalid_input', jsonb_build_object('field', 'dealer_code')); end if;
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

  with prepared as materialized (
    select e.ordinality::integer as row_index,e.value as raw_row,
      public.navision_backend_normalize_row(e.value) as normalized
    from jsonb_array_elements(p_rows) with ordinality e(value,ordinality)
  ), rows as materialized (
    select row_index,raw_row,
      public.navision_backend_source_record_id(raw_row) as source_record_id,
      encode(extensions.digest(coalesce(normalized,'null'::jsonb)::text,'sha256'),'hex') as row_hash,
      public.navision_backend_row_has_forbidden_fields(raw_row) as forbidden
    from prepared
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

  select
    (select encode(extensions.digest(coalesce(jsonb_agg(jsonb_build_object(
       'row_index',row_index,'source_record_id',source_record_id,
       'row_hash',row_hash,'forbidden',forbidden
     ) order by row_index),'[]'::jsonb)::text,'sha256'),'hex') from rows),
    (select coalesce(jsonb_agg(jsonb_build_object(
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
  ) order by row_index), '[]'::jsonb) from item_rows)
  into v_source_hash,v_items;

  with incoming as materialized (
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
$function$;


CREATE OR REPLACE FUNCTION public.apply_navision_backend_import_preholding_055(p_idempotency_key text, p_rows jsonb, p_source_system text, p_dealer_code text, p_source_name text, p_source_timestamp timestamp with time zone, p_source_hash text, p_preview_hash text, p_expected_revision bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
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
    v_source_record_id := v_item ->> 'source_record_id';
    v_row_hash := v_item ->> 'row_hash';
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
    perform public.navision_refresh_linked_vehicle_projection_770(v_record.id);

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
$function$;


-- Keep a bounded timeout with headroom for the largest supported dealer files.
-- Publishing it on the RPC makes PostgREST apply the limit to the whole save.
ALTER FUNCTION public.apply_navision_upload_profile(text,text,jsonb,text,timestamptz,text,text,bigint) SET statement_timeout='120s';
ALTER FUNCTION pdc_navision_upload_private.apply_profile(text,text,jsonb,text,timestamptz,text,text,bigint) SET statement_timeout='120s';

DO $verify$
DECLARE sample record; after_result jsonb;
BEGIN
 FOR sample IN SELECT * FROM pdc_upload_preview_equivalence LOOP
  after_result:=public.navision_backend_preview_internal(sample.rows,'microsoft_navision',sample.dealer_code,'migration-equivalence.tsv',NULL);
  IF after_result IS DISTINCT FROM sample.before_result THEN
   RAISE EXCEPTION 'optimized_preview_contract_changed_for_dealer_%',sample.dealer_code;
  END IF;
 END LOOP;
 IF NOT has_function_privilege('authenticated','pdc_navision_upload_private.preview_profile(text,jsonb,text,timestamptz)','EXECUTE') THEN
  RAISE EXCEPTION 'navision_upload_staff_access_missing';
 END IF;
END $verify$;
NOTIFY pgrst,'reload schema';
