-- STAGING ONLY 407: canonical whole-minute Workshop stage estimate editing.
-- One atomic action records a durable manual stage delta and cascades the exact
-- booking duration. Raw source-operation estimates remain immutable evidence.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-407-workshop-stage-estimated-minutes',0));

DO $guard$
DECLARE v_head text;
BEGIN
  SELECT max(version) INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$';
  IF current_user<>'postgres' OR session_user<>'postgres'
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR v_head IS DISTINCT FROM '20260826154500'
    OR to_regclass('public.vehicle_workshop_line_adjustments') IS NULL
    OR to_regprocedure('public.cascade_workshop_schedule(text,uuid,integer,text,integer,timestamp with time zone,integer,uuid,integer,text,jsonb)') IS NULL
    OR to_regprocedure('public.workshop_vehicle_stage_estimated_duration_minutes(uuid,uuid)') IS NULL
    OR (SELECT count(*) FROM public.vehicle_notifications)<>1 THEN
    RAISE EXCEPTION 'PDC_407_STAGING_HEAD_OR_CONTAINMENT_MISMATCH' USING errcode='55000';
  END IF;
END $guard$;

CREATE TABLE public.pdc_workshop_stage_estimate_receipts_407(
  receipt_id uuid PRIMARY KEY,
  actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  actor_email text NOT NULL,
  vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
  booking_id uuid NOT NULL REFERENCES public.workshop_bookings(id) ON DELETE RESTRICT,
  stage_code text NOT NULL,
  total_minutes integer NOT NULL CHECK(total_minutes BETWEEN 1 AND 59999),
  idempotency_key uuid NOT NULL,
  request_sha256 text NOT NULL CHECK(request_sha256~'^[0-9a-f]{64}$'),
  request_payload jsonb NOT NULL,
  response jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(actor_id,idempotency_key)
);
ALTER TABLE public.pdc_workshop_stage_estimate_receipts_407 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_workshop_stage_estimate_receipts_407 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_workshop_stage_estimate_receipts_407 FROM public,anon,authenticated,service_role;

-- The new RPC owns adjustment + cascade atomically. Suppress only the legacy
-- immediate reconciler inside that exact transaction; every other writer keeps
-- the existing trigger behaviour.
CREATE OR REPLACE FUNCTION public.workshop_reconcile_adjustment_booking_duration()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $trigger$
BEGIN
  IF current_setting('pdc.defer_workshop_adjustment_reconcile',true)='407' THEN RETURN NULL; END IF;
  IF tg_op IN('UPDATE','DELETE') AND old.active THEN
    PERFORM public.workshop_sync_vehicle_stage_booking_duration(old.vehicle_id,old.stage_code,'workshop_adjustment_'||lower(tg_op));
  END IF;
  IF tg_op IN('UPDATE','INSERT') AND new.active AND (tg_op='INSERT' OR new.vehicle_id IS DISTINCT FROM old.vehicle_id OR new.stage_code IS DISTINCT FROM old.stage_code OR new.estimated_hours IS DISTINCT FROM old.estimated_hours OR new.active IS DISTINCT FROM old.active) THEN
    PERFORM public.workshop_sync_vehicle_stage_booking_duration(new.vehicle_id,new.stage_code,'workshop_adjustment_'||lower(tg_op));
  END IF;
  RETURN NULL;
END $trigger$;
REVOKE ALL ON FUNCTION public.workshop_reconcile_adjustment_booking_duration() FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.pdc_reconcile_required_work_after_adjustment_322()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $required$
BEGIN
  IF current_setting('pdc.defer_workshop_required_work_reconcile',true)='407' THEN RETURN NULL; END IF;
  IF tg_op IN('UPDATE','DELETE') THEN PERFORM public.pdc_auditor_recalculate_required_work_226(ARRAY[old.vehicle_id]); END IF;
  IF tg_op IN('INSERT','UPDATE') AND (tg_op='INSERT' OR new.vehicle_id IS DISTINCT FROM old.vehicle_id OR new.stage_code IS DISTINCT FROM old.stage_code OR new.active IS DISTINCT FROM old.active) THEN
    PERFORM public.pdc_auditor_recalculate_required_work_226(ARRAY[new.vehicle_id]);
  END IF;
  RETURN NULL;
