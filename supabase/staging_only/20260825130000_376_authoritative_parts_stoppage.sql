-- STAGING ONLY 376: authoritative audited Parts STOPPAGE and recovery.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-376-authoritative-parts-stoppage',0));
DO $pre$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260825120000' AND name='375_acceptance_closure_intake')<>1
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260825120000')
   OR (SELECT count(*) FROM public.vehicle_notifications)<>0
   OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
   OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)
   OR public.pdc_acceptance_protected_digest_375() IS DISTINCT FROM jsonb_build_object('rows',1498,'sha256','cb43c3582df4fd646ffb457a627273ce59dc273034bc0e7b95c24c13f2dc437e') THEN
  RAISE EXCEPTION 'PDC_376_STAGING_HEAD_OR_CONTAINMENT_MISMATCH' USING errcode='55000'; END IF;
END $pre$;

CREATE TABLE public.pdc_parts_stoppage_receipts_376(
 receipt_id uuid PRIMARY KEY,
 vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
 actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 actor_email text NOT NULL,
 idempotency_key uuid NOT NULL,
 action text NOT NULL CHECK(action IN('set','clear')),
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 3 AND 240),
 expected_vehicle_version integer NOT NULL CHECK(expected_vehicle_version>0),
 request_sha256 text NOT NULL CHECK(request_sha256~'^[a-f0-9]{64}$'),
 before_state jsonb NOT NULL CHECK(jsonb_typeof(before_state)='object'),
 after_state jsonb NOT NULL CHECK(jsonb_typeof(after_state)='object'),
 response jsonb NOT NULL CHECK(jsonb_typeof(response)='object'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(actor_id,idempotency_key)
);
ALTER TABLE public.pdc_parts_stoppage_receipts_376 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_parts_stoppage_receipts_376 FROM public,anon,authenticated,service_role;

CREATE FUNCTION public.pdc_parts_stoppage_receipt_append_only_376()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $append$
BEGIN RAISE EXCEPTION 'PDC_376_RECEIPT_APPEND_ONLY' USING errcode='55000'; END $append$;
REVOKE ALL ON FUNCTION public.pdc_parts_stoppage_receipt_append_only_376() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_parts_stoppage_receipts_append_only_376 BEFORE UPDATE OR DELETE ON public.pdc_parts_stoppage_receipts_376
FOR EACH ROW EXECUTE FUNCTION public.pdc_parts_stoppage_receipt_append_only_376();

