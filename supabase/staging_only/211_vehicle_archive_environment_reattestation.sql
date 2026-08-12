-- STAGING ONLY — independently attest the migration-210 archive RPC shape and
-- ACL state inside the exact PDC staging environment. Migration 210 is already
-- applied and remains immutable; this append-only migration fails closed before
-- re-attesting its intended security state.
begin;
set local lock_timeout = '10s';
set local statement_timeout = '300s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-211-vehicle-archive-environment-reattestation',0));

do $guard$
declare v_head text;v_name text;
begin
 select version,name into v_head,v_name
 from supabase_migrations.schema_migrations
 where version ~ '^[0-9]+$'
 order by version::bigint desc limit 1;
 if not public.pdc_monitor_staging_guard()
    or to_regclass('public.pdc_staging_environment_sentinel') is null
    or not exists(
      select 1 from public.pdc_staging_environment_sentinel
      where singleton and project_ref='cdsmnqxtyyoeoznmbidd'
    )
    or to_regclass('public.pdc_production_environment_sentinel') is not null
    or v_head is distinct from '210'
    or v_name is distinct from 'vehicle_archive_postgrest_overload_fix'
    or exists(select 1 from supabase_migrations.schema_migrations where version='211') then
  raise exception 'PDC_211_STAGING_OR_LEDGER_MISMATCH'
    using errcode='55000',detail='wrong_environment_or_exact_head';
 end if;
end
$guard$;

-- Fail closed if migration 210 did not leave exactly one public archive name
-- and one separately named private implementation helper.
do $shape$
begin
 if to_regprocedure('public.pdc_admin_archive_vehicle(uuid,integer,text,text)') is null
    or to_regprocedure('public.pdc_admin_archive_vehicle_impl(uuid,integer,text,text,text)') is null
    or to_regprocedure('public.pdc_admin_reset_staging_test_vehicle(uuid,integer,text,text)') is null
    or (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
        where n.nspname='public' and p.proname='pdc_admin_archive_vehicle') <> 1 then
  raise exception 'PDC_211_ARCHIVE_RPC_SHAPE_MISMATCH'
    using errcode='55000',detail='archive_rpc_shape_not_210';
 end if;
end
$shape$;

-- Re-attest the security boundary after the independently staging-bound guards.
revoke all on function public.pdc_admin_archive_vehicle_impl(uuid,integer,text,text,text)
 from public,anon,authenticated,service_role;
revoke all on function public.pdc_admin_archive_vehicle(uuid,integer,text,text),
 public.pdc_admin_reset_staging_test_vehicle(uuid,integer,text,text)
 from public,anon,authenticated,service_role;
grant execute on function public.pdc_admin_archive_vehicle(uuid,integer,text,text),
 public.pdc_admin_reset_staging_test_vehicle(uuid,integer,text,text)
 to authenticated;

-- Keep every retired destructive lifecycle bypass closed.
revoke all on function public.mark_vehicle_deleted(uuid,integer,text),
 public.restore_vehicle(uuid,integer,text),
 public.purge_vehicle_from_board(uuid,integer,text),
 public.purge_all_staging_board_vehicles(text,text)
 from public,anon,authenticated,service_role;

insert into supabase_migrations.schema_migrations(version,name,statements)
values('211','vehicle_archive_environment_reattestation',array[
 'Independently require the exact PDC staging guard, staging project sentinel, and absence of the production sentinel',
 'Require exact migration 210 ledger head and unambiguous archive/reset RPC shape',
 'Re-attest private-helper, public-wrapper, and retired lifecycle RPC ACL boundaries'
]);
commit;
