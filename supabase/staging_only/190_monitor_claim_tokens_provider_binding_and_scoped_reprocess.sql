-- Staging-only: instance-bound claims, heartbeats, retained provider binding and scoped Administrator reprocess.
begin;
set local lock_timeout='5s';set local statement_timeout='120s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-190-monitor-claims',0));
do $guard$ begin
 if not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
    or not exists(select 1 from supabase_migrations.schema_migrations where version='189' and name='exact_auditor_work_requirement_rollback')
    or exists(select 1 from supabase_migrations.schema_migrations where version='190') then
  raise exception 'PDC_190_STAGING_OR_LEDGER_MISMATCH' using errcode='55000';
 end if;
end $guard$;

alter table public.ai_email_intake
 add column if not exists claim_token uuid,
 add column if not exists gateway_instance_id text;
create unique index if not exists ai_email_intake_active_claim_token_unique
 on public.ai_email_intake(claim_token) where claim_token is not null;

create or replace function public.enqueue_pdc_email_intake(p_message jsonb,p_attachments jsonb default '[]'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare s jsonb:=public.pdc_monitor_actor_scope();v_id uuid;v_new boolean:=false;a jsonb;v_mailbox public.monitored_mailboxes%rowtype;v_recipient text;v_auth jsonb;
begin
 if jsonb_typeof(p_message) is distinct from 'object' or jsonb_typeof(p_attachments) is distinct from 'array'
    or coalesce(p_message->>'graph_message_id',p_message->>'provider_uid','')=''
    or lower(coalesce(p_message->>'source_hash',''))!~'^[a-f0-9]{64}$'
    or jsonb_array_length(p_attachments)>25 then raise exception 'pdc_monitor_identity_required' using errcode='22023';end if;
 v_recipient:=lower(btrim(coalesce(p_message->>'recipient_mailbox','')));
 v_auth:=coalesce(p_message->'provider_authentication','null'::jsonb);
 select * into v_mailbox from public.monitored_mailboxes where active and lower(mailbox_address)=v_recipient;
 if not found or jsonb_typeof(v_auth) is distinct from 'object'
    or (select array_agg(k order by k) from jsonb_object_keys(v_auth)k) is distinct from array['dkim_aligned','dmarc_aligned','gmail_authentication_results','sender_domain','spf_aligned']::text[]
    or v_auth->'gmail_authentication_results' is distinct from 'true'::jsonb
    or not(v_auth->'spf_aligned'='true'::jsonb or v_auth->'dkim_aligned'='true'::jsonb or v_auth->'dmarc_aligned'='true'::jsonb)
    then raise exception 'pdc_monitor_provider_binding_invalid' using errcode='22023';end if;
 insert into public.ai_email_intake(graph_message_id,internet_message_id,provider_uid,source_hash,subject,sender_email,sender_name,received_at,raw_body,parsed_text,attachment_names,status,queue_attempts,next_attempt_at,monitored_mailbox_id,recipient_mailbox,extracted_data,created_at,updated_at)
 values(p_message->>'graph_message_id',p_message->>'internet_message_id',p_message->>'provider_uid',lower(p_message->>'source_hash'),left(p_message->>'subject',1000),lower(p_message->>'sender_email'),left(p_message->>'sender_name',300),nullif(p_message->>'received_at','')::timestamptz,p_message->>'raw_body',p_message->>'parsed_text',coalesce(array(select jsonb_array_elements_text(coalesce(p_message->'attachment_names','[]'::jsonb))),array[]::text[]),'received',0,clock_timestamp(),v_mailbox.id,v_mailbox.mailbox_address,jsonb_build_object('provider_authentication',v_auth,'provider_authserv_id',p_message->>'provider_authserv_id'),clock_timestamp(),clock_timestamp())
 on conflict(source_hash) where source_hash is not null do nothing returning id into v_id;
 if v_id is null then select id into v_id from public.ai_email_intake where source_hash=lower(p_message->>'source_hash');else v_new:=true;end if;
 if v_new then
  for a in select value from jsonb_array_elements(p_attachments) loop
   if lower(coalesce(a->>'source_hash',''))!~'^[a-f0-9]{64}$' or length(btrim(coalesce(a->>'file_name',''))) not between 1 and 180 then raise exception 'pdc_monitor_attachment_invalid' using errcode='22023';end if;
   insert into public.ai_email_attachments(intake_id,file_name,content_type,size_bytes,source_hash,storage_path,created_at)
   values(v_id,btrim(a->>'file_name'),left(a->>'content_type',200),coalesce((a->>'size_bytes')::bigint,0),lower(a->>'source_hash'),left(a->>'storage_path',1000),clock_timestamp())
   on conflict(source_hash) where source_hash is not null do nothing;
  end loop;
 end if;
 return jsonb_build_object('ok',true,'code',case when v_new then 'pdc_monitor_intake_enqueued' else 'pdc_monitor_intake_duplicate' end,'intake_id',v_id,'duplicate',not v_new,'actor_email',s->>'email');
end $$;
revoke all on function public.enqueue_pdc_email_intake(jsonb,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.enqueue_pdc_email_intake(jsonb,jsonb) to authenticated;

create or replace function public.claim_pdc_email_intake_batch(p_limit integer,p_gateway_instance_id text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare s jsonb:=public.pdc_monitor_actor_scope();rows jsonb;
begin
 if p_limit not between 1 and 50 or length(btrim(coalesce(p_gateway_instance_id,''))) not between 3 and 120 then raise exception 'pdc_monitor_claim_invalid' using errcode='22023';end if;
 with candidates as(
  select id from public.ai_email_intake where status in('received','failed','processing') and not permanent_failure and coalesce(next_attempt_at,'-infinity')<=clock_timestamp()
   and (status<>'processing' or locked_at<clock_timestamp()-interval '10 minutes') order by received_at nulls last,created_at for update skip locked limit p_limit
 ),claimed as(
  update public.ai_email_intake i set status='processing',locked_at=clock_timestamp(),locked_by=(s->>'user_id')::uuid,claim_token=gen_random_uuid(),gateway_instance_id=btrim(p_gateway_instance_id),last_attempt_at=clock_timestamp(),queue_attempts=queue_attempts+1,error_details=null,last_error_code=null
   from candidates c where i.id=c.id returning i.id,i.subject,i.sender_email,i.received_at,i.graph_message_id,i.internet_message_id,i.source_hash,i.raw_body,i.parsed_text,i.queue_attempts,i.claim_token,i.gateway_instance_id,i.extracted_data->'provider_authentication' provider_authentication,i.extracted_data->>'provider_authserv_id' provider_authserv_id
 ) select coalesce(jsonb_agg(to_jsonb(claimed) order by received_at),'[]'::jsonb) into rows from claimed;
 update public.pdc_email_monitor_status set running_status='running',last_started_at=clock_timestamp(),gateway_instance_id=btrim(p_gateway_instance_id),updated_at=clock_timestamp() where singleton;
 return jsonb_build_object('ok',true,'items',rows,'count',jsonb_array_length(rows));
end $$;
revoke all on function public.claim_pdc_email_intake_batch(integer,text) from public,anon,authenticated,service_role;
grant execute on function public.claim_pdc_email_intake_batch(integer,text) to authenticated;

create or replace function public.heartbeat_pdc_email_intake_claim(p_intake_id uuid,p_claim_token uuid,p_gateway_instance_id text)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare s jsonb:=public.pdc_monitor_actor_scope();begin
 update public.ai_email_intake set locked_at=clock_timestamp() where id=p_intake_id and status='processing' and locked_by=(s->>'user_id')::uuid and claim_token=p_claim_token and gateway_instance_id=btrim(p_gateway_instance_id) and locked_at>=clock_timestamp()-interval '10 minutes';
 if not found then raise exception 'pdc_monitor_claim_lost' using errcode='42501';end if;
 return jsonb_build_object('ok',true,'intake_id',p_intake_id,'claim_token',p_claim_token);
end $$;
revoke all on function public.heartbeat_pdc_email_intake_claim(uuid,uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.heartbeat_pdc_email_intake_claim(uuid,uuid,text) to authenticated;

create or replace function public.get_pdc_monitor_intake_attachments(p_intake_id uuid,p_claim_token uuid,p_gateway_instance_id text)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public as $$
declare s jsonb:=public.pdc_monitor_actor_scope();rows jsonb;begin
 if not exists(select 1 from public.ai_email_intake i where i.id=p_intake_id and i.locked_by=(s->>'user_id')::uuid and i.status='processing' and i.claim_token=p_claim_token and i.gateway_instance_id=btrim(p_gateway_instance_id) and i.locked_at>=clock_timestamp()-interval '10 minutes') then raise exception 'pdc_monitor_attachment_claim_missing' using errcode='42501';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'file_name',a.file_name,'source_hash',a.source_hash,'storage_path',a.storage_path) order by a.created_at),'[]'::jsonb) into rows from public.ai_email_attachments a where a.intake_id=p_intake_id;
 return jsonb_build_object('ok',true,'attachments',rows);
end $$;
revoke all on function public.get_pdc_monitor_intake_attachments(uuid) from public,anon,authenticated,service_role;
revoke all on function public.get_pdc_monitor_intake_attachments(uuid,uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.get_pdc_monitor_intake_attachments(uuid,uuid,text) to authenticated;

create or replace function public.record_pdc_email_intake_result(p_intake_id uuid,p_claim_token uuid,p_gateway_instance_id text,p_success boolean,p_result jsonb,p_error_code text,p_error_detail text,p_temporary boolean,p_revision_summary jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare s jsonb:=public.pdc_monitor_actor_scope();r public.ai_email_intake%rowtype;delay interval;begin
 select * into r from public.ai_email_intake where id=p_intake_id and status='processing' and locked_by=(s->>'user_id')::uuid and claim_token=p_claim_token and gateway_instance_id=btrim(p_gateway_instance_id) and locked_at>=clock_timestamp()-interval '10 minutes' for update;
 if not found then raise exception 'pdc_monitor_result_claim_missing' using errcode='42501';end if;
 if p_success then
  update public.ai_email_intake set status=case when coalesce(p_result->>'code','') like '%review%' then 'needs_review'::public.ai_intake_status else 'parsed'::public.ai_intake_status end,processing_result=coalesce(p_result,'{}'::jsonb),last_success_at=clock_timestamp(),next_attempt_at=null,permanent_failure=false,retry_class=null,locked_at=null,locked_by=null,claim_token=null,gateway_instance_id=null,error_details=null,last_error_code=null,revision_summary=coalesce(p_revision_summary,'{}'::jsonb) where id=p_intake_id;
  update public.pdc_email_monitor_status set running_status='idle',last_successful_run=clock_timestamp(),last_finished_at=clock_timestamp(),last_error=null,last_error_code=null,updated_at=clock_timestamp() where singleton;
 else
  delay:=case when r.queue_attempts<=1 then interval '1 minute' when r.queue_attempts=2 then interval '5 minutes' when r.queue_attempts=3 then interval '15 minutes' else interval '1 hour' end;
  update public.ai_email_intake set status='failed',processing_result=coalesce(p_result,'{}'::jsonb),error_details=left(coalesce(p_error_detail,'unknown error'),8000),last_error_code=left(coalesce(p_error_code,'processing_failed'),120),retry_class=case when p_temporary then 'temporary' else 'permanent' end,permanent_failure=not p_temporary or queue_attempts>=5,next_attempt_at=case when p_temporary and queue_attempts<5 then clock_timestamp()+delay else null end,locked_at=null,locked_by=null,claim_token=null,gateway_instance_id=null where id=p_intake_id;
  update public.pdc_email_monitor_status set running_status='degraded',last_finished_at=clock_timestamp(),last_error=left(coalesce(p_error_detail,'unknown error'),8000),last_error_code=left(coalesce(p_error_code,'processing_failed'),120),updated_at=clock_timestamp() where singleton;
 end if;
 return jsonb_build_object('ok',true,'intake_id',p_intake_id,'success',p_success,'retry_scheduled',not p_success and p_temporary and r.queue_attempts<5);
end $$;
revoke all on function public.record_pdc_email_intake_result(uuid,boolean,jsonb,text,text,boolean,jsonb) from public,anon,authenticated,service_role;
revoke all on function public.record_pdc_email_intake_result(uuid,uuid,text,boolean,jsonb,text,text,boolean,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.record_pdc_email_intake_result(uuid,uuid,text,boolean,jsonb,text,text,boolean,jsonb) to authenticated;

create or replace function public.reprocess_pdc_failed_email(p_intake_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
begin
 perform public.require_pdc_role('administrator');
 update public.ai_email_intake set status='received',permanent_failure=false,retry_class=null,next_attempt_at=clock_timestamp(),locked_at=null,locked_by=null,claim_token=null,gateway_instance_id=null,error_details=null,last_error_code=null where id=p_intake_id and status='failed';
 if not found then raise exception 'failed_email_not_found' using errcode='P0002';end if;
 insert into public.audit_events(action,table_name,actor_id,actor_email,before_data,after_data,metadata) values('update','ai_email_intake',auth.uid(),public.current_actor_email(),jsonb_build_object('id',p_intake_id,'status','failed'),jsonb_build_object('id',p_intake_id,'status','received'),jsonb_build_object('source','administrator_monitor_reprocess','scoped_rpc',true));
 return jsonb_build_object('ok',true,'code','email_requeued','intake_id',p_intake_id);
end $$;
revoke all on function public.reprocess_pdc_failed_email(uuid) from public,anon,authenticated,service_role;
grant execute on function public.reprocess_pdc_failed_email(uuid) to authenticated;

insert into supabase_migrations.schema_migrations(version,name,statements) values('190','monitor_claim_tokens_provider_binding_and_scoped_reprocess',array[
 'Bind every queue claim to a unique claim token and gateway instance with a bounded heartbeat',
 'Require exact active monitored mailbox and retained aligned provider authentication at enqueue',
 'Require claim token and instance for attachment reads and terminal result recording',
 'Restrict controlled failed-email reprocessing to Administrator and retain audit evidence'
]);
commit;
