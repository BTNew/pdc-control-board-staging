-- Staging-only migration 161: provider-attested non-Navision job cards.
-- If and only if no current canonical Navision row exists, create/reuse one
-- exact operational vehicle and place a newly-created vehicle at PMB.
begin;
set local lock_timeout='10s';set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-161-non-navision-jobcards',0));
do $guard$ begin
 if not public.pdc_monitor_staging_guard()
   or not exists(select 1 from supabase_migrations.schema_migrations where version='160' and name='email_communication_board_actions')
   or to_regclass('public.pdc_provider_email_observations') is null then
  raise exception 'PDC_161_STAGING_OR_DEPENDENCY_MISMATCH' using errcode='55000';
 end if;
 if exists(select 1 from supabase_migrations.schema_migrations where version='161') then raise exception 'PDC_161_ALREADY_APPLIED';end if;
end $guard$;

alter table public.pdc_authenticated_email_operation_lines
 drop constraint if exists pdc_authenticated_email_operation_lines_source_contract_check,
 add constraint pdc_authenticated_email_operation_lines_source_contract_check
  check(source_contract is null or source_contract in('pdc_staging_workbook_reset_136','pmb-email-communications-v1','pmb-non-navision-jobcard-161'));

create table public.pdc_non_navision_jobcard_receipts(
 receipt_id uuid primary key default gen_random_uuid(),actor_id uuid not null references auth.users(id) on delete restrict,actor_email text not null,
 intake_id uuid not null unique references public.ai_email_intake(id) on delete restrict,attachment_id uuid not null references public.ai_email_attachments(id) on delete restrict,
 source_hash text not null unique check(source_hash~'^[a-f0-9]{64}$'),attachment_hash text not null check(attachment_hash~'^[a-f0-9]{64}$'),
 extraction_hash text not null check(extraction_hash~'^[a-f0-9]{64}$'),server_extraction_hash text not null check(server_extraction_hash~'^[a-f0-9]{64}$'),
 request_sha256 text not null unique check(request_sha256~'^[a-f0-9]{64}$'),canonical_import_receipt_id uuid not null unique references public.pdc_authenticated_email_import_receipts(receipt_id) on delete restrict,
 vehicle_id uuid not null references public.vehicles(id) on delete restrict,vehicle_created boolean not null,operation_count integer not null check(operation_count between 1 and 50),
 operation_lines_sha256 text not null check(operation_lines_sha256~'^[a-f0-9]{64}$'),
 response jsonb not null check(jsonb_typeof(response)='object'),created_at timestamptz not null default clock_timestamp()
);
create table public.pdc_non_navision_jobcard_source_row_receipts(
 source_row_receipt_id uuid primary key default gen_random_uuid(),
 receipt_id uuid not null references public.pdc_non_navision_jobcard_receipts(receipt_id) on delete restrict deferrable initially deferred,
 operation_line_id uuid not null unique references public.pdc_authenticated_email_operation_lines(operation_line_id) on delete restrict,
 source_row_no integer not null check(source_row_no between 1 and 50),operation_no text not null check(operation_no~'^OP([1-9]|[1-4][0-9]|50)$'),
 parser_contract text not null check(parser_contract='pmb-email-work-v2/operation-line-v1'),
 source_start integer not null check(source_start>=0),source_end integer not null check(source_end>source_start),
 retained_source_text text not null check(length(retained_source_text) between 3 and 240 and retained_source_text=btrim(retained_source_text)),
 tuple_sha256 text not null check(tuple_sha256~'^[a-f0-9]{64}$'),created_at timestamptz not null default clock_timestamp(),
 unique(receipt_id,source_row_no),unique(receipt_id,operation_no),unique(receipt_id,source_start,source_end)
);
alter table public.pdc_non_navision_jobcard_receipts enable row level security;
alter table public.pdc_non_navision_jobcard_source_row_receipts enable row level security;
revoke all on table public.pdc_non_navision_jobcard_receipts from public,anon,authenticated,service_role;
revoke all on table public.pdc_non_navision_jobcard_source_row_receipts from public,anon,authenticated,service_role;
create trigger pdc_non_navision_jobcard_receipts_immutable before update or delete on public.pdc_non_navision_jobcard_receipts
for each row execute function public.pdc_jobcard_attachment_receipt_reject_mutation();
create trigger pdc_non_navision_jobcard_source_row_receipts_immutable before update or delete on public.pdc_non_navision_jobcard_source_row_receipts
for each row execute function public.pdc_jobcard_attachment_receipt_reject_mutation();
create unique index pdc_non_navision_operation_lines_receipt_row_unique on public.pdc_authenticated_email_operation_lines(import_receipt_id,source_row_no)
where source_contract='pmb-non-navision-jobcard-161';
create trigger pdc_non_navision_operation_lines_immutable before update or delete on public.pdc_authenticated_email_operation_lines
for each row when (old.source_contract='pmb-non-navision-jobcard-161') execute function public.pdc_email_operation_line_reject_mutation();

