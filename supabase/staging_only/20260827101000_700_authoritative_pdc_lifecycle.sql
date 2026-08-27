-- STAGING ONLY 700: final authoritative PDC lifecycle successor.
--
-- This is append-only over the live 672 ledger. It preserves the applied
-- 169/399/412/428/429/481 contracts as historical evidence while routing all
-- new QC -> RFT -> booked -> Collected -> Delivered actions through one
-- canonical, server-authoritative state machine. Production is forbidden.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-700-final-authoritative-lifecycle',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $pre$
DECLARE
  v_reconcile_hash text;
  v_snapshot_hash text;
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260827067200'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260827067200' AND name='672_authenticated_active_email_monitor_identity_successor')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260827067200')
     OR to_regclass('public.pdc_email_monitor_authenticated_active_capability_controls_672') IS NULL
     OR to_regprocedure('public.reconcile_navision_operational_record(uuid,uuid,text)') IS NULL
     OR to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()') IS NULL
     OR to_regprocedure('public.pdc_qc_operation_lines_379(uuid)') IS NULL
     OR to_regprocedure('public.pdc_rft_transport_snapshot_412(uuid)') IS NULL
     OR to_regclass('public.pdc_qc_finalization_photo_evidence_399') IS NULL
     OR to_regclass('public.pdc_qc_finalization_receipts_399') IS NULL
     OR to_regclass('public.pdc_rft_transport_action_receipts_412') IS NULL
     OR to_regclass('public.pdc_rft_transport_salesperson_outbox_412') IS NULL
  THEN
    RAISE EXCEPTION 'PDC_700_EXACT_STAGING_671_PRESTATE_REQUIRED' USING errcode='55000';
  END IF;
  SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.reconcile_navision_operational_record(uuid,uuid,text)'::regprocedure),'UTF8'),'sha256'),'hex') INTO v_reconcile_hash;
  SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.get_pdc_email_vehicle_location_snapshot()'::regprocedure),'UTF8'),'sha256'),'hex') INTO v_snapshot_hash;
  IF v_reconcile_hash<>'2b2201e6cf5a5b13ef07250fe94c8d2a79375daa9aa93da58cef62432e7723f7'
     OR v_snapshot_hash<>'f383e043dc27e5bcf089cea9b23a8c976df2393bb85c2a727b56f02665ac8691'
  THEN
    RAISE EXCEPTION 'PDC_700_PREDECESSOR_FUNCTION_HASH_MISMATCH' USING errcode='55000';
  END IF;
END $pre$;

ALTER TABLE public.vehicles
  ADD COLUMN IF NOT EXISTS dealer_transit_started_at timestamptz,
  ADD COLUMN IF NOT EXISTS dealer_transit_closed_at timestamptz,
  ADD COLUMN IF NOT EXISTS dealer_transit_duration_seconds bigint;
DO $constraints$
BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conname='vehicles_dealer_transit_duration_nonnegative') THEN
    ALTER TABLE public.vehicles ADD CONSTRAINT vehicles_dealer_transit_duration_nonnegative CHECK(dealer_transit_duration_seconds IS NULL OR dealer_transit_duration_seconds>=0);
  END IF;
END $constraints$;
COMMENT ON COLUMN public.vehicles.dealer_transit_started_at IS 'Immutable exact RFT Booked timestamp that starts the dealer-transit interval.';
COMMENT ON COLUMN public.vehicles.dealer_transit_closed_at IS 'Immutable exact Navision Delivered - At Dealer timestamp that closes the dealer-transit interval.';
COMMENT ON COLUMN public.vehicles.dealer_transit_duration_seconds IS 'Immutable non-negative elapsed dealer-transit duration in whole seconds.';

CREATE TABLE public.pdc_final_pdc_lifecycle_receipts_700(
  receipt_id uuid PRIMARY KEY,
  vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
  action text NOT NULL CHECK(action IN('qc_signed_off','rft_booked','collected','delivered')),
  actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  actor_email text NOT NULL CHECK(length(btrim(actor_email))>3),
  idempotency_key uuid NOT NULL,
  request_sha256 text NOT NULL CHECK(request_sha256~'^[a-f0-9]{64}$'),
  request_payload jsonb NOT NULL CHECK(jsonb_typeof(request_payload)='object'),
  before_state jsonb NOT NULL CHECK(jsonb_typeof(before_state)='object'),
  after_state jsonb NOT NULL CHECK(jsonb_typeof(after_state)='object'),
  evidence jsonb NOT NULL CHECK(jsonb_typeof(evidence)='object'),
  response jsonb NOT NULL CHECK(jsonb_typeof(response)='object'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(vehicle_id,action),
  UNIQUE(actor_id,idempotency_key)
);
CREATE INDEX pdc_final_pdc_lifecycle_receipts_700_vehicle_idx ON public.pdc_final_pdc_lifecycle_receipts_700(vehicle_id,created_at,action);
ALTER TABLE public.pdc_final_pdc_lifecycle_receipts_700 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_final_pdc_lifecycle_receipts_700 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_final_pdc_lifecycle_receipts_700 FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.pdc_final_pdc_lifecycle_receipt_immutable_700()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN RAISE EXCEPTION 'PDC_700_LIFECYCLE_RECEIPT_IMMUTABLE' USING errcode='55000'; END $$;
REVOKE ALL ON FUNCTION public.pdc_final_pdc_lifecycle_receipt_immutable_700() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_final_pdc_lifecycle_receipt_immutable_700
  BEFORE UPDATE OR DELETE ON public.pdc_final_pdc_lifecycle_receipts_700
  FOR EACH ROW EXECUTE FUNCTION public.pdc_final_pdc_lifecycle_receipt_immutable_700();

-- Legacy 399 creates historical evidence only. It is no longer callable by
-- the authenticated UI; the final QC RPC below never creates a 399 outbox row.
REVOKE EXECUTE ON FUNCTION public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid) FROM authenticated;
COMMENT ON TABLE public.pdc_qc_salesperson_update_outbox_399 IS
  'Historical 399 QC evidence only. Non-dispatchable; final lifecycle 700 owns the sole salesperson email outbox at RFT Booked.';