END $required$;
REVOKE ALL ON FUNCTION public.pdc_reconcile_required_work_after_adjustment_322() FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.set_workshop_stage_estimated_minutes_407(
  p_vehicle_id uuid,
  p_expected_vehicle_version integer,
  p_booking_id uuid,
  p_expected_booking_version integer,
  p_stage_code text,
  p_total_minutes integer,
  p_idempotency_key uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions SET statement_timeout='120s' AS $set$
DECLARE
  v_actor uuid:=auth.uid(); v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_stage text:=public.workshop_canonical_stage_code(p_stage_code); v_stage_id uuid; v_bay_number integer;
  v_vehicle public.vehicles%rowtype; v_booking public.workshop_bookings%rowtype;
  v_adjustment public.vehicle_workshop_line_adjustments%rowtype; v_before_adjustment jsonb; v_after_adjustment jsonb;
  v_line_key text; v_current_minutes integer; v_manual_minutes integer:=0; v_base_minutes integer; v_delta_minutes integer; v_delta_hours numeric;
  v_authoritative_minutes integer; v_cascade jsonb; v_request jsonb; v_request_sha text; v_response jsonb; v_existing public.pdc_workshop_stage_estimate_receipts_407%rowtype; v_receipt_id uuid;
BEGIN
  IF v_actor IS NULL OR p_vehicle_id IS NULL OR p_expected_vehicle_version IS NULL OR p_booking_id IS NULL OR p_expected_booking_version IS NULL OR v_stage IS NULL OR p_total_minutes IS NULL OR p_total_minutes NOT BETWEEN 1 AND 59999 OR p_idempotency_key IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','invalid_stage_estimate_input');
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=v_actor AND lower(r.email)=v_email AND r.active AND r.account_status='approved' AND r.role IN('operator','administrator') FOR SHARE) THEN
    RETURN jsonb_build_object('ok',false,'code','not_authorized');
  END IF;
  v_request:=jsonb_build_object('contract','pdc-workshop-stage-estimated-minutes-407','vehicle_id',p_vehicle_id,'expected_vehicle_version',p_expected_vehicle_version,'booking_id',p_booking_id,'expected_booking_version',p_expected_booking_version,'stage_code',v_stage,'total_minutes',p_total_minutes,'idempotency_key',p_idempotency_key,'actor_id',v_actor);
  v_request_sha:=encode(extensions.digest(convert_to(v_request::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-407-stage-estimate-actor:'||v_actor::text||':'||p_idempotency_key::text,0));
  SELECT * INTO v_existing FROM public.pdc_workshop_stage_estimate_receipts_407 WHERE actor_id=v_actor AND idempotency_key=p_idempotency_key;
  IF FOUND THEN
    IF v_existing.request_sha256<>v_request_sha THEN RETURN jsonb_build_object('ok',false,'code','idempotency_payload_mismatch'); END IF;
    RETURN v_existing.response||jsonb_build_object('replay',true);
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-407-stage-estimate-vehicle:'||p_vehicle_id::text,0));
  SELECT * INTO v_vehicle FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
  IF NOT FOUND OR v_vehicle.deleted_at IS NOT NULL OR v_vehicle.lifecycle_state<>'active' THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_found'); END IF;
  IF v_vehicle.version<>p_expected_vehicle_version THEN RETURN jsonb_build_object('ok',false,'code','vehicle_version_conflict','data',jsonb_build_object('current_version',v_vehicle.version)); END IF;
  SELECT id INTO v_stage_id FROM public.workshop_stages WHERE code=v_stage AND active FOR SHARE;
  IF v_stage_id IS NULL THEN RETURN jsonb_build_object('ok',false,'code','stage_not_found'); END IF;
  IF NOT EXISTS(SELECT 1 FROM public.vehicle_work_items wi WHERE wi.vehicle_id=p_vehicle_id AND wi.required AND NOT wi.completed AND public.workshop_canonical_stage_code(wi.work_key)=v_stage FOR SHARE) THEN
    RETURN jsonb_build_object('ok',false,'code','canonical_requirement_missing_or_completed');
  END IF;
  SELECT * INTO v_booking FROM public.workshop_bookings WHERE id=p_booking_id AND vehicle_id=p_vehicle_id AND stage_id=v_stage_id AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND OR v_booking.status::text NOT IN('queued','planned') THEN RETURN jsonb_build_object('ok',false,'code','booking_not_editable'); END IF;
  IF v_booking.version<>p_expected_booking_version THEN RETURN jsonb_build_object('ok',false,'code','version_conflict','data',jsonb_build_object('current_version',v_booking.version)); END IF;
  SELECT bay_number INTO v_bay_number FROM public.workshop_bays WHERE id=v_booking.bay_id AND is_active FOR SHARE;
  IF v_bay_number IS NULL THEN RETURN jsonb_build_object('ok',false,'code','bay_inactive_or_wrong_station'); END IF;

  v_line_key:='manual:planner-stage:'||v_stage;
  SELECT * INTO v_adjustment FROM public.vehicle_workshop_line_adjustments WHERE vehicle_id=p_vehicle_id AND line_key=v_line_key FOR UPDATE;
  IF FOUND AND v_adjustment.active THEN v_manual_minutes:=round(coalesce(v_adjustment.estimated_hours,0)*60)::integer; END IF;
  v_current_minutes:=coalesce(public.workshop_vehicle_stage_estimated_duration_minutes(p_vehicle_id,v_stage_id),0);
  v_base_minutes:=greatest(0,v_current_minutes-v_manual_minutes);
  IF p_total_minutes<v_base_minutes THEN
    RETURN jsonb_build_object('ok',false,'code','estimated_minutes_below_authenticated_work','data',jsonb_build_object('minimum_minutes',v_base_minutes));
  END IF;
  v_delta_minutes:=p_total_minutes-v_base_minutes;
  v_delta_hours:=round(v_delta_minutes::numeric/60,2);
  PERFORM set_config('pdc.hermes_test_wrapper_vehicle_365',p_vehicle_id::text,true);
  PERFORM set_config('pdc.defer_workshop_adjustment_reconcile','407',true);
  PERFORM set_config('pdc.defer_workshop_required_work_reconcile','407',true);
  v_before_adjustment:=CASE WHEN v_adjustment.adjustment_id IS NULL THEN NULL ELSE to_jsonb(v_adjustment) END;
  IF v_delta_minutes=0 THEN
    IF v_adjustment.adjustment_id IS NOT NULL AND v_adjustment.active THEN
      UPDATE public.vehicle_workshop_line_adjustments SET active=false,version=version+1,updated_by=v_actor,updated_at=clock_timestamp() WHERE adjustment_id=v_adjustment.adjustment_id RETURNING * INTO v_adjustment;
    END IF;
  ELSIF v_adjustment.adjustment_id IS NULL THEN
    INSERT INTO public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,correction_origin,active,version,created_by,updated_by)
    VALUES(p_vehicle_id,v_line_key,'manual',v_stage,'Planner stage time adjustment',v_delta_hours,'manual_operator',true,1,v_actor,v_actor) RETURNING * INTO v_adjustment;
  ELSE
    UPDATE public.vehicle_workshop_line_adjustments SET stage_code=v_stage,description='Planner stage time adjustment',estimated_hours=v_delta_hours,correction_origin='manual_operator',active=true,version=version+1,updated_by=v_actor,updated_at=clock_timestamp() WHERE adjustment_id=v_adjustment.adjustment_id RETURNING * INTO v_adjustment;
  END IF;
  v_after_adjustment:=CASE WHEN v_adjustment.adjustment_id IS NULL THEN NULL ELSE to_jsonb(v_adjustment) END;
  PERFORM set_config('pdc.defer_workshop_adjustment_reconcile','',true);
  PERFORM set_config('pdc.defer_workshop_required_work_reconcile','',true);
  v_authoritative_minutes:=coalesce(public.workshop_vehicle_stage_estimated_duration_minutes(p_vehicle_id,v_stage_id),0);
  IF v_authoritative_minutes<>p_total_minutes THEN RAISE EXCEPTION 'PDC_407_CANONICAL_MINUTE_RECONCILIATION_FAILED expected %, got %',p_total_minutes,v_authoritative_minutes USING errcode='55000'; END IF;

  v_cascade:=public.cascade_workshop_schedule(
    'extend',
    p_booking_id,p_expected_booking_version,v_stage,v_bay_number,v_booking.scheduled_start_at,p_total_minutes,NULL,
    greatest(0,p_total_minutes-v_booking.default_duration_minutes),NULL,
    jsonb_build_object('source','stage_estimated_minutes_407','request_id',p_idempotency_key,'canonical_minutes',p_total_minutes,'base_authenticated_minutes',v_base_minutes,'manual_delta_minutes',v_delta_minutes));
  IF coalesce((v_cascade->>'ok')::boolean,false) IS NOT TRUE THEN RAISE EXCEPTION 'PDC_407_CASCADE_FAILED: %',v_cascade USING errcode='55000'; END IF;
  SELECT * INTO v_booking FROM public.workshop_bookings WHERE id=p_booking_id;
  IF v_booking.default_duration_minutes<>p_total_minutes THEN RAISE EXCEPTION 'PDC_407_BOOKING_READBACK_FAILED' USING errcode='55000'; END IF;
  v_receipt_id:=extensions.uuid_generate_v5('40700000-0000-5000-8000-000000000407'::uuid,'stage-estimate:'||v_actor::text||':'||p_idempotency_key::text);
  v_response:=jsonb_build_object('ok',true,'code','workshop_stage_estimated_minutes_saved','replay',false,'receipt_id',v_receipt_id,'vehicle_id',p_vehicle_id,'vehicle_version',v_vehicle.version,'booking_id',p_booking_id,'booking_version',v_booking.version,'stage_code',v_stage,'base_authenticated_minutes',v_base_minutes,'manual_delta_minutes',v_delta_minutes,'total_minutes',p_total_minutes,'adjustment',v_after_adjustment,'cascade',v_cascade);
  INSERT INTO public.pdc_workshop_stage_estimate_receipts_407(receipt_id,actor_id,actor_email,vehicle_id,booking_id,stage_code,total_minutes,idempotency_key,request_sha256,request_payload,response)
  VALUES(v_receipt_id,v_actor,v_email,p_vehicle_id,p_booking_id,v_stage,p_total_minutes,p_idempotency_key,v_request_sha,v_request,v_response);
  IF v_adjustment.adjustment_id IS NOT NULL THEN
    INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
    VALUES(CASE WHEN v_before_adjustment IS NULL THEN 'insert'::public.audit_action ELSE 'update'::public.audit_action END,'vehicle_workshop_line_adjustments',v_adjustment.adjustment_id,p_vehicle_id,v_actor,v_email,v_before_adjustment,v_after_adjustment,jsonb_build_object('action','set_workshop_stage_estimated_minutes_407','receipt_id',v_receipt_id,'stage_code',v_stage,'base_authenticated_minutes',v_base_minutes,'manual_delta_minutes',v_delta_minutes,'total_minutes',p_total_minutes,'booking_id',p_booking_id));
  END IF;
  RETURN v_response;
EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('pdc.defer_workshop_adjustment_reconcile','',true);
  PERFORM set_config('pdc.defer_workshop_required_work_reconcile','',true);
  RAISE;
END $set$;
REVOKE ALL ON FUNCTION public.set_workshop_stage_estimated_minutes_407(uuid,integer,uuid,integer,text,integer,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.set_workshop_stage_estimated_minutes_407(uuid,integer,uuid,integer,text,integer,uuid) TO authenticated;

DO $post$
DECLARE d text:=pg_get_functiondef('public.set_workshop_stage_estimated_minutes_407(uuid,integer,uuid,integer,text,integer,uuid)'::regprocedure);
BEGIN
  IF position('pdc.defer_workshop_adjustment_reconcile' in d)=0 OR position('cascade_workshop_schedule' in d)=0 OR position('workshop_vehicle_stage_estimated_duration_minutes' in d)=0 OR position('pdc.hermes_test_wrapper_vehicle_365' in d)=0
    OR has_function_privilege('public','public.set_workshop_stage_estimated_minutes_407(uuid,integer,uuid,integer,text,integer,uuid)','EXECUTE')
    OR has_function_privilege('anon','public.set_workshop_stage_estimated_minutes_407(uuid,integer,uuid,integer,text,integer,uuid)','EXECUTE')
    OR has_function_privilege('service_role','public.set_workshop_stage_estimated_minutes_407(uuid,integer,uuid,integer,text,integer,uuid)','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.set_workshop_stage_estimated_minutes_407(uuid,integer,uuid,integer,text,integer,uuid)','EXECUTE')
    OR (SELECT count(*) FROM public.vehicle_notifications)<>1 THEN RAISE EXCEPTION 'PDC_407_POSTCONDITION' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826160000','407_workshop_stage_estimated_minutes',ARRAY[
  'Accept clean decimal-hour UI values by canonicalising once to whole minutes',
  'Persist one deterministic manual stage delta and atomically cascade the exact booking duration',
  'Preserve immutable authenticated operation evidence, optimistic versions, replay receipts, conflicts and staging containment'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
