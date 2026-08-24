-- STAGING ONLY 353: stop every Monitor/mailbox/writer path before the authorised
-- full vehicle-history reset. This migration grants no reset or generic DML authority.
begin;
set local lock_timeout='10s';
set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-353-full-reset-containment',0));

do $guard$
begin
  if not public.pdc_monitor_staging_guard()
     or (select count(*) from public.pdc_staging_environment_sentinel
         where singleton and project_ref='cdsmnqxtyyoeoznmbidd')<>1
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or not exists(select 1 from supabase_migrations.schema_migrations
                   where version='20260824130000' and name='352_activate_future_only_pdc_monitor')
     or exists(select 1 from supabase_migrations.schema_migrations
               where version>'20260824130000' and version~'^[0-9]{14}$') then
    raise exception 'PDC_353_STAGING_TARGET_OR_HEAD_MISMATCH' using errcode='55000';
  end if;
end
$guard$;

update public.pdc_email_monitor_pilot
   set enabled=false,outbound_email_enabled=false,automatic_rule_application=false,
       automatic_authenticated_jobcards=false,updated_at=clock_timestamp()
 where singleton;
update public.monitored_mailboxes
   set active=false,test_mode=true,
       config=(config-'supervised_pilot_enabled')||jsonb_build_object(
         'supervised_pilot_enabled',false,'outbound_email_enabled',false,
         'containment','craig-full-history-reset-20260824'),
       updated_at=clock_timestamp()
 where active or mailbox_key='pdc_pmb_email';
update public.pdc_monitor_stage_activation_writers
   set active=false,revoked_at=coalesce(revoked_at,clock_timestamp()),
       reason='Craig full staging vehicle-history reset 2026-08-24: authority revoked'
 where active or revoked_at is null;
update public.pdc_email_monitor_status
   set running_status='stopped',gateway_instance_id=null,
       last_finished_at=coalesce(last_finished_at,clock_timestamp()),
       last_error='Staging Monitor stopped for full vehicle-history reset; no mailbox or writer authority.',
       last_error_code='staging_full_history_reset_contained',updated_at=clock_timestamp()
 where singleton;

-- Reassert all retired purge/cleanse surfaces.
revoke all on function public.pdc_admin_run_staging_cleanse_348() from public,anon,authenticated,service_role;
revoke all on function public.purge_all_staging_board_vehicles(text,text) from public,anon,authenticated,service_role;
revoke all on function public.purge_vehicle_from_board(uuid,integer,text) from public,anon,authenticated,service_role;
do $optional$
begin
 if to_regprocedure('public.pdc_admin_complete_vehicle_delete(uuid,integer,text,text,text)') is not null then
  execute 'revoke all on function public.pdc_admin_complete_vehicle_delete(uuid,integer,text,text,text) from public,anon,authenticated,service_role';
 end if;
end
$optional$;

do $verify$
begin
 if exists(select 1 from public.pdc_email_monitor_pilot where enabled or outbound_email_enabled
           or automatic_rule_application or automatic_authenticated_jobcards)
    or exists(select 1 from public.monitored_mailboxes where active)
    or exists(select 1 from public.pdc_monitor_stage_activation_writers where active and revoked_at is null)
    or exists(select 1 from public.pdc_email_monitor_status where running_status<>'stopped' or gateway_instance_id is not null)
    or has_function_privilege('authenticated','public.pdc_admin_run_staging_cleanse_348()','EXECUTE')
    or has_function_privilege('authenticated','public.purge_all_staging_board_vehicles(text,text)','EXECUTE')
    or has_function_privilege('authenticated','public.purge_vehicle_from_board(uuid,integer,text)','EXECUTE') then
  raise exception 'PDC_353_CONTAINMENT_POSTCONDITION_FAILED' using errcode='55000';
 end if;
end
$verify$;

insert into supabase_migrations.schema_migrations(version,name,statements)
values('20260824140000','353_contain_monitor_for_full_history_reset',array[
 'Require exact staging sentinel and migration 352 head; Production sentinel forbidden',
 'Stop pilot, mailbox, automatic actions, stage writers and runtime gateway before backup/reset',
 'Keep outbound mail false and reassert every retired cleanse/purge authority',
 'Grant no reset, generic DML, mailbox, writer or Production authority'
]);
notify pgrst,'reload schema';
commit;
