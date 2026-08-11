begin;
set local lock_timeout='10s';
set local statement_timeout='300s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-156-review-remediation',0));

do $guard$ begin
 if not public.pdc_monitor_staging_guard()
   or not exists(select 1 from supabase_migrations.schema_migrations where version='154' and name='monitor_updates_and_complete_board_purge')
   or not exists(select 1 from supabase_migrations.schema_migrations where version='155' and name='navision_activation_board_purge_order')
   or to_regclass('public.pdc_sublet_bookings') is null then
  raise exception 'PDC_MIGRATION_156_STAGING_OR_DEPENDENCY_MISMATCH';
 end if;
 if exists(select 1 from supabase_migrations.schema_migrations where version='156') then
  raise exception 'PDC_MIGRATION_156_ALREADY_APPLIED';
 end if;
end $guard$;

-- Retain planner reconciliation history when the mutable booking is purged.
alter table public.workshop_booking_history add column if not exists vehicle_id uuid references public.vehicles(id) on delete restrict;
alter table public.workshop_booking_history add column if not exists purged_booking_id uuid;
update public.workshop_booking_history h set vehicle_id=b.vehicle_id
from public.workshop_bookings b where b.id=h.booking_id and h.vehicle_id is null;
update public.workshop_booking_history set purged_booking_id=booking_id where purged_booking_id is null;
do $history$ begin
 if exists(select 1 from public.workshop_booking_history where vehicle_id is null or purged_booking_id is null) then
  raise exception 'PDC_156_HISTORY_VEHICLE_BACKFILL_FAILED';
 end if;
end $history$;
alter table public.workshop_booking_history alter column vehicle_id set not null;
alter table public.workshop_booking_history alter column purged_booking_id set not null;
alter table public.workshop_booking_history alter column booking_id drop not null;
alter table public.workshop_booking_history drop constraint if exists workshop_booking_history_booking_id_fkey;
alter table public.workshop_booking_history add constraint workshop_booking_history_booking_id_fkey
 foreign key(booking_id) references public.workshop_bookings(id) on delete set null;
create index if not exists workshop_booking_history_vehicle_created_idx on public.workshop_booking_history(vehicle_id,created_at desc);
create or replace function public.workshop_booking_history_bind_vehicle()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $trigger$
begin
 if new.vehicle_id is null and new.booking_id is not null then
  select b.vehicle_id into new.vehicle_id from public.workshop_bookings b where b.id=new.booking_id;
 end if;
 new.purged_booking_id:=coalesce(new.purged_booking_id,new.booking_id);
 if new.vehicle_id is null or new.purged_booking_id is null then raise exception 'PDC_WORKSHOP_HISTORY_IDENTITY_REQUIRED' using errcode='23502'; end if;
 return new;
end $trigger$;
revoke all on function public.workshop_booking_history_bind_vehicle() from public,anon,authenticated,service_role;
drop trigger if exists workshop_booking_history_bind_vehicle on public.workshop_booking_history;
create trigger workshop_booking_history_bind_vehicle before insert on public.workshop_booking_history
for each row execute function public.workshop_booking_history_bind_vehicle();

-- Use the same advisory-lock namespace as normal planner RPCs.
create or replace function public.workshop_sync_vehicle_stage_booking_duration(p_vehicle_id uuid,p_stage_code text,p_reason text)
returns integer language plpgsql security definer set search_path=pg_catalog,public,extensions as $sync$
declare
 v_stage text:=public.workshop_canonical_stage_code(p_stage_code);
 v_booking public.workshop_bookings%rowtype;
 v_minutes integer;v_end timestamptz;v_before jsonb;v_after jsonb;v_count integer:=0;
 v_original_claims text:=current_setting('request.jwt.claims',true);
 v_initiator_uid uuid:=auth.uid();v_initiator_email text:=public.current_actor_email();
 v_system_actor uuid;v_system_email text;
begin
 if p_vehicle_id is null or v_stage is null then return 0; end if;
 select r.auth_user_id,r.email into v_system_actor,v_system_email
 from public.pdc_user_roles r join auth.users u on u.id=r.auth_user_id
 where r.active and r.account_status='approved' and r.role='administrator' and r.auth_user_id is not null
 order by r.created_at,r.id limit 1;
 if v_system_actor is null then raise exception 'PDC_156_WORKSHOP_SYSTEM_ACTOR_MISSING' using errcode='55000'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',v_system_actor,'email',v_system_email,'role','authenticated')::text,true);
 perform pg_advisory_xact_lock(hashtextextended('pdc:workshop:estimate-sync:'||p_vehicle_id::text,0));
 -- Wait for every in-flight booking/assignment writer before taking the
 -- candidate snapshot, then prevent move/create/cascade membership changes
 -- until reconciliation commits. EXCLUSIVE also conflicts with ROW SHARE
 -- (SELECT FOR UPDATE), avoiding target-first cascade row-lock inversions.
 lock table public.workshop_bookings,public.workshop_booking_assignments in exclusive mode;
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

alter table public.pdc_authenticated_email_import_receipts
 add column backend_record_version integer check(backend_record_version is null or backend_record_version>=1);

