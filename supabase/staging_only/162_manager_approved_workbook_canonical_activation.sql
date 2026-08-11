-- Staging-only Migration 162: Manager-approved canonical activation bridge for retained PMB workbook pairs.
-- This migration does not weaken or replace Migration157 Preview -> Administrator approvals -> hash/count Apply.
-- It activates only exact current Navision Stock identities, then requires a fresh Migration157 Preview.
begin;
set local lock_timeout='10s';
set local statement_timeout='600s';
set local idle_in_transaction_session_timeout='300s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-162-workbook-canonical-activation',0));

do $guard$ begin
 if not public.pdc_monitor_staging_guard()
   or to_regclass('public.pdc_production_environment_sentinel') is not null
   or to_regclass('public.pdc_staging_environment_sentinel') is null
   or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
   or not exists(select 1 from supabase_migrations.schema_migrations where version='161' and name='non_navision_jobcard_board_creation')
   or not exists(select 1 from supabase_migrations.schema_migrations where version='157' and name='bounded_pmb_workbook_importer_review')
   or to_regprocedure('public.reconcile_navision_operational_record(uuid,uuid,text)') is null then
  raise exception 'PDC_162_STAGING_OR_DEPENDENCY_MISMATCH' using errcode='55000';
 end if;
 if exists(select 1 from supabase_migrations.schema_migrations where version='162') then
  raise exception 'PDC_162_VERSION_CONFLICT' using errcode='55000';
 end if;
end $guard$;

-- The current role enum has no Manager value. An Administrator must explicitly enroll
-- an approved operator in this staging-only Manager authority registry before approval.
create table public.pdc_pmb_canonical_manager_authorities(
 user_id uuid primary key references auth.users(id) on delete restrict,
 active boolean not null default true,authorized_by uuid not null references auth.users(id) on delete restrict,
 authorized_by_email text not null,authorized_at timestamptz not null default clock_timestamp(),
 revoked_by uuid references auth.users(id) on delete restrict,revoked_by_email text,revoked_at timestamptz,
 check((active and revoked_by is null and revoked_by_email is null and revoked_at is null)
    or(not active and revoked_by is not null and revoked_by_email is not null and revoked_at is not null))
);
alter table public.pdc_pmb_canonical_manager_authorities enable row level security;
revoke all on table public.pdc_pmb_canonical_manager_authorities from public,anon,authenticated,service_role;

create or replace function public.configure_pdc_pmb_canonical_manager_authority(p_user_id uuid,p_active boolean,p_confirmation text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $manager_authority$
declare uid uuid:=auth.uid();email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));x public.pdc_user_roles%rowtype;old jsonb;fresh jsonb;expected_confirmation text;
begin
 expected_confirmation:=case when p_active then 'AUTHORIZE WORKBOOK CANONICAL MANAGER' else 'REVOKE WORKBOOK CANONICAL MANAGER' end;
 if not public.pdc_monitor_staging_guard() or uid is null or p_user_id is null or p_active is null
   or p_confirmation is distinct from expected_confirmation
 then return public.navision_backend_response(false,'invalid_manager_authority_request');end if;
 perform pg_advisory_xact_lock(hashtextextended('pdc162-manager:'||p_user_id::text,0));
 select r.* into x from public.pdc_user_roles r where r.auth_user_id=uid and lower(r.email)=email and r.active and r.account_status='approved' and r.role='administrator';
 if not found then return public.navision_backend_response(false,'administrator_required');end if;
 select to_jsonb(a) into old from public.pdc_pmb_canonical_manager_authorities a where a.user_id=p_user_id for update;
 if p_active then
  perform 1 from public.pdc_user_roles where auth_user_id=p_user_id and active and account_status='approved' and role='operator';
  if not found then return public.navision_backend_response(false,'target_must_be_approved_operator');end if;
  insert into public.pdc_pmb_canonical_manager_authorities(user_id,active,authorized_by,authorized_by_email,authorized_at,revoked_by,revoked_by_email,revoked_at)
  values(p_user_id,true,uid,email,clock_timestamp(),null,null,null)
  on conflict(user_id) do update set active=true,authorized_by=excluded.authorized_by,authorized_by_email=excluded.authorized_by_email,
   authorized_at=excluded.authorized_at,revoked_by=null,revoked_by_email=null,revoked_at=null;
 else
  update public.pdc_pmb_canonical_manager_authorities set active=false,revoked_by=uid,revoked_by_email=email,revoked_at=clock_timestamp()
  where user_id=p_user_id and active;
  if not found then return public.navision_backend_response(false,'manager_authority_not_active');end if;
 end if;
 select to_jsonb(a) into fresh from public.pdc_pmb_canonical_manager_authorities a where a.user_id=p_user_id;
 insert into public.audit_events(action,table_name,row_id,actor_id,actor_email,before_data,after_data,metadata)
 values('update','pdc_pmb_canonical_manager_authorities',p_user_id,uid,email,old,fresh,
  jsonb_build_object('source','manager_approved_workbook_canonical_activation_162','active',p_active));
 return public.navision_backend_response(true,case when p_active then 'canonical_manager_authorized' else 'canonical_manager_revoked' end,
  jsonb_build_object('user_id',p_user_id,'active',p_active));
end;$manager_authority$;
revoke all on function public.configure_pdc_pmb_canonical_manager_authority(uuid,boolean,text) from public,anon,authenticated,service_role;
grant execute on function public.configure_pdc_pmb_canonical_manager_authority(uuid,boolean,text) to authenticated;

