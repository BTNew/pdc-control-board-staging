-- Staging-only migration 124: Administrator-authorized, fail-closed JC/Stock workbook import.
-- Unresolved vehicle identities and missing work authority are retained as immutable quarantine evidence.
begin;

set local lock_timeout='5s';
set local statement_timeout='60s';
set local idle_in_transaction_session_timeout='60s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-124-bulk-workbook',0));

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd') then
    raise exception 'PDC_BULK_124_STAGING_SENTINEL_MISMATCH';
  end if;
  if to_regclass('supabase_migrations.schema_migrations') is null
     or not exists(select 1 from supabase_migrations.schema_migrations where version='123' and name='harden_ai_auditor_human_review_binding') then
    raise exception 'PDC_BULK_124_PREDECESSOR_123_IDENTITY_MISMATCH';
  end if;
  if exists(select 1 from supabase_migrations.schema_migrations where version='124' and name<>'bulk_jc_stock_workbook_contract') then
    raise exception 'PDC_BULK_124_VERSION_CONFLICT';
  end if;
  if to_regclass('public.navision_backend_records') is null
     or to_regclass('public.navision_board_activations') is null
     or to_regclass('public.pdc_authenticated_email_import_receipts') is null
     or to_regclass('public.pdc_authenticated_email_operation_lines') is null
     or to_regclass('public.vehicle_work_items') is null
     or to_regclass('public.audit_events') is null then
    raise exception 'PDC_BULK_124_DEPENDENCY_MISSING';
  end if;
end;
$guard$;

create table public.pdc_bulk_workbook_authorizations(
  authorization_id uuid primary key default gen_random_uuid(),
  actor_id uuid not null references auth.users(id) on delete restrict,
  workbook_sha256 text not null check(workbook_sha256 ~ '^[a-f0-9]{64}$'),
  expected_pair_count integer not null check(expected_pair_count between 1 and 500),
  expected_operation_count integer not null check(expected_operation_count between 1 and 50000),
  created_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  claimed_at timestamptz,
  claimed_payload_sha256 text check(claimed_payload_sha256 is null or claimed_payload_sha256 ~ '^[a-f0-9]{64}$'),
  claimed_preview_id uuid,
  status text not null default 'available' check(status in ('available','claimed','applied','expired')),
  check(expires_at>created_at and expires_at<=created_at+interval '2 hours'),
  check((status in ('available','expired') and claimed_at is null and claimed_payload_sha256 is null and claimed_preview_id is null)
     or (status in ('claimed','applied') and claimed_at is not null and claimed_payload_sha256 is not null and claimed_preview_id is not null)),
  unique(actor_id,workbook_sha256,expected_pair_count,expected_operation_count,created_at)
);

create table public.pdc_bulk_workbook_previews(
  preview_id uuid primary key default gen_random_uuid(),
  authorization_id uuid not null references public.pdc_bulk_workbook_authorizations(authorization_id) on delete restrict,
  actor_id uuid not null references auth.users(id) on delete restrict,
  workbook_sha256 text not null check(workbook_sha256 ~ '^[a-f0-9]{64}$'),
  payload_sha256 text not null check(payload_sha256 ~ '^[a-f0-9]{64}$'),
  preview_payload jsonb not null check(jsonb_typeof(preview_payload)='array'),
  row_count integer not null check(row_count between 1 and 500),
  operation_count integer not null check(operation_count between 1 and 50000),
  accepted_count integer not null check(accepted_count>=0),
  quarantine_count integer not null check(quarantine_count>=0),
  operation_quarantine_count integer not null check(operation_quarantine_count>=0),
  blocked_count integer not null default 0 check(blocked_count=0),
  created_at timestamptz not null default clock_timestamp(),
  unique(authorization_id,workbook_sha256,payload_sha256)
);

alter table public.pdc_bulk_workbook_authorizations
  add constraint pdc_bulk_workbook_authorizations_claimed_preview_fkey
  foreign key(claimed_preview_id) references public.pdc_bulk_workbook_previews(preview_id) on delete restrict;

create table public.pdc_bulk_workbook_quarantine(
  quarantine_id uuid primary key default gen_random_uuid(),
  preview_id uuid not null references public.pdc_bulk_workbook_previews(preview_id) on delete restrict,
  row_no integer not null,
  job_card_number text not null,
  stock_number text not null,
  reason_code text not null check(reason_code in (
    'missing_authoritative_work_key','multiple_current_identity_matches','partial_identity_disagreement',
    'operational_identity_conflict','operational_exact_without_current_navision','no_current_match'
  )),
  operation_quarantine_count integer not null check(operation_quarantine_count>=0),
  row_payload jsonb not null check(jsonb_typeof(row_payload)='object'),
  created_at timestamptz not null default clock_timestamp(),
  unique(preview_id,row_no)
);

