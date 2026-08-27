-- STAGING ONLY 702: repair final Collected projection for the live NOT NULL
-- workshop_status contract. Applied 700/701 remain immutable; the neutral
-- queued value means no active workshop booking while preserving the schema.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-702-final-collected-status-repair',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $pre$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260827102000'
     OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260827102000' AND name='701_final_qc_two_transition_repair')
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260827102000')
     OR to_regprocedure('public.collect_rft_transport_700(uuid,integer,uuid)') IS NULL
  THEN RAISE EXCEPTION 'PDC_702_EXACT_701_PRESTATE_REQUIRED' USING errcode='55000'; END IF;
END $pre$;

CREATE OR REPLACE FUNCTION public.collect_rft_transport_700(
  p_vehicle_id uuid,p_expected_vehicle_version integer,p_idempotency_key uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions SET statement_timeout='120s' AS $collect$
DECLARE
  uid uuid:=auth.uid(); actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); v public.vehicles%rowtype; old public.pdc_final_pdc_lifecycle_receipts_700%rowtype; b public.workshop_bookings%rowtype;
  request_payload jsonb; request_sha text; before_state jsonb; after_state jsonb; receipt uuid; result jsonb; cancelled integer:=0; movement uuid; booking_result jsonb; collected_at timestamptz:=clock_timestamp();
