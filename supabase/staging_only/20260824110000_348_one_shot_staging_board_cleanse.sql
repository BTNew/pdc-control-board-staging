-- STAGING ONLY 348: one-shot Administrator cleanse bound to the exact verified
-- encrypted operational recovery artifact produced after migration 347 containment.
begin;
set local lock_timeout='10s';
set local statement_timeout='600s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-348-one-shot-board-cleanse',0));

do $guard$
begin
  if not public.pdc_monitor_staging_guard()
     or (select count(*) from public.pdc_staging_environment_sentinel
         where singleton and project_ref='cdsmnqxtyyoeoznmbidd')<>1
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or not exists(select 1 from supabase_migrations.schema_migrations
                   where version='20260824100000' and name='347_staging_board_containment')
     or exists(select 1 from supabase_migrations.schema_migrations
               where version='20260824110000') then
    raise exception 'PDC_348_STAGING_SENTINEL_OR_PREDECESSOR_MISMATCH'
      using errcode='55000';
  end if;
end
$guard$;

create table public.pdc_staging_cleanse_receipts_348(
  receipt_id uuid primary key,
  project_ref text not null check(project_ref='cdsmnqxtyyoeoznmbidd'),
  action_key text not null unique check(action_key='craig-staging-board-cleanse-20260824'),
  backup_manifest_sha256 text not null unique check(backup_manifest_sha256~'^[a-f0-9]{64}$'),
  encrypted_backup_sha256 text not null check(encrypted_backup_sha256~'^[a-f0-9]{64}$'),
  backup_gzip_sha256 text not null check(backup_gzip_sha256~'^[a-f0-9]{64}$'),
  backup_raw_bytes bigint not null check(backup_raw_bytes>0),
  applied_by uuid not null references auth.users(id) on delete restrict,
  applied_by_email text not null,
  applied_at timestamptz not null default clock_timestamp(),
  prestate jsonb not null check(jsonb_typeof(prestate)='object'),
  poststate jsonb not null check(jsonb_typeof(poststate)='object'),
  replay_evidence_before jsonb not null check(jsonb_typeof(replay_evidence_before)='object'),
  replay_evidence_after jsonb not null check(jsonb_typeof(replay_evidence_after)='object'),
  cleanse_result jsonb not null check(jsonb_typeof(cleanse_result)='object')
);
alter table public.pdc_staging_cleanse_receipts_348 enable row level security;
revoke all on table public.pdc_staging_cleanse_receipts_348
  from public,anon,authenticated,service_role;

create function public.pdc_staging_cleanse_receipt_immutable_348()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
begin
  raise exception 'PDC_348_CLEANSE_RECEIPT_IMMUTABLE' using errcode='55000';
end
$$;
revoke all on function public.pdc_staging_cleanse_receipt_immutable_348()
  from public,anon,authenticated,service_role;
create trigger pdc_staging_cleanse_receipt_immutable_348
before update or delete on public.pdc_staging_cleanse_receipts_348
for each row execute function public.pdc_staging_cleanse_receipt_immutable_348();

create function public.pdc_admin_run_staging_cleanse_348()
returns jsonb language plpgsql volatile security definer
set search_path=pg_catalog,public,extensions as $$
declare
  v_actor jsonb;
  v_actor_id uuid;
  v_actor_email text;
  v_existing public.pdc_staging_cleanse_receipts_348%rowtype;
  v_pre jsonb;
  v_post jsonb;
  v_replay_before jsonb;
  v_replay_after jsonb;
  v_result jsonb;
  v_manifest constant text:='73196732f8f0ebe25fa5853a7557d1bbf9c9dd64202ce3ae352865bc80f9f552';
  v_gzip constant text:='548f20c7489266055db67ea15310ebce00ff836f026c4275fbb48c15c1909407';
  v_encrypted constant text:='47372294375d9c6787fb8bd01521a763969a2b4d298acb9d1c1a71e72bd912e3';
  v_raw_bytes constant bigint:=19382148;
