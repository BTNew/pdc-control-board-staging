-- STAGING ONLY: deterministic inbound eligibility successor after 854.
-- Non-enrolled/unapproved senders are retained as an immutable review receipt and skipped;
-- approved enrolled senders continue through the exact authenticated adapter.
BEGIN;
SELECT pg_advisory_xact_lock(hashtextextended('pdc-monitor-staging-855-inbound-eligibility',0));
DO $$ BEGIN
 IF current_setting('app.environment',true)='production' OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260831200000' AND name='854_exact_claim_839_845_compatibility_successor')<>1
 THEN RAISE EXCEPTION 'PDC_855_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $$;
CREATE TABLE public.pdc_monitor_inbound_eligibility_receipts_855(
 receipt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(), receipt_key text NOT NULL UNIQUE CHECK(receipt_key ~ '^[a-f0-9]{64}$'),
 provider_uid text NOT NULL, source_hash text NOT NULL CHECK(source_hash ~ '^[a-f0-9]{64}$'), sender_address text NOT NULL,
 recipient_mailbox text NOT NULL, provider_authserv_id text NOT NULL, provider_authentication jsonb NOT NULL,
 disposition text NOT NULL CHECK(disposition='review_queued'), review_queued boolean NOT NULL CHECK(review_queued),
 board_mutations integer NOT NULL CHECK(board_mutations=0), mailbox_flags_changed boolean NOT NULL CHECK(NOT mailbox_flags_changed),
 outbound_email_sent boolean NOT NULL CHECK(NOT outbound_email_sent), production_writes boolean NOT NULL CHECK(NOT production_writes),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_monitor_inbound_eligibility_receipts_855 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_monitor_inbound_eligibility_receipts_855 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_monitor_inbound_eligibility_receipts_855 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_monitor_inbound_eligibility_receipts_855_immutable() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$ BEGIN RAISE EXCEPTION 'PDC_855_RECEIPT_IMMUTABLE' USING errcode='55000'; END $$;
CREATE TRIGGER pdc_monitor_inbound_eligibility_receipts_855_immutable BEFORE UPDATE OR DELETE ON public.pdc_monitor_inbound_eligibility_receipts_855 FOR EACH ROW EXECUTE FUNCTION public.pdc_monitor_inbound_eligibility_receipts_855_immutable();
CREATE OR REPLACE FUNCTION public.pdc_monitor_authenticated_active_scope_839()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,auth,extensions
AS $scope$
DECLARE v_actor uuid:=auth.uid(); v_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); v_binding public.pdc_monitor_runtime_bindings_255%rowtype; v_mailbox public.monitored_mailboxes%rowtype;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR lower(coalesce(current_setting('app.environment',true),''))='production' OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR v_actor IS DISTINCT FROM 'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid OR v_email<>'sales@broometoyota.com.au' OR coalesce(auth.jwt()->>'role','')<>'authenticated'
 THEN RAISE EXCEPTION 'PDC_839_AUTHENTICATED_ACTIVE_IDENTITY_REQUIRED' USING errcode='42501'; END IF;
 IF (SELECT count(*) FROM auth.users u WHERE u.id=v_actor AND lower(coalesce(u.email,''))=v_email AND coalesce(u.raw_app_meta_data->>'pdc_identity_type','')='non_human_monitor')<>1
    OR (SELECT count(*) FROM public.pdc_user_roles r WHERE r.auth_user_id=v_actor AND lower(r.email)=v_email AND r.active AND r.account_status='approved' AND r.role::text='importer')<>1
    OR (SELECT count(*) FROM public.pdc_user_roles r WHERE r.auth_user_id=v_actor AND r.active)<>1
    OR (SELECT count(*) FROM public.pdc_monitor_stage_activation_writers w WHERE w.user_id=v_actor AND w.active AND w.revoked_at IS NULL)<>1
    OR (SELECT count(*) FROM public.pdc_monitor_stage_activation_writers w WHERE w.active AND w.revoked_at IS NULL)<>1
    OR EXISTS(SELECT 1 FROM public.pdc_auditor_worker_identities w WHERE w.auth_user_id=v_actor AND w.active)
    OR EXISTS(SELECT 1 FROM public.pdc_auditor_user_dealer_scopes s WHERE s.auth_user_id=v_actor AND s.active)
    OR EXISTS(SELECT 1 FROM public.pdc_auditor_executor_identities e WHERE e.auth_user_id=v_actor AND e.active AND e.expires_at>clock_timestamp())
    OR EXISTS(SELECT 1 FROM public.pdc_auditor_service_identities_225 s WHERE s.auth_user_id=v_actor AND s.active)
 THEN RAISE EXCEPTION 'PDC_839_AUTHENTICATED_ACTIVE_ROLE_WRITER_REQUIRED' USING errcode='42501'; END IF;
 SELECT * INTO v_mailbox FROM public.monitored_mailboxes WHERE id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57' AND active AND test_mode AND mailbox_key='pdc_pmb_email' AND lower(mailbox_address)='pmbcontroller@gmail.com' AND lower(provider)='gmail' AND config->>'owner_profile'='pdc-monitor' AND config->>'contains_credentials'='false' AND config->>'operational_scope'='staging';
 IF NOT FOUND OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>1 THEN RAISE EXCEPTION 'PDC_839_EXACT_ACTIVE_MAILBOX_REQUIRED' USING errcode='42501'; END IF;
 IF (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND NOT enabled AND NOT automatic_rule_application AND NOT automatic_authenticated_jobcards AND NOT outbound_email_enabled)<>1
    OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_active_capability_controls_672 WHERE singleton AND enabled AND actor_id=v_actor AND jwt_role='authenticated' AND server_application_role='importer' AND NOT production_writes AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed)<>1
    OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_execution_attachment_controls_673 WHERE singleton AND enabled AND actor_id=v_actor AND observed_mime_part_count=7 AND retained_authenticated_attachment_count=4 AND all_mime_parts_retained AND NOT production_writes AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed)<>1
    OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_mailbox_activation_controls_674 WHERE singleton AND enabled AND actor_id=v_actor AND mailbox_id=v_mailbox.id AND mailbox_key='pdc_pmb_email' AND mailbox_address='pmbcontroller@gmail.com' AND provider='gmail' AND test_mode AND NOT production_writes AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed)<>1
    OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_enqueue_trigger_controls_675 WHERE singleton AND enabled AND actor_id=v_actor AND NOT production_writes AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed)<>1
 THEN RAISE EXCEPTION 'PDC_839_ACTIVE_CONFIGURATION_REQUIRED' USING errcode='42501'; END IF;
 SELECT * INTO v_binding FROM public.pdc_monitor_runtime_bindings_255 WHERE singleton AND actor_id=v_actor AND gateway_instance_id='pdc-monitor-staging-sales-uid509-v1' AND release_name='pdc-monitor-staging-m502-2026.08.44' AND source_sha='e850c319989d98b45b95a28aa815d78e2c2e3a4b' AND manifest_sha256='d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d' AND semantic_planner_sha256='7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348' AND semantic_planner_trust_receipt_sha256='e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227' AND semantic_planner_commissioned_at IS NOT NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'PDC_839_ACTIVE_RUNTIME_BINDING_REQUIRED' USING errcode='42501'; END IF;
 RETURN jsonb_build_object('actor_id',v_actor,'actor_email',v_email,'jwt_role','authenticated','server_application_role','importer','gateway_instance_id',v_binding.gateway_instance_id,'release_name',v_binding.release_name,'source_sha',v_binding.source_sha,'manifest_sha256',v_binding.manifest_sha256,'semantic_planner_sha256',v_binding.semantic_planner_sha256,'semantic_planner_trust_receipt_sha256',v_binding.semantic_planner_trust_receipt_sha256,'writer_active',true,'planner_commissioned',true,'mailbox_id',v_mailbox.id,'mailbox_active',true,'active_mailbox_count',1,'operational',true,'activation_ready',true,'production_writes',false,'task_enabled',false,'mailbox_contacted',false,'uid514_processed',false,'adapter_head',839);