create table public.pdc_bulk_workbook_apply_receipts(
  receipt_id uuid primary key default gen_random_uuid(),
  preview_id uuid not null unique references public.pdc_bulk_workbook_previews(preview_id) on delete restrict,
  authorization_id uuid not null references public.pdc_bulk_workbook_authorizations(authorization_id) on delete restrict,
  actor_id uuid not null references auth.users(id) on delete restrict,
  workbook_sha256 text not null check(workbook_sha256 ~ '^[a-f0-9]{64}$'),
  payload_sha256 text not null check(payload_sha256 ~ '^[a-f0-9]{64}$'),
  accepted_count integer not null check(accepted_count>0),
  quarantine_count integer not null check(quarantine_count>=0),
  operation_quarantine_count integer not null check(operation_quarantine_count>=0),
  operation_lines_added integer not null check(operation_lines_added>=0),
  work_items_added integer not null check(work_items_added>=0),
  applied_at timestamptz not null default clock_timestamp(),
  receipt_hash text not null unique check(receipt_hash ~ '^[a-f0-9]{64}$')
);

create table public.pdc_bulk_workbook_row_receipts(
  row_receipt_id uuid primary key default gen_random_uuid(),
  receipt_id uuid not null references public.pdc_bulk_workbook_apply_receipts(receipt_id) on delete restrict deferrable initially deferred,
  row_no integer not null,
  job_card_number text not null,
  stock_number text not null,
  classification text not null check(classification='unique_exact_current'),
  vehicle_id uuid not null references public.vehicles(id) on delete restrict,
  backend_record_id uuid not null references public.navision_backend_records(id) on delete restrict,
  source_hash text not null check(source_hash ~ '^[a-f0-9]{64}$'),
  operation_count integer not null check(operation_count>0),
  estimated_hours_count integer not null check(estimated_hours_count>=0),
  created_at timestamptz not null default clock_timestamp(),
  unique(receipt_id,row_no), unique(receipt_id,job_card_number,stock_number)
);

create or replace function public.pdc_bulk_workbook_reject_mutation()
returns trigger language plpgsql set search_path=pg_catalog,public as $immutable$
begin
  raise exception 'pdc_bulk_workbook_immutable_record' using errcode='55000';
end;
$immutable$;

create trigger pdc_bulk_workbook_previews_immutable before update or delete on public.pdc_bulk_workbook_previews for each row execute function public.pdc_bulk_workbook_reject_mutation();
create trigger pdc_bulk_workbook_quarantine_immutable before update or delete on public.pdc_bulk_workbook_quarantine for each row execute function public.pdc_bulk_workbook_reject_mutation();
create trigger pdc_bulk_workbook_apply_receipts_immutable before update or delete on public.pdc_bulk_workbook_apply_receipts for each row execute function public.pdc_bulk_workbook_reject_mutation();
create trigger pdc_bulk_workbook_row_receipts_immutable before update or delete on public.pdc_bulk_workbook_row_receipts for each row execute function public.pdc_bulk_workbook_reject_mutation();

create or replace function public.pdc_bulk_workbook_canonical_payload_sha256(p_payload jsonb)
returns text language sql immutable parallel safe set search_path=pg_catalog,public,extensions as $hash$
  select encode(extensions.digest(convert_to(coalesce(p_payload,'null'::jsonb)::text,'UTF8'),'sha256'),'hex');
$hash$;

create or replace function public.pdc_bulk_workbook_actor_scope()
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $scope$
declare v_uid uuid:=auth.uid(); v_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); v_count integer;
begin
  if not public.pdc_monitor_staging_guard() or v_uid is null or v_email='' then return public.navision_backend_response(false,'unauthorized'); end if;
  select count(*) into v_count from public.pdc_user_roles r
  join auth.users u on u.id=v_uid and lower(u.email)=v_email
  where r.auth_user_id=v_uid and lower(r.email)=v_email and r.role='administrator' and r.active and r.account_status='approved';
  if v_count<>1 then return public.navision_backend_response(false,'unauthorized'); end if;
  return public.navision_backend_response(true,'authorized',jsonb_build_object('actor_id',v_uid,'actor_email',v_email));
end;
$scope$;

