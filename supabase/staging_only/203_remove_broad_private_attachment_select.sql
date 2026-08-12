-- Staging-only: remove the legacy private-bucket SELECT policy that OR-bypasses the scoped Monitor path policy.
begin;
set local lock_timeout='5s';
set local statement_timeout='120s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-203-remove-broad-private-attachment-select',0));
do $guard$
begin
 if not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
 or not exists(select 1 from supabase_migrations.schema_migrations where version='202' and name='publish_monitor_reprocess_realtime_signal')
 or exists(select 1 from supabase_migrations.schema_migrations where version='203') then
  raise exception 'PDC_203_STAGING_OR_LEDGER_MISMATCH' using errcode='55000';
 end if;
end
$guard$;

drop policy if exists pdc_monitor_attachment_select on storage.objects;
revoke all on function public.pdc_can_read_private_email_attachment() from public,anon,authenticated,service_role;
drop function if exists public.pdc_can_read_private_email_attachment();

insert into supabase_migrations.schema_migrations(version,name,statements)
values('203','remove_broad_private_attachment_select',array[
 'Remove permissive legacy private-bucket SELECT policy that allowed operator/administrator reads outside the exact retained attachment path policy',
 'Retain pdc_monitor_read_bound_email_attachments as the only Monitor private attachment SELECT policy'
]);
commit;
