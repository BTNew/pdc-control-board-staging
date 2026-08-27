-- STAGING ONLY 670: commission the exact .44 actor capability and reconcile
-- the retained UID514 seven-part MIME contract. This does not start a task,
-- fetch a mailbox, process UID514, send email, or write Production.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-670-email-monitor-active-capability',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260827066000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827066000' AND name='508_uid514_receipt_code_compatibility')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260827066000')<>0
     OR to_regclass('public.pdc_email_monitor_active_capability_controls_670') IS NOT NULL
     OR to_regclass('public.pdc_email_monitor_active_capability_history_670') IS NOT NULL
     OR to_regprocedure('public.admin_rollback_pdc_email_monitor_active_capability_670(text)') IS NOT NULL
     OR to_regprocedure('public.pdc_email_monitor_active_capability_visible_670()') IS NOT NULL
     OR (SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') FROM pg_proc p WHERE p.oid='public.read_pdc_uid514_transaction_receipt_257(integer)'::regprocedure)<>'7666a61158aaeb1012184231d58e9bdf8e620bfaec2427dabc1aefdd11aaebad'
     OR (SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') FROM pg_proc p WHERE p.oid='public.pdc_monitor_actor_scope()'::regprocedure)<>'55b6e195304992cf4a453d78f628d2591964c343317461b96c51e1df04aa6485'
     OR NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='pdc_email_monitor')
     OR NOT EXISTS(SELECT 1 FROM pg_auth_members am JOIN pg_roles r ON r.oid=am.roleid JOIN pg_roles m ON m.oid=am.member WHERE r.rolname='pdc_email_monitor' AND m.rolname='authenticator' AND NOT am.admin_option)
     OR (SELECT count(*) FROM public.pdc_monitor_runtime_bindings_255 WHERE singleton AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND gateway_instance_id='pdc-monitor-staging-sales-uid509-v1' AND release_name='pdc-monitor-staging-m502-2026.08.44' AND source_sha='e850c319989d98b45b95a28aa815d78e2c2e3a4b' AND manifest_sha256='d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d' AND semantic_planner_sha256 IS NULL AND semantic_planner_trust_receipt_sha256 IS NULL AND semantic_planner_commissioned_at IS NULL)<>1
     OR (SELECT count(*) FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)<>0
     OR (SELECT count(*) FROM public.pdc_user_roles WHERE auth_user_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND lower(email)='sales@broometoyota.com.au' AND active AND account_status='approved' AND role::text='viewer')<>1
     OR (SELECT count(*) FROM public.pdc_uid514_recovery_authorizations_257 WHERE recovery_event_id=25751401)<>0
     OR NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.pdc_uid514_recovery_authorizations_257'::regclass AND conname='pdc_uid514_recovery_authorizations_257_attachment_count_check' AND pg_get_constraintdef(oid) LIKE '%attachment_count = 7%')
     OR position('v_count<>7' IN pg_get_functiondef('public.authorize_pdc_uid514_retained_intake_257(uuid,integer)'::regprocedure))=0
     OR position('25751401' IN pg_get_functiondef('public.authorize_pdc_uid514_retained_intake_257(uuid,integer)'::regprocedure))=0
  THEN RAISE EXCEPTION 'PDC_670_EXACT_508_PREDECESSOR_OR_COLLISION_MISMATCH' USING errcode='55000'; END IF;
END
$guard$;

CREATE TABLE public.pdc_email_monitor_active_capability_controls_670(
  singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
  enabled boolean NOT NULL DEFAULT true,
  actor_id uuid NOT NULL,
  actor_email text NOT NULL CHECK(actor_email='sales@broometoyota.com.au'),
  gateway_instance_id text NOT NULL,
  release_name text NOT NULL,
  source_sha text NOT NULL,
  manifest_sha256 text NOT NULL,
  planner_interface text NOT NULL CHECK(planner_interface='pmb-pdc-agentic-email-plan-v1'),
  planner_sha256 text NOT NULL CHECK(planner_sha256='d3ee4933b380cfce2712ff8804419a35f9d33d6039c1dcd3653d1fb6f923c09a'),
  trust_receipt_sha256 text NOT NULL CHECK(trust_receipt_sha256='639148337b6f9708479e5a03f7fb6894665cb4372d27072087e4c777bc54bc65'),
  trust_receipt jsonb NOT NULL,
  capability_active boolean NOT NULL DEFAULT true CHECK(capability_active),
  writer_active boolean NOT NULL DEFAULT true CHECK(writer_active),
  planner_commissioned boolean NOT NULL DEFAULT true CHECK(planner_commissioned),
  activation_ready boolean NOT NULL DEFAULT true CHECK(activation_ready),
  windows_monitor_enabled boolean NOT NULL DEFAULT false CHECK(NOT windows_monitor_enabled),
  outbound_email_enabled boolean NOT NULL DEFAULT false CHECK(NOT outbound_email_enabled),
  production_writes boolean NOT NULL DEFAULT false CHECK(NOT production_writes),
  observed_mime_part_count integer NOT NULL DEFAULT 7 CHECK(observed_mime_part_count=7),
  retained_authenticated_attachment_count integer NOT NULL DEFAULT 4 CHECK(retained_authenticated_attachment_count=4),
  qualifying_attachment_sha256 text NOT NULL CHECK(qualifying_attachment_sha256='9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4'),
  all_mime_parts_retained boolean NOT NULL DEFAULT true CHECK(all_mime_parts_retained),
  changed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_email_monitor_active_capability_controls_670 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_monitor_active_capability_controls_670 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_email_monitor_active_capability_controls_670 FROM public,anon,authenticated,service_role,pdc_email_monitor;

CREATE TABLE public.pdc_email_monitor_active_capability_history_670(
  history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key text NOT NULL UNIQUE,
  event_kind text NOT NULL CHECK(event_kind IN('forward_capability','rollback')),
  actor_id uuid NOT NULL,
  actor_email text NOT NULL,
  gateway_instance_id text NOT NULL,
  release_name text NOT NULL,
  source_sha text NOT NULL,
  manifest_sha256 text NOT NULL,
  planner_interface text NOT NULL,
  planner_sha256 text NOT NULL,
  trust_receipt_sha256 text NOT NULL,
  before_role text NOT NULL,
  after_role text NOT NULL,
  before_writer_active boolean NOT NULL,
  after_writer_active boolean NOT NULL,
  before_reader_active boolean NOT NULL,
  after_reader_active boolean NOT NULL,
  before_planner_commissioned boolean NOT NULL,
  after_planner_commissioned boolean NOT NULL,
  observed_mime_part_count integer NOT NULL CHECK(observed_mime_part_count=7),
  retained_authenticated_attachment_count integer NOT NULL CHECK(retained_authenticated_attachment_count=4),
  qualifying_attachment_sha256 text NOT NULL CHECK(qualifying_attachment_sha256='9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4'),
  all_mime_parts_retained boolean NOT NULL CHECK(all_mime_parts_retained),
  before_state jsonb NOT NULL,
  after_state jsonb NOT NULL,
  performed_by uuid,
  performed_by_email text,
  rollback_contract text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE FUNCTION public.pdc_email_monitor_active_capability_history_immutable_670()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public
AS $immutable$ BEGIN RAISE EXCEPTION 'PDC_670_ACTIVE_CAPABILITY_HISTORY_IMMUTABLE' USING errcode='55000'; END $immutable$;
CREATE TRIGGER pdc_email_monitor_active_capability_history_immutable_670
BEFORE UPDATE OR DELETE ON public.pdc_email_monitor_active_capability_history_670
FOR EACH ROW EXECUTE FUNCTION public.pdc_email_monitor_active_capability_history_immutable_670();
ALTER TABLE public.pdc_email_monitor_active_capability_history_670 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_monitor_active_capability_history_670 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_email_monitor_active_capability_history_670 FROM public,anon,authenticated,service_role,pdc_email_monitor;

INSERT INTO public.pdc_email_monitor_active_capability_controls_670(
  actor_id,actor_email,gateway_instance_id,release_name,source_sha,manifest_sha256,
  planner_interface,planner_sha256,trust_receipt_sha256,trust_receipt,qualifying_attachment_sha256)
VALUES(
  'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b','sales@broometoyota.com.au',
  'pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44',
  'e850c319989d98b45b95a28aa815d78e2c2e3a4b',
  'd48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d',
  'pmb-pdc-agentic-email-plan-v1',
  'd3ee4933b380cfce2712ff8804419a35f9d33d6039c1dcd3653d1fb6f923c09a',
  '639148337b6f9708479e5a03f7fb6894665cb4372d27072087e4c777bc54bc65',
  '{"approved_at":"2026-08-27T05:03:14Z","approved_by":"Craig Watson","contract":"pdc-active-semantic-planner-trust-v1","planner_interface":"pmb-pdc-agentic-email-plan-v1","planner_sha256":"d3ee4933b380cfce2712ff8804419a35f9d33d6039c1dcd3653d1fb6f923c09a","release_series":"pdc-monitor-staging-m502"}'::jsonb,
  '9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4');

DO $activate$
DECLARE
  v_role public.pdc_user_roles%rowtype;
  v_writer public.pdc_monitor_stage_activation_writers%rowtype;
  v_reader public.pdc_monitor_vehicle_identity_readers%rowtype;
  v_binding public.pdc_monitor_runtime_bindings_255%rowtype;
  v_before_role jsonb; v_after_role jsonb; v_before_writer jsonb; v_after_writer jsonb;
  v_before_reader jsonb; v_after_reader jsonb; v_before_binding jsonb; v_after_binding jsonb; v_event_key text;
BEGIN
  SELECT * INTO v_role FROM public.pdc_user_roles
   WHERE auth_user_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND lower(email)='sales@broometoyota.com.au'
     AND active AND account_status='approved' AND role::text='viewer' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_670_SALES_VIEWER_PRESTATE_MISMATCH' USING errcode='42501'; END IF;
  SELECT * INTO v_writer FROM public.pdc_monitor_stage_activation_writers
   WHERE user_id=v_role.auth_user_id AND NOT active AND revoked_at IS NOT NULL FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_670_SALES_WRITER_PRESTATE_MISMATCH' USING errcode='42501'; END IF;
  SELECT * INTO v_reader FROM public.pdc_monitor_vehicle_identity_readers
   WHERE user_id=v_role.auth_user_id AND active AND revoked_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_670_SALES_READER_PRESTATE_MISMATCH' USING errcode='42501'; END IF;
  SELECT * INTO v_binding FROM public.pdc_monitor_runtime_bindings_255
   WHERE singleton AND actor_id=v_role.auth_user_id AND gateway_instance_id='pdc-monitor-staging-sales-uid509-v1'
     AND release_name='pdc-monitor-staging-m502-2026.08.44'
     AND source_sha='e850c319989d98b45b95a28aa815d78e2c2e3a4b'
     AND manifest_sha256='d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d'
     AND semantic_planner_sha256 IS NULL AND semantic_planner_trust_receipt_sha256 IS NULL
     AND semantic_planner_commissioned_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_670_BINDING_PRESTATE_MISMATCH' USING errcode='55000'; END IF;
  v_before_role:=to_jsonb(v_role); v_before_writer:=to_jsonb(v_writer); v_before_reader:=to_jsonb(v_reader); v_before_binding:=to_jsonb(v_binding);

  UPDATE public.pdc_user_roles SET role='importer',notes=left(btrim(coalesce(notes,''))||' | Craig-authorised .44 active staging capability 670',1000),updated_at=clock_timestamp()
   WHERE id=v_role.id RETURNING * INTO v_role;
  UPDATE public.pdc_monitor_stage_activation_writers SET active=true,revoked_at=NULL,reason='Craig-authorised staging Email Bot 2026.08.44 activation acceptance',granted_at=clock_timestamp()
   WHERE user_id=v_writer.user_id RETURNING * INTO v_writer;

  UPDATE public.pdc_monitor_runtime_bindings_255 SET
    semantic_planner_sha256='d3ee4933b380cfce2712ff8804419a35f9d33d6039c1dcd3653d1fb6f923c09a',
    semantic_planner_trust_receipt_sha256='639148337b6f9708479e5a03f7fb6894665cb4372d27072087e4c777bc54bc65',
    semantic_planner_commissioned_at=clock_timestamp(),provisioned_at=clock_timestamp()
   WHERE binding_id=v_binding.binding_id AND singleton AND actor_id=v_binding.actor_id
     AND semantic_planner_sha256 IS NULL AND semantic_planner_trust_receipt_sha256 IS NULL AND semantic_planner_commissioned_at IS NULL
   RETURNING * INTO v_binding;
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_670_BINDING_CONCURRENT_DRIFT' USING errcode='40001'; END IF;
  v_after_role:=to_jsonb(v_role); v_after_writer:=to_jsonb(v_writer); v_after_reader:=to_jsonb(v_reader); v_after_binding:=to_jsonb(v_binding);
  v_event_key:=encode(extensions.digest(convert_to('pdc-staging-670-email-monitor-active-capability|forward|'||v_binding.binding_id::text,'UTF8'),'sha256'),'hex');
  INSERT INTO public.pdc_email_monitor_active_capability_history_670(
    event_key,event_kind,actor_id,actor_email,gateway_instance_id,release_name,source_sha,manifest_sha256,
    planner_interface,planner_sha256,trust_receipt_sha256,before_role,after_role,before_writer_active,after_writer_active,before_reader_active,after_reader_active,
    before_planner_commissioned,after_planner_commissioned,observed_mime_part_count,retained_authenticated_attachment_count,
    qualifying_attachment_sha256,all_mime_parts_retained,before_state,after_state,rollback_contract)
  VALUES(v_event_key,'forward_capability',v_binding.actor_id,'sales@broometoyota.com.au',v_binding.gateway_instance_id,v_binding.release_name,v_binding.source_sha,v_binding.manifest_sha256,
    'pmb-pdc-agentic-email-plan-v1','d3ee4933b380cfce2712ff8804419a35f9d33d6039c1dcd3653d1fb6f923c09a','639148337b6f9708479e5a03f7fb6894665cb4372d27072087e4c777bc54bc65',
    'viewer','importer',false,true,true,true,false,true,7,4,'9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4',true,
    jsonb_build_object('role',v_before_role,'writer',v_before_writer,'reader',v_before_reader,'binding',v_before_binding),
    jsonb_build_object('role',v_after_role,'writer',v_after_writer,'reader',v_after_reader,'binding',v_after_binding),
    'forward capability only; rollback restores viewer role, inactive writer/reader and null planner binding; no task or mailbox action');
  INSERT INTO public.audit_events(action,table_name,row_id,actor_id,actor_email,before_data,after_data,metadata)
  VALUES('role_change','pdc_user_roles',v_role.id,NULL,'staging-management-remediation',v_before_role,v_after_role,
    jsonb_build_object('event_type','pdc_email_monitor_active_capability_commissioned_670','authorized_by','Craig Watson','actor_id',v_binding.actor_id,'role_before','viewer','role_after','importer','production_untouched',true,'windows_monitor_enabled',false,'observed_mime_part_count',7,'retained_authenticated_attachment_count',4));
END
$activate$;

CREATE OR REPLACE FUNCTION public.read_pdc_uid514_transaction_receipt_257(p_recovery_event_id integer)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,auth AS $reader$
DECLARE
  v_actor_id uuid:=auth.uid(); v_actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_binding public.pdc_monitor_runtime_bindings_255%rowtype; v_auth public.pdc_uid514_recovery_authorizations_257%rowtype;
  v_receipt public.pdc_jobcard_attachment_import_receipts%rowtype; v_terminal public.pdc_uid514_staging_commissioning_terminal_receipts_507%rowtype;
  v_code text; v_kind text; v_source text;
  v_active boolean:=false;
BEGIN
  IF p_recovery_event_id<>25751401 THEN RAISE EXCEPTION 'PDC_261_UID514_SCOPE_INVALID' USING errcode='22023'; END IF;
  IF public.pdc_monitor_staging_guard() AND v_actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'::uuid THEN
    SELECT * INTO v_binding FROM public.pdc_monitor_runtime_bindings_255 WHERE singleton;
    IF coalesce(auth.jwt()->>'role','')='pdc_email_monitor'
       AND v_actor_email='sales@broometoyota.com.au'
       AND EXISTS(SELECT 1 FROM auth.users u WHERE u.id=v_actor_id AND lower(u.email)=v_actor_email AND coalesce(u.raw_app_meta_data->>'pdc_identity_type','')='non_human_monitor')
       AND (SELECT count(*) FROM public.pdc_user_roles r WHERE r.auth_user_id=v_actor_id AND lower(r.email)=v_actor_email AND r.active AND r.account_status='approved' AND r.role::text='importer')=1
       AND (SELECT count(*) FROM public.pdc_user_roles r WHERE r.auth_user_id=v_actor_id AND r.active)=1
       AND (SELECT count(*) FROM public.pdc_monitor_stage_activation_writers w WHERE w.user_id=v_actor_id AND w.active AND w.revoked_at IS NULL)=1
       AND NOT EXISTS(SELECT 1 FROM public.pdc_auditor_worker_identities w WHERE w.auth_user_id=v_actor_id AND w.active)
       AND NOT EXISTS(SELECT 1 FROM public.pdc_auditor_user_dealer_scopes s WHERE s.auth_user_id=v_actor_id AND s.active)
       AND NOT EXISTS(SELECT 1 FROM public.pdc_auditor_executor_identities e WHERE e.auth_user_id=v_actor_id AND e.active AND e.expires_at>clock_timestamp())
       AND NOT EXISTS(SELECT 1 FROM public.pdc_auditor_service_identities_225 s WHERE s.auth_user_id=v_actor_id AND s.active)
       AND v_binding.actor_id=v_actor_id AND v_binding.gateway_instance_id='pdc-monitor-staging-sales-uid509-v1'
       AND v_binding.release_name='pdc-monitor-staging-m502-2026.08.44'
       AND v_binding.source_sha='e850c319989d98b45b95a28aa815d78e2c2e3a4b'
       AND v_binding.manifest_sha256='d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d'
       AND v_binding.semantic_planner_sha256='d3ee4933b380cfce2712ff8804419a35f9d33d6039c1dcd3653d1fb6f923c09a'
       AND v_binding.semantic_planner_trust_receipt_sha256='639148337b6f9708479e5a03f7fb6894665cb4372d27072087e4c777bc54bc65'
       AND v_binding.semantic_planner_commissioned_at IS NOT NULL THEN v_active:=true;
    END IF;
    IF NOT v_active THEN
      IF coalesce(auth.jwt()->>'role','')<>'authenticated' OR v_actor_email<>'sales@broometoyota.com.au'
         OR NOT EXISTS(SELECT 1 FROM auth.users u WHERE u.id=v_actor_id AND lower(u.email)=v_actor_email AND coalesce(u.raw_app_meta_data->>'pdc_identity_type','')='non_human_monitor')
         OR (SELECT count(*) FROM public.pdc_user_roles r WHERE r.auth_user_id=v_actor_id AND lower(r.email)=v_actor_email AND r.active AND r.account_status='approved' AND r.role::text='viewer')<>1
         OR (SELECT count(*) FROM public.pdc_user_roles r WHERE r.auth_user_id=v_actor_id AND r.active)<>1
         OR (SELECT count(*) FROM public.pdc_monitor_stage_activation_writers w WHERE w.active AND w.revoked_at IS NULL)<>0
         OR EXISTS(SELECT 1 FROM public.pdc_auditor_worker_identities w WHERE w.auth_user_id=v_actor_id AND w.active)
         OR EXISTS(SELECT 1 FROM public.pdc_auditor_user_dealer_scopes s WHERE s.auth_user_id=v_actor_id AND s.active)
         OR EXISTS(SELECT 1 FROM public.pdc_auditor_executor_identities e WHERE e.auth_user_id=v_actor_id AND e.active AND e.expires_at>clock_timestamp())
         OR EXISTS(SELECT 1 FROM public.pdc_auditor_service_identities_225 s WHERE s.auth_user_id=v_actor_id AND s.active)
         OR v_binding.actor_id<>v_actor_id OR v_binding.semantic_planner_sha256 IS NOT NULL OR v_binding.semantic_planner_trust_receipt_sha256 IS NOT NULL OR v_binding.semantic_planner_commissioned_at IS NOT NULL
      THEN RAISE EXCEPTION 'PDC_670_ACTIVE_OR_CONTAINED_IDENTITY_MISMATCH' USING errcode='42501'; END IF;
    END IF;
    IF (SELECT enabled FROM public.pdc_monitor_uid514_reader_compatibility_controls_506 WHERE singleton) IS DISTINCT FROM true THEN RAISE EXCEPTION 'PDC_506_READER_COMPATIBILITY_DISABLED' USING errcode='55000'; END IF;
    SELECT r.* INTO v_terminal FROM public.pdc_uid514_staging_commissioning_terminal_receipts_507 r
     JOIN public.pdc_uid514_staging_commissioning_controls_507 c ON c.singleton AND c.enabled
     WHERE r.recovery_event_id=25751401 AND r.actor_id=v_actor_id AND r.gateway_instance_id='pdc-monitor-staging-sales-uid509-v1'
       AND r.release_name='pdc-monitor-staging-m502-2026.08.44' AND r.source_sha='e850c319989d98b45b95a28aa815d78e2c2e3a4b'
       AND r.source_tree_sha='8981540501bc629e189c39c9ea8a9adf3165d397' AND r.manifest_sha256='d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d'
       AND r.archive_sha256='4ba4d827839f6dfe1835110719f0906a8b9345b0e41b653f96269abdeaccbf90'
       AND r.synthetic_staging_commissioning AND NOT r.physical_mailbox_fetch AND NOT r.mailbox_flags_changed
       AND r.vehicle_operations=0 AND r.operation_lines=0 AND NOT r.operational AND NOT r.activation_ready AND NOT r.writer_active AND NOT r.planner_commissioned AND NOT r.production_writes;
    IF NOT FOUND THEN RAISE EXCEPTION 'PDC_670_UID514_TERMINAL_RECEIPT_MISSING' USING errcode='55000'; END IF;
    IF v_active THEN
      SELECT * INTO v_auth FROM public.pdc_uid514_recovery_authorizations_257 WHERE recovery_event_id=25751401;
      IF FOUND THEN
        SELECT * INTO v_receipt FROM public.pdc_jobcard_attachment_import_receipts WHERE actor_id=v_actor_id AND intake_id=v_auth.intake_id AND parent_source_hash=v_auth.parent_source_hash AND attachment_source_hash=v_auth.qualifying_attachment_sha256;
        IF FOUND THEN
          RETURN jsonb_build_object('ok',true,'code','uid514_receipt_terminal','terminal',true,'recovery_event_id',25751401,'mailbox','pmbcontroller@gmail.com','folder','Inbox','uidvalidity',1,'uid',514,'parent_source_hash',v_auth.parent_source_hash,'canonical_receipt_id',v_receipt.receipt_id,'vehicle_id',v_receipt.vehicle_id,'vehicle_version',v_receipt.vehicle_version,'synthetic_staging_commissioning',false,'physical_mailbox_fetch',true,'mailbox_flags_changed',false,'vehicle_operations',v_receipt.operation_count,'operation_lines',v_receipt.operation_count,'operational',true,'activation_ready',true,'writer_active',true,'planner_commissioned',true,'production_writes',false,'observed_mime_part_count',7,'retained_authenticated_attachment_count',4,'qualifying_attachment_sha256',v_auth.qualifying_attachment_sha256,'all_mime_parts_retained',true);
        END IF;
        RETURN jsonb_build_object('ok',true,'code','uid514_receipt_pending','terminal',false,'recovery_event_id',25751401,'mailbox','pmbcontroller@gmail.com','folder','Inbox','uidvalidity',1,'uid',514,'parent_source_hash',v_auth.parent_source_hash,'observed_mime_part_count',7,'retained_authenticated_attachment_count',4,'qualifying_attachment_sha256',v_auth.qualifying_attachment_sha256,'all_mime_parts_retained',true);
      END IF;
      SELECT response_code,receipt_kind,receipt_source INTO v_code,v_kind,v_source FROM public.pdc_uid514_receipt_code_compatibility_controls_508 c WHERE c.singleton AND c.enabled AND c.receipt_id=v_terminal.receipt_id AND c.recovery_event_id=25751401 AND c.response_code='uid514_receipt_terminal' AND c.receipt_kind='staging_commissioning' AND c.receipt_source='logical_507_exact_terminal_receipt' AND NOT c.operational AND NOT c.activation_ready AND NOT c.writer_active AND NOT c.planner_commissioned AND NOT c.production_writes;
      RETURN jsonb_build_object('ok',true,'code',coalesce(v_code,'uid514_receipt_terminal'),'terminal',true,'recovery_event_id',25751401,'mailbox','pmbcontroller@gmail.com','folder','Inbox','uidvalidity',1,'uid',514,'canonical_receipt_id',v_terminal.receipt_id,'vehicle_id',null,'vehicle_version',null,'synthetic_staging_commissioning',true,'receipt_kind',coalesce(v_kind,'staging_commissioning'),'receipt_source',coalesce(v_source,'logical_507_exact_terminal_receipt'),'physical_mailbox_fetch',false,'mailbox_flags_changed',false,'vehicle_operations',0,'operation_lines',0,'operational',false,'activation_ready',true,'writer_active',true,'planner_commissioned',true,'production_writes',false,'observed_mime_part_count',7,'retained_authenticated_attachment_count',4,'qualifying_attachment_sha256','9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4','all_mime_parts_retained',true);
    END IF;
    RETURN jsonb_build_object('ok',true,'code','uid514_receipt_terminal','terminal',true,'recovery_event_id',25751401,'mailbox','pmbcontroller@gmail.com','folder','Inbox','uidvalidity',1,'uid',514,'canonical_receipt_id',v_terminal.receipt_id,'vehicle_id',null,'vehicle_version',null,'synthetic_staging_commissioning',true,'receipt_kind','staging_commissioning','receipt_source','logical_507_exact_terminal_receipt','physical_mailbox_fetch',false,'mailbox_flags_changed',false,'vehicle_operations',0,'operation_lines',0,'operational',false,'activation_ready',false,'writer_active',false,'planner_commissioned',false,'production_writes',false,'observed_mime_part_count',7,'retained_authenticated_attachment_count',4,'qualifying_attachment_sha256','9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4','all_mime_parts_retained',true);
  END IF;
  PERFORM public.pdc_monitor_actor_scope();
  SELECT * INTO v_auth FROM public.pdc_uid514_recovery_authorizations_257 WHERE recovery_event_id=25751401;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',true,'code','uid514_authorization_pending','terminal',false,'recovery_event_id',25751401,'mailbox','pmbcontroller@gmail.com','folder','Inbox','uidvalidity',1,'uid',514); END IF;
  SELECT * INTO v_receipt FROM public.pdc_jobcard_attachment_import_receipts WHERE actor_id=v_actor_id AND intake_id=v_auth.intake_id AND parent_source_hash=v_auth.parent_source_hash AND attachment_source_hash=v_auth.qualifying_attachment_sha256;
  RETURN jsonb_build_object('ok',true,'code',case when found then 'uid514_receipt_terminal' else 'uid514_receipt_pending' end,'terminal',found,'recovery_event_id',25751401,'mailbox',v_auth.mailbox_address,'folder',v_auth.mailbox_folder,'uidvalidity',1,'uid',514,'parent_source_hash',v_auth.parent_source_hash,'canonical_receipt_id',case when found then v_receipt.receipt_id else null end,'vehicle_id',case when found then v_receipt.vehicle_id else null end,'vehicle_version',case when found then v_receipt.vehicle_version else null end);
END
$reader$;

REVOKE ALL ON FUNCTION public.read_pdc_uid514_transaction_receipt_257(integer) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.read_pdc_uid514_transaction_receipt_257(integer) TO authenticated,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.verify_pdc_monitor_runtime_binding_503(text,text,text,text,text,text,text) TO pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.authorize_pdc_uid514_retained_intake_257(uuid,integer),public.claim_pdc_uid514_recovery_257(text,integer),public.import_pdc_monitor_jobcard_attachment_279(text,uuid,uuid,text,text,jsonb,jsonb,jsonb,jsonb),public.read_pdc_monitor_jobcard_attachment_receipt_279(text,uuid) TO pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.record_pdc_email_monitor_cycle(text,text,text),public.get_pdc_monitor_intake_attachments(uuid,uuid,text),public.heartbeat_pdc_email_intake_claim(uuid,uuid,text),public.record_pdc_email_intake_result(uuid,uuid,text,boolean,jsonb,text,text,boolean,jsonb) TO pdc_email_monitor;

CREATE FUNCTION public.admin_rollback_pdc_email_monitor_active_capability_670(p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,auth AS $rollback$
DECLARE
  v_admin uuid:=auth.uid(); v_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); v_count integer;
  c public.pdc_email_monitor_active_capability_controls_670%rowtype; h public.pdc_email_monitor_active_capability_history_670%rowtype;
  r public.pdc_user_roles%rowtype; w public.pdc_monitor_stage_activation_writers%rowtype; v_reader public.pdc_monitor_vehicle_identity_readers%rowtype; b public.pdc_monitor_runtime_bindings_255%rowtype;
  before_state jsonb; after_state jsonb; event_key text;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR v_admin IS NULL OR coalesce(auth.jwt()->>'role','')<>'authenticated' OR length(btrim(coalesce(p_reason,'')))<10 THEN RAISE EXCEPTION 'PDC_670_ADMIN_AUTHORITY_REQUIRED' USING errcode='42501'; END IF;
  SELECT count(*) INTO v_count FROM public.pdc_user_roles r0 JOIN auth.users u ON u.id=r0.auth_user_id AND lower(u.email)=v_email WHERE r0.auth_user_id=v_admin AND lower(r0.email)=v_email AND r0.active AND r0.account_status='approved' AND r0.role::text='administrator';
  IF v_count<>1 THEN RAISE EXCEPTION 'PDC_670_ADMIN_AUTHORITY_REQUIRED' USING errcode='42501'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-staging-670-email-monitor-active-capability',0));
  SELECT * INTO c FROM public.pdc_email_monitor_active_capability_controls_670 WHERE singleton FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_670_CAPABILITY_CONTROL_MISSING' USING errcode='55000'; END IF;
  SELECT * INTO h FROM public.pdc_email_monitor_active_capability_history_670 WHERE event_kind='rollback' ORDER BY created_at DESC,history_id DESC LIMIT 1;
  IF FOUND THEN IF c.enabled THEN RAISE EXCEPTION 'PDC_670_ROLLBACK_STATE_DRIFT' USING errcode='55000'; END IF; RETURN jsonb_build_object('ok',true,'code','pdc_email_monitor_active_capability_rolled_back_670','idempotent',true,'history_id',h.history_id,'production_writes',false,'windows_monitor_enabled',false); END IF;
  SELECT * INTO r FROM public.pdc_user_roles WHERE auth_user_id=c.actor_id AND lower(email)=c.actor_email AND active AND account_status='approved' FOR UPDATE;
  SELECT * INTO w FROM public.pdc_monitor_stage_activation_writers WHERE user_id=c.actor_id FOR UPDATE;
  SELECT * INTO v_reader FROM public.pdc_monitor_vehicle_identity_readers WHERE user_id=c.actor_id FOR UPDATE;
  SELECT * INTO b FROM public.pdc_monitor_runtime_bindings_255 WHERE singleton AND actor_id=c.actor_id FOR UPDATE;
  IF NOT FOUND OR r.role::text<>'importer' OR NOT w.active OR w.revoked_at IS NOT NULL OR NOT v_reader.active OR v_reader.revoked_at IS NOT NULL OR b.semantic_planner_sha256<>c.planner_sha256 OR b.semantic_planner_trust_receipt_sha256<>c.trust_receipt_sha256 OR b.semantic_planner_commissioned_at IS NULL THEN RAISE EXCEPTION 'PDC_670_ROLLBACK_SCOPE_MISMATCH' USING errcode='55000'; END IF;
  before_state:=jsonb_build_object('role',to_jsonb(r),'writer',to_jsonb(w),'reader',to_jsonb(v_reader),'binding',to_jsonb(b));
  UPDATE public.pdc_monitor_runtime_bindings_255 SET semantic_planner_sha256=NULL,semantic_planner_trust_receipt_sha256=NULL,semantic_planner_commissioned_at=NULL,provisioned_at=clock_timestamp() WHERE binding_id=b.binding_id;
  UPDATE public.pdc_monitor_stage_activation_writers SET active=false,revoked_at=clock_timestamp(),reason='670 capability rollback: '||left(btrim(p_reason),700) WHERE user_id=c.actor_id RETURNING * INTO w;
  UPDATE public.pdc_user_roles SET role='viewer',notes=left(btrim(coalesce(notes,''))||' | 670 capability rollback',1000),updated_at=clock_timestamp() WHERE id=r.id RETURNING * INTO r;
  SELECT * INTO b FROM public.pdc_monitor_runtime_bindings_255 WHERE binding_id=b.binding_id;
  SELECT * INTO v_reader FROM public.pdc_monitor_vehicle_identity_readers WHERE user_id=c.actor_id;
  after_state:=jsonb_build_object('role',to_jsonb(r),'writer',to_jsonb(w),'reader',to_jsonb(v_reader),'binding',to_jsonb(b));
  UPDATE public.pdc_email_monitor_active_capability_controls_670 SET enabled=false WHERE singleton;
  event_key:=encode(extensions.digest(convert_to('pdc-staging-670-email-monitor-active-capability|rollback|'||c.actor_id::text,'UTF8'),'sha256'),'hex');
  INSERT INTO public.pdc_email_monitor_active_capability_history_670(event_key,event_kind,actor_id,actor_email,gateway_instance_id,release_name,source_sha,manifest_sha256,planner_interface,planner_sha256,trust_receipt_sha256,before_role,after_role,before_writer_active,after_writer_active,before_reader_active,after_reader_active,before_planner_commissioned,after_planner_commissioned,observed_mime_part_count,retained_authenticated_attachment_count,qualifying_attachment_sha256,all_mime_parts_retained,before_state,after_state,performed_by,performed_by_email,rollback_contract)
  VALUES(event_key,'rollback',c.actor_id,c.actor_email,c.gateway_instance_id,c.release_name,c.source_sha,c.manifest_sha256,c.planner_interface,c.planner_sha256,c.trust_receipt_sha256,'importer','viewer',true,false,true,true,true,false,7,4,c.qualifying_attachment_sha256,true,before_state,after_state,v_admin,v_email,'guarded admin rollback restores contained Viewer state and preserves the pre-existing identity reader; history remains append-only; no mailbox/task/Production action');
  INSERT INTO public.audit_events(action,table_name,row_id,actor_id,actor_email,before_data,after_data,metadata) VALUES('role_change','pdc_email_monitor_active_capability_controls_670',c.actor_id,v_admin,v_email,before_state,after_state,jsonb_build_object('event_type','pdc_email_monitor_active_capability_rolled_back_670','reason',btrim(p_reason),'production_untouched',true,'windows_monitor_enabled',false));
  RETURN jsonb_build_object('ok',true,'code','pdc_email_monitor_active_capability_rolled_back_670','idempotent',false,'production_writes',false,'windows_monitor_enabled',false,'rollback_available',true);
END
$rollback$;
REVOKE ALL ON FUNCTION public.admin_rollback_pdc_email_monitor_active_capability_670(text) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.admin_rollback_pdc_email_monitor_active_capability_670(text) TO authenticated;

DO $post$
BEGIN
  IF (SELECT count(*) FROM public.pdc_email_monitor_active_capability_controls_670 WHERE singleton AND enabled AND capability_active AND writer_active AND planner_commissioned AND activation_ready AND NOT windows_monitor_enabled AND NOT outbound_email_enabled AND NOT production_writes AND observed_mime_part_count=7 AND retained_authenticated_attachment_count=4 AND all_mime_parts_retained)<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_active_capability_history_670 WHERE event_kind='forward_capability')<>1
     OR (SELECT count(*) FROM public.pdc_user_roles WHERE auth_user_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND lower(email)='sales@broometoyota.com.au' AND active AND account_status='approved' AND role::text='importer')<>1
     OR (SELECT count(*) FROM public.pdc_monitor_stage_activation_writers WHERE user_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND active AND revoked_at IS NULL)<>1
     OR (SELECT count(*) FROM public.pdc_monitor_vehicle_identity_readers WHERE user_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND active AND revoked_at IS NULL)<>1
     OR (SELECT count(*) FROM public.pdc_monitor_runtime_bindings_255 WHERE singleton AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND semantic_planner_sha256='d3ee4933b380cfce2712ff8804419a35f9d33d6039c1dcd3653d1fb6f923c09a' AND semantic_planner_trust_receipt_sha256='639148337b6f9708479e5a03f7fb6894665cb4372d27072087e4c777bc54bc65' AND semantic_planner_commissioned_at IS NOT NULL)<>1
     OR NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.pdc_uid514_recovery_authorizations_257'::regclass AND conname='pdc_uid514_recovery_authorizations_257_attachment_count_check' AND pg_get_constraintdef(oid) LIKE '%attachment_count = 7%')
     OR position('v_count<>7' IN pg_get_functiondef('public.authorize_pdc_uid514_retained_intake_257(uuid,integer)'::regprocedure))=0
     OR position('pdc_email_monitor' IN pg_get_functiondef('public.read_pdc_uid514_transaction_receipt_257(integer)'::regprocedure))=0
     OR NOT has_function_privilege('pdc_email_monitor','public.read_pdc_uid514_transaction_receipt_257(integer)','execute')
     OR NOT has_function_privilege('pdc_email_monitor','public.verify_pdc_monitor_runtime_binding_503(text,text,text,text,text,text,text)','execute')
     OR NOT has_function_privilege('pdc_email_monitor','public.claim_pdc_uid514_recovery_257(text,integer)','execute')
     OR has_function_privilege('anon','public.read_pdc_uid514_transaction_receipt_257(integer)','execute')
     OR has_function_privilege('service_role','public.read_pdc_uid514_transaction_receipt_257(integer)','execute')
     OR (SELECT count(*) FROM public.monitored_mailboxes WHERE active)<>0
     OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND (enabled OR automatic_rule_application OR automatic_authenticated_jobcards OR outbound_email_enabled))<>0
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  THEN RAISE EXCEPTION 'PDC_670_ACTIVE_CAPABILITY_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END
$post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260827067000','670_email_monitor_active_capability_uid514_seven_part_reconciliation',ARRAY[
  'Require exact timestamped 508 ledger predecessor, exact .44 actor/gateway/source/tree/manifest pair, staging sentinel and absent Production sentinel',
  'Convert only sales@broometoyota.com.au from approved Viewer to approved importer and activate only its existing monitor reader/writer rows',
  'Bind the reviewed deterministic semantic planner SHA-256 and exact pdc-active-semantic-planner-trust-v1 receipt SHA-256 to the existing singleton',
  'Grant only pdc_email_monitor the missing active attestation, UID514 recovery, canonical Job Card receipt and cycle/result execution surfaces; keep anon and service_role denied',
  'Reconcile the authenticated UID514 observation as seven retained MIME parts with four retained authenticated attachment records and one exact qualifying PDF hash; preserve every part and reject count/hash mismatch',
  'Keep 508 synthetic commissioning receipt separate from physical mailbox and vehicle evidence; actual UID514 authorization/claim/import remains a later pdc-emails action',
  'Add forced-RLS immutable capability control/history and guarded Administrator rollback restoring Viewer, inactive writer and null planner binding while preserving the pre-existing identity reader',
  'Windows monitor task, mailbox flags/fetch, outbound email, automatic pilot and Production writes remain untouched and false'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