create table public.pdc_pmb_canonical_manager_approvals(
 approval_id uuid primary key default gen_random_uuid(),
 preview_id uuid not null references public.pdc_pmb_workbook_previews(preview_id) on delete restrict,
 pair_id uuid not null references public.pdc_pmb_workbook_pair_reviews(pair_id) on delete restrict,
 workbook_sha256 text not null check(workbook_sha256~'^[a-f0-9]{64}$'),
 payload_sha256 text not null check(payload_sha256~'^[a-f0-9]{64}$'),
 preview_hash text not null check(preview_hash~'^[a-f0-9]{64}$'),
 pair_hash text not null check(pair_hash~'^[a-f0-9]{64}$'),
 source_hash text not null check(source_hash~'^[a-f0-9]{64}$'),
 backend_record_id uuid not null references public.navision_backend_records(id) on delete restrict,
 backend_record_version integer not null,
 target_vehicle_id uuid references public.vehicles(id) on delete restrict,
 target_vehicle_version integer,
 action text not null check(action in('create_canonical_vehicle','reactivate_complete_board_purge')),
 reason text not null check(length(reason) between 12 and 500),
 confirmation text not null check(confirmation='MANAGER APPROVE CANONICAL BOARD ACTIVATION'),
 approval_hash text not null unique check(approval_hash~'^[a-f0-9]{64}$'),
 approved_by uuid not null references auth.users(id) on delete restrict,
 approved_email text not null,
 approved_at timestamptz not null default clock_timestamp(),
 unique(preview_id,pair_id),
 check((action='create_canonical_vehicle' and target_vehicle_id is null and target_vehicle_version is null)
    or (action='reactivate_complete_board_purge' and target_vehicle_id is not null and target_vehicle_version is not null))
);
create table public.pdc_pmb_canonical_admin_countersignatures(
 countersignature_id uuid primary key default gen_random_uuid(),
 manager_approval_id uuid not null unique references public.pdc_pmb_canonical_manager_approvals(approval_id) on delete restrict,
 preview_id uuid not null references public.pdc_pmb_workbook_previews(preview_id) on delete restrict,
 pair_id uuid not null references public.pdc_pmb_workbook_pair_reviews(pair_id) on delete restrict,
 manager_approval_hash text not null check(manager_approval_hash~'^[a-f0-9]{64}$'),
 reason text not null check(length(reason) between 12 and 500),
 confirmation text not null check(confirmation='ADMINISTRATOR COUNTERSIGN CANONICAL BOARD ACTIVATION'),
 countersignature_hash text not null unique check(countersignature_hash~'^[a-f0-9]{64}$'),
 countersigned_by uuid not null references auth.users(id) on delete restrict,
 countersigned_email text not null,
 countersigned_at timestamptz not null default clock_timestamp(),
 unique(preview_id,pair_id)
);
create table public.pdc_pmb_canonical_apply_authorizations(
 authorization_id uuid primary key default gen_random_uuid(),
 preview_id uuid not null unique references public.pdc_pmb_workbook_previews(preview_id) on delete restrict,
 workbook_sha256 text not null check(workbook_sha256~'^[a-f0-9]{64}$'),
 payload_sha256 text not null check(payload_sha256~'^[a-f0-9]{64}$'),
 preview_hash text not null check(preview_hash~'^[a-f0-9]{64}$'),
 backend_revision bigint not null check(backend_revision>=0),
 expected_activation_count integer not null check(expected_activation_count between 1 and 600),
 approval_set_hash text not null check(approval_set_hash~'^[a-f0-9]{64}$'),
 confirmation text not null check(confirmation='AUTHORIZE MANAGER APPROVED CANONICAL ACTIVATIONS'),
 authorization_hash text not null unique check(authorization_hash~'^[a-f0-9]{64}$'),
 authorized_by uuid not null references auth.users(id) on delete restrict,
 authorized_email text not null,
 authorized_at timestamptz not null default clock_timestamp(),
 expires_at timestamptz not null check(expires_at>authorized_at and expires_at<=authorized_at+interval '2 hours')
);
create table public.pdc_pmb_canonical_apply_receipts(
 receipt_id uuid primary key default gen_random_uuid(),
 authorization_id uuid not null unique references public.pdc_pmb_canonical_apply_authorizations(authorization_id) on delete restrict,
 preview_id uuid not null unique references public.pdc_pmb_workbook_previews(preview_id) on delete restrict,
 workbook_sha256 text not null check(workbook_sha256~'^[a-f0-9]{64}$'),
 payload_sha256 text not null check(payload_sha256~'^[a-f0-9]{64}$'),
 backend_revision_before bigint not null,
 backend_revision_after bigint not null,
 activated_pair_count integer not null check(activated_pair_count between 1 and 600),
 vehicles_created integer not null check(vehicles_created>=0),
 vehicles_reactivated integer not null check(vehicles_reactivated>=0),
 approval_set_hash text not null check(approval_set_hash~'^[a-f0-9]{64}$'),
 pair_aggregate_sha256 text not null check(pair_aggregate_sha256~'^[a-f0-9]{64}$'),
 receipt_hash text not null unique check(receipt_hash~'^[a-f0-9]{64}$'),
 applied_by uuid not null references auth.users(id) on delete restrict,
 applied_email text not null,
 applied_at timestamptz not null default clock_timestamp()
);
create table public.pdc_pmb_canonical_pair_receipts(
 pair_receipt_id uuid primary key default gen_random_uuid(),
 receipt_id uuid not null references public.pdc_pmb_canonical_apply_receipts(receipt_id) on delete restrict deferrable initially deferred,
 preview_id uuid not null references public.pdc_pmb_workbook_previews(preview_id) on delete restrict,
 pair_id uuid not null references public.pdc_pmb_workbook_pair_reviews(pair_id) on delete restrict,
 pair_no integer not null,
 pair_hash text not null check(pair_hash~'^[a-f0-9]{64}$'),
 source_hash text not null check(source_hash~'^[a-f0-9]{64}$'),
 backend_record_id uuid not null references public.navision_backend_records(id) on delete restrict,
 vehicle_id uuid not null references public.vehicles(id) on delete restrict,
 action text not null check(action in('create_canonical_vehicle','reactivate_complete_board_purge')),
 manager_approval_hash text not null check(manager_approval_hash~'^[a-f0-9]{64}$'),
 administrator_countersignature_hash text not null check(administrator_countersignature_hash~'^[a-f0-9]{64}$'),
 pair_receipt_hash text not null unique check(pair_receipt_hash~'^[a-f0-9]{64}$'),
 created_at timestamptz not null default clock_timestamp(),
 unique(receipt_id,pair_id),unique(receipt_id,pair_no)
);

