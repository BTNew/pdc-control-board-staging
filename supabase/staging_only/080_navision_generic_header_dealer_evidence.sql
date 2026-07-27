-- Staging-only migration 080.
-- Preserve exact Dealer-header authority, but recover safely when pasted report
-- rows retain the original dealer value/name under a generic positional header.
begin;

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd') then
    raise exception 'PDC_STAGING_SENTINEL_MISMATCH';
  end if;
end
$guard$;

create or replace function public.navision_row_declared_dealer_code(p_row jsonb)
returns text
language sql
immutable
set search_path='pg_catalog','public'
as $function$
  with columns as materialized(
    select
      regexp_replace(lower(btrim(coalesce(c.value->>'header',''))),'[^a-z0-9]+','','g') header_key,
      btrim(coalesce(nullif(c.value->>'value',''),c.value->>'rawValue','')) source_value
    from jsonb_array_elements(
      case
        when jsonb_typeof(p_row #> '{navisionRawEvidence,columns}')='array'
          then p_row #> '{navisionRawEvidence,columns}'
        when jsonb_typeof(p_row #> '{raw_evidence,columns}')='array'
          then p_row #> '{raw_evidence,columns}'
        else '[]'::jsonb
      end
    ) c(value)
  ), exact_header as(
    select nullif(regexp_replace(source_value,'^0+',''),'') code
    from columns
    where header_key in ('dealer','dealercode','dealerno','dealernumber')
    limit 1
  ), fallback_candidates as(
    select distinct case
      when regexp_replace(source_value,'^0+','') in ('14450','37047')
        then regexp_replace(source_value,'^0+','')
      when upper(regexp_replace(source_value,'[^A-Za-z]+',' ','g')) like '%PILBARA TOYOTA%'
        then '14450'
      when upper(regexp_replace(source_value,'[^A-Za-z]+',' ','g')) like '%BROOME TOYOTA%'
        then '37047'
      else null
    end code
    from columns
  ), unique_fallback as(
    select min(code) code
    from fallback_candidates
    where code is not null
    having count(distinct code)=1
  )
  select case
    when exists(select 1 from columns where header_key in ('dealer','dealercode','dealerno','dealernumber'))
      then (select code from exact_header)
    else (select code from unique_fallback)
  end;
$function$;

revoke all on function public.navision_row_declared_dealer_code(jsonb) from public;

commit;
