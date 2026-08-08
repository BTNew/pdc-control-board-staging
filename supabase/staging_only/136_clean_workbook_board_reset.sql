begin;

-- Staging-only, one-shot controlled reset. Payload is supplied by the guarded installer.
do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
     or to_regprocedure('public.pdc_bulk_workbook_canonical_payload_sha256(jsonb)') is null
     or to_regprocedure('public.navision_operational_location(jsonb)') is null
     or to_regprocedure('public.navision_kewdale_eta_from_payload(jsonb)') is null
     or to_regclass('public.pdc_authenticated_email_operation_lines') is null then
    raise exception 'PDC_RESET_136_STAGING_PREREQUISITE_MISSING' using errcode='55000';
  end if;
end;
$guard$;

alter table public.pdc_authenticated_email_operation_lines
  add column if not exists job_card_number text,
  add column if not exists source_row_no integer,
  add column if not exists source_contract text;

alter table public.pdc_authenticated_email_operation_lines
  drop constraint if exists pdc_authenticated_email_operation_lines_job_card_number_check,
  add constraint pdc_authenticated_email_operation_lines_job_card_number_check
    check(job_card_number is null or (job_card_number=btrim(job_card_number) and length(job_card_number) between 1 and 80)),
  drop constraint if exists pdc_authenticated_email_operation_lines_source_row_no_check,
  add constraint pdc_authenticated_email_operation_lines_source_row_no_check
    check(source_row_no is null or source_row_no between 1 and 100000),
  drop constraint if exists pdc_authenticated_email_operation_lines_source_contract_check,
  add constraint pdc_authenticated_email_operation_lines_source_contract_check
    check(source_contract is null or source_contract='pdc_staging_workbook_reset_136');

create table if not exists public.pdc_staging_reset_batches (
  reset_id uuid primary key default gen_random_uuid(),
  contract text not null check(contract='pdc_staging_workbook_reset_136'),
  workbook_sha256 text not null check(workbook_sha256 ~ '^[a-f0-9]{64}$'),
  source_payload_sha256 text not null check(source_payload_sha256 ~ '^[a-f0-9]{64}$'),
  accepted_payload_sha256 text not null check(accepted_payload_sha256 ~ '^[a-f0-9]{64}$'),
  authority_binding_sha256 text not null check(authority_binding_sha256 ~ '^[a-f0-9]{64}$'),
  backup_manifest_sha256 text not null check(backup_manifest_sha256 ~ '^[a-f0-9]{64}$'),
  actor_id uuid not null references auth.users(id) on delete restrict,
  actor_email text not null,
  before_counts jsonb not null check(jsonb_typeof(before_counts)='object'),
  after_counts jsonb not null check(jsonb_typeof(after_counts)='object'),
  summary jsonb not null check(jsonb_typeof(summary)='object'),
  applied_at timestamptz not null default clock_timestamp(),
  unique(contract,workbook_sha256,accepted_payload_sha256,authority_binding_sha256)
);

create table if not exists public.pdc_staging_reset_rows (
  reset_id uuid not null references public.pdc_staging_reset_batches(reset_id) on delete restrict deferrable initially deferred,
  source_row_no integer not null,
  job_card_number text not null,
  stock_number text not null,
  accepted boolean not null,
  reason text,
  backend_record_id uuid references public.navision_backend_records(id) on delete restrict,
  vehicle_id uuid references public.vehicles(id) on delete restrict,
  target_location text,
  source_hash text check(source_hash is null or source_hash ~ '^[a-f0-9]{64}$'),
  operation_count integer not null check(operation_count>=0),
  primary key(reset_id,source_row_no),
  check((accepted and reason is null and backend_record_id is not null and vehicle_id is not null and target_location in ('YH','IT','PMB','RFT','Other') and source_hash is not null)
     or (not accepted and reason is not null and backend_record_id is null and vehicle_id is null and target_location is null and source_hash is null))
);

create or replace function public.pdc_staging_reset_reject_mutation()
returns trigger language plpgsql set search_path=pg_catalog,public as $immutable$
begin
  raise exception 'PDC_RESET_HISTORY_IMMUTABLE' using errcode='55000';
end;
$immutable$;
revoke all on function public.pdc_staging_reset_reject_mutation() from public,anon,authenticated,service_role;

drop trigger if exists pdc_staging_reset_batches_immutable on public.pdc_staging_reset_batches;
create trigger pdc_staging_reset_batches_immutable before update or delete on public.pdc_staging_reset_batches
for each row execute function public.pdc_staging_reset_reject_mutation();
drop trigger if exists pdc_staging_reset_rows_immutable on public.pdc_staging_reset_rows;
create trigger pdc_staging_reset_rows_immutable before update or delete on public.pdc_staging_reset_rows
for each row execute function public.pdc_staging_reset_reject_mutation();