BEGIN
  IF uid IS NULL OR p_vehicle_id IS NULL OR p_expected_vehicle_version IS NULL OR p_expected_vehicle_version<1 OR p_idempotency_key IS NULL THEN RETURN jsonb_build_object('ok',false,'code','collection_invalid_input'); END IF;
  IF NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=uid AND lower(r.email)=actor_email AND r.active AND r.account_status='approved' AND r.role IN('operator','administrator') FOR SHARE) THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
  request_payload:=jsonb_build_object('contract','pdc-final-rft-collected-700','vehicle_id',p_vehicle_id,'expected_vehicle_version',p_expected_vehicle_version,'idempotency_key',p_idempotency_key);
  request_sha:=encode(extensions.digest(convert_to(request_payload::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-702-collect-actor:'||uid::text||':'||p_idempotency_key::text,0));
  SELECT * INTO old FROM public.pdc_final_pdc_lifecycle_receipts_700 WHERE actor_id=uid AND idempotency_key=p_idempotency_key;
  IF FOUND THEN IF old.request_sha256<>request_sha THEN RETURN jsonb_build_object('ok',false,'code','idempotency_payload_mismatch'); END IF; RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false); END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-702-collect-vehicle:'||p_vehicle_id::text,0));
  SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
  IF NOT FOUND OR v.deleted_at IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_found'); END IF;
  SELECT * INTO old FROM public.pdc_final_pdc_lifecycle_receipts_700 WHERE vehicle_id=p_vehicle_id AND action='collected';
  IF FOUND THEN RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false); END IF;
  IF v.version<>p_expected_vehicle_version THEN RETURN jsonb_build_object('ok',false,'code','vehicle_version_conflict','data',jsonb_build_object('vehicle_id',v.id,'vehicle_version',v.version)); END IF;
  IF v.lifecycle_state<>'rft' OR upper(btrim(coalesce(v.current_location,'')))<>'RFT' THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_in_rft'); END IF;
  IF NOT EXISTS(SELECT 1 FROM public.pdc_final_pdc_lifecycle_receipts_700 WHERE vehicle_id=v.id AND action='rft_booked') OR v.dealer_transit_started_at IS NULL THEN RETURN jsonb_build_object('ok',false,'code','transport_booking_required'); END IF;
  IF EXISTS(SELECT 1 FROM public.workshop_bookings x WHERE x.vehicle_id=v.id AND x.status::text='started') THEN RETURN jsonb_build_object('ok',false,'code','started_booking_must_be_completed_before_collection'); END IF;
  before_state:=jsonb_build_object('vehicle',to_jsonb(v),'state','RFT','timer_started_at',v.dealer_transit_started_at);
  FOR b IN SELECT * FROM public.workshop_bookings WHERE vehicle_id=v.id AND status::text NOT IN('completed','deleted','cancelled') ORDER BY id FOR UPDATE LOOP
    booking_result:=public.cancel_workshop_booking(b.id,b.version,'Vehicle collected from RFT',jsonb_build_object('source','collect_rft_transport_702'));
    IF NOT coalesce((booking_result->>'ok')::boolean,false) THEN RAISE EXCEPTION 'PDC_702_BOOKING_CANCEL_FAILED:%',coalesce(booking_result->>'error',booking_result->>'code','unknown') USING errcode='40001'; END IF;
    cancelled:=cancelled+1;
  END LOOP;
  UPDATE public.vehicles SET current_location='Collected',lifecycle_state='rft',rft_collected_at=collected_at,rft_collected_by=uid,visible_on_board=false,pmb_stage=NULL,pmb_bay_stage=NULL,pmb_bay_number=NULL,active_workshop_booking_id=NULL,workshop_status='queued',workshop_status_updated_at=collected_at,workshop_status_updated_by=uid,version=version+1,updated_at=collected_at,updated_by=uid WHERE id=v.id RETURNING * INTO v;
  INSERT INTO public.vehicle_movements(vehicle_id,from_location,to_location,from_pmb_stage,to_pmb_stage,from_pmb_bay_stage,to_pmb_bay_stage,from_pmb_bay_number,to_pmb_bay_number,reason,moved_by)
  VALUES(v.id,'RFT','Collected',NULL,NULL,NULL,NULL,NULL,NULL,'RFT vehicle physically collected; dealer transit timer remains open',uid) RETURNING id INTO movement;
  after_state:=jsonb_build_object('vehicle',to_jsonb(v),'state','Collected','collected_at',collected_at,'timer_started_at',v.dealer_transit_started_at,'timer_closed',false);
  receipt:=extensions.uuid_generate_v5('70000000-0000-5000-8000-000000000700'::uuid,uid::text||':collect:'||p_idempotency_key::text);
  result:=jsonb_build_object('ok',true,'code','rft_vehicle_collected','replay',false,'data',jsonb_build_object('receipt_id',receipt,'vehicle_id',v.id,'vehicle_version_before',p_expected_vehicle_version,'vehicle_version_after',v.version,'collected_at',collected_at,'current_location','Collected','lifecycle_state','rft','dealer_transit_started_at',v.dealer_transit_started_at,'dealer_transit_closed_at',null,'dealer_transit_duration_seconds',null,'cancelled_active_booking_count',cancelled,'movement_id',movement,'timer_closed',false));
  INSERT INTO public.pdc_final_pdc_lifecycle_receipts_700(receipt_id,vehicle_id,action,actor_id,actor_email,idempotency_key,request_sha256,request_payload,before_state,after_state,evidence,response)
  VALUES(receipt,v.id,'collected',uid,actor_email,p_idempotency_key,request_sha,request_payload,before_state,after_state,jsonb_build_object('collected_at',collected_at,'cancelled_active_booking_count',cancelled,'cleared_active_bay',true,'workshop_status_neutralized','queued','workshop_booking_history_retained',true,'timer_closed',false,'completed',false),result);
  PERFORM public.audit_pdc_event('update','vehicles',v.id,v.id,before_state->'vehicle',to_jsonb(v),jsonb_build_object('action','collect_rft_transport_702','receipt_id',receipt,'movement_id',movement,'cancelled_active_booking_count',cancelled,'timer_closed',false,'completed',false));
  RETURN result;
EXCEPTION WHEN unique_violation THEN
  SELECT * INTO old FROM public.pdc_final_pdc_lifecycle_receipts_700 WHERE actor_id=uid AND idempotency_key=p_idempotency_key;
  IF FOUND THEN RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false); END IF;
  SELECT * INTO old FROM public.pdc_final_pdc_lifecycle_receipts_700 WHERE vehicle_id=p_vehicle_id AND action='collected';
  IF FOUND THEN RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false); END IF;
  RETURN jsonb_build_object('ok',false,'code','collection_conflict');
END $collect$;
REVOKE ALL ON FUNCTION public.collect_rft_transport_700(uuid,integer,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.collect_rft_transport_700(uuid,integer,uuid) TO authenticated;

DO $post$
DECLARE d text;
BEGIN
 SELECT pg_get_functiondef('public.collect_rft_transport_700(uuid,integer,uuid)'::regprocedure) INTO d;
 IF position('workshop_status=''queued''' in d)=0 OR NOT has_function_privilege('authenticated','public.collect_rft_transport_700(uuid,integer,uuid)','EXECUTE') OR has_function_privilege('anon','public.collect_rft_transport_700(uuid,integer,uuid)','EXECUTE') THEN RAISE EXCEPTION 'PDC_702_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260827103000','702_final_collected_workshop_status_repair',ARRAY['Preserve the live vehicles workshop_status NOT NULL contract by neutralizing collected rows to queued while clearing active bay/booking pointers','Applied 700/701 receipts, state, timer, email outbox and audit history are preserved; Production untouched']);
NOTIFY pgrst,'reload schema';
COMMIT;
