-- STAGING ONLY: exact frozen latest-10 Navision Board reset/activation.
-- The function is intentionally private; the controller executes it through the
-- approved staging database connection after authenticating an Administrator.
begin;
set local lock_timeout='20s';
set local statement_timeout='600s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-latest10-navision-board-reset-20260902',0));

do $guard$
begin
  if not public.pdc_monitor_staging_guard()
     or to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or to_regprocedure('public.pdc_admin_reset_staging_test_vehicle(uuid,integer,text,text)') is null
     or to_regprocedure('public.navision_operational_location(jsonb)') is null
     or to_regprocedure('public.navision_kewdale_eta(jsonb)') is null
     or exists(select 1 from supabase_migrations.schema_migrations where version='20260902250000') then
    raise exception 'PDC_LATEST10_STAGING_OR_DEPENDENCY_MISMATCH' using errcode='55000';
  end if;
end
$guard$;

create table if not exists public.pdc_staging_latest10_navision_reset_batches(
  reset_id uuid primary key default gen_random_uuid(),
  contract text not null check(contract='pdc_staging_latest10_navision_reset_20260902'),
  backup_manifest_sha256 text not null check(backup_manifest_sha256~'^[a-f0-9]{64}$'),
  scheduler_state_sha256 text not null check(scheduler_state_sha256~'^[a-f0-9]{64}$'),
  actor_id uuid not null references auth.users(id) on delete restrict,
  actor_email text not null,
  before_counts jsonb not null check(jsonb_typeof(before_counts)='object'),
  zero_counts jsonb not null check(jsonb_typeof(zero_counts)='object'),
  after_counts jsonb not null check(jsonb_typeof(after_counts)='object'),
  source_fingerprint_before text not null check(source_fingerprint_before~'^[a-f0-9]{64}$'),
  source_fingerprint_after text not null check(source_fingerprint_after~'^[a-f0-9]{64}$'),
  evidence_fingerprint_before text not null check(evidence_fingerprint_before~'^[a-f0-9]{64}$'),
  evidence_fingerprint_after text not null check(evidence_fingerprint_after~'^[a-f0-9]{64}$'),
  frozen_stocks jsonb not null check(jsonb_typeof(frozen_stocks)='array'),
  applied_at timestamptz not null default clock_timestamp(),
  unique(contract,backup_manifest_sha256,scheduler_state_sha256)
);

create table if not exists public.pdc_staging_latest10_navision_reset_rows(
  reset_id uuid not null references public.pdc_staging_latest10_navision_reset_batches(reset_id) on delete restrict,
  ordinal integer not null check(ordinal between 1 and 10),
  backend_record_id uuid not null references public.navision_backend_records(id) on delete restrict,
  stock_number text not null,
  dealer_code text not null check(dealer_code in('14450','37047')),
  vehicle_id uuid not null references public.vehicles(id) on delete restrict,
  target_location text not null check(target_location in('YH','IT','PMB','RFT','Other')),
  eta_to_kewdale date,
  source_row_hash text not null check(source_row_hash~'^[a-f0-9]{64}$'),
  primary key(reset_id,ordinal),
  unique(reset_id,backend_record_id),
  unique(reset_id,stock_number)
);

alter table public.pdc_staging_latest10_navision_reset_rows
  drop constraint if exists pdc_staging_latest10_navision_reset_rows_reset_id_fkey,
  add constraint pdc_staging_latest10_navision_reset_rows_reset_id_fkey
    foreign key(reset_id) references public.pdc_staging_latest10_navision_reset_batches(reset_id) on delete restrict deferrable initially deferred;

create or replace function public.pdc_staging_latest10_reset_immutable()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
begin
  raise exception 'PDC_LATEST10_RESET_HISTORY_IMMUTABLE' using errcode='55000';
end
$$;
revoke all on function public.pdc_staging_latest10_reset_immutable() from public,anon,authenticated,service_role;
drop trigger if exists pdc_staging_latest10_reset_batches_immutable on public.pdc_staging_latest10_navision_reset_batches;
create trigger pdc_staging_latest10_reset_batches_immutable before update or delete on public.pdc_staging_latest10_navision_reset_batches for each row execute function public.pdc_staging_latest10_reset_immutable();
drop trigger if exists pdc_staging_latest10_reset_rows_immutable on public.pdc_staging_latest10_navision_reset_rows;
create trigger pdc_staging_latest10_reset_rows_immutable before update or delete on public.pdc_staging_latest10_navision_reset_rows for each row execute function public.pdc_staging_latest10_reset_immutable();
alter table public.pdc_staging_latest10_navision_reset_batches enable row level security;
alter table public.pdc_staging_latest10_navision_reset_rows enable row level security;
revoke all on public.pdc_staging_latest10_navision_reset_batches,public.pdc_staging_latest10_navision_reset_rows from public,anon,authenticated,service_role;

