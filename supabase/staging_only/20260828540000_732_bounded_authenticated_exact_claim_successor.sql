-- STAGING ONLY 732: bounded exact authenticated PMB monitor claim successor.
-- The legacy generic claimant remains present for predecessor evidence but is not
-- executable by authenticated callers after this migration. This function is the
-- only queue-claim surface granted to the exact staging actor.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-732-bounded-exact-authenticated-claim',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR NOT EXISTS(SELECT 1 FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR to_regprocedure('public.claim_pdc_email_intake_authenticated_exact_731(integer,text)') IS NULL
     OR to_regprocedure('public.claim_pdc_email_intake_authenticated_exact_732(integer,text)') IS NOT NULL
     OR (SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') FROM pg_proc p WHERE p.oid='public.claim_pdc_email_intake_authenticated_exact_731(integer,text)'::regprocedure)<>'a7cd82b4ab1ba1629f9d7466a6bd06657ac5a068dbe67512640ec61869e52513'
     OR (SELECT count(*) FROM public.pdc_monitor_runtime_bindings_255 WHERE singleton AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND gateway_instance_id='pdc-monitor-staging-sales-uid509-v1' AND release_name='pdc-monitor-staging-m502-2026.08.44' AND source_sha='e850c319989d98b45b95a28aa815d78e2c2e3a4b' AND manifest_sha256='d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d' AND semantic_planner_sha256='7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348' AND semantic_planner_trust_receipt_sha256='e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227' AND semantic_planner_commissioned_at IS NOT NULL)<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_active_capability_controls_672 WHERE singleton AND enabled AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND jwt_role='authenticated' AND server_application_role='importer' AND gateway_instance_id='pdc-monitor-staging-sales-uid509-v1' AND release_name='pdc-monitor-staging-m502-2026.08.44' AND source_sha='e850c319989d98b45b95a28aa815d78e2c2e3a4b' AND manifest_sha256='d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d' AND planner_sha256='7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348' AND trust_receipt_sha256='e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227' AND NOT production_writes AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed)<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_execution_attachment_controls_673 WHERE singleton AND enabled AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND actor_email='sales@broometoyota.com.au' AND jwt_role='authenticated' AND server_application_role='importer' AND gateway_instance_id='pdc-monitor-staging-sales-uid509-v1' AND release_name='pdc-monitor-staging-m502-2026.08.44' AND source_sha='e850c319989d98b45b95a28aa815d78e2c2e3a4b' AND manifest_sha256='d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d' AND planner_sha256='7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348' AND trust_receipt_sha256='e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227' AND observed_mime_part_count=7 AND retained_authenticated_attachment_count=4 AND all_mime_parts_retained AND NOT production_writes AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed)<>1
     OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>1
     OR (SELECT count(*) FROM public.monitored_mailboxes WHERE id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57' AND mailbox_key='pdc_pmb_email' AND lower(mailbox_address)='pmbcontroller@gmail.com' AND lower(provider)='gmail' AND active AND test_mode AND config->>'owner_profile'='pdc-monitor' AND config->>'contains_credentials'='false' AND config->>'operational_scope'='staging')<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND minimum_uid=639 AND NOT enabled AND NOT automatic_rule_application AND NOT automatic_authenticated_jobcards AND NOT outbound_email_enabled)<>1
     OR (SELECT count(*) FROM public.ai_email_intake WHERE provider_uid='imap_uid:514')<>1
  THEN RAISE EXCEPTION 'PDC_732_EXACT_731_PREDECESSOR_OR_SCOPE_PRESTATE_MISMATCH' USING errcode='55000';
  END IF;
END
$guard$;

CREATE OR REPLACE FUNCTION public.claim_pdc_email_intake_authenticated_exact_732(p_limit integer,p_gateway_instance_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,public,auth
AS $claim$
DECLARE
  v_rows jsonb;
  v_minimum_uid integer;
BEGIN
  IF current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR auth.uid()<>'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid
     OR lower(btrim(coalesce(auth.jwt()->>'email','')))<>'sales@broometoyota.com.au'
     OR coalesce(auth.jwt()->>'role','')<>'authenticated'
     OR public.current_pdc_user_role()<>'importer'
     OR btrim(coalesce(p_gateway_instance_id,''))<>'pdc-monitor-staging-sales-uid509-v1'
     OR NOT public.pdc_email_monitor_runtime_authorized_502(p_gateway_instance_id)
     OR NOT public.pdc_monitor_authenticated_active_scope_674(p_gateway_instance_id)
     OR (SELECT count(*) FROM public.pdc_monitor_runtime_bindings_255 WHERE singleton AND actor_id=auth.uid() AND gateway_instance_id='pdc-monitor-staging-sales-uid509-v1' AND release_name='pdc-monitor-staging-m502-2026.08.44' AND source_sha='e850c319989d98b45b95a28aa815d78e2c2e3a4b' AND manifest_sha256='d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d' AND semantic_planner_sha256='7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348' AND semantic_planner_trust_receipt_sha256='e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227' AND semantic_planner_commissioned_at IS NOT NULL)<>1
     OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>1
     OR (SELECT count(*) FROM public.monitored_mailboxes WHERE id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57' AND mailbox_key='pdc_pmb_email' AND lower(mailbox_address)='pmbcontroller@gmail.com' AND lower(provider)='gmail' AND active AND test_mode)<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND minimum_uid=639 AND NOT enabled AND NOT automatic_rule_application AND NOT automatic_authenticated_jobcards AND NOT outbound_email_enabled)<>1
  THEN RAISE EXCEPTION 'PDC_731_EXACT_ACTOR_RUNTIME_UNAUTHORIZED' USING errcode='42501';
  END IF;
  IF p_limit NOT BETWEEN 1 AND 10 THEN RAISE EXCEPTION 'pdc_monitor_claim_invalid' USING errcode='22023'; END IF;
  SELECT minimum_uid INTO v_minimum_uid FROM public.pdc_email_monitor_pilot WHERE singleton;
  WITH candidates AS (
    SELECT id
    FROM public.ai_email_intake
    WHERE status IN('received','failed','processing')
      AND NOT permanent_failure
      AND monitored_mailbox_id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57'::uuid
      AND lower(recipient_mailbox)='pmbcontroller@gmail.com'
      AND provider_uid<>'imap_uid:514'
      AND provider_uid~'^imap_uid:[0-9]+$'
      AND CASE WHEN provider_uid~'^imap_uid:[0-9]+$' THEN substring(provider_uid from '^imap_uid:([0-9]+)$')::bigint ELSE -1 END>=v_minimum_uid
      AND CASE WHEN provider_uid~'^imap_uid:[0-9]+$' THEN substring(provider_uid from '^imap_uid:([0-9]+)$')::bigint ELSE 100000 END<100000
      AND lower(coalesce(source_hash,''))~'^[a-f0-9]{64}$'
      AND coalesce(next_attempt_at,'-infinity')<=clock_timestamp()
      AND(status<>'processing' OR locked_at<clock_timestamp()-interval '10 minutes')
    ORDER BY received_at NULLS LAST,created_at
    FOR UPDATE SKIP LOCKED LIMIT p_limit
  ), claimed AS (
    UPDATE public.ai_email_intake i
    SET status='processing',locked_at=clock_timestamp(),locked_by=auth.uid(),claim_token=gen_random_uuid(),gateway_instance_id=btrim(p_gateway_instance_id),last_attempt_at=clock_timestamp(),queue_attempts=queue_attempts+1,error_details=null,last_error_code=null
    FROM candidates c WHERE i.id=c.id
    RETURNING i.id,i.subject,i.sender_email,i.received_at,i.graph_message_id,i.graph_thread_id,i.internet_message_id,i.source_hash,i.raw_body,i.parsed_text,i.queue_attempts,i.claim_token,i.gateway_instance_id,i.provider_authentication,i.provider_authserv_id,i.provider_uid,i.recipient_mailbox,i.monitored_mailbox_id
  )
  SELECT coalesce(jsonb_agg(to_jsonb(claimed) ORDER BY received_at),'[]'::jsonb) INTO v_rows FROM claimed;
  UPDATE public.pdc_email_monitor_status SET running_status='running',last_started_at=clock_timestamp(),gateway_instance_id=btrim(p_gateway_instance_id),updated_at=clock_timestamp() WHERE singleton;
  RETURN jsonb_build_object('ok',true,'items',v_rows,'count',jsonb_array_length(v_rows),'claim_scope','authenticated-exact-731','source_scope','server-side-provider-uid-and-source-hash');
END
$claim$;

REVOKE ALL ON FUNCTION public.claim_pdc_email_intake_batch(integer,text) FROM public,anon,authenticated,service_role,pdc_email_monitor;
REVOKE ALL ON FUNCTION public.claim_pdc_email_intake_authenticated_exact_731(integer,text) FROM public,anon,authenticated,service_role,pdc_email_monitor;
REVOKE ALL ON FUNCTION public.claim_pdc_email_intake_authenticated_exact_732(integer,text) FROM public,anon,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.claim_pdc_email_intake_authenticated_exact_732(integer,text) TO authenticated;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260828540000','732_bounded_authenticated_exact_claim_successor',ARRAY[
  'Revoke authenticated EXECUTE on the legacy generic claimant',
  'Add an exact actor/importer/gateway/runtime-binding/mailbox/current-provider-UID security-definer claim successor',
  'Preserve server-side source hashes, claim tokens, queue attempts, retry state and UID514 exclusion',
  'Grant only authenticated EXECUTE on the exact successor; deny anon, service_role and direct queue DML'
]);
COMMIT;
