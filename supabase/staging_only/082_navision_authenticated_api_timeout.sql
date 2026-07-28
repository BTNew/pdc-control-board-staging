-- Staging-only migration 082.
-- Full 663-row Navision reconciliations require about 14 seconds with complete
-- source evidence. The staging authenticated API role was still capped at 8
-- seconds, so PostgREST cancelled the atomic Apply with SQLSTATE 57014 before
-- the function-level 120-second safety bound could help. Raise only the signed-
-- in staging role to a measured 30-second bound; anon and production are not
-- changed.
begin;

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd') then
    raise exception 'PDC_STAGING_SENTINEL_MISMATCH';
  end if;
end
$guard$;

alter role authenticated set statement_timeout = '30s';
notify pgrst, 'reload config';

commit;
