begin;
set local lock_timeout='10s';
set local statement_timeout='300s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-154-monitor-updates-board-purge',0));

do $guard$
begin
 if to_regclass('public.pdc_staging_environment_sentinel') is null
    or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
    or to_regclass('public.pdc_production_environment_sentinel') is not null
    or not exists(select 1 from supabase_migrations.schema_migrations where version='153' and name='planner_operation_estimate_release_review_remediation')
    or exists(select 1 from supabase_migrations.schema_migrations where version='154') then
  raise exception 'PDC_154_STAGING_OR_LEDGER_MISMATCH' using errcode='55000';
 end if;
end
$guard$;

-- Reconciliation is trigger-only and revoked. It temporarily assumes an existing
-- Workshop administrator solely so the protected booking/assignment triggers can
-- validate a monitor Viewer import. The original monitor identity remains explicit
-- in immutable history metadata. Any overlap or lifecycle error aborts the complete
-- email import transaction.
create or replace function public.workshop_sync_vehicle_stage_booking_duration(p_vehicle_id uuid,p_stage_code text,p_reason text)
returns integer language plpgsql security definer set search_path=pg_catalog,public,extensions as $sync$
declare
 v_stage text:=public.workshop_canonical_stage_code(p_stage_code);
 v_booking public.workshop_bookings%rowtype;
 v_minutes integer;v_end timestamptz;v_before jsonb;v_after jsonb;v_count integer:=0;v_id uuid;
 v_original_claims text:=current_setting('request.jwt.claims',true);
 v_initiator_uid uuid:=auth.uid();v_initiator_email text:=public.current_actor_email();
 v_system_actor uuid;v_system_email text;
begin
 if p_vehicle_id is null or v_stage is null then return 0; end if;
 select r.auth_user_id,r.email into v_system_actor,v_system_email
 from public.pdc_user_roles r join auth.users u on u.id=r.auth_user_id
 where r.active and r.account_status='approved' and r.role='administrator' and r.auth_user_id is not null
 order by r.created_at,r.id limit 1;
 if v_system_actor is null then raise exception 'PDC_154_WORKSHOP_SYSTEM_ACTOR_MISSING' using errcode='55000'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',v_system_actor,'email',v_system_email,'role','authenticated')::text,true);
 perform pg_advisory_xact_lock(hashtextextended('pdc:workshop:estimate-sync:'||p_vehicle_id::text,0));
 for v_id in select distinct b.bay_id from public.workshop_bookings b join public.workshop_stages s on s.id=b.stage_id
   where b.vehicle_id=p_vehicle_id and b.deleted_at is null and b.status::text in('queued','planned','started','stoppage')
     and public.workshop_canonical_stage_code(s.code)=v_stage order by b.bay_id loop
  perform pg_advisory_xact_lock(hashtextextended('pdc:workshop:bay:'||v_id::text,0));
 end loop;
 for v_id in select distinct a.technician_id from public.workshop_booking_assignments a join public.workshop_bookings b on b.id=a.booking_id
   join public.workshop_stages s on s.id=b.stage_id where b.vehicle_id=p_vehicle_id and b.deleted_at is null
   and b.status::text in('queued','planned','started','stoppage') and a.released_at is null
   and public.workshop_canonical_stage_code(s.code)=v_stage order by a.technician_id loop
  perform pg_advisory_xact_lock(hashtextextended('pdc:workshop:technician:'||v_id::text,0));
 end loop;
 for v_booking in select b.* from public.workshop_bookings b join public.workshop_stages s on s.id=b.stage_id
   where b.vehicle_id=p_vehicle_id and b.deleted_at is null and b.status::text in('queued','planned','started','stoppage')
     and public.workshop_canonical_stage_code(s.code)=v_stage order by b.scheduled_start_at,b.id for update of b loop
  v_minutes:=coalesce(greatest(60,round(public.workshop_vehicle_stage_estimated_hours(p_vehicle_id,v_stage)*60)::integer),60);
  v_end:=public.workshop_add_operational_minutes(v_booking.scheduled_start_at,v_minutes);
  if v_booking.default_duration_minutes is distinct from v_minutes or v_booking.scheduled_end_at is distinct from v_end then
   v_before:=public.workshop_booking_snapshot(v_booking.id);
   update public.workshop_bookings set default_duration_minutes=v_minutes,scheduled_end_at=v_end,version=version+1 where id=v_booking.id;
   update public.workshop_booking_assignments set scheduled_start_at=v_booking.scheduled_start_at,scheduled_end_at=v_end
    where booking_id=v_booking.id and released_at is null;
   v_after:=public.workshop_booking_snapshot(v_booking.id);
   insert into public.workshop_booking_history(booking_id,event_type,before_data,after_data,metadata,actor_user_id,actor_email)
   values(v_booking.id,'operation_estimate_duration_reconciled',v_before,v_after,
    jsonb_build_object('system_reconciliation',true,'source',coalesce(p_reason,'operation_estimate_change'),'stage_code',v_stage,
      'duration_minutes',v_minutes,'initiator_auth_uid',v_initiator_uid,'initiator_email',v_initiator_email),v_system_actor,v_system_email);
   v_count:=v_count+1;
  end if;
 end loop;
 perform set_config('request.jwt.claims',coalesce(v_original_claims,''),true);
 return v_count;
