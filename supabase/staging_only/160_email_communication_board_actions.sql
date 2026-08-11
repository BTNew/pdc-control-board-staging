-- Staging-only migration 160: evidence-bound PMB communication actions.
-- Provider-authenticated retained email/PDF evidence may complete Parts, set an
-- exact Sublet booking date, or add approved unscheduled accessory work.
-- It never creates a workshop booking, schedules a bay, or mutates location.
begin;
set local lock_timeout='10s';
set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-160-email-communications',0));

do $guard$ begin
  if not public.pdc_monitor_staging_guard()
     or not exists(select 1 from supabase_migrations.schema_migrations where version='159' and name='bounded_jobcard_attachment_canonical_adapter')
     or to_regclass('public.pdc_provider_email_observations') is null
     or to_regclass('public.pdc_sublet_bookings') is null
     or to_regclass('public.pdc_authenticated_email_operation_lines') is null then
    raise exception 'PDC_160_STAGING_OR_DEPENDENCY_MISMATCH' using errcode='55000';
  end if;
  if exists(select 1 from supabase_migrations.schema_migrations where version='160') then
    raise exception 'PDC_160_ALREADY_APPLIED' using errcode='55000';
  end if;
end $guard$;

alter table public.pdc_authenticated_email_operation_lines
  drop constraint if exists pdc_authenticated_email_operation_lines_source_contract_check,
  add constraint pdc_authenticated_email_operation_lines_source_contract_check
    check(source_contract is null or source_contract in('pdc_staging_workbook_reset_136','pmb-email-communications-v1'));

create table public.pdc_email_communication_receipts(
  receipt_id uuid primary key default gen_random_uuid(),
  contract_version text not null check(contract_version='pmb-email-communications-v1'),
  actor_id uuid not null references auth.users(id) on delete restrict,
  actor_email text not null,
  intake_id uuid not null unique references public.ai_email_intake(id) on delete restrict,
  attachment_id uuid not null references public.ai_email_attachments(id) on delete restrict,
  source_hash text not null unique check(source_hash~'^[a-f0-9]{64}$'),
  attachment_hash text not null check(attachment_hash~'^[a-f0-9]{64}$'),
  extraction_hash text not null check(extraction_hash~'^[a-f0-9]{64}$'),
  server_extraction_hash text not null check(server_extraction_hash~'^[a-f0-9]{64}$'),
  request_sha256 text not null unique check(request_sha256~'^[a-f0-9]{64}$'),
  vehicle_id uuid not null references public.vehicles(id) on delete restrict,
  action_count integer not null check(action_count between 1 and 20),
  response jsonb not null check(jsonb_typeof(response)='object'),
  created_at timestamptz not null default clock_timestamp()
);
create table public.pdc_email_communication_action_receipts(
  action_receipt_id uuid primary key default gen_random_uuid(),
  receipt_id uuid not null references public.pdc_email_communication_receipts(receipt_id) on delete restrict deferrable initially deferred,
  source_action_no integer not null check(source_action_no between 1 and 20),
  action_type text not null check(action_type in('parts_complete','set_sublet_booking_date','add_accessory_work')),
  evidence text not null check(length(evidence) between 3 and 240 and evidence=btrim(evidence)),
  retained_clause text not null check(length(retained_clause) between 3 and 240 and retained_clause=btrim(retained_clause)),
  retained_clause_sha256 text not null check(retained_clause_sha256~'^[a-f0-9]{64}$'),
  requested_action jsonb not null check(jsonb_typeof(requested_action)='object'),
  before_data jsonb,
  after_data jsonb not null check(jsonb_typeof(after_data)='object'),
  action_sha256 text not null check(action_sha256~'^[a-f0-9]{64}$'),
  created_at timestamptz not null default clock_timestamp(),
  unique(receipt_id,source_action_no),unique(receipt_id,action_sha256)
);
alter table public.pdc_email_communication_receipts enable row level security;
alter table public.pdc_email_communication_action_receipts enable row level security;
revoke all on table public.pdc_email_communication_receipts from public,anon,authenticated,service_role;
revoke all on table public.pdc_email_communication_action_receipts from public,anon,authenticated,service_role;
create trigger pdc_email_communication_receipts_immutable before update or delete on public.pdc_email_communication_receipts
for each row execute function public.pdc_jobcard_attachment_receipt_reject_mutation();
create trigger pdc_email_communication_action_receipts_immutable before update or delete on public.pdc_email_communication_action_receipts
for each row execute function public.pdc_jobcard_attachment_receipt_reject_mutation();

