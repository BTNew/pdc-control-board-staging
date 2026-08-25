-- STAGING ONLY 399: receipt-backed QC photo finalization, salesperson outbox and
-- atomic QC -> RFT transition. Production is intentionally untouched. The
-- salesperson update is an immutable, unsent staging outbox record; no dispatch
-- worker, mailbox or real notification is enabled here.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-399-qc-finalization-photo-rft',0));

DO $pre$
DECLARE v_head text;
BEGIN
  SELECT max(version) INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$';
  IF current_user<>'postgres' OR session_user<>'postgres'
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR v_head IS DISTINCT FROM '20260826131500'
    OR to_regprocedure('public.pdc_qc_operation_lines_379(uuid)') IS NULL
    OR to_regprocedure('public.pdc_vehicle_effective_salesperson_json_386(uuid)') IS NULL
    OR to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()') IS NULL
    OR to_regclass('public.vehicles') IS NULL
    OR to_regclass('public.vehicle_movements') IS NULL
    OR to_regclass('public.audit_events') IS NULL
    OR to_regclass('storage.objects') IS NULL
    OR (SELECT count(*) FROM public.vehicle_notifications)<>1 THEN
    RAISE EXCEPTION 'PDC_399_STAGING_HEAD_OR_CONTAINMENT_MISMATCH' USING errcode='55000';
  END IF;
END $pre$;

-- The bucket is private and only accepts paths owned by the authenticated
-- uploader. The application never receives a public URL for this evidence.
INSERT INTO storage.buckets(id,name,public)
VALUES('pdc-qc-evidence-staging','pdc-qc-evidence-staging',false)
ON CONFLICT(id) DO UPDATE SET public=false;
DROP POLICY IF EXISTS pdc_qc_evidence_upload_399 ON storage.objects;
CREATE POLICY pdc_qc_evidence_upload_399 ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK(
    bucket_id='pdc-qc-evidence-staging'
    AND name LIKE 'qc-finalization/'||auth.uid()::text||'/%'
  );

