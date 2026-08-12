-- Staging-only: durable PMB Email Monitor queue, scoped identity and retry/status RPCs.
begin;
set local lock_timeout='5s';set local statement_timeout='120s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-177-email-monitor-reliability',0));
do $guard$ begin
 if to_regclass('public.pdc_staging_environment_sentinel') is null or not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
  or to_regclass('public.pdc_production_environment_sentinel') is not null
  or not exists(select 1 from supabase_migrations.schema_migrations where version='176' and name='instruction_bound_ai_auditor_operation_batches')
  or exists(select 1 from supabase_migrations.schema_migrations where version='177') then raise exception 'PDC_MONITOR_177_STAGING_OR_LEDGER_MISMATCH' using errcode='55000'; end if;
end $guard$;

alter table public.ai_email_intake
 add column if not exists queue_attempts integer not null default 0,
 add column if not exists next_attempt_at timestamptz,
 add column if not exists last_attempt_at timestamptz,
 add column if not exists last_success_at timestamptz,
 add column if not exists permanent_failure boolean not null default false,
 add column if not exists retry_class text,
 add column if not exists locked_at timestamptz,
 add column if not exists locked_by uuid,
 add column if not exists last_error_code text,
 add column if not exists provider_uid text,
 add column if not exists revision_summary jsonb not null default '{}'::jsonb;
alter table public.ai_email_intake
 drop constraint if exists ai_email_intake_queue_attempts_check,
 add constraint ai_email_intake_queue_attempts_check check(queue_attempts between 0 and 20),
 drop constraint if exists ai_email_intake_retry_class_check,
 add constraint ai_email_intake_retry_class_check check(retry_class is null or retry_class in('temporary','permanent','review'));
create unique index if not exists ai_email_intake_provider_uid_unique on public.ai_email_intake(provider_uid) where provider_uid is not null;
create index if not exists ai_email_intake_retry_queue_idx on public.ai_email_intake(permanent_failure,next_attempt_at,received_at) where status in('received','failed');

create table public.pdc_email_monitor_status(
 singleton boolean primary key default true check(singleton),running_status text not null default 'stopped' check(running_status in('running','idle','stopped','degraded')),
 last_started_at timestamptz,last_successful_run timestamptz,last_finished_at timestamptz,last_error text,last_error_code text,
 gateway_instance_id text,updated_at timestamptz not null default clock_timestamp()
);
insert into public.pdc_email_monitor_status(singleton) values(true) on conflict(singleton) do nothing;
alter table public.pdc_email_monitor_status enable row level security;
revoke all on public.pdc_email_monitor_status from public,anon,authenticated,service_role;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('pdc-email-intake-private','pdc-email-intake-private',false,10485760,array['application/pdf','text/plain','text/csv','image/png','image/jpeg'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists pdc_monitor_attachment_insert on storage.objects;
create policy pdc_monitor_attachment_insert on storage.objects for insert to authenticated with check(bucket_id='pdc-email-intake-private' and exists(select 1 from public.pdc_monitor_stage_activation_writers w where w.user_id=auth.uid() and w.active and w.revoked_at is null));
drop policy if exists pdc_monitor_attachment_select on storage.objects;
create policy pdc_monitor_attachment_select on storage.objects for select to authenticated using(bucket_id='pdc-email-intake-private' and (exists(select 1 from public.pdc_monitor_stage_activation_writers w where w.user_id=auth.uid() and w.active and w.revoked_at is null) or public.current_pdc_user_role() in('operator','administrator')));

create or replace function public.pdc_monitor_actor_scope()
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare v_uid uuid:=auth.uid();v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));v_count integer;
begin
 select count(*) into v_count from public.pdc_monitor_stage_activation_writers w
 join public.pdc_user_roles r on r.auth_user_id=w.user_id and lower(r.email)=v_email and r.active and r.account_status='approved' and r.role::text='viewer'
 join auth.users u on u.id=w.user_id and lower(coalesce(u.email,''))=v_email
 where w.user_id=v_uid and w.active and w.revoked_at is null;
 if v_uid is null or v_email='' or v_count<>1 then raise exception 'pdc_monitor_unauthorized' using errcode='42501'; end if;
 return jsonb_build_object('user_id',v_uid,'email',v_email,'role','viewer');
end $$;
revoke all on function public.pdc_monitor_actor_scope() from public,anon,authenticated,service_role;

