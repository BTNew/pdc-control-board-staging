begin;

-- Atomically commit all online-state documents participating in one legacy
-- UI transaction. Each item still uses the existing role/version/idempotency,
-- canonical reconciliation and audit controls. The exception block rolls the
-- entire batch back if any item is rejected.
create or replace function public.save_pdc_online_state_batch(
  p_items jsonb,
  p_batch_key text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $batch$
declare
  v_batch_key text := lower(btrim(coalesce(p_batch_key, '')));
  v_item jsonb;
  v_result jsonb;
  v_results jsonb := '[]'::jsonb;
  v_index integer := 0;
  v_keys text[] := '{}'::text[];
  v_key text;
  v_idempotency text;
begin
  if auth.uid() is null or public.current_pdc_user_role()::text not in ('operator', 'importer', 'administrator') then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if v_batch_key !~ '^pdc-batch-[a-f0-9]{32}$' then
    return jsonb_build_object('ok', false, 'error', 'invalid_batch_key');
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) < 1 or jsonb_array_length(p_items) > 20 then
    return jsonb_build_object('ok', false, 'error', 'invalid_batch_items');
  end if;

  begin
    for v_item in select value from jsonb_array_elements(p_items)
    loop
      v_index := v_index + 1;
      if jsonb_typeof(v_item) <> 'object' then
        raise exception using errcode = 'P0001', message = 'invalid_batch_item';
      end if;
      v_key := btrim(coalesce(v_item->>'state_key', ''));
      if not public.pdc_online_state_key_allowed(v_key) then
        raise exception using errcode = 'P0001', message = 'invalid_state_key';
      end if;
      if v_key = any(v_keys) then
        raise exception using errcode = 'P0001', message = 'duplicate_state_key';
      end if;
      v_keys := array_append(v_keys, v_key);
      if not (v_item ? 'expected_version') or (v_item->>'expected_version') !~ '^[0-9]+$' then
        raise exception using errcode = 'P0001', message = 'expected_version_required';
      end if;
      v_idempotency := 'pdc-online-' || substr(
        encode(extensions.digest(v_batch_key || ':' || v_index::text, 'sha256'), 'hex'),
        1, 32
      );
      v_result := public.save_pdc_online_state(
        v_key,
        v_item->'payload',
        (v_item->>'expected_version')::bigint,
        v_idempotency
      );
      if coalesce((v_result->>'ok')::boolean, false) is not true then
        raise exception using errcode = 'P0001', message = coalesce(v_result->>'error', 'batch_item_failed');
      end if;
      v_results := v_results || jsonb_build_array(v_result);
    end loop;
    return jsonb_build_object(
      'ok', true,
      'authority', 'supabase_online_only',
      'results', v_results,
      'revision', coalesce((v_results->(jsonb_array_length(v_results) - 1)->>'revision')::bigint, 0)
    );
  exception
    when others then
      return jsonb_build_object(
        'ok', false,
        'error', 'batch_failed',
        'detail', sqlerrm
      );
  end;
end;
$batch$;

revoke all on function public.save_pdc_online_state_batch(jsonb,text) from public, anon, authenticated;
grant execute on function public.save_pdc_online_state_batch(jsonb,text) to authenticated;
comment on function public.save_pdc_online_state_batch(jsonb,text) is
  'Atomic multi-document online-state mutation. Any rejected item rolls the complete batch back.';

commit;
