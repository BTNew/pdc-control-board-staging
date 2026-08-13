-- Staging-only forward security closure 250: remove service_role EXECUTE
-- from all legacy client scheduling/move/resize RPCs.
begin;
set local lock_timeout='20s';
set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-installation',0));
do $guard$
begin
 if to_regclass('public.pdc_staging_environment_sentinel') is null
    or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
    or to_regclass('public.pdc_production_environment_sentinel') is not null
    or not exists(select 1 from supabase_migrations.schema_migrations where version='249' and name='workshop_admin_create_undo_history_order')
    or exists(select 1 from supabase_migrations.schema_migrations where version~'^[0-9]+$' and version::numeric>250)
    or exists(select 1 from supabase_migrations.schema_migrations where version='250' and name<>'revoke_service_role_legacy_workshop_rpc') then
  raise exception 'PDC_250_STAGING_OR_LEDGER_MISMATCH' using errcode='55000';
 end if;
end $guard$;

revoke all on function public.schedule_vehicle_work(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb) from public,anon,authenticated,service_role;
revoke all on function public.cascade_workshop_schedule(text,uuid,integer,text,integer,timestamptz,integer,uuid,integer,text,jsonb) from public,anon,authenticated,service_role;
revoke all on function public.move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb) from public,anon,authenticated,service_role;
revoke all on function public.resize_workshop_booking(uuid,integer,integer,jsonb) from public,anon,authenticated,service_role;
revoke all on function public.change_booking_bay(uuid,integer,integer,jsonb) from public,anon,authenticated,service_role;

do $verify$
declare n text;
begin
 foreach n in array array['schedule_vehicle_work','cascade_workshop_schedule','move_workshop_booking','resize_workshop_booking','change_booking_bay'] loop
  if exists(select 1 from pg_proc p join pg_namespace s on s.oid=p.pronamespace where s.nspname='public' and p.proname=n and (has_function_privilege('public',p.oid,'execute') or has_function_privilege('anon',p.oid,'execute') or has_function_privilege('authenticated',p.oid,'execute') or has_function_privilege('service_role',p.oid,'execute'))) then
   raise exception 'PDC_250_RPC_GRANT_VERIFY_FAILED:%',n using errcode='55000';
  end if;
 end loop;
end $verify$;

insert into supabase_migrations.schema_migrations(version,name,statements)
values('250','revoke_service_role_legacy_workshop_rpc',array['staging-only forward closure: legacy scheduling RPCs denied to public, anon, authenticated and service_role'])
on conflict(version) do update set name=excluded.name,statements=excluded.statements where supabase_migrations.schema_migrations.name=excluded.name;
commit;
