-- Staging-only: align provider-bound enqueue with the current partial source-hash uniqueness index.
begin;
set local lock_timeout='5s';set local statement_timeout='120s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-194-monitor-enqueue-partial-index',0));
do $guard$ begin if not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd') or not exists(select 1 from supabase_migrations.schema_migrations where version='193' and name='align_monitor_enqueue_partial_source_hash_index') or exists(select 1 from supabase_migrations.schema_migrations where version='194') then raise exception 'PDC_194_STAGING_OR_LEDGER_MISMATCH' using errcode='55000';end if;end $guard$;
create or replace function public.enqueue_pdc_email_intake(p_intake jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare s jsonb:=public.pdc_monitor_actor_scope();i public.ai_email_intake%rowtype;h text;sender text;begin
 if jsonb_typeof(p_intake)<>'object' or nullif(btrim(p_intake->>'source_hash'),'') is null or lower(p_intake->>'source_hash')!~'^[a-f0-9]{64}$' then raise exception 'pdc_monitor_intake_invalid' using errcode='22023';end if;
 insert into public.ai_email_intake(status,subject,sender_email,sender_name,received_at,graph_message_id,graph_thread_id,internet_message_id,attachment_names,raw_body,parsed_text,processing_result,source_hash,monitored_mailbox_id,recipient_mailbox,provider_message_link,provider_uid,provider_authserv_id,provider_authentication,next_attempt_at)
 values('received',left(coalesce(p_intake->>'subject',''),1000),lower(btrim(p_intake->>'sender_email')),left(coalesce(p_intake->>'sender_name',''),500),coalesce(nullif(p_intake->>'received_at','')::timestamptz,clock_timestamp()),nullif(p_intake->>'graph_message_id',''),nullif(p_intake->>'graph_thread_id',''),nullif(p_intake->>'internet_message_id',''),case when jsonb_typeof(p_intake->'attachment_names')='array' then array(select jsonb_array_elements_text(p_intake->'attachment_names')) else array[]::text[] end,coalesce(p_intake->>'raw_body',''),coalesce(p_intake->>'parsed_text',''),coalesce(p_intake->'processing_result','{}'::jsonb),lower(p_intake->>'source_hash'),nullif(p_intake->>'monitored_mailbox_id','')::uuid,lower(btrim(p_intake->>'recipient_mailbox')),nullif(p_intake->>'provider_message_link',''),nullif(p_intake->>'provider_uid',''),lower(btrim(p_intake->>'provider_authserv_id')),p_intake->'provider_authentication',clock_timestamp())
 on conflict(source_hash) where source_hash is not null do update set updated_at=clock_timestamp() returning * into i;
 if not exists(select 1 from public.monitored_mailboxes m where m.id=i.monitored_mailbox_id and m.active and m.test_mode and lower(m.mailbox_address)=lower(i.recipient_mailbox)) then raise exception 'pdc_monitor_mailbox_not_bound' using errcode='42501';end if;
 sender:=lower(btrim(i.sender_email));h:=encode(extensions.digest(convert_to(sender,'UTF8'),'sha256'),'hex');
 if not exists(select 1 from public.pdc_monitor_exact_sender_enrollments e where e.active and e.sender_sha256=h) then raise exception 'pdc_monitor_sender_not_enrolled' using errcode='42501';end if;
 if i.provider_authserv_id<>'mx.google.com' or jsonb_typeof(i.provider_authentication)<>'object' or coalesce((i.provider_authentication->>'gmail_authentication_results')::boolean,false) is not true or not(coalesce((i.provider_authentication->>'dkim_aligned')::boolean,false) or coalesce((i.provider_authentication->>'dmarc_aligned')::boolean,false) or coalesce((i.provider_authentication->>'spf_aligned')::boolean,false)) then raise exception 'pdc_monitor_provider_authentication_missing' using errcode='42501';end if;
 update public.pdc_email_monitor_status set updated_at=clock_timestamp() where singleton;
 return jsonb_build_object('ok',true,'code','email_intake_enqueued','intake_id',i.id,'status',i.status);
end $$;
revoke all on function public.enqueue_pdc_email_intake(jsonb) from public,anon,authenticated,service_role;
grant execute on function public.enqueue_pdc_email_intake(jsonb) to authenticated;
insert into supabase_migrations.schema_migrations(version,name,statements) values('194','fix_provider_bound_enqueue_status_signal',array['Publish provider-bound enqueue status by updating the Realtime status row']);
commit;
