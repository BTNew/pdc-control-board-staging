-- STAGING ONLY 412: authoritative stoppage clearing and mandatory RFT transport workflow.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-412-stoppage-rft-transport',0));

DO $pre$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR NOT public.pdc_monitor_staging_guard()
   OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260826170000' AND name='411_yh_workshop_eligibility_hide_test_fleet')
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260826170000')
   OR to_regprocedure('public.return_work_to_queue(uuid,integer,text,jsonb)') IS NULL
   OR to_regprocedure('public.cancel_workshop_booking(uuid,integer,text,jsonb)') IS NULL
   OR to_regprocedure('public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text)') IS NULL
   OR to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()') IS NULL
   OR to_regclass('public.pdc_qc_finalization_receipts_399') IS NULL
   OR to_regclass('public.pdc_qc_finalization_photo_evidence_399') IS NULL THEN
  RAISE EXCEPTION 'PDC_412_STAGING_HEAD_OR_DEPENDENCY_MISMATCH' USING errcode='55000';
 END IF;
END $pre$;

ALTER TABLE public.vehicles ADD COLUMN IF NOT EXISTS rft_transport_booked_at timestamptz;
ALTER TABLE public.vehicles ADD COLUMN IF NOT EXISTS rft_transport_booked_by uuid REFERENCES auth.users(id);

CREATE TABLE public.pdc_rft_transport_action_receipts_412(
 receipt_id uuid PRIMARY KEY,
 vehicle_id uuid NOT NULL REFERENCES public.vehicles(id),
 action text NOT NULL CHECK(action IN('clear_stoppage','transport_booked','collected')),
 expected_vehicle_version integer NOT NULL CHECK(expected_vehicle_version>0),
 vehicle_version_before integer NOT NULL CHECK(vehicle_version_before>0),
 vehicle_version_after integer NOT NULL CHECK(vehicle_version_after>0),
 actor_id uuid NOT NULL,
 actor_email text NOT NULL,
 idempotency_key uuid NOT NULL,
 request_sha256 text NOT NULL CHECK(request_sha256~'^[a-f0-9]{64}$'),
 request_payload jsonb NOT NULL,
 before_state jsonb NOT NULL,
 after_state jsonb NOT NULL,
 response jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(actor_id,idempotency_key)
);
CREATE INDEX pdc_rft_transport_action_receipts_412_vehicle_idx ON public.pdc_rft_transport_action_receipts_412(vehicle_id,created_at DESC);

