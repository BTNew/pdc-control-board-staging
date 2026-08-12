-- Staging-only migration 233: attachment-atomic retained UIDVALIDITY 1 / UID 478 successor.
-- This migration provisions contracts only.  It performs no mailbox access or replay.
begin;
set local lock_timeout='10s';
set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-233-uid478-attachment-atomic',0));

do $guard$
begin
  if to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or not exists(select 1 from supabase_migrations.schema_migrations where version='232')
     or exists(select 1 from supabase_migrations.schema_migrations where version ~ '^[0-9]+$' and version::integer>232)
     or exists(select 1 from supabase_migrations.schema_migrations where version='233')
     or to_regclass('public.pdc_provider_email_observations') is null
     or to_regprocedure('public.pdc_monitor_actor_scope()') is null then
    raise exception 'PDC_233_STAGING_OR_LEDGER_MISMATCH' using errcode='55000';
  end if;
end $guard$;

-- Migration 159 made message-level columns unique because its caller consumed one
-- attachment. Preserve all rows and callers while generalising identity to attachment.
alter table public.pdc_provider_email_observations
  drop constraint pdc_provider_email_observations_intake_id_key,
  drop constraint pdc_provider_email_observations_parent_source_hash_key,
  drop constraint pdc_provider_email_observations_provider_message_id_key,
  add constraint pdc_provider_email_observations_intake_attachment_key unique(intake_id,attachment_id);

-- Retain the parent message hash as evidence, but use an immutable
-- attachment-derived digest as canonical source identity so all four attachments
-- can pass older unique source-hash constraints independently.
alter table public.pdc_jobcard_attachment_import_receipts
  drop constraint pdc_jobcard_attachment_import_receipts_parent_source_hash_key,
  add column canonical_source_hash text check(canonical_source_hash is null or canonical_source_hash~'^[a-f0-9]{64}$'),
  add constraint pdc_jobcard_attachment_import_receipts_canonical_source_hash_key unique(canonical_source_hash);
-- Migration-159 receipts are immutable evidence. Historical rows remain byte-for-byte
-- untouched and continue to resolve through parent_source_hash; only new 233 imports
-- populate the attachment-derived canonical_source_hash.

do $generalise_canonical_import$
declare d text;
begin
  select pg_get_functiondef('public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)'::regprocedure) into d;
  if position($decl$v_parent_hash text:=lower(btrim(coalesce(p_expected_parent_hash,'')));$decl$ in d)=0
     or position('v_submit:=public.submit_pdc_ai_intake_observation(' in d)=0 then
    raise exception 'PDC_233_CANONICAL_IMPORT_FUNCTION_DRIFT' using errcode='55000';
  end if;
  d:=replace(d,$decl$v_parent_hash text:=lower(btrim(coalesce(p_expected_parent_hash,'')));$decl$,
    $newdecl$v_parent_hash text:=lower(btrim(coalesce(p_expected_parent_hash,'')));
  v_canonical_source_hash text;$newdecl$);
  d:=replace(d,'v_source_uid:=''pdc-jc-159:''||encode(extensions.digest(convert_to(',
    'v_canonical_source_hash:=encode(extensions.digest(convert_to(jsonb_build_object(''contract_version'',''233.1'',''intake_id'',p_intake_id,''attachment_id'',p_attachment_id,''parent_source_hash'',v_parent_hash,''attachment_source_hash'',v_attachment_hash)::text,''UTF8''),''sha256''),''hex'');'||E'\n  '||'v_source_uid:=''pdc-jc-159:''||encode(extensions.digest(convert_to(');
  d:=replace(d,'v_submit:=public.submit_pdc_ai_intake_observation('||E'\n      v_parent_hash,v_attachment_hash,v_source_uid','v_submit:=public.submit_pdc_ai_intake_observation('||E'\n      v_canonical_source_hash,v_attachment_hash,v_source_uid');
  d:=replace(d,'v_vehicle_result:=public.import_pdc_authenticated_vehicle_email('||E'\n      v_idempotency_key,v_parent_hash,v_attachment_hash,v_source_uid','v_vehicle_result:=public.import_pdc_authenticated_vehicle_email('||E'\n      v_idempotency_key,v_canonical_source_hash,v_attachment_hash,v_source_uid');
  d:=replace(d,'public.import_pdc_authenticated_email_operations_with_hours('||E'\n      v_parent_hash,v_source_uid','public.import_pdc_authenticated_email_operations_with_hours('||E'\n      v_canonical_source_hash,v_source_uid');
  d:=replace(d,'where actor_id=v_actor and source_hash=v_parent_hash and source_uid=v_source_uid for share;','where actor_id=v_actor and source_hash=v_canonical_source_hash and source_uid=v_source_uid for share;');
  d:=replace(d,'on ol.source_hash=v_parent_hash and ol.source_uid=v_source_uid','on ol.source_hash=v_canonical_source_hash and ol.source_uid=v_source_uid');
  d:=replace(d,'where source_hash=v_parent_hash)<>v_operation_count','where source_hash=v_canonical_source_hash)<>v_operation_count');
  d:=replace(d,'attachment_source_hash,attachment_size_bytes,attachment_content_type,source_uid,proposal_id','attachment_source_hash,canonical_source_hash,attachment_size_bytes,attachment_content_type,source_uid,proposal_id');
  d:=replace(d,'v_attachment_hash,v_attachment.size_bytes,lower(v_attachment.content_type),v_source_uid,v_proposal_id','v_attachment_hash,v_canonical_source_hash,v_attachment.size_bytes,lower(v_attachment.content_type),v_source_uid,v_proposal_id');
  d:=replace(d,'where source_hash=v_parent_hash and operation_no=v_item->>''operation_no'';','where source_hash=v_canonical_source_hash and operation_no=v_item->>''operation_no'';');
  d:=replace(d,$old_status$v_intake.status in ('duplicate_detected','failed','ignored','vehicle_created','vehicle_updated')$old_status$,
    $new_status$(v_intake.status in ('duplicate_detected','failed','ignored','vehicle_created') or (v_intake.status='vehicle_updated' and v_intake.processing_result->>'uid478_attachment_atomic_contract' is distinct from '233.1'))$new_status$);
  d:=replace(d,$old_result$'jobcard_attachment_imported_at',clock_timestamp())$old_result$,
    $new_result$'jobcard_attachment_imported_at',clock_timestamp(),'uid478_attachment_atomic_contract','233.1')$new_result$);
  execute d;
