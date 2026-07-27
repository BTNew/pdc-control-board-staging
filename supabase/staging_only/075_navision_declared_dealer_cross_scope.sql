-- Staging-only migration 075.
-- A Navision extract carries a server-verifiable Dealer column in each source
-- row. Permit cross-scope identity overlap only when every valid incoming row
-- explicitly declares the selected dealer. This supports genuine vehicle moves
-- between dealer scopes without trusting the browser's selected option alone.
begin;

create or replace function public.navision_row_declared_dealer_code(p_row jsonb)
returns text
language sql
immutable
set search_path='pg_catalog','public'
as $$
  select nullif(regexp_replace(btrim(c.value->>'value'), '^0+', ''), '')
  from jsonb_array_elements(
    case
      when jsonb_typeof(p_row #> '{navisionRawEvidence,columns}')='array'
        then p_row #> '{navisionRawEvidence,columns}'
      when jsonb_typeof(p_row #> '{raw_evidence,columns}')='array'
        then p_row #> '{raw_evidence,columns}'
      else '[]'::jsonb
    end
  ) c(value)
  where regexp_replace(lower(btrim(coalesce(c.value->>'header',''))), '[^a-z0-9]+', '', 'g')
    in ('dealer','dealercode','dealerno','dealernumber')
  limit 1
$$;

revoke all on function public.navision_row_declared_dealer_code(jsonb) from public;

-- Reapply-safe preservation of the prior safety layer.
do $rename$
begin
  if to_regprocedure('public.navision_import_safety_assessment_pre075(jsonb,text,text,text,jsonb)') is null then
    alter function public.navision_import_safety_assessment(jsonb,text,text,text,jsonb)
      rename to navision_import_safety_assessment_pre075;
  end if;
end
$rename$;

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
set search_path='pg_catalog','public','extensions'
as $$
declare
  v_result jsonb;
  v_reason text;
  v_selected text:=regexp_replace(btrim(coalesce(p_dealer_code,'')), '^0+', '');
  v_incoming integer:=0;
  v_valid_rows integer:=0;
  v_declared_selected integer:=0;
  v_declared_missing integer:=0;
  v_declared_other integer:=0;
begin
  v_result:=public.navision_import_safety_assessment_pre075(
    p_rows,p_source_system,p_dealer_code,p_source_name,p_preview_data
  );
  v_reason:=coalesce(v_result->>'reason','');
  v_incoming:=coalesce((v_result->>'incoming_valid_count')::integer,0);

  if v_reason='cross_dealer_identity_overlap'
     and lower(btrim(coalesce(p_source_system,'')))='microsoft_navision'
     and v_selected in ('14450','37047')
     and v_incoming>=100
     and jsonb_typeof(p_rows)='array' then
    with valid_rows as materialized (
      select e.value,
             public.navision_row_declared_dealer_code(e.value) as declared_dealer
      from jsonb_array_elements(p_rows) e(value)
      where jsonb_typeof(e.value)='object'
        and not public.navision_backend_row_has_forbidden_fields(e.value)
        and public.navision_backend_source_record_id(e.value) is not null
    )
    select count(*)::integer,
           count(*) filter(where declared_dealer=v_selected)::integer,
           count(*) filter(where declared_dealer is null)::integer,
           count(*) filter(where declared_dealer is not null and declared_dealer<>v_selected)::integer
    into v_valid_rows,v_declared_selected,v_declared_missing,v_declared_other
    from valid_rows;

    if v_valid_rows=v_incoming
       and v_declared_selected=v_incoming
       and v_declared_missing=0
       and v_declared_other=0 then
      v_result:=jsonb_set(v_result,'{blocking}','false'::jsonb,true);
      v_result:=jsonb_set(v_result,'{reason}','null'::jsonb,true);
      v_result:=jsonb_set(v_result,'{authority}',to_jsonb('navision_declared_dealer_scope_v1'::text),true);
      v_result:=jsonb_set(v_result,'{declared_dealer_release}',jsonb_build_object(
        'released',true,
        'selected_dealer_code',v_selected,
        'valid_rows',v_valid_rows,
        'declared_selected_rows',v_declared_selected,
        'declared_missing_rows',v_declared_missing,
        'declared_other_rows',v_declared_other,
        'minimum_incoming',100,
        'hard_delete',false
      ),true);
    end if;
  end if;

  return v_result;
end
$$;

revoke all on function public.navision_import_safety_assessment(jsonb,text,text,text,jsonb) from public;
grant execute on function public.navision_import_safety_assessment(jsonb,text,text,text,jsonb) to authenticated;

commit;
