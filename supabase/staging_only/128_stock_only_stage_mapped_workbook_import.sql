-- Staging-only migration 128: stock-authoritative, stage-mapped current PMB workbook import.
begin;
set local lock_timeout='5s';
set local statement_timeout='180s';
set local idle_in_transaction_session_timeout='180s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-128-stock-stage-workbook',0));

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
     or to_regclass('public.pdc_production_environment_sentinel') is not null then
    raise exception 'PDC_BULK_128_STAGING_SENTINEL_MISMATCH';
  end if;
  if not exists(select 1 from supabase_migrations.schema_migrations where version='127' and name='admin_bulk_workbook_review_page') then
    raise exception 'PDC_BULK_128_PREDECESSOR_127_IDENTITY_MISMATCH';
  end if;
  if exists(select 1 from supabase_migrations.schema_migrations where version='128') then
    raise exception 'PDC_BULK_128_VERSION_CONFLICT';
  end if;
end;
$guard$;

alter table public.pdc_bulk_workbook_authorizations
  add column authorized_payload_sha256 text,
  add column stage_mapping_policy text,
  add constraint pdc_bulk_workbook_authorized_payload_sha256_check
    check(authorized_payload_sha256 is null or authorized_payload_sha256 ~ '^[a-f0-9]{64}$'),
  add constraint pdc_bulk_workbook_stage_mapping_policy_check
    check(stage_mapping_policy is null or stage_mapping_policy='pmb-workshop-stages-v1');

alter table public.pdc_bulk_workbook_previews
  add column stage_mapping_policy text,
  add column accepted_stock_count integer,
  add constraint pdc_bulk_workbook_preview_stage_mapping_policy_check
    check(stage_mapping_policy is null or stage_mapping_policy='pmb-workshop-stages-v1'),
  add constraint pdc_bulk_workbook_preview_accepted_stock_count_check
    check(accepted_stock_count is null or accepted_stock_count between 1 and row_count);

alter table public.pdc_bulk_workbook_apply_receipts
  add column stage_mapping_policy text,
  add column unique_stock_count integer,
  add column vehicles_created integer,
  add constraint pdc_bulk_workbook_apply_stage_mapping_policy_check
    check(stage_mapping_policy is null or stage_mapping_policy='pmb-workshop-stages-v1'),
  add constraint pdc_bulk_workbook_apply_unique_stock_count_check
    check(unique_stock_count is null or unique_stock_count between 1 and accepted_count),
  add constraint pdc_bulk_workbook_apply_vehicles_created_check
    check(vehicles_created is null or vehicles_created between 0 and unique_stock_count);

alter table public.pdc_bulk_workbook_quarantine drop constraint pdc_bulk_workbook_quarantine_reason_code_check;
alter table public.pdc_bulk_workbook_quarantine add constraint pdc_bulk_workbook_quarantine_reason_code_check check(reason_code in (
  'missing_authoritative_work_key','multiple_current_identity_matches','partial_identity_disagreement',
  'operational_identity_conflict','operational_exact_without_current_navision','no_current_match',
  'multiple_current_navision_stock_matches','multiple_operational_stock_matches',
  'protected_existing_lifecycle','navision_activation_conflict'
));

alter table public.pdc_bulk_workbook_row_receipts alter column backend_record_id drop not null;
alter table public.pdc_bulk_workbook_row_receipts drop constraint pdc_bulk_workbook_row_receipts_classification_check;
alter table public.pdc_bulk_workbook_row_receipts add constraint pdc_bulk_workbook_row_receipts_classification_check check(classification in (
  'unique_exact_current','stock_existing','stock_created_navision','stock_created_workbook'
));
alter table public.pdc_bulk_workbook_row_receipts drop constraint pdc_bulk_workbook_row_receipts_operation_count_check;
alter table public.pdc_bulk_workbook_row_receipts add constraint pdc_bulk_workbook_row_receipts_operation_count_check check(operation_count>=0);

alter table public.pdc_authenticated_email_import_receipts drop constraint pdc_authenticated_email_import_receipts_identity_source_check;
alter table public.pdc_authenticated_email_import_receipts add constraint pdc_authenticated_email_import_receipts_identity_source_check
  check(identity_source in ('navision_exact','operational_exact','email_new','workbook_stock_only'));

alter table public.pdc_authenticated_email_operation_lines drop constraint pdc_authenticated_email_operation_lines_work_key_check;
alter table public.pdc_authenticated_email_operation_lines add constraint pdc_authenticated_email_operation_lines_work_key_check
  check(work_key in ('bus4x4','tint','hoist','fitting','fabrication','electrical','tyre','pitInspection','PARTS','sublet'));

