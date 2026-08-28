-- STAGING ONLY 734: durable RFT transport lifecycle successor.
--
-- This migration is append-only over the applied 700 lifecycle.  It repairs
-- the last semantic gap: collection is a distinct Collected state, while the
-- dealer-transit interval remains open until exact Toyota/Navision
-- "Delivered - At Dealer" evidence closes it.  No production object is
-- callable or mutated by this migration.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-734-durable-rft-transport-lifecycle',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR NOT EXISTS(SELECT 1 FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT max(version) FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$')<>'20260828550000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260828550000' AND name='733_acceptance_sublet_cleanup')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260829000000')
     OR to_regprocedure('public.pdc_rft_transport_snapshot_412(uuid)') IS NULL
     OR to_regprocedure('public.pdc_qc_operation_lines_379(uuid)') IS NULL
     OR to_regclass('public.pdc_qc_finalization_photo_evidence_399') IS NULL
     OR to_regclass('public.pdc_final_pdc_lifecycle_receipts_700') IS NULL
     OR to_regprocedure('public.cancel_workshop_booking(uuid,integer,text,jsonb)') IS NULL
  THEN RAISE EXCEPTION 'PDC_734_STAGING_ONLY' USING errcode='55000'; END IF;
END $guard$;

ALTER TABLE public.vehicles
  ADD COLUMN IF NOT EXISTS rft_transport_booked_at timestamptz,
  ADD COLUMN IF NOT EXISTS rft_transport_booked_by uuid REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS dealer_transit_started_at timestamptz,
  ADD COLUMN IF NOT EXISTS dealer_transit_closed_at timestamptz,
  ADD COLUMN IF NOT EXISTS dealer_transit_duration_seconds bigint;

