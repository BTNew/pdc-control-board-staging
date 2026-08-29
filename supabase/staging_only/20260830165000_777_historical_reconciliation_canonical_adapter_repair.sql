-- STAGING ONLY 777 canonical historical reconciliation adapter repair successor.
-- Append-only successor to the observed live head 20260830164000.
-- Repairs the live adapter without rewriting prior migrations or receipts.
-- Existing pdc_ai_intake_history and consumed_at claim evidence remain immutable.
begin;
set local lock_timeout='15s';
set local statement_timeout='180s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-777-historical-reconciliation-canonical-adapter',0));
lock table supabase_migrations.schema_migrations in exclusive mode;

do $guard$
begin
  if current_user<>'postgres' or session_user<>'postgres'
     or (select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd')<>1
     or to_regclass('public.pdc_production_environment_sentinel') is not null
     or not exists(select 1 from supabase_migrations.schema_migrations where version='20260830164000' and name='777_historical_reconciliation_canonical_adapter')
     or to_regclass('public.pdc_historical_reconciliation_writer_authorizations_773') is null
     or to_regclass('public.pdc_historical_observation_777_receipts') is null
     or to_regclass('public.pdc_historical_observation_777_claims') is null
     or exists(select 1 from supabase_migrations.schema_migrations where version='20260830165000') then
    raise exception 'PDC_777_1650_PREDECESSOR_OR_CANONICAL_CONTRACT_MISMATCH' using errcode='55000';
  end if;
end
$guard$;

create or replace function public.pdc_historical_writer_authorized_777(
 p_source_hash text,p_evidence_hash text,p_source_uid text,p_sender text,p_authentication jsonb,p_stock text,p_observations jsonb)
returns boolean language plpgsql stable security definer
set search_path=pg_catalog,public,auth,extensions as $authz$
declare
 v_source text:=lower(btrim(coalesce(p_source_hash,'')));
 v_evidence text:=lower(btrim(coalesce(p_evidence_hash,'')));
 v_uid text:=btrim(coalesce(p_source_uid,''));
 v_sender text:=lower(btrim(coalesce(p_sender,'')));
 v_stock text:=public.normalize_vehicle_stock_number(p_stock);
 v_attachment_id uuid;
 v_attachment_hash text:=lower(btrim(coalesce(p_observations->'attachment_manifest'->0->>'source_hash','')));
begin
 if not public.pdc_monitor_staging_guard()
    or to_regclass('public.pdc_production_environment_sentinel') is not null
    or auth.uid()<>'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid
    or lower(btrim(coalesce(auth.jwt()->>'email','')))<>'sales@broometoyota.com.au'
    or coalesce(auth.jwt()->>'role','')<>'authenticated'
    or coalesce(auth.jwt()->>'app_role','importer') not in ('importer','')
    or not public.pdc_monitor_authenticated_active_scope_674('pdc-monitor-staging-sales-uid509-v1')
    or v_uid='1:197' or v_stock='13056899'
    or v_source!~'^[a-f0-9]{64}$' or v_evidence!~'^[a-f0-9]{64}$'
    or jsonb_typeof(p_authentication) is distinct from 'object'
    or jsonb_typeof(p_observations) is distinct from 'object'
    or jsonb_typeof(p_observations->'attachment_manifest') is distinct from 'array' then
   return false;
 end if;
 if coalesce(p_observations->'attachment_manifest'->0->>'attachment_id','')
       ~'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
   v_attachment_id:=(p_observations->'attachment_manifest'->0->>'attachment_id')::uuid;
 end if;
 return exists(
   select 1 from public.pdc_historical_reconciliation_writer_authorizations_773 e
   where e.active and e.manifest_sha256='aa9e2451645b3fc51eba68c422b5eaf6f146ed18596a94ce8560c55b80729018'
     and e.provider_uid=v_uid and e.parent_source_hash=v_source and e.sender_email=v_sender
     and e.sender_sha256=encode(extensions.digest(convert_to(v_sender,'UTF8'),'sha256'),'hex')
     and e.provider_authentication is not distinct from p_authentication
     and public.normalize_vehicle_stock_number(e.stock_number)=v_stock
     and e.authorized_actor_id=auth.uid()
     and e.authorized_actor_email=lower(btrim(auth.jwt()->>'email'))
     and e.authorized_gateway_instance_id='pdc-monitor-staging-sales-uid509-v1'
 ) or exists(
   select 1
   from public.pdc_historical_reconciliation_writer_authorizations_773 e
   join public.ai_email_intake i on lower(i.source_hash)=e.parent_source_hash
   join public.ai_email_attachments a on a.intake_id=i.id
   where e.active and e.manifest_sha256='aa9e2451645b3fc51eba68c422b5eaf6f146ed18596a94ce8560c55b80729018'
     and e.sender_email=v_sender and e.provider_authentication is not distinct from p_authentication
     and public.normalize_vehicle_stock_number(e.stock_number)=v_stock
     and e.authorized_actor_id=auth.uid()
     and e.authorized_actor_email=lower(btrim(auth.jwt()->>'email'))
     and e.authorized_gateway_instance_id='pdc-monitor-staging-sales-uid509-v1'
     and v_attachment_id is not null and a.id=v_attachment_id
     and lower(a.source_hash)=v_attachment_hash
     and v_source=public.pdc_233_length_prefixed_sha256(array[
       'pdc-attachment-canonical-source','233.1',i.id::text,a.id::text,
       e.parent_source_hash,v_attachment_hash])
     and v_uid='pdc-jc-159:'||encode(extensions.digest(convert_to(
       i.id::text||':'||a.id::text||':'||e.parent_source_hash||':'||v_attachment_hash,'UTF8'),'sha256'),'hex')
 );
end
$authz$;
revoke all on function public.pdc_historical_writer_authorized_777(text,text,text,text,jsonb,text,jsonb) from public,anon,authenticated,service_role,pdc_email_monitor;

create or replace function public.submit_pdc_historical_observation_777(p_request jsonb)
returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,auth,extensions
set statement_timeout='180s'
as $body$
declare
 v_actor uuid:=auth.uid();
 v_actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
 v_request jsonb:=coalesce(p_request,'null'::jsonb);
 v_manifest text:=lower(btrim(coalesce(v_request->>'manifest_sha256','')));
 v_uidvalidity text:=coalesce(v_request->>'manifest_uidvalidity','');
 v_high_water text:=coalesce(v_request->>'manifest_high_water_uid','');
 v_uid_count text:=coalesce(v_request->>'manifest_uid_count','');
 v_gateway text:=btrim(coalesce(v_request->>'gateway_instance_id',''));
 v_release text:=btrim(coalesce(v_request->>'release_name',''));
 v_release_source text:=lower(btrim(coalesce(v_request->>'release_source_sha','')));
 v_release_manifest text:=lower(btrim(coalesce(v_request->>'release_manifest_sha256','')));
 v_uid text:=btrim(coalesce(v_request->>'provider_uid',''));
 v_parent text:=lower(btrim(coalesce(v_request->>'parent_source_hash','')));
 v_sender text:=lower(btrim(coalesce(v_request->>'sender_email','')));
 v_stock text;
 v_auth jsonb:=coalesce(v_request->'authentication','null'::jsonb);
 v_manifest_items jsonb:=coalesce(v_request->'attachment_manifest','null'::jsonb);
 v_children jsonb:=coalesce(v_request->'job_card_children','null'::jsonb);
 v_observations jsonb:=coalesce(v_request->'observations','null'::jsonb);
 v_received timestamptz;
 v_intake_id uuid;
 v_intake public.ai_email_intake%rowtype;
 v_mailbox public.monitored_mailboxes%rowtype;
 v_authz public.pdc_historical_reconciliation_writer_authorizations_773%rowtype;
 v_existing public.pdc_historical_observation_777_receipts%rowtype;
 v_claim public.pdc_historical_observation_777_claims%rowtype;
 v_runtime jsonb;
 v_request_hash text;
 v_manifest_hash text;
 v_child jsonb;
 v_item jsonb;
 v_child_result jsonb;
 v_child_results jsonb:='[]'::jsonb;
 v_parent_result jsonb;
 v_response jsonb;
 v_failure jsonb;
 v_attachment_id uuid;
 v_child_attachment public.ai_email_attachments%rowtype;
 v_child_ordinal integer;
 v_child_count integer:=0;
 v_child_success_count integer:=0;
 v_child_failure_count integer:=0;
 v_existing_status text;
 v_ordinal integer;
begin
 -- Exact request shape prevents optional bypass fields and makes the frozen
 -- checkpoint/release binding part of the signed caller contract.
 if not public.pdc_monitor_staging_guard()
    or to_regclass('public.pdc_production_environment_sentinel') is not null
    or v_actor<>'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid
    or v_actor_email<>'sales@broometoyota.com.au'
    or not public.pdc_monitor_authenticated_active_scope_674(v_gateway)
    or jsonb_typeof(v_request) is distinct from 'object'
    or (select array_agg(k order by k) from jsonb_object_keys(v_request) k) is distinct from array[
      'action_type','attachment_manifest','authentication','evidence_hash','gateway_instance_id',
      'intake_id','job_card_children','manifest_high_water_uid','manifest_sha256',
      'manifest_uid_count','manifest_uidvalidity','observations','parent_source_hash',
      'provider_uid','release_manifest_sha256','release_name','release_source_sha',
      'sender_email','source_received_at','stock_number','subject','summary']::text[] then
   return jsonb_build_object('ok',false,'code','unauthorized');
 end if;
 if v_gateway<>'pdc-monitor-staging-sales-uid509-v1'
    or v_release<>'pdc-monitor-staging-m502-2026.08.44'
    or v_release_source<>'e850c319989d98b45b95a28aa815d78e2c2e3a4b'
    or v_release_manifest<>'d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d'
    or v_manifest<>'aa9e2451645b3fc51eba68c422b5eaf6f146ed18596a94ce8560c55b80729018'
    or v_uidvalidity<>'1' or v_high_water<>'685' or v_uid_count<>'669' then
   return jsonb_build_object('ok',false,'code','historical_manifest_or_runtime_binding_mismatch');
 end if;
 v_runtime:=public.verify_pdc_monitor_runtime_binding_authenticated_766(
   'active',v_gateway,v_release,v_release_source,v_release_manifest,
   '7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348',
   'e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227');
 if coalesce(v_runtime->>'ok','false')<>'true'
    or v_runtime->>'actor_id'<>v_actor::text
    or v_runtime->>'actor_email'<>v_actor_email
    or v_runtime->>'gateway_instance_id'<>v_gateway
    or v_runtime->>'release_name'<>v_release
    or v_runtime->>'source_sha'<>v_release_source
    or v_runtime->>'manifest_sha256'<>v_release_manifest
    or v_runtime->>'production_writes'<>'false'
    or v_runtime->>'task_enabled'<>'false'
    or v_runtime->>'mailbox_contacted'<>'false' then
   return jsonb_build_object('ok',false,'code','historical_runtime_binding_unavailable');
 end if;
 v_stock:=public.normalize_vehicle_stock_number(v_request->>'stock_number');
 begin
   v_received:=(v_request->>'source_received_at')::timestamptz;
 exception when others then
   return jsonb_build_object('ok',false,'code','invalid_input');
 end;
 if v_uid!~'^1:[1-9][0-9]{0,5}$' or v_uid='1:197'
    or v_parent!~'^[a-f0-9]{64}$'
    or v_sender!~'^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?$'
    or jsonb_typeof(v_auth) is distinct from 'object'
    or jsonb_typeof(v_manifest_items) is distinct from 'array'
    or jsonb_array_length(v_manifest_items) not between 1 and 25
    or jsonb_typeof(v_children) is distinct from 'array'
    or jsonb_array_length(v_children)>25
    or jsonb_typeof(v_observations) is distinct from 'object'
    or length(coalesce(v_request->>'evidence_hash',''))<>64
    or length(coalesce(v_request->>'subject','')) not between 1 and 300
    or length(coalesce(v_request->>'summary','')) not between 1 and 2000
    or lower(coalesce(v_request->>'action_type','')) not in ('board_activate_only','review_only')
    or v_received is null
    or v_received>clock_timestamp()+interval '5 minutes' then
   return jsonb_build_object('ok',false,'code','invalid_input');
 end if;
 if v_stock='13056899' or not public.is_real_vehicle_stock_number(v_stock) then
   return jsonb_build_object('ok',false,'code','historical_reference_stock_excluded');
 end if;
 select * into v_authz
 from public.pdc_historical_reconciliation_writer_authorizations_773 e
 where e.active and e.manifest_sha256=v_manifest and e.provider_uid=v_uid
   and e.parent_source_hash=v_parent and e.sender_email=v_sender
   and e.sender_sha256=encode(extensions.digest(convert_to(v_sender,'UTF8'),'sha256'),'hex')
   and e.provider_authentication is not distinct from v_auth
   and public.normalize_vehicle_stock_number(e.stock_number)=v_stock
   and e.authorized_actor_id=v_actor and e.authorized_actor_email=v_actor_email
   and e.authorized_gateway_instance_id=v_gateway;
 if not found then return jsonb_build_object('ok',false,'code','PDC_777_EXACT_AUTHORIZATION_FAILED'); end if;
 if not exists(select 1 from public.pdc_monitor_exact_sender_enrollments e where e.active
              and e.sender_sha256=encode(extensions.digest(convert_to(v_sender,'UTF8'),'sha256'),'hex')) then
   return jsonb_build_object('ok',false,'code','sender_not_enrolled');
 end if;
 if clock_timestamp()>v_authz.authorized_at+interval '24 hours' then
   return jsonb_build_object('ok',false,'code','historical_authorization_expired');
 end if;
 v_manifest_hash:=encode(extensions.digest(convert_to(v_manifest_items::text,'UTF8'),'sha256'),'hex');
 if v_manifest_hash<>v_authz.attachment_manifest_sha256
    or v_manifest_items is distinct from v_authz.attachment_manifest
    or jsonb_array_length(v_manifest_items)<>v_authz.attachment_count then
   return jsonb_build_object('ok',false,'code','historical_attachment_manifest_mismatch');
 end if;
 v_request_hash:=encode(extensions.digest(convert_to(v_request::text,'UTF8'),'sha256'),'hex');
 perform pg_advisory_xact_lock(hashtextextended('pdc-777-1640:'||v_uid||':'||v_parent,0));
 select * into v_existing from public.pdc_historical_observation_777_receipts
  where actor_id=v_actor and provider_uid=v_uid and parent_source_hash=v_parent;
 if found then
   if v_existing.request_sha256<>v_request_hash then return jsonb_build_object('ok',false,'code','historical_replay_conflict'); end if;
   return v_existing.canonical_response;
 end if;
 select * into v_claim from public.pdc_historical_observation_777_claims
  where actor_id=v_actor and provider_uid=v_uid and parent_source_hash=v_parent;
 if found then return jsonb_build_object('ok',false,'code','historical_authorization_consumed'); end if;

 -- rehydrate the exact frozen message and every non_job_card_sibling plus
 -- Job Card sibling into the canonical
 -- staging tables without mailbox access. Existing rows must be exact; old
 -- completed/failed/duplicate mail is never reopened by this adapter.
 select * into v_mailbox from public.monitored_mailboxes
 where id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57' and mailbox_key='pdc_pmb_email'
   and lower(mailbox_address)='pmbcontroller@gmail.com' and lower(provider)='gmail' and active and test_mode;
 if not found then return jsonb_build_object('ok',false,'code','historical_mailbox_binding_mismatch'); end if;
 select * into v_intake from public.ai_email_intake where lower(source_hash)=v_parent for update;
 if found then
   v_existing_status:=v_intake.status::text;
   if v_intake.duplicate_of is not null or v_existing_status not in ('received','processing') then
     return jsonb_build_object('ok',false,'code','historical_old_mail_completed');
   end if;
   if v_intake.provider_uid is distinct from v_uid or lower(coalesce(v_intake.sender_email,''))<>v_sender
      or v_intake.received_at is distinct from v_received
      or v_intake.monitored_mailbox_id is distinct from v_mailbox.id
      or lower(coalesce(v_intake.recipient_mailbox,''))<>'pmbcontroller@gmail.com' then
     return jsonb_build_object('ok',false,'code','historical_source_binding_mismatch');
   end if;
   v_intake_id:=v_intake.id;
 else
   begin
     insert into public.ai_email_intake(
       graph_message_id,internet_message_id,provider_uid,source_hash,subject,sender_email,sender_name,received_at,
       raw_body,parsed_text,attachment_names,status,queue_attempts,next_attempt_at,monitored_mailbox_id,recipient_mailbox,
       provider_authserv_id,provider_authentication,extracted_data,created_at,updated_at)
     values('pdc-historical-777:'||replace(v_uid,':','-'),'<pdc-historical-777-'||replace(v_uid,':','-')||'>',v_uid,v_parent,
       v_request->>'subject',v_sender,split_part(v_sender,'@',1),v_received,
       v_request->>'summary',v_request->>'summary',array(select x->>'filename' from jsonb_array_elements(v_manifest_items) x),
       'received',0,clock_timestamp(),v_mailbox.id,'pmbcontroller@gmail.com','mx.google.com',v_auth,
       jsonb_build_object('historical_manifest_sha256',v_manifest,'provider_authentication',v_auth),clock_timestamp(),clock_timestamp())
     returning id into v_intake_id;
   exception when unique_violation then
     return jsonb_build_object('ok',false,'code','historical_source_replay_conflict');
   end;
 end if;
 v_ordinal:=0;
 for v_item in select value from jsonb_array_elements(v_manifest_items) loop
   v_ordinal:=v_ordinal+1;
   if jsonb_typeof(v_item) is distinct from 'object'
      or (select array_agg(k order by k) from jsonb_object_keys(v_item) k) is distinct from array['content_type','filename','sha256','size']::text[]
      or lower(coalesce(v_item->>'sha256',''))!~'^[a-f0-9]{64}$'
      or length(coalesce(v_item->>'filename','')) not between 1 and 180
      or v_item->>'filename'<>btrim(v_item->>'filename')
      or coalesce(v_item->>'content_type','') not in ('application/pdf','image/jpeg','image/png')
      or coalesce(v_item->>'size','')!~'^[1-9][0-9]{0,7}$' then
     return jsonb_build_object('ok',false,'code','historical_attachment_manifest_mismatch');
   end if;
   select * into v_child_attachment from public.ai_email_attachments a
    where lower(coalesce(a.source_hash,''))=lower(v_item->>'sha256') for update;
   if found then
     if v_child_attachment.intake_id<>v_intake_id or v_child_attachment.file_name<>v_item->>'filename'
        or v_child_attachment.content_type<>v_item->>'content_type'
        or v_child_attachment.size_bytes<>(v_item->>'size')::bigint then
       return jsonb_build_object('ok',false,'code','historical_attachment_row_conflict');
     end if;
   else
     insert into public.ai_email_attachments(intake_id,file_name,content_type,size_bytes,source_hash,storage_path,created_at)
     values(v_intake_id,v_item->>'filename',v_item->>'content_type',(v_item->>'size')::bigint,
       lower(v_item->>'sha256'),'pdc-email-intake-private/historical-777/'||v_parent||'/'||lower(v_item->>'sha256')||'.bin',clock_timestamp())
     returning id into v_attachment_id;
     select * into v_child_attachment from public.ai_email_attachments where id=v_attachment_id;
   end if;
   if not exists(select 1 from public.pdc_provider_email_observations o
                 where o.intake_id=v_intake_id and o.attachment_id=v_child_attachment.id) then
     insert into public.pdc_provider_email_observations(
       contract_version,intake_id,attachment_id,parent_source_hash,attachment_source_hash,provider_message_id,
       provider_authserv_id,authentication,request_sha256,attested_by,attested_authority)
     values('historical-777.1',v_intake_id,v_child_attachment.id,v_parent,lower(v_item->>'sha256'),
       'pdc-historical-777:'||v_uid,'mx.google.com',v_auth,
       encode(extensions.digest(convert_to(jsonb_build_object('manifest',v_manifest,'uid',v_uid,'ordinal',v_ordinal,'sha256',lower(v_item->>'sha256'))::text,'UTF8'),'sha256'),'hex'),
       v_actor,'frozen_read_only_inbox_manifest');
   end if;
 end loop;
 if (select count(*) from public.ai_email_attachments where intake_id=v_intake_id)<>jsonb_array_length(v_manifest_items)
    or (select count(*) from public.pdc_provider_email_observations where intake_id=v_intake_id)<>jsonb_array_length(v_manifest_items) then
   return jsonb_build_object('ok',false,'code','historical_attachment_evidence_mismatch');
 end if;
 if jsonb_array_length(v_children)<>(select count(distinct coalesce(x->>'attachment_ordinal','')) from jsonb_array_elements(v_children) x) then
   return jsonb_build_object('ok',false,'code','historical_child_sibling_duplicate');
 end if;

 -- The parent goes through the existing typed observation path. It creates no
 -- bookings, completions or locations; Job Card children use the canonical 159
 -- importer below and never fall back to the legacy historical writer.
 v_observations:=v_observations||jsonb_build_object('historical_manifest_sha256',v_manifest,
   'manifest_uidvalidity',1,'manifest_high_water_uid',685,'manifest_uid_count',669,
   'attachment_manifest',v_manifest_items);
 v_parent_result:=public.submit_pdc_ai_intake_observation_pre135(
   v_parent,v_request->>'evidence_hash',v_uid,v_sender,v_auth,v_received,
   v_request->>'subject',v_request->>'action_type',v_stock,v_request->>'summary',v_observations);
 if not coalesce((v_parent_result->>'ok')::boolean,false) then return v_parent_result; end if;

 -- Each child is isolated in its own PL/pgSQL subtransaction. One ambiguous or
 -- malformed sibling is recorded and skipped while other genuine Job Cards can
 -- still reach the canonical importer for this exact vehicle only.
 for v_child in select value from jsonb_array_elements(v_children) loop
   v_child_count:=v_child_count+1;
   v_child_result:=null;
   begin
     if jsonb_typeof(v_child) is distinct from 'object'
        or (select array_agg(k order by k) from jsonb_object_keys(v_child) k) is distinct from array[
          'attachment_id','attachment_ordinal','attachment_kind','canonical_document_hash','extraction','extraction_hash']::text[]
        or (v_child->>'attachment_ordinal')!~'^[1-9][0-9]{0,2}$' then
       v_child_result:=jsonb_build_object('ok',false,'code','historical_child_invalid');
     else
       v_child_ordinal:=(v_child->>'attachment_ordinal')::integer;
       if v_child_ordinal>jsonb_array_length(v_manifest_items) then
         v_child_result:=jsonb_build_object('ok',false,'code','historical_child_sibling_out_of_range');
       elsif v_child->>'attachment_kind'='ambiguous_job_card' then
         v_child_result:=jsonb_build_object('ok',false,'code','historical_child_ambiguous');
       elsif v_child->>'attachment_kind'<>'job_card'
          or lower(coalesce(v_child->>'canonical_document_hash',''))<>lower(v_manifest_items->(v_child_ordinal-1)->>'sha256')
          or v_manifest_items->(v_child_ordinal-1)->>'content_type'<>'application/pdf'
          or lower(coalesce(v_child->>'extraction_hash',''))!~'^[a-f0-9]{64}$'
          or jsonb_typeof(v_child->'extraction') is distinct from 'object' then
         v_child_result:=jsonb_build_object('ok',false,'code','historical_child_binding_mismatch');
       else
         select a.id into v_attachment_id from public.ai_email_attachments a
          where a.intake_id=v_intake_id and lower(a.source_hash)=lower(v_child->>'canonical_document_hash');
         if v_attachment_id is null then
           v_child_result:=jsonb_build_object('ok',false,'code','historical_child_attachment_missing');
         elsif jsonb_typeof(v_child->'extraction'->'email_vehicle'->'stock_numbers') is distinct from 'array'
            or v_child->'extraction'->'email_vehicle'->'stock_numbers'<>jsonb_build_array(v_stock)
            or jsonb_typeof(v_child->'extraction'->'email_vehicle'->'conflicts') is distinct from 'array'
            or v_child->'extraction'->'email_vehicle'->'conflicts'<>'[]'::jsonb
            or v_child->'extraction'->'email_vehicle'->'cancelled' is distinct from 'false'::jsonb then
           v_child_result:=jsonb_build_object('ok',false,'code','historical_child_vehicle_scope_mismatch');
         else
           v_child_result:=public.import_pdc_jobcard_attachment_canonical(
             v_intake_id,v_attachment_id,v_parent,lower(v_child->>'canonical_document_hash'),v_auth,
             v_child->'extraction'->'email_vehicle',v_child->'extraction'->'required_work',
             v_child->'extraction'->'operation_lines');
           if v_child_result->>'code' in ('not_found','navision_not_found','identity_conflict','unauthorized','operational_identity_present') then
             v_child_result:=v_child_result||jsonb_build_object('historical_fail_closed',true);
           end if;
         end if;
       end if;
     end if;
     if coalesce((v_child_result->>'ok')::boolean,false) then
       v_child_success_count:=v_child_success_count+1;
     else
       v_child_failure_count:=v_child_failure_count+1;
     end if;
   exception when others then
     v_child_failure_count:=v_child_failure_count+1;
     v_child_result:=jsonb_build_object('ok',false,'code','historical_child_atomic_failure');
   end;
   v_child_results:=v_child_results||jsonb_build_array(jsonb_build_object(
     'attachment_ordinal',coalesce(v_child->>'attachment_ordinal',''),'result',coalesce(v_child_result,'{}'::jsonb)));
 end loop;
 if v_child_failure_count>0 and v_child_success_count=0 and v_child_count>0 then
   v_response:=jsonb_build_object('ok',false,'code','historical_observation_children_failed','data',jsonb_build_object('parent',v_parent_result,'attachment_receipts',v_child_results));
 elsif v_child_failure_count>0 then
   v_response:=jsonb_build_object('ok',true,'code','historical_observation_partial','data',jsonb_build_object('parent',v_parent_result,'attachment_receipts',v_child_results));
 else
   v_response:=jsonb_build_object('ok',true,'code','historical_observation_777_receipt','data',jsonb_build_object('parent',v_parent_result,'attachment_receipts',v_child_results));
 end if;
 insert into public.pdc_historical_observation_777_receipts(
   contract_version,actor_id,actor_email,gateway_instance_id,manifest_sha256,provider_uid,parent_source_hash,
   sender_email,stock_number,request_sha256,attachment_count,job_card_count,active_until,request_evidence,canonical_response)
 values('777.1',v_actor,v_actor_email,v_gateway,v_manifest,v_uid,v_parent,v_sender,v_stock,v_request_hash,
   jsonb_array_length(v_manifest_items),v_child_success_count,v_authz.authorized_at+interval '24 hours',v_request,v_response);
 select * into v_existing from public.pdc_historical_observation_777_receipts
  where actor_id=v_actor and provider_uid=v_uid and parent_source_hash=v_parent;
 insert into public.pdc_historical_observation_777_claims(
   authorization_id,actor_id,actor_email,gateway_instance_id,release_name,release_source_sha,release_manifest_sha256,
   manifest_sha256,manifest_uidvalidity,manifest_high_water_uid,manifest_uid_count,provider_uid,parent_source_hash,
   request_sha256,receipt_id)
 values(v_authz.authorization_id,v_actor,v_actor_email,v_gateway,v_release,v_release_source,v_release_manifest,
   v_manifest,1,685,669,v_uid,v_parent,v_request_hash,v_existing.receipt_id);
 insert into public.audit_events(action,table_name,row_id,actor_id,actor_email,before_data,after_data,metadata)
 values('insert','pdc_historical_observation_777_claims',v_existing.receipt_id,v_actor,v_actor_email,null,
   jsonb_build_object('contract','777.1','provider_uid',v_uid,'parent_source_hash',v_parent,
     'attachment_count',jsonb_array_length(v_manifest_items),'job_card_success_count',v_child_success_count,
     'job_card_failure_count',v_child_failure_count,'historical_authorization_consumed',true,
     'no_booking',true,'no_completion',true,'no_location_mutation',true),
   jsonb_build_object('manifest_sha256',v_manifest,'manifest_uidvalidity',1,'manifest_high_water_uid',685,
     'manifest_uid_count',669,'gateway_instance_id',v_gateway,'release_name',v_release,
     'release_source_sha',v_release_source,'release_manifest_sha256',v_release_manifest));
 return v_response;
exception when unique_violation then
 return jsonb_build_object('ok',false,'code','historical_replay_conflict');
when others then
 return jsonb_build_object('ok',false,'code','historical_adapter_atomic_rollback');
end
$body$;
revoke all on function public.submit_pdc_historical_observation_777(jsonb) from public,anon,authenticated,service_role,pdc_email_monitor;
grant execute on function public.submit_pdc_historical_observation_777(jsonb) to authenticated;

insert into supabase_migrations.schema_migrations(version,name,statements) values('20260830165000','777_historical_reconciliation_canonical_adapter_repair',array[
 'Guard the exact live 20260830164000 adapter predecessor and preserve the forced-RLS immutable claim/receipt tables',
 'Repair image/PDF sibling rehydration, duplicate child ordinals, exact child Stock scope, canonical Navision not_found/identity fail-closed results and current actor/gateway/release binding',
 'Preserve frozen UIDVALIDITY 1/high-water 685/669-message manifest, sender enrollment, reference Stock 13056899 exclusion, one-time expiry, replay, old-mail protection and no mailbox/outbound/Production paths'
]);

do $verify$
begin
 if to_regclass('public.pdc_production_environment_sentinel') is not null
    or to_regclass('public.pdc_historical_observation_777_claims') is null
    or (select relrowsecurity and relforcerowsecurity from pg_class where oid='public.pdc_historical_observation_777_claims'::regclass) is distinct from true
    or (select relrowsecurity and relforcerowsecurity from pg_class where oid='public.pdc_historical_observation_777_receipts'::regclass) is distinct from true
    or not has_function_privilege('authenticated','public.submit_pdc_historical_observation_777(jsonb)','execute')
    or has_function_privilege('anon','public.submit_pdc_historical_observation_777(jsonb)','execute')
    or has_function_privilege('service_role','public.submit_pdc_historical_observation_777(jsonb)','execute')
    or has_function_privilege('anon','public.pdc_historical_writer_authorized_777(text,text,text,text,jsonb,text,jsonb)','execute')
    or has_function_privilege('service_role','public.pdc_historical_writer_authorized_777(text,text,text,text,jsonb,text,jsonb)','execute') then
   raise exception 'PDC_777_1650_POSTCONDITION_FAILED' using errcode='55000';
 end if;
end
$verify$;
notify pgrst,'reload schema';
commit;