create or replace function public.authorize_pdc_bulk_stock_stage_workbook(
  p_workbook_sha256 text,
  p_payload_sha256 text,
  p_expected_pair_count integer,
  p_expected_operation_count integer,
  p_stage_mapping_policy text
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions as $authorize$
declare
  v_scope jsonb:=public.pdc_bulk_workbook_actor_scope(); v_uid uuid;
  v_workbook text:=lower(btrim(coalesce(p_workbook_sha256,'')));
  v_payload text:=lower(btrim(coalesce(p_payload_sha256,'')));
  v_existing public.pdc_bulk_workbook_authorizations%rowtype; v_id uuid; v_expires timestamptz;
begin
  if not coalesce((v_scope->>'ok')::boolean,false) then return v_scope; end if;
  v_uid:=(v_scope->'data'->>'actor_id')::uuid;
  if v_workbook !~ '^[a-f0-9]{64}$' or v_payload !~ '^[a-f0-9]{64}$'
     or p_expected_pair_count not between 1 and 500
     or p_expected_operation_count not between 1 and 50000
     or p_stage_mapping_policy<>'pmb-workshop-stages-v1' then
    return public.navision_backend_response(false,'invalid_stock_stage_authorization_binding');
  end if;
  perform pg_advisory_xact_lock(hashtextextended('pdc-bulk-stock-stage-authorize:'||v_uid::text,0));
  select * into v_existing from public.pdc_bulk_workbook_authorizations
   where actor_id=v_uid and workbook_sha256=v_workbook
     and authorized_payload_sha256=v_payload and stage_mapping_policy=p_stage_mapping_policy
     and expected_pair_count=p_expected_pair_count and expected_operation_count=p_expected_operation_count
     and status in ('available','claimed','applied')
     and (status<>'available' or expires_at>clock_timestamp())
   order by created_at desc limit 1;
  if found then
    return public.navision_backend_response(true,'exact_stock_stage_authorization_replay',jsonb_build_object(
      'authorization_id',v_existing.authorization_id,'workbook_sha256',v_workbook,'payload_sha256',v_payload,
      'expected_pair_count',p_expected_pair_count,'expected_operation_count',p_expected_operation_count,
      'stage_mapping_policy',p_stage_mapping_policy,'expires_at',v_existing.expires_at,'status',v_existing.status));
  end if;
  update public.pdc_bulk_workbook_authorizations set status='expired'
   where actor_id=v_uid and status='available' and expires_at<=clock_timestamp();
  v_expires:=clock_timestamp()+interval '2 hours';
  insert into public.pdc_bulk_workbook_authorizations(
    actor_id,workbook_sha256,authorized_payload_sha256,stage_mapping_policy,
    expected_pair_count,expected_operation_count,expires_at
  ) values(v_uid,v_workbook,v_payload,p_stage_mapping_policy,p_expected_pair_count,p_expected_operation_count,v_expires)
  returning authorization_id into v_id;
  return public.navision_backend_response(true,'stock_stage_authorized',jsonb_build_object(
    'authorization_id',v_id,'workbook_sha256',v_workbook,'payload_sha256',v_payload,
    'expected_pair_count',p_expected_pair_count,'expected_operation_count',p_expected_operation_count,
    'stage_mapping_policy',p_stage_mapping_policy,'expires_at',v_expires));
end;
$authorize$;

create or replace function public.preview_pdc_bulk_stock_stage_workbook(
  p_workbook_sha256 text,p_payload jsonb,p_authorized_payload_sha256 text,p_stage_mapping_policy text
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions set statement_timeout='180s' as $preview$
declare
  v_scope jsonb:=public.pdc_bulk_workbook_actor_scope(); v_uid uuid;
  v_workbook text:=lower(btrim(coalesce(p_workbook_sha256,''))); v_payload jsonb:=coalesce(p_payload,'null'::jsonb);
  v_authorized_payload text:=lower(btrim(coalesce(p_authorized_payload_sha256,'')));
  v_payload_sha text; v_auth public.pdc_bulk_workbook_authorizations%rowtype;
  v_existing public.pdc_bulk_workbook_previews%rowtype; v_preview_id uuid:=gen_random_uuid();
  v_row jsonb; v_row_no integer; v_jc text; v_stock text; v_reason text; v_ops integer;
  v_active integer; v_any integer; v_nav integer; v_rows integer; v_operation_count integer;
  v_accepted integer:=0; v_accepted_stocks integer:=0; v_quarantine integer:=0; v_operation_quarantine integer:=0;
begin
  if not coalesce((v_scope->>'ok')::boolean,false) then return v_scope; end if;
  v_uid:=(v_scope->'data'->>'actor_id')::uuid;
  if v_workbook !~ '^[a-f0-9]{64}$' or v_authorized_payload !~ '^[a-f0-9]{64}$' or p_stage_mapping_policy<>'pmb-workshop-stages-v1'
     or jsonb_typeof(v_payload) is distinct from 'array' or jsonb_array_length(v_payload) not between 1 and 500 then
    return public.navision_backend_response(false,'invalid_stock_stage_payload');
  end if;
  if exists(select 1 from jsonb_array_elements(v_payload) r where jsonb_typeof(r)<>'object'
    or not (r ?& array['row_no','job_card_number','stock_number','operations'])
    or exists(select 1 from jsonb_object_keys(r) k where k<>all(array['row_no','job_card_number','stock_number','vin','customer_name','vehicle_description','registration','salesperson_reference','eta_to_kewdale','operations']))
    or jsonb_typeof(r->'row_no')<>'number' or coalesce(r->>'row_no','') !~ '^[1-9][0-9]{0,5}$'
    or length(coalesce(r->>'job_card_number','')) not between 1 and 60 or r->>'job_card_number' is distinct from btrim(r->>'job_card_number') or r->>'job_card_number' ~ '[[:cntrl:]]'
    or length(coalesce(r->>'stock_number','')) not between 1 and 80 or r->>'stock_number' is distinct from btrim(r->>'stock_number') or r->>'stock_number' ~ '[[:cntrl:]]' or not public.is_real_vehicle_stock_number(r->>'stock_number')
    or jsonb_typeof(r->'operations')<>'array' or jsonb_array_length(r->'operations')>100
    or exists(select 1 from jsonb_array_elements(r->'operations') o where jsonb_typeof(o)<>'object'
      or (select array_agg(k order by k) from jsonb_object_keys(o) k) is distinct from array['description','estimated_hours','estimated_hours_source','operation_no','work_key']::text[]
      or coalesce(o->>'operation_no','') !~ '^OP([1-9]|[1-9][0-9]|100)$'
      or jsonb_typeof(o->'work_key')<>'string' or o->>'work_key' not in ('bus4x4','tint','hoist','fitting','fabrication','electrical','tyre','PARTS','pitInspection','sublet')
      or length(coalesce(o->>'description','')) not between 1 and 180 or o->>'description' is distinct from btrim(o->>'description') or o->>'description' ~ '[[:cntrl:]]'
      or jsonb_typeof(o->'estimated_hours') not in ('number','null')
      or (jsonb_typeof(o->'estimated_hours')='number' and coalesce(o->>'estimated_hours_source','') not in ('job_card','ai_estimate'))
      or (jsonb_typeof(o->'estimated_hours')='null' and o->>'estimated_hours_source' is not null)
      or (jsonb_typeof(o->'estimated_hours')='number' and ((o->>'estimated_hours')::numeric<0 or (o->>'estimated_hours')::numeric>999.99 or mod((o->>'estimated_hours')::numeric,0.01)<>0))
    ) or (select count(*) from jsonb_array_elements(r->'operations'))<>(select count(distinct o->>'operation_no') from jsonb_array_elements(r->'operations') o)
  ) then return public.navision_backend_response(false,'invalid_stock_stage_row_or_operation'); end if;
  if jsonb_array_length(v_payload)<>(select count(distinct (r->>'row_no')::integer) from jsonb_array_elements(v_payload) r)
     or jsonb_array_length(v_payload)<>(select count(distinct upper(btrim(r->>'job_card_number'))||'|'||public.normalize_vehicle_stock_number(r->>'stock_number')) from jsonb_array_elements(v_payload) r) then
    return public.navision_backend_response(false,'duplicate_stock_stage_source_row');
  end if;
  v_rows:=jsonb_array_length(v_payload);
  select coalesce(sum(jsonb_array_length(r->'operations')),0) into v_operation_count from jsonb_array_elements(v_payload) r;
  v_payload_sha:=public.pdc_bulk_workbook_canonical_payload_sha256(v_payload);
  perform pg_advisory_xact_lock(hashtextextended('pdc-bulk-stock-stage-preview:'||v_uid::text,0));
  select * into v_auth from public.pdc_bulk_workbook_authorizations a
   where a.actor_id=v_uid and a.workbook_sha256=v_workbook and a.authorized_payload_sha256=v_authorized_payload
     and a.stage_mapping_policy=p_stage_mapping_policy and a.expected_pair_count=v_rows
     and a.expected_operation_count=v_operation_count and a.status='available' and a.expires_at>clock_timestamp()
   order by a.created_at desc limit 1 for update;
  if not found then
    select * into v_auth from public.pdc_bulk_workbook_authorizations a
     where a.actor_id=v_uid and a.workbook_sha256=v_workbook and a.authorized_payload_sha256=v_authorized_payload
       and a.stage_mapping_policy=p_stage_mapping_policy and a.claimed_payload_sha256=v_payload_sha
       and a.status in ('claimed','applied') order by a.created_at desc limit 1;
    if not found then return public.navision_backend_response(false,'stock_stage_authorization_not_available'); end if;
    select * into strict v_existing from public.pdc_bulk_workbook_previews where preview_id=v_auth.claimed_preview_id and actor_id=v_uid;
    return public.navision_backend_response(true,'exact_stock_stage_preview_replay',jsonb_build_object(
      'preview_id',v_existing.preview_id,'authorization_id',v_auth.authorization_id,
      'workbook_sha256',v_workbook,'authorized_payload_sha256',v_authorized_payload,'payload_sha256',v_payload_sha,'stage_mapping_policy',p_stage_mapping_policy,
      'row_count',v_existing.row_count,'operation_count',v_existing.operation_count,
      'accepted_count',v_existing.accepted_count,'accepted_stock_count',v_existing.accepted_stock_count,
      'quarantine_count',v_existing.quarantine_count,'operation_quarantine_count',v_existing.operation_quarantine_count,
      'blocked_count',v_existing.blocked_count,'applyable',v_existing.accepted_count>0));
  end if;
  create temporary table pg_temp.pdc_bulk_stock_stage_classification(
    row_no integer primary key,jc text,stock text,reason text,op_quarantine integer,row_payload jsonb
  ) on commit drop;
  for v_row in select value from jsonb_array_elements(v_payload) loop
    v_row_no:=(v_row->>'row_no')::integer; v_jc:=upper(btrim(v_row->>'job_card_number'));
    v_stock:=public.normalize_vehicle_stock_number(v_row->>'stock_number'); v_ops:=jsonb_array_length(v_row->'operations'); v_reason:=null;
    select count(*) into v_nav from public.navision_backend_records r where r.source_system='microsoft_navision' and r.record_status='current' and r.is_current and public.normalize_vehicle_stock_number(r.normalized_data->>'batch')=v_stock;
    select count(*) filter(where v.deleted_at is null and v.lifecycle_state='active'),count(*) into v_active,v_any from public.vehicles v where public.normalize_vehicle_stock_number(v.stock_number)=v_stock;
    if v_nav>1 then v_reason:='multiple_current_navision_stock_matches';
    elsif v_any>1 or v_active>1 then v_reason:='multiple_operational_stock_matches';
    elsif v_active=0 and v_any=1 then v_reason:='protected_existing_lifecycle';
    elsif v_nav=1 and exists(
      select 1 from public.navision_backend_records r join public.navision_board_activations a on a.backend_record_id=r.id
      left join public.vehicles v on v.id=a.canonical_vehicle_id
      where r.source_system='microsoft_navision' and r.record_status='current' and r.is_current
        and public.normalize_vehicle_stock_number(r.normalized_data->>'batch')=v_stock
        and (not a.active or a.completed_at is not null or (a.canonical_vehicle_id is not null and (v.id is null or v.deleted_at is not null or v.lifecycle_state<>'active' or public.normalize_vehicle_stock_number(v.stock_number)<>v_stock)))
    ) then v_reason:='navision_activation_conflict';
    else v_accepted:=v_accepted+1; end if;
    if v_reason is not null then v_quarantine:=v_quarantine+1; v_operation_quarantine:=v_operation_quarantine+v_ops; end if;
    insert into pg_temp.pdc_bulk_stock_stage_classification values(v_row_no,v_jc,v_stock,v_reason,case when v_reason is null then 0 else v_ops end,v_row);
  end loop;
  select count(distinct stock) into v_accepted_stocks from pg_temp.pdc_bulk_stock_stage_classification where reason is null;
  insert into public.pdc_bulk_workbook_previews(
    preview_id,authorization_id,actor_id,workbook_sha256,payload_sha256,preview_payload,row_count,operation_count,
    accepted_count,quarantine_count,operation_quarantine_count,blocked_count,stage_mapping_policy,accepted_stock_count
  ) values(v_preview_id,v_auth.authorization_id,v_uid,v_workbook,v_payload_sha,v_payload,v_rows,v_operation_count,
    v_accepted,v_quarantine,v_operation_quarantine,0,p_stage_mapping_policy,v_accepted_stocks);
  insert into public.pdc_bulk_workbook_quarantine(preview_id,row_no,job_card_number,stock_number,reason_code,operation_quarantine_count,row_payload)
  select v_preview_id,row_no,jc,stock,reason,op_quarantine,row_payload from pg_temp.pdc_bulk_stock_stage_classification where reason is not null order by row_no;
  update public.pdc_bulk_workbook_authorizations set claimed_at=clock_timestamp(),claimed_payload_sha256=v_payload_sha,claimed_preview_id=v_preview_id,status='claimed'
   where authorization_id=v_auth.authorization_id and status='available';
  if not found then raise exception 'pdc_bulk_stock_stage_authorization_claim_race' using errcode='40001'; end if;
  return public.navision_backend_response(true,'stock_stage_preview_ready',jsonb_build_object(
    'preview_id',v_preview_id,'authorization_id',v_auth.authorization_id,'workbook_sha256',v_workbook,'authorized_payload_sha256',v_authorized_payload,
    'payload_sha256',v_payload_sha,'stage_mapping_policy',p_stage_mapping_policy,'row_count',v_rows,
    'operation_count',v_operation_count,'accepted_count',v_accepted,'accepted_stock_count',v_accepted_stocks,
    'quarantine_count',v_quarantine,'operation_quarantine_count',v_operation_quarantine,
    'blocked_count',0,'applyable',v_accepted>0));
end;
$preview$;

create or replace function public.apply_pdc_bulk_stock_stage_workbook(
  p_preview_id uuid,p_workbook_sha256 text,p_payload_sha256 text,p_stage_mapping_policy text
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions set statement_timeout='180s' as $apply$
declare
  v_scope jsonb:=public.pdc_bulk_workbook_actor_scope(); v_uid uuid; v_email text;
  v_preview public.pdc_bulk_workbook_previews%rowtype; v_auth public.pdc_bulk_workbook_authorizations%rowtype;
  v_existing public.pdc_bulk_workbook_apply_receipts%rowtype; v_receipt_id uuid:=gen_random_uuid(); v_receipt_hash text;
  v_row jsonb; v_op jsonb; v_row_no integer; v_jc text; v_stock text; v_source_hash text; v_source_uid text;
  v_backend uuid; v_vehicle uuid; v_import_receipt uuid; v_line uuid; v_classification text;
  v_record public.navision_backend_records%rowtype; v_before public.vehicle_work_items%rowtype; v_after public.vehicle_work_items%rowtype;
  v_active integer; v_any integer; v_nav integer; v_row_lines integer; v_row_hours integer;
  v_lines_added integer:=0; v_work_added integer:=0; v_vehicles_created integer:=0;
  v_eta date; v_eta_text text; v_location text; v_vin text; v_vehicle_description text; v_customer text; v_registration text; v_job text; v_order text; v_salesperson text;
begin
  if not coalesce((v_scope->>'ok')::boolean,false) then return v_scope; end if;
  v_uid:=(v_scope->'data'->>'actor_id')::uuid; v_email:=v_scope->'data'->>'actor_email';
  if p_preview_id is null or lower(btrim(coalesce(p_workbook_sha256,''))) !~ '^[a-f0-9]{64}$'
     or lower(btrim(coalesce(p_payload_sha256,''))) !~ '^[a-f0-9]{64}$'
     or p_stage_mapping_policy<>'pmb-workshop-stages-v1' then
    return public.navision_backend_response(false,'invalid_stock_stage_apply_binding');
  end if;
  perform pg_advisory_xact_lock(hashtextextended('pdc-bulk-stock-stage-apply:'||p_preview_id::text,0));
  select * into v_preview from public.pdc_bulk_workbook_previews where preview_id=p_preview_id and actor_id=v_uid for share;
  if not found then return public.navision_backend_response(false,'stock_stage_preview_not_found'); end if;
  select * into v_auth from public.pdc_bulk_workbook_authorizations where authorization_id=v_preview.authorization_id and actor_id=v_uid for update;
  if v_auth.claimed_preview_id<>v_preview.preview_id or v_auth.workbook_sha256<>lower(btrim(p_workbook_sha256))
     or v_auth.authorized_payload_sha256 is null or v_auth.claimed_payload_sha256<>lower(btrim(p_payload_sha256))
     or v_auth.stage_mapping_policy<>p_stage_mapping_policy or v_preview.stage_mapping_policy<>p_stage_mapping_policy
     or v_preview.workbook_sha256<>lower(btrim(p_workbook_sha256)) or v_preview.payload_sha256<>lower(btrim(p_payload_sha256))
     or public.pdc_bulk_workbook_canonical_payload_sha256(v_preview.preview_payload)<>v_preview.payload_sha256 then
    return public.navision_backend_response(false,'stock_stage_apply_binding_mismatch');
  end if;
  select * into v_existing from public.pdc_bulk_workbook_apply_receipts where preview_id=p_preview_id;
  if found then return public.navision_backend_response(true,'exact_stock_stage_replay',jsonb_build_object(
    'receipt_id',v_existing.receipt_id,'preview_id',p_preview_id,'workbook_sha256',v_existing.workbook_sha256,
    'payload_sha256',v_existing.payload_sha256,'stage_mapping_policy',v_existing.stage_mapping_policy,
    'accepted_count',v_existing.accepted_count,'unique_stock_count',v_existing.unique_stock_count,
    'quarantine_count',v_existing.quarantine_count,'operation_quarantine_count',v_existing.operation_quarantine_count,
    'operation_lines_added',v_existing.operation_lines_added,'work_items_added',v_existing.work_items_added,
    'vehicles_created',v_existing.vehicles_created,'receipt_hash',v_existing.receipt_hash,'zero_add_replay',true)); end if;
  if v_preview.accepted_count=0 then return public.navision_backend_response(false,'zero_accepted_stock_stage_preview'); end if;
  if v_auth.status<>'claimed' or v_auth.expires_at<=clock_timestamp() or v_preview.blocked_count<>0
     or v_preview.row_count<>v_auth.expected_pair_count or v_preview.operation_count<>v_auth.expected_operation_count then
    return public.navision_backend_response(false,'stock_stage_authorization_or_preview_not_applyable');
  end if;
  for v_row in select value from jsonb_array_elements(v_preview.preview_payload) r
    where not exists(select 1 from public.pdc_bulk_workbook_quarantine q where q.preview_id=p_preview_id and q.row_no=(r.value->>'row_no')::integer)
    order by (value->>'row_no')::integer loop
    v_row_no:=(v_row->>'row_no')::integer; v_jc:=upper(btrim(v_row->>'job_card_number'));
    v_stock:=public.normalize_vehicle_stock_number(v_row->>'stock_number');
    perform pg_advisory_xact_lock(hashtextextended('pdc-bulk-stock:'||v_stock,0));
    select count(*) into v_nav from public.navision_backend_records r where r.source_system='microsoft_navision' and r.record_status='current' and r.is_current and public.normalize_vehicle_stock_number(r.normalized_data->>'batch')=v_stock;
    select count(*) filter(where v.deleted_at is null and v.lifecycle_state='active'),count(*) into v_active,v_any from public.vehicles v where public.normalize_vehicle_stock_number(v.stock_number)=v_stock;
    if v_nav>1 or v_any>1 or v_active>1 or (v_active=0 and v_any>0) then
      raise exception 'pdc_bulk_stock_identity_no_longer_unique row %',v_row_no using errcode='40001';
    end if;
    v_backend:=null; v_record:=null;
    if v_nav=1 then
      select * into strict v_record from public.navision_backend_records r where r.source_system='microsoft_navision' and r.record_status='current' and r.is_current and public.normalize_vehicle_stock_number(r.normalized_data->>'batch')=v_stock;
      v_backend:=v_record.id;
      if exists(select 1 from public.navision_board_activations a left join public.vehicles av on av.id=a.canonical_vehicle_id
        where a.backend_record_id=v_backend and (not a.active or a.completed_at is not null or (a.canonical_vehicle_id is not null and (av.id is null or av.deleted_at is not null or av.lifecycle_state<>'active' or public.normalize_vehicle_stock_number(av.stock_number)<>v_stock)))) then
        raise exception 'pdc_bulk_stock_activation_conflict row %',v_row_no using errcode='40001';
      end if;
    end if;
    if v_active=1 then
      select id into strict v_vehicle from public.vehicles where deleted_at is null and lifecycle_state='active' and public.normalize_vehicle_stock_number(stock_number)=v_stock;
      v_classification:='stock_existing';
    else
      v_vehicle:=extensions.uuid_generate_v5('b58b5f75-d004-5a76-b9aa-48c801b4ad7d'::uuid,'bulk-stock:'||v_preview.workbook_sha256||':'||v_stock);
      v_eta:=null; v_eta_text:=null; v_vin:=null; v_vehicle_description:=null; v_customer:=null; v_registration:=null; v_job:=null; v_order:=null; v_salesperson:=null;
      if v_backend is not null then
        v_eta_text:=coalesce(nullif(btrim(v_record.normalized_data->>'navisionKewdaleEta'),''),nullif(btrim(v_record.normalized_data->>'etaAtDealer'),''));
        if v_eta_text ~ '^\d{4}-\d{2}-\d{2}$' and to_char(to_date(v_eta_text,'YYYY-MM-DD'),'YYYY-MM-DD')=v_eta_text then v_eta:=to_date(v_eta_text,'YYYY-MM-DD'); end if;
        v_vin:=case when public.is_valid_vehicle_vin(v_record.normalized_data->>'vin') then nullif(public.normalize_vehicle_vin(v_record.normalized_data->>'vin'),'') end;
        v_customer:=coalesce(nullif(btrim(v_record.normalized_data->>'client'),''),nullif(btrim(v_record.normalized_data->>'customerSurname'),''),nullif(btrim(v_record.normalized_data->>'dealerCustomerName'),''),nullif(btrim(v_record.normalized_data->>'toyotaCustomer'),''));
        v_vehicle_description:=coalesce(nullif(btrim(v_record.normalized_data->>'modelDescription'),''),nullif(btrim(v_record.normalized_data->>'toyotaVehicle'),''),nullif(btrim(v_record.normalized_data->>'vehicle'),''));
        v_registration:=nullif(upper(btrim(v_record.normalized_data->>'registration')),'');
        v_job:=nullif(btrim(v_record.normalized_data->>'jobCardNumber'),'');
        v_order:=nullif(btrim(v_record.normalized_data->>'order'),'');
        v_salesperson:=coalesce(public.navision_original_column_value(v_record.normalized_data,'Salesperson'),nullif(btrim(v_record.normalized_data->>'salesperson'),''),nullif(btrim(v_record.normalized_data->>'consultant'),''),nullif(btrim(v_record.normalized_data->>'owner'),''));
      end if;
      v_location:=case when v_eta is not null and v_eta>=current_date then 'IT' else 'YH' end;
      insert into public.vehicles(
        id,permanent_vehicle_id,stock_number,vin,toyota_order_number,job_card_number,customer_name,
        vehicle_description,model,salesperson_reference,registration,lifecycle_state,visible_on_board,current_location,
        eta_to_kewdale,source_system,source_batch_id,source_record_id,source_payload,created_by,updated_by
      ) values(
        v_vehicle,'PDC-BULK-'||upper(substr(encode(extensions.digest(convert_to(v_preview.workbook_sha256||':'||v_stock,'UTF8'),'sha256'),'hex'),1,24)),
        case when v_backend is not null then v_record.normalized_data->>'batch' else v_stock end,v_vin,v_order,v_job,v_customer,
        v_vehicle_description,v_vehicle_description,v_salesperson,v_registration,'active',true,v_location,v_eta,
        case when v_backend is not null then 'microsoft_navision' else 'pdc_bulk_workbook' end,
        case when v_backend is not null then v_record.dealer_code else v_preview.workbook_sha256 end,
        case when v_backend is not null then v_backend::text else v_stock end,
        jsonb_build_object('intake_contract','pdc_bulk_stock_stage_128','bulk_preview_id',p_preview_id,'workbook_sha256',v_preview.workbook_sha256,'stock_only',true),v_uid,v_uid
      );
      v_vehicles_created:=v_vehicles_created+1;
      v_classification:=case when v_backend is null then 'stock_created_workbook' else 'stock_created_navision' end;
      insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
      select 'insert'::public.audit_action,'vehicles',v_vehicle,v_vehicle,v_uid,v_email,null,to_jsonb(v),jsonb_build_object(
        'source','pdc_bulk_stock_stage_128','preview_id',p_preview_id,'row_no',v_row_no,'stock_only',true,'no_booking',true,'completed_work_reopened',false)
      from public.vehicles v where v.id=v_vehicle;
    end if;
    if v_backend is not null then
      if exists(select 1 from public.navision_board_activations a where a.backend_record_id=v_backend and a.canonical_vehicle_id is not null and a.canonical_vehicle_id<>v_vehicle) then
        raise exception 'pdc_bulk_stock_activation_vehicle_conflict row %',v_row_no using errcode='40001';
      end if;
      insert into public.navision_board_activations(backend_record_id,activation_source,activated_stock_number,activated_by,activated_by_email,canonical_vehicle_id,active)
      values(v_backend,'approved_key_list',v_record.normalized_data->>'batch',v_uid,v_email,v_vehicle,true)
      on conflict(backend_record_id) do update set canonical_vehicle_id=coalesce(public.navision_board_activations.canonical_vehicle_id,excluded.canonical_vehicle_id),updated_at=clock_timestamp()
      where public.navision_board_activations.active and public.navision_board_activations.completed_at is null;
    end if;
    v_source_hash:=encode(extensions.digest(convert_to(v_preview.payload_sha256||':'||v_row_no::text,'UTF8'),'sha256'),'hex');
    v_source_uid:='bulk-stock-stage:'||p_preview_id::text||':'||v_row_no::text;
    insert into public.pdc_authenticated_email_import_receipts(
      actor_id,idempotency_key,request_hash,source_hash,evidence_hash,source_uid,sender_address,source_received_at,
      stock_number,vin,backend_record_id,vehicle_id,identity_source,required_work,response
    ) values(
      v_uid,v_source_uid,v_preview.payload_sha256,v_source_hash,v_source_hash,v_source_uid,v_email,v_preview.created_at,
      v_stock,null,v_backend,v_vehicle,case when v_backend is null then 'workbook_stock_only' else 'navision_exact' end,
      coalesce((select jsonb_agg(k order by k) from (select distinct o->>'work_key' k from jsonb_array_elements(v_row->'operations') o) x),'[]'::jsonb),
      jsonb_build_object('source','pdc_bulk_stock_stage_128','preview_id',p_preview_id,'row_no',v_row_no,'stage_mapping_policy',p_stage_mapping_policy,'booking_created',false,'completed_work_reopened',false)
    ) on conflict(source_hash) do nothing returning receipt_id into v_import_receipt;
    if v_import_receipt is null then select receipt_id into strict v_import_receipt from public.pdc_authenticated_email_import_receipts where source_hash=v_source_hash and actor_id=v_uid and vehicle_id=v_vehicle; end if;
    for v_op in select value from jsonb_array_elements(v_row->'operations') loop
      if exists(select 1 from public.pdc_authenticated_email_operation_lines ol where ol.source_hash=v_source_hash and ol.operation_no=v_op->>'operation_no' and
        (ol.vehicle_id<>v_vehicle or ol.work_key<>v_op->>'work_key' or ol.description<>v_op->>'description'
         or ol.estimated_hours is distinct from case when jsonb_typeof(v_op->'estimated_hours')='number' then (v_op->>'estimated_hours')::numeric else null end
         or ol.estimated_hours_source is distinct from v_op->>'estimated_hours_source')) then
        raise exception 'pdc_bulk_stock_operation_identity_conflict row % operation %',v_row_no,v_op->>'operation_no' using errcode='40001';
      end if;
      insert into public.pdc_authenticated_email_operation_lines(
        import_receipt_id,vehicle_id,source_hash,source_uid,operation_no,work_key,description,estimated_hours,estimated_hours_source,operation_fingerprint
      ) values(
        v_import_receipt,v_vehicle,v_source_hash,v_source_uid,v_op->>'operation_no',v_op->>'work_key',v_op->>'description',
        case when jsonb_typeof(v_op->'estimated_hours')='number' then (v_op->>'estimated_hours')::numeric else null end,
        v_op->>'estimated_hours_source',encode(extensions.digest(jsonb_build_object('source_hash',v_source_hash,'operation_no',v_op->>'operation_no','work_key',v_op->>'work_key','description',v_op->>'description')::text,'sha256'),'hex')
      ) on conflict(source_hash,operation_no) do nothing returning operation_line_id into v_line;
      if v_line is not null then
        v_lines_added:=v_lines_added+1;
        insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
        values('insert','pdc_authenticated_email_operation_lines',v_line,v_vehicle,v_uid,v_email,null,
          jsonb_build_object('operation_no',v_op->>'operation_no','work_key',v_op->>'work_key','description',v_op->>'description','estimated_hours',v_op->'estimated_hours','estimated_hours_source',v_op->>'estimated_hours_source'),
          jsonb_build_object('source','pdc_bulk_stock_stage_128','preview_id',p_preview_id,'row_no',v_row_no,'no_booking',true,'completed_work_reopened',false));
      end if;
      v_line:=null; v_before:=null; v_after:=null;
      select * into v_before from public.vehicle_work_items where vehicle_id=v_vehicle and work_key=v_op->>'work_key' for update;
      insert into public.vehicle_work_items(vehicle_id,work_key,required,completed,completed_by,completed_at,notes,updated_at)
      values(v_vehicle,v_op->>'work_key',true,false,null,null,null,clock_timestamp())
      on conflict(vehicle_id,work_key) do update set required=true,updated_at=clock_timestamp()
      where not public.vehicle_work_items.completed and not public.vehicle_work_items.required returning * into v_after;
      if v_after.id is not null and (v_before.id is null or (not v_before.completed and not v_before.required)) then
        v_work_added:=v_work_added+1;
        insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
        values(case when v_before.id is null then 'insert'::public.audit_action else 'update'::public.audit_action end,
          'vehicle_work_items',v_after.id,v_vehicle,v_uid,v_email,case when v_before.id is null then null else to_jsonb(v_before) end,to_jsonb(v_after),
          jsonb_build_object('source','pdc_bulk_stock_stage_128','preview_id',p_preview_id,'row_no',v_row_no,'required_work',v_op->>'work_key','no_booking',true,'completed_work_reopened',false));
      end if;
    end loop;
    select count(*),count(*) filter(where estimated_hours is not null) into v_row_lines,v_row_hours from public.pdc_authenticated_email_operation_lines where source_hash=v_source_hash;
    if v_row_lines<>jsonb_array_length(v_row->'operations') then raise exception 'pdc_bulk_stock_operation_readback_mismatch row %',v_row_no using errcode='40001'; end if;
    insert into public.pdc_bulk_workbook_row_receipts(
      receipt_id,row_no,job_card_number,stock_number,classification,vehicle_id,backend_record_id,source_hash,operation_count,estimated_hours_count
    ) values(v_receipt_id,v_row_no,v_jc,v_stock,v_classification,v_vehicle,v_backend,v_source_hash,v_row_lines,v_row_hours);
  end loop;
  v_receipt_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'receipt_id',v_receipt_id,'preview_id',p_preview_id,'authorization_id',v_auth.authorization_id,
    'workbook_sha256',v_preview.workbook_sha256,'payload_sha256',v_preview.payload_sha256,
    'stage_mapping_policy',p_stage_mapping_policy,'accepted_count',v_preview.accepted_count,
    'unique_stock_count',v_preview.accepted_stock_count,'quarantine_count',v_preview.quarantine_count,
    'operation_quarantine_count',v_preview.operation_quarantine_count,'operation_lines_added',v_lines_added,
    'work_items_added',v_work_added,'vehicles_created',v_vehicles_created)::text,'UTF8'),'sha256'),'hex');
  insert into public.pdc_bulk_workbook_apply_receipts(
    receipt_id,preview_id,authorization_id,actor_id,workbook_sha256,payload_sha256,accepted_count,quarantine_count,
    operation_quarantine_count,operation_lines_added,work_items_added,receipt_hash,stage_mapping_policy,unique_stock_count,vehicles_created
  ) values(v_receipt_id,p_preview_id,v_auth.authorization_id,v_uid,v_preview.workbook_sha256,v_preview.payload_sha256,v_preview.accepted_count,v_preview.quarantine_count,
    v_preview.operation_quarantine_count,v_lines_added,v_work_added,v_receipt_hash,p_stage_mapping_policy,v_preview.accepted_stock_count,v_vehicles_created);
  update public.pdc_bulk_workbook_authorizations set status='applied' where authorization_id=v_auth.authorization_id and status='claimed';
  return public.navision_backend_response(true,'stock_stage_applied',jsonb_build_object(
    'receipt_id',v_receipt_id,'preview_id',p_preview_id,'accepted_count',v_preview.accepted_count,
    'unique_stock_count',v_preview.accepted_stock_count,'quarantine_count',v_preview.quarantine_count,
    'operation_quarantine_count',v_preview.operation_quarantine_count,'operation_lines_added',v_lines_added,
    'work_items_added',v_work_added,'vehicles_created',v_vehicles_created,'receipt_hash',v_receipt_hash,
    'stage_mapping_policy',p_stage_mapping_policy,'booking_created',false,'completed_work_reopened',false,
    'parts_completion_created',false,'zero_add_replay',false));
