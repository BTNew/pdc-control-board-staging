-- Staging-only migration 157: bounded retained PMB workbook Importer review/apply lane.
-- Additive replacement for the Administrator-only 124-129 lane; those contracts are not changed.
begin;
set local lock_timeout='10s';
set local statement_timeout='600s';
set local idle_in_transaction_session_timeout='300s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-157-bounded-pmb-workbook',0));

do $guard$
begin
  if not public.pdc_monitor_staging_guard()
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where project_ref='cdsmnqxtyyoeoznmbidd')
     or not exists(select 1 from supabase_migrations.schema_migrations where version='156' and name='monitor_parts_and_complete_purge_review_remediation') then
    raise exception 'PDC_157_STAGING_OR_PREDECESSOR_MISMATCH';
  end if;
  if exists(select 1 from supabase_migrations.schema_migrations where version='157') then
    raise exception 'PDC_157_VERSION_CONFLICT';
  end if;
  if to_regclass('public.pdc_monitor_stage_activation_writers') is null
     or to_regclass('public.navision_backend_revision') is null
     or to_regclass('public.navision_backend_records') is null
     or to_regclass('public.vehicles') is null
     or to_regclass('public.pdc_authenticated_email_import_receipts') is null
     or to_regclass('public.pdc_authenticated_email_operation_lines') is null
     or to_regclass('public.vehicle_work_items') is null then
    raise exception 'PDC_157_DEPENDENCY_MISSING';
  end if;
end
$guard$;

create table public.pdc_pmb_workbook_previews(
  preview_id uuid primary key default gen_random_uuid(),
  submitted_by uuid not null references auth.users(id) on delete restrict,
  submitted_email text not null,
  workbook_sha256 text not null check(workbook_sha256~'^[a-f0-9]{64}$'),
  payload_sha256 text not null check(payload_sha256~'^[a-f0-9]{64}$'),
  confirmation text not null check(confirmation='PREVIEW RETAINED PMB WORKBOOK'),
  pair_count integer not null check(pair_count between 1 and 600),
  operation_count integer not null check(operation_count between 0 and 60000),
  backend_revision bigint not null check(backend_revision>=0),
  expires_at timestamptz not null default (clock_timestamp()+interval '24 hours'),
  applicable_pair_count integer not null check(applicable_pair_count between 0 and pair_count),
  approval_required_count integer not null check(approval_required_count between 0 and pair_count),
  terminal_pair_count integer not null check(terminal_pair_count between 0 and pair_count),
  accepted_operation_count integer not null check(accepted_operation_count between 0 and operation_count),
  quarantined_operation_count integer not null check(quarantined_operation_count between 0 and operation_count),
  preview_hash text not null unique check(preview_hash~'^[a-f0-9]{64}$'),
  created_at timestamptz not null default clock_timestamp(),
  unique(preview_id,submitted_by,workbook_sha256,payload_sha256)
);

create table public.pdc_pmb_workbook_pair_reviews(
  pair_id uuid primary key default gen_random_uuid(),
  preview_id uuid not null references public.pdc_pmb_workbook_previews(preview_id) on delete restrict,
  pair_no integer not null check(pair_no between 1 and 600),
  pair_hash text not null check(pair_hash~'^[a-f0-9]{64}$'),
  source_hash text not null check(source_hash~'^[a-f0-9]{64}$'),
  job_card_number text,
  stock_number text,
  registration text,
  classification text not null check(classification in (
    'exact_current_stock','no_current_stock_manager_override_required',
    'registration_identity_approval_required','terminal_excluded_stock',
    'terminal_identity_conflict','terminal_pair_quarantine')),
  reason_code text not null,
  backend_record_id uuid references public.navision_backend_records(id) on delete restrict,
  backend_record_version integer,
  vehicle_id uuid references public.vehicles(id) on delete restrict,
  vehicle_version integer,
  operation_count integer not null check(operation_count between 0 and 100),
  created_at timestamptz not null default clock_timestamp(),
  unique(preview_id,pair_no), unique(preview_id,pair_hash),
  check((backend_record_id is null)=(backend_record_version is null)),
  check((vehicle_id is null)=(vehicle_version is null))
);

create table public.pdc_pmb_workbook_operation_reviews(
  operation_review_id uuid primary key default gen_random_uuid(),
  preview_id uuid not null references public.pdc_pmb_workbook_previews(preview_id) on delete restrict,
  pair_id uuid not null references public.pdc_pmb_workbook_pair_reviews(pair_id) on delete restrict,
  source_hash text not null check(source_hash~'^[a-f0-9]{64}$'),
  operation_index integer not null check(operation_index between 1 and 100),
  operation_no text,
  work_key text,
  description text,
  estimated_hours numeric(8,2),
  estimated_hours_source text,
  operation_hash text not null check(operation_hash~'^[a-f0-9]{64}$'),
  disposition text not null check(disposition in ('accepted','quarantined')),
  reason_code text not null,
  created_at timestamptz not null default clock_timestamp(),
  unique(pair_id,operation_index)
);

create table public.pdc_pmb_workbook_pair_approvals(
  approval_id uuid primary key default gen_random_uuid(),
  preview_id uuid not null references public.pdc_pmb_workbook_previews(preview_id) on delete restrict,
  pair_id uuid not null references public.pdc_pmb_workbook_pair_reviews(pair_id) on delete restrict,
  workbook_sha256 text not null check(workbook_sha256~'^[a-f0-9]{64}$'),
  payload_sha256 text not null check(payload_sha256~'^[a-f0-9]{64}$'),
  target_backend_record_id uuid references public.navision_backend_records(id) on delete restrict,
  target_vehicle_id uuid references public.vehicles(id) on delete restrict,
  target_vehicle_version integer,
  decision text not null check(decision in ('approve_exact_target','approve_stock_only_create')),
  reason text not null check(length(reason) between 8 and 500),
  approval_hash text not null unique check(approval_hash~'^[a-f0-9]{64}$'),
  approved_by uuid not null references auth.users(id) on delete restrict,
  approved_email text not null,
  approved_at timestamptz not null default clock_timestamp(),
  unique(preview_id,pair_id),
  check((target_vehicle_id is null)=(target_vehicle_version is null)),
  check((decision='approve_stock_only_create' and target_backend_record_id is null and target_vehicle_id is null)
     or (decision='approve_exact_target' and target_vehicle_id is not null))
);

create table public.pdc_pmb_workbook_apply_authorizations(
  authorization_id uuid primary key default gen_random_uuid(),
  preview_id uuid not null unique references public.pdc_pmb_workbook_previews(preview_id) on delete restrict,
  workbook_sha256 text not null check(workbook_sha256~'^[a-f0-9]{64}$'),
  payload_sha256 text not null check(payload_sha256~'^[a-f0-9]{64}$'),
  expected_pair_count integer not null check(expected_pair_count between 1 and 600),
  expected_operation_count integer not null check(expected_operation_count between 0 and 60000),
  backend_revision bigint not null check(backend_revision>=0),
  approval_set_hash text not null check(approval_set_hash~'^[a-f0-9]{64}$'),
  confirmation text not null check(confirmation='AUTHORIZE RETAINED PMB WORKBOOK APPLY'),
  authorization_hash text not null unique check(authorization_hash~'^[a-f0-9]{64}$'),
  authorized_by uuid not null references auth.users(id) on delete restrict,
  authorized_email text not null,
  authorized_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null check(expires_at>authorized_at and expires_at<=authorized_at+interval '2 hours')
);

create table public.pdc_pmb_workbook_apply_receipts(
  receipt_id uuid primary key default gen_random_uuid(),
  preview_id uuid not null unique references public.pdc_pmb_workbook_previews(preview_id) on delete restrict,
  authorization_id uuid not null unique references public.pdc_pmb_workbook_apply_authorizations(authorization_id) on delete restrict,
  workbook_sha256 text not null check(workbook_sha256~'^[a-f0-9]{64}$'),
  payload_sha256 text not null check(payload_sha256~'^[a-f0-9]{64}$'),
  pair_count integer not null check(pair_count between 1 and 600),
  applied_pair_count integer not null check(applied_pair_count between 0 and pair_count),
  terminal_pair_count integer not null check(terminal_pair_count between 0 and pair_count),
  operation_lines_added integer not null check(operation_lines_added>=0),
  work_items_added integer not null check(work_items_added>=0),
  vehicles_created integer not null check(vehicles_created>=0),
  pair_aggregate_sha256 text not null check(pair_aggregate_sha256~'^[a-f0-9]{64}$'),
  operation_aggregate_sha256 text not null check(operation_aggregate_sha256~'^[a-f0-9]{64}$'),
  approval_set_hash text not null check(approval_set_hash~'^[a-f0-9]{64}$'),
  receipt_hash text not null unique check(receipt_hash~'^[a-f0-9]{64}$'),
  applied_by uuid not null references auth.users(id) on delete restrict,
  applied_email text not null,
  applied_at timestamptz not null default clock_timestamp()
);

