-- STAGING ONLY: review repair for receipt-backed milestone authorization,
-- residual booking versioning, exact after-state capture, and drift-safe replay.
BEGIN;
SET LOCAL lock_timeout='20s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-external-completion-20260903134000',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR NOT public.pdc_monitor_staging_guard()
     OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260903133000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260903133000' AND name='navision_seven_update_retention_ledger_20260903')<>1
     OR to_regprocedure('public.complete_external_rft_collection_20260903(uuid,integer,text,boolean,text,uuid)') IS NULL
     OR to_regprocedure('public.pdc_vehicle_first_milestones()') IS NULL
  THEN RAISE EXCEPTION 'PDC_EXTERNAL_COMPLETION_REVIEW_REPAIR_HEAD_MISMATCH' USING errcode='55000'; END IF;
END $guard$;

CREATE TABLE public.pdc_external_completion_authorizations_20260903(
  receipt_id uuid PRIMARY KEY,
  vehicle_id uuid NOT NULL UNIQUE REFERENCES public.vehicles(id) ON DELETE RESTRICT,
  actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  request_sha256 text NOT NULL CHECK(request_sha256~'^[a-f0-9]{64}$'),
  authorized_at timestamptz NOT NULL
);
CREATE TRIGGER pdc_external_completion_authorizations_append_only_20260903
  BEFORE UPDATE OR DELETE ON public.pdc_external_completion_authorizations_20260903
  FOR EACH ROW EXECUTE FUNCTION public.pdc_external_completion_append_only_20260903();
ALTER TABLE public.pdc_external_completion_authorizations_20260903 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_external_completion_authorizations_20260903 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_external_completion_authorizations_20260903 FROM public,anon,authenticated,service_role;

DO $receipt_constraint$
DECLARE c name;
BEGIN
  SELECT conname INTO c FROM pg_constraint
  WHERE conrelid='public.pdc_external_completion_receipts_20260903'::regclass
    AND contype='c' AND pg_get_constraintdef(oid) LIKE '%vehicle_version_after%expected_vehicle_version%';
  IF c IS NULL THEN RAISE EXCEPTION 'PDC_EXTERNAL_COMPLETION_VERSION_CONSTRAINT_NOT_FOUND' USING errcode='55000'; END IF;
  EXECUTE format('ALTER TABLE public.pdc_external_completion_receipts_20260903 DROP CONSTRAINT %I',c);
END $receipt_constraint$;
ALTER TABLE public.pdc_external_completion_receipts_20260903
  ADD COLUMN vehicle_version_before_completion integer;
UPDATE public.pdc_external_completion_receipts_20260903
SET vehicle_version_before_completion=expected_vehicle_version
WHERE vehicle_version_before_completion IS NULL;
ALTER TABLE public.pdc_external_completion_receipts_20260903
  ALTER COLUMN vehicle_version_before_completion SET NOT NULL,
  ADD CONSTRAINT pdc_external_completion_version_sequence_20260903
    CHECK(vehicle_version_before_completion>=expected_vehicle_version AND vehicle_version_after=vehicle_version_before_completion+1);

CREATE OR REPLACE FUNCTION public.pdc_vehicle_first_milestones()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,public AS $milestones$
DECLARE
  v_business_date date:=(clock_timestamp() at time zone 'Australia/Perth')::date;
  v_receipt_backed_external_completion boolean:=false;
