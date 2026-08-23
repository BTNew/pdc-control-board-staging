-- STAGING ONLY 352: restore only the dedicated future-mail Monitor authority.
-- Existing Inbox/Spam replay fences remain immutable; outbound mail and every
-- cleanse/purge or generic table-DML path remain forbidden.
begin;
set local lock_timeout='10s';
set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-352-future-only-monitor-activation',0));

do $guard$
declare
  v_actor constant uuid:='69846ef4-a74c-4569-9e35-376cf0837888';
begin
  if not public.pdc_monitor_staging_guard()
     or (select count(*) from public.pdc_staging_environment_sentinel
         where singleton and project_ref='cdsmnqxtyyoeoznmbidd')<>1
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or not exists(select 1 from supabase_migrations.schema_migrations
                   where version='20260824100000' and name='347_staging_board_containment')
     or not exists(select 1 from supabase_migrations.schema_migrations
                   where version='20260824110000' and name='348_one_shot_staging_board_cleanse')
     or not exists(select 1 from supabase_migrations.schema_migrations
                   where version='20260824113000' and name='350_cleanse_stale_predecessor_projections')
     or not exists(select 1 from supabase_migrations.schema_migrations
                   where version='20260824114000' and name='351_cleanse_orphan_navision_activations')
     or not exists(select 1 from supabase_migrations.schema_migrations
                   where version='20260824120000' and name='349_retire_staging_cleanse_authority')
     or exists(select 1 from supabase_migrations.schema_migrations
               where version>'20260824120000' and version~'^[0-9]{14}$')
     or exists(select 1 from supabase_migrations.schema_migrations where version='20260824130000')
     or (select count(*) from public.pdc_staging_containment_receipts_347
         where action_key='craig-staging-board-containment-20260824')<>1
     or (select count(*) from public.pdc_staging_cleanse_receipts_348
         where action_key='craig-staging-board-cleanse-20260824')<>1
     or exists(select 1 from public.vehicles
               where deleted_at is null and board_purged_at is null)
     or exists(select 1 from public.workshop_bookings)
     or exists(select 1 from public.vehicle_work_items)
     or not exists(select 1 from pg_trigger
                   where tgrelid='public.vehicles'::regclass
                     and tgname='pdc_reject_shared_board_qa_fixture_347'
                     and not tgisinternal)
     or (select count(*) from public.pdc_monitor_runtime_bindings_255 b
         where b.singleton and b.actor_id=v_actor
           and b.gateway_instance_id='pdc-monitor-staging-pmbcontroller-hourly-v1'
           and b.release_name='pdc-monitor-staging-m279-2026.08.39'
           and b.source_sha='7782ca5d875b27be7db63e1aa5380216c70c8d2e'
           and b.manifest_sha256='951e85db7d1a833d0d132b7a4a8063c579bf1f1e72df945e2a3862df61ec892e')<>1
     or (select count(*) from public.pdc_user_roles r
         where r.auth_user_id=v_actor and lower(r.email)='pmbcontroller@gmail.com'
           and r.active and r.account_status='approved')<>1
     or (select count(*) from public.monitored_mailboxes m
         where m.mailbox_key='pdc_pmb_email' and m.provider='gmail'
           and lower(m.mailbox_address)='pmbcontroller@gmail.com'
           and not m.active and m.test_mode
           and coalesce((m.config->>'contains_credentials')::boolean,false)=false
           and m.config->>'operational_scope'='staging'
           and (m.config->>'minimum_uid')::bigint=471
           and coalesce((m.config->>'outbound_email_enabled')::boolean,false)=false)<>1
     or exists(select 1 from public.pdc_monitor_stage_activation_writers
               where active and revoked_at is null)
     or exists(select 1 from public.pdc_email_monitor_pilot
               where enabled or outbound_email_enabled or automatic_rule_application
                  or automatic_authenticated_jobcards)
     or exists(select 1 from public.pdc_email_monitor_status
               where running_status<>'stopped' or gateway_instance_id is not null) then
    raise exception 'PDC_352_STAGING_PREDECESSOR_BINDING_OR_BASELINE_MISMATCH'
      using errcode='55000';
  end if;
end
$guard$;