create table public.pdc_pmb_workbook_pair_receipts(
  pair_receipt_id uuid primary key default gen_random_uuid(),
  receipt_id uuid not null references public.pdc_pmb_workbook_apply_receipts(receipt_id) on delete restrict deferrable initially deferred,
  preview_id uuid not null references public.pdc_pmb_workbook_previews(preview_id) on delete restrict,
  pair_id uuid not null references public.pdc_pmb_workbook_pair_reviews(pair_id) on delete restrict,
  pair_no integer not null,
  classification text not null,
  vehicle_id uuid not null references public.vehicles(id) on delete restrict,
  backend_record_id uuid references public.navision_backend_records(id) on delete restrict,
  source_hash text not null check(source_hash~'^[a-f0-9]{64}$'),
  operation_count integer not null check(operation_count>=0),
  estimated_hours_count integer not null check(estimated_hours_count>=0),
  pair_receipt_hash text not null unique check(pair_receipt_hash~'^[a-f0-9]{64}$'),
  created_at timestamptz not null default clock_timestamp(),
  unique(receipt_id,pair_id), unique(receipt_id,pair_no)
);

create or replace function public.pdc_pmb_workbook_reject_mutation()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $immutable$
begin raise exception 'PDC_157_IMMUTABLE_RECORD' using errcode='55000'; end
$immutable$;
revoke all on function public.pdc_pmb_workbook_reject_mutation() from public,anon,authenticated,service_role;

do $triggers$ declare t text; begin
  foreach t in array array['pdc_pmb_workbook_previews','pdc_pmb_workbook_pair_reviews','pdc_pmb_workbook_operation_reviews','pdc_pmb_workbook_pair_approvals','pdc_pmb_workbook_apply_authorizations','pdc_pmb_workbook_apply_receipts','pdc_pmb_workbook_pair_receipts'] loop
    execute format('create trigger %I before update or delete on public.%I for each row execute function public.pdc_pmb_workbook_reject_mutation()',t||'_immutable',t);
  end loop;
end $triggers$;

do $rls$ declare t text; begin
  foreach t in array array['pdc_pmb_workbook_previews','pdc_pmb_workbook_pair_reviews','pdc_pmb_workbook_operation_reviews','pdc_pmb_workbook_pair_approvals','pdc_pmb_workbook_apply_authorizations','pdc_pmb_workbook_apply_receipts','pdc_pmb_workbook_pair_receipts'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on table public.%I from public,anon,authenticated,service_role',t);
  end loop;
end $rls$;

create or replace function public.pdc_pmb_workbook_hash(p_value jsonb)
returns text language sql immutable parallel safe set search_path=pg_catalog,public,extensions as $hash$
 select encode(extensions.digest(convert_to(coalesce(p_value,'null'::jsonb)::text,'UTF8'),'sha256'),'hex')
$hash$;
revoke all on function public.pdc_pmb_workbook_hash(jsonb) from public,anon,authenticated,service_role;

create or replace function public.pdc_pmb_workbook_actor_scope(p_administrator boolean)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $scope$
declare v_uid uuid:=auth.uid(); v_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); v_count integer;
begin
 if not public.pdc_monitor_staging_guard() or v_uid is null or v_email='' then return public.navision_backend_response(false,'unauthorized'); end if;
 select count(*) into v_count from public.pdc_user_roles r join auth.users u on u.id=v_uid and lower(u.email)=v_email
 where r.auth_user_id=v_uid and lower(r.email)=v_email and r.active and r.account_status='approved'
   and r.role=(case when p_administrator then 'administrator' else 'importer' end)::public.pdc_role;
 if v_count<>1 then return public.navision_backend_response(false,'unauthorized'); end if;
 if not p_administrator then
   select count(*) into v_count from public.pdc_monitor_stage_activation_writers w
    where w.user_id=v_uid and w.active and w.revoked_at is null;
   if v_count<>1 then return public.navision_backend_response(false,'unauthorized'); end if;
 end if;
 return public.navision_backend_response(true,'authorized',jsonb_build_object('actor_id',v_uid,'actor_email',v_email));
end
$scope$;
revoke all on function public.pdc_pmb_workbook_actor_scope(boolean) from public,anon,authenticated,service_role;

create or replace function public.pdc_pmb_workbook_classify_identity(p_stock text,p_registration text,p_job_card text)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $identity$
declare v_backend_ids uuid[]:='{}';v_owner_ids uuid[]:='{}';v_backend public.navision_backend_records%rowtype;v_vehicle public.vehicles%rowtype;
begin
 if p_stock='13056899' then return jsonb_build_object('classification','terminal_excluded_stock','reason','explicit_terminal_stock_13056899_exclusion');end if;
 if p_stock is not null and not public.is_real_vehicle_stock_number(p_stock) then return jsonb_build_object('classification','terminal_pair_quarantine','reason','unsupported_stock_identity');end if;
 if p_stock is not null then
  select coalesce(array_agg(r.id order by r.id),'{}'::uuid[]) into v_backend_ids from public.navision_backend_records r
   where r.source_system='microsoft_navision' and r.dealer_code in('14450','37047') and r.record_status='current' and r.is_current
     and public.normalize_vehicle_stock_number(r.normalized_data->>'batch')=p_stock;
  select coalesce(array_agg(distinct vehicle_id order by vehicle_id),'{}'::uuid[]) into v_owner_ids from(
   select v.id vehicle_id from public.vehicles v where v.deleted_at is null and public.normalize_vehicle_stock_number(v.stock_number)=p_stock
   union all select a.vehicle_id from public.vehicle_aliases a where a.active and a.alias_type_normalized='stock_number' and a.normalized_alias_value=p_stock
  ) owners;
  if cardinality(v_backend_ids)>1 or cardinality(v_owner_ids)>1 then return jsonb_build_object('classification','terminal_identity_conflict','reason','stock_identity_not_unique');end if;
  if cardinality(v_backend_ids)=1 then
   select * into strict v_backend from public.navision_backend_records where id=v_backend_ids[1];
   if v_backend.canonical_vehicle_id is null or cardinality(v_owner_ids)<>1 or v_owner_ids[1]<>v_backend.canonical_vehicle_id
     or not exists(select 1 from public.navision_board_activations a where a.backend_record_id=v_backend.id and a.canonical_vehicle_id=v_backend.canonical_vehicle_id and a.active and a.completed_at is null) then
    return jsonb_build_object('classification','terminal_identity_conflict','reason','canonical_stock_activation_or_owner_conflict');
   end if;
   select * into v_vehicle from public.vehicles where id=v_backend.canonical_vehicle_id;
   if not found or v_vehicle.deleted_at is not null or v_vehicle.lifecycle_state<>'active' or not v_vehicle.visible_on_board
     or v_vehicle.rft_collected_at is not null or upper(btrim(coalesce(v_vehicle.current_location,'')))='COMPLETED'
     or (p_job_card is not null and nullif(upper(btrim(coalesce(v_vehicle.job_card_number,''))),'') is not null and upper(btrim(v_vehicle.job_card_number))<>p_job_card) then
    return jsonb_build_object('classification','terminal_identity_conflict','reason','protected_or_conflicting_stock_vehicle');
   end if;
   return jsonb_build_object('classification','exact_current_stock','reason','unique_current_stock_active_canonical_vehicle','backend_record_id',v_backend.id,'backend_record_version',v_backend.version,'vehicle_id',v_vehicle.id,'vehicle_version',v_vehicle.version);
  end if;
  if cardinality(v_owner_ids)=1 then
   select * into v_vehicle from public.vehicles where id=v_owner_ids[1];
   if not found or v_vehicle.deleted_at is not null or v_vehicle.lifecycle_state<>'active' or v_vehicle.rft_collected_at is not null
     or upper(btrim(coalesce(v_vehicle.current_location,'')))='COMPLETED'
     or (p_job_card is not null and nullif(upper(btrim(coalesce(v_vehicle.job_card_number,''))),'') is not null and upper(btrim(v_vehicle.job_card_number))<>p_job_card) then
    return jsonb_build_object('classification','terminal_identity_conflict','reason','protected_or_conflicting_stock_override_target');
   end if;
   return jsonb_build_object('classification','no_current_stock_manager_override_required','reason','manager_exact_target_required','vehicle_id',v_vehicle.id,'vehicle_version',v_vehicle.version);
  end if;
  return jsonb_build_object('classification','no_current_stock_manager_override_required','reason','manager_stock_only_create_required');
 end if;
 if p_registration is not null then
  select coalesce(array_agg(distinct vehicle_id order by vehicle_id),'{}'::uuid[]) into v_owner_ids from(
   select v.id vehicle_id from public.vehicles v where v.deleted_at is null and regexp_replace(upper(btrim(coalesce(v.registration,''))),'[^A-Z0-9]','','g')=p_registration
   union all select a.vehicle_id from public.vehicle_aliases a where a.active and a.alias_type_normalized='registration' and a.normalized_alias_value=p_registration
  ) owners;
  if cardinality(v_owner_ids)<>1 then return jsonb_build_object('classification','terminal_identity_conflict','reason','registration_identity_not_exactly_one_active_vehicle');end if;
  select * into v_vehicle from public.vehicles where id=v_owner_ids[1];
  if not found or v_vehicle.deleted_at is not null or v_vehicle.lifecycle_state<>'active' or v_vehicle.rft_collected_at is not null
    or upper(btrim(coalesce(v_vehicle.current_location,'')))='COMPLETED'
    or (p_job_card is not null and nullif(upper(btrim(coalesce(v_vehicle.job_card_number,''))),'') is not null and upper(btrim(v_vehicle.job_card_number))<>p_job_card) then
   return jsonb_build_object('classification','terminal_identity_conflict','reason','protected_or_conflicting_registration_target');
  end if;
  return jsonb_build_object('classification','registration_identity_approval_required','reason','unique_active_registration_manager_approval_required','vehicle_id',v_vehicle.id,'vehicle_version',v_vehicle.version);
 end if;
 return jsonb_build_object('classification','terminal_pair_quarantine','reason','stock_or_registration_required');
