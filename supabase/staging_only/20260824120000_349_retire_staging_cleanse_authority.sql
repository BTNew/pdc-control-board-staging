-- STAGING ONLY 349: retire the one-shot cleanse mutation surface after live
-- success/replay acceptance, leaving only typed read-back.
begin;
set local lock_timeout='10s';
set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-349-retire-cleanse-authority',0));

do $guard$
begin
  if not public.pdc_monitor_staging_guard()
     or (select count(*) from public.pdc_staging_environment_sentinel
         where singleton and project_ref='cdsmnqxtyyoeoznmbidd')<>1
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or not exists(select 1 from supabase_migrations.schema_migrations
                   where version='20260824110000' and name='348_one_shot_staging_board_cleanse')
     or (select count(*) from public.pdc_staging_cleanse_receipts_348
         where action_key='craig-staging-board-cleanse-20260824')<>1
     or exists(select 1 from public.vehicles
               where deleted_at is null or board_purged_at is null or visible_on_board or lifecycle_state<>'deleted')
     or exists(select 1 from public.workshop_bookings)
     or exists(select 1 from public.vehicle_work_items)
     or exists(select 1 from public.pdc_email_monitor_pilot where enabled or outbound_email_enabled
               or automatic_rule_application or automatic_authenticated_jobcards)
     or exists(select 1 from public.monitored_mailboxes where active)
     or exists(select 1 from public.pdc_monitor_stage_activation_writers where active and revoked_at is null)
     or exists(select 1 from public.pdc_email_monitor_status
               where running_status<>'stopped' or gateway_instance_id is not null)
     or exists(select 1 from supabase_migrations.schema_migrations
               where version='20260824120000') then
    raise exception 'PDC_349_CLEANSE_ACCEPTANCE_OR_TARGET_MISMATCH' using errcode='55000';
  end if;
end
$guard$;

revoke all on function public.pdc_admin_run_staging_cleanse_348()
  from public,anon,authenticated,service_role;
revoke all on function public.purge_all_staging_board_vehicles(text,text)
  from public,anon,authenticated,service_role;
revoke all on function public.purge_vehicle_from_board(uuid,integer,text)
  from public,anon,authenticated,service_role;

do $optional_complete_delete$
begin
  if to_regprocedure('public.pdc_admin_complete_vehicle_delete(uuid,integer,text,text,text)') is not null then
    execute 'revoke all on function public.pdc_admin_complete_vehicle_delete(uuid,integer,text,text,text) from public,anon,authenticated,service_role';
  end if;
end
$optional_complete_delete$;

create function public.get_pdc_staging_cleanse_status_349()
returns jsonb language plpgsql stable security definer
set search_path=pg_catalog,public as $$
declare r public.pdc_staging_cleanse_receipts_348%rowtype;
begin
  perform public.require_pdc_role('viewer');
  select * into r from public.pdc_staging_cleanse_receipts_348
   where action_key='craig-staging-board-cleanse-20260824';
  return jsonb_build_object(
    'environment','staging','project_ref','cdsmnqxtyyoeoznmbidd',
    'cleanse_receipt_id',r.receipt_id,
    'backup_manifest_sha256',r.backup_manifest_sha256,
    'encrypted_backup_sha256',r.encrypted_backup_sha256,
    'backup_gzip_sha256',r.backup_gzip_sha256,
    'backup_raw_bytes',r.backup_raw_bytes,
    'applied_at',r.applied_at,
    'prestate',r.prestate,'poststate',r.poststate,
    'replay_evidence_preserved',r.replay_evidence_before is not distinct from r.replay_evidence_after,
    'operational_vehicles',(select count(*) from public.vehicles where deleted_at is null and board_purged_at is null),
    'visible_operational_vehicles',(select count(*) from public.vehicles where deleted_at is null and board_purged_at is null and visible_on_board),
    'workshop_bookings',(select count(*) from public.workshop_bookings),
    'vehicle_work_items',(select count(*) from public.vehicle_work_items),
    'pilot_enabled',(select enabled from public.pdc_email_monitor_pilot where singleton),
    'outbound_email_enabled',(select outbound_email_enabled from public.pdc_email_monitor_pilot where singleton),
    'running_status',(select running_status from public.pdc_email_monitor_status where singleton),
    'active_mailboxes',(select count(*) from public.monitored_mailboxes where active),
    'active_monitor_writers',(select count(*) from public.pdc_monitor_stage_activation_writers where active and revoked_at is null),
    'qa_fixture_guard',exists(select 1 from pg_trigger where tgrelid='public.vehicles'::regclass and tgname='pdc_reject_shared_board_qa_fixture_347' and not tgisinternal),
    'cleanse_execute_authenticated',has_function_privilege('authenticated','public.pdc_admin_run_staging_cleanse_348()','EXECUTE'),
    'legacy_bulk_purge_execute_authenticated',has_function_privilege('authenticated','public.purge_all_staging_board_vehicles(text,text)','EXECUTE'),
    'legacy_vehicle_purge_execute_authenticated',has_function_privilege('authenticated','public.purge_vehicle_from_board(uuid,integer,text)','EXECUTE')
  );
end
$$;
revoke all on function public.get_pdc_staging_cleanse_status_349()
  from public,anon,authenticated,service_role;
grant execute on function public.get_pdc_staging_cleanse_status_349() to authenticated;

insert into supabase_migrations.schema_migrations(version,name,statements)
values('20260824120000','349_retire_staging_cleanse_authority',array[
  'Require exact successful cleanse receipt and zero operational/Monitor postconditions',
  'Revoke one-shot cleanse, bulk purge, per-vehicle purge and optional complete-delete mutation authority',
  'Retain immutable recovery/audit evidence and expose authenticated typed read-back only'
]);
notify pgrst,'reload schema';
commit;
