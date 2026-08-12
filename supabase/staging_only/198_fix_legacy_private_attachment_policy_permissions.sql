-- Staging-only: remove direct-table permission failures from legacy private attachment policies.
begin;
set local lock_timeout='5s';set local statement_timeout='120s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-198-monitor-storage-policy-fix',0));
do $guard$ begin if not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd') or not exists(select 1 from supabase_migrations.schema_migrations where version='196' and name='scoped_monitor_storage_predicate') or exists(select 1 from supabase_migrations.schema_migrations where version='198') then raise exception 'PDC_198_STAGING_OR_LEDGER_MISMATCH' using errcode='55000';end if;end $guard$;
create or replace function public.pdc_can_read_private_email_attachment()
returns boolean language sql stable security definer set search_path=pg_catalog,public as $$
 select exists(select 1 from public.pdc_monitor_stage_activation_writers w where w.user_id=auth.uid() and w.active and w.revoked_at is null)
 or public.current_pdc_user_role() in('operator','administrator')
$$;
revoke all on function public.pdc_can_read_private_email_attachment() from public,anon,authenticated,service_role;grant execute on function public.pdc_can_read_private_email_attachment() to authenticated;
drop policy if exists pdc_monitor_attachment_select on storage.objects;
create policy pdc_monitor_attachment_select on storage.objects for select to authenticated using(bucket_id='pdc-email-intake-private' and public.pdc_can_read_private_email_attachment());
insert into supabase_migrations.schema_migrations(version,name,statements) values('198','fix_legacy_private_attachment_policy_permissions',array['Preserve legacy writer/operator/administrator private attachment reads via non-data-returning security-definer predicate','Allow scoped bound Monitor policy to evaluate without revoked-table permission errors']);
commit;
