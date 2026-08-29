-- STAGING ONLY 766: current-head authenticated Monitor compatibility successor.
-- This is append-only and external-control oriented. It binds the exact live
-- 765 predecessor, current canonical claim/provider/process RPCs, the existing
-- sales@ authenticated actor, exact gateway/planner/trust, one active staging
-- mailbox, forced-RLS controls, and the existing no-outbound/no-Production
-- boundary. It does not enable the pilot or Scheduled Task and never contacts
-- the mailbox or processes UID514.
BEGIN;
SET LOCAL lock_timeout='15s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-766-monitor-current-head-compatibility',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR lower(coalesce(current_setting('app.environment',true),''))='production'
     OR (SELECT max(version) FILTER (WHERE version~'^[0-9]{14}$') FROM supabase_migrations.schema_migrations)<>'20260830040000'
     OR NOT EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260830040000' AND name='765_authenticated_exact_claim_floor_640_successor')
     OR to_regclass('public.pdc_email_monitor_current_head_compatibility_controls_766') IS NOT NULL
     OR to_regclass('public.pdc_email_monitor_current_head_compatibility_history_766') IS NOT NULL
     OR to_regprocedure('public.verify_pdc_monitor_runtime_binding_authenticated_766(text,text,text,text,text,text,text)') IS NOT NULL
     OR to_regprocedure('public.attest_pdc_monitor_provider_email_observation_current_766(text,uuid,uuid,uuid,text,text,text,text,jsonb)') IS NOT NULL
     OR to_regprocedure('public.claim_pdc_email_intake_authenticated_exact_732(integer,text)') IS NULL
     OR to_regprocedure('public.attest_pdc_provider_email_observation(uuid,uuid,text,text,text,text,jsonb)') IS NULL
     OR to_regprocedure('public.process_claimed_pdc_email_intake_work(uuid,uuid,text,text,text,jsonb)') IS NULL
     OR (SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') FROM pg_proc p WHERE p.oid='public.claim_pdc_email_intake_authenticated_exact_732(integer,text)'::regprocedure)<>'561302063f300f1f25a2e21f87d4aff34b939008dd8c6d9c0f032ddf5882c747'
     OR (SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') FROM pg_proc p WHERE p.oid='public.attest_pdc_provider_email_observation(uuid,uuid,text,text,text,text,jsonb)'::regprocedure)<>'7be3241ac65da67024907c2afd1f47d3d82ca429960d3f1464dc56d489c8e0dd'
     OR (SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') FROM pg_proc p WHERE p.oid='public.process_claimed_pdc_email_intake_work(uuid,uuid,text,text,text,jsonb)'::regprocedure)<>'2300607f798c007efc03a835840a50926a0a150ece6a9bc86db719666ac1c8b7'
     OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>1
     OR (SELECT count(*) FROM public.monitored_mailboxes WHERE id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57' AND mailbox_key='pdc_pmb_email' AND lower(mailbox_address)='pmbcontroller@gmail.com' AND lower(provider)='gmail' AND active AND test_mode AND config->>'owner_profile'='pdc-monitor' AND config->>'contains_credentials'='false' AND config->>'operational_scope'='staging')<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND minimum_uid=640 AND NOT enabled AND NOT automatic_rule_application AND NOT automatic_authenticated_jobcards AND NOT outbound_email_enabled)<>1
     OR (SELECT count(*) FROM public.ai_email_intake WHERE provider_uid='imap_uid:514')<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_mailbox_activation_controls_674 WHERE singleton AND enabled AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND NOT production_writes AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed)<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_enqueue_trigger_controls_675 WHERE singleton AND enabled AND pilot_remains_disabled AND NOT production_writes AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed)<>1
  THEN RAISE EXCEPTION 'PDC_766_EXACT_765_PREDECESSOR_OR_CANONICAL_CONTRACT_MISMATCH' USING errcode='55000'; END IF;
END
$guard$;

CREATE TABLE public.pdc_email_monitor_current_head_compatibility_controls_766(
  singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
  enabled boolean NOT NULL DEFAULT true CHECK(enabled),
  predecessor_head text NOT NULL CHECK(predecessor_head='20260830040000'),
  successor_head text NOT NULL CHECK(successor_head='20260830050000'),
  actor_id uuid NOT NULL CHECK(actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'),
  actor_email text NOT NULL CHECK(actor_email='sales@broometoyota.com.au'),
  jwt_role text NOT NULL CHECK(jwt_role='authenticated'),
  server_application_role text NOT NULL CHECK(server_application_role='importer'),
  gateway_instance_id text NOT NULL CHECK(gateway_instance_id='pdc-monitor-staging-sales-uid509-v1'),
  release_name text NOT NULL CHECK(release_name='pdc-monitor-staging-m502-2026.08.44'),
  source_sha text NOT NULL CHECK(source_sha='e850c319989d98b45b95a28aa815d78e2c2e3a4b'),
  manifest_sha256 text NOT NULL CHECK(manifest_sha256='d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d'),
  planner_interface text NOT NULL CHECK(planner_interface='pmb-pdc-agentic-email-plan-v1'),
  planner_sha256 text NOT NULL CHECK(planner_sha256='7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348'),
  trust_receipt_sha256 text NOT NULL CHECK(trust_receipt_sha256='e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227'),
  canonical_contract jsonb NOT NULL,
  task_enabled boolean NOT NULL DEFAULT false CHECK(NOT task_enabled),
  mailbox_contacted boolean NOT NULL DEFAULT false CHECK(NOT mailbox_contacted),
  uid514_processed boolean NOT NULL DEFAULT false CHECK(NOT uid514_processed),
  production_writes boolean NOT NULL DEFAULT false CHECK(NOT production_writes),
  changed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_email_monitor_current_head_compatibility_controls_766 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_monitor_current_head_compatibility_controls_766 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_email_monitor_current_head_compatibility_controls_766 FROM public,anon,authenticated,service_role,pdc_email_monitor;

INSERT INTO public.pdc_email_monitor_current_head_compatibility_controls_766(
  predecessor_head,successor_head,actor_id,actor_email,jwt_role,server_application_role,gateway_instance_id,release_name,source_sha,manifest_sha256,planner_interface,planner_sha256,trust_receipt_sha256,canonical_contract)
VALUES(
 '20260830040000','20260830050000','df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b','sales@broometoyota.com.au','authenticated','importer','pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44','e850c319989d98b45b95a28aa815d78e2c2e3a4b','d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d','pmb-pdc-agentic-email-plan-v1','7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348','e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227',
 jsonb_build_object(
  'claim','public.claim_pdc_email_intake_authenticated_exact_732(integer,text)','claim_sha256','561302063f300f1f25a2e21f87d4aff34b939008dd8c6d9c0f032ddf5882c747',
  'provider_observation','public.attest_pdc_provider_email_observation(uuid,uuid,text,text,text,text,jsonb)','provider_observation_sha256','7be3241ac65da67024907c2afd1f47d3d82ca429960d3f1464dc56d489c8e0dd',
  'provider_wrapper','public.attest_pdc_monitor_provider_email_observation_current_766(text,uuid,uuid,uuid,text,text,text,text,jsonb)',
  'process','public.process_claimed_pdc_email_intake_work(uuid,uuid,text,text,text,jsonb)','process_sha256','2300607f798c007efc03a835840a50926a0a150ece6a9bc86db719666ac1c8b7',
  'cycle','public.record_pdc_email_monitor_cycle(text,text,text)','cycle_sha256','9d6062c9f76327de371b59f1bd895572da03d4dff8d5799b8b405a215f964405',
  'heartbeat','public.heartbeat_pdc_email_intake_claim(uuid,uuid,text)','heartbeat_sha256','6c759cdc8e9c2f6bc6a55e93e9a95f19e19a6744ba73e03c3ce094076d89028d',
  'attachments','public.get_pdc_monitor_intake_attachments(uuid,uuid,text)','attachments_sha256','52468b02eac43a7b53f2fa46c5f2c917807d60d72685fd23d7b17a6b6c5e1194',
  'extraction','public.record_pdc_monitor_attachment_extraction(uuid,uuid,uuid,text,text,text)','extraction_sha256','a370c23c861fa91b9f1f18c0454d151abf457cbc6ea4f7fc081cdf9f172d47e3',
  'result','public.record_pdc_email_intake_result(uuid,uuid,text,boolean,jsonb,text,text,boolean,jsonb)','result_sha256','679fe3b75df0ac020810cb6d3253557576d50583d5c78acad9c51e7a2db3c63c'
  )
 );

CREATE TABLE public.pdc_email_monitor_current_head_compatibility_history_766(
  history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key text NOT NULL UNIQUE,
  event_kind text NOT NULL CHECK(event_kind IN('forward_current_head_compatibility','rollback')),
  predecessor_head text NOT NULL CHECK(predecessor_head='20260830040000'),
  successor_head text NOT NULL CHECK(successor_head='20260830050000'),
  actor_id uuid NOT NULL,
  actor_email text NOT NULL,
  gateway_instance_id text NOT NULL,
  release_name text NOT NULL,
  source_sha text NOT NULL,
  manifest_sha256 text NOT NULL,
  canonical_contract jsonb NOT NULL,
  task_enabled boolean NOT NULL CHECK(NOT task_enabled),
  mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),
  uid514_processed boolean NOT NULL CHECK(NOT uid514_processed),
  production_writes boolean NOT NULL CHECK(NOT production_writes),
  rollback_contract text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_email_monitor_current_head_compatibility_history_766 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_monitor_current_head_compatibility_history_766 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_email_monitor_current_head_compatibility_history_766 FROM public,anon,authenticated,service_role,pdc_email_monitor;
CREATE FUNCTION public.pdc_email_monitor_current_head_compatibility_history_immutable_766()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public
AS $immutable$ BEGIN RAISE EXCEPTION 'PDC_766_CURRENT_HEAD_HISTORY_IMMUTABLE' USING errcode='55000'; END $immutable$;
CREATE TRIGGER pdc_email_monitor_current_head_compatibility_history_immutable_766
BEFORE UPDATE OR DELETE ON public.pdc_email_monitor_current_head_compatibility_history_766
FOR EACH ROW EXECUTE FUNCTION public.pdc_email_monitor_current_head_compatibility_history_immutable_766();

CREATE FUNCTION public.attest_pdc_monitor_provider_email_observation_current_766(
  p_gateway_instance_id text,p_claim_token uuid,p_intake_id uuid,p_attachment_id uuid,
  p_expected_parent_hash text,p_expected_attachment_hash text,p_provider_message_id text,
  p_provider_authserv_id text,p_authentication jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,auth,extensions
SET statement_timeout='60s'
AS $attest$
DECLARE i public.ai_email_intake%rowtype; a public.ai_email_attachments%rowtype; r jsonb;
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR NOT public.pdc_monitor_authenticated_active_scope_674(p_gateway_instance_id)
     OR auth.uid()<>'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid
     OR coalesce(auth.jwt()->>'role','')<>'authenticated'
     OR lower(btrim(coalesce(auth.jwt()->>'email','')))<>'sales@broometoyota.com.au'
     OR p_gateway_instance_id<>'pdc-monitor-staging-sales-uid509-v1'
     OR p_intake_id IS NULL OR p_claim_token IS NULL OR p_attachment_id IS NULL
  THEN RETURN public.navision_backend_response(false,'provider_observation_binding_mismatch'); END IF;
  SELECT * INTO i FROM public.ai_email_intake
   WHERE id=p_intake_id AND status='processing' AND locked_by=auth.uid() AND claim_token=p_claim_token
     AND gateway_instance_id=btrim(p_gateway_instance_id) AND locked_at>=clock_timestamp()-interval '10 minutes'
     AND lower(coalesce(source_hash,''))=lower(btrim(coalesce(p_expected_parent_hash,'')))
     AND monitored_mailbox_id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57'::uuid
     AND lower(recipient_mailbox)='pmbcontroller@gmail.com';
  IF NOT FOUND THEN RETURN public.navision_backend_response(false,'provider_observation_binding_mismatch'); END IF;
  SELECT * INTO a FROM public.ai_email_attachments
   WHERE id=p_attachment_id AND intake_id=i.id
     AND lower(coalesce(source_hash,''))=lower(btrim(coalesce(p_expected_attachment_hash,''))) FOR SHARE;
  IF NOT FOUND THEN RETURN public.navision_backend_response(false,'provider_observation_binding_mismatch'); END IF;
  IF p_provider_message_id IS DISTINCT FROM coalesce(nullif(btrim(i.internet_message_id),''),i.graph_message_id)
     OR lower(btrim(coalesce(p_provider_authserv_id,'')))<>'mx.google.com'
     OR p_authentication IS DISTINCT FROM i.provider_authentication
  THEN RETURN public.navision_backend_response(false,'provider_observation_binding_mismatch'); END IF;
  -- The existing provider RPC remains the sole observation insert/idempotency
  -- authority. This wrapper only supplies the authenticated claim custody.
  r:=public.attest_pdc_provider_email_observation(i.id,a.id,lower(btrim(p_expected_parent_hash)),lower(btrim(p_expected_attachment_hash)),p_provider_message_id,lower(btrim(p_provider_authserv_id)),p_authentication);
  RETURN r;
END
$attest$;
REVOKE ALL ON FUNCTION public.attest_pdc_monitor_provider_email_observation_current_766(text,uuid,uuid,uuid,text,text,text,text,jsonb) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.attest_pdc_monitor_provider_email_observation_current_766(text,uuid,uuid,uuid,text,text,text,text,jsonb) TO authenticated;

CREATE FUNCTION public.verify_pdc_monitor_runtime_binding_authenticated_766(
  p_mode text,p_gateway_instance_id text,p_release_name text,p_source_sha text,p_manifest_sha256 text,
  p_semantic_planner_sha256 text DEFAULT NULL,p_semantic_planner_trust_receipt_sha256 text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,auth,extensions
AS $verify$
DECLARE c public.pdc_email_monitor_current_head_compatibility_controls_766%rowtype; h text; n text;
BEGIN
  IF NOT public.pdc_monitor_authenticated_active_scope_674(p_gateway_instance_id)
     OR lower(btrim(coalesce(p_mode,'')))<>'active'
     OR p_gateway_instance_id<>'pdc-monitor-staging-sales-uid509-v1'
     OR p_release_name<>'pdc-monitor-staging-m502-2026.08.44'
     OR lower(p_source_sha)<>'e850c319989d98b45b95a28aa815d78e2c2e3a4b'
     OR lower(p_manifest_sha256)<>'d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d'
     OR lower(p_semantic_planner_sha256)<>'7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348'
     OR lower(p_semantic_planner_trust_receipt_sha256)<>'e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227'
  THEN RETURN jsonb_build_object('ok',false,'code','runtime_binding_mismatch','production_writes',false); END IF;
  SELECT * INTO c FROM public.pdc_email_monitor_current_head_compatibility_controls_766 WHERE singleton AND enabled;
  SELECT version,name INTO h,n FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1;
  IF NOT FOUND OR h<>'20260830050000' OR n<>'766_monitor_current_head_compatibility'
     OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND minimum_uid=640 AND NOT enabled AND NOT automatic_rule_application AND NOT automatic_authenticated_jobcards AND NOT outbound_email_enabled)<>1
     OR (SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') FROM pg_proc p WHERE p.oid='public.claim_pdc_email_intake_authenticated_exact_732(integer,text)'::regprocedure)<>c.canonical_contract->>'claim_sha256'
     OR (SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') FROM pg_proc p WHERE p.oid='public.attest_pdc_provider_email_observation(uuid,uuid,text,text,text,text,jsonb)'::regprocedure)<>c.canonical_contract->>'provider_observation_sha256'
     OR (SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') FROM pg_proc p WHERE p.oid='public.process_claimed_pdc_email_intake_work(uuid,uuid,text,text,text,jsonb)'::regprocedure)<>c.canonical_contract->>'process_sha256'
     OR NOT has_function_privilege('authenticated',c.canonical_contract->>'claim','execute')
     OR has_function_privilege('anon',c.canonical_contract->>'claim','execute')
     OR has_function_privilege('service_role',c.canonical_contract->>'claim','execute')
     OR NOT has_function_privilege('authenticated',c.canonical_contract->>'provider_wrapper','execute')
     OR has_function_privilege('anon',c.canonical_contract->>'provider_wrapper','execute')
     OR has_function_privilege('service_role',c.canonical_contract->>'provider_wrapper','execute')
     OR NOT has_function_privilege('authenticated',c.canonical_contract->>'process','execute')
     OR has_function_privilege('anon',c.canonical_contract->>'process','execute')
     OR has_function_privilege('service_role',c.canonical_contract->>'process','execute')
  THEN RETURN jsonb_build_object('ok',false,'code','current_head_or_canonical_contract_mismatch','production_writes',false); END IF;
  RETURN jsonb_build_object('ok',true,'code','runtime_binding_verified_authenticated_766','mode','active','operational',true,'activation_ready',true,
    'actor_id',c.actor_id,'actor_email',c.actor_email,'jwt_role',c.jwt_role,'server_application_role',c.server_application_role,
    'gateway_instance_id',c.gateway_instance_id,'release_name',c.release_name,'source_sha',c.source_sha,'manifest_sha256',c.manifest_sha256,
    'semantic_planner_sha256',c.planner_sha256,'semantic_planner_trust_receipt_sha256',c.trust_receipt_sha256,
    'planner_commissioned',true,'writer_active',true,'mailbox_id','12fe383d-5c1e-5801-96e4-f67cf3e3bb57','mailbox_active',true,'active_mailbox_count',1,
    'migration_head',766,'compatibility_successor_head',766,'canonical_contract',c.canonical_contract,
    'production_writes',false,'task_enabled',false,'mailbox_contacted',false,'uid514_processed',false);
END
$verify$;
REVOKE ALL ON FUNCTION public.verify_pdc_monitor_runtime_binding_authenticated_766(text,text,text,text,text,text,text) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.verify_pdc_monitor_runtime_binding_authenticated_766(text,text,text,text,text,text,text) TO authenticated;

INSERT INTO public.pdc_email_monitor_current_head_compatibility_history_766(
 event_key,event_kind,predecessor_head,successor_head,actor_id,actor_email,gateway_instance_id,release_name,source_sha,manifest_sha256,canonical_contract,task_enabled,mailbox_contacted,uid514_processed,production_writes,rollback_contract)
SELECT encode(extensions.digest(convert_to('pdc-staging-766-monitor-current-head-compatibility|forward|20260830050000','UTF8'),'sha256'),'hex'),
 'forward_current_head_compatibility',c.predecessor_head,c.successor_head,c.actor_id,c.actor_email,c.gateway_instance_id,c.release_name,c.source_sha,c.manifest_sha256,c.canonical_contract,false,false,false,false,
 'Administrator-only forward successor disable path; preserves prior .44/.66 artifacts, all immutable histories, mailbox flags, UID514 receipt and canonical importer authority'
FROM public.pdc_email_monitor_current_head_compatibility_controls_766 c WHERE c.singleton AND c.enabled;

DO $post$
BEGIN
  IF (SELECT count(*) FROM public.pdc_email_monitor_current_head_compatibility_controls_766 WHERE singleton AND enabled AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed AND NOT production_writes)<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_current_head_compatibility_history_766 WHERE event_kind='forward_current_head_compatibility')<>1
     OR NOT has_function_privilege('authenticated','public.verify_pdc_monitor_runtime_binding_authenticated_766(text,text,text,text,text,text,text)','execute')
     OR NOT has_function_privilege('authenticated','public.attest_pdc_monitor_provider_email_observation_current_766(text,uuid,uuid,uuid,text,text,text,text,jsonb)','execute')
     OR has_function_privilege('anon','public.verify_pdc_monitor_runtime_binding_authenticated_766(text,text,text,text,text,text,text)','execute')
     OR has_function_privilege('service_role','public.verify_pdc_monitor_runtime_binding_authenticated_766(text,text,text,text,text,text,text)','execute')
     OR has_function_privilege('anon','public.attest_pdc_monitor_provider_email_observation_current_766(text,uuid,uuid,uuid,text,text,text,text,jsonb)','execute')
     OR has_function_privilege('service_role','public.attest_pdc_monitor_provider_email_observation_current_766(text,uuid,uuid,uuid,text,text,text,text,jsonb)','execute')
     OR (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid='public.pdc_email_monitor_current_head_compatibility_history_766'::regclass) IS DISTINCT FROM true
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  THEN RAISE EXCEPTION 'PDC_766_CURRENT_HEAD_COMPATIBILITY_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END
$post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
 '20260830050000','766_monitor_current_head_compatibility',ARRAY[
  'Guard exact live 765 predecessor and current staging-only project sentinel',
  'Bind the standard authenticated sales actor, exact gateway, sealed .44 release/source/manifest and commissioned planner/trust',
  'Expose current-head 766 runtime attestation and claim-bound authenticated provider observation custody',
  'Verify canonical claim_732, provider observation, claimed process, cycle, heartbeat, attachment, extraction and result RPC identities/hashes',
  'Preserve exact minimum UID 640, UID514 exclusion, mailbox flags, canonical source-hash/idempotency/receipt path and forced-RLS boundaries',
  'Keep pdc_email_monitor_pilot, outbound email and Scheduled Task disabled; no mailbox contact, UID514 processing or Production access'
 ]);
NOTIFY pgrst,'reload schema';
COMMIT;
