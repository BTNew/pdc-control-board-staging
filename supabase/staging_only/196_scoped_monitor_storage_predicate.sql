-- Staging-only: make scoped private attachment Storage policy executable without granting intake-table reads.
begin;
set local lock_timeout='5s';set local statement_timeout='120s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-196-monitor-storage-predicate',0));
do $guard$ begin if not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd') or not exists(select 1 from supabase_migrations.schema_migrations where version='195' and name='scoped_monitor_bound_attachment_storage_read') or exists(select 1 from supabase_migrations.schema_migrations where version='196') then raise exception 'PDC_196_STAGING_OR_LEDGER_MISMATCH' using errcode='55000';end if;end $guard$;
create or replace function public.pdc_monitor_can_read_bound_attachment(p_bucket text,p_name text)
returns boolean language sql stable security definer set search_path=pg_catalog,public as $$
 select p_bucket in('pdc-email-attachments','pdc-email-intake-private')
 and exists(select 1 from public.pdc_user_roles r where r.auth_user_id=auth.uid() and lower(r.email)='pdc.email.monitor.staging@pmb.local' and r.role='viewer' and r.active)
 and exists(select 1 from public.ai_email_attachments a where a.storage_path=p_bucket||'/'||p_name)
$$;
revoke all on function public.pdc_monitor_can_read_bound_attachment(text,text) from public,anon,authenticated,service_role;
grant execute on function public.pdc_monitor_can_read_bound_attachment(text,text) to authenticated;
drop policy if exists pdc_monitor_read_bound_email_attachments on storage.objects;
create policy pdc_monitor_read_bound_email_attachments on storage.objects for select to authenticated using(public.pdc_monitor_can_read_bound_attachment(bucket_id,name));
insert into supabase_migrations.schema_migrations(version,name,statements) values('196','scoped_monitor_storage_predicate',array['Security-definer boolean predicate exposes no intake data and binds private object reads to Monitor auth.uid and exact retained attachment path']);
commit;
