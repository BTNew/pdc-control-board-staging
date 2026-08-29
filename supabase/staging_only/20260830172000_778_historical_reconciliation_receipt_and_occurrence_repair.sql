-- STAGING ONLY 778 receipt and occurrence repair successor.
-- non_job_card_sibling evidence is retained and never child-imported.
-- Append-only repair after observed live head 20260830171000.
begin;
set local lock_timeout='15s';
set local statement_timeout='300s';
select pg_advisory_xact_lock(hashtextextended('pdc-staging-778-historical-reconciliation-security-successor',0));
lock table supabase_migrations.schema_migrations in exclusive mode;
do $guard$
begin
 if current_user<>'postgres' or session_user<>'postgres'
    or not public.pdc_monitor_staging_guard()
    or to_regclass('public.pdc_production_environment_sentinel') is not null
    or not exists(select 1 from supabase_migrations.schema_migrations where version='20260830171000' and name='778_historical_reconciliation_security_successor')
    or to_regclass('public.pdc_historical_provider_observations_778') is null
    or to_regclass('public.pdc_historical_reconciliation_778_receipts') is null
    or exists(select 1 from supabase_migrations.schema_migrations where version='20260830172000') then
   raise exception 'PDC_778_1720_PREDECESSOR_OR_CANONICAL_CONTRACT_MISMATCH' using errcode='55000';
 end if;
end
$guard$;

create or replace function public.submit_pdc_historical_reconciliation_778(p_request jsonb)
returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,auth,extensions
set statement_timeout='300s'
as $body$
declare
 v_actor uuid:=auth.uid(); v_actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
 v_request jsonb:=coalesce(p_request,'null'::jsonb);
 v_auth jsonb:=coalesce(v_request->'authentication','null'::jsonb);
 v_manifest text:=lower(btrim(coalesce(v_request->>'manifest_sha256','')));
 v_uid text:=btrim(coalesce(v_request->>'provider_uid',''));
 v_parent text:=lower(btrim(coalesce(v_request->>'parent_source_hash','')));
 v_sender text:=lower(btrim(coalesce(v_request->>'sender_email','')));
 v_stock text:=public.normalize_vehicle_stock_number(v_request->>'stock_number');
 v_items jsonb:=coalesce(v_request->'attachment_manifest','null'::jsonb);
 v_children jsonb:=coalesce(v_request->'job_card_children','null'::jsonb);
 v_source jsonb:=coalesce(v_request->'source_metadata','null'::jsonb);
 v_authz public.pdc_historical_reconciliation_writer_authorizations_773%rowtype;
 v_existing public.pdc_historical_reconciliation_778_receipts%rowtype;
 v_intake public.ai_email_intake%rowtype;
 v_enqueue jsonb; v_parent_result jsonb; v_child_result jsonb; v_child_results jsonb:='[]'::jsonb; v_response jsonb;
 v_runtime jsonb; v_manifest_hash text; v_request_hash text; v_observation_sha text;
 v_child jsonb; v_item jsonb; v_attachment public.ai_email_attachments%rowtype; v_attachment_id uuid;
 v_intake_id uuid; v_receipt_id uuid:=gen_random_uuid(); v_child_ordinal integer; v_index integer:=0; v_job_card_success integer:=0; v_job_card_failure integer:=0; v_sibling_count integer:=0;