do $secure$ declare t text;begin
 foreach t in array array['pdc_pmb_canonical_manager_approvals','pdc_pmb_canonical_admin_countersignatures','pdc_pmb_canonical_apply_authorizations','pdc_pmb_canonical_apply_receipts','pdc_pmb_canonical_pair_receipts'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on table public.%I from public,anon,authenticated,service_role',t);
  execute format('create trigger %I before update or delete on public.%I for each row execute function public.pdc_pmb_workbook_reject_mutation()',t||'_immutable',t);
 end loop;
end $secure$;

create function public.pdc_pmb_workbook_canonical_candidate(p_pair_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $candidate$
declare
 p public.pdc_pmb_workbook_pair_reviews%rowtype;r public.navision_backend_records%rowtype;v public.vehicles%rowtype;
 a public.navision_board_activations%rowtype;backend_ids uuid[]:='{}';owner_ids uuid[]:='{}';vin_ids uuid[]:='{}';stock text;vin text;
begin
 if not public.pdc_monitor_staging_guard() or p_pair_id is null then return jsonb_build_object('eligible',false,'reason','wrong_environment_or_input');end if;
 select * into p from public.pdc_pmb_workbook_pair_reviews where pair_id=p_pair_id;
 if not found or p.classification<>'terminal_identity_conflict' or p.reason_code<>'canonical_stock_activation_or_owner_conflict'
   or p.stock_number is null then return jsonb_build_object('eligible',false,'reason','pair_not_canonical_activation_quarantine');end if;
 stock:=public.normalize_vehicle_stock_number(p.stock_number);
 if stock='13056899' then return jsonb_build_object('eligible',false,'reason','terminal_excluded_stock13056899');end if;
 select coalesce(array_agg(x.id order by x.id),'{}'::uuid[]) into backend_ids from public.navision_backend_records x
 where x.source_system='microsoft_navision' and x.dealer_code in('14450','37047') and x.is_current and x.record_status='current'
   and public.normalize_vehicle_stock_number(x.normalized_data->>'batch')=stock;
 if cardinality(backend_ids)<>1 then return jsonb_build_object('eligible',false,'reason','current_navision_stock_not_exactly_one');end if;
 select * into strict r from public.navision_backend_records where id=backend_ids[1];
 if public.navision_operational_location(r.normalized_data)='Completed' then return jsonb_build_object('eligible',false,'reason','protected_backend_completed');end if;
 vin:=case when public.is_valid_vehicle_vin(r.normalized_data->>'vin') then public.normalize_vehicle_vin(r.normalized_data->>'vin') else null end;
 select coalesce(array_agg(distinct vehicle_id order by vehicle_id),'{}'::uuid[]) into owner_ids from(
  select x.id vehicle_id from public.vehicles x where x.stock_number_normalized=stock
  union all select x.vehicle_id from public.vehicle_aliases x where x.alias_type_normalized='stock_number' and x.normalized_alias_value=stock
 ) owners;
 if vin is not null then
  select coalesce(array_agg(distinct vehicle_id order by vehicle_id),'{}'::uuid[]) into vin_ids from(
   select x.id vehicle_id from public.vehicles x where x.vin_normalized=vin
   union all select x.vehicle_id from public.vehicle_aliases x where x.alias_type_normalized='vin' and x.normalized_alias_value=vin
  ) owners;
 end if;
 if r.canonical_vehicle_id is null then
  if cardinality(owner_ids)<>0 or cardinality(vin_ids)<>0
    or exists(select 1 from public.navision_board_activations x where x.backend_record_id=r.id or public.normalize_vehicle_stock_number(x.activated_stock_number)=stock)
    or exists(select 1 from public.vehicles x where x.source_system_normalized='microsoft_navision' and x.source_record_id_normalized=public.normalize_vehicle_source_identifier(r.id::text)) then
   return jsonb_build_object('eligible',false,'reason','create_identity_surface_conflict');
  end if;
  return jsonb_build_object('eligible',true,'action','create_canonical_vehicle','backend_record_id',r.id,'backend_record_version',r.version,
   'target_vehicle_id',null,'target_vehicle_version',null,'stock_number',stock);
 end if;
 select * into v from public.vehicles where id=r.canonical_vehicle_id;
 if not found or cardinality(owner_ids)<>1 or owner_ids[1] is distinct from v.id
   or exists(select 1 from unnest(vin_ids) z where z<>v.id)
   or v.stock_number_normalized is distinct from stock or v.board_purged_at is null or v.deleted_at is null
   or v.lifecycle_state<>'deleted' or v.visible_on_board or v.rft_collected_at is not null
   or upper(btrim(coalesce(v.current_location,'')))='COMPLETED'
   or nullif(btrim(coalesce(v.deleted_reason,'')),'') is null
   or v.deleted_reason is distinct from v.board_purge_reason or v.board_purged_by is null
   or v.pmb_stage is not null or v.pmb_bay_stage is not null or v.pmb_bay_number is not null
   or v.active_workshop_booking_id is not null
   or exists(select 1 from public.workshop_bookings x where x.vehicle_id=v.id)
   or exists(select 1 from public.vehicle_work_items x where x.vehicle_id=v.id)
   or exists(select 1 from public.vehicle_parts_updates x where x.vehicle_id=v.id)
   or exists(select 1 from public.vehicle_workshop_line_adjustments x where x.vehicle_id=v.id)
   or exists(select 1 from public.vehicle_sublet_providers x where x.vehicle_id=v.id)
   or exists(select 1 from public.pdc_sublet_bookings x where x.vehicle_id=v.id) then
  return jsonb_build_object('eligible',false,'reason','not_exact_complete_board_purge_tombstone');
 end if;
 select * into a from public.navision_board_activations where backend_record_id=r.id;
 if not found or a.canonical_vehicle_id is distinct from v.id or a.active or a.completed_at is null
   or a.completion_reason is distinct from 'Staging board purge'
   or public.normalize_vehicle_stock_number(a.activated_stock_number) is distinct from stock
   or exists(select 1 from public.navision_board_activations x where x.backend_record_id<>r.id and public.normalize_vehicle_stock_number(x.activated_stock_number)=stock) then
  return jsonb_build_object('eligible',false,'reason','purged_activation_binding_conflict');
 end if;
 return jsonb_build_object('eligible',true,'action','reactivate_complete_board_purge','backend_record_id',r.id,'backend_record_version',r.version,
  'target_vehicle_id',v.id,'target_vehicle_version',v.version,'stock_number',stock);
end $candidate$;
revoke all on function public.pdc_pmb_workbook_canonical_candidate(uuid) from public,anon,authenticated,service_role;

create function public.manager_approve_pdc_pmb_canonical_activation(
 p_preview_id uuid,p_pair_id uuid,p_workbook_sha256 text,p_payload_sha256 text,p_expected_action text,
 p_expected_backend_record_id uuid,p_expected_backend_record_version integer,p_expected_vehicle_id uuid,p_expected_vehicle_version integer,
 p_reason text,p_confirmation text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions as $manager$
declare uid uuid:=auth.uid();email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));pr public.pdc_pmb_workbook_previews%rowtype;
 pair public.pdc_pmb_workbook_pair_reviews%rowtype;c jsonb;old public.pdc_pmb_canonical_manager_approvals%rowtype;h text;id uuid;
begin
 if not public.pdc_monitor_staging_guard() or uid is null or email='' or p_confirmation<>'MANAGER APPROVE CANONICAL BOARD ACTIVATION'
  or length(btrim(coalesce(p_reason,''))) not between 12 and 500 then return public.navision_backend_response(false,'invalid_manager_approval');end if;
 perform pg_advisory_xact_lock(hashtextextended('navision-backend-store',0));
 perform pg_advisory_xact_lock(hashtextextended('pdc-pmb-canonical-pair:'||p_pair_id::text,0));
 select * into pr from public.pdc_pmb_workbook_previews where preview_id=p_preview_id for share;
 select * into pair from public.pdc_pmb_workbook_pair_reviews where preview_id=p_preview_id and pair_id=p_pair_id for share;
 if not found or pr.workbook_sha256<>lower(btrim(coalesce(p_workbook_sha256,''))) or pr.payload_sha256<>lower(btrim(coalesce(p_payload_sha256,'')))
   or pr.expires_at<=clock_timestamp() then return public.navision_backend_response(false,'manager_approval_binding_mismatch');end if;
 c:=public.pdc_pmb_workbook_canonical_candidate(p_pair_id);
 if not coalesce((c->>'eligible')::boolean,false) or c->>'action' is distinct from p_expected_action
   or (c->>'backend_record_id')::uuid is distinct from p_expected_backend_record_id
   or (c->>'backend_record_version')::integer is distinct from p_expected_backend_record_version
   or nullif(c->>'target_vehicle_id','')::uuid is distinct from p_expected_vehicle_id
   or nullif(c->>'target_vehicle_version','')::integer is distinct from p_expected_vehicle_version then
  return public.navision_backend_response(false,'manager_exact_candidate_mismatch',c);end if;
 if p_expected_backend_record_id is not null then perform 1 from public.navision_backend_records where id=p_expected_backend_record_id for share;end if;
 if p_expected_vehicle_id is not null then perform 1 from public.vehicles where id=p_expected_vehicle_id for share;end if;
 -- Exact active approved operator plus explicit Administrator enrollment is the staging Manager authority.
 perform 1 from public.pdc_user_roles r where r.auth_user_id=uid and lower(r.email)=email and r.role='operator'
   and r.active and r.account_status='approved' for share;
 if not found then return public.navision_backend_response(false,'manager_operator_required');end if;
 perform 1 from public.pdc_pmb_canonical_manager_authorities a where a.user_id=uid and a.active for share;
 if not found then return public.navision_backend_response(false,'manager_authority_required');end if;
 select * into old from public.pdc_pmb_canonical_manager_approvals where preview_id=p_preview_id and pair_id=p_pair_id;
 if found then return public.navision_backend_response(true,'exact_manager_approval_replay',jsonb_build_object('approval_id',old.approval_id,'approval_hash',old.approval_hash));end if;
 h:=public.pdc_pmb_workbook_hash(jsonb_build_object('contract','pdc_pmb_canonical_manager_162','preview_hash',pr.preview_hash,'pair_hash',pair.pair_hash,
  'source_hash',pair.source_hash,'action',p_expected_action,'backend_record_id',p_expected_backend_record_id,'backend_record_version',p_expected_backend_record_version,
  'target_vehicle_id',p_expected_vehicle_id,'target_vehicle_version',p_expected_vehicle_version,'reason',btrim(p_reason),'approved_by',uid));
 insert into public.pdc_pmb_canonical_manager_approvals(preview_id,pair_id,workbook_sha256,payload_sha256,preview_hash,pair_hash,source_hash,
  backend_record_id,backend_record_version,target_vehicle_id,target_vehicle_version,action,reason,confirmation,approval_hash,approved_by,approved_email)
 values(p_preview_id,p_pair_id,pr.workbook_sha256,pr.payload_sha256,pr.preview_hash,pair.pair_hash,pair.source_hash,p_expected_backend_record_id,
  p_expected_backend_record_version,p_expected_vehicle_id,p_expected_vehicle_version,p_expected_action,btrim(p_reason),p_confirmation,h,uid,email)
 returning approval_id into id;
 return public.navision_backend_response(true,'manager_approval_recorded',jsonb_build_object('approval_id',id,'approval_hash',h,'action',p_expected_action));
end $manager$;

create function public.administrator_countersign_pdc_pmb_canonical_activation(
 p_manager_approval_id uuid,p_manager_approval_hash text,p_reason text,p_confirmation text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions as $admin$
declare uid uuid:=auth.uid();email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));m public.pdc_pmb_canonical_manager_approvals%rowtype;
 old public.pdc_pmb_canonical_admin_countersignatures%rowtype;c jsonb;h text;id uuid;
