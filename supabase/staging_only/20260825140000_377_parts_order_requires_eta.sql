-- STAGING ONLY 377: authoritative ETA prerequisite and receipted Parts ordering.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-377-parts-order-eta',0));
DO $pre$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260825130000' AND name='376_authoritative_parts_stoppage')<>1
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260825130000')
   OR (SELECT count(*) FROM public.vehicle_notifications)<>0
   OR public.pdc_acceptance_protected_digest_375() IS DISTINCT FROM jsonb_build_object('rows',1413,'sha256','28476c8fac93aa03707b20a84b4b836b4268c96fa6710bf1238f0f6ebb265f11')
   OR to_regprocedure('public.mark_pdc_parts_ordered(uuid,integer)') IS NULL THEN
  RAISE EXCEPTION 'PDC_377_STAGING_HEAD_OR_CONTAINMENT_MISMATCH' USING errcode='55000'; END IF;
END $pre$;

CREATE TABLE public.pdc_parts_order_receipts_377(
 receipt_id uuid PRIMARY KEY,
 vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
 actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 actor_email text NOT NULL,
 idempotency_key uuid NOT NULL,
 expected_vehicle_version integer NOT NULL CHECK(expected_vehicle_version>0),
 request_sha256 text NOT NULL CHECK(request_sha256~'^[a-f0-9]{64}$'),
 authoritative_eta date NOT NULL,
 response jsonb NOT NULL CHECK(jsonb_typeof(response)='object'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(actor_id,idempotency_key)
);
ALTER TABLE public.pdc_parts_order_receipts_377 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_parts_order_receipts_377 FROM public,anon,authenticated,service_role;
CREATE FUNCTION public.pdc_parts_order_receipt_append_only_377()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $append$
BEGIN RAISE EXCEPTION 'PDC_377_RECEIPT_APPEND_ONLY' USING errcode='55000'; END $append$;
REVOKE ALL ON FUNCTION public.pdc_parts_order_receipt_append_only_377() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_parts_order_receipts_append_only_377 BEFORE UPDATE OR DELETE ON public.pdc_parts_order_receipts_377
FOR EACH ROW EXECUTE FUNCTION public.pdc_parts_order_receipt_append_only_377();

CREATE FUNCTION public.pdc_parts_order_requires_eta_377()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,public AS $guard$
BEGIN
 IF coalesce(NEW.parts_ordered,false) AND NEW.worst_eta IS NULL THEN
  RAISE EXCEPTION 'PDC_PARTS_ETA_REQUIRED' USING errcode='23514',detail=jsonb_build_object('ok',false,'code','parts_eta_required','vehicle_id',NEW.vehicle_id)::text;
 END IF;
 RETURN NEW;
END $guard$;
REVOKE ALL ON FUNCTION public.pdc_parts_order_requires_eta_377() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_parts_order_requires_eta_377 BEFORE INSERT OR UPDATE OF parts_ordered,worst_eta ON public.vehicle_parts_updates
FOR EACH ROW EXECUTE FUNCTION public.pdc_parts_order_requires_eta_377();

CREATE FUNCTION public.mark_pdc_parts_ordered_377(p_vehicle_id uuid,p_expected_version integer,p_idempotency_key uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,extensions SET statement_timeout='90s' AS $order$
DECLARE
 v_actor uuid:=auth.uid(); v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
 v_vehicle public.vehicles%rowtype; v_parts public.vehicle_parts_updates%rowtype; v_receipt public.pdc_parts_order_receipts_377%rowtype;
 v_request jsonb; v_sha text; v_result jsonb; v_response jsonb; v_id uuid; v_eta date; v_notifications bigint;
BEGIN
 IF p_vehicle_id IS NULL OR p_expected_version IS NULL OR p_expected_version<1 OR p_idempotency_key IS NULL THEN
  RAISE EXCEPTION 'PDC_377_INVALID_INPUT' USING errcode='22023'; END IF;
 IF v_actor IS NULL OR v_email='' OR NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=v_actor AND lower(r.email)=v_email
   AND r.role IN('operator','administrator') AND r.active AND r.account_status='approved' FOR SHARE) THEN
  RAISE EXCEPTION 'PDC_377_UNAUTHORIZED' USING errcode='42501'; END IF;
 v_request:=jsonb_build_object('contract','pdc-parts-order-eta-377','vehicle_id',p_vehicle_id,'expected_version',p_expected_version,
  'idempotency_key',p_idempotency_key,'actor_id',v_actor);
 v_sha:=encode(extensions.digest(convert_to(v_request::text,'UTF8'),'sha256'),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-parts-order-377:'||v_actor::text||':'||p_idempotency_key::text,0));
 SELECT * INTO v_receipt FROM public.pdc_parts_order_receipts_377 WHERE actor_id=v_actor AND idempotency_key=p_idempotency_key;
 IF FOUND THEN
  IF v_receipt.request_sha256<>v_sha OR v_receipt.actor_email<>v_email THEN RAISE EXCEPTION 'PDC_377_IDEMPOTENCY_PAYLOAD_MISMATCH' USING errcode='22023'; END IF;
  SELECT * INTO v_vehicle FROM public.vehicles WHERE id=v_receipt.vehicle_id;
  SELECT * INTO v_parts FROM public.vehicle_parts_updates WHERE vehicle_id=v_receipt.vehicle_id ORDER BY updated_at DESC,id DESC LIMIT 1;
  IF NOT public.pdc_monitor_staging_guard() OR (SELECT count(*) FROM public.vehicle_notifications)<>0 OR NOT coalesce(v_parts.parts_ordered,false)
    OR v_parts.worst_eta IS DISTINCT FROM v_receipt.authoritative_eta OR v_vehicle.version<(v_receipt.response->>'vehicle_version_after')::integer THEN
   RAISE EXCEPTION 'PDC_377_REPLAY_READBACK_OR_CONTAINMENT_MISMATCH' USING errcode='55000'; END IF;
  RETURN jsonb_set(v_receipt.response,'{replay}','true'::jsonb,false)||jsonb_build_object('replay_containment_verified',true,'current_notification_count',0);
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-parts-order-vehicle:'||p_vehicle_id::text,0));
 SELECT * INTO v_vehicle FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_found','changed',false); END IF;
 IF v_vehicle.version<>p_expected_version THEN RETURN jsonb_build_object('ok',false,'code','vehicle_version_conflict','changed',false,'current_version',v_vehicle.version); END IF;
 SELECT * INTO v_parts FROM public.vehicle_parts_updates WHERE vehicle_id=p_vehicle_id ORDER BY updated_at DESC,id DESC LIMIT 1 FOR UPDATE;
 v_eta:=v_parts.worst_eta;
 IF v_eta IS NULL THEN RETURN jsonb_build_object('ok',false,'code','parts_eta_required','changed',false,'vehicle_id',p_vehicle_id); END IF;
 IF coalesce(v_parts.parts_received,false) THEN RETURN jsonb_build_object('ok',false,'code','parts_already_received','changed',false,'vehicle_id',p_vehicle_id); END IF;
 v_notifications:=(SELECT count(*) FROM public.vehicle_notifications);
 IF NOT public.pdc_monitor_staging_guard() OR v_notifications<>0 THEN RAISE EXCEPTION 'PDC_377_RUNTIME_CONTAINMENT_MISMATCH' USING errcode='55000'; END IF;
 v_result:=public.mark_pdc_parts_ordered(p_vehicle_id,p_expected_version);
 IF coalesce((v_result->>'ok')::boolean,false) IS NOT TRUE THEN RETURN coalesce(v_result,'{}'::jsonb)||jsonb_build_object('changed',false); END IF;
 SELECT * INTO v_vehicle FROM public.vehicles WHERE id=p_vehicle_id;
 SELECT * INTO v_parts FROM public.vehicle_parts_updates WHERE vehicle_id=p_vehicle_id ORDER BY updated_at DESC,id DESC LIMIT 1;
 IF NOT coalesce(v_parts.parts_ordered,false) OR v_parts.worst_eta IS DISTINCT FROM v_eta OR v_vehicle.version<>p_expected_version+1
   OR (SELECT count(*) FROM public.vehicle_notifications)<>0 THEN RAISE EXCEPTION 'PDC_377_ORDERED_READBACK_FAILED' USING errcode='55000'; END IF;
 v_id:=extensions.uuid_generate_v5('37700000-0000-5000-8000-000000000377'::uuid,v_actor::text||':'||p_idempotency_key::text);
 v_response:=jsonb_build_object('ok',true,'code','parts_ordered','replay',false,'receipt_id',v_id,'request_sha256',v_sha,'vehicle_id',p_vehicle_id,
  'changed',true,'authoritative_eta',v_eta,'vehicle_version_before',p_expected_version,'vehicle_version_after',v_vehicle.version,
  'vehicle',to_jsonb(v_vehicle),'parts_update',to_jsonb(v_parts),'notification_delta',0);
 INSERT INTO public.pdc_parts_order_receipts_377(receipt_id,vehicle_id,actor_id,actor_email,idempotency_key,expected_vehicle_version,request_sha256,authoritative_eta,response)
 VALUES(v_id,p_vehicle_id,v_actor,v_email,p_idempotency_key,p_expected_version,v_sha,v_eta,v_response);
 RETURN v_response;
END $order$;
REVOKE ALL ON FUNCTION public.mark_pdc_parts_ordered_377(uuid,integer,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.mark_pdc_parts_ordered_377(uuid,integer,uuid) TO authenticated;

DO $post$
BEGIN
 IF EXISTS(SELECT 1 FROM public.pdc_parts_order_receipts_377)
   OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.vehicle_parts_updates'::regclass AND tgname='pdc_parts_order_requires_eta_377' AND tgenabled='O' AND NOT tgisinternal)
   OR has_function_privilege('public','public.mark_pdc_parts_ordered_377(uuid,integer,uuid)','EXECUTE')
   OR has_function_privilege('anon','public.mark_pdc_parts_ordered_377(uuid,integer,uuid)','EXECUTE')
   OR has_function_privilege('service_role','public.mark_pdc_parts_ordered_377(uuid,integer,uuid)','EXECUTE')
   OR NOT has_function_privilege('authenticated','public.mark_pdc_parts_ordered_377(uuid,integer,uuid)','EXECUTE') THEN
  RAISE EXCEPTION 'PDC_377_ACL_TRIGGER_OR_EMPTY_RECEIPT_POSTCONDITION' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260825140000','377_parts_order_requires_eta',array[
 'Server trigger rejects ordered Parts without authoritative typed ETA for every write path',
 'Receipted idempotent ordered RPC with expected-version, replay and direct-call readback',
 'Missing ETA, stale version, received vehicle and unauthorized calls fail closed without state or receipt',
 'UI reenables only after authoritative ETA save and snapshot convergence'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