CREATE FUNCTION public.set_pdc_parts_stoppage_376(
 p_vehicle_id uuid,p_expected_version integer,p_idempotency_key uuid,p_action text,p_reason text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,extensions SET statement_timeout='90s' AS $set$
DECLARE
 v_actor uuid:=auth.uid(); v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
 v_action text:=lower(btrim(coalesce(p_action,''))); v_reason text:=btrim(coalesce(p_reason,''));
 v_vehicle_before public.vehicles%rowtype; v_vehicle_after public.vehicles%rowtype;
 v_parts_before public.vehicle_parts_updates%rowtype; v_parts_after public.vehicle_parts_updates%rowtype;
 v_receipt public.pdc_parts_stoppage_receipts_376%rowtype; v_request jsonb; v_sha text; v_id uuid; v_response jsonb;
 v_before_state jsonb; v_after_state jsonb; v_code text; v_changed boolean:=false;
 v_notifications_before bigint; v_notifications_after bigint; v_pdc_before bigint; v_pdc_after bigint; v_workshop_before bigint; v_workshop_after bigint;
BEGIN
 IF p_vehicle_id IS NULL OR p_expected_version IS NULL OR p_expected_version<1 OR p_idempotency_key IS NULL
   OR v_action NOT IN('set','clear') OR length(v_reason) NOT BETWEEN 3 AND 240 THEN
  RAISE EXCEPTION 'PDC_376_INVALID_INPUT' USING errcode='22023'; END IF;
 IF v_actor IS NULL OR v_email='' OR NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=v_actor AND lower(r.email)=v_email
   AND r.role IN('operator','administrator') AND r.active AND r.account_status='approved' FOR SHARE) THEN
  RAISE EXCEPTION 'PDC_376_UNAUTHORIZED' USING errcode='42501'; END IF;
 v_request:=jsonb_build_object('contract','pdc-parts-stoppage-376','vehicle_id',p_vehicle_id,'expected_version',p_expected_version,
  'idempotency_key',p_idempotency_key,'action',v_action,'reason',v_reason,'actor_id',v_actor);
 v_sha:=encode(extensions.digest(convert_to(v_request::text,'UTF8'),'sha256'),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-parts-stoppage-376:'||v_actor::text||':'||p_idempotency_key::text,0));
 SELECT * INTO v_receipt FROM public.pdc_parts_stoppage_receipts_376 WHERE actor_id=v_actor AND idempotency_key=p_idempotency_key;
 IF FOUND THEN
  IF v_receipt.request_sha256<>v_sha OR v_receipt.actor_email<>v_email THEN RAISE EXCEPTION 'PDC_376_IDEMPOTENCY_PAYLOAD_MISMATCH' USING errcode='22023'; END IF;
  SELECT * INTO v_vehicle_after FROM public.vehicles WHERE id=v_receipt.vehicle_id;
  SELECT * INTO v_parts_after FROM public.vehicle_parts_updates WHERE vehicle_id=v_receipt.vehicle_id ORDER BY updated_at DESC,id DESC LIMIT 1;
  v_after_state:=jsonb_build_object('vehicle',to_jsonb(v_vehicle_after),'parts_update',CASE WHEN v_parts_after.id IS NULL THEN NULL ELSE to_jsonb(v_parts_after) END);
  IF NOT public.pdc_monitor_staging_guard() OR (SELECT count(*) FROM public.vehicle_notifications)<>0
    OR v_after_state IS DISTINCT FROM v_receipt.after_state THEN
   RAISE EXCEPTION 'PDC_376_REPLAY_CONTAINMENT_MISMATCH' USING errcode='55000'; END IF;
  RETURN jsonb_set(v_receipt.response,'{replay}','true'::jsonb,false)||jsonb_build_object('replay_containment_verified',true,'current_notification_count',0);
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-parts-stoppage-vehicle:'||p_vehicle_id::text,0));
 LOCK TABLE public.vehicle_notifications IN SHARE MODE;
 IF NOT public.pdc_monitor_staging_guard() OR (SELECT count(*) FROM public.vehicle_notifications)<>0
   OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
   OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL) THEN
  RAISE EXCEPTION 'PDC_376_RUNTIME_CONTAINMENT_MISMATCH' USING errcode='55000'; END IF;
 SELECT * INTO v_vehicle_before FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'PDC_376_VEHICLE_NOT_FOUND' USING errcode='P0002'; END IF;
 SELECT * INTO v_parts_before FROM public.vehicle_parts_updates WHERE vehicle_id=p_vehicle_id ORDER BY updated_at DESC,id DESC LIMIT 1 FOR UPDATE;
 v_before_state:=jsonb_build_object('vehicle',to_jsonb(v_vehicle_before),'parts_update',CASE WHEN v_parts_before.id IS NULL THEN NULL ELSE to_jsonb(v_parts_before) END);
 v_notifications_before:=(SELECT count(*) FROM public.vehicle_notifications);
 SELECT revision INTO v_pdc_before FROM public.pdc_email_vehicle_revision WHERE singleton;
 SELECT revision INTO v_workshop_before FROM public.workshop_revision WHERE id=1;
 IF v_vehicle_before.version<>p_expected_version THEN v_code:='vehicle_version_conflict';
 ELSIF v_vehicle_before.deleted_at IS NOT NULL OR v_vehicle_before.lifecycle_state IN('completed','deleted') OR NOT v_vehicle_before.visible_on_board THEN v_code:='vehicle_inactive_or_issued';
 ELSIF coalesce(v_parts_before.parts_received,false) THEN v_code:='parts_already_received';
 ELSIF v_action='set' AND coalesce(v_parts_before.parts_stoppage,false) THEN v_code:='parts_stoppage_already_active';
 ELSIF v_action='clear' AND NOT coalesce(v_parts_before.parts_stoppage,false) THEN v_code:='parts_stoppage_not_active';
 ELSE
  INSERT INTO public.vehicle_parts_updates(vehicle_id,parts_required,parts_ordered,parts_received,parts_stoppage,parts_stoppage_reason,worst_eta,updated_by,updated_at)
  VALUES(p_vehicle_id,true,coalesce(v_parts_before.parts_ordered,false),false,v_action='set',CASE WHEN v_action='set' THEN v_reason ELSE NULL END,
   v_parts_before.worst_eta,v_actor,clock_timestamp()) RETURNING * INTO v_parts_after;
  UPDATE public.vehicles SET version=version+1,updated_by=v_actor,updated_at=clock_timestamp() WHERE id=p_vehicle_id RETURNING * INTO v_vehicle_after;
  PERFORM public.audit_pdc_event('insert','vehicle_parts_updates',v_parts_after.id,p_vehicle_id,
   CASE WHEN v_parts_before.id IS NULL THEN NULL ELSE to_jsonb(v_parts_before) END,to_jsonb(v_parts_after),
   jsonb_build_object('action',CASE WHEN v_action='set' THEN 'pdc_parts_stoppage_set_376' ELSE 'pdc_parts_stoppage_clear_376' END,
    'reason',v_reason,'actor_id',v_actor,'recorded_at',clock_timestamp(),'notification_enqueued',false));
  v_changed:=true; v_code:=CASE WHEN v_action='set' THEN 'parts_stoppage_recorded' ELSE 'parts_stoppage_cleared' END;
 END IF;
 SELECT * INTO v_vehicle_after FROM public.vehicles WHERE id=p_vehicle_id;
 SELECT * INTO v_parts_after FROM public.vehicle_parts_updates WHERE vehicle_id=p_vehicle_id ORDER BY updated_at DESC,id DESC LIMIT 1;
 v_after_state:=jsonb_build_object('vehicle',to_jsonb(v_vehicle_after),'parts_update',CASE WHEN v_parts_after.id IS NULL THEN NULL ELSE to_jsonb(v_parts_after) END);
 v_notifications_after:=(SELECT count(*) FROM public.vehicle_notifications);
 SELECT revision INTO v_pdc_after FROM public.pdc_email_vehicle_revision WHERE singleton;
 SELECT revision INTO v_workshop_after FROM public.workshop_revision WHERE id=1;
 IF v_notifications_before<>0 OR v_notifications_after<>0 OR v_pdc_after<v_pdc_before OR v_pdc_after-v_pdc_before>8
   OR v_workshop_after<v_workshop_before OR v_workshop_after-v_workshop_before>8
   OR (v_changed AND (v_vehicle_after.version<>v_vehicle_before.version+1 OR v_parts_after.id IS NULL
     OR v_parts_after.parts_stoppage IS DISTINCT FROM (v_action='set') OR (v_action='set' AND v_parts_after.parts_stoppage_reason<>v_reason)))
   OR (NOT v_changed AND (v_after_state IS DISTINCT FROM v_before_state OR v_pdc_after IS DISTINCT FROM v_pdc_before OR v_workshop_after IS DISTINCT FROM v_workshop_before)) THEN
  RAISE EXCEPTION 'PDC_376_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
 v_id:=extensions.uuid_generate_v5('37600000-0000-5000-8000-000000000376'::uuid,v_actor::text||':'||p_idempotency_key::text);
 v_response:=jsonb_build_object('ok',v_changed,'code',v_code,'replay',false,'receipt_id',v_id,'request_sha256',v_sha,'vehicle_id',p_vehicle_id,
  'action',v_action,'reason',v_reason,'changed',v_changed,'vehicle_version_before',v_vehicle_before.version,'vehicle_version_after',v_vehicle_after.version,
  'vehicle',to_jsonb(v_vehicle_after),'parts_update',CASE WHEN v_parts_after.id IS NULL THEN NULL ELSE to_jsonb(v_parts_after) END,'notification_delta',0);
 INSERT INTO public.pdc_parts_stoppage_receipts_376(receipt_id,vehicle_id,actor_id,actor_email,idempotency_key,action,reason,expected_vehicle_version,
  request_sha256,before_state,after_state,response)
 VALUES(v_id,p_vehicle_id,v_actor,v_email,p_idempotency_key,v_action,v_reason,p_expected_version,v_sha,v_before_state,v_after_state,v_response);
 RETURN v_response;