CREATE OR REPLACE FUNCTION public.finalize_pdc_qc_to_rft_700(
  p_vehicle_id uuid,
  p_expected_vehicle_version integer,
  p_photo_receipt_id uuid,
  p_idempotency_key uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions SET statement_timeout='120s' AS $qc$
DECLARE
  uid uuid:=auth.uid();
  actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v public.vehicles%rowtype;
  v_after public.vehicles%rowtype;
  photo public.pdc_qc_finalization_photo_evidence_399%rowtype;
  old public.pdc_final_pdc_lifecycle_receipts_700%rowtype;
  lines_all jsonb; lines jsonb;
  request_payload jsonb; request_sha text; before_state jsonb; after_state jsonb;
  receipt uuid; result jsonb; notifications_before bigint; notifications_after bigint;
BEGIN
  IF uid IS NULL OR p_vehicle_id IS NULL OR p_expected_vehicle_version IS NULL OR p_expected_vehicle_version<1 OR p_photo_receipt_id IS NULL OR p_idempotency_key IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','qc_finalization_invalid_input');
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=uid AND lower(r.email)=actor_email AND r.active AND r.account_status='approved' AND r.role IN('operator','administrator') FOR SHARE) THEN
    RETURN jsonb_build_object('ok',false,'code','not_authorized');
  END IF;
  request_payload:=jsonb_build_object('contract','pdc-final-authoritative-qc-to-rft-700','vehicle_id',p_vehicle_id,'expected_vehicle_version',p_expected_vehicle_version,'photo_receipt_id',p_photo_receipt_id,'idempotency_key',p_idempotency_key);
  request_sha:=encode(extensions.digest(convert_to(request_payload::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-700-qc-actor:'||uid::text||':'||p_idempotency_key::text,0));
  SELECT * INTO old FROM public.pdc_final_pdc_lifecycle_receipts_700 WHERE actor_id=uid AND idempotency_key=p_idempotency_key;
  IF FOUND THEN
    IF old.request_sha256<>request_sha THEN RETURN jsonb_build_object('ok',false,'code','idempotency_payload_mismatch'); END IF;
    RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false);
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-700-qc-vehicle:'||p_vehicle_id::text,0));
  SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
  IF NOT FOUND OR v.deleted_at IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_found'); END IF;
  SELECT * INTO old FROM public.pdc_final_pdc_lifecycle_receipts_700 WHERE vehicle_id=p_vehicle_id AND action='qc_signed_off';
  IF FOUND THEN RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false); END IF;
  IF v.version<>p_expected_vehicle_version THEN RETURN jsonb_build_object('ok',false,'code','vehicle_version_conflict','data',jsonb_build_object('vehicle_id',p_vehicle_id,'vehicle_version',v.version)); END IF;
  IF v.lifecycle_state<>'active' OR upper(btrim(coalesce(v.current_location,'')))<>'QC' THEN RETURN jsonb_build_object('ok',false,'code','qc_vehicle_not_in_qc'); END IF;
  SELECT * INTO photo FROM public.pdc_qc_finalization_photo_evidence_399 WHERE photo_receipt_id=p_photo_receipt_id AND vehicle_id=p_vehicle_id FOR SHARE;
  IF NOT FOUND OR photo.bucket_id<>'pdc-qc-evidence-staging' OR photo.content_type NOT LIKE 'image/%' OR photo.byte_length NOT BETWEEN 1 AND 1048576 THEN RETURN jsonb_build_object('ok',false,'code','qc_photo_receipt_required'); END IF;
  lines_all:=public.pdc_qc_operation_lines_379(p_vehicle_id);
  lines:=coalesce((SELECT jsonb_agg(line ORDER BY line->>'stage_code',line->>'operation_no',line->>'line_identity') FROM jsonb_array_elements(lines_all) line WHERE coalesce((line->>'active')::boolean,false)),'[]'::jsonb);
  IF jsonb_array_length(lines)=0 OR EXISTS(SELECT 1 FROM jsonb_array_elements(lines) line WHERE NOT coalesce((line->>'completed')::boolean,false) OR (line->>'estimated_hours') IS NULL) THEN RETURN jsonb_build_object('ok',false,'code','qc_operation_lines_incomplete'); END IF;
  LOCK TABLE public.vehicle_notifications IN SHARE MODE;
  notifications_before:=(SELECT count(*) FROM public.vehicle_notifications);
  before_state:=jsonb_build_object('vehicle',to_jsonb(v),'qc_state','QC','email_outbox_399_created',false,'timer_started',false);
  UPDATE public.vehicles SET qc_completed_at=coalesce(qc_completed_at,clock_timestamp()),qc_completed_by=uid,lifecycle_state='rft',current_location='RFT',date_to_rft=coalesce(date_to_rft,(clock_timestamp() at time zone 'Australia/Perth')::date),rft_transferred_at=coalesce(rft_transferred_at,clock_timestamp()),version=version+1,updated_at=clock_timestamp(),updated_by=uid WHERE id=p_vehicle_id RETURNING * INTO v_after;
  after_state:=jsonb_build_object('vehicle',to_jsonb(v_after),'qc_state','RFT','email_outbox_399_created',false,'timer_started',false);
  receipt:=extensions.uuid_generate_v5('70000000-0000-5000-8000-000000000700'::uuid,uid::text||':qc:'||p_idempotency_key::text);
  result:=jsonb_build_object('ok',true,'code','qc_signed_off_moved_to_rft','replay',false,'data',jsonb_build_object('receipt_id',receipt,'vehicle_id',p_vehicle_id,'vehicle_version_before',v.version-1,'vehicle_version_after',v_after.version,'photo_receipt_id',photo.photo_receipt_id,'completed_items',lines,'email_outbox_created',false,'timer_started',false));
  INSERT INTO public.pdc_final_pdc_lifecycle_receipts_700(receipt_id,vehicle_id,action,actor_id,actor_email,idempotency_key,request_sha256,request_payload,before_state,after_state,evidence,response)
  VALUES(receipt,p_vehicle_id,'qc_signed_off',uid,actor_email,p_idempotency_key,request_sha,request_payload,before_state,after_state,jsonb_build_object('photo_receipt_id',photo.photo_receipt_id,'photo_storage_path',photo.storage_path,'completed_items',lines,'legacy_399_outbox_dispatchable',false),result);
  PERFORM public.audit_pdc_event('rft','vehicles',p_vehicle_id,p_vehicle_id,to_jsonb(v),to_jsonb(v_after),jsonb_build_object('action','finalize_pdc_qc_to_rft_700','receipt_id',receipt,'photo_receipt_id',photo.photo_receipt_id,'completed_item_count',jsonb_array_length(lines),'email_outbox_created',false,'timer_started',false));
  notifications_after:=(SELECT count(*) FROM public.vehicle_notifications);
  IF notifications_after<>notifications_before OR v_after.current_location<>'RFT' OR v_after.lifecycle_state<>'rft' OR v_after.version<>v.version+1 OR v_after.rft_transport_booked_at IS NOT NULL OR v_after.dealer_transit_started_at IS NOT NULL THEN
    RAISE EXCEPTION 'PDC_700_QC_POSTCONDITION_FAILED' USING errcode='55000';
  END IF;
  RETURN result;
EXCEPTION WHEN unique_violation THEN
  SELECT * INTO old FROM public.pdc_final_pdc_lifecycle_receipts_700 WHERE actor_id=uid AND idempotency_key=p_idempotency_key;
  IF FOUND THEN RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false); END IF;
  RETURN jsonb_build_object('ok',false,'code','qc_finalization_conflict');
