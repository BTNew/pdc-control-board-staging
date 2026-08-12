-- Staging-only migration 207: permit the Administrator authority helper to take its auth-bound row lock.
begin;
set local lock_timeout='10s';
set local statement_timeout='300s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-207-admin-actor-volatility',0));
do $guard$
begin
 if not public.pdc_monitor_staging_guard()
    or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
    or to_regclass('public.pdc_production_environment_sentinel') is not null
    or not exists(select 1 from supabase_migrations.schema_migrations where version='206' and name='recoverable_archive_booking_history_identity')
    or exists(select 1 from supabase_migrations.schema_migrations where version='207') then
  raise exception 'PDC_207_STAGING_OR_LEDGER_MISMATCH' using errcode='55000',detail='wrong_environment_or_predecessor';
 end if;
end $guard$;

create or replace function public.pdc_admin_vehicle_actor()
returns jsonb language plpgsql volatile security definer set search_path=pg_catalog,public as $$
declare v_uid uuid:=auth.uid();v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));v_role text;
begin
 if not public.pdc_monitor_staging_guard() then return public.navision_backend_response(false,'wrong_environment'); end if;
 if v_uid is null or v_email='' then return public.navision_backend_response(false,'administrator_required'); end if;
 select r.role::text into v_role from public.pdc_user_roles r
 where r.auth_user_id=v_uid and lower(r.email)=v_email and r.active and r.account_status='approved' for share;
 if v_role is distinct from 'administrator' then return public.navision_backend_response(false,'administrator_required'); end if;
 return public.navision_backend_response(true,'administrator',jsonb_build_object('actor_id',v_uid,'actor_email',v_email));
end $$;
revoke all on function public.pdc_admin_vehicle_actor() from public,anon,authenticated,service_role;

insert into supabase_migrations.schema_migrations(version,name,statements) values('207','admin_vehicle_actor_lock_volatility',array[
 'Declare the auth-bound Administrator authority helper VOLATILE so its FOR SHARE role lock is legal'
]);
commit;
