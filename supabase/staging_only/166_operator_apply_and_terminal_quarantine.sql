-- Staging-only append fix: terminal Stock 13056899 remains quarantined rather than blocking the entire batch,
-- and the final Apply actor is a separately approved active Operator instead of the authorizing Administrator.
begin;
do $guard$ begin
 if not public.pdc_monitor_staging_guard() then raise exception 'PDC_166_STAGING_ONLY';end if;
 if not exists(select 1 from supabase_migrations.schema_migrations where version='165' and name='receipt_bound_retained_jobcard_classification') or exists(select 1 from supabase_migrations.schema_migrations where version>'165') then raise exception 'PDC_166_PREDECESSOR_MISMATCH';end if;
end $guard$;

-- Canonical identity belongs only to live rows. Soft-deleted rows remain immutable audit evidence
-- but must not prevent a new live vehicle from taking the same exact identity.
drop index if exists public.vehicles_master_stock_unique_idx;
create unique index vehicles_master_stock_unique_idx on public.vehicles(stock_number_normalized)
 where deleted_at is null and public.is_real_vehicle_stock_number(stock_number);
drop index if exists public.vehicles_master_vin_unique_idx;
create unique index vehicles_master_vin_unique_idx on public.vehicles(vin_normalized)
 where deleted_at is null and public.is_valid_vehicle_vin(vin);
drop index if exists public.vehicles_master_source_unique_idx;
create unique index vehicles_master_source_unique_idx on public.vehicles(source_system_normalized,source_record_id_normalized)
 where deleted_at is null and source_system_normalized is not null and source_record_id_normalized is not null;

-- Soft-deleted historical rows are audit evidence, not active identity owners.
create or replace function public.enforce_vehicle_master_identity_uniqueness()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if nullif(btrim(new.vin), '') is not null
     and not public.is_valid_vehicle_vin(new.vin)
     and (tg_op = 'INSERT' or old.vin is distinct from new.vin) then
    raise exception 'invalid VIN'
      using errcode = '23514',
            detail = public.vehicle_master_response(false, 'invalid_value', jsonb_build_object('field', 'vin'))::text;
  end if;

  if public.is_valid_vehicle_vin(new.vin) then
    perform pg_advisory_xact_lock(hashtextextended(
      'vehicle-master:vin:' || public.normalize_vehicle_vin(new.vin), 0
    ));
    if exists (
      select 1 from public.vehicles v
      where v.id <> new.id
        and v.deleted_at is null
        and public.is_valid_vehicle_vin(v.vin)
        and v.vin_normalized = public.normalize_vehicle_vin(new.vin)
    ) then
      raise exception 'duplicate canonical VIN'
        using errcode = '23505',
              detail = public.vehicle_master_response(false, 'duplicate_candidate', jsonb_build_object('field', 'vin'))::text;
    end if;
    if exists (
      select 1 from public.vehicle_aliases a
      join public.vehicles owner on owner.id=a.vehicle_id and owner.deleted_at is null
      where a.vehicle_id <> new.id
        and a.active
        and a.alias_type_normalized = 'vin'
        and a.normalized_alias_value = public.normalize_vehicle_vin(new.vin)
    ) then
      raise exception 'canonical VIN conflicts with another vehicle alias'
        using errcode = '23505',
              detail = public.vehicle_master_response(false, 'conflicting_candidate', jsonb_build_object('field', 'vin'))::text;
    end if;
  end if;

  if public.is_real_vehicle_stock_number(new.stock_number) then
    perform pg_advisory_xact_lock(hashtextextended(
      'vehicle-master:stock_number:' || public.normalize_vehicle_stock_number(new.stock_number), 0
    ));
    if exists (
      select 1 from public.vehicles v
      where v.id <> new.id
        and v.deleted_at is null
        and public.is_real_vehicle_stock_number(v.stock_number)
        and v.stock_number_normalized = public.normalize_vehicle_stock_number(new.stock_number)
    ) then
      raise exception 'duplicate canonical stock number'
        using errcode = '23505',
              detail = public.vehicle_master_response(false, 'duplicate_candidate', jsonb_build_object('field', 'stock_number'))::text;
    end if;
    if exists (
      select 1 from public.vehicle_aliases a
      join public.vehicles owner on owner.id=a.vehicle_id and owner.deleted_at is null
      where a.vehicle_id <> new.id
        and a.active
        and a.alias_type_normalized = 'stock_number'
        and a.normalized_alias_value = public.normalize_vehicle_stock_number(new.stock_number)
    ) then
      raise exception 'canonical stock number conflicts with another vehicle alias'
        using errcode = '23505',
              detail = public.vehicle_master_response(false, 'conflicting_candidate', jsonb_build_object('field', 'stock_number'))::text;
    end if;
  end if;

  if public.normalize_vehicle_source_system(new.source_system) is not null
     and public.normalize_vehicle_source_identifier(new.source_record_id) is not null then
    perform pg_advisory_xact_lock(hashtextextended(
      'vehicle-master:source:' || public.normalize_vehicle_source_system(new.source_system)
        || ':' || public.normalize_vehicle_source_identifier(new.source_record_id), 0
    ));
    if exists (
      select 1 from public.vehicles v
      where v.id <> new.id
        and v.deleted_at is null
        and v.source_system_normalized = public.normalize_vehicle_source_system(new.source_system)
        and v.source_record_id_normalized = public.normalize_vehicle_source_identifier(new.source_record_id)
    ) then
      raise exception 'duplicate source-scoped vehicle identifier'
        using errcode = '23505',
              detail = public.vehicle_master_response(false, 'duplicate_candidate', jsonb_build_object('field', 'source_record_id'))::text;
    end if;
  end if;

  return new;
