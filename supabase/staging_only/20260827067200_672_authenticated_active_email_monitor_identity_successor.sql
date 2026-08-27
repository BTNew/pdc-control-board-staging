-- STAGING ONLY 672: accept the exact sales actor's standard Supabase
-- authenticated JWT through new server-side proof RPCs. This append-only
-- successor does not issue tokens, alter JWT signing, contact the mailbox,
-- process UID514, enable a task, grant table DML, or write Production.
-- The active_mailboxes precondition remains zero throughout this successor.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-672-authenticated-active-email-monitor-identity',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres'
     OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260827067100'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827067100' AND name='671_email_monitor_active_planner_rotation_after_670')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260827067100')<>0
     OR to_regclass('public.pdc_email_monitor_authenticated_active_capability_controls_672') IS NOT NULL
     OR to_regclass('public.pdc_email_monitor_authenticated_active_capability_history_672') IS NOT NULL
     OR to_regprocedure('public.pdc_monitor_authenticated_active_scope_672()') IS NOT NULL
     OR to_regprocedure('public.verify_pdc_monitor_runtime_binding_authenticated_672(text,text,text,text,text,text,text)') IS NOT NULL
     OR to_regprocedure('public.read_pdc_uid514_transaction_receipt_authenticated_672(integer)') IS NOT NULL
     OR (SELECT count(*) FROM public.pdc_email_monitor_active_capability_controls_670 WHERE singleton AND enabled AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND actor_email='sales@broometoyota.com.au' AND writer_active AND planner_commissioned AND activation_ready AND NOT windows_monitor_enabled AND NOT outbound_email_enabled AND NOT production_writes AND observed_mime_part_count=7 AND retained_authenticated_attachment_count=4 AND all_mime_parts_retained)<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_active_planner_rotation_controls_671 WHERE singleton AND enabled AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND actor_email='sales@broometoyota.com.au' AND writer_active AND planner_commissioned AND activation_ready AND NOT windows_monitor_enabled AND NOT outbound_email_enabled AND NOT production_writes AND observed_mime_part_count=7 AND retained_authenticated_attachment_count=4 AND all_mime_parts_retained)<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_active_planner_rotation_history_671 WHERE event_kind='forward_planner_rotation' AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b')<>1
     OR (SELECT count(*) FROM public.pdc_user_roles WHERE auth_user_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND lower(email)='sales@broometoyota.com.au' AND active AND account_status='approved' AND role::text='importer')<>1
     OR (SELECT count(*) FROM public.pdc_user_roles WHERE auth_user_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND active)<>1
     OR (SELECT count(*) FROM public.pdc_monitor_stage_activation_writers WHERE user_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND active AND revoked_at IS NULL)<>1
     OR (SELECT count(*) FROM public.pdc_monitor_runtime_bindings_255 WHERE singleton AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND gateway_instance_id='pdc-monitor-staging-sales-uid509-v1' AND release_name='pdc-monitor-staging-m502-2026.08.44' AND source_sha='e850c319989d98b45b95a28aa815d78e2c2e3a4b' AND manifest_sha256='d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d' AND semantic_planner_sha256='7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348' AND semantic_planner_trust_receipt_sha256='e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227' AND semantic_planner_commissioned_at IS NOT NULL)<>1
     OR (SELECT count(*) FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)<>1
     OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>0
     OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND (enabled OR automatic_rule_application OR automatic_authenticated_jobcards OR outbound_email_enabled))<>0
  THEN RAISE EXCEPTION 'PDC_672_EXACT_671_PREDECESSOR_OR_COLLISION_MISMATCH' USING errcode='55000'; END IF;
END
$guard$;

