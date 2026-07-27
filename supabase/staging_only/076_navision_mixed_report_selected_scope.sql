-- Staging-only migration 076.
-- A pasted Navision report can contain both approved dealer scopes. Scope the
-- server Preview and Apply paths to the selected dealer only when every source
-- row has valid original Dealer evidence for one of the two approved dealers.
begin;

create or replace function public.navision_scope_rows_for_selected_dealer(
  p_rows jsonb,
  p_source_system text,
  p_dealer_code text
)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','public','extensions'
as $$
declare
  v_selected text:=regexp_replace(btrim(coalesce(p_dealer_code,'')), '^0+', '');
  v_total integer:=0;
  v_valid integer:=0;
  v_known integer:=0;
  v_selected_count integer:=0;
  v_other_count integer:=0;
  v_rows jsonb:='[]'::jsonb;
begin
  if jsonb_typeof(p_rows)<>'array'
     or lower(btrim(coalesce(p_source_system,'')))<>'microsoft_navision'
     or v_selected not in ('14450','37047') then
    return jsonb_build_object('applied',false,'rows',p_rows,'reason','not_eligible_scope');
  end if;

  v_total:=jsonb_array_length(p_rows);
  with source_rows as materialized (
    select e.ordinality,e.value,
           public.navision_row_declared_dealer_code(e.value) declared_dealer,
           (jsonb_typeof(e.value)='object'
            and not public.navision_backend_row_has_forbidden_fields(e.value)
            and public.navision_backend_source_record_id(e.value) is not null) valid
    from jsonb_array_elements(p_rows) with ordinality e(value,ordinality)
  )
  select count(*) filter(where valid)::integer,
         count(*) filter(where valid and declared_dealer in ('14450','37047'))::integer,
         count(*) filter(where valid and declared_dealer=v_selected)::integer,
         count(*) filter(where valid and declared_dealer in ('14450','37047') and declared_dealer<>v_selected)::integer,
         coalesce(jsonb_agg(value order by ordinality) filter(where valid and declared_dealer=v_selected),'[]'::jsonb)
  into v_valid,v_known,v_selected_count,v_other_count,v_rows
  from source_rows;

  -- Never hide invalid, missing-dealer or unknown-dealer rows. Auto-scoping is
  -- permitted only for a substantial selected-dealer snapshot inside a fully
  -- evidenced two-dealer report.
  if v_total=v_valid
     and v_valid=v_known
     and v_selected_count>=100
     and v_other_count>0 then
    return jsonb_build_object(
      'applied',true,
      'rows',v_rows,
      'selected_dealer_code',v_selected,
      'source_rows',v_total,
      'selected_rows',v_selected_count,
      'ignored_other_dealer_rows',v_other_count,
      'authority','navision_original_dealer_column_v1'
    );
  end if;

  return jsonb_build_object(
    'applied',false,
    'rows',p_rows,
    'selected_dealer_code',v_selected,
    'source_rows',v_total,
    'valid_rows',v_valid,
    'known_dealer_rows',v_known,
    'selected_rows',v_selected_count,
    'other_dealer_rows',v_other_count,
    'reason','mixed_report_not_safely_scopeable'
  );
end
$$;

revoke all on function public.navision_scope_rows_for_selected_dealer(jsonb,text,text) from public;

-- Preserve and wrap Preview.
do $rename_preview$
begin
  if to_regprocedure('public.preview_navision_backend_import_pre076(jsonb,text,text,text,timestamptz)') is null then
    alter function public.preview_navision_backend_import(jsonb,text,text,text,timestamptz)
      rename to preview_navision_backend_import_pre076;
  end if;
end
$rename_preview$;

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
set search_path='pg_catalog','public','extensions'
as $$
declare
  v_scope jsonb;
  v_result jsonb;
  v_data jsonb;
begin
  v_scope:=public.navision_scope_rows_for_selected_dealer(p_rows,p_source_system,p_dealer_code);
  v_result:=public.preview_navision_backend_import_pre076(
    case when coalesce((v_scope->>'applied')::boolean,false) then v_scope->'rows' else p_rows end,
    p_source_system,p_dealer_code,p_source_name,p_source_timestamp
  );
  if coalesce((v_result->>'ok')::boolean,false)
     and coalesce((v_scope->>'applied')::boolean,false) then
    v_data:=coalesce(v_result->'data','{}'::jsonb) || jsonb_build_object(
      'source_scope_filter',v_scope-'rows'
    );
    v_result:=jsonb_set(v_result,'{data}',v_data,true);
  end if;
  return v_result;
end
$$;

revoke all on function public.preview_navision_backend_import(jsonb,text,text,text,timestamptz) from public;
grant execute on function public.preview_navision_backend_import(jsonb,text,text,text,timestamptz) to authenticated;

-- Preserve and wrap Apply with the identical server-side scope operation.
do $rename_apply$
begin
  if to_regprocedure('public.apply_navision_backend_import_pre076(text,jsonb,text,text,text,timestamptz,text,text,bigint)') is null then
    alter function public.apply_navision_backend_import(text,jsonb,text,text,text,timestamptz,text,text,bigint)
      rename to apply_navision_backend_import_pre076;
  end if;
end
$rename_apply$;

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
set search_path='pg_catalog','public','extensions'
as $$
declare
  v_scope jsonb;
  v_result jsonb;
  v_data jsonb;
begin
  v_scope:=public.navision_scope_rows_for_selected_dealer(p_rows,p_source_system,p_dealer_code);
  v_result:=public.apply_navision_backend_import_pre076(
    p_idempotency_key,
    case when coalesce((v_scope->>'applied')::boolean,false) then v_scope->'rows' else p_rows end,
    p_source_system,p_dealer_code,p_source_name,p_source_timestamp,
    p_source_hash,p_preview_hash,p_expected_revision
  );
  if coalesce((v_result->>'ok')::boolean,false)
     and coalesce((v_scope->>'applied')::boolean,false) then
    v_data:=coalesce(v_result->'data','{}'::jsonb) || jsonb_build_object(
      'source_scope_filter',v_scope-'rows'
    );
    v_result:=jsonb_set(v_result,'{data}',v_data,true);
  end if;
  return v_result;
end
$$;

revoke all on function public.apply_navision_backend_import(text,jsonb,text,text,text,timestamptz,text,text,bigint) from public;
grant execute on function public.apply_navision_backend_import(text,jsonb,text,text,text,timestamptz,text,text,bigint) to authenticated;

commit;