alter table public.pdc_staging_reset_batches enable row level security;
alter table public.pdc_staging_reset_rows enable row level security;
revoke all on table public.pdc_staging_reset_batches,public.pdc_staging_reset_rows from public,anon,authenticated,service_role;

-- Preserve QC-before-RFT for normal workflow. The sole exception is explicit Navision
-- Delivered-to/at-Dealer reset authority; no fake QC event is manufactured.
create or replace function public.pdc_enforce_qc_then_rft()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $function$
declare
  v_issues text[];
  v_authoritative_delivered_rft boolean:=coalesce(new.source_payload->>'reset_location_authority','')='navision_delivered_dealer';
begin
  if (upper(btrim(coalesce(new.current_location,'')))='RFT'
      or lower(btrim(coalesce(new.lifecycle_state::text,'')))='rft')
     and new.qc_completed_at is null and not v_authoritative_delivered_rft then
    raise exception 'RFT vehicles must retain a prior QC sign-off' using errcode='22023';
  end if;
  if old.qc_completed_at is null and new.qc_completed_at is not null then
    if upper(btrim(coalesce(new.current_location,'')))='RFT'
       or lower(btrim(coalesce(new.lifecycle_state::text,'')))='rft' then
      raise exception 'QC sign-off and RFT transfer must be separate audited transitions' using errcode='22023';
    end if;
    v_issues:=public.pdc_qc_gate_issues(old.id);
    if coalesce(array_length(v_issues,1),0)>0 then
      raise exception 'QC gate failed: %',array_to_string(v_issues,'; ') using errcode='22023';
    end if;
  end if;
  if ((upper(btrim(coalesce(old.current_location,''))) is distinct from 'RFT'
       and upper(btrim(coalesce(new.current_location,'')))='RFT')
      or (lower(btrim(coalesce(old.lifecycle_state::text,''))) is distinct from 'rft'
       and lower(btrim(coalesce(new.lifecycle_state::text,'')))='rft'))
     and not v_authoritative_delivered_rft then
    if old.qc_completed_at is null then
      raise exception 'QC sign-off must be completed before RFT transfer' using errcode='22023';
    end if;
    v_issues:=public.pdc_qc_gate_issues(old.id);
    if coalesce(array_length(v_issues,1),0)>0 then
      raise exception 'RFT gate failed: %',array_to_string(v_issues,'; ') using errcode='22023';
    end if;
  end if;
  return new;
end;
$function$;
revoke all on function public.pdc_enforce_qc_then_rft() from public,anon,authenticated;

create or replace function public.apply_pdc_staging_workbook_reset_136(
  p_preview jsonb,
  p_backup_manifest_sha256 text
) returns jsonb
language plpgsql security definer
set search_path=pg_catalog,public,extensions
as $reset$
declare
  v_actor_id uuid;
  v_actor_email text;
  v_now timestamptz:=clock_timestamp();
  v_reset_id uuid:=gen_random_uuid();
  v_before jsonb;
  v_after jsonb;
  v_pair record;
  v_op record;
  v_receipt_id uuid;
  v_source_hash text;
  v_required_work jsonb;
  v_rows integer;
  v_operation_rows integer;
  v_work_rows integer;