exception when others then
 perform set_config('request.jwt.claims',coalesce(v_original_claims,''),true);
 raise;
end
$sync$;
revoke all on function public.workshop_sync_vehicle_stage_booking_duration(uuid,text,text) from public,anon,authenticated,service_role;

-- Migration 153's initial deferred operation trigger referenced a DTO-only field.
-- Source rows store work_key; normalize it through the canonical stage mapper.
create or replace function public.workshop_reconcile_operation_line_booking_duration()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,extensions as $trigger$
begin
 if tg_op in('UPDATE','DELETE') and (tg_op='DELETE' or old.vehicle_id is distinct from new.vehicle_id or old.work_key is distinct from new.work_key or old.estimated_hours is distinct from new.estimated_hours) then
  perform public.workshop_sync_vehicle_stage_booking_duration(old.vehicle_id,public.workshop_stage_code_for_work_key(old.work_key),'operation_line_'||lower(tg_op));
 end if;
 if tg_op in('UPDATE','INSERT') and (tg_op='INSERT' or new.vehicle_id is distinct from old.vehicle_id or new.work_key is distinct from old.work_key or new.estimated_hours is distinct from old.estimated_hours) then
  perform public.workshop_sync_vehicle_stage_booking_duration(new.vehicle_id,public.workshop_stage_code_for_work_key(new.work_key),'operation_line_'||lower(tg_op));
 end if;
 return null;
end
$trigger$;
revoke all on function public.workshop_reconcile_operation_line_booking_duration() from public,anon,authenticated,service_role;

