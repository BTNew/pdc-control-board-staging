-- STAGING ONLY 814: keep historical rollback boundary free of monitor-status drift.
-- 812 historical enqueue copied the normal live enqueue status timestamp update.
-- 793 snapshots the protected boundary before enqueue, so that harmless status
-- timestamp changed the snapshot and raised PDC_788_PROTECTED_BOUNDARY_DRIFT.
-- Remove only that update from the separately named historical adapter; normal
-- enqueue remains unchanged and all identity/evidence/intake/attachment,
-- idempotency, RLS/grants and atomic rollback controls remain enforced.
BEGIN;
SET LOCAL lock_timeout='15s'; SET LOCAL statement_timeout='300s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-814-historical-status-drift',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
DECLARE v text;
BEGIN
 SELECT p.prosrc INTO v FROM pg_proc p WHERE p.oid='public.enqueue_pdc_historical_email_intake_812(jsonb,jsonb)'::regprocedure;
 IF current_user<>'postgres' OR session_user<>'postgres' OR NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR (SELECT (version,name)::text FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1) IS DISTINCT FROM '(20260830234000,813_historical_unique_attachment_observation_request_hash_successor)' OR encode(extensions.digest(convert_to(v,'UTF8'),'sha256'),'hex') IS DISTINCT FROM '3aafebd348bbec26ec54dca67587fe2a09b3e95c00310c0734bebb2e7970e8d7' OR position('UPDATE public.pdc_email_monitor_status SET updated_at=clock_timestamp() WHERE singleton' in v)=0 OR (SELECT count(*) FROM public.pdc_historical_reconciliation_writer_authorizations_809 WHERE active AND expires_at>clock_timestamp())<>5 OR (SELECT count(*) FROM public.pdc_historical_reconciliation_778_receipts)<>0 OR (SELECT count(*) FROM public.pdc_historical_provider_observations_778)<>0 OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>0 THEN RAISE EXCEPTION 'PDC_814_CURRENT_HEAD_OR_HELPER_PRESTATE_FAILED' USING errcode='55000'; END IF;
