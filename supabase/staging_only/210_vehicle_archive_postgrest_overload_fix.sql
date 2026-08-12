-- STAGING ONLY — remove PostgREST ambiguity between the public four-argument
-- archive RPC and its private five-argument implementation helper.
begin;
set local lock_timeout = '10s';
set local statement_timeout = '300s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-210-vehicle-archive-postgrest-overload-fix',0));

do $guard$
declare v_head bigint;v_name text;
begin
 select max(version::bigint) into v_head from supabase_migrations.schema_migrations where version~'^[0-9]+$';
 select name into v_name from supabase_migrations.schema_migrations where version='209';
 if v_head is distinct from 209 or v_name is distinct from 'vehicle_lifecycle_review_hardening' then
  raise exception 'PDC_STAGING_MIGRATION_HEAD_MISMATCH' using errcode='55000',detail=format('expected 209 vehicle_lifecycle_review_hardening; got %s %s',v_head,coalesce(v_name,'missing'));
 end if;
end $guard$;

-- A default cannot be removed in-place. Rename the private helper so PostgREST
-- sees only one pdc_admin_archive_vehicle candidate, then repoint both public
-- wrappers to the renamed implementation. The implementation remains private.
alter function public.pdc_admin_archive_vehicle(uuid,integer,text,text,text)
 rename to pdc_admin_archive_vehicle_impl;
revoke all on function public.pdc_admin_archive_vehicle_impl(uuid,integer,text,text,text) from public,anon,authenticated,service_role;

create or replace function public.pdc_admin_archive_vehicle(
 p_vehicle_id uuid,p_expected_version integer,p_confirmation_stock text,p_reason text
) returns jsonb language sql security definer set search_path=pg_catalog,public as $$
 select public.pdc_admin_archive_vehicle_impl(p_vehicle_id,p_expected_version,p_confirmation_stock,p_reason,'manual_delete')
$$;

create or replace function public.pdc_admin_reset_staging_test_vehicle(
 p_vehicle_id uuid,p_expected_version integer,p_confirmation_stock text,p_reason text
) returns jsonb language sql security definer set search_path=pg_catalog,public as $$
 select public.pdc_admin_archive_vehicle_impl(p_vehicle_id,p_expected_version,p_confirmation_stock,p_reason,'staging_reset')
$$;

revoke all on function public.pdc_admin_archive_vehicle(uuid,integer,text,text),public.pdc_admin_reset_staging_test_vehicle(uuid,integer,text,text) from public,anon,authenticated,service_role;
grant execute on function public.pdc_admin_archive_vehicle(uuid,integer,text,text),public.pdc_admin_reset_staging_test_vehicle(uuid,integer,text,text) to authenticated;

insert into supabase_migrations.schema_migrations(version,name,statements) values('210','vehicle_archive_postgrest_overload_fix',array[
 'Rename private five-argument archive helper so PostgREST resolves the public four-argument RPC unambiguously',
 'Repoint manual archive and staging-reset wrappers to the private implementation',
 'Retain strict private-helper ACL and exact migration-head guard'
]);
commit;
