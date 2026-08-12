-- Staging-only: align the active two-argument Monitor enqueue contract and close residual ACL/policy gaps.
begin;
set local lock_timeout='5s';
set local statement_timeout='120s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-204-monitor-enqueue-acl-upload',0));
do $guard$
begin
 if not exists(select 1 from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')
 or not exists(select 1 from supabase_migrations.schema_migrations where version='203' and name='remove_broad_private_attachment_select')
 or exists(select 1 from supabase_migrations.schema_migrations where version='204') then
  raise exception 'PDC_204_STAGING_OR_LEDGER_MISMATCH' using errcode='55000';
 end if;
end
$guard$;

-- This effective view is an internal Auditor implementation surface. All external
-- reads remain behind role/scoped RPCs rather than a broad authenticated grant.
revoke all on public.pdc_effective_operation_lines from public,anon,authenticated,service_role;

-- Storage policy expressions execute as the authenticated caller. Delegate only
-- the non-data-returning identity decision so revoked activation tables stay private.
create or replace function public.pdc_can_insert_private_email_attachment()
returns boolean
language plpgsql
stable
security definer
set search_path=pg_catalog,public
as $$
declare s jsonb;
begin
 s:=public.pdc_monitor_actor_scope();
 return auth.uid() is not null and (s->>'user_id')::uuid=auth.uid() and s->>'role'='viewer';
exception when others then
 return false;
end
$$;
revoke all on function public.pdc_can_insert_private_email_attachment() from public,anon,authenticated,service_role;
grant execute on function public.pdc_can_insert_private_email_attachment() to authenticated;
drop policy if exists pdc_monitor_attachment_insert on storage.objects;
create policy pdc_monitor_attachment_insert on storage.objects
 for insert to authenticated
 with check(bucket_id='pdc-email-intake-private' and public.pdc_can_insert_private_email_attachment());

-- The importer calls this two-argument overload because attachment evidence must be
-- committed in the same transaction. Persist canonical provider fields as well as
-- the legacy extracted_data copy retained for compatibility with older diagnostics.
create or replace function public.enqueue_pdc_email_intake(p_message jsonb,p_attachments jsonb default '[]'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare
 s jsonb:=public.pdc_monitor_actor_scope();
 v_id uuid;
 v_new boolean:=false;
 a jsonb;
 v_mailbox public.monitored_mailboxes%rowtype;
 v_recipient text;
 v_authserv text;
 v_auth jsonb;
 v_sender text;
 v_sender_hash text;
begin
 if jsonb_typeof(p_message) is distinct from 'object'
 or jsonb_typeof(p_attachments) is distinct from 'array'
 or coalesce(p_message->>'graph_message_id',p_message->>'provider_uid','')=''
 or lower(coalesce(p_message->>'source_hash',''))!~'^[a-f0-9]{64}$'
 or jsonb_array_length(p_attachments)>25 then
  raise exception 'pdc_monitor_identity_required' using errcode='22023';
 end if;
 v_recipient:=lower(btrim(coalesce(p_message->>'recipient_mailbox','')));
 v_authserv:=lower(btrim(coalesce(p_message->>'provider_authserv_id','')));
 v_auth:=coalesce(p_message->'provider_authentication','null'::jsonb);
 v_sender:=lower(btrim(coalesce(p_message->>'sender_email','')));
 select * into v_mailbox from public.monitored_mailboxes
  where active and test_mode and lower(mailbox_address)=v_recipient;
 if not found or v_authserv<>'mx.google.com' or jsonb_typeof(v_auth) is distinct from 'object'
 or (select array_agg(k order by k) from jsonb_object_keys(v_auth)k)
    is distinct from array['dkim_aligned','dmarc_aligned','gmail_authentication_results','sender_domain','spf_aligned']::text[]
 or v_auth->'gmail_authentication_results' is distinct from 'true'::jsonb
 or not(v_auth->'spf_aligned'='true'::jsonb or v_auth->'dkim_aligned'='true'::jsonb or v_auth->'dmarc_aligned'='true'::jsonb)
 or v_auth->>'sender_domain' is distinct from split_part(v_sender,'@',2) then
  raise exception 'pdc_monitor_provider_binding_invalid' using errcode='22023';
 end if;
 v_sender_hash:=encode(extensions.digest(convert_to(v_sender,'UTF8'),'sha256'),'hex');
 if not exists(select 1 from public.pdc_monitor_exact_sender_enrollments e where e.active and e.sender_sha256=v_sender_hash) then
  raise exception 'pdc_monitor_sender_not_enrolled' using errcode='42501';
 end if;
 insert into public.ai_email_intake(
  graph_message_id,internet_message_id,provider_uid,source_hash,subject,sender_email,sender_name,received_at,
  raw_body,parsed_text,attachment_names,status,queue_attempts,next_attempt_at,monitored_mailbox_id,recipient_mailbox,
  provider_authserv_id,provider_authentication,extracted_data,created_at,updated_at)
 values(
  p_message->>'graph_message_id',p_message->>'internet_message_id',p_message->>'provider_uid',lower(p_message->>'source_hash'),
  left(p_message->>'subject',1000),v_sender,left(p_message->>'sender_name',300),nullif(p_message->>'received_at','')::timestamptz,
  p_message->>'raw_body',p_message->>'parsed_text',coalesce(array(select jsonb_array_elements_text(coalesce(p_message->'attachment_names','[]'::jsonb))),array[]::text[]),
  'received',0,clock_timestamp(),v_mailbox.id,v_mailbox.mailbox_address,v_authserv,v_auth,
  jsonb_build_object('provider_authentication',v_auth,'provider_authserv_id',v_authserv),clock_timestamp(),clock_timestamp())
 on conflict(source_hash) where source_hash is not null do nothing returning id into v_id;
 if v_id is null then
  select id into v_id from public.ai_email_intake where source_hash=lower(p_message->>'source_hash');
 else
  v_new:=true;
 end if;
 if v_new then
  for a in select value from jsonb_array_elements(p_attachments) loop
   if lower(coalesce(a->>'source_hash',''))!~'^[a-f0-9]{64}$'
   or length(btrim(coalesce(a->>'file_name',''))) not between 1 and 180
   or btrim(coalesce(a->>'storage_path','')) not like 'pdc-email-intake-private/%' then
    raise exception 'pdc_monitor_attachment_invalid' using errcode='22023';
   end if;
   insert into public.ai_email_attachments(intake_id,file_name,content_type,size_bytes,source_hash,storage_path,created_at)
   values(v_id,btrim(a->>'file_name'),left(a->>'content_type',200),coalesce((a->>'size_bytes')::bigint,0),lower(a->>'source_hash'),left(a->>'storage_path',1000),clock_timestamp())
   on conflict(source_hash) where source_hash is not null do nothing;
  end loop;
 end if;
 update public.pdc_email_monitor_status set updated_at=clock_timestamp() where singleton;
 return jsonb_build_object('ok',true,'code',case when v_new then 'pdc_monitor_intake_enqueued' else 'pdc_monitor_intake_duplicate' end,'intake_id',v_id,'duplicate',not v_new,'actor_email',s->>'email');
end
$$;
revoke all on function public.enqueue_pdc_email_intake(jsonb,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.enqueue_pdc_email_intake(jsonb,jsonb) to authenticated;

insert into supabase_migrations.schema_migrations(version,name,statements)
values('204','align_monitor_enqueue_acl_and_upload_policy',array[
 'Persist canonical provider authentication in the active two-argument attachment enqueue contract',
 'Remove broad authenticated reads from the internal effective-operation view',
 'Authorize Monitor private attachment uploads through a fail-closed security-definer identity predicate'
]);
commit;