begin
  if not public.pdc_monitor_staging_guard()
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or (select count(*) from public.pdc_staging_environment_sentinel
         where singleton and project_ref='cdsmnqxtyyoeoznmbidd')<>1 then
    return public.navision_backend_response(false,'wrong_environment');
  end if;
  v_actor:=public.pdc_admin_vehicle_actor();
  if not coalesce((v_actor->>'ok')::boolean,false) then return v_actor; end if;
  v_actor_id:=(v_actor->'data'->>'actor_id')::uuid;
  v_actor_email:=v_actor->'data'->>'actor_email';

  perform pg_advisory_xact_lock(hashtextextended('pdc-staging-348-one-shot-board-cleanse',0));
  select * into v_existing from public.pdc_staging_cleanse_receipts_348
   where action_key='craig-staging-board-cleanse-20260824' for share;
  if found then
    if exists(select 1 from public.vehicles
              where deleted_at is null or board_purged_at is null or visible_on_board or lifecycle_state<>'deleted')
       or exists(select 1 from public.workshop_bookings)
       or exists(select 1 from public.vehicle_work_items)
       or exists(select 1 from public.pdc_email_monitor_pilot where enabled or outbound_email_enabled
                 or automatic_rule_application or automatic_authenticated_jobcards)
       or exists(select 1 from public.monitored_mailboxes where active)
       or exists(select 1 from public.pdc_monitor_stage_activation_writers where active and revoked_at is null)
       or exists(select 1 from public.pdc_email_monitor_status
                 where running_status<>'stopped' or gateway_instance_id is not null) then
      raise exception 'PDC_348_REPLAY_POSTCONDITION_DRIFT' using errcode='55000';
    end if;
    return public.navision_backend_response(true,'replayed',
      v_existing.cleanse_result||jsonb_build_object('changed',false,'receipt_id',v_existing.receipt_id));
  end if;

  -- Exact immutable recovery artifact coverage must still equal live contained state.
  if (select count(*) from public.vehicles)<>1730
     or (select count(*) from public.workshop_bookings)<>1100
     or (select count(*) from public.workshop_booking_assignments)<>0
     or (select count(*) from public.workshop_transition_authorizations)<>0
     or (select count(*) from public.workshop_booking_history)<>4979
     or (select count(*) from public.workshop_booking_move_receipts)<>8
     or (select count(*) from public.workshop_parts_overrides)<>22
     or (select count(*) from public.vehicle_work_items)<>3228
     or (select count(*) from public.vehicle_parts_updates)<>33
     or (select count(*) from public.vehicle_sublet_providers)<>0
     or (select count(*) from public.vehicle_workshop_line_adjustments)<>1483
     or (select count(*) from public.pdc_sublet_bookings)<>0
     or (select count(*) from public.navision_board_activations)<>448 then
    return public.navision_backend_response(false,'backup_live_count_drift');
  end if;
  if exists(select 1 from public.pdc_email_monitor_pilot where enabled or outbound_email_enabled
            or automatic_rule_application or automatic_authenticated_jobcards)
     or exists(select 1 from public.monitored_mailboxes where active)
     or exists(select 1 from public.pdc_monitor_stage_activation_writers where active and revoked_at is null)
     or exists(select 1 from public.pdc_email_monitor_status
               where running_status<>'stopped' or gateway_instance_id is not null) then
    return public.navision_backend_response(false,'containment_required');
  end if;

  v_pre:=jsonb_build_object(
    'vehicles_total',(select count(*) from public.vehicles),
    'operational_vehicles',(select count(*) from public.vehicles where deleted_at is null and board_purged_at is null),
    'visible_operational_vehicles',(select count(*) from public.vehicles where deleted_at is null and board_purged_at is null and visible_on_board),
    'workshop_bookings',(select count(*) from public.workshop_bookings),
    'vehicle_work_items',(select count(*) from public.vehicle_work_items),
    'source_counts',(select coalesce(jsonb_object_agg(source_system,n),'{}'::jsonb)
                     from (select coalesce(source_system,'<null>') source_system,count(*) n
                           from public.vehicles where deleted_at is null and board_purged_at is null
                           group by 1) s)
  );
  v_replay_before:=jsonb_build_object(
    'email_source_claims',(select count(*) from public.pdc_email_source_claims),
    'provider_email_observations',(select count(*) from public.pdc_provider_email_observations),
    'email_intakes',(select count(*) from public.ai_email_intake),
    'telegram_instructions',(select count(*) from public.pdc_auditor_telegram_instructions_225),
    'telegram_deliveries',(select count(*) from public.pdc_auditor_telegram_deliveries_230)
  );

  insert into public.pdc_staging_verified_backup_manifests(
    backup_manifest_sha256,backup_gzip_sha256,raw_bytes,table_counts,verified_by)
  values(v_manifest,v_gzip,v_raw_bytes,jsonb_build_object(
    'vehicles',1730,'workshop_bookings',1100,'workshop_booking_assignments',0,
    'workshop_transition_authorizations',0,'workshop_booking_history',4979,
    'workshop_booking_move_receipts',8,'workshop_parts_overrides',22,
    'vehicle_work_items',3228,'vehicle_parts_updates',33,'vehicle_sublet_providers',0,
    'vehicle_workshop_line_adjustments',1483,'pdc_sublet_bookings',0,
    'navision_board_activations',448,'encrypted_backup_sha256',v_encrypted),v_actor_id)
  on conflict (backup_manifest_sha256) do nothing;

  if not exists(select 1 from public.pdc_staging_verified_backup_manifests
                where backup_manifest_sha256=v_manifest
                  and backup_gzip_sha256=v_gzip and raw_bytes=v_raw_bytes) then
    raise exception 'PDC_348_BACKUP_MANIFEST_REGISTRATION_FAILED' using errcode='55000';
  end if;

  v_result:=public.purge_all_staging_board_vehicles(
    'REMOVE ALL STAGING BOARD VEHICLES FOR BULK UPLOAD TEST',v_manifest);
  if not coalesce((v_result->>'ok')::boolean,false) then
    raise exception 'PDC_348_CLEANSE_FAILED:%',v_result using errcode='55000';
  end if;

  v_post:=jsonb_build_object(
    'vehicles_total',(select count(*) from public.vehicles),
    'operational_vehicles',(select count(*) from public.vehicles where deleted_at is null and board_purged_at is null),
    'visible_operational_vehicles',(select count(*) from public.vehicles where deleted_at is null and board_purged_at is null and visible_on_board),
    'workshop_bookings',(select count(*) from public.workshop_bookings),
    'vehicle_work_items',(select count(*) from public.vehicle_work_items),
    'pilot_enabled',(select enabled from public.pdc_email_monitor_pilot where singleton),
    'active_mailboxes',(select count(*) from public.monitored_mailboxes where active),
    'active_monitor_writers',(select count(*) from public.pdc_monitor_stage_activation_writers where active and revoked_at is null),
    'running_status',(select running_status from public.pdc_email_monitor_status where singleton)
  );
  v_replay_after:=jsonb_build_object(
    'email_source_claims',(select count(*) from public.pdc_email_source_claims),
    'provider_email_observations',(select count(*) from public.pdc_provider_email_observations),
    'email_intakes',(select count(*) from public.ai_email_intake),
    'telegram_instructions',(select count(*) from public.pdc_auditor_telegram_instructions_225),
    'telegram_deliveries',(select count(*) from public.pdc_auditor_telegram_deliveries_230)
  );
  if (v_post->>'operational_vehicles')::integer<>0
     or (v_post->>'visible_operational_vehicles')::integer<>0
     or (v_post->>'workshop_bookings')::integer<>0
     or (v_post->>'vehicle_work_items')::integer<>0
     or (v_post->>'pilot_enabled')::boolean
     or (v_post->>'active_mailboxes')::integer<>0
     or (v_post->>'active_monitor_writers')::integer<>0
     or v_post->>'running_status'<>'stopped'
     or v_replay_before is distinct from v_replay_after then
    raise exception 'PDC_348_CLEANSE_POSTCONDITION_FAILED' using errcode='55000';
  end if;

  insert into public.pdc_staging_cleanse_receipts_348(
    receipt_id,project_ref,action_key,backup_manifest_sha256,encrypted_backup_sha256,
    backup_gzip_sha256,backup_raw_bytes,applied_by,applied_by_email,
    prestate,poststate,replay_evidence_before,replay_evidence_after,cleanse_result)
  values(gen_random_uuid(),'cdsmnqxtyyoeoznmbidd','craig-staging-board-cleanse-20260824',
    v_manifest,v_encrypted,v_gzip,v_raw_bytes,v_actor_id,v_actor_email,
    v_pre,v_post,v_replay_before,v_replay_after,v_result->'data')
  returning receipt_id into v_existing.receipt_id;
  return public.navision_backend_response(true,'staging_board_cleanse_completed',
    (v_result->'data')||jsonb_build_object('receipt_id',v_existing.receipt_id,'changed',true,
      'replay_evidence_preserved',true,'encrypted_backup_sha256',v_encrypted));
end
$$;
revoke all on function public.pdc_admin_run_staging_cleanse_348()
  from public,anon,authenticated,service_role;
grant execute on function public.pdc_admin_run_staging_cleanse_348() to authenticated;

-- Retire the broader predecessor entry point. The successor invokes it only as
-- its SECURITY DEFINER owner after exact actor/backup/containment checks.
revoke execute on function public.purge_all_staging_board_vehicles(text,text)
  from authenticated,service_role,anon,public;

insert into supabase_migrations.schema_migrations(version,name,statements)
values('20260824110000','348_one_shot_staging_board_cleanse',array[
  'Exact staging sentinel and containment predecessor; Production sentinel forbidden',
  'Exact encrypted recovery artifact hashes, byte count and thirteen-table live coverage',
  'Administrator-only zero-argument one-shot cleanse using existing fixed-catalog purge internals',
  'Preserve immutable replay evidence and reject any pre/post evidence drift',
  'Retire broader legacy purge entry point and expose no generic DML'
]);
notify pgrst,'reload schema';
commit;
