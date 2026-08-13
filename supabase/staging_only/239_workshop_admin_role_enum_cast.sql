-- Staging-only migration 239: cast pdc_role enum before case-normalising.
begin;
set local lock_timeout='20s';
set local statement_timeout='120s';

create or replace function public.workshop_require_website_administrator_238()
returns void language plpgsql stable security definer
set search_path='pg_catalog','public'
as $fn$
declare v_role text; v_email text;
begin
  if auth.uid() is null or session_user<>'authenticator' then
    raise exception 'PDC_238_WEBSITE_AUTH_REQUIRED' using errcode='42501';
  end if;
  select lower(role::text),lower(email) into v_role,v_email
  from public.pdc_user_roles
  where auth_user_id=auth.uid() and active and approved_at is not null and revoked_at is null;
  if v_role<>'administrator' then
    raise exception 'PDC_238_ADMINISTRATOR_REQUIRED' using errcode='42501';
  end if;
  if coalesce(v_email,'') like '%monitor%' or coalesce(v_email,'') like '%auditor%'
     or coalesce(v_email,'') like '%viewer%' or coalesce(v_email,'') like '%bot%' then
    raise exception 'PDC_238_NON_HUMAN_IDENTITY_DENIED' using errcode='42501';
  end if;
end;
$fn$;
revoke all on function public.workshop_require_website_administrator_238() from public,anon,authenticated,service_role;

insert into supabase_migrations.schema_migrations(version,name,statements)
values('239','workshop_admin_role_enum_cast',array['cast pdc_role enum to text before lower() in website Administrator guard'])
on conflict(version) do update set name=excluded.name,statements=excluded.statements;
commit;