begin
 if not public.pdc_monitor_staging_guard() or to_regclass('public.pdc_production_environment_sentinel') is not null
    or v_actor<>'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid
    or v_actor_email<>'sales@broometoyota.com.au'
    or not public.pdc_monitor_authenticated_active_scope_674('pdc-monitor-staging-sales-uid509-v1')
    or jsonb_typeof(v_request) is distinct from 'object'
    or (select array_agg(k order by k) from jsonb_object_keys(v_request) k) is distinct from array[
      'action_type','attachment_manifest','authentication','evidence_hash','gateway_instance_id','job_card_children',
      'manifest_high_water_uid','manifest_sha256','manifest_uid_count','manifest_uidvalidity','observations',
      'parent_source_hash','provider_uid','release_manifest_sha256','release_name','release_source_sha',
      'sender_email','source_metadata','stock_number','subject','summary']::text[] then
   return jsonb_build_object('ok',false,'code','unauthorized');
 end if;
 if v_request->>'gateway_instance_id'<>'pdc-monitor-staging-sales-uid509-v1'
    or v_request->>'release_name'<>'pdc-monitor-staging-m502-2026.08.44'
    or lower(v_request->>'release_source_sha')<>'e850c319989d98b45b95a28aa815d78e2c2e3a4b'
    or lower(v_request->>'release_manifest_sha256')<>'d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d'
    or v_request->>'manifest_uidvalidity'<>'1' or v_request->>'manifest_high_water_uid'<>'685' or v_request->>'manifest_uid_count'<>'669' then
   return jsonb_build_object('ok',false,'code','historical_manifest_or_runtime_binding_mismatch');
 end if;
 v_runtime:=public.verify_pdc_monitor_runtime_binding_authenticated_766('active',
   'pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44',
   'e850c319989d98b45b95a28aa815d78e2c2e3a4b','d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d',
   '7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348',
   'e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227');
 if coalesce(v_runtime->>'ok','false')<>'true' or v_runtime->>'actor_id'<>v_actor::text
    or v_runtime->>'actor_email'<>v_actor_email or v_runtime->>'task_enabled'<>'false'
    or v_runtime->>'mailbox_contacted'<>'false' or v_runtime->>'production_writes'<>'false' then
   return jsonb_build_object('ok',false,'code','historical_runtime_binding_unavailable');
 end if;
 if v_manifest<>'aa9e2451645b3fc51eba68c422b5eaf6f146ed18596a94ce8560c55b80729018'
    or v_uid!~'^1:[1-9][0-9]{0,5}$' or v_uid='1:197' or v_parent!~'^[a-f0-9]{64}$'
    or v_sender!~'^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?$'
    or jsonb_typeof(v_auth) is distinct from 'object' or jsonb_typeof(v_items) is distinct from 'array'
    or jsonb_array_length(v_items) not between 1 and 25 or jsonb_typeof(v_children) is distinct from 'array'
    or jsonb_array_length(v_children)>25 or jsonb_typeof(v_source) is distinct from 'object'
    or length(coalesce(v_request->>'evidence_hash',''))<>64 or length(coalesce(v_request->>'subject','')) not between 1 and 300
    or length(coalesce(v_request->>'summary','')) not between 5 and 2000
    or lower(coalesce(v_request->>'action_type','')) not in ('board_activate_only','review_only') then
   return jsonb_build_object('ok',false,'code','invalid_input');
 end if;
 if v_stock='13056899' or not public.is_real_vehicle_stock_number(v_stock) then
   return jsonb_build_object('ok',false,'code','historical_reference_stock_excluded');
 end if;
 if (select array_agg(k order by k) from jsonb_object_keys(v_source) k) is distinct from array[
      'attachment_names','graph_message_id','internet_message_id','parsed_text','provider_authserv_id','raw_body',
      'received_at','recipient_mailbox','sender_name','uid','uidvalidity']::text[]
    or v_source->>'uidvalidity'<>'1' or (v_source->>'uid')::integer<>substring(v_uid from '^1:([0-9]+)$')::integer
    or v_source->>'provider_authserv_id'<>'mx.google.com' or v_source->>'received_at' is null
    or lower(v_source->>'recipient_mailbox')<>'pmbcontroller@gmail.com' then
   return jsonb_build_object('ok',false,'code','invalid_source_metadata');
 end if;
 select * into v_authz from public.pdc_historical_reconciliation_writer_authorizations_773 e
  where e.active and e.manifest_sha256=v_manifest and e.provider_uid=v_uid and e.parent_source_hash=v_parent
    and e.sender_email=v_sender and e.sender_sha256=encode(extensions.digest(convert_to(v_sender,'UTF8'),'sha256'),'hex')
    and e.provider_authentication is not distinct from v_auth
    and public.normalize_vehicle_stock_number(e.stock_number)=v_stock
    and e.authorized_actor_id=v_actor and e.authorized_actor_email=v_actor_email
    and e.authorized_gateway_instance_id='pdc-monitor-staging-sales-uid509-v1';
 if not found then return jsonb_build_object('ok',false,'code','PDC_778_EXACT_AUTHORIZATION_FAILED'); end if;
 if clock_timestamp()>v_authz.authorized_at+interval '24 hours' then
   return jsonb_build_object('ok',false,'code','historical_authorization_expired');
 end if;
 v_manifest_hash:=encode(extensions.digest(convert_to(v_items::text,'UTF8'),'sha256'),'hex');
 if v_items is distinct from v_authz.attachment_manifest or v_manifest_hash<>v_authz.attachment_manifest_sha256
    or jsonb_array_length(v_items)<>v_authz.attachment_count then
   return jsonb_build_object('ok',false,'code','historical_attachment_manifest_mismatch');
 end if;
 v_request_hash:=encode(extensions.digest(convert_to(v_request::text,'UTF8'),'sha256'),'hex');
 perform pg_advisory_xact_lock(hashtextextended('pdc-778-1710:'||v_uid||':'||v_parent,0));
 select * into v_existing from public.pdc_historical_reconciliation_778_receipts
  where actor_id=v_actor and provider_uid=v_uid and parent_source_hash=v_parent;
 if found then
   if v_existing.request_sha256<>v_request_hash then return jsonb_build_object('ok',false,'code','historical_replay_conflict'); end if;
   return v_existing.canonical_response;
 end if;

 v_enqueue:=public.enqueue_pdc_email_intake(
   jsonb_build_object('graph_message_id',v_source->>'graph_message_id','internet_message_id',v_source->>'internet_message_id',
     'provider_uid',v_uid,'source_hash',v_parent,'subject',v_request->>'subject','sender_email',v_sender,
     'sender_name',v_source->>'sender_name','received_at',v_source->>'received_at','raw_body',v_source->>'raw_body',
     'parsed_text',v_source->>'parsed_text','attachment_names',v_source->'attachment_names',
     'recipient_mailbox',lower(v_source->>'recipient_mailbox'),'provider_authserv_id',v_source->>'provider_authserv_id',
     'provider_authentication',v_auth,'stock_number',v_stock),
   (select jsonb_agg(jsonb_build_object('graph_attachment_id',v_uid||':historical-778-'||lower(x.m->>'sha256'),
      'file_name',x.m->>'filename','content_type',x.m->>'content_type','size_bytes',(x.m->>'size')::bigint,
      'source_hash',lower(x.m->>'sha256'),'storage_path','pdc-email-intake-private/historical-778/'||lower(x.m->>'sha256'),
      'validation_status','verified') order by x.ordinality)
    from jsonb_array_elements(v_items) with ordinality x(m,ordinality)));
 if not coalesce((v_enqueue->>'ok')::boolean,false) then return v_enqueue; end if;
 begin v_intake_id:=(v_enqueue->>'intake_id')::uuid; exception when others then return jsonb_build_object('ok',false,'code','enqueue_missing_intake_id'); end;
 select * into v_intake from public.ai_email_intake where id=v_intake_id for update;
 if not found or lower(coalesce(v_intake.source_hash,''))<>v_parent or v_intake.provider_uid<>v_uid
    or lower(coalesce(v_intake.sender_email,''))<>v_sender or v_intake.received_at is distinct from (v_source->>'received_at')::timestamptz
    or v_intake.internet_message_id is distinct from v_source->>'internet_message_id'
    or v_intake.graph_message_id is distinct from v_source->>'graph_message_id'
    or v_intake.provider_authentication is distinct from v_auth then
   return jsonb_build_object('ok',false,'code','historical_evidence_binding_mismatch');
 end if;
 if v_intake.duplicate_of is not null or v_intake.status::text not in ('received','processing') then
   return jsonb_build_object('ok',false,'code','historical_old_mail_completed');
 end if;
 if jsonb_array_length(v_children)<>(select count(distinct coalesce(x->>'attachment_ordinal','')) from jsonb_array_elements(v_children) x) then
   return jsonb_build_object('ok',false,'code','historical_child_sibling_duplicate');
 end if;
 for v_item in select value from jsonb_array_elements(v_items) loop
   select * into v_attachment from public.ai_email_attachments a where a.intake_id=v_intake_id
     and lower(a.source_hash)=lower(v_item->>'sha256') and lower(a.file_name)=lower(v_item->>'filename')
     and a.size_bytes=(v_item->>'size')::bigint;
   if not found then return jsonb_build_object('ok',false,'code','historical_attachment_evidence_mismatch'); end if;
   v_observation_sha:=encode(extensions.digest(convert_to(jsonb_build_object('contract_version','778.1',
     'authorization_id',v_authz.authorization_id,'intake_id',v_intake_id,'attachment_id',v_attachment.id,
     'provider_uid',v_uid,'parent_source_hash',v_parent,'attachment_source_hash',lower(v_item->>'sha256'),
     'provider_message_id',v_source->>'internet_message_id','provider_authserv_id',v_source->>'provider_authserv_id',
     'authentication',v_auth)::text,'UTF8'),'sha256'),'hex');
   insert into public.pdc_historical_provider_observations_778(contract_version,authorization_id,actor_id,actor_email,
     gateway_instance_id,manifest_sha256,provider_uid,parent_source_hash,sender_email,stock_number,intake_id,attachment_id,
     attachment_source_hash,provider_message_id,provider_authserv_id,authentication,request_sha256)
   values('778.1',v_authz.authorization_id,v_actor,v_actor_email,'pdc-monitor-staging-sales-uid509-v1',v_manifest,v_uid,v_parent,
     v_sender,v_stock,v_intake_id,v_attachment.id,lower(v_item->>'sha256'),v_source->>'internet_message_id',
     v_source->>'provider_authserv_id',v_auth,v_observation_sha) on conflict(intake_id,attachment_id) do nothing;
 end loop;
 v_parent_result:=public.submit_pdc_ai_intake_observation_pre135(v_parent,lower(v_request->>'evidence_hash'),v_uid,v_sender,v_auth,
   (v_source->>'received_at')::timestamptz,v_request->>'subject',v_request->>'action_type',v_stock,v_request->>'summary',v_request->'observations');
 if not coalesce((v_parent_result->>'ok')::boolean,false) then
   raise exception 'PDC_778_PARENT_FALSE_RESULT' using errcode='P0001';
 end if;
 for v_child in select value from jsonb_array_elements(v_children) loop
   v_index:=v_index+1; v_child_result:=null;
   begin
     if jsonb_typeof(v_child) is distinct from 'object'
        or (select array_agg(k order by k) from jsonb_object_keys(v_child) k) is distinct from array['attachment_hash','attachment_kind','attachment_ordinal','extraction','extraction_hash']::text[]
        or (v_child->>'attachment_ordinal')!~'^[1-9][0-9]{0,2}$'
        or v_child->>'attachment_kind'='ambiguous_job_card' then
       v_child_result:=jsonb_build_object('ok',false,'code','historical_child_ambiguous');
     elsif v_child->>'attachment_kind'<>'job_card'
        or lower(coalesce(v_child->>'attachment_hash',''))!~'^[a-f0-9]{64}$'
        or lower(coalesce(v_child->>'extraction_hash',''))!~'^[a-f0-9]{64}$'
        or jsonb_typeof(v_child->'extraction') is distinct from 'object'
        or not exists(select 1 from jsonb_array_elements(v_items) with ordinality x(m,ordinality) where x.ordinality=(v_child->>'attachment_ordinal')::integer and lower(x.m->>'sha256')=lower(v_child->>'attachment_hash') and x.m->>'content_type'='application/pdf') then
       v_child_result:=jsonb_build_object('ok',false,'code','historical_child_binding_mismatch');
     else
       v_child_ordinal:=(v_child->>'attachment_ordinal')::integer;
       select a.* into v_attachment from public.ai_email_attachments a where a.intake_id=v_intake_id and lower(a.source_hash)=lower(v_child->>'attachment_hash');
       if not found then v_child_result:=jsonb_build_object('ok',false,'code','historical_child_attachment_not_found');
       elsif jsonb_typeof(v_child->'extraction'->'email_vehicle'->'stock_numbers') is distinct from 'array'
          or v_child->'extraction'->'email_vehicle'->'stock_numbers'<>jsonb_build_array(v_stock)
          or v_child->'extraction'->'email_vehicle'->'conflicts' is distinct from '[]'::jsonb
          or v_child->'extraction'->'email_vehicle'->'cancelled' is distinct from 'false'::jsonb then
         v_child_result:=jsonb_build_object('ok',false,'code','historical_child_vehicle_scope_mismatch');
       else
         v_child_result:=public.import_pdc_jobcard_attachment_canonical(v_intake_id,v_attachment.id,v_parent,
           lower(v_child->>'attachment_hash'),v_auth,v_child->'extraction'->'email_vehicle',
           v_child->'extraction'->'required_work',v_child->'extraction'->'operation_lines');
         if v_child_result->>'code' in ('not_found','navision_not_found','identity_conflict','unauthorized','operational_identity_present') then
           v_child_result:=v_child_result||jsonb_build_object('historical_fail_closed',true);
         end if;
       end if;
     end if;
     if coalesce((v_child_result->>'ok')::boolean,false) then v_job_card_success:=v_job_card_success+1; else v_job_card_failure:=v_job_card_failure+1; end if;
   exception when others then v_job_card_failure:=v_job_card_failure+1; v_child_result:=jsonb_build_object('ok',false,'code','historical_child_atomic_failure'); end;
   v_child_results:=v_child_results||jsonb_build_array(jsonb_build_object('ordinal',v_index,'result',coalesce(v_child_result,'{}'::jsonb)));
 end loop;
 select count(*) into v_sibling_count from public.pdc_historical_provider_observations_778 where intake_id=v_intake_id;
 if v_job_card_failure>0 and v_job_card_success=0 and jsonb_array_length(v_children)>0 then
   v_response:=jsonb_build_object('ok',false,'code','historical_reconciliation_children_failed','data',jsonb_build_object('receipt_id',v_receipt_id,'parent_observation',v_parent_result,'attachment_receipts',v_child_results));
 elsif v_job_card_failure>0 then
   v_response:=jsonb_build_object('ok',true,'code','historical_reconciliation_partial','data',jsonb_build_object('receipt_id',v_receipt_id,'parent_observation',v_parent_result,'attachment_receipts',v_child_results));
 else
   v_response:=jsonb_build_object('ok',true,'code','historical_reconciliation_778_receipt','data',jsonb_build_object('receipt_id',v_receipt_id,'contract_version','778.1','manifest_sha256',v_manifest,'provider_uid',v_uid,'parent_source_hash',v_parent,'sender_email',v_sender,'stock_number',v_stock,'intake_id',v_intake_id,'attachment_count',jsonb_array_length(v_items),'job_card_count',v_job_card_success,'sibling_count',v_sibling_count,'attachment_receipts',v_child_results,'parent_observation',v_parent_result,'source_metadata',v_source,'attachment_manifest',v_items,'booking_created',false,'completion_created',false,'location_scheduled',false,'no_booking',true,'no_completion',true,'no_location_mutation',true,'authorization_expires_at',v_authz.authorized_at+interval '24 hours'));
 end if;
 insert into public.pdc_historical_reconciliation_778_receipts(receipt_id,contract_version,actor_id,actor_email,gateway_instance_id,manifest_sha256,provider_uid,parent_source_hash,sender_email,stock_number,request_sha256,intake_id,attachment_count,job_card_count,sibling_count,request_evidence,canonical_response)
 values(v_receipt_id,'778.1',v_actor,v_actor_email,'pdc-monitor-staging-sales-uid509-v1',v_manifest,v_uid,v_parent,v_sender,v_stock,v_request_hash,v_intake_id,jsonb_array_length(v_items),v_job_card_success,v_sibling_count,v_request,v_response);
 insert into public.audit_events(action,table_name,actor_id,actor_email,before_data,after_data,metadata)
 values('insert','pdc_historical_reconciliation_778_receipts',v_actor,v_actor_email,null,jsonb_build_object('provider_uid',v_uid,'parent_source_hash',v_parent,'intake_id',v_intake_id,'attachment_count',jsonb_array_length(v_items),'job_card_success_count',v_job_card_success,'job_card_failure_count',v_job_card_failure,'authorization_expiry',v_authz.authorized_at+interval '24 hours','no_booking',true,'no_completion',true,'no_location_mutation',true),jsonb_build_object('contract','778.1','manifest_sha256',v_manifest,'gateway_instance_id','pdc-monitor-staging-sales-uid509-v1','release_name','pdc-monitor-staging-m502-2026.08.44'));
 return v_response;