create function public.pdc_email_safe_positive_numeric(p_value jsonb,p_max numeric) returns numeric language plpgsql immutable strict
set search_path=pg_catalog as $safe$
declare n numeric;begin
 if jsonb_typeof(p_value)<>'number' then return null;end if;n:=(p_value#>>'{}')::numeric;
 if n<=0 or n>p_max or mod(n,0.01)<>0 then return null;end if;return n;
exception when others then return null;end $safe$;
revoke all on function public.pdc_email_safe_positive_numeric(jsonb,numeric) from public,anon,authenticated,service_role;

create function public.pdc_email_jobcard_clause_matches(p_clause text,p_description text,p_hours numeric) returns boolean
language plpgsql immutable strict set search_path=pg_catalog,public as $match$
declare c text:=public.pdc_email_normalized_clause(p_clause);d text:=public.pdc_email_normalized_clause(p_description);tail text;n numeric;begin
 if c not like d||' %' then return false;end if;tail:=substr(c,length(d)+2);
 if tail!~'^[0-9]+([.][0-9]{1,2})? hours?$' then return false;end if;
 begin n:=split_part(tail,' ',1)::numeric;exception when others then return false;end;
 return n=p_hours;
end $match$;
revoke all on function public.pdc_email_jobcard_clause_matches(text,text,numeric) from public,anon,authenticated,service_role;

create function public.pdc_email_jobcard_work_key(p_description text) returns text language plpgsql immutable strict
set search_path=pg_catalog,public as $classify$
declare d text:=public.pdc_email_normalized_clause(p_description);begin
 return case
  when d~'(^| )(uhf|radio|electrical|spot ?lights?|light bar)( |$)' then 'electrical'
  when d~'(^| )(tyres?|tires?)( |$)' then 'tyre'
  when d~'(^| )(canopy|tray|fabricat)' then 'fabrication'
  when d~'(^| )(tint)( |$)' then 'tint'
  when d~'(^| )(hoist)( |$)' then 'hoist'
  when d~'(^| )(pit inspection|pit inspect)( |$)' then 'pitInspection'
  when d~'(^| )(parts?)( |$)' then 'PARTS'
  when d~'(^| )(bus ?4x4)( |$)' then 'bus4x4'
  when d~'(^| )(fit|install|long range( fuel)? tank|tow ?bar)( |$)' then 'fitting'
  else null end;
end $classify$;
revoke all on function public.pdc_email_jobcard_work_key(text) from public,anon,authenticated,service_role;

create function public.read_pdc_non_navision_jobcard_receipt(p_receipt_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,extensions as $read$
declare v_actor uuid:=auth.uid();v_r public.pdc_non_navision_jobcard_receipts%rowtype;v_lines jsonb;v_digest text;begin
 if not public.pdc_monitor_staging_guard() or v_actor is null then return public.navision_backend_response(false,'unauthorized');end if;
 select * into v_r from public.pdc_non_navision_jobcard_receipts where receipt_id=p_receipt_id and actor_id=v_actor;
 if not found then return public.navision_backend_response(false,'receipt_not_found');end if;
 select coalesce(jsonb_agg(jsonb_build_object('description',ol.description,'estimated_hours',ol.estimated_hours,'operation_no',ol.operation_no,
  'source_row_no',ol.source_row_no,'work_key',ol.work_key,'parser_contract',sr.parser_contract,'source_start',sr.source_start,
  'source_end',sr.source_end,'retained_source_text',sr.retained_source_text) order by ol.source_row_no),'[]'::jsonb)
 into v_lines from public.pdc_authenticated_email_operation_lines ol
 join public.pdc_non_navision_jobcard_source_row_receipts sr on sr.operation_line_id=ol.operation_line_id and sr.receipt_id=v_r.receipt_id
 where ol.import_receipt_id=v_r.canonical_import_receipt_id and ol.vehicle_id=v_r.vehicle_id and ol.source_hash=v_r.source_hash
   and ol.source_contract='pmb-non-navision-jobcard-161'
   and sr.source_row_no=ol.source_row_no and sr.operation_no=ol.operation_no
   and sr.tuple_sha256=encode(extensions.digest(convert_to(jsonb_build_object('parser_contract',sr.parser_contract,
    'source_start',sr.source_start,'source_end',sr.source_end,'retained_source_text',sr.retained_source_text,
    'source_row_no',ol.source_row_no,'operation_no',ol.operation_no,'work_key',ol.work_key,'description',ol.description,
    'estimated_hours',ol.estimated_hours)::text,'UTF8'),'sha256'),'hex');
 v_digest:=encode(extensions.digest(convert_to(v_lines::text,'UTF8'),'sha256'),'hex');
 if jsonb_array_length(v_lines)<>v_r.operation_count or v_digest<>v_r.operation_lines_sha256 then
  return public.navision_backend_response(false,'non_navision_receipt_drift');
 end if;
 return public.navision_backend_response(true,'non_navision_jobcard_receipt',jsonb_build_object('receipt_id',v_r.receipt_id,'vehicle_id',v_r.vehicle_id,
  'vehicle_created',v_r.vehicle_created,'operation_count',v_r.operation_count,'operation_lines',v_lines,'initial_location',case when v_r.vehicle_created then 'PMB' else null end,
  'booking_created',false,'completion_created',false));
end $read$;
revoke all on function public.read_pdc_non_navision_jobcard_receipt(uuid) from public,anon,authenticated,service_role;
grant execute on function public.read_pdc_non_navision_jobcard_receipt(uuid) to authenticated;

create function public.process_pdc_non_navision_jobcard(
 p_intake_id uuid,p_expected_source_hash text,p_extraction_hash text,p_extraction jsonb,p_actor text
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions set statement_timeout='180s' as $process$
declare
 v_actor uuid:=auth.uid();v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));v_source text:=lower(btrim(coalesce(p_expected_source_hash,'')));
 v_xhash text:=lower(btrim(coalesce(p_extraction_hash,'')));v_payload jsonb:=coalesce(p_extraction,'null'::jsonb);v_server text;v_request text;
 v_intake public.ai_email_intake%rowtype;v_attachment public.ai_email_attachments%rowtype;v_observation public.pdc_provider_email_observations%rowtype;
 v_r public.pdc_non_navision_jobcard_receipts%rowtype;v_import public.pdc_authenticated_email_import_receipts%rowtype;v_vehicle public.vehicles%rowtype;
 v_email_vehicle jsonb;v_lines jsonb;v_required jsonb;v_line jsonb;v_stock text;v_vin text;v_job text;v_candidates uuid[];
 v_stock_candidates uuid[];v_vin_candidates uuid[];v_job_candidates uuid[];v_stock_navision uuid[];v_vin_navision uuid[];v_job_navision uuid[];
 v_attachment_id uuid;v_source_clause text;v_source_start integer;v_source_end integer;v_tuple_hash text;
 v_created boolean:=false;v_receipt_id uuid:=gen_random_uuid();v_source_uid text;v_work_key text;v_work public.vehicle_work_items%rowtype;
 v_operation_id uuid;v_fingerprint text;v_result jsonb;v_now timestamptz:=clock_timestamp();v_make text;v_description text;v_retained text;v_lines_digest text;
begin
 if not public.pdc_monitor_staging_guard() or v_actor is null or v_email='' or lower(btrim(coalesce(p_actor,'')))<>'pdc-monitor'
   or v_source!~'^[a-f0-9]{64}$' or v_xhash!~'^[a-f0-9]{64}$' or jsonb_typeof(v_payload)<>'object'
   or (select array_agg(k order by k) from jsonb_object_keys(v_payload) k) is distinct from array[
    'authentication','canonical_attachment_id','canonical_document_hash','contract_version','email_vehicle','operation_lines','required_work']::text[]
   or v_payload->>'contract_version'<>'pmb-email-work-v2'
   or jsonb_typeof(v_payload->'authentication')<>'object'
   or coalesce(v_payload->>'canonical_attachment_id','')!~'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
   or lower(coalesce(v_payload->>'canonical_document_hash',''))!~'^[a-f0-9]{64}$'
   or jsonb_typeof(v_payload->'email_vehicle')<>'object'
   or jsonb_typeof(v_payload->'operation_lines')<>'array' or jsonb_array_length(v_payload->'operation_lines') not between 1 and 50
   or jsonb_typeof(v_payload->'required_work')<>'array' or jsonb_array_length(v_payload->'required_work') not between 1 and 10 then
  return public.navision_backend_response(false,'invalid_non_navision_extraction');
 end if;
 v_attachment_id:=public.pdc_email_safe_uuid(v_payload->>'canonical_attachment_id');
 if v_attachment_id is null then return public.navision_backend_response(false,'invalid_non_navision_extraction');end if;
 perform 1 from public.pdc_user_roles r where r.auth_user_id=v_actor and lower(r.email)=v_email and r.role='importer' and r.active and r.account_status='approved' for share;
 if not found then return public.navision_backend_response(false,'unauthorized');end if;
 perform 1 from public.pdc_monitor_stage_activation_writers w where w.user_id=v_actor and w.active and w.revoked_at is null for share;
 if not found then return public.navision_backend_response(false,'unauthorized');end if;
 v_email_vehicle:=v_payload->'email_vehicle';v_lines:=v_payload->'operation_lines';v_required:=v_payload->'required_work';
 if (select array_agg(k order by k) from jsonb_object_keys(v_email_vehicle) k) is distinct from array[
   'cancelled','conflicts','customer_name','eta_to_kewdale','job_card_number','registration','stock_numbers','toyota_order_number','vehicle_description','vins']::text[]
   or v_email_vehicle->'cancelled'<>'false'::jsonb or v_email_vehicle->'conflicts'<>'[]'::jsonb
   or jsonb_typeof(v_email_vehicle->'stock_numbers')<>'array' or jsonb_array_length(v_email_vehicle->'stock_numbers')>1
   or jsonb_typeof(v_email_vehicle->'vins')<>'array' or jsonb_array_length(v_email_vehicle->'vins')>1
   or exists(select 1 from jsonb_array_elements(v_email_vehicle->'stock_numbers') x where jsonb_typeof(x)<>'string')
   or exists(select 1 from jsonb_array_elements(v_email_vehicle->'vins') x where jsonb_typeof(x)<>'string')
   or jsonb_typeof(v_email_vehicle->'job_card_number')<>'string' then
  return public.navision_backend_response(false,'non_navision_vehicle_identity_invalid');
 end if;
 v_stock:=nullif(public.normalize_vehicle_stock_number(v_email_vehicle->'stock_numbers'->>0),'');
 v_vin:=nullif(public.normalize_vehicle_vin(v_email_vehicle->'vins'->>0),'');v_job:=nullif(upper(btrim(v_email_vehicle->>'job_card_number')),'');
 if v_job is null or length(v_job)>80 or v_job~'[[:cntrl:]]' or (v_stock is null and v_vin is null)
   or (v_stock is not null and not public.is_real_vehicle_stock_number(v_stock)) or (v_vin is not null and not public.is_valid_vehicle_vin(v_vin)) then
  return public.navision_backend_response(false,'non_navision_vehicle_identity_invalid');
 end if;
 if exists(select 1 from jsonb_array_elements(v_lines) with ordinality x(a,n) where jsonb_typeof(a)<>'object'
   or (select array_agg(k order by k) from jsonb_object_keys(a) k) is distinct from array['description','estimated_hours','operation_no','source_row_no','work_key']::text[]
   or a->>'operation_no' is distinct from 'OP'||n::text
   or public.pdc_email_safe_positive_integer(a->'source_row_no',50) is distinct from n::integer
   or coalesce(a->>'work_key','') not in('bus4x4','tint','hoist','fitting','fabrication','electrical','tyre','pitInspection','PARTS')
   or public.pdc_email_jobcard_work_key(a->>'description') is distinct from a->>'work_key'
   or length(coalesce(a->>'description','')) not between 1 and 180 or a->>'description' is distinct from btrim(a->>'description')
   or (a->>'description')~'[[:cntrl:]]'
   or public.pdc_email_safe_positive_numeric(a->'estimated_hours',999.99) is null)
   or exists(select 1 from jsonb_array_elements(v_required) x where jsonb_typeof(x)<>'string')
   or jsonb_array_length(v_lines)<>(select count(distinct public.pdc_email_safe_positive_integer(a->'source_row_no',50)) from jsonb_array_elements(v_lines) a)
   or (select array_agg(distinct a->>'work_key' order by a->>'work_key') from jsonb_array_elements(v_lines) a)
      is distinct from (select array_agg(x order by x) from jsonb_array_elements_text(v_required) x) then
  return public.navision_backend_response(false,'non_navision_operation_lines_invalid');
 end if;
 select * into v_intake from public.ai_email_intake where id=p_intake_id for update;if not found then return public.navision_backend_response(false,'intake_not_found');end if;
 select * into v_attachment from public.ai_email_attachments where id=v_attachment_id and intake_id=p_intake_id for share;
 if not found then return public.navision_backend_response(false,'attachment_not_found');end if;
 select * into v_observation from public.pdc_provider_email_observations where intake_id=p_intake_id and attachment_id=v_attachment.id for share;
 if not found or v_observation.parent_source_hash<>v_source or v_observation.attachment_source_hash<>lower(v_payload->>'canonical_document_hash')
   or v_observation.authentication is distinct from v_payload->'authentication' or lower(v_intake.source_hash)<>v_source
   or lower(v_attachment.source_hash)<>lower(v_payload->>'canonical_document_hash')
   or v_attachment.text_extraction_status<>'extracted' or nullif(btrim(coalesce(v_attachment.extracted_text,'')),'') is null
   or length(v_attachment.extracted_text)>500000 then
  return public.navision_backend_response(false,'non_navision_evidence_binding_failed');
 end if;
 perform pg_advisory_xact_lock(hashtextextended('pdc-non-navision-jobcard-161:'||p_intake_id::text,0));
 v_server:=encode(extensions.digest(convert_to(v_payload::text,'UTF8'),'sha256'),'hex');
 v_request:=encode(extensions.digest(convert_to(jsonb_build_object('contract','161.2','actor_id',v_actor,'intake_id',p_intake_id,'source',v_source,
  'extraction_hash',v_xhash,'server_hash',v_server,'payload',v_payload)::text,'UTF8'),'sha256'),'hex');
 select * into v_r from public.pdc_non_navision_jobcard_receipts where intake_id=p_intake_id;
 if found then
  if v_r.actor_id<>v_actor or v_r.source_hash<>v_source or v_r.extraction_hash<>v_xhash or v_r.server_extraction_hash<>v_server
     or v_r.request_sha256<>v_request then return public.navision_backend_response(false,'non_navision_replay_conflict');end if;
  return public.read_pdc_non_navision_jobcard_receipt(v_r.receipt_id);
 end if;
 if v_intake.duplicate_of is not null or v_intake.received_at is null or v_intake.received_at>clock_timestamp()+interval '5 minutes'
   or v_intake.received_at<clock_timestamp()-interval '30 days'
   or not exists(select 1 from public.pdc_monitor_exact_sender_enrollments e where e.active and e.sender_sha256=
     encode(extensions.digest(convert_to(lower(btrim(v_intake.sender_email)),'UTF8'),'sha256'),'hex')) then
  return public.navision_backend_response(false,'non_navision_evidence_binding_failed');
 end if;
 v_retained:=public.pdc_email_normalized_clause(v_attachment.extracted_text);
 if position(lower(v_job) in v_retained)=0 or (v_stock is not null and position(lower(v_stock) in v_retained)=0)
    or (v_vin is not null and position(lower(v_vin) in regexp_replace(v_retained,'[^a-z0-9]','','g'))=0)
    or exists(select 1 from jsonb_array_elements(v_lines) a where
      (select count(*) from regexp_split_to_table(v_attachment.extracted_text,
        E'[!?](?=\\s|$)|\\.(?=\\s|$)|\\r?\\n') clause
       where public.pdc_email_jobcard_clause_matches(clause,a->>'description',public.pdc_email_safe_positive_numeric(a->'estimated_hours',999.99)))<>1) then
  return public.navision_backend_response(false,'non_navision_retained_text_mismatch');
 end if;
 perform pg_advisory_xact_lock(hashtextextended('pdc-email-evidence-consumption:'||v_source,0));
 if exists(select 1 from public.pdc_email_evidence_consumptions c where c.source_hash=v_source)
    or exists(select 1 from public.pdc_authenticated_email_import_receipts r where r.source_hash=v_source) then
  return public.navision_backend_response(false,'non_navision_evidence_already_consumed');
 end if;
 perform pg_advisory_xact_lock(hashtextextended('navision-backend-store',0));
 select coalesce(array_agg(distinct b.id order by b.id),'{}'::uuid[]) into v_stock_navision
 from public.navision_backend_records b where b.source_system='microsoft_navision' and b.dealer_code in('14450','37047')
  and b.is_current and b.record_status='current' and v_stock is not null
  and public.normalize_vehicle_stock_number(coalesce(b.normalized_data->>'batch',b.normalized_data->>'stock_number'))=v_stock;
 select coalesce(array_agg(distinct b.id order by b.id),'{}'::uuid[]) into v_vin_navision
 from public.navision_backend_records b where b.source_system='microsoft_navision' and b.dealer_code in('14450','37047')
  and b.is_current and b.record_status='current' and v_vin is not null
  and public.normalize_vehicle_vin(coalesce(b.normalized_data->>'vin',b.normalized_data->>'vin_number'))=v_vin;
 select coalesce(array_agg(distinct b.id order by b.id),'{}'::uuid[]) into v_job_navision
 from public.navision_backend_records b where b.source_system='microsoft_navision' and b.dealer_code in('14450','37047')
  and b.is_current and b.record_status='current' and v_job is not null
  and upper(btrim(coalesce(b.normalized_data->>'job_card_number',b.normalized_data->>'jobcard_number',b.normalized_data->>'job_card','')))=v_job;
 if cardinality(v_stock_navision)>1 or cardinality(v_vin_navision)>1 or cardinality(v_job_navision)>1 then
  return public.navision_backend_response(false,'non_navision_navision_identity_ambiguous');
 end if;
 if cardinality(v_stock_navision)>0 or cardinality(v_vin_navision)>0 or cardinality(v_job_navision)>0 then
  return public.navision_backend_response(false,'navision_record_requires_canonical_path');
 end if;
 select coalesce(array_agg(distinct id order by id),'{}'::uuid[]) into v_stock_candidates from (
  select v.id from public.vehicles v where v.deleted_at is null and v_stock is not null and v.stock_number_normalized=v_stock
  union all select a.vehicle_id from public.vehicle_aliases a where a.active and v_stock is not null and a.alias_type_normalized='stock_number' and a.normalized_alias_value=v_stock) q;
 select coalesce(array_agg(distinct id order by id),'{}'::uuid[]) into v_vin_candidates from (
  select v.id from public.vehicles v where v.deleted_at is null and v_vin is not null and v.vin_normalized=v_vin
  union all select a.vehicle_id from public.vehicle_aliases a where a.active and v_vin is not null and a.alias_type_normalized='vin' and a.normalized_alias_value=v_vin) q;
 select coalesce(array_agg(distinct id order by id),'{}'::uuid[]) into v_job_candidates from (
  select v.id from public.vehicles v where v.deleted_at is null and upper(btrim(coalesce(v.job_card_number,'')))=v_job
  union all select a.vehicle_id from public.vehicle_aliases a where a.active and a.alias_type_normalized in('job_card','job_card_number') and upper(btrim(a.normalized_alias_value))=v_job) q;
 if cardinality(v_stock_candidates)>1 or cardinality(v_vin_candidates)>1 or cardinality(v_job_candidates)>1 then
  return public.navision_backend_response(false,'non_navision_operational_identity_ambiguous');
 end if;
 if cardinality(v_stock_candidates)+cardinality(v_vin_candidates)+cardinality(v_job_candidates)=0 then
  v_candidates:='{}'::uuid[];
 elsif (v_stock is not null and cardinality(v_stock_candidates)<>1)
    or (v_vin is not null and cardinality(v_vin_candidates)<>1) or cardinality(v_job_candidates)<>1 then
  return public.navision_backend_response(false,'non_navision_vehicle_identity_disagreement');
 else
  v_candidates:=v_job_candidates;
  if (v_stock is not null and v_stock_candidates[1]<>v_candidates[1])
     or (v_vin is not null and v_vin_candidates[1]<>v_candidates[1]) then
   return public.navision_backend_response(false,'non_navision_vehicle_identity_disagreement');
  end if;
 end if;
 if cardinality(v_candidates)=1 then
  select * into v_vehicle from public.vehicles where id=v_candidates[1] for update;
  if v_vehicle.lifecycle_state<>'active' or v_vehicle.deleted_at is not null or v_vehicle.board_purged_at is not null or v_vehicle.rft_collected_at is not null
    or upper(btrim(coalesce(v_vehicle.current_location,'')))='COMPLETED' or not v_vehicle.visible_on_board then
   return public.navision_backend_response(false,'non_navision_operational_vehicle_protected');
  end if;
  if upper(btrim(coalesce(v_vehicle.job_card_number,''))) is distinct from v_job
    or (v_stock is not null and v_vehicle.stock_number_normalized is distinct from v_stock
      and not exists(select 1 from public.vehicle_aliases a where a.vehicle_id=v_vehicle.id and a.active and a.alias_type_normalized='stock_number' and a.normalized_alias_value=v_stock))
    or (v_vin is not null and v_vehicle.vin_normalized is distinct from v_vin
      and not exists(select 1 from public.vehicle_aliases a where a.vehicle_id=v_vehicle.id and a.active and a.alias_type_normalized='vin' and a.normalized_alias_value=v_vin)) then
   return public.navision_backend_response(false,'non_navision_vehicle_identity_disagreement');
  end if;
  perform 1 from public.vehicle_work_items w where w.vehicle_id=v_vehicle.id and w.work_key in
    (select x from jsonb_array_elements_text(v_required) x) for update;
  if exists(select 1 from public.vehicle_work_items w where w.vehicle_id=v_vehicle.id and w.completed and w.work_key in
    (select x from jsonb_array_elements_text(v_required) x)) then
   return public.navision_backend_response(false,'non_navision_completed_work_protected');
  end if;
  update public.vehicles set job_card_number=coalesce(job_card_number,v_job),customer_name=coalesce(customer_name,nullif(btrim(v_email_vehicle->>'customer_name'),'')),
   vehicle_description=coalesce(vehicle_description,nullif(btrim(v_email_vehicle->>'vehicle_description'),'')),registration=coalesce(registration,nullif(btrim(v_email_vehicle->>'registration'),'')),
   version=version+1,updated_at=v_now,updated_by=v_actor where id=v_vehicle.id returning * into v_vehicle;
 else
  v_description:=nullif(btrim(v_email_vehicle->>'vehicle_description'),'');
  v_make:=case when v_description~*'^Nissan\M' then 'Nissan' when v_description~*'^Isuzu\M' then 'Isuzu' when v_description~*'^Toyota\M' then 'Toyota' else null end;
  insert into public.vehicles(permanent_vehicle_id,stock_number,vin,toyota_order_number,job_card_number,customer_name,vehicle_description,make,model,registration,
   lifecycle_state,visible_on_board,current_location,pmb_stage,source_system,source_batch_id,source_record_id,source_payload,created_by,updated_by)
  values('EMAIL-'||substring(v_source,1,32),v_stock,v_vin,nullif(btrim(v_email_vehicle->>'toyota_order_number'),''),v_job,
   nullif(btrim(v_email_vehicle->>'customer_name'),''),v_description,v_make,v_description,nullif(btrim(v_email_vehicle->>'registration'),''),
   'active',true,'PMB','UNALLOCATED','authenticated_email','pdc-monitor',p_intake_id::text,
   jsonb_build_object('contract','pmb-non-navision-jobcard-161','source_hash',v_source,'attachment_hash',lower(v_attachment.source_hash)),v_actor,v_actor)
  returning * into v_vehicle;v_created:=true;
 end if;
 v_source_uid:='pdc-jc-161:'||substring(v_source,1,64);
 v_result:=public.navision_backend_response(true,'non_navision_jobcard_imported',jsonb_build_object('vehicle_id',v_vehicle.id,'vehicle_created',v_created,
  'current_location',v_vehicle.current_location,'operation_count',jsonb_array_length(v_lines),'booking_created',false,'completion_created',false));
 insert into public.pdc_authenticated_email_import_receipts(actor_id,idempotency_key,request_hash,source_hash,evidence_hash,source_uid,sender_address,source_received_at,
  stock_number,vin,backend_record_id,backend_record_version,vehicle_id,identity_source,required_work,response)
 values(v_actor,'pdc-email-import-'||substring(v_request,1,64),v_request,v_source,lower(v_attachment.source_hash),v_source_uid,lower(v_intake.sender_email),v_intake.received_at,
  v_stock,v_vin,null,null,v_vehicle.id,case when v_created then 'email_new' else 'operational_exact' end,v_required,v_result) returning * into v_import;
 for v_line in select value from jsonb_array_elements(v_lines) order by public.pdc_email_safe_positive_integer(value->'source_row_no',50) loop
  v_work_key:=v_line->>'work_key';v_fingerprint:=encode(extensions.digest(convert_to(jsonb_build_object('source',v_source,'line',v_line)::text,'UTF8'),'sha256'),'hex');
  select btrim(clause),strpos(v_attachment.extracted_text,btrim(clause))-1,
    strpos(v_attachment.extracted_text,btrim(clause))-1+length(btrim(clause))
  into strict v_source_clause,v_source_start,v_source_end
  from regexp_split_to_table(v_attachment.extracted_text,E'[!?](?=\\s|$)|\\.(?=\\s|$)|\\r?\\n') clause
  where public.pdc_email_jobcard_clause_matches(clause,v_line->>'description',public.pdc_email_safe_positive_numeric(v_line->'estimated_hours',999.99));
  insert into public.pdc_authenticated_email_operation_lines(import_receipt_id,vehicle_id,source_hash,source_uid,operation_no,work_key,description,operation_fingerprint,
   estimated_hours,estimated_hours_source,job_card_number,source_row_no,source_contract)
  values(v_import.receipt_id,v_vehicle.id,v_source,v_source_uid,v_line->>'operation_no',v_work_key,v_line->>'description',v_fingerprint,
   public.pdc_email_safe_positive_numeric(v_line->'estimated_hours',999.99),'job_card',v_job,
   public.pdc_email_safe_positive_integer(v_line->'source_row_no',50),'pmb-non-navision-jobcard-161') returning operation_line_id into v_operation_id;
  select encode(extensions.digest(convert_to(jsonb_build_object('parser_contract','pmb-email-work-v2/operation-line-v1',
    'source_start',v_source_start,'source_end',v_source_end,'retained_source_text',v_source_clause,
    'source_row_no',ol.source_row_no,'operation_no',ol.operation_no,
    'work_key',ol.work_key,'description',ol.description,'estimated_hours',ol.estimated_hours)::text,'UTF8'),'sha256'),'hex')
  into strict v_tuple_hash from public.pdc_authenticated_email_operation_lines ol where ol.operation_line_id=v_operation_id;
  insert into public.pdc_non_navision_jobcard_source_row_receipts(receipt_id,operation_line_id,source_row_no,operation_no,parser_contract,
    source_start,source_end,retained_source_text,tuple_sha256)
  values(v_receipt_id,v_operation_id,public.pdc_email_safe_positive_integer(v_line->'source_row_no',50),v_line->>'operation_no',
    'pmb-email-work-v2/operation-line-v1',v_source_start,v_source_end,v_source_clause,v_tuple_hash);
  insert into public.vehicle_work_items(vehicle_id,work_key,required,completed,notes,updated_at)
  values(v_vehicle.id,v_work_key,true,false,'Required by retained non-Navision job card '||v_job,v_now)
  on conflict(vehicle_id,work_key) do update set required=true,updated_at=v_now;
 end loop;
 select encode(extensions.digest(convert_to(coalesce(jsonb_agg(jsonb_build_object('description',ol.description,'estimated_hours',ol.estimated_hours,
  'operation_no',ol.operation_no,'source_row_no',ol.source_row_no,'work_key',ol.work_key,'parser_contract',sr.parser_contract,
  'source_start',sr.source_start,'source_end',sr.source_end,'retained_source_text',sr.retained_source_text) order by ol.source_row_no),'[]'::jsonb)::text,'UTF8'),'sha256'),'hex')
 into v_lines_digest from public.pdc_authenticated_email_operation_lines ol
 join public.pdc_non_navision_jobcard_source_row_receipts sr on sr.operation_line_id=ol.operation_line_id and sr.receipt_id=v_receipt_id
 where ol.import_receipt_id=v_import.receipt_id and ol.source_contract='pmb-non-navision-jobcard-161';
 if exists(select 1 from jsonb_array_elements_text(v_required) x where x='PARTS') then
  insert into public.vehicle_parts_updates(vehicle_id,parts_required,updated_by,updated_at) values(v_vehicle.id,true,v_actor,v_now);
 end if;
 insert into public.pdc_email_evidence_consumptions(source_hash,intake_id,attachment_id,observation_id,actor_id,vehicle_id,operation_family,request_sha256,receipt_id)
 values(v_source,p_intake_id,v_attachment.id,v_observation.observation_id,v_actor,v_vehicle.id,'non_navision_jobcard',v_request,v_receipt_id);
 insert into public.pdc_non_navision_jobcard_receipts(receipt_id,actor_id,actor_email,intake_id,attachment_id,source_hash,attachment_hash,extraction_hash,
  server_extraction_hash,request_sha256,canonical_import_receipt_id,vehicle_id,vehicle_created,operation_count,operation_lines_sha256,response)
 values(v_receipt_id,v_actor,v_email,p_intake_id,v_attachment.id,v_source,lower(v_attachment.source_hash),v_xhash,v_server,v_request,v_import.receipt_id,
  v_vehicle.id,v_created,jsonb_array_length(v_lines),v_lines_digest,v_result);
 insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
 values(case when v_created then 'insert'::public.audit_action else 'update'::public.audit_action end,'pdc_non_navision_jobcard_receipts',v_receipt_id,v_vehicle.id,
  v_actor,v_email,null,to_jsonb(v_vehicle),jsonb_build_object('source','pdc_non_navision_jobcard_161','source_hash',v_source,'vehicle_created',v_created,
   'initial_location',case when v_created then 'PMB' else null end,'no_booking',true));
 update public.ai_email_intake set status=(case when v_created then 'vehicle_created' else 'vehicle_updated' end)::public.ai_intake_status,linked_vehicle_id=v_vehicle.id,
  processing_result=coalesce(processing_result,'{}'::jsonb)||jsonb_build_object('non_navision_jobcard_receipt_id',v_receipt_id,'processed_at',v_now) where id=p_intake_id;
 return public.read_pdc_non_navision_jobcard_receipt(v_receipt_id);
exception when unique_violation then return public.navision_backend_response(false,'non_navision_identity_or_receipt_conflict');
end $process$;
revoke all on function public.process_pdc_non_navision_jobcard(uuid,text,text,jsonb,text) from public,anon,authenticated,service_role;
grant execute on function public.process_pdc_non_navision_jobcard(uuid,text,text,jsonb,text) to authenticated;
comment on function public.process_pdc_non_navision_jobcard(uuid,text,text,jsonb,text) is
 'Staging-only provider-attested fallback when zero current Navision rows exist; creates/reuses one exact active Board vehicle, new vehicles at PMB, imports job-card lines, creates no booking.';
insert into supabase_migrations.schema_migrations(version,name,statements) values('161','non_navision_jobcard_board_creation',array[
 'zero-current-Navision fallback only','exact stock/VIN operational identity and protected lifecycle guard','new used/Nissan/Isuzu/non-Navision job-card vehicles at PMB',
 'canonical operation lines and required work; no booking or completion']);
commit;
