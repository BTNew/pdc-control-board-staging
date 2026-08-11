-- Staging-only append fix: multiple retained job cards may share one canonical Navision backend/vehicle.
begin;
do $guard$ begin
 if not public.pdc_monitor_staging_guard() then raise exception 'PDC_164_STAGING_ONLY'; end if;
 if not exists(select 1 from supabase_migrations.schema_migrations where version='163' and name='canonical_activation_runtime_ambiguity_fix') or exists(select 1 from supabase_migrations.schema_migrations where version>'163') then raise exception 'PDC_164_PREDECESSOR_MISMATCH'; end if;
end $guard$;
create or replace function public.apply_pdc_pmb_canonical_activations(
 p_authorization_id uuid,p_workbook_sha256 text,p_payload_sha256 text,p_expected_activation_count integer,p_confirmation text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions set statement_timeout='300s' as $apply$
#variable_conflict use_column
declare uid uuid:=auth.uid();actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));au public.pdc_pmb_canonical_apply_authorizations%rowtype;
 pr public.pdc_pmb_workbook_previews%rowtype;old public.pdc_pmb_canonical_apply_receipts%rowtype;m public.pdc_pmb_canonical_manager_approvals%rowtype;
 a public.pdc_pmb_canonical_admin_countersignatures%rowtype;c jsonb;r public.navision_backend_records%rowtype;v public.vehicles%rowtype;
 activation public.navision_board_activations%rowtype;receipt uuid:=gen_random_uuid();rev bigint;next_rev bigint;cnt integer;
 created integer:=0;reactivated integer:=0;set_hash text;source_pair_hash text;source_hash text;pair_receipt_hash text;pair_agg text;receipt_hash text;vehicle_id uuid;