CREATE TABLE public.pdc_email_monitor_authenticated_active_capability_controls_672(
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
  active_writer_required boolean NOT NULL DEFAULT true CHECK(active_writer_required),
  planner_commissioned_required boolean NOT NULL DEFAULT true CHECK(planner_commissioned_required),
  production_writes boolean NOT NULL DEFAULT false CHECK(NOT production_writes),
  task_enabled boolean NOT NULL DEFAULT false CHECK(NOT task_enabled),
  mailbox_contacted boolean NOT NULL DEFAULT false CHECK(NOT mailbox_contacted),
  uid514_processed boolean NOT NULL DEFAULT false CHECK(NOT uid514_processed),
  changed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_email_monitor_authenticated_active_capability_controls_672 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_monitor_authenticated_active_capability_controls_672 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_email_monitor_authenticated_active_capability_controls_672 FROM public,anon,authenticated,service_role,pdc_email_monitor;

CREATE TABLE public.pdc_email_monitor_authenticated_active_capability_history_672(
  history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key text NOT NULL UNIQUE,
  event_kind text NOT NULL CHECK(event_kind='forward_authenticated_identity_successor'),
  predecessor_head text NOT NULL CHECK(predecessor_head='20260827067100'),
  successor_head text NOT NULL CHECK(successor_head='20260827067200'),
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
  proof jsonb NOT NULL,
  production_writes boolean NOT NULL CHECK(NOT production_writes),
  task_enabled boolean NOT NULL CHECK(NOT task_enabled),
  mailbox_contacted boolean NOT NULL CHECK(NOT mailbox_contacted),
  uid514_processed boolean NOT NULL CHECK(NOT uid514_processed),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE FUNCTION public.pdc_email_monitor_authenticated_active_capability_history_immutable_672()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public
AS $immutable$ BEGIN RAISE EXCEPTION 'PDC_672_AUTHENTICATED_ACTIVE_HISTORY_IMMUTABLE' USING errcode='55000'; END $immutable$;
CREATE TRIGGER pdc_email_monitor_authenticated_active_capability_history_immutable_672
BEFORE UPDATE OR DELETE ON public.pdc_email_monitor_authenticated_active_capability_history_672
FOR EACH ROW EXECUTE FUNCTION public.pdc_email_monitor_authenticated_active_capability_history_immutable_672();
ALTER TABLE public.pdc_email_monitor_authenticated_active_capability_history_672 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_monitor_authenticated_active_capability_history_672 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_email_monitor_authenticated_active_capability_history_672 FROM public,anon,authenticated,service_role,pdc_email_monitor;

INSERT INTO public.pdc_email_monitor_authenticated_active_capability_controls_672(
  actor_id,actor_email,jwt_role,server_application_role,gateway_instance_id,release_name,source_sha,manifest_sha256,planner_interface,planner_sha256,trust_receipt_sha256)
VALUES(
  'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b','sales@broometoyota.com.au','authenticated','importer',
  'pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44',
  'e850c319989d98b45b95a28aa815d78e2c2e3a4b','d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d',
  'pmb-pdc-agentic-email-plan-v1','7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348','e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227');

INSERT INTO public.pdc_email_monitor_authenticated_active_capability_history_672(
  event_key,event_kind,predecessor_head,successor_head,actor_id,actor_email,jwt_role,server_application_role,
  gateway_instance_id,release_name,source_sha,manifest_sha256,planner_sha256,trust_receipt_sha256,proof,
  production_writes,task_enabled,mailbox_contacted,uid514_processed)
VALUES(
  encode(extensions.digest(convert_to('pdc-staging-672-authenticated-active-email-monitor-identity|forward|df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b','UTF8'),'sha256'),'hex'),
  'forward_authenticated_identity_successor','20260827067100','20260827067200',
  'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b','sales@broometoyota.com.au','authenticated','importer',
  'pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44',
  'e850c319989d98b45b95a28aa815d78e2c2e3a4b','d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d',
  '7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348','e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227',
  jsonb_build_object('server_side_actor_id_proof',true,'server_side_actor_email_proof',true,'approved_importer_proof',true,'active_writer_proof',true,'exact_gateway_release_source_manifest_proof',true,'commissioned_planner_trust_proof',true,'production_exclusion_proof',true,'direct_table_access',false,'standard_authenticated_jwt_only',true),
  false,false,false,false);

CREATE FUNCTION public.pdc_monitor_authenticated_active_scope_672()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,auth
AS $scope$
DECLARE
  v_actor_id uuid:=auth.uid();
  v_jwt_role text:=coalesce(auth.jwt()->>'role','');
  v_jwt_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_db_email text;
  v_control public.pdc_email_monitor_authenticated_active_capability_controls_672%rowtype;
  v_binding public.pdc_monitor_runtime_bindings_255%rowtype;
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR lower(coalesce(current_setting('app.environment',true),''))='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR v_actor_id IS DISTINCT FROM 'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid
     OR v_jwt_role<>'authenticated'
     OR v_jwt_email<>'sales@broometoyota.com.au' THEN
    RAISE EXCEPTION 'PDC_672_AUTHENTICATED_ACTIVE_IDENTITY_REQUIRED' USING errcode='42501';
  END IF;
  SELECT lower(u.email) INTO v_db_email FROM auth.users u
   WHERE u.id=v_actor_id AND lower(coalesce(u.email,''))=v_jwt_email
     AND coalesce(u.raw_app_meta_data->>'pdc_identity_type','')='non_human_monitor';
  IF v_db_email IS DISTINCT FROM 'sales@broometoyota.com.au' THEN
    RAISE EXCEPTION 'PDC_672_AUTHENTICATED_ACTIVE_ACTOR_EMAIL_PROOF_REQUIRED' USING errcode='42501';
  END IF;
  SELECT * INTO v_control FROM public.pdc_email_monitor_authenticated_active_capability_controls_672 WHERE singleton AND enabled;
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_672_AUTHENTICATED_ACTIVE_CONTROL_MISSING' USING errcode='55000'; END IF;
  IF v_control.actor_id<>v_actor_id OR v_control.actor_email<>v_db_email OR v_control.jwt_role<>v_jwt_role OR v_control.server_application_role<>'importer'
     OR v_control.gateway_instance_id<>'pdc-monitor-staging-sales-uid509-v1' OR v_control.release_name<>'pdc-monitor-staging-m502-2026.08.44'
     OR v_control.source_sha<>'e850c319989d98b45b95a28aa815d78e2c2e3a4b' OR v_control.manifest_sha256<>'d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d'
     OR v_control.planner_sha256<>'7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348' OR v_control.trust_receipt_sha256<>'e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227'
     OR v_control.production_writes OR v_control.task_enabled OR v_control.mailbox_contacted OR v_control.uid514_processed THEN
    RAISE EXCEPTION 'PDC_672_AUTHENTICATED_ACTIVE_CONTROL_MISMATCH' USING errcode='42501';
  END IF;
  IF (SELECT count(*) FROM public.pdc_user_roles r WHERE r.auth_user_id=v_actor_id AND lower(r.email)=v_db_email AND r.active AND r.account_status='approved' AND r.role::text='importer')<>1
     OR (SELECT count(*) FROM public.pdc_user_roles r WHERE r.auth_user_id=v_actor_id AND r.active)<>1
     OR (SELECT count(*) FROM public.pdc_monitor_stage_activation_writers w WHERE w.user_id=v_actor_id AND w.active AND w.revoked_at IS NULL)<>1
     OR (SELECT count(*) FROM public.pdc_monitor_stage_activation_writers w WHERE w.active AND w.revoked_at IS NULL)<>1
     OR EXISTS(SELECT 1 FROM public.pdc_auditor_worker_identities w WHERE w.auth_user_id=v_actor_id AND w.active)
     OR EXISTS(SELECT 1 FROM public.pdc_auditor_user_dealer_scopes s WHERE s.auth_user_id=v_actor_id AND s.active)
     OR EXISTS(SELECT 1 FROM public.pdc_auditor_executor_identities e WHERE e.auth_user_id=v_actor_id AND e.active AND e.expires_at>clock_timestamp())
     OR EXISTS(SELECT 1 FROM public.pdc_auditor_service_identities_225 s WHERE s.auth_user_id=v_actor_id AND s.active)
     OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>0
     OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND (enabled OR automatic_rule_application OR automatic_authenticated_jobcards OR outbound_email_enabled))<>0 THEN
    RAISE EXCEPTION 'PDC_672_AUTHENTICATED_ACTIVE_ROLE_WRITER_OR_CONTAINMENT_PROOF_REQUIRED' USING errcode='42501';
  END IF;
  SELECT * INTO v_binding FROM public.pdc_monitor_runtime_bindings_255
   WHERE singleton AND actor_id=v_actor_id AND gateway_instance_id=v_control.gateway_instance_id AND release_name=v_control.release_name
     AND source_sha=v_control.source_sha AND manifest_sha256=v_control.manifest_sha256
     AND semantic_planner_sha256=v_control.planner_sha256 AND semantic_planner_trust_receipt_sha256=v_control.trust_receipt_sha256
     AND semantic_planner_commissioned_at IS NOT NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_672_AUTHENTICATED_ACTIVE_RUNTIME_BINDING_PROOF_REQUIRED' USING errcode='42501'; END IF;
  RETURN jsonb_build_object('actor_id',v_actor_id,'actor_email',v_db_email,'jwt_role',v_jwt_role,'server_application_role','importer','gateway_instance_id',v_binding.gateway_instance_id,'release_name',v_binding.release_name,'source_sha',v_binding.source_sha,'manifest_sha256',v_binding.manifest_sha256,'semantic_planner_sha256',v_binding.semantic_planner_sha256,'semantic_planner_trust_receipt_sha256',v_binding.semantic_planner_trust_receipt_sha256,'writer_active',true,'planner_commissioned',true,'production_writes',false,'task_enabled',false,'mailbox_contacted',false,'uid514_processed',false,'migration_head',503,'compatibility_successor_head',672);
END
$scope$;
REVOKE ALL ON FUNCTION public.pdc_monitor_authenticated_active_scope_672() FROM public,anon,authenticated,service_role,pdc_email_monitor;

CREATE FUNCTION public.verify_pdc_monitor_runtime_binding_authenticated_672(
  p_mode text,p_gateway_instance_id text,p_release_name text,p_source_sha text,p_manifest_sha256 text,
  p_semantic_planner_sha256 text DEFAULT NULL,p_semantic_planner_trust_receipt_sha256 text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,auth
AS $verify$
DECLARE s jsonb:=public.pdc_monitor_authenticated_active_scope_672();
BEGIN
  IF lower(btrim(coalesce(p_mode,'')))<>'active'
     OR btrim(coalesce(p_gateway_instance_id,''))<>s->>'gateway_instance_id'
     OR btrim(coalesce(p_release_name,''))<>s->>'release_name'
     OR lower(btrim(coalesce(p_source_sha,'')))<>s->>'source_sha'
     OR lower(btrim(coalesce(p_manifest_sha256,'')))<>s->>'manifest_sha256'
     OR lower(btrim(coalesce(p_semantic_planner_sha256,'')))<>s->>'semantic_planner_sha256'
     OR lower(btrim(coalesce(p_semantic_planner_trust_receipt_sha256,'')))<>s->>'semantic_planner_trust_receipt_sha256' THEN
    RETURN jsonb_build_object('ok',false,'code','runtime_binding_mismatch','activation_ready',false,'production_writes',false);
  END IF;
  RETURN s||jsonb_build_object('ok',true,'code','runtime_binding_verified_authenticated_672','mode','active','operational',true,'activation_ready',true);
END
$verify$;
REVOKE ALL ON FUNCTION public.verify_pdc_monitor_runtime_binding_authenticated_672(text,text,text,text,text,text,text) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.verify_pdc_monitor_runtime_binding_authenticated_672(text,text,text,text,text,text,text) TO authenticated;

CREATE FUNCTION public.read_pdc_uid514_transaction_receipt_authenticated_672(p_recovery_event_id integer)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,auth
AS $reader$
DECLARE
  s jsonb:=public.pdc_monitor_authenticated_active_scope_672();
  v_auth public.pdc_uid514_recovery_authorizations_257%rowtype;
  v_receipt public.pdc_jobcard_attachment_import_receipts%rowtype;
  v_terminal public.pdc_uid514_staging_commissioning_terminal_receipts_507%rowtype;
  v_code text; v_kind text; v_source text;
BEGIN
  IF p_recovery_event_id<>25751401 THEN RAISE EXCEPTION 'PDC_672_UID514_SCOPE_INVALID' USING errcode='22023'; END IF;
  IF (SELECT enabled FROM public.pdc_monitor_uid514_reader_compatibility_controls_506 WHERE singleton) IS DISTINCT FROM true THEN RAISE EXCEPTION 'PDC_506_READER_COMPATIBILITY_DISABLED' USING errcode='55000'; END IF;
  SELECT r.* INTO v_terminal FROM public.pdc_uid514_staging_commissioning_terminal_receipts_507 r
   JOIN public.pdc_uid514_staging_commissioning_controls_507 c ON c.singleton AND c.enabled
   WHERE r.recovery_event_id=25751401 AND r.actor_id=(s->>'actor_id')::uuid AND r.gateway_instance_id=s->>'gateway_instance_id'
     AND r.release_name=s->>'release_name' AND r.source_sha=s->>'source_sha' AND r.manifest_sha256=s->>'manifest_sha256'
     AND r.synthetic_staging_commissioning AND NOT r.physical_mailbox_fetch AND NOT r.mailbox_flags_changed
     AND r.vehicle_operations=0 AND r.operation_lines=0 AND NOT r.operational AND NOT r.activation_ready AND NOT r.writer_active AND NOT r.planner_commissioned AND NOT r.production_writes;
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_672_UID514_TERMINAL_RECEIPT_MISSING' USING errcode='55000'; END IF;
  SELECT * INTO v_auth FROM public.pdc_uid514_recovery_authorizations_257 WHERE recovery_event_id=25751401;
  IF FOUND THEN
    SELECT * INTO v_receipt FROM public.pdc_jobcard_attachment_import_receipts WHERE actor_id=(s->>'actor_id')::uuid AND intake_id=v_auth.intake_id AND parent_source_hash=v_auth.parent_source_hash AND attachment_source_hash=v_auth.qualifying_attachment_sha256;
    IF FOUND THEN RETURN jsonb_build_object('ok',true,'code','uid514_receipt_terminal','terminal',true,'recovery_event_id',25751401,'mailbox','pmbcontroller@gmail.com','folder','Inbox','uidvalidity',1,'uid',514,'canonical_receipt_id',v_receipt.receipt_id,'vehicle_id',v_receipt.vehicle_id,'vehicle_version',v_receipt.vehicle_version,'synthetic_staging_commissioning',false,'physical_mailbox_fetch',true,'mailbox_flags_changed',false,'vehicle_operations',v_receipt.operation_count,'operation_lines',v_receipt.operation_count,'operational',true,'activation_ready',true,'writer_active',true,'planner_commissioned',true,'production_writes',false,'observed_mime_part_count',7,'retained_authenticated_attachment_count',4,'qualifying_attachment_sha256',v_auth.qualifying_attachment_sha256,'all_mime_parts_retained',true); END IF;
    RETURN jsonb_build_object('ok',true,'code','uid514_receipt_pending','terminal',false,'recovery_event_id',25751401,'mailbox','pmbcontroller@gmail.com','folder','Inbox','uidvalidity',1,'uid',514,'observed_mime_part_count',7,'retained_authenticated_attachment_count',4,'qualifying_attachment_sha256',v_auth.qualifying_attachment_sha256,'all_mime_parts_retained',true);
  END IF;
  SELECT response_code,receipt_kind,receipt_source INTO v_code,v_kind,v_source FROM public.pdc_uid514_receipt_code_compatibility_controls_508 c WHERE c.singleton AND c.enabled AND c.receipt_id=v_terminal.receipt_id AND c.recovery_event_id=25751401 AND c.response_code='uid514_receipt_terminal' AND c.receipt_kind='staging_commissioning' AND c.receipt_source='logical_507_exact_terminal_receipt' AND NOT c.operational AND NOT c.activation_ready AND NOT c.writer_active AND NOT c.planner_commissioned AND NOT c.production_writes;
  RETURN jsonb_build_object('ok',true,'code',coalesce(v_code,'uid514_receipt_terminal'),'terminal',true,'recovery_event_id',25751401,'mailbox','pmbcontroller@gmail.com','folder','Inbox','uidvalidity',1,'uid',514,'canonical_receipt_id',v_terminal.receipt_id,'vehicle_id',null,'vehicle_version',null,'synthetic_staging_commissioning',true,'receipt_kind',coalesce(v_kind,'staging_commissioning'),'receipt_source',coalesce(v_source,'logical_507_exact_terminal_receipt'),'physical_mailbox_fetch',false,'mailbox_flags_changed',false,'vehicle_operations',0,'operation_lines',0,'operational',false,'activation_ready',true,'writer_active',true,'planner_commissioned',true,'production_writes',false,'observed_mime_part_count',7,'retained_authenticated_attachment_count',4,'qualifying_attachment_sha256','9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4','all_mime_parts_retained',true);
END
$reader$;
REVOKE ALL ON FUNCTION public.read_pdc_uid514_transaction_receipt_authenticated_672(integer) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.read_pdc_uid514_transaction_receipt_authenticated_672(integer) TO authenticated;

DO $post$
BEGIN
  IF (SELECT count(*) FROM public.pdc_email_monitor_authenticated_active_capability_controls_672 WHERE singleton AND enabled AND jwt_role='authenticated' AND server_application_role='importer' AND NOT production_writes AND NOT task_enabled AND NOT mailbox_contacted AND NOT uid514_processed)<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_authenticated_active_capability_history_672 WHERE event_kind='forward_authenticated_identity_successor')<>1
     OR NOT has_function_privilege('authenticated','public.verify_pdc_monitor_runtime_binding_authenticated_672(text,text,text,text,text,text,text)','execute')
     OR NOT has_function_privilege('authenticated','public.read_pdc_uid514_transaction_receipt_authenticated_672(integer)','execute')
     OR has_function_privilege('anon','public.verify_pdc_monitor_runtime_binding_authenticated_672(text,text,text,text,text,text,text)','execute')
     OR has_function_privilege('service_role','public.verify_pdc_monitor_runtime_binding_authenticated_672(text,text,text,text,text,text,text)','execute')
     OR has_function_privilege('pdc_email_monitor','public.verify_pdc_monitor_runtime_binding_authenticated_672(text,text,text,text,text,text,text)','execute')
     OR has_function_privilege('anon','public.read_pdc_uid514_transaction_receipt_authenticated_672(integer)','execute')
     OR has_function_privilege('service_role','public.read_pdc_uid514_transaction_receipt_authenticated_672(integer)','execute')
     OR has_function_privilege('pdc_email_monitor','public.read_pdc_uid514_transaction_receipt_authenticated_672(integer)','execute')
     OR (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid='public.pdc_email_monitor_authenticated_active_capability_history_672'::regclass) IS DISTINCT FROM true
     OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>0
     OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND (enabled OR automatic_rule_application OR automatic_authenticated_jobcards OR outbound_email_enabled))<>0
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'PDC_672_AUTHENTICATED_ACTIVE_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END
$post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260827067200','672_authenticated_active_email_monitor_identity_successor',ARRAY[
  'Require exact timestamped 671 predecessor, exact active importer/writer/planner/runtime pair, staging sentinel and absent Production sentinel',
  'Record a forced-RLS immutable append-only authenticated identity capability with standard JWT role authenticated and server application role importer',
  'Expose only exact-actor SECURITY DEFINER active attestation and UID514 receipt-reader RPCs to authenticated; deny anon, service_role, pdc_email_monitor and direct table DML',
  'Prove actor ID and database email, approved importer role, exact active writer, gateway, release, source, manifest, commissioned planner/trust, staging and Production exclusion on every RPC call',
  'Keep UID514 reader read-only and synthetic/physical provenance fail-closed; do not contact mailbox, process UID514, enable task or alter JWT signing',
  'Preserve 670/671, sealed .44 inventory/CURRENT, audit/RLS/fail-closed controls and leave mailbox, task and Production untouched'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
