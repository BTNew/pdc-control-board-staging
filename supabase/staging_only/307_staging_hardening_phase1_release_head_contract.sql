-- Staging-only migration 307: report the semantic numbered schema head.
begin;
set local lock_timeout='10s';
set local statement_timeout='60s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-installation',0));

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or (select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd') <> 1
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or to_regprocedure('public.get_pdc_staging_release_compatibility(text)') is null
     or not exists(select 1 from supabase_migrations.schema_migrations where version='306')
     or exists(select 1 from supabase_migrations.schema_migrations where version='307')
  then raise exception 'PDC_307_EXACT_STAGING_DEPENDENCY_MISMATCH' using errcode='55000'; end if;
end $guard$;

create or replace function public.get_pdc_staging_release_compatibility(p_release_contract text)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,public,supabase_migrations
as $compat$
declare
  v_head bigint;
  v_contract constant text:='pdc-control-board-staging-hardening-phase1';
begin
  if not public.pdc_monitor_staging_guard() then return public.navision_backend_response(false,'wrong_environment'); end if;
  perform public.require_pdc_role('viewer');
  -- Timestamp-form maintenance entries are not frontend schema releases.
  select max(version::bigint) into v_head
  from supabase_migrations.schema_migrations
  where version ~ '^[0-9]{1,3}$';
  if coalesce(p_release_contract,'')<>v_contract then
    return public.navision_backend_response(false,'release_contract_mismatch',jsonb_build_object('project_ref','cdsmnqxtyyoeoznmbidd','database_migration_head',v_head));
  end if;
  if coalesce(v_head,0)<307 then
    return public.navision_backend_response(false,'database_release_too_old',jsonb_build_object('project_ref','cdsmnqxtyyoeoznmbidd','database_migration_head',v_head));
  end if;
  return public.navision_backend_response(true,'compatible',jsonb_build_object(
    'project_ref','cdsmnqxtyyoeoznmbidd','database_migration_head',v_head,
    'release_contract',v_contract,'parts_completion_revision_mode','single_explicit_revision'
  ));
end;
$compat$;
revoke all on function public.get_pdc_staging_release_compatibility(text) from public,anon,authenticated,service_role;
grant execute on function public.get_pdc_staging_release_compatibility(text) to authenticated;

insert into supabase_migrations.schema_migrations(version,name,statements) values('307','staging_hardening_phase1_release_head_contract',array[
  'Report the numbered frontend schema head and exclude timestamp-form maintenance entries from compatibility attestation'
]);
commit;