end $generalise_canonical_import$;

do $generalise_canonical_read$
declare d text;
begin
  select pg_get_functiondef('public.read_pdc_jobcard_attachment_import_receipt(uuid)'::regprocedure) into d;
  if position('ol.source_hash=v_receipt.parent_source_hash' in d)=0 or position('ir.source_hash=v_receipt.parent_source_hash' in d)=0 or position('p.source_hash=v_receipt.parent_source_hash' in d)=0 then
    raise exception 'PDC_233_CANONICAL_READ_FUNCTION_DRIFT' using errcode='55000';
  end if;
  d:=replace(d,'ol.source_hash=v_receipt.parent_source_hash','ol.source_hash=v_receipt.canonical_source_hash');
  d:=replace(d,'ir.source_hash=v_receipt.parent_source_hash','ir.source_hash=v_receipt.canonical_source_hash');
  d:=replace(d,'p.source_hash=v_receipt.parent_source_hash','p.source_hash=v_receipt.canonical_source_hash');
  d:=replace(d,'''parent_source_hash'',v_receipt.parent_source_hash,''attachment_source_hash'',v_receipt.attachment_source_hash','''parent_source_hash'',v_receipt.parent_source_hash,''canonical_source_hash'',v_receipt.canonical_source_hash,''attachment_source_hash'',v_receipt.attachment_source_hash');
  execute d;
end $generalise_canonical_read$;

-- Patch the current Migration177 implementation rather than replacing its security,
-- authentication, sender, mailbox, and caller-compatible contract.
do $generalise_observation$
declare d text; old_lock text; new_lock text; old_lookup text; new_lookup text;
begin
  select pg_get_functiondef('public.attest_pdc_provider_email_observation(uuid,uuid,text,text,text,text,jsonb)'::regprocedure) into d;
  old_lock:=$old$'pdc-provider-email-observation-177:'||p_intake_id::text$old$;
  new_lock:=$new$'pdc-provider-email-observation-233:'||p_intake_id::text||':'||p_attachment_id::text$new$;
  old_lookup:='where intake_id=p_intake_id;';
  new_lookup:='where intake_id=p_intake_id and attachment_id=p_attachment_id;';
  if position(old_lock in d)=0 or position(old_lookup in d)=0 then
    raise exception 'PDC_233_OBSERVATION_FUNCTION_DRIFT' using errcode='55000';
  end if;
  execute replace(replace(d,old_lock,new_lock),old_lookup,new_lookup);
end $generalise_observation$;

create table public.pdc_uid478_attachment_attempt_receipts(
  attempt_receipt_id uuid primary key default gen_random_uuid(),
  contract_version text not null check(contract_version='233.1'),
  intake_id uuid not null references public.ai_email_intake(id) on delete restrict,
  attachment_id uuid not null references public.ai_email_attachments(id) on delete restrict,
  actor_id uuid not null references auth.users(id) on delete restrict,
  mailbox_address text not null,
  mailbox_uidvalidity bigint not null check(mailbox_uidvalidity=1),
  mailbox_uid bigint not null check(mailbox_uid=478),
  message_received_at timestamptz not null,
  attachment_file_name text not null,
  attachment_sha256 text not null check(attachment_sha256~'^[a-f0-9]{64}$'),
  original_extracted_values jsonb not null check(jsonb_typeof(original_extracted_values)='object'),
  match_evidence jsonb not null check(jsonb_typeof(match_evidence)='object'),
  attempt_metadata jsonb not null check(jsonb_typeof(attempt_metadata)='object'),
  request_sha256 text not null unique check(request_sha256~'^[a-f0-9]{64}$'),
  attempted_at timestamptz not null default clock_timestamp(),
  unique(intake_id,attachment_id,request_sha256),
  check(mailbox_uid not between 470 and 477)
);

create table public.pdc_uid478_attachment_terminal_receipts(
  terminal_receipt_id uuid primary key default gen_random_uuid(),
  contract_version text not null check(contract_version='233.1'),
  attempt_receipt_id uuid not null unique references public.pdc_uid478_attachment_attempt_receipts(attempt_receipt_id) on delete restrict,
  intake_id uuid not null references public.ai_email_intake(id) on delete restrict,
  attachment_id uuid not null references public.ai_email_attachments(id) on delete restrict,
  actor_id uuid not null references auth.users(id) on delete restrict,
  mailbox_address text not null,
  mailbox_uidvalidity bigint not null check(mailbox_uidvalidity=1),
  mailbox_uid bigint not null check(mailbox_uid=478),
  message_received_at timestamptz not null,
  attachment_file_name text not null,
  attachment_sha256 text not null check(attachment_sha256~'^[a-f0-9]{64}$'),
  original_extracted_values jsonb not null check(jsonb_typeof(original_extracted_values)='object'),
  match_evidence jsonb not null check(jsonb_typeof(match_evidence)='object'),
  attempt_metadata jsonb not null check(jsonb_typeof(attempt_metadata)='object'),
  terminal_status text not null check(terminal_status in ('applied','review')),
  review_metadata jsonb check(review_metadata is null or jsonb_typeof(review_metadata)='object'),
  applied_metadata jsonb check(applied_metadata is null or jsonb_typeof(applied_metadata)='object'),
  canonical_import_receipt_id uuid references public.pdc_jobcard_attachment_import_receipts(receipt_id) on delete restrict,
  request_sha256 text not null check(request_sha256~'^[a-f0-9]{64}$'),
  terminal_at timestamptz not null default clock_timestamp(),
  unique(intake_id,attachment_id),
  unique(intake_id,attachment_file_name),
  unique(attachment_sha256),
  check(mailbox_uid not between 470 and 477),
  check((terminal_status='review' and review_metadata is not null and applied_metadata is null and canonical_import_receipt_id is null)
     or (terminal_status='applied' and review_metadata is null and applied_metadata is not null and canonical_import_receipt_id is not null))
);

create table public.pdc_uid478_message_receipts(
  message_receipt_id uuid primary key default gen_random_uuid(),
  contract_version text not null check(contract_version='233.1'),
  intake_id uuid not null unique references public.ai_email_intake(id) on delete restrict,
  actor_id uuid not null references auth.users(id) on delete restrict,
  mailbox_address text not null,
  mailbox_uidvalidity bigint not null check(mailbox_uidvalidity=1),
  mailbox_uid bigint not null check(mailbox_uid=478),
  message_received_at timestamptz not null,
  attachment_count integer not null check(attachment_count=4),
  terminal_attachment_count integer not null check(terminal_attachment_count=4),
  terminal_receipt_ids uuid[] not null check(cardinality(terminal_receipt_ids)=4),
  all_attachments_terminal boolean not null check(all_attachments_terminal),
  high_water_eligible boolean not null check(high_water_eligible),
  aggregate_sha256 text not null unique check(aggregate_sha256~'^[a-f0-9]{64}$'),
  created_at timestamptz not null default clock_timestamp(),
  unique(mailbox_address,mailbox_uidvalidity,mailbox_uid),
  check(mailbox_uid not between 470 and 477)
);

alter table public.pdc_uid478_attachment_attempt_receipts enable row level security;
alter table public.pdc_uid478_attachment_terminal_receipts enable row level security;
alter table public.pdc_uid478_message_receipts enable row level security;
revoke all on table public.pdc_uid478_attachment_attempt_receipts from public,anon,authenticated,service_role;
revoke all on table public.pdc_uid478_attachment_terminal_receipts from public,anon,authenticated,service_role;
revoke all on table public.pdc_uid478_message_receipts from public,anon,authenticated,service_role;

create function public.pdc_uid478_receipt_reject_mutation()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $immutable$
begin raise exception 'PDC_233_RECEIPT_IMMUTABLE' using errcode='55000'; end $immutable$;
revoke all on function public.pdc_uid478_receipt_reject_mutation() from public,anon,authenticated,service_role;
create trigger pdc_uid478_attachment_attempt_receipts_immutable before update or delete on public.pdc_uid478_attachment_attempt_receipts for each row execute function public.pdc_uid478_receipt_reject_mutation();
create trigger pdc_uid478_attachment_terminal_receipts_immutable before update or delete on public.pdc_uid478_attachment_terminal_receipts for each row execute function public.pdc_uid478_receipt_reject_mutation();
create trigger pdc_uid478_message_receipts_immutable before update or delete on public.pdc_uid478_message_receipts for each row execute function public.pdc_uid478_receipt_reject_mutation();

-- Shared exact fixture check.  Filename-only matching is explicitly insufficient:
-- the retained extraction must also carry exact JC/line and bounded Stock/VIN evidence.
create function public.pdc_uid478_validate_attachment_fixture(p_file_name text,p_original jsonb)
returns boolean language sql immutable set search_path=pg_catalog,public as $fixture$
  select jsonb_typeof(p_original)='object' and case p_file_name
    when '12658679.pdf' then p_original->>'job_card_number'='J139124174' and p_original->>'line_count'='20'
      and p_original->'stock_number'='null'::jsonb and p_original->>'vin'='MR0MABAVX02401646'
    when '12661296.pdf' then p_original->>'job_card_number'='J139125297' and p_original->>'line_count'='5' and p_original->>'stock_number'='12661296'
    when '12550488.pdf' then p_original->>'job_card_number'='J139124665' and p_original->>'line_count'='23' and p_original->>'stock_number'='12550488'
    when '12535460.pdf' then p_original->>'job_card_number'='J139125061' and p_original->>'line_count'='14' and p_original->>'stock_number'='12535460'
    else false end;
$fixture$;
revoke all on function public.pdc_uid478_validate_attachment_fixture(text,jsonb) from public,anon,authenticated,service_role;

create function public.record_pdc_uid478_attachment_attempt(
  p_intake_id uuid,p_attachment_id uuid,p_mailbox_address text,p_mailbox_uidvalidity bigint,p_mailbox_uid bigint,
  p_message_received_at timestamptz,p_attachment_file_name text,p_attachment_sha256 text,
  p_original_extracted_values jsonb,p_match_evidence jsonb,p_attempt_metadata jsonb
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions as $attempt$
declare v_scope jsonb:=public.pdc_monitor_actor_scope();v_id uuid;v_request text;v_existing public.pdc_uid478_attachment_attempt_receipts%rowtype;
begin
  -- UIDVALIDITY1_UID478_ONLY. UIDs between 470 and 477 are never accepted or touched.
  if p_mailbox_uidvalidity<>1 or p_mailbox_uid<>478 or p_mailbox_uid between 470 and 477
     or lower(btrim(coalesce(p_mailbox_address,'')))<>'pmbcontroller@gmail.com'
     or p_message_received_at is null or coalesce(p_attachment_sha256,'')!~'^[a-f0-9]{64}$'
     or not public.pdc_uid478_validate_attachment_fixture(p_attachment_file_name,p_original_extracted_values)
     or jsonb_typeof(p_match_evidence) is distinct from 'object' or p_match_evidence='{}'::jsonb
     or jsonb_typeof(p_attempt_metadata) is distinct from 'object'
     or coalesce(lower(p_attempt_metadata->>'parent_source_hash'),'')!~'^[a-f0-9]{64}$' then
    raise exception 'UIDVALIDITY1_UID478_ONLY' using errcode='22023';
  end if;
  perform 1 from public.ai_email_attachments a where a.id=p_attachment_id and a.intake_id=p_intake_id
    and a.file_name=p_attachment_file_name and lower(a.source_hash)=p_attachment_sha256;
  if not found then raise exception 'PDC_233_ATTACHMENT_BINDING_MISMATCH' using errcode='22023'; end if;
  v_request:=encode(extensions.digest(convert_to(jsonb_build_object('contract','233.1','intake_id',p_intake_id,'attachment_id',p_attachment_id,
    'mailbox_uidvalidity',p_mailbox_uidvalidity,'mailbox_uid',p_mailbox_uid,'received_at',p_message_received_at,
    'file_name',p_attachment_file_name,'sha256',p_attachment_sha256,'original',p_original_extracted_values,
    'match_evidence',p_match_evidence,'attempt_metadata',p_attempt_metadata)::text,'UTF8'),'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended('pdc-uid478-attempt:'||p_intake_id::text||':'||p_attachment_id::text||':'||v_request,0));
  select * into v_existing from public.pdc_uid478_attachment_attempt_receipts where request_sha256=v_request;
  if found then return jsonb_build_object('ok',true,'code','attempt_already_recorded','attempt_receipt_id',v_existing.attempt_receipt_id); end if;
  insert into public.pdc_uid478_attachment_attempt_receipts(contract_version,intake_id,attachment_id,actor_id,mailbox_address,mailbox_uidvalidity,mailbox_uid,message_received_at,attachment_file_name,attachment_sha256,original_extracted_values,match_evidence,attempt_metadata,request_sha256)
  values('233.1',p_intake_id,p_attachment_id,(v_scope->>'user_id')::uuid,lower(btrim(p_mailbox_address)),1,478,p_message_received_at,p_attachment_file_name,p_attachment_sha256,p_original_extracted_values,p_match_evidence,p_attempt_metadata,v_request)
  returning attempt_receipt_id into v_id;
  return jsonb_build_object('ok',true,'code','attempt_recorded','attempt_receipt_id',v_id);
end $attempt$;

create function public.record_pdc_uid478_attachment_terminal(
  p_attempt_receipt_id uuid,p_terminal_status text,p_review_metadata jsonb,p_applied_metadata jsonb,p_canonical_import_receipt_id uuid
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions as $terminal$
declare v_scope jsonb:=public.pdc_monitor_actor_scope();v_attempt public.pdc_uid478_attachment_attempt_receipts%rowtype;v_existing public.pdc_uid478_attachment_terminal_receipts%rowtype;v_canonical public.pdc_jobcard_attachment_import_receipts%rowtype;v_id uuid;v_request text;
begin
  select * into v_attempt from public.pdc_uid478_attachment_attempt_receipts where attempt_receipt_id=p_attempt_receipt_id for update;
  if not found then raise exception 'PDC_233_ATTEMPT_NOT_FOUND' using errcode='P0002'; end if;
  if v_attempt.actor_id is distinct from (v_scope->>'user_id')::uuid then raise exception 'PDC_233_ATTEMPT_ACTOR_MISMATCH' using errcode='42501'; end if;
  if (p_terminal_status='review' and jsonb_typeof(p_review_metadata)='object' and p_review_metadata<>'{}'::jsonb and p_applied_metadata is null and p_canonical_import_receipt_id is null)
     is not true and
     (p_terminal_status='applied' and p_review_metadata is null and jsonb_typeof(p_applied_metadata)='object' and p_applied_metadata<>'{}'::jsonb and p_canonical_import_receipt_id is not null)
     is not true then raise exception 'PDC_233_TERMINAL_METADATA_INVALID' using errcode='22023'; end if;
  if p_terminal_status='applied' then
    select * into v_canonical from public.pdc_jobcard_attachment_import_receipts where receipt_id=p_canonical_import_receipt_id for update;
    if not found or v_canonical.intake_id is distinct from v_attempt.intake_id
       or v_canonical.attachment_id is distinct from v_attempt.attachment_id
       or v_canonical.parent_source_hash is distinct from lower(v_attempt.attempt_metadata->>'parent_source_hash')
       or v_canonical.attachment_source_hash is distinct from v_attempt.attachment_sha256
       or v_canonical.actor_id is distinct from v_attempt.actor_id
       or v_canonical.actor_id is distinct from (v_scope->>'user_id')::uuid then
      raise exception 'PDC_233_CANONICAL_RECEIPT_BINDING_MISMATCH' using errcode='22023';
    end if;
  end if;
  v_request:=encode(extensions.digest(convert_to(jsonb_build_object('contract','233.1','attempt_receipt_id',p_attempt_receipt_id,'status',p_terminal_status,'review',p_review_metadata,'applied',p_applied_metadata,'canonical_receipt',p_canonical_import_receipt_id)::text,'UTF8'),'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended('pdc-uid478-terminal:'||v_attempt.intake_id::text||':'||v_attempt.attachment_id::text,0));
  select * into v_existing from public.pdc_uid478_attachment_terminal_receipts where intake_id=v_attempt.intake_id and attachment_id=v_attempt.attachment_id;
  if found then
    if v_existing.request_sha256<>v_request then raise exception 'PDC_233_TERMINAL_REPLAY_CONFLICT' using errcode='23505'; end if;
    return jsonb_build_object('ok',true,'code','terminal_already_recorded','terminal_receipt_id',v_existing.terminal_receipt_id,'status',v_existing.terminal_status);
  end if;
  insert into public.pdc_uid478_attachment_terminal_receipts(contract_version,attempt_receipt_id,intake_id,attachment_id,actor_id,mailbox_address,mailbox_uidvalidity,mailbox_uid,message_received_at,attachment_file_name,attachment_sha256,original_extracted_values,match_evidence,attempt_metadata,terminal_status,review_metadata,applied_metadata,canonical_import_receipt_id,request_sha256)
  values('233.1',v_attempt.attempt_receipt_id,v_attempt.intake_id,v_attempt.attachment_id,(v_scope->>'user_id')::uuid,v_attempt.mailbox_address,1,478,v_attempt.message_received_at,v_attempt.attachment_file_name,v_attempt.attachment_sha256,v_attempt.original_extracted_values,v_attempt.match_evidence,v_attempt.attempt_metadata,p_terminal_status,p_review_metadata,p_applied_metadata,p_canonical_import_receipt_id,v_request) returning terminal_receipt_id into v_id;
  return jsonb_build_object('ok',true,'code','terminal_recorded','terminal_receipt_id',v_id,'status',p_terminal_status);
end $terminal$;

create function public.finalize_pdc_uid478_message(p_intake_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions as $aggregate$
declare v_scope jsonb:=public.pdc_monitor_actor_scope();v_ids uuid[];v_count integer;v_terminal integer;v_digest text;v_existing public.pdc_uid478_message_receipts%rowtype;v_received timestamptz;v_id uuid;
begin
  perform pg_advisory_xact_lock(hashtextextended('pdc-uid478-message:'||p_intake_id::text,0));
  select count(*),count(*) filter(where terminal_status in ('applied','review')),array_agg(terminal_receipt_id order by attachment_file_name),min(message_received_at)
    into v_count,v_terminal,v_ids,v_received from public.pdc_uid478_attachment_terminal_receipts where intake_id=p_intake_id;
  if v_count<>4 or v_terminal<>4 or cardinality(v_ids)<>4 then
    return jsonb_build_object('ok',false,'code','attachments_not_all_terminal','all_attachments_terminal',false,'high_water_eligible',false);
  end if;
  v_digest:=encode(extensions.digest(convert_to(jsonb_build_object('contract','233.1','intake_id',p_intake_id,'uidvalidity',1,'uid',478,'terminal_receipt_ids',v_ids)::text,'UTF8'),'sha256'),'hex');
  select * into v_existing from public.pdc_uid478_message_receipts where intake_id=p_intake_id;
  if found then
    if v_existing.aggregate_sha256<>v_digest or v_existing.actor_id is distinct from (v_scope->>'user_id')::uuid
       or v_existing.terminal_receipt_ids is distinct from v_ids or not v_existing.all_attachments_terminal
       or not v_existing.high_water_eligible then raise exception 'PDC_233_MESSAGE_REPLAY_CONFLICT' using errcode='23505'; end if;
    return jsonb_build_object('ok',true,'code','message_already_terminal','message_receipt_id',v_existing.message_receipt_id,'all_attachments_terminal',true,'high_water_eligible',true,'high_water_uid',478);
  end if;
  insert into public.pdc_uid478_message_receipts(contract_version,intake_id,actor_id,mailbox_address,mailbox_uidvalidity,mailbox_uid,message_received_at,attachment_count,terminal_attachment_count,terminal_receipt_ids,all_attachments_terminal,high_water_eligible,aggregate_sha256)
  values('233.1',p_intake_id,(v_scope->>'user_id')::uuid,'pmbcontroller@gmail.com',1,478,v_received,4,4,v_ids,true,true,v_digest) returning message_receipt_id into v_id;
  select * into v_existing from public.pdc_uid478_message_receipts where message_receipt_id=v_id for share;
  if not found or v_existing.intake_id is distinct from p_intake_id
     or v_existing.actor_id is distinct from (v_scope->>'user_id')::uuid
     or v_existing.terminal_receipt_ids is distinct from v_ids
     or v_existing.aggregate_sha256 is distinct from v_digest
     or not v_existing.all_attachments_terminal or not v_existing.high_water_eligible then
    raise exception 'PDC_233_MESSAGE_RECEIPT_VERIFY_FAILED' using errcode='55000';
  end if;
  return jsonb_build_object('ok',true,'code','message_terminal','message_receipt_id',v_id,'all_attachments_terminal',true,'high_water_eligible',true,'high_water_uid',478);
end $aggregate$;

revoke all on function public.record_pdc_uid478_attachment_attempt(uuid,uuid,text,bigint,bigint,timestamptz,text,text,jsonb,jsonb,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.record_pdc_uid478_attachment_attempt(uuid,uuid,text,bigint,bigint,timestamptz,text,text,jsonb,jsonb,jsonb) to authenticated;
revoke all on function public.record_pdc_uid478_attachment_terminal(uuid,text,jsonb,jsonb,uuid) from public,anon,authenticated,service_role;
grant execute on function public.record_pdc_uid478_attachment_terminal(uuid,text,jsonb,jsonb,uuid) to authenticated;
revoke all on function public.finalize_pdc_uid478_message(uuid) from public,anon,authenticated,service_role;
grant execute on function public.finalize_pdc_uid478_message(uuid) to authenticated;

do $verify$
declare d text; canonical_d text; read_d text;
begin
  select pg_get_functiondef('public.attest_pdc_provider_email_observation(uuid,uuid,text,text,text,text,jsonb)'::regprocedure) into d;
  select pg_get_functiondef('public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)'::regprocedure) into canonical_d;
  select pg_get_functiondef('public.read_pdc_jobcard_attachment_import_receipt(uuid)'::regprocedure) into read_d;
  if position('pdc-provider-email-observation-233:' in d)=0
     or position('where intake_id=p_intake_id and attachment_id=p_attachment_id' in d)=0
     or position('v_canonical_source_hash:=encode' in canonical_d)=0
     or position('v_canonical_source_hash,v_attachment_hash,v_source_uid' in canonical_d)=0
     or position('source_hash=v_canonical_source_hash' in canonical_d)=0
     or position('canonical_source_hash' in read_d)=0
     or has_function_privilege('service_role','public.record_pdc_uid478_attachment_terminal(uuid,text,jsonb,jsonb,uuid)','EXECUTE') then
    raise exception 'PDC_233_POSTCONDITION_FAILED' using errcode='55000';
  end if;
  insert into supabase_migrations.schema_migrations(version,name,statements) values('233','uid478_attachment_atomic_import',array[
    'generalise immutable provider observations from one message row to one row per attachment without deleting legacy evidence or changing the RPC signature',
    'append immutable UIDVALIDITY 1 UID 478 attempt and applied-or-review terminal receipts containing original extraction and match evidence',
    'make exact terminal replay idempotent and attachment scoped while allowing ambiguity review or failed attempts to leave other attachments dispatchable',
    'publish message aggregate and high-water eligibility only after exactly four attachments have terminal receipts',
    'grant new execution only to the existing scoped authenticated Monitor identity; no mailbox access credentials service-role bot replay or production changes'
  ]);
end $verify$;
notify pgrst,'reload schema';
commit;
