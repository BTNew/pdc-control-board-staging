-- Staging-only migration 081.
-- Migration 076 replaced the dealer-scoped preview/apply wrappers after the
-- bounded 120-second timeout had been attached in migration 041. Replacing the
-- functions removed that proconfig, returning large dealer files to the short
-- PostgREST role timeout (SQLSTATE 57014). Restore the same bounded timeout to
-- the currently exposed wrappers and their preserved delegates.
begin;

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd') then
    raise exception 'PDC_STAGING_SENTINEL_MISMATCH';
  end if;
end
$guard$;

alter function public.preview_navision_backend_import(jsonb,text,text,text,timestamptz)
  set statement_timeout = '120s';
alter function public.apply_navision_backend_import(text,jsonb,text,text,text,timestamptz,text,text,bigint)
  set statement_timeout = '120s';

-- The preserved functions are called by the wrappers. Keep the same bound at
-- both layers so a future direct internal call cannot regress to the role limit.
alter function public.preview_navision_backend_import_pre076(jsonb,text,text,text,timestamptz)
  set statement_timeout = '120s';
alter function public.apply_navision_backend_import_pre076(text,jsonb,text,text,text,timestamptz,text,text,bigint)
  set statement_timeout = '120s';

commit;