begin
  if p_preview->>'format'<>'pdc-staging-reset-preview-136-v1'
     or p_preview->>'project_ref'<>'cdsmnqxtyyoeoznmbidd'
     or p_preview->>'stage_mapping_policy'<>'pmb-workshop-stages-v1'
     or p_preview#>>'{summary,workbook_sha256}'<>'d89a36dce52994acf34c234a6fc988c11b3ca1aa76a11123fdbacd8d507ffaa3'
     or p_preview#>>'{summary,source_payload_sha256}'<>'f0da81b18daebdaf3c7adc6b54efce2f506ea23630289e6fbc5ea00dad1f278a'
     or p_preview#>>'{summary,accepted_payload_sha256}'<>'f9606af816433a3dcecf1bebaf41c6c4a8b206fec81679ddfafd8808524c0741'
     or p_preview#>>'{summary,authority_binding_sha256}'<>'9f1c7fa4e1ec15b9b06ec60e426614780e500b104041d8a8b9b8b6a664b8e00e'
     or public.pdc_bulk_workbook_canonical_payload_sha256(p_preview->'accepted_pairs')<>'f0b426579c1cb25b26f2f17637c49383aefaa928512737adc67d5a7d97ec0bd4'
     or public.pdc_bulk_workbook_canonical_payload_sha256(p_preview->'authority_binding')<>'c20548bd02ac81bb7460db9518291de4f677aef7fa66519c439ce584181f199c'
     or p_backup_manifest_sha256<>'b624e19411f00eabf9128ea166dd75bb3c43945a2edc9ef716419ce60b6d930a' then
    raise exception 'PDC_RESET_136_INPUT_DIGEST_MISMATCH' using errcode='22023';
  end if;
  if (p_preview#>>'{summary,workbook_pair_count}')::integer<>411
     or (p_preview#>>'{summary,accepted_pair_count}')::integer<>330
     or (p_preview#>>'{summary,accepted_unique_stock_count}')::integer<>325
     or (p_preview#>>'{summary,accepted_operation_count}')::integer<>2943
     or (p_preview#>>'{summary,exception_pair_count}')::integer<>81
     or (p_preview#>>'{summary,exception_unique_stock_count}')::integer<>78
     or (p_preview#>>'{summary,exception_operation_count}')::integer<>540 then
    raise exception 'PDC_RESET_136_INPUT_COUNT_MISMATCH' using errcode='22023';
  end if;
  if not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd') then
    raise exception 'PDC_RESET_136_NOT_STAGING' using errcode='55000';
  end if;
  if exists(select 1 from public.pdc_staging_reset_batches where contract='pdc_staging_workbook_reset_136') then
    raise exception 'PDC_RESET_136_ALREADY_APPLIED' using errcode='55000';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('pdc-staging-workbook-reset-136',0));
  lock table public.pdc_ai_intake_proposals,public.navision_backend_records,public.navision_board_activations,
    public.vehicles,public.vehicle_work_items,public.workshop_bookings,public.workshop_booking_assignments,
    public.workshop_booking_history,public.workshop_parts_overrides,public.workshop_transition_authorizations,
    public.pdc_authenticated_email_operation_lines,public.pdc_authenticated_email_import_receipts,
    public.vehicle_parts_updates,public.vehicle_workshop_line_adjustments,public.pdc_sublet_bookings,
    public.vehicle_sublet_providers,public.audit_events in share row exclusive mode;

  select r.auth_user_id,r.email into v_actor_id,v_actor_email
  from public.pdc_user_roles r
  where r.active and r.role='administrator' and r.auth_user_id is not null
    and exists(select 1 from auth.users u where u.id=r.auth_user_id)
  order by r.created_at,r.id limit 1;
  if v_actor_id is null then raise exception 'PDC_RESET_136_ADMIN_ACTOR_MISSING' using errcode='55000'; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_actor_id,'email',v_actor_email,'role','authenticated')::text,true);

  create temp table pdc_reset_pairs_136 on commit drop as
  select (p->>'row_no')::integer source_row_no,btrim(p->>'job_card_number') job_card_number,
    public.normalize_vehicle_stock_number(p->>'stock_number') stock_number,
    (p->>'backend_record_id')::uuid backend_record_id,p->>'backend_row_hash' backend_row_hash,
    (p->>'backend_version')::integer backend_version,(p->>'existing_vehicle_id')::uuid vehicle_id,
    p->>'location' target_location,p->'operations' operations
  from jsonb_array_elements(p_preview->'accepted_pairs') p;
  create unique index on pdc_reset_pairs_136(source_row_no);

  create temp table pdc_reset_stocks_136 on commit drop as
  select stock_number,backend_record_id,backend_row_hash,backend_version,vehicle_id,target_location
  from pdc_reset_pairs_136 group by stock_number,backend_record_id,backend_row_hash,backend_version,vehicle_id,target_location;
  create unique index on pdc_reset_stocks_136(stock_number);
  create unique index on pdc_reset_stocks_136(backend_record_id);
  create unique index on pdc_reset_stocks_136(vehicle_id);

  create temp table pdc_reset_exceptions_136 on commit drop as
  select (p->>'row_no')::integer source_row_no,btrim(p->>'job_card_number') job_card_number,
    public.normalize_vehicle_stock_number(p->>'stock_number') stock_number,p->>'reason' reason,
    (p->>'operation_count')::integer operation_count
  from jsonb_array_elements(p_preview->'exceptions') p;
  create unique index on pdc_reset_exceptions_136(source_row_no);

  if (select count(*) from pdc_reset_pairs_136)<>330
     or (select count(*) from pdc_reset_stocks_136)<>325
     or (select coalesce(sum(jsonb_array_length(operations)),0) from pdc_reset_pairs_136)<>2943
     or (select count(*) from pdc_reset_exceptions_136)<>81
     or (select count(distinct stock_number) from pdc_reset_exceptions_136)<>78
     or exists(select 1 from pdc_reset_stocks_136 join pdc_reset_exceptions_136 using(stock_number)) then
    raise exception 'PDC_RESET_136_TEMP_RECONCILIATION_FAILED' using errcode='22023';
  end if;

  perform r.id from public.navision_backend_records r join pdc_reset_stocks_136 s on s.backend_record_id=r.id order by r.id for update;
  perform v.id from public.vehicles v order by v.id for update;

  if exists(
    select 1 from pdc_reset_stocks_136 s
    left join public.navision_backend_records r on r.id=s.backend_record_id
    left join public.vehicles v on v.id=s.vehicle_id
    where r.id is null or not r.is_current or r.record_status<>'current' or r.source_system<>'microsoft_navision'
      or r.row_hash<>s.backend_row_hash or r.version<>s.backend_version
      or public.normalize_vehicle_stock_number(r.normalized_data->>'batch')<>s.stock_number
      or r.canonical_vehicle_id is distinct from s.vehicle_id
      or v.id is null or public.normalize_vehicle_stock_number(v.stock_number)<>s.stock_number
      or (case when public.navision_operational_location(r.normalized_data)='Completed' then 'RFT'
               else public.navision_operational_location(r.normalized_data) end)<>s.target_location
      or (s.target_location='RFT' and lower(r.normalized_data::text) not like '%delivered - at dealer%'
          and lower(r.normalized_data::text) not like '%delivered - to dealer%')
  ) then raise exception 'PDC_RESET_136_AUTHORITY_DRIFT' using errcode='40001'; end if;
  if exists(
    select 1 from public.navision_backend_records
    where source_system='microsoft_navision' and is_current and record_status='current'
      and public.normalize_vehicle_stock_number(normalized_data->>'batch') in(select stock_number from pdc_reset_stocks_136)
    group by public.normalize_vehicle_stock_number(normalized_data->>'batch') having count(*)<>1
  ) then raise exception 'PDC_RESET_136_DUPLICATE_CURRENT_AUTHORITY' using errcode='40001'; end if;
  if exists(
    select 1 from pdc_reset_exceptions_136 e join public.navision_backend_records r
      on r.source_system='microsoft_navision' and r.is_current and r.record_status='current'
     and public.normalize_vehicle_stock_number(r.normalized_data->>'batch')=e.stock_number
  ) then raise exception 'PDC_RESET_136_EXCEPTION_AUTHORITY_CHANGED' using errcode='40001'; end if;
  if exists(
    select 1 from public.vehicles
    where public.normalize_vehicle_stock_number(stock_number) in(select stock_number from pdc_reset_stocks_136)
    group by public.normalize_vehicle_stock_number(stock_number) having count(*)>1
  ) then
    raise exception 'PDC_RESET_136_VEHICLE_IDENTITY_DRIFT' using errcode='40001';
  end if;
  if exists(select 1 from public.pdc_auditor_booking_work_relations) then
    raise exception 'PDC_RESET_136_AUDITOR_RELATION_BLOCK' using errcode='55000';
  end if;

  select jsonb_build_object(
    'vehicles_total',(select count(*) from public.vehicles),
    'vehicles_visible',(select count(*) from public.vehicles where visible_on_board and deleted_at is null),
    'vehicles_active',(select count(*) from public.vehicles where lifecycle_state='active' and deleted_at is null),
    'work_items',(select count(*) from public.vehicle_work_items),
    'operation_lines',(select count(*) from public.pdc_authenticated_email_operation_lines),
    'bookings',(select count(*) from public.workshop_bookings),
    'parts_updates',(select count(*) from public.vehicle_parts_updates),
    'line_adjustments',(select count(*) from public.vehicle_workshop_line_adjustments),
    'sublet_bookings',(select count(*) from public.pdc_sublet_bookings)
  ) into v_before;
  create temp table pdc_reset_vehicle_before_136 on commit drop as select * from public.vehicles;

  -- Suppress only the Navision activation reconciliation trigger during this bounded transaction.
  drop trigger navision_activation_operational_reconcile on public.navision_board_activations;

  update public.vehicles set
    lifecycle_state='deleted',visible_on_board=false,current_location='Other',pmb_stage=null,pmb_bay_stage=null,
    pmb_bay_number=null,pmb_key_tag=null,active_workshop_booking_id=null,workshop_status='queued',
    workshop_status_updated_at=null,workshop_status_updated_by=null,qc_completed_at=null,qc_completed_by=null,
    rft_transferred_at=null,rft_collected_at=null,rft_collected_by=null,deleted_at=v_now,
    deleted_reason='Staging clean reset 136: not in accepted workbook authority set',
    source_payload=jsonb_build_object('authority','pdc_staging_workbook_reset_136','archived_at',v_now,
      'backup_manifest_sha256',p_backup_manifest_sha256),
    version=version+1,updated_by=v_actor_id,updated_at=v_now;

  delete from public.workshop_bookings;
  delete from public.vehicle_workshop_line_adjustments;
  delete from public.vehicle_parts_updates;
  delete from public.pdc_sublet_bookings;
  delete from public.vehicle_sublet_providers;
  delete from public.pdc_authenticated_email_operation_lines;
  delete from public.vehicle_work_items;

  update public.navision_board_activations set active=false,updated_at=v_now where active;

  update public.vehicles v set
    stock_number=r.normalized_data->>'batch',
    vin=case when public.is_valid_vehicle_vin(r.normalized_data->>'vin') then public.normalize_vehicle_vin(r.normalized_data->>'vin')
             when public.is_valid_vehicle_vin(v.vin) then public.normalize_vehicle_vin(v.vin) else null end,
    toyota_order_number=coalesce(nullif(btrim(r.normalized_data->>'order'),''),v.toyota_order_number),
    job_card_number=coalesce(nullif(btrim(r.normalized_data->>'jobCardNumber'),''),p.job_card_number),
    customer_name=coalesce(nullif(btrim(r.normalized_data->>'client'),''),nullif(btrim(r.normalized_data->>'customerSurname'),''),
      nullif(btrim(r.normalized_data->>'dealerCustomerName'),''),nullif(btrim(r.normalized_data->>'toyotaCustomer'),''),v.customer_name),
    vehicle_description=coalesce(nullif(btrim(r.normalized_data->>'modelDescription'),''),nullif(btrim(r.normalized_data->>'toyotaVehicle'),''),
      nullif(btrim(r.normalized_data->>'vehicle'),''),v.vehicle_description),
    model=coalesce(nullif(btrim(r.normalized_data->>'modelDescription'),''),nullif(btrim(r.normalized_data->>'toyotaVehicle'),''),
      nullif(btrim(r.normalized_data->>'vehicle'),''),v.model),
    registration=coalesce(nullif(upper(btrim(r.normalized_data->>'registration')),''),v.registration),
    lifecycle_state='active',visible_on_board=true,current_location=s.target_location,
    pmb_stage=null,pmb_bay_stage=null,pmb_bay_number=null,pmb_key_tag=null,
    eta_to_kewdale=public.navision_kewdale_eta_from_payload(r.normalized_data),
    active_workshop_booking_id=null,workshop_status='queued',workshop_status_updated_at=null,workshop_status_updated_by=null,
    qc_completed_at=null,qc_completed_by=null,rft_transferred_at=null,rft_collected_at=null,rft_collected_by=null,
    deleted_at=null,deleted_reason=null,source_system='microsoft_navision',source_batch_id=r.dealer_code,source_record_id=r.id::text,
    source_payload=jsonb_build_object('authority','pdc_staging_workbook_reset_136','navision_record_id',r.id,
      'workbook_sha256',p_preview#>>'{summary,workbook_sha256}','accepted_payload_sha256',p_preview#>>'{summary,accepted_payload_sha256}',
      'mapped_location',s.target_location,'latest_navision_status',r.normalized_data->>'toyotaStatus',
      'reset_location_authority',case when s.target_location='RFT' then 'navision_delivered_dealer' else null end,'reset_at',v_now),
    version=v.version+1,updated_by=v_actor_id,updated_at=v_now
  from pdc_reset_stocks_136 s
  join public.navision_backend_records r on r.id=s.backend_record_id
  join lateral(select job_card_number from pdc_reset_pairs_136 x where x.stock_number=s.stock_number order by source_row_no limit 1) p on true
  where v.id=s.vehicle_id;
  get diagnostics v_rows=row_count;
  if v_rows<>325 then raise exception 'PDC_RESET_136_VEHICLE_REACTIVATION_COUNT:%',v_rows using errcode='55000'; end if;

  update public.navision_board_activations a set active=true,canonical_vehicle_id=s.vehicle_id,
    completed_at=null,completion_reason=null,completed_by=null,completed_by_email=null,updated_at=v_now
  from pdc_reset_stocks_136 s where a.backend_record_id=s.backend_record_id;
  get diagnostics v_rows=row_count;
  if v_rows<>325 then raise exception 'PDC_RESET_136_ACTIVATION_COUNT:%',v_rows using errcode='55000'; end if;

  create trigger navision_activation_operational_reconcile
  after insert or update of active,activated_stock_number on public.navision_board_activations
  for each row execute function public.trigger_reconcile_navision_operational_record();

  for v_pair in select * from pdc_reset_pairs_136 order by source_row_no loop
    v_source_hash:=encode(digest('pdc-reset-136|'||(p_preview#>>'{summary,accepted_payload_sha256}')||'|'||v_pair.source_row_no::text||'|'||v_pair.job_card_number||'|'||v_pair.stock_number,'sha256'),'hex');
    select coalesce(jsonb_agg(work_key order by work_key),'[]'::jsonb) into v_required_work
    from (select distinct x.op->>'work_key' work_key from jsonb_array_elements(v_pair.operations) as x(op)) q;
    insert into public.pdc_authenticated_email_import_receipts(
      actor_id,idempotency_key,request_hash,source_hash,evidence_hash,source_uid,sender_address,source_received_at,
      stock_number,backend_record_id,vehicle_id,identity_source,required_work,response
    ) values(
      v_actor_id,'pdc-reset-136-row-'||v_pair.source_row_no,
      encode(digest('request|'||v_source_hash,'sha256'),'hex'),v_source_hash,
      encode(digest('evidence|'||v_source_hash,'sha256'),'hex'),
      'pdc-reset-136:'||v_pair.stock_number||':'||v_pair.job_card_number||':row'||v_pair.source_row_no,
      v_actor_email,v_now,v_pair.stock_number,v_pair.backend_record_id,v_pair.vehicle_id,'workbook_stock_only',v_required_work,
      jsonb_build_object('ok',true,'code','pdc_staging_workbook_reset_136','job_card_number',v_pair.job_card_number,
        'source_row_no',v_pair.source_row_no,'booking_created',false,'completion_changed',false,'parts_changed',false)
    ) returning receipt_id into v_receipt_id;

    for v_op in select value op from jsonb_array_elements(v_pair.operations) loop
      insert into public.pdc_authenticated_email_operation_lines(
        import_receipt_id,vehicle_id,source_hash,source_uid,operation_no,work_key,description,operation_fingerprint,
        estimated_hours,estimated_hours_source,job_card_number,source_row_no,source_contract
      ) values(
        v_receipt_id,v_pair.vehicle_id,v_source_hash,
        'pdc-reset-136:'||v_pair.stock_number||':'||v_pair.job_card_number||':row'||v_pair.source_row_no,
        v_op.op->>'operation_no',v_op.op->>'work_key',v_op.op->>'description',
        encode(digest(v_source_hash||'|'||(v_op.op->>'operation_no')||'|'||(v_op.op->>'work_key')||'|'||(v_op.op->>'description'),'sha256'),'hex'),
        nullif(v_op.op->>'estimated_hours','')::numeric,nullif(v_op.op->>'estimated_hours_source',''),
        v_pair.job_card_number,v_pair.source_row_no,'pdc_staging_workbook_reset_136'
      );
    end loop;
    insert into public.pdc_staging_reset_rows(reset_id,source_row_no,job_card_number,stock_number,accepted,
      backend_record_id,vehicle_id,target_location,source_hash,operation_count)
    values(v_reset_id,v_pair.source_row_no,v_pair.job_card_number,v_pair.stock_number,true,
      v_pair.backend_record_id,v_pair.vehicle_id,v_pair.target_location,v_source_hash,jsonb_array_length(v_pair.operations));
  end loop;

  insert into public.pdc_staging_reset_rows(reset_id,source_row_no,job_card_number,stock_number,accepted,reason,operation_count)
  select v_reset_id,source_row_no,job_card_number,stock_number,false,reason,operation_count
  from pdc_reset_exceptions_136 order by source_row_no;

  insert into public.vehicle_work_items(vehicle_id,work_key,required,completed,completed_by,completed_at,notes,updated_at)
  select distinct p.vehicle_id,x.op->>'work_key',true,false,null::uuid,null::timestamptz,
    'Required by staging workbook reset 136; not completed, not booked',v_now
  from pdc_reset_pairs_136 p cross join lateral jsonb_array_elements(p.operations) as x(op);
  get diagnostics v_work_rows=row_count;

  select count(*) into v_operation_rows from public.pdc_authenticated_email_operation_lines
  where source_contract='pdc_staging_workbook_reset_136';
  if v_operation_rows<>2943 then raise exception 'PDC_RESET_136_OPERATION_COUNT:%',v_operation_rows using errcode='55000'; end if;

  insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
  select 'update'::public.audit_action,'vehicles',v.id,v.id,v_actor_id,v_actor_email,to_jsonb(b),to_jsonb(v),
    jsonb_build_object('source','pdc_staging_workbook_reset_136','reset_id',v_reset_id,
      'accepted',s.vehicle_id is not null,'target_location',s.target_location,'backup_manifest_sha256',p_backup_manifest_sha256,
      'booking_created',false,'completion_changed',false,'parts_changed',false)
  from public.vehicles v join pdc_reset_vehicle_before_136 b on b.id=v.id
  left join pdc_reset_stocks_136 s on s.vehicle_id=v.id
  where to_jsonb(b) is distinct from to_jsonb(v);

  update public.pdc_email_vehicle_revision set revision=revision+1,updated_at=v_now where singleton;
  update public.navision_backend_revision set revision=revision+1,updated_at=v_now where singleton;

  select jsonb_build_object(
    'vehicles_total',(select count(*) from public.vehicles),
    'vehicles_visible',(select count(*) from public.vehicles where visible_on_board and deleted_at is null),
    'vehicles_active',(select count(*) from public.vehicles where lifecycle_state='active' and deleted_at is null),
    'active_unique_stocks',(select count(distinct public.normalize_vehicle_stock_number(stock_number)) from public.vehicles where visible_on_board and deleted_at is null and lifecycle_state='active'),
    'work_items',(select count(*) from public.vehicle_work_items),
    'completed_work_items',(select count(*) from public.vehicle_work_items where completed),
    'operation_lines',(select count(*) from public.pdc_authenticated_email_operation_lines),
    'reset_operation_lines',v_operation_rows,
    'bookings',(select count(*) from public.workshop_bookings),
    'parts_updates',(select count(*) from public.vehicle_parts_updates),
    'line_adjustments',(select count(*) from public.vehicle_workshop_line_adjustments),
    'sublet_bookings',(select count(*) from public.pdc_sublet_bookings),
    'accepted_rows',(select count(*) from public.pdc_staging_reset_rows where reset_id=v_reset_id and accepted),
    'exception_rows',(select count(*) from public.pdc_staging_reset_rows where reset_id=v_reset_id and not accepted),
    'work_item_rows',v_work_rows
  ) into v_after;

  if (v_after->>'vehicles_visible')::integer<>325 or (v_after->>'vehicles_active')::integer<>325
     or (v_after->>'active_unique_stocks')::integer<>325 or (v_after->>'operation_lines')::integer<>2943
     or (v_after->>'completed_work_items')::integer<>0 or (v_after->>'bookings')::integer<>0
     or (v_after->>'parts_updates')::integer<>0 or (v_after->>'line_adjustments')::integer<>0
     or (v_after->>'sublet_bookings')::integer<>0 or (v_after->>'accepted_rows')::integer<>330
     or (v_after->>'exception_rows')::integer<>81 then
    raise exception 'PDC_RESET_136_POSTCONDITION:%',v_after using errcode='55000';
  end if;

  insert into public.pdc_staging_reset_batches(reset_id,contract,workbook_sha256,source_payload_sha256,
    accepted_payload_sha256,authority_binding_sha256,backup_manifest_sha256,actor_id,actor_email,before_counts,after_counts,summary)
  values(v_reset_id,'pdc_staging_workbook_reset_136',p_preview#>>'{summary,workbook_sha256}',
    p_preview#>>'{summary,source_payload_sha256}',p_preview#>>'{summary,accepted_payload_sha256}',
    p_preview#>>'{summary,authority_binding_sha256}',p_backup_manifest_sha256,v_actor_id,v_actor_email,v_before,v_after,p_preview->'summary');

  insert into public.audit_events(action,table_name,row_id,actor_id,actor_email,before_data,after_data,metadata)
  values('import','pdc_staging_reset_batches',v_reset_id,v_actor_id,v_actor_email,v_before,v_after,
    jsonb_build_object('source','pdc_staging_workbook_reset_136','reset_id',v_reset_id,
      'workbook_sha256',p_preview#>>'{summary,workbook_sha256}','backup_manifest_sha256',p_backup_manifest_sha256,
      'accepted_stocks',325,'accepted_pairs',330,'operation_lines',2943,'exception_pairs',81,
      'booking_created',false,'completion_changed',false,'parts_changed',false));

  return jsonb_build_object('ok',true,'code','pdc_staging_workbook_reset_136_applied','reset_id',v_reset_id,
    'before',v_before,'after',v_after,'workbook_sha256',p_preview#>>'{summary,workbook_sha256}',
    'accepted_payload_sha256',p_preview#>>'{summary,accepted_payload_sha256}',
    'backup_manifest_sha256',p_backup_manifest_sha256,'production_changed',false);
end;
$reset$;
revoke all on function public.apply_pdc_staging_workbook_reset_136(jsonb,text) from public,anon,authenticated,service_role;

-- Preserve complete Job Card identity in the bounded board snapshot.
create or replace function public.get_pdc_email_vehicle_location_snapshot()
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $snapshot$
declare v_role text; v_revision bigint; v_rows jsonb;
begin
  v_role:=public.current_pdc_user_role()::text;
  if v_role not in ('viewer','operator','importer','administrator') then return public.navision_backend_response(false,'unauthorized'); end if;
  select revision into v_revision from public.pdc_email_vehicle_revision where singleton;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,'version',v.version,'stock_number',v.stock_number,'vin',v.vin,
    'job_card_number',v.job_card_number,'customer_name',v.customer_name,'vehicle_description',v.vehicle_description,
    'salesperson_reference',v.salesperson_reference,'registration',v.registration,'eta_to_kewdale',v.eta_to_kewdale,
    'current_location',v.current_location,'visible_on_board',v.visible_on_board,'source_system',v.source_system,
    'source_record_id',v.source_record_id,'updated_at',v.updated_at,
    'work_items',coalesce((select jsonb_agg(jsonb_build_object('work_key',wi.work_key,'required',wi.required,'completed',wi.completed,
      'completed_at',wi.completed_at,'completed_by',wi.completed_by) order by wi.work_key) from public.vehicle_work_items wi where wi.vehicle_id=v.id),'[]'::jsonb),
    'operation_lines',coalesce((select jsonb_agg(jsonb_build_object(
      'operation_line_id',ol.operation_line_id,'operation_no',ol.operation_no,'work_key',ol.work_key,'description',ol.description,
      'estimated_hours',ol.estimated_hours,'estimated_hours_source',ol.estimated_hours_source,'source_uid',ol.source_uid,
      'job_card_number',ol.job_card_number,'source_row_no',ol.source_row_no,'source_contract',ol.source_contract,
      'source_ref',case when ol.job_card_number is null then ol.operation_no else 'JC '||ol.job_card_number||' / '||ol.operation_no end,
      'created_at',ol.created_at) order by ol.source_row_no,
        case when ol.operation_no like 'OP%' then substring(ol.operation_no from 3)::integer else substring(ol.operation_no from 3 for 3)::integer end,
        ol.operation_line_id) from (select line.* from public.pdc_authenticated_email_operation_lines line
          where line.vehicle_id=v.id order by line.created_at desc,line.operation_line_id desc limit 50) ol),'[]'::jsonb),
    'parts_required',coalesce((select pu.parts_required from public.vehicle_parts_updates pu where pu.vehicle_id=v.id order by pu.updated_at desc,pu.id desc limit 1),false),
    'parts_completed',coalesce((select wi.completed from public.vehicle_work_items wi where wi.vehicle_id=v.id and wi.work_key='PARTS'),false),
    'parts_update',coalesce((select jsonb_build_object('parts_required',pu.parts_required,'parts_ordered',pu.parts_ordered,
      'parts_received',pu.parts_received,'parts_stoppage',pu.parts_stoppage,'parts_stoppage_reason',pu.parts_stoppage_reason,
      'worst_eta',pu.worst_eta,'previous_worst_eta',(select prior.worst_eta from public.vehicle_parts_updates prior where prior.vehicle_id=v.id and prior.id<>pu.id and prior.worst_eta is not null order by prior.updated_at desc,prior.id desc limit 1),
      'updated_by',pu.updated_by,'updated_at',pu.updated_at) from public.vehicle_parts_updates pu where pu.vehicle_id=v.id order by pu.updated_at desc,pu.id desc limit 1),'{}'::jsonb),
    'sublet_booking',coalesce((select jsonb_build_object('provider',s.provider,'provider_email',s.provider_email,
      'po_sent_date',s.po_sent_date,'booking_date',s.booking_date,'expected_return_date',s.expected_return_date,
      'actual_return_date',s.actual_return_date,'notes',s.notes,'email_sent',s.email_sent,'version',s.version,
      'provider_names',coalesce(to_jsonb(s.provider_names),'[]'::jsonb),'provider_source',coalesce(s.provider_source,''),'updated_at',s.updated_at)
      from public.pdc_sublet_bookings s where s.vehicle_id=v.id),'{}'::jsonb)
  ) order by coalesce(v.stock_number,v.vin,v.permanent_vehicle_id),v.id),'[]'::jsonb) into v_rows
  from public.vehicles v where v.deleted_at is null and v.lifecycle_state='active' and v.visible_on_board
    and exists(select 1 from public.pdc_authenticated_email_import_receipts r where r.vehicle_id=v.id);
  return public.navision_backend_response(true,'ok',jsonb_build_object('revision',coalesce(v_revision,1),'vehicles',v_rows));
end;
$snapshot$;
revoke all on function public.get_pdc_email_vehicle_location_snapshot() from public,anon,authenticated;
grant execute on function public.get_pdc_email_vehicle_location_snapshot() to authenticated;
comment on function public.get_pdc_email_vehicle_location_snapshot() is
  'Restricted staging board snapshot with bounded complete reset-136 Job Card operation identity, Parts ETA and Sublet projections.';

commit;