create or replace function public.authorize_pdc_bulk_jc_stock_workbook(
  p_workbook_sha256 text, p_expected_pair_count integer, p_expected_operation_count integer
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions as $authorize$
declare v_scope jsonb:=public.pdc_bulk_workbook_actor_scope(); v_uid uuid; v_sha text:=lower(btrim(coalesce(p_workbook_sha256,''))); v_id uuid; v_expires timestamptz;
begin
  if not coalesce((v_scope->>'ok')::boolean,false) then return v_scope; end if;
  v_uid:=(v_scope->'data'->>'actor_id')::uuid;
  if v_sha !~ '^[a-f0-9]{64}$' or p_expected_pair_count not between 1 and 500 or p_expected_operation_count not between 1 and 50000 then
    return public.navision_backend_response(false,'invalid_authorization_binding');
  end if;
  perform pg_advisory_xact_lock(hashtextextended('pdc-bulk-workbook-authorize:'||v_uid::text,0));
  update public.pdc_bulk_workbook_authorizations set status='expired'
   where actor_id=v_uid and status='available' and expires_at<=clock_timestamp();
  v_expires:=clock_timestamp()+interval '2 hours';
  insert into public.pdc_bulk_workbook_authorizations(actor_id,workbook_sha256,expected_pair_count,expected_operation_count,expires_at)
  values(v_uid,v_sha,p_expected_pair_count,p_expected_operation_count,v_expires) returning authorization_id into v_id;
  return public.navision_backend_response(true,'authorized',jsonb_build_object('authorization_id',v_id,'workbook_sha256',v_sha,'expected_pair_count',p_expected_pair_count,'expected_operation_count',p_expected_operation_count,'expires_at',v_expires));
end;
$authorize$;

create or replace function public.preview_pdc_bulk_jc_stock_workbook(p_workbook_sha256 text,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions as $preview$
declare
  v_scope jsonb:=public.pdc_bulk_workbook_actor_scope(); v_uid uuid; v_sha text:=lower(btrim(coalesce(p_workbook_sha256,'')));
  v_payload jsonb:=coalesce(p_payload,'null'::jsonb); v_payload_sha text; v_auth public.pdc_bulk_workbook_authorizations%rowtype;
  v_preview_id uuid:=gen_random_uuid(); v_row jsonb; v_row_no integer; v_jc text; v_stock text; v_reason text;
  v_exact integer; v_stock_count integer; v_jc_count integer; v_oper_exact integer; v_oper_partial integer; v_ops integer;
  v_rows integer; v_operation_count integer; v_accepted integer:=0; v_quarantine integer:=0; v_operation_quarantine integer:=0;
begin
  if not coalesce((v_scope->>'ok')::boolean,false) then return v_scope; end if; v_uid:=(v_scope->'data'->>'actor_id')::uuid;
  if v_sha !~ '^[a-f0-9]{64}$' or jsonb_typeof(v_payload) is distinct from 'array' or jsonb_array_length(v_payload) not between 1 and 500 then
    return public.navision_backend_response(false,'invalid_workbook_payload');
  end if;
  if exists(select 1 from jsonb_array_elements(v_payload) r where jsonb_typeof(r)<>'object'
    or not (r ?& array['row_no','job_card_number','stock_number','operations'])
    or exists(select 1 from jsonb_object_keys(r) k where k<>all(array['row_no','job_card_number','stock_number','vin','customer_name','vehicle_description','registration','salesperson_reference','eta_to_kewdale','operations']))
    or jsonb_typeof(r->'row_no')<>'number' or coalesce(r->>'row_no','') !~ '^[1-9][0-9]{0,5}$'
    or length(coalesce(r->>'job_card_number','')) not between 1 and 60 or r->>'job_card_number' is distinct from btrim(r->>'job_card_number') or r->>'job_card_number' ~ '[[:cntrl:]]'
    or length(coalesce(r->>'stock_number','')) not between 1 and 80 or r->>'stock_number' is distinct from btrim(r->>'stock_number') or r->>'stock_number' ~ '[[:cntrl:]]' or not public.is_real_vehicle_stock_number(r->>'stock_number')
    or exists(select 1 from jsonb_each(r) e where e.key in ('vin','customer_name','vehicle_description','registration','salesperson_reference','eta_to_kewdale') and jsonb_typeof(e.value) not in ('string','null'))
    or length(coalesce(r->>'vin',''))>80 or coalesce(r->>'vin','') ~ '[[:cntrl:]]'
    or length(coalesce(r->>'customer_name',''))>180 or coalesce(r->>'customer_name','') ~ '[[:cntrl:]]'
    or length(coalesce(r->>'vehicle_description',''))>180 or coalesce(r->>'vehicle_description','') ~ '[[:cntrl:]]'
    or length(coalesce(r->>'registration',''))>40 or coalesce(r->>'registration','') ~ '[[:cntrl:]]'
    or length(coalesce(r->>'salesperson_reference',''))>120 or coalesce(r->>'salesperson_reference','') ~ '[[:cntrl:]]'
    or (coalesce(r->>'eta_to_kewdale','')<>'' and coalesce(r->>'eta_to_kewdale','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$')
    or jsonb_typeof(r->'operations')<>'array' or jsonb_array_length(r->'operations') not between 1 and 100
    or exists(select 1 from jsonb_array_elements(r->'operations') o where jsonb_typeof(o)<>'object'
      or (select array_agg(k order by k) from jsonb_object_keys(o) k) is distinct from array['description','estimated_hours','estimated_hours_source','operation_no','work_key']::text[]
      or coalesce(o->>'operation_no','') !~ '^OP([1-9]|[1-9][0-9]{1,2})$'
      or not ((o->'work_key')='null'::jsonb or (jsonb_typeof(o->'work_key')='string' and o->>'work_key' in ('bus4x4','tint','hoist','fitting','fabrication','electrical','tyre','PARTS')))
      or length(coalesce(o->>'description','')) not between 1 and 180 or o->>'description' is distinct from btrim(o->>'description') or o->>'description' ~ '[[:cntrl:]]'
      or jsonb_typeof(o->'estimated_hours') not in ('number','null')
      or (jsonb_typeof(o->'estimated_hours')='number' and coalesce(o->>'estimated_hours_source','') not in ('job_card','ai_estimate'))
      or (jsonb_typeof(o->'estimated_hours')='null' and o->>'estimated_hours_source' is not null)
      or (jsonb_typeof(o->'estimated_hours')='number' and ((o->>'estimated_hours')::numeric<0 or (o->>'estimated_hours')::numeric>999.99 or mod((o->>'estimated_hours')::numeric,0.01)<>0))
    ) or (select count(*) from jsonb_array_elements(r->'operations'))<>(select count(distinct o->>'operation_no') from jsonb_array_elements(r->'operations') o)
  ) then return public.navision_backend_response(false,'invalid_row_or_operation'); end if;
  if jsonb_array_length(v_payload)<>(select count(distinct (r->>'row_no')::integer) from jsonb_array_elements(v_payload) r) then return public.navision_backend_response(false,'duplicate_row'); end if;
  if jsonb_array_length(v_payload)<>(select count(distinct upper(btrim(r->>'job_card_number'))||'|'||public.normalize_vehicle_stock_number(r->>'stock_number')) from jsonb_array_elements(v_payload) r) then return public.navision_backend_response(false,'duplicate_jc_stock_pair'); end if;
  v_rows:=jsonb_array_length(v_payload);
  select sum(jsonb_array_length(r->'operations')) into v_operation_count from jsonb_array_elements(v_payload) r;
  v_payload_sha:=public.pdc_bulk_workbook_canonical_payload_sha256(v_payload);
  perform pg_advisory_xact_lock(hashtextextended('pdc-bulk-workbook-preview:'||v_uid::text,0));
  select * into v_auth from public.pdc_bulk_workbook_authorizations a where a.actor_id=v_uid and a.workbook_sha256=v_sha and a.expected_pair_count=v_rows and a.expected_operation_count=v_operation_count and a.status='available' and a.expires_at>clock_timestamp() order by a.created_at desc limit 1 for update;
  if not found then
    select * into v_auth from public.pdc_bulk_workbook_authorizations a where a.actor_id=v_uid and a.workbook_sha256=v_sha and a.claimed_payload_sha256=v_payload_sha and a.status in ('claimed','applied') order by a.created_at desc limit 1;
    if not found then return public.navision_backend_response(false,'authorization_not_available_or_count_mismatch'); end if;
    return public.navision_backend_response(true,'exact_preview_replay',jsonb_build_object('preview_id',v_auth.claimed_preview_id,'authorization_id',v_auth.authorization_id,'workbook_sha256',v_sha,'payload_sha256',v_payload_sha));
  end if;
  create temporary table pg_temp.pdc_bulk_classification(row_no integer primary key,jc text,stock text,reason text,op_quarantine integer,row_payload jsonb) on commit drop;
  for v_row in select value from jsonb_array_elements(v_payload) loop
    v_row_no:=(v_row->>'row_no')::integer; v_jc:=upper(btrim(v_row->>'job_card_number')); v_stock:=public.normalize_vehicle_stock_number(v_row->>'stock_number'); v_ops:=jsonb_array_length(v_row->'operations');
    select count(*) into v_exact from public.navision_backend_records r where r.source_system='microsoft_navision' and r.record_status='current' and r.is_current and public.normalize_vehicle_stock_number(r.normalized_data->>'batch')=v_stock and upper(btrim(coalesce(r.normalized_data->>'jobCardNumber','')))=v_jc;
    select count(*) into v_stock_count from public.navision_backend_records r where r.source_system='microsoft_navision' and r.record_status='current' and r.is_current and public.normalize_vehicle_stock_number(r.normalized_data->>'batch')=v_stock;
    select count(*) into v_jc_count from public.navision_backend_records r where r.source_system='microsoft_navision' and r.record_status='current' and r.is_current and upper(btrim(coalesce(r.normalized_data->>'jobCardNumber','')))=v_jc;
    select count(*) into v_oper_exact from public.vehicles v where v.deleted_at is null and v.lifecycle_state='active' and public.normalize_vehicle_stock_number(v.stock_number)=v_stock and upper(btrim(coalesce(v.job_card_number,'')))=v_jc;
    select count(*) into v_oper_partial from public.vehicles v where v.deleted_at is null and v.lifecycle_state='active' and ((public.normalize_vehicle_stock_number(v.stock_number)=v_stock and upper(btrim(coalesce(v.job_card_number,'')))<>v_jc) or (upper(btrim(coalesce(v.job_card_number,'')))=v_jc and public.normalize_vehicle_stock_number(v.stock_number)<>v_stock));
    v_reason:=null;
    if exists(select 1 from jsonb_array_elements(v_row->'operations') o where o->'work_key'='null'::jsonb) then v_reason:='missing_authoritative_work_key';
    elsif v_exact=1 and v_stock_count=1 and v_jc_count=1 and (v_oper_partial>0 or v_oper_exact>1) then v_reason:='operational_identity_conflict';
    elsif v_exact=1 and v_stock_count=1 and v_jc_count=1 then v_accepted:=v_accepted+1;
    elsif v_exact>1 or v_stock_count>1 or v_jc_count>1 then v_reason:='multiple_current_identity_matches';
    elsif v_stock_count>0 or v_jc_count>0 then v_reason:='partial_identity_disagreement';
    elsif v_oper_partial>0 then v_reason:='operational_identity_conflict';
    elsif v_oper_exact=1 then v_reason:='operational_exact_without_current_navision';
    else v_reason:='no_current_match'; end if;
    if v_reason is not null then v_quarantine:=v_quarantine+1; v_operation_quarantine:=v_operation_quarantine+v_ops; end if;
    insert into pg_temp.pdc_bulk_classification values(v_row_no,v_jc,v_stock,v_reason,case when v_reason is null then 0 else v_ops end,v_row);
  end loop;
  insert into public.pdc_bulk_workbook_previews(preview_id,authorization_id,actor_id,workbook_sha256,payload_sha256,preview_payload,row_count,operation_count,accepted_count,quarantine_count,operation_quarantine_count,blocked_count)
  values(v_preview_id,v_auth.authorization_id,v_uid,v_sha,v_payload_sha,v_payload,v_rows,v_operation_count,v_accepted,v_quarantine,v_operation_quarantine,0);
  insert into public.pdc_bulk_workbook_quarantine(preview_id,row_no,job_card_number,stock_number,reason_code,operation_quarantine_count,row_payload)
  select v_preview_id,row_no,jc,stock,reason,op_quarantine,row_payload from pg_temp.pdc_bulk_classification where reason is not null order by row_no;
  update public.pdc_bulk_workbook_authorizations set claimed_at=clock_timestamp(),claimed_payload_sha256=v_payload_sha,claimed_preview_id=v_preview_id,status='claimed' where authorization_id=v_auth.authorization_id and status='available';
  if not found then raise exception 'pdc_bulk_workbook_authorization_claim_race' using errcode='40001'; end if;
  return public.navision_backend_response(true,'preview_ready',jsonb_build_object('preview_id',v_preview_id,'authorization_id',v_auth.authorization_id,'workbook_sha256',v_sha,'payload_sha256',v_payload_sha,'row_count',v_rows,'operation_count',v_operation_count,'accepted_count',v_accepted,'quarantine_count',v_quarantine,'operation_quarantine_count',v_operation_quarantine,'blocked_count',0,'applyable',v_accepted>0));
end;
$preview$;

create or replace function public.apply_pdc_bulk_jc_stock_workbook(p_preview_id uuid,p_workbook_sha256 text,p_payload_sha256 text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions as $apply$
declare
  v_scope jsonb:=public.pdc_bulk_workbook_actor_scope(); v_uid uuid; v_email text; v_preview public.pdc_bulk_workbook_previews%rowtype; v_auth public.pdc_bulk_workbook_authorizations%rowtype; v_existing public.pdc_bulk_workbook_apply_receipts%rowtype;
  v_receipt_id uuid:=gen_random_uuid(); v_receipt_hash text; v_row jsonb; v_op jsonb; v_row_no integer; v_jc text; v_stock text; v_backend uuid; v_vehicle uuid; v_source_hash text; v_source_uid text; v_import_receipt uuid; v_line uuid; v_before public.vehicle_work_items%rowtype; v_after public.vehicle_work_items%rowtype;
  v_lines_added integer:=0; v_work_added integer:=0; v_row_lines integer; v_row_hours integer;
begin
  if not coalesce((v_scope->>'ok')::boolean,false) then return v_scope; end if; v_uid:=(v_scope->'data'->>'actor_id')::uuid; v_email:=v_scope->'data'->>'actor_email';
  if p_preview_id is null or lower(btrim(coalesce(p_workbook_sha256,''))) !~ '^[a-f0-9]{64}$' or lower(btrim(coalesce(p_payload_sha256,''))) !~ '^[a-f0-9]{64}$' then return public.navision_backend_response(false,'invalid_apply_binding'); end if;
  perform pg_advisory_xact_lock(hashtextextended('pdc-bulk-workbook-apply:'||p_preview_id::text,0));
  select * into v_preview from public.pdc_bulk_workbook_previews where preview_id=p_preview_id and actor_id=v_uid for share;
  if not found then return public.navision_backend_response(false,'preview_not_found'); end if;
  select * into v_auth from public.pdc_bulk_workbook_authorizations where authorization_id=v_preview.authorization_id and actor_id=v_uid for update;
  if v_auth.claimed_preview_id<>v_preview.preview_id or v_auth.workbook_sha256<>lower(btrim(p_workbook_sha256)) or v_auth.claimed_payload_sha256<>lower(btrim(p_payload_sha256)) or v_preview.workbook_sha256<>lower(btrim(p_workbook_sha256)) or v_preview.payload_sha256<>lower(btrim(p_payload_sha256)) or public.pdc_bulk_workbook_canonical_payload_sha256(v_preview.preview_payload)<>v_preview.payload_sha256 then return public.navision_backend_response(false,'apply_binding_mismatch'); end if;
  -- Exact replay is deliberately before every operational INSERT/UPDATE.
  select * into v_existing from public.pdc_bulk_workbook_apply_receipts where preview_id=p_preview_id;
  if found then return public.navision_backend_response(true,'exact_replay',jsonb_build_object('receipt_id',v_existing.receipt_id,'preview_id',p_preview_id,'workbook_sha256',v_existing.workbook_sha256,'payload_sha256',v_existing.payload_sha256,'operation_lines_added',0,'work_items_added',0,'zero_add_replay',true)); end if;
  if v_preview.accepted_count=0 then return public.navision_backend_response(false,'zero_accepted_preview'); end if;
  if v_auth.status<>'claimed' or v_auth.expires_at<=clock_timestamp() or v_preview.blocked_count<>0 or v_preview.row_count<>v_auth.expected_pair_count or v_preview.operation_count<>v_auth.expected_operation_count then return public.navision_backend_response(false,'authorization_or_preview_not_applyable'); end if;
  for v_row in select value from jsonb_array_elements(v_preview.preview_payload) r where not exists(select 1 from public.pdc_bulk_workbook_quarantine q where q.preview_id=p_preview_id and q.row_no=(r.value->>'row_no')::integer) order by (value->>'row_no')::integer loop
    v_row_no:=(v_row->>'row_no')::integer; v_jc:=upper(btrim(v_row->>'job_card_number')); v_stock:=public.normalize_vehicle_stock_number(v_row->>'stock_number');
    if (select count(*) from public.navision_backend_records r where r.source_system='microsoft_navision' and r.record_status='current' and r.is_current and public.normalize_vehicle_stock_number(r.normalized_data->>'batch')=v_stock)<>1
       or (select count(*) from public.navision_backend_records r where r.source_system='microsoft_navision' and r.record_status='current' and r.is_current and upper(btrim(coalesce(r.normalized_data->>'jobCardNumber','')))=v_jc)<>1
       or (select count(*) from public.vehicles v where v.deleted_at is null and v.lifecycle_state='active' and public.normalize_vehicle_stock_number(v.stock_number)=v_stock and upper(btrim(coalesce(v.job_card_number,'')))=v_jc)>1
       or exists(select 1 from public.vehicles v where v.deleted_at is null and v.lifecycle_state='active' and ((public.normalize_vehicle_stock_number(v.stock_number)=v_stock and upper(btrim(coalesce(v.job_card_number,'')))<>v_jc) or (upper(btrim(coalesce(v.job_card_number,'')))=v_jc and public.normalize_vehicle_stock_number(v.stock_number)<>v_stock)))
    then raise exception 'pdc_bulk_workbook_identity_no_longer_unique row %',v_row_no using errcode='40001'; end if;
    select r.id into strict v_backend from public.navision_backend_records r where r.source_system='microsoft_navision' and r.record_status='current' and r.is_current and public.normalize_vehicle_stock_number(r.normalized_data->>'batch')=v_stock and upper(btrim(coalesce(r.normalized_data->>'jobCardNumber','')))=v_jc;
    insert into public.navision_board_activations(backend_record_id,activation_source,activated_stock_number,activated_by,activated_by_email,active)
    values(v_backend,'approved_key_list',v_stock,v_uid,v_email,true)
    on conflict(backend_record_id) do update set active=true,updated_at=clock_timestamp() where not public.navision_board_activations.active and public.navision_board_activations.completed_at is null;
    select canonical_vehicle_id into v_vehicle from public.navision_board_activations where backend_record_id=v_backend and active and completed_at is null;
    if v_vehicle is null then raise exception 'pdc_bulk_workbook_navision_activation_failed row %',v_row_no using errcode='40001'; end if;
    v_source_hash:=encode(extensions.digest(convert_to(v_preview.payload_sha256||':'||v_row_no::text,'UTF8'),'sha256'),'hex'); v_source_uid:='bulk-workbook:'||p_preview_id::text||':'||v_row_no::text;
    insert into public.pdc_authenticated_email_import_receipts(actor_id,idempotency_key,request_hash,source_hash,evidence_hash,source_uid,sender_address,source_received_at,stock_number,vin,backend_record_id,vehicle_id,identity_source,required_work,response)
    values(v_uid,v_source_uid,v_preview.payload_sha256,v_source_hash,v_source_hash,v_source_uid,v_email,v_preview.created_at,v_stock,null,v_backend,v_vehicle,'navision_exact',(select jsonb_agg(k order by k) from (select distinct o->>'work_key' k from jsonb_array_elements(v_row->'operations') o) x),jsonb_build_object('source','pdc_bulk_workbook_124','preview_id',p_preview_id,'row_no',v_row_no,'booking_created',false,'completed_work_reopened',false))
    on conflict(source_hash) do nothing returning receipt_id into v_import_receipt;
    if v_import_receipt is null then select receipt_id into strict v_import_receipt from public.pdc_authenticated_email_import_receipts where source_hash=v_source_hash and actor_id=v_uid and vehicle_id=v_vehicle; end if;
    for v_op in select value from jsonb_array_elements(v_row->'operations') loop
      if exists(select 1 from public.pdc_authenticated_email_operation_lines ol where ol.source_hash=v_source_hash and ol.operation_no=v_op->>'operation_no' and (ol.vehicle_id<>v_vehicle or ol.work_key<>v_op->>'work_key' or ol.description<>v_op->>'description' or ol.estimated_hours is distinct from case when jsonb_typeof(v_op->'estimated_hours')='number' then (v_op->>'estimated_hours')::numeric else null end or ol.estimated_hours_source is distinct from v_op->>'estimated_hours_source')) then raise exception 'pdc_bulk_workbook_operation_identity_conflict row % operation %',v_row_no,v_op->>'operation_no' using errcode='40001'; end if;
      insert into public.pdc_authenticated_email_operation_lines(import_receipt_id,vehicle_id,source_hash,source_uid,operation_no,work_key,description,estimated_hours,estimated_hours_source,operation_fingerprint)
      values(v_import_receipt,v_vehicle,v_source_hash,v_source_uid,v_op->>'operation_no',v_op->>'work_key',v_op->>'description',case when jsonb_typeof(v_op->'estimated_hours')='number' then (v_op->>'estimated_hours')::numeric else null end,v_op->>'estimated_hours_source',encode(extensions.digest(jsonb_build_object('source_hash',v_source_hash,'operation_no',v_op->>'operation_no','work_key',v_op->>'work_key','description',v_op->>'description')::text,'sha256'),'hex'))
      on conflict(source_hash,operation_no) do nothing returning operation_line_id into v_line;
      if v_line is not null then v_lines_added:=v_lines_added+1; insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata) values('insert','pdc_authenticated_email_operation_lines',v_line,v_vehicle,v_uid,v_email,null,jsonb_build_object('operation_no',v_op->>'operation_no','work_key',v_op->>'work_key','description',v_op->>'description','estimated_hours',v_op->'estimated_hours','estimated_hours_source',v_op->>'estimated_hours_source'),jsonb_build_object('source','pdc_bulk_workbook_124','preview_id',p_preview_id,'row_no',v_row_no,'no_booking',true,'completed_work_reopened',false)); end if;
      v_line:=null; v_before:=null; v_after:=null;
      select * into v_before from public.vehicle_work_items where vehicle_id=v_vehicle and work_key=v_op->>'work_key' for update;
      insert into public.vehicle_work_items(vehicle_id,work_key,required,completed,completed_by,completed_at,notes,updated_at)
      values(v_vehicle,v_op->>'work_key',true,false,null,null,null,clock_timestamp())
      on conflict(vehicle_id,work_key) do update set required=true,updated_at=clock_timestamp() where not public.vehicle_work_items.completed and not public.vehicle_work_items.required returning * into v_after;
      if v_after.id is not null and (v_before.id is null or (not v_before.completed and not v_before.required)) then v_work_added:=v_work_added+1; insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata) values(case when v_before.id is null then 'insert'::public.audit_action else 'update'::public.audit_action end,'vehicle_work_items',v_after.id,v_vehicle,v_uid,v_email,case when v_before.id is null then null else to_jsonb(v_before) end,to_jsonb(v_after),jsonb_build_object('source','pdc_bulk_workbook_124','preview_id',p_preview_id,'row_no',v_row_no,'required_work',v_op->>'work_key','no_booking',true,'completed_work_reopened',false)); end if;
    end loop;
    select count(*),count(*) filter(where estimated_hours is not null) into v_row_lines,v_row_hours from public.pdc_authenticated_email_operation_lines where source_hash=v_source_hash;
    if v_row_lines<>jsonb_array_length(v_row->'operations') then raise exception 'pdc_bulk_workbook_operation_readback_mismatch row %',v_row_no using errcode='40001'; end if;
    insert into public.pdc_bulk_workbook_row_receipts(receipt_id,row_no,job_card_number,stock_number,classification,vehicle_id,backend_record_id,source_hash,operation_count,estimated_hours_count)
    values(v_receipt_id,v_row_no,v_jc,v_stock,'unique_exact_current',v_vehicle,v_backend,v_source_hash,v_row_lines,v_row_hours);
  end loop;
  v_receipt_hash:=encode(extensions.digest(convert_to(jsonb_build_object('receipt_id',v_receipt_id,'preview_id',p_preview_id,'authorization_id',v_auth.authorization_id,'workbook_sha256',v_preview.workbook_sha256,'payload_sha256',v_preview.payload_sha256,'accepted_count',v_preview.accepted_count,'quarantine_count',v_preview.quarantine_count,'operation_quarantine_count',v_preview.operation_quarantine_count,'operation_lines_added',v_lines_added,'work_items_added',v_work_added)::text,'UTF8'),'sha256'),'hex');
  insert into public.pdc_bulk_workbook_apply_receipts(receipt_id,preview_id,authorization_id,actor_id,workbook_sha256,payload_sha256,accepted_count,quarantine_count,operation_quarantine_count,operation_lines_added,work_items_added,receipt_hash)
  values(v_receipt_id,p_preview_id,v_auth.authorization_id,v_uid,v_preview.workbook_sha256,v_preview.payload_sha256,v_preview.accepted_count,v_preview.quarantine_count,v_preview.operation_quarantine_count,v_lines_added,v_work_added,v_receipt_hash);
  update public.pdc_bulk_workbook_authorizations set status='applied' where authorization_id=v_auth.authorization_id and status='claimed';
  return public.navision_backend_response(true,'applied',jsonb_build_object('receipt_id',v_receipt_id,'preview_id',p_preview_id,'accepted_count',v_preview.accepted_count,'quarantine_count',v_preview.quarantine_count,'operation_quarantine_count',v_preview.operation_quarantine_count,'operation_lines_added',v_lines_added,'work_items_added',v_work_added,'receipt_hash',v_receipt_hash,'booking_created',false,'completed_work_reopened',false,'parts_completion_created',false,'zero_add_replay',false));
end;
$apply$;

create or replace function public.read_pdc_bulk_jc_stock_workbook_receipt(p_receipt_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,extensions as $readback$
declare v_scope jsonb:=public.pdc_bulk_workbook_actor_scope(); v_uid uuid; v_receipt public.pdc_bulk_workbook_apply_receipts%rowtype; v_pairs integer; v_lines integer; v_hours integer; v_pair_hash text; v_line_hash text; v_mismatch integer;
begin
  if not coalesce((v_scope->>'ok')::boolean,false) then return v_scope; end if; v_uid:=(v_scope->'data'->>'actor_id')::uuid;
  select * into v_receipt from public.pdc_bulk_workbook_apply_receipts where receipt_id=p_receipt_id and actor_id=v_uid; if not found then return public.navision_backend_response(false,'receipt_not_found'); end if;
  select count(*),encode(extensions.digest(convert_to(coalesce(string_agg(rr.job_card_number||'|'||rr.stock_number||'|'||rr.backend_record_id::text,';' order by rr.row_no),''),'UTF8'),'sha256'),'hex') into v_pairs,v_pair_hash from public.pdc_bulk_workbook_row_receipts rr where rr.receipt_id=p_receipt_id;
  select count(ol.operation_line_id),count(ol.operation_line_id) filter(where ol.estimated_hours is not null),encode(extensions.digest(convert_to(coalesce(string_agg(ol.operation_no||'|'||ol.work_key||'|'||ol.operation_fingerprint,';' order by rr.row_no,ol.operation_no),''),'UTF8'),'sha256'),'hex') into v_lines,v_hours,v_line_hash from public.pdc_bulk_workbook_row_receipts rr left join public.pdc_authenticated_email_operation_lines ol on ol.source_hash=rr.source_hash where rr.receipt_id=p_receipt_id;
  select count(*) into v_mismatch from public.pdc_bulk_workbook_row_receipts rr join public.vehicles v on v.id=rr.vehicle_id where rr.receipt_id=p_receipt_id and (upper(btrim(coalesce(v.job_card_number,'')))<>rr.job_card_number or public.normalize_vehicle_stock_number(v.stock_number)<>rr.stock_number or (select count(*) from public.pdc_authenticated_email_operation_lines ol where ol.source_hash=rr.source_hash)<>rr.operation_count);
  return public.navision_backend_response(v_pairs=v_receipt.accepted_count and v_mismatch=0,case when v_pairs=v_receipt.accepted_count and v_mismatch=0 then 'readback_complete' else 'readback_mismatch' end,jsonb_build_object('receipt_id',v_receipt.receipt_id,'preview_id',v_receipt.preview_id,'workbook_sha256',v_receipt.workbook_sha256,'payload_sha256',v_receipt.payload_sha256,'accepted_pair_count',v_pairs,'operation_line_count',v_lines,'estimated_hours_count',v_hours,'quarantine_count',v_receipt.quarantine_count,'operation_quarantine_count',v_receipt.operation_quarantine_count,'pair_aggregate_sha256',v_pair_hash,'operation_aggregate_sha256',v_line_hash,'immutable_receipt_hash',v_receipt.receipt_hash,'zero_add_replay_available',true));
end;
$readback$;

alter table public.pdc_bulk_workbook_authorizations enable row level security;
alter table public.pdc_bulk_workbook_previews enable row level security;
alter table public.pdc_bulk_workbook_quarantine enable row level security;
alter table public.pdc_bulk_workbook_apply_receipts enable row level security;
alter table public.pdc_bulk_workbook_row_receipts enable row level security;
revoke all on table public.pdc_bulk_workbook_authorizations,public.pdc_bulk_workbook_previews,public.pdc_bulk_workbook_quarantine,public.pdc_bulk_workbook_apply_receipts,public.pdc_bulk_workbook_row_receipts from public,anon,authenticated;
revoke all on function public.pdc_bulk_workbook_actor_scope() from public,anon,authenticated;
revoke all on function public.pdc_bulk_workbook_canonical_payload_sha256(jsonb) from public,anon,authenticated;
revoke all on function public.authorize_pdc_bulk_jc_stock_workbook(text,integer,integer) from public,anon,authenticated;
grant execute on function public.authorize_pdc_bulk_jc_stock_workbook(text,integer,integer) to authenticated;
revoke all on function public.preview_pdc_bulk_jc_stock_workbook(text,jsonb) from public,anon,authenticated;
grant execute on function public.preview_pdc_bulk_jc_stock_workbook(text,jsonb) to authenticated;
revoke all on function public.apply_pdc_bulk_jc_stock_workbook(uuid,text,text) from public,anon,authenticated;
grant execute on function public.apply_pdc_bulk_jc_stock_workbook(uuid,text,text) to authenticated;
revoke all on function public.read_pdc_bulk_jc_stock_workbook_receipt(uuid) from public,anon,authenticated;
grant execute on function public.read_pdc_bulk_jc_stock_workbook_receipt(uuid) to authenticated;

insert into supabase_migrations.schema_migrations(version,name,statements)
values('124','bulk_jc_stock_workbook_contract',array['staging-only Administrator-authorized exact workbook preview/apply; unresolved identity and null work authority quarantined; zero-accepted Apply denied; unique-current Navision activation; direct bounded operation/work-item writes preserving completion; aggregate readback']);
comment on function public.authorize_pdc_bulk_jc_stock_workbook(text,integer,integer) is 'Approved active Administrator authorization bound to workbook SHA and expected pair/operation counts; expires within two hours.';
comment on function public.preview_pdc_bulk_jc_stock_workbook(text,jsonb) is 'Fail-closed Preview retaining immutable vehicle/work-authority quarantine; quarantine is nonblocking and zero accepted is valid but not Apply-able.';
comment on function public.apply_pdc_bulk_jc_stock_workbook(uuid,text,text) is 'Exact-bound Apply for accepted unique-current Navision rows only; exact replay precedes DML; never creates unmatched vehicles, bookings, completion, or Parts completion.';
comment on function public.read_pdc_bulk_jc_stock_workbook_receipt(uuid) is 'Administrator-only aggregate receipt/readback without raw row payloads.';
commit;
