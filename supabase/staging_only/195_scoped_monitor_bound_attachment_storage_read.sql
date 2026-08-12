-- Staging-only: allow the scoped Monitor identity to read only retained attachment objects already bound to intake rows.
begin;
set local lock_timeout='5s';set local statement_timeout='120s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-195-monitor-storage-read',0));
do $guard$ begin if not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd') or not exists(select 1 from supabase_migrations.schema_migrations where version='194' and name='fix_provider_bound_enqueue_status_signal') or exists(select 1 from supabase_migrations.schema_migrations where version='195') then raise exception 'PDC_195_STAGING_OR_LEDGER_MISMATCH' using errcode='55000';end if;end $guard$;
drop policy if exists pdc_monitor_read_bound_email_attachments on storage.objects;
create policy pdc_monitor_read_bound_email_attachments on storage.objects for select to authenticated using(
 bucket_id in('pdc-email-attachments','pdc-email-intake-private')
 and exists(select 1 from public.pdc_user_roles r where r.auth_user_id=auth.uid() and lower(r.email)='pdc.email.monitor.staging@pmb.local' and r.role='viewer' and r.active)
 and exists(select 1 from public.ai_email_attachments a where a.storage_path=bucket_id||'/'||name)
);
insert into supabase_migrations.schema_migrations(version,name,statements) values('195','scoped_monitor_bound_attachment_storage_read',array['Monitor Viewer may read only private storage objects already bound by exact path to retained intake attachments']);
commit;