begin
 if not public.pdc_monitor_staging_guard() or uid is null or actor_email='' or p_confirmation<>'APPLY MANAGER APPROVED CANONICAL ACTIVATIONS'
   or coalesce(p_expected_activation_count,0) not between 1 and 600 then return public.navision_backend_response(false,'invalid_canonical_apply');end if;
 perform pg_advisory_xact_lock(hashtextextended('navision-backend-store',0));
 perform pg_advisory_xact_lock(hashtextextended('pdc-pmb-canonical-apply:'||p_authorization_id::text,0));
 select * into au from public.pdc_pmb_canonical_apply_authorizations where authorization_id=p_authorization_id for share;
 if not found then return public.navision_backend_response(false,'canonical_authorization_missing');end if;
 select * into pr from public.pdc_pmb_workbook_previews where preview_id=au.preview_id for share;
 if not found or au.workbook_sha256<>lower(btrim(coalesce(p_workbook_sha256,''))) or au.payload_sha256<>lower(btrim(coalesce(p_payload_sha256,'')))
   or au.expected_activation_count<>p_expected_activation_count then
  return public.navision_backend_response(false,'canonical_apply_binding_mismatch');end if;
 perform 1 from public.pdc_user_roles x where x.auth_user_id=uid and lower(x.email)=actor_email and x.role='administrator'
   and x.active and x.account_status='approved' for share;
 if not found then return public.navision_backend_response(false,'administrator_required');end if;
 select * into old from public.pdc_pmb_canonical_apply_receipts where authorization_id=au.authorization_id;
 if found then return public.navision_backend_response(true,'exact_canonical_apply_replay',jsonb_build_object('receipt_id',old.receipt_id,
  'receipt_hash',old.receipt_hash,'activated_pair_count',old.activated_pair_count,'vehicles_created',old.vehicles_created,
  'vehicles_reactivated',old.vehicles_reactivated,'repreview_required',true,'zero_add_replay',true));end if;
 if au.expires_at<=clock_timestamp() then
  return public.navision_backend_response(false,'canonical_authorization_expired');end if;
 -- Close the empty-identity race before taking any row lock. These locks
 -- conflict with every Navision/activation/vehicle/alias INSERT or UPDATE,
 -- including writers that do not participate in the canonical advisory locks.
 lock table public.navision_backend_records in share row exclusive mode;
 lock table public.navision_board_activations in share row exclusive mode;
 lock table public.vehicles in share row exclusive mode;
 lock table public.vehicle_aliases in share row exclusive mode;
 for m in select * from public.pdc_pmb_canonical_manager_approvals where preview_id=au.preview_id order by pair_id loop
  perform pg_advisory_xact_lock(hashtextextended('pdc-pmb-canonical-pair:'||m.pair_id::text,0));
  perform 1 from public.navision_backend_records where id=m.backend_record_id for update;
  if m.target_vehicle_id is not null then perform pg_advisory_xact_lock(hashtextextended('pdc:board-purge:'||m.target_vehicle_id::text,0));perform 1 from public.vehicles where id=m.target_vehicle_id for update;end if;
 end loop;
 select revision into rev from public.navision_backend_revision where singleton for update;
 if rev is distinct from au.backend_revision then return public.navision_backend_response(false,'backend_revision_conflict');end if;
 create temporary table if not exists pg_temp.pdc162_candidates(pair_id uuid primary key,manager_approval_id uuid,action text,backend_id uuid,
  backend_version integer,vehicle_id uuid,vehicle_version integer) on commit drop;
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
 if exists(select 1 from pg_temp.pdc162_candidates group by backend_id having count(distinct (action,backend_version,vehicle_id,vehicle_version))>1) then return public.navision_backend_response(false,'canonical_duplicate_backend_binding_conflict');end if;
 if exists(select 1 from pg_temp.pdc162_candidates where vehicle_id is not null group by vehicle_id having count(distinct backend_id)>1) then return public.navision_backend_response(false,'canonical_vehicle_multiple_backend_conflict');end if;
 if exists(
  select 1 from pg_temp.pdc162_candidates f join public.navision_backend_records r on r.id=f.backend_id
  where public.is_valid_vehicle_vin(r.normalized_data->>'vin')
  group by public.normalize_vehicle_vin(r.normalized_data->>'vin') having count(distinct f.backend_id)>1
 ) then return public.navision_backend_response(false,'canonical_batch_cross_pair_vin_conflict');end if;
 select public.pdc_pmb_workbook_hash(coalesce(jsonb_agg(jsonb_build_object('pair_no',p.pair_no,'pair_hash',p.pair_hash,
  'source_hash',p.source_hash,'manager_approval_hash',m.approval_hash,'administrator_countersignature_hash',a.countersignature_hash,
  'action',m.action,'backend_record_id',m.backend_record_id,'backend_record_version',m.backend_record_version,'target_vehicle_id',m.target_vehicle_id,
  'target_vehicle_version',m.target_vehicle_version) order by p.pair_no),'[]'::jsonb)) into set_hash
 from public.pdc_pmb_canonical_manager_approvals m join public.pdc_pmb_canonical_admin_countersignatures a on a.manager_approval_id=m.approval_id
 join public.pdc_pmb_workbook_pair_reviews p on p.pair_id=m.pair_id where m.preview_id=au.preview_id;
 if set_hash is distinct from au.approval_set_hash then return public.navision_backend_response(false,'canonical_approval_set_hash_conflict');end if;
 -- All validation is complete. Activate each canonical backend record exactly once; multiple retained job-card pairs may bind to the same vehicle.
 for m in select distinct on (m.backend_record_id) m.* from public.pdc_pmb_canonical_manager_approvals m join public.pdc_pmb_workbook_pair_reviews p on p.pair_id=m.pair_id where m.preview_id=au.preview_id order by m.backend_record_id,p.pair_no loop
  select * into strict r from public.navision_backend_records where id=m.backend_record_id for update;
  if m.action='reactivate_complete_board_purge' then
   update public.vehicles set lifecycle_state='active',visible_on_board=true,deleted_at=null,deleted_reason=null,board_purged_at=null,board_purge_reason=null,board_purged_by=null,version=version+1,updated_by=uid,updated_at=clock_timestamp() where id=m.target_vehicle_id returning * into v;
   update public.navision_board_activations set active=true,activation_source='manual',activated_stock_number=r.normalized_data->>'batch',activated_at=clock_timestamp(),activated_by=uid,activated_by_email=actor_email,canonical_vehicle_id=v.id,completed_at=null,completion_reason=null,completed_by=null,completed_by_email=null,updated_at=clock_timestamp() where backend_record_id=r.id returning * into activation;
   if activation.backend_record_id is null then raise exception 'PDC_164_REACTIVATION_BINDING_LOST:%',m.pair_id using errcode='40001';end if;reactivated:=reactivated+1;
  else
   insert into public.navision_board_activations(backend_record_id,activation_source,activated_stock_number,activated_by,activated_by_email,active) values(r.id,'manual',r.normalized_data->>'batch',uid,actor_email,true) returning * into activation;created:=created+1;
  end if;
 end loop;
 -- Preserve one immutable receipt per approved pair, including extra job cards sharing a canonical vehicle.
 for m in select m.* from public.pdc_pmb_canonical_manager_approvals m join public.pdc_pmb_workbook_pair_reviews p on p.pair_id=m.pair_id where m.preview_id=au.preview_id order by p.pair_no loop
  select * into strict r from public.navision_backend_records where id=m.backend_record_id;
  select nba.canonical_vehicle_id into vehicle_id from public.navision_board_activations nba where nba.backend_record_id=r.id and nba.active and nba.completed_at is null;
  select * into v from public.vehicles where id=vehicle_id;
  if not found or v.deleted_at is not null or v.lifecycle_state<>'active' or not v.visible_on_board or v.board_purged_at is not null or v.rft_collected_at is not null or public.normalize_vehicle_stock_number(v.stock_number) is distinct from public.normalize_vehicle_stock_number(r.normalized_data->>'batch') then raise exception 'PDC_164_CANONICAL_POSTCONDITION_FAILED:%',m.pair_id using errcode='40001';end if;
  select * into r from public.navision_backend_records where id=m.backend_record_id;if not found or r.canonical_vehicle_id is distinct from v.id then raise exception 'PDC_164_CANONICAL_BACKEND_BINDING_FAILED:%',m.pair_id using errcode='40001';end if;
  select * into a from public.pdc_pmb_canonical_admin_countersignatures where manager_approval_id=m.approval_id;select p.pair_hash,p.source_hash into strict source_pair_hash,source_hash from public.pdc_pmb_workbook_pair_reviews p where p.pair_id=m.pair_id;
  pair_receipt_hash:=public.pdc_pmb_workbook_hash(jsonb_build_object('receipt_id',receipt,'pair_hash',source_pair_hash,'source_hash',source_hash,'backend_record_id',r.id,'vehicle_id',v.id,'action',m.action,'manager_approval_hash',m.approval_hash,'administrator_countersignature_hash',a.countersignature_hash));
  insert into public.pdc_pmb_canonical_pair_receipts(receipt_id,preview_id,pair_id,pair_no,pair_hash,source_hash,backend_record_id,vehicle_id,action,manager_approval_hash,administrator_countersignature_hash,pair_receipt_hash) select receipt,au.preview_id,p.pair_id,p.pair_no,p.pair_hash,p.source_hash,r.id,v.id,m.action,m.approval_hash,a.countersignature_hash,pair_receipt_hash from public.pdc_pmb_workbook_pair_reviews p where p.pair_id=m.pair_id;
 end loop;
 select revision into next_rev from public.navision_backend_revision where singleton;
 if next_rev is distinct from rev+created+reactivated then
  raise exception 'PDC_164_BACKEND_REVISION_POSTCONDITION_FAILED expected %, got %',rev+created+reactivated,next_rev using errcode='40001';
 end if;
 select encode(extensions.digest(convert_to(string_agg(pair_no::text||'|'||pair_receipt_hash,';' order by pair_no),'UTF8'),'sha256'),'hex')
 into pair_agg from public.pdc_pmb_canonical_pair_receipts where receipt_id=receipt;
 receipt_hash:=public.pdc_pmb_workbook_hash(jsonb_build_object('contract','pdc_pmb_canonical_apply_receipt_162','receipt_id',receipt,
  'authorization_hash',au.authorization_hash,'preview_hash',pr.preview_hash,'approval_set_hash',set_hash,'backend_revision_before',rev,
  'backend_revision_after',next_rev,'activated_pair_count',cnt,'vehicles_created',created,'vehicles_reactivated',reactivated,'pair_aggregate_sha256',pair_agg));
 insert into public.pdc_pmb_canonical_apply_receipts(receipt_id,authorization_id,preview_id,workbook_sha256,payload_sha256,
  backend_revision_before,backend_revision_after,activated_pair_count,vehicles_created,vehicles_reactivated,approval_set_hash,pair_aggregate_sha256,
  receipt_hash,applied_by,applied_email) values(receipt,au.authorization_id,au.preview_id,au.workbook_sha256,au.payload_sha256,rev,next_rev,cnt,
  created,reactivated,set_hash,pair_agg,receipt_hash,uid,actor_email);
 insert into public.navision_backend_audit(action,revision,evidence,actor_id,actor_email)
 values('board_activate',next_rev,jsonb_build_object('contract','pdc_pmb_canonical_activation_162','preview_id',au.preview_id,
  'workbook_sha256',au.workbook_sha256,'payload_sha256',au.payload_sha256,'approval_set_hash',set_hash,'activated_pair_count',cnt,
  'vehicles_created',created,'vehicles_reactivated',reactivated,'receipt_id',receipt,'receipt_hash',receipt_hash,
  'manager_and_administrator_pair_approval',true,'repreview_required',true,'booking_mutated',false,'completion_mutated',false,
  'parts_mutated',false,'work_mutated',false),uid,actor_email);
 return public.navision_backend_response(true,'canonical_activations_applied',jsonb_build_object('receipt_id',receipt,'receipt_hash',receipt_hash,
  'activated_pair_count',cnt,'vehicles_created',created,'vehicles_reactivated',reactivated,'backend_revision',next_rev,
  'pair_aggregate_sha256',pair_agg,'repreview_required',true,'migration157_apply_not_bypassed',true,'booking_mutated',false,
  'completion_mutated',false,'parts_mutated',false,'work_mutated',false,'zero_add_replay',false));
end $apply$;

revoke all on function public.apply_pdc_pmb_canonical_activations(uuid,text,text,integer,text) from public,anon,authenticated,service_role;
grant execute on function public.apply_pdc_pmb_canonical_activations(uuid,text,text,integer,text) to authenticated;
insert into supabase_migrations.schema_migrations(version,name,statements) values('164','canonical_activation_shared_vehicle_pairs',array['Activate each distinct canonical backend exactly once while retaining immutable receipts for every approved workbook pair.']);
notify pgrst,'reload schema';
commit;