BEGIN
  IF tg_op='INSERT' THEN
    IF upper(btrim(coalesce(new.current_location,''))) IN ('PMB','PIT','QC','RFT','COMPLETED') THEN new.date_to_pmb:=coalesce(new.date_to_pmb,v_business_date); END IF;
    IF upper(btrim(coalesce(new.current_location,''))) IN ('RFT','COMPLETED') THEN new.date_to_rft:=coalesce(new.date_to_rft,v_business_date); END IF;
    IF lower(btrim(coalesce(new.lifecycle_state::text,'')))='completed' THEN new.delivered_to_dealer_date:=coalesce(new.delivered_to_dealer_date,v_business_date); END IF;
    RETURN new;
  END IF;

  v_receipt_backed_external_completion:=
    old.delivered_to_dealer_date IS NULL
    AND new.delivered_to_dealer_date IS NULL
    AND new.rft_collected_at IS NOT NULL
    AND lower(btrim(coalesce(new.lifecycle_state::text,'')))='completed'
    AND EXISTS(
      SELECT 1 FROM public.pdc_external_completion_authorizations_20260903 a
      WHERE a.vehicle_id=new.id
        AND a.receipt_id::text=coalesce(new.source_payload->>'external_completion_receipt_id','')
        AND a.actor_id=new.updated_by
    );

  new.date_to_pmb:=coalesce(old.date_to_pmb,new.date_to_pmb,
    CASE WHEN upper(btrim(coalesce(new.current_location,''))) IN ('PMB','PIT','QC','RFT','COMPLETED') THEN v_business_date END);
  new.date_to_rft:=coalesce(old.date_to_rft,new.date_to_rft,
    CASE WHEN upper(btrim(coalesce(new.current_location,''))) IN ('RFT','COMPLETED') THEN v_business_date END);
  new.delivered_to_dealer_date:=CASE
    WHEN v_receipt_backed_external_completion THEN NULL
    ELSE coalesce(old.delivered_to_dealer_date,new.delivered_to_dealer_date,
      CASE WHEN lower(btrim(coalesce(new.lifecycle_state::text,'')))='completed' THEN v_business_date END)
  END;
  RETURN new;