-- One retained provider-observed source may drive exactly one terminal operation family.
create table public.pdc_email_evidence_consumptions(
  source_hash text primary key check(source_hash~'^[a-f0-9]{64}$'),
  intake_id uuid not null unique references public.ai_email_intake(id) on delete restrict,
  attachment_id uuid not null references public.ai_email_attachments(id) on delete restrict,
  observation_id uuid not null unique references public.pdc_provider_email_observations(observation_id) on delete restrict,
  actor_id uuid not null references auth.users(id) on delete restrict,
  vehicle_id uuid not null references public.vehicles(id) on delete restrict,
  operation_family text not null check(operation_family in('communication','non_navision_jobcard')),
  request_sha256 text not null unique check(request_sha256~'^[a-f0-9]{64}$'),
  receipt_id uuid not null unique,
  created_at timestamptz not null default clock_timestamp()
);
alter table public.pdc_email_evidence_consumptions enable row level security;
revoke all on table public.pdc_email_evidence_consumptions from public,anon,authenticated,service_role;
create trigger pdc_email_evidence_consumptions_immutable before update or delete on public.pdc_email_evidence_consumptions
for each row execute function public.pdc_jobcard_attachment_receipt_reject_mutation();

create function public.pdc_email_import_receipt_consumption_guard() returns trigger language plpgsql security definer
set search_path=pg_catalog,public,extensions as $guard$
begin
  perform pg_advisory_xact_lock(hashtextextended('pdc-email-evidence-consumption:'||new.source_hash,0));
  if exists(select 1 from public.pdc_email_evidence_consumptions c where c.source_hash=new.source_hash) then
    raise exception 'retained email evidence already consumed' using errcode='23505';
  end if;
  return new;
end $guard$;
revoke all on function public.pdc_email_import_receipt_consumption_guard() from public,anon,authenticated,service_role;
create trigger pdc_email_import_receipt_consumption_guard before insert on public.pdc_authenticated_email_import_receipts
for each row execute function public.pdc_email_import_receipt_consumption_guard();

create function public.pdc_email_operation_line_reject_mutation() returns trigger language plpgsql security definer
set search_path=pg_catalog,public as $immutable$
begin raise exception 'authenticated email source operation lines are immutable' using errcode='55000';end $immutable$;
revoke all on function public.pdc_email_operation_line_reject_mutation() from public,anon,authenticated,service_role;
create trigger pdc_email_communication_operation_lines_immutable before update or delete on public.pdc_authenticated_email_operation_lines
for each row when (old.source_contract='pmb-email-communications-v1') execute function public.pdc_email_operation_line_reject_mutation();

create function public.pdc_email_safe_date(p_value text) returns date language plpgsql immutable strict
set search_path=pg_catalog as $safe$ begin return p_value::date;exception when others then return null;end $safe$;
revoke all on function public.pdc_email_safe_date(text) from public,anon,authenticated,service_role;

create function public.pdc_email_safe_uuid(p_value text) returns uuid language plpgsql immutable strict
set search_path=pg_catalog as $safe$
begin
  if p_value!~'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then return null;end if;
  return p_value::uuid;
exception when others then return null;end $safe$;
revoke all on function public.pdc_email_safe_uuid(text) from public,anon,authenticated,service_role;