begin
 if not public.pdc_monitor_staging_guard() or uid is null or email='' or p_confirmation<>'ADMINISTRATOR COUNTERSIGN CANONICAL BOARD ACTIVATION'
   or length(btrim(coalesce(p_reason,''))) not between 12 and 500 then return public.navision_backend_response(false,'invalid_administrator_countersignature');end if;
 perform pg_advisory_xact_lock(hashtextextended('navision-backend-store',0));
 select * into m from public.pdc_pmb_canonical_manager_approvals where approval_id=p_manager_approval_id for share;
 if not found or m.approval_hash<>lower(btrim(coalesce(p_manager_approval_hash,''))) then return public.navision_backend_response(false,'manager_approval_binding_mismatch');end if;
 perform pg_advisory_xact_lock(hashtextextended('pdc-pmb-canonical-pair:'||m.pair_id::text,0));
 perform 1 from public.navision_backend_records where id=m.backend_record_id for share;
 if m.target_vehicle_id is not null then perform 1 from public.vehicles where id=m.target_vehicle_id for share;end if;
 c:=public.pdc_pmb_workbook_canonical_candidate(m.pair_id);
 if not coalesce((c->>'eligible')::boolean,false) or c->>'action' is distinct from m.action
   or (c->>'backend_record_id')::uuid is distinct from m.backend_record_id or (c->>'backend_record_version')::integer is distinct from m.backend_record_version
   or nullif(c->>'target_vehicle_id','')::uuid is distinct from m.target_vehicle_id
   or nullif(c->>'target_vehicle_version','')::integer is distinct from m.target_vehicle_version then
  return public.navision_backend_response(false,'administrator_candidate_drift',c);end if;
 perform 1 from public.pdc_user_roles r where r.auth_user_id=uid and lower(r.email)=email and r.role='administrator'
   and r.active and r.account_status='approved' for share;
 if not found then return public.navision_backend_response(false,'administrator_required');end if;
 if uid=m.approved_by then return public.navision_backend_response(false,'independent_manager_and_administrator_required');end if;
 select * into old from public.pdc_pmb_canonical_admin_countersignatures where manager_approval_id=m.approval_id;
 if found then return public.navision_backend_response(true,'exact_administrator_countersignature_replay',jsonb_build_object('countersignature_id',old.countersignature_id,'countersignature_hash',old.countersignature_hash));end if;
 h:=public.pdc_pmb_workbook_hash(jsonb_build_object('contract','pdc_pmb_canonical_admin_162','manager_approval_hash',m.approval_hash,
  'preview_id',m.preview_id,'pair_id',m.pair_id,'reason',btrim(p_reason),'countersigned_by',uid));
 insert into public.pdc_pmb_canonical_admin_countersignatures(manager_approval_id,preview_id,pair_id,manager_approval_hash,reason,confirmation,
  countersignature_hash,countersigned_by,countersigned_email) values(m.approval_id,m.preview_id,m.pair_id,m.approval_hash,btrim(p_reason),p_confirmation,h,uid,email)
 returning countersignature_id into id;
 return public.navision_backend_response(true,'administrator_countersignature_recorded',jsonb_build_object('countersignature_id',id,'countersignature_hash',h));
