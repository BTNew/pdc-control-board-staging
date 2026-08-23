-- STAGING ONLY 351: contain orphan active Navision Board activations that
-- have no canonical vehicle and therefore cannot be retired per vehicle.
begin;
set local lock_timeout='10s';
set local statement_timeout='600s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-351-orphan-navision-activation-cleanse',0));

do $guard$
begin
  if not public.pdc_monitor_staging_guard()
     or (select count(*) from public.pdc_staging_environment_sentinel
         where singleton and project_ref='cdsmnqxtyyoeoznmbidd')<>1
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or not exists(select 1 from supabase_migrations.schema_migrations
                   where version='20260824113000' and name='350_cleanse_stale_predecessor_projections')
     or exists(select 1 from public.pdc_staging_cleanse_receipts_348)
     or exists(select 1 from supabase_migrations.schema_migrations
               where version='20260824114000') then
    raise exception 'PDC_351_STAGING_PREDECESSOR_OR_FAILED_ATTEMPT_MISMATCH' using errcode='55000';
  end if;
end
$guard$;

create or replace function public.pdc_admin_run_staging_cleanse_348()
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
  v_stale_bookings integer:=0;
  v_stale_work_items integer:=0;
  v_stale_parts integer:=0;
  v_stale_sublet_providers integer:=0;
  v_stale_sublet_bookings integer:=0;
  v_stale_line_adjustments integer:=0;
  v_stale_navision_activations integer:=0;
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

  -- The 2026-08-18 purge left operational children later recreated against
  -- already-purged vehicles. Remove only those exact stale projections first;
  -- all rows are covered by the bound encrypted backup above.
  delete from public.workshop_bookings b using public.vehicles v
   where b.vehicle_id=v.id and v.board_purged_at is not null and v.deleted_at is not null
     and v.lifecycle_state='deleted' and not v.visible_on_board;
  get diagnostics v_stale_bookings=row_count;
  delete from public.vehicle_work_items x using public.vehicles v
   where x.vehicle_id=v.id and v.board_purged_at is not null and v.deleted_at is not null
     and v.lifecycle_state='deleted' and not v.visible_on_board;
  get diagnostics v_stale_work_items=row_count;
  delete from public.vehicle_parts_updates x using public.vehicles v
   where x.vehicle_id=v.id and v.board_purged_at is not null and v.deleted_at is not null
     and v.lifecycle_state='deleted' and not v.visible_on_board;
  get diagnostics v_stale_parts=row_count;
  delete from public.vehicle_sublet_providers x using public.vehicles v
   where x.vehicle_id=v.id and v.board_purged_at is not null and v.deleted_at is not null
     and v.lifecycle_state='deleted' and not v.visible_on_board;
  get diagnostics v_stale_sublet_providers=row_count;
  delete from public.pdc_sublet_bookings x using public.vehicles v
   where x.vehicle_id=v.id and v.board_purged_at is not null and v.deleted_at is not null
     and v.lifecycle_state='deleted' and not v.visible_on_board;
  get diagnostics v_stale_sublet_bookings=row_count;
  update public.vehicle_workshop_line_adjustments x
     set active=false,updated_at=clock_timestamp(),updated_by=v_actor_id
    from public.vehicles v where x.vehicle_id=v.id and x.active
     and v.board_purged_at is not null and v.deleted_at is not null
     and v.lifecycle_state='deleted' and not v.visible_on_board;
  get diagnostics v_stale_line_adjustments=row_count;
  -- All active Board activations are operational projection state. Thirteen
  -- legacy rows have no canonical vehicle and cannot be reached per vehicle.
  -- The bound backup covers the complete 448-row activation table.
  update public.navision_board_activations x
     set active=false,completed_at=coalesce(completed_at,clock_timestamp()),
         completion_reason=coalesce(completion_reason,'Staging board cleanse activation containment'),
         updated_at=clock_timestamp()
   where x.active;
  get diagnostics v_stale_navision_activations=row_count;

  v_result:=public.purge_all_staging_board_vehicles(
    'REMOVE ALL STAGING BOARD VEHICLES FOR BULK UPLOAD TEST',v_manifest);
  if not coalesce((v_result->>'ok')::boolean,false) then
    raise exception 'PDC_348_CLEANSE_FAILED:%',v_result using errcode='55000';
  end if;
  v_result:=jsonb_set(v_result,'{data,stale_predecessor_cleanup}',jsonb_build_object(
    'workshop_bookings',v_stale_bookings,'vehicle_work_items',v_stale_work_items,
    'vehicle_parts_updates',v_stale_parts,'vehicle_sublet_providers',v_stale_sublet_providers,
    'pdc_sublet_bookings',v_stale_sublet_bookings,'line_adjustments_deactivated',v_stale_line_adjustments,
    'navision_activations_deactivated',v_stale_navision_activations),true);

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

insert into supabase_migrations.schema_migrations(version,name,statements)
values('20260824114000','351_cleanse_orphan_navision_activations',array[
  'Require exact staging target, containment and zero committed cleanse receipts',
  'Deactivate complete backup-covered active Navision Board projection including orphan canonical IDs',
  'Retain fixed-catalog per-vehicle purge, replay-evidence equality and zero-state postconditions'
]);
notify pgrst,'reload schema';
commit;
