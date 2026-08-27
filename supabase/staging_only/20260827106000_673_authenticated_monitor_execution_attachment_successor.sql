-- STAGING ONLY 673: external runtime/RPC compatibility successor.
-- The sealed .44 bundle, CURRENT pointer, 670/671/672 history and all
-- retained evidence remain unchanged. This migration does not enable a task,
-- contact a mailbox, process UID514, delete evidence or write Production.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-673-authenticated-monitor-execution-attachment-successor',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE
  v_scope_hash text;
  v_runtime_hash text;
  v_agentic_hash text;
  v_source_hash text;
  v_authorize_hash text;
  v_claim_hash text;
BEGIN
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_scope_hash
    FROM pg_proc p WHERE p.oid='public.pdc_monitor_actor_scope()'::regprocedure;
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_runtime_hash
    FROM pg_proc p WHERE p.oid='public.pdc_email_monitor_runtime_authorized_502(text)'::regprocedure;
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_agentic_hash
    FROM pg_proc p WHERE p.oid='public.pdc_agentic_email_authorized_502()'::regprocedure;
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_source_hash
    FROM pg_proc p WHERE p.oid='public.pdc_agentic_email_source_authorized_502(jsonb)'::regprocedure;
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_authorize_hash
    FROM pg_proc p WHERE p.oid='public.authorize_pdc_uid514_retained_intake_257(uuid,integer)'::regprocedure;
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_claim_hash
    FROM pg_proc p WHERE p.oid='public.claim_pdc_uid514_recovery_257(text,integer)'::regprocedure;
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR lower(coalesce(current_setting('app.environment',true),''))='production'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827067200' AND name='672_authenticated_active_email_monitor_identity_successor')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827067100' AND name='671_email_monitor_active_planner_rotation_after_670')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827067000' AND name='670_email_monitor_active_capability_uid514_seven_part_reconciliation')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827106000')<>0
     OR to_regclass('public.pdc_email_monitor_authenticated_execution_attachment_controls_673') IS NOT NULL
     OR to_regclass('public.pdc_email_monitor_authenticated_execution_attachment_history_673') IS NOT NULL
     OR to_regclass('public.pdc_uid514_attachment_selection_673') IS NOT NULL
     OR to_regprocedure('public.pdc_monitor_authenticated_active_scope_673(text)') IS NOT NULL
     OR to_regprocedure('public.admin_rollback_pdc_email_monitor_authenticated_execution_673(text)') IS NOT NULL
     OR v_scope_hash<>'55b6e195304992cf4a453d78f628d2591964c343317461b96c51e1df04aa6485'
     OR v_runtime_hash<>'33be21966f0122b760acff694fb08e896cdf031cbdd4c9e4d4fd6d51415158d9'
     OR v_agentic_hash<>'23b7447ff343f51e1dcc19916316db89920b627a85002ce0d6433251f11e1621'
     OR v_source_hash<>'55161035e5ec36c10d2df3b84ec85f937d9287c55163f87d7f4d2335d24b3f79'
     OR v_authorize_hash<>'cd34bcbf0e099cdc1e83c6f0037c9fbfc530552afd9454c95cd02388a30db20b'
     OR v_claim_hash<>'937a18081480543436e790469c4b62351f6c0e758badf1d5d1213cf0377b375b'
     OR (SELECT count(*) FROM public.pdc_email_monitor_active_capability_controls_670 WHERE singleton AND enabled AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND writer_active AND planner_commissioned AND activation_ready AND observed_mime_part_count=7 AND retained_authenticated_attachment_count=4 AND all_mime_parts_retained AND NOT production_writes)<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_active_planner_rotation_controls_671 WHERE singleton AND enabled AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND writer_active AND planner_commissioned AND activation_ready AND observed_mime_part_count=7 AND retained_authenticated_attachment_count=4 AND all_mime_parts_retained AND NOT production_writes)<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_active_capability_controls_672 WHERE singleton AND enabled AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND jwt_role='authenticated' AND server_application_role='importer' AND NOT production_writes AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed)<>1
     OR (SELECT count(*) FROM public.pdc_monitor_runtime_bindings_255 WHERE singleton AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND gateway_instance_id='pdc-monitor-staging-sales-uid509-v1' AND release_name='pdc-monitor-staging-m502-2026.08.44' AND source_sha='e850c319989d98b45b95a28aa815d78e2c2e3a4b' AND manifest_sha256='d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d' AND semantic_planner_sha256='7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348' AND semantic_planner_trust_receipt_sha256='e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227' AND semantic_planner_commissioned_at IS NOT NULL)<>1
     OR (SELECT count(*) FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)<>1
     OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>0
     OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND (enabled OR automatic_rule_application OR automatic_authenticated_jobcards OR outbound_email_enabled))<>0
     OR (SELECT count(*) FROM public.ai_email_intake WHERE provider_uid='imap_uid:514')<>0
     OR (SELECT count(*) FROM public.pdc_uid514_recovery_authorizations_257 WHERE recovery_event_id=25751401)<>0
  THEN RAISE EXCEPTION 'PDC_673_EXACT_672_PREDECESSOR_OR_FUNCTION_HASH_MISMATCH' USING errcode='55000'; END IF;
