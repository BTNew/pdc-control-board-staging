-- Staging-only migration 089: Toyota Navision rows require a real Kewdale ETA before IT.
-- Missing/invalid ETA keeps pre-workflow vehicles in Other. A later authoritative
-- Navision refresh with an ETA moves a transit-status row into IT automatically.
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
  if to_regclass('public.navision_backend_records') is null
     or to_regclass('public.vehicles') is null
     or to_regclass('public.audit_events') is null
     or to_regclass('public.pdc_email_vehicle_revision') is null then
    raise exception 'PDC_MIGRATION_089_DEPENDENCY_MISSING';
  end if;
end;
$guard$;

create or replace function public.navision_kewdale_eta_from_payload(p_data jsonb)
returns date
language plpgsql
immutable
parallel safe
set search_path=pg_catalog,public
as $eta$
declare
  v_text text:=nullif(btrim(coalesce(
    p_data->>'navisionKewdaleEta',
    p_data->>'etaAtKewdale',
    p_data->>'etaAtDealer',
    ''
  )), '');
  v_date date;
begin
  if v_text is null then return null; end if;
  begin
    if v_text ~ '^\d{4}-\d{2}-\d{2}(?:[T ].*)?$' then
      v_text:=substr(v_text,1,10);
      v_date:=make_date(substr(v_text,1,4)::integer,substr(v_text,6,2)::integer,substr(v_text,9,2)::integer);
      return v_date;
    end if;
    if v_text ~ '^\d{1,2}[/-]\d{1,2}[/-]\d{4}$' then
      v_text:=replace(v_text,'-','/');
      v_date:=make_date(split_part(v_text,'/',3)::integer,split_part(v_text,'/',2)::integer,split_part(v_text,'/',1)::integer);
      return v_date;
    end if;
  exception when others then
    return null;
  end;
  return null;
end;
$eta$;

revoke all on function public.navision_kewdale_eta_from_payload(jsonb) from public,anon,authenticated;
grant execute on function public.navision_kewdale_eta_from_payload(jsonb) to authenticated;

create or replace function public.navision_operational_location(p_data jsonb)
returns text
language sql
immutable
parallel safe
set search_path=pg_catalog,public
as $location$
  with source as (
    select public.workshop_normalize_identifier(concat_ws(' ',
      coalesce(p_data->>'toyotaStatus',''),
      coalesce(p_data->>'navisionLocationStatus',''),
      coalesce(p_data->>'navisionSubLocationDescription',''),
      coalesce(p_data->>'internalStatus','')
    )) as value
  )
  select case
    when value like '%ATDEALER%' or value like '%DELIVEREDTODEALER%' then 'Completed'
    when value like '%BODYBUILDER%' or value like '%PERTHMOTORBODIES%' or value like '%PMB%' then 'PMB'
    when value like '%YARDHOLD%' or value='YH' then 'YH'
    when value like '%INTRANSIT%'
      and public.navision_kewdale_eta_from_payload(p_data) is not null then 'IT'
    when (value like '%SHIPMENT%' or value like '%WHARF%')
      and public.navision_kewdale_eta_from_payload(p_data) is not null then 'IT'
    else 'Other'
  end from source;
$location$;

revoke all on function public.navision_operational_location(jsonb) from public,anon,authenticated;
grant execute on function public.navision_operational_location(jsonb) to authenticated;

create or replace function public.enforce_toyota_navision_it_eta()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public
as $enforce$
declare
  v_data jsonb;
  v_record_found boolean:=false;
begin
  if lower(regexp_replace(coalesce(new.source_system,''),'[^a-z0-9]+','','g')) not in ('navision','microsoftnavision') then
    return new;
  end if;

  if nullif(btrim(coalesce(new.source_record_id,'')),'') is not null then
    select n.normalized_data,true into v_data,v_record_found
    from public.navision_backend_records n
    where n.id::text=btrim(new.source_record_id)
      and n.is_current
      and n.record_status='current'
    limit 1;
  end if;

  if v_record_found then
    -- The current Navision snapshot is authoritative, including a newly blank ETA.
    new.eta_to_kewdale:=public.navision_kewdale_eta_from_payload(v_data);
  end if;

  if upper(btrim(coalesce(new.current_location,'')))='IT'
     and new.eta_to_kewdale is null then
    new.current_location:='Other';
  end if;
  return new;
end;
$enforce$;

revoke all on function public.enforce_toyota_navision_it_eta() from public,anon,authenticated;
drop trigger if exists vehicles_toyota_navision_it_eta_gate on public.vehicles;
create trigger vehicles_toyota_navision_it_eta_gate
before insert or update of current_location,eta_to_kewdale,source_system,source_record_id
on public.vehicles
for each row execute function public.enforce_toyota_navision_it_eta();

do $backfill$
declare
  v_row record;
  v_eta date;
  v_derived text;
  v_target_location text;
  v_after jsonb;
  v_changed integer:=0;
begin
  for v_row in
    select v.id,to_jsonb(v) as before_data,v.current_location,v.eta_to_kewdale,n.normalized_data
    from public.vehicles v
    join public.navision_backend_records n on n.id::text=btrim(coalesce(v.source_record_id,''))
    where v.lifecycle_state='active'
      and v.deleted_at is null
      and lower(regexp_replace(coalesce(v.source_system,''),'[^a-z0-9]+','','g')) in ('navision','microsoftnavision')
      and n.is_current and n.record_status='current'
      and upper(btrim(coalesce(v.current_location,''))) in ('IT','OTHER')
    order by v.id
    for update of v
  loop
    v_eta:=public.navision_kewdale_eta_from_payload(v_row.normalized_data);
    v_derived:=public.navision_operational_location(v_row.normalized_data);
    v_target_location:=case
      when v_derived='IT' then 'IT'
      when upper(btrim(coalesce(v_row.current_location,'')))='IT' and v_eta is null then 'Other'
      else v_row.current_location
    end;
    if v_row.eta_to_kewdale is distinct from v_eta
       or v_row.current_location is distinct from v_target_location then
      update public.vehicles
      set eta_to_kewdale=v_eta,current_location=v_target_location,version=version+1
      where id=v_row.id
      returning to_jsonb(public.vehicles.*) into v_after;
      insert into public.audit_events(action,table_name,row_id,vehicle_id,before_data,after_data,metadata)
      values('update','vehicles',v_row.id,v_row.id,v_row.before_data,v_after,
        jsonb_build_object('source','toyota_navision_it_eta_gate_089','reason','Kewdale ETA controls Navision IT classification'));
      v_changed:=v_changed+1;
    end if;
  end loop;
  if v_changed>0 then
    update public.pdc_email_vehicle_revision
    set revision=revision+1,updated_at=clock_timestamp()
    where singleton;
  end if;
end;
$backfill$;

commit;
