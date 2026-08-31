-- STAGING ONLY: append-only replay repair after the live 55000 attachment conflict.
-- A duplicate intake may receive newly attested attachment parts after a prior
-- partial import. Preserve all existing rows and append only exact new parts.
BEGIN;
SELECT pg_advisory_xact_lock(hashtextextended('pdc-monitor-staging-860-append-missing-attachments',0));
DO $$ BEGIN
 IF current_setting('app.environment',true)='production'
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260831380000' AND name='pdc_email_ai_successor_actor_first_gate')<>1
 THEN RAISE EXCEPTION 'PDC_860_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $$;

CREATE OR REPLACE FUNCTION public.enqueue_pdc_email_intake(p_message jsonb,p_attachments jsonb DEFAULT '[]'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog','public','extensions'
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
  INSERT INTO public.pdc_monitor_inbound_eligibility_receipts_855(receipt_key,provider_uid,source_hash,sender_address,recipient_mailbox,provider_authserv_id,provider_authentication,disposition,review_queued,board_mutations,mailbox_flags_changed,outbound_email_sent,production_writes)
  VALUES(v_receipt_key,btrim(coalesce(p_message->>'provider_uid','')),lower(coalesce(p_message->>'source_hash','')),v_sender,v_recipient,v_authserv,v_auth,'review_queued',true,0,false,false,false) ON CONFLICT(receipt_key) DO NOTHING;
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
 -- On replay, do not reject an exact payload that contains newly attested parts.
 -- Existing rows not present in the payload are still rejected below, preserving
 -- append-only evidence and preventing a subset replay from being accepted.
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
 IF NOT v_new AND EXISTS(SELECT 1 FROM public.ai_email_attachments x WHERE x.intake_id=v_id AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p_attachments) supplied(value) WHERE supplied.value->>'graph_attachment_id'=x.graph_attachment_id)) THEN RAISE EXCEPTION 'pdc_monitor_attachment_replay_conflict' USING errcode='55000';END IF;
 UPDATE public.pdc_email_monitor_status SET updated_at=clock_timestamp() WHERE singleton;
 RETURN jsonb_build_object('ok',true,'code',CASE WHEN v_new THEN 'pdc_monitor_intake_enqueued' ELSE 'pdc_monitor_intake_duplicate' END,'intake_id',v_id,'duplicate',NOT v_new,'sender_enrolled',v_sender_enrolled,'actor_email',s->>'email');
END $function$;
REVOKE ALL ON FUNCTION public.enqueue_pdc_email_intake(jsonb,jsonb) FROM public,anon,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.enqueue_pdc_email_intake(jsonb,jsonb) TO authenticated;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260831390000','860_append_missing_monitor_attachments_on_replay',ARRAY['Append exact newly attested attachment parts on a matching intake replay','Retain omission and metadata conflict guards','Preserve append-only evidence, authenticated execution and Production exclusion']);
NOTIFY pgrst,'reload schema';
COMMIT;
