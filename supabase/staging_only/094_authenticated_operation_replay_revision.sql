-- Staging-only migration 094: exact-replay revision stability for authenticated operation evidence.
-- A row-level trigger bumps the snapshot revision only when an operation row is actually inserted,
-- updated or deleted; ON CONFLICT DO NOTHING replays remain revision-stable.
begin;
do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists (
       select 1 from public.pdc_staging_environment_sentinel
       where singleton and project_ref='cdsmnqxtyyoeoznmbidd'
     )
     or to_regclass('public.pdc_authenticated_email_operation_lines') is null then
    raise exception 'PDC_MIGRATION_094_STAGING_OR_DEPENDENCY_MISMATCH';
  end if;
end;
$guard$;

drop trigger if exists pdc_email_vehicle_revision_operation_lines
  on public.pdc_authenticated_email_operation_lines;
create trigger pdc_email_vehicle_revision_operation_lines
after insert or update or delete on public.pdc_authenticated_email_operation_lines
for each row execute function public.bump_pdc_email_vehicle_revision();

comment on trigger pdc_email_vehicle_revision_operation_lines on public.pdc_authenticated_email_operation_lines is
  'Row-level revision bump: exact ON CONFLICT DO NOTHING replays do not drift the authenticated-email snapshot revision.';
commit;