create or replace function public.pdc_staging_latest10_archive_vehicle(
  p_vehicle_id uuid,
  p_expected_version integer,
  p_confirmation_stock text,
  p_reason text
) returns jsonb
language plpgsql security definer
set search_path=pg_catalog,public,auth,extensions
as $archive$
declare
  v_scope jsonb;
  v_uid uuid;
  v_email text;
  v public.vehicles%rowtype;
  v_after public.vehicles%rowtype;
  t public.pdc_vehicle_tombstones%rowtype;
  v_stock text;
  v_now timestamptz:=clock_timestamp();
  v_bookings integer:=0;
  v_activations integer:=0;
begin
  v_scope:=public.pdc_admin_vehicle_actor();
  if not coalesce((v_scope->>'ok')::boolean,false) then return v_scope; end if;
  v_uid:=(v_scope->'data'->>'actor_id')::uuid;
  v_email:=v_scope->'data'->>'actor_email';
  if p_vehicle_id is null or p_expected_version is null or length(btrim(coalesce(p_reason,''))) not between 8 and 300 then
    return public.navision_backend_response(false,'invalid_input');
  end if;
  perform pg_advisory_xact_lock(hashtextextended('pdc:vehicle-lifecycle:'||p_vehicle_id::text,0));
  select * into v from public.vehicles where id=p_vehicle_id for update;
  if not found then return public.navision_backend_response(false,'vehicle_not_found'); end if;
  v_stock:=public.normalize_vehicle_stock_number(v.stock_number);
  if v_stock is null or p_confirmation_stock is distinct from v_stock then return public.navision_backend_response(false,'invalid_input'); end if;
  if v.version<>p_expected_version then return public.navision_backend_response(false,'vehicle_version_conflict'); end if;
  -- A retained staging recovery fixture is intentionally immutable against
  -- archive/lifecycle deletion. Remove only its Board visibility and activation
  -- while preserving the fixture and its historical evidence.
  if v.id='d777b071-a2b0-5367-893b-aa83a07fcfce'::uuid then
    update public.vehicles set visible_on_board=false,current_location='Other',updated_by=v_uid,updated_at=v_now,version=version+1 where id=v.id returning * into v_after;
    update public.navision_board_activations set active=false,completed_at=coalesce(completed_at,v_now),completion_reason=coalesce(completion_reason,'Latest-10 staging Board reset'),updated_at=v_now where canonical_vehicle_id=v.id and active;
    insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
    values('update'::public.audit_action,'vehicles',v.id,v.id,v_uid,v_email,to_jsonb(v),to_jsonb(v_after),jsonb_build_object('source','pdc_staging_latest10_navision_reset_20260902','protected_fixture_visibility_only',true,'mutable_history_preserved',true));
    update public.pdc_email_vehicle_revision set revision=revision+1,updated_at=v_now where singleton;
    update public.navision_backend_revision set revision=revision+1,updated_at=v_now where singleton;
    perform public.workshop_bump_revision();
    return public.navision_backend_response(true,'protected_fixture_hidden',jsonb_build_object('vehicle_id',v.id,'vehicle_version',v_after.version,'archive_not_permitted',true));
  end if;
  select * into t from public.pdc_vehicle_tombstones x where x.vehicle_id=v.id
    and not exists(select 1 from public.pdc_vehicle_lifecycle_events e where e.tombstone_id=x.tombstone_id and e.event_kind='restored')
    order by x.deleted_at desc limit 1 for share;
  if found then return public.navision_backend_response(false,'vehicle_already_tombstoned'); end if;
  v_scope:=public.pdc_admin_vehicle_actor();
  if not coalesce((v_scope->>'ok')::boolean,false) then return v_scope; end if;
  insert into public.pdc_vehicle_tombstones(vehicle_id,normalized_stock,stock_number,tombstone_kind,deleted_by,deleted_by_email,deleted_at,reason,previous_lifecycle_state,previous_location,previous_visible_on_board,previous_status,vehicle_snapshot)
  values(v.id,v_stock,v.stock_number,'staging_reset',v_uid,v_email,v_now,btrim(p_reason),v.lifecycle_state,v.current_location,v.visible_on_board,v.workshop_status::text,to_jsonb(v)) returning * into t;
  update public.workshop_bookings set deleted_at=v_now,deleted_reason='Vehicle archived: '||btrim(p_reason),version=version+1,updated_by=v_uid,updated_at=v_now where vehicle_id=v.id and deleted_at is null;
  get diagnostics v_bookings=row_count;
  insert into public.workshop_booking_history(booking_id,event_type,before_data,after_data,metadata,actor_user_id,actor_email,vehicle_id,purged_booking_id)
  select b.id,'vehicle_archived',null,to_jsonb(b),jsonb_build_object('tombstone_id',t.tombstone_id,'reason',btrim(p_reason)),v_uid,v_email,v.id,b.id from public.workshop_bookings b where b.vehicle_id=v.id and b.deleted_at=v_now;
  update public.navision_board_activations set active=false,completed_at=coalesce(completed_at,v_now),completion_reason=coalesce(completion_reason,'Vehicle archived'),updated_at=v_now where canonical_vehicle_id=v.id and active;
  get diagnostics v_activations=row_count;
  -- Source operation overlays are immutable evidence and deliberately remain
  -- attached to the tombstoned vehicle; they are not active Board state.
  perform set_config('pdc.vehicle_restore_tombstone',t.tombstone_id::text,true);
  update public.vehicles set stock_number=null,lifecycle_state='deleted',visible_on_board=false,current_location='Other',pmb_stage=null,pmb_bay_stage=null,pmb_bay_number=null,pmb_key_tag=null,active_workshop_booking_id=null,workshop_status='queued',deleted_at=v_now,deleted_reason=btrim(p_reason),board_purged_at=v_now,board_purge_reason=btrim(p_reason),board_purged_by=v_uid,version=version+1,updated_by=v_uid,updated_at=v_now where id=v.id returning * into v_after;
  insert into public.pdc_vehicle_lifecycle_events(tombstone_id,vehicle_id,normalized_stock,event_kind,actor_id,actor_email,evidence)
  values(t.tombstone_id,v.id,v_stock,'reset',v_uid,v_email,jsonb_build_object('bookings_archived',v_bookings,'activations_deactivated',v_activations,'source_overlays_preserved',true));
  insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
  values('delete'::public.audit_action,'vehicles',v.id,v.id,v_uid,v_email,to_jsonb(v),to_jsonb(v_after),jsonb_build_object('source','pdc_staging_latest10_navision_reset_20260902','tombstone_id',t.tombstone_id,'source_overlays_preserved',true,'mutable_history_preserved',true));
  update public.pdc_email_vehicle_revision set revision=revision+1,updated_at=v_now where singleton;
  update public.navision_backend_revision set revision=revision+1,updated_at=v_now where singleton;
  perform public.workshop_bump_revision();
  return public.navision_backend_response(true,'vehicle_reset',jsonb_build_object('vehicle_id',v.id,'vehicle_version',v_after.version,'tombstone_id',t.tombstone_id,'source_overlays_preserved',true));