exception when unique_violation then return jsonb_build_object('ok',false,'code','historical_replay_conflict');
when others then return jsonb_build_object('ok',false,'code','historical_reconciliation_778_atomic_rollback');
end
$body$;
revoke all on function public.submit_pdc_historical_reconciliation_778(jsonb) from public,anon,authenticated,service_role,pdc_email_monitor;
grant execute on function public.submit_pdc_historical_reconciliation_778(jsonb) to authenticated;

create function public.read_pdc_historical_reconciliation_778_receipt(p_receipt_id uuid)
returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,auth,extensions as $reader$
declare r public.pdc_historical_reconciliation_778_receipts%rowtype;
begin
 if auth.uid()<>'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid
    or lower(btrim(coalesce(auth.jwt()->>'email','')))<>'sales@broometoyota.com.au'
    or not public.pdc_monitor_authenticated_active_scope_674('pdc-monitor-staging-sales-uid509-v1') then
   return jsonb_build_object('ok',false,'code','unauthorized');
 end if;
 select * into r from public.pdc_historical_reconciliation_778_receipts where receipt_id=p_receipt_id;
 if not found then return jsonb_build_object('ok',false,'code','historical_receipt_not_found'); end if;
 return jsonb_build_object('ok',true,'code','historical_reconciliation_receipt_read','data',jsonb_build_object(
   'receipt_id',r.receipt_id,'contract_version',r.contract_version,'provider_uid',r.provider_uid,
   'parent_source_hash',r.parent_source_hash,'request_sha256',r.request_sha256,
   'canonical_response',r.canonical_response));