end;
$apply$;

create or replace function public.read_pdc_bulk_stock_stage_receipt(p_receipt_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,extensions as $readback$
declare
  v_scope jsonb:=public.pdc_bulk_workbook_actor_scope(); v_uid uuid; v_receipt public.pdc_bulk_workbook_apply_receipts%rowtype;
  v_pairs integer; v_stocks integer; v_lines integer; v_hours integer; v_created integer; v_mismatch integer;
  v_pair_hash text; v_line_hash text; v_stage_counts jsonb;
begin
  if not coalesce((v_scope->>'ok')::boolean,false) then return v_scope; end if; v_uid:=(v_scope->'data'->>'actor_id')::uuid;
  select * into v_receipt from public.pdc_bulk_workbook_apply_receipts where receipt_id=p_receipt_id and actor_id=v_uid;
  if not found or v_receipt.stage_mapping_policy is null then return public.navision_backend_response(false,'stock_stage_receipt_not_found'); end if;
  select count(*),count(distinct rr.stock_number),encode(extensions.digest(convert_to(coalesce(string_agg(
    rr.job_card_number||'|'||rr.stock_number||'|'||coalesce(rr.backend_record_id::text,'NO-BACKEND'),';' order by rr.row_no),''),'UTF8'),'sha256'),'hex')
    into v_pairs,v_stocks,v_pair_hash from public.pdc_bulk_workbook_row_receipts rr where rr.receipt_id=p_receipt_id;
  select count(ol.operation_line_id),count(ol.operation_line_id) filter(where ol.estimated_hours is not null),
    encode(extensions.digest(convert_to(coalesce(string_agg(ol.operation_no||'|'||ol.work_key||'|'||ol.operation_fingerprint,';' order by rr.row_no,ol.operation_no),''),'UTF8'),'sha256'),'hex')
    into v_lines,v_hours,v_line_hash from public.pdc_bulk_workbook_row_receipts rr left join public.pdc_authenticated_email_operation_lines ol on ol.source_hash=rr.source_hash where rr.receipt_id=p_receipt_id;
  select coalesce(jsonb_object_agg(work_key,n order by work_key),'{}'::jsonb) into v_stage_counts from (
    select ol.work_key,count(*) n from public.pdc_bulk_workbook_row_receipts rr join public.pdc_authenticated_email_operation_lines ol on ol.source_hash=rr.source_hash where rr.receipt_id=p_receipt_id group by ol.work_key
  ) s;
  select count(*) into v_created from public.vehicles v where v.source_payload->>'bulk_preview_id'=v_receipt.preview_id::text and v.deleted_at is null and v.lifecycle_state='active';
  select count(*) into v_mismatch from public.pdc_bulk_workbook_row_receipts rr join public.vehicles v on v.id=rr.vehicle_id
   where rr.receipt_id=p_receipt_id and (v.deleted_at is not null or v.lifecycle_state<>'active'
     or public.normalize_vehicle_stock_number(v.stock_number)<>rr.stock_number
     or (select count(*) from public.pdc_authenticated_email_operation_lines ol where ol.source_hash=rr.source_hash)<>rr.operation_count);
  return public.navision_backend_response(
    v_pairs=v_receipt.accepted_count and v_stocks=v_receipt.unique_stock_count and v_created=v_receipt.vehicles_created and v_mismatch=0,
    case when v_pairs=v_receipt.accepted_count and v_stocks=v_receipt.unique_stock_count and v_created=v_receipt.vehicles_created and v_mismatch=0 then 'stock_stage_readback_complete' else 'stock_stage_readback_mismatch' end,
    jsonb_build_object('receipt_id',v_receipt.receipt_id,'preview_id',v_receipt.preview_id,
      'workbook_sha256',v_receipt.workbook_sha256,'payload_sha256',v_receipt.payload_sha256,
      'stage_mapping_policy',v_receipt.stage_mapping_policy,'accepted_pair_count',v_pairs,'unique_stock_count',v_stocks,
      'vehicles_created',v_created,'operation_line_count',v_lines,'estimated_hours_count',v_hours,
      'stage_counts',v_stage_counts,'quarantine_count',v_receipt.quarantine_count,
      'operation_quarantine_count',v_receipt.operation_quarantine_count,'pair_aggregate_sha256',v_pair_hash,
      'operation_aggregate_sha256',v_line_hash,'immutable_receipt_hash',v_receipt.receipt_hash,
      'zero_add_replay_available',true));
end;
$readback$;

revoke all on function public.authorize_pdc_bulk_stock_stage_workbook(text,text,integer,integer,text) from public,anon,authenticated,service_role;
grant execute on function public.authorize_pdc_bulk_stock_stage_workbook(text,text,integer,integer,text) to authenticated;
revoke all on function public.preview_pdc_bulk_stock_stage_workbook(text,jsonb,text,text) from public,anon,authenticated,service_role;
grant execute on function public.preview_pdc_bulk_stock_stage_workbook(text,jsonb,text,text) to authenticated;
revoke all on function public.apply_pdc_bulk_stock_stage_workbook(uuid,text,text,text) from public,anon,authenticated,service_role;
grant execute on function public.apply_pdc_bulk_stock_stage_workbook(uuid,text,text,text) to authenticated;
revoke all on function public.read_pdc_bulk_stock_stage_receipt(uuid) from public,anon,authenticated,service_role;
grant execute on function public.read_pdc_bulk_stock_stage_receipt(uuid) to authenticated;

comment on function public.authorize_pdc_bulk_stock_stage_workbook(text,text,integer,integer,text) is 'Staging-only Administrator authorization bound before Preview to workbook bytes, canonical payload bytes, counts, and PMB workshop-stage policy.';
comment on function public.preview_pdc_bulk_stock_stage_workbook(text,jsonb,text,text) is 'Stock-authoritative Preview; source JC/key numbers remain evidence only; repeated stock rows share one vehicle; ambiguity and protected lifecycle fail closed.';
comment on function public.apply_pdc_bulk_stock_stage_workbook(uuid,text,text,text) is 'Exact-bound stock/stage Apply; creates only missing current-workbook stock cards, preserves existing/manual lifecycle and location, writes no bookings/completion/notifications, and supports exact replay.';
comment on function public.read_pdc_bulk_stock_stage_receipt(uuid) is 'Administrator-only aggregate readback for stock cardinality, vehicles created, operation lines, hours and workshop-stage counts.';

insert into supabase_migrations.schema_migrations(version,name,statements)
values('128','stock_only_stage_mapped_workbook_import',array[
  'staging-only exact workbook/payload authorization',
  'source JC and key numbers ignored as identity authority; unique normalized stock is authoritative',
  'repeated source stock rows share one canonical vehicle',
  'operation descriptions and estimated hours retained with deterministic PMB workshop-stage mapping',
  'placeholder no-operation rows omitted; stock-only vehicles permitted',
  'ambiguous stock, completed/deleted lifecycle, and Navision activation conflict quarantine fail closed',
  'exact Apply/readback/replay with no bookings, completion, notification or existing-location mutation'
]);
commit;