create or replace function public.enqueue_pdc_email_intake(p_message jsonb,p_attachments jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_scope jsonb:=public.pdc_monitor_actor_scope();v_id uuid;v_existing public.ai_email_intake%rowtype;v_a jsonb;v_graph text:=btrim(coalesce(p_message->>'graph_message_id',''));v_hash text:=lower(btrim(coalesce(p_message->>'source_hash','')));v_uid text:=btrim(coalesce(p_message->>'provider_uid',''));
begin
 if jsonb_typeof(p_message)<>'object' or jsonb_typeof(p_attachments)<>'array' or v_graph='' or v_hash!~'^[a-f0-9]{64}$' or v_uid='' or jsonb_array_length(p_attachments)>25 then raise exception 'pdc_monitor_enqueue_invalid' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended('pdc-email-enqueue:'||v_uid,0));
 select * into v_existing from public.ai_email_intake where provider_uid=v_uid or graph_message_id=v_graph or source_hash=v_hash order by created_at limit 1;
 if found then return jsonb_build_object('ok',true,'code','already_enqueued','intake_id',v_existing.id,'status',v_existing.status,'duplicate',true); end if;
 insert into public.ai_email_intake(status,subject,sender_email,sender_name,received_at,graph_message_id,graph_thread_id,internet_message_id,attachment_names,raw_body,parsed_text,processing_result,source_hash,provider_uid,next_attempt_at)
 values('received',left(p_message->>'subject',1000),lower(nullif(btrim(p_message->>'sender_email'),'')),left(p_message->>'sender_name',300),nullif(p_message->>'received_at','')::timestamptz,v_graph,left(p_message->>'graph_thread_id',1000),left(p_message->>'internet_message_id',1024),
  coalesce(array(select jsonb_array_elements_text(coalesce(p_message->'attachment_names','[]'::jsonb))),'{}'::text[]),left(p_message->>'raw_body',120000),left(p_message->>'parsed_text',120000),jsonb_build_object('source','pdc_monitor_scoped_rpc_177','enqueued_by',v_scope->>'email'),v_hash,v_uid,clock_timestamp()) returning id into v_id;
 for v_a in select value from jsonb_array_elements(p_attachments) loop
  if lower(coalesce(v_a->>'source_hash',''))!~'^[a-f0-9]{64}$' or length(btrim(coalesce(v_a->>'file_name',''))) not between 1 and 180 then raise exception 'pdc_monitor_attachment_invalid' using errcode='22023'; end if;
  insert into public.ai_email_attachments(intake_id,graph_attachment_id,file_name,content_type,size_bytes,storage_path,text_extraction_status,source_hash)
  values(v_id,nullif(v_a->>'graph_attachment_id',''),btrim(v_a->>'file_name'),left(v_a->>'content_type',200),nullif(v_a->>'size_bytes','')::bigint,left(v_a->>'storage_path',1000),'pending',lower(v_a->>'source_hash'))
  on conflict(source_hash) do nothing;
 end loop;
 return jsonb_build_object('ok',true,'code','enqueued','intake_id',v_id,'status','received','duplicate',false);
end $$;
revoke all on function public.enqueue_pdc_email_intake(jsonb,jsonb) from public,anon,authenticated,service_role;grant execute on function public.enqueue_pdc_email_intake(jsonb,jsonb) to authenticated;