CREATE TABLE public.pdc_rft_transport_salesperson_outbox_412(
 notification_id uuid PRIMARY KEY,
 transport_receipt_id uuid NOT NULL UNIQUE REFERENCES public.pdc_rft_transport_action_receipts_412(receipt_id),
 vehicle_id uuid NOT NULL REFERENCES public.vehicles(id),
 recipient_email text NOT NULL CHECK(recipient_email=lower(recipient_email) AND recipient_email~'^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
 delivery_status text NOT NULL DEFAULT 'pending' CHECK(delivery_status IN('pending','sending','sent','failed','cancelled')),
 sent_at timestamptz,
 delivered_at timestamptz,
 payload jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CHECK(delivery_status<>'pending' OR (sent_at IS NULL AND delivered_at IS NULL))
);
CREATE INDEX pdc_rft_transport_salesperson_outbox_412_vehicle_idx ON public.pdc_rft_transport_salesperson_outbox_412(vehicle_id,created_at DESC);

CREATE OR REPLACE FUNCTION public.pdc_412_append_only()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN RAISE EXCEPTION 'PDC_412_APPEND_ONLY' USING errcode='55000'; END $$;
REVOKE ALL ON FUNCTION public.pdc_412_append_only() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_rft_transport_action_receipts_412_append_only BEFORE UPDATE OR DELETE ON public.pdc_rft_transport_action_receipts_412 FOR EACH ROW EXECUTE FUNCTION public.pdc_412_append_only();
CREATE TRIGGER pdc_rft_transport_salesperson_outbox_412_append_only BEFORE UPDATE OR DELETE ON public.pdc_rft_transport_salesperson_outbox_412 FOR EACH ROW EXECUTE FUNCTION public.pdc_412_append_only();
ALTER TABLE public.pdc_rft_transport_action_receipts_412 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_rft_transport_action_receipts_412 FORCE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_rft_transport_salesperson_outbox_412 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_rft_transport_salesperson_outbox_412 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_rft_transport_action_receipts_412 FROM public,anon,authenticated,service_role;
REVOKE ALL ON TABLE public.pdc_rft_transport_salesperson_outbox_412 FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.pdc_rft_transport_snapshot_412(p_vehicle_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $snapshot$
 SELECT coalesce((SELECT jsonb_build_object(
   'vehicle_id',v.id,'vehicle_version',v.version,'stock_number',v.stock_number,'job_card_number',v.job_card_number,
   'customer_name',v.customer_name,'vehicle_description',v.vehicle_description,'current_location',v.current_location,
   'lifecycle_state',v.lifecycle_state,'date_to_pmb',v.date_to_pmb,'date_to_rft',v.date_to_rft,
   'qc_completed_at',v.qc_completed_at,'rft_transferred_at',v.rft_transferred_at,
   'transport_booked_at',v.rft_transport_booked_at,'transport_booked_by',v.rft_transport_booked_by,
   'collected_at',v.rft_collected_at,'collected_by',v.rft_collected_by,
   'salesperson',public.pdc_vehicle_effective_salesperson_json_386(v.id),
   'completed_work',coalesce((SELECT jsonb_agg(jsonb_build_object('work_key',w.work_key,'required',w.required,'completed',w.completed,'completed_at',w.completed_at,'completed_by',w.completed_by) ORDER BY w.work_key) FROM public.vehicle_work_items w WHERE w.vehicle_id=v.id AND w.required),'[]'::jsonb),
   'qc_finalization',coalesce((SELECT jsonb_build_object('receipt_id',q.receipt_id,'photo_receipt_id',q.photo_receipt_id,'created_at',q.created_at,'completed_items',q.completed_items_snapshot) FROM public.pdc_qc_finalization_receipts_399 q WHERE q.vehicle_id=v.id ORDER BY q.created_at DESC LIMIT 1),'{}'::jsonb),
   'photo',coalesce((SELECT jsonb_build_object('photo_receipt_id',p.photo_receipt_id,'bucket_id',p.bucket_id,'storage_path',p.storage_path,'content_type',p.content_type,'byte_length',p.byte_length,'image_width',p.image_width,'image_height',p.image_height,'sha256',p.sha256,'original_filename',p.original_filename) FROM public.pdc_qc_finalization_photo_evidence_399 p WHERE p.vehicle_id=v.id ORDER BY p.created_at DESC LIMIT 1),'{}'::jsonb),
   'build_times',coalesce((SELECT jsonb_agg(jsonb_build_object('booking_id',b.id,'stage_code',s.code,'bay',bay.display_name,'status',b.status,'scheduled_start_at',b.scheduled_start_at,'scheduled_end_at',b.scheduled_end_at,'planned_minutes',b.default_duration_minutes,'actual_start_at',b.actual_start_at,'actual_end_at',b.actual_end_at,'actual_minutes',b.actual_duration_minutes,'stoppage_minutes',b.stoppage_accumulated_minutes) ORDER BY b.created_at,b.id) FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id LEFT JOIN public.workshop_bays bay ON bay.id=b.bay_id WHERE b.vehicle_id=v.id),'[]'::jsonb),
   'stoppages',coalesce((SELECT jsonb_agg(jsonb_build_object('history_id',h.id,'booking_id',h.booking_id,'event_type',h.event_type,'before',h.before_data,'after',h.after_data,'metadata',h.metadata,'created_at',h.created_at) ORDER BY h.created_at,h.id) FROM public.workshop_booking_history h WHERE h.vehicle_id=v.id AND (lower(h.event_type) LIKE '%stoppage%' OR lower(h.event_type) LIKE '%resume%' OR lower(h.event_type) LIKE '%return%')),'[]'::jsonb)
 ) FROM public.vehicles v WHERE v.id=p_vehicle_id),'{}'::jsonb);
$snapshot$;
REVOKE ALL ON FUNCTION public.pdc_rft_transport_snapshot_412(uuid) FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.clear_vehicle_stoppage_412(p_vehicle_id uuid,p_expected_vehicle_version integer,p_resolution_note text,p_idempotency_key uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,extensions SET statement_timeout='90s' AS $clear$
DECLARE
 uid uuid:=auth.uid(); email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); note text:=regexp_replace(btrim(coalesce(p_resolution_note,'')),'\s+',' ','g');
 v public.vehicles%rowtype; b public.workshop_bookings%rowtype; parts public.vehicle_parts_updates%rowtype; result jsonb;
 payload jsonb; sha text; receipt uuid; before_j jsonb; after_j jsonb; cleared integer:=0; version_before integer; version_after integer;
 old public.pdc_rft_transport_action_receipts_412%rowtype; part_key uuid;
BEGIN
 IF uid IS NULL OR p_vehicle_id IS NULL OR p_expected_vehicle_version<1 OR p_idempotency_key IS NULL OR length(note) NOT BETWEEN 3 AND 240
   OR NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=uid AND lower(r.email)=email AND r.active AND r.account_status='approved' AND r.role IN('operator','administrator')) THEN
  RETURN jsonb_build_object('ok',false,'code','stoppage_clear_invalid_or_unauthorized'); END IF;
 payload:=jsonb_build_object('contract','pdc-clear-stoppage-412','vehicle_id',p_vehicle_id,'expected_vehicle_version',p_expected_vehicle_version,'resolution_note',note,'idempotency_key',p_idempotency_key);
 sha:=encode(extensions.digest(convert_to(payload::text,'UTF8'),'sha256'),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-412-clear:'||uid::text||':'||p_idempotency_key::text,0));
 SELECT * INTO old FROM public.pdc_rft_transport_action_receipts_412 WHERE actor_id=uid AND idempotency_key=p_idempotency_key;
 IF FOUND THEN IF old.request_sha256<>sha THEN RAISE EXCEPTION 'PDC_412_IDEMPOTENCY_PAYLOAD_MISMATCH' USING errcode='22023'; END IF; RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false); END IF;
 SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
 IF NOT FOUND OR v.deleted_at IS NOT NULL OR v.lifecycle_state IN('completed','deleted') THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_active'); END IF;
 IF v.version<>p_expected_vehicle_version THEN RETURN jsonb_build_object('ok',false,'code','vehicle_version_conflict','current_version',v.version); END IF;
 IF v.stock_number LIKE 'HERMES-TEST-%' THEN PERFORM set_config('pdc.hermes_test_wrapper_vehicle_365',v.id::text,true); END IF;
 version_before:=v.version; before_j:=public.pdc_rft_transport_snapshot_412(v.id);
 FOR b IN SELECT * FROM public.workshop_bookings WHERE vehicle_id=v.id AND status::text='stoppage' ORDER BY id FOR UPDATE LOOP
  result:=public.return_work_to_queue(b.id,b.version,NULL,jsonb_build_object('source','clear_vehicle_stoppage_412','resolution_note',note));
  IF NOT coalesce((result->>'ok')::boolean,false) THEN RAISE EXCEPTION 'PDC_412_BOOKING_CLEAR_FAILED:%',coalesce(result->>'error','unknown') USING errcode='40001'; END IF;
  cleared:=cleared+1;
 END LOOP;
 SELECT * INTO parts FROM public.vehicle_parts_updates WHERE vehicle_id=v.id ORDER BY updated_at DESC,id DESC LIMIT 1 FOR UPDATE;
 IF coalesce(parts.parts_stoppage,false) THEN
  part_key:=extensions.uuid_generate_v5('41200000-0000-5000-8000-000000000412'::uuid,p_idempotency_key::text||':parts');
  result:=public.set_pdc_parts_stoppage_376(v.id,v.version,part_key,'clear',note);
  IF NOT coalesce((result->>'ok')::boolean,false) THEN RAISE EXCEPTION 'PDC_412_PARTS_CLEAR_FAILED:%',coalesce(result->>'code','unknown') USING errcode='40001'; END IF;
  cleared:=cleared+1;
 END IF;
 IF cleared=0 THEN RETURN jsonb_build_object('ok',false,'code','no_active_stoppage'); END IF;
 SELECT version INTO version_after FROM public.vehicles WHERE id=v.id; after_j:=public.pdc_rft_transport_snapshot_412(v.id);
 receipt:=extensions.uuid_generate_v5('41200000-0000-5000-8000-000000000412'::uuid,uid::text||':'||p_idempotency_key::text);
 result:=jsonb_build_object('ok',true,'code','stoppage_cleared_to_unallocated','replay',false,'receipt_id',receipt,'vehicle_id',v.id,'vehicle_version_before',version_before,'vehicle_version_after',version_after,'cleared_count',cleared,'resolution_note',note,'before',before_j,'after',after_j);
 INSERT INTO public.pdc_rft_transport_action_receipts_412 VALUES(receipt,v.id,'clear_stoppage',p_expected_vehicle_version,version_before,version_after,uid,email,p_idempotency_key,sha,payload,before_j,after_j,result,clock_timestamp());
 RETURN result;
END $clear$;

CREATE OR REPLACE FUNCTION public.book_rft_transport_412(p_vehicle_id uuid,p_expected_vehicle_version integer,p_idempotency_key uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,extensions SET statement_timeout='90s' AS $book$
DECLARE
 uid uuid:=auth.uid(); email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); v public.vehicles%rowtype; before_j jsonb; after_j jsonb;
 payload jsonb; sha text; receipt uuid; notification uuid; result jsonb; recipient text; salesperson jsonb; photo jsonb; completed jsonb; booked_at timestamptz:=clock_timestamp();
 old public.pdc_rft_transport_action_receipts_412%rowtype; notifications_before bigint; notifications_after bigint;
BEGIN
 IF uid IS NULL OR p_vehicle_id IS NULL OR p_expected_vehicle_version<1 OR p_idempotency_key IS NULL
   OR NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=uid AND lower(r.email)=email AND r.active AND r.account_status='approved' AND r.role IN('operator','administrator')) THEN
  RETURN jsonb_build_object('ok',false,'code','transport_booking_invalid_or_unauthorized'); END IF;
 payload:=jsonb_build_object('contract','pdc-rft-transport-booked-412','vehicle_id',p_vehicle_id,'expected_vehicle_version',p_expected_vehicle_version,'idempotency_key',p_idempotency_key);
 sha:=encode(extensions.digest(convert_to(payload::text,'UTF8'),'sha256'),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-412-book:'||uid::text||':'||p_idempotency_key::text,0));
 SELECT * INTO old FROM public.pdc_rft_transport_action_receipts_412 WHERE actor_id=uid AND idempotency_key=p_idempotency_key;
 IF FOUND THEN IF old.request_sha256<>sha THEN RAISE EXCEPTION 'PDC_412_IDEMPOTENCY_PAYLOAD_MISMATCH' USING errcode='22023'; END IF; RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false); END IF;
 LOCK TABLE public.vehicle_notifications IN SHARE MODE; notifications_before:=(SELECT count(*) FROM public.vehicle_notifications);
 SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
 IF NOT FOUND OR v.deleted_at IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_found'); END IF;
 IF v.version<>p_expected_vehicle_version THEN RETURN jsonb_build_object('ok',false,'code','vehicle_version_conflict','current_version',v.version); END IF;
 IF v.lifecycle_state<>'rft' OR upper(btrim(coalesce(v.current_location,'')))<>'RFT' OR v.rft_collected_at IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_in_rft'); END IF;
 IF v.rft_transport_booked_at IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'code','transport_already_booked','booked_at',v.rft_transport_booked_at); END IF;
 before_j:=public.pdc_rft_transport_snapshot_412(v.id); salesperson:=before_j->'salesperson'; photo:=before_j->'photo'; completed:=before_j->'qc_finalization';
 recipient:=lower(btrim(coalesce(salesperson->>'salesperson_email','')));
 IF recipient='' OR recipient!~'^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' THEN RETURN jsonb_build_object('ok',false,'code','salesperson_email_required'); END IF;
 IF coalesce(photo->>'photo_receipt_id','')='' OR coalesce(completed->>'receipt_id','')='' OR jsonb_array_length(coalesce(completed->'completed_items','[]'::jsonb))=0 THEN RETURN jsonb_build_object('ok',false,'code','qc_evidence_required'); END IF;
 IF v.stock_number LIKE 'HERMES-TEST-%' THEN PERFORM set_config('pdc.hermes_test_wrapper_vehicle_365',v.id::text,true); END IF;
 UPDATE public.vehicles SET rft_transport_booked_at=booked_at,rft_transport_booked_by=uid,version=version+1,updated_at=booked_at,updated_by=uid WHERE id=v.id RETURNING * INTO v;
 after_j:=public.pdc_rft_transport_snapshot_412(v.id);
 receipt:=extensions.uuid_generate_v5('41200000-0000-5000-8000-000000000412'::uuid,uid::text||':'||p_idempotency_key::text);
 notification:=extensions.uuid_generate_v5('41200000-0000-5000-8000-000000000412'::uuid,receipt::text||':mandatory-salesperson-update');
 result:=jsonb_build_object('ok',true,'code','rft_transport_booked','replay',false,'receipt_id',receipt,'notification_id',notification,'vehicle_id',v.id,'vehicle_version_before',p_expected_vehicle_version,'vehicle_version_after',v.version,'transport_booked_at',booked_at,'recipient_email',recipient,'delivery_status','pending','delivery_enabled',false,'snapshot',after_j);
 INSERT INTO public.pdc_rft_transport_action_receipts_412 VALUES(receipt,v.id,'transport_booked',p_expected_vehicle_version,p_expected_vehicle_version,v.version,uid,email,p_idempotency_key,sha,payload,before_j,after_j,result,clock_timestamp());
 INSERT INTO public.pdc_rft_transport_salesperson_outbox_412(notification_id,transport_receipt_id,vehicle_id,recipient_email,payload)
 VALUES(notification,receipt,v.id,recipient,jsonb_build_object('contract','mandatory-rft-transport-salesperson-email-412','delivery_enabled',false,'mandatory',true,
  'subject','RFT transport booked - Stock '||coalesce(v.stock_number,'No stock'),'recipient',salesperson,'vehicle',after_j - 'salesperson' - 'completed_work' - 'build_times' - 'stoppages' - 'qc_finalization' - 'photo',
  'completed_work',after_j->'completed_work','qc_completed_items',after_j#>'{qc_finalization,completed_items}','dates',jsonb_build_object('date_to_pmb',v.date_to_pmb,'date_to_rft',v.date_to_rft,'qc_completed_at',v.qc_completed_at,'rft_transferred_at',v.rft_transferred_at,'transport_booked_at',v.rft_transport_booked_at),
  'build_times',after_j->'build_times','stoppages',after_j->'stoppages','photo_attachment',after_j->'photo'));
 PERFORM public.audit_pdc_event('update','vehicles',v.id,v.id,before_j,after_j,jsonb_build_object('action','book_rft_transport_412','receipt_id',receipt,'mandatory_salesperson_outbox',notification,'notification_enqueued',false));
 notifications_after:=(SELECT count(*) FROM public.vehicle_notifications);
 IF notifications_after<>notifications_before OR EXISTS(SELECT 1 FROM public.pdc_rft_transport_salesperson_outbox_412 o WHERE o.notification_id=notification AND (o.delivery_status<>'pending' OR o.sent_at IS NOT NULL OR o.delivered_at IS NOT NULL OR (o.payload->>'delivery_enabled')::boolean)) THEN RAISE EXCEPTION 'PDC_412_OUTBOX_CONTAINMENT_FAILED' USING errcode='55000'; END IF;
 RETURN result;