end $admin$;

create function public.authorize_pdc_pmb_canonical_activation_apply(
 p_preview_id uuid,p_workbook_sha256 text,p_payload_sha256 text,p_expected_activation_count integer,p_confirmation text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions as $authorize$
declare uid uuid:=auth.uid();email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));pr public.pdc_pmb_workbook_previews%rowtype;
 old public.pdc_pmb_canonical_apply_authorizations%rowtype;rev bigint;cnt integer;set_hash text;h text;id uuid;
begin
 if not public.pdc_monitor_staging_guard() or uid is null or email='' or p_confirmation<>'AUTHORIZE MANAGER APPROVED CANONICAL ACTIVATIONS'
   or coalesce(p_expected_activation_count,0) not between 1 and 600 then return public.navision_backend_response(false,'invalid_canonical_apply_authorization');end if;
 perform pg_advisory_xact_lock(hashtextextended('navision-backend-store',0));
 perform pg_advisory_xact_lock(hashtextextended('pdc-pmb-canonical-authorize:'||p_preview_id::text,0));
 select * into pr from public.pdc_pmb_workbook_previews where preview_id=p_preview_id for share;
 if not found or pr.workbook_sha256<>lower(btrim(coalesce(p_workbook_sha256,''))) or pr.payload_sha256<>lower(btrim(coalesce(p_payload_sha256,'')))
   or pr.expires_at<=clock_timestamp() then return public.navision_backend_response(false,'canonical_authorization_binding_mismatch');end if;
 select revision into rev from public.navision_backend_revision where singleton for update;
 select count(*),public.pdc_pmb_workbook_hash(coalesce(jsonb_agg(jsonb_build_object('pair_no',p.pair_no,'pair_hash',p.pair_hash,
  'source_hash',p.source_hash,'manager_approval_hash',m.approval_hash,'administrator_countersignature_hash',a.countersignature_hash,
  'action',m.action,'backend_record_id',m.backend_record_id,'backend_record_version',m.backend_record_version,'target_vehicle_id',m.target_vehicle_id,
  'target_vehicle_version',m.target_vehicle_version) order by p.pair_no),'[]'::jsonb)) into cnt,set_hash
 from public.pdc_pmb_canonical_manager_approvals m join public.pdc_pmb_canonical_admin_countersignatures a on a.manager_approval_id=m.approval_id
 join public.pdc_pmb_workbook_pair_reviews p on p.pair_id=m.pair_id where m.preview_id=p_preview_id;
 if cnt<>p_expected_activation_count then return public.navision_backend_response(false,'canonical_approval_count_mismatch',jsonb_build_object('actual_count',cnt));end if;
 if exists(select 1 from public.pdc_pmb_canonical_manager_approvals m where m.preview_id=p_preview_id
  and not exists(select 1 from public.pdc_pmb_canonical_admin_countersignatures a where a.manager_approval_id=m.approval_id)) then
  return public.navision_backend_response(false,'administrator_countersignatures_incomplete');end if;
 perform 1 from public.pdc_user_roles r where r.auth_user_id=uid and lower(r.email)=email and r.role='administrator'
   and r.active and r.account_status='approved' for share;
 if not found then return public.navision_backend_response(false,'administrator_required');end if;
 select * into old from public.pdc_pmb_canonical_apply_authorizations where preview_id=p_preview_id;
 if found then
  if old.expires_at>clock_timestamp() and old.backend_revision=rev
    and old.expected_activation_count=p_expected_activation_count and old.approval_set_hash=set_hash then
   return public.navision_backend_response(true,'exact_canonical_authorization_replay',jsonb_build_object('authorization_id',old.authorization_id,'authorization_hash',old.authorization_hash));
  end if;
  return public.navision_backend_response(false,'canonical_authorization_conflict_or_expired');
 end if;
 h:=public.pdc_pmb_workbook_hash(jsonb_build_object('contract','pdc_pmb_canonical_authorization_162','preview_hash',pr.preview_hash,
  'workbook_sha256',pr.workbook_sha256,'payload_sha256',pr.payload_sha256,'backend_revision',rev,'expected_activation_count',cnt,
  'approval_set_hash',set_hash,'authorized_by',uid));
 insert into public.pdc_pmb_canonical_apply_authorizations(preview_id,workbook_sha256,payload_sha256,preview_hash,backend_revision,
  expected_activation_count,approval_set_hash,confirmation,authorization_hash,authorized_by,authorized_email,expires_at)
 values(pr.preview_id,pr.workbook_sha256,pr.payload_sha256,pr.preview_hash,rev,cnt,set_hash,p_confirmation,h,uid,email,clock_timestamp()+interval '119 minutes')
 returning authorization_id into id;
 return public.navision_backend_response(true,'canonical_apply_authorized',jsonb_build_object('authorization_id',id,'authorization_hash',h,
  'approval_set_hash',set_hash,'activation_count',cnt));