end
$identity$;
revoke all on function public.pdc_pmb_workbook_classify_identity(text,text,text) from public,anon,authenticated,service_role;

create or replace function public.preview_pdc_pmb_retained_workbook(
 p_workbook_sha256 text,p_payload_sha256 text,p_confirmation text,p_payload jsonb
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions set statement_timeout='300s' as $preview$
declare
 v_scope jsonb:=public.pdc_pmb_workbook_actor_scope(false); v_uid uuid; v_email text;
 v_workbook text:=lower(btrim(coalesce(p_workbook_sha256,''))); v_claimed text:=lower(btrim(coalesce(p_payload_sha256,'')));
 v_payload jsonb:=coalesce(p_payload,'null'::jsonb); v_server text; v_revision bigint; v_existing public.pdc_pmb_workbook_previews%rowtype;v_applied public.pdc_pmb_workbook_apply_receipts%rowtype;
 v_preview uuid:=gen_random_uuid(); v_pair jsonb; v_op jsonb; v_pair_no integer; v_op_index integer;
 v_stock text; v_reg text; v_jc text; v_class text; v_reason text; v_pair_hash text; v_source_hash text; v_pair_id uuid;v_identity jsonb;
 v_nav_count integer; v_vehicle_count integer; v_backend uuid; v_backend_version integer; v_vehicle uuid; v_vehicle_version integer;
 v_pairs integer; v_ops integer:=0; v_applicable integer:=0; v_approval integer:=0; v_terminal integer:=0; v_accepted_ops integer:=0; v_quarantined_ops integer:=0;
 v_op_no text; v_work_key text; v_description text; v_hours numeric; v_hours_source text; v_disposition text; v_op_reason text; v_op_hash text; v_preview_hash text;
begin
 if not coalesce((v_scope->>'ok')::boolean,false) then return v_scope; end if;
 v_uid:=(v_scope->'data'->>'actor_id')::uuid; v_email:=v_scope->'data'->>'actor_email';
 if v_workbook!~'^[a-f0-9]{64}$' or v_claimed!~'^[a-f0-9]{64}$' or p_confirmation<>'PREVIEW RETAINED PMB WORKBOOK'
    or jsonb_typeof(v_payload) is distinct from 'array' or jsonb_array_length(v_payload) not between 1 and 600 then
  return public.navision_backend_response(false,'invalid_preview_binding');
 end if;
 if exists(select 1 from jsonb_array_elements(v_payload) p where jsonb_typeof(p)<>'object'
   or not(p ? 'pair_no') or not(p ? 'operations') or jsonb_typeof(p->'pair_no')<>'number'
   or coalesce(p->>'pair_no','')!~'^[1-9][0-9]{0,2}$' or (p->>'pair_no')::integer>600
   or jsonb_typeof(p->'operations')<>'array' or jsonb_array_length(p->'operations')>100
   or exists(select 1 from jsonb_object_keys(p) k where k<>all(array['pair_no','job_card_number','stock_number','registration','operations']))) then
  return public.navision_backend_response(false,'invalid_pair_structure');
 end if;
 if jsonb_array_length(v_payload)<>(select count(distinct (p->>'pair_no')::integer) from jsonb_array_elements(v_payload) p) then
  return public.navision_backend_response(false,'duplicate_pair_number');
 end if;
 v_server:=public.pdc_pmb_workbook_hash(v_payload);
 if v_server<>v_claimed then return public.navision_backend_response(false,'server_payload_hash_mismatch',jsonb_build_object('server_payload_sha256',v_server)); end if;
 perform pg_advisory_xact_lock(hashtextextended('navision-backend-store',0));
 perform 1 from public.pdc_user_roles r where r.auth_user_id=v_uid and lower(r.email)=v_email and r.role='importer'
   and r.active and r.account_status='approved' for share;
 if not found then return public.navision_backend_response(false,'importer_revoked');end if;
 perform 1 from public.pdc_monitor_stage_activation_writers w where w.user_id=v_uid and w.active and w.revoked_at is null for share;
 if not found then return public.navision_backend_response(false,'writer_enrollment_revoked');end if;
 select revision into v_revision from public.navision_backend_revision where singleton;
 if v_revision is null then raise exception 'PDC_157_BACKEND_REVISION_MISSING'; end if;
 perform pg_advisory_xact_lock(hashtextextended('pdc-pmb-workbook-preview:'||v_uid::text||':'||v_workbook,0));
 select ar.* into v_applied from public.pdc_pmb_workbook_apply_receipts ar join public.pdc_pmb_workbook_previews p using(preview_id)
 where p.workbook_sha256=v_workbook and p.payload_sha256=v_server order by ar.applied_at desc,ar.receipt_id desc limit 1;
 if found then return public.navision_backend_response(true,'exact_applied_workbook_replay',jsonb_build_object('preview_id',v_applied.preview_id,'receipt_id',v_applied.receipt_id,'receipt_hash',v_applied.receipt_hash,'applied_pair_count',v_applied.applied_pair_count,'zero_add_replay',true));end if;
 select p.* into v_existing from public.pdc_pmb_workbook_previews p left join public.pdc_pmb_workbook_apply_authorizations a using(preview_id)
 where p.submitted_by=v_uid and p.workbook_sha256=v_workbook and p.payload_sha256=v_server and p.backend_revision=v_revision
   and p.expires_at>clock_timestamp() and (a.authorization_id is null or a.expires_at>clock_timestamp())
 order by p.created_at desc,p.preview_id desc limit 1;
 if found then return public.navision_backend_response(true,'exact_preview_replay',jsonb_build_object('preview_id',v_existing.preview_id,'preview_hash',v_existing.preview_hash,'pair_count',v_existing.pair_count,'operation_count',v_existing.operation_count,'applicable_pair_count',v_existing.applicable_pair_count,'approval_required_count',v_existing.approval_required_count,'terminal_pair_count',v_existing.terminal_pair_count,'accepted_operation_count',v_existing.accepted_operation_count,'quarantined_operation_count',v_existing.quarantined_operation_count)); end if;
 create temporary table if not exists pg_temp.pdc157_pairs(pair_id uuid,pair_no integer,pair_hash text,source_hash text,jc text,stock text,registration text,classification text,reason text,backend_id uuid,backend_version integer,vehicle_id uuid,vehicle_version integer,operation_count integer) on commit drop;
 create temporary table if not exists pg_temp.pdc157_ops(pair_id uuid,operation_index integer,operation_no text,work_key text,description text,estimated_hours numeric(8,2),estimated_hours_source text,operation_hash text,disposition text,reason text) on commit drop;
 truncate pg_temp.pdc157_pairs,pg_temp.pdc157_ops;
 for v_pair in select value from jsonb_array_elements(v_payload) order by (value->>'pair_no')::integer loop
  v_pair_no:=(v_pair->>'pair_no')::integer; v_jc:=nullif(upper(btrim(coalesce(v_pair->>'job_card_number',''))),'');
  v_stock:=nullif(public.normalize_vehicle_stock_number(v_pair->>'stock_number'),''); v_reg:=nullif(regexp_replace(upper(btrim(coalesce(v_pair->>'registration',''))),'[^A-Z0-9]','','g'),'');
  if length(coalesce(v_jc,''))>60 or length(coalesce(v_stock,''))>80 or length(coalesce(v_reg,''))>40 then return public.navision_backend_response(false,'identity_value_too_long'); end if;
  v_pair_hash:=public.pdc_pmb_workbook_hash(jsonb_build_object('pair_no',v_pair_no,'job_card_number',v_jc,'stock_number',v_stock,'registration',v_reg,'operations',v_pair->'operations'));
  v_source_hash:=public.pdc_pmb_workbook_hash(jsonb_build_object('contract','pdc_pmb_retained_workbook_157','workbook_sha256',v_workbook,'payload_sha256',v_server,'pair_no',v_pair_no,'pair_hash',v_pair_hash));
  v_pair_id:=gen_random_uuid(); v_backend:=null; v_backend_version:=null; v_vehicle:=null; v_vehicle_version:=null;
  v_identity:=public.pdc_pmb_workbook_classify_identity(v_stock,v_reg,v_jc);
  v_class:=v_identity->>'classification';v_reason:=v_identity->>'reason';
  v_backend:=nullif(v_identity->>'backend_record_id','')::uuid;v_backend_version:=nullif(v_identity->>'backend_record_version','')::integer;
  v_vehicle:=nullif(v_identity->>'vehicle_id','')::uuid;v_vehicle_version:=nullif(v_identity->>'vehicle_version','')::integer;
  if v_class='exact_current_stock' then v_applicable:=v_applicable+1;
  elsif v_class in('no_current_stock_manager_override_required','registration_identity_approval_required') then v_approval:=v_approval+1;
  else v_terminal:=v_terminal+1;end if;
  insert into pg_temp.pdc157_pairs values(v_pair_id,v_pair_no,v_pair_hash,v_source_hash,v_jc,v_stock,v_reg,v_class,v_reason,v_backend,v_backend_version,v_vehicle,v_vehicle_version,jsonb_array_length(v_pair->'operations'));
  v_op_index:=0;
  for v_op in select value from jsonb_array_elements(v_pair->'operations') loop
   v_op_index:=v_op_index+1; v_ops:=v_ops+1; v_op_no:=nullif(upper(btrim(coalesce(v_op->>'operation_no',''))),''); v_work_key:=nullif(btrim(coalesce(v_op->>'work_key','')),''); v_description:=nullif(btrim(coalesce(v_op->>'description','')),''); v_hours_source:=nullif(btrim(coalesce(v_op->>'estimated_hours_source','')),''); v_hours:=null;
   v_disposition:='accepted';v_op_reason:='accepted';
   if jsonb_typeof(v_op)<>'object' or exists(select 1 from jsonb_object_keys(v_op) k where k<>all(array['operation_no','work_key','description','estimated_hours','estimated_hours_source'])) then v_disposition:='quarantined';v_op_reason:='invalid_operation_object_or_keys';
   elsif v_op_no is null or v_op_no!~'^OP([1-9]|[1-9][0-9]|100)$' then v_disposition:='quarantined';v_op_reason:='invalid_operation_number';
   elsif (select count(*) from jsonb_array_elements(v_pair->'operations') z where upper(btrim(coalesce(z->>'operation_no','')))=v_op_no)>1 then v_disposition:='quarantined';v_op_reason:='duplicate_operation_number_within_pair';
   elsif v_work_key not in ('bus4x4','tint','hoist','fitting','fabrication','electrical','tyre','pitInspection','PARTS','sublet') then v_disposition:='quarantined';v_op_reason:='unsupported_work_key';
   elsif v_description is null or length(v_description)>180 or v_description~'[[:cntrl:]]' then v_disposition:='quarantined';v_op_reason:='invalid_operation_description';
   elsif not(v_op ? 'estimated_hours') or jsonb_typeof(v_op->'estimated_hours') not in ('number','null') then v_disposition:='quarantined';v_op_reason:='invalid_estimated_hours_type';
   elsif jsonb_typeof(v_op->'estimated_hours')='number' and ((v_op->>'estimated_hours')::numeric<0 or (v_op->>'estimated_hours')::numeric>999.99 or mod((v_op->>'estimated_hours')::numeric,0.01)<>0) then v_disposition:='quarantined';v_op_reason:='estimated_hours_out_of_range';
   elsif jsonb_typeof(v_op->'estimated_hours')='number' and v_hours_source not in ('job_card','ai_estimate') then v_disposition:='quarantined';v_op_reason:='invalid_estimated_hours_source';
   elsif jsonb_typeof(v_op->'estimated_hours')='null' and v_hours_source is not null then v_disposition:='quarantined';v_op_reason:='hours_source_without_hours';
   end if;
   if jsonb_typeof(v_op->'estimated_hours')='number' and v_disposition='accepted' then v_hours:=(v_op->>'estimated_hours')::numeric; end if;
   if v_disposition='accepted' then v_accepted_ops:=v_accepted_ops+1; else v_quarantined_ops:=v_quarantined_ops+1;v_hours:=null; end if;
   v_op_hash:=public.pdc_pmb_workbook_hash(jsonb_build_object('source_hash',v_source_hash,'operation_index',v_op_index,'operation_no',v_op_no,'work_key',v_work_key,'description',v_description,'estimated_hours',v_hours,'estimated_hours_source',v_hours_source,'disposition',v_disposition,'reason',v_op_reason));
   insert into pg_temp.pdc157_ops values(v_pair_id,v_op_index,v_op_no,v_work_key,v_description,v_hours,v_hours_source,v_op_hash,v_disposition,v_op_reason);
  end loop;
 end loop;
 v_pairs:=jsonb_array_length(v_payload); v_preview_hash:=public.pdc_pmb_workbook_hash(jsonb_build_object('contract','pdc_pmb_retained_workbook_157','preview_id',v_preview,'submitted_by',v_uid,'workbook_sha256',v_workbook,'payload_sha256',v_server,'pair_count',v_pairs,'operation_count',v_ops,'backend_revision',v_revision));
 insert into public.pdc_pmb_workbook_previews(preview_id,submitted_by,submitted_email,workbook_sha256,payload_sha256,confirmation,pair_count,operation_count,backend_revision,applicable_pair_count,approval_required_count,terminal_pair_count,accepted_operation_count,quarantined_operation_count,preview_hash)
 values(v_preview,v_uid,v_email,v_workbook,v_server,p_confirmation,v_pairs,v_ops,v_revision,v_applicable,v_approval,v_terminal,v_accepted_ops,v_quarantined_ops,v_preview_hash);
 insert into public.pdc_pmb_workbook_pair_reviews(pair_id,preview_id,pair_no,pair_hash,source_hash,job_card_number,stock_number,registration,classification,reason_code,backend_record_id,backend_record_version,vehicle_id,vehicle_version,operation_count)
 select pair_id,v_preview,pair_no,pair_hash,source_hash,jc,stock,registration,classification,reason,backend_id,backend_version,vehicle_id,vehicle_version,operation_count from pg_temp.pdc157_pairs order by pair_no;
 insert into public.pdc_pmb_workbook_operation_reviews(preview_id,pair_id,source_hash,operation_index,operation_no,work_key,description,estimated_hours,estimated_hours_source,operation_hash,disposition,reason_code)
 select v_preview,o.pair_id,p.source_hash,o.operation_index,o.operation_no,o.work_key,o.description,o.estimated_hours,o.estimated_hours_source,o.operation_hash,o.disposition,o.reason
 from pg_temp.pdc157_ops o join pg_temp.pdc157_pairs p using(pair_id) order by o.pair_id,o.operation_index;
 return public.navision_backend_response(true,'preview_ready',jsonb_build_object('preview_id',v_preview,'preview_hash',v_preview_hash,'server_payload_sha256',v_server,'pair_count',v_pairs,'operation_count',v_ops,'applicable_pair_count',v_applicable,'approval_required_count',v_approval,'terminal_pair_count',v_terminal,'accepted_operation_count',v_accepted_ops,'quarantined_operation_count',v_quarantined_ops));
end
$preview$;

create or replace function public.read_pdc_pmb_workbook_pair_verification(p_preview_id uuid,p_offset integer,p_limit integer)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,extensions as $read$
declare v_scope jsonb;v_uid uuid;v_preview public.pdc_pmb_workbook_previews%rowtype;v_admin boolean:=false;v_pairs jsonb;
begin
 if p_preview_id is null or coalesce(p_offset,-1)<0 or coalesce(p_limit,0) not between 1 and 100 then return public.navision_backend_response(false,'invalid_read_window'); end if;
 v_scope:=public.pdc_pmb_workbook_actor_scope(false);
 if coalesce((v_scope->>'ok')::boolean,false) then v_uid:=(v_scope->'data'->>'actor_id')::uuid; else v_scope:=public.pdc_pmb_workbook_actor_scope(true);if not coalesce((v_scope->>'ok')::boolean,false) then return v_scope;end if;v_uid:=(v_scope->'data'->>'actor_id')::uuid;v_admin:=true;end if;
 select * into v_preview from public.pdc_pmb_workbook_previews where preview_id=p_preview_id and (v_admin or submitted_by=v_uid);
 if not found then return public.navision_backend_response(false,'preview_not_found'); end if;
 select coalesce(jsonb_agg(jsonb_build_object('pair_id',q.pair_id,'pair_no',q.pair_no,'pair_hash',q.pair_hash,'source_hash',q.source_hash,'classification',q.classification,'reason_code',q.reason_code,'backend_record_id',q.backend_record_id,'backend_record_version',q.backend_record_version,'vehicle_id',q.vehicle_id,'vehicle_version',q.vehicle_version,'operation_count',q.operation_count,'approval_id',a.approval_id,'apply_receipt_id',pr.receipt_id,'applied_vehicle_id',pr.vehicle_id,'applied_operation_count',pr.operation_count,'applied_estimated_hours_count',pr.estimated_hours_count,'pair_receipt_hash',pr.pair_receipt_hash,'operations',(select coalesce(jsonb_agg(jsonb_build_object('operation_index',o.operation_index,'operation_no',o.operation_no,'work_key',o.work_key,'description',o.description,'estimated_hours',o.estimated_hours,'estimated_hours_source',o.estimated_hours_source,'operation_hash',o.operation_hash,'disposition',o.disposition,'reason_code',o.reason_code) order by o.operation_index),'[]'::jsonb) from public.pdc_pmb_workbook_operation_reviews o where o.pair_id=q.pair_id)) order by q.pair_no),'[]'::jsonb) into v_pairs
 from (select * from public.pdc_pmb_workbook_pair_reviews where preview_id=p_preview_id order by pair_no offset p_offset limit p_limit) q
 left join public.pdc_pmb_workbook_pair_approvals a on a.preview_id=q.preview_id and a.pair_id=q.pair_id
 left join public.pdc_pmb_workbook_pair_receipts pr on pr.preview_id=q.preview_id and pr.pair_id=q.pair_id;
 return public.navision_backend_response(true,'pair_verification',jsonb_build_object('preview_id',p_preview_id,'preview_hash',v_preview.preview_hash,'workbook_sha256',v_preview.workbook_sha256,'payload_sha256',v_preview.payload_sha256,'pair_count',v_preview.pair_count,'offset',p_offset,'limit',p_limit,'pairs',v_pairs));
end
$read$;

create or replace function public.approve_pdc_pmb_workbook_pair_exception(
 p_preview_id uuid,p_pair_id uuid,p_workbook_sha256 text,p_payload_sha256 text,p_target_backend_record_id uuid,p_target_vehicle_id uuid,p_expected_vehicle_version integer,p_reason text
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions as $approve$
declare v_scope jsonb;v_uid uuid;v_email text;v_preview public.pdc_pmb_workbook_previews%rowtype;v_pair public.pdc_pmb_workbook_pair_reviews%rowtype;v_existing public.pdc_pmb_workbook_pair_approvals%rowtype;v_decision text;v_hash text;v_identity jsonb;v_revision bigint;v_vehicle public.vehicles%rowtype;v_record public.navision_backend_records%rowtype;
begin
 v_scope:=public.pdc_pmb_workbook_actor_scope(true);if not coalesce((v_scope->>'ok')::boolean,false) then return v_scope;end if;
 if p_preview_id is null or p_pair_id is null or lower(btrim(coalesce(p_workbook_sha256,'')))!~'^[a-f0-9]{64}$' or lower(btrim(coalesce(p_payload_sha256,'')))!~'^[a-f0-9]{64}$' or length(btrim(coalesce(p_reason,''))) not between 8 and 500 then return public.navision_backend_response(false,'invalid_approval_binding');end if;
 perform pg_advisory_xact_lock(hashtextextended('pdc-pmb-pair-approval:'||p_pair_id::text,0));
 perform pg_advisory_xact_lock(hashtextextended('navision-backend-store',0));
 select * into v_preview from public.pdc_pmb_workbook_previews where preview_id=p_preview_id for share;
 select * into v_pair from public.pdc_pmb_workbook_pair_reviews where preview_id=p_preview_id and pair_id=p_pair_id for share;
 if not found or v_preview.workbook_sha256<>lower(btrim(p_workbook_sha256)) or v_preview.payload_sha256<>lower(btrim(p_payload_sha256)) then return public.navision_backend_response(false,'approval_binding_mismatch');end if;
 if v_preview.expires_at<=clock_timestamp() or v_pair.stock_number='13056899' then return public.navision_backend_response(false,'preview_expired_or_excluded_stock13056899');end if;
 select revision into v_revision from public.navision_backend_revision where singleton;
 if v_revision is distinct from v_preview.backend_revision then return public.navision_backend_response(false,'backend_revision_conflict');end if;
 v_identity:=public.pdc_pmb_workbook_classify_identity(v_pair.stock_number,v_pair.registration,v_pair.job_card_number);
 if v_identity->>'classification' is distinct from v_pair.classification
   or nullif(v_identity->>'vehicle_id','')::uuid is distinct from v_pair.vehicle_id
   or nullif(v_identity->>'vehicle_version','')::integer is distinct from v_pair.vehicle_version then
  return public.navision_backend_response(false,'pair_identity_drift');
 end if;
 if p_target_backend_record_id is not null then select * into v_record from public.navision_backend_records where id=p_target_backend_record_id for share; if not found or not v_record.is_current or v_record.record_status<>'current' or public.normalize_vehicle_stock_number(v_record.normalized_data->>'batch')<>v_pair.stock_number then return public.navision_backend_response(false,'target_backend_not_exact_current_stock');end if;end if;
 if p_target_vehicle_id is not null then select * into v_vehicle from public.vehicles where id=p_target_vehicle_id for share;if not found or v_vehicle.deleted_at is not null or v_vehicle.lifecycle_state<>'active' or v_vehicle.version<>p_expected_vehicle_version then return public.navision_backend_response(false,'target_vehicle_version_or_state_mismatch');end if;end if;
 -- Every potentially blocking wait is complete before the final Administrator role lock.
 v_scope:=public.pdc_pmb_workbook_actor_scope(true);if not coalesce((v_scope->>'ok')::boolean,false) then return v_scope;end if;v_uid:=(v_scope->'data'->>'actor_id')::uuid;v_email:=v_scope->'data'->>'actor_email';
 perform 1 from public.pdc_user_roles r where r.auth_user_id=v_uid and r.role='administrator' and r.active and r.account_status='approved' for share;if not found then return public.navision_backend_response(false,'administrator_required');end if;
 select * into v_existing from public.pdc_pmb_workbook_pair_approvals where preview_id=p_preview_id and pair_id=p_pair_id;
 if found then return public.navision_backend_response(true,'exact_pair_approval_replay',jsonb_build_object('approval_id',v_existing.approval_id,'approval_hash',v_existing.approval_hash,'decision',v_existing.decision));end if;
 if v_pair.classification='registration_identity_approval_required' then
  if p_target_backend_record_id is not null or p_target_vehicle_id is distinct from v_pair.vehicle_id or p_expected_vehicle_version is distinct from v_pair.vehicle_version then return public.navision_backend_response(false,'registration_exact_target_required');end if;v_decision:='approve_exact_target';
 elsif v_pair.classification='no_current_stock_manager_override_required' then
  if p_target_backend_record_id is not null then return public.navision_backend_response(false,'exception_backend_target_forbidden');
  elsif p_target_vehicle_id is null then
   if v_pair.vehicle_id is not null then return public.navision_backend_response(false,'bound_stock_target_required');end if;
   v_decision:='approve_stock_only_create';
  elsif p_target_vehicle_id is distinct from v_pair.vehicle_id or p_expected_vehicle_version is distinct from v_pair.vehicle_version
    or public.normalize_vehicle_stock_number(v_vehicle.stock_number)<>v_pair.stock_number then return public.navision_backend_response(false,'stock_target_mismatch');
  else v_decision:='approve_exact_target';end if;
 else return public.navision_backend_response(false,'pair_not_approval_eligible');end if;
 v_hash:=public.pdc_pmb_workbook_hash(jsonb_build_object('contract','pdc_pmb_pair_approval_157','preview_hash',v_preview.preview_hash,'pair_hash',v_pair.pair_hash,'target_backend_record_id',p_target_backend_record_id,'target_vehicle_id',p_target_vehicle_id,'target_vehicle_version',p_expected_vehicle_version,'decision',v_decision,'reason',btrim(p_reason),'approved_by',v_uid));
 insert into public.pdc_pmb_workbook_pair_approvals(preview_id,pair_id,workbook_sha256,payload_sha256,target_backend_record_id,target_vehicle_id,target_vehicle_version,decision,reason,approval_hash,approved_by,approved_email)
 values(p_preview_id,p_pair_id,v_preview.workbook_sha256,v_preview.payload_sha256,p_target_backend_record_id,p_target_vehicle_id,p_expected_vehicle_version,v_decision,btrim(p_reason),v_hash,v_uid,v_email) returning approval_id into v_existing.approval_id;
 return public.navision_backend_response(true,'pair_approved',jsonb_build_object('approval_id',v_existing.approval_id,'approval_hash',v_hash,'decision',v_decision));
end
$approve$;

create or replace function public.authorize_pdc_pmb_workbook_apply(p_preview_id uuid,p_workbook_sha256 text,p_payload_sha256 text,p_confirmation text,p_expected_pair_count integer,p_expected_operation_count integer)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions as $authorize$
declare v_scope jsonb;v_uid uuid;v_email text;v_preview public.pdc_pmb_workbook_previews%rowtype;v_existing public.pdc_pmb_workbook_apply_authorizations%rowtype;v_hash text;v_approval_set_hash text;v_revision bigint;v_id uuid;v record;
begin
 v_scope:=public.pdc_pmb_workbook_actor_scope(true);if not coalesce((v_scope->>'ok')::boolean,false) then return v_scope;end if;
 if p_preview_id is null or p_confirmation<>'AUTHORIZE RETAINED PMB WORKBOOK APPLY' then return public.navision_backend_response(false,'invalid_apply_authorization');end if;
 perform pg_advisory_xact_lock(hashtextextended('pdc-pmb-authorize:'||p_preview_id::text,0));
 perform pg_advisory_xact_lock(hashtextextended('navision-backend-store',0));
 select * into v_preview from public.pdc_pmb_workbook_previews where preview_id=p_preview_id for share;
 if not found or v_preview.workbook_sha256<>lower(btrim(coalesce(p_workbook_sha256,''))) or v_preview.payload_sha256<>lower(btrim(coalesce(p_payload_sha256,''))) or v_preview.pair_count<>p_expected_pair_count or v_preview.operation_count<>p_expected_operation_count then return public.navision_backend_response(false,'authorization_binding_mismatch');end if;
 if v_preview.expires_at<=clock_timestamp() or exists(select 1 from public.pdc_pmb_workbook_pair_reviews where preview_id=p_preview_id and stock_number='13056899') then return public.navision_backend_response(false,'preview_expired_or_excluded_stock13056899');end if;
 select revision into v_revision from public.navision_backend_revision where singleton;
 if v_revision is distinct from v_preview.backend_revision then return public.navision_backend_response(false,'backend_revision_conflict');end if;
 perform 1 from public.pdc_pmb_workbook_pair_reviews where preview_id=p_preview_id order by pair_id for share;
 for v in select coalesce(a.target_backend_record_id,r.backend_record_id) backend_id,coalesce(a.target_vehicle_id,r.vehicle_id) vehicle_id from public.pdc_pmb_workbook_pair_reviews r left join public.pdc_pmb_workbook_pair_approvals a using(preview_id,pair_id) where r.preview_id=p_preview_id and r.classification in('exact_current_stock','no_current_stock_manager_override_required','registration_identity_approval_required') order by r.pair_id loop
  if v.backend_id is not null then perform 1 from public.navision_backend_records where id=v.backend_id for share;end if;if v.vehicle_id is not null then perform 1 from public.vehicles where id=v.vehicle_id for share;end if;
 end loop;
 v_scope:=public.pdc_pmb_workbook_actor_scope(true);if not coalesce((v_scope->>'ok')::boolean,false) then return v_scope;end if;v_uid:=(v_scope->'data'->>'actor_id')::uuid;v_email:=v_scope->'data'->>'actor_email';
 perform 1 from public.pdc_user_roles r where r.auth_user_id=v_uid and r.role='administrator' and r.active and r.account_status='approved' for share;if not found then return public.navision_backend_response(false,'administrator_required');end if;
 select * into v_existing from public.pdc_pmb_workbook_apply_authorizations where preview_id=p_preview_id;
 if found then
  if v_existing.expires_at>clock_timestamp() then return public.navision_backend_response(true,'exact_apply_authorization_replay',jsonb_build_object('authorization_id',v_existing.authorization_id,'authorization_hash',v_existing.authorization_hash,'expires_at',v_existing.expires_at));end if;
  return public.navision_backend_response(false,'apply_authorization_expired_repreview_required',jsonb_build_object('preview_id',p_preview_id,'authorization_id',v_existing.authorization_id));
 end if;
 if exists(select 1 from public.pdc_pmb_workbook_pair_reviews r where r.preview_id=p_preview_id and r.classification in('no_current_stock_manager_override_required','registration_identity_approval_required') and not exists(select 1 from public.pdc_pmb_workbook_pair_approvals a where a.preview_id=r.preview_id and a.pair_id=r.pair_id)) then return public.navision_backend_response(false,'pair_approvals_incomplete');end if;
 if not exists(select 1 from public.pdc_pmb_workbook_pair_reviews r where r.preview_id=p_preview_id and r.classification in('exact_current_stock','no_current_stock_manager_override_required','registration_identity_approval_required')) then return public.navision_backend_response(false,'zero_applicable_pairs');end if;
 select public.pdc_pmb_workbook_hash(coalesce(jsonb_agg(jsonb_build_object('pair_no',r.pair_no,'pair_hash',r.pair_hash,'approval_hash',a.approval_hash) order by r.pair_no),'[]'::jsonb)) into v_approval_set_hash
 from public.pdc_pmb_workbook_pair_reviews r left join public.pdc_pmb_workbook_pair_approvals a using(preview_id,pair_id)
 where r.preview_id=p_preview_id and r.classification in('no_current_stock_manager_override_required','registration_identity_approval_required');
 v_hash:=public.pdc_pmb_workbook_hash(jsonb_build_object('contract','pdc_pmb_apply_authorization_157','preview_hash',v_preview.preview_hash,'workbook_sha256',v_preview.workbook_sha256,'payload_sha256',v_preview.payload_sha256,'backend_revision',v_revision,'approval_set_hash',v_approval_set_hash,'expected_pair_count',p_expected_pair_count,'expected_operation_count',p_expected_operation_count,'authorized_by',v_uid));
 insert into public.pdc_pmb_workbook_apply_authorizations(preview_id,workbook_sha256,payload_sha256,expected_pair_count,expected_operation_count,backend_revision,approval_set_hash,confirmation,authorization_hash,authorized_by,authorized_email,expires_at)
 values(p_preview_id,v_preview.workbook_sha256,v_preview.payload_sha256,p_expected_pair_count,p_expected_operation_count,v_revision,v_approval_set_hash,p_confirmation,v_hash,v_uid,v_email,clock_timestamp()+interval '119 minutes') returning authorization_id into v_id;
 return public.navision_backend_response(true,'apply_authorized',jsonb_build_object('authorization_id',v_id,'authorization_hash',v_hash,'approval_set_hash',v_approval_set_hash,'expires_at',clock_timestamp()+interval '119 minutes'));
end
$authorize$;

create or replace function public.apply_pdc_pmb_retained_workbook(p_preview_id uuid,p_workbook_sha256 text,p_payload_sha256 text,p_confirmation text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions set statement_timeout='300s' as $apply$
declare v_scope jsonb;v_uid uuid;v_email text;v_preview public.pdc_pmb_workbook_previews%rowtype;v_auth public.pdc_pmb_workbook_apply_authorizations%rowtype;v_existing public.pdc_pmb_workbook_apply_receipts%rowtype;v_pair public.pdc_pmb_workbook_pair_reviews%rowtype;v_approval public.pdc_pmb_workbook_pair_approvals%rowtype;v_vehicle public.vehicles%rowtype;v_record public.navision_backend_records%rowtype;v_op public.pdc_pmb_workbook_operation_reviews%rowtype;v_import uuid;v_line uuid;v_before public.vehicle_work_items%rowtype;v_after public.vehicle_work_items%rowtype;v_receipt uuid:=gen_random_uuid();v_vehicle_id uuid;v_backend_id uuid;v_source_uid text;v_pair_receipt_hash text;v_receipt_hash text;v_pair_agg text;v_op_agg text;v_approval_set_hash text;v_identity jsonb;v_revision bigint;v_applied integer:=0;v_lines integer:=0;v_work integer:=0;v_created integer:=0;v_row_lines integer;v_row_hours integer;
begin
 v_scope:=public.pdc_pmb_workbook_actor_scope(true);if not coalesce((v_scope->>'ok')::boolean,false) then return v_scope;end if;
 if p_preview_id is null or p_confirmation<>'APPLY RETAINED PMB WORKBOOK' then return public.navision_backend_response(false,'invalid_apply_confirmation');end if;
 perform pg_advisory_xact_lock(hashtextextended('pdc-pmb-apply:'||p_preview_id::text,0));
 perform pg_advisory_xact_lock(hashtextextended('navision-backend-store',0));
 select * into v_preview from public.pdc_pmb_workbook_previews where preview_id=p_preview_id for share;
 if not found or v_preview.workbook_sha256<>lower(btrim(coalesce(p_workbook_sha256,''))) or v_preview.payload_sha256<>lower(btrim(coalesce(p_payload_sha256,''))) then return public.navision_backend_response(false,'apply_binding_mismatch');end if;
 select * into v_auth from public.pdc_pmb_workbook_apply_authorizations where preview_id=p_preview_id for share;if not found then return public.navision_backend_response(false,'apply_authorization_missing');end if;
 perform 1 from public.pdc_pmb_workbook_pair_reviews where preview_id=p_preview_id order by pair_id for share;
 for v_pair in select * from public.pdc_pmb_workbook_pair_reviews where preview_id=p_preview_id and classification in('exact_current_stock','no_current_stock_manager_override_required','registration_identity_approval_required') order by pair_id loop
  select * into v_approval from public.pdc_pmb_workbook_pair_approvals where preview_id=p_preview_id and pair_id=v_pair.pair_id;
  v_backend_id:=coalesce(v_approval.target_backend_record_id,v_pair.backend_record_id);v_vehicle_id:=coalesce(v_approval.target_vehicle_id,v_pair.vehicle_id);
  if v_backend_id is not null then select * into v_record from public.navision_backend_records where id=v_backend_id for share;end if;
  if v_vehicle_id is not null then select * into v_vehicle from public.vehicles where id=v_vehicle_id for update;end if;
  if v_vehicle_id is null and v_pair.stock_number is not null then perform pg_advisory_xact_lock(hashtextextended('pdc-pmb-stock-create:'||v_pair.stock_number,0));end if;
 end loop;
 v_scope:=public.pdc_pmb_workbook_actor_scope(true);if not coalesce((v_scope->>'ok')::boolean,false) then return v_scope;end if;v_uid:=(v_scope->'data'->>'actor_id')::uuid;v_email:=v_scope->'data'->>'actor_email';
 perform 1 from public.pdc_user_roles r where r.auth_user_id=v_uid and r.role='administrator' and r.active and r.account_status='approved' for share;if not found then return public.navision_backend_response(false,'administrator_required');end if;
 -- Exact replay is before every operational INSERT/UPDATE.
 select ar.* into v_existing from public.pdc_pmb_workbook_apply_receipts ar join public.pdc_pmb_workbook_previews p using(preview_id)
 where p.workbook_sha256=v_preview.workbook_sha256 and p.payload_sha256=v_preview.payload_sha256
 order by ar.applied_at desc,ar.receipt_id desc limit 1;
 if found then return public.navision_backend_response(true,case when v_existing.preview_id=p_preview_id then 'exact_apply_replay' else 'exact_workbook_apply_replay' end,jsonb_build_object('receipt_id',v_existing.receipt_id,'receipt_hash',v_existing.receipt_hash,'applied_preview_id',v_existing.preview_id,'applied_pair_count',v_existing.applied_pair_count,'operation_lines_added',v_existing.operation_lines_added,'work_items_added',v_existing.work_items_added,'vehicles_created',v_existing.vehicles_created,'zero_add_replay',true));end if;
 if v_auth.workbook_sha256<>v_preview.workbook_sha256 or v_auth.payload_sha256<>v_preview.payload_sha256 or v_auth.expected_pair_count<>v_preview.pair_count or v_auth.expected_operation_count<>v_preview.operation_count or v_auth.expires_at<=clock_timestamp() then return public.navision_backend_response(false,'immutable_authorization_binding_mismatch_or_expired');end if;
 if exists(select 1 from public.pdc_pmb_workbook_pair_reviews where preview_id=p_preview_id and stock_number='13056899') then return public.navision_backend_response(false,'excluded_stock13056899');end if;
 select revision into v_revision from public.navision_backend_revision where singleton;if v_revision is distinct from v_preview.backend_revision or v_revision is distinct from v_auth.backend_revision then return public.navision_backend_response(false,'backend_revision_conflict');end if;
 select public.pdc_pmb_workbook_hash(coalesce(jsonb_agg(jsonb_build_object('pair_no',r.pair_no,'pair_hash',r.pair_hash,'approval_hash',a.approval_hash) order by r.pair_no),'[]'::jsonb)) into v_approval_set_hash
 from public.pdc_pmb_workbook_pair_reviews r left join public.pdc_pmb_workbook_pair_approvals a using(preview_id,pair_id)
 where r.preview_id=p_preview_id and r.classification in('no_current_stock_manager_override_required','registration_identity_approval_required');
 if v_approval_set_hash is distinct from v_auth.approval_set_hash then return public.navision_backend_response(false,'approval_set_hash_conflict');end if;
 for v_pair in select * from public.pdc_pmb_workbook_pair_reviews where preview_id=p_preview_id and classification in('exact_current_stock','no_current_stock_manager_override_required','registration_identity_approval_required') order by pair_no loop
  v_approval:=null;v_vehicle:=null;v_record:=null;select * into v_approval from public.pdc_pmb_workbook_pair_approvals where preview_id=p_preview_id and pair_id=v_pair.pair_id;
  v_identity:=public.pdc_pmb_workbook_classify_identity(v_pair.stock_number,v_pair.registration,v_pair.job_card_number);
  if v_identity->>'classification' is distinct from v_pair.classification
    or nullif(v_identity->>'backend_record_id','')::uuid is distinct from v_pair.backend_record_id
    or nullif(v_identity->>'backend_record_version','')::integer is distinct from v_pair.backend_record_version
    or nullif(v_identity->>'vehicle_id','')::uuid is distinct from v_pair.vehicle_id
    or nullif(v_identity->>'vehicle_version','')::integer is distinct from v_pair.vehicle_version then
   raise exception 'PDC_157_PAIR_IDENTITY_DRIFT pair %',v_pair.pair_no using errcode='40001';
  end if;
  v_backend_id:=coalesce(v_approval.target_backend_record_id,v_pair.backend_record_id);v_vehicle_id:=coalesce(v_approval.target_vehicle_id,v_pair.vehicle_id);
  if v_backend_id is not null then select * into v_record from public.navision_backend_records where id=v_backend_id;if not found or not v_record.is_current or v_record.record_status<>'current' or (v_pair.backend_record_id=v_backend_id and v_record.version<>v_pair.backend_record_version) then raise exception 'PDC_157_BACKEND_RECORD_VERSION_CONFLICT pair %',v_pair.pair_no using errcode='40001';end if;end if;
  if v_vehicle_id is not null then select * into v_vehicle from public.vehicles where id=v_vehicle_id;if not found or v_vehicle.deleted_at is not null or v_vehicle.lifecycle_state<>'active' or v_vehicle.version<>coalesce(v_approval.target_vehicle_version,v_pair.vehicle_version) then raise exception 'PDC_157_VEHICLE_VERSION_CONFLICT pair %',v_pair.pair_no using errcode='40001';end if;
  else
   if v_approval.decision is distinct from 'approve_stock_only_create' or v_pair.stock_number is null then raise exception 'PDC_157_CREATE_APPROVAL_REQUIRED pair %',v_pair.pair_no;end if;
   if exists(select 1 from public.vehicles x where public.normalize_vehicle_stock_number(x.stock_number)=v_pair.stock_number) then raise exception 'PDC_157_STOCK_CREATE_CONFLICT pair %',v_pair.pair_no using errcode='40001';end if;
   v_vehicle_id:=extensions.uuid_generate_v5('b58b5f75-d004-5a76-b9aa-48c801b4ad7d'::uuid,'pmb157:'||v_preview.workbook_sha256||':'||v_pair.stock_number);
   insert into public.vehicles(id,permanent_vehicle_id,stock_number,job_card_number,lifecycle_state,visible_on_board,current_location,source_system,source_batch_id,source_record_id,source_payload,created_by,updated_by)
   values(v_vehicle_id,'PDC-PMB-'||upper(substr(v_pair.source_hash,1,24)),v_pair.stock_number,v_pair.job_card_number,'active',true,'Other','pdc_pmb_workbook',v_preview.workbook_sha256,v_pair.pair_id::text,jsonb_build_object('intake_contract','pdc_pmb_retained_workbook_157','preview_id',p_preview_id,'pair_hash',v_pair.pair_hash,'stock_only',true,'privacy_preserved',true),v_uid,v_uid);
   v_created:=v_created+1;select * into strict v_vehicle from public.vehicles where id=v_vehicle_id;
  end if;
  v_source_uid:='pmb-workbook-157:'||p_preview_id::text||':'||v_pair.pair_no::text;
  v_import:=null;
  insert into public.pdc_authenticated_email_import_receipts(actor_id,idempotency_key,request_hash,source_hash,evidence_hash,source_uid,sender_address,source_received_at,stock_number,vin,backend_record_id,backend_record_version,vehicle_id,identity_source,required_work,response)
  values(v_preview.submitted_by,v_source_uid,v_preview.payload_sha256,v_pair.source_hash,v_pair.pair_hash,v_source_uid,v_preview.submitted_email,v_preview.created_at,v_pair.stock_number,null,v_backend_id,case when v_backend_id is null then null else v_record.version end,v_vehicle_id,case when v_backend_id is not null then 'navision_exact' when v_pair.stock_number is not null then 'workbook_stock_only' else 'operational_exact' end,coalesce((select jsonb_agg(distinct o.work_key order by o.work_key) from public.pdc_pmb_workbook_operation_reviews o where o.pair_id=v_pair.pair_id and o.disposition='accepted'),'[]'::jsonb),jsonb_build_object('source','pdc_pmb_retained_workbook_157','preview_id',p_preview_id,'pair_id',v_pair.pair_id,'booking_created',false,'completion_created',false,'parts_mutated',false,'location_mutated',false))
  on conflict(source_hash) do nothing returning receipt_id into v_import;
  if v_import is null then select receipt_id into strict v_import from public.pdc_authenticated_email_import_receipts where source_hash=v_pair.source_hash and actor_id=v_preview.submitted_by and vehicle_id=v_vehicle_id;end if;
  for v_op in select * from public.pdc_pmb_workbook_operation_reviews where pair_id=v_pair.pair_id and disposition='accepted' order by operation_index loop
   if exists(select 1 from public.pdc_authenticated_email_operation_lines x where x.source_hash=v_pair.source_hash and x.operation_no=v_op.operation_no and (x.vehicle_id<>v_vehicle_id or x.work_key<>v_op.work_key or x.description<>v_op.description or x.estimated_hours is distinct from v_op.estimated_hours or x.estimated_hours_source is distinct from v_op.estimated_hours_source)) then raise exception 'PDC_157_OPERATION_CONFLICT pair % operation %',v_pair.pair_no,v_op.operation_no using errcode='40001';end if;
   insert into public.pdc_authenticated_email_operation_lines(import_receipt_id,vehicle_id,source_hash,source_uid,operation_no,work_key,description,estimated_hours,estimated_hours_source,operation_fingerprint)
   values(v_import,v_vehicle_id,v_pair.source_hash,v_source_uid,v_op.operation_no,v_op.work_key,v_op.description,v_op.estimated_hours,v_op.estimated_hours_source,v_op.operation_hash)
   on conflict(source_hash,operation_no) do nothing returning operation_line_id into v_line;
   if v_line is not null then v_lines:=v_lines+1;end if;v_line:=null;v_before:=null;v_after:=null;
   select * into v_before from public.vehicle_work_items where vehicle_id=v_vehicle_id and work_key=v_op.work_key for update;
   insert into public.vehicle_work_items(vehicle_id,work_key,required,completed,completed_by,completed_at,notes,updated_at)
   values(v_vehicle_id,v_op.work_key,true,false,null,null,null,clock_timestamp())
   on conflict(vehicle_id,work_key) do update set required=true,updated_at=clock_timestamp() where not public.vehicle_work_items.completed and not public.vehicle_work_items.required returning * into v_after;
   if v_after.id is not null and (v_before.id is null or (not v_before.completed and not v_before.required)) then v_work:=v_work+1;end if;
  end loop;
  select count(*),count(*) filter(where estimated_hours is not null) into v_row_lines,v_row_hours from public.pdc_authenticated_email_operation_lines where source_hash=v_pair.source_hash;
  if v_row_lines<>(select count(*) from public.pdc_pmb_workbook_operation_reviews where pair_id=v_pair.pair_id and disposition='accepted') then raise exception 'PDC_157_OPERATION_READBACK_MISMATCH pair %',v_pair.pair_no;end if;
  v_pair_receipt_hash:=public.pdc_pmb_workbook_hash(jsonb_build_object('receipt_id',v_receipt,'pair_hash',v_pair.pair_hash,'vehicle_id',v_vehicle_id,'backend_record_id',v_backend_id,'source_hash',v_pair.source_hash,'operation_count',v_row_lines,'estimated_hours_count',v_row_hours));
  insert into public.pdc_pmb_workbook_pair_receipts(receipt_id,preview_id,pair_id,pair_no,classification,vehicle_id,backend_record_id,source_hash,operation_count,estimated_hours_count,pair_receipt_hash)
  values(v_receipt,p_preview_id,v_pair.pair_id,v_pair.pair_no,v_pair.classification,v_vehicle_id,v_backend_id,v_pair.source_hash,v_row_lines,v_row_hours,v_pair_receipt_hash);v_applied:=v_applied+1;
 end loop;
 select encode(extensions.digest(convert_to(coalesce(string_agg(pair_no::text||'|'||pair_receipt_hash,';' order by pair_no),''),'UTF8'),'sha256'),'hex') into v_pair_agg from public.pdc_pmb_workbook_pair_receipts where receipt_id=v_receipt;
 select encode(extensions.digest(convert_to(coalesce(string_agg(r.pair_no::text||'|'||o.operation_no||'|'||o.operation_fingerprint,';' order by r.pair_no,o.operation_no),''),'UTF8'),'sha256'),'hex') into v_op_agg from public.pdc_pmb_workbook_pair_receipts r join public.pdc_authenticated_email_operation_lines o on o.source_hash=r.source_hash where r.receipt_id=v_receipt;
 v_receipt_hash:=public.pdc_pmb_workbook_hash(jsonb_build_object('receipt_id',v_receipt,'preview_hash',v_preview.preview_hash,'authorization_hash',v_auth.authorization_hash,'approval_set_hash',v_approval_set_hash,'applied_pair_count',v_applied,'terminal_pair_count',v_preview.terminal_pair_count,'operation_lines_added',v_lines,'work_items_added',v_work,'vehicles_created',v_created,'pair_aggregate_sha256',v_pair_agg,'operation_aggregate_sha256',v_op_agg));
 insert into public.pdc_pmb_workbook_apply_receipts(receipt_id,preview_id,authorization_id,workbook_sha256,payload_sha256,pair_count,applied_pair_count,terminal_pair_count,operation_lines_added,work_items_added,vehicles_created,pair_aggregate_sha256,operation_aggregate_sha256,approval_set_hash,receipt_hash,applied_by,applied_email)
 values(v_receipt,p_preview_id,v_auth.authorization_id,v_preview.workbook_sha256,v_preview.payload_sha256,v_preview.pair_count,v_applied,v_preview.terminal_pair_count,v_lines,v_work,v_created,v_pair_agg,v_op_agg,v_approval_set_hash,v_receipt_hash,v_uid,v_email);
 return public.navision_backend_response(true,'workbook_applied',jsonb_build_object('receipt_id',v_receipt,'receipt_hash',v_receipt_hash,'applied_pair_count',v_applied,'terminal_pair_count',v_preview.terminal_pair_count,'operation_lines_added',v_lines,'work_items_added',v_work,'vehicles_created',v_created,'pair_aggregate_sha256',v_pair_agg,'operation_aggregate_sha256',v_op_agg,'booking_created',false,'completion_created',false,'parts_mutated',false,'location_mutated',false,'zero_add_replay',false));
end
$apply$;

revoke all on function public.preview_pdc_pmb_retained_workbook(text,text,text,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.preview_pdc_pmb_retained_workbook(text,text,text,jsonb) to authenticated;
revoke all on function public.read_pdc_pmb_workbook_pair_verification(uuid,integer,integer) from public,anon,authenticated,service_role;
grant execute on function public.read_pdc_pmb_workbook_pair_verification(uuid,integer,integer) to authenticated;
revoke all on function public.approve_pdc_pmb_workbook_pair_exception(uuid,uuid,text,text,uuid,uuid,integer,text) from public,anon,authenticated,service_role;
grant execute on function public.approve_pdc_pmb_workbook_pair_exception(uuid,uuid,text,text,uuid,uuid,integer,text) to authenticated;
revoke all on function public.authorize_pdc_pmb_workbook_apply(uuid,text,text,text,integer,integer) from public,anon,authenticated,service_role;
grant execute on function public.authorize_pdc_pmb_workbook_apply(uuid,text,text,text,integer,integer) to authenticated;
revoke all on function public.apply_pdc_pmb_retained_workbook(uuid,text,text,text) from public,anon,authenticated,service_role;
grant execute on function public.apply_pdc_pmb_retained_workbook(uuid,text,text,text) to authenticated;

comment on function public.preview_pdc_pmb_retained_workbook(text,text,text,jsonb) is 'Staging-only cap-600 exact enrolled Importer+writer Preview; immutable pair/line review, server hashes, terminal Stock13056899 exclusion, no operational mutation.';
comment on function public.read_pdc_pmb_workbook_pair_verification(uuid,integer,integer) is 'Owner Importer or Administrator bounded immutable pair verification; no raw workbook payload or customer/key data.';
comment on function public.approve_pdc_pmb_workbook_pair_exception(uuid,uuid,text,text,uuid,uuid,integer,text) is 'Administrator-only immutable pair-specific registration or Stock exception approval bound to exact hashes and target version.';
comment on function public.authorize_pdc_pmb_workbook_apply(uuid,text,text,text,integer,integer) is 'Administrator-only immutable exact Preview/hash/count Apply authorization after all pair approvals.';
comment on function public.apply_pdc_pmb_retained_workbook(uuid,text,text,text) is 'Administrator-only exact replay-safe Apply; accepted operation lines keyed by source hash and operation number; incomplete work only; no booking/completion/Parts/location mutation.';

do $verify$ declare t text;d text;begin
 foreach t in array array['pdc_pmb_workbook_previews','pdc_pmb_workbook_pair_reviews','pdc_pmb_workbook_operation_reviews','pdc_pmb_workbook_pair_approvals','pdc_pmb_workbook_apply_authorizations','pdc_pmb_workbook_apply_receipts','pdc_pmb_workbook_pair_receipts'] loop
  if to_regclass('public.'||t) is null or has_table_privilege('service_role','public.'||t,'SELECT') or has_table_privilege('service_role','public.'||t,'INSERT') or has_table_privilege('service_role','public.'||t,'UPDATE') or has_table_privilege('service_role','public.'||t,'DELETE')
    or not exists(select 1 from pg_trigger where tgrelid=to_regclass('public.'||t) and tgname=t||'_immutable' and not tgisinternal and tgenabled<>'D') then raise exception 'PDC_157_TABLE_ACL_OR_IMMUTABILITY_FAILED:%',t;end if;
 end loop;
 if has_function_privilege('service_role','public.preview_pdc_pmb_retained_workbook(text,text,text,jsonb)','EXECUTE')
   or has_function_privilege('service_role','public.apply_pdc_pmb_retained_workbook(uuid,text,text,text)','EXECUTE')
   or not has_function_privilege('authenticated','public.preview_pdc_pmb_retained_workbook(text,text,text,jsonb)','EXECUTE')
   or not has_function_privilege('authenticated','public.apply_pdc_pmb_retained_workbook(uuid,text,text,text)','EXECUTE') then raise exception 'PDC_157_RPC_ACL_FAILED';end if;
 select pg_get_functiondef('public.apply_pdc_pmb_retained_workbook(uuid,text,text,text)'::regprocedure) into d;
 if position('exact_apply_replay' in d)=0 or position('backend_revision_conflict' in d)=0 or position('where not public.vehicle_work_items.completed' in d)=0
   or position('workshop_bookings' in lower(d))>0 or position('vehicle_parts_updates' in lower(d))>0 or position('update public.vehicles' in lower(d))>0 then raise exception 'PDC_157_APPLY_DEFINITION_POSTCONDITION_FAILED';end if;
 select pg_get_functiondef('public.preview_pdc_pmb_retained_workbook(text,text,text,jsonb)'::regprocedure) into d;
 if position('between 1 and 600' in d)=0 or position('pdc_pmb_workbook_classify_identity' in d)=0 then raise exception 'PDC_157_PREVIEW_DEFINITION_POSTCONDITION_FAILED';end if;
 select pg_get_functiondef('public.pdc_pmb_workbook_classify_identity(text,text,text)'::regprocedure) into d;
 if position('13056899' in d)=0 or position('registration_identity_approval_required' in d)=0 or position('navision_board_activations' in d)=0 then raise exception 'PDC_157_IDENTITY_DEFINITION_POSTCONDITION_FAILED';end if;
 if not exists(select 1 from supabase_migrations.schema_migrations where version='124' and name='bulk_jc_stock_workbook_contract')
   or not exists(select 1 from supabase_migrations.schema_migrations where version='129' and name='bulk_stock_only_vehicle_privacy_guard') then raise exception 'PDC_157_LEGACY_ADMIN_CONTRACTS_MISSING';end if;
 insert into supabase_migrations.schema_migrations(version,name,statements) values('157','bounded_pmb_workbook_importer_review',array[
  'additive staging-only cap-600 retained PMB workbook Preview for exact enrolled active approved Importer+writer',
  'immutable pair and operation review with server hashes, backend revision and record/vehicle version binding',
  'pair-specific Administrator Stock/registration approval and exact immutable Apply authorization',
  'explicit terminal Stock13056899 exclusion and pair/line-scope conflict quarantine',
  'exact replay before operational DML; immutable Apply/pair receipts and aggregate readback hashes',
  'registration-only never creates; approved Stock-only create starts at Other; existing state/location preserved',
  'operation lines keyed source_hash plus operation_no; incomplete work only; no booking/completion/Parts/location mutation',
  'all seven evidence tables deny direct privileges including service_role; migrations124-129 unchanged'
 ]);
 insert into public.audit_events(vehicle_id,action,actor_id,actor_email,before_data,after_data,metadata)
 values(null,'insert',auth.uid(),public.current_actor_email(),null,jsonb_build_object('migration','157_bounded_pmb_workbook_importer_review'),jsonb_build_object('source','staging_migration_157','environment','staging','production_unchanged',true));
end $verify$;
commit;