end
$reader$;
revoke all on function public.read_pdc_historical_reconciliation_778_receipt(uuid) from public,anon,authenticated,service_role,pdc_email_monitor;
grant execute on function public.read_pdc_historical_reconciliation_778_receipt(uuid) to authenticated;

insert into supabase_migrations.schema_migrations(version,name,statements) values('20260830172000','778_historical_reconciliation_receipt_and_occurrence_repair',array[
 'Bind the UUID-free caller to frozen UIDVALIDITY 1/high-water 685/669-message manifest and current authenticated Monitor release/gateway/runtime',
 'Enforce exact immutable 773 authorization, sender/source/authentication/Stock binding, 24-hour expiry and receipt-backed one-time replay protection',
 'Use provider-bound enqueue and immutable per-sibling observations, continue valid Job Card siblings while ambiguous siblings fail closed, and require exact child Stock scope',
 'Preserve Navision not_found/identity failures, old-mail completion protection, Stock 13056899 / UID 1:197 exclusion, audit, no booking/completion/location, outbound email, task and Production boundaries'
]);
do $verify$
begin
 if to_regclass('public.pdc_production_environment_sentinel') is not null
    or not has_function_privilege('authenticated','public.submit_pdc_historical_reconciliation_778(jsonb)','execute')
    or has_function_privilege('anon','public.submit_pdc_historical_reconciliation_778(jsonb)','execute')
    or has_function_privilege('service_role','public.submit_pdc_historical_reconciliation_778(jsonb)','execute')
    or not has_function_privilege('authenticated','public.read_pdc_historical_reconciliation_778_receipt(uuid)','execute')
    or has_function_privilege('anon','public.read_pdc_historical_reconciliation_778_receipt(uuid)','execute') then
  raise exception 'PDC_778_1720_POSTCONDITION_FAILED' using errcode='55000';
 end if;
end
$verify$;
notify pgrst,'reload schema';
commit;
