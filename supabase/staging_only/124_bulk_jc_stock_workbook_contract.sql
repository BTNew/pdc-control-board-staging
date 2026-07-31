-- Staging-only migration 124: one-time retained bulk JC/Stock workbook contract.
-- Preview and Apply are exact-workbook/exact-payload bound. This migration never
-- grants Importer, Administrator or service-role access and never reads a mailbox.
begin;

do $guard$
declare v_monitor_count integer;
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
     or to_regprocedure('public.import_pdc_authenticated_email_operations_with_hours(text,text,jsonb)') is null
     or to_regclass('public.pdc_monitor_vehicle_identity_readers') is null
     or to_regclass('public.pdc_monitor_stage_activation_writers') is null then
    raise exception 'PDC_BULK_124_DEPENDENCY_MISSING';
  end if;
  select count(*) into v_monitor_count
  from public.pdc_monitor_vehicle_identity_readers i
  join public.pdc_monitor_stage_activation_writers w on w.user_id=i.user_id
  join public.pdc_user_roles r on r.auth_user_id=i.user_id
  join auth.users u on u.id=i.user_id and lower(u.email)=lower(r.email)
  where i.active and i.revoked_at is null and w.active and w.revoked_at is null
    and r.role='viewer' and r.active and r.account_status='approved';
  if v_monitor_count<>1 then
    raise exception 'PDC_BULK_124_EXACT_VIEWER_IDENTITY_COUNT_MISMATCH';
  end if;
end;
$guard$;

create table public.pdc_bulk_workbook_authorizations (
  authorization_id uuid primary key default gen_random_uuid(),
  actor_id uuid not null references auth.users(id) on delete restrict,
  authorization_reference text not null unique,
  authorization_scope text not null check(authorization_scope='retained_bulk_jc_stock_workbook_31_july'),
  allow_no_current_navision_override boolean not null,
  expected_quarantine_count integer not null check(expected_quarantine_count>=0),
  created_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  claimed_at timestamptz,
  claimed_workbook_sha256 text check(claimed_workbook_sha256 is null or claimed_workbook_sha256 ~ '^[a-f0-9]{64}$'),
  claimed_payload_sha256 text check(claimed_payload_sha256 is null or claimed_payload_sha256 ~ '^[a-f0-9]{64}$'),
  claimed_preview_id uuid,
  status text not null default 'available' check(status in ('available','claimed','applied','expired')),
  check(expires_at>created_at),
  check((claimed_at is null and claimed_workbook_sha256 is null and claimed_payload_sha256 is null and claimed_preview_id is null and status in ('available','expired'))
     or (claimed_at is not null and claimed_workbook_sha256 is not null and claimed_payload_sha256 is not null and claimed_preview_id is not null and status in ('claimed','applied')))
);

create table public.pdc_bulk_workbook_previews (
  preview_id uuid primary key default gen_random_uuid(),
  authorization_id uuid not null references public.pdc_bulk_workbook_authorizations(authorization_id) on delete restrict,
  actor_id uuid not null references auth.users(id) on delete restrict,
  workbook_sha256 text not null check(workbook_sha256 ~ '^[a-f0-9]{64}$'),
  payload_sha256 text not null check(payload_sha256 ~ '^[a-f0-9]{64}$'),
  preview_payload jsonb not null check(jsonb_typeof(preview_payload)='array'),
  row_count integer not null check(row_count between 1 and 500),
  accepted_count integer not null check(accepted_count>=0),
  quarantine_count integer not null check(quarantine_count>=0),
  blocked_count integer not null check(blocked_count>=0),
  created_at timestamptz not null default clock_timestamp(),
  unique(authorization_id,workbook_sha256,payload_sha256)
);

alter table public.pdc_bulk_workbook_authorizations
  add constraint pdc_bulk_workbook_authorizations_claimed_preview_fkey
  foreign key(claimed_preview_id) references public.pdc_bulk_workbook_previews(preview_id) on delete restrict;

create table public.pdc_bulk_workbook_quarantine (
  quarantine_id uuid primary key default gen_random_uuid(),
  preview_id uuid not null references public.pdc_bulk_workbook_previews(preview_id) on delete restrict,
  row_no integer not null,
  job_card_number text not null,
  stock_number text not null,
  reason_code text not null,
  manager_override_selected boolean not null default false,
  row_payload jsonb not null check(jsonb_typeof(row_payload)='object'),
  created_at timestamptz not null default clock_timestamp(),
  unique(preview_id,row_no)
);

create table public.pdc_bulk_workbook_apply_receipts (
  receipt_id uuid primary key default gen_random_uuid(),
  preview_id uuid not null unique references public.pdc_bulk_workbook_previews(preview_id) on delete restrict,
  authorization_id uuid not null references public.pdc_bulk_workbook_authorizations(authorization_id) on delete restrict,
  actor_id uuid not null references auth.users(id) on delete restrict,
  workbook_sha256 text not null check(workbook_sha256 ~ '^[a-f0-9]{64}$'),
  payload_sha256 text not null check(payload_sha256 ~ '^[a-f0-9]{64}$'),
  row_count integer not null,
  quarantine_count integer not null,
  vehicles_added integer not null,
  operation_lines_added integer not null,
  estimated_hours_added integer not null,
  applied_at timestamptz not null default clock_timestamp(),
  receipt_hash text not null unique check(receipt_hash ~ '^[a-f0-9]{64}$')
);

create table public.pdc_bulk_workbook_row_receipts (
  row_receipt_id uuid primary key default gen_random_uuid(),
  receipt_id uuid not null references public.pdc_bulk_workbook_apply_receipts(receipt_id) on delete restrict deferrable initially deferred,
  row_no integer not null,
  job_card_number text not null,
  stock_number text not null,
  classification text not null check(classification in ('navision_exact','manager_override_no_current_navision_match')),
  vehicle_id uuid not null references public.vehicles(id) on delete restrict,
  backend_record_id uuid references public.navision_backend_records(id) on delete restrict,
  source_hash text not null check(source_hash ~ '^[a-f0-9]{64}$'),
  operation_count integer not null check(operation_count>=0),
  estimated_hours_count integer not null check(estimated_hours_count>=0),
  created_at timestamptz not null default clock_timestamp(),
  unique(receipt_id,row_no),
  unique(receipt_id,job_card_number,stock_number)
);

create or replace function public.pdc_bulk_workbook_reject_mutation()
returns trigger language plpgsql set search_path=pg_catalog,public as $immutable$
begin
  raise exception 'pdc_bulk_workbook_immutable_record' using errcode='55000';
end;
$immutable$;

create trigger pdc_bulk_workbook_previews_immutable before update or delete on public.pdc_bulk_workbook_previews
for each row execute function public.pdc_bulk_workbook_reject_mutation();
create trigger pdc_bulk_workbook_quarantine_immutable before update or delete on public.pdc_bulk_workbook_quarantine
for each row execute function public.pdc_bulk_workbook_reject_mutation();
create trigger pdc_bulk_workbook_apply_receipts_immutable before update or delete on public.pdc_bulk_workbook_apply_receipts
for each row execute function public.pdc_bulk_workbook_reject_mutation();
create trigger pdc_bulk_workbook_row_receipts_immutable before update or delete on public.pdc_bulk_workbook_row_receipts
for each row execute function public.pdc_bulk_workbook_reject_mutation();