END
$guard$;

CREATE TABLE public.pdc_email_monitor_authenticated_execution_attachment_controls_673(
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
  planner_interface text NOT NULL CHECK(planner_interface='pmb-pdc-agentic-email-plan-v1'),
  planner_sha256 text NOT NULL CHECK(planner_sha256='7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348'),
  trust_receipt_sha256 text NOT NULL CHECK(trust_receipt_sha256='e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227'),
  observed_mime_part_count integer NOT NULL DEFAULT 7 CHECK(observed_mime_part_count=7),
  retained_authenticated_attachment_count integer NOT NULL DEFAULT 4 CHECK(retained_authenticated_attachment_count=4),
  qualifying_attachment_sha256 text NOT NULL CHECK(qualifying_attachment_sha256='9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4'),
  all_mime_parts_retained boolean NOT NULL DEFAULT true CHECK(all_mime_parts_retained),
  production_writes boolean NOT NULL DEFAULT false CHECK(NOT production_writes),
  task_enabled boolean NOT NULL DEFAULT false CHECK(NOT task_enabled),
  mailbox_contacted boolean NOT NULL DEFAULT false CHECK(NOT mailbox_contacted),
  uid514_processed boolean NOT NULL DEFAULT false CHECK(NOT uid514_processed),
  changed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_email_monitor_authenticated_execution_attachment_controls_673 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_monitor_authenticated_execution_attachment_controls_673 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_email_monitor_authenticated_execution_attachment_controls_673 FROM public,anon,authenticated,service_role,pdc_email_monitor;
INSERT INTO public.pdc_email_monitor_authenticated_execution_attachment_controls_673(
 actor_id,actor_email,jwt_role,server_application_role,gateway_instance_id,release_name,source_sha,manifest_sha256,
 planner_interface,planner_sha256,trust_receipt_sha256,qualifying_attachment_sha256)
VALUES(
 'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b','sales@broometoyota.com.au','authenticated','importer',
 'pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44',
 'e850c319989d98b45b95a28aa815d78e2c2e3a4b','d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d',
 'pmb-pdc-agentic-email-plan-v1','7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348','e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227','9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4');

CREATE TABLE public.pdc_email_monitor_authenticated_execution_attachment_history_673(
  history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key text NOT NULL UNIQUE,
  event_kind text NOT NULL CHECK(event_kind IN('forward_authenticated_execution_attachment','rollback')),
  predecessor_head text NOT NULL CHECK(predecessor_head='20260827067200'),
  successor_head text NOT NULL CHECK(successor_head='20260827106000'),
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
  observed_mime_part_count integer NOT NULL CHECK(observed_mime_part_count=7),
  retained_authenticated_attachment_count integer NOT NULL CHECK(retained_authenticated_attachment_count=4),
  qualifying_attachment_sha256 text NOT NULL CHECK(qualifying_attachment_sha256='9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4'),
  all_mime_parts_retained boolean NOT NULL CHECK(all_mime_parts_retained),
  proof jsonb NOT NULL,
  production_writes boolean NOT NULL CHECK(NOT production_writes),
  task_enabled boolean NOT NULL CHECK(NOT task_enabled),
  mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),
  uid514_processed boolean NOT NULL CHECK(NOT uid514_processed),
  performed_by uuid,
  performed_by_email text,
  rollback_contract text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE FUNCTION public.pdc_email_monitor_authenticated_execution_attachment_history_immutable_673()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public
AS $immutable$ BEGIN RAISE EXCEPTION 'PDC_673_AUTHENTICATED_EXECUTION_HISTORY_IMMUTABLE' USING errcode='55000'; END $immutable$;
CREATE TRIGGER pdc_email_monitor_authenticated_execution_attachment_history_immutable_673
BEFORE UPDATE OR DELETE ON public.pdc_email_monitor_authenticated_execution_attachment_history_673
FOR EACH ROW EXECUTE FUNCTION public.pdc_email_monitor_authenticated_execution_attachment_history_immutable_673();
ALTER TABLE public.pdc_email_monitor_authenticated_execution_attachment_history_673 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_monitor_authenticated_execution_attachment_history_673 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_email_monitor_authenticated_execution_attachment_history_673 FROM public,anon,authenticated,service_role,pdc_email_monitor;

CREATE TABLE public.pdc_uid514_attachment_selection_673(
  selection_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  recovery_event_id integer NOT NULL UNIQUE CHECK(recovery_event_id=25751401),
  intake_id uuid NOT NULL UNIQUE REFERENCES public.ai_email_intake(id) ON DELETE RESTRICT,
  parent_source_hash text NOT NULL CHECK(parent_source_hash~'^[a-f0-9]{64}$'),
  all_attachment_ids uuid[] NOT NULL CHECK(cardinality(all_attachment_ids)=7),
  qualifying_attachment_ids uuid[] NOT NULL CHECK(cardinality(qualifying_attachment_ids)=4),
  job_card_attachment_id uuid NOT NULL,
  observed_mime_part_count integer NOT NULL CHECK(observed_mime_part_count=7),
  retained_authenticated_attachment_count integer NOT NULL CHECK(retained_authenticated_attachment_count=4),
  qualifying_attachment_sha256 text NOT NULL CHECK(qualifying_attachment_sha256='9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4'),
  all_mime_parts_retained boolean NOT NULL CHECK(all_mime_parts_retained),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE FUNCTION public.pdc_uid514_attachment_selection_immutable_673()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public
AS $immutable$ BEGIN RAISE EXCEPTION 'PDC_673_UID514_ATTACHMENT_SELECTION_IMMUTABLE' USING errcode='55000'; END $immutable$;
CREATE TRIGGER pdc_uid514_attachment_selection_immutable_673
BEFORE UPDATE OR DELETE ON public.pdc_uid514_attachment_selection_673
FOR EACH ROW EXECUTE FUNCTION public.pdc_uid514_attachment_selection_immutable_673();
ALTER TABLE public.pdc_uid514_attachment_selection_673 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_uid514_attachment_selection_673 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_uid514_attachment_selection_673 FROM public,anon,authenticated,service_role,pdc_email_monitor;

CREATE FUNCTION public.pdc_monitor_authenticated_active_scope_673(p_gateway_instance_id text DEFAULT NULL)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,auth
AS $scope$
SELECT public.pdc_monitor_staging_guard()
 AND lower(coalesce(current_setting('app.environment',true),''))<>'production'
 AND to_regclass('public.pdc_production_environment_sentinel') IS NULL
 AND auth.uid()='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid
 AND lower(btrim(coalesce(auth.jwt()->>'email','')))='sales@broometoyota.com.au'
 AND coalesce(auth.jwt()->>'role','') IN('authenticated','pdc_email_monitor')
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
 AND (SELECT count(*) FROM public.monitored_mailboxes WHERE active)=0
 AND (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND (enabled OR automatic_rule_application OR automatic_authenticated_jobcards OR outbound_email_enabled))=0
 AND EXISTS(SELECT 1 FROM public.pdc_email_monitor_authenticated_active_capability_controls_672 c WHERE c.singleton AND c.enabled AND c.actor_id=auth.uid() AND c.jwt_role='authenticated' AND c.server_application_role='importer' AND c.gateway_instance_id='pdc-monitor-staging-sales-uid509-v1' AND c.release_name='pdc-monitor-staging-m502-2026.08.44' AND c.source_sha='e850c319989d98b45b95a28aa815d78e2c2e3a4b' AND c.manifest_sha256='d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d' AND c.planner_sha256='7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348' AND c.trust_receipt_sha256='e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227' AND NOT c.production_writes AND NOT c.task_enabled AND NOT c.mailbox_contacted AND NOT c.uid514_processed)
 AND EXISTS(SELECT 1 FROM public.pdc_email_monitor_authenticated_execution_attachment_controls_673 c WHERE c.singleton AND c.enabled AND c.actor_id=auth.uid() AND c.actor_email='sales@broometoyota.com.au' AND c.jwt_role='authenticated' AND c.server_application_role='importer' AND c.gateway_instance_id='pdc-monitor-staging-sales-uid509-v1' AND c.release_name='pdc-monitor-staging-m502-2026.08.44' AND c.source_sha='e850c319989d98b45b95a28aa815d78e2c2e3a4b' AND c.manifest_sha256='d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d' AND c.planner_sha256='7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348' AND c.trust_receipt_sha256='e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227' AND c.observed_mime_part_count=7 AND c.retained_authenticated_attachment_count=4 AND c.all_mime_parts_retained AND NOT c.production_writes AND NOT c.task_enabled AND NOT c.mailbox_contacted AND NOT c.uid514_processed)
 AND EXISTS(SELECT 1 FROM public.pdc_monitor_runtime_bindings_255 b WHERE b.singleton AND b.actor_id=auth.uid() AND b.gateway_instance_id='pdc-monitor-staging-sales-uid509-v1' AND b.release_name='pdc-monitor-staging-m502-2026.08.44' AND b.source_sha='e850c319989d98b45b95a28aa815d78e2c2e3a4b' AND b.manifest_sha256='d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d' AND b.semantic_planner_sha256='7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348' AND b.semantic_planner_trust_receipt_sha256='e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227' AND b.semantic_planner_commissioned_at IS NOT NULL)
$scope$;
REVOKE ALL ON FUNCTION public.pdc_monitor_authenticated_active_scope_673(text) FROM public,anon,authenticated,service_role,pdc_email_monitor;
-- PDC_673_AUTHENTICATED_ACTIVE_IDENTITY_REQUIRED is the fail-closed identity
-- marker returned by the external/runtime handoff when this boolean is false.

-- Preserve the legacy contained branch while adding only the exact active
-- importer branch. All callers still resolve through one server-side scope.
CREATE OR REPLACE FUNCTION public.pdc_monitor_actor_scope()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,auth AS $body$
DECLARE
  v_uid uuid:=auth.uid();
  v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_count integer;
BEGIN
  IF public.pdc_monitor_authenticated_active_scope_673(NULL) THEN
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
AS $authorized$ SELECT public.pdc_monitor_authenticated_active_scope_673(p_gateway_instance_id) $authorized$;
REVOKE ALL ON FUNCTION public.pdc_email_monitor_runtime_authorized_502(text) FROM public,anon,authenticated,service_role,pdc_email_monitor;

-- Retain every attachment row while authorizing exactly four verified PDFs as
-- the canonical business-document projection. The Job Card is hash-bound.
CREATE OR REPLACE FUNCTION public.authorize_pdc_uid514_retained_intake_257(p_intake_id uuid,p_recovery_event_id integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,auth,extensions AS $authorize$
DECLARE
  s jsonb:=public.pdc_monitor_actor_scope();
  v_intake public.ai_email_intake%rowtype;
  v_existing public.pdc_uid514_recovery_authorizations_257%rowtype;
  v_selection public.pdc_uid514_attachment_selection_673%rowtype;
  v_count integer; v_pdf_count integer; v_valid_count integer; v_match integer;
  v_all_ids uuid[]; v_pdf_ids uuid[]; v_job_card_id uuid;
BEGIN
  IF p_recovery_event_id<>25751401 THEN RAISE EXCEPTION 'PDC_257_UID514_SCOPE_INVALID' USING errcode='22023'; END IF;
  SELECT q.* INTO v_intake FROM public.ai_email_intake q JOIN public.monitored_mailboxes m ON m.id=q.monitored_mailbox_id
   WHERE q.id=p_intake_id AND q.provider_uid='imap_uid:514' AND lower(q.recipient_mailbox)='pmbcontroller@gmail.com'
    AND lower(m.mailbox_address)='pmbcontroller@gmail.com' AND m.active AND q.provider_authserv_id='mx.google.com'
    AND q.provider_authentication->>'gmail_authentication_results'='true'
    AND q.provider_authentication->>'sender_domain'='pmgwa.com.au'
    AND (q.provider_authentication->>'dkim_aligned'='true' OR q.provider_authentication->>'dmarc_aligned'='true') FOR SHARE OF q;
  IF NOT FOUND OR lower(coalesce(v_intake.source_hash,''))!~'^[a-f0-9]{64}$' THEN RAISE EXCEPTION 'PDC_257_UID514_INTAKE_AUTH_MISMATCH' USING errcode='42501'; END IF;
  SELECT count(*),
    count(*) FILTER(WHERE lower(coalesce(a.content_type,''))='application/pdf' AND lower(a.file_name)~'\.pdf$'),
    count(*) FILTER(WHERE lower(coalesce(a.source_hash,''))~'^[a-f0-9]{64}$' AND lower(coalesce(a.content_type,'')) IN('application/pdf','image/png','image/jpeg') AND lower(a.file_name)~'\.(pdf|png|jpe?g)$' AND coalesce(a.storage_path,'') LIKE 'pdc-email-intake-private/%' AND coalesce(a.size_bytes,0) BETWEEN 1 AND 10485760),
    count(*) FILTER(WHERE lower(a.source_hash)='9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4' AND lower(a.content_type)='application/pdf' AND lower(a.file_name)~'\.pdf$'),
    array_agg(a.id ORDER BY a.created_at,a.id),
    array_agg(a.id ORDER BY a.created_at,a.id) FILTER(WHERE lower(a.content_type)='application/pdf' AND lower(a.file_name)~'\.pdf$'),
    (array_agg(a.id ORDER BY a.created_at,a.id) FILTER(WHERE lower(a.source_hash)='9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4' AND lower(a.content_type)='application/pdf' AND lower(a.file_name)~'\.pdf$'))[1]
   INTO v_count,v_pdf_count,v_valid_count,v_match,v_all_ids,v_pdf_ids,v_job_card_id
   FROM public.ai_email_attachments a WHERE a.intake_id=p_intake_id;
  IF v_count<>7 OR v_pdf_count<>4 OR v_valid_count<>7 OR v_match<>1 OR cardinality(v_all_ids)<>7 OR cardinality(v_pdf_ids)<>4 OR v_job_card_id IS NULL THEN
    RAISE EXCEPTION 'PDC_673_ATTACHMENT_SET_MISMATCH' USING errcode='42501';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-uid514-recovery-257',0));
  SELECT * INTO v_existing FROM public.pdc_uid514_recovery_authorizations_257 WHERE recovery_event_id=25751401;
  IF FOUND THEN
    SELECT * INTO v_selection FROM public.pdc_uid514_attachment_selection_673 WHERE recovery_event_id=25751401;
    IF NOT FOUND OR v_existing.intake_id<>p_intake_id OR v_existing.parent_source_hash<>lower(v_intake.source_hash)
       OR v_selection.all_attachment_ids<>v_all_ids OR v_selection.qualifying_attachment_ids<>v_pdf_ids OR v_selection.job_card_attachment_id<>v_job_card_id THEN
      RAISE EXCEPTION 'PDC_673_ATTACHMENT_SELECTION_REPLAY_CONFLICT' USING errcode='23505';
    END IF;
    RETURN jsonb_build_object('ok',true,'code','uid514_authorization_replayed','recovery_event_id',25751401,'parent_source_hash',v_existing.parent_source_hash,'observed_mime_part_count',7,'retained_authenticated_attachment_count',4,'qualifying_attachment_sha256','9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4','all_mime_parts_retained',true);
  END IF;
  INSERT INTO public.pdc_uid514_recovery_authorizations_257(recovery_event_id,intake_id,mailbox_address,mailbox_folder,mailbox_uidvalidity,mailbox_uid,parent_source_hash,qualifying_attachment_sha256,stock_number,job_card_number,attachment_count)
  VALUES(25751401,p_intake_id,'pmbcontroller@gmail.com','Inbox',1,514,lower(v_intake.source_hash),'9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4','13016925','J139125482',4) RETURNING * INTO v_existing;
  INSERT INTO public.pdc_uid514_attachment_selection_673(recovery_event_id,intake_id,parent_source_hash,all_attachment_ids,qualifying_attachment_ids,job_card_attachment_id,observed_mime_part_count,retained_authenticated_attachment_count,qualifying_attachment_sha256,all_mime_parts_retained)
  VALUES(25751401,p_intake_id,lower(v_intake.source_hash),v_all_ids,v_pdf_ids,v_job_card_id,7,4,'9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4',true);
  RETURN jsonb_build_object('ok',true,'code','uid514_authorized','recovery_event_id',25751401,'parent_source_hash',v_existing.parent_source_hash,'observed_mime_part_count',7,'retained_authenticated_attachment_count',4,'qualifying_attachment_sha256','9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4','all_mime_parts_retained',true);
END
$authorize$;
REVOKE ALL ON FUNCTION public.authorize_pdc_uid514_retained_intake_257(uuid,integer) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.authorize_pdc_uid514_retained_intake_257(uuid,integer) TO authenticated,pdc_email_monitor;

-- Active standard-authenticated JWTs can use the existing claim RPC only after
-- the exact actor scope above has passed; its immutable attempt evidence stays.
REVOKE ALL ON FUNCTION public.claim_pdc_uid514_recovery_257(text,integer) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.claim_pdc_uid514_recovery_257(text,integer) TO authenticated,pdc_email_monitor;

-- The existing 502 bodies remain the reviewed implementation. Their internal
-- authorization helper now accepts only the exact authenticated actor branch,
-- so granting these specific RPCs does not grant table DML or receipt access.
GRANT EXECUTE ON FUNCTION public.enqueue_pdc_email_intake(jsonb,jsonb),
 public.claim_pdc_email_intake_batch(integer,text),
 public.record_pdc_email_monitor_cycle(text,text,text),
 public.heartbeat_pdc_email_intake_claim(uuid,uuid,text),
 public.get_pdc_monitor_intake_attachments(uuid,uuid,text),
 public.record_pdc_monitor_attachment_extraction(uuid,uuid,uuid,text,text,text),
 public.record_pdc_email_intake_result(uuid,uuid,text,boolean,jsonb,text,text,boolean,jsonb),
 public.process_claimed_pdc_email_intake_work(uuid,uuid,text,text,text,jsonb),
 public.read_pdc_agentic_email_context_502(jsonb),
 public.record_pdc_agentic_email_plan_502(jsonb),
 public.execute_pdc_agentic_email_action_502(jsonb),
 public.pdc_agentic_apply_action_502(uuid),
 public.read_pdc_agentic_email_vehicle_502(uuid),
 public.append_pdc_agentic_email_action_audit_502(jsonb),
 public.finalize_pdc_agentic_email_plan_502(jsonb)
 TO authenticated;

CREATE FUNCTION public.admin_rollback_pdc_email_monitor_authenticated_execution_673(p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,auth AS $rollback$
DECLARE
  v_admin uuid:=auth.uid(); v_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); v_count integer;
  v_control public.pdc_email_monitor_authenticated_execution_attachment_controls_673%rowtype;
  v_existing public.pdc_email_monitor_authenticated_execution_attachment_history_673%rowtype;
  v_before jsonb; v_after jsonb; v_event_key text;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR v_admin IS NULL OR coalesce(auth.jwt()->>'role','')<>'authenticated' OR length(btrim(coalesce(p_reason,'')))<10 THEN RAISE EXCEPTION 'PDC_673_ADMIN_AUTHORITY_REQUIRED' USING errcode='42501'; END IF;
  SELECT count(*) INTO v_count FROM public.pdc_user_roles r JOIN auth.users u ON u.id=r.auth_user_id AND lower(u.email)=v_email WHERE r.auth_user_id=v_admin AND lower(r.email)=v_email AND r.active AND r.account_status='approved' AND r.role::text='administrator';
  IF v_count<>1 THEN RAISE EXCEPTION 'PDC_673_ADMIN_AUTHORITY_REQUIRED' USING errcode='42501'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-staging-673-authenticated-monitor-execution-attachment-successor',0));
  SELECT * INTO v_control FROM public.pdc_email_monitor_authenticated_execution_attachment_controls_673 WHERE singleton FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_673_CONTROL_MISSING' USING errcode='55000'; END IF;
  v_event_key:=encode(extensions.digest(convert_to('pdc-staging-673-authenticated-monitor-execution-attachment-successor|rollback|'||v_control.actor_id::text,'UTF8'),'sha256'),'hex');
  SELECT * INTO v_existing FROM public.pdc_email_monitor_authenticated_execution_attachment_history_673 WHERE event_key=v_event_key;
  IF FOUND THEN
    IF v_control.enabled THEN RAISE EXCEPTION 'PDC_673_ROLLBACK_STATE_DRIFT' USING errcode='55000'; END IF;
    RETURN jsonb_build_object('ok',true,'code','pdc_email_monitor_authenticated_execution_rolled_back_673','idempotent',true,'history_id',v_existing.history_id,'production_writes',false,'task_enabled',false,'mailbox_contacted',false,'uid514_processed',false);
  END IF;
  IF NOT v_control.enabled THEN RAISE EXCEPTION 'PDC_673_ROLLBACK_STATE_DRIFT' USING errcode='55000'; END IF;
  v_before:=to_jsonb(v_control);
  UPDATE public.pdc_email_monitor_authenticated_execution_attachment_controls_673 SET enabled=false,changed_at=clock_timestamp() WHERE singleton RETURNING * INTO v_control;
  v_after:=to_jsonb(v_control);
  INSERT INTO public.pdc_email_monitor_authenticated_execution_attachment_history_673(event_key,event_kind,predecessor_head,successor_head,actor_id,actor_email,jwt_role,server_application_role,gateway_instance_id,release_name,source_sha,manifest_sha256,planner_sha256,trust_receipt_sha256,observed_mime_part_count,retained_authenticated_attachment_count,qualifying_attachment_sha256,all_mime_parts_retained,proof,production_writes,task_enabled,mailbox_contacted,uid514_processed,performed_by,performed_by_email,rollback_contract)
  VALUES(v_event_key,'rollback','20260827067200','20260827106000',v_control.actor_id,v_control.actor_email,'authenticated','importer',v_control.gateway_instance_id,v_control.release_name,v_control.source_sha,v_control.manifest_sha256,v_control.planner_sha256,v_control.trust_receipt_sha256,7,4,'9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4',true,jsonb_build_object('before',v_before,'after',v_after,'server_side_scope_disabled',true),false,false,false,false,v_admin,v_email,'Guarded Administrator disable only; immutable 670/671/672 history and every retained attachment remain unchanged');
  INSERT INTO public.audit_events(action,table_name,row_id,actor_id,actor_email,before_data,after_data,metadata)
  VALUES('update','pdc_email_monitor_authenticated_execution_attachment_controls_673',true,v_admin,v_email,v_before,v_after,jsonb_build_object('event_type','pdc_email_monitor_authenticated_execution_rolled_back_673','reason',btrim(p_reason),'production_untouched',true,'task_enabled',false,'mailbox_contacted',false,'uid514_processed',false));
  RETURN jsonb_build_object('ok',true,'code','pdc_email_monitor_authenticated_execution_rolled_back_673','idempotent',false,'production_writes',false,'task_enabled',false,'mailbox_contacted',false,'uid514_processed',false,'rollback_available',true);
END
$rollback$;
REVOKE ALL ON FUNCTION public.admin_rollback_pdc_email_monitor_authenticated_execution_673(text) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.admin_rollback_pdc_email_monitor_authenticated_execution_673(text) TO authenticated;

DO $history$
BEGIN
  INSERT INTO public.pdc_email_monitor_authenticated_execution_attachment_history_673(
    event_key,event_kind,predecessor_head,successor_head,actor_id,actor_email,jwt_role,server_application_role,gateway_instance_id,release_name,source_sha,manifest_sha256,planner_sha256,trust_receipt_sha256,
    observed_mime_part_count,retained_authenticated_attachment_count,qualifying_attachment_sha256,all_mime_parts_retained,proof,production_writes,task_enabled,mailbox_contacted,uid514_processed,rollback_contract)
  VALUES(
    encode(extensions.digest(convert_to('pdc-staging-673-authenticated-monitor-execution-attachment-successor|forward|df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b','UTF8'),'sha256'),'hex'),'forward_authenticated_execution_attachment','20260827067200','20260827106000',
    'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b','sales@broometoyota.com.au','authenticated','importer','pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44',
    'e850c319989d98b45b95a28aa815d78e2c2e3a4b','d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d','7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348','e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227',
    7,4,'9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4',true,
    jsonb_build_object('predecessor_head','20260827067200','standard_authenticated_jwt_only',true,'server_side_actor_id_proof',true,'server_side_actor_email_proof',true,'approved_importer_proof',true,'active_writer_proof',true,'exact_gateway_release_source_manifest_proof',true,'commissioned_planner_trust_proof',true,'seven_mime_parts_preserved',true,'four_authenticated_business_pdfs_selected',true,'job_card_sha256','9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4','direct_table_dml',false,'production_exclusion_proof',true),
    false,false,false,false,'Forward compatibility only; Administrator rollback disables this successor without changing prior immutable history or evidence');
END
$history$;

DO $post$
BEGIN
  IF (SELECT count(*) FROM public.pdc_email_monitor_authenticated_execution_attachment_controls_673 WHERE singleton AND enabled AND observed_mime_part_count=7 AND retained_authenticated_attachment_count=4 AND all_mime_parts_retained AND NOT production_writes AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed)<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_execution_attachment_history_673 WHERE event_kind='forward_authenticated_execution_attachment')<>1
     OR NOT has_function_privilege('authenticated','public.claim_pdc_email_intake_batch(integer,text)','execute')
     OR NOT has_function_privilege('authenticated','public.record_pdc_email_monitor_cycle(text,text,text)','execute')
     OR NOT has_function_privilege('authenticated','public.read_pdc_agentic_email_context_502(jsonb)','execute')
     OR NOT has_function_privilege('authenticated','public.pdc_agentic_apply_action_502(uuid)','execute')
     OR has_function_privilege('anon','public.claim_pdc_email_intake_batch(integer,text)','execute')
     OR has_function_privilege('service_role','public.claim_pdc_email_intake_batch(integer,text)','execute')
     OR has_table_privilege('authenticated','public.pdc_email_monitor_authenticated_execution_attachment_controls_673','select')
     OR has_table_privilege('authenticated','public.pdc_email_monitor_authenticated_execution_attachment_history_673','select')
     OR has_table_privilege('authenticated','public.pdc_uid514_attachment_selection_673','select')
     OR (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid='public.pdc_email_monitor_authenticated_execution_attachment_history_673'::regclass) IS DISTINCT FROM true
     OR (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid='public.pdc_uid514_attachment_selection_673'::regclass) IS DISTINCT FROM true
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>0
     OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND (enabled OR automatic_rule_application OR automatic_authenticated_jobcards OR outbound_email_enabled))<>0
  THEN RAISE EXCEPTION 'PDC_673_AUTHENTICATED_EXECUTION_ATTACHMENT_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END
$post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260827106000','673_authenticated_monitor_execution_attachment_successor',ARRAY[
 'Require exact applied 670/671/672 predecessor rows and exact prestate function hashes while allowing unrelated later staging ledger entries',
 'Add a protected external-runtime compatibility control with exact authenticated actor, gateway, release, source, manifest, planner and trust proof',
 'Permit only the required existing queue, claim, attachment, result, canonical-work and agentic execution RPCs to authenticated; preserve anon/service_role/direct-table denial',
 'Make the existing monitor scope and 502 runtime authorization accept the exact standard authenticated actor only after server-side importer/writer/containment/binding proof',
 'Authorize UID514 with seven MIME parts, exactly four verified PDF business documents and one exact Job Card hash while preserving every attachment row and recording deterministic selection',
 'Add forced-RLS immutable history, an Administrator disable/rollback path and fail-closed malformed, wrong-actor, wrong-gateway and conflicting-replay behavior',
 'Do not enable the Windows task, contact the mailbox, process UID514, delete retained evidence or write Production'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