end;
$$;
revoke all on function public.enforce_vehicle_master_identity_uniqueness() from public,anon,authenticated,service_role;
create or replace function public.pdc_pmb_workbook_operator_scope()
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $scope$
declare v_uid uuid:=auth.uid();v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));v_count integer;
begin
 if not public.pdc_monitor_staging_guard() or v_uid is null or v_email='' then return public.navision_backend_response(false,'unauthorized');end if;
 select count(*) into v_count from public.pdc_user_roles r join auth.users u on u.id=v_uid and lower(u.email)=v_email
 where r.auth_user_id=v_uid and lower(r.email)=v_email and r.role='operator' and r.active and r.account_status='approved';
 if v_count<>1 then return public.navision_backend_response(false,'operator_required');end if;
 return public.navision_backend_response(true,'authorized_operator',jsonb_build_object('actor_id',v_uid,'actor_email',v_email));
end
$scope$;
revoke all on function public.pdc_pmb_workbook_operator_scope() from public,anon,authenticated,service_role;

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
 if v_preview.expires_at<=clock_timestamp() or exists(select 1 from public.pdc_pmb_workbook_pair_reviews where preview_id=p_preview_id and stock_number='13056899' and classification in('exact_current_stock','no_current_stock_manager_override_required','registration_identity_approval_required')) then return public.navision_backend_response(false,'preview_expired_or_excluded_stock13056899');end if;
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
 v_scope:=public.pdc_pmb_workbook_operator_scope();if not coalesce((v_scope->>'ok')::boolean,false) then return v_scope;end if;
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
 v_scope:=public.pdc_pmb_workbook_operator_scope();if not coalesce((v_scope->>'ok')::boolean,false) then return v_scope;end if;v_uid:=(v_scope->'data'->>'actor_id')::uuid;v_email:=v_scope->'data'->>'actor_email';
 perform 1 from public.pdc_user_roles r where r.auth_user_id=v_uid and r.role='operator' and r.active and r.account_status='approved' for share;if not found then return public.navision_backend_response(false,'operator_required');end if;
 -- Exact replay is before every operational INSERT/UPDATE.
 select ar.* into v_existing from public.pdc_pmb_workbook_apply_receipts ar join public.pdc_pmb_workbook_previews p using(preview_id)
 where p.workbook_sha256=v_preview.workbook_sha256 and p.payload_sha256=v_preview.payload_sha256
 order by ar.applied_at desc,ar.receipt_id desc limit 1;
 if found then return public.navision_backend_response(true,case when v_existing.preview_id=p_preview_id then 'exact_apply_replay' else 'exact_workbook_apply_replay' end,jsonb_build_object('receipt_id',v_existing.receipt_id,'receipt_hash',v_existing.receipt_hash,'applied_preview_id',v_existing.preview_id,'applied_pair_count',v_existing.applied_pair_count,'operation_lines_added',v_existing.operation_lines_added,'work_items_added',v_existing.work_items_added,'vehicles_created',v_existing.vehicles_created,'zero_add_replay',true));end if;
 if v_auth.workbook_sha256<>v_preview.workbook_sha256 or v_auth.payload_sha256<>v_preview.payload_sha256 or v_auth.expected_pair_count<>v_preview.pair_count or v_auth.expected_operation_count<>v_preview.operation_count or v_auth.expires_at<=clock_timestamp() then return public.navision_backend_response(false,'immutable_authorization_binding_mismatch_or_expired');end if;
 if exists(select 1 from public.pdc_pmb_workbook_pair_reviews where preview_id=p_preview_id and stock_number='13056899' and classification in('exact_current_stock','no_current_stock_manager_override_required','registration_identity_approval_required')) then return public.navision_backend_response(false,'excluded_stock13056899');end if;
 select revision into v_revision from public.navision_backend_revision where singleton;if v_revision is distinct from v_preview.backend_revision or v_revision is distinct from v_auth.backend_revision then return public.navision_backend_response(false,'backend_revision_conflict');end if;
 select public.pdc_pmb_workbook_hash(coalesce(jsonb_agg(jsonb_build_object('pair_no',r.pair_no,'pair_hash',r.pair_hash,'approval_hash',a.approval_hash) order by r.pair_no),'[]'::jsonb)) into v_approval_set_hash
 from public.pdc_pmb_workbook_pair_reviews r left join public.pdc_pmb_workbook_pair_approvals a using(preview_id,pair_id)
 where r.preview_id=p_preview_id and r.classification in('no_current_stock_manager_override_required','registration_identity_approval_required');
 if v_approval_set_hash is distinct from v_auth.approval_set_hash then return public.navision_backend_response(false,'approval_set_hash_conflict');end if;
 -- Freeze and validate every identity before the first operational mutation. This prevents
 -- one approved Stock-only pair from changing how a later pair for the same Stock classifies.
 for v_pair in select * from public.pdc_pmb_workbook_pair_reviews where preview_id=p_preview_id and classification in('exact_current_stock','no_current_stock_manager_override_required','registration_identity_approval_required') order by pair_no loop
  v_identity:=public.pdc_pmb_workbook_classify_identity(v_pair.stock_number,v_pair.registration,v_pair.job_card_number);
  if v_identity->>'classification' is distinct from v_pair.classification
    or nullif(v_identity->>'backend_record_id','')::uuid is distinct from v_pair.backend_record_id
    or nullif(v_identity->>'backend_record_version','')::integer is distinct from v_pair.backend_record_version
    or nullif(v_identity->>'vehicle_id','')::uuid is distinct from v_pair.vehicle_id
    or nullif(v_identity->>'vehicle_version','')::integer is distinct from v_pair.vehicle_version then
   raise exception 'PDC_157_PAIR_IDENTITY_DRIFT pair %',v_pair.pair_no using errcode='40001';
  end if;
 end loop;
 for v_pair in select * from public.pdc_pmb_workbook_pair_reviews where preview_id=p_preview_id and classification in('exact_current_stock','no_current_stock_manager_override_required','registration_identity_approval_required') order by pair_no loop
  v_approval:=null;v_vehicle:=null;v_record:=null;select * into v_approval from public.pdc_pmb_workbook_pair_approvals where preview_id=p_preview_id and pair_id=v_pair.pair_id;
  v_backend_id:=coalesce(v_approval.target_backend_record_id,v_pair.backend_record_id);v_vehicle_id:=coalesce(v_approval.target_vehicle_id,v_pair.vehicle_id);
  if v_backend_id is not null then select * into v_record from public.navision_backend_records where id=v_backend_id;if not found or not v_record.is_current or v_record.record_status<>'current' or (v_pair.backend_record_id=v_backend_id and v_record.version<>v_pair.backend_record_version) then raise exception 'PDC_157_BACKEND_RECORD_VERSION_CONFLICT pair %',v_pair.pair_no using errcode='40001';end if;end if;
  if v_vehicle_id is not null then select * into v_vehicle from public.vehicles where id=v_vehicle_id;if not found or v_vehicle.deleted_at is not null or v_vehicle.lifecycle_state<>'active' or v_vehicle.version<>coalesce(v_approval.target_vehicle_version,v_pair.vehicle_version) then raise exception 'PDC_157_VEHICLE_VERSION_CONFLICT pair %',v_pair.pair_no using errcode='40001';end if;
  else
   if v_approval.decision is distinct from 'approve_stock_only_create' or v_pair.stock_number is null then raise exception 'PDC_157_CREATE_APPROVAL_REQUIRED pair %',v_pair.pair_no;end if;
   v_vehicle_id:=extensions.uuid_generate_v5('b58b5f75-d004-5a76-b9aa-48c801b4ad7d'::uuid,'pmb157:'||v_preview.workbook_sha256||':'||v_pair.stock_number);
   select * into v_vehicle from public.vehicles where id=v_vehicle_id;
   if found then
    if v_vehicle.deleted_at is not null or v_vehicle.lifecycle_state<>'active' or not v_vehicle.visible_on_board
      or v_vehicle.source_system<>'pdc_pmb_workbook' or v_vehicle.source_batch_id<>v_preview.workbook_sha256
      or public.normalize_vehicle_stock_number(v_vehicle.stock_number) is distinct from v_pair.stock_number then
     raise exception 'PDC_157_SHARED_STOCK_CREATE_CONFLICT pair %',v_pair.pair_no using errcode='40001';
    end if;
   else
    if exists(select 1 from public.vehicles x where x.deleted_at is null and public.normalize_vehicle_stock_number(x.stock_number)=v_pair.stock_number) then raise exception 'PDC_157_STOCK_CREATE_CONFLICT pair %',v_pair.pair_no using errcode='40001';end if;
    insert into public.vehicles(id,permanent_vehicle_id,stock_number,job_card_number,lifecycle_state,visible_on_board,current_location,source_system,source_batch_id,source_record_id,source_payload,created_by,updated_by)
    values(v_vehicle_id,'PDC-PMB-'||upper(substr(v_pair.source_hash,1,24)),v_pair.stock_number,v_pair.job_card_number,'active',true,'Other','pdc_pmb_workbook',v_preview.workbook_sha256,v_pair.pair_id::text,jsonb_build_object('intake_contract','pdc_pmb_retained_workbook_157','preview_id',p_preview_id,'pair_hash',v_pair.pair_hash,'stock_only',true,'privacy_preserved',true),v_uid,v_uid);
    v_created:=v_created+1;select * into strict v_vehicle from public.vehicles where id=v_vehicle_id;
   end if;
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

revoke all on function public.authorize_pdc_pmb_workbook_apply(uuid,text,text,text,integer,integer) from public,anon,authenticated,service_role;
grant execute on function public.authorize_pdc_pmb_workbook_apply(uuid,text,text,text,integer,integer) to authenticated;
revoke all on function public.apply_pdc_pmb_retained_workbook(uuid,text,text,text) from public,anon,authenticated,service_role;
grant execute on function public.apply_pdc_pmb_retained_workbook(uuid,text,text,text) to authenticated;
insert into supabase_migrations.schema_migrations(version,name,statements) values('166','operator_apply_and_terminal_quarantine',array['Keep terminal Stock 13056899 quarantined without blocking eligible pairs; require a separately approved active Operator for Apply.']);
notify pgrst,'reload schema';
commit;