END $set$;
REVOKE ALL ON FUNCTION public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text) TO authenticated;

DO $post$
BEGIN
 IF EXISTS(SELECT 1 FROM public.pdc_parts_stoppage_receipts_376)
   OR has_table_privilege('public','public.pdc_parts_stoppage_receipts_376','SELECT,INSERT,UPDATE,DELETE')
   OR has_table_privilege('anon','public.pdc_parts_stoppage_receipts_376','SELECT,INSERT,UPDATE,DELETE')
   OR has_table_privilege('authenticated','public.pdc_parts_stoppage_receipts_376','SELECT,INSERT,UPDATE,DELETE')
   OR has_table_privilege('service_role','public.pdc_parts_stoppage_receipts_376','SELECT,INSERT,UPDATE,DELETE')
   OR has_function_privilege('public','public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text)','EXECUTE')
   OR has_function_privilege('anon','public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text)','EXECUTE')
   OR has_function_privilege('service_role','public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text)','EXECUTE')
   OR NOT has_function_privilege('authenticated','public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text)','EXECUTE') THEN
  RAISE EXCEPTION 'PDC_376_ACL_OR_EMPTY_RECEIPT_POSTCONDITION' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260825130000','376_authoritative_parts_stoppage',array[
 'Expected-version audited Parts STOPPAGE and recovery with actor, reason and timestamp',
 'Immutable idempotency receipts including replay and authoritative rejection evidence',
 'Issued/completed/stale/unauthorized fail-closed checks with no browser-local fallback',
 'Zero notification creation and canonical snapshot/revision convergence'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
