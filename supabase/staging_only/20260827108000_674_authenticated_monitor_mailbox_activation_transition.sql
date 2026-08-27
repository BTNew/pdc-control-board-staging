-- STAGING ONLY 674: guarded activation of the one pre-provisioned PMB mailbox.
-- This is an append-only successor to 670-673. It activates only the existing
-- pdc_pmb_email staging row for the exact .44 authenticated actor/binding. It
-- does not fetch mail, change flags, process UID514, mutate vehicles, send
-- email, weaken RLS/ACLs, run as UID514, or contact Production.
--
-- Runtime hash anchors accepted by this successor:
--   673 scope p.prosrc: 927f9e2f4a250aa2a49df8715308f0456a814824b29f10f81869814213af22a7
--   673 actor scope p.prosrc: 93a1a4af8e22ffb202ff250daf65e060ee16c847b1b4db338928ca20b3d2d86d
--   673 runtime helper p.prosrc: cb0d2d29f827b7677cf735eec9587a9bc88383a428c8433e95d428166f8d0143
--   673 source helper p.prosrc: 55161035e5ec36c10d2df3b84ec85f937d9287c55163f87d7f4d2335d24b3f79
--   sealed .44 runner: 52affc8ea7374f6067be51f56cb633deb520b0628801b427e5215c873ec26ebd
--   external adapter: 08e9a0dbca7640b93911fe397e3f9577b7f1e79bebc97c780efbe6aeb4a298e0

BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-674-authenticated-monitor-mailbox-activation',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE
  v_scope_hash text;
  v_actor_scope_hash text;
  v_runtime_hash text;
  v_source_hash text;