create table public.pdc_staging_monitor_activation_receipts_352(
  receipt_id uuid primary key,
  action_key text not null unique
    check(action_key='craig-future-only-pdc-monitor-30m-20260824'),
  project_ref text not null check(project_ref='cdsmnqxtyyoeoznmbidd'),
  actor_id uuid not null check(actor_id='69846ef4-a74c-4569-9e35-376cf0837888'),
  gateway_instance_id text not null
    check(gateway_instance_id='pdc-monitor-staging-pmbcontroller-hourly-v1'),
  release_name text not null
    check(release_name='pdc-monitor-staging-m279-2026.08.39'),
  source_sha text not null
    check(source_sha='7782ca5d875b27be7db63e1aa5380216c70c8d2e'),
  manifest_sha256 text not null
    check(manifest_sha256='951e85db7d1a833d0d132b7a4a8063c579bf1f1e72df945e2a3862df61ec892e'),
  inbox_uidvalidity bigint not null check(inbox_uidvalidity=1),
  inbox_activation_high_water_uid bigint not null check(inbox_activation_high_water_uid=589),
  inbox_future_minimum_uid bigint not null check(inbox_future_minimum_uid=590),
  spam_historical_baseline_uid bigint not null check(spam_historical_baseline_uid=5),
  poll_interval_minutes integer not null check(poll_interval_minutes=30),
  prestate jsonb not null check(jsonb_typeof(prestate)='object'),
  poststate jsonb not null check(jsonb_typeof(poststate)='object'),
  replay_state jsonb not null check(jsonb_typeof(replay_state)='object'),
  replay_state_sha256 text not null check(replay_state_sha256~'^[a-f0-9]{64}$'),
  applied_at timestamptz not null default clock_timestamp()
);
alter table public.pdc_staging_monitor_activation_receipts_352 enable row level security;
revoke all on table public.pdc_staging_monitor_activation_receipts_352
  from public,anon,authenticated,service_role;

create function public.pdc_staging_monitor_activation_receipt_immutable_352()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
begin
  raise exception 'PDC_352_ACTIVATION_RECEIPT_IMMUTABLE' using errcode='55000';
end
$$;
revoke all on function public.pdc_staging_monitor_activation_receipt_immutable_352()
  from public,anon,authenticated,service_role;
create trigger pdc_staging_monitor_activation_receipt_immutable_352
before update or delete on public.pdc_staging_monitor_activation_receipts_352
for each row execute function public.pdc_staging_monitor_activation_receipt_immutable_352();

do $activate$
declare
  v_actor constant uuid:='69846ef4-a74c-4569-9e35-376cf0837888';
  v_pre jsonb;
  v_post jsonb;
  v_replay_before jsonb;
  v_replay_after jsonb;