create or replace function public.claim_pdc_email_intake_batch(p_limit integer,p_gateway_instance_id text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_scope jsonb:=public.pdc_monitor_actor_scope();v_rows jsonb;
begin
 if p_limit not between 1 and 50 or length(btrim(coalesce(p_gateway_instance_id,''))) not between 3 and 120 then raise exception 'pdc_monitor_claim_invalid' using errcode='22023'; end if;
 with candidates as(select id from public.ai_email_intake where status in('received','failed') and not permanent_failure and coalesce(next_attempt_at,'-infinity')<=clock_timestamp() and (locked_at is null or locked_at<clock_timestamp()-interval '10 minutes') order by received_at nulls last,created_at for update skip locked limit p_limit),
 claimed as(update public.ai_email_intake i set status='processing',locked_at=clock_timestamp(),locked_by=(v_scope->>'user_id')::uuid,last_attempt_at=clock_timestamp(),queue_attempts=queue_attempts+1,error_details=null,last_error_code=null from candidates c where i.id=c.id returning i.id,i.subject,i.sender_email,i.received_at,i.graph_message_id,i.internet_message_id,i.source_hash,i.raw_body,i.parsed_text,i.queue_attempts)
 select coalesce(jsonb_agg(to_jsonb(claimed) order by received_at),'[]'::jsonb) into v_rows from claimed;
 update public.pdc_email_monitor_status set running_status='running',last_started_at=clock_timestamp(),gateway_instance_id=btrim(p_gateway_instance_id),updated_at=clock_timestamp() where singleton;
 return jsonb_build_object('ok',true,'items',v_rows,'count',jsonb_array_length(v_rows));
end $$;
revoke all on function public.claim_pdc_email_intake_batch(integer,text) from public,anon,authenticated,service_role;grant execute on function public.claim_pdc_email_intake_batch(integer,text) to authenticated;

create or replace function public.get_pdc_monitor_intake_attachments(p_intake_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare v_scope jsonb:=public.pdc_monitor_actor_scope();v_rows jsonb;
begin
 if not exists(select 1 from public.ai_email_intake i where i.id=p_intake_id and i.locked_by=(v_scope->>'user_id')::uuid and i.status='processing') then raise exception 'pdc_monitor_attachment_claim_missing' using errcode='42501';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'file_name',a.file_name,'source_hash',a.source_hash,'storage_path',a.storage_path) order by a.created_at),'[]'::jsonb) into v_rows from public.ai_email_attachments a where a.intake_id=p_intake_id;
 return jsonb_build_object('ok',true,'attachments',v_rows);
end $$;
revoke all on function public.get_pdc_monitor_intake_attachments(uuid) from public,anon,authenticated,service_role;grant execute on function public.get_pdc_monitor_intake_attachments(uuid) to authenticated;

