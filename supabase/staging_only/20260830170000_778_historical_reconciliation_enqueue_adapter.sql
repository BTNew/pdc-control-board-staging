-- STAGING ONLY 778: UUID-free, exact 773-derived historical reconciliation successor.
-- Append-only successor to 20260830162000 / 777 repair2. This is a separately
-- callable bounded contract, not normal automation and not a historical Apply job.
-- It uses the approved provider-bound enqueue path, then derives server IDs by hash.
begin;
set local lock_timeout='15s';
set local statement_timeout='300s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-778-historical-reconciliation-enqueue-adapter',0));
lock table supabase_migrations.schema_migrations in exclusive mode;

do $guard$
begin
  if current_user<>'postgres' or session_user<>'postgres'
     or not public.pdc_monitor_staging_guard()
     or (select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')<>1
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or not exists(select 1 from supabase_migrations.schema_migrations where version='20260830166000' and name='777_historical_reconciliation_canonical_adapter_repair2')
     or to_regclass('public.pdc_historical_reconciliation_writer_authorizations_773') is null
     or (select count(*) from public.pdc_historical_reconciliation_writer_authorizations_773)<>15
     or exists(select 1 from public.pdc_historical_reconciliation_writer_authorizations_773 where provider_uid='1:197' or stock_number='13056899')
     or not exists(select 1 from public.pdc_email_monitor_current_head_compatibility_controls_766 where singleton and enabled and actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' and actor_email='sales@broometoyota.com.au' and gateway_instance_id='pdc-monitor-staging-sales-uid509-v1' and not task_enabled and not mailbox_contacted and not production_writes)
     or to_regprocedure('public.pdc_historical_writer_authorized_773(text,text,text,jsonb,text)') is null
     or to_regprocedure('public.enqueue_pdc_email_intake(jsonb,jsonb)') is null
     or to_regprocedure('public.submit_pdc_ai_intake_observation_pre135(text,text,text,text,jsonb,timestamp with time zone,text,text,text,text,jsonb)') is null
     or to_regprocedure('public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)') is null
     or to_regprocedure('public.import_pdc_authenticated_email_operations_with_hours(text,text,jsonb)') is null
     or exists(select 1 from supabase_migrations.schema_migrations where version='20260830170000') then
    raise exception 'PDC_778_EXACT_777_PREDECESSOR_OR_CANONICAL_CONTRACT_MISMATCH' using errcode='55000';
  end if;
end
$guard$;

-- One immutable observation per server-derived attachment. The existing 159 table
-- is intentionally one-per-intake; this table keeps multi-child historical evidence
-- separate and lets the canonical child gate accept only this exact 773 exception.
create table public.pdc_historical_provider_observations_778(
  observation_id uuid primary key default gen_random_uuid(),
  contract_version text not null check(contract_version='778.1'),
  authorization_id uuid not null references public.pdc_historical_reconciliation_writer_authorizations_773(authorization_id) on delete restrict,
  actor_id uuid not null check(actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'),
  actor_email text not null check(actor_email='sales@broometoyota.com.au'),
  gateway_instance_id text not null check(gateway_instance_id='pdc-monitor-staging-sales-uid509-v1'),
  manifest_sha256 text not null check(manifest_sha256='aa9e2451645b3fc51eba68c422b5eaf6f146ed18596a94ce8560c55b80729018'),
  provider_uid text not null check(provider_uid~'^1:[1-9][0-9]{0,5}$' and provider_uid<>'1:197'),
  parent_source_hash text not null check(parent_source_hash~'^[a-f0-9]{64}$'),
  sender_email text not null check(sender_email=lower(btrim(sender_email))),
  stock_number text not null check(stock_number<>'13056899' and public.is_real_vehicle_stock_number(stock_number)),
  intake_id uuid not null references public.ai_email_intake(id) on delete restrict,
  attachment_id uuid not null references public.ai_email_attachments(id) on delete restrict,
  attachment_source_hash text not null check(attachment_source_hash~'^[a-f0-9]{64}$'),
  provider_message_id text not null check(length(provider_message_id) between 1 and 1024),
  provider_authserv_id text not null check(provider_authserv_id='mx.google.com'),
  authentication jsonb not null check(jsonb_typeof(authentication)='object'),
  request_sha256 text not null unique check(request_sha256~'^[a-f0-9]{64}$'),
  observed_at timestamptz not null default clock_timestamp(),
  unique(intake_id,attachment_id),
  unique(intake_id,attachment_source_hash)
);
alter table public.pdc_historical_provider_observations_778 enable row level security;
alter table public.pdc_historical_provider_observations_778 force row level security;
revoke all on table public.pdc_historical_provider_observations_778 from public,anon,authenticated,service_role,pdc_email_monitor;

create table public.pdc_historical_reconciliation_778_receipts(
  receipt_id uuid primary key default gen_random_uuid(),
  contract_version text not null check(contract_version='778.1'),
  actor_id uuid not null check(actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'),
  actor_email text not null check(actor_email='sales@broometoyota.com.au'),
  gateway_instance_id text not null check(gateway_instance_id='pdc-monitor-staging-sales-uid509-v1'),
  manifest_sha256 text not null check(manifest_sha256='aa9e2451645b3fc51eba68c422b5eaf6f146ed18596a94ce8560c55b80729018'),
  provider_uid text not null check(provider_uid<>'1:197'),
  parent_source_hash text not null check(parent_source_hash~'^[a-f0-9]{64}$'),
  sender_email text not null,
  stock_number text not null check(stock_number<>'13056899'),
  request_sha256 text not null unique check(request_sha256~'^[a-f0-9]{64}$'),
  intake_id uuid not null references public.ai_email_intake(id) on delete restrict,
  attachment_count integer not null check(attachment_count between 1 and 25),
  job_card_count integer not null check(job_card_count between 0 and 25),
  sibling_count integer not null check(sibling_count between 0 and 25),
  request_evidence jsonb not null check(jsonb_typeof(request_evidence)='object'),
  canonical_response jsonb not null check(jsonb_typeof(canonical_response)='object'),
  created_at timestamptz not null default clock_timestamp(),
  unique(actor_id,provider_uid,parent_source_hash)
);
alter table public.pdc_historical_reconciliation_778_receipts enable row level security;
alter table public.pdc_historical_reconciliation_778_receipts force row level security;
revoke all on table public.pdc_historical_reconciliation_778_receipts from public,anon,authenticated,service_role,pdc_email_monitor;

create function public.pdc_historical_778_receipt_immutable()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $immutable$
begin raise exception 'PDC_778_RECEIPT_IMMUTABLE' using errcode='55000'; end
$immutable$;
revoke all on function public.pdc_historical_778_receipt_immutable() from public,anon,authenticated,service_role,pdc_email_monitor;
create trigger pdc_historical_provider_observations_778_immutable before update or delete on public.pdc_historical_provider_observations_778 for each row execute function public.pdc_historical_778_receipt_immutable();
create trigger pdc_historical_reconciliation_778_receipts_immutable before update or delete on public.pdc_historical_reconciliation_778_receipts for each row execute function public.pdc_historical_778_receipt_immutable();

-- Narrowly permit the exact 773 tuple through the approved enqueue path. Ordinary
-- senders still require the pre-existing exact enrollment table.
do $patch_enqueue$
declare d text; old_gate text; new_gate text;
begin
  select pg_get_functiondef('public.enqueue_pdc_email_intake(jsonb,jsonb)'::regprocedure) into d;
  old_gate:=$old$v_sender_enrolled:=EXISTS(SELECT 1 FROM public.pdc_monitor_exact_sender_enrollments e WHERE e.active AND e.sender_sha256=v_sender_hash);$old$;
  new_gate:=$new$v_sender_enrolled:=EXISTS(SELECT 1 FROM public.pdc_monitor_exact_sender_enrollments e WHERE e.active AND e.sender_sha256=v_sender_hash)
    OR public.pdc_historical_writer_authorized_773(lower(coalesce(p_message->>'source_hash','')),btrim(coalesce(p_message->>'provider_uid','')),v_sender,v_auth,p_message->>'stock_number');$new$;
  if position(old_gate in d)=0 or position('pdc_historical_writer_authorized_773' in d)>0 then raise exception 'PDC_778_ENQUEUE_GATE_DRIFT' using errcode='55000'; end if;
  execute replace(d,old_gate,new_gate);
end
$patch_enqueue$;

-- The canonical child importer keeps its ordinary sender/observation/revision/
-- identity/hour/Sublet/unmapped rules. Only this exact 773-derived sender and
-- per-attachment observation is an additional accepted provenance.
do $patch_child$
declare d text; old_sender text; new_sender text; old_observation text; new_observation text; old_status text; new_status text;
begin
  select pg_get_functiondef('public.import_pdc_jobcard_attachment_canonical(uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb)'::regprocedure) into d;
  old_sender:=$old$or not exists(select 1 from public.pdc_monitor_exact_sender_enrollments e where e.active
       and e.sender_sha256=encode(extensions.digest(convert_to(v_sender,'UTF8'),'sha256'),'hex'))$old$;
  new_sender:=$new$or (not exists(select 1 from public.pdc_monitor_exact_sender_enrollments e where e.active
       and e.sender_sha256=encode(extensions.digest(convert_to(v_sender,'UTF8'),'sha256'),'hex'))
       and not public.pdc_historical_writer_authorized_773(v_parent_hash,coalesce(v_intake.provider_uid,''),v_sender,v_auth,v_email_vehicle->'stock_numbers'->>0))$new$;
  if position(old_sender in d)=0 then raise exception 'PDC_778_CHILD_SENDER_GATE_DRIFT' using errcode='55000'; end if;
  d:=replace(d,old_sender,new_sender);
  old_observation:=$old$if not found
     or v_provider_observation.parent_source_hash<>v_parent_hash
     or v_provider_observation.attachment_source_hash<>v_attachment_hash
     or v_provider_observation.provider_authserv_id<>'mx.google.com'
     or v_provider_observation.authentication is distinct from v_auth then$old$;
  new_observation:=$new$if (not found
     or v_provider_observation.parent_source_hash<>v_parent_hash
     or v_provider_observation.attachment_source_hash<>v_attachment_hash
     or v_provider_observation.provider_authserv_id<>'mx.google.com'
     or v_provider_observation.authentication is distinct from v_auth)
     and not exists(select 1 from public.pdc_historical_provider_observations_778 h
       where h.intake_id=p_intake_id and h.attachment_id=p_attachment_id
         and h.manifest_sha256='aa9e2451645b3fc51eba68c422b5eaf6f146ed18596a94ce8560c55b80729018'
         and h.provider_uid=coalesce(v_intake.provider_uid,'') and h.parent_source_hash=v_parent_hash
         and h.attachment_source_hash=v_attachment_hash and h.sender_email=v_sender
         and h.actor_id=v_actor and h.actor_email=v_actor_email and h.gateway_instance_id='pdc-monitor-staging-sales-uid509-v1'
         and public.pdc_historical_writer_authorized_773(v_parent_hash,h.provider_uid,v_sender,v_auth,v_email_vehicle->'stock_numbers'->>0)) then$new$;
  if position(old_observation in d)=0 then raise exception 'PDC_778_CHILD_OBSERVATION_GATE_DRIFT' using errcode='55000'; end if;
  d:=replace(d,old_observation,new_observation);
  old_status:=$old$if v_intake.duplicate_of is not null or (v_intake.status in ('duplicate_detected','failed','ignored','vehicle_created') or (v_intake.status='vehicle_updated' and v_intake.processing_result->>'uid478_attachment_atomic_contract' is distinct from '233.1'))$old$;
  new_status:=$new$if v_intake.duplicate_of is not null or v_intake.status in ('duplicate_detected','failed','ignored','vehicle_created')
     or (v_intake.status='vehicle_updated' and v_intake.processing_result->>'uid478_attachment_atomic_contract' is distinct from '233.1'
         and not public.pdc_historical_writer_authorized_773(v_parent_hash,coalesce(v_intake.provider_uid,''),v_sender,v_auth,v_email_vehicle->'stock_numbers'->>0))$new$;
  if position(old_status in d)=0 then raise exception 'PDC_778_CHILD_STATUS_GATE_DRIFT' using errcode='55000'; end if;
  d:=replace(d,old_status,new_status);
  execute d;
end
$patch_child$;

create function public.submit_pdc_historical_reconciliation_778(p_request jsonb)
returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,auth,extensions
set statement_timeout='300s'
as $body$
declare
  v_actor uuid:=auth.uid(); v_actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_request jsonb:=coalesce(p_request,'null'::jsonb); v_authentication jsonb:=coalesce(v_request->'authentication','null'::jsonb);
  v_manifest_sha256 text:=lower(btrim(coalesce(v_request->>'manifest_sha256',''))); v_provider_uid text:=btrim(coalesce(v_request->>'provider_uid',''));
  v_parent_source_hash text:=lower(btrim(coalesce(v_request->>'parent_source_hash',''))); v_sender text:=lower(btrim(coalesce(v_request->>'sender_email','')));
  v_stock text:=public.normalize_vehicle_stock_number(v_request->>'stock_number'); v_manifest_items jsonb:=coalesce(v_request->'attachment_manifest','null'::jsonb);
  v_children jsonb:=coalesce(v_request->'job_card_children','null'::jsonb); v_source jsonb:=coalesce(v_request->'source_metadata','null'::jsonb);
  v_authz public.pdc_historical_reconciliation_writer_authorizations_773%rowtype; v_existing public.pdc_historical_reconciliation_778_receipts%rowtype;
  v_enqueue jsonb; v_parent_observation jsonb; v_child_result jsonb; v_child_results jsonb:='[]'::jsonb;
  v_response jsonb; v_manifest_hash text; v_request_hash text; v_child jsonb; v_item jsonb; v_intake public.ai_email_intake%rowtype;
  v_intake_id uuid; v_attachment_id uuid; v_attachment public.ai_email_attachments%rowtype; v_index integer:=0; v_job_card_count integer:=0; v_sibling_count integer:=0; v_observation_sha text;
begin
  if not public.pdc_monitor_staging_guard() or to_regclass('public.pdc_production_environment_sentinel') is not null
     or v_actor<>'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid or v_actor_email<>'sales@broometoyota.com.au'
     or not public.pdc_monitor_authenticated_active_scope_674('pdc-monitor-staging-sales-uid509-v1')
     or jsonb_typeof(v_request) is distinct from 'object'
     or (select array_agg(k order by k) from jsonb_object_keys(v_request) k) is distinct from array[
       'action_type','attachment_manifest','authentication','evidence_hash','job_card_children','manifest_sha256','observations','parent_source_hash','provider_uid','sender_email','source_metadata','stock_number','subject','summary']::text[] then
    return jsonb_build_object('ok',false,'code','unauthorized');
  end if;
  if v_manifest_sha256<>'aa9e2451645b3fc51eba68c422b5eaf6f146ed18596a94ce8560c55b80729018'
     or v_provider_uid!~'^1:[1-9][0-9]{0,5}$' or v_provider_uid='1:197' or v_parent_source_hash!~'^[a-f0-9]{64}$'
     or v_sender!~'^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?$'
     or jsonb_typeof(v_authentication) is distinct from 'object' or jsonb_typeof(v_manifest_items) is distinct from 'array'
     or jsonb_array_length(v_manifest_items) not between 1 and 25 or jsonb_typeof(v_children) is distinct from 'array'
     or jsonb_array_length(v_children)>25 or jsonb_typeof(v_source) is distinct from 'object'
     or length(coalesce(v_request->>'evidence_hash',''))<>64 or length(coalesce(v_request->>'subject','')) not between 1 and 300
     or length(coalesce(v_request->>'summary','')) not between 5 and 2000 or length(coalesce(v_request->>'action_type','')) not between 1 and 80 then
    return jsonb_build_object('ok',false,'code','invalid_input');
  end if;
  if v_stock='13056899' or not public.is_real_vehicle_stock_number(v_stock) then return jsonb_build_object('ok',false,'code','historical_reference_stock_excluded'); end if;
  if (select array_agg(k order by k) from jsonb_object_keys(v_source) k) is distinct from array[
       'attachment_names','graph_message_id','internet_message_id','parsed_text','provider_authserv_id','raw_body','received_at','recipient_mailbox','sender_name','uid','uidvalidity']::text[]
     or (v_source->>'uidvalidity')::integer<>1 or (v_source->>'uid')::integer<>substring(v_provider_uid from '^1:([0-9]+)$')::integer
     or v_source->>'provider_authserv_id'<>'mx.google.com' or v_source->>'received_at' is null
     or v_source->>'recipient_mailbox' is null then return jsonb_build_object('ok',false,'code','invalid_source_metadata'); end if;
  select * into v_authz from public.pdc_historical_reconciliation_writer_authorizations_773 e
   where e.active and e.manifest_sha256=v_manifest_sha256 and e.provider_uid=v_provider_uid and e.parent_source_hash=v_parent_source_hash
     and e.sender_email=v_sender and e.sender_sha256=encode(extensions.digest(convert_to(v_sender,'UTF8'),'sha256'),'hex')
     and e.provider_authentication is not distinct from v_authentication and public.normalize_vehicle_stock_number(e.stock_number)=v_stock
     and e.authorized_actor_id=v_actor and e.authorized_actor_email=v_actor_email and e.authorized_gateway_instance_id='pdc-monitor-staging-sales-uid509-v1';
  if not found then return jsonb_build_object('ok',false,'code','PDC_778_EXACT_AUTHORIZATION_FAILED'); end if;
  v_manifest_hash:=encode(extensions.digest(convert_to(v_manifest_items::text,'UTF8'),'sha256'),'hex');
  if v_manifest_items is distinct from v_authz.attachment_manifest or v_manifest_hash<>v_authz.attachment_manifest_sha256
     or (select jsonb_array_length(v_manifest_items))<>v_authz.attachment_count then return jsonb_build_object('ok',false,'code','historical_attachment_manifest_mismatch'); end if;
  if exists(select 1 from jsonb_array_elements(v_manifest_items) m where lower(coalesce(m->>'sha256',''))!~'^[a-f0-9]{64}' or (m->>'filename') is null or (m->>'content_type') is null or (m->>'size')!~'^[1-9][0-9]{0,7}$') then return jsonb_build_object('ok',false,'code','invalid_attachment_metadata'); end if;
  v_request_hash:=encode(extensions.digest(convert_to(v_request::text,'UTF8'),'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended('pdc-778:'||v_provider_uid||':'||v_parent_source_hash,0));
  select * into v_existing from public.pdc_historical_reconciliation_778_receipts where actor_id=v_actor and provider_uid=v_provider_uid and parent_source_hash=v_parent_source_hash;
  if found then if v_existing.request_sha256<>v_request_hash then return jsonb_build_object('ok',false,'code','historical_replay_conflict'); end if; return v_existing.canonical_response; end if;

  -- The exact provider-bound enqueue remains the only parent/attachment creation path.
-- Approved enqueue call shape: enqueue_pdc_email_intake(p_message,p_attachments).
  v_enqueue:=public.enqueue_pdc_email_intake(
    jsonb_build_object('graph_message_id',v_source->>'graph_message_id','internet_message_id',v_source->>'internet_message_id','provider_uid',v_provider_uid,
      'source_hash',v_parent_source_hash,'subject',v_request->>'subject','sender_email',v_sender,'sender_name',v_source->>'sender_name','received_at',v_source->>'received_at',
      'raw_body',v_source->>'raw_body','parsed_text',v_source->>'parsed_text','attachment_names',v_source->'attachment_names','recipient_mailbox',lower(v_source->>'recipient_mailbox'),
      'provider_authserv_id',v_source->>'provider_authserv_id','provider_authentication',v_authentication,'stock_number',v_stock),
    (select jsonb_agg(jsonb_build_object('graph_attachment_id',v_provider_uid||':historical-778-'||lower(x.m->>'sha256'),'file_name',x.m->>'filename','content_type',x.m->>'content_type',
      'size_bytes',(x.m->>'size')::bigint,'source_hash',lower(x.m->>'sha256'),'storage_path','pdc-email-intake-private/historical-778/'||lower(x.m->>'sha256'),'validation_status','verified') order by x.ordinality)
     from jsonb_array_elements(v_manifest_items) with ordinality as x(m,ordinality))
  );
  if not coalesce((v_enqueue->>'ok')::boolean,false) then return v_enqueue; end if;

  begin v_intake_id:=(v_enqueue->>'intake_id')::uuid; exception when others then return jsonb_build_object('ok',false,'code','enqueue_missing_intake_id'); end;
  select * into v_intake from public.ai_email_intake where id=v_intake_id for update;
  if not found or lower(v_intake.source_hash)<>v_parent_source_hash or v_intake.provider_uid<>v_provider_uid or lower(v_intake.sender_email)<>v_sender
     or v_intake.received_at is distinct from (v_source->>'received_at')::timestamptz or v_intake.internet_message_id is distinct from v_source->>'internet_message_id'
     or v_intake.graph_message_id is distinct from v_source->>'graph_message_id' or v_intake.provider_authentication is distinct from v_authentication then return jsonb_build_object('ok',false,'code','historical_evidence_binding_mismatch'); end if;

  -- non_job_card_sibling attachments remain evidence and are never child-imported.
  for v_item in select value from jsonb_array_elements(v_manifest_items) loop
    -- select id into v_attachment_id is deliberately derived from attachment hash, never caller supplied.
    select a.* into v_attachment from public.ai_email_attachments a where a.intake_id=v_intake_id and lower(a.source_hash)=lower(v_item->>'sha256') and lower(a.file_name)=lower(v_item->>'filename') and a.size_bytes=(v_item->>'size')::bigint;
    if found then v_attachment_id:=v_attachment.id; end if;
    if not found then return jsonb_build_object('ok',false,'code','historical_attachment_evidence_mismatch'); end if;
    v_observation_sha:=encode(extensions.digest(convert_to(jsonb_build_object('contract_version','778.1','authorization_id',v_authz.authorization_id,'intake_id',v_intake_id,'attachment_id',v_attachment_id,'provider_uid',v_provider_uid,'parent_source_hash',v_parent_source_hash,'attachment_source_hash',lower(v_item->>'sha256'),'provider_message_id',v_source->>'internet_message_id','provider_authserv_id',v_source->>'provider_authserv_id','authentication',v_authentication)::text,'UTF8'),'sha256'),'hex');
    insert into public.pdc_historical_provider_observations_778(contract_version,authorization_id,actor_id,actor_email,gateway_instance_id,manifest_sha256,provider_uid,parent_source_hash,sender_email,stock_number,intake_id,attachment_id,attachment_source_hash,provider_message_id,provider_authserv_id,authentication,request_sha256)
    values('778.1',v_authz.authorization_id,v_actor,v_actor_email,'pdc-monitor-staging-sales-uid509-v1',v_manifest_sha256,v_provider_uid,v_parent_source_hash,v_sender,v_stock,v_intake_id,v_attachment_id,lower(v_item->>'sha256'),v_source->>'internet_message_id',v_source->>'provider_authserv_id',v_authentication,v_observation_sha)
    on conflict(intake_id,attachment_id) do nothing;
    if v_item->>'attachment_kind'='job_card' then v_job_card_count:=v_job_card_count+1; else v_sibling_count:=v_sibling_count+1; end if;
  end loop;
  v_parent_observation:=public.submit_pdc_ai_intake_observation_pre135(v_parent_source_hash,lower(v_request->>'evidence_hash'),v_provider_uid,v_sender,v_authentication,(v_source->>'received_at')::timestamptz,v_request->>'subject',v_request->>'action_type',v_stock,v_request->>'summary',v_request->'observations');
  if not coalesce((v_parent_observation->>'ok')::boolean,false) then return v_parent_observation; end if;

  for v_child in select value from jsonb_array_elements(v_children) loop
    v_index:=v_index+1;
    if jsonb_typeof(v_child) is distinct from 'object' or (select array_agg(k order by k) from jsonb_object_keys(v_child) k) is distinct from array['attachment_hash','attachment_kind','extraction','extraction_hash']::text[]
       or v_child->>'attachment_kind'<>'job_card' or lower(coalesce(v_child->>'attachment_hash',''))!~'^[a-f0-9]{64}$' or lower(coalesce(v_child->>'extraction_hash',''))!~'^[a-f0-9]{64}$'
       or jsonb_typeof(v_child->'extraction') is distinct from 'object' or not exists(select 1 from jsonb_array_elements(v_manifest_items) m where lower(m->>'sha256')=lower(v_child->>'attachment_hash')) then
      return jsonb_build_object('ok',false,'code','historical_child_invalid');
    end if;
    select a.* into v_attachment from public.ai_email_attachments a where a.intake_id=v_intake_id and lower(a.source_hash)=lower(v_child->>'attachment_hash');
    if found then v_attachment_id:=v_attachment.id; end if;
    if not found then return jsonb_build_object('ok',false,'code','historical_child_attachment_not_found'); end if;
    v_child_result:=public.import_pdc_jobcard_attachment_canonical(v_intake_id,v_attachment_id,v_parent_source_hash,lower(v_child->>'attachment_hash'),v_authentication,v_child->'extraction'->'email_vehicle',v_child->'extraction'->'required_work',v_child->'extraction'->'operation_lines');
    if not coalesce((v_child_result->>'ok')::boolean,false) then return v_child_result; end if;
    v_child_results:=v_child_results||jsonb_build_array(jsonb_build_object('attachment_hash',lower(v_child->>'attachment_hash'),'derived_attachment_id',v_attachment_id,'receipt',v_child_result));
  end loop;
  v_response:=jsonb_build_object('ok',true,'code','historical_reconciliation_778_receipt','data',jsonb_build_object('contract_version','778.1','manifest_sha256',v_manifest_sha256,'provider_uid',v_provider_uid,'parent_source_hash',v_parent_source_hash,'sender_email',v_sender,'stock_number',v_stock,'intake_id',v_intake_id,'attachment_count',jsonb_array_length(v_manifest_items),'job_card_count',v_job_card_count,'sibling_count',v_sibling_count,'attachment_receipts',v_child_results,'parent_observation',v_parent_observation,'source_metadata',v_source,'attachment_manifest',v_manifest_items,'booking_created',false,'completion_created',false,'location_scheduled',false,'no_booking',true,'no_completion',true,'no_location_mutation',true));
  insert into public.pdc_historical_reconciliation_778_receipts(contract_version,actor_id,actor_email,gateway_instance_id,manifest_sha256,provider_uid,parent_source_hash,sender_email,stock_number,request_sha256,intake_id,attachment_count,job_card_count,sibling_count,request_evidence,canonical_response)
  values('778.1',v_actor,v_actor_email,'pdc-monitor-staging-sales-uid509-v1',v_manifest_sha256,v_provider_uid,v_parent_source_hash,v_sender,v_stock,v_request_hash,v_intake_id,jsonb_array_length(v_manifest_items),v_job_card_count,v_sibling_count,v_request,v_response);
  insert into public.audit_events(action,table_name,actor_id,actor_email,before_data,after_data,metadata) values('insert','pdc_historical_reconciliation_778_receipts',v_actor,v_actor_email,null,jsonb_build_object('provider_uid',v_provider_uid,'parent_source_hash',v_parent_source_hash,'intake_id',v_intake_id,'attachment_count',jsonb_array_length(v_manifest_items),'job_card_count',v_job_card_count,'sibling_count',v_sibling_count),jsonb_build_object('contract','778.1','manifest_sha256',v_manifest_sha256,'no_booking',true,'no_completion',true,'no_location_mutation',true));
  return v_response;
exception when others then
  return jsonb_build_object('ok',false,'code','historical_reconciliation_778_atomic_rollback');
end
$body$;
revoke all on function public.submit_pdc_historical_reconciliation_778(jsonb) from public,anon,authenticated,service_role,pdc_email_monitor;
grant execute on function public.submit_pdc_historical_reconciliation_778(jsonb) to authenticated;

insert into supabase_migrations.schema_migrations(version,name,statements) values('20260830170000','778_historical_reconciliation_enqueue_adapter',array[
 'Guard exact live 777 repair2 predecessor, staging sentinel, current Monitor actor/gateway, 766 controls and Production absence',
 'Accept one UUID-free exact 773-derived request with full source metadata and full attachment manifest; use provider-bound enqueue to create/reuse intake and derive attachment IDs by attachment hash',
 'Persist immutable per-attachment provider observations and aggregate/child receipts; preserve PO/PickList siblings as evidence and exclude UID 1:197 / Stock 13056899',
 'Patch only the canonical child sender/observation/status gates for the exact 773 tuple; ordinary enrollment and all identity/hour/zero/Sublet/unmapped/revision rules remain fail closed',
 'Delegate parent pre135 and canonical job-card/operation-hour contracts; no booking, completion, location, mailbox, credentials, task, Production or global-pilot mutation'
]);

do $verify$
begin
  if (select count(*) from public.pdc_historical_reconciliation_writer_authorizations_773)<>15
     or exists(select 1 from public.pdc_historical_reconciliation_writer_authorizations_773 where provider_uid='1:197' or stock_number='13056899')
     or (select relrowsecurity and relforcerowsecurity from pg_class where oid='public.pdc_historical_provider_observations_778'::regclass) is distinct from true
     or (select relrowsecurity and relforcerowsecurity from pg_class where oid='public.pdc_historical_reconciliation_778_receipts'::regclass) is distinct from true
     or not has_function_privilege('authenticated','public.submit_pdc_historical_reconciliation_778(jsonb)','execute')
     or has_function_privilege('anon','public.submit_pdc_historical_reconciliation_778(jsonb)','execute')
     or has_function_privilege('service_role','public.submit_pdc_historical_reconciliation_778(jsonb)','execute')
     or to_regclass('public.pdc_production_environment_sentinel') is not null then raise exception 'PDC_778_POSTCONDITION_FAILED' using errcode='55000'; end if;
end
$verify$;
notify pgrst,'reload schema';
commit;