BEGIN
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_scope_hash
    FROM pg_proc p WHERE p.oid='public.pdc_monitor_authenticated_active_scope_673(text)'::regprocedure;
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_actor_scope_hash
    FROM pg_proc p WHERE p.oid='public.pdc_monitor_actor_scope()'::regprocedure;
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_runtime_hash
    FROM pg_proc p WHERE p.oid='public.pdc_email_monitor_runtime_authorized_502(text)'::regprocedure;
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_source_hash
    FROM pg_proc p WHERE p.oid='public.pdc_agentic_email_source_authorized_502(jsonb)'::regprocedure;

  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827106000' AND name='673_authenticated_monitor_execution_attachment_successor')<>1
     OR to_regclass('public.pdc_email_monitor_authenticated_mailbox_activation_controls_674') IS NOT NULL
     OR to_regclass('public.pdc_email_monitor_authenticated_mailbox_activation_history_674') IS NOT NULL
     OR to_regprocedure('public.pdc_monitor_authenticated_active_scope_674(text)') IS NOT NULL
     OR to_regprocedure('public.admin_rollback_pdc_email_monitor_authenticated_mailbox_activation_674(text)') IS NOT NULL
     OR v_scope_hash<>'927f9e2f4a250aa2a49df8715308f0456a814824b29f10f81869814213af22a7'
     OR v_actor_scope_hash<>'93a1a4af8e22ffb202ff250daf65e060ee16c847b1b4db338928ca20b3d2d86d'
     OR v_runtime_hash<>'cb0d2d29f827b7677cf735eec9587a9bc88383a428c8433e95d428166f8d0143'
     OR v_source_hash<>'55161035e5ec36c10d2df3b84ec85f937d9287c55163f87d7f4d2335d24b3f79'
     OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_execution_attachment_controls_673 WHERE singleton AND enabled AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND actor_email='sales@broometoyota.com.au' AND jwt_role='authenticated' AND server_application_role='importer' AND gateway_instance_id='pdc-monitor-staging-sales-uid509-v1' AND release_name='pdc-monitor-staging-m502-2026.08.44' AND source_sha='e850c319989d98b45b95a28aa815d78e2c2e3a4b' AND manifest_sha256='d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d' AND planner_sha256='7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348' AND trust_receipt_sha256='e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227' AND observed_mime_part_count=7 AND retained_authenticated_attachment_count=4 AND all_mime_parts_retained AND NOT production_writes AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed)<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_execution_attachment_history_673 WHERE event_kind='forward_authenticated_execution_attachment')<>1
     OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>0
     OR (SELECT count(*) FROM public.monitored_mailboxes WHERE id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57' AND mailbox_key='pdc_pmb_email' AND lower(mailbox_address)='pmbcontroller@gmail.com' AND lower(provider)='gmail' AND NOT active AND test_mode AND config->>'owner_profile'='pdc-monitor' AND config->>'contains_credentials'='false' AND config->>'operational_scope'='staging')<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND (enabled OR automatic_rule_application OR automatic_authenticated_jobcards OR outbound_email_enabled))<>0
     OR (SELECT count(*) FROM public.ai_email_intake WHERE provider_uid='imap_uid:514')<>0
  THEN RAISE EXCEPTION 'PDC_674_EXACT_673_PREDECESSOR_FUNCTION_OR_MAILBOX_PRESTATE_MISMATCH' USING errcode='55000'; END IF;
END
$guard$;

CREATE TABLE public.pdc_email_monitor_authenticated_mailbox_activation_controls_674(
  singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
  enabled boolean NOT NULL DEFAULT true CHECK(enabled),
  actor_id uuid NOT NULL CHECK(actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'),
  actor_email text NOT NULL CHECK(actor_email='sales@broometoyota.com.au'),
  jwt_role text NOT NULL CHECK(jwt_role='authenticated'),
  server_application_role text NOT NULL CHECK(server_application_role='importer'),
  gateway_instance_id text NOT NULL CHECK(gateway_instance_id='pdc-monitor-staging-sales-uid509-v1'),
  release_name text NOT NULL CHECK(release_name='pdc-monitor-staging-m502-2026.08.44'),
  source_sha text NOT NULL CHECK(source_sha='e850c319989d98b45b95a28aa815d78e2c2e3a4b'),
  manifest_sha256 text NOT NULL CHECK(manifest_sha256='d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d'),
  planner_sha256 text NOT NULL CHECK(planner_sha256='7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348'),
  trust_receipt_sha256 text NOT NULL CHECK(trust_receipt_sha256='e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227'),
  mailbox_id uuid NOT NULL CHECK(mailbox_id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57'),
  mailbox_key text NOT NULL CHECK(mailbox_key='pdc_pmb_email'),
  mailbox_address text NOT NULL CHECK(mailbox_address='pmbcontroller@gmail.com'),
  provider text NOT NULL CHECK(provider='gmail'),
  test_mode boolean NOT NULL CHECK(test_mode),
  production_writes boolean NOT NULL DEFAULT false CHECK(NOT production_writes),
  task_enabled boolean NOT NULL DEFAULT false CHECK(NOT task_enabled),
  mailbox_contacted boolean NOT NULL DEFAULT false CHECK(NOT mailbox_contacted),
  uid514_processed boolean NOT NULL DEFAULT false CHECK(NOT uid514_processed),
  changed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_email_monitor_authenticated_mailbox_activation_controls_674 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_monitor_authenticated_mailbox_activation_controls_674 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_email_monitor_authenticated_mailbox_activation_controls_674 FROM public,anon,authenticated,service_role,pdc_email_monitor;

INSERT INTO public.pdc_email_monitor_authenticated_mailbox_activation_controls_674(
  actor_id,actor_email,jwt_role,server_application_role,gateway_instance_id,release_name,source_sha,manifest_sha256,
  planner_sha256,trust_receipt_sha256,mailbox_id,mailbox_key,mailbox_address,provider,test_mode)
VALUES(
  'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b','sales@broometoyota.com.au','authenticated','importer',
  'pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44',
  'e850c319989d98b45b95a28aa815d78e2c2e3a4b','d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d',
  '7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348','e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227',
  '12fe383d-5c1e-5801-96e4-f67cf3e3bb57','pdc_pmb_email','pmbcontroller@gmail.com','gmail',true);

CREATE TABLE public.pdc_email_monitor_authenticated_mailbox_activation_history_674(
  history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key text NOT NULL UNIQUE,
  event_kind text NOT NULL CHECK(event_kind IN('forward_mailbox_activation','rollback')),
  predecessor_head text NOT NULL CHECK(predecessor_head='20260827106000'),
  successor_head text NOT NULL CHECK(successor_head='20260827108000'),
  actor_id uuid NOT NULL CHECK(actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'),
  actor_email text NOT NULL CHECK(actor_email='sales@broometoyota.com.au'),
  jwt_role text NOT NULL CHECK(jwt_role='authenticated'),
  server_application_role text NOT NULL CHECK(server_application_role='importer'),
  gateway_instance_id text NOT NULL,
  release_name text NOT NULL,
  source_sha text NOT NULL,
  manifest_sha256 text NOT NULL,
  planner_sha256 text NOT NULL,
  trust_receipt_sha256 text NOT NULL,
  mailbox_id uuid NOT NULL CHECK(mailbox_id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57'),
  mailbox_key text NOT NULL CHECK(mailbox_key='pdc_pmb_email'),
  mailbox_address text NOT NULL CHECK(mailbox_address='pmbcontroller@gmail.com'),
  before_state jsonb NOT NULL,
  after_state jsonb NOT NULL,
  production_writes boolean NOT NULL CHECK(NOT production_writes),
  task_enabled boolean NOT NULL CHECK(NOT task_enabled),
  mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),
  uid514_processed boolean NOT NULL CHECK(NOT uid514_processed),
  performed_by uuid,
  performed_by_email text,
  rollback_contract text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE FUNCTION public.pdc_email_monitor_authenticated_mailbox_activation_history_immutable_674()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public
AS $immutable$ BEGIN RAISE EXCEPTION 'PDC_674_AUTHENTICATED_MAILBOX_HISTORY_IMMUTABLE' USING errcode='55000'; END $immutable$;
CREATE TRIGGER pdc_email_monitor_authenticated_mailbox_activation_history_immutable_674
BEFORE UPDATE OR DELETE ON public.pdc_email_monitor_authenticated_mailbox_activation_history_674
FOR EACH ROW EXECUTE FUNCTION public.pdc_email_monitor_authenticated_mailbox_activation_history_immutable_674();
ALTER TABLE public.pdc_email_monitor_authenticated_mailbox_activation_history_674 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_monitor_authenticated_mailbox_activation_history_674 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_email_monitor_authenticated_mailbox_activation_history_674 FROM public,anon,authenticated,service_role,pdc_email_monitor;

DO $activate$
DECLARE
  v_before jsonb;
  v_after jsonb;
  v_mailbox public.monitored_mailboxes%rowtype;
  v_event_key text;
BEGIN
  SELECT * INTO v_mailbox FROM public.monitored_mailboxes
   WHERE id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57' AND mailbox_key='pdc_pmb_email'
     AND lower(mailbox_address)='pmbcontroller@gmail.com' AND lower(provider)='gmail'
     AND NOT active AND test_mode
   FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_674_EXACT_MAILBOX_ACTIVATION_PRESTATE_MISMATCH' USING errcode='55000'; END IF;
  v_before:=to_jsonb(v_mailbox);
  UPDATE public.monitored_mailboxes
     SET active=true,test_mode=true,
         config=jsonb_build_object('owner_profile','pdc-monitor','contains_credentials',false,'operational_scope','staging'),
         updated_at=clock_timestamp()
   WHERE id=v_mailbox.id AND mailbox_key='pdc_pmb_email' AND NOT active
   RETURNING * INTO v_mailbox;
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_674_EXACT_MAILBOX_ACTIVATION_CONCURRENT_DRIFT' USING errcode='40001'; END IF;
  v_after:=to_jsonb(v_mailbox);
  v_event_key:=encode(extensions.digest(convert_to('pdc-staging-674-authenticated-monitor-mailbox-activation|forward|'||v_mailbox.id::text,'UTF8'),'sha256'),'hex');
  INSERT INTO public.pdc_email_monitor_authenticated_mailbox_activation_history_674(
    event_key,event_kind,predecessor_head,successor_head,actor_id,actor_email,jwt_role,server_application_role,
    gateway_instance_id,release_name,source_sha,manifest_sha256,planner_sha256,trust_receipt_sha256,
    mailbox_id,mailbox_key,mailbox_address,before_state,after_state,production_writes,task_enabled,mailbox_contacted,uid514_processed,rollback_contract)
  VALUES(v_event_key,'forward_mailbox_activation','20260827106000','20260827108000',
    'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b','sales@broometoyota.com.au','authenticated','importer',
    'pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44',
    'e850c319989d98b45b95a28aa815d78e2c2e3a4b','d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d',
    '7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348','e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227',
    v_mailbox.id,'pdc_pmb_email','pmbcontroller@gmail.com',v_before,v_after,false,false,false,false,
    'Exact existing staging mailbox activation only; rollback disables this row and preserves all evidence/history without task, mailbox-fetch, UID514, vehicle or Production action');
  INSERT INTO public.audit_events(action,table_name,row_id,actor_id,actor_email,before_data,after_data,metadata)
  VALUES('update','monitored_mailboxes',v_mailbox.id,NULL,'staging-management-remediation',v_before,v_after,
    jsonb_build_object('event_type','pdc_email_monitor_authenticated_mailbox_activated_674','authorized_by','Craig Watson','actor_id','df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b','gateway_instance_id','pdc-monitor-staging-sales-uid509-v1','release_name','pdc-monitor-staging-m502-2026.08.44','exact_mailbox_only',true,'production_untouched',true,'task_enabled',false,'mailbox_contacted',false,'uid514_processed',false));
END
$activate$;

CREATE FUNCTION public.pdc_monitor_authenticated_active_scope_674(p_gateway_instance_id text DEFAULT NULL)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,auth
AS $scope$
SELECT public.pdc_monitor_staging_guard()
 AND lower(coalesce(current_setting('app.environment',true),''))<>'production'
 AND to_regclass('public.pdc_production_environment_sentinel') IS NULL
 AND auth.uid()='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid
 AND lower(btrim(coalesce(auth.jwt()->>'email','')))='sales@broometoyota.com.au'
 AND coalesce(auth.jwt()->>'role','')='authenticated'
 AND (p_gateway_instance_id IS NULL OR btrim(p_gateway_instance_id)='pdc-monitor-staging-sales-uid509-v1')
 AND EXISTS(SELECT 1 FROM auth.users u WHERE u.id=auth.uid() AND lower(coalesce(u.email,''))='sales@broometoyota.com.au' AND coalesce(u.raw_app_meta_data->>'pdc_identity_type','')='non_human_monitor')
 AND (SELECT count(*) FROM public.pdc_user_roles r WHERE r.auth_user_id=auth.uid() AND lower(r.email)='sales@broometoyota.com.au' AND r.active AND r.account_status='approved' AND r.role::text='importer')=1
 AND (SELECT count(*) FROM public.pdc_user_roles r WHERE r.auth_user_id=auth.uid() AND r.active)=1
 AND (SELECT count(*) FROM public.pdc_monitor_stage_activation_writers w WHERE w.user_id=auth.uid() AND w.active AND w.revoked_at IS NULL)=1
 AND (SELECT count(*) FROM public.pdc_monitor_stage_activation_writers w WHERE w.active AND w.revoked_at IS NULL)=1
 AND NOT EXISTS(SELECT 1 FROM public.pdc_auditor_worker_identities w WHERE w.auth_user_id=auth.uid() AND w.active)
 AND NOT EXISTS(SELECT 1 FROM public.pdc_auditor_user_dealer_scopes s WHERE s.auth_user_id=auth.uid() AND s.active)
 AND NOT EXISTS(SELECT 1 FROM public.pdc_auditor_executor_identities e WHERE e.auth_user_id=auth.uid() AND e.active AND e.expires_at>clock_timestamp())
 AND NOT EXISTS(SELECT 1 FROM public.pdc_auditor_service_identities_225 s WHERE s.auth_user_id=auth.uid() AND s.active)
 AND (SELECT count(*) FROM public.monitored_mailboxes WHERE active)=1
 AND EXISTS(SELECT 1 FROM public.monitored_mailboxes m WHERE m.id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57' AND m.mailbox_key='pdc_pmb_email' AND lower(m.mailbox_address)='pmbcontroller@gmail.com' AND lower(m.provider)='gmail' AND m.active AND m.test_mode AND m.config->>'owner_profile'='pdc-monitor' AND m.config->>'contains_credentials'='false' AND m.config->>'operational_scope'='staging')
 AND (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND (enabled OR automatic_rule_application OR automatic_authenticated_jobcards OR outbound_email_enabled))=0
 AND EXISTS(SELECT 1 FROM public.pdc_email_monitor_authenticated_active_capability_controls_672 c WHERE c.singleton AND c.enabled AND c.actor_id=auth.uid() AND c.jwt_role='authenticated' AND c.server_application_role='importer' AND c.gateway_instance_id='pdc-monitor-staging-sales-uid509-v1' AND c.release_name='pdc-monitor-staging-m502-2026.08.44' AND c.source_sha='e850c319989d98b45b95a28aa815d78e2c2e3a4b' AND c.manifest_sha256='d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d' AND c.planner_sha256='7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348' AND c.trust_receipt_sha256='e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227' AND NOT c.production_writes AND NOT c.task_enabled AND NOT c.mailbox_contacted AND NOT c.uid514_processed)
 AND EXISTS(SELECT 1 FROM public.pdc_email_monitor_authenticated_execution_attachment_controls_673 c WHERE c.singleton AND c.enabled AND c.actor_id=auth.uid() AND c.actor_email='sales@broometoyota.com.au' AND c.jwt_role='authenticated' AND c.server_application_role='importer' AND c.gateway_instance_id='pdc-monitor-staging-sales-uid509-v1' AND c.release_name='pdc-monitor-staging-m502-2026.08.44' AND c.source_sha='e850c319989d98b45b95a28aa815d78e2c2e3a4b' AND c.manifest_sha256='d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d' AND c.planner_sha256='7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348' AND c.trust_receipt_sha256='e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227' AND c.observed_mime_part_count=7 AND c.retained_authenticated_attachment_count=4 AND c.all_mime_parts_retained AND NOT c.production_writes AND NOT c.task_enabled AND NOT c.mailbox_contacted AND NOT c.uid514_processed)
 AND EXISTS(SELECT 1 FROM public.pdc_email_monitor_authenticated_mailbox_activation_controls_674 c WHERE c.singleton AND c.enabled AND c.actor_id=auth.uid() AND c.actor_email='sales@broometoyota.com.au' AND c.jwt_role='authenticated' AND c.server_application_role='importer' AND c.gateway_instance_id='pdc-monitor-staging-sales-uid509-v1' AND c.release_name='pdc-monitor-staging-m502-2026.08.44' AND c.source_sha='e850c319989d98b45b95a28aa815d78e2c2e3a4b' AND c.manifest_sha256='d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d' AND c.planner_sha256='7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348' AND c.trust_receipt_sha256='e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227' AND c.mailbox_id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57' AND c.mailbox_key='pdc_pmb_email' AND c.mailbox_address='pmbcontroller@gmail.com' AND c.provider='gmail' AND c.test_mode AND NOT c.production_writes AND NOT c.task_enabled AND NOT c.mailbox_contacted AND NOT c.uid514_processed)
 AND EXISTS(SELECT 1 FROM public.pdc_monitor_runtime_bindings_255 b WHERE b.singleton AND b.actor_id=auth.uid() AND b.gateway_instance_id='pdc-monitor-staging-sales-uid509-v1' AND b.release_name='pdc-monitor-staging-m502-2026.08.44' AND b.source_sha='e850c319989d98b45b95a28aa815d78e2c2e3a4b' AND b.manifest_sha256='d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d' AND b.semantic_planner_sha256='7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348' AND b.semantic_planner_trust_receipt_sha256='e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227' AND b.semantic_planner_commissioned_at IS NOT NULL)
$scope$;
REVOKE ALL ON FUNCTION public.pdc_monitor_authenticated_active_scope_674(text) FROM public,anon,authenticated,service_role,pdc_email_monitor;

-- Preserve the contained Viewer branch and route only the exact standard
-- authenticated actor through the active importer branch.
CREATE OR REPLACE FUNCTION public.pdc_monitor_actor_scope()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,auth AS $body$
DECLARE
  v_uid uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_count integer;
BEGIN
  IF public.pdc_monitor_authenticated_active_scope_674(NULL) THEN
    RETURN jsonb_build_object('user_id',v_uid,'email',v_email,'role','importer');
  END IF;
  SELECT count(*) INTO v_count
  FROM public.pdc_monitor_runtime_bindings_255 b
  JOIN public.pdc_monitor_stage_activation_writers w ON w.user_id=b.actor_id AND w.active AND w.revoked_at IS NULL
  JOIN public.pdc_user_roles r ON r.auth_user_id=b.actor_id AND lower(r.email)=v_email AND r.active AND r.account_status='approved' AND r.role::text='viewer'
  JOIN auth.users u ON u.id=b.actor_id AND lower(coalesce(u.email,''))=v_email AND coalesce(u.raw_app_meta_data->>'pdc_identity_type','')='non_human_monitor'
  WHERE b.singleton AND b.actor_id=v_uid;
  IF v_uid IS NULL OR v_email='' OR v_count<>1
     OR EXISTS(SELECT 1 FROM public.pdc_auditor_worker_identities w WHERE w.auth_user_id=v_uid AND w.active)
     OR EXISTS(SELECT 1 FROM public.pdc_auditor_user_dealer_scopes s WHERE s.auth_user_id=v_uid AND s.active)
     OR EXISTS(SELECT 1 FROM public.pdc_auditor_executor_identities e WHERE e.auth_user_id=v_uid AND e.active AND e.expires_at>clock_timestamp())
     OR EXISTS(SELECT 1 FROM public.pdc_auditor_service_identities_225 s WHERE s.auth_user_id=v_uid AND s.active)
  THEN RAISE EXCEPTION 'PDC_255_MONITOR_DEDICATED_IDENTITY_REQUIRED' USING errcode='42501'; END IF;
  RETURN jsonb_build_object('user_id',v_uid,'email',v_email,'role','viewer');
END
$body$;
REVOKE ALL ON FUNCTION public.pdc_monitor_actor_scope() FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.pdc_email_monitor_runtime_authorized_502(p_gateway_instance_id text DEFAULT NULL)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,auth
AS $authorized$ SELECT public.pdc_monitor_authenticated_active_scope_674(p_gateway_instance_id) $authorized$;
REVOKE ALL ON FUNCTION public.pdc_email_monitor_runtime_authorized_502(text) FROM public,anon,authenticated,service_role,pdc_email_monitor;

-- Fresh authenticated proof/readback RPCs bind the now-active mailbox state
-- without rewriting 672's zero-mailbox commissioning contract.
CREATE FUNCTION public.verify_pdc_monitor_runtime_binding_authenticated_674(
  p_mode text,p_gateway_instance_id text,p_release_name text,p_source_sha text,p_manifest_sha256 text,
  p_semantic_planner_sha256 text DEFAULT NULL,p_semantic_planner_trust_receipt_sha256 text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,auth
AS $verify$
DECLARE
  v_binding public.pdc_monitor_runtime_bindings_255%rowtype;
BEGIN
  IF NOT public.pdc_monitor_authenticated_active_scope_674(p_gateway_instance_id) THEN
    RAISE EXCEPTION 'PDC_674_AUTHENTICATED_ACTIVE_IDENTITY_REQUIRED' USING errcode='42501';
  END IF;
  IF lower(btrim(coalesce(p_mode,'')))<>'active'
     OR btrim(coalesce(p_gateway_instance_id,''))<>'pdc-monitor-staging-sales-uid509-v1'
     OR btrim(coalesce(p_release_name,''))<>'pdc-monitor-staging-m502-2026.08.44'
     OR lower(btrim(coalesce(p_source_sha,'')))<>'e850c319989d98b45b95a28aa815d78e2c2e3a4b'
     OR lower(btrim(coalesce(p_manifest_sha256,'')))<>'d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d'
     OR lower(btrim(coalesce(p_semantic_planner_sha256,'')))<>'7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348'
     OR lower(btrim(coalesce(p_semantic_planner_trust_receipt_sha256,'')))<>'e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227' THEN
    RETURN jsonb_build_object('ok',false,'code','runtime_binding_mismatch','activation_ready',false,'production_writes',false);
  END IF;
  SELECT * INTO v_binding FROM public.pdc_monitor_runtime_bindings_255 WHERE singleton AND actor_id=auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_674_AUTHENTICATED_ACTIVE_RUNTIME_BINDING_PROOF_REQUIRED' USING errcode='42501'; END IF;
  RETURN jsonb_build_object('ok',true,'code','runtime_binding_verified_authenticated_674','mode','active','operational',true,'activation_ready',true,
    'actor_id',auth.uid(),'actor_email','sales@broometoyota.com.au','jwt_role','authenticated','server_application_role','importer',
    'gateway_instance_id',v_binding.gateway_instance_id,'release_name',v_binding.release_name,'source_sha',v_binding.source_sha,'manifest_sha256',v_binding.manifest_sha256,
    'semantic_planner_sha256',v_binding.semantic_planner_sha256,'semantic_planner_trust_receipt_sha256',v_binding.semantic_planner_trust_receipt_sha256,
    'planner_commissioned',true,'writer_active',true,'mailbox_id','12fe383d-5c1e-5801-96e4-f67cf3e3bb57','mailbox_active',true,
    'active_mailbox_count',1,'production_writes',false,'task_enabled',false,'mailbox_contacted',false,'uid514_processed',false,
    'migration_head',503,'compatibility_successor_head',674);
END
$verify$;
REVOKE ALL ON FUNCTION public.verify_pdc_monitor_runtime_binding_authenticated_674(text,text,text,text,text,text,text) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.verify_pdc_monitor_runtime_binding_authenticated_674(text,text,text,text,text,text,text) TO authenticated;

CREATE FUNCTION public.read_pdc_uid514_transaction_receipt_authenticated_674(p_recovery_event_id integer)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,auth
AS $reader$
DECLARE
  v_intake public.pdc_uid514_recovery_authorizations_257%rowtype;
  v_receipt public.pdc_jobcard_attachment_import_receipts%rowtype;
  v_terminal public.pdc_uid514_staging_commissioning_terminal_receipts_507%rowtype;
  v_code text; v_kind text; v_source text;
BEGIN
  IF NOT public.pdc_monitor_authenticated_active_scope_674(NULL) THEN RAISE EXCEPTION 'PDC_674_AUTHENTICATED_ACTIVE_IDENTITY_REQUIRED' USING errcode='42501'; END IF;
  IF p_recovery_event_id<>25751401 THEN RAISE EXCEPTION 'PDC_674_UID514_SCOPE_INVALID' USING errcode='22023'; END IF;
  IF (SELECT enabled FROM public.pdc_monitor_uid514_reader_compatibility_controls_506 WHERE singleton) IS DISTINCT FROM true THEN RAISE EXCEPTION 'PDC_506_READER_COMPATIBILITY_DISABLED'; END IF;
  SELECT r.* INTO v_terminal FROM public.pdc_uid514_staging_commissioning_terminal_receipts_507 r
   JOIN public.pdc_uid514_staging_commissioning_controls_507 c ON c.singleton AND c.enabled
   WHERE r.recovery_event_id=25751401 AND r.actor_id=auth.uid() AND r.gateway_instance_id='pdc-monitor-staging-sales-uid509-v1'
     AND r.release_name='pdc-monitor-staging-m502-2026.08.44' AND r.source_sha='e850c319989d98b45b95a28aa815d78e2c2e3a4b'
     AND r.manifest_sha256='d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d'
     AND r.synthetic_staging_commissioning AND NOT r.physical_mailbox_fetch AND NOT r.mailbox_flags_changed
     AND r.vehicle_operations=0 AND r.operation_lines=0 AND NOT r.operational AND NOT r.activation_ready AND NOT r.writer_active AND NOT r.planner_commissioned AND NOT r.production_writes;
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_674_UID514_TERMINAL_RECEIPT_MISSING' USING errcode='55000'; END IF;
  SELECT * INTO v_intake FROM public.pdc_uid514_recovery_authorizations_257 WHERE recovery_event_id=25751401;
  IF FOUND THEN
    SELECT * INTO v_receipt FROM public.pdc_jobcard_attachment_import_receipts WHERE actor_id=auth.uid() AND intake_id=v_intake.intake_id AND parent_source_hash=v_intake.parent_source_hash AND attachment_source_hash=v_intake.qualifying_attachment_sha256;
    IF FOUND THEN RETURN jsonb_build_object('ok',true,'code','uid514_receipt_terminal','terminal',true,'recovery_event_id',25751401,'mailbox','pmbcontroller@gmail.com','folder','Inbox','uidvalidity',1,'uid',514,'canonical_receipt_id',v_receipt.receipt_id,'vehicle_id',v_receipt.vehicle_id,'vehicle_version',v_receipt.vehicle_version,'synthetic_staging_commissioning',false,'physical_mailbox_fetch',true,'mailbox_flags_changed',false,'vehicle_operations',v_receipt.operation_count,'operation_lines',v_receipt.operation_count,'operational',true,'activation_ready',true,'writer_active',true,'planner_commissioned',true,'production_writes',false,'observed_mime_part_count',7,'retained_authenticated_attachment_count',4,'qualifying_attachment_sha256',v_intake.qualifying_attachment_sha256,'all_mime_parts_retained',true); END IF;
    RETURN jsonb_build_object('ok',true,'code','uid514_receipt_pending','terminal',false,'recovery_event_id',25751401,'mailbox','pmbcontroller@gmail.com','folder','Inbox','uidvalidity',1,'uid',514,'observed_mime_part_count',7,'retained_authenticated_attachment_count',4,'qualifying_attachment_sha256',v_intake.qualifying_attachment_sha256,'all_mime_parts_retained',true);
  END IF;
  SELECT response_code,receipt_kind,receipt_source INTO v_code,v_kind,v_source FROM public.pdc_uid514_receipt_code_compatibility_controls_508 c WHERE c.singleton AND c.enabled AND c.receipt_id=v_terminal.receipt_id AND c.recovery_event_id=25751401 AND c.response_code='uid514_receipt_terminal' AND c.receipt_kind='staging_commissioning' AND c.receipt_source='logical_507_exact_terminal_receipt' AND NOT c.operational AND NOT c.activation_ready AND NOT c.writer_active AND NOT c.planner_commissioned AND NOT c.production_writes;
  RETURN jsonb_build_object('ok',true,'code',coalesce(v_code,'uid514_receipt_terminal'),'terminal',true,'recovery_event_id',25751401,'mailbox','pmbcontroller@gmail.com','folder','Inbox','uidvalidity',1,'uid',514,'canonical_receipt_id',v_terminal.receipt_id,'vehicle_id',null,'vehicle_version',null,'synthetic_staging_commissioning',true,'receipt_kind',coalesce(v_kind,'staging_commissioning'),'receipt_source',coalesce(v_source,'logical_507_exact_terminal_receipt'),'physical_mailbox_fetch',false,'mailbox_flags_changed',false,'vehicle_operations',0,'operation_lines',0,'operational',false,'activation_ready',true,'writer_active',true,'planner_commissioned',true,'production_writes',false,'observed_mime_part_count',7,'retained_authenticated_attachment_count',4,'qualifying_attachment_sha256','9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4','all_mime_parts_retained',true);
END
$reader$;
REVOKE ALL ON FUNCTION public.read_pdc_uid514_transaction_receipt_authenticated_674(integer) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.read_pdc_uid514_transaction_receipt_authenticated_674(integer) TO authenticated;

CREATE FUNCTION public.admin_rollback_pdc_email_monitor_authenticated_mailbox_activation_674(p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,auth AS $rollback$
DECLARE
  v_admin uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_count integer;
  v_control public.pdc_email_monitor_authenticated_mailbox_activation_controls_674%rowtype;
  v_existing public.pdc_email_monitor_authenticated_mailbox_activation_history_674%rowtype;
  v_mailbox public.monitored_mailboxes%rowtype;
  v_before jsonb;
  v_after jsonb;
  v_event_key text;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR v_admin IS NULL OR coalesce(auth.jwt()->>'role','')<>'authenticated' OR length(btrim(coalesce(p_reason,'')))<10 THEN RAISE EXCEPTION 'PDC_674_ADMIN_AUTHORITY_REQUIRED' USING errcode='42501'; END IF;
  SELECT count(*) INTO v_count FROM public.pdc_user_roles r JOIN auth.users u ON u.id=r.auth_user_id AND lower(u.email)=v_email WHERE r.auth_user_id=v_admin AND lower(r.email)=v_email AND r.active AND r.account_status='approved' AND r.role::text='administrator';
  IF v_count<>1 THEN RAISE EXCEPTION 'PDC_674_ADMIN_AUTHORITY_REQUIRED' USING errcode='42501'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-staging-674-authenticated-monitor-mailbox-activation',0));
  SELECT * INTO v_control FROM public.pdc_email_monitor_authenticated_mailbox_activation_controls_674 WHERE singleton FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_674_CONTROL_MISSING' USING errcode='55000'; END IF;
  v_event_key:=encode(extensions.digest(convert_to('pdc-staging-674-authenticated-monitor-mailbox-activation|rollback|'||v_control.mailbox_id::text,'UTF8'),'sha256'),'hex');
  SELECT * INTO v_existing FROM public.pdc_email_monitor_authenticated_mailbox_activation_history_674 WHERE event_key=v_event_key;
  IF FOUND THEN
    IF v_control.enabled THEN RAISE EXCEPTION 'PDC_674_ROLLBACK_STATE_DRIFT' USING errcode='55000'; END IF;
    RETURN jsonb_build_object('ok',true,'code','pdc_email_monitor_authenticated_mailbox_activation_rolled_back_674','idempotent',true,'history_id',v_existing.history_id,'mailbox_active',false,'production_writes',false,'task_enabled',false,'mailbox_contacted',false,'uid514_processed',false);
  END IF;
  IF NOT v_control.enabled OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>1 THEN RAISE EXCEPTION 'PDC_674_ROLLBACK_SCOPE_MISMATCH' USING errcode='55000'; END IF;
  SELECT * INTO v_mailbox FROM public.monitored_mailboxes WHERE id=v_control.mailbox_id AND mailbox_key=v_control.mailbox_key AND lower(mailbox_address)=v_control.mailbox_address AND lower(provider)=v_control.provider AND active AND test_mode FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_674_ROLLBACK_MAILBOX_SCOPE_MISMATCH' USING errcode='55000'; END IF;
  v_before:=to_jsonb(v_mailbox);
  UPDATE public.monitored_mailboxes SET active=false,updated_at=clock_timestamp() WHERE id=v_mailbox.id AND active RETURNING * INTO v_mailbox;
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_674_ROLLBACK_CONCURRENT_DRIFT' USING errcode='40001'; END IF;
  v_after:=to_jsonb(v_mailbox);
  UPDATE public.pdc_email_monitor_authenticated_mailbox_activation_controls_674 SET enabled=false,changed_at=clock_timestamp() WHERE singleton;
  INSERT INTO public.pdc_email_monitor_authenticated_mailbox_activation_history_674(
    event_key,event_kind,predecessor_head,successor_head,actor_id,actor_email,jwt_role,server_application_role,
    gateway_instance_id,release_name,source_sha,manifest_sha256,planner_sha256,trust_receipt_sha256,
    mailbox_id,mailbox_key,mailbox_address,before_state,after_state,production_writes,task_enabled,mailbox_contacted,uid514_processed,performed_by,performed_by_email,rollback_contract)
  VALUES(v_event_key,'rollback','20260827106000','20260827108000',v_control.actor_id,v_control.actor_email,'authenticated','importer',v_control.gateway_instance_id,v_control.release_name,v_control.source_sha,v_control.manifest_sha256,v_control.planner_sha256,v_control.trust_receipt_sha256,v_control.mailbox_id,v_control.mailbox_key,v_control.mailbox_address,v_before,v_after,false,false,false,false,v_admin,v_email,'Guarded Administrator rollback disables only the exact pre-provisioned mailbox, preserves all rows/history/evidence and leaves task, UID514, vehicles, email and Production untouched');
  INSERT INTO public.audit_events(action,table_name,row_id,actor_id,actor_email,before_data,after_data,metadata)
  VALUES('update','pdc_email_monitor_authenticated_mailbox_activation_controls_674',v_control.mailbox_id,v_admin,v_email,v_before,v_after,jsonb_build_object('event_type','pdc_email_monitor_authenticated_mailbox_activation_rolled_back_674','reason',btrim(p_reason),'exact_mailbox_only',true,'production_untouched',true,'task_enabled',false,'mailbox_contacted',false,'uid514_processed',false));
  RETURN jsonb_build_object('ok',true,'code','pdc_email_monitor_authenticated_mailbox_activation_rolled_back_674','idempotent',false,'mailbox_active',false,'production_writes',false,'task_enabled',false,'mailbox_contacted',false,'uid514_processed',false,'rollback_available',true);
END
$rollback$;
REVOKE ALL ON FUNCTION public.admin_rollback_pdc_email_monitor_authenticated_mailbox_activation_674(text) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.admin_rollback_pdc_email_monitor_authenticated_mailbox_activation_674(text) TO authenticated;

DO $post$
BEGIN
  IF (SELECT count(*) FROM public.pdc_email_monitor_authenticated_mailbox_activation_controls_674 WHERE singleton AND enabled AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND actor_email='sales@broometoyota.com.au' AND jwt_role='authenticated' AND server_application_role='importer' AND mailbox_id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57' AND mailbox_key='pdc_pmb_email' AND mailbox_address='pmbcontroller@gmail.com' AND provider='gmail' AND test_mode AND NOT production_writes AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed)<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_mailbox_activation_history_674 WHERE event_kind='forward_mailbox_activation')<>1
     OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>1
     OR (SELECT count(*) FROM public.monitored_mailboxes WHERE id='12fe383d-5c1e-5801-96e4-f67cf3e3bb57' AND mailbox_key='pdc_pmb_email' AND lower(mailbox_address)='pmbcontroller@gmail.com' AND lower(provider)='gmail' AND active AND test_mode)<>1
     OR NOT has_function_privilege('authenticated','public.admin_rollback_pdc_email_monitor_authenticated_mailbox_activation_674(text)','execute')
     OR NOT has_function_privilege('authenticated','public.verify_pdc_monitor_runtime_binding_authenticated_674(text,text,text,text,text,text,text)','execute')
     OR NOT has_function_privilege('authenticated','public.read_pdc_uid514_transaction_receipt_authenticated_674(integer)','execute')
     OR has_function_privilege('anon','public.admin_rollback_pdc_email_monitor_authenticated_mailbox_activation_674(text)','execute')
     OR has_function_privilege('anon','public.verify_pdc_monitor_runtime_binding_authenticated_674(text,text,text,text,text,text,text)','execute')
     OR has_function_privilege('anon','public.read_pdc_uid514_transaction_receipt_authenticated_674(integer)','execute')
     OR has_function_privilege('service_role','public.admin_rollback_pdc_email_monitor_authenticated_mailbox_activation_674(text)','execute')
     OR has_function_privilege('service_role','public.verify_pdc_monitor_runtime_binding_authenticated_674(text,text,text,text,text,text,text)','execute')
     OR has_function_privilege('service_role','public.read_pdc_uid514_transaction_receipt_authenticated_674(integer)','execute')
     OR has_function_privilege('pdc_email_monitor','public.verify_pdc_monitor_runtime_binding_authenticated_674(text,text,text,text,text,text,text)','execute')
     OR has_function_privilege('pdc_email_monitor','public.read_pdc_uid514_transaction_receipt_authenticated_674(integer)','execute')
     OR has_table_privilege('authenticated','public.pdc_email_monitor_authenticated_mailbox_activation_controls_674','select')
     OR has_table_privilege('authenticated','public.pdc_email_monitor_authenticated_mailbox_activation_history_674','select')
     OR (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid='public.pdc_email_monitor_authenticated_mailbox_activation_history_674'::regclass) IS DISTINCT FROM true
     OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND (enabled OR automatic_rule_application OR automatic_authenticated_jobcards OR outbound_email_enabled))<>0
     OR (SELECT count(*) FROM public.ai_email_intake WHERE provider_uid='imap_uid:514')<>0
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  THEN RAISE EXCEPTION 'PDC_674_AUTHENTICATED_MAILBOX_ACTIVATION_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END
$post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260827108000','674_authenticated_monitor_mailbox_activation_transition',ARRAY[
  'Require exact applied 673 predecessor, exact 673 function hashes, sealed .44 runner and external adapter hash anchors, staging sentinel and absent Production sentinel',
  'Activate exactly the existing pdc_pmb_email Gmail staging mailbox row for the exact sales authenticated actor/gateway/release/source/manifest/planner/trust binding',
  'Require exactly one active mailbox and fail closed for unrelated or additional active mailboxes while preserving test_mode and credential-free staging config',
  'Route the standard authenticated JWT actor scope and existing enqueue/claim/attachment/result/canonical/agentic RPC chain through the guarded active scope',
  'Add forced-RLS immutable forward/history and an authenticated Administrator rollback that disables only the exact mailbox without deleting evidence',
  'Keep malformed input, wrong actor/gateway/role, anon/service_role, UID514, task, vehicle, outbound-email and Production paths fail closed'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