create or replace function public.record_pdc_email_intake_result(p_intake_id uuid,p_success boolean,p_result jsonb,p_error_code text,p_error_detail text,p_temporary boolean,p_revision_summary jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_scope jsonb:=public.pdc_monitor_actor_scope();v_row public.ai_email_intake%rowtype;v_delay interval;
begin
 select * into v_row from public.ai_email_intake where id=p_intake_id and locked_by=(v_scope->>'user_id')::uuid for update;
 if not found then raise exception 'pdc_monitor_result_claim_missing' using errcode='42501'; end if;
 if p_success then
  update public.ai_email_intake set status=case when coalesce(p_result->>'code','') like '%review%' then 'needs_review'::public.ai_intake_status else 'parsed'::public.ai_intake_status end,
   processing_result=coalesce(p_result,'{}'::jsonb),last_success_at=clock_timestamp(),next_attempt_at=null,permanent_failure=false,retry_class=null,locked_at=null,locked_by=null,error_details=null,last_error_code=null,revision_summary=coalesce(p_revision_summary,'{}'::jsonb) where id=p_intake_id;
  update public.pdc_email_monitor_status set running_status='idle',last_successful_run=clock_timestamp(),last_finished_at=clock_timestamp(),last_error=null,last_error_code=null,updated_at=clock_timestamp() where singleton;
 else
  v_delay:=case when v_row.queue_attempts<=1 then interval '1 minute' when v_row.queue_attempts=2 then interval '5 minutes' when v_row.queue_attempts=3 then interval '15 minutes' else interval '1 hour' end;
  update public.ai_email_intake set status='failed',processing_result=coalesce(p_result,'{}'::jsonb),error_details=left(coalesce(p_error_detail,'unknown error'),8000),last_error_code=left(coalesce(p_error_code,'processing_failed'),120),
   retry_class=case when p_temporary then 'temporary' else 'permanent' end,permanent_failure=not p_temporary or queue_attempts>=5,next_attempt_at=case when p_temporary and queue_attempts<5 then clock_timestamp()+v_delay else null end,locked_at=null,locked_by=null where id=p_intake_id;
  update public.pdc_email_monitor_status set running_status='degraded',last_finished_at=clock_timestamp(),last_error=left(coalesce(p_error_detail,'unknown error'),8000),last_error_code=left(coalesce(p_error_code,'processing_failed'),120),updated_at=clock_timestamp() where singleton;
 end if;
 return jsonb_build_object('ok',true,'intake_id',p_intake_id,'success',p_success,'retry_scheduled',not p_success and p_temporary and v_row.queue_attempts<5);
end $$;
revoke all on function public.record_pdc_email_intake_result(uuid,boolean,jsonb,text,text,boolean,jsonb) from public,anon,authenticated,service_role;grant execute on function public.record_pdc_email_intake_result(uuid,boolean,jsonb,text,text,boolean,jsonb) to authenticated;

create or replace function public.reprocess_pdc_failed_email(p_intake_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
begin
 perform public.workshop_require_planner_operator();
 update public.ai_email_intake set status='received',permanent_failure=false,retry_class=null,next_attempt_at=clock_timestamp(),locked_at=null,locked_by=null,error_details=null,last_error_code=null where id=p_intake_id and status='failed';
 if not found then raise exception 'failed_email_not_found' using errcode='P0002'; end if;
 return jsonb_build_object('ok',true,'code','email_requeued','intake_id',p_intake_id);
end $$;
revoke all on function public.reprocess_pdc_failed_email(uuid) from public,anon,authenticated,service_role;grant execute on function public.reprocess_pdc_failed_email(uuid) to authenticated;

create or replace function public.get_pdc_email_monitor_status()
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare v_status public.pdc_email_monitor_status%rowtype;v_queue integer;v_failed integer;
begin
 perform public.require_pdc_role('viewer');select * into v_status from public.pdc_email_monitor_status where singleton;
 select count(*) into v_queue from public.ai_email_intake where status in('received','processing','failed') and not permanent_failure;
 select count(*) into v_failed from public.ai_email_intake where status='failed';
 return jsonb_build_object('running_status',v_status.running_status,'last_successful_run',v_status.last_successful_run,'queue_count',v_queue,'failed_count',v_failed,'last_error',v_status.last_error,'last_error_code',v_status.last_error_code,'updated_at',v_status.updated_at);
end $$;
revoke all on function public.get_pdc_email_monitor_status() from public,anon,authenticated,service_role;grant execute on function public.get_pdc_email_monitor_status() to authenticated;

create or replace function public.record_pdc_email_monitor_cycle(p_running_status text,p_error_code text default null,p_error text default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_scope jsonb:=public.pdc_monitor_actor_scope();
begin
 if p_running_status not in('running','idle','stopped','degraded') then raise exception 'pdc_monitor_cycle_status_invalid' using errcode='22023';end if;
 update public.pdc_email_monitor_status set running_status=p_running_status,last_started_at=case when p_running_status='running' then clock_timestamp() else last_started_at end,last_finished_at=case when p_running_status<>'running' then clock_timestamp() else last_finished_at end,last_successful_run=case when p_running_status='idle' then clock_timestamp() else last_successful_run end,last_error=case when p_running_status='degraded' then left(coalesce(p_error,'unknown error'),8000) else null end,last_error_code=case when p_running_status='degraded' then left(coalesce(p_error_code,'cycle_failed'),120) else null end,updated_at=clock_timestamp() where singleton;
 return jsonb_build_object('ok',true,'running_status',p_running_status,'actor',v_scope->>'email');
end $$;
revoke all on function public.record_pdc_email_monitor_cycle(text,text,text) from public,anon,authenticated,service_role;grant execute on function public.record_pdc_email_monitor_cycle(text,text,text) to authenticated;

-- Replace service-role attestation with the existing enrolled Monitor Viewer identity.
create or replace function public.attest_pdc_provider_email_observation(p_intake_id uuid,p_attachment_id uuid,p_expected_parent_hash text,p_expected_attachment_hash text,p_provider_message_id text,p_provider_authserv_id text,p_authentication jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,extensions as $attest$
declare v_scope jsonb:=public.pdc_monitor_actor_scope();v_intake public.ai_email_intake%rowtype;v_attachment public.ai_email_attachments%rowtype;v_mailbox public.monitored_mailboxes%rowtype;v_existing public.pdc_provider_email_observations%rowtype;v_parent text:=lower(btrim(coalesce(p_expected_parent_hash,'')));v_attachment_hash text:=lower(btrim(coalesce(p_expected_attachment_hash,'')));v_message_id text:=btrim(coalesce(p_provider_message_id,''));v_authserv text:=lower(btrim(coalesce(p_provider_authserv_id,'')));v_auth jsonb:=coalesce(p_authentication,'null'::jsonb);v_sender text;v_request text;
begin
 if p_intake_id is null or p_attachment_id is null or v_parent!~'^[a-f0-9]{64}$' or v_attachment_hash!~'^[a-f0-9]{64}$' or length(v_message_id) not between 1 and 1024 or v_authserv<>'mx.google.com' or jsonb_typeof(v_auth) is distinct from 'object'
  or (select array_agg(k order by k) from jsonb_object_keys(v_auth)k) is distinct from array['dkim_aligned','dmarc_aligned','gmail_authentication_results','sender_domain','spf_aligned']::text[]
  or v_auth->'gmail_authentication_results' is distinct from 'true'::jsonb or not(v_auth->'spf_aligned'='true'::jsonb or v_auth->'dkim_aligned'='true'::jsonb or v_auth->'dmarc_aligned'='true'::jsonb) then return public.navision_backend_response(false,'provider_observation_invalid');end if;
 select * into v_intake from public.ai_email_intake where id=p_intake_id for share;if not found then return public.navision_backend_response(false,'intake_not_found');end if;
 select * into v_attachment from public.ai_email_attachments where id=p_attachment_id and intake_id=p_intake_id for share;if not found then return public.navision_backend_response(false,'attachment_not_found');end if;
 select * into v_mailbox from public.monitored_mailboxes where id=v_intake.monitored_mailbox_id for share;v_sender:=lower(btrim(coalesce(v_intake.sender_email,'')));
 if not found or not v_mailbox.active or lower(btrim(coalesce(v_intake.recipient_mailbox,'')))<>lower(btrim(v_mailbox.mailbox_address)) or lower(coalesce(v_intake.source_hash,''))<>v_parent or lower(coalesce(v_attachment.source_hash,''))<>v_attachment_hash
  or v_message_id is distinct from coalesce(nullif(btrim(v_intake.internet_message_id),''),v_intake.graph_message_id) or v_auth->>'sender_domain' is distinct from split_part(v_sender,'@',2)
  or not exists(select 1 from public.pdc_monitor_exact_sender_enrollments e where e.active and e.sender_sha256=encode(extensions.digest(convert_to(v_sender,'UTF8'),'sha256'),'hex')) then return public.navision_backend_response(false,'provider_observation_binding_mismatch');end if;
 v_request:=encode(extensions.digest(convert_to(jsonb_build_object('contract_version','177.1','intake_id',p_intake_id,'attachment_id',p_attachment_id,'parent_source_hash',v_parent,'attachment_source_hash',v_attachment_hash,'provider_message_id',v_message_id,'provider_authserv_id',v_authserv,'authentication',v_auth)::text,'UTF8'),'sha256'),'hex');
 perform pg_advisory_xact_lock(hashtextextended('pdc-provider-email-observation-177:'||p_intake_id::text,0));select * into v_existing from public.pdc_provider_email_observations where intake_id=p_intake_id;
 if found then if v_existing.request_sha256<>v_request or v_existing.attachment_id<>p_attachment_id then return public.navision_backend_response(false,'provider_observation_replay_conflict');end if;return public.navision_backend_response(true,'provider_observation_already_attested',jsonb_build_object('observation_id',v_existing.observation_id,'request_sha256',v_existing.request_sha256));end if;
 insert into public.pdc_provider_email_observations(contract_version,intake_id,attachment_id,parent_source_hash,attachment_source_hash,provider_message_id,provider_authserv_id,authentication,request_sha256)
 values('159.2',p_intake_id,p_attachment_id,v_parent,v_attachment_hash,v_message_id,v_authserv,v_auth,v_request) returning * into v_existing;
 return public.navision_backend_response(true,'provider_observation_attested',jsonb_build_object('observation_id',v_existing.observation_id,'request_sha256',v_existing.request_sha256));
end $attest$;
revoke all on function public.attest_pdc_provider_email_observation(uuid,uuid,text,text,text,text,jsonb) from public,anon,authenticated,service_role;grant execute on function public.attest_pdc_provider_email_observation(uuid,uuid,text,text,text,text,jsonb) to authenticated;

alter publication supabase_realtime add table public.pdc_email_monitor_status;
insert into supabase_migrations.schema_migrations(version,name,statements) values('177','pmb_email_monitor_durable_queue_and_scoped_identity',array['Supabase-authoritative durable retry queue with full errors and bounded transient retries','existing enrolled Viewer Monitor identity replaces service-role execution','idempotent provider UID/source/message constraints and attachment evidence','running status last success queue failed last error and operator reprocess RPC','Realtime status publication and restart-safe unlocked queue claims']);
commit;
