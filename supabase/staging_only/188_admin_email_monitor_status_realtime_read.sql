-- Staging-only: permit Administrator Realtime reads of monitor health only.
begin;
do $guard$ begin if not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd') or not exists(select 1 from supabase_migrations.schema_migrations where version='187') or exists(select 1 from supabase_migrations.schema_migrations where version='188') then raise exception 'PDC_188_GUARD_MISMATCH';end if;end $guard$;
drop policy if exists pdc_email_monitor_status_admin_realtime on public.pdc_email_monitor_status;
create policy pdc_email_monitor_status_admin_realtime on public.pdc_email_monitor_status for select to authenticated using(public.current_pdc_user_role()='administrator');
grant select on public.pdc_email_monitor_status to authenticated;
insert into supabase_migrations.schema_migrations(version,name,statements) values('188','admin_email_monitor_status_realtime_read',array['Administrator-only Realtime select policy for the single monitor health row']);commit;