END $book$;

CREATE OR REPLACE FUNCTION public.collect_rft_transport_412(p_vehicle_id uuid,p_expected_vehicle_version integer,p_idempotency_key uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,extensions SET statement_timeout='90s' AS $collect$
DECLARE
 uid uuid:=auth.uid(); email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); v public.vehicles%rowtype; b public.workshop_bookings%rowtype; before_j jsonb; after_j jsonb;
 payload jsonb; sha text; receipt uuid; result jsonb; old public.pdc_rft_transport_action_receipts_412%rowtype; cancelled integer:=0; movement uuid;
BEGIN
 IF uid IS NULL OR p_vehicle_id IS NULL OR p_expected_vehicle_version<1 OR p_idempotency_key IS NULL
   OR NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=uid AND lower(r.email)=email AND r.active AND r.account_status='approved' AND r.role IN('operator','administrator')) THEN
  RETURN jsonb_build_object('ok',false,'code','collection_invalid_or_unauthorized'); END IF;
 payload:=jsonb_build_object('contract','pdc-rft-collected-412','vehicle_id',p_vehicle_id,'expected_vehicle_version',p_expected_vehicle_version,'idempotency_key',p_idempotency_key);
 sha:=encode(extensions.digest(convert_to(payload::text,'UTF8'),'sha256'),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-412-collect:'||uid::text||':'||p_idempotency_key::text,0));
 SELECT * INTO old FROM public.pdc_rft_transport_action_receipts_412 WHERE actor_id=uid AND idempotency_key=p_idempotency_key;
 IF FOUND THEN IF old.request_sha256<>sha THEN RAISE EXCEPTION 'PDC_412_IDEMPOTENCY_PAYLOAD_MISMATCH' USING errcode='22023'; END IF; RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false); END IF;
 SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
 IF NOT FOUND OR v.deleted_at IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_found'); END IF;
 IF v.version<>p_expected_vehicle_version THEN RETURN jsonb_build_object('ok',false,'code','vehicle_version_conflict','current_version',v.version); END IF;
 IF v.lifecycle_state<>'rft' OR upper(btrim(coalesce(v.current_location,'')))<>'RFT' OR v.rft_collected_at IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_in_rft'); END IF;
 IF v.rft_transport_booked_at IS NULL OR NOT EXISTS(SELECT 1 FROM public.pdc_rft_transport_salesperson_outbox_412 o WHERE o.vehicle_id=v.id AND o.delivery_status='pending' AND o.sent_at IS NULL AND o.delivered_at IS NULL) THEN RETURN jsonb_build_object('ok',false,'code','transport_booking_and_mandatory_email_required'); END IF;
 IF EXISTS(SELECT 1 FROM public.workshop_bookings x WHERE x.vehicle_id=v.id AND x.status::text='started') THEN RETURN jsonb_build_object('ok',false,'code','started_booking_must_be_completed_before_collection'); END IF;
 IF v.stock_number LIKE 'HERMES-TEST-%' THEN PERFORM set_config('pdc.hermes_test_wrapper_vehicle_365',v.id::text,true); END IF;
 before_j:=public.pdc_rft_transport_snapshot_412(v.id);
 FOR b IN SELECT * FROM public.workshop_bookings WHERE vehicle_id=v.id AND status::text NOT IN('completed','deleted','cancelled') ORDER BY id FOR UPDATE LOOP
  result:=public.cancel_workshop_booking(b.id,b.version,'Vehicle collected from RFT',jsonb_build_object('source','collect_rft_transport_412'));
  IF NOT coalesce((result->>'ok')::boolean,false) THEN RAISE EXCEPTION 'PDC_412_BOOKING_CANCEL_FAILED:%',coalesce(result->>'error','unknown') USING errcode='40001'; END IF;
  cancelled:=cancelled+1;
 END LOOP;
 UPDATE public.vehicles SET lifecycle_state='completed',current_location='Completed',rft_collected_at=clock_timestamp(),rft_collected_by=uid,visible_on_board=false,
  pmb_stage=NULL,pmb_bay_stage=NULL,pmb_bay_number=NULL,active_workshop_booking_id=NULL,workshop_status=NULL,workshop_status_updated_at=clock_timestamp(),workshop_status_updated_by=uid,
  version=version+1,updated_at=clock_timestamp(),updated_by=uid WHERE id=v.id RETURNING * INTO v;
 INSERT INTO public.vehicle_movements(vehicle_id,from_location,to_location,from_pmb_stage,to_pmb_stage,from_pmb_bay_stage,to_pmb_bay_stage,from_pmb_bay_number,to_pmb_bay_number,reason,moved_by)
 VALUES(v.id,'RFT','Completed',NULL,NULL,NULL,NULL,NULL,NULL,'Collected after RFT transport booking',uid) RETURNING id INTO movement;
 after_j:=public.pdc_rft_transport_snapshot_412(v.id);
 receipt:=extensions.uuid_generate_v5('41200000-0000-5000-8000-000000000412'::uuid,uid::text||':'||p_idempotency_key::text);
 result:=jsonb_build_object('ok',true,'code','rft_vehicle_collected_completed','replay',false,'receipt_id',receipt,'vehicle_id',v.id,'vehicle_version_before',p_expected_vehicle_version,'vehicle_version_after',v.version,'cancelled_active_booking_count',cancelled,'movement_id',movement,'snapshot',after_j);
 INSERT INTO public.pdc_rft_transport_action_receipts_412 VALUES(receipt,v.id,'collected',p_expected_vehicle_version,p_expected_vehicle_version,v.version,uid,email,p_idempotency_key,sha,payload,before_j,after_j,result,clock_timestamp());
 PERFORM public.audit_pdc_event('update','vehicles',v.id,v.id,before_j,after_j,jsonb_build_object('action','collect_rft_transport_412','receipt_id',receipt,'cancelled_active_booking_count',cancelled,'movement_id',movement));
 RETURN result;