-- Receipt-bound status-only Parts completion for the pdc-monitor Viewer. This is
-- monotonic: it can complete Parts on an active vehicle but can never reopen work,
-- create bookings, change location, or alter canonical source evidence.
create or replace function public.apply_pdc_authenticated_parts_completion(
 p_source_hash text,p_source_uid text,p_expected_vehicle_version integer,p_evidence text
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $parts$
declare
 v_actor uuid:=auth.uid();v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
 v_hash text:=lower(btrim(coalesce(p_source_hash,'')));v_uid text:=btrim(coalesce(p_source_uid,''));
 v_evidence text:=btrim(coalesce(p_evidence,''));v_receipt public.pdc_authenticated_email_import_receipts%rowtype;
 v_vehicle public.vehicles%rowtype;v_work public.vehicle_work_items%rowtype;v_parts public.vehicle_parts_updates%rowtype;v_now timestamptz:=clock_timestamp();
 v_original_claims text:=current_setting('request.jwt.claims',true);v_system_actor uuid;v_system_email text;
begin
 if not public.pdc_monitor_staging_guard() or v_actor is null or v_email='' or v_hash!~'^[a-f0-9]{64}$'
    or length(v_uid) not between 1 and 100 or length(v_evidence) not between 8 and 500 then
  return public.navision_backend_response(false,'invalid_or_unauthorized');
 end if;
 perform 1 from public.pdc_user_roles r where r.email=v_email and (r.auth_user_id is null or r.auth_user_id=v_actor)
   and r.role='viewer' and r.active and r.account_status='approved' for share;
 if not found then return public.navision_backend_response(false,'unauthorized'); end if;
 perform 1 from public.pdc_monitor_stage_activation_writers w where w.user_id=v_actor and w.active and w.revoked_at is null for share;
 if not found then return public.navision_backend_response(false,'unauthorized'); end if;
 perform pg_advisory_xact_lock(hashtextextended('pdc-email-parts-completion:'||v_hash,0));
 select * into v_receipt from public.pdc_authenticated_email_import_receipts
 where actor_id=v_actor and source_hash=v_hash and source_uid=v_uid for update;
 if not found then return public.navision_backend_response(false,'source_receipt_not_found'); end if;
 perform 1 from public.pdc_email_source_claims c join public.pdc_ai_intake_proposals p on p.proposal_id::text=c.proposal_ref
 where c.source_hash=v_hash and p.source_hash=v_hash and p.source_uid=v_uid
   and p.evidence_hash=v_receipt.evidence_hash and lower(p.sender_address)=lower(v_receipt.sender_address)
   and p.status='applied' and jsonb_typeof(p.authentication)='object' for share of c,p;
 if not found then return public.navision_backend_response(false,'source_proposal_binding_mismatch'); end if;
 select * into v_vehicle from public.vehicles where id=v_receipt.vehicle_id for update;
 if not found or v_vehicle.lifecycle_state<>'active' or v_vehicle.deleted_at is not null then
  return public.navision_backend_response(false,'operational_vehicle_inactive');
 end if;
 if p_expected_vehicle_version is null or v_vehicle.version<>p_expected_vehicle_version then
  return public.navision_backend_response(false,'vehicle_version_conflict',jsonb_build_object('current_version',v_vehicle.version));
 end if;
 select * into v_work from public.vehicle_work_items where vehicle_id=v_vehicle.id and work_key='parts' for update;
 select * into v_parts from public.vehicle_parts_updates where vehicle_id=v_vehicle.id order by updated_at desc,id desc limit 1 for update;
 if coalesce(v_work.completed,false) and coalesce(v_parts.parts_received,false) then
  return public.navision_backend_response(true,'replayed',jsonb_build_object('vehicle_id',v_vehicle.id,'vehicle_version',v_vehicle.version,'changed',false));
 end if;
 select r.auth_user_id,r.email into v_system_actor,v_system_email from public.pdc_user_roles r join auth.users u on u.id=r.auth_user_id
 where r.active and r.account_status='approved' and r.role='administrator' and r.auth_user_id is not null order by r.created_at,r.id limit 1;
 if v_system_actor is null then raise exception 'PDC_154_PARTS_SYSTEM_ACTOR_MISSING' using errcode='55000'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',v_system_actor,'email',v_system_email,'role','authenticated')::text,true);
 insert into public.vehicle_work_items(vehicle_id,work_key,required,completed,completed_by,completed_at,notes,updated_at)
 values(v_vehicle.id,'parts',true,true,v_actor,v_now,'Completed from authenticated retained email evidence',v_now)
 on conflict(vehicle_id,work_key) do update set required=true,completed=true,completed_by=v_actor,completed_at=v_now,
  notes='Completed from authenticated retained email evidence',updated_at=v_now;
 insert into public.vehicle_parts_updates(vehicle_id,parts_required,parts_ordered,parts_received,parts_stoppage,parts_stoppage_reason,worst_eta,updated_by,updated_at)
 values(v_vehicle.id,true,true,true,false,null,v_parts.worst_eta,v_actor,v_now);
 update public.vehicles set version=version+1,updated_at=v_now where id=v_vehicle.id returning * into v_vehicle;
 insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
 values('update'::public.audit_action,'vehicle_work_items',v_vehicle.id,v_vehicle.id,v_actor,v_email,
  case when v_work.id is null then null else to_jsonb(v_work) end,
  (select to_jsonb(w) from public.vehicle_work_items w where w.vehicle_id=v_vehicle.id and w.work_key='parts'),
  jsonb_build_object('source','authenticated_email_parts_completion_154','source_hash',v_hash,'source_uid',v_uid,'evidence',v_evidence,'monotonic',true));
 update public.pdc_email_vehicle_revision set revision=revision+1,updated_at=v_now where singleton;
 perform set_config('request.jwt.claims',coalesce(v_original_claims,''),true);
 return public.navision_backend_response(true,'parts_completed',jsonb_build_object('vehicle_id',v_vehicle.id,'vehicle_version',v_vehicle.version,'changed',true));
exception when others then
 perform set_config('request.jwt.claims',coalesce(v_original_claims,''),true);
 raise;
end
$parts$;
revoke all on function public.apply_pdc_authenticated_parts_completion(text,text,integer,text) from public,anon,authenticated,service_role;
grant execute on function public.apply_pdc_authenticated_parts_completion(text,text,integer,text) to authenticated;

alter table public.vehicles add column if not exists board_purged_at timestamptz;
alter table public.vehicles add column if not exists board_purge_reason text;
alter table public.vehicles add column if not exists board_purged_by uuid references auth.users(id) on delete restrict;

create or replace function public.purge_vehicle_from_board(p_vehicle_id uuid,p_expected_version integer,p_reason text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $purge$
declare v_before public.vehicles%rowtype;v_after public.vehicles%rowtype;v_actor uuid:=auth.uid();v_email text:=public.current_actor_email();v_now timestamptz:=clock_timestamp();
begin
 if public.current_pdc_user_role()::text<>'administrator' then return public.navision_backend_response(false,'administrator_required'); end if;
 if p_vehicle_id is null or p_expected_version is null or length(btrim(coalesce(p_reason,''))) not between 8 and 300 then
  return public.navision_backend_response(false,'invalid_input');
 end if;
 perform pg_advisory_xact_lock(hashtextextended('pdc:board-purge:'||p_vehicle_id::text,0));
 select * into v_before from public.vehicles where id=p_vehicle_id for update;
 if not found then return public.navision_backend_response(false,'vehicle_not_found'); end if;
 if v_before.version<>p_expected_version then return public.navision_backend_response(false,'vehicle_version_conflict',jsonb_build_object('current_version',v_before.version)); end if;
 delete from public.workshop_bookings where vehicle_id=p_vehicle_id;
 delete from public.vehicle_workshop_line_adjustments where vehicle_id=p_vehicle_id;
 delete from public.vehicle_parts_updates where vehicle_id=p_vehicle_id;
 delete from public.vehicle_sublet_providers where vehicle_id=p_vehicle_id;
 delete from public.vehicle_work_items where vehicle_id=p_vehicle_id;
 update public.navision_board_activations set active=false,completed_at=v_now,completion_reason='Staging board purge',updated_at=v_now
  where canonical_vehicle_id=p_vehicle_id and active;
 update public.vehicles set lifecycle_state='deleted',visible_on_board=false,current_location='Other',pmb_stage=null,pmb_bay_stage=null,
  pmb_bay_number=null,pmb_key_tag=null,active_workshop_booking_id=null,workshop_status='queued',workshop_status_updated_at=null,
  workshop_status_updated_by=null,qc_completed_at=null,qc_completed_by=null,rft_transferred_at=null,rft_collected_at=null,
  rft_collected_by=null,deleted_at=v_now,deleted_reason=btrim(p_reason),board_purged_at=v_now,board_purge_reason=btrim(p_reason),
  board_purged_by=v_actor,version=version+1,updated_by=v_actor,updated_at=v_now where id=p_vehicle_id returning * into v_after;
 insert into public.deleted_completed_vehicles(vehicle_id,final_state,snapshot,reason,acted_by)
 values(p_vehicle_id,'deleted',to_jsonb(v_after),btrim(p_reason),v_actor);
 insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
 values('delete'::public.audit_action,'vehicles',p_vehicle_id,p_vehicle_id,v_actor,v_email,to_jsonb(v_before),to_jsonb(v_after),
  jsonb_build_object('source','complete_board_purge_154','hard_database_delete',false,'immutable_evidence_retained',true,'mutable_board_state_removed',true));
 update public.pdc_email_vehicle_revision set revision=revision+1,updated_at=v_now where singleton;
 update public.navision_backend_revision set revision=revision+1,updated_at=v_now where singleton;
 perform public.workshop_bump_revision();
 return public.navision_backend_response(true,'vehicle_purged_from_board',jsonb_build_object('vehicle_id',p_vehicle_id,'vehicle_version',v_after.version));
end
$purge$;
revoke all on function public.purge_vehicle_from_board(uuid,integer,text) from public,anon,authenticated,service_role;
grant execute on function public.purge_vehicle_from_board(uuid,integer,text) to authenticated;

create or replace function public.purge_all_staging_board_vehicles(p_confirmation text,p_backup_manifest_sha256 text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $all$
declare v record;v_result jsonb;v_count integer:=0;v_before integer;v_reason text:='Staging board cleared for bulk upload test';
begin
 if not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
    or to_regclass('public.pdc_production_environment_sentinel') is not null then raise exception 'PDC_154_NOT_STAGING' using errcode='55000'; end if;
 if public.current_pdc_user_role()::text<>'administrator' then return public.navision_backend_response(false,'administrator_required'); end if;
 if p_confirmation<>'REMOVE ALL STAGING BOARD VEHICLES FOR BULK UPLOAD TEST'
    or coalesce(p_backup_manifest_sha256,'')!~'^[a-f0-9]{64}$' then return public.navision_backend_response(false,'confirmation_or_backup_invalid'); end if;
 perform pg_advisory_xact_lock(hashtextextended('pdc-staging-purge-all-board-vehicles-154',0));
 select count(*) into v_before from public.vehicles where board_purged_at is null;
 for v in select id,version from public.vehicles order by id for update loop
  v_result:=public.purge_vehicle_from_board(v.id,v.version,v_reason||' · backup '||p_backup_manifest_sha256);
  if coalesce((v_result->>'ok')::boolean,false) is not true then raise exception 'PDC_154_PURGE_FAILED:%:%',v.id,v_result using errcode='55000'; end if;
  v_count:=v_count+1;
 end loop;
 if exists(select 1 from public.vehicles where visible_on_board or deleted_at is null or lifecycle_state<>'deleted' or board_purged_at is null)
    or exists(select 1 from public.workshop_bookings) or exists(select 1 from public.vehicle_work_items)
    or exists(select 1 from public.vehicle_parts_updates) or exists(select 1 from public.vehicle_workshop_line_adjustments) then
  raise exception 'PDC_154_PURGE_POSTCONDITION_FAILED' using errcode='55000';
 end if;
 return public.navision_backend_response(true,'staging_board_cleared',jsonb_build_object('vehicles_processed',v_count,'previously_unpurged',v_before,
  'visible_vehicles',0,'bookings',0,'work_items',0,'parts_updates',0,'line_adjustments',0,'backup_manifest_sha256',p_backup_manifest_sha256));
end
$all$;
revoke all on function public.purge_all_staging_board_vehicles(text,text) from public,anon,authenticated,service_role;
grant execute on function public.purge_all_staging_board_vehicles(text,text) to authenticated;

insert into supabase_migrations.schema_migrations(version,name,statements) values('154','monitor_updates_and_complete_board_purge',array[
 'allow receipt-bound Viewer operation imports to reconcile active planner intervals under audited system authority',
 'add monotonic retained-email Parts completion contract',
 'add administrator complete board purge while retaining immutable source and audit evidence',
 'add guarded staging all-vehicle clear for bulk upload testing']);

commit;