end $authorize$;

create function public.apply_pdc_pmb_canonical_activations(
 p_authorization_id uuid,p_workbook_sha256 text,p_payload_sha256 text,p_expected_activation_count integer,p_confirmation text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions set statement_timeout='300s' as $apply$
declare uid uuid:=auth.uid();email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));au public.pdc_pmb_canonical_apply_authorizations%rowtype;
 pr public.pdc_pmb_workbook_previews%rowtype;old public.pdc_pmb_canonical_apply_receipts%rowtype;m public.pdc_pmb_canonical_manager_approvals%rowtype;
 a public.pdc_pmb_canonical_admin_countersignatures%rowtype;c jsonb;r public.navision_backend_records%rowtype;v public.vehicles%rowtype;
 activation public.navision_board_activations%rowtype;receipt uuid:=gen_random_uuid();rev bigint;next_rev bigint;cnt integer;
 created integer:=0;reactivated integer:=0;set_hash text;source_pair_hash text;source_hash text;pair_receipt_hash text;pair_agg text;receipt_hash text;vehicle_id uuid;
begin
 if not public.pdc_monitor_staging_guard() or uid is null or email='' or p_confirmation<>'APPLY MANAGER APPROVED CANONICAL ACTIVATIONS'
   or coalesce(p_expected_activation_count,0) not between 1 and 600 then return public.navision_backend_response(false,'invalid_canonical_apply');end if;
 perform pg_advisory_xact_lock(hashtextextended('navision-backend-store',0));
 perform pg_advisory_xact_lock(hashtextextended('pdc-pmb-canonical-apply:'||p_authorization_id::text,0));
 select * into au from public.pdc_pmb_canonical_apply_authorizations where authorization_id=p_authorization_id for share;
 if not found then return public.navision_backend_response(false,'canonical_authorization_missing');end if;
 select * into pr from public.pdc_pmb_workbook_previews where preview_id=au.preview_id for share;
 if not found or au.workbook_sha256<>lower(btrim(coalesce(p_workbook_sha256,''))) or au.payload_sha256<>lower(btrim(coalesce(p_payload_sha256,'')))
   or au.expected_activation_count<>p_expected_activation_count or au.expires_at<=clock_timestamp() then
  return public.navision_backend_response(false,'canonical_apply_binding_mismatch_or_expired');end if;
 for m in select * from public.pdc_pmb_canonical_manager_approvals where preview_id=au.preview_id order by pair_id loop
  perform pg_advisory_xact_lock(hashtextextended('pdc-pmb-canonical-pair:'||m.pair_id::text,0));
  perform 1 from public.navision_backend_records where id=m.backend_record_id for update;
  if m.target_vehicle_id is not null then perform pg_advisory_xact_lock(hashtextextended('pdc:board-purge:'||m.target_vehicle_id::text,0));perform 1 from public.vehicles where id=m.target_vehicle_id for update;end if;
 end loop;
 perform 1 from public.pdc_user_roles x where x.auth_user_id=uid and lower(x.email)=email and x.role='administrator'
   and x.active and x.account_status='approved' for share;
 if not found then return public.navision_backend_response(false,'administrator_required');end if;
 select * into old from public.pdc_pmb_canonical_apply_receipts where authorization_id=au.authorization_id;
 if found then return public.navision_backend_response(true,'exact_canonical_apply_replay',jsonb_build_object('receipt_id',old.receipt_id,
  'receipt_hash',old.receipt_hash,'activated_pair_count',old.activated_pair_count,'vehicles_created',old.vehicles_created,
  'vehicles_reactivated',old.vehicles_reactivated,'repreview_required',true,'zero_add_replay',true));end if;
 select revision into rev from public.navision_backend_revision where singleton for update;
 if rev is distinct from au.backend_revision then return public.navision_backend_response(false,'backend_revision_conflict');end if;
 create temporary table if not exists pg_temp.pdc162_candidates(pair_id uuid primary key,manager_approval_id uuid,action text,backend_id uuid unique,
  backend_version integer,vehicle_id uuid unique,vehicle_version integer) on commit drop;
 truncate pg_temp.pdc162_candidates;
 for m in select * from public.pdc_pmb_canonical_manager_approvals where preview_id=au.preview_id order by pair_id loop
  select * into a from public.pdc_pmb_canonical_admin_countersignatures where manager_approval_id=m.approval_id;
  if not found or a.manager_approval_hash<>m.approval_hash or a.countersigned_by=m.approved_by then
   return public.navision_backend_response(false,'administrator_countersignature_missing_or_not_independent');end if;
  c:=public.pdc_pmb_workbook_canonical_candidate(m.pair_id);
  if not coalesce((c->>'eligible')::boolean,false) or c->>'action' is distinct from m.action
    or (c->>'backend_record_id')::uuid is distinct from m.backend_record_id or (c->>'backend_record_version')::integer is distinct from m.backend_record_version
    or nullif(c->>'target_vehicle_id','')::uuid is distinct from m.target_vehicle_id
    or nullif(c->>'target_vehicle_version','')::integer is distinct from m.target_vehicle_version then
   return public.navision_backend_response(false,'canonical_candidate_drift',jsonb_build_object('pair_id',m.pair_id,'candidate',c));end if;
  insert into pg_temp.pdc162_candidates values(m.pair_id,m.approval_id,m.action,m.backend_record_id,m.backend_record_version,m.target_vehicle_id,m.target_vehicle_version);
 end loop;
 select count(*) into cnt from pg_temp.pdc162_candidates;
 if cnt<>au.expected_activation_count then return public.navision_backend_response(false,'canonical_frozen_count_mismatch');end if;
 if exists(
  select 1 from pg_temp.pdc162_candidates f join public.navision_backend_records r on r.id=f.backend_id
  where public.is_valid_vehicle_vin(r.normalized_data->>'vin')
  group by public.normalize_vehicle_vin(r.normalized_data->>'vin') having count(*)>1
 ) then return public.navision_backend_response(false,'canonical_batch_cross_pair_vin_conflict');end if;
 select public.pdc_pmb_workbook_hash(coalesce(jsonb_agg(jsonb_build_object('pair_no',p.pair_no,'pair_hash',p.pair_hash,
  'source_hash',p.source_hash,'manager_approval_hash',m.approval_hash,'administrator_countersignature_hash',a.countersignature_hash,
  'action',m.action,'backend_record_id',m.backend_record_id,'backend_record_version',m.backend_record_version,'target_vehicle_id',m.target_vehicle_id,
  'target_vehicle_version',m.target_vehicle_version) order by p.pair_no),'[]'::jsonb)) into set_hash
 from public.pdc_pmb_canonical_manager_approvals m join public.pdc_pmb_canonical_admin_countersignatures a on a.manager_approval_id=m.approval_id
 join public.pdc_pmb_workbook_pair_reviews p on p.pair_id=m.pair_id where m.preview_id=au.preview_id;
 if set_hash is distinct from au.approval_set_hash then return public.navision_backend_response(false,'canonical_approval_set_hash_conflict');end if;
 -- All validation is complete. From here every failed postcondition raises and rolls back the complete batch.
 for m in select m.* from public.pdc_pmb_canonical_manager_approvals m join public.pdc_pmb_workbook_pair_reviews p on p.pair_id=m.pair_id
  where m.preview_id=au.preview_id order by p.pair_no loop
  select * into strict r from public.navision_backend_records where id=m.backend_record_id for update;
  if m.action='reactivate_complete_board_purge' then
   update public.vehicles set lifecycle_state='active',visible_on_board=true,deleted_at=null,deleted_reason=null,
    board_purged_at=null,board_purge_reason=null,board_purged_by=null,version=version+1,updated_by=uid,updated_at=clock_timestamp()
   where id=m.target_vehicle_id returning * into v;
   update public.navision_board_activations set active=true,activation_source='manual',activated_stock_number=r.normalized_data->>'batch',
    activated_at=clock_timestamp(),activated_by=uid,activated_by_email=email,canonical_vehicle_id=v.id,updated_at=clock_timestamp()
   where backend_record_id=r.id returning * into activation;
   if activation.backend_record_id is null then raise exception 'PDC_162_REACTIVATION_BINDING_LOST:%',m.pair_id using errcode='40001';end if;
   vehicle_id:=v.id;reactivated:=reactivated+1;
  else
   insert into public.navision_board_activations(backend_record_id,activation_source,activated_stock_number,activated_by,activated_by_email,active)
   values(r.id,'manual',r.normalized_data->>'batch',uid,email,true) returning * into activation;
   vehicle_id:=null;created:=created+1;
  end if;
  -- The retained activation trigger invokes reconcile_navision_operational_record exactly once.
  -- Its authoritative postconditions below are stronger than trusting a trigger return value.
  select a.canonical_vehicle_id into vehicle_id from public.navision_board_activations a where a.backend_record_id=r.id and a.active and a.completed_at is null;
  select * into v from public.vehicles where id=vehicle_id;
  if not found or v.deleted_at is not null or v.lifecycle_state<>'active' or not v.visible_on_board or v.board_purged_at is not null
    or v.rft_collected_at is not null or public.normalize_vehicle_stock_number(v.stock_number) is distinct from public.normalize_vehicle_stock_number(r.normalized_data->>'batch')
    or r.canonical_vehicle_id is distinct from v.id then
   -- Refresh the backend row because the reconciler owns canonical_vehicle_id.
   select * into r from public.navision_backend_records where id=m.backend_record_id;
   if not found or r.canonical_vehicle_id is distinct from v.id then raise exception 'PDC_162_CANONICAL_POSTCONDITION_FAILED:%',m.pair_id using errcode='40001';end if;
  end if;
  select * into a from public.pdc_pmb_canonical_admin_countersignatures where manager_approval_id=m.approval_id;
  select p.pair_hash,p.source_hash into strict source_pair_hash,source_hash from public.pdc_pmb_workbook_pair_reviews p where p.pair_id=m.pair_id;
  pair_receipt_hash:=public.pdc_pmb_workbook_hash(jsonb_build_object('receipt_id',receipt,'pair_hash',source_pair_hash,'source_hash',source_hash,
   'backend_record_id',r.id,'vehicle_id',v.id,'action',m.action,'manager_approval_hash',m.approval_hash,
   'administrator_countersignature_hash',a.countersignature_hash));
  insert into public.pdc_pmb_canonical_pair_receipts(receipt_id,preview_id,pair_id,pair_no,pair_hash,source_hash,backend_record_id,vehicle_id,
   action,manager_approval_hash,administrator_countersignature_hash,pair_receipt_hash)
  select receipt,au.preview_id,p.pair_id,p.pair_no,p.pair_hash,p.source_hash,r.id,v.id,m.action,m.approval_hash,a.countersignature_hash,pair_receipt_hash
  from public.pdc_pmb_workbook_pair_reviews p where p.pair_id=m.pair_id;
 end loop;
 select revision into next_rev from public.navision_backend_revision where singleton;
 if next_rev is distinct from rev+cnt then
  raise exception 'PDC_162_BACKEND_REVISION_POSTCONDITION_FAILED expected %, got %',rev+cnt,next_rev using errcode='40001';
 end if;
 select encode(extensions.digest(convert_to(string_agg(pair_no::text||'|'||pair_receipt_hash,';' order by pair_no),'UTF8'),'sha256'),'hex')
 into pair_agg from public.pdc_pmb_canonical_pair_receipts where receipt_id=receipt;
 receipt_hash:=public.pdc_pmb_workbook_hash(jsonb_build_object('contract','pdc_pmb_canonical_apply_receipt_162','receipt_id',receipt,
  'authorization_hash',au.authorization_hash,'preview_hash',pr.preview_hash,'approval_set_hash',set_hash,'backend_revision_before',rev,
  'backend_revision_after',next_rev,'activated_pair_count',cnt,'vehicles_created',created,'vehicles_reactivated',reactivated,'pair_aggregate_sha256',pair_agg));
 insert into public.pdc_pmb_canonical_apply_receipts(receipt_id,authorization_id,preview_id,workbook_sha256,payload_sha256,
  backend_revision_before,backend_revision_after,activated_pair_count,vehicles_created,vehicles_reactivated,approval_set_hash,pair_aggregate_sha256,
  receipt_hash,applied_by,applied_email) values(receipt,au.authorization_id,au.preview_id,au.workbook_sha256,au.payload_sha256,rev,next_rev,cnt,
  created,reactivated,set_hash,pair_agg,receipt_hash,uid,email);
 insert into public.navision_backend_audit(action,revision,evidence,actor_id,actor_email)
 values('board_activate',next_rev,jsonb_build_object('contract','pdc_pmb_canonical_activation_162','preview_id',au.preview_id,
  'workbook_sha256',au.workbook_sha256,'payload_sha256',au.payload_sha256,'approval_set_hash',set_hash,'activated_pair_count',cnt,
  'vehicles_created',created,'vehicles_reactivated',reactivated,'receipt_id',receipt,'receipt_hash',receipt_hash,
  'manager_and_administrator_pair_approval',true,'repreview_required',true,'booking_mutated',false,'completion_mutated',false,
  'parts_mutated',false,'work_mutated',false),uid,email);
 return public.navision_backend_response(true,'canonical_activations_applied',jsonb_build_object('receipt_id',receipt,'receipt_hash',receipt_hash,
  'activated_pair_count',cnt,'vehicles_created',created,'vehicles_reactivated',reactivated,'backend_revision',next_rev,
  'pair_aggregate_sha256',pair_agg,'repreview_required',true,'migration157_apply_not_bypassed',true,'booking_mutated',false,
  'completion_mutated',false,'parts_mutated',false,'work_mutated',false,'zero_add_replay',false));