END $guard$;
CREATE OR REPLACE FUNCTION public.enqueue_pdc_historical_email_intake_812(p_message jsonb, p_attachments jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
 s jsonb:=jsonb_build_object('ok',public.pdc_monitor_authenticated_active_scope_673(NULL),'user_id',auth.uid(),'email',lower(btrim(coalesce(auth.jwt()->>'email',''))),'role','importer');v_id uuid;v_new boolean:=false;a jsonb;
 v_mailbox public.monitored_mailboxes%rowtype;v_recipient text;v_authserv text;v_auth jsonb;v_sender text;v_sender_hash text;v_sender_enrolled boolean;
 v_validation text;v_validation_error text;v_storage text;v_graph_attachment text;
BEGIN
 IF jsonb_typeof(p_message) IS DISTINCT FROM 'object' OR jsonb_typeof(p_attachments) IS DISTINCT FROM 'array'
 OR coalesce(p_message->>'graph_message_id',p_message->>'provider_uid','')='' OR lower(coalesce(p_message->>'source_hash',''))!~'^[a-f0-9]{64}$'
 OR jsonb_array_length(p_attachments)>25 THEN RAISE EXCEPTION 'pdc_monitor_identity_required' USING errcode='22023';END IF;
 v_recipient:=lower(btrim(coalesce(p_message->>'recipient_mailbox','')));v_authserv:=lower(btrim(coalesce(p_message->>'provider_authserv_id','')));
 v_auth:=coalesce(p_message->'provider_authentication','null'::jsonb);v_sender:=lower(btrim(coalesce(p_message->>'sender_email','')));
 SELECT * INTO v_mailbox FROM public.monitored_mailboxes WHERE id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57'::uuid AND test_mode AND NOT active AND lower(mailbox_address)=v_recipient;
 IF NOT coalesce((s->>'ok')::boolean,false) OR p_message->>'historical_manifest_sha256' IS NULL OR p_message->>'historical_evidence_hash' IS NULL OR (SELECT count(*) FROM public.pdc_historical_writer_authorization_809_resolve(p_message->>'historical_manifest_sha256',p_message->>'provider_uid',p_message->>'source_hash',v_sender,v_auth,p_message->>'stock_number',p_message->>'historical_evidence_hash'))<>1 THEN RAISE EXCEPTION 'pdc_historical_enqueue_authorization_failed' USING errcode='42501'; END IF;
 IF NOT FOUND OR v_authserv<>'mx.google.com' OR jsonb_typeof(v_auth) IS DISTINCT FROM 'object'
 OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_auth)k) IS DISTINCT FROM array['dkim_aligned','dmarc_aligned','gmail_authentication_results','sender_domain','spf_aligned']::text[]
 OR v_auth->'gmail_authentication_results' IS DISTINCT FROM 'true'::jsonb
 OR NOT(v_auth->'spf_aligned'='true'::jsonb OR v_auth->'dkim_aligned'='true'::jsonb OR v_auth->'dmarc_aligned'='true'::jsonb)
 OR v_auth->>'sender_domain' IS DISTINCT FROM split_part(v_sender,'@',2) THEN RAISE EXCEPTION 'pdc_monitor_provider_binding_invalid' USING errcode='22023';END IF;
 v_sender_hash:=encode(extensions.digest(convert_to(v_sender,'UTF8'),'sha256'),'hex');
 v_sender_enrolled:=EXISTS(SELECT 1 FROM public.pdc_monitor_exact_sender_enrollments e WHERE e.active AND e.sender_sha256=v_sender_hash)
    OR public.pdc_historical_writer_authorized_773(lower(coalesce(p_message->>'source_hash','')),btrim(coalesce(p_message->>'provider_uid','')),v_sender,v_auth,p_message->>'stock_number');
 INSERT INTO public.ai_email_intake(graph_message_id,internet_message_id,provider_uid,source_hash,subject,sender_email,sender_name,received_at,raw_body,parsed_text,attachment_names,status,queue_attempts,next_attempt_at,monitored_mailbox_id,recipient_mailbox,provider_authserv_id,provider_authentication,extracted_data,created_at,updated_at)
 VALUES(p_message->>'graph_message_id',p_message->>'internet_message_id',p_message->>'provider_uid',lower(p_message->>'source_hash'),left(p_message->>'subject',1000),v_sender,left(p_message->>'sender_name',300),nullif(p_message->>'received_at','')::timestamptz,p_message->>'raw_body',p_message->>'parsed_text',coalesce(array(SELECT jsonb_array_elements_text(coalesce(p_message->'attachment_names','[]'::jsonb))),array[]::text[]),'received',0,clock_timestamp(),NULL,v_recipient,v_authserv,v_auth,jsonb_build_object('provider_authentication',v_auth,'provider_authserv_id',v_authserv,'sender_enrolled',v_sender_enrolled),clock_timestamp(),clock_timestamp())
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
 -- Historical 778 is rollback-only and must not mutate monitor status.
 RETURN jsonb_build_object('ok',true,'code',CASE WHEN v_new THEN 'pdc_monitor_intake_enqueued' ELSE 'pdc_monitor_intake_duplicate' END,'intake_id',v_id,'duplicate',NOT v_new,'sender_enrolled',v_sender_enrolled,'actor_email',s->>'email');
END $function$
;
REVOKE ALL ON FUNCTION public.enqueue_pdc_historical_email_intake_812(jsonb,jsonb) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.enqueue_pdc_historical_email_intake_812(jsonb,jsonb) TO postgres;
DO $post$
DECLARE v text; owner_name text; secdef boolean; acl text;
BEGIN
 SELECT p.prosrc,p.proowner::regrole::text,p.prosecdef,p.proacl::text INTO v,owner_name,secdef,acl FROM pg_proc p WHERE p.oid='public.enqueue_pdc_historical_email_intake_812(jsonb,jsonb)'::regprocedure;
 IF owner_name IS DISTINCT FROM 'postgres' OR NOT secdef OR acl IS DISTINCT FROM '{postgres=X/postgres}' OR encode(extensions.digest(convert_to(v,'UTF8'),'sha256'),'hex') IS DISTINCT FROM 'cfae838fa89fadb4176ae6f73c11a88ca25ecdecde1009641b6998ce6e847c12' OR position('UPDATE public.pdc_email_monitor_status SET updated_at=clock_timestamp() WHERE singleton' in v)>0 OR position('pdc_monitor_authenticated_active_scope_673' in v)=0 OR position('pdc_historical_writer_authorization_809_resolve' in v)=0 OR position('pdc_historical_enqueue_authorization_failed' in v)=0 THEN RAISE EXCEPTION 'PDC_814_HISTORICAL_STATUS_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260830235000','814_historical_enqueue_status_drift_successor',ARRAY['remove only historical enqueue monitor-status timestamp update that violated 793 protected boundary zero-drift snapshot','preserve normal live enqueue, exact 673/809 identity/evidence binding and inactive staging mailbox rules','preserve atomic rollback, idempotency, RLS/grants, ten conflicts and no prohibited operations']);
COMMIT;
