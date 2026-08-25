-- STAGING ONLY migration 324: typed, receipt-backed Monitor Parts completion.
-- The contract is limited to the retained Talin Parker UIDVALIDITY 1 / UID 615
-- source and its exact Parts-complete evidence. It never enables a scheduler,
-- writes mailbox flags, creates bookings, changes location, or grants generic DML.
begin;
set local lock_timeout='10s';
set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-324-typed-monitor-parts-complete',0));

-- This is intentionally an environment/dependency guard rather than a numeric
-- migration-head guess: the staging branch contains timestamped forward fixes,
-- while Production has no corresponding object and must fail closed.
do $guard$
begin
  if not public.pdc_monitor_staging_guard()
     or to_regclass('public.pdc_staging_environment_sentinel') is null
     or (select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')<>1
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or to_regclass('public.ai_email_intake') is null
     or to_regclass('public.ai_email_attachments') is null
     or to_regclass('public.monitored_mailboxes') is null
     or to_regclass('public.pdc_provider_email_observations') is null
     or to_regclass('public.pdc_monitor_exact_sender_enrollments') is null
     or to_regclass('public.pdc_monitor_stage_activation_writers') is null
     or to_regclass('public.pdc_user_roles') is null
     or to_regclass('public.vehicles') is null
     or to_regclass('public.vehicle_aliases') is null
     or to_regclass('public.vehicle_work_items') is null
     or to_regclass('public.vehicle_parts_updates') is null
     or to_regclass('public.audit_events') is null
     or to_regclass('public.pdc_email_vehicle_revision') is null
     or to_regprocedure('public.navision_backend_response(boolean,text,jsonb)') is null
     or to_regprocedure('public.bump_pdc_email_vehicle_revision()') is null
     or exists(select 1 from supabase_migrations.schema_migrations where version='20260825090000')
  then raise exception 'PDC_324_EXACT_STAGING_DEPENDENCY_MISMATCH' using errcode='55000'; end if;
end $guard$;

-- Exact sender enrollment is retained as a hash in the pre-existing enrollment
-- table and repeated here as a purpose-bound rule, never as a domain wildcard.
insert into public.pdc_monitor_exact_sender_enrollments(sender_sha256,purpose)
values('cc12057f15e3ff891893e79a0d5dc5424fb9ee1d4bade8f58b1e4a67b60c40dd','typed Parts completion sender Talin Parker')
on conflict(sender_sha256) do update set purpose=excluded.purpose,active=true;

create table public.pdc_email_parts_complete_rules_324(
  rule_id uuid primary key default gen_random_uuid(),
  rule_key text not null unique check(rule_key='pmb-monitor-parts-complete-13016923'),
  rule_version integer not null unique check(rule_version=1),
  active boolean not null default true,
  normalized_action text not null check(normalized_action='parts_complete'),
  sender_email text not null check(sender_email='talin.parker@pmgwa.com.au'),
  sender_display_name text not null check(sender_display_name='Talin Parker'),
  sender_role text not null check(sender_role='enrolled_parts_completion_sender'),
  sender_sha256 text not null check(sender_sha256='cc12057f15e3ff891893e79a0d5dc5424fb9ee1d4bade8f58b1e4a67b60c40dd'),
  provider text not null check(provider='gmail'),
  provider_authserv_id text not null check(provider_authserv_id='mx.google.com'),
  authentication jsonb not null check(authentication='{"dkim_aligned":true,"dmarc_aligned":false,"gmail_authentication_results":true,"sender_domain":"pmgwa.com.au","spf_aligned":true}'::jsonb),
  mailbox_address text not null check(mailbox_address='pmbcontroller@gmail.com'),
  mailbox_folder text not null check(mailbox_folder='Inbox'),
  uidvalidity bigint not null check(uidvalidity=1),
  uid bigint not null check(uid=615),
  provider_message_id text not null check(provider_message_id='<SY1P282MB635569B0CA01A2D8BA5CE4E8ACA02@SY1P282MB6355.AUSP282.PROD.OUTLOOK.COM>'),
  parent_source_hash text not null check(parent_source_hash='721e14afcdede43ef0091ae34456fbc4ba55dbe9696509f2b9bfe6b163b162f8'),
  subject_exact text not null check(subject_exact='RE: 13016923'),
  body_policy text not null check(body_policy='current_unquoted_definitive_parts_complete_only'),
  body_equivalents text[] not null check(body_equivalents=array['Parts complete','Parts completed','Parts received']::text[]),
  stock_number text not null check(stock_number='13016923'),
  priority integer not null check(priority=1500),
  authorising_task_ref text not null check(authorising_task_ref='t_1a35c0e0'),
  created_at timestamptz not null default clock_timestamp(),
  disabled_at timestamptz,
  disabled_reason text,
  rollback_at timestamptz,
  rollback_reason text
);
alter table public.pdc_email_parts_complete_rules_324 enable row level security;
revoke all on public.pdc_email_parts_complete_rules_324 from public,anon,authenticated,service_role;

create table public.pdc_email_parts_complete_rule_history_324(
  event_id uuid primary key default gen_random_uuid(),
  rule_id uuid not null references public.pdc_email_parts_complete_rules_324(rule_id) on delete restrict,
  rule_version integer not null check(rule_version=1),
  event_type text not null check(event_type in('applied','disabled','rollback')),
  event_reason text not null check(length(btrim(event_reason)) between 3 and 500),
  actor_id uuid references auth.users(id) on delete restrict,
  actor_email text,
  migration_version text not null check(migration_version='20260825090000'),
  metadata jsonb not null default '{}'::jsonb check(jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default clock_timestamp()
);
alter table public.pdc_email_parts_complete_rule_history_324 enable row level security;
revoke all on public.pdc_email_parts_complete_rule_history_324 from public,anon,authenticated,service_role;

create function public.pdc_parts_complete_rule_history_immutable_324()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
begin raise exception 'PDC_324_RULE_HISTORY_IMMUTABLE' using errcode='55000'; end $$;
revoke all on function public.pdc_parts_complete_rule_history_immutable_324() from public,anon,authenticated,service_role;
create trigger pdc_email_parts_complete_rule_history_immutable_324
before update or delete on public.pdc_email_parts_complete_rule_history_324
for each row execute function public.pdc_parts_complete_rule_history_immutable_324();

insert into public.pdc_email_parts_complete_rules_324(
  rule_key,rule_version,active,normalized_action,sender_email,sender_display_name,sender_role,sender_sha256,
  provider,provider_authserv_id,authentication,mailbox_address,mailbox_folder,uidvalidity,uid,provider_message_id,
  parent_source_hash,subject_exact,body_policy,body_equivalents,stock_number,priority,authorising_task_ref
) values(
  'pmb-monitor-parts-complete-13016923',1,true,'parts_complete','talin.parker@pmgwa.com.au','Talin Parker',
  'enrolled_parts_completion_sender','cc12057f15e3ff891893e79a0d5dc5424fb9ee1d4bade8f58b1e4a67b60c40dd',
  'gmail','mx.google.com','{"dkim_aligned":true,"dmarc_aligned":false,"gmail_authentication_results":true,"sender_domain":"pmgwa.com.au","spf_aligned":true}'::jsonb,
  'pmbcontroller@gmail.com','Inbox',1,615,
  '<SY1P282MB635569B0CA01A2D8BA5CE4E8ACA02@SY1P282MB6355.AUSP282.PROD.OUTLOOK.COM>',
  '721e14afcdede43ef0091ae34456fbc4ba55dbe9696509f2b9bfe6b163b162f8',
  'RE: 13016923','current_unquoted_definitive_parts_complete_only',
  array['Parts complete','Parts completed','Parts received']::text[],'13016923',1500,'t_1a35c0e0'
);
insert into public.pdc_email_parts_complete_rule_history_324(rule_id,rule_version,event_type,event_reason,actor_id,actor_email,migration_version,metadata)
select rule_id,rule_version,'applied','Craig-authorised staging rule installed from task t_3d2538d9',null,'migration-324','20260825090000','{}'::jsonb
from public.pdc_email_parts_complete_rules_324 where rule_key='pmb-monitor-parts-complete-13016923';

create table public.pdc_email_parts_complete_receipts_324(
  receipt_id uuid primary key default gen_random_uuid(),
  contract_version text not null check(contract_version='pmb-monitor-parts-complete-v1'),
  rule_id uuid not null references public.pdc_email_parts_complete_rules_324(rule_id) on delete restrict,
  rule_version integer not null check(rule_version=1),
  actor_id uuid not null references auth.users(id) on delete restrict,
  actor_email text not null check(actor_email='pmbcontroller@gmail.com'),
  gateway_instance_id text not null check(gateway_instance_id='pdc-monitor-staging-pmbcontroller-hourly-v1'),
  intake_id uuid not null unique references public.ai_email_intake(id) on delete restrict,
  claim_token uuid not null,
  parent_source_hash text not null unique check(parent_source_hash='721e14afcdede43ef0091ae34456fbc4ba55dbe9696509f2b9bfe6b163b162f8'),
  mailbox_address text not null check(mailbox_address='pmbcontroller@gmail.com'),
  mailbox_folder text not null check(mailbox_folder='Inbox'),
  uidvalidity bigint not null check(uidvalidity=1),
  uid bigint not null check(uid=615),
  provider_message_id text not null unique check(provider_message_id='<SY1P282MB635569B0CA01A2D8BA5CE4E8ACA02@SY1P282MB6355.AUSP282.PROD.OUTLOOK.COM>'),
  provider_authserv_id text not null check(provider_authserv_id='mx.google.com'),
  authentication jsonb not null,
  sender_email text not null check(sender_email='talin.parker@pmgwa.com.au'),
  sender_display_name text not null check(sender_display_name='Talin Parker'),
  subject_evidence text not null check(subject_evidence='RE: 13016923'),
  current_unquoted_evidence text not null check(current_unquoted_evidence in('Parts complete','Parts completed','Parts received')),
  stock_number text not null check(stock_number='13016923'),
  attachment_id uuid not null references public.ai_email_attachments(id) on delete restrict,
  attachment_source_hash text not null check(attachment_source_hash~'^[a-f0-9]{64}$'),
  vehicle_id uuid not null references public.vehicles(id) on delete restrict,
  vehicle_version_before integer not null check(vehicle_version_before>=1),
  vehicle_version_after integer not null check(vehicle_version_after=vehicle_version_before+1),
  shared_revision_before bigint not null,
  shared_revision_after bigint not null check(shared_revision_after=shared_revision_before+1),
  request_sha256 text not null unique check(request_sha256~'^[a-f0-9]{64}$'),
  response jsonb not null check(jsonb_typeof(response)='object'),
  created_at timestamptz not null default clock_timestamp()
);

create table public.pdc_email_parts_complete_action_receipts_324(
  action_receipt_id uuid primary key default gen_random_uuid(),
  receipt_id uuid not null unique references public.pdc_email_parts_complete_receipts_324(receipt_id) on delete restrict,
  action_type text not null check(action_type='parts_complete'),
  evidence text not null,
  before_vehicle jsonb not null check(jsonb_typeof(before_vehicle)='object'),
  after_vehicle jsonb not null check(jsonb_typeof(after_vehicle)='object'),
  before_parts jsonb,
  after_parts jsonb not null check(jsonb_typeof(after_parts)='object'),
  before_work_item jsonb,
  after_work_item jsonb not null check(jsonb_typeof(after_work_item)='object'),
  non_parts_diff jsonb not null check(non_parts_diff='{}'::jsonb),
  action_sha256 text not null check(action_sha256~'^[a-f0-9]{64}$'),
  created_at timestamptz not null default clock_timestamp()
);

alter table public.pdc_email_parts_complete_receipts_324 enable row level security;
alter table public.pdc_email_parts_complete_action_receipts_324 enable row level security;
revoke all on public.pdc_email_parts_complete_receipts_324,public.pdc_email_parts_complete_action_receipts_324 from public,anon,authenticated,service_role;
create trigger pdc_email_parts_complete_receipts_immutable_324
before update or delete on public.pdc_email_parts_complete_receipts_324
for each row execute function public.pdc_parts_complete_rule_history_immutable_324();
create trigger pdc_email_parts_complete_action_receipts_immutable_324
before update or delete on public.pdc_email_parts_complete_action_receipts_324
for each row execute function public.pdc_parts_complete_rule_history_immutable_324();

-- The existing statement triggers increment the shared email revision once per
-- changed table. Batch suppression is opt-in and leaves ordinary writers intact;
-- the typed action then emits exactly one explicit revision.
create or replace function public.bump_pdc_email_vehicle_revision()
returns trigger language plpgsql security definer set search_path=pg_catalog,public as $$
begin
  if current_setting('pdc.email_vehicle_revision_batch',true)='suppress' then return null; end if;
  update public.pdc_email_vehicle_revision set revision=revision+1,updated_at=clock_timestamp() where singleton;
  return null;
end $$;
revoke all on function public.bump_pdc_email_vehicle_revision() from public,anon,authenticated,service_role;

create function public.pdc_parts_complete_current_unquoted_text_324(p_raw_body text)
returns text language plpgsql immutable strict set search_path=pg_catalog as $$
declare v_line text; v_text text;begin
  if p_raw_body is null then return null; end if;
  for v_line in select regexp_split_to_table(replace(p_raw_body,E'\r\n',E'\n'),E'\n') loop
    v_text:=btrim(regexp_replace(v_line,'[[:space:]]+',' ','g'));
    if v_text='' then continue; end if;
    if left(v_text,1)='>' or v_text~* '^(on .+ wrote:|from:|sent:|to:|subject:|-----original message-----)' then return null; end if;
    if v_text='--' then return null; end if;
    return v_text;
  end loop;
  return null;
end $$;
revoke all on function public.pdc_parts_complete_current_unquoted_text_324(text) from public,anon,authenticated,service_role;

create function public.pdc_parts_complete_monitor_scope_324(p_gateway_instance_id text)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,auth as $$
declare v_uid uuid:=auth.uid();v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));v_gateway text:=btrim(coalesce(p_gateway_instance_id,''));v_count integer;begin
  select count(*) into v_count from public.pdc_monitor_stage_activation_writers w
  join public.pdc_user_roles r on r.auth_user_id=w.user_id and lower(r.email)=v_email
   and r.role::text='importer' and r.active and r.account_status='approved'
  join auth.users u on u.id=w.user_id and lower(coalesce(u.email,''))=v_email
  where w.user_id=v_uid and w.active and w.revoked_at is null;
  if v_uid is null or v_email<>'pmbcontroller@gmail.com' or v_gateway<>'pdc-monitor-staging-pmbcontroller-hourly-v1' or v_count<>1 then
    raise exception 'PDC_324_MONITOR_IMPORTER_SCOPE_REQUIRED' using errcode='42501';
  end if;
  return jsonb_build_object('actor_id',v_uid,'actor_email',v_email,'role','importer','gateway_instance_id',v_gateway);