begin
  v_replay_before:=jsonb_build_object(
    'email_intakes',(select count(*) from public.ai_email_intake),
    'email_attachments',(select count(*) from public.ai_email_attachments),
    'provider_observations',(select count(*) from public.pdc_provider_email_observations),
    'canonical_jobcard_receipts',(select count(*) from public.pdc_jobcard_attachment_import_receipts),
    'canonical_rule_receipts',(select count(*) from public.pdc_jobcard_attachment_rule_receipts_279),
    'supervised_applications',(select count(*) from public.pdc_supervised_monitor_applications),
    'inbox_uidvalidity',1,
    'inbox_activation_high_water_uid',589,
    'inbox_future_minimum_uid',590,
    'spam_historical_baseline_uid',5
  );
  v_pre:=jsonb_build_object(
    'pilot_enabled',(select enabled from public.pdc_email_monitor_pilot where singleton),
    'active_mailboxes',(select count(*) from public.monitored_mailboxes where active),
    'active_monitor_writers',(select count(*) from public.pdc_monitor_stage_activation_writers where active and revoked_at is null),
    'actor_role',(select role::text from public.pdc_user_roles where auth_user_id=v_actor),
    'running_status',(select running_status from public.pdc_email_monitor_status where singleton),
    'gateway_instance_id',(select gateway_instance_id from public.pdc_email_monitor_status where singleton),
    'operational_vehicles',(select count(*) from public.vehicles where deleted_at is null and board_purged_at is null)
  );

  update public.pdc_user_roles
     set role='importer',active=true,account_status='approved',updated_at=clock_timestamp()
   where auth_user_id=v_actor and lower(email)='pmbcontroller@gmail.com';

  update public.pdc_monitor_stage_activation_writers
     set active=true,
         revoked_at=null,
         reason='Craig authorised dedicated pdc-emails Monitor future-only staging imports every 30 minutes on 2026-08-24',
         granted_by=(select authorized_by from public.pdc_email_monitor_pilot where singleton),
         granted_at=clock_timestamp()
   where user_id=v_actor;

  update public.pdc_email_monitor_pilot
     set enabled=true,
         outbound_email_enabled=false,
         automatic_rule_application=true,
         automatic_authenticated_jobcards=true,
         ambiguous_to_review=true,
         exactly_once_required=true,
         updated_at=clock_timestamp()
   where singleton and project_ref='cdsmnqxtyyoeoznmbidd'
     and mailbox_key='pdc_pmb_email' and minimum_uid=471;

  update public.monitored_mailboxes
     set active=true,
         test_mode=true,
         config=(config-'containment')||jsonb_build_object(
           'supervised_pilot_enabled',true,
           'outbound_email_enabled',false,
           'exactly_once_required',true,
           'inbox_uidvalidity',1,
           'activation_high_water_uid',589,
           'future_only_minimum_uid',590,
           'spam_historical_baseline_uid',5,
           'poll_interval_minutes',30,
           'activation','craig-future-only-pdc-monitor-30m-20260824'),
         updated_at=clock_timestamp()
   where mailbox_key='pdc_pmb_email' and provider='gmail'
     and lower(mailbox_address)='pmbcontroller@gmail.com';

  update public.pdc_email_monitor_status
     set running_status='stopped',
         gateway_instance_id='pdc-monitor-staging-pmbcontroller-hourly-v1',
         last_error='Future-only staging Monitor authority active; awaiting first authenticated 30-minute cycle.',
         last_error_code='activation_awaiting_first_cycle',
         updated_at=clock_timestamp()
   where singleton;

  -- Reassert the narrow RPC-only boundary and permanently retired cleanup surface.
  revoke all on table public.monitored_mailboxes,public.pdc_email_monitor_pilot,
    public.pdc_email_monitor_status,public.pdc_monitor_stage_activation_writers,
    public.pdc_monitor_runtime_bindings_255
    from public,anon,authenticated,service_role;
  revoke all on function public.pdc_admin_run_staging_cleanse_348()
    from public,anon,authenticated,service_role;
  revoke all on function public.purge_all_staging_board_vehicles(text,text)
    from public,anon,authenticated,service_role;
  revoke all on function public.purge_vehicle_from_board(uuid,integer,text)
    from public,anon,authenticated,service_role;
  if to_regprocedure('public.pdc_admin_complete_vehicle_delete(uuid,integer,text,text,text)') is not null then
    execute 'revoke all on function public.pdc_admin_complete_vehicle_delete(uuid,integer,text,text,text) from public,anon,authenticated,service_role';
  end if;

  v_replay_after:=jsonb_build_object(
    'email_intakes',(select count(*) from public.ai_email_intake),
    'email_attachments',(select count(*) from public.ai_email_attachments),
    'provider_observations',(select count(*) from public.pdc_provider_email_observations),
    'canonical_jobcard_receipts',(select count(*) from public.pdc_jobcard_attachment_import_receipts),
    'canonical_rule_receipts',(select count(*) from public.pdc_jobcard_attachment_rule_receipts_279),
    'supervised_applications',(select count(*) from public.pdc_supervised_monitor_applications),
    'inbox_uidvalidity',1,
    'inbox_activation_high_water_uid',589,
    'inbox_future_minimum_uid',590,
    'spam_historical_baseline_uid',5
  );
  v_post:=jsonb_build_object(
    'pilot_enabled',(select enabled from public.pdc_email_monitor_pilot where singleton),
    'outbound_email_enabled',(select outbound_email_enabled from public.pdc_email_monitor_pilot where singleton),
    'automatic_rule_application',(select automatic_rule_application from public.pdc_email_monitor_pilot where singleton),
    'automatic_authenticated_jobcards',(select automatic_authenticated_jobcards from public.pdc_email_monitor_pilot where singleton),
    'active_mailboxes',(select count(*) from public.monitored_mailboxes where active),
    'active_monitor_writers',(select count(*) from public.pdc_monitor_stage_activation_writers where active and revoked_at is null),
    'actor_role',(select role::text from public.pdc_user_roles where auth_user_id=v_actor),
    'running_status',(select running_status from public.pdc_email_monitor_status where singleton),
    'gateway_instance_id',(select gateway_instance_id from public.pdc_email_monitor_status where singleton),
    'operational_vehicles',(select count(*) from public.vehicles where deleted_at is null and board_purged_at is null),
    'visible_operational_vehicles',(select count(*) from public.vehicles where deleted_at is null and board_purged_at is null and visible_on_board),
    'workshop_bookings',(select count(*) from public.workshop_bookings),
    'vehicle_work_items',(select count(*) from public.vehicle_work_items),
    'qa_fixture_guard',exists(select 1 from pg_trigger where tgrelid='public.vehicles'::regclass and tgname='pdc_reject_shared_board_qa_fixture_347' and not tgisinternal)
  );

  if not (v_post->>'pilot_enabled')::boolean
     or (v_post->>'outbound_email_enabled')::boolean
     or not (v_post->>'automatic_rule_application')::boolean
     or not (v_post->>'automatic_authenticated_jobcards')::boolean
     or (v_post->>'active_mailboxes')::integer<>1
     or (v_post->>'active_monitor_writers')::integer<>1
     or v_post->>'actor_role'<>'importer'
     or v_post->>'running_status'<>'stopped'
     or v_post->>'gateway_instance_id'<>'pdc-monitor-staging-pmbcontroller-hourly-v1'
     or (v_post->>'operational_vehicles')::integer<>0
     or (v_post->>'visible_operational_vehicles')::integer<>0
     or (v_post->>'workshop_bookings')::integer<>0
     or (v_post->>'vehicle_work_items')::integer<>0
     or not (v_post->>'qa_fixture_guard')::boolean
     or v_replay_before is distinct from v_replay_after
     or exists(select 1 from public.pdc_monitor_stage_activation_writers w
               where w.user_id<>v_actor and w.active)
     or has_function_privilege('authenticated','public.pdc_admin_run_staging_cleanse_348()','EXECUTE')
     or has_function_privilege('authenticated','public.purge_all_staging_board_vehicles(text,text)','EXECUTE')
     or has_function_privilege('authenticated','public.purge_vehicle_from_board(uuid,integer,text)','EXECUTE') then
    raise exception 'PDC_352_ACTIVATION_POSTCONDITION_FAILED' using errcode='55000';
  end if;

  insert into public.pdc_staging_monitor_activation_receipts_352(
    receipt_id,action_key,project_ref,actor_id,gateway_instance_id,release_name,
    source_sha,manifest_sha256,inbox_uidvalidity,inbox_activation_high_water_uid,
    inbox_future_minimum_uid,spam_historical_baseline_uid,poll_interval_minutes,
    prestate,poststate,replay_state,replay_state_sha256)
  values(
    gen_random_uuid(),'craig-future-only-pdc-monitor-30m-20260824','cdsmnqxtyyoeoznmbidd',
    v_actor,'pdc-monitor-staging-pmbcontroller-hourly-v1','pdc-monitor-staging-m279-2026.08.39',
    '7782ca5d875b27be7db63e1aa5380216c70c8d2e',
    '951e85db7d1a833d0d132b7a4a8063c579bf1f1e72df945e2a3862df61ec892e',
    1,589,590,5,30,v_pre,v_post,v_replay_after,
    encode(extensions.digest(convert_to(v_replay_after::text,'UTF8'),'sha256'),'hex'));