create function public.pdc_email_safe_positive_integer(p_value jsonb,p_max integer) returns integer language plpgsql immutable strict
set search_path=pg_catalog as $safe$
declare n numeric;begin
  if jsonb_typeof(p_value)<>'number' then return null;end if;
  n:=(p_value#>>'{}')::numeric;
  if n<>trunc(n) or n<1 or n>p_max then return null;end if;
  return n::integer;
exception when others then return null;end $safe$;
revoke all on function public.pdc_email_safe_positive_integer(jsonb,integer) from public,anon,authenticated,service_role;

create function public.pdc_email_normalized_clause(p_value text) returns text language sql immutable strict
set search_path=pg_catalog as $safe$
select lower(btrim(regexp_replace(p_value,'[[:space:]]+',' ','g'),' .,;:-')) $safe$;
revoke all on function public.pdc_email_normalized_clause(text) from public,anon,authenticated,service_role;

create function public.read_pdc_email_communication_receipt(p_receipt_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,extensions as $read$
declare v_actor uuid:=auth.uid();v_receipt public.pdc_email_communication_receipts%rowtype;v_actions jsonb;begin
  if not public.pdc_monitor_staging_guard() or v_actor is null or p_receipt_id is null then
    return public.navision_backend_response(false,'unauthorized');
  end if;
  select * into v_receipt from public.pdc_email_communication_receipts where receipt_id=p_receipt_id and actor_id=v_actor;
  if not found then return public.navision_backend_response(false,'receipt_not_found'); end if;
  select coalesce(jsonb_agg(jsonb_build_object('source_action_no',source_action_no,'action_type',action_type,
    'evidence',evidence,'retained_clause',retained_clause,'retained_clause_sha256',retained_clause_sha256,
    'requested_action',requested_action,'before_data',before_data,'after_data',after_data)
    order by source_action_no),'[]'::jsonb) into v_actions
  from public.pdc_email_communication_action_receipts where receipt_id=v_receipt.receipt_id;
  if jsonb_array_length(v_actions)<>v_receipt.action_count or exists(
    select 1 from public.pdc_email_communication_action_receipts a where a.receipt_id=v_receipt.receipt_id and (
      a.retained_clause<>public.pdc_email_normalized_clause(a.evidence)
      or a.retained_clause_sha256<>encode(extensions.digest(convert_to(a.retained_clause,'UTF8'),'sha256'),'hex')
      or a.action_sha256<>encode(extensions.digest(convert_to(jsonb_build_object('source_hash',v_receipt.source_hash,'action',a.requested_action)::text,'UTF8'),'sha256'),'hex')
    )) then
    return public.navision_backend_response(false,'communication_receipt_drift');
  end if;
  return public.navision_backend_response(true,'communication_receipt',jsonb_build_object(
    'receipt_id',v_receipt.receipt_id,'intake_id',v_receipt.intake_id,'attachment_id',v_receipt.attachment_id,
    'vehicle_id',v_receipt.vehicle_id,'action_count',v_receipt.action_count,'actions',v_actions,
    'booking_created',false,'location_changed',false));
end $read$;
revoke all on function public.read_pdc_email_communication_receipt(uuid) from public,anon,authenticated,service_role;
grant execute on function public.read_pdc_email_communication_receipt(uuid) to authenticated;

create function public.process_pdc_email_communication(
  p_intake_id uuid,p_expected_source_hash text,p_extraction_hash text,p_extraction jsonb,p_actor text
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions set statement_timeout='180s' as $process$
declare
  v_actor uuid:=auth.uid();v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_source text:=lower(btrim(coalesce(p_expected_source_hash,'')));v_extraction_hash text:=lower(btrim(coalesce(p_extraction_hash,'')));
  v_payload jsonb:=coalesce(p_extraction,'null'::jsonb);v_server_hash text;v_request text;
  v_intake public.ai_email_intake%rowtype;v_attachment public.ai_email_attachments%rowtype;v_observation public.pdc_provider_email_observations%rowtype;
  v_receipt public.pdc_email_communication_receipts%rowtype;v_vehicle public.vehicles%rowtype;v_parts public.vehicle_parts_updates%rowtype;
  v_work public.vehicle_work_items%rowtype;v_sublet public.pdc_sublet_bookings%rowtype;v_import public.pdc_authenticated_email_import_receipts%rowtype;
  v_identity jsonb;v_actions jsonb;v_action jsonb;v_candidates uuid[];v_stock_candidates uuid[];v_vin_candidates uuid[];v_job_candidates uuid[];
  v_stock text;v_vin text;v_job text;v_type text;v_evidence text;v_retained text;v_norm_evidence text;v_attachment_id uuid;
  v_before jsonb;v_after jsonb;v_result jsonb;v_failure jsonb;v_receipt_id uuid:=gen_random_uuid();v_source_uid text;v_action_hash text;
  v_required_work jsonb:='[]'::jsonb;v_work_key text;v_description text;v_date date;v_line_id uuid;v_operation_no text;v_now timestamptz:=clock_timestamp();
begin
  if not public.pdc_monitor_staging_guard() or v_actor is null or v_email='' or lower(btrim(coalesce(p_actor,'')))<>'pdc-monitor'
     or v_source!~'^[a-f0-9]{64}$' or v_extraction_hash!~'^[a-f0-9]{64}$' or jsonb_typeof(v_payload)<>'object'
     or (select array_agg(k order by k) from jsonb_object_keys(v_payload) k) is distinct from array[
       'actions','authentication','auto_applicable','canonical_attachment_id','canonical_document_hash','contract_version','identity','review_reasons']::text[]
     or v_payload->>'contract_version'<>'pmb-email-communications-v1' or v_payload->'auto_applicable'<>'true'::jsonb
     or v_payload->'review_reasons'<>'[]'::jsonb
     or coalesce(v_payload->>'canonical_attachment_id','')!~'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
     or lower(coalesce(v_payload->>'canonical_document_hash',''))!~'^[a-f0-9]{64}$'
     or jsonb_typeof(v_payload->'authentication')<>'object' or jsonb_typeof(v_payload->'identity')<>'object'
     or jsonb_typeof(v_payload->'actions')<>'array' or jsonb_array_length(v_payload->'actions') not between 1 and 20 then
    return public.navision_backend_response(false,'invalid_communication_extraction');
  end if;
  v_attachment_id:=public.pdc_email_safe_uuid(v_payload->>'canonical_attachment_id');
  if v_attachment_id is null then return public.navision_backend_response(false,'invalid_communication_extraction');end if;
  perform 1 from public.pdc_user_roles r where r.auth_user_id=v_actor and lower(r.email)=v_email
    and r.role='importer' and r.active and r.account_status='approved' for share;
  if not found then return public.navision_backend_response(false,'unauthorized'); end if;
  perform 1 from public.pdc_monitor_stage_activation_writers w where w.user_id=v_actor and w.active and w.revoked_at is null for share;
  if not found then return public.navision_backend_response(false,'unauthorized'); end if;

  v_identity:=v_payload->'identity';v_actions:=v_payload->'actions';
  if (select array_agg(k order by k) from jsonb_object_keys(v_identity) k) is distinct from array['job_card_numbers','stock_numbers','vins']::text[]
     or jsonb_typeof(v_identity->'job_card_numbers')<>'array' or jsonb_array_length(v_identity->'job_card_numbers')>1
     or jsonb_typeof(v_identity->'stock_numbers')<>'array' or jsonb_array_length(v_identity->'stock_numbers')>1
     or jsonb_typeof(v_identity->'vins')<>'array' or jsonb_array_length(v_identity->'vins')>1
     or exists(select 1 from jsonb_array_elements(v_identity->'job_card_numbers') x where jsonb_typeof(x)<>'string')
     or exists(select 1 from jsonb_array_elements(v_identity->'stock_numbers') x where jsonb_typeof(x)<>'string')
     or exists(select 1 from jsonb_array_elements(v_identity->'vins') x where jsonb_typeof(x)<>'string')
     or jsonb_array_length(v_identity->'job_card_numbers')+jsonb_array_length(v_identity->'stock_numbers')+jsonb_array_length(v_identity->'vins')<1 then
    return public.navision_backend_response(false,'communication_vehicle_identity_invalid');
  end if;
  v_stock:=nullif(public.normalize_vehicle_stock_number(v_identity->'stock_numbers'->>0),'');
  v_vin:=nullif(public.normalize_vehicle_vin(v_identity->'vins'->>0),'');
  v_job:=nullif(upper(btrim(v_identity->'job_card_numbers'->>0)),'');
  if (v_stock is not null and not public.is_real_vehicle_stock_number(v_stock)) or (v_vin is not null and not public.is_valid_vehicle_vin(v_vin))
     or (v_job is not null and (length(v_job)>80 or v_job~'[[:cntrl:]]')) then
    return public.navision_backend_response(false,'communication_vehicle_identity_invalid');
  end if;

  select * into v_intake from public.ai_email_intake where id=p_intake_id for update;
  if not found then return public.navision_backend_response(false,'intake_not_found'); end if;
  select * into v_attachment from public.ai_email_attachments where id=v_attachment_id and intake_id=p_intake_id for share;
  if not found then return public.navision_backend_response(false,'attachment_not_found'); end if;
  select * into v_observation from public.pdc_provider_email_observations where intake_id=p_intake_id and attachment_id=v_attachment.id for share;
  if not found or v_observation.parent_source_hash<>v_source or v_observation.attachment_source_hash<>lower(v_payload->>'canonical_document_hash')
     or v_observation.authentication is distinct from v_payload->'authentication' or lower(v_intake.source_hash)<>v_source
     or lower(v_attachment.source_hash)<>lower(v_payload->>'canonical_document_hash')
     or v_attachment.text_extraction_status<>'extracted' or nullif(btrim(coalesce(v_attachment.extracted_text,'')),'') is null
     or length(v_attachment.extracted_text)>500000 then
    return public.navision_backend_response(false,'communication_evidence_binding_failed');
  end if;

  if exists(select 1 from jsonb_array_elements(v_actions) with ordinality x(a,n) where jsonb_typeof(a)<>'object'
    or public.pdc_email_safe_positive_integer(a->'source_action_no',20) is distinct from n::integer
    or a->>'action_type' not in('parts_complete','set_sublet_booking_date','add_accessory_work')
    or length(coalesce(a->>'evidence','')) not between 3 and 240 or a->>'evidence' is distinct from btrim(a->>'evidence')
    or (a->>'evidence')~'[[:cntrl:]]'
    or (a->>'action_type'='parts_complete' and (select array_agg(k order by k) from jsonb_object_keys(a) k) is distinct from array['action_type','evidence','source_action_no']::text[])
    or (a->>'action_type'='set_sublet_booking_date' and ((select array_agg(k order by k) from jsonb_object_keys(a) k) is distinct from array['action_type','booking_date','evidence','source_action_no']::text[] or public.pdc_email_safe_date(a->>'booking_date') is null))
    or (a->>'action_type'='add_accessory_work' and ((select array_agg(k order by k) from jsonb_object_keys(a) k) is distinct from array['action_type','description','evidence','source_action_no','work_key']::text[]
      or (a->>'description',a->>'work_key') not in(('Long range tank','fitting'),('UHF radio','electrical'),('Towbar','fitting'),('Canopy','fabrication'),('Tray','fabrication'),('Tyre upgrade','tyre'),('Spotlights','electrical'),('Light bar','electrical'))))
  ) or (select count(*) from jsonb_array_elements(v_actions) a where a->>'action_type'='parts_complete')>1
    or (select count(*) from jsonb_array_elements(v_actions) a where a->>'action_type'='set_sublet_booking_date')>1
    or (select count(*) from jsonb_array_elements(v_actions) a where a->>'action_type'='add_accessory_work')<>
       (select count(distinct a->>'work_key') from jsonb_array_elements(v_actions) a where a->>'action_type'='add_accessory_work') then
    return public.navision_backend_response(false,'communication_actions_invalid');
  end if;

  perform pg_advisory_xact_lock(hashtextextended('pdc-email-communication-160:'||p_intake_id::text,0));
  v_server_hash:=encode(extensions.digest(convert_to(v_payload::text,'UTF8'),'sha256'),'hex');
  v_request:=encode(extensions.digest(convert_to(jsonb_build_object('contract_version','160.2','actor_id',v_actor,'intake_id',p_intake_id,
    'source_hash',v_source,'extraction_hash',v_extraction_hash,'server_hash',v_server_hash,'payload',v_payload)::text,'UTF8'),'sha256'),'hex');
  select * into v_receipt from public.pdc_email_communication_receipts where intake_id=p_intake_id;
  if found then
    if v_receipt.actor_id<>v_actor or v_receipt.source_hash<>v_source or v_receipt.extraction_hash<>v_extraction_hash
       or v_receipt.server_extraction_hash<>v_server_hash or v_receipt.request_sha256<>v_request then
      return public.navision_backend_response(false,'communication_replay_conflict');
    end if;
    return public.read_pdc_email_communication_receipt(v_receipt.receipt_id);
  end if;

  if v_intake.duplicate_of is not null or v_intake.received_at is null or v_intake.received_at>clock_timestamp()+interval '5 minutes'
     or v_intake.received_at<clock_timestamp()-interval '30 days'
     or not exists(select 1 from public.pdc_monitor_exact_sender_enrollments e where e.active and e.sender_sha256=
       encode(extensions.digest(convert_to(lower(btrim(v_intake.sender_email)),'UTF8'),'sha256'),'hex')) then
    return public.navision_backend_response(false,'communication_evidence_binding_failed');
  end if;
  v_retained:=public.pdc_email_normalized_clause(v_attachment.extracted_text);
  if (v_stock is not null and position(lower(v_stock) in v_retained)=0)
     or (v_vin is not null and position(lower(v_vin) in regexp_replace(v_retained,'[^a-z0-9]','','g'))=0)
     or (v_job is not null and position(lower(v_job) in v_retained)=0)
     or exists(select 1 from jsonb_array_elements(v_actions) a where
       (select count(*) from regexp_split_to_table(v_attachment.extracted_text,
          E'[!?](?=\\s|$)|\\.(?=\\s|$)|\\r?\\n') clause
        where public.pdc_email_normalized_clause(clause)=public.pdc_email_normalized_clause(a->>'evidence'))<>1
       or (a->>'evidence')~* '(^|[^[:alnum:]_])(if|when|once|unless|provided|assuming|can|could|would|should|will|shall|may|might|expected?|expecting|proposed?|proposal|planned?|intended?|due|tentative|provisional|perhaps|maybe|soon|tomorrow|pending|outstanding|waiting|cancelled?|not|no|never|without|remove|delete|incomplete)([^[:alnum:]_]|$)|[?]|(^|[^0-9])[0-9]{1,3}[[:space:]]*%'
       or (a->>'action_type'='parts_complete' and not (a->>'evidence')~* '(^|[^a-z0-9_])parts?[^a-z0-9_].{0,60}(complete|completed|received)([^a-z0-9_]|$)')
       or (a->>'action_type'='set_sublet_booking_date' and (not (a->>'evidence')~* 'sub[ -]?let.{0,120}(booked|booking|scheduled)'
         or not (lower(a->>'evidence') like '%'||lower(a->>'booking_date')||'%'
           or lower(a->>'evidence') like '%'||lower(to_char(public.pdc_email_safe_date(a->>'booking_date'),'DD/MM/YYYY'))||'%'
           or lower(a->>'evidence') like '%'||lower(to_char(public.pdc_email_safe_date(a->>'booking_date'),'DD-MM-YYYY'))||'%'
           or lower(a->>'evidence') like '%'||lower(to_char(public.pdc_email_safe_date(a->>'booking_date'),'FMDD FMMonth YYYY'))||'%')))
       or (a->>'action_type'='add_accessory_work' and (
         not public.pdc_email_normalized_clause(a->>'evidence')~
           '^(please )?(add|fit|install) (a |an |the )?(long range( fuel)? tank|uhf( radio)?|tow ?bar|canopy|tray|tyres?|tires?|tyre upgrade|tire upgrade|spot ?lights?|light bar) (to|onto|on) (this )?(job|job card|vehicle)$'
         or case a->>'description'
           when 'Long range tank' then not (a->>'evidence')~* 'long[ -]?range( fuel)? tank'
           when 'UHF radio' then not (a->>'evidence')~* '(^|[^[:alnum:]_])uhf([^[:alnum:]_]|$)'
           when 'Towbar' then not (a->>'evidence')~* 'tow[ -]?bar'
           when 'Canopy' then not (a->>'evidence')~* '(^|[^[:alnum:]_])canopy([^[:alnum:]_]|$)'
           when 'Tray' then not (a->>'evidence')~* '(^|[^[:alnum:]_])tray([^[:alnum:]_]|$)'
           when 'Tyre upgrade' then not (a->>'evidence')~* '(^|[^[:alnum:]_])(tyre|tire)s?([^[:alnum:]_]|$)'
           when 'Spotlights' then not (a->>'evidence')~* 'spot[ -]?lights?'
           when 'Light bar' then not (a->>'evidence')~* 'light[ -]?bar'
           else true end))
     ) then return public.navision_backend_response(false,'communication_retained_text_mismatch'); end if;

  perform pg_advisory_xact_lock(hashtextextended('pdc-email-evidence-consumption:'||v_source,0));
  if exists(select 1 from public.pdc_email_evidence_consumptions c where c.source_hash=v_source)
     or exists(select 1 from public.pdc_authenticated_email_import_receipts r where r.source_hash=v_source) then
    return public.navision_backend_response(false,'communication_evidence_already_consumed');
  end if;

  select coalesce(array_agg(distinct id order by id),'{}'::uuid[]) into v_stock_candidates from (
    select v.id from public.vehicles v where v.deleted_at is null and v_stock is not null and v.stock_number_normalized=v_stock
    union all select a.vehicle_id from public.vehicle_aliases a where a.active and v_stock is not null
      and a.alias_type_normalized='stock_number' and a.normalized_alias_value=v_stock) q;
  select coalesce(array_agg(distinct id order by id),'{}'::uuid[]) into v_vin_candidates from (
    select v.id from public.vehicles v where v.deleted_at is null and v_vin is not null and v.vin_normalized=v_vin
    union all select a.vehicle_id from public.vehicle_aliases a where a.active and v_vin is not null
      and a.alias_type_normalized='vin' and a.normalized_alias_value=v_vin) q;
  select coalesce(array_agg(distinct id order by id),'{}'::uuid[]) into v_job_candidates from (
    select v.id from public.vehicles v where v.deleted_at is null and v_job is not null and upper(btrim(coalesce(v.job_card_number,'')))=v_job
    union all select a.vehicle_id from public.vehicle_aliases a where a.active and v_job is not null
      and a.alias_type_normalized in('job_card','job_card_number') and upper(btrim(a.normalized_alias_value))=v_job) q;
  if (v_stock is not null and cardinality(v_stock_candidates)=0) or (v_vin is not null and cardinality(v_vin_candidates)=0)
     or (v_job is not null and cardinality(v_job_candidates)=0) then
    return public.navision_backend_response(false,'communication_vehicle_not_found');
  end if;
  if cardinality(v_stock_candidates)>1 or cardinality(v_vin_candidates)>1 or cardinality(v_job_candidates)>1 then
    return public.navision_backend_response(false,'communication_vehicle_ambiguous');
  end if;
  v_candidates:=case when v_stock is not null then v_stock_candidates when v_vin is not null then v_vin_candidates else v_job_candidates end;
  if (v_stock is not null and v_stock_candidates[1]<>v_candidates[1])
     or (v_vin is not null and v_vin_candidates[1]<>v_candidates[1])
     or (v_job is not null and v_job_candidates[1]<>v_candidates[1]) then
    return public.navision_backend_response(false,'communication_vehicle_identity_disagreement');
  end if;
  perform pg_advisory_xact_lock(hashtextextended('pdc-email-communication-vehicle-160:'||v_candidates[1]::text,0));
  select * into v_vehicle from public.vehicles where id=v_candidates[1] for update;
  if not found or v_vehicle.deleted_at is not null or v_vehicle.lifecycle_state<>'active' or not v_vehicle.visible_on_board
     or v_vehicle.board_purged_at is not null or v_vehicle.rft_collected_at is not null
     or upper(btrim(coalesce(v_vehicle.current_location,'')))='COMPLETED' then
    return public.navision_backend_response(false,'communication_vehicle_protected');
  end if;
  if (v_stock is not null and v_vehicle.stock_number_normalized is distinct from v_stock
      and not exists(select 1 from public.vehicle_aliases a where a.vehicle_id=v_vehicle.id and a.active and a.alias_type_normalized='stock_number' and a.normalized_alias_value=v_stock))
     or (v_vin is not null and v_vehicle.vin_normalized is distinct from v_vin
      and not exists(select 1 from public.vehicle_aliases a where a.vehicle_id=v_vehicle.id and a.active and a.alias_type_normalized='vin' and a.normalized_alias_value=v_vin))
     or (v_job is not null and upper(btrim(coalesce(v_vehicle.job_card_number,''))) is distinct from v_job) then
    return public.navision_backend_response(false,'communication_vehicle_identity_disagreement');
  end if;
  perform 1 from public.vehicle_work_items w where w.vehicle_id=v_vehicle.id and w.work_key in
    (select a->>'work_key' from jsonb_array_elements(v_actions) a where a->>'action_type'='add_accessory_work') for update;
  if exists(select 1 from public.vehicle_work_items w where w.vehicle_id=v_vehicle.id and w.completed and w.work_key in
    (select a->>'work_key' from jsonb_array_elements(v_actions) a where a->>'action_type'='add_accessory_work')) then
    return public.navision_backend_response(false,'communication_completed_work_protected');
  end if;

  begin
    -- One operational receipt lets approved added work appear in existing canonical job-line views.
    if exists(select 1 from jsonb_array_elements(v_actions) a where a->>'action_type'='add_accessory_work') then
      select coalesce(jsonb_agg(distinct to_jsonb(a->>'work_key')),'[]'::jsonb) into v_required_work
        from jsonb_array_elements(v_actions) a where a->>'action_type'='add_accessory_work';
      v_source_uid:='pdc-comm-160:'||substring(v_source,1,64);
      insert into public.pdc_authenticated_email_import_receipts(actor_id,idempotency_key,request_hash,source_hash,evidence_hash,source_uid,
        sender_address,source_received_at,stock_number,vin,backend_record_id,backend_record_version,vehicle_id,identity_source,required_work,response)
      values(v_actor,'pdc-email-import-'||substring(v_request,1,64),v_request,v_source,lower(v_attachment.source_hash),v_source_uid,
        lower(v_intake.sender_email),v_intake.received_at,v_vehicle.stock_number,v_vehicle.vin,null,null,v_vehicle.id,'operational_exact',v_required_work,
        public.navision_backend_response(true,'communication_source_bound',jsonb_build_object('vehicle_id',v_vehicle.id,'booking_created',false)))
      returning * into v_import;
    end if;

    for v_action in select value from jsonb_array_elements(v_actions) order by public.pdc_email_safe_positive_integer(value->'source_action_no',20) loop
      v_type:=v_action->>'action_type';v_evidence:=v_action->>'evidence';v_norm_evidence:=public.pdc_email_normalized_clause(v_evidence);v_before:=null;v_after:=null;
      if v_type='parts_complete' then
        select * into v_work from public.vehicle_work_items where vehicle_id=v_vehicle.id and work_key='PARTS' for update;
        v_before:=case when found then to_jsonb(v_work) else null end;
        insert into public.vehicle_work_items(vehicle_id,work_key,required,completed,completed_by,completed_at,notes,updated_at)
        values(v_vehicle.id,'PARTS',true,true,v_actor,v_now,'Completed from authenticated retained communication',v_now)
        on conflict(vehicle_id,work_key) do update set required=true,completed=true,completed_by=v_actor,
          completed_at=coalesce(public.vehicle_work_items.completed_at,v_now),
          notes=case when public.vehicle_work_items.completed then public.vehicle_work_items.notes else 'Completed from authenticated retained communication' end,
          updated_at=case when public.vehicle_work_items.completed then public.vehicle_work_items.updated_at else v_now end;
        select * into v_parts from public.vehicle_parts_updates where vehicle_id=v_vehicle.id order by updated_at desc,id desc limit 1 for update;
        insert into public.vehicle_parts_updates(vehicle_id,parts_required,parts_ordered,parts_received,parts_stoppage,parts_stoppage_reason,worst_eta,updated_by,updated_at)
        values(v_vehicle.id,true,true,true,false,null,v_parts.worst_eta,v_actor,v_now);
        select to_jsonb(w) into v_after from public.vehicle_work_items w where w.vehicle_id=v_vehicle.id and w.work_key='PARTS';
      elsif v_type='set_sublet_booking_date' then
        begin v_date:=(v_action->>'booking_date')::date;exception when others then v_failure:=public.navision_backend_response(false,'invalid_sublet_date');raise exception 'PDC_160_FALSE';end;
        select * into v_sublet from public.pdc_sublet_bookings where vehicle_id=v_vehicle.id for update;
        v_before:=case when found then to_jsonb(v_sublet) else null end;
        v_result:=public.update_pdc_sublet_booking_field(v_vehicle.id,coalesce(v_sublet.version,0),'booking_date',v_date::text);
        if not coalesce((v_result->>'ok')::boolean,false) then v_failure:=v_result;raise exception 'PDC_160_FALSE';end if;
        select to_jsonb(s) into v_after from public.pdc_sublet_bookings s where s.vehicle_id=v_vehicle.id;
      else
        v_work_key:=v_action->>'work_key';v_description:=btrim(v_action->>'description');v_operation_no:='OP'||public.pdc_email_safe_positive_integer(v_action->'source_action_no',20)::text;
        select * into v_work from public.vehicle_work_items where vehicle_id=v_vehicle.id and work_key=v_work_key for update;
        v_before:=case when found then to_jsonb(v_work) else null end;
        insert into public.vehicle_work_items(vehicle_id,work_key,required,completed,completed_by,completed_at,notes,updated_at)
        values(v_vehicle.id,v_work_key,true,false,null,null,'Added from authenticated retained communication: '||v_description,v_now)
        on conflict(vehicle_id,work_key) do update set required=true,
          notes='New explicit communication work: '||v_description,updated_at=v_now;
        v_action_hash:=encode(extensions.digest(convert_to(v_action::text,'UTF8'),'sha256'),'hex');
        insert into public.pdc_authenticated_email_operation_lines(import_receipt_id,vehicle_id,source_hash,source_uid,operation_no,work_key,description,
          operation_fingerprint,estimated_hours,estimated_hours_source,job_card_number,source_row_no,source_contract)
        values(v_import.receipt_id,v_vehicle.id,v_source,v_source_uid,v_operation_no,v_work_key,v_description,v_action_hash,1.00,'ai_estimate',
          v_vehicle.job_card_number,public.pdc_email_safe_positive_integer(v_action->'source_action_no',20),'pmb-email-communications-v1') returning operation_line_id into v_line_id;
        select jsonb_build_object('work_item',to_jsonb(w),'operation_line_id',v_line_id,'estimated_hours',1.00,
          'estimated_hours_source','communication_60m_fallback','booking_created',false) into v_after
        from public.vehicle_work_items w where w.vehicle_id=v_vehicle.id and w.work_key=v_work_key;
      end if;
      v_action_hash:=encode(extensions.digest(convert_to(jsonb_build_object('source_hash',v_source,'action',v_action)::text,'UTF8'),'sha256'),'hex');
      insert into public.pdc_email_communication_action_receipts(receipt_id,source_action_no,action_type,evidence,retained_clause,retained_clause_sha256,
        requested_action,before_data,after_data,action_sha256)
      values(v_receipt_id,public.pdc_email_safe_positive_integer(v_action->'source_action_no',20),v_type,v_evidence,v_norm_evidence,
        encode(extensions.digest(convert_to(v_norm_evidence,'UTF8'),'sha256'),'hex'),v_action,v_before,v_after,v_action_hash);
      insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
      values('update','pdc_email_communication_action_receipts',v_receipt_id,v_vehicle.id,v_actor,v_email,v_before,v_after,
        jsonb_build_object('source','pdc_email_communication_160','source_hash',v_source,'action_type',v_type,'evidence',v_evidence,
          'no_booking',true,'no_location_change',true));
    end loop;
    update public.vehicles set version=version+1,updated_at=v_now,updated_by=v_actor where id=v_vehicle.id returning * into v_vehicle;
    v_result:=public.navision_backend_response(true,'communication_applied',jsonb_build_object('receipt_id',v_receipt_id,'vehicle_id',v_vehicle.id,
      'vehicle_version',v_vehicle.version,'action_count',jsonb_array_length(v_actions),'booking_created',false,'location_changed',false));
    insert into public.pdc_email_evidence_consumptions(source_hash,intake_id,attachment_id,observation_id,actor_id,vehicle_id,operation_family,request_sha256,receipt_id)
    values(v_source,p_intake_id,v_attachment.id,v_observation.observation_id,v_actor,v_vehicle.id,'communication',v_request,v_receipt_id);
    insert into public.pdc_email_communication_receipts(receipt_id,contract_version,actor_id,actor_email,intake_id,attachment_id,source_hash,
      attachment_hash,extraction_hash,server_extraction_hash,request_sha256,vehicle_id,action_count,response)
    values(v_receipt_id,'pmb-email-communications-v1',v_actor,v_email,p_intake_id,v_attachment.id,v_source,lower(v_attachment.source_hash),
      v_extraction_hash,v_server_hash,v_request,v_vehicle.id,jsonb_array_length(v_actions),v_result);
    update public.ai_email_intake set status='vehicle_updated',linked_vehicle_id=v_vehicle.id,
      processing_result=coalesce(processing_result,'{}'::jsonb)||jsonb_build_object('communication_receipt_id',v_receipt_id,
        'communication_contract','pmb-email-communications-v1','communication_applied_at',v_now) where id=p_intake_id;
  exception when others then
    if sqlerrm='PDC_160_FALSE' then return coalesce(v_failure,public.navision_backend_response(false,'communication_action_failed')); end if;
    return public.navision_backend_response(false,'atomic_communication_failed');
  end;
  return public.read_pdc_email_communication_receipt(v_receipt_id);
exception when unique_violation then
  return public.navision_backend_response(false,'communication_identity_or_replay_conflict');
end $process$;
revoke all on function public.process_pdc_email_communication(uuid,text,text,jsonb,text) from public,anon,authenticated,service_role;
grant execute on function public.process_pdc_email_communication(uuid,text,text,jsonb,text) to authenticated;
comment on function public.process_pdc_email_communication(uuid,text,text,jsonb,text) is
 'Staging-only enrolled Monitor adapter for exact provider-attested communication actions: Parts completion, Sublet booking date and unscheduled accessory work; atomic, replay-safe, no booking or location change.';

insert into supabase_migrations.schema_migrations(version,name,statements) values('160','email_communication_board_actions',array[
  'immutable retained communication/action receipts','exact active vehicle resolution and protected lifecycle guard',
  'Parts completion, exact Sublet date, approved accessory work with 60m missing-estimate fallback','authenticated Importer only; no booking/location mutation']);
commit;