END
$scope$;
REVOKE ALL ON FUNCTION public.pdc_monitor_authenticated_active_scope_839() FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.pdc_monitor_authenticated_active_scope_839() TO authenticated;

CREATE OR REPLACE FUNCTION public.enqueue_pdc_email_intake(p_message jsonb, p_attachments jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
 s jsonb:=public.pdc_monitor_authenticated_active_scope_839();v_id uuid;v_new boolean:=false;a jsonb;
 v_mailbox public.monitored_mailboxes%rowtype;v_recipient text;v_authserv text;v_auth jsonb;v_sender text;v_sender_hash text;v_sender_enrolled boolean;
 v_validation text;v_validation_error text;v_storage text;v_graph_attachment text;v_receipt_key text;v_receipt_id uuid;
BEGIN
 IF jsonb_typeof(p_message) IS DISTINCT FROM 'object' OR jsonb_typeof(p_attachments) IS DISTINCT FROM 'array'
 OR coalesce(p_message->>'graph_message_id',p_message->>'provider_uid','')='' OR lower(coalesce(p_message->>'source_hash',''))!~'^[a-f0-9]{64}$'
 OR jsonb_array_length(p_attachments)>25 THEN RAISE EXCEPTION 'pdc_monitor_identity_required' USING errcode='22023';END IF;
 v_recipient:=lower(btrim(coalesce(p_message->>'recipient_mailbox','')));v_authserv:=lower(btrim(coalesce(p_message->>'provider_authserv_id','')));
 v_auth:=coalesce(p_message->'provider_authentication','null'::jsonb);v_sender:=lower(btrim(coalesce(p_message->>'sender_email','')));
 IF NOT EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active AND test_mode AND lower(mailbox_address)=v_recipient) THEN RETURN jsonb_build_object('ok',true,'code','pdc_monitor_message_ignored_wrong_recipient','ignored',true,'mailbox_contacted',false,'uid514_processed',false,'production_writes',false); END IF;
 SELECT * INTO v_mailbox FROM public.monitored_mailboxes WHERE active AND test_mode AND lower(mailbox_address)=v_recipient;
 IF NOT FOUND OR v_authserv<>'mx.google.com' OR jsonb_typeof(v_auth) IS DISTINCT FROM 'object'
 OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_auth)k) IS DISTINCT FROM array['dkim_aligned','dmarc_aligned','gmail_authentication_results','sender_domain','spf_aligned']::text[]
 OR v_auth->'gmail_authentication_results' IS DISTINCT FROM 'true'::jsonb
 OR NOT(v_auth->'spf_aligned'='true'::jsonb OR v_auth->'dkim_aligned'='true'::jsonb OR v_auth->'dmarc_aligned'='true'::jsonb)
 OR lower(btrim(v_auth->>'sender_domain')) IS DISTINCT FROM lower(btrim(split_part(v_sender,'@',2))) THEN RAISE EXCEPTION 'pdc_monitor_provider_binding_invalid' USING errcode='22023';END IF;
 v_sender_hash:=encode(extensions.digest(convert_to(v_sender,'UTF8'),'sha256'),'hex');
 v_sender_enrolled:=EXISTS(SELECT 1 FROM public.pdc_monitor_exact_sender_enrollments e WHERE e.active AND e.sender_sha256=v_sender_hash)
    OR EXISTS(SELECT 1 FROM public.pdc_historical_reconciliation_writer_authorizations_773 e WHERE e.active AND e.provider_uid=btrim(coalesce(p_message->>'provider_uid','')) AND e.parent_source_hash=lower(coalesce(p_message->>'source_hash','')) AND e.sender_email=v_sender AND e.sender_sha256=v_sender_hash AND e.provider_authentication IS NOT DISTINCT FROM v_auth AND public.normalize_vehicle_stock_number(e.stock_number)=public.normalize_vehicle_stock_number(p_message->>'stock_number') AND e.authorized_actor_id=(s->>'user_id')::uuid AND e.authorized_actor_email=s->>'email' AND e.authorized_gateway_instance_id='pdc-monitor-staging-sales-uid509-v1' AND e.manifest_sha256='aa9e2451645b3fc51eba68c422b5eaf6f146ed18596a94ce8560c55b80729018');
 IF NOT v_sender_enrolled THEN
  v_receipt_key:=encode(extensions.digest(convert_to(v_sender||'|'||v_recipient||'|'||btrim(coalesce(p_message->>'provider_uid',''))||'|'||lower(coalesce(p_message->>'source_hash',''))||'|'||coalesce(v_auth::text,'null'),'UTF8'),'sha256'),'hex');
  INSERT INTO public.pdc_monitor_inbound_eligibility_receipts_855(
    receipt_key,provider_uid,source_hash,sender_address,recipient_mailbox,provider_authserv_id,provider_authentication,
    disposition,review_queued,board_mutations,mailbox_flags_changed,outbound_email_sent,production_writes
  ) VALUES(
    v_receipt_key,btrim(coalesce(p_message->>'provider_uid','')),lower(coalesce(p_message->>'source_hash','')),v_sender,v_recipient,v_authserv,v_auth,
    'review_queued',true,0,false,false,false
  ) ON CONFLICT(receipt_key) DO NOTHING;
  SELECT receipt_id INTO v_receipt_id FROM public.pdc_monitor_inbound_eligibility_receipts_855 WHERE receipt_key=v_receipt_key;
  RETURN jsonb_build_object('ok',true,'code','pdc_monitor_sender_not_enrolled','disposition','review_queued','receipt_id',v_receipt_id,'receipt_key',v_receipt_key,'idempotent',true,'sender_enrolled',false,'board_mutations',0,'mailbox_flags_changed',false,'outbound_email_sent',false,'production_writes',false);
 END IF;
 INSERT INTO public.ai_email_intake(graph_message_id,internet_message_id,provider_uid,source_hash,subject,sender_email,sender_name,received_at,raw_body,parsed_text,attachment_names,status,queue_attempts,next_attempt_at,monitored_mailbox_id,recipient_mailbox,provider_authserv_id,provider_authentication,extracted_data,created_at,updated_at)
 VALUES(p_message->>'graph_message_id',p_message->>'internet_message_id',p_message->>'provider_uid',lower(p_message->>'source_hash'),left(p_message->>'subject',1000),v_sender,left(p_message->>'sender_name',300),nullif(p_message->>'received_at','')::timestamptz,p_message->>'raw_body',p_message->>'parsed_text',coalesce(array(SELECT jsonb_array_elements_text(coalesce(p_message->'attachment_names','[]'::jsonb))),array[]::text[]),'received',0,clock_timestamp(),v_mailbox.id,v_mailbox.mailbox_address,v_authserv,v_auth,jsonb_build_object('provider_authentication',v_auth,'provider_authserv_id',v_authserv,'sender_enrolled',v_sender_enrolled),clock_timestamp(),clock_timestamp())
 ON CONFLICT(source_hash) WHERE source_hash IS NOT NULL DO NOTHING RETURNING id INTO v_id;
 IF v_id IS NULL THEN
  SELECT id INTO v_id FROM public.ai_email_intake WHERE source_hash=lower(p_message->>'source_hash');
  IF v_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.ai_email_intake i WHERE i.id=v_id
   AND i.graph_message_id=p_message->>'graph_message_id' AND coalesce(i.internet_message_id,'')=coalesce(p_message->>'internet_message_id','')
   AND i.provider_uid=p_message->>'provider_uid' AND i.source_hash=lower(p_message->>'source_hash')
   AND lower(i.sender_email)=v_sender AND lower(i.recipient_mailbox)=v_recipient AND i.provider_authserv_id=v_authserv
   AND i.provider_authentication IS NOT DISTINCT FROM v_auth) THEN RAISE EXCEPTION 'pdc_monitor_intake_replay_conflict' USING errcode='55000';END IF;
 ELSE v_new:=true;END IF;
 IF jsonb_array_length(p_attachments)<>(SELECT count(DISTINCT value->>'graph_attachment_id') FROM jsonb_array_elements(p_attachments)) THEN RAISE EXCEPTION 'pdc_monitor_attachment_payload_duplicate' USING errcode='22023';END IF;
 IF NOT v_new AND(
  jsonb_array_length(p_attachments)<>(SELECT count(*) FROM public.ai_email_attachments x WHERE x.intake_id=v_id)
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_attachments) supplied(value) LEFT JOIN public.ai_email_attachments x ON x.intake_id=v_id AND x.graph_attachment_id=supplied.value->>'graph_attachment_id' WHERE x.id IS NULL)
  OR EXISTS(SELECT 1 FROM public.ai_email_attachments x WHERE x.intake_id=v_id AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p_attachments) supplied(value) WHERE supplied.value->>'graph_attachment_id'=x.graph_attachment_id))
 ) THEN RAISE EXCEPTION 'pdc_monitor_attachment_replay_conflict' USING errcode='55000';END IF;
 FOR a IN SELECT value FROM jsonb_array_elements(p_attachments) LOOP
  v_validation:=btrim(coalesce(a->>'validation_status',''));v_validation_error:=left(btrim(coalesce(a->>'validation_error','')),500);v_storage:=btrim(coalesce(a->>'storage_path',''));v_graph_attachment:=btrim(coalesce(a->>'graph_attachment_id',''));
  IF lower(coalesce(a->>'source_hash',''))!~'^[a-f0-9]{64}$' OR length(btrim(coalesce(a->>'file_name',''))) NOT BETWEEN 1 AND 180
   OR length(v_graph_attachment) NOT BETWEEN 20 AND 300 OR v_graph_attachment NOT LIKE (p_message->>'provider_uid')||':%'
   OR v_validation NOT IN('verified','failed') OR (v_validation='verified' AND v_storage NOT LIKE 'pdc-email-intake-private/%')
   OR (v_validation='failed' AND (v_storage<>'' OR v_validation_error='')) THEN RAISE EXCEPTION 'pdc_monitor_attachment_invalid' USING errcode='22023';END IF;
  INSERT INTO public.ai_email_attachments(intake_id,graph_attachment_id,file_name,content_type,size_bytes,source_hash,storage_path,text_extraction_status,extraction_error,created_at)
  VALUES(v_id,v_graph_attachment,btrim(a->>'file_name'),left(a->>'content_type',200),coalesce((a->>'size_bytes')::bigint,0),lower(a->>'source_hash'),nullif(v_storage,''),CASE WHEN v_validation='verified' THEN 'pending' ELSE 'failed' END,nullif(v_validation_error,''),clock_timestamp())
  ON CONFLICT(intake_id,graph_attachment_id) WHERE graph_attachment_id IS NOT NULL DO NOTHING;
  IF NOT EXISTS(SELECT 1 FROM public.ai_email_attachments x WHERE x.intake_id=v_id AND x.graph_attachment_id=v_graph_attachment
   AND x.file_name=btrim(a->>'file_name') AND coalesce(x.content_type,'')=coalesce(left(a->>'content_type',200),'')
   AND x.size_bytes=coalesce((a->>'size_bytes')::bigint,0) AND x.source_hash=lower(a->>'source_hash') AND coalesce(x.storage_path,'')=v_storage
   AND ((v_validation='verified' AND x.text_extraction_status IN('pending','extracted') AND x.extraction_error IS NULL)
     OR (v_validation='failed' AND x.text_extraction_status='failed' AND coalesce(x.extraction_error,'')=v_validation_error)))
  THEN RAISE EXCEPTION 'pdc_monitor_attachment_replay_conflict' USING errcode='55000';END IF;
 END LOOP;
 IF jsonb_array_length(p_attachments)<>(SELECT count(DISTINCT value->>'graph_attachment_id') FROM jsonb_array_elements(p_attachments)) THEN RAISE EXCEPTION 'pdc_monitor_attachment_payload_duplicate' USING errcode='22023';END IF;
 IF NOT v_new AND jsonb_array_length(p_attachments)<>(SELECT count(*) FROM public.ai_email_attachments x WHERE x.intake_id=v_id) THEN RAISE EXCEPTION 'pdc_monitor_attachment_replay_conflict' USING errcode='55000';END IF;
 UPDATE public.pdc_email_monitor_status SET updated_at=clock_timestamp() WHERE singleton;
 RETURN jsonb_build_object('ok',true,'code',CASE WHEN v_new THEN 'pdc_monitor_intake_enqueued' ELSE 'pdc_monitor_intake_duplicate' END,'intake_id',v_id,'duplicate',NOT v_new,'sender_enrolled',v_sender_enrolled,'actor_email',s->>'email');
END $function$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260831210000','855_deterministic_inbound_sender_eligibility_successor',ARRAY['Retain non-enrolled sender messages as immutable review-queued deterministic receipts','Skip non-enrolled messages without Board, mailbox-flag, outbound or Production mutation','Preserve exact authenticated enrolled-sender adapter, RLS, UID514 and replay guarantees']);
NOTIFY pgrst,'reload schema';
COMMIT;