END;
$milestones$;
REVOKE ALL ON FUNCTION public.pdc_vehicle_first_milestones() FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.complete_external_rft_collection_20260903(
  p_vehicle_id uuid,p_expected_vehicle_version integer,p_completion_type text,
  p_operator_approved boolean,p_reason text,p_idempotency_key uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions SET statement_timeout='120s' AS $complete$
DECLARE
  uid uuid:=auth.uid(); actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v public.vehicles%rowtype; old public.pdc_external_completion_receipts_20260903%rowtype;
  b public.workshop_bookings%rowtype; collected public.pdc_rft_transport_lifecycle_receipts_734%rowtype;
  request_payload jsonb; request_sha text; before_state jsonb; after_state jsonb; external_json jsonb; lifecycle_after jsonb;
  collection_evidence jsonb; result jsonb; booking_result jsonb;
  receipt uuid; completed_at timestamptz:=clock_timestamp(); cancelled integer:=0; version_before_completion integer;
  notifications_before bigint; outbox_412_before bigint; outbox_734_before bigint;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'code','wrong_environment'); END IF;
  IF uid IS NULL OR p_vehicle_id IS NULL OR p_expected_vehicle_version IS NULL OR p_expected_vehicle_version<1
     OR p_completion_type IS NULL OR p_operator_approved IS NULL OR p_idempotency_key IS NULL
     OR length(btrim(coalesce(p_reason,''))) NOT BETWEEN 12 AND 500 THEN RETURN jsonb_build_object('ok',false,'code','external_completion_invalid_input'); END IF;
  IF p_completion_type<>'external_non_navision_final_collection' THEN RETURN jsonb_build_object('ok',false,'code','external_completion_type_required'); END IF;
  IF NOT p_operator_approved THEN RETURN jsonb_build_object('ok',false,'code','explicit_operator_approval_required'); END IF;
  IF NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=uid AND lower(r.email)=actor_email AND r.active AND r.account_status='approved' AND r.role IN('operator','administrator') FOR SHARE) THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
  request_payload:=jsonb_build_object('contract','pdc-external-non-navision-final-collection-20260903','vehicle_id',p_vehicle_id,'expected_vehicle_version',p_expected_vehicle_version,'completion_type',p_completion_type,'operator_approved',p_operator_approved,'reason',btrim(p_reason),'idempotency_key',p_idempotency_key,'actor_id',uid);
  request_sha:=encode(extensions.digest(convert_to(request_payload::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-external-completion-actor:'||uid::text||':'||p_idempotency_key::text,0));
  SELECT * INTO old FROM public.pdc_external_completion_receipts_20260903 WHERE actor_id=uid AND idempotency_key=p_idempotency_key;
  IF FOUND THEN
    IF old.request_sha256<>request_sha THEN RETURN jsonb_build_object('ok',false,'code','idempotency_payload_mismatch'); END IF;
    SELECT * INTO v FROM public.vehicles WHERE id=old.vehicle_id;
    IF NOT FOUND OR v.lifecycle_state<>'completed' OR v.current_location<>'Completed' OR v.visible_on_board
       OR v.delivered_to_dealer_date IS NOT NULL OR v.dealer_transit_closed_at IS NOT NULL OR v.dealer_transit_duration_seconds IS NOT NULL
       OR NOT EXISTS(SELECT 1 FROM public.pdc_external_completion_authorizations_20260903 a WHERE a.receipt_id=old.receipt_id AND a.vehicle_id=old.vehicle_id AND a.actor_id=old.actor_id AND a.request_sha256=old.request_sha256)
       OR old.after_state IS DISTINCT FROM jsonb_build_object('vehicle',to_jsonb(v),'pdc_lifecycle',public.pdc_rft_transport_lifecycle_state_734(v.id))
    THEN RETURN jsonb_build_object('ok',false,'code','external_completion_replay_state_drift'); END IF;
    RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false);
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-external-completion-vehicle:'||p_vehicle_id::text,0));
  SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
  IF NOT FOUND OR v.deleted_at IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_found'); END IF;
  IF EXISTS(SELECT 1 FROM public.pdc_external_completion_receipts_20260903 x WHERE x.vehicle_id=v.id) THEN RETURN jsonb_build_object('ok',false,'code','external_completion_already_recorded','data',jsonb_build_object('vehicle_id',v.id,'vehicle_version',v.version)); END IF;
  IF v.version<>p_expected_vehicle_version THEN RETURN jsonb_build_object('ok',false,'code','vehicle_version_conflict','data',jsonb_build_object('vehicle_id',v.id,'vehicle_version',v.version)); END IF;
  IF coalesce(v.source_system_normalized,lower(regexp_replace(coalesce(v.source_system,''),'[^a-z0-9]+','','g'))) IN('navision','microsoft_navision','microsoftnavision')
     OR EXISTS(SELECT 1 FROM public.navision_backend_records n WHERE n.canonical_vehicle_id=v.id AND n.is_current AND n.record_status='current') THEN RETURN jsonb_build_object('ok',false,'code','external_non_navision_vehicle_required'); END IF;
  SELECT * INTO collected FROM public.pdc_rft_transport_lifecycle_receipts_734 r WHERE r.vehicle_id=v.id AND r.action='collected' FOR SHARE;
  IF NOT FOUND OR v.rft_collected_at IS NULL OR v.lifecycle_state<>'rft' OR upper(btrim(coalesce(v.current_location,'')))<>'COLLECTED' THEN RETURN jsonb_build_object('ok',false,'code','recorded_external_collection_required'); END IF;
  IF v.dealer_transit_closed_at IS NOT NULL OR v.dealer_transit_duration_seconds IS NOT NULL OR v.delivered_to_dealer_date IS NOT NULL
     OR EXISTS(SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 r WHERE r.vehicle_id=v.id AND r.action='delivered') THEN RETURN jsonb_build_object('ok',false,'code','navision_delivery_state_not_external'); END IF;
  IF EXISTS(SELECT 1 FROM public.workshop_bookings x WHERE x.vehicle_id=v.id AND x.status::text='started') THEN RETURN jsonb_build_object('ok',false,'code','started_booking_must_be_completed_before_external_completion'); END IF;

  notifications_before:=(SELECT count(*) FROM public.vehicle_notifications);
  outbox_412_before:=(SELECT count(*) FROM public.pdc_rft_transport_salesperson_outbox_412);
  outbox_734_before:=(SELECT count(*) FROM public.pdc_rft_transport_email_outbox_734);
  before_state:=jsonb_build_object('vehicle',to_jsonb(v),'pdc_lifecycle',public.pdc_rft_transport_lifecycle_state_734(v.id));
  FOR b IN SELECT * FROM public.workshop_bookings WHERE vehicle_id=v.id AND status::text NOT IN('completed','deleted','cancelled') ORDER BY id FOR UPDATE LOOP
    booking_result:=public.cancel_workshop_booking(b.id,b.version,'External/non-Navision vehicle completed after recorded collection',jsonb_build_object('source','complete_external_rft_collection_20260903'));
    IF NOT coalesce((booking_result->>'ok')::boolean,false) THEN RAISE EXCEPTION 'PDC_EXTERNAL_COMPLETION_BOOKING_CANCEL_FAILED:%',coalesce(booking_result->>'error',booking_result->>'code','unknown') USING errcode='40001'; END IF;
    cancelled:=cancelled+1;
  END LOOP;
  SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
  IF v.deleted_at IS NOT NULL OR v.lifecycle_state<>'rft' OR upper(btrim(coalesce(v.current_location,'')))<>'COLLECTED'
     OR v.delivered_to_dealer_date IS NOT NULL OR v.dealer_transit_closed_at IS NOT NULL OR v.dealer_transit_duration_seconds IS NOT NULL
  THEN RAISE EXCEPTION 'PDC_EXTERNAL_COMPLETION_STATE_DRIFT_AFTER_BOOKING_CANCEL' USING errcode='40001'; END IF;
  version_before_completion:=v.version;
  receipt:=extensions.uuid_generate_v5('13000000-0000-5000-8000-000000001300'::uuid,uid::text||':'||p_idempotency_key::text);
  collection_evidence:=jsonb_build_object('rft_collection_receipt_id',collected.receipt_id,'rft_collected_at',v.rft_collected_at,'rft_collected_by',v.rft_collected_by,'receipt_evidence',collected.evidence,'physical_collection_recorded',true,'physical_delivery_asserted',false);
  INSERT INTO public.pdc_external_completion_authorizations_20260903(receipt_id,vehicle_id,actor_id,request_sha256,authorized_at)
  VALUES(receipt,v.id,uid,request_sha,completed_at);
  UPDATE public.vehicles SET lifecycle_state='completed',current_location='Completed',visible_on_board=false,
    pmb_stage=NULL,pmb_bay_stage=NULL,pmb_bay_number=NULL,active_workshop_booking_id=NULL,
    workshop_status='queued',workshop_status_updated_at=completed_at,workshop_status_updated_by=uid,
    source_payload=coalesce(source_payload,'{}'::jsonb)||jsonb_build_object('completion_authority','external_non_navision_final_collection','external_completion_receipt_id',receipt,'external_completion_at',completed_at,'physical_collection_recorded',true,'physical_delivery_asserted',false),
    version=version+1,updated_at=completed_at,updated_by=uid
  WHERE id=v.id AND version=version_before_completion RETURNING * INTO v;
  IF NOT FOUND THEN RAISE EXCEPTION 'PDC_EXTERNAL_COMPLETION_VERSION_DRIFT' USING errcode='40001'; END IF;
  external_json:=jsonb_build_object('receipt_id',receipt,'completion_type',p_completion_type,'operator_approved',true,'reason',btrim(p_reason),'completed_at',completed_at,'completed_by',actor_email,'physical_collection_evidence',collection_evidence,'physical_delivery_asserted',false,'navision_delivery_authority_used',false);
  lifecycle_after:=public.pdc_rft_transport_lifecycle_state_734(v.id)||jsonb_build_object('state','completed','external_completed',true,'lifecycle_state','completed','current_location','Completed','external_completion',external_json);
  after_state:=jsonb_build_object('vehicle',to_jsonb(v),'pdc_lifecycle',lifecycle_after);
  result:=jsonb_build_object('ok',true,'code','external_collection_completed','replay',false,'data',jsonb_build_object('receipt_id',receipt,'vehicle_id',v.id,'vehicle_version_before',p_expected_vehicle_version,'vehicle_version_before_completion',version_before_completion,'vehicle_version_after',v.version,'completion_type',p_completion_type,'completion_authority','external_non_navision_final_collection','completed_at',completed_at,'current_location','Completed','lifecycle_state','completed','cancelled_active_booking_count',cancelled,'physical_collection_recorded',true,'physical_delivery_asserted',false,'navision_delivery_authority_used',false,'dealer_transit_closed_at',null,'dealer_transit_duration_seconds',null,'delivered_to_dealer_date',null));
  INSERT INTO public.pdc_external_completion_receipts_20260903(receipt_id,vehicle_id,expected_vehicle_version,vehicle_version_before_completion,vehicle_version_after,completion_type,operator_approved,reason,actor_id,actor_email,idempotency_key,request_sha256,request_payload,before_state,after_state,physical_collection_evidence,response,completed_at)
  VALUES(receipt,v.id,p_expected_vehicle_version,version_before_completion,v.version,p_completion_type,true,btrim(p_reason),uid,actor_email,p_idempotency_key,request_sha,request_payload,before_state,after_state,collection_evidence,result,completed_at);
  IF after_state IS DISTINCT FROM jsonb_build_object('vehicle',to_jsonb(v),'pdc_lifecycle',public.pdc_rft_transport_lifecycle_state_734(v.id)) THEN RAISE EXCEPTION 'PDC_EXTERNAL_COMPLETION_RECEIPT_STATE_MISMATCH' USING errcode='55000'; END IF;
  INSERT INTO public.vehicle_movements(vehicle_id,from_location,to_location,reason,moved_by) VALUES(v.id,'Collected','Completed','Approved external/non-Navision completion after recorded physical collection; delivery not asserted',uid);
  PERFORM public.audit_pdc_event('update','vehicles',v.id,v.id,before_state->'vehicle',to_jsonb(v),jsonb_build_object('action','complete_external_rft_collection_20260903','receipt_id',receipt,'completion_type',p_completion_type,'operator_approved',true,'reason',btrim(p_reason),'physical_collection_recorded',true,'physical_delivery_asserted',false,'navision_delivery_authority_used',false,'cancelled_active_booking_count',cancelled));
  UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=completed_at WHERE singleton;
  IF v.lifecycle_state<>'completed' OR v.current_location<>'Completed' OR v.visible_on_board OR v.dealer_transit_closed_at IS NOT NULL OR v.dealer_transit_duration_seconds IS NOT NULL OR v.delivered_to_dealer_date IS NOT NULL OR v.active_workshop_booking_id IS NOT NULL
     OR EXISTS(SELECT 1 FROM public.workshop_bookings x WHERE x.vehicle_id=v.id AND x.status::text NOT IN('completed','deleted','cancelled'))
     OR (SELECT count(*) FROM public.vehicle_notifications)<>notifications_before OR (SELECT count(*) FROM public.pdc_rft_transport_salesperson_outbox_412)<>outbox_412_before OR (SELECT count(*) FROM public.pdc_rft_transport_email_outbox_734)<>outbox_734_before
  THEN RAISE EXCEPTION 'PDC_EXTERNAL_COMPLETION_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
  RETURN result;
EXCEPTION WHEN unique_violation THEN
  RETURN jsonb_build_object('ok',false,'code','external_completion_conflict');
END $complete$;
REVOKE ALL ON FUNCTION public.complete_external_rft_collection_20260903(uuid,integer,text,boolean,text,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.complete_external_rft_collection_20260903(uuid,integer,text,boolean,text,uuid) TO authenticated;

DO $post$
BEGIN
  IF has_table_privilege('authenticated','public.pdc_external_completion_authorizations_20260903','SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
     OR (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid='public.pdc_external_completion_authorizations_20260903'::regclass) IS DISTINCT FROM true
     OR NOT has_function_privilege('authenticated','public.complete_external_rft_collection_20260903(uuid,integer,text,boolean,text,uuid)','execute')
     OR has_function_privilege('anon','public.complete_external_rft_collection_20260903(uuid,integer,text,boolean,text,uuid)','execute')
  THEN RAISE EXCEPTION 'PDC_EXTERNAL_COMPLETION_REVIEW_REPAIR_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260903134000','external_completion_review_repairs_20260903',ARRAY[
  'Receipt-backed private milestone authorization replaces mutable source-marker authority',
  'Residual booking cancellation version deltas are captured before the single completion increment',
  'Immutable receipt after_state equals authoritative post-insert lifecycle readback',
  'Exact replay fails closed when current critical state, authorization, or receipt snapshot drifts'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