END $collect$;

-- Disable the legacy collection route so mandatory transport booking/email evidence cannot be bypassed.
CREATE OR REPLACE FUNCTION public.rft_collect_vehicle(p_vehicle_id uuid,p_expected_version integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN PERFORM public.workshop_require_planner_operator(); RETURN jsonb_build_object('ok',false,'error','transport_booking_required_use_412'); END $$;

REVOKE ALL ON FUNCTION public.clear_vehicle_stoppage_412(uuid,integer,text,uuid) FROM public,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.book_rft_transport_412(uuid,integer,uuid) FROM public,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.collect_rft_transport_412(uuid,integer,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.clear_vehicle_stoppage_412(uuid,integer,text,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.book_rft_transport_412(uuid,integer,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.collect_rft_transport_412(uuid,integer,uuid) TO authenticated;

ALTER FUNCTION public.get_pdc_email_vehicle_location_snapshot() RENAME TO get_pdc_email_vehicle_location_snapshot_pre_412;
CREATE FUNCTION public.get_pdc_email_vehicle_location_snapshot()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE r jsonb; rows jsonb;
BEGIN
 r:=public.get_pdc_email_vehicle_location_snapshot_pre_412(); IF NOT coalesce((r->>'ok')::boolean,false) THEN RETURN r; END IF;
 SELECT coalesce(jsonb_agg(x||jsonb_build_object('rft_transport_booked_at',v.rft_transport_booked_at,'rft_transport_booked_by',v.rft_transport_booked_by,'rft_collected_at',v.rft_collected_at,'rft_collected_by',v.rft_collected_by,
   'rft_transport_outbox',coalesce((SELECT jsonb_build_object('notification_id',o.notification_id,'delivery_status',o.delivery_status,'sent_at',o.sent_at,'delivered_at',o.delivered_at,'mandatory',true) FROM public.pdc_rft_transport_salesperson_outbox_412 o WHERE o.vehicle_id=v.id ORDER BY o.created_at DESC LIMIT 1),'{}'::jsonb)) ORDER BY coalesce(x->>'stock_number',x->>'vin',x->>'id')),'[]'::jsonb)
 INTO rows FROM jsonb_array_elements(coalesce(r#>'{data,vehicles}','[]'::jsonb)) x JOIN public.vehicles v ON v.id=(x->>'id')::uuid;
 RETURN jsonb_set(r,'{data,vehicles}',rows,true);
END $$;
REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_location_snapshot_pre_412() FROM public,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() FROM public,anon;
GRANT EXECUTE ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() TO authenticated;

DO $post$
BEGIN
 IF NOT has_function_privilege('authenticated','public.clear_vehicle_stoppage_412(uuid,integer,text,uuid)','EXECUTE')
   OR NOT has_function_privilege('authenticated','public.book_rft_transport_412(uuid,integer,uuid)','EXECUTE')
   OR NOT has_function_privilege('authenticated','public.collect_rft_transport_412(uuid,integer,uuid)','EXECUTE')
   OR has_function_privilege('anon','public.book_rft_transport_412(uuid,integer,uuid)','EXECUTE')
   OR has_table_privilege('authenticated','public.pdc_rft_transport_action_receipts_412','SELECT,INSERT,UPDATE,DELETE')
   OR has_table_privilege('authenticated','public.pdc_rft_transport_salesperson_outbox_412','SELECT,INSERT,UPDATE,DELETE') THEN
  RAISE EXCEPTION 'PDC_412_ACL_POSTCONDITION' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826173000','412_stoppage_rft_transport_workflow',ARRAY[
 'Receipt-backed clear-stoppage action returns stopped bookings to Unallocated and clears Parts stoppage when present',
 'RFT transport-booked timestamp/operator and mandatory pending salesperson outbox with completed work, dates, build times, stoppage history and QC photo attachment reference',
 'Collected requires transport-booking/outbox evidence, moves vehicle to Completed, hides it from active Board and removes/cancels active bay bookings',
 'Legacy direct collection route disabled; append-only receipts/outbox, exact UUID/version/idempotency and narrow authenticated RPC grants'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
