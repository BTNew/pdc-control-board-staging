-- Staging-only forward correction 247: fail closed when no qualifying
-- approved Administrator account row exists.
begin;
set local lock_timeout='20s';
set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-installation',0));
do $guard$
begin
 if to_regclass('public.pdc_staging_environment_sentinel') is null
    or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
    or to_regclass('public.pdc_production_environment_sentinel') is not null
    or not exists(select 1 from supabase_migrations.schema_migrations where version='246' and name='workshop_admin_intent_hash_schema')
    or exists(select 1 from supabase_migrations.schema_migrations where version~'^[0-9]+$' and version::numeric>247)
    or exists(select 1 from supabase_migrations.schema_migrations where version='247' and name<>'workshop_admin_null_role_fail_closed') then
   raise exception 'PDC_247_STAGING_OR_LEDGER_MISMATCH' using errcode='55000';
 end if;
end $guard$;

create or replace function public.workshop_require_website_administrator_238()
returns void language plpgsql stable security definer set search_path='pg_catalog','public' as $fn$
declare v_role text; v_email text;
begin
  if auth.uid() is null or session_user<>'authenticator' then raise exception 'PDC_244_WEBSITE_AUTH_REQUIRED' using errcode='42501'; end if;
  select lower(role::text),lower(email) into v_role,v_email from public.pdc_user_roles
  where auth_user_id=auth.uid() and active and approved_at is not null and disabled_at is null and account_status::text='approved';
  if v_role is distinct from 'administrator' then raise exception 'PDC_244_ADMINISTRATOR_REQUIRED' using errcode='42501'; end if;
  if coalesce(v_email,'')~'(monitor|auditor|viewer|bot|service|import)' then
    raise exception 'PDC_244_NON_HUMAN_IDENTITY_DENIED' using errcode='42501';
  end if;
  if exists(select 1 from public.pdc_auditor_executor_identities x where x.auth_user_id=auth.uid() and x.active and x.disabled_at is null)
     or exists(select 1 from public.pdc_auditor_service_identities_225 x where x.auth_user_id=auth.uid() and x.active and x.revoked_at is null)
     or exists(select 1 from public.pdc_auditor_worker_identities x where x.auth_user_id=auth.uid() and x.active)
     or exists(select 1 from public.pdc_monitor_stage_activation_writers x where x.user_id=auth.uid() and x.active and x.revoked_at is null)
     or exists(select 1 from public.pdc_monitor_vehicle_identity_readers x where x.user_id=auth.uid() and x.active and x.revoked_at is null) then
    raise exception 'PDC_244_NON_HUMAN_IDENTITY_DENIED' using errcode='42501';
  end if;
end;
$fn$;
revoke all on function public.workshop_require_website_administrator_238() from public,anon,authenticated,service_role;

insert into supabase_migrations.schema_migrations(version,name,statements)
values('247','workshop_admin_null_role_fail_closed',array['staging-only forward correction: missing or unapproved Administrator rows fail closed with IS DISTINCT FROM'])
on conflict(version) do update set name=excluded.name,statements=excluded.statements
where supabase_migrations.schema_migrations.name=excluded.name;
do $verify$
begin
 if not exists(select 1 from supabase_migrations.schema_migrations where version='247' and name='workshop_admin_null_role_fail_closed') then raise exception 'PDC_247_LEDGER_VERIFY_FAILED'; end if;
 if position('IS DISTINCT FROM' in upper(pg_get_functiondef('public.workshop_require_website_administrator_238()'::regprocedure)))=0 then raise exception 'PDC_247_GUARD_VERIFY_FAILED'; end if;
end $verify$;
commit;