-- Keep the enrolled monitor role functional without granting ordinary mutation authority.
-- The canonical receipt importer now records PARTS scope so completion can be proven later.
do $monitor_contract$
declare
 v_vehicle text;v_operations text;
 v_role text:=$token$r.role='viewer'$token$;
 v_limit text:='jsonb_array_length(v_work)>9';
 v_case text:=$token$when 'sublet' then 'sublet' when 'pitinspection' then 'pitInspection' else null end$token$;
 v_stage_guard text:='if v_work_key is null or not exists(select 1 from public.workshop_stages s where s.work_key=v_work_key and s.active) then';
 v_receipt_columns text:='vin,backend_record_id,vehicle_id,identity_source';
 v_receipt_values text:='v_extracted_vin,v_record.id,v_vehicle.id';
begin
 select pg_get_functiondef('public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamptz,text,jsonb,jsonb)'::regprocedure) into v_vehicle;
 if obj_description('public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamptz,text,jsonb,jsonb)'::regprocedure,'pg_proc') is distinct from
      'Staging v7 Monitor importer: v6 exact retained source/proposal/activation binding; canonical document evidence hash is independently validated and bound immutably by the explicit receipt request hash.'
   or length(v_vehicle)-length(replace(v_vehicle,v_role,''))<>length(v_role)
   or length(v_vehicle)-length(replace(v_vehicle,v_limit,''))<>length(v_limit)
   or length(v_vehicle)-length(replace(v_vehicle,v_case,''))<>2*length(v_case)
   or length(v_vehicle)-length(replace(v_vehicle,v_stage_guard,''))<>length(v_stage_guard)
   or length(v_vehicle)-length(replace(v_vehicle,v_receipt_columns,''))<>length(v_receipt_columns)
   or length(v_vehicle)-length(replace(v_vehicle,v_receipt_values,''))<>length(v_receipt_values)
   or length(v_vehicle)-length(replace(v_vehicle,'pdc_monitor_canonical_stock_import_148',''))<>2*length('pdc_monitor_canonical_stock_import_148')
   or position($cv7$'contract_version',7$cv7$ in v_vehicle)=0
   or position('source_proposal_binding_mismatch' in v_vehicle)=0
   or position('insert into public.vehicles' in lower(v_vehicle))>0
   or position('insert into public.navision_board_activations' in lower(v_vehicle))>0
   or position('update public.navision_board_activations' in lower(v_vehicle))>0
   or position('vehicle_parts_updates' in lower(v_vehicle))>0
   or position('workshop_bookings' in lower(v_vehicle))>0 then
  raise exception 'PDC_156_VEHICLE_IMPORTER_DEFINITION_DRIFT';
 end if;
 v_vehicle:=replace(v_vehicle,v_role,$new$r.role in('viewer','importer')$new$);
 v_vehicle:=replace(v_vehicle,v_limit,'jsonb_array_length(v_work)>10');
 v_vehicle:=replace(v_vehicle,v_case,
  $new$when 'sublet' then 'sublet' when 'pitinspection' then 'pitInspection' when 'parts' then 'PARTS' else null end$new$);
 v_vehicle:=replace(v_vehicle,v_stage_guard,
  $new$if v_work_key is null or (v_work_key<>'PARTS' and not exists(select 1 from public.workshop_stages s where s.work_key=v_work_key and s.active)) then$new$);
 v_vehicle:=replace(v_vehicle,v_receipt_columns,'vin,backend_record_id,backend_record_version,vehicle_id,identity_source');
 v_vehicle:=replace(v_vehicle,v_receipt_values,'v_extracted_vin,v_record.id,v_record.version,v_vehicle.id');
 execute v_vehicle;

 select pg_get_functiondef('public.import_pdc_authenticated_email_operations_with_hours(text,text,jsonb)'::regprocedure) into v_operations;
 if obj_description('public.import_pdc_authenticated_email_operations_with_hours(text,text,jsonb)'::regprocedure,'pg_proc') is distinct from
      'Staging-only enrolled-Viewer typed import of bounded authenticated job-card OP lines, including Parts, with job-card/AI hour provenance; job-card hours win; never books or completes work.'
   or length(v_operations)-length(replace(v_operations,v_role,''))<>length(v_role)
   or length(v_operations)-length(replace(v_operations,'pdc_authenticated_email_operation_hours_145',''))<>3*length('pdc_authenticated_email_operation_hours_145')
   or position('insert into public.workshop_bookings' in lower(v_operations))>0
   or position('update public.workshop_bookings' in lower(v_operations))>0
   or position('vehicle_parts_updates' in lower(v_operations))>0 then
  raise exception 'PDC_156_OPERATION_IMPORTER_DEFINITION_DRIFT';
 end if;
 v_operations:=replace(v_operations,v_role,$new$r.role in('viewer','importer')$new$);
 v_operations:=replace(v_operations,'pdc_authenticated_email_operation_hours_145','pdc_authenticated_email_operation_hours_156');
 execute v_operations;
end
$monitor_contract$;
revoke all on function public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamptz,text,jsonb,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamptz,text,jsonb,jsonb) to authenticated;
comment on function public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamptz,text,jsonb,jsonb) is
 'Staging v156 Monitor importer: exact v7 source/proposal/activation binding; enrolled Viewer/Importer only; canonical PARTS scope; no Parts completion, booking, or location mutation.';