CREATE TABLE public.pdc_rft_transport_lifecycle_receipts_734(
  receipt_id uuid PRIMARY KEY,
  vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
  action text NOT NULL CHECK(action IN('rft_booked','collected','delivered')),
  actor_id uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
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
CREATE INDEX pdc_rft_transport_lifecycle_receipts_734_vehicle_idx
  ON public.pdc_rft_transport_lifecycle_receipts_734(vehicle_id,created_at,action);

CREATE TABLE public.pdc_rft_transport_email_outbox_734(
  notification_id uuid PRIMARY KEY,
  lifecycle_receipt_id uuid NOT NULL UNIQUE REFERENCES public.pdc_rft_transport_lifecycle_receipts_734(receipt_id) ON DELETE RESTRICT,
  vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
  recipient_email text NOT NULL CHECK(recipient_email=lower(recipient_email) AND recipient_email~'^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
  delivery_status text NOT NULL DEFAULT 'intercepted' CHECK(delivery_status='intercepted'),
  delivery_enabled boolean NOT NULL DEFAULT false CHECK(NOT delivery_enabled),
  sent_at timestamptz,
  delivered_at timestamptz,
  payload jsonb NOT NULL CHECK(jsonb_typeof(payload)='object'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK(sent_at IS NULL AND delivered_at IS NULL)
);
CREATE INDEX pdc_rft_transport_email_outbox_734_vehicle_idx
  ON public.pdc_rft_transport_email_outbox_734(vehicle_id,created_at DESC);

CREATE TABLE public.pdc_rft_transport_email_evidence_734(
  evidence_id uuid PRIMARY KEY,
  notification_id uuid NOT NULL UNIQUE REFERENCES public.pdc_rft_transport_email_outbox_734(notification_id) ON DELETE RESTRICT,
  vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
  mime_version text NOT NULL CHECK(mime_version='1.0'),
  mime_content_type text NOT NULL CHECK(mime_content_type='multipart/mixed'),
  mime_sha256 text NOT NULL CHECK(mime_sha256~'^[a-f0-9]{64}$'),
  mime_document jsonb NOT NULL CHECK(jsonb_typeof(mime_document)='object'),
  photo_receipt_id uuid NOT NULL REFERENCES public.pdc_qc_finalization_photo_evidence_399(photo_receipt_id) ON DELETE RESTRICT,
  photo_bucket_id text NOT NULL,
  photo_storage_path text NOT NULL,
  photo_content_type text NOT NULL CHECK(photo_content_type LIKE 'image/%'),
  photo_byte_length integer NOT NULL CHECK(photo_byte_length>0),
  photo_sha256 text NOT NULL CHECK(photo_sha256~'^[a-f0-9]{64}$'),
  intercepted boolean NOT NULL DEFAULT true CHECK(intercepted),
  sent_at timestamptz,
  delivered_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK(sent_at IS NULL AND delivered_at IS NULL)
);

CREATE TABLE public.pdc_rft_dealer_transit_statistics_734(
  statistic_id uuid PRIMARY KEY,
  vehicle_id uuid NOT NULL UNIQUE REFERENCES public.vehicles(id) ON DELETE RESTRICT,
  delivered_receipt_id uuid NOT NULL UNIQUE REFERENCES public.pdc_rft_transport_lifecycle_receipts_734(receipt_id) ON DELETE RESTRICT,
  started_at timestamptz NOT NULL,
  closed_at timestamptz NOT NULL,
  duration_seconds bigint NOT NULL CHECK(duration_seconds>=0),
  status_literal text NOT NULL CHECK(status_literal='Delivered - At Dealer'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE OR REPLACE FUNCTION public.pdc_734_append_only()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN RAISE EXCEPTION 'PDC_734_APPEND_ONLY' USING errcode='55000'; END $$;
REVOKE ALL ON FUNCTION public.pdc_734_append_only() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_rft_transport_lifecycle_receipts_734_append_only
  BEFORE UPDATE OR DELETE ON public.pdc_rft_transport_lifecycle_receipts_734
  FOR EACH ROW EXECUTE FUNCTION public.pdc_734_append_only();
CREATE TRIGGER pdc_rft_transport_email_outbox_734_append_only
  BEFORE UPDATE OR DELETE ON public.pdc_rft_transport_email_outbox_734
  FOR EACH ROW EXECUTE FUNCTION public.pdc_734_append_only();
CREATE TRIGGER pdc_rft_transport_email_evidence_734_append_only
  BEFORE UPDATE OR DELETE ON public.pdc_rft_transport_email_evidence_734
  FOR EACH ROW EXECUTE FUNCTION public.pdc_734_append_only();
CREATE TRIGGER pdc_rft_dealer_transit_statistics_734_append_only
  BEFORE UPDATE OR DELETE ON public.pdc_rft_dealer_transit_statistics_734
  FOR EACH ROW EXECUTE FUNCTION public.pdc_734_append_only();

ALTER TABLE public.pdc_rft_transport_lifecycle_receipts_734 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_rft_transport_lifecycle_receipts_734 FORCE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_rft_transport_email_outbox_734 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_rft_transport_email_outbox_734 FORCE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_rft_transport_email_evidence_734 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_rft_transport_email_evidence_734 FORCE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_rft_dealer_transit_statistics_734 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_rft_dealer_transit_statistics_734 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_rft_transport_lifecycle_receipts_734 FROM public,anon,authenticated,service_role;
REVOKE ALL ON TABLE public.pdc_rft_transport_email_outbox_734 FROM public,anon,authenticated,service_role;
REVOKE ALL ON TABLE public.pdc_rft_transport_email_evidence_734 FROM public,anon,authenticated,service_role;
REVOKE ALL ON TABLE public.pdc_rft_dealer_transit_statistics_734 FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.pdc_rft_transport_lifecycle_state_734(p_vehicle_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
SELECT coalesce((SELECT jsonb_build_object(
  'state',CASE WHEN EXISTS(SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 r WHERE r.vehicle_id=v.id AND r.action='delivered') THEN 'completed'
    WHEN EXISTS(SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 r WHERE r.vehicle_id=v.id AND r.action='collected') THEN 'collected'
    WHEN EXISTS(SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 r WHERE r.vehicle_id=v.id AND r.action='rft_booked') THEN 'rft_booked'
    ELSE lower(v.lifecycle_state::text) END,
  'rft_booked',EXISTS(SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 r WHERE r.vehicle_id=v.id AND r.action='rft_booked'),
  'collected',EXISTS(SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 r WHERE r.vehicle_id=v.id AND r.action='collected'),
  'delivered',EXISTS(SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 r WHERE r.vehicle_id=v.id AND r.action='delivered'),
  'rft_transport_booked_at',v.rft_transport_booked_at,'dealer_transit_started_at',v.dealer_transit_started_at,
  'dealer_transit_closed_at',v.dealer_transit_closed_at,'dealer_transit_duration_seconds',v.dealer_transit_duration_seconds,
  'rft_collected_at',v.rft_collected_at,'rft_collected_by',v.rft_collected_by,'current_location',v.current_location,
  'lifecycle_state',v.lifecycle_state::text
) FROM public.vehicles v WHERE v.id=p_vehicle_id),'{}'::jsonb);
$$;
REVOKE ALL ON FUNCTION public.pdc_rft_transport_lifecycle_state_734(uuid) FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.pdc_rft_transport_snapshot_734(p_vehicle_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
SELECT coalesce(public.pdc_rft_transport_snapshot_412(p_vehicle_id),'{}'::jsonb)
  || jsonb_build_object(
    'pdc_lifecycle', public.pdc_rft_transport_lifecycle_state_734(p_vehicle_id),
    'rft_transport_outbox', coalesce((SELECT jsonb_build_object(
      'notification_id',o.notification_id,'delivery_status',o.delivery_status,'delivery_enabled',o.delivery_enabled,
      'sent_at',o.sent_at,'delivered_at',o.delivered_at,'intercepted',true,
      'evidence',coalesce((SELECT jsonb_build_object('evidence_id',e.evidence_id,'mime_version',e.mime_version,
        'mime_content_type',e.mime_content_type,'mime_sha256',e.mime_sha256,'photo_receipt_id',e.photo_receipt_id,
        'photo_bucket_id',e.photo_bucket_id,'photo_storage_path',e.photo_storage_path,'photo_content_type',e.photo_content_type,
        'photo_byte_length',e.photo_byte_length,'photo_sha256',e.photo_sha256,'intercepted',e.intercepted)
        FROM public.pdc_rft_transport_email_evidence_734 e WHERE e.notification_id=o.notification_id),'{}'::jsonb))
      FROM public.pdc_rft_transport_email_outbox_734 o WHERE o.vehicle_id=p_vehicle_id),'{}'::jsonb),
    'dealer_transit_statistic',coalesce((SELECT jsonb_build_object('statistic_id',s.statistic_id,'started_at',s.started_at,
      'closed_at',s.closed_at,'duration_seconds',s.duration_seconds,'status_literal',s.status_literal)
      FROM public.pdc_rft_dealer_transit_statistics_734 s WHERE s.vehicle_id=p_vehicle_id),'{}'::jsonb)
  );
$$;
REVOKE ALL ON FUNCTION public.pdc_rft_transport_snapshot_734(uuid) FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.pdc_rft_transport_lifecycle_state_734(p_vehicle_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
SELECT coalesce((SELECT jsonb_build_object(
  'state',CASE WHEN EXISTS(SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 r WHERE r.vehicle_id=v.id AND r.action='delivered') THEN 'completed'
    WHEN EXISTS(SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 r WHERE r.vehicle_id=v.id AND r.action='collected') THEN 'collected'
    WHEN EXISTS(SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 r WHERE r.vehicle_id=v.id AND r.action='rft_booked') THEN 'rft_booked'
    ELSE lower(v.lifecycle_state::text) END,
  'rft_booked',EXISTS(SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 r WHERE r.vehicle_id=v.id AND r.action='rft_booked'),
  'collected',EXISTS(SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 r WHERE r.vehicle_id=v.id AND r.action='collected'),
  'delivered',EXISTS(SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 r WHERE r.vehicle_id=v.id AND r.action='delivered'),
  'rft_transport_booked_at',v.rft_transport_booked_at,'dealer_transit_started_at',v.dealer_transit_started_at,
  'dealer_transit_closed_at',v.dealer_transit_closed_at,'dealer_transit_duration_seconds',v.dealer_transit_duration_seconds,
  'rft_collected_at',v.rft_collected_at,'rft_collected_by',v.rft_collected_by,'current_location',v.current_location,
  'lifecycle_state',v.lifecycle_state::text
) FROM public.vehicles v WHERE v.id=p_vehicle_id),'{}'::jsonb);
$$;
REVOKE ALL ON FUNCTION public.pdc_rft_transport_lifecycle_state_734(uuid) FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.book_rft_transport_734(
  p_vehicle_id uuid,p_expected_vehicle_version integer,p_idempotency_key uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions SET statement_timeout='120s' AS $book$
DECLARE
  uid uuid:=auth.uid(); actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v public.vehicles%rowtype; old public.pdc_rft_transport_lifecycle_receipts_734%rowtype;
  photo public.pdc_qc_finalization_photo_evidence_399%rowtype; snap jsonb; salesperson jsonb; lines jsonb;
  before_state jsonb; after_state jsonb; request_payload jsonb; request_sha text; payload jsonb; mime_document jsonb;
  body text; mime_sha text; receipt uuid; notification uuid; evidence_id uuid; booked_at timestamptz:=clock_timestamp(); result jsonb;
  object_count integer;
BEGIN
  IF uid IS NULL OR p_vehicle_id IS NULL OR p_expected_vehicle_version IS NULL OR p_expected_vehicle_version<1 OR p_idempotency_key IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','transport_booking_invalid_input'); END IF;
  IF NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=uid AND lower(r.email)=actor_email AND r.active AND r.account_status='approved' AND r.role IN('operator','administrator') FOR SHARE) THEN
    RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
  request_payload:=jsonb_build_object('contract','pdc-durable-rft-booked-734','vehicle_id',p_vehicle_id,'expected_vehicle_version',p_expected_vehicle_version,'idempotency_key',p_idempotency_key);
  request_sha:=encode(extensions.digest(convert_to(request_payload::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-734-book-actor:'||uid::text||':'||p_idempotency_key::text,0));
  SELECT * INTO old FROM public.pdc_rft_transport_lifecycle_receipts_734 WHERE actor_id=uid AND idempotency_key=p_idempotency_key;
  IF FOUND THEN
    IF old.request_sha256<>request_sha THEN RETURN jsonb_build_object('ok',false,'code','idempotency_payload_mismatch'); END IF;
    RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false);
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-734-book-vehicle:'||p_vehicle_id::text,0));
  SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
  IF NOT FOUND OR v.deleted_at IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_found'); END IF;
  SELECT * INTO old FROM public.pdc_rft_transport_lifecycle_receipts_734 WHERE vehicle_id=p_vehicle_id AND action='rft_booked';
  IF FOUND THEN RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false); END IF;
  IF v.version<>p_expected_vehicle_version THEN RETURN jsonb_build_object('ok',false,'code','vehicle_version_conflict','data',jsonb_build_object('vehicle_id',v.id,'vehicle_version',v.version)); END IF;
  IF v.lifecycle_state<>'rft' OR upper(btrim(coalesce(v.current_location,'')))<>'RFT' OR v.rft_collected_at IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_in_rft'); END IF;
  IF NOT EXISTS(SELECT 1 FROM public.pdc_final_pdc_lifecycle_receipts_700 q WHERE q.vehicle_id=v.id AND q.action='qc_signed_off') THEN RETURN jsonb_build_object('ok',false,'code','qc_receipt_required'); END IF;
  snap:=public.pdc_rft_transport_snapshot_734(v.id); salesperson:=snap->'salesperson';
  IF lower(btrim(coalesce(salesperson->>'salesperson_email','')))='' OR lower(btrim(salesperson->>'salesperson_email'))!~'^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' THEN RETURN jsonb_build_object('ok',false,'code','salesperson_email_required'); END IF;
  SELECT * INTO photo FROM public.pdc_qc_finalization_photo_evidence_399 WHERE vehicle_id=v.id ORDER BY created_at DESC LIMIT 1 FOR SHARE;
  IF NOT FOUND OR photo.bucket_id<>'pdc-qc-evidence-staging' OR photo.content_type NOT LIKE 'image/%' OR photo.byte_length<1 THEN RETURN jsonb_build_object('ok',false,'code','qc_photo_receipt_required'); END IF;
  SELECT count(*) INTO object_count FROM storage.objects o WHERE o.bucket_id=photo.bucket_id AND o.name=photo.storage_path;
  IF object_count<>1 THEN RETURN jsonb_build_object('ok',false,'code','qc_photo_storage_missing'); END IF;
  lines:=coalesce(public.pdc_qc_operation_lines_379(v.id),'[]'::jsonb);
  IF jsonb_array_length(lines)=0 OR EXISTS(SELECT 1 FROM jsonb_array_elements(lines) line WHERE coalesce((line->>'active')::boolean,false) AND (NOT coalesce((line->>'completed')::boolean,false) OR nullif(btrim(coalesce(line->>'estimated_hours','')),'') IS NULL)) THEN
    RETURN jsonb_build_object('ok',false,'code','qc_items_required'); END IF;
  before_state:=snap;
  UPDATE public.vehicles SET rft_transport_booked_at=booked_at,rft_transport_booked_by=uid,dealer_transit_started_at=booked_at,version=version+1,updated_at=booked_at,updated_by=uid WHERE id=v.id RETURNING * INTO v;
  snap:=public.pdc_rft_transport_snapshot_734(v.id); after_state:=snap;
  receipt:=extensions.uuid_generate_v5('73400000-0000-5000-8000-000000000734'::uuid,uid::text||':book:'||p_idempotency_key::text);
  notification:=extensions.uuid_generate_v5('73400000-0000-5000-8000-000000000734'::uuid,receipt::text||':salesperson-email');
  evidence_id:=extensions.uuid_generate_v5('73400000-0000-5000-8000-000000000734'::uuid,notification::text||':mime');
  body:=concat('RFT transport booked',chr(10),chr(10),'Stock: ',coalesce(v.stock_number,'(none)'),chr(10),'Job Card: ',coalesce(v.job_card_number,'(none)'),chr(10),'Customer: ',coalesce(v.customer_name,'(none)'),chr(10),'Vehicle: ',coalesce(v.vehicle_description,concat_ws(' ',v.make,v.model)),chr(10),'Completed work: ',coalesce(lines::text,'[]'),chr(10),'RFT transferred at: ',coalesce(v.rft_transferred_at::text,'(unknown)'),chr(10),'Transport booked at: ',booked_at::text);
  mime_document:=jsonb_build_object('mime_version','1.0','content_type','multipart/mixed','headers',jsonb_build_object('To',lower(btrim(salesperson->>'salesperson_email')),'Subject','RFT transport booked - Stock '||coalesce(v.stock_number,'No stock'),'X-PDC-Delivery','INTERCEPTED-STAGING'),'text_body',body,'completed_work',lines,'dates',jsonb_build_object('date_to_pmb',v.date_to_pmb,'date_to_rft',v.date_to_rft,'qc_completed_at',v.qc_completed_at,'rft_transferred_at',v.rft_transferred_at,'transport_booked_at',v.rft_transport_booked_at,'dealer_transit_started_at',v.dealer_transit_started_at),'build_times',snap->'build_times','stoppages',snap->'stoppages','photo_attachment',jsonb_build_object('photo_receipt_id',photo.photo_receipt_id,'bucket_id',photo.bucket_id,'storage_path',photo.storage_path,'content_type',photo.content_type,'byte_length',photo.byte_length,'sha256',photo.sha256,'original_filename',photo.original_filename));
  mime_sha:=encode(extensions.digest(convert_to(mime_document::text,'UTF8'),'sha256'),'hex');
  payload:=jsonb_build_object('contract','mandatory-rft-booked-salesperson-email-734','environment','staging','synthetic_only',left(upper(coalesce(v.stock_number,'')),11)='HERMES-TEST','delivery_enabled',false,'delivery_status','intercepted','intercepted',true,'notification_id',notification,'recipient',salesperson,'vehicle',jsonb_build_object('vehicle_id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,'stock_number',v.stock_number,'vin',v.vin,'job_card_number',v.job_card_number,'customer_name',v.customer_name,'vehicle_description',v.vehicle_description),'completed_work',lines,'relevant_dates',mime_document->'dates','build_times',snap->'build_times','stoppages',snap->'stoppages','photo_attachment',mime_document->'photo_attachment','mime_document',mime_document,'mime_sha256',mime_sha,'sent_at',null,'delivered_at',null);
  result:=jsonb_build_object('ok',true,'code','rft_transport_booked','replay',false,'data',jsonb_build_object('receipt_id',receipt,'notification_id',notification,'evidence_id',evidence_id,'vehicle_id',v.id,'vehicle_version_before',p_expected_vehicle_version,'vehicle_version_after',v.version,'transport_booked_at',booked_at,'dealer_transit_started_at',booked_at,'recipient_email',lower(btrim(salesperson->>'salesperson_email')),'delivery_status','intercepted','delivery_enabled',false,'intercepted',true,'mime_sha256',mime_sha));
  INSERT INTO public.pdc_rft_transport_lifecycle_receipts_734(receipt_id,vehicle_id,action,actor_id,actor_email,idempotency_key,request_sha256,request_payload,before_state,after_state,evidence,response)
  VALUES(receipt,v.id,'rft_booked',uid,actor_email,p_idempotency_key,request_sha,request_payload,before_state,after_state,jsonb_build_object('notification_id',notification,'evidence_id',evidence_id,'mime_sha256',mime_sha,'photo_receipt_id',photo.photo_receipt_id,'photo_storage_path',photo.storage_path,'photo_content_type',photo.content_type,'photo_byte_length',photo.byte_length,'photo_sha256',photo.sha256,'completed_work',lines,'delivery_enabled',false,'intercepted',true),result);
  INSERT INTO public.pdc_rft_transport_email_outbox_734(notification_id,lifecycle_receipt_id,vehicle_id,recipient_email,payload)
  VALUES(notification,receipt,v.id,lower(btrim(salesperson->>'salesperson_email')),payload);
  INSERT INTO public.pdc_rft_transport_email_evidence_734(evidence_id,notification_id,vehicle_id,mime_version,mime_content_type,mime_sha256,mime_document,photo_receipt_id,photo_bucket_id,photo_storage_path,photo_content_type,photo_byte_length,photo_sha256,intercepted,sent_at,delivered_at)
  VALUES(evidence_id,notification,v.id,'1.0','multipart/mixed',mime_sha,mime_document,photo.photo_receipt_id,photo.bucket_id,photo.storage_path,photo.content_type,photo.byte_length,photo.sha256,true,null,null);
  PERFORM public.audit_pdc_event('update','vehicles',v.id,v.id,before_state,after_state,jsonb_build_object('action','book_rft_transport_734','receipt_id',receipt,'notification_id',notification,'email_delivery','intercepted','timer_started_at',booked_at));
  IF v.rft_transport_booked_at IS DISTINCT FROM booked_at OR v.dealer_transit_started_at IS DISTINCT FROM booked_at
     OR NOT EXISTS(SELECT 1 FROM public.pdc_rft_transport_email_outbox_734 o WHERE o.notification_id=notification AND o.delivery_status='intercepted' AND NOT o.delivery_enabled AND o.sent_at IS NULL AND o.delivered_at IS NULL)
     OR NOT EXISTS(SELECT 1 FROM public.pdc_rft_transport_email_evidence_734 e WHERE e.vehicle_id=v.id AND e.intercepted AND e.photo_receipt_id=photo.photo_receipt_id) THEN
    RAISE EXCEPTION 'PDC_734_BOOK_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
  RETURN result;
EXCEPTION WHEN unique_violation THEN
  SELECT * INTO old FROM public.pdc_rft_transport_lifecycle_receipts_734 WHERE actor_id=uid AND idempotency_key=p_idempotency_key;
  IF FOUND THEN RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false); END IF;
  SELECT * INTO old FROM public.pdc_rft_transport_lifecycle_receipts_734 WHERE vehicle_id=p_vehicle_id AND action='rft_booked';
  IF FOUND THEN RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false); END IF;
  RETURN jsonb_build_object('ok',false,'code','rft_booking_conflict');
END $book$;
REVOKE ALL ON FUNCTION public.book_rft_transport_734(uuid,integer,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.book_rft_transport_734(uuid,integer,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.collect_rft_transport_734(
  p_vehicle_id uuid,p_expected_vehicle_version integer,p_idempotency_key uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions SET statement_timeout='120s' AS $collect$
DECLARE
  uid uuid:=auth.uid(); actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); v public.vehicles%rowtype; old public.pdc_rft_transport_lifecycle_receipts_734%rowtype; b public.workshop_bookings%rowtype;
  request_payload jsonb; request_sha text; before_state jsonb; after_state jsonb; receipt uuid; result jsonb; booking_result jsonb; movement uuid; cancelled integer:=0; collected_at timestamptz:=clock_timestamp();
BEGIN
  IF uid IS NULL OR p_vehicle_id IS NULL OR p_expected_vehicle_version IS NULL OR p_expected_vehicle_version<1 OR p_idempotency_key IS NULL THEN RETURN jsonb_build_object('ok',false,'code','collection_invalid_input'); END IF;
  IF NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=uid AND lower(r.email)=actor_email AND r.active AND r.account_status='approved' AND r.role IN('operator','administrator') FOR SHARE) THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
  request_payload:=jsonb_build_object('contract','pdc-durable-rft-collected-734','vehicle_id',p_vehicle_id,'expected_vehicle_version',p_expected_vehicle_version,'idempotency_key',p_idempotency_key);
  request_sha:=encode(extensions.digest(convert_to(request_payload::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-734-collect-actor:'||uid::text||':'||p_idempotency_key::text,0));
  SELECT * INTO old FROM public.pdc_rft_transport_lifecycle_receipts_734 WHERE actor_id=uid AND idempotency_key=p_idempotency_key;
  IF FOUND THEN IF old.request_sha256<>request_sha THEN RETURN jsonb_build_object('ok',false,'code','idempotency_payload_mismatch'); END IF; RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false); END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-734-collect-vehicle:'||p_vehicle_id::text,0));
  SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
  IF NOT FOUND OR v.deleted_at IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_found'); END IF;
  SELECT * INTO old FROM public.pdc_rft_transport_lifecycle_receipts_734 WHERE vehicle_id=p_vehicle_id AND action='collected';
  IF FOUND THEN RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false); END IF;
  IF v.version<>p_expected_vehicle_version THEN RETURN jsonb_build_object('ok',false,'code','vehicle_version_conflict','data',jsonb_build_object('vehicle_id',v.id,'vehicle_version',v.version)); END IF;
  IF v.lifecycle_state<>'rft' OR upper(btrim(coalesce(v.current_location,'')))<>'RFT' OR v.rft_collected_at IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_in_rft'); END IF;
  IF NOT EXISTS(SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 r WHERE r.vehicle_id=v.id AND r.action='rft_booked')
     OR NOT EXISTS(SELECT 1 FROM public.pdc_rft_transport_email_outbox_734 o WHERE o.vehicle_id=v.id AND o.delivery_status='intercepted' AND NOT o.delivery_enabled AND o.sent_at IS NULL AND o.delivered_at IS NULL)
     OR NOT EXISTS(SELECT 1 FROM public.pdc_rft_transport_email_evidence_734 e WHERE e.vehicle_id=v.id AND e.intercepted) THEN RETURN jsonb_build_object('ok',false,'code','transport_booking_required'); END IF;
  IF EXISTS(SELECT 1 FROM public.workshop_bookings x WHERE x.vehicle_id=v.id AND x.status::text='started') THEN RETURN jsonb_build_object('ok',false,'code','started_booking_must_be_completed_before_collection'); END IF;
  before_state:=public.pdc_rft_transport_snapshot_734(v.id);
  FOR b IN SELECT * FROM public.workshop_bookings WHERE vehicle_id=v.id AND status::text IN('queued','planned','stoppage') ORDER BY id FOR UPDATE LOOP
    booking_result:=public.cancel_workshop_booking(b.id,b.version,'Vehicle collected from RFT',jsonb_build_object('source','collect_rft_transport_734'));
    IF NOT coalesce((booking_result->>'ok')::boolean,false) THEN RAISE EXCEPTION 'PDC_734_BOOKING_CANCEL_FAILED:%',coalesce(booking_result->>'error',booking_result->>'code','unknown') USING errcode='40001'; END IF;
    cancelled:=cancelled+1;
  END LOOP;
  UPDATE public.vehicles SET lifecycle_state='rft',current_location='Collected',rft_collected_at=collected_at,rft_collected_by=uid,visible_on_board=false,pmb_stage=NULL,pmb_bay_stage=NULL,pmb_bay_number=NULL,active_workshop_booking_id=NULL,workshop_status='queued',workshop_status_updated_at=collected_at,workshop_status_updated_by=uid,version=version+1,updated_at=collected_at,updated_by=uid WHERE id=v.id RETURNING * INTO v;
  INSERT INTO public.vehicle_movements(vehicle_id,from_location,to_location,from_pmb_stage,to_pmb_stage,from_pmb_bay_stage,to_pmb_bay_stage,from_pmb_bay_number,to_pmb_bay_number,reason,moved_by)
  VALUES(v.id,'RFT','Collected',NULL,NULL,NULL,NULL,NULL,NULL,'RFT vehicle collected; dealer-transit timer remains open',uid) RETURNING id INTO movement;
  after_state:=public.pdc_rft_transport_snapshot_734(v.id);
  receipt:=extensions.uuid_generate_v5('73400000-0000-5000-8000-000000000734'::uuid,uid::text||':collect:'||p_idempotency_key::text);
  result:=jsonb_build_object('ok',true,'code','rft_vehicle_collected','replay',false,'data',jsonb_build_object('receipt_id',receipt,'vehicle_id',v.id,'vehicle_version_before',p_expected_vehicle_version,'vehicle_version_after',v.version,'collected_at',collected_at,'current_location','Collected','lifecycle_state','rft','dealer_transit_started_at',v.dealer_transit_started_at,'dealer_transit_closed_at',null,'dealer_transit_duration_seconds',null,'cancelled_non_started_allocation_count',cancelled,'movement_id',movement,'timer_closed',false,'completed',false));
  INSERT INTO public.pdc_rft_transport_lifecycle_receipts_734(receipt_id,vehicle_id,action,actor_id,actor_email,idempotency_key,request_sha256,request_payload,before_state,after_state,evidence,response)
  VALUES(receipt,v.id,'collected',uid,actor_email,p_idempotency_key,request_sha,request_payload,before_state,after_state,jsonb_build_object('cancelled_non_started_allocation_count',cancelled,'cleared_active_bay',true,'workshop_booking_history_retained',true,'timer_started_at',v.dealer_transit_started_at,'timer_closed',false,'completed',false),result);
  PERFORM public.audit_pdc_event('update','vehicles',v.id,v.id,before_state,after_state,jsonb_build_object('action','collect_rft_transport_734','receipt_id',receipt,'movement_id',movement,'cancelled_non_started_allocation_count',cancelled,'timer_closed',false,'completed',false));
  RETURN result;
EXCEPTION WHEN unique_violation THEN
  SELECT * INTO old FROM public.pdc_rft_transport_lifecycle_receipts_734 WHERE actor_id=uid AND idempotency_key=p_idempotency_key;
  IF FOUND THEN RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false); END IF;
  SELECT * INTO old FROM public.pdc_rft_transport_lifecycle_receipts_734 WHERE vehicle_id=p_vehicle_id AND action='collected';
  IF FOUND THEN RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false); END IF;
  RETURN jsonb_build_object('ok',false,'code','collection_conflict');
END $collect$;
REVOKE ALL ON FUNCTION public.collect_rft_transport_734(uuid,integer,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.collect_rft_transport_734(uuid,integer,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.reconcile_navision_delivery_734(
  p_backend_record_id uuid,p_actor_id uuid DEFAULT NULL,p_actor_email text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions SET statement_timeout='120s' AS $delivery$
DECLARE
  actor_id uuid:=p_actor_id; actor_email text:=lower(btrim(coalesce(p_actor_email,''))); b public.navision_backend_records%rowtype; v public.vehicles%rowtype; old public.pdc_rft_transport_lifecycle_receipts_734%rowtype;
  raw_status text; normalized text; request_payload jsonb; request_sha text; before_state jsonb; after_state jsonb; receipt uuid; result jsonb; closed_at timestamptz:=clock_timestamp(); duration bigint; statistic uuid; activation public.navision_board_activations%rowtype;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() OR p_backend_record_id IS NULL THEN RETURN public.navision_backend_response(false,'wrong_environment_or_invalid_input'); END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-734-delivery-record:'||p_backend_record_id::text,0));
  SELECT * INTO b FROM public.navision_backend_records WHERE id=p_backend_record_id FOR UPDATE;
  IF NOT FOUND OR NOT b.is_current OR b.record_status<>'current' OR b.canonical_vehicle_id IS NULL THEN RETURN public.navision_backend_response(false,'delivery_record_not_current'); END IF;
  raw_status:=btrim(coalesce(b.normalized_data->>'toyotaStatus',''));
  normalized:=lower(replace(replace(replace(btrim(raw_status),'–','-'),' ',''),'-',''));
  IF normalized<>'deliveredatdealer' THEN RETURN public.navision_backend_response(false,'delivery_status_not_exact'); END IF;
  SELECT * INTO v FROM public.vehicles WHERE id=b.canonical_vehicle_id FOR UPDATE;
  IF NOT FOUND OR v.deleted_at IS NOT NULL THEN RETURN public.navision_backend_response(false,'delivery_vehicle_not_found'); END IF;
  IF b.dealer_code IS DISTINCT FROM v.source_batch_id THEN RETURN public.navision_backend_response(false,'delivery_wrong_dealer_scope'); END IF;
  SELECT * INTO old FROM public.pdc_rft_transport_lifecycle_receipts_734 WHERE vehicle_id=v.id AND action='delivered';
  IF FOUND THEN RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false); END IF;
  IF NOT EXISTS(SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 r WHERE r.vehicle_id=v.id AND r.action='rft_booked')
     OR NOT EXISTS(SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 r WHERE r.vehicle_id=v.id AND r.action='collected') THEN RETURN public.navision_backend_response(false,'delivery_requires_collected_interval'); END IF;
  IF v.lifecycle_state<>'rft' OR upper(btrim(coalesce(v.current_location,'')))<>'COLLECTED' OR v.dealer_transit_started_at IS NULL OR v.dealer_transit_closed_at IS NOT NULL OR v.dealer_transit_duration_seconds IS NOT NULL THEN RETURN public.navision_backend_response(false,'delivery_interval_not_open'); END IF;
  duration:=greatest(0,floor(extract(epoch FROM (closed_at-v.dealer_transit_started_at)))::bigint);
  request_payload:=jsonb_build_object('contract','pdc-durable-navision-delivery-734','backend_record_id',p_backend_record_id,'vehicle_id',v.id,'status','Delivered - At Dealer');
  request_sha:=encode(extensions.digest(convert_to(request_payload::text,'UTF8'),'sha256'),'hex');
  before_state:=public.pdc_rft_transport_snapshot_734(v.id);
  UPDATE public.vehicles SET lifecycle_state='completed',current_location='Completed',visible_on_board=false,dealer_transit_closed_at=closed_at,dealer_transit_duration_seconds=duration,delivered_to_dealer_date=coalesce(delivered_to_dealer_date,(closed_at AT TIME ZONE 'Australia/Perth')::date),source_payload=coalesce(source_payload,'{}'::jsonb)||jsonb_build_object('authority','pdc_durable_rft_transport_734','navision_record_id',p_backend_record_id,'navision_status_literal','Delivered - At Dealer','delivered_at',closed_at),version=version+1,updated_at=closed_at,updated_by=actor_id WHERE id=v.id RETURNING * INTO v;
  UPDATE public.navision_board_activations SET canonical_vehicle_id=v.id,active=false,completed_at=coalesce(completed_at,closed_at),completion_reason='Delivered - At Dealer',completed_by=actor_id,completed_by_email=actor_email,updated_at=closed_at WHERE backend_record_id=b.id RETURNING * INTO activation;
  receipt:=extensions.uuid_generate_v5('73400000-0000-5000-8000-000000000734'::uuid,'delivery:'||p_backend_record_id::text||':'||v.id::text);
  result:=jsonb_build_object('ok',true,'code','delivered_at_dealer_completed','replay',false,'data',jsonb_build_object('receipt_id',receipt,'vehicle_id',v.id,'backend_record_id',p_backend_record_id,'status','Delivered - At Dealer','vehicle_version_after',v.version,'dealer_transit_started_at',v.dealer_transit_started_at,'dealer_transit_closed_at',closed_at,'dealer_transit_duration_seconds',duration,'current_location','Completed','lifecycle_state','completed'));
  after_state:=public.pdc_rft_transport_snapshot_734(v.id);
  INSERT INTO public.pdc_rft_transport_lifecycle_receipts_734(receipt_id,vehicle_id,action,actor_id,actor_email,idempotency_key,request_sha256,request_payload,before_state,after_state,evidence,response)
  VALUES(receipt,v.id,'delivered',actor_id,coalesce(nullif(actor_email,''),'system@staging.invalid'),extensions.uuid_generate_v5('73400000-0000-5000-8000-000000000734'::uuid,'delivery-idempotency:'||p_backend_record_id::text||':'||v.id::text),request_sha,request_payload,before_state,after_state,jsonb_build_object('exact_status_literal',true,'normalized_status',normalized,'dealer_scope_exact',true,'open_interval_required',true,'duration_seconds',duration),result);
  statistic:=extensions.uuid_generate_v5('73400000-0000-5000-8000-000000000734'::uuid,'statistic:'||v.id::text);
  INSERT INTO public.pdc_rft_dealer_transit_statistics_734(statistic_id,vehicle_id,delivered_receipt_id,started_at,closed_at,duration_seconds,status_literal)
  VALUES(statistic,v.id,receipt,v.dealer_transit_started_at,closed_at,duration,'Delivered - At Dealer');
  PERFORM public.audit_pdc_event('update','vehicles',v.id,v.id,before_state,after_state,jsonb_build_object('action','reconcile_navision_delivery_734','receipt_id',receipt,'backend_record_id',p_backend_record_id,'status_literal','Delivered - At Dealer','duration_seconds',duration));
  UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=closed_at WHERE singleton;
  UPDATE public.navision_backend_revision SET revision=revision+1,updated_at=closed_at WHERE singleton;
  RETURN result;
EXCEPTION WHEN unique_violation THEN
  SELECT * INTO old FROM public.pdc_rft_transport_lifecycle_receipts_734 WHERE vehicle_id=b.canonical_vehicle_id AND action='delivered';
  IF FOUND THEN RETURN jsonb_set(old.response,'{replay}','true'::jsonb,false); END IF;
  RETURN public.navision_backend_response(false,'delivery_replay_conflict');
END $delivery$;
REVOKE ALL ON FUNCTION public.reconcile_navision_delivery_734(uuid,uuid,text) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.reconcile_navision_delivery_734(uuid,uuid,text) TO authenticated,service_role;

-- The old public RPC names are retained as fail-closed compatibility fences.
CREATE OR REPLACE FUNCTION public.rft_collect_vehicle(p_vehicle_id uuid,p_expected_version integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN RETURN jsonb_build_object('ok',false,'error','transport_lifecycle_successor_required','code','transport_lifecycle_successor_required'); END $$;
REVOKE ALL ON FUNCTION public.rft_collect_vehicle(uuid,integer) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.rft_collect_vehicle(uuid,integer) TO authenticated;
CREATE OR REPLACE FUNCTION public.book_rft_transport_700(p_vehicle_id uuid,p_expected_vehicle_version integer,p_idempotency_key uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN RETURN jsonb_build_object('ok',false,'code','transport_lifecycle_successor_required'); END $$;
REVOKE ALL ON FUNCTION public.book_rft_transport_700(uuid,integer,uuid) FROM public,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.collect_rft_transport_700(p_vehicle_id uuid,p_expected_vehicle_version integer,p_idempotency_key uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN RETURN jsonb_build_object('ok',false,'code','transport_lifecycle_successor_required'); END $$;
REVOKE ALL ON FUNCTION public.collect_rft_transport_700(uuid,integer,uuid) FROM public,anon,authenticated,service_role;

-- Protect Collected and Completed latches from old mail/Navision paths. Exact
-- Delivered - At Dealer is the only allowed completion route.
ALTER FUNCTION public.reconcile_navision_operational_record(uuid,uuid,text) RENAME TO reconcile_navision_operational_record_pre_734;
CREATE FUNCTION public.reconcile_navision_operational_record(p_backend_record_id uuid,p_actor_id uuid DEFAULT NULL,p_actor_email text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,extensions AS $wrapper$
DECLARE b public.navision_backend_records%rowtype; v public.vehicles%rowtype; raw_status text; normalized text;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() THEN RETURN public.navision_backend_response(false,'wrong_environment'); END IF;
  SELECT * INTO b FROM public.navision_backend_records WHERE id=p_backend_record_id;
  IF FOUND THEN
    raw_status:=btrim(coalesce(b.normalized_data->>'toyotaStatus',''));
    normalized:=lower(replace(replace(replace(btrim(raw_status),'–','-'),' ',''),'-',''));
    IF normalized='deliveredatdealer' THEN RETURN public.reconcile_navision_delivery_734(p_backend_record_id,p_actor_id,p_actor_email); END IF;
    IF b.canonical_vehicle_id IS NOT NULL THEN
      SELECT * INTO v FROM public.vehicles WHERE id=b.canonical_vehicle_id;
      IF FOUND AND (v.lifecycle_state='completed' OR upper(btrim(coalesce(v.current_location,'')))='COMPLETED') THEN RETURN public.navision_backend_response(false,'protected_completed_lifecycle'); END IF;
      IF FOUND AND (upper(btrim(coalesce(v.current_location,'')))='COLLECTED' OR v.rft_collected_at IS NOT NULL) THEN RETURN public.navision_backend_response(false,'protected_collected_lifecycle'); END IF;
    END IF;
  END IF;
  RETURN public.reconcile_navision_operational_record_pre_734(p_backend_record_id,p_actor_id,p_actor_email);
END $wrapper$;
REVOKE ALL ON FUNCTION public.reconcile_navision_operational_record_pre_734(uuid,uuid,text) FROM public,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.reconcile_navision_operational_record(uuid,uuid,text) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.reconcile_navision_operational_record(uuid,uuid,text) TO authenticated,service_role;

CREATE OR REPLACE FUNCTION public.read_pdc_rft_transport_evidence_734(p_vehicle_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE uid uuid:=auth.uid(); email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); v public.vehicles%rowtype; r jsonb; o jsonb; e jsonb; s jsonb;
BEGIN
  IF uid IS NULL OR NOT EXISTS(SELECT 1 FROM public.pdc_user_roles x WHERE x.auth_user_id=uid AND lower(x.email)=lower(btrim(coalesce(auth.jwt()->>'email',''))) AND x.active AND x.account_status='approved' AND x.role IN('viewer','operator','administrator','importer')) THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
  SELECT * INTO v FROM public.vehicles WHERE id=p_vehicle_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_found'); END IF;
  SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.created_at,x.action),'[]'::jsonb) INTO r FROM public.pdc_rft_transport_lifecycle_receipts_734 x WHERE x.vehicle_id=p_vehicle_id;
  SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.created_at),'[]'::jsonb) INTO o FROM public.pdc_rft_transport_email_outbox_734 x WHERE x.vehicle_id=p_vehicle_id;
  SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.created_at),'[]'::jsonb) INTO e FROM public.pdc_rft_transport_email_evidence_734 x WHERE x.vehicle_id=p_vehicle_id;
  SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.created_at),'[]'::jsonb) INTO s FROM public.pdc_rft_dealer_transit_statistics_734 x WHERE x.vehicle_id=p_vehicle_id;
  RETURN jsonb_build_object('ok',true,'code','rft_transport_evidence','vehicle_id',p_vehicle_id,'vehicle',to_jsonb(v),'receipts',r,'outbox',o,'email_evidence',e,'statistics',s,'production',false,'delivery_intercepted',true);
END $$;
REVOKE ALL ON FUNCTION public.read_pdc_rft_transport_evidence_734(uuid) FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.read_pdc_rft_transport_evidence_734(uuid) TO authenticated;

-- Project the successor state into the existing authoritative email snapshot.
ALTER FUNCTION public.get_pdc_email_vehicle_location_snapshot() RENAME TO get_pdc_email_vehicle_location_snapshot_pre_734;
CREATE FUNCTION public.get_pdc_email_vehicle_location_snapshot()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $snapshot$
DECLARE r jsonb; rows jsonb; appended jsonb;
BEGIN
  r:=public.get_pdc_email_vehicle_location_snapshot_pre_734();
  IF NOT coalesce((r->>'ok')::boolean,false) THEN RETURN r; END IF;
  SELECT coalesce(jsonb_agg(x||jsonb_build_object('pdc_lifecycle',public.pdc_rft_transport_lifecycle_state_734((x->>'id')::uuid),'rft_transport_outbox',coalesce((SELECT jsonb_build_object('notification_id',o.notification_id,'delivery_status',o.delivery_status,'delivery_enabled',o.delivery_enabled,'sent_at',o.sent_at,'delivered_at',o.delivered_at,'intercepted',true,'evidence',coalesce((SELECT jsonb_build_object('evidence_id',e.evidence_id,'mime_version',e.mime_version,'mime_content_type',e.mime_content_type,'mime_sha256',e.mime_sha256,'photo_receipt_id',e.photo_receipt_id,'photo_bucket_id',e.photo_bucket_id,'photo_storage_path',e.photo_storage_path,'photo_content_type',e.photo_content_type,'photo_byte_length',e.photo_byte_length,'photo_sha256',e.photo_sha256,'intercepted',e.intercepted) FROM public.pdc_rft_transport_email_evidence_734 e WHERE e.notification_id=o.notification_id),'{}'::jsonb)) FROM public.pdc_rft_transport_email_outbox_734 o WHERE o.vehicle_id=(x->>'id')::uuid ORDER BY o.created_at DESC LIMIT 1),'{}'::jsonb),'dealer_transit_statistic',coalesce((SELECT jsonb_build_object('statistic_id',s.statistic_id,'started_at',s.started_at,'closed_at',s.closed_at,'duration_seconds',s.duration_seconds,'status_literal',s.status_literal) FROM public.pdc_rft_dealer_transit_statistics_734 s WHERE s.vehicle_id=(x->>'id')::uuid),'{}'::jsonb)) ORDER BY coalesce(x->>'stock_number',x->>'vin',x->>'id')),'[]'::jsonb) INTO rows
  FROM jsonb_array_elements(coalesce(r#>'{data,vehicles}','[]'::jsonb)) x;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',v.id,'permanent_vehicle_id',v.permanent_vehicle_id,'version',v.version,'stock_number',v.stock_number,'vin',v.vin,'job_card_number',v.job_card_number,'customer_name',v.customer_name,'vehicle_description',v.vehicle_description,'model',v.model,'registration',v.registration,'current_location',v.current_location,'lifecycle_state',v.lifecycle_state::text,'visible_on_board',v.visible_on_board,'pmb_stage',v.pmb_stage,'pmb_bay_stage',v.pmb_bay_stage,'pmb_bay_number',v.pmb_bay_number,'date_to_pmb',v.date_to_pmb,'date_to_rft',v.date_to_rft,'rft_transferred_at',v.rft_transferred_at,'rft_collected_at',v.rft_collected_at,'rft_collected_by',v.rft_collected_by,'qc_completed_at',v.qc_completed_at,'qc_completed_by',v.qc_completed_by,'rft_transport_booked_at',v.rft_transport_booked_at,'rft_transport_booked_by',v.rft_transport_booked_by,'dealer_transit_started_at',v.dealer_transit_started_at,'dealer_transit_closed_at',v.dealer_transit_closed_at,'dealer_transit_duration_seconds',v.dealer_transit_duration_seconds,'salesperson_id',v.salesperson_id,'salesperson_reference',sp->>'salesperson_name','salesperson_code',sp->>'salesperson_code','salesperson_name',sp->>'salesperson_name','salesperson_email',sp->>'salesperson_email','work_items',coalesce((SELECT jsonb_agg(to_jsonb(w) ORDER BY w.work_key) FROM public.vehicle_work_items w WHERE w.vehicle_id=v.id),'[]'::jsonb),'pdc_lifecycle',public.pdc_rft_transport_lifecycle_state_734(v.id),'rft_transport_outbox',coalesce((SELECT jsonb_build_object('notification_id',o.notification_id,'delivery_status',o.delivery_status,'delivery_enabled',o.delivery_enabled,'sent_at',o.sent_at,'delivered_at',o.delivered_at,'intercepted',true) FROM public.pdc_rft_transport_email_outbox_734 o WHERE o.vehicle_id=v.id ORDER BY o.created_at DESC LIMIT 1),'{}'::jsonb),'dealer_transit_statistic',coalesce((SELECT jsonb_build_object('statistic_id',s.statistic_id,'started_at',s.started_at,'closed_at',s.closed_at,'duration_seconds',s.duration_seconds,'status_literal',s.status_literal) FROM public.pdc_rft_dealer_transit_statistics_734 s WHERE s.vehicle_id=v.id),'{}'::jsonb)
  ) ORDER BY v.rft_collected_at,v.id),'[]'::jsonb) INTO appended
  FROM public.vehicles v CROSS JOIN LATERAL public.pdc_vehicle_effective_salesperson_json_386(v.id) sp
  WHERE v.deleted_at IS NULL AND v.current_location IN('Collected','Completed') AND EXISTS(SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 q WHERE q.vehicle_id=v.id AND q.action IN('collected','delivered')) AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(rows) x WHERE (x->>'id')=v.id::text);
  rows:=rows||coalesce(appended,'[]'::jsonb);
  RETURN jsonb_set(r,'{data,vehicles}',rows,true);
END $snapshot$;
REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_location_snapshot_pre_734() FROM public,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() TO authenticated;

DO $post$
BEGIN
  IF NOT has_function_privilege('authenticated','public.book_rft_transport_734(uuid,integer,uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.collect_rft_transport_734(uuid,integer,uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.read_pdc_rft_transport_evidence_734(uuid)','EXECUTE')
     OR has_function_privilege('anon','public.book_rft_transport_734(uuid,integer,uuid)','EXECUTE')
     OR has_table_privilege('authenticated','public.pdc_rft_transport_lifecycle_receipts_734','SELECT,INSERT,UPDATE,DELETE')
     OR has_table_privilege('authenticated','public.pdc_rft_transport_email_outbox_734','SELECT,INSERT,UPDATE,DELETE')
     OR (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid='public.pdc_rft_transport_lifecycle_receipts_734'::regclass) IS DISTINCT FROM true
     OR EXISTS(SELECT 1 FROM public.pdc_rft_transport_email_outbox_734 WHERE delivery_enabled OR sent_at IS NOT NULL OR delivered_at IS NOT NULL)
  THEN RAISE EXCEPTION 'PDC_734_SECURITY_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260829000000','734_durable_rft_transport_lifecycle',ARRAY[
  'Staging-only append-only lifecycle receipts, intercepted MIME/photo email evidence, and immutable dealer-transit statistics',
  'RFT Booked is the only transport-booking confirmation; salesperson email, completed QC items, dates, build times, stoppages and durable photo metadata are atomically captured with delivery disabled',
  'Collected is lifecycle_state rft/current_location Collected, requires booked email evidence, blocks STARTED work, clears non-started allocations and bays, and retains history without completing the vehicle',
  'Only exact Toyota/Navision Delivered - At Dealer closes the open interval, saves seconds as a statistic, and moves Collected to Completed idempotently',
  'Old rft_collect_vehicle and 700 transport routes fail closed; old mail/Navision cannot reopen or regress Collected/Completed latches',
  'Authoritative snapshot/readback exposes RFT Booked, Collected, Completed, intercepted MIME/photo evidence and timer statistics; Production sentinel is forbidden'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