CREATE TABLE public.pdc_qc_finalization_photo_evidence_399(
  photo_receipt_id uuid PRIMARY KEY,
  vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
  expected_vehicle_version integer NOT NULL CHECK(expected_vehicle_version>0),
  uploader_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  uploader_email text NOT NULL CHECK(length(btrim(uploader_email))>3),
  bucket_id text NOT NULL CHECK(bucket_id='pdc-qc-evidence-staging'),
  storage_path text NOT NULL CHECK(storage_path~'^qc-finalization/[0-9a-f-]{36}/[0-9a-f-]{36}/[^/]{1,180}$'),
  content_type text NOT NULL CHECK(content_type LIKE 'image/%'),
  byte_length integer NOT NULL CHECK(byte_length BETWEEN 1 AND 1048576),
  original_byte_length integer NOT NULL CHECK(original_byte_length BETWEEN 1 AND 10485760),
  image_width integer NOT NULL CHECK(image_width BETWEEN 1 AND 1600),
  image_height integer NOT NULL CHECK(image_height BETWEEN 1 AND 1600),
  sha256 text NOT NULL CHECK(sha256~'^[a-f0-9]{64}$'),
  original_filename text NOT NULL CHECK(length(btrim(original_filename)) BETWEEN 1 AND 180),
  idempotency_key uuid NOT NULL,
  request_sha256 text NOT NULL CHECK(request_sha256~'^[a-f0-9]{64}$'),
  response jsonb NOT NULL CHECK(jsonb_typeof(response)='object'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(vehicle_id),
  UNIQUE(uploader_id,idempotency_key)
);
ALTER TABLE public.pdc_qc_finalization_photo_evidence_399 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_qc_finalization_photo_evidence_399 FROM public,anon,authenticated,service_role;

CREATE TABLE public.pdc_qc_finalization_receipts_399(
  receipt_id uuid PRIMARY KEY,
  vehicle_id uuid NOT NULL UNIQUE REFERENCES public.vehicles(id) ON DELETE RESTRICT,
  actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  actor_email text NOT NULL,
  expected_vehicle_version integer NOT NULL CHECK(expected_vehicle_version>0),
  vehicle_version_before integer NOT NULL CHECK(vehicle_version_before>0),
  vehicle_version_after integer NOT NULL CHECK(vehicle_version_after>0),
  photo_receipt_id uuid NOT NULL UNIQUE REFERENCES public.pdc_qc_finalization_photo_evidence_399(photo_receipt_id) ON DELETE RESTRICT,
  salesperson_snapshot jsonb NOT NULL CHECK(jsonb_typeof(salesperson_snapshot)='object'),
  completed_items_snapshot jsonb NOT NULL CHECK(jsonb_typeof(completed_items_snapshot)='array'),
  idempotency_key uuid NOT NULL,
  request_sha256 text NOT NULL CHECK(request_sha256~'^[a-f0-9]{64}$'),
  request_payload jsonb NOT NULL CHECK(jsonb_typeof(request_payload)='object'),
  response jsonb NOT NULL CHECK(jsonb_typeof(response)='object'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(actor_id,idempotency_key)
);
ALTER TABLE public.pdc_qc_finalization_receipts_399 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_qc_finalization_receipts_399 FROM public,anon,authenticated,service_role;

CREATE TABLE public.pdc_qc_salesperson_update_outbox_399(
  notification_id uuid PRIMARY KEY,
  finalization_receipt_id uuid NOT NULL UNIQUE REFERENCES public.pdc_qc_finalization_receipts_399(receipt_id) ON DELETE RESTRICT,
  vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
  recipient_email text NOT NULL CHECK(length(btrim(recipient_email))>3),
  delivery_status text NOT NULL DEFAULT 'pending' CHECK(delivery_status='pending'),
  sent_at timestamptz,
  delivered_at timestamptz,
  payload jsonb NOT NULL CHECK(jsonb_typeof(payload)='object'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK(sent_at IS NULL AND delivered_at IS NULL)
);
ALTER TABLE public.pdc_qc_salesperson_update_outbox_399 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_qc_salesperson_update_outbox_399 FROM public,anon,authenticated,service_role;

CREATE TABLE public.pdc_sublet_provider_update_receipts_399(
  receipt_id uuid PRIMARY KEY,
  booking_id uuid NOT NULL REFERENCES public.pdc_sublet_booking_instances(booking_id) ON DELETE RESTRICT,
  actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  actor_email text NOT NULL,
  provider_id uuid NOT NULL REFERENCES public.sublet_providers(id) ON DELETE RESTRICT,
  expected_booking_version bigint NOT NULL CHECK(expected_booking_version>0),
  request_sha256 text NOT NULL CHECK(request_sha256~'^[a-f0-9]{64}$'),
  response jsonb NOT NULL CHECK(jsonb_typeof(response)='object'),
  idempotency_key uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(actor_id,idempotency_key)
);
ALTER TABLE public.pdc_sublet_provider_update_receipts_399 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_sublet_provider_update_receipts_399 FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.pdc_qc_finalization_append_only_399()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN RAISE EXCEPTION 'PDC_399_APPEND_ONLY_EVIDENCE' USING errcode='55000'; END $$;
REVOKE ALL ON FUNCTION public.pdc_qc_finalization_append_only_399() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_qc_photo_append_only_399 BEFORE UPDATE OR DELETE ON public.pdc_qc_finalization_photo_evidence_399
  FOR EACH ROW EXECUTE FUNCTION public.pdc_qc_finalization_append_only_399();
CREATE TRIGGER pdc_qc_finalization_append_only_399 BEFORE UPDATE OR DELETE ON public.pdc_qc_finalization_receipts_399
  FOR EACH ROW EXECUTE FUNCTION public.pdc_qc_finalization_append_only_399();
CREATE TRIGGER pdc_qc_outbox_append_only_399 BEFORE UPDATE OR DELETE ON public.pdc_qc_salesperson_update_outbox_399
  FOR EACH ROW EXECUTE FUNCTION public.pdc_qc_finalization_append_only_399();
CREATE TRIGGER pdc_sublet_provider_update_append_only_399 BEFORE UPDATE OR DELETE ON public.pdc_sublet_provider_update_receipts_399
  FOR EACH ROW EXECUTE FUNCTION public.pdc_qc_finalization_append_only_399();

CREATE OR REPLACE FUNCTION public.update_pdc_sublet_booking_provider_399(
  p_booking_id uuid, p_expected_version bigint, p_provider_id uuid, p_provider_email text, p_idempotency_key uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions AS $provider$
DECLARE
  v_user uuid:=auth.uid(); v_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); v_before public.pdc_sublet_booking_instances%rowtype; v_after public.pdc_sublet_booking_instances%rowtype; v_provider public.sublet_providers%rowtype; v_existing public.pdc_sublet_provider_update_receipts_399%rowtype; v_request jsonb; v_sha text; v_receipt_id uuid; v_revision bigint; v_response jsonb;
BEGIN
  IF v_user IS NULL OR p_booking_id IS NULL OR p_expected_version IS NULL OR p_expected_version<1 OR p_provider_id IS NULL OR p_idempotency_key IS NULL OR length(btrim(coalesce(p_provider_email,'')))>254 THEN RETURN jsonb_build_object('ok',false,'code','invalid_input'); END IF;
  IF NOT public.pdc_sublet_actor_allowed() THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
  SELECT * INTO v_provider FROM public.sublet_providers WHERE id=p_provider_id AND active;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','provider_not_found'); END IF;
  v_request:=jsonb_build_object('contract','pdc-sublet-provider-update-399','booking_id',p_booking_id,'expected_version',p_expected_version,'provider_id',p_provider_id,'provider_email',lower(btrim(coalesce(p_provider_email,''))),'idempotency_key',p_idempotency_key,'actor_id',v_user);
  v_sha:=encode(extensions.digest(convert_to(v_request::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-399-sublet-provider:'||v_user::text||':'||p_idempotency_key::text,0));
  SELECT * INTO v_existing FROM public.pdc_sublet_provider_update_receipts_399 WHERE actor_id=v_user AND idempotency_key=p_idempotency_key;
  IF FOUND THEN
    IF v_existing.request_sha256<>v_sha THEN RETURN jsonb_build_object('ok',false,'code','idempotency_payload_mismatch'); END IF;
    RETURN jsonb_set(v_existing.response,'{data,replay}','true'::jsonb,false)||jsonb_build_object('replay',true);
  END IF;
  SELECT * INTO v_before FROM public.pdc_sublet_booking_instances WHERE booking_id=p_booking_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','booking_not_found'); END IF;
  IF v_before.status<>'active' THEN RETURN jsonb_build_object('ok',false,'code','booking_not_active'); END IF;
  IF v_before.version<>p_expected_version THEN RETURN jsonb_build_object('ok',false,'code','version_conflict','data',jsonb_build_object('current_version',v_before.version)); END IF;
  PERFORM set_config('pdc.hermes_test_wrapper_vehicle_365',v_before.vehicle_id::text,true);
  UPDATE public.pdc_sublet_booking_instances SET provider_id=v_provider.id,provider_name=v_provider.name,provider_email=lower(btrim(coalesce(p_provider_email,''))),version=version+1,updated_at=clock_timestamp(),updated_by=v_user WHERE booking_id=p_booking_id RETURNING * INTO v_after;
  INSERT INTO public.pdc_sublet_booking_instance_history(booking_id,vehicle_id,actor_id,actor_email,action,before_data,after_data,booking_version) VALUES(v_after.booking_id,v_after.vehicle_id,v_user,v_email,'updated',to_jsonb(v_before),to_jsonb(v_after),v_after.version);
  UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton RETURNING revision INTO v_revision;
  v_receipt_id:=extensions.uuid_generate_v5('39900000-0000-5000-8000-000000000399'::uuid,'sublet-provider:'||v_user::text||':'||p_idempotency_key::text);
  v_response:=jsonb_build_object('ok',true,'code','sublet_provider_updated','data',jsonb_build_object('receipt_id',v_receipt_id,'booking_id',v_after.booking_id,'vehicle_id',v_after.vehicle_id,'provider_id',v_after.provider_id,'provider_name',v_after.provider_name,'provider_email',v_after.provider_email,'version',v_after.version,'revision',v_revision,'replay',false));
  INSERT INTO public.pdc_sublet_provider_update_receipts_399(receipt_id,booking_id,actor_id,actor_email,provider_id,expected_booking_version,request_sha256,response,idempotency_key) VALUES(v_receipt_id,v_after.booking_id,v_user,v_email,v_after.provider_id,p_expected_version,v_sha,v_response,p_idempotency_key);
  RETURN v_response;
EXCEPTION WHEN unique_violation THEN
  SELECT * INTO v_existing FROM public.pdc_sublet_provider_update_receipts_399 WHERE actor_id=v_user AND idempotency_key=p_idempotency_key;
  IF FOUND THEN RETURN jsonb_set(v_existing.response,'{data,replay}','true'::jsonb,false)||jsonb_build_object('replay',true); END IF;
  RETURN jsonb_build_object('ok',false,'code','sublet_provider_update_conflict');
END $provider$;
REVOKE ALL ON FUNCTION public.update_pdc_sublet_booking_provider_399(uuid,bigint,uuid,text,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.update_pdc_sublet_booking_provider_399(uuid,bigint,uuid,text,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.record_pdc_qc_photo_evidence_399(
  p_vehicle_id uuid,
  p_expected_vehicle_version integer,
  p_bucket_id text,
  p_storage_path text,
  p_content_type text,
  p_byte_length integer,
  p_original_byte_length integer,
  p_image_width integer,
  p_image_height integer,
  p_sha256 text,
  p_original_filename text,
  p_idempotency_key uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions SET statement_timeout='60s' AS $photo$
DECLARE
  v_actor uuid:=auth.uid(); v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_vehicle public.vehicles%rowtype; v_existing public.pdc_qc_finalization_photo_evidence_399%rowtype;
  v_request jsonb; v_sha text; v_receipt_id uuid; v_response jsonb; v_object_count integer;
BEGIN
  IF v_actor IS NULL OR p_vehicle_id IS NULL OR p_expected_vehicle_version IS NULL OR p_expected_vehicle_version<1
    OR p_idempotency_key IS NULL OR p_bucket_id<>'pdc-qc-evidence-staging'
    OR p_storage_path!~('^qc-finalization/'||v_actor::text||'/[0-9a-f-]{36}/[^/]{1,180}$')
    OR lower(btrim(coalesce(p_content_type,''))) NOT LIKE 'image/%'
    OR p_byte_length IS NULL OR p_byte_length NOT BETWEEN 1 AND 1048576
    OR p_original_byte_length IS NULL OR p_original_byte_length NOT BETWEEN 1 AND 10485760
    OR p_image_width IS NULL OR p_image_width NOT BETWEEN 1 AND 1600
    OR p_image_height IS NULL OR p_image_height NOT BETWEEN 1 AND 1600
    OR lower(btrim(coalesce(p_sha256,'')))!~'^[a-f0-9]{64}$'
    OR length(btrim(coalesce(p_original_filename,''))) NOT BETWEEN 1 AND 180 THEN
    RETURN jsonb_build_object('ok',false,'code','qc_photo_invalid_input');
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=v_actor AND lower(r.email)=v_email
    AND r.role IN('operator','administrator') AND r.active AND r.account_status='approved' FOR SHARE) THEN
    RETURN jsonb_build_object('ok',false,'code','not_authorized');
  END IF;
  v_request:=jsonb_build_object('contract','pdc-qc-photo-evidence-399','vehicle_id',p_vehicle_id,
    'expected_vehicle_version',p_expected_vehicle_version,'bucket_id',p_bucket_id,'storage_path',p_storage_path,
    'content_type',lower(btrim(p_content_type)),'byte_length',p_byte_length,'original_byte_length',p_original_byte_length,'image_width',p_image_width,'image_height',p_image_height,'sha256',lower(btrim(p_sha256)),
    'original_filename',btrim(p_original_filename),'idempotency_key',p_idempotency_key,'actor_id',v_actor);
  v_sha:=encode(extensions.digest(convert_to(v_request::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-399-photo:'||v_actor::text||':'||p_idempotency_key::text,0));
  SELECT * INTO v_existing FROM public.pdc_qc_finalization_photo_evidence_399 WHERE uploader_id=v_actor AND idempotency_key=p_idempotency_key;
  IF FOUND THEN
    IF v_existing.request_sha256<>v_sha THEN RETURN jsonb_build_object('ok',false,'code','idempotency_payload_mismatch'); END IF;
    RETURN jsonb_set(v_existing.response,'{data,replay}','true'::jsonb,false)||jsonb_build_object('replay',true);
  END IF;
  SELECT * INTO v_vehicle FROM public.vehicles WHERE id=p_vehicle_id FOR SHARE;
  IF NOT FOUND OR v_vehicle.deleted_at IS NOT NULL OR v_vehicle.lifecycle_state<>'active' OR upper(btrim(coalesce(v_vehicle.current_location,'')))<>'QC' THEN
    RETURN jsonb_build_object('ok',false,'code','qc_photo_vehicle_not_in_qc');
  END IF;
  IF v_vehicle.version<>p_expected_vehicle_version THEN RETURN jsonb_build_object('ok',false,'code','vehicle_version_conflict','data',jsonb_build_object('vehicle_id',p_vehicle_id,'vehicle_version',v_vehicle.version)); END IF;
  SELECT count(*) INTO v_object_count FROM storage.objects o
  WHERE o.bucket_id=p_bucket_id AND o.name=p_storage_path AND o.owner_id=v_actor::text;
  IF v_object_count<>1 THEN RETURN jsonb_build_object('ok',false,'code','qc_photo_storage_object_not_owned'); END IF;
  SELECT * INTO v_existing FROM public.pdc_qc_finalization_photo_evidence_399 WHERE vehicle_id=p_vehicle_id;
  IF FOUND THEN
    IF v_existing.sha256=lower(btrim(p_sha256)) AND v_existing.storage_path=p_storage_path THEN
      RETURN jsonb_set(v_existing.response,'{data,replay}','true'::jsonb,false)||jsonb_build_object('replay',true);
    END IF;
    RETURN jsonb_build_object('ok',false,'code','qc_photo_already_recorded','data',jsonb_build_object('photo_receipt_id',v_existing.photo_receipt_id));
  END IF;
  v_receipt_id:=extensions.uuid_generate_v5('39900000-0000-5000-8000-000000000399'::uuid,v_actor::text||':'||p_idempotency_key::text);
  v_response:=jsonb_build_object('ok',true,'code','qc_photo_stored','data',jsonb_build_object('photo_receipt_id',v_receipt_id,
    'vehicle_id',p_vehicle_id,'vehicle_version',v_vehicle.version,'bucket_id',p_bucket_id,'storage_path',p_storage_path,
    'content_type',lower(btrim(p_content_type)),'byte_length',p_byte_length,'original_byte_length',p_original_byte_length,'image_width',p_image_width,'image_height',p_image_height,'sha256',lower(btrim(p_sha256)),
    'original_filename',btrim(p_original_filename),'uploader_id',v_actor,'uploader_email',v_email,'replay',false));
  INSERT INTO public.pdc_qc_finalization_photo_evidence_399(photo_receipt_id,vehicle_id,expected_vehicle_version,uploader_id,uploader_email,bucket_id,storage_path,content_type,byte_length,original_byte_length,image_width,image_height,sha256,original_filename,idempotency_key,request_sha256,response)
  VALUES(v_receipt_id,p_vehicle_id,p_expected_vehicle_version,v_actor,v_email,p_bucket_id,p_storage_path,lower(btrim(p_content_type)),p_byte_length,p_original_byte_length,p_image_width,p_image_height,lower(btrim(p_sha256)),btrim(p_original_filename),p_idempotency_key,v_sha,v_response);
  RETURN v_response;
EXCEPTION WHEN unique_violation THEN
  SELECT * INTO v_existing FROM public.pdc_qc_finalization_photo_evidence_399 WHERE uploader_id=v_actor AND idempotency_key=p_idempotency_key;
  IF FOUND THEN RETURN jsonb_set(v_existing.response,'{data,replay}','true'::jsonb,false)||jsonb_build_object('replay',true); END IF;
  RETURN jsonb_build_object('ok',false,'code','qc_photo_already_recorded');
END $photo$;
REVOKE ALL ON FUNCTION public.record_pdc_qc_photo_evidence_399(uuid,integer,text,text,text,integer,integer,integer,integer,text,text,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.record_pdc_qc_photo_evidence_399(uuid,integer,text,text,text,integer,integer,integer,integer,text,text,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.finalize_pdc_qc_to_rft_399(
  p_vehicle_id uuid,
  p_expected_vehicle_version integer,
  p_photo_receipt_id uuid,
  p_idempotency_key uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions SET statement_timeout='120s' AS $finalize$
DECLARE
  v_actor uuid:=auth.uid(); v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_before public.vehicles%rowtype; v_signed public.vehicles%rowtype; v_after public.vehicles%rowtype;
  v_photo public.pdc_qc_finalization_photo_evidence_399%rowtype; v_existing public.pdc_qc_finalization_receipts_399%rowtype;
  v_salesperson public.salespeople%rowtype; v_lines_all jsonb; v_lines jsonb; v_sp jsonb; v_payload jsonb; v_request jsonb; v_request_sha text;
  v_receipt_id uuid; v_notification_id uuid; v_response jsonb; v_notifications_before bigint; v_notifications_after bigint; v_revision_before bigint; v_revision_after bigint;
BEGIN
  IF v_actor IS NULL OR p_vehicle_id IS NULL OR p_expected_vehicle_version IS NULL OR p_expected_vehicle_version<1 OR p_photo_receipt_id IS NULL OR p_idempotency_key IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','qc_finalization_invalid_input');
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=v_actor AND lower(r.email)=v_email AND r.active AND r.account_status='approved' AND r.role IN('operator','administrator') FOR SHARE) THEN
    RETURN jsonb_build_object('ok',false,'code','not_authorized');
  END IF;
  v_request:=jsonb_build_object('contract','pdc-qc-finalization-to-rft-399','vehicle_id',p_vehicle_id,'expected_vehicle_version',p_expected_vehicle_version,'photo_receipt_id',p_photo_receipt_id,'idempotency_key',p_idempotency_key,'actor_id',v_actor);
  v_request_sha:=encode(extensions.digest(convert_to(v_request::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-399-finalize-actor:'||v_actor::text||':'||p_idempotency_key::text,0));
  SELECT * INTO v_existing FROM public.pdc_qc_finalization_receipts_399 WHERE actor_id=v_actor AND idempotency_key=p_idempotency_key;
  IF FOUND THEN
    IF v_existing.request_sha256<>v_request_sha THEN RETURN jsonb_build_object('ok',false,'code','idempotency_payload_mismatch'); END IF;
    RETURN jsonb_set(v_existing.response,'{data,replay}','true'::jsonb,false)||jsonb_build_object('replay',true);
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-399-finalize-vehicle:'||p_vehicle_id::text,0));
  SELECT * INTO v_before FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
  IF NOT FOUND OR v_before.deleted_at IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'code','vehicle_not_found'); END IF;
  SELECT * INTO v_existing FROM public.pdc_qc_finalization_receipts_399 WHERE vehicle_id=p_vehicle_id;
  IF FOUND THEN RETURN jsonb_build_object('ok',false,'code','already_finalized','data',jsonb_build_object('receipt_id',v_existing.receipt_id,'vehicle_id',p_vehicle_id)); END IF;
  IF v_before.version<>p_expected_vehicle_version THEN RETURN jsonb_build_object('ok',false,'code','vehicle_version_conflict','data',jsonb_build_object('vehicle_id',p_vehicle_id,'vehicle_version',v_before.version)); END IF;
  IF v_before.lifecycle_state<>'active' OR upper(btrim(coalesce(v_before.current_location,'')))<>'QC' THEN RETURN jsonb_build_object('ok',false,'code','qc_vehicle_not_in_qc'); END IF;
  SELECT * INTO v_photo FROM public.pdc_qc_finalization_photo_evidence_399 WHERE photo_receipt_id=p_photo_receipt_id AND vehicle_id=p_vehicle_id FOR SHARE;
  IF NOT FOUND OR v_photo.bucket_id<>'pdc-qc-evidence-staging' OR v_photo.content_type NOT LIKE 'image/%' OR v_photo.byte_length NOT BETWEEN 1 AND 1048576 THEN RETURN jsonb_build_object('ok',false,'code','qc_photo_receipt_required'); END IF;
  SELECT * INTO v_salesperson FROM public.salespeople s WHERE s.id=v_before.salesperson_id AND s.active AND length(btrim(coalesce(s.email,'')))>3 AND position('@' IN s.email)>1;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','salesperson_email_required'); END IF;
  v_sp:=jsonb_build_object('salesperson_id',v_salesperson.id,'salesperson_code',upper(btrim(coalesce(v_salesperson.code,''))),'salesperson_name',btrim(coalesce(v_salesperson.name,'')),'salesperson_email',lower(btrim(v_salesperson.email)));
  v_lines_all:=public.pdc_qc_operation_lines_379(p_vehicle_id);
  v_lines:=coalesce((SELECT jsonb_agg(line ORDER BY line->>'stage_code',line->>'operation_no',line->>'line_identity') FROM jsonb_array_elements(v_lines_all) line WHERE coalesce((line->>'active')::boolean,false)),'[]'::jsonb);
  IF jsonb_array_length(v_lines)=0 OR EXISTS(SELECT 1 FROM jsonb_array_elements(v_lines) line WHERE NOT coalesce((line->>'completed')::boolean,false) OR (line->>'estimated_hours') IS NULL) THEN RETURN jsonb_build_object('ok',false,'code','qc_operation_lines_incomplete'); END IF;
  LOCK TABLE public.vehicle_notifications IN SHARE MODE;
  SELECT count(*) INTO v_notifications_before FROM public.vehicle_notifications;
  SELECT revision INTO v_revision_before FROM public.pdc_email_vehicle_revision WHERE singleton FOR UPDATE;
  IF NOT public.pdc_monitor_staging_guard() OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active) OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL) THEN RETURN jsonb_build_object('ok',false,'code','staging_notification_dispatch_not_contained'); END IF;
  v_receipt_id:=extensions.uuid_generate_v5('39900000-0000-5000-8000-000000000399'::uuid,'finalization:'||v_actor::text||':'||p_idempotency_key::text);
  v_notification_id:=extensions.uuid_generate_v5('39900000-0000-5000-8000-000000000399'::uuid,'salesperson-outbox:'||v_receipt_id::text);
  v_payload:=jsonb_build_object('contract','pdc-qc-salesperson-update-399','environment','staging','synthetic_only',left(upper(coalesce(v_before.source_batch_id,'')),11)='HERMES-TEST','delivery_enabled',false,'delivery_status','pending','notification_id',v_notification_id,
    'recipient',v_sp,'vehicle',jsonb_build_object('vehicle_id',v_before.id,'stock_number',v_before.stock_number,'job_card_number',v_before.job_card_number,'model',v_before.model,'customer_name',v_before.customer_name),
    'photo',jsonb_build_object('photo_receipt_id',v_photo.photo_receipt_id,'bucket_id',v_photo.bucket_id,'storage_path',v_photo.storage_path,'content_type',v_photo.content_type,'byte_length',v_photo.byte_length,'original_byte_length',v_photo.original_byte_length,'image_width',v_photo.image_width,'image_height',v_photo.image_height,'sha256',v_photo.sha256,'original_filename',v_photo.original_filename,'uploader_id',v_photo.uploader_id,'uploader_email',v_photo.uploader_email),
    'completed_items',v_lines,'qc_location','QC','rft_location','RFT','sent_at',null,'delivered_at',null);
  PERFORM set_config('pdc.hermes_test_wrapper_vehicle_365',p_vehicle_id::text,true);
  -- Preserve the existing QC-then-RFT invariant as two audited row transitions
  -- inside this one atomic transaction.
  UPDATE public.vehicles SET qc_completed_at=coalesce(qc_completed_at,clock_timestamp()),qc_completed_by=v_actor,version=version+1,updated_by=v_actor,updated_at=clock_timestamp() WHERE id=p_vehicle_id RETURNING * INTO v_signed;
  PERFORM public.audit_pdc_event('update','vehicles',p_vehicle_id,p_vehicle_id,to_jsonb(v_before),to_jsonb(v_signed),jsonb_build_object('action','finalize_pdc_qc_to_rft_399_qc_signoff','photo_receipt_id',v_photo.photo_receipt_id,'notification_enqueued',false));
  UPDATE public.vehicles SET lifecycle_state='rft',current_location='RFT',date_to_rft=coalesce(date_to_rft,(clock_timestamp() at time zone 'Australia/Perth')::date),rft_transferred_at=coalesce(rft_transferred_at,clock_timestamp()),version=version+1,updated_by=v_actor,updated_at=clock_timestamp() WHERE id=p_vehicle_id RETURNING * INTO v_after;
  INSERT INTO public.vehicle_movements(vehicle_id,from_location,to_location,from_pmb_stage,to_pmb_stage,from_pmb_bay_stage,to_pmb_bay_stage,from_pmb_bay_number,to_pmb_bay_number,reason,moved_by)
    VALUES(p_vehicle_id,'QC','RFT',v_before.pmb_stage,v_before.pmb_stage,v_before.pmb_bay_stage,v_before.pmb_bay_stage,v_before.pmb_bay_number,v_before.pmb_bay_number,'QC final sign-off with completion photo; salesperson update held in staging outbox',v_actor);
  v_response:=jsonb_build_object('ok',true,'code','qc_signed_off_moved_to_rft','replay',false,'receipt_id',v_receipt_id,'vehicle_id',p_vehicle_id,'vehicle_version_before',v_before.version,'vehicle_version_after',v_after.version,'photo_receipt_id',v_photo.photo_receipt_id,'salesperson',v_sp,'completed_items',v_lines,'outbox',jsonb_build_object('notification_id',v_notification_id,'recipient_email',v_salesperson.email,'delivery_status','pending','sent_at',null,'delivered_at',null),'payload',v_payload,'notification_delta',0);
  INSERT INTO public.pdc_qc_finalization_receipts_399(receipt_id,vehicle_id,actor_id,actor_email,expected_vehicle_version,vehicle_version_before,vehicle_version_after,photo_receipt_id,salesperson_snapshot,completed_items_snapshot,idempotency_key,request_sha256,request_payload,response)
    VALUES(v_receipt_id,p_vehicle_id,v_actor,v_email,p_expected_vehicle_version,v_before.version,v_after.version,v_photo.photo_receipt_id,v_sp,v_lines,p_idempotency_key,v_request_sha,v_request,v_response);
  INSERT INTO public.pdc_qc_salesperson_update_outbox_399(notification_id,finalization_receipt_id,vehicle_id,recipient_email,payload)
    VALUES(v_notification_id,v_receipt_id,p_vehicle_id,lower(btrim(v_salesperson.email)),v_payload);
  PERFORM public.audit_pdc_event('rft','vehicles',p_vehicle_id,p_vehicle_id,to_jsonb(v_signed),to_jsonb(v_after),jsonb_build_object('action','finalize_pdc_qc_to_rft_399','receipt_id',v_receipt_id,'photo_receipt_id',v_photo.photo_receipt_id,'salesperson_email',lower(btrim(v_salesperson.email)),'completed_item_count',jsonb_array_length(v_lines),'notification_enqueued',true,'notification_dispatched',false));
  SELECT revision INTO v_revision_after FROM public.pdc_email_vehicle_revision WHERE singleton;
  SELECT count(*) INTO v_notifications_after FROM public.vehicle_notifications;
  IF v_after.current_location<>'RFT' OR v_after.version<>v_before.version+2 OR v_notifications_after<>v_notifications_before OR v_revision_after-v_revision_before<>2 OR NOT EXISTS(SELECT 1 FROM public.pdc_qc_salesperson_update_outbox_399 WHERE notification_id=v_notification_id AND sent_at IS NULL AND delivered_at IS NULL) THEN
    RAISE EXCEPTION 'PDC_399_FINALIZATION_POSTCONDITION' USING errcode='55000';
  END IF;
  RETURN v_response;
END $finalize$;
REVOKE ALL ON FUNCTION public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.read_pdc_qc_finalization_receipt_399(p_receipt_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $read$
DECLARE v_actor uuid:=auth.uid(); v_email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); v_r public.pdc_qc_finalization_receipts_399%rowtype; v_o public.pdc_qc_salesperson_update_outbox_399%rowtype;
BEGIN
  IF v_actor IS NULL OR NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=v_actor AND lower(r.email)=v_email AND r.active AND r.account_status='approved' AND r.role IN('operator','administrator')) THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
  SELECT * INTO v_r FROM public.pdc_qc_finalization_receipts_399 WHERE receipt_id=p_receipt_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','receipt_not_found'); END IF;
  SELECT * INTO v_o FROM public.pdc_qc_salesperson_update_outbox_399 WHERE finalization_receipt_id=v_r.receipt_id;
  RETURN jsonb_build_object('ok',true,'code','qc_finalization_receipt','data',jsonb_build_object('receipt_id',v_r.receipt_id,'vehicle_id',v_r.vehicle_id,'actor_id',v_r.actor_id,'actor_email',v_r.actor_email,'vehicle_version_before',v_r.vehicle_version_before,'vehicle_version_after',v_r.vehicle_version_after,'photo_receipt_id',v_r.photo_receipt_id,'salesperson',v_r.salesperson_snapshot,'completed_items',v_r.completed_items_snapshot,'response',v_r.response,'outbox',to_jsonb(v_o)));
END $read$;
REVOKE ALL ON FUNCTION public.read_pdc_qc_finalization_receipt_399(uuid) FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.read_pdc_qc_finalization_receipt_399(uuid) TO authenticated;

ALTER FUNCTION public.get_pdc_email_vehicle_location_snapshot() RENAME TO get_pdc_email_vehicle_location_snapshot_pre_399;
REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_location_snapshot_pre_399() FROM public,anon,authenticated,service_role;
CREATE FUNCTION public.get_pdc_email_vehicle_location_snapshot()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $snapshot$
DECLARE v_result jsonb; v_rows jsonb;
BEGIN
  v_result:=public.get_pdc_email_vehicle_location_snapshot_pre_399();
  IF NOT coalesce((v_result->>'ok')::boolean,false) THEN RETURN v_result; END IF;
  SELECT coalesce(jsonb_agg(vehicle||jsonb_build_object('qc_finalization',coalesce((SELECT jsonb_build_object('receipt_id',r.receipt_id,'photo_receipt_id',r.photo_receipt_id,'actor_id',r.actor_id,'actor_email',r.actor_email,'signed_off_at',r.created_at,'vehicle_version_before',r.vehicle_version_before,'vehicle_version_after',r.vehicle_version_after,'salesperson',r.salesperson_snapshot,'completed_items',r.completed_items_snapshot,'outbox_status',o.delivery_status,'outbox_notification_id',o.notification_id,'outbox_sent_at',o.sent_at,'outbox_delivered_at',o.delivered_at) FROM public.pdc_qc_finalization_receipts_399 r LEFT JOIN public.pdc_qc_salesperson_update_outbox_399 o ON o.finalization_receipt_id=r.receipt_id WHERE r.vehicle_id=(vehicle->>'id')::uuid ORDER BY r.created_at DESC LIMIT 1),'null'::jsonb)) ORDER BY ordinal),'[]'::jsonb) INTO v_rows
  FROM jsonb_array_elements(coalesce(v_result#>'{data,vehicles}','[]'::jsonb)) WITH ORDINALITY rows(vehicle,ordinal);
  RETURN jsonb_set(v_result,'{data,vehicles}',v_rows,true);
END $snapshot$;
REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() TO authenticated,service_role;

DO $post$
BEGIN
  IF has_function_privilege('public','public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid)','EXECUTE')
    OR has_function_privilege('anon','public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid)','EXECUTE')
    OR has_function_privilege('service_role','public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid)','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.finalize_pdc_qc_to_rft_399(uuid,integer,uuid,uuid)','EXECUTE')
    OR has_function_privilege('public','public.update_pdc_sublet_booking_provider_399(uuid,bigint,uuid,text,uuid)','EXECUTE')
    OR has_function_privilege('anon','public.update_pdc_sublet_booking_provider_399(uuid,bigint,uuid,text,uuid)','EXECUTE')
    OR has_function_privilege('service_role','public.update_pdc_sublet_booking_provider_399(uuid,bigint,uuid,text,uuid)','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.update_pdc_sublet_booking_provider_399(uuid,bigint,uuid,text,uuid)','EXECUTE')
    OR has_function_privilege('public','public.record_pdc_qc_photo_evidence_399(uuid,integer,text,text,text,integer,integer,integer,integer,text,text,uuid)','EXECUTE')
    OR has_function_privilege('anon','public.record_pdc_qc_photo_evidence_399(uuid,integer,text,text,text,integer,integer,integer,integer,text,text,uuid)','EXECUTE')
    OR has_function_privilege('service_role','public.record_pdc_qc_photo_evidence_399(uuid,integer,text,text,text,integer,integer,integer,integer,text,text,uuid)','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.record_pdc_qc_photo_evidence_399(uuid,integer,text,text,text,integer,integer,integer,integer,text,text,uuid)','EXECUTE')
    OR has_function_privilege('public','public.get_pdc_email_vehicle_location_snapshot()','EXECUTE')
    OR has_function_privilege('anon','public.get_pdc_email_vehicle_location_snapshot()','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.get_pdc_email_vehicle_location_snapshot()','EXECUTE')
    OR NOT has_function_privilege('service_role','public.get_pdc_email_vehicle_location_snapshot()','EXECUTE')
    OR (SELECT count(*) FROM public.vehicle_notifications)<>1 THEN
    RAISE EXCEPTION 'PDC_399_ACL_OR_NOTIFICATION_POSTCONDITION' USING errcode='55000';
  END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826140000','399_qc_finalization_photo_rft_salesperson_outbox',ARRAY[
  'Private staging-only QC photo evidence with authenticated uploader, image MIME, <=10MB, SHA-256, byte length and storage path',
  'Atomic receipt-backed QC named sign-off, exact completed active operation snapshot and QC-to-RFT movement',
  'Active canonical salesperson email is required and exact Stock/JC/model/photo/completed-item payload is immutable',
  'Staging salesperson update remains pending in a no-dispatch outbox with zero delivered notification delta',
  'UUID idempotency, vehicle/version conflicts, append-only receipt/audit/readback and final snapshot projection',
  'No protected vehicle data is mutated by this migration'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
