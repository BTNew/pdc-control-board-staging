-- STAGING ONLY 455: retain authenticated unknown senders for review while
-- preserving exact-sender enforcement in every canonical mutation path.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-455-inbox-review-and-archive-runtime',0));
DO $pre$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
 OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR NOT public.pdc_monitor_staging_guard()
 OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260827004000' AND name='454_inbox_monitor_activation')
 OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260827004000')
 OR encode(extensions.digest(convert_to(pg_get_functiondef('public.enqueue_pdc_email_intake(jsonb,jsonb)'::regprocedure),'UTF8'),'sha256'),'hex')<>'6308833b3eaaeeb21cc2046aa9605cb92d651e82828b26e2f2e1357ac0413145'
 THEN RAISE EXCEPTION 'PDC_455_STAGING_HEAD_OR_FUNCTION_MISMATCH' USING errcode='55000'; END IF;
END $pre$;

CREATE OR REPLACE FUNCTION public.enqueue_pdc_email_intake(p_message jsonb,p_attachments jsonb DEFAULT '[]'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,extensions AS $function$
DECLARE
 s jsonb:=public.pdc_monitor_actor_scope();v_id uuid;v_new boolean:=false;a jsonb;
 v_mailbox public.monitored_mailboxes%rowtype;v_recipient text;v_authserv text;v_auth jsonb;v_sender text;v_sender_hash text;v_sender_enrolled boolean;
 v_validation text;v_validation_error text;v_storage text;v_graph_attachment text;
BEGIN
 IF jsonb_typeof(p_message) IS DISTINCT FROM 'object' OR jsonb_typeof(p_attachments) IS DISTINCT FROM 'array'
 OR coalesce(p_message->>'graph_message_id',p_message->>'provider_uid','')='' OR lower(coalesce(p_message->>'source_hash',''))!~'^[a-f0-9]{64}$'
 OR jsonb_array_length(p_attachments)>25 THEN RAISE EXCEPTION 'pdc_monitor_identity_required' USING errcode='22023';END IF;
 v_recipient:=lower(btrim(coalesce(p_message->>'recipient_mailbox','')));v_authserv:=lower(btrim(coalesce(p_message->>'provider_authserv_id','')));
 v_auth:=coalesce(p_message->'provider_authentication','null'::jsonb);v_sender:=lower(btrim(coalesce(p_message->>'sender_email','')));
 SELECT * INTO v_mailbox FROM public.monitored_mailboxes WHERE active AND test_mode AND lower(mailbox_address)=v_recipient;
 IF NOT FOUND OR v_authserv<>'mx.google.com' OR jsonb_typeof(v_auth) IS DISTINCT FROM 'object'
 OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_auth)k) IS DISTINCT FROM array['dkim_aligned','dmarc_aligned','gmail_authentication_results','sender_domain','spf_aligned']::text[]
 OR v_auth->'gmail_authentication_results' IS DISTINCT FROM 'true'::jsonb
 OR NOT(v_auth->'spf_aligned'='true'::jsonb OR v_auth->'dkim_aligned'='true'::jsonb OR v_auth->'dmarc_aligned'='true'::jsonb)
 OR v_auth->>'sender_domain' IS DISTINCT FROM split_part(v_sender,'@',2) THEN RAISE EXCEPTION 'pdc_monitor_provider_binding_invalid' USING errcode='22023';END IF;
 v_sender_hash:=encode(extensions.digest(convert_to(v_sender,'UTF8'),'sha256'),'hex');
 v_sender_enrolled:=EXISTS(SELECT 1 FROM public.pdc_monitor_exact_sender_enrollments e WHERE e.active AND e.sender_sha256=v_sender_hash);
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

CREATE TABLE public.pdc_email_monitor_runtime_receipts_455(
 receipt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),project_ref text NOT NULL CHECK(project_ref='cdsmnqxtyyoeoznmbidd'),
 actor_id uuid NOT NULL CHECK(actor_id='69846ef4-a74c-4569-9e35-376cf0837888'::uuid),
 monitor_sha256 text NOT NULL CHECK(monitor_sha256~'^[a-f0-9]{64}$'),bridge_sha256 text NOT NULL CHECK(bridge_sha256~'^[a-f0-9]{64}$'),
 processor_sha256 text NOT NULL CHECK(processor_sha256~'^[a-f0-9]{64}$'),manifest_sha256 text NOT NULL CHECK(manifest_sha256~'^[a-f0-9]{64}$'),
 archive_method text NOT NULL CHECK(archive_method='UID MOVE to [Gmail]/All Mail after terminal processing'),
 unknown_sender_policy text NOT NULL CHECK(unknown_sender_policy='retain for review; canonical mutations still require exact active sender enrollment'),
 production_untouched boolean NOT NULL CHECK(production_untouched),created_at timestamptz NOT NULL DEFAULT clock_timestamp());
REVOKE ALL ON public.pdc_email_monitor_runtime_receipts_455 FROM public,anon,authenticated,service_role;
CREATE FUNCTION public.pdc_email_monitor_runtime_receipt_immutable_455() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN RAISE EXCEPTION 'PDC_455_RUNTIME_RECEIPT_IMMUTABLE' USING errcode='55000';END $$;
REVOKE ALL ON FUNCTION public.pdc_email_monitor_runtime_receipt_immutable_455() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_email_monitor_runtime_receipt_immutable_455 BEFORE UPDATE OR DELETE ON public.pdc_email_monitor_runtime_receipts_455 FOR EACH ROW EXECUTE FUNCTION public.pdc_email_monitor_runtime_receipt_immutable_455();
INSERT INTO public.pdc_email_monitor_runtime_receipts_455(project_ref,actor_id,monitor_sha256,bridge_sha256,processor_sha256,manifest_sha256,archive_method,unknown_sender_policy,production_untouched)
VALUES('cdsmnqxtyyoeoznmbidd','69846ef4-a74c-4569-9e35-376cf0837888',
 'ee44fb7efe22300e08f889687954669ba0b71903f6d49db22bf5dedb4b8e0423','139b890f9eb6d2011cad6f4845a0bd26e7cc460eeeabb736c5c6ebf99f2854c0',
 '3e1e222ea1fba05cb26bd00bb7734c25fe9ae30f270d05036f5c7e0daf084f52','f15dad0070827344525cd06aa2b24171a2474e3a3a859063815d300253ef8cc2',
 'UID MOVE to [Gmail]/All Mail after terminal processing','retain for review; canonical mutations still require exact active sender enrollment',true);

DO $post$
BEGIN
 IF pg_get_functiondef('public.enqueue_pdc_email_intake(jsonb,jsonb)'::regprocedure) NOT LIKE '%sender_enrolled%'
 OR pg_get_functiondef('public.enqueue_pdc_email_intake(jsonb,jsonb)'::regprocedure) LIKE '%raise exception ''pdc_monitor_sender_not_enrolled''%'
 OR (SELECT count(*) FROM public.pdc_email_monitor_runtime_receipts_455)<>1
 OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.pdc_email_monitor_runtime_receipts_455'::regclass AND tgname='pdc_email_monitor_runtime_receipt_immutable_455' AND NOT tgisinternal)
 THEN RAISE EXCEPTION 'PDC_455_POSTCONDITION_FAILED' USING errcode='55000';END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260827005000','455_inbox_review_and_archive_runtime',ARRAY[
 'Provider-authenticated unknown senders are retained for review instead of rejected at enqueue',
 'Every canonical mutation path retains exact active sender enrollment and receipt requirements',
 'Exact runtime hashes bind Gmail UID MOVE archive behavior; Production remains untouched'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
