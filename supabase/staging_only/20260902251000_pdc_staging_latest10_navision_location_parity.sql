-- STAGING ONLY: restore Migration-139 pre-arrival Navision IT parity
-- for the exact latest-10 projection after the 169 location successor.
begin;
set local lock_timeout='20s';
set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-latest10-navision-location-parity-20260902',0));

do $guard$
begin
  if not public.pdc_monitor_staging_guard()
     or to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or not exists(select 1 from supabase_migrations.schema_migrations where version='20260902250000' and name='pdc_staging_latest10_navision_board_reset')
     or exists(select 1 from supabase_migrations.schema_migrations where version='20260902251000') then
    raise exception 'PDC_LATEST10_LOCATION_PARITY_STAGING_OR_DEPENDENCY_MISMATCH' using errcode='55000';
  end if;
end
$guard$;

create or replace function public.navision_operational_location(p_data jsonb)
returns text
language plpgsql stable security definer
set search_path=pg_catalog,public
as $location$
declare
  v_status text:=public.navision_exact_lifecycle_status(p_data);
  v_eta date:=public.navision_kewdale_eta(p_data);
  v_business_date date:=(statement_timestamp() at time zone 'Australia/Perth')::date;
  v_declared text:=lower(btrim(coalesce(p_data->>'navisionLocationStatus','')));
begin
  if v_status='deliveredatdealer' then return 'Completed'; end if;
  if v_status='deliveredatbodybuilder' then return 'PMB'; end if;
  if v_status in('vehicleinyardhold','inyardhold','yardhold') then return 'YH'; end if;
  if v_status=any(array['waitingpd2','vehicledelayed','awaitingtrayfit','vehiclewaitingwholesale','vehiclewaitingforwholesale'])
     and v_eta is not null and v_eta<v_business_date then return 'YH'; end if;
  if v_eta is not null and (
       v_declared='it'
       or (v_status like '%fromtwa%' and (v_status like '%despatch%' or v_status like '%dispatch%'))
       or v_status like '%intransit%'
       or v_status like '%shipment%'
       or v_status like '%wharf%'
     ) then return 'IT'; end if;
  return 'Other';
end
$location$;
revoke all on function public.navision_operational_location(jsonb) from public,anon,authenticated;
grant execute on function public.navision_operational_location(jsonb) to authenticated;
comment on function public.navision_operational_location(jsonb) is 'Staging canonical Navision location with ETA-bearing pre-arrival IT parity and progressed YH/PMB rules.';

do $repair$
declare
  v_uid uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_before jsonb;
  v_after jsonb;
  v_vehicle public.vehicles%rowtype;
  v_record public.navision_backend_records%rowtype;
  v_location text;
begin
  if v_uid is null or v_email='' or not exists(select 1 from public.pdc_user_roles where auth_user_id=v_uid and lower(email)=v_email and role::text='administrator' and active and account_status='approved') then raise exception 'PDC_LATEST10_LOCATION_PARITY_ADMIN_REQUIRED' using errcode='42501'; end if;
  select * into strict v_record from public.navision_backend_records where id='fdfe2735-658c-401b-bd20-4e98fe95e0f6'::uuid for share;
  select * into strict v_vehicle from public.vehicles where stock_number_normalized='13058808' and deleted_at is null and lifecycle_state='active' for update;
  v_location:=public.navision_operational_location(v_record.normalized_data);
  if v_location<>'IT' then raise exception 'PDC_LATEST10_LOCATION_PARITY_RULE_FAILED' using errcode='40001'; end if;
  v_before:=to_jsonb(v_vehicle);
  if v_vehicle.current_location is distinct from 'IT' then
    update public.vehicles set current_location='IT',source_payload=coalesce(source_payload,'{}'::jsonb)||jsonb_build_object('mapped_location','IT','location_rule','navision_eta_bearing_prearrival_it_parity_139'),updated_by=v_uid,updated_at=clock_timestamp(),version=version+1 where id=v_vehicle.id returning * into v_vehicle;
    v_after:=to_jsonb(v_vehicle);
    insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
    values('update','vehicles',v_vehicle.id,v_vehicle.id,v_uid,v_email,v_before,v_after,jsonb_build_object('source','pdc_staging_latest10_navision_location_parity_20260902','backend_record_id',v_record.id,'status',v_record.normalized_data->>'toyotaStatus','declared_location_status',v_record.normalized_data->>'navisionLocationStatus','eta_to_kewdale',v_record.normalized_data->>'navisionKewdaleEta','production_changed',false));
  end if;
  insert into supabase_migrations.schema_migrations(version,name,statements) values('20260902251000','pdc_staging_latest10_navision_location_parity',array['Restore ETA-bearing pre-arrival Navision IT parity from migration 139','Correct exact frozen Stock 13058808 projection']);
end
$repair$;
commit;