end $apply$;

revoke all on function public.manager_approve_pdc_pmb_canonical_activation(uuid,uuid,text,text,text,uuid,integer,uuid,integer,text,text) from public,anon,authenticated,service_role;
grant execute on function public.manager_approve_pdc_pmb_canonical_activation(uuid,uuid,text,text,text,uuid,integer,uuid,integer,text,text) to authenticated;
revoke all on function public.administrator_countersign_pdc_pmb_canonical_activation(uuid,text,text,text) from public,anon,authenticated,service_role;
grant execute on function public.administrator_countersign_pdc_pmb_canonical_activation(uuid,text,text,text) to authenticated;
revoke all on function public.authorize_pdc_pmb_canonical_activation_apply(uuid,text,text,integer,text) from public,anon,authenticated,service_role;
grant execute on function public.authorize_pdc_pmb_canonical_activation_apply(uuid,text,text,integer,text) to authenticated;
revoke all on function public.apply_pdc_pmb_canonical_activations(uuid,text,text,integer,text) from public,anon,authenticated,service_role;
grant execute on function public.apply_pdc_pmb_canonical_activations(uuid,text,text,integer,text) to authenticated;
comment on function public.manager_approve_pdc_pmb_canonical_activation(uuid,uuid,text,text,text,uuid,integer,uuid,integer,text,text) is
 'Staging-only exact Administrator-enrolled active approved operator Manager pair approval, bound to Migration157 source/preview/pair hashes and exact backend/vehicle versions.';
