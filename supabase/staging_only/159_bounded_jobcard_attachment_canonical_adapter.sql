-- Staging-only Migration 159: one bounded attachment-scoped adapter from retained
-- AI email rows into the existing canonical observation/activation/import/hour chain.
begin;
set local lock_timeout='10s';
set local statement_timeout='300s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-159-jobcard-attachment-adapter',0));

do $guard$
begin
  if not public.pdc_monitor_staging_guard()
     or to_regclass('public.pdc_staging_environment_sentinel') is null
     or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or not exists(select 1 from supabase_migrations.schema_migrations where version='158' and name='pmb_email_board_purge_reactivation')
     or exists(select 1 from supabase_migrations.schema_migrations where version='159') then
    raise exception 'PDC_159_STAGING_OR_EXACT_PREDECESSOR_MISMATCH' using errcode='55000';
  end if;
  if to_regclass('public.ai_email_intake') is null
     or to_regclass('public.ai_email_attachments') is null
     or to_regclass('public.monitored_mailboxes') is null
     or to_regclass('public.pdc_monitor_stage_activation_writers') is null
     or to_regclass('public.pdc_authenticated_email_import_receipts') is null
     or to_regclass('public.pdc_authenticated_email_operation_lines') is null
     or to_regprocedure('public.submit_pdc_ai_intake_observation(text,text,text,text,jsonb,timestamptz,text,text,text,text,jsonb)') is null
     or to_regprocedure('public.import_pdc_authenticated_vehicle_email(text,text,text,text,text,jsonb,timestamptz,text,jsonb,jsonb)') is null
     or to_regprocedure('public.import_pdc_authenticated_email_operations_with_hours(text,text,jsonb)') is null
     or to_regprocedure('public.process_email_intake_work(uuid,text,text,jsonb,text)') is not null
     or to_regprocedure('public.attest_pdc_provider_email_observation(uuid,uuid,text,text,text,text,jsonb)') is not null
     or to_regprocedure('public.get_pdc_email_intake_work_receipt(uuid,text,text)') is not null then
    raise exception 'PDC_159_DEPENDENCY_MISSING' using errcode='55000';
  end if;
end
$guard$;

-- Only exact, hash-enrolled senders may use automatic operational import.
-- The enrolled hash was explicitly authorised for this staging job-card path;
-- no clear-text sender address is retained in source or configuration tables.
create table public.pdc_monitor_exact_sender_enrollments(
  sender_sha256 text primary key check(sender_sha256~'^[a-f0-9]{64}$'),
  purpose text not null check(length(purpose) between 3 and 120),
  active boolean not null default true,
  enrolled_at timestamptz not null default clock_timestamp()
);
alter table public.pdc_monitor_exact_sender_enrollments enable row level security;
revoke all on table public.pdc_monitor_exact_sender_enrollments from public,anon,authenticated,service_role;
insert into public.pdc_monitor_exact_sender_enrollments(sender_sha256,purpose)
values('804fa93bee0e630b96662762114aff45529af322fa1afd59908595932d3f9f4b','explicit PMB job-card sender');

-- Backend-only mailbox identity. Credentials, polling and schedules remain owned by
-- the isolated pdc-monitor profile; this row contains no credential material.
insert into public.monitored_mailboxes(
  id,mailbox_key,display_name,mailbox_address,provider,active,test_mode,config
) values(
  extensions.uuid_generate_v5('47de1860-a47d-5c3a-9f33-30c4235efaa7'::uuid,'pdc-pmb-email-staging'),
  'pdc_pmb_email','PDC PMB Email','pmbcontroller@gmail.com','gmail',true,true,
  jsonb_build_object('owner_profile','pdc-monitor','contains_credentials',false,'operational_scope','staging')
) on conflict(mailbox_key) do update set
  display_name=excluded.display_name,mailbox_address=excluded.mailbox_address,provider=excluded.provider,
  active=true,test_mode=true,config=excluded.config,updated_at=clock_timestamp();