END $qc$;
REVOKE ALL ON FUNCTION public.finalize_pdc_qc_to_rft_700(uuid,integer,uuid,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.finalize_pdc_qc_to_rft_700(uuid,integer,uuid,uuid) TO authenticated;

-- 412 remains the canonical intercepted outbox storage. New booking is the
-- only writer for new final-lifecycle email payloads; the legacy 412 booking
-- RPC is revoked below, so this table cannot gain a second path.
CREATE UNIQUE INDEX IF NOT EXISTS pdc_rft_transport_salesperson_outbox_412_vehicle_once
  ON public.pdc_rft_transport_salesperson_outbox_412(vehicle_id);
REVOKE EXECUTE ON FUNCTION public.book_rft_transport_412(uuid,integer,uuid) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.collect_rft_transport_412(uuid,integer,uuid) FROM authenticated;

CREATE OR REPLACE FUNCTION public.book_rft_transport_700(
  p_vehicle_id uuid,
  p_expected_vehicle_version integer,
  p_idempotency_key uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions SET statement_timeout='120s' AS $book$
DECLARE
  uid uuid:=auth.uid(); actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v public.vehicles%rowtype; old public.pdc_final_pdc_lifecycle_receipts_700%rowtype;
  transport_old public.pdc_rft_transport_action_receipts_412%rowtype;
  photo jsonb; salesperson jsonb; snap jsonb; lines jsonb; payload jsonb; request_payload jsonb; request_sha text;
  receipt uuid; transport_receipt uuid; notification uuid; booked_at timestamptz:=clock_timestamp(); before_state jsonb; after_state jsonb; result jsonb;
BEGIN
  IF uid IS NULL OR p_vehicle_id IS NULL OR p_expected_vehicle_version IS NULL OR p_expected_vehicle_version<1 OR p_idempotency_key IS NULL THEN RETURN jsonb_build_object('ok',false,'code','transport_booking_invalid_input'); END IF;
  IF NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=uid AND lower(r.email)=actor_email AND r.active AND r.account_status='approved' AND r.role IN('operator','administrator') FOR SHARE) THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
  request_payload:=jsonb_build_object('contract','pdc-final-rft-booked-700','vehicle_id',p_vehicle_id,'expected_vehicle_version',p_expected_vehicle_version,'idempotency_key',p_idempotency_key);
  request_sha:=encode(extensions.digest(convert_to(request_payload::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-700-book-actor:'||uid::text||':'||p_idempotency_key::text,0));
  SELECT * INTO old FROM public.pdc_final_pdc_lifecycle_receipts_700 WHERE actor_id=uid AND idempotency_key=p_idempotency_key;
  IF FOUND THEN
    IF old.request_sha256<>request_sha THEN RETURN jsonb_build_object('ok',false,'code','idempotency_payload_mismatch'); END IF;
    RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false);
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-700-book-vehicle:'||p_vehicle_id::text,0));
  SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
  IF NOT FOUND OR v.deleted_at IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_found'); END IF;
  SELECT * INTO old FROM public.pdc_final_pdc_lifecycle_receipts_700 WHERE vehicle_id=p_vehicle_id AND action='rft_booked';
  IF FOUND THEN RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false); END IF;
  IF v.version<>p_expected_vehicle_version THEN RETURN jsonb_build_object('ok',false,'code','vehicle_version_conflict','data',jsonb_build_object('vehicle_id',p_vehicle_id,'vehicle_version',v.version)); END IF;
  IF v.lifecycle_state<>'rft' OR upper(btrim(coalesce(v.current_location,'')))<>'RFT' OR v.rft_collected_at IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_in_rft'); END IF;
  IF NOT EXISTS(SELECT 1 FROM public.pdc_final_pdc_lifecycle_receipts_700 WHERE vehicle_id=v.id AND action='qc_signed_off') THEN RETURN jsonb_build_object('ok',false,'code','qc_receipt_required'); END IF;
  snap:=public.pdc_rft_transport_snapshot_412(v.id);
  salesperson:=snap->'salesperson';
  IF coalesce(salesperson->>'salesperson_email','')='' OR (salesperson->>'salesperson_email')!~'^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' THEN RETURN jsonb_build_object('ok',false,'code','salesperson_email_required'); END IF;
  photo:=snap->'photo';
  IF coalesce(photo->>'photo_receipt_id','')='' THEN RETURN jsonb_build_object('ok',false,'code','qc_photo_receipt_required'); END IF;
  lines:=coalesce(snap->'completed_work','[]'::jsonb);
  before_state:=jsonb_build_object('vehicle',to_jsonb(v),'timer_started',false,'email_outbox_count',(SELECT count(*) FROM public.pdc_rft_transport_salesperson_outbox_412 WHERE vehicle_id=v.id));
  UPDATE public.vehicles SET rft_transport_booked_at=booked_at,rft_transport_booked_by=uid,dealer_transit_started_at=booked_at,version=version+1,updated_at=booked_at,updated_by=uid WHERE id=v.id RETURNING * INTO v;
  transport_receipt:=extensions.uuid_generate_v5('41200000-0000-5000-8000-000000000412'::uuid,uid::text||':700:'||p_idempotency_key::text);
  notification:=extensions.uuid_generate_v5('41200000-0000-5000-8000-000000000412'::uuid,transport_receipt::text||':mandatory-salesperson-update');
  payload:=jsonb_build_object('contract','mandatory-rft-booked-salesperson-email-700','environment','staging','synthetic_only',left(upper(coalesce(v.source_batch_id,'')),11)='HERMES-TEST','delivery_enabled',false,'delivery_status','pending','notification_id',notification,'recipient',salesperson,'vehicle',jsonb_build_object('vehicle_id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,'stock_number',v.stock_number,'vin',v.vin,'job_card_number',v.job_card_number,'customer_name',v.customer_name,'vehicle_description',v.vehicle_description,'model',v.model),'completed_work',lines,'qc_completed_items',coalesce((SELECT r.evidence->'completed_items' FROM public.pdc_final_pdc_lifecycle_receipts_700 r WHERE r.vehicle_id=v.id AND r.action='qc_signed_off'),'[]'::jsonb),'relevant_dates',jsonb_build_object('date_to_pmb',v.date_to_pmb,'date_to_rft',v.date_to_rft,'qc_completed_at',v.qc_completed_at,'rft_transferred_at',v.rft_transferred_at,'rft_transport_booked_at',v.rft_transport_booked_at,'dealer_transit_started_at',v.dealer_transit_started_at),'build_times',snap->'build_times','stoppages',snap->'stoppages','photo_attachment',photo,'sent_at',null,'delivered_at',null);
  after_state:=jsonb_build_object('vehicle',to_jsonb(v),'timer_started',true,'timer_started_at',booked_at,'email_outbox_count',1);
  INSERT INTO public.pdc_rft_transport_action_receipts_412(receipt_id,vehicle_id,action,expected_vehicle_version,vehicle_version_before,vehicle_version_after,actor_id,actor_email,idempotency_key,request_sha256,request_payload,before_state,after_state,response)
  VALUES(transport_receipt,v.id,'transport_booked',p_expected_vehicle_version,p_expected_vehicle_version,v.version,uid,actor_email,p_idempotency_key,request_sha,request_payload,before_state,after_state,jsonb_build_object('receipt_id',transport_receipt,'notification_id',notification,'vehicle_id',v.id,'transport_booked_at',booked_at,'delivery_enabled',false));
  INSERT INTO public.pdc_rft_transport_salesperson_outbox_412(notification_id,transport_receipt_id,vehicle_id,recipient_email,payload)
  VALUES(notification,transport_receipt,v.id,lower(btrim(salesperson->>'salesperson_email')),payload);
  receipt:=extensions.uuid_generate_v5('70000000-0000-5000-8000-000000000700'::uuid,uid::text||':book:'||p_idempotency_key::text);
  result:=jsonb_build_object('ok',true,'code','rft_transport_booked','replay',false,'data',jsonb_build_object('receipt_id',receipt,'transport_receipt_id',transport_receipt,'notification_id',notification,'vehicle_id',v.id,'vehicle_version_before',p_expected_vehicle_version,'vehicle_version_after',v.version,'transport_booked_at',booked_at,'dealer_transit_started_at',booked_at,'recipient_email',lower(btrim(salesperson->>'salesperson_email')),'delivery_status','pending','delivery_enabled',false,'email_outbox_count',1,'payload',payload));
  INSERT INTO public.pdc_final_pdc_lifecycle_receipts_700(receipt_id,vehicle_id,action,actor_id,actor_email,idempotency_key,request_sha256,request_payload,before_state,after_state,evidence,response)
  VALUES(receipt,v.id,'rft_booked',uid,actor_email,p_idempotency_key,request_sha,request_payload,before_state,after_state,jsonb_build_object('transport_receipt_id',transport_receipt,'notification_id',notification,'payload',payload,'outbox_owner','412_successor_700','email_dispatchable',false),result);
  PERFORM public.audit_pdc_event('update','vehicles',v.id,v.id,before_state->'vehicle',to_jsonb(v),jsonb_build_object('action','book_rft_transport_700','receipt_id',receipt,'transport_receipt_id',transport_receipt,'notification_id',notification,'timer_started_at',booked_at,'notification_enqueued',false));
  IF v.rft_transport_booked_at IS DISTINCT FROM booked_at OR v.dealer_transit_started_at IS DISTINCT FROM booked_at OR (SELECT count(*) FROM public.pdc_rft_transport_salesperson_outbox_412 WHERE vehicle_id=v.id)<>1 OR EXISTS(SELECT 1 FROM public.pdc_rft_transport_salesperson_outbox_412 o WHERE o.vehicle_id=v.id AND (o.delivery_status<>'pending' OR o.sent_at IS NOT NULL OR o.delivered_at IS NOT NULL OR coalesce((o.payload->>'delivery_enabled')::boolean,false))) THEN RAISE EXCEPTION 'PDC_700_BOOK_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
  RETURN result;
EXCEPTION WHEN unique_violation THEN
  SELECT * INTO old FROM public.pdc_final_pdc_lifecycle_receipts_700 WHERE actor_id=uid AND idempotency_key=p_idempotency_key;
  IF FOUND THEN RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false); END IF;
  SELECT * INTO old FROM public.pdc_final_pdc_lifecycle_receipts_700 WHERE vehicle_id=p_vehicle_id AND action='rft_booked';
  IF FOUND THEN RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false); END IF;
  RETURN jsonb_build_object('ok',false,'code','rft_booking_conflict');
END $book$;
REVOKE ALL ON FUNCTION public.book_rft_transport_700(uuid,integer,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.book_rft_transport_700(uuid,integer,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.collect_rft_transport_700(
  p_vehicle_id uuid,
  p_expected_vehicle_version integer,
  p_idempotency_key uuid
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
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-700-collect-actor:'||uid::text||':'||p_idempotency_key::text,0));
  SELECT * INTO old FROM public.pdc_final_pdc_lifecycle_receipts_700 WHERE actor_id=uid AND idempotency_key=p_idempotency_key;
  IF FOUND THEN IF old.request_sha256<>request_sha THEN RETURN jsonb_build_object('ok',false,'code','idempotency_payload_mismatch'); END IF; RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false); END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-700-collect-vehicle:'||p_vehicle_id::text,0));
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
    booking_result:=public.cancel_workshop_booking(b.id,b.version,'Vehicle collected from RFT',jsonb_build_object('source','collect_rft_transport_700'));
    IF NOT coalesce((booking_result->>'ok')::boolean,false) THEN RAISE EXCEPTION 'PDC_700_BOOKING_CANCEL_FAILED:%',coalesce(booking_result->>'error',booking_result->>'code','unknown') USING errcode='40001'; END IF;
    cancelled:=cancelled+1;
  END LOOP;
  UPDATE public.vehicles SET current_location='Collected',lifecycle_state='rft',rft_collected_at=collected_at,rft_collected_by=uid,visible_on_board=false,pmb_stage=NULL,pmb_bay_stage=NULL,pmb_bay_number=NULL,active_workshop_booking_id=NULL,workshop_status=NULL,workshop_status_updated_at=collected_at,workshop_status_updated_by=uid,version=version+1,updated_at=collected_at,updated_by=uid WHERE id=v.id RETURNING * INTO v;
  INSERT INTO public.vehicle_movements(vehicle_id,from_location,to_location,from_pmb_stage,to_pmb_stage,from_pmb_bay_stage,to_pmb_bay_stage,from_pmb_bay_number,to_pmb_bay_number,reason,moved_by)
  VALUES(v.id,'RFT','Collected',NULL,NULL,NULL,NULL,NULL,NULL,'RFT vehicle physically collected; dealer transit timer remains open',uid) RETURNING id INTO movement;
  after_state:=jsonb_build_object('vehicle',to_jsonb(v),'state','Collected','collected_at',collected_at,'timer_started_at',v.dealer_transit_started_at,'timer_closed',false);
  receipt:=extensions.uuid_generate_v5('70000000-0000-5000-8000-000000000700'::uuid,uid::text||':collect:'||p_idempotency_key::text);
  result:=jsonb_build_object('ok',true,'code','rft_vehicle_collected','replay',false,'data',jsonb_build_object('receipt_id',receipt,'vehicle_id',v.id,'vehicle_version_before',p_expected_vehicle_version,'vehicle_version_after',v.version,'collected_at',collected_at,'current_location','Collected','lifecycle_state','rft','dealer_transit_started_at',v.dealer_transit_started_at,'dealer_transit_closed_at',null,'dealer_transit_duration_seconds',null,'cancelled_active_booking_count',cancelled,'movement_id',movement,'timer_closed',false));
  INSERT INTO public.pdc_final_pdc_lifecycle_receipts_700(receipt_id,vehicle_id,action,actor_id,actor_email,idempotency_key,request_sha256,request_payload,before_state,after_state,evidence,response)
  VALUES(receipt,v.id,'collected',uid,actor_email,p_idempotency_key,request_sha,request_payload,before_state,after_state,jsonb_build_object('collected_at',collected_at,'cancelled_active_booking_count',cancelled,'cleared_active_bay',true,'workshop_booking_history_retained',true,'timer_closed',false,'completed',false),result);
  PERFORM public.audit_pdc_event('update','vehicles',v.id,v.id,before_state->'vehicle',to_jsonb(v),jsonb_build_object('action','collect_rft_transport_700','receipt_id',receipt,'movement_id',movement,'cancelled_active_booking_count',cancelled,'timer_closed',false,'completed',false));
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

CREATE OR REPLACE FUNCTION public.reconcile_navision_delivery_700(
  p_backend_record_id uuid,
  p_actor_id uuid DEFAULT NULL,
  p_actor_email text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions SET statement_timeout='120s' AS $delivery$
DECLARE
  uid uuid:=coalesce(p_actor_id,auth.uid()); actor_email text:=lower(btrim(coalesce(p_actor_email,auth.jwt()->>'email',''))); b public.navision_backend_records%rowtype; v public.vehicles%rowtype; old public.pdc_final_pdc_lifecycle_receipts_700%rowtype;
  raw_status text; request_payload jsonb; request_sha text; before_state jsonb; after_state jsonb; receipt uuid; result jsonb; closed_at timestamptz:=clock_timestamp(); duration bigint; activation public.navision_board_activations%rowtype;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() OR p_backend_record_id IS NULL THEN RETURN public.navision_backend_response(false,'wrong_environment_or_invalid_input'); END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-700-delivery-record:'||p_backend_record_id::text,0));
  SELECT * INTO b FROM public.navision_backend_records WHERE id=p_backend_record_id FOR UPDATE;
  IF NOT FOUND OR NOT b.is_current OR b.record_status<>'current' OR b.canonical_vehicle_id IS NULL THEN RETURN public.navision_backend_response(false,'delivery_record_not_current'); END IF;
  raw_status:=coalesce(b.normalized_data->>'toyotaStatus',b.normalized_data->>'navisionSubLocationDescription',b.normalized_data->>'vehicleStatus',b.normalized_data->>'navisionLocationStatus','');
  IF btrim(raw_status)<>'Delivered - At Dealer' THEN RETURN public.navision_backend_response(false,'delivery_status_not_exact'); END IF;
  SELECT * INTO v FROM public.vehicles WHERE id=b.canonical_vehicle_id FOR UPDATE;
  IF NOT FOUND OR v.deleted_at IS NOT NULL THEN RETURN public.navision_backend_response(false,'delivery_vehicle_not_found'); END IF;
  IF b.dealer_code IS DISTINCT FROM v.source_batch_id THEN RETURN public.navision_backend_response(false,'delivery_wrong_dealer_scope'); END IF;
  SELECT * INTO old FROM public.pdc_final_pdc_lifecycle_receipts_700 WHERE vehicle_id=v.id AND action='delivered';
  IF FOUND THEN RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false); END IF;
  IF NOT EXISTS(SELECT 1 FROM public.pdc_final_pdc_lifecycle_receipts_700 WHERE vehicle_id=v.id AND action='rft_booked') OR NOT EXISTS(SELECT 1 FROM public.pdc_final_pdc_lifecycle_receipts_700 WHERE vehicle_id=v.id AND action='collected') THEN RETURN public.navision_backend_response(false,'delivery_requires_collected_interval'); END IF;
  IF v.lifecycle_state<>'rft' OR upper(btrim(coalesce(v.current_location,'')))<>'COLLECTED' OR v.dealer_transit_started_at IS NULL OR v.dealer_transit_closed_at IS NOT NULL OR v.dealer_transit_duration_seconds IS NOT NULL THEN RETURN public.navision_backend_response(false,'delivery_interval_not_open'); END IF;
  duration:=greatest(0,floor(extract(epoch from (closed_at-v.dealer_transit_started_at)))::bigint);
  request_payload:=jsonb_build_object('contract','pdc-final-navision-delivery-700','backend_record_id',p_backend_record_id,'vehicle_id',v.id,'status',raw_status,'actor_id',uid);
  request_sha:=encode(extensions.digest(convert_to(request_payload::text,'UTF8'),'sha256'),'hex');
  before_state:=jsonb_build_object('vehicle',to_jsonb(v),'navision_record_id',p_backend_record_id,'status',raw_status,'timer_started_at',v.dealer_transit_started_at);
  UPDATE public.vehicles SET lifecycle_state='completed',current_location='Completed',visible_on_board=false,dealer_transit_closed_at=closed_at,dealer_transit_duration_seconds=duration,delivered_to_dealer_date=coalesce(delivered_to_dealer_date,(closed_at at time zone 'Australia/Perth')::date),source_payload=coalesce(source_payload,'{}'::jsonb)||jsonb_build_object('authority','pdc_final_authoritative_lifecycle_700','navision_record_id',p_backend_record_id,'navision_status_literal',raw_status,'delivered_at',closed_at),version=version+1,updated_at=closed_at,updated_by=uid WHERE id=v.id RETURNING * INTO v;
  UPDATE public.navision_board_activations SET canonical_vehicle_id=v.id,active=false,completed_at=coalesce(completed_at,closed_at),completion_reason='Delivered - At Dealer',completed_by=uid,completed_by_email=actor_email,updated_at=closed_at WHERE backend_record_id=b.id RETURNING * INTO activation;
  INSERT INTO public.vehicle_movements(vehicle_id,from_location,to_location,from_pmb_stage,to_pmb_stage,from_pmb_bay_stage,to_pmb_bay_stage,from_pmb_bay_number,to_pmb_bay_number,reason,moved_by)
  VALUES(v.id,'Collected','Completed',NULL,NULL,NULL,NULL,NULL,NULL,'Exact Navision status Delivered - At Dealer closed dealer-transit timer',uid);
  after_state:=jsonb_build_object('vehicle',to_jsonb(v),'navision_record_id',p_backend_record_id,'status',raw_status,'timer_closed_at',closed_at,'duration_seconds',duration);
  receipt:=extensions.uuid_generate_v5('70000000-0000-5000-8000-000000000700'::uuid,'delivery:'||p_backend_record_id::text||':'||v.id::text);
  result:=jsonb_build_object('ok',true,'code','delivered_at_dealer_completed','replay',false,'data',jsonb_build_object('receipt_id',receipt,'vehicle_id',v.id,'backend_record_id',p_backend_record_id,'status','Delivered - At Dealer','vehicle_version_after',v.version,'dealer_transit_started_at',v.dealer_transit_started_at,'dealer_transit_closed_at',closed_at,'dealer_transit_duration_seconds',duration,'current_location','Completed','lifecycle_state','completed'));
  INSERT INTO public.pdc_final_pdc_lifecycle_receipts_700(receipt_id,vehicle_id,action,actor_id,actor_email,idempotency_key,request_sha256,request_payload,before_state,after_state,evidence,response)
  VALUES(receipt,v.id,'delivered',uid,coalesce(actor_email,'system@staging.invalid'),extensions.uuid_generate_v5('70000000-0000-5000-8000-000000000700'::uuid,'delivery-idempotency:'||p_backend_record_id::text||':'||v.id::text),request_sha,request_payload,before_state,after_state,jsonb_build_object('exact_status_literal',true,'dealer_scope_exact',true,'open_interval_required',true,'duration_seconds',duration),result);
  PERFORM public.audit_pdc_event('update','vehicles',v.id,v.id,before_state->'vehicle',to_jsonb(v),jsonb_build_object('action','reconcile_navision_delivery_700','receipt_id',receipt,'backend_record_id',p_backend_record_id,'status_literal',raw_status,'duration_seconds',duration));
  UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=closed_at WHERE singleton;
  UPDATE public.navision_backend_revision SET revision=revision+1,updated_at=closed_at WHERE singleton;
  RETURN result;
EXCEPTION WHEN unique_violation THEN
  SELECT * INTO old FROM public.pdc_final_pdc_lifecycle_receipts_700 WHERE vehicle_id=b.canonical_vehicle_id AND action='delivered';
  IF FOUND THEN RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false); END IF;
  RETURN public.navision_backend_response(false,'delivery_replay_conflict');
END $delivery$;
REVOKE ALL ON FUNCTION public.reconcile_navision_delivery_700(uuid,uuid,text) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.reconcile_navision_delivery_700(uuid,uuid,text) TO authenticated;

-- Only exact Delivered - At Dealer is intercepted here. Near misses are
-- rejected by 700 rather than delegated to the older normalizer, preventing
-- the 169 path from completing on a fuzzy status.
ALTER FUNCTION public.reconcile_navision_operational_record(uuid,uuid,text) RENAME TO reconcile_navision_operational_record_pre_700;
CREATE FUNCTION public.reconcile_navision_operational_record(p_backend_record_id uuid,p_actor_id uuid DEFAULT NULL,p_actor_email text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,extensions AS $wrapper$
DECLARE b public.navision_backend_records%rowtype; raw_status text; normalized text;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() THEN RETURN public.navision_backend_response(false,'wrong_environment'); END IF;
  SELECT * INTO b FROM public.navision_backend_records WHERE id=p_backend_record_id;
  IF FOUND THEN
    raw_status:=coalesce(b.normalized_data->>'toyotaStatus',b.normalized_data->>'navisionSubLocationDescription',b.normalized_data->>'vehicleStatus',b.normalized_data->>'navisionLocationStatus','');
    normalized:=lower(regexp_replace(btrim(raw_status),'[^a-z0-9]+','','g'));
    IF normalized='deliveredatdealer' THEN RETURN public.reconcile_navision_delivery_700(p_backend_record_id,p_actor_id,p_actor_email); END IF;
  END IF;
  RETURN public.reconcile_navision_operational_record_pre_700(p_backend_record_id,p_actor_id,p_actor_email);
END $wrapper$;
REVOKE ALL ON FUNCTION public.reconcile_navision_operational_record_pre_700(uuid,uuid,text) FROM public,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.reconcile_navision_operational_record(uuid,uuid,text) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.reconcile_navision_operational_record(uuid,uuid,text) TO authenticated,service_role;

-- Snapshot overlay: the new authoritative lifecycle state is separate from
-- legacy lifecycle_state until Delivery, and retained history is always read
-- from the server. Collected rows are appended to the authenticated snapshot.
CREATE OR REPLACE FUNCTION public.pdc_final_lifecycle_overlay_700(p_vehicle_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
SELECT coalesce((SELECT jsonb_build_object(
  'state',CASE WHEN EXISTS(SELECT 1 FROM public.pdc_final_pdc_lifecycle_receipts_700 r WHERE r.vehicle_id=v.id AND r.action='delivered') THEN 'completed' WHEN EXISTS(SELECT 1 FROM public.pdc_final_pdc_lifecycle_receipts_700 r WHERE r.vehicle_id=v.id AND r.action='collected') THEN 'collected' WHEN EXISTS(SELECT 1 FROM public.pdc_final_pdc_lifecycle_receipts_700 r WHERE r.vehicle_id=v.id AND r.action='rft_booked') THEN 'rft_booked' WHEN EXISTS(SELECT 1 FROM public.pdc_final_pdc_lifecycle_receipts_700 r WHERE r.vehicle_id=v.id AND r.action='qc_signed_off') THEN 'rft' ELSE lower(v.lifecycle_state::text) END,
  'qc_signed_off',EXISTS(SELECT 1 FROM public.pdc_final_pdc_lifecycle_receipts_700 r WHERE r.vehicle_id=v.id AND r.action='qc_signed_off'),
  'rft_booked',EXISTS(SELECT 1 FROM public.pdc_final_pdc_lifecycle_receipts_700 r WHERE r.vehicle_id=v.id AND r.action='rft_booked'),
  'collected',EXISTS(SELECT 1 FROM public.pdc_final_pdc_lifecycle_receipts_700 r WHERE r.vehicle_id=v.id AND r.action='collected'),
  'delivered',EXISTS(SELECT 1 FROM public.pdc_final_pdc_lifecycle_receipts_700 r WHERE r.vehicle_id=v.id AND r.action='delivered'),
  'rft_transport_booked_at',v.rft_transport_booked_at,'dealer_transit_started_at',v.dealer_transit_started_at,'dealer_transit_closed_at',v.dealer_transit_closed_at,'dealer_transit_duration_seconds',v.dealer_transit_duration_seconds,
  'rft_collected_at',v.rft_collected_at,'rft_collected_by',v.rft_collected_by,'current_location',v.current_location,'lifecycle_state',v.lifecycle_state::text
) FROM public.vehicles v WHERE v.id=p_vehicle_id),'{}'::jsonb);
$$;
REVOKE ALL ON FUNCTION public.pdc_final_lifecycle_overlay_700(uuid) FROM public,anon,authenticated,service_role;

ALTER FUNCTION public.get_pdc_email_vehicle_location_snapshot() RENAME TO get_pdc_email_vehicle_location_snapshot_pre_700;
CREATE FUNCTION public.get_pdc_email_vehicle_location_snapshot()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $snapshot$
DECLARE r jsonb; rows jsonb; collected_rows jsonb;
BEGIN
  r:=public.get_pdc_email_vehicle_location_snapshot_pre_700();
  IF NOT coalesce((r->>'ok')::boolean,false) THEN RETURN r; END IF;
  SELECT coalesce(jsonb_agg(x||public.pdc_final_lifecycle_overlay_700((x->>'id')::uuid) ORDER BY coalesce(x->>'stock_number',x->>'vin',x->>'id')),'[]'::jsonb) INTO rows
  FROM jsonb_array_elements(coalesce(r#>'{data,vehicles}','[]'::jsonb)) x;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,'version',v.version,'stock_number',v.stock_number,'vin',v.vin,'key_number',v.key_number,'job_card_number',v.job_card_number,'customer_name',v.customer_name,'vehicle_description',v.vehicle_description,'model',v.model,'registration',v.registration,'current_location',v.current_location,'lifecycle_state',v.lifecycle_state::text,'visible_on_board',v.visible_on_board,'pmb_stage',v.pmb_stage,'pmb_bay_stage',v.pmb_bay_stage,'pmb_bay_number',v.pmb_bay_number,'date_to_pmb',v.date_to_pmb,'date_to_rft',v.date_to_rft,'rft_transferred_at',v.rft_transferred_at,'rft_collected_at',v.rft_collected_at,'rft_collected_by',v.rft_collected_by,'qc_completed_at',v.qc_completed_at,'qc_completed_by',v.qc_completed_by,'salesperson_id',v.salesperson_id,'salesperson_reference',v.salesperson_reference,'rft_transport_booked_at',v.rft_transport_booked_at,'dealer_transit_started_at',v.dealer_transit_started_at,'dealer_transit_closed_at',v.dealer_transit_closed_at,'dealer_transit_duration_seconds',v.dealer_transit_duration_seconds,
    'work_items',coalesce((SELECT jsonb_agg(jsonb_build_object('vehicle_id',wi.vehicle_id,'work_key',wi.work_key,'required',wi.required,'completed',wi.completed,'completed_at',wi.completed_at,'completed_by',wi.completed_by) ORDER BY wi.work_key) FROM public.vehicle_work_items wi WHERE wi.vehicle_id=v.id),'[]'::jsonb),
    'pdc_lifecycle',public.pdc_final_lifecycle_overlay_700(v.id),
    'qc_finalization',coalesce((SELECT jsonb_build_object('receipt_id',q.receipt_id,'photo_receipt_id',q.evidence->>'photo_receipt_id','signed_off_at',q.created_at,'completed_items',q.evidence->'completed_items') FROM public.pdc_final_pdc_lifecycle_receipts_700 q WHERE q.vehicle_id=v.id AND q.action='qc_signed_off'),'{}'::jsonb),
    'photo',coalesce((SELECT jsonb_build_object('photo_receipt_id',p.photo_receipt_id,'bucket_id',p.bucket_id,'storage_path',p.storage_path,'content_type',p.content_type,'byte_length',p.byte_length,'image_width',p.image_width,'image_height',p.image_height,'sha256',p.sha256,'original_filename',p.original_filename) FROM public.pdc_qc_finalization_photo_evidence_399 p WHERE p.vehicle_id=v.id ORDER BY p.created_at DESC LIMIT 1),'{}'::jsonb),
    'rft_transport_outbox',coalesce((SELECT jsonb_build_object('notification_id',o.notification_id,'delivery_status',o.delivery_status,'sent_at',o.sent_at,'delivered_at',o.delivered_at,'intercepted',EXISTS(SELECT 1 FROM public.pdc_rft_transport_email_intercept_receipts_429 i WHERE i.notification_id=o.notification_id)) FROM public.pdc_rft_transport_salesperson_outbox_412 o WHERE o.vehicle_id=v.id),'{}'::jsonb)
  ) ORDER BY v.rft_collected_at,v.id),'[]'::jsonb) INTO collected_rows
  FROM public.vehicles v
  WHERE v.deleted_at IS NULL AND v.current_location='Collected' AND EXISTS(SELECT 1 FROM public.pdc_final_pdc_lifecycle_receipts_700 q WHERE q.vehicle_id=v.id AND q.action='collected') AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(rows) x WHERE (x->>'id')=v.id::text);
  rows:=rows||collected_rows;
  RETURN jsonb_set(r,'{data,vehicles}',rows,true);
END $snapshot$;
REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_location_snapshot_pre_700() FROM public,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() TO authenticated;

DO $post$
BEGIN
  IF has_function_privilege('authenticated','public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.finalize_pdc_qc_to_rft_700(uuid,integer,uuid,uuid)','EXECUTE')
     OR has_function_privilege('authenticated','public.book_rft_transport_412(uuid,integer,uuid)','EXECUTE')
     OR has_function_privilege('authenticated','public.collect_rft_transport_412(uuid,integer,uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.book_rft_transport_700(uuid,integer,uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.collect_rft_transport_700(uuid,integer,uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.get_pdc_email_vehicle_location_snapshot()','EXECUTE')
     OR has_table_privilege('authenticated','public.pdc_final_pdc_lifecycle_receipts_700','SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
     OR (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid='public.pdc_final_pdc_lifecycle_receipts_700'::regclass) IS DISTINCT FROM true
     OR (SELECT count(*) FROM public.pdc_rft_transport_salesperson_outbox_412 GROUP BY vehicle_id HAVING count(*)>1)<>0
  THEN RAISE EXCEPTION 'PDC_700_SECURITY_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260827101000','700_final_authoritative_pdc_lifecycle',ARRAY[
  'Append-only successor bound to the live staging 672 ledger and exact predecessor function hashes; no applied migration rewritten',
  'One immutable per-vehicle QC/RFT-booked/Collected/Delivered receipt chain with actor, request, before/after and evidence hashes',
  'QC preserves canonical operation completion, private photo and history, moves QC to RFT, creates no email and starts no timer; authenticated 399 finalization is revoked',
  'RFT Booked is explicit and idempotent, sets rft_transport_booked_at and dealer_transit_started_at to one exact timestamp, and writes one pending delivery-disabled 412 outbox payload',
  'Collected is distinct from Completed: current_location Collected, active bay/workshop pointers cleared with booking history retained, timer remains open and delivery remains pending',
  'Only exact Delivered - At Dealer on the linked dealer record, after an open booked/collected interval, closes once with immutable non-negative duration and moves Completed',
  'Snapshot exposes RFT, Collected and Completed from authoritative server state; direct table DML remains denied and Production sentinel is forbidden'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