create or replace function public.pdc_bulk_workbook_canonical_payload_sha256(p_payload jsonb)
returns text language sql immutable parallel safe
set search_path=pg_catalog,public,extensions
as $hash$
  select encode(extensions.digest(convert_to(coalesce(p_payload,'null'::jsonb)::text,'UTF8'),'sha256'),'hex');
$hash$;

create or replace function public.pdc_bulk_workbook_actor_scope()
returns jsonb language plpgsql stable security definer
set search_path=pg_catalog,public
as $scope$
declare
  v_uid uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_count integer;
begin
  if not public.pdc_monitor_staging_guard() or v_uid is null or v_email='' then
    return public.navision_backend_response(false,'unauthorized');
  end if;
  select count(*) into v_count
  from public.pdc_user_roles r
  join public.pdc_monitor_vehicle_identity_readers i on i.user_id=v_uid and i.active and i.revoked_at is null
  join public.pdc_monitor_stage_activation_writers w on w.user_id=v_uid and w.active and w.revoked_at is null
  where r.auth_user_id=v_uid and lower(r.email)=v_email and r.role='viewer'
    and r.active and r.account_status='approved';
  if v_count<>1 then return public.navision_backend_response(false,'unauthorized'); end if;
  return public.navision_backend_response(true,'authorized',jsonb_build_object('actor_id',v_uid,'actor_email',v_email));
end;
$scope$;

-- Build-time draft used only to force PostgreSQL to type-check the validation branch.
-- It is never granted and is dropped before the callable final Preview is created.
create or replace function public.pdc_bulk_workbook_preview_validation_draft(
  p_workbook_sha256 text,
  p_payload jsonb
)
returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,extensions
as $preview$
declare
  v_scope jsonb:=public.pdc_bulk_workbook_actor_scope();
  v_uid uuid;
  v_workbook_sha256 text:=lower(btrim(coalesce(p_workbook_sha256,'')));
  v_payload jsonb:=coalesce(p_payload,'null'::jsonb);
  v_payload_sha256 text;
  v_auth public.pdc_bulk_workbook_authorizations%rowtype;
  v_preview_id uuid:=gen_random_uuid();
  v_row jsonb;
  v_ops jsonb;
  v_row_no integer;
  v_jc text;
  v_stock text;
  v_resolution text;
  v_exact_count integer;
  v_stock_count integer;
  v_jc_count integer;
  v_operational_exact_count integer;
  v_operational_partial_count integer;
  v_classification text;
  v_reason text;
  v_accepted integer:=0;
  v_quarantine integer:=0;
  v_blocked integer:=0;
