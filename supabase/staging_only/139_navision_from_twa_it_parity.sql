-- Staging-only migration 139: restore approved Navision From-TWA location parity.
-- Both Despatched and Planned For Despatch from TWA become IT only with a
-- parsed Kewdale ETA. Existing workflow progress remains authoritative.
begin;

select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-139',0));

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists (
       select 1 from public.pdc_staging_environment_sentinel
       where singleton and project_ref='cdsmnqxtyyoeoznmbidd'
     ) then
    raise exception 'PDC_STAGING_SENTINEL_MISMATCH';
  end if;
  if to_regprocedure('public.navision_kewdale_eta_from_payload(jsonb)') is null
     or to_regclass('public.navision_backend_records') is null
     or to_regclass('public.vehicles') is null
     or to_regclass('public.audit_events') is null
     or to_regclass('public.pdc_email_vehicle_revision') is null then
    raise exception 'PDC_MIGRATION_139_DEPENDENCY_MISSING';
  end if;
end;
$guard$;

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
    when value like '%FROMTWA%'
      and (value like '%DESPATCH%' or value like '%DISPATCH%')
      and public.navision_kewdale_eta_from_payload(p_data) is not null then 'IT'
    when (
      value like '%PLANNEDFORPRODUCTION%' or value like '%LINEOFFCOMPLETE%' or
      value like '%FINALINSPECTION%' or value like '%READYFORSHIPMENT%' or
      value like '%INTRANSIT%' or value like '%SHIPMENT%' or value like '%WHARF%'
    ) and public.navision_kewdale_eta_from_payload(p_data) is not null then 'IT'
    else 'Other'
  end from source;
$location$;

revoke all on function public.navision_operational_location(jsonb) from public,anon,authenticated;
grant execute on function public.navision_operational_location(jsonb) to authenticated;
comment on function public.navision_operational_location(jsonb) is
  'Staging canonical Navision location: From TWA despatch statuses and other approved pre-arrival statuses require a parsed Kewdale ETA for IT; progressed workflow locations are preserved by reconciliation.';

do $backfill$
declare
  v_row record;
  v_eta date;
  v_after jsonb;
  v_changed integer:=0;
begin
  for v_row in
    select v.id,to_jsonb(v) before_data,v.current_location,v.eta_to_kewdale,n.normalized_data
    from public.vehicles v
    join public.navision_backend_records n
      on n.id::text=btrim(coalesce(v.source_record_id,''))
    where v.lifecycle_state='active'
      and v.deleted_at is null
      and lower(regexp_replace(coalesce(v.source_system,''),'[^a-z0-9]+','','g')) in ('navision','microsoftnavision')
      and n.is_current
      and n.record_status='current'
      and upper(btrim(coalesce(v.current_location,''))) in ('IT','OTHER')
      and public.workshop_normalize_identifier(concat_ws(' ',
        coalesce(n.normalized_data->>'toyotaStatus',''),
        coalesce(n.normalized_data->>'navisionLocationStatus',''),
        coalesce(n.normalized_data->>'navisionSubLocationDescription',''),
        coalesce(n.normalized_data->>'internalStatus','')
      )) like '%FROMTWA%'
      and (
        public.workshop_normalize_identifier(concat_ws(' ',
          coalesce(n.normalized_data->>'toyotaStatus',''),
          coalesce(n.normalized_data->>'navisionLocationStatus',''),
          coalesce(n.normalized_data->>'navisionSubLocationDescription',''),
          coalesce(n.normalized_data->>'internalStatus','')
        )) like '%DESPATCH%'
        or public.workshop_normalize_identifier(concat_ws(' ',
          coalesce(n.normalized_data->>'toyotaStatus',''),
          coalesce(n.normalized_data->>'navisionLocationStatus',''),
          coalesce(n.normalized_data->>'navisionSubLocationDescription',''),
          coalesce(n.normalized_data->>'internalStatus','')
        )) like '%DISPATCH%'
      )
    order by v.id
    for update of v
  loop
    v_eta:=public.navision_kewdale_eta_from_payload(v_row.normalized_data);
    if v_eta is not null
       and public.navision_operational_location(v_row.normalized_data)='IT'
       and (v_row.eta_to_kewdale is distinct from v_eta
         or upper(btrim(coalesce(v_row.current_location,'')))<>'IT') then
      update public.vehicles
      set eta_to_kewdale=v_eta,current_location='IT',version=version+1
      where id=v_row.id
      returning to_jsonb(public.vehicles.*) into v_after;

      insert into public.audit_events(action,table_name,row_id,vehicle_id,before_data,after_data,metadata)
      values('update','vehicles',v_row.id,v_row.id,v_row.before_data,v_after,
        jsonb_build_object(
          'source','navision_from_twa_it_parity_139',
          'reason','Approved From TWA despatch status with Kewdale ETA maps to IT',
          'previous_location',v_row.current_location,
          'eta_to_kewdale',v_eta
        ));
      v_changed:=v_changed+1;
    end if;
  end loop;

  if v_changed>0 then
    update public.pdc_email_vehicle_revision
    set revision=revision+1,updated_at=clock_timestamp()
    where singleton;
  end if;

  raise notice 'PDC migration 139 changed % From-TWA vehicles',v_changed;
end;
$backfill$;

commit;