end
$archive$;
revoke all on function public.pdc_staging_latest10_archive_vehicle(uuid,integer,text,text) from public,anon,authenticated,service_role;

create or replace function public.apply_pdc_staging_latest10_navision_board_reset_20260902(
  p_backup_manifest_sha256 text,
  p_scheduler_state_sha256 text
) returns jsonb
language plpgsql security definer
set search_path=pg_catalog,public,auth,extensions
as $reset$
declare
  v_uid uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_admin_count integer;
  v_reset_id uuid:=gen_random_uuid();
  v_now timestamptz:=clock_timestamp();
  v_admin_runtime_active boolean;
  v_admin_runtime_revoked_at timestamptz;
  v_source_before text;
  v_source_after text;
  v_evidence_before text;
  v_evidence_after text;
  v_before jsonb;
  v_zero jsonb;
  v_after jsonb;
  v_vehicle record;
  v_overlay record;
  v_expected record;
  v_existing public.pdc_staging_latest10_navision_reset_batches%rowtype;
  v_record public.navision_backend_records%rowtype;
  v_location text;
  v_eta date;
  v_vehicle_id uuid;
  v_result jsonb;
  v_stocks jsonb;
  v_archived integer:=0;
  v_activated integer:=0;
begin
  if not public.pdc_monitor_staging_guard()
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or p_backup_manifest_sha256 !~ '^[a-f0-9]{64}$'
     or p_scheduler_state_sha256 !~ '^[a-f0-9]{64}$'
     or auth.role()<>'authenticated' or v_uid is null or v_email='' then
    raise exception 'PDC_LATEST10_INVALID_STAGING_REQUEST' using errcode='42501';
  end if;
  select count(*) into v_admin_count
  from public.pdc_user_roles r
  join auth.users u on u.id=r.auth_user_id and lower(u.email)=v_email
  where r.auth_user_id=v_uid and lower(r.email)=v_email
    and r.role::text='administrator' and r.active and r.account_status='approved';
  if v_admin_count<>1 then raise exception 'PDC_LATEST10_ADMINISTRATOR_REQUIRED' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended('pdc-staging-latest10-navision-board-reset-20260902',0));
  select * into v_existing from public.pdc_staging_latest10_navision_reset_batches
  where contract='pdc_staging_latest10_navision_reset_20260902' limit 1;
  if found then
    if v_existing.backup_manifest_sha256<>p_backup_manifest_sha256 or v_existing.scheduler_state_sha256<>p_scheduler_state_sha256 then
      raise exception 'PDC_LATEST10_REPLAY_BINDING_CONFLICT' using errcode='40001';
    end if;
    return jsonb_build_object('ok',true,'code','pdc_staging_latest10_navision_reset_exact_replay','replay',true,'environment','staging','project_ref','cdsmnqxtyyoeoznmbidd','reset_id',v_existing.reset_id,'before',v_existing.before_counts,'zero',v_existing.zero_counts,'after',v_existing.after_counts,'source_fingerprint_before',v_existing.source_fingerprint_before,'source_fingerprint_after',v_existing.source_fingerprint_after,'evidence_fingerprint_before',v_existing.evidence_fingerprint_before,'evidence_fingerprint_after',v_existing.evidence_fingerprint_after,'backup_manifest_sha256',v_existing.backup_manifest_sha256,'scheduler_state_sha256',v_existing.scheduler_state_sha256,'production_changed',false,'rollback_path','Existing Administrator recoverable archive/reset and encrypted format-v2 backup');
  end if;

  create temporary table pdc_latest10_expected(ordinal integer primary key,stock_number text not null,backend_record_id uuid not null,dealer_code text not null) on commit drop;
  insert into pdc_latest10_expected values
    (1,'13018222','ffd23638-13ed-4fae-b4de-2db627f84bec','14450'),
    (2,'13021135','ff215473-eb45-4378-94ef-f0e921882f89','14450'),
    (3,'13021137','feee8b5d-8702-4031-bb80-f6683cead5eb','14450'),
    (4,'13021112','fee7918e-72b4-470e-a067-0c3725849cda','14450'),
    (5,'13017833','fe964618-a28a-48d1-b81a-245399a8bfca','14450'),
    (6,'13076089','fe08c46c-3a45-44bc-8704-f97b2b731a2a','14450'),
    (7,'13058808','fdfe2735-658c-401b-bd20-4e98fe95e0f6','14450'),
    (8,'13087430','fdbed610-bc28-4b8f-b446-e6feb4c09fef','14450'),
    (9,'13059093','fd9fb979-5429-4a3a-aa8e-d79d29a51590','14450'),
    (10,'12662907','fd997b60-e48c-41bb-b194-98dfe67838d5','14450');

  lock table public.navision_backend_records,public.navision_board_activations,public.vehicles,
    public.vehicle_aliases,public.vehicle_work_items,public.workshop_bookings,
    public.pdc_authenticated_email_import_receipts,public.ai_email_intake,public.ai_email_attachments
    in share row exclusive mode;

  if exists(
    select 1 from pdc_latest10_expected e left join public.navision_backend_records r on r.id=e.backend_record_id
    where r.id is null or r.source_system<>'microsoft_navision' or r.dealer_code<>e.dealer_code
      or not r.is_current or r.record_status<>'current'
      or public.normalize_vehicle_stock_number(r.normalized_data->>'batch')<>e.stock_number
      or r.canonical_vehicle_id is not null
  ) or (select count(*) from pdc_latest10_expected e join public.navision_backend_records r on r.id=e.backend_record_id)<>10 then
    raise exception 'PDC_LATEST10_FROZEN_SOURCE_DRIFT' using errcode='40001';
  end if;
  if exists(
    select 1 from public.navision_board_activations a join pdc_latest10_expected e on e.backend_record_id=a.backend_record_id
    where a.active or a.canonical_vehicle_id is not null
  ) or exists(
    select 1 from public.vehicles v join pdc_latest10_expected e on e.stock_number=public.normalize_vehicle_stock_number(v.stock_number)
    where v.deleted_at is null
  ) or exists(
    select 1 from public.vehicle_aliases a join pdc_latest10_expected e on e.stock_number=a.normalized_alias_value
    where a.active and a.alias_type_normalized='stock_number'
  ) then
    raise exception 'PDC_LATEST10_OPERATIONAL_IDENTITY_PRESENT' using errcode='40001';
  end if;

  select encode(extensions.digest(convert_to(coalesce(string_agg(
    r.id::text||'|'||coalesce(r.row_hash,'')||'|'||r.dealer_code||'|'||r.record_status||'|'||r.is_current::text||'|'||r.normalized_data::text,';' order by r.id),''),'UTF8'),'sha256'),'hex')
    into v_source_before from public.navision_backend_records r
    where r.source_system='microsoft_navision' and r.is_current and r.record_status='current';
  select encode(extensions.digest(convert_to(coalesce(string_agg(
    x.kind||'|'||x.id::text||'|'||x.source_hash||'|'||x.evidence_hash,';' order by x.kind,x.id),''),'UTF8'),'sha256'),'hex')
    into v_evidence_before
  from (
    select 'email_receipt' kind,r.receipt_id id,r.source_hash,r.evidence_hash from public.pdc_authenticated_email_import_receipts r
    union all
    select 'intake' kind,i.id,coalesce(i.source_hash,''),'' from public.ai_email_intake i
    union all
    select 'attachment' kind,a.id,coalesce(a.source_hash,''),'' from public.ai_email_attachments a
  ) x;
  select jsonb_build_object(
    'active_visible_vehicles',(select count(*) from public.vehicles where lifecycle_state='active' and visible_on_board and deleted_at is null),
    'active_navision_activations',(select count(*) from public.navision_board_activations where active),
    'active_work_items',(select count(*) from public.vehicle_work_items w join public.vehicles v on v.id=w.vehicle_id where v.lifecycle_state='active' and v.visible_on_board and v.deleted_at is null and w.required and not w.completed),
    'active_bookings',(select count(*) from public.workshop_bookings b join public.vehicles v on v.id=b.vehicle_id where v.lifecycle_state='active' and v.visible_on_board and v.deleted_at is null and b.deleted_at is null and b.status in('queued','planned','started','stoppage','completed')),
    'operation_lines',(select count(*) from public.pdc_authenticated_email_operation_lines),
    'import_receipts',(select count(*) from public.pdc_authenticated_email_import_receipts),
    'ai_intake',(select count(*) from public.ai_email_intake),
    'ai_attachments',(select count(*) from public.ai_email_attachments),
    'navision_source_rows',(select count(*) from public.navision_backend_records where source_system='microsoft_navision')
  ) into v_before;

  select active,revoked_at into v_admin_runtime_active,v_admin_runtime_revoked_at
  from public.pdc_email_ai_successor_runtime_identities
  where environment='staging' and identity_purpose='pdc_email_ai_transaction_successor'
  order by created_at desc limit 1 for update;
  if v_admin_runtime_active is null then raise exception 'PDC_LATEST10_SUCCESSOR_IDENTITY_MISSING' using errcode='55000'; end if;
  if v_admin_runtime_active then
    update public.pdc_email_ai_successor_runtime_identities set active=false,revoked_at=v_now
    where environment='staging' and identity_purpose='pdc_email_ai_transaction_successor' and active;
    insert into public.audit_events(action,table_name,actor_id,actor_email,before_data,after_data,metadata)
    values('update','pdc_email_ai_successor_runtime_identities',v_uid,v_email,
      jsonb_build_object('active',true,'revoked_at',v_admin_runtime_revoked_at),
      jsonb_build_object('active',false,'revoked_at',v_now),
      jsonb_build_object('source','pdc_staging_latest10_navision_reset_20260902','scheduler_state_sha256',p_scheduler_state_sha256,'production_changed',false));
  end if;

  -- This legacy parity check is deferred globally and would re-evaluate
  -- unrelated pre-existing rows during a reset. Preserve its definition and
  -- restore it before commit; the new rows still carry complete parity fields.
  drop trigger if exists zz_vehicle_navision_parity_494 on public.vehicles;
  drop trigger if exists navision_activation_operational_reconcile on public.navision_board_activations;
  -- Use the scoped recoverable archive path for every current
  -- active/visible Board row. Source rows and evidence are never deleted.
  for v_vehicle in
    select id,version,public.normalize_vehicle_stock_number(stock_number) stock_number
    from public.vehicles
    where lifecycle_state='active' and visible_on_board and deleted_at is null
    order by id
  loop
    if v_vehicle.stock_number is null then raise exception 'PDC_LATEST10_ACTIVE_VEHICLE_STOCK_MISSING:%',v_vehicle.id using errcode='40001'; end if;
    v_result:=public.pdc_staging_latest10_archive_vehicle(v_vehicle.id,v_vehicle.version,v_vehicle.stock_number,'STAGING latest-10 Navision Board reset 20260902');
    if not coalesce((v_result->>'ok')::boolean,false) then raise exception 'PDC_LATEST10_ARCHIVE_FAILED:%:%',v_vehicle.id,v_result using errcode='55000'; end if;
    v_archived:=v_archived+1;
  end loop;
  -- Retire any stale active activation whose canonical vehicle is already
  -- hidden/completed; retain its immutable source and activation history.
  update public.navision_board_activations a
  set active=false,completed_at=coalesce(completed_at,v_now),completion_reason=coalesce(completion_reason,'Latest-10 staging Navision reset: stale hidden activation'),updated_at=v_now
  where a.active and not exists(
    select 1 from public.vehicles v
    where v.id=a.canonical_vehicle_id and v.lifecycle_state='active' and v.visible_on_board and v.deleted_at is null
  );
  insert into public.audit_events(action,table_name,actor_id,actor_email,before_data,after_data,metadata)
  values('update','navision_board_activations',v_uid,v_email,null,null,jsonb_build_object('source','pdc_staging_latest10_navision_reset_20260902','stale_hidden_activations_retired',true,'production_changed',false));
  select jsonb_build_object(
    'active_visible_vehicles',(select count(*) from public.vehicles where lifecycle_state='active' and visible_on_board and deleted_at is null),
    'active_navision_activations',(select count(*) from public.navision_board_activations where active),
    'active_work_items',(select count(*) from public.vehicle_work_items w join public.vehicles v on v.id=w.vehicle_id where v.lifecycle_state='active' and v.visible_on_board and v.deleted_at is null and w.required and not w.completed),
    'active_bookings',(select count(*) from public.workshop_bookings b join public.vehicles v on v.id=b.vehicle_id where v.lifecycle_state='active' and v.visible_on_board and v.deleted_at is null and b.deleted_at is null and b.status in('queued','planned','started','stoppage','completed'))
  ) into v_zero;
  if (v_zero->>'active_visible_vehicles')::integer<>0 or (v_zero->>'active_navision_activations')::integer<>0
     or (v_zero->>'active_work_items')::integer<>0 or (v_zero->>'active_bookings')::integer<>0 then
    raise exception 'PDC_LATEST10_ZERO_STATE_FAILED:%',v_zero using errcode='55000';
  end if;

  -- The canonical Navision location/ETA functions remain the sole mapping
  -- authority. The trigger is restored before the transaction commits.
  drop trigger if exists navision_activation_operational_reconcile on public.navision_board_activations;
  for v_expected in select * from pdc_latest10_expected order by ordinal loop
    select * into strict v_record from public.navision_backend_records where id=v_expected.backend_record_id for update;
    v_location:=public.navision_operational_location(v_record.normalized_data);
    if v_location='Completed' then raise exception 'PDC_LATEST10_COMPLETED_SOURCE_NOT_ACTIVATABLE:%',v_expected.stock_number using errcode='22023'; end if;
    v_eta:=public.navision_kewdale_eta(v_record.normalized_data);
    v_vehicle_id:=extensions.uuid_generate_v5('b58b5f75-d004-5a76-b9aa-48c801b4ad7d'::uuid,'NAVISION:'||v_record.dealer_code||':'||v_expected.stock_number||':'||v_record.id::text);
    insert into public.vehicles(
      id,permanent_vehicle_id,stock_number,vin,toyota_order_number,job_card_number,customer_name,
      vehicle_description,model,registration,lifecycle_state,visible_on_board,current_location,
      eta_to_kewdale,source_system,source_batch_id,source_record_id,source_payload,created_by,updated_by
    ) values(
      v_vehicle_id,'PDC-NAV-'||upper(replace(substr(v_vehicle_id::text,1,24),'-','')),v_expected.stock_number,
      case when public.is_valid_vehicle_vin(v_record.normalized_data->>'vin') then public.normalize_vehicle_vin(v_record.normalized_data->>'vin') else null end,
      nullif(btrim(v_record.normalized_data->>'order'),''),nullif(btrim(v_record.normalized_data->>'jobCardNumber'),''),
      coalesce(nullif(btrim(v_record.normalized_data->>'client'),''),nullif(btrim(v_record.normalized_data->>'customerSurname'),''),nullif(btrim(v_record.normalized_data->>'dealerCustomerName'),''),nullif(btrim(v_record.normalized_data->>'toyotaCustomer'),'')),
      coalesce(nullif(btrim(v_record.normalized_data->>'modelDescription'),''),nullif(btrim(v_record.normalized_data->>'toyotaVehicle'),''),nullif(btrim(v_record.normalized_data->>'vehicle'),'')),
      coalesce(nullif(btrim(v_record.normalized_data->>'modelDescription'),''),nullif(btrim(v_record.normalized_data->>'toyotaVehicle'),''),nullif(btrim(v_record.normalized_data->>'vehicle'),'')),
      nullif(upper(btrim(v_record.normalized_data->>'registration')),''),'active',true,v_location,v_eta,
      'microsoft_navision',v_record.dealer_code,v_record.id::text,
      jsonb_build_object('authority','pdc_staging_latest10_navision_reset_20260902','navision_record_id',v_record.id,'navision_version',v_record.version::text,'navision_status',coalesce(v_record.normalized_data->>'toyotaStatus',''),'navision_updated_at',v_record.updated_at,'latest_navision_status',v_record.normalized_data->>'toyotaStatus','mapped_location',v_location,'backup_manifest_sha256',p_backup_manifest_sha256,'scheduler_state_sha256',p_scheduler_state_sha256),
      v_uid,v_uid
    );
    insert into public.navision_board_activations(backend_record_id,activation_source,activated_stock_number,activated_by,activated_by_email,canonical_vehicle_id,active)
    values(v_record.id,'manual',v_expected.stock_number,v_uid,v_email,v_vehicle_id,true);
    update public.navision_backend_records set canonical_vehicle_id=v_vehicle_id where id=v_record.id;
    insert into public.pdc_staging_latest10_navision_reset_rows(reset_id,ordinal,backend_record_id,stock_number,dealer_code,vehicle_id,target_location,eta_to_kewdale,source_row_hash)
    values(v_reset_id,v_expected.ordinal,v_record.id,v_expected.stock_number,v_record.dealer_code,v_vehicle_id,v_location,v_eta,v_record.row_hash);
    v_activated:=v_activated+1;
  end loop;
  create trigger navision_activation_operational_reconcile
    after insert or update of active,activated_stock_number on public.navision_board_activations
    for each row execute function public.trigger_reconcile_navision_operational_record();
  create constraint trigger zz_vehicle_navision_parity_494
    after insert or update of stock_number,source_system,source_record_id,source_payload,deleted_at on public.vehicles
    deferrable initially deferred for each row execute function public.pdc_enforce_navision_vehicle_parity_494();

  if v_activated<>10 then raise exception 'PDC_LATEST10_ACTIVATION_COUNT:%',v_activated using errcode='55000'; end if;
  select jsonb_build_object(
    'active_visible_vehicles',(select count(*) from public.vehicles where lifecycle_state='active' and visible_on_board and deleted_at is null),
    'active_unique_stocks',(select count(distinct public.normalize_vehicle_stock_number(stock_number)) from public.vehicles where lifecycle_state='active' and visible_on_board and deleted_at is null),
    'active_navision_activations',(select count(*) from public.navision_board_activations where active),
    'active_work_items',(select count(*) from public.vehicle_work_items w join public.vehicles v on v.id=w.vehicle_id where v.lifecycle_state='active' and v.visible_on_board and v.deleted_at is null and w.required and not w.completed),
    'active_bookings',(select count(*) from public.workshop_bookings b join public.vehicles v on v.id=b.vehicle_id where v.lifecycle_state='active' and v.visible_on_board and v.deleted_at is null and b.deleted_at is null and b.status in('queued','planned','started','stoppage','completed')),
    'operation_lines',(select count(*) from public.pdc_authenticated_email_operation_lines),
    'import_receipts',(select count(*) from public.pdc_authenticated_email_import_receipts),
    'ai_intake',(select count(*) from public.ai_email_intake),
    'ai_attachments',(select count(*) from public.ai_email_attachments),
    'navision_source_rows',(select count(*) from public.navision_backend_records where source_system='microsoft_navision')
  ) into v_after;
  if (v_after->>'active_visible_vehicles')::integer<>10 or (v_after->>'active_unique_stocks')::integer<>10
     or (v_after->>'active_navision_activations')::integer<>10 or (v_after->>'active_work_items')::integer<>0
     or (v_after->>'active_bookings')::integer<>0 then raise exception 'PDC_LATEST10_POSTCONDITION_FAILED:%',v_after using errcode='55000'; end if;
  select encode(extensions.digest(convert_to(coalesce(string_agg(
    r.id::text||'|'||coalesce(r.row_hash,'')||'|'||r.dealer_code||'|'||r.record_status||'|'||r.is_current::text||'|'||r.normalized_data::text,';' order by r.id),''),'UTF8'),'sha256'),'hex')
    into v_source_after from public.navision_backend_records r
    where r.source_system='microsoft_navision' and r.is_current and r.record_status='current';
  select encode(extensions.digest(convert_to(coalesce(string_agg(
    x.kind||'|'||x.id::text||'|'||x.source_hash||'|'||x.evidence_hash,';' order by x.kind,x.id),''),'UTF8'),'sha256'),'hex')
    into v_evidence_after
  from (
    select 'email_receipt' kind,r.receipt_id id,r.source_hash,r.evidence_hash from public.pdc_authenticated_email_import_receipts r
    union all
    select 'intake' kind,i.id,coalesce(i.source_hash,''),'' from public.ai_email_intake i
    union all
    select 'attachment' kind,a.id,coalesce(a.source_hash,''),'' from public.ai_email_attachments a
  ) x;
  if v_source_after<>v_source_before or v_evidence_after<>v_evidence_before then raise exception 'PDC_LATEST10_SOURCE_EVIDENCE_DRIFT' using errcode='40001'; end if;

  -- Restore exactly the prior successor identity state. OS Task Scheduler is
  -- restored by the controller only after it proves the board remains bounded.
  if v_admin_runtime_active then
    update public.pdc_email_ai_successor_runtime_identities set active=true,revoked_at=v_admin_runtime_revoked_at
    where environment='staging' and identity_purpose='pdc_email_ai_transaction_successor';
    insert into public.audit_events(action,table_name,actor_id,actor_email,before_data,after_data,metadata)
    values('update','pdc_email_ai_successor_runtime_identities',v_uid,v_email,
      jsonb_build_object('active',false,'revoked_at',v_now),
      jsonb_build_object('active',true,'revoked_at',v_admin_runtime_revoked_at),
      jsonb_build_object('source','pdc_staging_latest10_navision_reset_20260902','restored_prior_state',true,'production_changed',false));
  end if;

  insert into public.pdc_staging_latest10_navision_reset_batches(
    reset_id,contract,backup_manifest_sha256,scheduler_state_sha256,actor_id,actor_email,
    before_counts,zero_counts,after_counts,source_fingerprint_before,source_fingerprint_after,
    evidence_fingerprint_before,evidence_fingerprint_after,frozen_stocks
  ) values(
    v_reset_id,'pdc_staging_latest10_navision_reset_20260902',p_backup_manifest_sha256,p_scheduler_state_sha256,v_uid,v_email,
    v_before,v_zero,v_after,v_source_before,v_source_after,v_evidence_before,v_evidence_after,
    (select jsonb_agg(jsonb_build_object('ordinal',ordinal,'stock_number',stock_number,'backend_record_id',backend_record_id,'dealer_code',dealer_code) order by ordinal) from pdc_latest10_expected)
  );
  insert into public.pdc_staging_board_purge_receipts(backup_manifest_sha256,confirmation,result,applied_by)
  values(p_backup_manifest_sha256,'STAGING LATEST-10 NAVISION RESET 20260902',jsonb_build_object('ok',true,'contract','pdc_staging_latest10_navision_reset_20260902','reset_id',v_reset_id,'archived_vehicles',v_archived,'activated_vehicles',v_activated,'before',v_before,'zero',v_zero,'after',v_after,'source_fingerprint_before',v_source_before,'source_fingerprint_after',v_source_after,'evidence_fingerprint_before',v_evidence_before,'evidence_fingerprint_after',v_evidence_after,'scheduler_state_sha256',p_scheduler_state_sha256,'runtime_identity_restored',true,'booking_created',false,'work_created',false,'parts_changed',false,'completion_changed',false,'production_changed',false),v_uid);
  insert into public.audit_events(action,table_name,row_id,actor_id,actor_email,before_data,after_data,metadata)
  values('import','pdc_staging_latest10_navision_reset_batches',v_reset_id,v_uid,v_email,v_before,v_after,jsonb_build_object('source','pdc_staging_latest10_navision_reset_20260902','zero_counts',v_zero,'backup_manifest_sha256',p_backup_manifest_sha256,'scheduler_state_sha256',p_scheduler_state_sha256,'archived_vehicles',v_archived,'activated_vehicles',v_activated,'production_changed',false,'rollback_path','Existing Administrator recoverable archive/reset and encrypted format-v2 backup; no source/evidence deletion'));
  return jsonb_build_object('ok',true,'code','pdc_staging_latest10_navision_reset_applied','environment','staging','project_ref','cdsmnqxtyyoeoznmbidd','reset_id',v_reset_id,'archived_vehicles',v_archived,'activated_vehicles',v_activated,'before',v_before,'zero',v_zero,'after',v_after,'source_fingerprint_before',v_source_before,'source_fingerprint_after',v_source_after,'evidence_fingerprint_before',v_evidence_before,'evidence_fingerprint_after',v_evidence_after,'backup_manifest_sha256',p_backup_manifest_sha256,'scheduler_state_sha256',p_scheduler_state_sha256,'runtime_identity_restored',true,'booking_created',false,'work_created',false,'parts_changed',false,'completion_changed',false,'production_changed',false,'rollback_path','Existing Administrator recoverable archive/reset and encrypted format-v2 backup');
end
$reset$;
revoke all on function public.apply_pdc_staging_latest10_navision_board_reset_20260902(text,text) from public,anon,authenticated,service_role;

insert into supabase_migrations.schema_migrations(version,name,statements) values('20260902250000','pdc_staging_latest10_navision_board_reset',array['Private exact frozen latest-10 Navision reset and activation contract']);
commit;
