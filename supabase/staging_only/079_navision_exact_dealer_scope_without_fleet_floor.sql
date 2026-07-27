-- Staging-only migration 079.
-- Accept a genuine full dealer extract even when that dealer has fewer than 100
-- vehicles. Authority comes from every original Dealer column matching the
-- selected scope, not from an arbitrary fleet-size threshold.
begin;

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd') then
    raise exception 'PDC_STAGING_SENTINEL_MISMATCH';
  end if;
end
$guard$;

alter table public.navision_initial_scope_approvals
  drop constraint if exists navision_initial_scope_approvals_row_count_check;
alter table public.navision_initial_scope_approvals
  add constraint navision_initial_scope_approvals_row_count_check check(row_count>0);

create or replace function public.approve_navision_initial_scope(
  p_rows jsonb,p_source_system text,p_dealer_code text
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public,extensions
as $approve$
declare
  v_user uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_role text:=public.current_pdc_user_role()::text;
  v_source_system text:=lower(btrim(coalesce(p_source_system,'')));
  v_dealer_code text:=regexp_replace(btrim(coalesce(p_dealer_code,'')),'^0+','');
  v_total integer:=0;
  v_valid integer:=0;
  v_current integer:=0;
  v_cross integer:=0;
  v_hash text;
begin
  if not public.pdc_monitor_staging_guard() then
    return public.navision_backend_response(false,'wrong_environment');
  end if;
  if v_user is null or v_email='' or v_role<>'administrator' then
    return public.navision_backend_response(false,'administrator_required');
  end if;
  if v_source_system<>'microsoft_navision'
     or v_dealer_code not in ('14450','37047')
     or jsonb_typeof(p_rows) is distinct from 'array' then
    return public.navision_backend_response(false,'invalid_scope_or_rows');
  end if;

  v_total:=jsonb_array_length(p_rows);
  if v_total<1 then
    return public.navision_backend_response(false,'initial_scope_requires_nonempty_snapshot',jsonb_build_object('received_rows',v_total));
  end if;

  select count(*)::integer into v_valid
  from jsonb_array_elements(p_rows) e(value)
  where jsonb_typeof(e.value)='object'
    and not public.navision_backend_row_has_forbidden_fields(e.value)
    and public.navision_backend_source_record_id(e.value) is not null
    and public.navision_row_declared_dealer_code(e.value)=v_dealer_code;
  if v_valid<>v_total then
    return public.navision_backend_response(false,'initial_scope_rows_invalid_or_wrong_dealer',jsonb_build_object('valid_selected_rows',v_valid,'received_rows',v_total));
  end if;

  select count(*)::integer into v_current
  from public.navision_backend_records r
  where r.source_system=v_source_system and r.dealer_code=v_dealer_code
    and r.is_current and r.record_status='current';
  if v_current<>0 then
    return public.navision_backend_response(false,'dealer_scope_already_established',jsonb_build_object('current_rows',v_current));
  end if;

  with incoming as materialized(
    select distinct public.navision_backend_source_record_id(e.value) source_record_id_normalized
    from jsonb_array_elements(p_rows)e(value)
  )
  select count(distinct i.source_record_id_normalized)::integer into v_cross
  from incoming i join public.navision_backend_records r
    on r.source_system=v_source_system
   and r.source_record_id_normalized=i.source_record_id_normalized
   and r.dealer_code<>v_dealer_code
   and r.dealer_code<>'LEGACY_UNSCOPED';
  if v_cross>0 then
    return public.navision_backend_response(false,'cross_dealer_identity_overlap',jsonb_build_object('cross_dealer_matches',v_cross));
  end if;

  v_hash:=encode(digest(convert_to(p_rows::text,'UTF8'),'sha256'),'hex');
  insert into public.navision_initial_scope_approvals(
    dealer_code,source_system,rows_hash,row_count,approved_by,approved_email,approved_at,expires_at
  ) values(
    v_dealer_code,v_source_system,v_hash,v_total,v_user,v_email,clock_timestamp(),clock_timestamp()+interval '2 hours'
  ) on conflict(dealer_code) do update set
    source_system=excluded.source_system,rows_hash=excluded.rows_hash,row_count=excluded.row_count,
    approved_by=excluded.approved_by,approved_email=excluded.approved_email,
    approved_at=excluded.approved_at,expires_at=excluded.expires_at;

  return public.navision_backend_response(true,'initial_scope_approved',jsonb_build_object(
    'dealer_code',v_dealer_code,'rows_hash',v_hash,'row_count',v_total,'expires_at',clock_timestamp()+interval '2 hours',
    'authority','navision_original_dealer_column_v2'
  ));
end
$approve$;
revoke all on function public.approve_navision_initial_scope(jsonb,text,text) from public,anon;
grant execute on function public.approve_navision_initial_scope(jsonb,text,text) to authenticated;

do $rename$
begin
  if to_regprocedure('public.navision_import_safety_assessment_pre079(jsonb,text,text,text,jsonb)') is null then
    alter function public.navision_import_safety_assessment(jsonb,text,text,text,jsonb)
      rename to navision_import_safety_assessment_pre079;
  end if;
end
$rename$;

create or replace function public.navision_import_safety_assessment(
  p_rows jsonb,p_source_system text,p_dealer_code text,p_source_name text,p_preview_data jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,public,extensions
as $safety$
declare
  v_result jsonb;
  v_reason text;
  v_selected text:=regexp_replace(btrim(coalesce(p_dealer_code,'')),'^0+','');
  v_incoming integer:=0;
  v_valid_rows integer:=0;
  v_declared_selected integer:=0;
begin
  v_result:=public.navision_import_safety_assessment_pre079(p_rows,p_source_system,p_dealer_code,p_source_name,p_preview_data);
  v_reason:=coalesce(v_result->>'reason','');
  v_incoming:=coalesce((v_result->>'incoming_valid_count')::integer,0);

  if v_reason='cross_dealer_identity_overlap'
     and lower(btrim(coalesce(p_source_system,'')))='microsoft_navision'
     and v_selected in ('14450','37047')
     and v_incoming>0
     and jsonb_typeof(p_rows)='array' then
    with valid_rows as materialized(
      select public.navision_row_declared_dealer_code(e.value) declared_dealer
      from jsonb_array_elements(p_rows)e(value)
      where jsonb_typeof(e.value)='object'
        and not public.navision_backend_row_has_forbidden_fields(e.value)
        and public.navision_backend_source_record_id(e.value) is not null
    )
    select count(*)::integer,count(*) filter(where declared_dealer=v_selected)::integer
      into v_valid_rows,v_declared_selected from valid_rows;

    if v_valid_rows=v_incoming and v_declared_selected=v_incoming then
      v_result:=jsonb_set(v_result,'{blocking}','false'::jsonb,true);
      v_result:=jsonb_set(v_result,'{reason}','null'::jsonb,true);
      v_result:=jsonb_set(v_result,'{authority}',to_jsonb('navision_original_dealer_column_v2'::text),true);
      v_result:=jsonb_set(v_result,'{declared_dealer_release}',jsonb_build_object(
        'released',true,'selected_dealer_code',v_selected,'valid_rows',v_valid_rows,
        'declared_selected_rows',v_declared_selected,'minimum_incoming',1,'hard_delete',false
      ),true);
    end if;
  end if;
  return v_result;
end
$safety$;
revoke all on function public.navision_import_safety_assessment(jsonb,text,text,text,jsonb) from public;
grant execute on function public.navision_import_safety_assessment(jsonb,text,text,text,jsonb) to authenticated;

create or replace function public.navision_scope_rows_for_selected_dealer(
  p_rows jsonb,p_source_system text,p_dealer_code text
)
returns jsonb
language plpgsql
stable
security definer
set search_path='pg_catalog','public','extensions'
as $scope$
declare
  v_selected text:=regexp_replace(btrim(coalesce(p_dealer_code,'')),'^0+','');
  v_total integer:=0;v_valid integer:=0;v_known integer:=0;v_selected_count integer:=0;v_other_count integer:=0;
  v_rows jsonb:='[]'::jsonb;
begin
  if jsonb_typeof(p_rows)<>'array' or lower(btrim(coalesce(p_source_system,'')))<>'microsoft_navision'
     or v_selected not in ('14450','37047') then
    return jsonb_build_object('applied',false,'rows',p_rows,'reason','not_eligible_scope');
  end if;
  v_total:=jsonb_array_length(p_rows);
  with source_rows as materialized(
    select e.ordinality,e.value,public.navision_row_declared_dealer_code(e.value) declared_dealer,
      (jsonb_typeof(e.value)='object' and not public.navision_backend_row_has_forbidden_fields(e.value)
       and public.navision_backend_source_record_id(e.value) is not null) valid
    from jsonb_array_elements(p_rows)with ordinality e(value,ordinality)
  )
  select count(*) filter(where valid)::integer,
    count(*) filter(where valid and declared_dealer in ('14450','37047'))::integer,
    count(*) filter(where valid and declared_dealer=v_selected)::integer,
    count(*) filter(where valid and declared_dealer in ('14450','37047') and declared_dealer<>v_selected)::integer,
    coalesce(jsonb_agg(value order by ordinality) filter(where valid and declared_dealer=v_selected),'[]'::jsonb)
  into v_valid,v_known,v_selected_count,v_other_count,v_rows from source_rows;

  if v_total=v_valid and v_valid=v_known and v_selected_count>0 and v_other_count>0 then
    return jsonb_build_object('applied',true,'rows',v_rows,'selected_dealer_code',v_selected,
      'source_rows',v_total,'selected_rows',v_selected_count,'ignored_other_dealer_rows',v_other_count,
      'authority','navision_original_dealer_column_v2');
  end if;
  return jsonb_build_object('applied',false,'rows',p_rows,'selected_dealer_code',v_selected,
    'source_rows',v_total,'valid_rows',v_valid,'known_dealer_rows',v_known,'selected_rows',v_selected_count,
    'other_dealer_rows',v_other_count,'reason','mixed_report_not_safely_scopeable');
end
$scope$;
revoke all on function public.navision_scope_rows_for_selected_dealer(jsonb,text,text) from public;

commit;
