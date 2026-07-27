-- Staging-only migration 074.
-- Permit an administrator to approve one exact first full dealer snapshot when
-- the selected dealer has no established Navision baseline. The approval is
-- user-bound, content-bound and expires; all ordinary row/conflict checks remain.
begin;

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists (
       select 1 from public.pdc_staging_environment_sentinel
       where singleton and project_ref='cdsmnqxtyyoeoznmbidd'
     ) then
    raise exception 'PDC_STAGING_SENTINEL_MISMATCH';
  end if;
end;
$guard$;

create table if not exists public.navision_initial_scope_approvals (
  dealer_code text primary key check(dealer_code in ('14450','37047')),
  source_system text not null check(source_system='microsoft_navision'),
  rows_hash text not null check(rows_hash ~ '^[0-9a-f]{64}$'),
  row_count integer not null check(row_count>=100),
  approved_by uuid not null references auth.users(id) on delete restrict,
  approved_email text not null,
  approved_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null
);
alter table public.navision_initial_scope_approvals enable row level security;
revoke all on table public.navision_initial_scope_approvals from public,anon,authenticated;

create or replace function public.approve_navision_initial_scope(
  p_rows jsonb,
  p_source_system text,
  p_dealer_code text
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
  v_dealer_code text:=btrim(coalesce(p_dealer_code,''));
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
  if v_total<100 then
    return public.navision_backend_response(false,'initial_scope_requires_full_snapshot',jsonb_build_object('minimum_rows',100,'received_rows',v_total));
  end if;

  select count(*)::integer into v_valid
  from jsonb_array_elements(p_rows) e(value)
  where jsonb_typeof(e.value)='object'
    and not public.navision_backend_row_has_forbidden_fields(e.value)
    and public.navision_backend_source_record_id(e.value) is not null;
  if v_valid<>v_total then
    return public.navision_backend_response(false,'initial_scope_rows_invalid',jsonb_build_object('valid_rows',v_valid,'received_rows',v_total));
  end if;

  select count(*)::integer into v_current
  from public.navision_backend_records r
  where r.source_system=v_source_system and r.dealer_code=v_dealer_code
    and r.is_current and r.record_status='current';
  if v_current<>0 then
    return public.navision_backend_response(false,'dealer_scope_already_established',jsonb_build_object('current_rows',v_current));
  end if;

  with incoming as materialized (
    select distinct public.normalize_vehicle_source_identifier(
      public.navision_backend_source_record_id(e.value)
    ) as source_record_id_normalized
    from jsonb_array_elements(p_rows) e(value)
  )
  select count(distinct i.source_record_id_normalized)::integer into v_cross
  from incoming i
  join public.navision_backend_records r
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
  ) values (
    v_dealer_code,v_source_system,v_hash,v_total,v_user,v_email,clock_timestamp(),clock_timestamp()+interval '2 hours'
  )
  on conflict(dealer_code) do update set
    source_system=excluded.source_system,
    rows_hash=excluded.rows_hash,
    row_count=excluded.row_count,
    approved_by=excluded.approved_by,
    approved_email=excluded.approved_email,
    approved_at=excluded.approved_at,
    expires_at=excluded.expires_at;

  return public.navision_backend_response(true,'initial_scope_approved',jsonb_build_object(
    'dealer_code',v_dealer_code,'rows_hash',v_hash,'row_count',v_total,'expires_at',clock_timestamp()+interval '2 hours'
  ));
end;
$approve$;
revoke all on function public.approve_navision_initial_scope(jsonb,text,text) from public,anon;
grant execute on function public.approve_navision_initial_scope(jsonb,text,text) to authenticated;

do $rename$
begin
  if to_regprocedure('public.navision_import_safety_assessment_pre074(jsonb,text,text,text,jsonb)') is null then
    alter function public.navision_import_safety_assessment(jsonb,text,text,text,jsonb)
      rename to navision_import_safety_assessment_pre074;
  end if;
end;
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
set search_path=pg_catalog,public,extensions
as $safety$
declare
  v_result jsonb;
  v_reason text;
  v_hash text;
  v_user uuid:=auth.uid();
begin
  v_result:=public.navision_import_safety_assessment_pre074(
    p_rows,p_source_system,p_dealer_code,p_source_name,p_preview_data
  );
  v_reason:=coalesce(v_result->>'reason','');

  if v_reason='unproven_empty_dealer_scope'
     and v_user is not null
     and jsonb_typeof(p_rows)='array' then
    v_hash:=encode(digest(convert_to(p_rows::text,'UTF8'),'sha256'),'hex');
    if exists(
      select 1 from public.navision_initial_scope_approvals a
      where a.dealer_code=btrim(coalesce(p_dealer_code,''))
        and a.source_system=lower(btrim(coalesce(p_source_system,'')))
        and a.rows_hash=v_hash
        and a.row_count=jsonb_array_length(p_rows)
        and a.approved_by=v_user
        and a.expires_at>clock_timestamp()
    ) then
      v_result:=jsonb_set(v_result,'{blocking}','false'::jsonb,true);
      v_result:=jsonb_set(v_result,'{reason}','null'::jsonb,true);
      v_result:=jsonb_set(v_result,'{authority}',to_jsonb('navision_initial_scope_exact_review_v1'::text),true);
      v_result:=jsonb_set(v_result,'{initial_scope_review}',jsonb_build_object(
        'approved',true,'content_bound',true,'user_bound',true,'expires',true
      ),true);
    end if;
  end if;
  return v_result;
end;
$safety$;
revoke all on function public.navision_import_safety_assessment(jsonb,text,text,text,jsonb)
  from public,anon,authenticated;

commit;