revoke all on function public.import_pdc_authenticated_email_operations_with_hours(text,text,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.import_pdc_authenticated_email_operations_with_hours(text,text,jsonb) to authenticated;
comment on function public.import_pdc_authenticated_email_operations_with_hours(text,text,jsonb) is
 'Staging v156 enrolled Viewer/Importer authenticated operation-hour import; canonical receipt/source binding; never books or completes work.';

-- Applied proposal evidence can authorize Parts completion, so its evidence-bearing
-- fields are immutable after application even to privileged application roles.
create or replace function public.pdc_protect_applied_proposal_evidence()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $trigger$
begin
 if tg_op='DELETE' then
  if old.status='applied' then raise exception 'PDC_APPLIED_PROPOSAL_EVIDENCE_IMMUTABLE' using errcode='55000'; end if;
  return old;
 end if;
 if old.status='applied' and (
   new.source_hash is distinct from old.source_hash or new.evidence_hash is distinct from old.evidence_hash
   or new.source_uid is distinct from old.source_uid or new.sender_address is distinct from old.sender_address
   or new.authentication is distinct from old.authentication or new.source_received_at is distinct from old.source_received_at
   or new.subject is distinct from old.subject or new.action_type is distinct from old.action_type
   or new.stock_number is distinct from old.stock_number or new.backend_record_id is distinct from old.backend_record_id
   or new.backend_record_version is distinct from old.backend_record_version or new.observations is distinct from old.observations
   or new.fingerprint is distinct from old.fingerprint or new.status is distinct from old.status) then
  raise exception 'PDC_APPLIED_PROPOSAL_EVIDENCE_IMMUTABLE' using errcode='55000';
 end if;
 return new;
end
$trigger$;
revoke all on function public.pdc_protect_applied_proposal_evidence() from public,anon,authenticated,service_role;
drop trigger if exists pdc_applied_proposal_evidence_immutable on public.pdc_ai_intake_proposals;
create trigger pdc_applied_proposal_evidence_immutable before update or delete on public.pdc_ai_intake_proposals
for each row execute function public.pdc_protect_applied_proposal_evidence();
revoke update,delete on table public.pdc_ai_intake_proposals from service_role;

create or replace function public.pdc_protect_email_source_claim()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $trigger$
begin raise exception 'PDC_EMAIL_SOURCE_CLAIM_IMMUTABLE' using errcode='55000'; end
$trigger$;
revoke all on function public.pdc_protect_email_source_claim() from public,anon,authenticated,service_role;
drop trigger if exists pdc_email_source_claim_immutable on public.pdc_email_source_claims;
create trigger pdc_email_source_claim_immutable before update or delete on public.pdc_email_source_claims
for each row execute function public.pdc_protect_email_source_claim();
revoke update,delete on table public.pdc_email_source_claims from service_role;

-- Viewer Parts completion requires an exact retained Parts-completion assertion and evidence string.
create or replace function public.apply_pdc_authenticated_parts_completion(
 p_source_hash text,p_source_uid text,p_expected_vehicle_version integer,p_evidence text
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $parts$
declare
 v_actor uuid:=auth.uid();v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
 v_hash text:=lower(btrim(coalesce(p_source_hash,'')));v_uid text:=btrim(coalesce(p_source_uid,''));
 v_evidence text:=btrim(coalesce(p_evidence,''));v_receipt public.pdc_authenticated_email_import_receipts%rowtype;
 v_vehicle public.vehicles%rowtype;v_backend public.navision_backend_records%rowtype;v_work public.vehicle_work_items%rowtype;v_parts public.vehicle_parts_updates%rowtype;v_now timestamptz:=clock_timestamp();
 v_original_claims text:=current_setting('request.jwt.claims',true);v_system_actor uuid;v_system_email text;
 v_observations jsonb;v_retained_evidence text;v_parts_asserted boolean:=false;
begin
 if not public.pdc_monitor_staging_guard() or v_actor is null or v_email='' or v_hash!~'^[a-f0-9]{64}$'
    or length(v_uid) not between 1 and 100 or length(v_evidence) not between 8 and 500 then
  return public.navision_backend_response(false,'invalid_or_unauthorized');
 end if;
 perform 1 from public.pdc_user_roles r where r.email=v_email and r.auth_user_id=v_actor
   and r.role in('viewer','importer') and r.active and r.account_status='approved' for share;
 if not found then return public.navision_backend_response(false,'unauthorized'); end if;
 perform 1 from public.pdc_monitor_stage_activation_writers w where w.user_id=v_actor and w.active and w.revoked_at is null for share;
 if not found then return public.navision_backend_response(false,'unauthorized'); end if;
 perform pg_advisory_xact_lock(hashtextextended('pdc-email-parts-completion:'||v_hash,0));
 select * into v_receipt from public.pdc_authenticated_email_import_receipts
 where actor_id=v_actor and source_hash=v_hash and source_uid=v_uid for update;
 if not found then return public.navision_backend_response(false,'source_receipt_not_found'); end if;
 if not exists(select 1 from jsonb_array_elements_text(coalesce(v_receipt.required_work,'[]'::jsonb)) x(work_key)
   where upper(btrim(x.work_key))='PARTS') then
  return public.navision_backend_response(false,'receipt_parts_scope_required');
 end if;
 perform pg_advisory_xact_lock(hashtextextended('navision-backend-store',0));
 select * into v_backend from public.navision_backend_records r where r.id=v_receipt.backend_record_id for share;
 if not found or v_backend.version is distinct from v_receipt.backend_record_version
   or not v_backend.is_current or v_backend.record_status<>'current' then
  return public.navision_backend_response(false,'backend_record_version_not_current');
 end if;
 select p.observations into v_observations
 from public.pdc_email_source_claims c join public.pdc_ai_intake_proposals p on p.proposal_id::text=c.proposal_ref
 where c.source_hash=v_hash and p.source_hash=v_hash and p.source_uid=v_uid
   and lower(p.sender_address)=lower(v_receipt.sender_address)
   and p.status='applied' and p.action_type='board_activate_only'
   and p.backend_record_id=v_receipt.backend_record_id and p.backend_record_version=v_receipt.backend_record_version
   and jsonb_typeof(p.authentication)='object' for share of c,p;
 if not found then return public.navision_backend_response(false,'source_proposal_binding_mismatch'); end if;
 v_retained_evidence:=btrim(coalesce(v_observations->>'parts_completion_evidence',v_observations#>>'{parts,evidence}',''));
 v_parts_asserted:=lower(coalesce(v_observations->>'parts_complete','')) in('true','yes')
   or lower(coalesce(v_observations->>'parts_status',v_observations#>>'{parts,status}','')) in('complete','completed','received');
 if not v_parts_asserted or length(v_retained_evidence) not between 8 and 500 or v_retained_evidence<>v_evidence then
  return public.navision_backend_response(false,'retained_parts_completion_evidence_required');
 end if;
 select * into v_vehicle from public.vehicles where id=v_receipt.vehicle_id for update;
 if not found or v_vehicle.lifecycle_state<>'active' or v_vehicle.deleted_at is not null then
  return public.navision_backend_response(false,'operational_vehicle_inactive');
 end if;
 select * into v_work from public.vehicle_work_items where vehicle_id=v_vehicle.id and work_key='PARTS' for update;
 select * into v_parts from public.vehicle_parts_updates where vehicle_id=v_vehicle.id order by updated_at desc,id desc limit 1 for update;
 if coalesce(v_work.completed,false) and coalesce(v_parts.parts_received,false)
   and exists(select 1 from public.audit_events a where a.vehicle_id=v_vehicle.id and a.table_name='vehicle_work_items'
     and a.metadata->>'source'='authenticated_email_parts_completion_156'
     and a.metadata->>'source_hash'=v_hash and a.metadata->>'source_uid'=v_uid) then
  return public.navision_backend_response(true,'replayed',jsonb_build_object('vehicle_id',v_vehicle.id,'vehicle_version',v_vehicle.version,'changed',false));
 end if;
 if p_expected_vehicle_version is null or v_vehicle.version<>p_expected_vehicle_version then
  return public.navision_backend_response(false,'vehicle_version_conflict',jsonb_build_object('current_version',v_vehicle.version));
 end if;
 select r.auth_user_id,r.email into v_system_actor,v_system_email from public.pdc_user_roles r join auth.users u on u.id=r.auth_user_id
 where r.active and r.account_status='approved' and r.role='administrator' and r.auth_user_id is not null order by r.created_at,r.id limit 1;
 if v_system_actor is null then raise exception 'PDC_156_PARTS_SYSTEM_ACTOR_MISSING' using errcode='55000'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',v_system_actor,'email',v_system_email,'role','authenticated')::text,true);
 insert into public.vehicle_work_items(vehicle_id,work_key,required,completed,completed_by,completed_at,notes,updated_at)
 values(v_vehicle.id,'PARTS',true,true,v_actor,v_now,'Completed from authenticated retained email evidence',v_now)
 on conflict(vehicle_id,work_key) do update set required=true,completed=true,completed_by=v_actor,completed_at=v_now,
  notes='Completed from authenticated retained email evidence',updated_at=v_now;
 insert into public.vehicle_parts_updates(vehicle_id,parts_required,parts_ordered,parts_received,parts_stoppage,parts_stoppage_reason,worst_eta,updated_by,updated_at)
 values(v_vehicle.id,true,true,true,false,null,v_parts.worst_eta,v_actor,v_now);
 update public.vehicles set version=version+1,updated_at=v_now where id=v_vehicle.id returning * into v_vehicle;
 insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
 values('update'::public.audit_action,'vehicle_work_items',v_vehicle.id,v_vehicle.id,v_actor,v_email,
  case when v_work.id is null then null else to_jsonb(v_work) end,
  (select to_jsonb(w) from public.vehicle_work_items w where w.vehicle_id=v_vehicle.id and w.work_key='PARTS'),
  jsonb_build_object('source','authenticated_email_parts_completion_156','source_hash',v_hash,'source_uid',v_uid,
    'retained_evidence_matched',true,'evidence',v_retained_evidence,'monotonic',true));
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

create table if not exists public.pdc_staging_board_purge_receipts(
 backup_manifest_sha256 text primary key check(backup_manifest_sha256~'^[a-f0-9]{64}$'),
 confirmation text not null,
 result jsonb not null,
 applied_by uuid not null references auth.users(id) on delete restrict,
 applied_at timestamptz not null default clock_timestamp()
);
alter table public.pdc_staging_board_purge_receipts enable row level security;
revoke all on table public.pdc_staging_board_purge_receipts from public,anon,authenticated,service_role;
create or replace function public.pdc_block_board_purge_receipt_mutation()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $trigger$
begin raise exception 'PDC_BOARD_PURGE_RECEIPT_IMMUTABLE' using errcode='55000'; end $trigger$;
revoke all on function public.pdc_block_board_purge_receipt_mutation() from public,anon,authenticated,service_role;

create table if not exists public.pdc_staging_verified_backup_manifests(
 backup_manifest_sha256 text primary key check(backup_manifest_sha256~'^[a-f0-9]{64}$'),
 backup_gzip_sha256 text not null check(backup_gzip_sha256~'^[a-f0-9]{64}$'),
 raw_bytes bigint not null check(raw_bytes>0),
 table_counts jsonb not null check(jsonb_typeof(table_counts)='object'),
 verified_by uuid not null references auth.users(id) on delete restrict,
 verified_at timestamptz not null default clock_timestamp()
);
alter table public.pdc_staging_verified_backup_manifests enable row level security;
revoke all on table public.pdc_staging_verified_backup_manifests from public,anon,authenticated,service_role;
drop trigger if exists pdc_staging_verified_backup_manifest_immutable on public.pdc_staging_verified_backup_manifests;
create trigger pdc_staging_verified_backup_manifest_immutable before update or delete on public.pdc_staging_verified_backup_manifests
for each row execute function public.pdc_block_board_purge_receipt_mutation();
drop trigger if exists pdc_staging_board_purge_receipt_immutable on public.pdc_staging_board_purge_receipts;
create trigger pdc_staging_board_purge_receipt_immutable before update or delete on public.pdc_staging_board_purge_receipts
for each row execute function public.pdc_block_board_purge_receipt_mutation();

create table if not exists public.pdc_staging_backup_restoration_receipts(
 backup_manifest_sha256 text not null check(backup_manifest_sha256~'^[a-f0-9]{64}$'),
 backup_gzip_sha256 text not null check(backup_gzip_sha256~'^[a-f0-9]{64}$'),
 restored_table text not null,
 source_rows integer not null check(source_rows>=0),
 source_rows_sha256 text not null check(source_rows_sha256~'^[a-f0-9]{64}$'),
 restored_rows integer not null check(restored_rows>=0 and restored_rows<=source_rows),
 restored_rows_sha256 text not null check(restored_rows_sha256~'^[a-f0-9]{64}$'),
 applied_by uuid not null references auth.users(id) on delete restrict,
 applied_at timestamptz not null default clock_timestamp(),
 primary key(backup_manifest_sha256,restored_table)
);
alter table public.pdc_staging_backup_restoration_receipts enable row level security;
revoke all on table public.pdc_staging_backup_restoration_receipts from public,anon,authenticated,service_role;
drop trigger if exists pdc_staging_backup_restoration_receipt_immutable on public.pdc_staging_backup_restoration_receipts;
create trigger pdc_staging_backup_restoration_receipt_immutable before update or delete on public.pdc_staging_backup_restoration_receipts
for each row execute function public.pdc_block_board_purge_receipt_mutation();

-- Recheck and lock the Administrator role after waiting for the vehicle lock.
create or replace function public.purge_vehicle_from_board(p_vehicle_id uuid,p_expected_version integer,p_reason text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions as $purge$
declare
 v_result jsonb;v_vehicle public.vehicles%rowtype;v_actor uuid:=auth.uid();v_email text:=public.current_actor_email();
 v_sublet integer:=0;v_deactivated integer:=0;v_now timestamptz:=clock_timestamp();
begin
 if not public.pdc_monitor_staging_guard() or p_vehicle_id is null or p_expected_version is null
   or length(btrim(coalesce(p_reason,''))) not between 8 and 300 then
  return public.navision_backend_response(false,'invalid_input');
 end if;
 perform pg_advisory_xact_lock(hashtextextended('navision-backend-store',0));
 perform pg_advisory_xact_lock(hashtextextended('pdc:board-purge:'||p_vehicle_id::text,0));
 select * into v_vehicle from public.vehicles where id=p_vehicle_id for update;
 if not found then return public.navision_backend_response(false,'vehicle_not_found'); end if;
 perform 1 from public.pdc_user_roles r where r.auth_user_id=v_actor and r.role='administrator'
   and r.active and r.account_status='approved' for share;
 if not found then return public.navision_backend_response(false,'administrator_required'); end if;
 if v_vehicle.board_purged_at is not null and v_vehicle.deleted_at is not null
   and v_vehicle.lifecycle_state='deleted' and not v_vehicle.visible_on_board then
  return public.navision_backend_response(true,'replayed',jsonb_build_object('vehicle_id',v_vehicle.id,'vehicle_version',v_vehicle.version,'changed',false));
 end if;
 if v_vehicle.version<>p_expected_version then
  return public.navision_backend_response(false,'vehicle_version_conflict',jsonb_build_object('current_version',v_vehicle.version));
 end if;
 v_result:=public.purge_vehicle_from_board_pre155(p_vehicle_id,p_expected_version,p_reason);
 if coalesce((v_result->>'ok')::boolean,false) is not true then return v_result; end if;
 delete from public.pdc_sublet_bookings where vehicle_id=p_vehicle_id;get diagnostics v_sublet=row_count;
 update public.navision_board_activations set active=false,completed_at=coalesce(completed_at,v_now),
   completion_reason=coalesce(completion_reason,'Staging board purge'),updated_at=v_now
 where canonical_vehicle_id=p_vehicle_id and active;get diagnostics v_deactivated=row_count;
 insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
 values('delete'::public.audit_action,'vehicles',p_vehicle_id,p_vehicle_id,v_actor,v_email,null,null,
  jsonb_build_object('source','complete_board_purge_156','sublet_bookings_removed',v_sublet,
   'navision_activations_deactivated',v_deactivated,'workshop_history_retained',true,'immutable_evidence_retained',true));
 return jsonb_set(jsonb_set(v_result,'{data,sublet_bookings_removed}',to_jsonb(v_sublet),true),
   '{data,navision_activations_deactivated}',to_jsonb(v_deactivated),true);
end
$purge$;
revoke all on function public.purge_vehicle_from_board(uuid,integer,text) from public,anon,authenticated,service_role;
grant execute on function public.purge_vehicle_from_board(uuid,integer,text) to authenticated;

-- Migration154 left shared Sublet projections behind for already-purged vehicles.
do $cleanup$ declare v_removed integer;begin
 delete from public.pdc_sublet_bookings s using public.vehicles veh
 where s.vehicle_id=veh.id and veh.board_purged_at is not null and veh.deleted_at is not null
   and veh.lifecycle_state='deleted' and not veh.visible_on_board;
 get diagnostics v_removed=row_count;
 if v_removed>0 then
  insert into public.audit_events(action,table_name,actor_id,actor_email,before_data,after_data,metadata)
  values('delete'::public.audit_action,'pdc_sublet_bookings',auth.uid(),public.current_actor_email(),null,null,
   jsonb_build_object('source','staging_migration_156_stale_sublet_cleanup','rows_removed',v_removed,
    'history_retained',true,'production_unchanged',true));
 end if;
end $cleanup$;

create or replace function public.purge_all_staging_board_vehicles(p_confirmation text,p_backup_manifest_sha256 text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions as $all$
declare
 v record;v_locked public.vehicles%rowtype;v_targets jsonb:='[]'::jsonb;v_result jsonb;v_count integer:=0;v_before integer;v_actor uuid:=auth.uid();
 v_reason text:='Staging board cleared for bulk upload test';v_receipt public.pdc_staging_board_purge_receipts%rowtype;
 v_stale_sublet integer:=0;
begin
 if not public.pdc_monitor_staging_guard() or p_confirmation<>'REMOVE ALL STAGING BOARD VEHICLES FOR BULK UPLOAD TEST'
   or coalesce(p_backup_manifest_sha256,'')!~'^[a-f0-9]{64}$' then
  return public.navision_backend_response(false,'confirmation_or_backup_invalid');
 end if;
 perform pg_advisory_xact_lock(hashtextextended('pdc-staging-purge-all-board-vehicles-156',0));
 if not exists(select 1 from public.pdc_user_roles r where r.auth_user_id=v_actor and r.role='administrator'
   and r.active and r.account_status='approved') then return public.navision_backend_response(false,'administrator_required'); end if;
 select * into v_receipt from public.pdc_staging_board_purge_receipts where backup_manifest_sha256=p_backup_manifest_sha256;
 if found then
  perform 1 from public.pdc_user_roles r where r.auth_user_id=v_actor and r.role='administrator'
    and r.active and r.account_status='approved' for share;
  if not found then return public.navision_backend_response(false,'administrator_required'); end if;
  if exists(select 1 from public.vehicles where visible_on_board or deleted_at is null or lifecycle_state<>'deleted' or board_purged_at is null)
    or exists(select 1 from public.workshop_bookings) or exists(select 1 from public.vehicle_work_items)
    or exists(select 1 from public.vehicle_parts_updates) or exists(select 1 from public.vehicle_workshop_line_adjustments)
    or exists(select 1 from public.vehicle_sublet_providers) or exists(select 1 from public.pdc_sublet_bookings)
    or exists(select 1 from public.navision_board_activations where active) then
   return public.navision_backend_response(false,'purge_receipt_state_drift');
  end if;
  return public.navision_backend_response(true,'replayed',v_receipt.result||jsonb_build_object('changed',false));
 end if;
 if not exists(select 1 from public.pdc_staging_verified_backup_manifests b
   where b.backup_manifest_sha256=p_backup_manifest_sha256) then
  return public.navision_backend_response(false,'verified_backup_manifest_required');
 end if;
 select count(*) into v_before from public.vehicles
 where not(board_purged_at is not null and deleted_at is not null and lifecycle_state='deleted' and not visible_on_board);
 -- Wait for every canonical per-vehicle advisory/row lock before locking Administrator authority.
 perform pg_advisory_xact_lock(hashtextextended('navision-backend-store',0));
 for v in select id from public.vehicles
   where not(board_purged_at is not null and deleted_at is not null and lifecycle_state='deleted' and not visible_on_board)
   order by id loop
  perform pg_advisory_xact_lock(hashtextextended('pdc:board-purge:'||v.id::text,0));
  select * into strict v_locked from public.vehicles where id=v.id for update;
  v_targets:=v_targets||jsonb_build_array(jsonb_build_object('id',v_locked.id,'version',v_locked.version));
 end loop;
 perform 1 from public.pdc_user_roles r where r.auth_user_id=v_actor and r.role='administrator'
   and r.active and r.account_status='approved' for share;
 if not found then return public.navision_backend_response(false,'administrator_required'); end if;
 for v in select * from jsonb_to_recordset(v_targets) as x(id uuid,version integer) order by id loop
  v_result:=public.purge_vehicle_from_board(v.id,v.version,v_reason||' · backup '||p_backup_manifest_sha256);
  if coalesce((v_result->>'ok')::boolean,false) is not true then raise exception 'PDC_156_PURGE_FAILED:%:%',v.id,v_result using errcode='55000'; end if;
  v_count:=v_count+1;
 end loop;
 delete from public.pdc_sublet_bookings s using public.vehicles veh
 where s.vehicle_id=veh.id and veh.board_purged_at is not null and veh.deleted_at is not null
   and veh.lifecycle_state='deleted' and not veh.visible_on_board;
 get diagnostics v_stale_sublet=row_count;
 if exists(select 1 from public.vehicles where visible_on_board or deleted_at is null or lifecycle_state<>'deleted' or board_purged_at is null)
   or exists(select 1 from public.workshop_bookings) or exists(select 1 from public.vehicle_work_items)
   or exists(select 1 from public.vehicle_parts_updates) or exists(select 1 from public.vehicle_workshop_line_adjustments)
   or exists(select 1 from public.vehicle_sublet_providers) or exists(select 1 from public.pdc_sublet_bookings)
   or exists(select 1 from public.navision_board_activations where active) then
  raise exception 'PDC_156_PURGE_POSTCONDITION_FAILED' using errcode='55000';
 end if;
 v_result:=jsonb_build_object('vehicles_processed',v_count,'previously_unpurged',v_before,'visible_vehicles',0,
   'bookings',0,'work_items',0,'parts_updates',0,'line_adjustments',0,'sublet_bookings',0,'stale_sublet_bookings_removed',v_stale_sublet,
   'active_navision_activations',0,'backup_manifest_sha256',p_backup_manifest_sha256,'changed',v_count>0);
 insert into public.pdc_staging_board_purge_receipts(backup_manifest_sha256,confirmation,result,applied_by)
 values(p_backup_manifest_sha256,p_confirmation,v_result,v_actor);
 return public.navision_backend_response(true,'staging_board_cleared',v_result);
end
$all$;
revoke all on function public.purge_all_staging_board_vehicles(text,text) from public,anon,authenticated,service_role;
grant execute on function public.purge_all_staging_board_vehicles(text,text) to authenticated;

-- Record the already-executed, backup-bound reset so it cannot be replayed after this fix.
do $backfill$ declare v_actor uuid;begin
 if not exists(select 1 from public.pdc_staging_board_purge_receipts where backup_manifest_sha256='1912754a3ca831d139d4a8419254d9fcbd6cec5bcc62925d574930b574812b24')
   and not exists(select 1 from public.vehicles where visible_on_board or deleted_at is null or lifecycle_state<>'deleted' or board_purged_at is null)
   and not exists(select 1 from public.workshop_bookings)
   and not exists(select 1 from public.vehicle_work_items)
   and not exists(select 1 from public.vehicle_parts_updates)
   and not exists(select 1 from public.vehicle_workshop_line_adjustments)
   and not exists(select 1 from public.vehicle_sublet_providers)
   and not exists(select 1 from public.pdc_sublet_bookings)
   and not exists(select 1 from public.navision_board_activations where active) then
  select r.auth_user_id into v_actor from public.pdc_user_roles r where r.role='administrator' and r.active and r.account_status='approved'
   and r.auth_user_id is not null order by r.created_at,r.id limit 1;
  if v_actor is null then raise exception 'PDC_156_PURGE_RECEIPT_ACTOR_MISSING'; end if;
  insert into public.pdc_staging_board_purge_receipts(backup_manifest_sha256,confirmation,result,applied_by)
  values('1912754a3ca831d139d4a8419254d9fcbd6cec5bcc62925d574930b574812b24',
   'REMOVE ALL STAGING BOARD VEHICLES FOR BULK UPLOAD TEST',
   jsonb_build_object('vehicles_processed',594,'visible_vehicles',0,'bookings',0,'work_items',0,'parts_updates',0,
    'line_adjustments',0,'sublet_providers',0,'sublet_bookings',0,'active_navision_activations',0,
    'backup_manifest_sha256','1912754a3ca831d139d4a8419254d9fcbd6cec5bcc62925d574930b574812b24',
    'changed',true,'historical_backfill',true),v_actor);
 end if;
end $backfill$;

do $verify$ declare d text;begin
 if not exists(select 1 from public.pdc_staging_backup_restoration_receipts
   where backup_manifest_sha256='1912754a3ca831d139d4a8419254d9fcbd6cec5bcc62925d574930b574812b24'
     and backup_gzip_sha256='07d8840916d9e954a24339fa64cdb34796cd02a8381aa774e770f831fbb5eec3'
     and restored_table='workshop_booking_history' and source_rows=211 and restored_rows=211
     and source_rows_sha256='08b3ae192d22f8202080923efffde76ba207590f83184e80479fef74ad176e7f'
     and restored_rows_sha256='b28f5f4edc75be3d3bd8db479b822d26d4c71cbdb4c454bfab80865841c431e7') then
  raise exception 'PDC_156_HASH_BOUND_HISTORY_RESTORATION_REQUIRED';
 end if;
 if not exists(select 1 from public.pdc_staging_verified_backup_manifests
   where backup_manifest_sha256='1912754a3ca831d139d4a8419254d9fcbd6cec5bcc62925d574930b574812b24'
     and backup_gzip_sha256='07d8840916d9e954a24339fa64cdb34796cd02a8381aa774e770f831fbb5eec3'
     and raw_bytes=2147833 and (table_counts->>'workshop_booking_history')::integer=211) then
  raise exception 'PDC_156_VERIFIED_BACKUP_MANIFEST_REQUIRED';
 end if;
 select pg_get_functiondef('public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamptz,text,jsonb,jsonb)'::regprocedure) into d;
 if position($role$r.role in('viewer','importer')$role$ in d)=0 or position($parts$when 'parts' then 'PARTS'$parts$ in d)=0
   or position('jsonb_array_length(v_work)>10' in d)=0 or position('backend_record_id,backend_record_version,vehicle_id' in d)=0
   or not exists(select 1 from information_schema.columns where table_schema='public'
     and table_name='pdc_authenticated_email_import_receipts' and column_name='backend_record_version') then
  raise exception 'PDC_156_MONITOR_RECEIPT_IMPORT_POSTCONDITION_FAILED';
 end if;
 select pg_get_functiondef('public.import_pdc_authenticated_email_operations_with_hours(text,text,jsonb)'::regprocedure) into d;
 if position($role$r.role in('viewer','importer')$role$ in d)=0 or position('pdc_authenticated_email_operation_hours_156' in d)=0 then
  raise exception 'PDC_156_MONITOR_HOURS_IMPORT_POSTCONDITION_FAILED';
 end if;
 if has_table_privilege('service_role','public.pdc_ai_intake_proposals','UPDATE')
   or has_table_privilege('service_role','public.pdc_ai_intake_proposals','DELETE')
   or not exists(select 1 from pg_trigger where tgrelid='public.pdc_ai_intake_proposals'::regclass
     and tgname='pdc_applied_proposal_evidence_immutable' and not tgisinternal and tgenabled<>'D') then
  raise exception 'PDC_156_PROPOSAL_EVIDENCE_IMMUTABILITY_POSTCONDITION_FAILED';
 end if;
 if has_table_privilege('service_role','public.pdc_email_source_claims','UPDATE')
   or has_table_privilege('service_role','public.pdc_email_source_claims','DELETE')
   or not exists(select 1 from pg_trigger where tgrelid='public.pdc_email_source_claims'::regclass
     and tgname='pdc_email_source_claim_immutable' and not tgisinternal and tgenabled<>'D') then
  raise exception 'PDC_156_SOURCE_CLAIM_IMMUTABILITY_POSTCONDITION_FAILED';
 end if;
 select pg_get_functiondef('public.workshop_sync_vehicle_stage_booking_duration(uuid,text,text)'::regprocedure) into d;
 if position('lock table public.workshop_bookings,public.workshop_booking_assignments in exclusive mode' in d)=0
   or position('workshop-bay:' in d)>0 or position('workshop-technician:' in d)>0 or position('workshop:vehicle:' in d)>0 then
  raise exception 'PDC_156_SCHEDULER_WRITER_BARRIER_POSTCONDITION_FAILED';
 end if;
 select pg_get_functiondef('public.apply_pdc_authenticated_parts_completion(text,text,integer,text)'::regprocedure) into d;
 if position('work_key=''PARTS''' in d)=0 or position('retained_parts_completion_evidence_required' in d)=0
   or position('p.backend_record_version=v_receipt.backend_record_version' in d)=0
   or position('navision-backend-store' in d)=0 or position('backend_record_version_not_current' in d)=0
   or position('from public.navision_backend_records r where r.id=v_receipt.backend_record_id for share' in d)=0 then
  raise exception 'PDC_156_PARTS_POSTCONDITION_FAILED';
 end if;
 select pg_get_functiondef('public.purge_vehicle_from_board(uuid,integer,text)'::regprocedure) into d;
 if position('for share' in lower(d))=0 or position('pdc_sublet_bookings' in d)=0 or position('''replayed''' in d)=0
   or position('navision-backend-store' in d)=0
   or position('navision-backend-store' in d)>position('pdc:board-purge:' in d) then
  raise exception 'PDC_156_PURGE_POSTCONDITION_FAILED';
 end if;
 if has_function_privilege('service_role','public.purge_vehicle_from_board(uuid,integer,text)','EXECUTE')
   or not has_function_privilege('authenticated','public.purge_vehicle_from_board(uuid,integer,text)','EXECUTE') then
  raise exception 'PDC_156_PURGE_ACL_FAILED';
 end if;
 if to_regclass('public.pdc_staging_backup_restoration_receipts') is null
   or to_regclass('public.pdc_staging_verified_backup_manifests') is null
   or has_table_privilege('service_role','public.pdc_staging_verified_backup_manifests','SELECT')
   or has_table_privilege('service_role','public.pdc_staging_verified_backup_manifests','INSERT')
   or has_table_privilege('service_role','public.pdc_staging_verified_backup_manifests','UPDATE')
   or has_table_privilege('service_role','public.pdc_staging_verified_backup_manifests','DELETE')
   or not exists(select 1 from pg_trigger where tgrelid='public.pdc_staging_verified_backup_manifests'::regclass
     and tgname='pdc_staging_verified_backup_manifest_immutable' and not tgisinternal and tgenabled<>'D') then
  raise exception 'PDC_156_RESTORATION_RECEIPT_POSTCONDITION_FAILED';
 end if;
 insert into supabase_migrations.schema_migrations(version,name,statements) values('156','monitor_parts_and_complete_purge_review_remediation',array[
  'bind enrolled monitor Parts completion to immutable exact Parts assertion, receipt/backend version and canonical PARTS key',
  'restore planner advisory lock namespace','retain Workshop history while removing mutable bookings and restore pre-clear history from hash-bound backup',
  'remove shared Sublet projection','recheck locked Administrator authority','make purge replay-safe and backup one-shot']);
 insert into public.audit_events(vehicle_id,action,actor_id,actor_email,before_data,after_data,metadata)
 values(null,'insert',auth.uid(),public.current_actor_email(),null,jsonb_build_object('migration','156_monitor_parts_and_complete_purge_review_remediation'),
  jsonb_build_object('source','staging_migration_156','environment','staging','production_unchanged',true));
end $verify$;
commit;
