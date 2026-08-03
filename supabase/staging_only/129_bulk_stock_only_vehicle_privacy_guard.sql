-- Staging-only migration 129: keep stock-workbook cards free of customer/key data.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';

do $$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
     or to_regclass('public.pdc_production_environment_sentinel') is not null then
    raise exception using errcode='P0001',message='PDC_BULK_129_STAGING_SENTINEL_MISMATCH';
  end if;
  if not exists(select 1 from supabase_migrations.schema_migrations where version='128' and name='stock_only_stage_mapped_workbook_import') then
    raise exception using errcode='P0001',message='migration_128_required';
  end if;
  if exists(select 1 from supabase_migrations.schema_migrations where version='129') then
    raise exception using errcode='P0001',message='migration_129_version_conflict';
  end if;
end $$;

create or replace function public.enforce_pdc_bulk_stock_only_vehicle_privacy()
returns trigger language plpgsql security invoker set search_path=pg_catalog,public as $$
begin
  if new.source_payload ? 'bulk_preview_id' then
    new.customer_name:=null;
    new.key_number:=null;
  end if;
  return new;
end $$;

revoke all on function public.enforce_pdc_bulk_stock_only_vehicle_privacy() from public,anon,authenticated,service_role;

drop trigger if exists vehicles_pdc_bulk_stock_only_privacy_guard on public.vehicles;
create trigger vehicles_pdc_bulk_stock_only_privacy_guard
before insert or update of customer_name,key_number,source_payload on public.vehicles
for each row execute function public.enforce_pdc_bulk_stock_only_vehicle_privacy();

update public.vehicles
set customer_name=null,
    key_number=null,
    version=version+1,
    updated_at=clock_timestamp(),
    source_payload=source_payload || jsonb_build_object('stock_only_identity_sanitized',true)
where source_payload ? 'bulk_preview_id'
  and (customer_name is not null or key_number is not null);

insert into supabase_migrations.schema_migrations(version,name,statements)
values('129','bulk_stock_only_vehicle_privacy_guard',array['staging-only stock-workbook privacy guard and one-time sanitization']);

comment on function public.enforce_pdc_bulk_stock_only_vehicle_privacy() is 'Prevents stock-workbook imports from persisting customer names or physical key numbers; stock and authorised operational planning fields remain.';

commit;
