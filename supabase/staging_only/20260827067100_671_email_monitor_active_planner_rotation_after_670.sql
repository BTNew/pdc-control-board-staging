-- STAGING ONLY 671: rotate the active .44 semantic planner to the
-- multi-action-safe reviewed artifact without rewriting migration 670.
-- No mailbox, UID514, vehicle, task, outbound-email or Production work occurs.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-671-email-monitor-planner-rotation',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260827067000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827067000' AND name='670_email_monitor_active_capability_uid514_seven_part_reconciliation')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260827067000')<>0
     OR to_regclass('public.pdc_email_monitor_active_planner_rotation_controls_671') IS NOT NULL
     OR to_regclass('public.pdc_email_monitor_active_planner_rotation_history_671') IS NOT NULL
     OR to_regprocedure('public.admin_rollback_pdc_email_monitor_active_planner_rotation_671(text)') IS NOT NULL
     OR (SELECT count(*) FROM public.pdc_email_monitor_active_capability_controls_670 WHERE singleton AND enabled AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND planner_sha256='d3ee4933b380cfce2712ff8804419a35f9d33d6039c1dcd3653d1fb6f923c09a' AND trust_receipt_sha256='639148337b6f9708479e5a03f7fb6894665cb4372d27072087e4c777bc54bc65' AND observed_mime_part_count=7 AND retained_authenticated_attachment_count=4 AND all_mime_parts_retained)<>1
     OR (SELECT count(*) FROM public.pdc_email_monitor_active_capability_history_670 WHERE event_kind='forward_capability' AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b')<>1
     OR (SELECT count(*) FROM public.pdc_monitor_runtime_bindings_255 WHERE singleton AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND semantic_planner_sha256='d3ee4933b380cfce2712ff8804419a35f9d33d6039c1dcd3653d1fb6f923c09a' AND semantic_planner_trust_receipt_sha256='639148337b6f9708479e5a03f7fb6894665cb4372d27072087e4c777bc54bc65' AND semantic_planner_commissioned_at IS NOT NULL)<>1
     OR (SELECT count(*) FROM public.pdc_user_roles WHERE auth_user_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND lower(email)='sales@broometoyota.com.au' AND active AND account_status='approved' AND role::text='importer')<>1
     OR (SELECT count(*) FROM public.pdc_monitor_stage_activation_writers WHERE user_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND active AND revoked_at IS NULL)<>1
     OR (SELECT count(*) FROM pg_trigger WHERE tgname='pdc_monitor_planner_binding_immutable_502' AND tgrelid='public.pdc_monitor_runtime_bindings_255'::regclass AND NOT tgisinternal AND tgenabled='O')<>1
  THEN RAISE EXCEPTION 'PDC_671_EXACT_670_PREDECESSOR_OR_COLLISION_MISMATCH' USING errcode='55000'; END IF;
END
$guard$;

CREATE TABLE public.pdc_email_monitor_active_planner_rotation_controls_671(
  singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
  enabled boolean NOT NULL DEFAULT true,
  actor_id uuid NOT NULL,
  actor_email text NOT NULL CHECK(actor_email='sales@broometoyota.com.au'),
  gateway_instance_id text NOT NULL,
  release_name text NOT NULL,
  source_sha text NOT NULL,
  manifest_sha256 text NOT NULL,
  predecessor_planner_sha256 text NOT NULL CHECK(predecessor_planner_sha256='d3ee4933b380cfce2712ff8804419a35f9d33d6039c1dcd3653d1fb6f923c09a'),
  predecessor_trust_receipt_sha256 text NOT NULL CHECK(predecessor_trust_receipt_sha256='639148337b6f9708479e5a03f7fb6894665cb4372d27072087e4c777bc54bc65'),
  planner_interface text NOT NULL CHECK(planner_interface='pmb-pdc-agentic-email-plan-v1'),
  planner_sha256 text NOT NULL CHECK(planner_sha256='7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348'),
  trust_receipt_sha256 text NOT NULL CHECK(trust_receipt_sha256='e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227'),
  trust_receipt jsonb NOT NULL,
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
ALTER TABLE public.pdc_email_monitor_active_planner_rotation_controls_671 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_monitor_active_planner_rotation_controls_671 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_email_monitor_active_planner_rotation_controls_671 FROM public,anon,authenticated,service_role,pdc_email_monitor;

CREATE TABLE public.pdc_email_monitor_active_planner_rotation_history_671(
  history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key text NOT NULL UNIQUE,
  event_kind text NOT NULL CHECK(event_kind IN('forward_planner_rotation','rollback')),
  actor_id uuid NOT NULL,
  actor_email text NOT NULL,
  gateway_instance_id text NOT NULL,
  release_name text NOT NULL,
  source_sha text NOT NULL,
  manifest_sha256 text NOT NULL,
  predecessor_planner_sha256 text NOT NULL,
  predecessor_trust_receipt_sha256 text NOT NULL,
  after_planner_sha256 text NOT NULL,
  after_trust_receipt_sha256 text NOT NULL,
  before_state jsonb NOT NULL,
  after_state jsonb NOT NULL,
  observed_mime_part_count integer NOT NULL CHECK(observed_mime_part_count=7),
  retained_authenticated_attachment_count integer NOT NULL CHECK(retained_authenticated_attachment_count=4),
  qualifying_attachment_sha256 text NOT NULL CHECK(qualifying_attachment_sha256='9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4'),
  all_mime_parts_retained boolean NOT NULL CHECK(all_mime_parts_retained),
  performed_by uuid,
  performed_by_email text,
  rollback_contract text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE FUNCTION public.pdc_email_monitor_active_planner_rotation_history_immutable_671()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public
AS $immutable$ BEGIN RAISE EXCEPTION 'PDC_671_ACTIVE_PLANNER_ROTATION_HISTORY_IMMUTABLE' USING errcode='55000'; END $immutable$;
CREATE TRIGGER pdc_email_monitor_active_planner_rotation_history_immutable_671
BEFORE UPDATE OR DELETE ON public.pdc_email_monitor_active_planner_rotation_history_671
FOR EACH ROW EXECUTE FUNCTION public.pdc_email_monitor_active_planner_rotation_history_immutable_671();
ALTER TABLE public.pdc_email_monitor_active_planner_rotation_history_671 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_monitor_active_planner_rotation_history_671 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_email_monitor_active_planner_rotation_history_671 FROM public,anon,authenticated,service_role,pdc_email_monitor;

INSERT INTO public.pdc_email_monitor_active_planner_rotation_controls_671(
 actor_id,actor_email,gateway_instance_id,release_name,source_sha,manifest_sha256,
 predecessor_planner_sha256,predecessor_trust_receipt_sha256,planner_interface,planner_sha256,trust_receipt_sha256,trust_receipt,qualifying_attachment_sha256)
VALUES(
 'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b','sales@broometoyota.com.au','pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44','e850c319989d98b45b95a28aa815d78e2c2e3a4b','d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d',
 'd3ee4933b380cfce2712ff8804419a35f9d33d6039c1dcd3653d1fb6f923c09a','639148337b6f9708479e5a03f7fb6894665cb4372d27072087e4c777bc54bc65','pmb-pdc-agentic-email-plan-v1','7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348','e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227',
 '{"approved_at":"2026-08-27T05:03:14Z","approved_by":"Craig Watson","contract":"pdc-active-semantic-planner-trust-v1","planner_interface":"pmb-pdc-agentic-email-plan-v1","planner_sha256":"7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348","release_series":"pdc-monitor-staging-m502"}'::jsonb,'9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4');

DO $rotate$
DECLARE v_before jsonb; v_after jsonb; v_binding public.pdc_monitor_runtime_bindings_255%rowtype; v_event_key text; v_definition text;
BEGIN
 SELECT * INTO v_binding FROM public.pdc_monitor_runtime_bindings_255 WHERE singleton FOR UPDATE;
 v_before:=to_jsonb(v_binding);
 SELECT pg_get_functiondef('public.read_pdc_uid514_transaction_receipt_257(integer)'::regprocedure) INTO v_definition;
 IF position('d3ee4933b380cfce2712ff8804419a35f9d33d6039c1dcd3653d1fb6f923c09a' IN v_definition)=0 OR position('639148337b6f9708479e5a03f7fb6894665cb4372d27072087e4c777bc54bc65' IN v_definition)=0 THEN RAISE EXCEPTION 'PDC_671_READER_PREDECESSOR_HASH_MISSING' USING errcode='55000'; END IF;
 v_definition:=replace(v_definition,'d3ee4933b380cfce2712ff8804419a35f9d33d6039c1dcd3653d1fb6f923c09a','7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348');
 v_definition:=replace(v_definition,'639148337b6f9708479e5a03f7fb6894665cb4372d27072087e4c777bc54bc65','e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227');
 EXECUTE v_definition;
 ALTER TABLE public.pdc_monitor_runtime_bindings_255 DISABLE TRIGGER pdc_monitor_planner_binding_immutable_502;
 UPDATE public.pdc_monitor_runtime_bindings_255 SET semantic_planner_sha256='7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348',semantic_planner_trust_receipt_sha256='e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227',semantic_planner_commissioned_at=clock_timestamp() WHERE singleton AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND semantic_planner_sha256='d3ee4933b380cfce2712ff8804419a35f9d33d6039c1dcd3653d1fb6f923c09a' AND semantic_planner_trust_receipt_sha256='639148337b6f9708479e5a03f7fb6894665cb4372d27072087e4c777bc54bc65';
 IF NOT FOUND THEN ALTER TABLE public.pdc_monitor_runtime_bindings_255 ENABLE TRIGGER pdc_monitor_planner_binding_immutable_502; RAISE EXCEPTION 'PDC_671_BINDING_ROTATION_NOT_APPLIED' USING errcode='40001'; END IF;
 ALTER TABLE public.pdc_monitor_runtime_bindings_255 ENABLE TRIGGER pdc_monitor_planner_binding_immutable_502;
 SELECT * INTO v_binding FROM public.pdc_monitor_runtime_bindings_255 WHERE singleton;
 v_after:=to_jsonb(v_binding);
 v_event_key:=encode(extensions.digest(convert_to('pdc-staging-671-email-monitor-planner-rotation|forward|'||v_binding.binding_id::text,'UTF8'),'sha256'),'hex');
 INSERT INTO public.pdc_email_monitor_active_planner_rotation_history_671(event_key,event_kind,actor_id,actor_email,gateway_instance_id,release_name,source_sha,manifest_sha256,predecessor_planner_sha256,predecessor_trust_receipt_sha256,after_planner_sha256,after_trust_receipt_sha256,before_state,after_state,observed_mime_part_count,retained_authenticated_attachment_count,qualifying_attachment_sha256,all_mime_parts_retained,rollback_contract)
 VALUES(v_event_key,'forward_planner_rotation',v_binding.actor_id,'sales@broometoyota.com.au',v_binding.gateway_instance_id,v_binding.release_name,v_binding.source_sha,v_binding.manifest_sha256,'d3ee4933b380cfce2712ff8804419a35f9d33d6039c1dcd3653d1fb6f923c09a','639148337b6f9708479e5a03f7fb6894665cb4372d27072087e4c777bc54bc65','7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348','e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227',v_before,v_after,7,4,'9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4',true,'forward planner rotation only; guarded admin rollback disables active capability and restores contained Viewer state');
END
$rotate$;

CREATE FUNCTION public.admin_rollback_pdc_email_monitor_active_planner_rotation_671(p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,auth AS $rollback$
DECLARE v_admin uuid:=auth.uid(); v_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); v_count integer; c public.pdc_email_monitor_active_planner_rotation_controls_671%rowtype; h public.pdc_email_monitor_active_planner_rotation_history_671%rowtype; r public.pdc_user_roles%rowtype; w public.pdc_monitor_stage_activation_writers%rowtype; b public.pdc_monitor_runtime_bindings_255%rowtype; before_state jsonb; after_state jsonb; event_key text;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR v_admin IS NULL OR coalesce(auth.jwt()->>'role','')<>'authenticated' OR length(btrim(coalesce(p_reason,'')))<10 THEN RAISE EXCEPTION 'PDC_671_ADMIN_AUTHORITY_REQUIRED' USING errcode='42501'; END IF;
 SELECT count(*) INTO v_count FROM public.pdc_user_roles r0 JOIN auth.users u ON u.id=r0.auth_user_id AND lower(u.email)=v_email WHERE r0.auth_user_id=v_admin AND lower(r0.email)=v_email AND r0.active AND r0.account_status='approved' AND r0.role::text='administrator';
 IF v_count<>1 THEN RAISE EXCEPTION 'PDC_671_ADMIN_AUTHORITY_REQUIRED' USING errcode='42501'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-staging-671-email-monitor-planner-rotation',0));
 SELECT * INTO c FROM public.pdc_email_monitor_active_planner_rotation_controls_671 WHERE singleton FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'PDC_671_ROTATION_CONTROL_MISSING' USING errcode='55000'; END IF;
 SELECT * INTO h FROM public.pdc_email_monitor_active_planner_rotation_history_671 WHERE event_kind='rollback' ORDER BY created_at DESC,history_id DESC LIMIT 1;
 IF FOUND THEN IF c.enabled THEN RAISE EXCEPTION 'PDC_671_ROLLBACK_STATE_DRIFT' USING errcode='55000'; END IF; RETURN jsonb_build_object('ok',true,'code','pdc_email_monitor_active_planner_rotation_rolled_back_671','idempotent',true,'history_id',h.history_id,'windows_monitor_enabled',false,'production_writes',false); END IF;
 SELECT * INTO r FROM public.pdc_user_roles WHERE auth_user_id=c.actor_id AND lower(email)=c.actor_email AND active AND account_status='approved' FOR UPDATE;
 SELECT * INTO w FROM public.pdc_monitor_stage_activation_writers WHERE user_id=c.actor_id FOR UPDATE;
 SELECT * INTO b FROM public.pdc_monitor_runtime_bindings_255 WHERE singleton AND actor_id=c.actor_id FOR UPDATE;
 IF NOT FOUND OR r.role::text<>'importer' OR NOT w.active OR w.revoked_at IS NOT NULL OR b.semantic_planner_sha256<>c.planner_sha256 OR b.semantic_planner_trust_receipt_sha256<>c.trust_receipt_sha256 OR b.semantic_planner_commissioned_at IS NULL THEN RAISE EXCEPTION 'PDC_671_ROLLBACK_SCOPE_MISMATCH' USING errcode='55000'; END IF;
 before_state:=jsonb_build_object('role',to_jsonb(r),'writer',to_jsonb(w),'binding',to_jsonb(b));
 ALTER TABLE public.pdc_monitor_runtime_bindings_255 DISABLE TRIGGER pdc_monitor_planner_binding_immutable_502;
 UPDATE public.pdc_monitor_runtime_bindings_255 SET semantic_planner_sha256=NULL,semantic_planner_trust_receipt_sha256=NULL,semantic_planner_commissioned_at=NULL WHERE binding_id=b.binding_id;
 ALTER TABLE public.pdc_monitor_runtime_bindings_255 ENABLE TRIGGER pdc_monitor_planner_binding_immutable_502;
 UPDATE public.pdc_monitor_stage_activation_writers SET active=false,revoked_at=clock_timestamp(),reason='671 capability rollback: '||left(btrim(p_reason),700) WHERE user_id=c.actor_id RETURNING * INTO w;
 UPDATE public.pdc_user_roles SET role='viewer',notes=left(btrim(coalesce(notes,''))||' | 671 capability rollback',1000),updated_at=clock_timestamp() WHERE id=r.id RETURNING * INTO r;
 SELECT * INTO b FROM public.pdc_monitor_runtime_bindings_255 WHERE binding_id=b.binding_id;
 after_state:=jsonb_build_object('role',to_jsonb(r),'writer',to_jsonb(w),'binding',to_jsonb(b));
 UPDATE public.pdc_email_monitor_active_planner_rotation_controls_671 SET enabled=false WHERE singleton;
 UPDATE public.pdc_email_monitor_active_capability_controls_670 SET enabled=false WHERE singleton;
 event_key:=encode(extensions.digest(convert_to('pdc-staging-671-email-monitor-planner-rotation|rollback|'||c.actor_id::text,'UTF8'),'sha256'),'hex');
 INSERT INTO public.pdc_email_monitor_active_planner_rotation_history_671(event_key,event_kind,actor_id,actor_email,gateway_instance_id,release_name,source_sha,manifest_sha256,predecessor_planner_sha256,predecessor_trust_receipt_sha256,after_planner_sha256,after_trust_receipt_sha256,before_state,after_state,observed_mime_part_count,retained_authenticated_attachment_count,qualifying_attachment_sha256,all_mime_parts_retained,performed_by,performed_by_email,rollback_contract)
 VALUES(event_key,'rollback',c.actor_id,c.actor_email,c.gateway_instance_id,c.release_name,c.source_sha,c.manifest_sha256,c.predecessor_planner_sha256,c.predecessor_trust_receipt_sha256,'7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348','e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227',before_state,after_state,7,4,c.qualifying_attachment_sha256,true,v_admin,v_email,'guarded admin rollback disables 670/671 active capability, restores contained Viewer and inactive writer, preserves pre-existing identity reader and all history');
 INSERT INTO public.audit_events(action,table_name,row_id,actor_id,actor_email,before_data,after_data,metadata) VALUES('role_change','pdc_email_monitor_active_planner_rotation_controls_671',c.actor_id,v_admin,v_email,before_state,after_state,jsonb_build_object('event_type','pdc_email_monitor_active_planner_rotation_rolled_back_671','reason',btrim(p_reason),'production_untouched',true,'windows_monitor_enabled',false));
 RETURN jsonb_build_object('ok',true,'code','pdc_email_monitor_active_planner_rotation_rolled_back_671','idempotent',false,'windows_monitor_enabled',false,'production_writes',false,'rollback_available',true);
END
$rollback$;
REVOKE ALL ON FUNCTION public.admin_rollback_pdc_email_monitor_active_planner_rotation_671(text) FROM public,anon,authenticated,service_role,pdc_email_monitor;
GRANT EXECUTE ON FUNCTION public.admin_rollback_pdc_email_monitor_active_planner_rotation_671(text) TO authenticated;

DO $post$
BEGIN
 IF (SELECT count(*) FROM public.pdc_email_monitor_active_planner_rotation_controls_671 WHERE singleton AND enabled AND writer_active AND planner_commissioned AND activation_ready AND NOT windows_monitor_enabled AND NOT outbound_email_enabled AND NOT production_writes AND observed_mime_part_count=7 AND retained_authenticated_attachment_count=4 AND all_mime_parts_retained)<>1
    OR (SELECT count(*) FROM public.pdc_email_monitor_active_planner_rotation_history_671 WHERE event_kind='forward_planner_rotation')<>1
    OR (SELECT count(*) FROM public.pdc_monitor_runtime_bindings_255 WHERE singleton AND actor_id='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b' AND semantic_planner_sha256='7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348' AND semantic_planner_trust_receipt_sha256='e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227' AND semantic_planner_commissioned_at IS NOT NULL)<>1
    OR position('d3ee4933b380cfce2712ff8804419a35f9d33d6039c1dcd3653d1fb6f923c09a' IN pg_get_functiondef('public.read_pdc_uid514_transaction_receipt_257(integer)'::regprocedure))<>0
    OR position('639148337b6f9708479e5a03f7fb6894665cb4372d27072087e4c777bc54bc65' IN pg_get_functiondef('public.read_pdc_uid514_transaction_receipt_257(integer)'::regprocedure))<>0
    OR (SELECT count(*) FROM pg_trigger WHERE tgname='pdc_monitor_planner_binding_immutable_502' AND tgrelid='public.pdc_monitor_runtime_bindings_255'::regclass AND NOT tgisinternal AND tgenabled='O')<>1
    OR NOT has_function_privilege('pdc_email_monitor','public.read_pdc_uid514_transaction_receipt_257(integer)','execute')
    OR has_function_privilege('anon','public.read_pdc_uid514_transaction_receipt_257(integer)','execute')
    OR has_function_privilege('service_role','public.read_pdc_uid514_transaction_receipt_257(integer)','execute')
 THEN RAISE EXCEPTION 'PDC_671_PLANNER_ROTATION_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END
$post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260827067100','671_email_monitor_active_planner_rotation_after_670',ARRAY[
 'Require exact applied 670 active capability, old planner/trust binding, actor role/importer and active writer before rotation',
 'Rotate only the exact .44 singleton from the superseded planner artifact to the reviewed multi-action-safe deterministic planner and trust receipt',
 'Preserve UID514 seven-part observation: seven MIME parts, four retained authenticated attachment records, one exact qualifying PDF hash and no silent part loss',
 'Update only the frozen UID514 reader hash binding while preserving contained and active identity gates and synthetic-vs-physical provenance',
 'Temporarily disable only the existing planner immutability trigger inside the guarded owner transaction and re-enable it before commit',
 'Keep forced-RLS immutable rotation control/history, authenticated-only guarded rollback and no service-role/browser-local/direct-DML bypass',
 'Windows monitor task, mailbox flags/fetch, outbound email, automatic pilot and Production writes remain untouched and false'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