comment on function public.apply_pdc_pmb_canonical_activations(uuid,text,text,integer,text) is
 'Staging-only Administrator Apply after independent exact Manager and Administrator pair approvals plus hash/count/revision authorization; canonical activation only; fresh Migration157 Preview required.';

do $verify$ declare d text;t text;begin
 if has_table_privilege('service_role','public.pdc_pmb_canonical_manager_authorities','SELECT')
   or has_table_privilege('service_role','public.pdc_pmb_canonical_manager_authorities','INSERT')
   or has_table_privilege('service_role','public.pdc_pmb_canonical_manager_authorities','UPDATE')
   or has_table_privilege('service_role','public.pdc_pmb_canonical_manager_authorities','DELETE')
   or not has_function_privilege('authenticated','public.configure_pdc_pmb_canonical_manager_authority(uuid,boolean,text)','EXECUTE')
   or has_function_privilege('service_role','public.configure_pdc_pmb_canonical_manager_authority(uuid,boolean,text)','EXECUTE') then
  raise exception 'PDC_162_MANAGER_AUTHORITY_SECURITY_FAILED';
 end if;
 foreach t in array array['pdc_pmb_canonical_manager_approvals','pdc_pmb_canonical_admin_countersignatures','pdc_pmb_canonical_apply_authorizations','pdc_pmb_canonical_apply_receipts','pdc_pmb_canonical_pair_receipts'] loop
  if has_table_privilege('service_role','public.'||t,'SELECT') or has_table_privilege('service_role','public.'||t,'INSERT')
    or has_table_privilege('service_role','public.'||t,'UPDATE') or has_table_privilege('service_role','public.'||t,'DELETE')
    or not exists(select 1 from pg_trigger where tgrelid=to_regclass('public.'||t) and tgname=t||'_immutable' and not tgisinternal and tgenabled<>'D') then
   raise exception 'PDC_162_EVIDENCE_SECURITY_FAILED:%',t;
  end if;
 end loop;
 select pg_get_functiondef('public.manager_approve_pdc_pmb_canonical_activation(uuid,uuid,text,text,text,uuid,integer,uuid,integer,text,text)'::regprocedure) into d;
 if position('pdc_pmb_canonical_manager_authorities' in d)=0 or position('manager_authority_required' in d)=0 then
  raise exception 'PDC_162_MANAGER_AUTHORITY_BINDING_FAILED';
 end if;
 select pg_get_functiondef('public.apply_pdc_pmb_canonical_activations(uuid,text,text,integer,text)'::regprocedure) into d;
 if position('migration157_apply_not_bypassed' in d)=0 or position('exact_canonical_apply_replay' in d)=0
   or position('backend_revision_conflict' in d)=0 or position('canonical_candidate_drift' in d)=0
   or position('workshop_bookings' in d)>0 or position('vehicle_work_items' in d)>0
   or position('vehicle_parts_updates' in d)>0 or position('pdc_sublet_bookings' in d)>0 then
  raise exception 'PDC_162_APPLY_POSTCONDITION_FAILED';
 end if;
 insert into supabase_migrations.schema_migrations(version,name,statements) values('162','manager_approved_workbook_canonical_activation',array[
  'staging-only exact current Navision Stock canonical activation bridge from immutable Migration157 quarantined pairs',
  'explicit Administrator-managed Manager authority registry plus exact enrolled approved-operator pair approval and independent Administrator countersignature',
  'hash/count/backend-revision authorization; immutable per-pair and aggregate receipts; exact replay before mutation',
  'create only when complete Stock/VIN/source/activation identity surfaces are empty',
  'reactivate only the same canonical complete-board-purge tombstone with exact purge and empty mutable-state markers',
  'Stock13056899, registration-only, completed, RFT, ordinary deleted and conflicting identities remain terminal',
  'activation/reconciliation only; no workbook operation, booking, completion, Parts or existing workflow-location mutation',
  'backend revision advances and fresh Migration157 Preview remains mandatory before workbook Apply'
 ]);
end $verify$;
commit;