-- Narrow Migration158's direct submission surface from whole-domain trust to the
-- same exact sender enrollment, and prevent evidence received before a deliberate
-- Board purge from reopening that later tombstone.
do $narrow_158$
declare
  d text;
  old_sender text:=$old$or split_part(v_sender,'@',2) not in ('broometoyota.com.au','pmgwa.com.au')$old$;
  new_sender text:=$new$or not exists(
       select 1 from public.pdc_monitor_exact_sender_enrollments e
       where e.active and e.sender_sha256=encode(extensions.digest(convert_to(v_sender,'UTF8'),'sha256'),'hex')
     )$new$;
  old_purge text:=$old$and v_record.canonical_vehicle_id=v_vehicle.id;
    if not found or (not v_reactivating_board_purge and ($old$;
  new_purge text:=$new$and v_record.canonical_vehicle_id=v_vehicle.id
      and v_proposal.source_received_at>v_vehicle.board_purged_at;
    if not found or (not v_reactivating_board_purge and ($new$;
begin
  select pg_get_functiondef('public.submit_pdc_ai_intake_observation_pre135(text,text,text,text,jsonb,timestamptz,text,text,text,text,jsonb)'::regprocedure) into d;
  if position(old_sender in d)=0 or position('pdc_monitor_exact_sender_enrollments' in d)>0 then
    raise exception 'PDC_159_PRE135_SENDER_DRIFT' using errcode='55000';
  end if;
  execute replace(d,old_sender,new_sender);

  select pg_get_functiondef('public.pdc_auto_apply_ai_intake_activation_internal(uuid,uuid,text,boolean)'::regprocedure) into d;
  if position(old_purge in d)=0 or position('source_received_at>v_vehicle.board_purged_at' in d)>0 then
    raise exception 'PDC_159_AUTO_APPLY_PURGE_FRESHNESS_DRIFT' using errcode='55000';
  end if;
  execute replace(d,old_purge,new_purge);
end
$narrow_158$;

create table public.pdc_provider_email_observations(
  observation_id uuid primary key default gen_random_uuid(),
  contract_version text not null check(contract_version='159.2'),
  intake_id uuid not null unique references public.ai_email_intake(id) on delete restrict,
  attachment_id uuid not null unique references public.ai_email_attachments(id) on delete restrict,
  parent_source_hash text not null unique check(parent_source_hash~'^[a-f0-9]{64}$'),
  attachment_source_hash text not null check(attachment_source_hash~'^[a-f0-9]{64}$'),
  provider_message_id text not null unique check(length(provider_message_id) between 1 and 1024),
  provider_authserv_id text not null check(provider_authserv_id='mx.google.com'),
  authentication jsonb not null check(jsonb_typeof(authentication)='object'),
  request_sha256 text not null unique check(request_sha256~'^[a-f0-9]{64}$'),
  observed_at timestamptz not null default clock_timestamp()
);
alter table public.pdc_provider_email_observations enable row level security;
revoke all on table public.pdc_provider_email_observations from public,anon,authenticated,service_role;

create table public.pdc_email_intake_work_receipts(
  work_receipt_id uuid primary key default gen_random_uuid(),
  intake_id uuid not null unique references public.ai_email_intake(id) on delete restrict,
  attachment_receipt_id uuid not null unique,
  actor_id uuid not null references auth.users(id) on delete restrict,
  source_hash text not null unique check(source_hash~'^[a-f0-9]{64}$'),
  extraction_hash text not null check(extraction_hash~'^[a-f0-9]{64}$'),
  server_extraction_hash text not null check(server_extraction_hash~'^[a-f0-9]{64}$'),
  request_sha256 text not null unique check(request_sha256~'^[a-f0-9]{64}$'),
  created_at timestamptz not null default clock_timestamp()
);
alter table public.pdc_email_intake_work_receipts enable row level security;
revoke all on table public.pdc_email_intake_work_receipts from public,anon,authenticated,service_role;

create table public.pdc_jobcard_attachment_import_receipts(
  receipt_id uuid primary key default gen_random_uuid(),
  contract_version text not null check(contract_version='159.1'),
  actor_id uuid not null references auth.users(id) on delete restrict,
  actor_email text not null,
  intake_id uuid not null references public.ai_email_intake(id) on delete restrict,
  attachment_id uuid not null references public.ai_email_attachments(id) on delete restrict,
  parent_source_hash text not null check(parent_source_hash~'^[a-f0-9]{64}$'),
  attachment_source_hash text not null check(attachment_source_hash~'^[a-f0-9]{64}$'),
  attachment_size_bytes bigint not null check(attachment_size_bytes between 1 and 10485760),
  attachment_content_type text not null,
  source_uid text not null check(length(source_uid) between 1 and 100),
  proposal_id uuid not null references public.pdc_ai_intake_proposals(proposal_id) on delete restrict,
  canonical_import_receipt_id uuid not null references public.pdc_authenticated_email_import_receipts(receipt_id) on delete restrict,
  vehicle_id uuid not null references public.vehicles(id) on delete restrict,
  vehicle_version integer not null check(vehicle_version>=1),
  backend_record_id uuid not null references public.navision_backend_records(id) on delete restrict,
  backend_record_version integer not null check(backend_record_version>=1),
  job_card_number text not null,
  requested_payload_sha256 text not null check(requested_payload_sha256~'^[a-f0-9]{64}$'),
  operation_sha256 text not null check(operation_sha256~'^[a-f0-9]{64}$'),
  operation_count integer not null check(operation_count between 1 and 50),
  estimated_hours_sum numeric(10,2) not null check(estimated_hours_sum>0),
  canonical_operation_line_ids uuid[] not null,
  response jsonb not null check(jsonb_typeof(response)='object'),
  created_at timestamptz not null default clock_timestamp(),
  unique(actor_id,intake_id,attachment_id),
  unique(parent_source_hash),
  unique(canonical_import_receipt_id),
  check(cardinality(canonical_operation_line_ids)=operation_count)
);

create table public.pdc_jobcard_attachment_source_row_receipts(
  source_row_receipt_id uuid primary key default gen_random_uuid(),
  receipt_id uuid not null references public.pdc_jobcard_attachment_import_receipts(receipt_id) on delete restrict,
  source_row_no integer not null check(source_row_no>0),
  operation_no text not null check(operation_no~'^OP([1-9]|[1-4][0-9]|50)$'),
  operation_line_id uuid not null references public.pdc_authenticated_email_operation_lines(operation_line_id) on delete restrict,
  work_key text not null check(work_key in ('bus4x4','tint','hoist','fitting','fabrication','electrical','tyre','pitInspection','PARTS')),
  description text not null check(length(description) between 1 and 180),
  estimated_hours numeric(6,2) not null check(estimated_hours>0 and estimated_hours<=999.99),
  estimated_hours_source text not null check(estimated_hours_source='job_card'),
  line_sha256 text not null check(line_sha256~'^[a-f0-9]{64}$'),
  created_at timestamptz not null default clock_timestamp(),
  unique(receipt_id,source_row_no),
  unique(receipt_id,operation_no),
  unique(receipt_id,operation_line_id)
);

alter table public.pdc_jobcard_attachment_import_receipts enable row level security;
alter table public.pdc_jobcard_attachment_source_row_receipts enable row level security;
revoke all on table public.pdc_jobcard_attachment_import_receipts from public,anon,authenticated,service_role;
revoke all on table public.pdc_jobcard_attachment_source_row_receipts from public,anon,authenticated,service_role;

create function public.pdc_jobcard_attachment_receipt_reject_mutation()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $immutable$
begin
  raise exception 'PDC_159_RECEIPT_IMMUTABLE' using errcode='55000';
end
$immutable$;
revoke all on function public.pdc_jobcard_attachment_receipt_reject_mutation() from public,anon,authenticated,service_role;
create trigger pdc_jobcard_attachment_import_receipts_immutable
before update or delete on public.pdc_jobcard_attachment_import_receipts
for each row execute function public.pdc_jobcard_attachment_receipt_reject_mutation();
create trigger pdc_jobcard_attachment_source_row_receipts_immutable
before update or delete on public.pdc_jobcard_attachment_source_row_receipts
for each row execute function public.pdc_jobcard_attachment_receipt_reject_mutation();
alter table public.pdc_email_intake_work_receipts
  add constraint pdc_email_intake_work_receipts_attachment_fk
  foreign key(attachment_receipt_id) references public.pdc_jobcard_attachment_import_receipts(receipt_id) on delete restrict;
create trigger pdc_provider_email_observations_immutable
before update or delete on public.pdc_provider_email_observations
for each row execute function public.pdc_jobcard_attachment_receipt_reject_mutation();
create trigger pdc_email_intake_work_receipts_immutable
before update or delete on public.pdc_email_intake_work_receipts
for each row execute function public.pdc_jobcard_attachment_receipt_reject_mutation();

create function public.attest_pdc_provider_email_observation(
  p_intake_id uuid,
  p_attachment_id uuid,
  p_expected_parent_hash text,
  p_expected_attachment_hash text,
  p_provider_message_id text,
  p_provider_authserv_id text,
  p_authentication jsonb
) returns jsonb
language plpgsql security definer
set search_path=pg_catalog,public,extensions
as $attest$
declare
  v_intake public.ai_email_intake%rowtype;
  v_attachment public.ai_email_attachments%rowtype;
  v_mailbox public.monitored_mailboxes%rowtype;
  v_existing public.pdc_provider_email_observations%rowtype;
  v_parent text:=lower(btrim(coalesce(p_expected_parent_hash,'')));
  v_attachment_hash text:=lower(btrim(coalesce(p_expected_attachment_hash,'')));
  v_message_id text:=btrim(coalesce(p_provider_message_id,''));
  v_authserv text:=lower(btrim(coalesce(p_provider_authserv_id,'')));
  v_auth jsonb:=coalesce(p_authentication,'null'::jsonb);
  v_sender text;
  v_request text;
begin
  if not public.pdc_monitor_staging_guard() or auth.role()<>'service_role'
     or p_intake_id is null or p_attachment_id is null
     or v_parent!~'^[a-f0-9]{64}$' or v_attachment_hash!~'^[a-f0-9]{64}$'
     or length(v_message_id) not between 1 and 1024 or v_authserv<>'mx.google.com'
     or jsonb_typeof(v_auth) is distinct from 'object'
     or (select array_agg(k order by k) from jsonb_object_keys(v_auth) k)
        is distinct from array['dkim_aligned','dmarc_aligned','gmail_authentication_results','sender_domain','spf_aligned']::text[]
     or v_auth->'gmail_authentication_results' is distinct from 'true'::jsonb
     or not(v_auth->'spf_aligned'='true'::jsonb or v_auth->'dkim_aligned'='true'::jsonb or v_auth->'dmarc_aligned'='true'::jsonb) then
    return public.navision_backend_response(false,'provider_observation_invalid');
  end if;
  select * into v_intake from public.ai_email_intake where id=p_intake_id for share;
  if not found then return public.navision_backend_response(false,'intake_not_found'); end if;
  select * into v_attachment from public.ai_email_attachments where id=p_attachment_id and intake_id=p_intake_id for share;
  if not found then return public.navision_backend_response(false,'attachment_not_found'); end if;
  select * into v_mailbox from public.monitored_mailboxes where id=v_intake.monitored_mailbox_id for share;
  v_sender:=lower(btrim(coalesce(v_intake.sender_email,'')));
  if not found or not v_mailbox.active
     or lower(btrim(coalesce(v_intake.recipient_mailbox,'')))<>lower(btrim(v_mailbox.mailbox_address))
     or lower(coalesce(v_intake.source_hash,''))<>v_parent
     or lower(coalesce(v_attachment.source_hash,''))<>v_attachment_hash
     or v_message_id is distinct from coalesce(nullif(btrim(v_intake.internet_message_id),''),v_intake.graph_message_id)
     or v_auth->>'sender_domain' is distinct from split_part(v_sender,'@',2)
     or not exists(select 1 from public.pdc_monitor_exact_sender_enrollments e where e.active
       and e.sender_sha256=encode(extensions.digest(convert_to(v_sender,'UTF8'),'sha256'),'hex')) then
    return public.navision_backend_response(false,'provider_observation_binding_mismatch');
  end if;
  v_request:=encode(extensions.digest(convert_to(jsonb_build_object(
    'contract_version','159.2','intake_id',p_intake_id,'attachment_id',p_attachment_id,
    'parent_source_hash',v_parent,'attachment_source_hash',v_attachment_hash,
    'provider_message_id',v_message_id,'provider_authserv_id',v_authserv,'authentication',v_auth
  )::text,'UTF8'),'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended('pdc-provider-email-observation-159:'||p_intake_id::text,0));
  select * into v_existing from public.pdc_provider_email_observations where intake_id=p_intake_id;
  if found then
    if v_existing.request_sha256<>v_request or v_existing.attachment_id<>p_attachment_id then
      return public.navision_backend_response(false,'provider_observation_replay_conflict');
    end if;
    return public.navision_backend_response(true,'provider_observation_already_attested',jsonb_build_object(
      'observation_id',v_existing.observation_id,'request_sha256',v_existing.request_sha256));
  end if;
  insert into public.pdc_provider_email_observations(
    contract_version,intake_id,attachment_id,parent_source_hash,attachment_source_hash,
    provider_message_id,provider_authserv_id,authentication,request_sha256
  ) values('159.2',p_intake_id,p_attachment_id,v_parent,v_attachment_hash,v_message_id,v_authserv,v_auth,v_request)
  returning * into v_existing;
  return public.navision_backend_response(true,'provider_observation_attested',jsonb_build_object(
    'observation_id',v_existing.observation_id,'request_sha256',v_existing.request_sha256));
end
$attest$;

create function public.read_pdc_jobcard_attachment_import_receipt(p_receipt_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path=pg_catalog,public,extensions
as $read$
declare
  v_actor uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_receipt public.pdc_jobcard_attachment_import_receipts%rowtype;
  v_lines jsonb;
  v_ids uuid[];
  v_digest text;
  v_count integer;
  v_hours numeric(10,2);
  v_row_count integer;
  v_drift boolean;
begin
  if not public.pdc_monitor_staging_guard() or p_receipt_id is null or v_actor is null or v_email='' then
    return public.navision_backend_response(false,'unauthorized');
  end if;
  perform 1 from public.pdc_user_roles r
   where r.auth_user_id=v_actor and lower(r.email)=v_email
     and r.role in('viewer','importer') and r.active and r.account_status='approved';
  if not found then return public.navision_backend_response(false,'unauthorized'); end if;
  perform 1 from public.pdc_monitor_stage_activation_writers w
   where w.user_id=v_actor and w.active and w.revoked_at is null;
  if not found then return public.navision_backend_response(false,'unauthorized'); end if;
  select * into v_receipt from public.pdc_jobcard_attachment_import_receipts
   where receipt_id=p_receipt_id and actor_id=v_actor;
  if not found then return public.navision_backend_response(false,'receipt_not_found'); end if;

  select count(*),coalesce(sum(ol.estimated_hours),0),
    coalesce(array_agg(ol.operation_line_id order by sr.source_row_no),'{}'::uuid[]),
    coalesce(jsonb_agg(jsonb_build_object(
      'source_row_no',sr.source_row_no,'operation_no',ol.operation_no,
      'operation_line_id',ol.operation_line_id,'work_key',ol.work_key,
      'description',ol.description,'estimated_hours',ol.estimated_hours,
      'estimated_hours_source',ol.estimated_hours_source
    ) order by sr.source_row_no),'[]'::jsonb)
  into v_count,v_hours,v_ids,v_lines
  from public.pdc_jobcard_attachment_source_row_receipts sr
  join public.pdc_authenticated_email_operation_lines ol on ol.operation_line_id=sr.operation_line_id
  where sr.receipt_id=v_receipt.receipt_id
    and ol.source_hash=v_receipt.parent_source_hash
    and ol.source_uid=v_receipt.source_uid
    and ol.vehicle_id=v_receipt.vehicle_id;
  select count(*) into v_row_count from public.pdc_jobcard_attachment_source_row_receipts where receipt_id=v_receipt.receipt_id;
  v_digest:=encode(extensions.digest(convert_to(v_lines::text,'UTF8'),'sha256'),'hex');
  v_drift:=v_row_count<>v_receipt.operation_count
    or v_count<>v_receipt.operation_count
    or v_hours is distinct from v_receipt.estimated_hours_sum
    or v_ids is distinct from v_receipt.canonical_operation_line_ids
    or v_digest is distinct from v_receipt.operation_sha256
    or exists(
      select 1 from public.pdc_jobcard_attachment_source_row_receipts sr
      left join public.pdc_authenticated_email_operation_lines ol on ol.operation_line_id=sr.operation_line_id
      where sr.receipt_id=v_receipt.receipt_id and (
        ol.operation_line_id is null or ol.operation_no<>sr.operation_no or ol.work_key<>sr.work_key
        or ol.description<>sr.description or ol.estimated_hours<>sr.estimated_hours
        or ol.estimated_hours_source<>'job_card' or sr.line_sha256<>encode(extensions.digest(convert_to(jsonb_build_object(
          'source_row_no',sr.source_row_no,'operation_no',ol.operation_no,'operation_line_id',ol.operation_line_id,
          'work_key',ol.work_key,'description',ol.description,'estimated_hours',ol.estimated_hours,
          'estimated_hours_source',ol.estimated_hours_source)::text,'UTF8'),'sha256'),'hex')
      )
    )
    or not exists(
      select 1
      from public.pdc_authenticated_email_import_receipts ir
      join public.vehicles v on v.id=ir.vehicle_id
      join public.navision_backend_records b on b.id=ir.backend_record_id
      join public.pdc_ai_intake_proposals p on p.proposal_id=v_receipt.proposal_id
      join public.navision_board_activations a on a.backend_record_id=b.id
      where ir.receipt_id=v_receipt.canonical_import_receipt_id
        and ir.actor_id=v_receipt.actor_id and ir.source_hash=v_receipt.parent_source_hash
        and ir.source_uid=v_receipt.source_uid and ir.vehicle_id=v_receipt.vehicle_id
        and ir.backend_record_id=v_receipt.backend_record_id
        and ir.backend_record_version=v_receipt.backend_record_version
        and p.submitted_by=v_receipt.actor_id and p.source_hash=v_receipt.parent_source_hash
        and p.source_uid=v_receipt.source_uid and p.status='applied'
        and p.backend_record_id=v_receipt.backend_record_id
        and v.version=v_receipt.vehicle_version and v.lifecycle_state='active'
        and v.deleted_at is null and v.visible_on_board and v.board_purged_at is null
        and upper(btrim(coalesce(v.job_card_number,'')))=upper(v_receipt.job_card_number)
        and b.version=v_receipt.backend_record_version and b.is_current and b.record_status='current'
        and a.canonical_vehicle_id=v_receipt.vehicle_id and a.active and a.completed_at is null
        and public.normalize_vehicle_stock_number(a.activated_stock_number)=public.normalize_vehicle_stock_number(ir.stock_number)
    );
  if v_drift then
    return public.navision_backend_response(false,'canonical_receipt_drift',jsonb_build_object(
      'receipt_id',v_receipt.receipt_id,'expected_operation_sha256',v_receipt.operation_sha256,
      'observed_operation_sha256',v_digest,'expected_operation_count',v_receipt.operation_count,
      'observed_operation_count',v_count));
  end if;
  return public.navision_backend_response(true,'jobcard_attachment_receipt',jsonb_build_object(
    'receipt_id',v_receipt.receipt_id,'intake_id',v_receipt.intake_id,'attachment_id',v_receipt.attachment_id,
    'parent_source_hash',v_receipt.parent_source_hash,'attachment_source_hash',v_receipt.attachment_source_hash,
    'attachment_size_bytes',v_receipt.attachment_size_bytes,'attachment_content_type',v_receipt.attachment_content_type,
    'source_uid',v_receipt.source_uid,'proposal_id',v_receipt.proposal_id,
    'canonical_import_receipt_id',v_receipt.canonical_import_receipt_id,
    'vehicle_id',v_receipt.vehicle_id,'vehicle_version',v_receipt.vehicle_version,
    'backend_record_id',v_receipt.backend_record_id,'backend_record_version',v_receipt.backend_record_version,
    'job_card_number',v_receipt.job_card_number,'requested_payload_sha256',v_receipt.requested_payload_sha256,
    'operation_sha256',v_receipt.operation_sha256,'operation_count',v_receipt.operation_count,
    'estimated_hours_sum',v_receipt.estimated_hours_sum,'canonical_operation_line_ids',to_jsonb(v_receipt.canonical_operation_line_ids),
    'operation_lines',v_lines,'canonical_import_response',v_receipt.response,
    'booking_created',false,'completion_created',false,'location_scheduled',false));
end
$read$;

create function public.import_pdc_jobcard_attachment_canonical(
  p_intake_id uuid,
  p_attachment_id uuid,
  p_expected_parent_hash text,
  p_expected_attachment_hash text,
  p_authentication jsonb,
  p_email_vehicle jsonb,
  p_required_work jsonb,
  p_operation_lines jsonb
) returns jsonb
language plpgsql security definer
set search_path=pg_catalog,public,extensions
set statement_timeout='180s'
as $adapter$
declare
  v_actor uuid:=auth.uid();
  v_actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_parent_hash text:=lower(btrim(coalesce(p_expected_parent_hash,'')));
  v_attachment_hash text:=lower(btrim(coalesce(p_expected_attachment_hash,'')));
  v_auth jsonb:=coalesce(p_authentication,'null'::jsonb);
  v_email_vehicle jsonb:=coalesce(p_email_vehicle,'null'::jsonb);
  v_required_work jsonb:=coalesce(p_required_work,'null'::jsonb);
  v_input_lines jsonb:=coalesce(p_operation_lines,'null'::jsonb);
  v_intake public.ai_email_intake%rowtype;
  v_attachment public.ai_email_attachments%rowtype;
  v_mailbox public.monitored_mailboxes%rowtype;
  v_provider_observation public.pdc_provider_email_observations%rowtype;
  v_existing public.pdc_jobcard_attachment_import_receipts%rowtype;
  v_import_receipt public.pdc_authenticated_email_import_receipts%rowtype;
  v_vehicle public.vehicles%rowtype;
  v_backend public.navision_backend_records%rowtype;
  v_source_uid text;
  v_idempotency_key text;
  v_sender text;
  v_subject text;
  v_stock text;
  v_job_card text;
  v_canonical_lines jsonb;
  v_observations jsonb;
  v_requested_digest text;
  v_operation_digest text;
  v_operation_count integer;
  v_hours_sum numeric(10,2);
  v_line_ids uuid[];
  v_submit jsonb;
  v_vehicle_result jsonb;
  v_hours_result jsonb;
  v_failure jsonb;
  v_proposal_id uuid;
  v_receipt_id uuid:=gen_random_uuid();
  v_response jsonb;
  v_item jsonb;
  v_line public.pdc_authenticated_email_operation_lines%rowtype;
  v_nested_marker boolean:=false;
begin
  if not public.pdc_monitor_staging_guard() or v_actor is null or v_actor_email='' then
    return public.navision_backend_response(false,'unauthorized');
  end if;
  perform 1 from public.pdc_user_roles r
   where r.auth_user_id=v_actor and lower(r.email)=v_actor_email
     and r.role in('viewer','importer') and r.active and r.account_status='approved' for share;
  if not found then return public.navision_backend_response(false,'unauthorized'); end if;
  perform 1 from public.pdc_monitor_stage_activation_writers w
   where w.user_id=v_actor and w.active and w.revoked_at is null for share;
  if not found then return public.navision_backend_response(false,'unauthorized'); end if;

  if p_intake_id is null or p_attachment_id is null
     or v_parent_hash!~'^[a-f0-9]{64}$' or v_attachment_hash!~'^[a-f0-9]{64}$'
     or jsonb_typeof(v_auth) is distinct from 'object'
     or (select array_agg(k order by k) from jsonb_object_keys(v_auth) k)
        is distinct from array['dkim_aligned','dmarc_aligned','gmail_authentication_results','sender_domain','spf_aligned']::text[]
     or v_auth->'gmail_authentication_results' is distinct from 'true'::jsonb
     or not(v_auth->'spf_aligned'='true'::jsonb or v_auth->'dkim_aligned'='true'::jsonb or v_auth->'dmarc_aligned'='true'::jsonb)
     or jsonb_typeof(v_email_vehicle) is distinct from 'object'
     or (select array_agg(k order by k) from jsonb_object_keys(v_email_vehicle) k)
        is distinct from array['cancelled','conflicts','customer_name','eta_to_kewdale','job_card_number','registration','stock_numbers','toyota_order_number','vehicle_description','vins']::text[]
     or jsonb_typeof(v_required_work) is distinct from 'array'
     or jsonb_array_length(v_required_work) not between 1 and 10
     or exists(select 1 from jsonb_array_elements(v_required_work) x where jsonb_typeof(x)<>'string' or x#>>'{}' not in
       ('bus4x4','tint','hoist','fitting','fabrication','electrical','tyre','pitInspection','PARTS'))
     or jsonb_array_length(v_required_work)<>(select count(distinct x) from jsonb_array_elements_text(v_required_work) x)
     or jsonb_typeof(v_input_lines) is distinct from 'array'
     or jsonb_array_length(v_input_lines) not between 1 and 50 then
    return public.navision_backend_response(false,'invalid_input');
  end if;
  if exists(
    select 1 from jsonb_array_elements(v_input_lines) with ordinality x(line,ordinality)
    where jsonb_typeof(line)<>'object'
       or (select array_agg(k order by k) from jsonb_object_keys(line) k)
          is distinct from array['description','estimated_hours','operation_no','source_row_no','work_key']::text[]
       or jsonb_typeof(line->'source_row_no')<>'number'
       or coalesce(line->>'source_row_no','')!~'^[1-9][0-9]{0,8}$'
       or line->>'operation_no' is distinct from 'OP'||ordinality::text
       or line->>'work_key' not in ('bus4x4','tint','hoist','fitting','fabrication','electrical','tyre','pitInspection','PARTS')
       or length(coalesce(line->>'description','')) not between 1 and 180
       or line->>'description' is distinct from btrim(line->>'description')
       or line->>'description'~'[[:cntrl:]]'
       or jsonb_typeof(line->'estimated_hours')<>'number'
       or (line->>'estimated_hours')::numeric<=0 or (line->>'estimated_hours')::numeric>999.99
       or mod((line->>'estimated_hours')::numeric,0.01)<>0
  ) or jsonb_array_length(v_input_lines)<>(select count(distinct (x->>'source_row_no')::integer) from jsonb_array_elements(v_input_lines) x)
    or jsonb_array_length(v_input_lines)<>(select count(distinct x->>'operation_no') from jsonb_array_elements(v_input_lines) x)
    or (select array_agg(distinct x->>'work_key' order by x->>'work_key') from jsonb_array_elements(v_input_lines) x)
       is distinct from (select array_agg(x order by x) from jsonb_array_elements_text(v_required_work) x) then
    return public.navision_backend_response(false,'invalid_operation_lines_or_required_work_set');
  end if;

  select * into v_intake from public.ai_email_intake where id=p_intake_id for update;
  if not found then return public.navision_backend_response(false,'intake_not_found'); end if;
  select * into v_attachment from public.ai_email_attachments
   where id=p_attachment_id and intake_id=p_intake_id for share;
  if not found then return public.navision_backend_response(false,'attachment_not_found'); end if;
  select * into v_provider_observation from public.pdc_provider_email_observations
   where intake_id=p_intake_id and attachment_id=p_attachment_id for share;
  if not found
     or v_provider_observation.parent_source_hash<>v_parent_hash
     or v_provider_observation.attachment_source_hash<>v_attachment_hash
     or v_provider_observation.provider_authserv_id<>'mx.google.com'
     or v_provider_observation.authentication is distinct from v_auth then
    return public.navision_backend_response(false,'provider_observation_required_or_mismatch');
  end if;
  select * into v_mailbox from public.monitored_mailboxes
   where id=v_intake.monitored_mailbox_id for share;
  if not found or not v_mailbox.active
     or lower(btrim(coalesce(v_intake.recipient_mailbox,'')))<>lower(btrim(v_mailbox.mailbox_address)) then
    return public.navision_backend_response(false,'monitored_mailbox_binding_mismatch');
  end if;
  if (select count(*) from public.ai_email_attachments a
      where a.id=p_attachment_id and a.intake_id=p_intake_id and lower(a.source_hash)=v_attachment_hash)<>1
     or lower(coalesce(v_intake.source_hash,''))<>v_parent_hash
     or lower(coalesce(v_attachment.source_hash,''))<>v_attachment_hash
     or v_attachment.size_bytes is null or v_attachment.size_bytes not between 1 and 10485760
     or lower(coalesce(v_attachment.content_type,'')) not in (
       'application/pdf','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
       'application/vnd.ms-excel','text/csv','text/plain') then
    return public.navision_backend_response(false,'attachment_identity_or_type_mismatch');
  end if;
  v_sender:=lower(btrim(coalesce(v_intake.sender_email,'')));
  v_subject:=btrim(coalesce(v_intake.subject,''));
  if v_sender!~'^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?$'
     or not exists(select 1 from public.pdc_monitor_exact_sender_enrollments e where e.active
       and e.sender_sha256=encode(extensions.digest(convert_to(v_sender,'UTF8'),'sha256'),'hex'))
     or v_auth->>'sender_domain' is distinct from split_part(v_sender,'@',2)
     or length(v_subject) not between 1 and 300 then
    return public.navision_backend_response(false,'sender_authentication_or_subject_invalid');
  end if;
  v_source_uid:='pdc-jc-159:'||encode(extensions.digest(convert_to(
    p_intake_id::text||':'||p_attachment_id::text||':'||v_parent_hash||':'||v_attachment_hash,'UTF8'),'sha256'),'hex');
  v_idempotency_key:='pdc-email-import-'||encode(extensions.digest(convert_to(p_intake_id::text||':'||p_attachment_id::text,'UTF8'),'sha256'),'hex');
  select jsonb_agg(jsonb_build_object(
    'operation_no',line->>'operation_no','work_key',line->>'work_key','description',line->>'description',
    'estimated_hours',(line->>'estimated_hours')::numeric,'estimated_hours_source','job_card') order by ordinality)
  into v_canonical_lines from jsonb_array_elements(v_input_lines) with ordinality x(line,ordinality);
  v_operation_count:=jsonb_array_length(v_canonical_lines);
  select sum((x->>'estimated_hours')::numeric) into v_hours_sum from jsonb_array_elements(v_canonical_lines) x;
  v_requested_digest:=encode(extensions.digest(convert_to(jsonb_build_object(
    'contract_version','159.1','actor_id',v_actor,'intake_id',p_intake_id,'attachment_id',p_attachment_id,
    'parent_source_hash',v_parent_hash,'attachment_source_hash',v_attachment_hash,'source_uid',v_source_uid,
    'authentication',v_auth,'email_vehicle',v_email_vehicle,'required_work',v_required_work,
    'operation_lines',v_input_lines)::text,'UTF8'),'sha256'),'hex');

  perform pg_advisory_xact_lock(hashtextextended('pdc-jobcard-attachment-159:'||p_intake_id::text||':'||p_attachment_id::text,0));
  select * into v_existing from public.pdc_jobcard_attachment_import_receipts
   where actor_id=v_actor and intake_id=p_intake_id and attachment_id=p_attachment_id;
  if found then
    if v_existing.requested_payload_sha256<>v_requested_digest
       or v_existing.parent_source_hash<>v_parent_hash
       or v_existing.attachment_source_hash<>v_attachment_hash then
      return public.navision_backend_response(false,'attachment_replay_conflict');
    end if;
    -- Exact replay returns verified stable readback before any delegated call or DML.
    return public.read_pdc_jobcard_attachment_import_receipt(v_existing.receipt_id);
  end if;

  if v_intake.duplicate_of is not null or v_intake.status in ('duplicate_detected','failed','ignored','vehicle_created','vehicle_updated')
     or v_intake.received_at is null or v_intake.received_at>clock_timestamp()+interval '5 minutes'
     or v_intake.received_at<clock_timestamp()-interval '30 days' then
    return public.navision_backend_response(false,'intake_duplicate_consumed_or_stale');
  end if;
  if jsonb_typeof(v_email_vehicle->'stock_numbers')<>'array' or jsonb_array_length(v_email_vehicle->'stock_numbers')<>1
     or jsonb_typeof(v_email_vehicle->'vins')<>'array' or jsonb_array_length(v_email_vehicle->'vins')>1
     or jsonb_typeof(v_email_vehicle->'conflicts')<>'array' or v_email_vehicle->'conflicts'<>'[]'::jsonb
     or v_email_vehicle->'cancelled' is distinct from 'false'::jsonb then
    return public.navision_backend_response(false,'email_vehicle_not_exact_or_conflicted');
  end if;
  v_stock:=public.normalize_vehicle_stock_number(v_email_vehicle->'stock_numbers'->>0);
  v_job_card:=btrim(coalesce(v_email_vehicle->>'job_card_number',''));
  if not public.is_real_vehicle_stock_number(v_stock) or length(v_job_card) not between 1 and 80 or v_job_card~'[[:cntrl:]]' then
    return public.navision_backend_response(false,'invalid_vehicle_identity');
  end if;
  v_observations:=jsonb_build_object(
    'attachment_manifest',jsonb_build_array(jsonb_build_object(
      'attachment_id',v_attachment.id,'source_hash',v_attachment_hash,'file_name',v_attachment.file_name,
      'size_bytes',v_attachment.size_bytes,'content_type',v_attachment.content_type)),
    'authenticated',true,'conflicts','[]'::jsonb,'customer',v_email_vehicle->'customer_name',
    'eta_to_kewdale',v_email_vehicle->'eta_to_kewdale','location_evidence','retained_ai_email_attachment',
    'match_outcome','resolved_navision_exact','match_reason','exact retained job-card attachment adapter',
    'required_work',v_required_work,'sender_domain',split_part(v_sender,'@',2),'vehicle',v_email_vehicle);

  -- Every nested mutation is a PL/pgSQL subtransaction. Any false delegate result
  -- is converted to an exception, rolling back proposal, activation, vehicle/work,
  -- operation lines, receipts, audit and intake update as one atomic unit.
  begin
    v_nested_marker:=true;
    v_submit:=public.submit_pdc_ai_intake_observation(
      v_parent_hash,v_attachment_hash,v_source_uid,v_sender,v_auth,v_intake.received_at,
      v_subject,'board_activate_only',v_stock,'Canonical retained job-card attachment import',v_observations);
    if not coalesce((v_submit->>'ok')::boolean,false)
       or not coalesce((v_submit->'data'->'auto_activation'->>'ok')::boolean,false) then
      v_failure:=coalesce(v_submit,public.navision_backend_response(false,'observation_failed'));
      raise exception 'PDC_159_NESTED_FALSE_RESULT' using errcode='P0001';
    end if;
    v_proposal_id:=nullif(v_submit->'data'->>'proposal_id','')::uuid;
    if v_proposal_id is null or not exists(select 1 from public.pdc_ai_intake_proposals p where p.proposal_id=v_proposal_id and p.status='applied') then
      v_failure:=public.navision_backend_response(false,'activation_not_applied');
      raise exception 'PDC_159_NESTED_FALSE_RESULT' using errcode='P0001';
    end if;

    v_vehicle_result:=public.import_pdc_authenticated_vehicle_email(
      v_idempotency_key,v_parent_hash,v_attachment_hash,v_source_uid,v_sender,v_auth,
      v_intake.received_at,v_subject,v_email_vehicle,v_required_work);
    if not coalesce((v_vehicle_result->>'ok')::boolean,false) then
      v_failure:=v_vehicle_result;
      raise exception 'PDC_159_NESTED_FALSE_RESULT' using errcode='P0001';
    end if;

    v_hours_result:=public.import_pdc_authenticated_email_operations_with_hours(
      v_parent_hash,v_source_uid,v_canonical_lines);
    if not coalesce((v_hours_result->>'ok')::boolean,false) then
      v_failure:=v_hours_result;
      raise exception 'PDC_159_NESTED_FALSE_RESULT' using errcode='P0001';
    end if;

    select * into v_import_receipt from public.pdc_authenticated_email_import_receipts
     where actor_id=v_actor and source_hash=v_parent_hash and source_uid=v_source_uid for share;
    if not found then
      v_failure:=public.navision_backend_response(false,'canonical_import_receipt_missing');
      raise exception 'PDC_159_NESTED_FALSE_RESULT' using errcode='P0001';
    end if;
    select * into v_vehicle from public.vehicles where id=v_import_receipt.vehicle_id for share;
    select * into v_backend from public.navision_backend_records where id=v_import_receipt.backend_record_id for share;
    if not found or v_vehicle.id is null or v_backend.id is null
       or v_import_receipt.backend_record_version is distinct from v_backend.version
       or v_vehicle.deleted_at is not null or v_vehicle.lifecycle_state<>'active'
       or upper(btrim(coalesce(v_vehicle.current_location,'')))='COMPLETED'
       or upper(btrim(coalesce(v_vehicle.job_card_number,'')))<>upper(v_job_card) then
      v_failure:=public.navision_backend_response(false,'canonical_identity_or_lifecycle_postcondition_failed');
      raise exception 'PDC_159_NESTED_FALSE_RESULT' using errcode='P0001';
    end if;
    select coalesce(array_agg(ol.operation_line_id order by (x.line->>'source_row_no')::integer),'{}'::uuid[]),
      coalesce(jsonb_agg(jsonb_build_object(
        'source_row_no',(x.line->>'source_row_no')::integer,'operation_no',ol.operation_no,
        'operation_line_id',ol.operation_line_id,'work_key',ol.work_key,'description',ol.description,
        'estimated_hours',ol.estimated_hours,'estimated_hours_source',ol.estimated_hours_source
      ) order by (x.line->>'source_row_no')::integer),'[]'::jsonb)
    into v_line_ids,v_canonical_lines
    from jsonb_array_elements(v_input_lines) x(line)
    join public.pdc_authenticated_email_operation_lines ol
      on ol.source_hash=v_parent_hash and ol.source_uid=v_source_uid and ol.vehicle_id=v_vehicle.id
     and ol.operation_no=x.line->>'operation_no' and ol.work_key=x.line->>'work_key'
     and ol.description=x.line->>'description' and ol.estimated_hours=(x.line->>'estimated_hours')::numeric
     and ol.estimated_hours_source='job_card';
    if cardinality(v_line_ids)<>v_operation_count
       or (select count(*) from public.pdc_authenticated_email_operation_lines where source_hash=v_parent_hash)<>v_operation_count then
      v_failure:=public.navision_backend_response(false,'canonical_operation_cardinality_mismatch');
      raise exception 'PDC_159_NESTED_FALSE_RESULT' using errcode='P0001';
    end if;
    v_operation_digest:=encode(extensions.digest(convert_to(v_canonical_lines::text,'UTF8'),'sha256'),'hex');
    v_response:=jsonb_build_object(
      'observation',v_submit,'vehicle_import',v_vehicle_result,'operation_import',v_hours_result,
      'booking_created',false,'completion_created',false,'location_scheduled',false);
    insert into public.pdc_jobcard_attachment_import_receipts(
      receipt_id,contract_version,actor_id,actor_email,intake_id,attachment_id,parent_source_hash,
      attachment_source_hash,attachment_size_bytes,attachment_content_type,source_uid,proposal_id,canonical_import_receipt_id,vehicle_id,vehicle_version,
      backend_record_id,backend_record_version,job_card_number,requested_payload_sha256,operation_sha256,
      operation_count,estimated_hours_sum,canonical_operation_line_ids,response
    ) values(
      v_receipt_id,'159.1',v_actor,v_actor_email,p_intake_id,p_attachment_id,v_parent_hash,
      v_attachment_hash,v_attachment.size_bytes,lower(v_attachment.content_type),v_source_uid,v_proposal_id,v_import_receipt.receipt_id,v_vehicle.id,v_vehicle.version,
      v_backend.id,v_backend.version,v_job_card,v_requested_digest,v_operation_digest,
      v_operation_count,v_hours_sum,v_line_ids,v_response);
    for v_item in select value from jsonb_array_elements(v_input_lines) loop
      select * into strict v_line from public.pdc_authenticated_email_operation_lines
       where source_hash=v_parent_hash and operation_no=v_item->>'operation_no';
      insert into public.pdc_jobcard_attachment_source_row_receipts(
        receipt_id,source_row_no,operation_no,operation_line_id,work_key,description,
        estimated_hours,estimated_hours_source,line_sha256
      ) values(
        v_receipt_id,(v_item->>'source_row_no')::integer,v_line.operation_no,v_line.operation_line_id,
        v_line.work_key,v_line.description,v_line.estimated_hours,v_line.estimated_hours_source,
        encode(extensions.digest(convert_to(jsonb_build_object(
          'source_row_no',(v_item->>'source_row_no')::integer,'operation_no',v_line.operation_no,
          'operation_line_id',v_line.operation_line_id,'work_key',v_line.work_key,'description',v_line.description,
          'estimated_hours',v_line.estimated_hours,'estimated_hours_source',v_line.estimated_hours_source
        )::text,'UTF8'),'sha256'),'hex'));
    end loop;
    insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
    values('insert','pdc_jobcard_attachment_import_receipts',v_receipt_id,v_vehicle.id,v_actor,v_actor_email,null,
      jsonb_build_object('receipt_id',v_receipt_id,'intake_id',p_intake_id,'attachment_id',p_attachment_id,
        'operation_count',v_operation_count,'estimated_hours_sum',v_hours_sum),
      jsonb_build_object('source','bounded_jobcard_attachment_canonical_adapter_159','parent_source_hash',v_parent_hash,
        'attachment_source_hash',v_attachment_hash,'no_booking',true,'no_completion',true,'no_location_scheduling',true));
    update public.ai_email_intake set
      status='vehicle_updated',linked_vehicle_id=v_vehicle.id,
      processing_result=coalesce(processing_result,'{}'::jsonb)||jsonb_build_object(
        'jobcard_attachment_import_receipt_id',v_receipt_id,
        'jobcard_attachment_import_contract','159.1',
        'jobcard_attachment_imported_at',clock_timestamp())
    where id=p_intake_id;
  exception when others then
    if sqlerrm='PDC_159_NESTED_FALSE_RESULT' then
      return coalesce(v_failure,public.navision_backend_response(false,'nested_import_failed'));
    end if;
    return public.navision_backend_response(false,'atomic_attachment_import_failed');
  end;
  return public.read_pdc_jobcard_attachment_import_receipt(v_receipt_id);
end
$adapter$;

create function public.get_pdc_email_intake_work_receipt(
  p_intake_id uuid,
  p_expected_source_hash text,
  p_expected_extraction_hash text
) returns jsonb
language plpgsql stable security definer
set search_path=pg_catalog,public,extensions
as $work_read$
declare
  v_actor uuid:=auth.uid();
  v_source text:=lower(btrim(coalesce(p_expected_source_hash,'')));
  v_extraction text:=lower(btrim(coalesce(p_expected_extraction_hash,'')));
  v_work public.pdc_email_intake_work_receipts%rowtype;
begin
  if not public.pdc_monitor_staging_guard() or v_actor is null
     or v_source!~'^[a-f0-9]{64}$' or v_extraction!~'^[a-f0-9]{64}$' then
    return public.navision_backend_response(false,'unauthorized');
  end if;
  select * into v_work from public.pdc_email_intake_work_receipts
   where intake_id=p_intake_id and actor_id=v_actor;
  if not found then return public.navision_backend_response(false,'work_receipt_not_found'); end if;
  if v_work.source_hash<>v_source or v_work.extraction_hash<>v_extraction then
    return public.navision_backend_response(false,'work_receipt_binding_mismatch');
  end if;
  return public.read_pdc_jobcard_attachment_import_receipt(v_work.attachment_receipt_id);
end
$work_read$;

create function public.process_email_intake_work(
  p_intake_id uuid,
  p_expected_source_hash text,
  p_extraction_hash text,
  p_extraction jsonb,
  p_actor text
) returns jsonb
language plpgsql security definer
set search_path=pg_catalog,public,extensions
set statement_timeout='180s'
as $work$
declare
  v_actor uuid:=auth.uid();
  v_source text:=lower(btrim(coalesce(p_expected_source_hash,'')));
  v_extraction_hash text:=lower(btrim(coalesce(p_extraction_hash,'')));
  v_payload jsonb:=coalesce(p_extraction,'null'::jsonb);
  v_server_hash text;
  v_request text;
  v_existing public.pdc_email_intake_work_receipts%rowtype;
  v_result jsonb;
  v_attachment_receipt public.pdc_jobcard_attachment_import_receipts%rowtype;
begin
  if not public.pdc_monitor_staging_guard() or v_actor is null
     or lower(btrim(coalesce(p_actor,''))) not in ('pdc-monitor','email_intake_service')
     or v_source!~'^[a-f0-9]{64}$' or v_extraction_hash!~'^[a-f0-9]{64}$'
     or jsonb_typeof(v_payload) is distinct from 'object'
     or (select array_agg(k order by k) from jsonb_object_keys(v_payload) k) is distinct from array[
       'authentication','canonical_attachment_id','canonical_document_hash','contract_version',
       'email_vehicle','operation_lines','required_work']::text[]
     or v_payload->>'contract_version'<>'pmb-email-work-v2'
     or coalesce(v_payload->>'canonical_attachment_id','')!~'^[a-f0-9-]{36}$'
     or lower(coalesce(v_payload->>'canonical_document_hash',''))!~'^[a-f0-9]{64}$' then
    return public.navision_backend_response(false,'invalid_work_extraction');
  end if;
  v_server_hash:=encode(extensions.digest(convert_to(v_payload::text,'UTF8'),'sha256'),'hex');
  v_request:=encode(extensions.digest(convert_to(jsonb_build_object(
    'contract_version','159.2','actor_id',v_actor,'intake_id',p_intake_id,
    'source_hash',v_source,'extraction_hash',v_extraction_hash,'server_extraction_hash',v_server_hash,
    'payload',v_payload,'actor_label',lower(btrim(p_actor))
  )::text,'UTF8'),'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended('pdc-email-intake-work-159:'||p_intake_id::text,0));
  select * into v_existing from public.pdc_email_intake_work_receipts where intake_id=p_intake_id;
  if found then
    if v_existing.actor_id<>v_actor or v_existing.source_hash<>v_source
       or v_existing.extraction_hash<>v_extraction_hash
       or v_existing.server_extraction_hash<>v_server_hash or v_existing.request_sha256<>v_request then
      return public.navision_backend_response(false,'work_receipt_replay_conflict');
    end if;
    return public.get_pdc_email_intake_work_receipt(p_intake_id,v_source,v_extraction_hash);
  end if;

  v_result:=public.import_pdc_jobcard_attachment_canonical(
    p_intake_id,(v_payload->>'canonical_attachment_id')::uuid,v_source,
    lower(v_payload->>'canonical_document_hash'),v_payload->'authentication',
    v_payload->'email_vehicle',v_payload->'required_work',v_payload->'operation_lines');
  if not coalesce((v_result->>'ok')::boolean,false) then return v_result; end if;
  select * into v_attachment_receipt from public.pdc_jobcard_attachment_import_receipts
   where intake_id=p_intake_id and actor_id=v_actor;
  if not found then return public.navision_backend_response(false,'attachment_receipt_missing'); end if;
  insert into public.pdc_email_intake_work_receipts(
    intake_id,attachment_receipt_id,actor_id,source_hash,extraction_hash,server_extraction_hash,request_sha256
  ) values(p_intake_id,v_attachment_receipt.receipt_id,v_actor,v_source,v_extraction_hash,v_server_hash,v_request);
  return public.get_pdc_email_intake_work_receipt(p_intake_id,v_source,v_extraction_hash);
exception when unique_violation then
  return public.navision_backend_response(false,'work_receipt_identity_conflict');
end
$work$;

revoke all on function public.attest_pdc_provider_email_observation(uuid,uuid,text,text,text,text,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.attest_pdc_provider_email_observation(uuid,uuid,text,text,text,text,jsonb) to service_role;
revoke all on function public.get_pdc_email_intake_work_receipt(uuid,text,text) from public,anon,authenticated,service_role;
grant execute on function public.get_pdc_email_intake_work_receipt(uuid,text,text) to authenticated;
revoke all on function public.process_email_intake_work(uuid,text,text,jsonb,text) from public,anon,authenticated,service_role;
grant execute on function public.process_email_intake_work(uuid,text,text,jsonb,text) to authenticated;

revoke all on function public.read_pdc_jobcard_attachment_import_receipt(uuid) from public,anon,authenticated,service_role;
grant execute on function public.read_pdc_jobcard_attachment_import_receipt(uuid) to authenticated;
revoke all on function public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb) to authenticated;

comment on function public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb) is
 'Staging-only atomic cap-50 retained AI-email attachment adapter; enrolled approved Viewer/Importer only; canonical job-card hours and source-row receipts; no booking, completion, Parts completion, or location scheduling.';
comment on function public.read_pdc_jobcard_attachment_import_receipt(uuid) is
 'Actor-owned staging receipt reader that re-derives canonical line cardinality, IDs, hours and digest and fails closed on drift.';

do $verify$
declare t text; d text;
begin
  foreach t in array array[
    'pdc_jobcard_attachment_import_receipts','pdc_jobcard_attachment_source_row_receipts',
    'pdc_provider_email_observations','pdc_email_intake_work_receipts'
  ] loop
    if has_table_privilege('anon','public.'||t,'SELECT')
       or has_table_privilege('authenticated','public.'||t,'SELECT')
       or has_table_privilege('service_role','public.'||t,'SELECT')
       or has_table_privilege('service_role','public.'||t,'INSERT')
       or has_table_privilege('service_role','public.'||t,'UPDATE')
       or has_table_privilege('service_role','public.'||t,'DELETE')
       or not exists(select 1 from pg_trigger where tgrelid=to_regclass('public.'||t)
         and tgname=t||'_immutable' and not tgisinternal and tgenabled<>'D') then
      raise exception 'PDC_159_RECEIPT_ACL_OR_IMMUTABILITY_FAILED:%',t;
    end if;
  end loop;
  if has_table_privilege('anon','public.pdc_monitor_exact_sender_enrollments','SELECT')
     or has_table_privilege('authenticated','public.pdc_monitor_exact_sender_enrollments','SELECT')
     or has_table_privilege('service_role','public.pdc_monitor_exact_sender_enrollments','SELECT') then
    raise exception 'PDC_159_SENDER_ENROLLMENT_ACL_FAILED';
  end if;
  select pg_get_functiondef('public.submit_pdc_ai_intake_observation_pre135(text,text,text,text,jsonb,timestamptz,text,text,text,text,jsonb)'::regprocedure) into d;
  if position('pdc_monitor_exact_sender_enrollments' in d)=0
     or position('split_part(v_sender,''@'',2) not in' in d)>0 then
    raise exception 'PDC_159_EXACT_SENDER_POSTCONDITION_FAILED';
  end if;
  select pg_get_functiondef('public.pdc_auto_apply_ai_intake_activation_internal(uuid,uuid,text,boolean)'::regprocedure) into d;
  if position('v_proposal.source_received_at>v_vehicle.board_purged_at' in d)=0 then
    raise exception 'PDC_159_POST_PURGE_FRESHNESS_POSTCONDITION_FAILED';
  end if;
  if has_function_privilege('service_role','public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)','EXECUTE')
     or has_function_privilege('service_role','public.read_pdc_jobcard_attachment_import_receipt(uuid)','EXECUTE')
     or has_function_privilege('service_role','public.process_email_intake_work(uuid,text,text,jsonb,text)','EXECUTE')
     or has_function_privilege('service_role','public.get_pdc_email_intake_work_receipt(uuid,text,text)','EXECUTE')
     or not has_function_privilege('service_role','public.attest_pdc_provider_email_observation(uuid,uuid,text,text,text,text,jsonb)','EXECUTE')
     or has_function_privilege('authenticated','public.attest_pdc_provider_email_observation(uuid,uuid,text,text,text,text,jsonb)','EXECUTE')
     or not has_function_privilege('authenticated','public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)','EXECUTE')
     or not has_function_privilege('authenticated','public.read_pdc_jobcard_attachment_import_receipt(uuid)','EXECUTE')
     or not has_function_privilege('authenticated','public.process_email_intake_work(uuid,text,text,jsonb,text)','EXECUTE')
     or not has_function_privilege('authenticated','public.get_pdc_email_intake_work_receipt(uuid,text,text)','EXECUTE') then
    raise exception 'PDC_159_RPC_ACL_FAILED';
  end if;
  select pg_get_functiondef('public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)'::regprocedure) into d;
  if position('PDC_159_NESTED_FALSE_RESULT' in d)=0
     or position('submit_pdc_ai_intake_observation' in d)=0
     or position('import_pdc_authenticated_vehicle_email' in d)=0
     or position('import_pdc_authenticated_email_operations_with_hours' in d)=0
     or position('workshop_bookings' in lower(d))>0
     or position('vehicle_parts_updates' in lower(d))>0 then
    raise exception 'PDC_159_ADAPTER_POSTCONDITION_FAILED';
  end if;
  insert into supabase_migrations.schema_migrations(version,name,statements) values(
    '159','bounded_jobcard_attachment_canonical_adapter',array[
      'bind exact retained AI intake, active monitored mailbox, exact hash-enrolled sender and one bounded attachment to server-derived source evidence',
      'require an immutable service-role provider observation from mx.google.com before the authenticated monitor actor may mutate operational state',
      'narrow Migration158 direct submission to exact sender enrollment and reject evidence received before a later deliberate Board purge',
      'provide the caller-compatible process_email_intake_work adapter and source/extraction-bound exact receipt reader for the pdc-monitor handoff',
      'adapt cap-50 positive unique source rows into ordered OP1..OPn canonical job-card hour payloads with exact required-work set equality',
      'execute observation, automatic Board activation, canonical vehicle receipt and operation-hour import in one rollback-on-false subtransaction',
      'retain immutable actor/source/identity/version/digest/line receipts with actor-owned drift-detecting readback',
      'preserve lifecycle and duplicate protections; create no bookings, completions, Parts completion or location scheduling'
    ]);
  insert into public.audit_events(action,table_name,actor_id,actor_email,before_data,after_data,metadata)
  values('insert','supabase_migrations.schema_migrations',auth.uid(),public.current_actor_email(),null,
    jsonb_build_object('migration','159_bounded_jobcard_attachment_canonical_adapter'),
    jsonb_build_object('source','staging_migration_159','environment','staging','production_unchanged',true));
end
$verify$;
commit;