end $$;
revoke all on function public.pdc_parts_complete_monitor_scope_324(text) from public,anon,authenticated,service_role;

create function public.pdc_parts_complete_canonical_apply_324(
  p_vehicle_id uuid,p_expected_version integer,p_actor_id uuid,p_receipt_id uuid,p_source text,p_metadata jsonb
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions as $$
declare v_before public.vehicles%rowtype;v_after public.vehicles%rowtype;v_parts_before public.vehicle_parts_updates%rowtype;v_parts_after public.vehicle_parts_updates%rowtype;v_work_before public.vehicle_work_items%rowtype;v_work_after public.vehicle_work_items%rowtype;v_revision_before bigint;v_revision_after bigint;v_now timestamptz:=clock_timestamp();v_clear_stoppage boolean;begin
  select revision into v_revision_before from public.pdc_email_vehicle_revision where singleton for update;
  select * into v_before from public.vehicles where id=p_vehicle_id for update;
  if not found then return public.navision_backend_response(false,'vehicle_not_found'); end if;
  if v_before.version<>p_expected_version then return public.navision_backend_response(false,'vehicle_version_conflict',jsonb_build_object('current_version',v_before.version)); end if;
  if v_before.lifecycle_state<>'active' or v_before.deleted_at is not null or not v_before.visible_on_board or v_before.rft_collected_at is not null or upper(btrim(coalesce(v_before.current_location,'')))='COMPLETED' then
    return public.navision_backend_response(false,'vehicle_protected');
  end if;
  select * into v_work_before from public.vehicle_work_items where vehicle_id=p_vehicle_id and upper(work_key)='PARTS' order by id limit 1 for update;
  select * into v_parts_before from public.vehicle_parts_updates where vehicle_id=p_vehicle_id order by updated_at desc,id desc limit 1 for update;
  if coalesce(v_work_before.completed,false) or coalesce(v_parts_before.parts_received,false) then return public.navision_backend_response(false,'parts_already_complete'); end if;
  v_clear_stoppage:=coalesce(v_parts_before.parts_stoppage,false);
  perform set_config('pdc.email_vehicle_revision_batch','suppress',true);
  insert into public.vehicle_parts_updates(vehicle_id,parts_required,parts_ordered,parts_received,parts_stoppage,parts_stoppage_reason,worst_eta,updated_by,updated_at)
  values(p_vehicle_id,true,coalesce(v_parts_before.parts_ordered,true),true,false,case when v_clear_stoppage then null else v_parts_before.parts_stoppage_reason end,case when v_clear_stoppage then null else v_parts_before.worst_eta end,p_actor_id,v_now)
  returning * into v_parts_after;
  if v_work_before.id is null then
    insert into public.vehicle_work_items(vehicle_id,work_key,required,completed,completed_by,completed_at,notes,updated_at)
    values(p_vehicle_id,'PARTS',true,true,p_actor_id,v_now,'Parts complete from typed Monitor email',v_now) returning * into v_work_after;
  else
    update public.vehicle_work_items set required=true,completed=true,completed_by=p_actor_id,completed_at=v_now,updated_at=v_now where id=v_work_before.id returning * into v_work_after;
  end if;
  update public.vehicles set version=version+1,updated_at=v_now,updated_by=p_actor_id where id=p_vehicle_id returning * into v_after;
  perform public.audit_pdc_event('insert','vehicle_parts_updates',v_parts_after.id,p_vehicle_id,case when v_parts_before.id is null then null else to_jsonb(v_parts_before) end,to_jsonb(v_parts_after),coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('action',p_source,'receipt_id',p_receipt_id));
  perform public.audit_pdc_event(case when v_work_before.id is null then 'insert'::public.audit_action else 'update'::public.audit_action end,'vehicle_work_items',v_work_after.id,p_vehicle_id,case when v_work_before.id is null then null else to_jsonb(v_work_before) end,to_jsonb(v_work_after),coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('action',p_source,'receipt_id',p_receipt_id));
  update public.pdc_email_vehicle_revision set revision=revision+1,updated_at=v_now where singleton returning revision into v_revision_after;
  if v_revision_after<>v_revision_before+1 then raise exception 'PDC_324_SHARED_REVISION_DELTA_FAILED' using errcode='55000'; end if;
  return public.navision_backend_response(true,'parts_completed',jsonb_build_object('receipt_id',p_receipt_id,'vehicle_id',p_vehicle_id,'vehicle_version',v_after.version,'revision_before',v_revision_before,'revision',v_revision_after,'changed',true,'parts_stoppage_cleared',v_clear_stoppage,'location_changed',false,'booking_created',false,'before_vehicle',to_jsonb(v_before),'after_vehicle',to_jsonb(v_after),'before_parts',case when v_parts_before.id is null then null else to_jsonb(v_parts_before) end,'after_parts',to_jsonb(v_parts_after),'before_work_item',case when v_work_before.id is null then null else to_jsonb(v_work_before) end,'after_work_item',to_jsonb(v_work_after)));
end $$;
revoke all on function public.pdc_parts_complete_canonical_apply_324(uuid,integer,uuid,uuid,text,jsonb) from public,anon,authenticated,service_role;

-- Canonical manual path: operator-only, with the same server-owned apply helper.
create or replace function public.mark_pdc_parts_complete(p_vehicle_id uuid,p_expected_version integer)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid:=auth.uid();v_receipt uuid:=gen_random_uuid();begin
  perform public.require_pdc_role('operator');
  if v_actor is null or p_vehicle_id is null or p_expected_version is null then return public.navision_backend_response(false,'invalid_input'); end if;
  return public.pdc_parts_complete_canonical_apply_324(p_vehicle_id,p_expected_version,v_actor,v_receipt,'mark_pdc_parts_complete',jsonb_build_object('source','manual_parts_completion'));
end $$;
revoke all on function public.mark_pdc_parts_complete(uuid,integer) from public,anon,authenticated,service_role;
grant execute on function public.mark_pdc_parts_complete(uuid,integer) to authenticated;

create function public.read_pdc_email_parts_complete_receipt_324(p_receipt_id uuid,p_gateway_instance_id text)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,extensions as $$
declare s jsonb:=public.pdc_parts_complete_monitor_scope_324(p_gateway_instance_id);r public.pdc_email_parts_complete_receipts_324%rowtype;a public.pdc_email_parts_complete_action_receipts_324%rowtype;rule public.pdc_email_parts_complete_rules_324%rowtype;begin
  select * into r from public.pdc_email_parts_complete_receipts_324 where receipt_id=p_receipt_id and actor_id=(s->>'actor_id')::uuid and gateway_instance_id=p_gateway_instance_id;
  if not found then return public.navision_backend_response(false,'parts_complete_receipt_not_found'); end if;
  select * into rule from public.pdc_email_parts_complete_rules_324 where rule_id=r.rule_id;
  if not found then return public.navision_backend_response(false,'parts_complete_receipt_drift'); end if;
  select * into a from public.pdc_email_parts_complete_action_receipts_324 where receipt_id=r.receipt_id;
  if not found or a.action_sha256<>encode(extensions.digest(convert_to(jsonb_build_object('source_hash',r.parent_source_hash,'action','parts_complete','evidence',r.current_unquoted_evidence,'vehicle_id',r.vehicle_id,'vehicle_version_after',r.vehicle_version_after)::text,'UTF8'),'sha256'),'hex') then return public.navision_backend_response(false,'parts_complete_receipt_drift'); end if;
  return public.navision_backend_response(true,'parts_complete_receipt',jsonb_build_object('receipt_id',r.receipt_id,'contract_version',r.contract_version,'rule_id',r.rule_id,'rule_version',r.rule_version,'intake_id',r.intake_id,'claim_token',r.claim_token,'parent_source_hash',r.parent_source_hash,'mailbox',r.mailbox_address,'folder',r.mailbox_folder,'uidvalidity',r.uidvalidity,'uid',r.uid,'provider_message_id',r.provider_message_id,'provider_authserv_id',r.provider_authserv_id,'authentication',r.authentication,'sender_email',r.sender_email,'sender_display_name',r.sender_display_name,'subject_evidence',r.subject_evidence,'current_unquoted_evidence',r.current_unquoted_evidence,'stock_number',r.stock_number,'attachment_id',r.attachment_id,'attachment_source_hash',r.attachment_source_hash,'vehicle_id',r.vehicle_id,'vehicle_version_before',r.vehicle_version_before,'vehicle_version_after',r.vehicle_version_after,'shared_revision_before',r.shared_revision_before,'shared_revision_after',r.shared_revision_after,'changed',false,'replayed',true,'location_changed',false,'booking_created',false,'non_parts_diff',a.non_parts_diff,'before_vehicle',a.before_vehicle,'after_vehicle',a.after_vehicle,'before_parts',a.before_parts,'after_parts',a.after_parts,'before_work_item',a.before_work_item,'after_work_item',a.after_work_item));
end $$;
revoke all on function public.read_pdc_email_parts_complete_receipt_324(uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.read_pdc_email_parts_complete_receipt_324(uuid,text) to authenticated;

create function public.process_pdc_email_parts_complete(
  p_intake_id uuid,p_claim_token uuid,p_gateway_instance_id text,p_expected_parent_source_hash text,
  p_uidvalidity bigint,p_uid bigint,p_provider_message_id text,p_provider_authserv_id text,p_authentication jsonb,
  p_subject text,p_current_unquoted_text text,p_expected_vehicle_version integer
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions as $$
declare s jsonb:=public.pdc_parts_complete_monitor_scope_324(p_gateway_instance_id);rule public.pdc_email_parts_complete_rules_324%rowtype;i public.ai_email_intake%rowtype;a public.ai_email_attachments%rowtype;o public.pdc_provider_email_observations%rowtype;r public.pdc_email_parts_complete_receipts_324%rowtype;apply_result jsonb;v_receipt uuid:=gen_random_uuid();v_request text;v_vehicle_id uuid;v_body text;v_attachment_count integer;v_image_count integer;v_auth jsonb:=coalesce(p_authentication,'null'::jsonb);v_revision_before bigint;v_action_hash text;v_candidate_count integer;begin
  select * into rule from public.pdc_email_parts_complete_rules_324 where active order by rule_version desc limit 1;
  if not found then return public.navision_backend_response(false,'parts_complete_rule_disabled'); end if;
  if p_intake_id is null or p_claim_token is null or lower(btrim(coalesce(p_expected_parent_source_hash,'')))<>rule.parent_source_hash or p_uidvalidity<>rule.uidvalidity or p_uid<>rule.uid or btrim(coalesce(p_provider_message_id,''))<>rule.provider_message_id or lower(btrim(coalesce(p_provider_authserv_id,'')))<>rule.provider_authserv_id or v_auth is distinct from rule.authentication or btrim(coalesce(p_subject,''))<>rule.subject_exact or length(btrim(coalesce(p_current_unquoted_text,''))) not between 8 and 80 or p_expected_vehicle_version is null then return public.navision_backend_response(false,'parts_complete_evidence_invalid'); end if;
  select * into i from public.ai_email_intake where id=p_intake_id for update;
  if not found then return public.navision_backend_response(false,'intake_not_found'); end if;
  v_request:=encode(extensions.digest(convert_to(jsonb_build_object('contract_version','pmb-monitor-parts-complete-v1','rule_id',rule.rule_id,'rule_version',rule.rule_version,'actor_id',(s->>'actor_id')::uuid,'gateway_instance_id',p_gateway_instance_id,'intake_id',p_intake_id,'claim_token',p_claim_token,'parent_source_hash',p_expected_parent_source_hash,'uidvalidity',p_uidvalidity,'uid',p_uid,'provider_message_id',p_provider_message_id,'provider_authserv_id',p_provider_authserv_id,'authentication',v_auth,'subject',p_subject,'current_unquoted_text',p_current_unquoted_text,'expected_vehicle_version',p_expected_vehicle_version)::text,'UTF8'),'sha256'),'hex');
  select * into r from public.pdc_email_parts_complete_receipts_324 where intake_id=p_intake_id or parent_source_hash=rule.parent_source_hash;
  if found then if r.request_sha256<>v_request or r.actor_id<>(s->>'actor_id')::uuid or r.gateway_instance_id<>p_gateway_instance_id then return public.navision_backend_response(false,'parts_complete_replay_conflict'); end if; return public.read_pdc_email_parts_complete_receipt_324(r.receipt_id,p_gateway_instance_id); end if;
  if i.status<>'processing' or i.locked_by<>(s->>'actor_id')::uuid or i.claim_token<>p_claim_token or i.gateway_instance_id<>p_gateway_instance_id or i.locked_at is null or i.locked_at<clock_timestamp()-interval '10 minutes' then return public.navision_backend_response(false,'parts_complete_claim_lost'); end if;
  if lower(coalesce(i.source_hash,''))<>rule.parent_source_hash or lower(coalesce(i.recipient_mailbox,''))<>rule.mailbox_address or lower(coalesce(i.sender_email,''))<>rule.sender_email or btrim(coalesce(i.sender_name,''))<>rule.sender_display_name or btrim(coalesce(i.subject,''))<>rule.subject_exact or coalesce(nullif(btrim(i.internet_message_id),''),nullif(btrim(i.graph_message_id),'')) is distinct from rule.provider_message_id or lower(coalesce(i.provider_uid,'')) not in('imap_uid:615','1:615') or lower(coalesce(i.provider_authserv_id,''))<>rule.provider_authserv_id or i.provider_authentication is distinct from rule.authentication or i.received_at is null or i.received_at>clock_timestamp()+interval '5 minutes' or i.received_at<clock_timestamp()-interval '30 days' then return public.navision_backend_response(false,'parts_complete_source_binding_failed'); end if;
  v_body:=public.pdc_parts_complete_current_unquoted_text_324(coalesce(nullif(i.raw_body,''),i.parsed_text,''));
  if v_body is null or v_body<>p_current_unquoted_text or not (v_body=any(rule.body_equivalents)) then return public.navision_backend_response(false,'parts_complete_current_text_not_definitive'); end if;
  select count(*),count(*) filter(where lower(coalesce(content_type,'')) like 'image/%'),min(id) into v_attachment_count,v_image_count,a.id from public.ai_email_attachments where intake_id=i.id;
  if v_attachment_count<>1 or v_image_count<>1 or a.id is null then return public.navision_backend_response(false,'parts_complete_attachment_scope_failed'); end if;
  select * into a from public.ai_email_attachments where id=a.id;
  select * into o from public.pdc_provider_email_observations where intake_id=i.id and attachment_id=a.id;
  if not found or o.parent_source_hash<>rule.parent_source_hash or o.provider_message_id<>rule.provider_message_id or o.provider_authserv_id<>rule.provider_authserv_id or o.authentication is distinct from rule.authentication then return public.navision_backend_response(false,'parts_complete_provider_observation_failed'); end if;
  select count(*),min(vehicle_id) into v_candidate_count,v_vehicle_id from (
    select v.id vehicle_id from public.vehicles v where v.deleted_at is null and v.lifecycle_state='active' and v.visible_on_board and public.normalize_vehicle_stock_number(v.stock_number)=rule.stock_number
    union
    select a.vehicle_id from public.vehicle_aliases a join public.vehicles v on v.id=a.vehicle_id
      where a.active and a.alias_type in('stock_number','stock') and public.normalize_vehicle_stock_number(a.alias_value)=rule.stock_number
        and v.deleted_at is null and v.lifecycle_state='active' and v.visible_on_board
  ) candidates;
  if v_candidate_count<>1 then return public.navision_backend_response(false,case when v_candidate_count=0 then 'parts_complete_vehicle_not_found' else 'parts_complete_vehicle_ambiguous' end); end if;
  perform pg_advisory_xact_lock(hashtextextended('pdc-parts-complete-324:'||rule.stock_number,0));
  select revision into v_revision_before from public.pdc_email_vehicle_revision where singleton for update;
  v_action_hash:=encode(extensions.digest(convert_to(jsonb_build_object('source_hash',rule.parent_source_hash,'action','parts_complete','evidence',p_current_unquoted_text,'vehicle_id',v_vehicle_id,'vehicle_version_after',p_expected_vehicle_version+1)::text,'UTF8'),'sha256'),'hex');
  apply_result:=public.pdc_parts_complete_canonical_apply_324(v_vehicle_id,p_expected_vehicle_version,(s->>'actor_id')::uuid,v_receipt,'process_pdc_email_parts_complete',jsonb_build_object('source','pdc_email_parts_complete_324','rule_id',rule.rule_id,'rule_version',rule.rule_version,'parent_source_hash',rule.parent_source_hash,'provider_uid','1:615','provider_message_id',rule.provider_message_id,'mailbox_flags_unchanged',true));
  if coalesce((apply_result->>'ok')::boolean,false) is not true then return apply_result; end if;
  insert into public.pdc_email_parts_complete_receipts(rule_id,rule_version,actor_id,actor_email,gateway_instance_id,intake_id,claim_token,parent_source_hash,mailbox_address,mailbox_folder,uidvalidity,uid,provider_message_id,provider_authserv_id,authentication,sender_email,sender_display_name,subject_evidence,current_unquoted_evidence,stock_number,attachment_id,attachment_source_hash,vehicle_id,vehicle_version_before,vehicle_version_after,shared_revision_before,shared_revision_after,request_sha256,response)
  select rule.rule_id,rule.rule_version,(s->>'actor_id')::uuid,s->>'actor_email',p_gateway_instance_id,i.id,p_claim_token,rule.parent_source_hash,rule.mailbox_address,rule.mailbox_folder,rule.uidvalidity,rule.uid,rule.provider_message_id,rule.provider_authserv_id,rule.authentication,rule.sender_email,rule.sender_display_name,rule.subject_exact,p_current_unquoted_text,rule.stock_number,a.id,a.source_hash,v_vehicle_id,p_expected_vehicle_version,(apply_result#>>'{data,vehicle_version}')::integer,v_revision_before,(apply_result#>>'{data,revision}')::bigint,v_request,apply_result;
  insert into public.pdc_email_parts_complete_action_receipts(receipt_id,action_type,evidence,before_vehicle,after_vehicle,before_parts,after_parts,before_work_item,after_work_item,non_parts_diff,action_sha256)
  select v_receipt,'parts_complete',p_current_unquoted_text,(apply_result#>>'{data,before_vehicle}')::jsonb,(apply_result#>>'{data,after_vehicle}')::jsonb,(apply_result#>>'{data,before_parts}')::jsonb,(apply_result#>>'{data,after_parts}')::jsonb,(apply_result#>>'{data,before_work_item}')::jsonb,(apply_result#>>'{data,after_work_item}')::jsonb,'{}'::jsonb,v_action_hash;
  update public.ai_email_intake set status='vehicle_updated',processing_result=coalesce(processing_result,'{}'::jsonb)||jsonb_build_object('parts_complete_receipt_id',v_receipt,'parts_complete_contract','pmb-monitor-parts-complete-v1'),last_success_at=clock_timestamp(),locked_at=null,locked_by=null,claim_token=null,gateway_instance_id=null where id=i.id;
  return public.read_pdc_email_parts_complete_receipt_324(v_receipt,p_gateway_instance_id);
end $$;
revoke all on function public.process_pdc_email_parts_complete(uuid,uuid,text,text,bigint,bigint,text,text,jsonb,text,text,integer) from public,anon,authenticated,service_role;
grant execute on function public.process_pdc_email_parts_complete(uuid,uuid,text,text,bigint,bigint,text,text,jsonb,text,text,integer) to authenticated;

-- Administrator-only forward disable/rollback path; no automatic enable and no
-- scheduler activation are performed by this migration.
create function public.disable_pdc_email_parts_complete_rule_324(p_reason text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare r public.pdc_email_parts_complete_rules_324%rowtype;v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));begin
  perform public.require_pdc_role('administrator');
  if length(btrim(coalesce(p_reason,''))) not between 3 and 500 then return public.navision_backend_response(false,'invalid_disable_reason'); end if;
  select * into r from public.pdc_email_parts_complete_rules_324 where active for update;
  if not found then return public.navision_backend_response(true,'already_disabled',jsonb_build_object('changed',false)); end if;
  update public.pdc_email_parts_complete_rules_324 set active=false,disabled_at=clock_timestamp(),disabled_reason=btrim(p_reason) where rule_id=r.rule_id;
  insert into public.pdc_email_parts_complete_rule_history(rule_id,rule_version,event_type,event_reason,actor_id,actor_email,migration_version,metadata) values(r.rule_id,r.rule_version,'disabled',btrim(p_reason),auth.uid(),v_email,'20260825090000',jsonb_build_object('source','disable_pdc_email_parts_complete_rule_324'));
  return public.navision_backend_response(true,'parts_complete_rule_disabled',jsonb_build_object('rule_id',r.rule_id,'rule_version',r.rule_version,'changed',true));
end $$;
revoke all on function public.disable_pdc_email_parts_complete_rule_324(text) from public,anon,authenticated,service_role;
grant execute on function public.disable_pdc_email_parts_complete_rule_324(text) to authenticated;

insert into supabase_migrations.schema_migrations(version,name,statements) values('20260825090000','typed_monitor_parts_complete',array[
 'Persist the exact versioned Talin Parker / Gmail / Inbox UIDVALIDITY 1 UID 615 parts_complete authority rule and applied/disable/rollback history',
 'Bind one importer gateway claim to the retained parent hash, message-id, exact authentication object, exact subject/body evidence, one image attachment and one visible active Stock 13016923 vehicle',
 'Apply only canonical PARTS work and Parts received/stoppage fields through a transaction-safe completion helper with version, audit, receipt, one shared revision and exact replay',
 'Expose target-scoped receipt readback and an Administrator-only disable path; direct receipt/rule tables and generic DML remain denied; no scheduler or mailbox flags are touched'
]);
notify pgrst,'reload schema';
commit;