end
$activate$;

create function public.get_pdc_staging_monitor_activation_status_352()
returns jsonb language plpgsql stable security definer
set search_path=pg_catalog,public as $$
declare
  v_actor uuid:=auth.uid();
  v_receipt public.pdc_staging_monitor_activation_receipts_352%rowtype;
begin
  perform public.require_pdc_role('viewer');
  select * into v_receipt from public.pdc_staging_monitor_activation_receipts_352
   where action_key='craig-future-only-pdc-monitor-30m-20260824';
  return jsonb_build_object(
    'environment','staging','project_ref',v_receipt.project_ref,
    'receipt_id',v_receipt.receipt_id,'applied_at',v_receipt.applied_at,
    'authenticated_actor_id',v_actor,
    'authenticated_actor_role',public.current_pdc_user_role()::text,
    'bound_actor_id',v_receipt.actor_id,
    'authenticated_actor_is_bound',v_actor=v_receipt.actor_id,
    'gateway_instance_id',v_receipt.gateway_instance_id,
    'release_name',v_receipt.release_name,'source_sha',v_receipt.source_sha,
    'manifest_sha256',v_receipt.manifest_sha256,
    'pilot_enabled',(select enabled from public.pdc_email_monitor_pilot where singleton),
    'outbound_email_enabled',(select outbound_email_enabled from public.pdc_email_monitor_pilot where singleton),
    'automatic_rule_application',(select automatic_rule_application from public.pdc_email_monitor_pilot where singleton),
    'automatic_authenticated_jobcards',(select automatic_authenticated_jobcards from public.pdc_email_monitor_pilot where singleton),
    'mailbox_active',(select active from public.monitored_mailboxes where mailbox_key='pdc_pmb_email'),
    'mailbox_test_mode',(select test_mode from public.monitored_mailboxes where mailbox_key='pdc_pmb_email'),
    'active_monitor_writers',(select count(*) from public.pdc_monitor_stage_activation_writers where active and revoked_at is null),
    'bound_writer_active',exists(select 1 from public.pdc_monitor_stage_activation_writers where user_id=v_receipt.actor_id and active and revoked_at is null),
    'inbox_uidvalidity',v_receipt.inbox_uidvalidity,
    'inbox_activation_high_water_uid',v_receipt.inbox_activation_high_water_uid,
    'inbox_future_minimum_uid',v_receipt.inbox_future_minimum_uid,
    'spam_historical_baseline_uid',v_receipt.spam_historical_baseline_uid,
    'poll_interval_minutes',v_receipt.poll_interval_minutes,
    'replay_state_sha256',v_receipt.replay_state_sha256,
    'operational_vehicles',(select count(*) from public.vehicles where deleted_at is null and board_purged_at is null),
    'visible_operational_vehicles',(select count(*) from public.vehicles where deleted_at is null and board_purged_at is null and visible_on_board),
    'workshop_bookings',(select count(*) from public.workshop_bookings),
    'vehicle_work_items',(select count(*) from public.vehicle_work_items),
    'qa_fixture_guard',exists(select 1 from pg_trigger where tgrelid='public.vehicles'::regclass and tgname='pdc_reject_shared_board_qa_fixture_347' and not tgisinternal),
    'cleanse_execute_authenticated',has_function_privilege('authenticated','public.pdc_admin_run_staging_cleanse_348()','EXECUTE'),
    'legacy_bulk_purge_execute_authenticated',has_function_privilege('authenticated','public.purge_all_staging_board_vehicles(text,text)','EXECUTE'),
    'legacy_vehicle_purge_execute_authenticated',has_function_privilege('authenticated','public.purge_vehicle_from_board(uuid,integer,text)','EXECUTE'),
    'monitor_tables_generic_dml_denied',
      not has_table_privilege('authenticated','public.monitored_mailboxes','INSERT,UPDATE,DELETE')
      and not has_table_privilege('authenticated','public.pdc_email_monitor_pilot','INSERT,UPDATE,DELETE')
      and not has_table_privilege('authenticated','public.pdc_email_monitor_status','INSERT,UPDATE,DELETE')
      and not has_table_privilege('authenticated','public.pdc_monitor_stage_activation_writers','INSERT,UPDATE,DELETE')
      and not has_table_privilege('authenticated','public.pdc_monitor_runtime_bindings_255','INSERT,UPDATE,DELETE')
  );
end
$$;
revoke all on function public.get_pdc_staging_monitor_activation_status_352()
  from public,anon,authenticated,service_role;
grant execute on function public.get_pdc_staging_monitor_activation_status_352() to authenticated;

insert into supabase_migrations.schema_migrations(version,name,statements)
values('20260824130000','352_activate_future_only_pdc_monitor',array[
  'Require exact 347/348/350/351/349 predecessor ledger, staging sentinel, zero Board and QA guard',
  'Reuse exact sealed pmbcontroller Monitor actor, gateway, m279 release, source and manifest binding',
  'Enable one test-mode mailbox and one writer with automatic authenticated Job Cards and approved rules',
  'Preserve Inbox UIDVALIDITY 1/high-water 589/future floor 590 and Spam historical baseline 5',
  'Keep outbound email false, Production sentinel forbidden, generic DML denied and cleanse/purge revoked',
  'Record immutable activation/replay receipt and expose authenticated typed status read-back'
]);
notify pgrst,'reload schema';
commit;