begin
  if not coalesce((v_scope->>'ok')::boolean,false) then return v_scope; end if;
  v_uid:=(v_scope->'data'->>'actor_id')::uuid;
  if v_workbook_sha256 !~ '^[a-f0-9]{64}$'
     or jsonb_typeof(v_payload) is distinct from 'array'
     or jsonb_array_length(v_payload) not between 1 and 500 then
    return public.navision_backend_response(false,'invalid_workbook_payload');
  end if;
  if exists(
    select 1 from jsonb_array_elements(v_payload) r
    where jsonb_typeof(r)<>'object'
       or not (r ?& array['row_no','job_card_number','stock_number','operations'])
       or exists(select 1 from jsonb_object_keys(r) k where k<>all(array['row_no','job_card_number','stock_number','vin','customer_name','vehicle_description','registration','salesperson_reference','eta_to_kewdale','resolution','operations']))
       or jsonb_typeof(r->'row_no')<>'number'
       or (r->>'row_no') !~ '^[1-9][0-9]{0,5}$'
       or length(coalesce(r->>'job_card_number','')) not between 1 and 60
       or r->>'job_card_number' is distinct from btrim(r->>'job_card_number')
       or r->>'job_card_number' ~ '[[:cntrl:]]'
       or length(coalesce(r->>'stock_number','')) not between 1 and 80
       or r->>'stock_number' is distinct from btrim(r->>'stock_number')
       or r->>'stock_number' ~ '[[:cntrl:]]'
       or not public.is_real_vehicle_stock_number(r->>'stock_number')
       or exists(select 1 from jsonb_each(r) e where e.key in ('vin','customer_name','vehicle_description','registration','salesperson_reference','eta_to_kewdale','resolution') and jsonb_typeof(e.value) not in ('string','null'))
      or length(coalesce(r->>'vin',''))>80 or coalesce(r->>'vin','') ~ '[[:cntrl:]]'
      or length(coalesce(r->>'customer_name',''))>180 or coalesce(r->>'customer_name','') ~ '[[:cntrl:]]'
      or length(coalesce(r->>'vehicle_description',''))>180 or coalesce(r->>'vehicle_description','') ~ '[[:cntrl:]]'
      or length(coalesce(r->>'registration',''))>40 or coalesce(r->>'registration','') ~ '[[:cntrl:]]'
      or length(coalesce(r->>'salesperson_reference',''))>120 or coalesce(r->>'salesperson_reference','') ~ '[[:cntrl:]]'
      or (coalesce(r->>'eta_to_kewdale','')<>'' and coalesce(r->>'eta_to_kewdale','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$')
      or (r ? 'resolution' and coalesce(r->>'resolution','')<>'manager_override_no_current_navision_match')
       or jsonb_typeof(r->'operations')<>'array'
       or jsonb_array_length(r->'operations') not between 1 and 100
       or exists(
         select 1 from jsonb_array_elements(r->'operations') o
         where jsonb_typeof(o)<>'object'
            or (select array_agg(k order by k) from jsonb_object_keys(o) k)
               is distinct from array['description','estimated_hours','estimated_hours_source','operation_no','work_key']::text[]
            or coalesce(o->>'operation_no','') !~ '^OP([1-9]|[1-9][0-9]{1,2})$'
            or coalesce(o->>'work_key','') not in ('bus4x4','tint','hoist','fitting','fabrication','electrical','tyre','pitInspection','PARTS')
            or length(coalesce(o->>'description','')) not between 1 and 180
            or o->>'description' is distinct from btrim(o->>'description')
            or o->>'description' ~ '[[:cntrl:]]'
            or jsonb_typeof(o->'estimated_hours') not in ('number','null')
            or (jsonb_typeof(o->'estimated_hours')='number' and coalesce(o->>'estimated_hours_source','') not in ('job_card','ai_estimate'))
            or (jsonb_typeof(o->'estimated_hours')='null' and o->>'estimated_hours_source' is not null)
            or (jsonb_typeof(o->'estimated_hours')='number' and (((o->>'estimated_hours')::numeric<0 or (o->>'estimated_hours')::numeric>999.99) or mod((o->>'estimated_hours')::numeric,0.01)<>0))
       )
       or (select count(*) from jsonb_array_elements(r->'operations'))<>(select count(distinct o->>'operation_no') from jsonb_array_elements(r->'operations') o)
  ) then
    return public.navision_backend_response(false,'invalid_row_or_operation');
  end if;
  if (select count(*) from jsonb_array_elements(v_payload))<>(select count(distinct (r->>'row_no')::integer) from jsonb_array_elements(v_payload) r) then
    return public.navision_backend_response(false,'duplicate_row');
  end if;
  if (select count(*) from jsonb_array_elements(v_payload))<>(select count(distinct upper(btrim(r->>'job_card_number'))||'|'||public.normalize_vehicle_stock_number(r->>'stock_number')) from jsonb_array_elements(v_payload) r) then
    return public.navision_backend_response(false,'duplicate_jc_stock_pair');
  end if;
  -- Explicit tokens retained for static contract review: duplicate_operation invalid_work_key invalid_hours.
  v_payload_sha256:=public.pdc_bulk_workbook_canonical_payload_sha256(v_payload);
  perform pg_advisory_xact_lock(hashtextextended('pdc-bulk-workbook-authorization:'||v_uid::text,0));
  select * into v_auth from public.pdc_bulk_workbook_authorizations a
   where a.actor_id=v_uid and a.status='available' and a.expires_at>clock_timestamp()
   order by a.created_at desc limit 1 for update;
  if not found then
    select * into v_auth from public.pdc_bulk_workbook_authorizations a
     where a.actor_id=v_uid and a.status in ('claimed','applied')
       and a.claimed_workbook_sha256=v_workbook_sha256 and a.claimed_payload_sha256=v_payload_sha256
     order by a.created_at desc limit 1 for update;
    if not found then return public.navision_backend_response(false,'authorization_not_available'); end if;
    select p.* into strict v_preview_id from public.pdc_bulk_workbook_previews p where p.preview_id=v_auth.claimed_preview_id;
    return public.navision_backend_response(true,'exact_preview_replay',jsonb_build_object(
      'preview_id',v_auth.claimed_preview_id,'authorization_id',v_auth.authorization_id,
      'workbook_sha256',v_workbook_sha256,'payload_sha256',v_payload_sha256));
  end if;

  insert into public.pdc_bulk_workbook_previews(preview_id,authorization_id,actor_id,workbook_sha256,payload_sha256,preview_payload,row_count,accepted_count,quarantine_count,blocked_count)
  values(v_preview_id,v_auth.authorization_id,v_uid,v_workbook_sha256,v_payload_sha256,v_payload,jsonb_array_length(v_payload),0,0,0);

  for v_row in select value from jsonb_array_elements(v_payload) loop
    v_row_no:=(v_row->>'row_no')::integer;
    v_jc:=upper(btrim(v_row->>'job_card_number'));
    v_stock:=public.normalize_vehicle_stock_number(v_row->>'stock_number');
    v_resolution:=v_row->>'resolution';
    select count(*) into v_exact_count from public.navision_backend_records r
     where r.source_system='microsoft_navision' and r.record_status='current' and r.is_current
       and public.normalize_vehicle_stock_number(r.normalized_data->>'batch')=v_stock
       and upper(btrim(coalesce(r.normalized_data->>'jobCardNumber','')))=v_jc;
    select count(*) into v_stock_count from public.navision_backend_records r
     where r.source_system='microsoft_navision' and r.record_status='current' and r.is_current
       and public.normalize_vehicle_stock_number(r.normalized_data->>'batch')=v_stock;
    select count(*) into v_jc_count from public.navision_backend_records r
     where r.source_system='microsoft_navision' and r.record_status='current' and r.is_current
       and upper(btrim(coalesce(r.normalized_data->>'jobCardNumber','')))=v_jc;
    select count(*) into v_operational_exact_count from public.vehicles v
     where v.deleted_at is null and v.lifecycle_state='active'
       and public.normalize_vehicle_stock_number(v.stock_number)=v_stock
       and upper(btrim(coalesce(v.job_card_number,'')))=v_jc;
    select count(*) into v_operational_partial_count from public.vehicles v
     where v.deleted_at is null and v.lifecycle_state='active'
       and ((public.normalize_vehicle_stock_number(v.stock_number)=v_stock and upper(btrim(coalesce(v.job_card_number,'')))<>v_jc)
         or (upper(btrim(coalesce(v.job_card_number,'')))=v_jc and public.normalize_vehicle_stock_number(v.stock_number)<>v_stock));
    v_reason:=null;
    if v_exact_count=1 then
      v_classification:='navision_exact'; v_accepted:=v_accepted+1;
    elsif v_exact_count>1 then
      v_classification:='quarantined'; v_reason:='multiple_current_exact_pair_matches'; v_quarantine:=v_quarantine+1; v_blocked:=v_blocked+1;
    elsif v_stock_count>0 or v_jc_count>0 then
      v_classification:='quarantined'; v_reason:='partial_identity_disagreement'; v_quarantine:=v_quarantine+1; v_blocked:=v_blocked+1;
    elsif v_operational_partial_count>0 or v_operational_exact_count>1 then
      v_classification:='quarantined'; v_reason:='operational_identity_conflict'; v_quarantine:=v_quarantine+1; v_blocked:=v_blocked+1;
    elsif v_resolution='manager_override_no_current_navision_match' and v_auth.allow_no_current_navision_override then
      v_classification:='manager_override_no_current_navision_match'; v_reason:='no_current_navision_match'; v_quarantine:=v_quarantine+1; v_accepted:=v_accepted+1;
    else
      v_classification:='quarantined'; v_reason:='no_current_navision_match'; v_quarantine:=v_quarantine+1; v_blocked:=v_blocked+1;
    end if;
    if v_reason is not null then
      insert into public.pdc_bulk_workbook_quarantine(preview_id,row_no,job_card_number,stock_number,reason_code,manager_override_selected,row_payload)
      values(v_preview_id,v_row_no,v_jc,v_stock,v_reason,v_classification='manager_override_no_current_navision_match',v_row);
    end if;
  end loop;

  if v_quarantine<>v_auth.expected_quarantine_count then
    raise exception 'pdc_bulk_workbook_quarantine_count_mismatch expected %, got %',v_auth.expected_quarantine_count,v_quarantine using errcode='22023';
  end if;
  if v_blocked>0 then
    raise exception 'pdc_bulk_workbook_unresolved_rows_blocked %',v_blocked using errcode='22023';
  end if;
  update public.pdc_bulk_workbook_previews set accepted_count=v_accepted,quarantine_count=v_quarantine,blocked_count=v_blocked where preview_id=v_preview_id;
  -- Preview immutability trigger intentionally requires the initial row to be final.
  -- The trigger is temporarily bypassed only inside this function via session_replication_role is forbidden;
  -- therefore replace the row atomically instead.
  raise exception 'PDC_BULK_124_INTERNAL_PREVIEW_FINALIZATION_UNREACHABLE';
end;
$preview$;

-- Replace Preview with a final-row implementation after removing the temporary trigger.
drop function public.pdc_bulk_workbook_preview_validation_draft(text,jsonb);
drop trigger pdc_bulk_workbook_previews_immutable on public.pdc_bulk_workbook_previews;

create or replace function public.preview_pdc_bulk_jc_stock_workbook(
  p_workbook_sha256 text,
  p_payload jsonb
)
returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,extensions
as $preview_final$
declare
  v_scope jsonb:=public.pdc_bulk_workbook_actor_scope(); v_uid uuid;
  v_workbook_sha256 text:=lower(btrim(coalesce(p_workbook_sha256,''))); v_payload jsonb:=coalesce(p_payload,'null'::jsonb); v_payload_sha256 text;
  v_auth public.pdc_bulk_workbook_authorizations%rowtype; v_preview_id uuid:=gen_random_uuid();
  v_row jsonb; v_row_no integer; v_jc text; v_stock text; v_resolution text;
  v_exact_count integer; v_stock_count integer; v_jc_count integer; v_operational_exact_count integer; v_operational_partial_count integer;
  v_classification text; v_reason text; v_accepted integer:=0; v_quarantine integer:=0; v_blocked integer:=0;
begin
  if not coalesce((v_scope->>'ok')::boolean,false) then return v_scope; end if; v_uid:=(v_scope->'data'->>'actor_id')::uuid;
  if v_workbook_sha256 !~ '^[a-f0-9]{64}$' or jsonb_typeof(v_payload) is distinct from 'array' or jsonb_array_length(v_payload) not between 1 and 500 then return public.navision_backend_response(false,'invalid_workbook_payload'); end if;
  if exists(select 1 from jsonb_array_elements(v_payload) r where jsonb_typeof(r)<>'object' or not (r ?& array['row_no','job_card_number','stock_number','operations'])
      or exists(select 1 from jsonb_object_keys(r) k where k<>all(array['row_no','job_card_number','stock_number','vin','customer_name','vehicle_description','registration','salesperson_reference','eta_to_kewdale','resolution','operations']))
      or jsonb_typeof(r->'row_no')<>'number' or (r->>'row_no') !~ '^[1-9][0-9]{0,5}$'
      or length(coalesce(r->>'job_card_number','')) not between 1 and 60 or r->>'job_card_number' is distinct from btrim(r->>'job_card_number') or r->>'job_card_number' ~ '[[:cntrl:]]'
      or length(coalesce(r->>'stock_number','')) not between 1 and 80 or r->>'stock_number' is distinct from btrim(r->>'stock_number') or r->>'stock_number' ~ '[[:cntrl:]]' or not public.is_real_vehicle_stock_number(r->>'stock_number')
      or exists(select 1 from jsonb_each(r) e where e.key in ('vin','customer_name','vehicle_description','registration','salesperson_reference','eta_to_kewdale','resolution') and jsonb_typeof(e.value) not in ('string','null'))
      or length(coalesce(r->>'vin',''))>80 or coalesce(r->>'vin','') ~ '[[:cntrl:]]'
      or length(coalesce(r->>'customer_name',''))>180 or coalesce(r->>'customer_name','') ~ '[[:cntrl:]]'
      or length(coalesce(r->>'vehicle_description',''))>180 or coalesce(r->>'vehicle_description','') ~ '[[:cntrl:]]'
      or length(coalesce(r->>'registration',''))>40 or coalesce(r->>'registration','') ~ '[[:cntrl:]]'
      or length(coalesce(r->>'salesperson_reference',''))>120 or coalesce(r->>'salesperson_reference','') ~ '[[:cntrl:]]'
      or (coalesce(r->>'eta_to_kewdale','')<>'' and coalesce(r->>'eta_to_kewdale','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$')
      or (r ? 'resolution' and coalesce(r->>'resolution','')<>'manager_override_no_current_navision_match')
      or jsonb_typeof(r->'operations')<>'array' or jsonb_array_length(r->'operations') not between 1 and 100
      or exists(select 1 from jsonb_array_elements(r->'operations') o where jsonb_typeof(o)<>'object'
        or (select array_agg(k order by k) from jsonb_object_keys(o) k) is distinct from array['description','estimated_hours','estimated_hours_source','operation_no','work_key']::text[]
        or coalesce(o->>'operation_no','') !~ '^OP([1-9]|[1-9][0-9]{1,2})$' or coalesce(o->>'work_key','') not in ('bus4x4','tint','hoist','fitting','fabrication','electrical','tyre','pitInspection','PARTS')
        or length(coalesce(o->>'description','')) not between 1 and 180 or o->>'description' is distinct from btrim(o->>'description') or o->>'description' ~ '[[:cntrl:]]'
        or jsonb_typeof(o->'estimated_hours') not in ('number','null')
        or (jsonb_typeof(o->'estimated_hours')='number' and coalesce(o->>'estimated_hours_source','') not in ('job_card','ai_estimate'))
        or (jsonb_typeof(o->'estimated_hours')='null' and o->>'estimated_hours_source' is not null)
        or (jsonb_typeof(o->'estimated_hours')='number' and (((o->>'estimated_hours')::numeric<0 or (o->>'estimated_hours')::numeric>999.99) or mod((o->>'estimated_hours')::numeric,0.01)<>0)))
      or (select count(*) from jsonb_array_elements(r->'operations'))<>(select count(distinct o->>'operation_no') from jsonb_array_elements(r->'operations') o)) then return public.navision_backend_response(false,'invalid_row_or_operation'); end if;
  if (select count(*) from jsonb_array_elements(v_payload))<>(select count(distinct (r->>'row_no')::integer) from jsonb_array_elements(v_payload) r) then return public.navision_backend_response(false,'duplicate_row'); end if;
  if (select count(*) from jsonb_array_elements(v_payload))<>(select count(distinct upper(btrim(r->>'job_card_number'))||'|'||public.normalize_vehicle_stock_number(r->>'stock_number')) from jsonb_array_elements(v_payload) r) then return public.navision_backend_response(false,'duplicate_jc_stock_pair'); end if;
  v_payload_sha256:=public.pdc_bulk_workbook_canonical_payload_sha256(v_payload);
  perform pg_advisory_xact_lock(hashtextextended('pdc-bulk-workbook-authorization:'||v_uid::text,0));
  select * into v_auth from public.pdc_bulk_workbook_authorizations a where a.actor_id=v_uid and a.status='available' and a.expires_at>clock_timestamp() order by a.created_at desc limit 1 for update;
  if not found then
    select * into v_auth from public.pdc_bulk_workbook_authorizations a where a.actor_id=v_uid and a.status in ('claimed','applied') and a.claimed_workbook_sha256=v_workbook_sha256 and a.claimed_payload_sha256=v_payload_sha256 order by a.created_at desc limit 1 for update;
    if not found then return public.navision_backend_response(false,'authorization_not_available'); end if;
    return public.navision_backend_response(true,'exact_preview_replay',jsonb_build_object('preview_id',v_auth.claimed_preview_id,'authorization_id',v_auth.authorization_id,'workbook_sha256',v_workbook_sha256,'payload_sha256',v_payload_sha256));
  end if;
  create temporary table pg_temp.pdc_bulk_preview_classifications(row_no integer primary key,job_card_number text,stock_number text,classification text,reason_code text,manager_override_selected boolean,row_payload jsonb) on commit drop;
  for v_row in select value from jsonb_array_elements(v_payload) loop
    v_row_no:=(v_row->>'row_no')::integer; v_jc:=upper(btrim(v_row->>'job_card_number')); v_stock:=public.normalize_vehicle_stock_number(v_row->>'stock_number'); v_resolution:=v_row->>'resolution';
    select count(*) into v_exact_count from public.navision_backend_records r where r.source_system='microsoft_navision' and r.record_status='current' and r.is_current and public.normalize_vehicle_stock_number(r.normalized_data->>'batch')=v_stock and upper(btrim(coalesce(r.normalized_data->>'jobCardNumber','')))=v_jc;
    select count(*) into v_stock_count from public.navision_backend_records r where r.source_system='microsoft_navision' and r.record_status='current' and r.is_current and public.normalize_vehicle_stock_number(r.normalized_data->>'batch')=v_stock;
    select count(*) into v_jc_count from public.navision_backend_records r where r.source_system='microsoft_navision' and r.record_status='current' and r.is_current and upper(btrim(coalesce(r.normalized_data->>'jobCardNumber','')))=v_jc;
    select count(*) into v_operational_exact_count from public.vehicles v where v.deleted_at is null and v.lifecycle_state='active' and public.normalize_vehicle_stock_number(v.stock_number)=v_stock and upper(btrim(coalesce(v.job_card_number,'')))=v_jc;
    select count(*) into v_operational_partial_count from public.vehicles v where v.deleted_at is null and v.lifecycle_state='active' and ((public.normalize_vehicle_stock_number(v.stock_number)=v_stock and upper(btrim(coalesce(v.job_card_number,'')))<>v_jc) or (upper(btrim(coalesce(v.job_card_number,'')))=v_jc and public.normalize_vehicle_stock_number(v.stock_number)<>v_stock));
    v_reason:=null;
    if v_exact_count=1 and v_stock_count=1 and v_jc_count=1 then v_classification:='navision_exact'; v_accepted:=v_accepted+1;
    elsif v_exact_count>1 or v_stock_count>1 or v_jc_count>1 then v_classification:='quarantined'; v_reason:='multiple_current_identity_matches'; v_quarantine:=v_quarantine+1; v_blocked:=v_blocked+1;
    elsif v_stock_count>0 or v_jc_count>0 then v_classification:='quarantined'; v_reason:='partial_identity_disagreement'; v_quarantine:=v_quarantine+1; v_blocked:=v_blocked+1;
    elsif v_operational_partial_count>0 or v_operational_exact_count>1 then v_classification:='quarantined'; v_reason:='operational_identity_conflict'; v_quarantine:=v_quarantine+1; v_blocked:=v_blocked+1;
    elsif v_resolution='manager_override_no_current_navision_match' and v_auth.allow_no_current_navision_override then v_classification:='manager_override_no_current_navision_match'; v_reason:='no_current_navision_match'; v_quarantine:=v_quarantine+1; v_accepted:=v_accepted+1;
    else v_classification:='quarantined'; v_reason:='no_current_navision_match'; v_quarantine:=v_quarantine+1; v_blocked:=v_blocked+1; end if;
    insert into pg_temp.pdc_bulk_preview_classifications values(v_row_no,v_jc,v_stock,v_classification,v_reason,v_classification='manager_override_no_current_navision_match',v_row);
  end loop;
  if v_quarantine<>v_auth.expected_quarantine_count then return public.navision_backend_response(false,'quarantine_count_mismatch',jsonb_build_object('expected',v_auth.expected_quarantine_count,'actual',v_quarantine)); end if;
  if v_blocked>0 then return public.navision_backend_response(false,'unresolved_rows_blocked',jsonb_build_object('blocked_count',v_blocked,'quarantine_count',v_quarantine)); end if;
  insert into public.pdc_bulk_workbook_previews(preview_id,authorization_id,actor_id,workbook_sha256,payload_sha256,preview_payload,row_count,accepted_count,quarantine_count,blocked_count)
  values(v_preview_id,v_auth.authorization_id,v_uid,v_workbook_sha256,v_payload_sha256,v_payload,jsonb_array_length(v_payload),v_accepted,v_quarantine,v_blocked);
  insert into public.pdc_bulk_workbook_quarantine(preview_id,row_no,job_card_number,stock_number,reason_code,manager_override_selected,row_payload)
  select v_preview_id,row_no,job_card_number,stock_number,reason_code,manager_override_selected,row_payload from pg_temp.pdc_bulk_preview_classifications where reason_code is not null order by row_no;
  update public.pdc_bulk_workbook_authorizations set claimed_at=clock_timestamp(),claimed_workbook_sha256=v_workbook_sha256,claimed_payload_sha256=v_payload_sha256,claimed_preview_id=v_preview_id,status='claimed' where authorization_id=v_auth.authorization_id and status='available';
  if not found then raise exception 'pdc_bulk_workbook_authorization_claim_race' using errcode='40001'; end if;
  return public.navision_backend_response(true,'preview_ready',jsonb_build_object('preview_id',v_preview_id,'authorization_id',v_auth.authorization_id,'workbook_sha256',v_workbook_sha256,'payload_sha256',v_payload_sha256,'row_count',jsonb_array_length(v_payload),'accepted_count',v_accepted,'quarantine_count',v_quarantine,'blocked_count',v_blocked,'manager_override_lane','manager_override_no_current_navision_match'));
end;
$preview_final$;

create trigger pdc_bulk_workbook_previews_immutable before update or delete on public.pdc_bulk_workbook_previews
for each row execute function public.pdc_bulk_workbook_reject_mutation();

create or replace function public.apply_pdc_bulk_jc_stock_workbook(
  p_preview_id uuid,
  p_workbook_sha256 text,
  p_payload_sha256 text
)
returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,extensions
as $apply$
declare
  v_scope jsonb:=public.pdc_bulk_workbook_actor_scope(); v_uid uuid; v_email text;
  v_preview public.pdc_bulk_workbook_previews%rowtype; v_auth public.pdc_bulk_workbook_authorizations%rowtype; v_existing public.pdc_bulk_workbook_apply_receipts%rowtype;
  v_receipt_id uuid:=gen_random_uuid(); v_receipt_hash text; v_row jsonb; v_row_no integer; v_jc text; v_stock text; v_classification text;
  v_backend_id uuid; v_vehicle_id uuid; v_existing_vehicle_count integer; v_vehicle_before uuid; v_activation public.navision_board_activations%rowtype;
  v_source_hash text; v_source_uid text; v_import_receipt_id uuid; v_identity_source text; v_ops jsonb; v_chunk jsonb; v_op_result jsonb; v_offset integer;
  v_total_vehicles_added integer:=0; v_total_lines_added integer:=0; v_total_hours_added integer:=0; v_row_lines integer; v_row_hours integer;
begin
  if not coalesce((v_scope->>'ok')::boolean,false) then return v_scope; end if; v_uid:=(v_scope->'data'->>'actor_id')::uuid; v_email:=v_scope->'data'->>'actor_email';
  if p_preview_id is null or lower(btrim(coalesce(p_workbook_sha256,''))) !~ '^[a-f0-9]{64}$' or lower(btrim(coalesce(p_payload_sha256,''))) !~ '^[a-f0-9]{64}$' then return public.navision_backend_response(false,'invalid_apply_binding'); end if;
  perform pg_advisory_xact_lock(hashtextextended('pdc-bulk-workbook-apply:'||p_preview_id::text,0));
  select * into v_preview from public.pdc_bulk_workbook_previews where preview_id=p_preview_id and actor_id=v_uid for share;
  if not found then return public.navision_backend_response(false,'preview_not_found'); end if;
  select * into v_auth from public.pdc_bulk_workbook_authorizations where authorization_id=v_preview.authorization_id and actor_id=v_uid for update;
  if v_auth.claimed_preview_id<>v_preview.preview_id or v_auth.claimed_workbook_sha256<>lower(btrim(p_workbook_sha256)) or v_auth.claimed_payload_sha256<>lower(btrim(p_payload_sha256)) or v_preview.workbook_sha256<>lower(btrim(p_workbook_sha256)) or v_preview.payload_sha256<>lower(btrim(p_payload_sha256)) or public.pdc_bulk_workbook_canonical_payload_sha256(v_preview.preview_payload)<>v_preview.payload_sha256 then return public.navision_backend_response(false,'apply_binding_mismatch'); end if;
  select * into v_existing from public.pdc_bulk_workbook_apply_receipts where preview_id=p_preview_id;
  if found then return public.navision_backend_response(true,'exact_replay',jsonb_build_object('receipt_id',v_existing.receipt_id,'preview_id',p_preview_id,'workbook_sha256',v_existing.workbook_sha256,'payload_sha256',v_existing.payload_sha256,'vehicles_added',0,'operation_lines_added',0,'estimated_hours_added',0,'zero_add_replay',true)); end if;
  if v_auth.status<>'claimed' or v_auth.expires_at<=clock_timestamp() or v_preview.blocked_count<>0 or v_preview.quarantine_count<>v_auth.expected_quarantine_count then return public.navision_backend_response(false,'authorization_or_preview_not_applyable'); end if;

  for v_row in select value from jsonb_array_elements(v_preview.preview_payload) order by (value->>'row_no')::integer loop
    v_row_no:=(v_row->>'row_no')::integer; v_jc:=upper(btrim(v_row->>'job_card_number')); v_stock:=public.normalize_vehicle_stock_number(v_row->>'stock_number'); v_ops:=v_row->'operations'; v_backend_id:=null; v_vehicle_id:=null; v_vehicle_before:=null;
    select case when exists(select 1 from public.pdc_bulk_workbook_quarantine q where q.preview_id=p_preview_id and q.row_no=v_row_no and q.manager_override_selected) then 'manager_override_no_current_navision_match' else 'navision_exact' end into v_classification;
    if v_classification='navision_exact' then
      if (select count(*) from public.navision_backend_records r where r.source_system='microsoft_navision' and r.record_status='current' and r.is_current and public.normalize_vehicle_stock_number(r.normalized_data->>'batch')=v_stock)<>1
         or (select count(*) from public.navision_backend_records r where r.source_system='microsoft_navision' and r.record_status='current' and r.is_current and upper(btrim(coalesce(r.normalized_data->>'jobCardNumber','')))=v_jc)<>1 then
        raise exception 'pdc_bulk_workbook_navision_identity_no_longer_unique row %',v_row_no using errcode='40001';
      end if;
      select r.id into strict v_backend_id from public.navision_backend_records r where r.source_system='microsoft_navision' and r.record_status='current' and r.is_current and public.normalize_vehicle_stock_number(r.normalized_data->>'batch')=v_stock and upper(btrim(coalesce(r.normalized_data->>'jobCardNumber','')))=v_jc;
      select canonical_vehicle_id into v_vehicle_before from public.navision_board_activations where backend_record_id=v_backend_id;
      insert into public.navision_board_activations(backend_record_id,activation_source,activated_stock_number,activated_by,activated_by_email,active)
      values(v_backend_id,'approved_key_list',v_stock,v_uid,v_email,true)
      on conflict(backend_record_id) do update set active=true,updated_at=clock_timestamp() where public.navision_board_activations.active=false and public.navision_board_activations.completed_at is null;
      select canonical_vehicle_id into v_vehicle_id from public.navision_board_activations where backend_record_id=v_backend_id and active;
      if v_vehicle_id is null then raise exception 'pdc_bulk_workbook_navision_activation_failed row %',v_row_no; end if;
      if v_vehicle_before is null then v_total_vehicles_added:=v_total_vehicles_added+1; end if;
      v_identity_source:='navision_exact';
    else
      if exists(select 1 from public.navision_backend_records r where r.source_system='microsoft_navision' and r.record_status='current' and r.is_current and (public.normalize_vehicle_stock_number(r.normalized_data->>'batch')=v_stock or upper(btrim(coalesce(r.normalized_data->>'jobCardNumber','')))=v_jc)) then raise exception 'pdc_bulk_workbook_override_stale_or_conflicting_navision_identity row %',v_row_no using errcode='40001'; end if;
      select count(*),min(v.id::text)::uuid into v_existing_vehicle_count,v_vehicle_id from public.vehicles v where v.deleted_at is null and v.lifecycle_state='active' and public.normalize_vehicle_stock_number(v.stock_number)=v_stock and upper(btrim(coalesce(v.job_card_number,'')))=v_jc;
      if v_existing_vehicle_count>1 or exists(select 1 from public.vehicles v where v.deleted_at is null and v.lifecycle_state='active' and ((public.normalize_vehicle_stock_number(v.stock_number)=v_stock and upper(btrim(coalesce(v.job_card_number,'')))<>v_jc) or (upper(btrim(coalesce(v.job_card_number,'')))=v_jc and public.normalize_vehicle_stock_number(v.stock_number)<>v_stock))) then raise exception 'pdc_bulk_workbook_override_operational_identity_conflict row %',v_row_no using errcode='40001'; end if;
      if v_existing_vehicle_count=0 then
        insert into public.vehicles(permanent_vehicle_id,stock_number,job_card_number,vin,customer_name,vehicle_description,registration,salesperson_reference,eta_to_kewdale,current_location,visible_on_board,source_system,source_record_id,lifecycle_state)
        values('BULK:'||p_preview_id::text||':'||v_row_no,v_stock,v_jc,nullif(btrim(coalesce(v_row->>'vin','')),''),nullif(btrim(coalesce(v_row->>'customer_name','')),''),coalesce(nullif(btrim(coalesce(v_row->>'vehicle_description','')),''),'Workbook identity pending Navision'),nullif(btrim(coalesce(v_row->>'registration','')),''),nullif(btrim(coalesce(v_row->>'salesperson_reference','')),''),case when coalesce(v_row->>'eta_to_kewdale','')='' then null else (v_row->>'eta_to_kewdale')::date end,'PMB',true,'bulk_workbook_manager_override','bulk:'||p_preview_id::text||':'||v_row_no,'active') returning id into v_vehicle_id;
        v_total_vehicles_added:=v_total_vehicles_added+1; v_identity_source:='email_new';
      else v_identity_source:='operational_exact'; end if;
    end if;
    update public.vehicles set current_location='PMB',visible_on_board=true,updated_at=clock_timestamp() where id=v_vehicle_id and deleted_at is null and lifecycle_state='active' and (current_location<>'PMB' or not visible_on_board);
    insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
    values('update','vehicles',v_vehicle_id,v_vehicle_id,v_uid,v_email,null,jsonb_build_object('current_location','PMB','visible_on_board',true),jsonb_build_object('source','pdc_bulk_workbook_124','preview_id',p_preview_id,'row_no',v_row_no,'authorization_reference',v_auth.authorization_reference,'classification',v_classification,'booking_created',false,'completed_work_reopened',false));
    v_source_hash:=encode(extensions.digest(convert_to(v_preview.payload_sha256||':'||v_row_no::text,'UTF8'),'sha256'),'hex'); v_source_uid:='bulk-workbook:'||p_preview_id::text||':'||v_row_no::text;
    insert into public.pdc_authenticated_email_import_receipts(actor_id,idempotency_key,request_hash,source_hash,evidence_hash,source_uid,sender_address,source_received_at,stock_number,vin,backend_record_id,vehicle_id,identity_source,required_work,response)
    values(v_uid,'bulk-workbook:'||p_preview_id::text||':'||v_row_no,v_preview.payload_sha256,v_source_hash,v_source_hash,v_source_uid,v_email,v_preview.created_at,v_stock,nullif(btrim(coalesce(v_row->>'vin','')),''),v_backend_id,v_vehicle_id,v_identity_source,(select coalesce(jsonb_agg(to_jsonb(work_key) order by work_key),'[]'::jsonb) from (select distinct o->>'work_key' work_key from jsonb_array_elements(v_ops) o) w),jsonb_build_object('source','pdc_bulk_workbook_124','preview_id',p_preview_id,'row_no',v_row_no,'classification',v_classification,'booking_created',false,'completed_work_reopened',false))
    on conflict(source_hash) do nothing returning receipt_id into v_import_receipt_id;
    if v_import_receipt_id is null then select receipt_id into strict v_import_receipt_id from public.pdc_authenticated_email_import_receipts where source_hash=v_source_hash and actor_id=v_uid and vehicle_id=v_vehicle_id; end if;
    v_offset:=0;
    while v_offset<jsonb_array_length(v_ops) loop
      select jsonb_agg(value order by ordinality) into v_chunk from jsonb_array_elements(v_ops) with ordinality where ordinality>v_offset and ordinality<=v_offset+50;
      v_op_result:=public.import_pdc_authenticated_email_operations_with_hours(v_source_hash,v_source_uid,v_chunk);
      if not coalesce((v_op_result->>'ok')::boolean,false) then raise exception 'pdc_bulk_workbook_operation_import_failed row %, code %',v_row_no,v_op_result->>'code'; end if;
      v_total_lines_added:=v_total_lines_added+coalesce((v_op_result->'data'->>'operation_lines_added')::integer,0); v_total_hours_added:=v_total_hours_added+coalesce((v_op_result->'data'->>'estimated_hours_added')::integer,0); v_offset:=v_offset+50;
    end loop;
    select count(*),count(*) filter(where estimated_hours is not null) into v_row_lines,v_row_hours from public.pdc_authenticated_email_operation_lines where source_hash=v_source_hash;
    if v_row_lines<>jsonb_array_length(v_ops) then raise exception 'pdc_bulk_workbook_operation_readback_mismatch row %',v_row_no; end if;
    insert into public.pdc_bulk_workbook_row_receipts(receipt_id,row_no,job_card_number,stock_number,classification,vehicle_id,backend_record_id,source_hash,operation_count,estimated_hours_count)
    values(v_receipt_id,v_row_no,v_jc,v_stock,v_classification,v_vehicle_id,v_backend_id,v_source_hash,v_row_lines,v_row_hours);
  end loop;
  v_receipt_hash:=encode(extensions.digest(convert_to(jsonb_build_object('receipt_id',v_receipt_id,'preview_id',p_preview_id,'authorization_id',v_auth.authorization_id,'workbook_sha256',v_preview.workbook_sha256,'payload_sha256',v_preview.payload_sha256,'row_count',v_preview.row_count,'quarantine_count',v_preview.quarantine_count,'vehicles_added',v_total_vehicles_added,'operation_lines_added',v_total_lines_added,'estimated_hours_added',v_total_hours_added)::text,'UTF8'),'sha256'),'hex');
  insert into public.pdc_bulk_workbook_apply_receipts(receipt_id,preview_id,authorization_id,actor_id,workbook_sha256,payload_sha256,row_count,quarantine_count,vehicles_added,operation_lines_added,estimated_hours_added,receipt_hash)
  values(v_receipt_id,p_preview_id,v_auth.authorization_id,v_uid,v_preview.workbook_sha256,v_preview.payload_sha256,v_preview.row_count,v_preview.quarantine_count,v_total_vehicles_added,v_total_lines_added,v_total_hours_added,v_receipt_hash);
  update public.pdc_bulk_workbook_authorizations set status='applied' where authorization_id=v_auth.authorization_id and status='claimed';
  return public.navision_backend_response(true,'applied',jsonb_build_object('receipt_id',v_receipt_id,'preview_id',p_preview_id,'workbook_sha256',v_preview.workbook_sha256,'payload_sha256',v_preview.payload_sha256,'row_count',v_preview.row_count,'quarantine_count',v_preview.quarantine_count,'vehicles_added',v_total_vehicles_added,'operation_lines_added',v_total_lines_added,'estimated_hours_added',v_total_hours_added,'receipt_hash',v_receipt_hash,'booking_created',false,'completed_work_reopened',false,'zero_add_replay',false));
end;
$apply$;

create or replace function public.read_pdc_bulk_jc_stock_workbook_receipt(p_receipt_id uuid)
returns jsonb language plpgsql stable security definer
set search_path=pg_catalog,public,extensions
as $readback$
declare v_scope jsonb:=public.pdc_bulk_workbook_actor_scope(); v_uid uuid; v_receipt public.pdc_bulk_workbook_apply_receipts%rowtype; v_rows jsonb; v_pair_count integer; v_line_count integer; v_hour_count integer; v_receipt_line_count integer; v_receipt_hour_count integer; v_identity_mismatch_count integer; v_ok boolean;
begin
  if not coalesce((v_scope->>'ok')::boolean,false) then return v_scope; end if; v_uid:=(v_scope->'data'->>'actor_id')::uuid;
  select * into v_receipt from public.pdc_bulk_workbook_apply_receipts where receipt_id=p_receipt_id and actor_id=v_uid; if not found then return public.navision_backend_response(false,'receipt_not_found'); end if;
  select count(*),coalesce(sum(rr.operation_count),0),coalesce(sum(rr.estimated_hours_count),0),coalesce(jsonb_agg(jsonb_build_object('row_no',rr.row_no,'job_card_number',rr.job_card_number,'stock_number',rr.stock_number,'classification',rr.classification,'vehicle_id',rr.vehicle_id,'backend_record_id',rr.backend_record_id,'operation_count',rr.operation_count,'estimated_hours_count',rr.estimated_hours_count,'operations',(select coalesce(jsonb_agg(jsonb_build_object('operation_no',ol.operation_no,'work_key',ol.work_key,'description',ol.description,'estimated_hours',ol.estimated_hours,'estimated_hours_source',ol.estimated_hours_source) order by ol.operation_no),'[]'::jsonb) from public.pdc_authenticated_email_operation_lines ol where ol.source_hash=rr.source_hash)) order by rr.row_no),'[]'::jsonb)
  into v_pair_count,v_receipt_line_count,v_receipt_hour_count,v_rows from public.pdc_bulk_workbook_row_receipts rr where rr.receipt_id=p_receipt_id;
  select count(ol.operation_line_id),count(ol.operation_line_id) filter(where ol.estimated_hours is not null)
  into v_line_count,v_hour_count
  from public.pdc_bulk_workbook_row_receipts rr
  left join public.pdc_authenticated_email_operation_lines ol on ol.source_hash=rr.source_hash
  where rr.receipt_id=p_receipt_id;
  select count(*) into v_identity_mismatch_count
  from public.pdc_bulk_workbook_row_receipts rr
  join public.vehicles v on v.id=rr.vehicle_id
  where rr.receipt_id=p_receipt_id
    and (upper(btrim(coalesce(v.job_card_number,'')))<>rr.job_card_number
      or public.normalize_vehicle_stock_number(v.stock_number)<>rr.stock_number
      or (select count(*) from public.pdc_authenticated_email_operation_lines ol where ol.source_hash=rr.source_hash)<>rr.operation_count
      or (select count(*) from public.pdc_authenticated_email_operation_lines ol where ol.source_hash=rr.source_hash and ol.estimated_hours is not null)<>rr.estimated_hours_count);
  v_ok:=v_pair_count=v_receipt.row_count and v_line_count=v_receipt_line_count and v_hour_count=v_receipt_hour_count and v_identity_mismatch_count=0;
  return public.navision_backend_response(v_ok,case when v_ok then 'readback_complete' else 'readback_mismatch' end,jsonb_build_object('receipt_id',v_receipt.receipt_id,'preview_id',v_receipt.preview_id,'workbook_sha256',v_receipt.workbook_sha256,'payload_sha256',v_receipt.payload_sha256,'jc_stock_pair_count',v_pair_count,'operation_line_count',v_line_count,'estimated_hours_count',v_hour_count,'quarantine_count',v_receipt.quarantine_count,'rows',v_rows,'immutable_receipt_hash',v_receipt.receipt_hash,'zero_add_replay_available',true));
end;
$readback$;

alter table public.pdc_bulk_workbook_authorizations enable row level security;
alter table public.pdc_bulk_workbook_previews enable row level security;
alter table public.pdc_bulk_workbook_quarantine enable row level security;
alter table public.pdc_bulk_workbook_apply_receipts enable row level security;
alter table public.pdc_bulk_workbook_row_receipts enable row level security;
revoke all on table public.pdc_bulk_workbook_authorizations from public,anon,authenticated;
revoke all on table public.pdc_bulk_workbook_previews from public,anon,authenticated;
revoke all on table public.pdc_bulk_workbook_quarantine from public,anon,authenticated;
revoke all on table public.pdc_bulk_workbook_apply_receipts from public,anon,authenticated;
revoke all on table public.pdc_bulk_workbook_row_receipts from public,anon,authenticated;
revoke all on function public.pdc_bulk_workbook_actor_scope() from public,anon,authenticated;
revoke all on function public.pdc_bulk_workbook_canonical_payload_sha256(jsonb) from public,anon,authenticated;
revoke all on function public.preview_pdc_bulk_jc_stock_workbook(text,jsonb) from public,anon,authenticated;
grant execute on function public.preview_pdc_bulk_jc_stock_workbook(text,jsonb) to authenticated;
revoke all on function public.apply_pdc_bulk_jc_stock_workbook(uuid,text,text) from public,anon,authenticated;
grant execute on function public.apply_pdc_bulk_jc_stock_workbook(uuid,text,text) to authenticated;
revoke all on function public.read_pdc_bulk_jc_stock_workbook_receipt(uuid) from public,anon,authenticated;
grant execute on function public.read_pdc_bulk_jc_stock_workbook_receipt(uuid) to authenticated;

insert into public.pdc_bulk_workbook_authorizations(actor_id,authorization_reference,authorization_scope,allow_no_current_navision_override,expected_quarantine_count,expires_at)
select i.user_id,'craig-31-july-2026-retained-workbook','retained_bulk_jc_stock_workbook_31_july',true,108,clock_timestamp()+interval '48 hours'
from public.pdc_monitor_vehicle_identity_readers i
join public.pdc_monitor_stage_activation_writers w on w.user_id=i.user_id
join public.pdc_user_roles r on r.auth_user_id=i.user_id
join auth.users u on u.id=i.user_id and lower(u.email)=lower(r.email)
where i.active and i.revoked_at is null and w.active and w.revoked_at is null and r.role='viewer' and r.active and r.account_status='approved';

insert into supabase_migrations.schema_migrations(version,name,statements)
values('124','bulk_jc_stock_workbook_contract',array['staging-only exact retained workbook preview/apply, unique-current activation, Craig manager override, immutable quarantine and receipts, JC/Stock read-back, zero-add replay']);

comment on function public.preview_pdc_bulk_jc_stock_workbook(text,jsonb) is 'Staging-only exact-workbook Preview for the retained JC/Stock workbook. Claims Craig 31 July authorization to one canonical payload and stores the 108 no-current rows in immutable quarantine.';
comment on function public.apply_pdc_bulk_jc_stock_workbook(uuid,text,text) is 'Staging-only exact-bound Apply. Unique-current Navision activation or Craig manager_override_no_current_navision_match only; persists individual operations/hours, never books, never reopens completed work; exact replay returns before DML.';
comment on function public.read_pdc_bulk_jc_stock_workbook_receipt(uuid) is 'Authenticated exact PDC Monitor JC/Stock and operation/hour read-back with immutable receipt hash and replay availability.';

commit;
