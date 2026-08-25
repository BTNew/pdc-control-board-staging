-- STAGING ONLY 396: Craig owner-supplied PDF Job Card intake.
--
-- This is deliberately additive to the provider-observed email contracts. It
-- accepts one exact owner instruction for Stock 13080553 / JC J139125519,
-- binds the supplied document hash/byte metadata, resolves one current
-- Navision record, and writes canonical Board operation evidence. It never
-- reads or fabricates an email intake, provider observation, mailbox, sender
-- authentication, booking, movement, completion, or notification.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-396-owner-supplied-document-jobcard',0));

DO $pre$
DECLARE v_head text;
BEGIN
  SELECT max(version) INTO v_head FROM supabase_migrations.schema_migrations
   WHERE version ~ '^[0-9]{14}$';
  IF current_user<>'postgres' OR session_user<>'postgres'
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel
        WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR NOT public.pdc_monitor_staging_guard()
    OR v_head IS DISTINCT FROM '20260826110000'
    OR (SELECT count(*) FROM supabase_migrations.schema_migrations
        WHERE version='20260826110000' AND name='395_restore_qc_operation_projection')<>1
    OR to_regclass('public.navision_backend_records') IS NULL
    OR to_regclass('public.navision_board_activations') IS NULL
    OR to_regclass('public.vehicles') IS NULL
    OR to_regclass('public.pdc_authenticated_email_import_receipts') IS NULL
    OR to_regclass('public.pdc_authenticated_email_operation_lines') IS NULL
    OR to_regclass('public.vehicle_work_items') IS NULL
    OR to_regclass('public.audit_events') IS NULL
    OR to_regclass('public.vehicle_notifications') IS NULL THEN
    RAISE EXCEPTION 'PDC_396_STAGING_HEAD_OR_DEPENDENCY_MISMATCH' USING errcode='55000';
  END IF;
END $pre$;

ALTER TABLE public.pdc_authenticated_email_operation_lines
  DROP CONSTRAINT IF EXISTS pdc_authenticated_email_operation_lines_source_contract_check,
  ADD CONSTRAINT pdc_authenticated_email_operation_lines_source_contract_check
    CHECK(source_contract IS NULL OR source_contract IN(
      'pdc_staging_workbook_reset_136','pmb-email-communications-v1',
      'pmb-non-navision-jobcard-161','pdc-owner-supplied-document-v1'));

CREATE TABLE public.pdc_owner_supplied_document_receipts_396(
  receipt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contract_version text NOT NULL CHECK(contract_version='pdc-owner-supplied-document-v1'),
  provenance text NOT NULL CHECK(provenance='owner_supplied_document'),
  owner_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  owner_email text NOT NULL CHECK(lower(owner_email)='pmbcontroller@gmail.com'),
  business_owner_email text NOT NULL DEFAULT 'craig.watson@broometoyota.com.au'
    CHECK(lower(business_owner_email)='craig.watson@broometoyota.com.au'),
  task_reference text NOT NULL CHECK(task_reference='t_3ff7139c'),
  owner_instruction text NOT NULL CHECK(owner_instruction='Import owner-supplied PDF Stock 13080553 / JC J139125519 into the Email Monitor/Board flow.'),
  idempotency_key text NOT NULL UNIQUE CHECK(idempotency_key~'^pdc-owner-document-[A-Za-z0-9_-]{16,160}$'),
  document_sha256 text NOT NULL UNIQUE CHECK(document_sha256~'^[a-f0-9]{64}$'),
  document_byte_length bigint NOT NULL CHECK(document_byte_length BETWEEN 1 AND 52428800),
  document_content_type text NOT NULL CHECK(document_content_type='application/pdf'),
  document_filename text NOT NULL CHECK(document_filename~*'^[^/\\[:cntrl:]]+[.]pdf$'),
  document_metadata jsonb NOT NULL CHECK(jsonb_typeof(document_metadata)='object'),
  stock_number text NOT NULL CHECK(stock_number='13080553'),
  job_card_number text NOT NULL CHECK(job_card_number='J139125519'),
  navision_backend_record_id uuid NOT NULL REFERENCES public.navision_backend_records(id) ON DELETE RESTRICT,
  canonical_import_receipt_id uuid NOT NULL UNIQUE REFERENCES public.pdc_authenticated_email_import_receipts(receipt_id) ON DELETE RESTRICT,
  vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
  vehicle_created boolean NOT NULL,
  vehicle_version integer NOT NULL CHECK(vehicle_version>=1),
  operation_count integer NOT NULL CHECK(operation_count BETWEEN 1 AND 50),
  explicit_hours_count integer NOT NULL CHECK(explicit_hours_count BETWEEN 0 AND 50),
  unknown_hours_count integer NOT NULL CHECK(unknown_hours_count BETWEEN 0 AND 50),
  operation_lines_sha256 text NOT NULL CHECK(operation_lines_sha256~'^[a-f0-9]{64}$'),
  request_sha256 text NOT NULL UNIQUE CHECK(request_sha256~'^[a-f0-9]{64}$'),
  response jsonb NOT NULL CHECK(jsonb_typeof(response)='object'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE public.pdc_owner_supplied_document_operation_receipts_396(
  operation_receipt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  receipt_id uuid NOT NULL REFERENCES public.pdc_owner_supplied_document_receipts_396(receipt_id) ON DELETE RESTRICT,
  operation_line_id uuid NOT NULL UNIQUE REFERENCES public.pdc_authenticated_email_operation_lines(operation_line_id) ON DELETE RESTRICT,
  operation_no text NOT NULL CHECK(operation_no~'^OP([1-9]|[1-4][0-9]|50)$'),
  source_row_no integer NOT NULL CHECK(source_row_no BETWEEN 1 AND 50),
  description text NOT NULL CHECK(length(btrim(description)) BETWEEN 1 AND 240 AND description=btrim(description)),
  estimated_hours numeric CHECK(estimated_hours IS NULL OR (estimated_hours>=0 AND estimated_hours<=999.99 AND estimated_hours=round(estimated_hours,2))),
  estimated_hours_source text NOT NULL CHECK(estimated_hours_source IN('owner_supplied_document','owner_supplied_document_unknown')),
  work_key text NOT NULL,
  operation_fingerprint text NOT NULL CHECK(operation_fingerprint~'^[a-f0-9]{64}$'),
  source_locator jsonb NOT NULL CHECK(jsonb_typeof(source_locator)='object'),
  work_item_id uuid,
  work_item_created boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(receipt_id,source_row_no),
  UNIQUE(receipt_id,operation_no)
);

CREATE TABLE public.pdc_owner_supplied_document_review_items_396(
  review_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  receipt_id uuid NOT NULL REFERENCES public.pdc_owner_supplied_document_receipts_396(receipt_id) ON DELETE RESTRICT,
  operation_line_id uuid NOT NULL UNIQUE REFERENCES public.pdc_authenticated_email_operation_lines(operation_line_id) ON DELETE RESTRICT,
  review_kind text NOT NULL CHECK(review_kind='unknown_hours'),
  status text NOT NULL DEFAULT 'pending' CHECK(status IN('pending','resolved','dismissed')),
  reason text NOT NULL CHECK(reason='owner-supplied document did not state hours'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE public.pdc_owner_supplied_document_undo_receipts_396(
  undo_receipt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  receipt_id uuid NOT NULL UNIQUE REFERENCES public.pdc_owner_supplied_document_receipts_396(receipt_id) ON DELETE RESTRICT,
  actor_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  actor_email text NOT NULL,
  undo_idempotency_key text NOT NULL UNIQUE CHECK(undo_idempotency_key~'^pdc-owner-undo-[A-Za-z0-9_-]{16,160}$'),
  request_sha256 text NOT NULL UNIQUE CHECK(request_sha256~'^[a-f0-9]{64}$'),
  reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 10 AND 500 AND reason=btrim(reason)),
  response jsonb NOT NULL CHECK(jsonb_typeof(response)='object'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

ALTER TABLE public.pdc_owner_supplied_document_receipts_396 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_owner_supplied_document_operation_receipts_396 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_owner_supplied_document_review_items_396 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_owner_supplied_document_undo_receipts_396 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_owner_supplied_document_receipts_396,
  public.pdc_owner_supplied_document_operation_receipts_396,
  public.pdc_owner_supplied_document_review_items_396,
  public.pdc_owner_supplied_document_undo_receipts_396
  FROM public,anon,authenticated,service_role;

CREATE FUNCTION public.pdc_owner_supplied_document_immutable_396()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public AS $immutable$
BEGIN
  IF TG_OP IN('DELETE','UPDATE')
     AND current_setting('pdc.owner_supplied_document_undo_396',true)='approved' THEN
    RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
  END IF;
  RAISE EXCEPTION 'PDC_396_OWNER_DOCUMENT_LEDGER_IMMUTABLE' USING errcode='55000';
END $immutable$;
REVOKE ALL ON FUNCTION public.pdc_owner_supplied_document_immutable_396() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_owner_document_receipts_immutable_396
  BEFORE UPDATE OR DELETE ON public.pdc_owner_supplied_document_receipts_396
  FOR EACH ROW EXECUTE FUNCTION public.pdc_owner_supplied_document_immutable_396();
CREATE TRIGGER pdc_owner_document_operation_receipts_immutable_396
  BEFORE UPDATE OR DELETE ON public.pdc_owner_supplied_document_operation_receipts_396
  FOR EACH ROW EXECUTE FUNCTION public.pdc_owner_supplied_document_immutable_396();
CREATE TRIGGER pdc_owner_document_review_items_immutable_396
  BEFORE UPDATE OR DELETE ON public.pdc_owner_supplied_document_review_items_396
  FOR EACH ROW EXECUTE FUNCTION public.pdc_owner_supplied_document_immutable_396();
CREATE TRIGGER pdc_owner_document_undo_receipts_immutable_396
  BEFORE UPDATE OR DELETE ON public.pdc_owner_supplied_document_undo_receipts_396
  FOR EACH ROW EXECUTE FUNCTION public.pdc_owner_supplied_document_immutable_396();

CREATE FUNCTION public.pdc_owner_supplied_document_operation_immutable_396()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public AS $immutable$
BEGIN
  IF TG_OP IN('DELETE','UPDATE')
     AND OLD.source_contract='pdc-owner-supplied-document-v1'
     AND current_setting('pdc.owner_supplied_document_undo_396',true)='approved' THEN
    RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
  END IF;
  RAISE EXCEPTION 'PDC_396_OWNER_OPERATION_IMMUTABLE' USING errcode='55000';
END $immutable$;
REVOKE ALL ON FUNCTION public.pdc_owner_supplied_document_operation_immutable_396() FROM public,anon,authenticated,service_role;
CREATE TRIGGER pdc_owner_document_operation_lines_immutable_396
  BEFORE UPDATE OR DELETE ON public.pdc_authenticated_email_operation_lines
  FOR EACH ROW WHEN(OLD.source_contract='pdc-owner-supplied-document-v1')
  EXECUTE FUNCTION public.pdc_owner_supplied_document_operation_immutable_396();

CREATE FUNCTION public.read_pdc_owner_supplied_document_receipt_396(p_receipt_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,extensions AS $read$
DECLARE
  v_actor uuid:=auth.uid(); v_r public.pdc_owner_supplied_document_receipts_396%rowtype;
  v_ops jsonb; v_digest_ops jsonb; v_reviews jsonb; v_undo jsonb; v_response jsonb;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() OR v_actor IS NULL OR p_receipt_id IS NULL THEN
    RETURN public.navision_backend_response(false,'unauthorized');
  END IF;
  SELECT * INTO v_r FROM public.pdc_owner_supplied_document_receipts_396
   WHERE receipt_id=p_receipt_id AND owner_id=v_actor;
  IF NOT FOUND THEN RETURN public.navision_backend_response(false,'owner_document_receipt_not_found'); END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'operation_line_id',o.operation_line_id,'operation_no',o.operation_no,
      'source_row_no',o.source_row_no,'description',o.description,
      'estimated_hours',o.estimated_hours,'estimated_hours_source',o.estimated_hours_source,
      'work_key',o.work_key,'operation_fingerprint',o.operation_fingerprint,
      'source_locator',o.source_locator,'work_item_id',o.work_item_id,
      'work_item_created',o.work_item_created
    ) ORDER BY o.source_row_no),'[]'::jsonb) INTO v_ops
   FROM public.pdc_owner_supplied_document_operation_receipts_396 o
   WHERE o.receipt_id=v_r.receipt_id;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'review_id',x.review_id,'operation_line_id',x.operation_line_id,
      'review_kind',x.review_kind,'status',x.status,'reason',x.reason
    ) ORDER BY x.review_id),'[]'::jsonb) INTO v_reviews
   FROM public.pdc_owner_supplied_document_review_items_396 x
   WHERE x.receipt_id=v_r.receipt_id;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'description',o.description,'hours',o.estimated_hours,'operation_no',o.operation_no
    ) ORDER BY o.source_row_no),'[]'::jsonb) INTO v_digest_ops
   FROM public.pdc_owner_supplied_document_operation_receipts_396 o
   WHERE o.receipt_id=v_r.receipt_id;
  SELECT to_jsonb(u) INTO v_undo FROM public.pdc_owner_supplied_document_undo_receipts_396 u
   WHERE u.receipt_id=v_r.receipt_id;
  IF v_undo IS NULL AND (jsonb_array_length(v_ops)<>v_r.operation_count
     OR (SELECT count(*) FROM public.pdc_owner_supplied_document_review_items_396 x WHERE x.receipt_id=v_r.receipt_id)<>v_r.unknown_hours_count
     OR encode(extensions.digest(convert_to(v_digest_ops::text,'UTF8'),'sha256'),'hex')<>v_r.operation_lines_sha256) THEN
    RETURN public.navision_backend_response(false,'owner_document_receipt_drift');
  END IF;
  v_response:=jsonb_build_object(
    'receipt_id',v_r.receipt_id,'contract_version',v_r.contract_version,
    'provenance',v_r.provenance,'actor_email',v_r.owner_email,
    'business_owner_email',v_r.business_owner_email,
    'task_reference',v_r.task_reference,'owner_instruction',v_r.owner_instruction,
    'idempotency_key',v_r.idempotency_key,
    'document_sha256',v_r.document_sha256,'document_byte_length',v_r.document_byte_length,
    'document_content_type',v_r.document_content_type,'document_filename',v_r.document_filename,
    'document_metadata',v_r.document_metadata,'stock_number',v_r.stock_number,
    'job_card_number',v_r.job_card_number,'navision_backend_record_id',v_r.navision_backend_record_id,
    'canonical_import_receipt_id',v_r.canonical_import_receipt_id,'vehicle_id',v_r.vehicle_id,
    'vehicle_created',v_r.vehicle_created,'operation_count',v_r.operation_count,
    'explicit_hours_count',v_r.explicit_hours_count,'unknown_hours_count',v_r.unknown_hours_count,
    'operation_lines_sha256',v_r.operation_lines_sha256,'request_sha256',v_r.request_sha256,
    'operations',v_ops,'review_items',v_reviews,'undo',v_undo,
    'booking_created',false,'physical_completion_created',false,'notification_delta',0
  );
  RETURN public.navision_backend_response(true,CASE WHEN v_undo IS NULL THEN 'owner_document_receipt' ELSE 'owner_document_receipt_undone' END,v_response);
END $read$;
REVOKE ALL ON FUNCTION public.read_pdc_owner_supplied_document_receipt_396(uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_pdc_owner_supplied_document_receipt_396(uuid) TO authenticated;

CREATE FUNCTION public.pdc_owner_document_numeric_396(p_value jsonb)
RETURNS numeric LANGUAGE plpgsql IMMUTABLE STRICT
SET search_path=pg_catalog AS $numeric$
BEGIN
  IF jsonb_typeof(p_value)<>'number' THEN RETURN NULL; END IF;
  RETURN (p_value#>>'{}')::numeric;
EXCEPTION WHEN others THEN RETURN NULL;
END $numeric$;
REVOKE ALL ON FUNCTION public.pdc_owner_document_numeric_396(jsonb) FROM public,anon,authenticated,service_role;

CREATE FUNCTION public.process_pdc_owner_supplied_document_jobcard_396(
  p_idempotency_key text,
  p_task_reference text,
  p_owner_instruction text,
  p_document jsonb,
  p_identity jsonb,
  p_operations jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions SET statement_timeout='180s' AS $process$
DECLARE
  v_actor uuid:=auth.uid(); v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_key text:=btrim(coalesce(p_idempotency_key,'')); v_doc jsonb:=coalesce(p_document,'null'::jsonb);
  v_identity jsonb:=coalesce(p_identity,'null'::jsonb); v_ops jsonb:=coalesce(p_operations,'null'::jsonb);
  v_stock text; v_job text; v_sha text; v_filename text; v_content_type text; v_source_label text;
  v_bytes bigint; v_request text; v_server_ops text; v_receipt public.pdc_owner_supplied_document_receipts_396%rowtype;
  v_backend public.navision_backend_records%rowtype; v_vehicle public.vehicles%rowtype; v_vehicle_id uuid;
  v_activation public.navision_board_activations%rowtype; v_canonical public.pdc_authenticated_email_import_receipts%rowtype;
  v_item jsonb; v_op jsonb; v_line_id uuid; v_work_id uuid; v_work_key text; v_description text;
  v_hours numeric; v_fingerprint text; v_source_uid text; v_required jsonb:='[]'::jsonb;
  v_before_work public.vehicle_work_items%rowtype; v_created_work boolean; v_review_count integer:=0;
  v_explicit_count integer:=0; v_notifications_before bigint; v_notifications_after bigint;
  v_bookings_before bigint; v_bookings_after bigint; v_movements_before bigint; v_movements_after bigint;
  v_vehicle_created boolean:=false; v_response jsonb; v_now timestamptz:=clock_timestamp();
BEGIN
  IF NOT public.pdc_monitor_staging_guard()
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RETURN public.navision_backend_response(false,'wrong_environment');
  END IF;
  IF v_actor IS NULL OR v_email<>'pmbcontroller@gmail.com' THEN
    RETURN public.navision_backend_response(false,'owner_identity_required');
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=v_actor
    AND lower(r.email)=v_email AND r.role='importer' AND r.active AND r.account_status='approved')
    OR NOT EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers w
      WHERE w.user_id=v_actor AND w.active AND w.revoked_at IS NULL) THEN
    RETURN public.navision_backend_response(false,'temporary_importer_writer_required');
  END IF;
  IF v_key!~'^pdc-owner-document-[A-Za-z0-9_-]{16,160}$'
     OR p_task_reference<>'t_3ff7139c'
     OR p_owner_instruction<>'Import owner-supplied PDF Stock 13080553 / JC J139125519 into the Email Monitor/Board flow.'
     OR jsonb_typeof(v_doc)<>'object'
     OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_doc) k) IS DISTINCT FROM
       ARRAY['byte_length','content_type','filename','metadata','sha256','source_label']::text[]
     OR v_doc->>'source_label'<>'owner_supplied_document'
     OR lower(coalesce(v_doc->>'sha256',''))!~'^[a-f0-9]{64}$'
     OR public.pdc_owner_document_numeric_396(v_doc->'byte_length') IS NULL
     OR public.pdc_owner_document_numeric_396(v_doc->'byte_length')<>trunc(public.pdc_owner_document_numeric_396(v_doc->'byte_length'))
     OR public.pdc_owner_document_numeric_396(v_doc->'byte_length') NOT BETWEEN 1 AND 52428800
     OR v_doc->>'content_type'<>'application/pdf'
     OR v_doc->>'filename'!~*'^[^/\\[:cntrl:]]+[.]pdf$'
     OR jsonb_typeof(v_doc->'metadata')<>'object'
     OR jsonb_typeof(v_identity)<>'object'
     OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_identity) k) IS DISTINCT FROM ARRAY['job_card_number','stock_number']::text[]
     OR jsonb_typeof(v_ops)<>'array' OR jsonb_array_length(v_ops) NOT BETWEEN 1 AND 50 THEN
    RETURN public.navision_backend_response(false,'owner_document_input_invalid');
  END IF;
  v_sha:=lower(v_doc->>'sha256'); v_bytes:=public.pdc_owner_document_numeric_396(v_doc->'byte_length')::bigint;
  v_filename:=v_doc->>'filename'; v_content_type:=v_doc->>'content_type'; v_source_label:=v_doc->>'source_label';
  v_stock:=upper(btrim(v_identity->>'stock_number')); v_job:=upper(btrim(v_identity->>'job_card_number'));
  IF v_stock<>'13080553' OR v_job<>'J139125519' THEN
    RETURN public.navision_backend_response(false,'owner_document_target_mismatch');
  END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_ops) WITH ORDINALITY x(op,n)
    WHERE jsonb_typeof(op)<>'object'
      OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(op) k) IS DISTINCT FROM ARRAY['description','hours','operation_no']::text[]
      OR op->>'operation_no' IS DISTINCT FROM 'OP'||n::text
      OR length(coalesce(op->>'description','')) NOT BETWEEN 1 AND 240
      OR op->>'description' IS DISTINCT FROM btrim(op->>'description')
      OR (op->>'description')~'[[:cntrl:]]'
      OR jsonb_typeof(op->'hours') NOT IN('number','null')
      OR (jsonb_typeof(op->'hours')='number' AND (public.pdc_owner_document_numeric_396(op->'hours') IS NULL
        OR public.pdc_owner_document_numeric_396(op->'hours')<0
        OR public.pdc_owner_document_numeric_396(op->'hours')>999.99
        OR public.pdc_owner_document_numeric_396(op->'hours')<>round(public.pdc_owner_document_numeric_396(op->'hours'),2)))) THEN
    RETURN public.navision_backend_response(false,'owner_document_operations_invalid');
  END IF;
  SELECT count(*) FILTER(WHERE jsonb_typeof(op->'hours')='number'),
         count(*) FILTER(WHERE jsonb_typeof(op->'hours')='null')
    INTO v_explicit_count,v_review_count FROM jsonb_array_elements(v_ops) x(op);
  IF v_explicit_count+v_review_count<>jsonb_array_length(v_ops) THEN
    RETURN public.navision_backend_response(false,'owner_document_hours_invalid');
  END IF;
  v_server_ops:=encode(extensions.digest(convert_to(v_ops::text,'UTF8'),'sha256'),'hex');
  v_request:=encode(extensions.digest(convert_to(jsonb_build_object(
    'contract_version','pdc-owner-supplied-document-v1','actor_id',v_actor,
    'task_reference',p_task_reference,'owner_instruction',p_owner_instruction,
    'document',v_doc,'identity',v_identity,'operations',v_ops
  )::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-owner-document-idempotency-396:'||v_key,0));
  SELECT * INTO v_receipt FROM public.pdc_owner_supplied_document_receipts_396 WHERE owner_id=v_actor AND idempotency_key=v_key;
  IF FOUND THEN
    IF v_receipt.request_sha256<>v_request THEN
      RETURN public.navision_backend_response(false,'owner_document_idempotency_conflict');
    END IF;
    RETURN public.read_pdc_owner_supplied_document_receipt_396(v_receipt.receipt_id);
  END IF;
  IF EXISTS(SELECT 1 FROM public.pdc_owner_supplied_document_receipts_396 WHERE owner_id=v_actor AND document_sha256=v_sha) THEN
    RETURN public.navision_backend_response(false,'owner_document_source_hash_conflict');
  END IF;
  IF EXISTS(SELECT 1 FROM public.pdc_authenticated_email_import_receipts WHERE source_hash=v_sha) THEN
    RETURN public.navision_backend_response(false,'owner_document_source_hash_conflict');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-owner-document-target-396:'||v_stock,0));
  LOCK TABLE public.navision_backend_records IN SHARE ROW EXCLUSIVE MODE;
  LOCK TABLE public.navision_board_activations IN SHARE ROW EXCLUSIVE MODE;
  LOCK TABLE public.vehicles IN SHARE ROW EXCLUSIVE MODE;
  LOCK TABLE public.vehicle_aliases IN SHARE ROW EXCLUSIVE MODE;
  LOCK TABLE public.vehicle_notifications IN SHARE ROW EXCLUSIVE MODE;
  v_notifications_before:=(SELECT count(*) FROM public.vehicle_notifications);
  SELECT * INTO v_backend FROM public.navision_backend_records r
   WHERE r.source_system='microsoft_navision' AND r.dealer_code IN('14450','37047')
     AND r.is_current AND r.record_status='current'
     AND public.normalize_vehicle_stock_number(coalesce(r.normalized_data->>'batch',r.normalized_data->>'stock_number'))=v_stock
     AND upper(btrim(coalesce(r.normalized_data->>'job_card_number',r.normalized_data->>'jobcard_number',r.normalized_data->>'job_card',r.normalized_data->>'jobCardNumber','')))=v_job;
  IF NOT FOUND THEN RETURN public.navision_backend_response(false,'owner_document_navision_match_not_found'); END IF;
  IF (SELECT count(*) FROM public.navision_backend_records r
      WHERE r.source_system='microsoft_navision' AND r.dealer_code IN('14450','37047') AND r.is_current AND r.record_status='current'
        AND public.normalize_vehicle_stock_number(coalesce(r.normalized_data->>'batch',r.normalized_data->>'stock_number'))=v_stock
        AND upper(btrim(coalesce(r.normalized_data->>'job_card_number',r.normalized_data->>'jobcard_number',r.normalized_data->>'job_card',r.normalized_data->>'jobCardNumber','')))=v_job)<>1 THEN
    RETURN public.navision_backend_response(false,'owner_document_navision_match_ambiguous');
  END IF;
  SELECT * INTO v_activation FROM public.navision_board_activations a WHERE a.backend_record_id=v_backend.id FOR UPDATE;
  IF FOUND AND (NOT v_activation.active OR public.normalize_vehicle_stock_number(v_activation.activated_stock_number)<>v_stock) THEN
    RETURN public.navision_backend_response(false,'owner_document_activation_conflict');
  END IF;
  IF NOT FOUND THEN
    v_vehicle_created:=true;
    INSERT INTO public.navision_board_activations(backend_record_id,activation_source,activated_stock_number,activated_by,activated_by_email,active)
      VALUES(v_backend.id,'manual',v_backend.normalized_data->>'batch',v_actor,v_email,true)
      RETURNING * INTO v_activation;
  END IF;
  SELECT a.canonical_vehicle_id INTO v_vehicle_id FROM public.navision_board_activations a WHERE a.backend_record_id=v_backend.id AND a.active;
  IF v_vehicle_id IS NULL THEN
    SELECT canonical_vehicle_id INTO v_vehicle_id FROM public.navision_backend_records WHERE id=v_backend.id;
  END IF;
  SELECT * INTO v_vehicle FROM public.vehicles WHERE id=v_vehicle_id FOR UPDATE;
  IF NOT FOUND OR v_vehicle.deleted_at IS NOT NULL OR v_vehicle.lifecycle_state<>'active' OR NOT v_vehicle.visible_on_board
     OR public.normalize_vehicle_stock_number(v_vehicle.stock_number)<>v_stock
     OR upper(btrim(coalesce(v_vehicle.job_card_number,'')))<>v_job THEN
    RAISE EXCEPTION 'PDC_396_EXACT_CANONICAL_VEHICLE_POSTCONDITION' USING errcode='40001';
  END IF;
  v_bookings_before:=(SELECT count(*) FROM public.workshop_bookings WHERE vehicle_id=v_vehicle.id);
  v_movements_before:=(SELECT count(*) FROM public.vehicle_movements WHERE vehicle_id=v_vehicle.id);
  v_source_uid:='pdc-owner-document-396:'||v_sha;
  INSERT INTO public.pdc_authenticated_email_import_receipts(
    actor_id,idempotency_key,request_hash,source_hash,evidence_hash,source_uid,sender_address,source_received_at,
    stock_number,vin,backend_record_id,backend_record_version,vehicle_id,identity_source,required_work,response
  ) VALUES(v_actor,'pdc-owner-import-'||substring(v_request,1,48),v_request,v_sha,v_sha,v_source_uid,
    'owner_supplied_document',v_now,v_stock,public.normalize_vehicle_vin(v_vehicle.vin),v_backend.id,v_backend.version,
    v_vehicle.id,'navision_exact', '[]'::jsonb,
    jsonb_build_object('contract','pdc-owner-supplied-document-v1','provenance','owner_supplied_document',
      'task_reference',p_task_reference,'document_sha256',v_sha,'booking_created',false,'physical_completion_created',false))
    RETURNING * INTO v_canonical;
  v_response:=jsonb_build_object('receipt_id',gen_random_uuid(),'provenance','owner_supplied_document',
    'task_reference',p_task_reference,'document_sha256',v_sha,'stock_number',v_stock,'job_card_number',v_job,
    'navision_backend_record_id',v_backend.id,'vehicle_id',v_vehicle.id,'vehicle_created',v_vehicle_created,
    'canonical_import_receipt_id',v_canonical.receipt_id,'operation_count',jsonb_array_length(v_ops),
    'explicit_hours_count',v_explicit_count,'unknown_hours_count',v_review_count,'operation_lines_sha256',v_server_ops,
    'booking_created',false,'physical_completion_created',false,'notification_delta',0);
  INSERT INTO public.pdc_owner_supplied_document_receipts_396(
    receipt_id,contract_version,provenance,owner_id,owner_email,task_reference,owner_instruction,idempotency_key,document_sha256,
    document_byte_length,document_content_type,document_filename,document_metadata,stock_number,job_card_number,
    navision_backend_record_id,canonical_import_receipt_id,vehicle_id,vehicle_created,vehicle_version,
    operation_count,explicit_hours_count,unknown_hours_count,operation_lines_sha256,request_sha256,response)
  VALUES((v_response->>'receipt_id')::uuid,'pdc-owner-supplied-document-v1','owner_supplied_document',v_actor,v_email,p_task_reference,p_owner_instruction,v_key,v_sha,
    v_bytes,v_content_type,v_filename,v_doc->'metadata',v_stock,v_job,v_backend.id,v_canonical.receipt_id,v_vehicle.id,v_vehicle_created,
    v_vehicle.version,jsonb_array_length(v_ops),v_explicit_count,v_review_count,v_server_ops,v_request,v_response)
  RETURNING * INTO v_receipt;
  FOR v_op IN SELECT value FROM jsonb_array_elements(v_ops) ORDER BY substring(value->>'operation_no' from 3)::integer LOOP
    v_description:=v_op->>'description';
    v_hours:=public.pdc_owner_document_numeric_396(v_op->'hours');
    v_work_key:=coalesce(public.pdc_email_jobcard_work_key(v_description),'owner_supplied_document');
    v_fingerprint:=encode(extensions.digest(convert_to(jsonb_build_object('source_hash',v_sha,'operation',v_op)::text,'UTF8'),'sha256'),'hex');
    v_created_work:=false; v_work_id:=null;
    IF v_work_key<>'owner_supplied_document' THEN
      SELECT * INTO v_before_work FROM public.vehicle_work_items WHERE vehicle_id=v_vehicle.id AND work_key=v_work_key FOR UPDATE;
      INSERT INTO public.vehicle_work_items(vehicle_id,work_key,required,completed,completed_by,completed_at,notes,updated_at)
      VALUES(v_vehicle.id,v_work_key,true,false,null,null,'Required by owner-supplied document receipt '||v_source_uid,v_now)
      ON CONFLICT(vehicle_id,work_key) DO UPDATE SET required=true,updated_at=v_now
        WHERE NOT public.vehicle_work_items.completed
      RETURNING id INTO v_work_id;
      v_created_work:=v_work_id IS NOT NULL AND v_before_work.id IS NULL;
      IF v_work_id IS NULL THEN SELECT id INTO v_work_id FROM public.vehicle_work_items WHERE vehicle_id=v_vehicle.id AND work_key=v_work_key; END IF;
    END IF;
    INSERT INTO public.pdc_authenticated_email_operation_lines(
      import_receipt_id,vehicle_id,source_hash,source_uid,operation_no,work_key,description,operation_fingerprint,
      estimated_hours,estimated_hours_source,job_card_number,source_row_no,source_contract)
    VALUES(v_canonical.receipt_id,v_vehicle.id,v_sha,v_source_uid,v_op->>'operation_no',v_work_key,v_description,v_fingerprint,
      v_hours,CASE WHEN v_hours IS NULL THEN 'owner_supplied_document_unknown' ELSE 'owner_supplied_document' END,
      v_job,substring(v_op->>'operation_no' from 3)::integer,'pdc-owner-supplied-document-v1')
    RETURNING operation_line_id INTO v_line_id;
    INSERT INTO public.pdc_owner_supplied_document_operation_receipts_396(
      receipt_id,operation_line_id,operation_no,source_row_no,description,estimated_hours,estimated_hours_source,
      work_key,operation_fingerprint,source_locator,work_item_id,work_item_created)
    VALUES(v_receipt.receipt_id,v_line_id,v_op->>'operation_no',substring(v_op->>'operation_no' from 3)::integer,v_description,v_hours,
      CASE WHEN v_hours IS NULL THEN 'owner_supplied_document_unknown' ELSE 'owner_supplied_document' END,
      v_work_key,v_fingerprint,jsonb_build_object('source','owner_supplied_document','row_no',substring(v_op->>'operation_no' from 3)::integer),v_work_id,v_created_work);
  END LOOP;
  v_notifications_after:=(SELECT count(*) FROM public.vehicle_notifications);
  v_bookings_after:=(SELECT count(*) FROM public.workshop_bookings WHERE vehicle_id=v_vehicle.id);
  v_movements_after:=(SELECT count(*) FROM public.vehicle_movements WHERE vehicle_id=v_vehicle.id);
  IF v_notifications_after<>v_notifications_before OR v_bookings_after<>v_bookings_before OR v_movements_after<>v_movements_before THEN
    RAISE EXCEPTION 'PDC_396_OPERATION_SIDE_EFFECT_POSTCONDITION' USING errcode='55000';
  END IF;
  FOR v_item IN SELECT value FROM jsonb_array_elements(v_ops) WHERE jsonb_typeof(value->'hours')='null' LOOP
    SELECT operation_line_id INTO v_line_id FROM public.pdc_authenticated_email_operation_lines
      WHERE source_hash=v_sha AND operation_no=v_item->>'operation_no';
    INSERT INTO public.pdc_owner_supplied_document_review_items_396(receipt_id,operation_line_id,reason)
      VALUES(v_receipt.receipt_id,v_line_id,'owner-supplied document did not state hours');
  END LOOP;

  INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
    VALUES('insert','pdc_owner_supplied_document_receipts_396',v_receipt.receipt_id,v_vehicle.id,v_actor,v_email,NULL,v_response,
      jsonb_build_object('provenance','owner_supplied_document','task_reference',p_task_reference,'document_sha256',v_sha,
        'no_booking',true,'no_physical_completion',true,'notification_delta',0));
  RETURN public.read_pdc_owner_supplied_document_receipt_396(v_receipt.receipt_id);
EXCEPTION WHEN unique_violation THEN
  RETURN public.navision_backend_response(false,'owner_document_identity_or_receipt_conflict');
END $process$;
REVOKE ALL ON FUNCTION public.process_pdc_owner_supplied_document_jobcard_396(text,text,text,jsonb,jsonb,jsonb) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.process_pdc_owner_supplied_document_jobcard_396(text,text,text,jsonb,jsonb,jsonb) TO authenticated;

CREATE FUNCTION public.undo_pdc_owner_supplied_document_jobcard_396(
  p_receipt_id uuid,p_undo_idempotency_key text,p_reason text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions AS $undo$
DECLARE
  v_actor uuid:=auth.uid(); v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_r public.pdc_owner_supplied_document_receipts_396%rowtype; v_u public.pdc_owner_supplied_document_undo_receipts_396%rowtype;
  v_request text; v_line record; v_n integer:=0; v_review integer:=0; v_work integer:=0;
  v_notifications bigint; v_bookings bigint; v_movements bigint; v_removed integer; v_response jsonb;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() OR v_actor IS NULL OR v_email<>'pmbcontroller@gmail.com'
     OR NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=v_actor AND lower(r.email)=v_email
       AND r.role='importer' AND r.active AND r.account_status='approved')
     OR NOT EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers w WHERE w.user_id=v_actor AND w.active AND w.revoked_at IS NULL)
     OR p_receipt_id IS NULL OR p_undo_idempotency_key!~'^pdc-owner-undo-[A-Za-z0-9_-]{16,160}$'
     OR length(btrim(coalesce(p_reason,''))) NOT BETWEEN 10 AND 500 THEN
    RETURN public.navision_backend_response(false,'owner_document_undo_unauthorized_or_invalid');
  END IF;
  SELECT * INTO v_r FROM public.pdc_owner_supplied_document_receipts_396 WHERE receipt_id=p_receipt_id AND owner_id=v_actor;
  IF NOT FOUND THEN RETURN public.navision_backend_response(false,'owner_document_receipt_not_found'); END IF;
  SELECT * INTO v_u FROM public.pdc_owner_supplied_document_undo_receipts_396 WHERE receipt_id=p_receipt_id;
  IF FOUND THEN
    v_request:=v_u.request_sha256;
    RETURN public.navision_backend_response(true,'owner_document_undo_replayed',v_u.response||jsonb_build_object('replayed',true));
  END IF;
  v_request:=encode(extensions.digest(convert_to(jsonb_build_object('contract','pdc-owner-supplied-document-undo-v1','actor_id',v_actor,
    'receipt_id',p_receipt_id,'undo_idempotency_key',p_undo_idempotency_key,'reason',btrim(p_reason))::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc-owner-document-undo-396:'||p_receipt_id::text,0));
  IF EXISTS(SELECT 1 FROM public.pdc_owner_supplied_document_undo_receipts_396 WHERE undo_idempotency_key=p_undo_idempotency_key
    AND request_sha256<>v_request) THEN RETURN public.navision_backend_response(false,'owner_document_undo_replay_conflict'); END IF;
  SELECT count(*) INTO v_bookings FROM public.workshop_bookings WHERE vehicle_id=v_r.vehicle_id;
  SELECT count(*) INTO v_movements FROM public.vehicle_movements WHERE vehicle_id=v_r.vehicle_id;
  SELECT count(*) INTO v_notifications FROM public.vehicle_notifications WHERE vehicle_id=v_r.vehicle_id;
  IF v_bookings<>0 OR v_movements<>0 OR v_notifications<>0 THEN
    RETURN public.navision_backend_response(false,'owner_document_undo_protected_side_effect');
  END IF;
  PERFORM set_config('pdc.owner_supplied_document_undo_396','approved',true);
  FOR v_line IN SELECT ol.operation_line_id,orx.work_item_id,orx.work_item_created
    FROM public.pdc_authenticated_email_operation_lines ol
    JOIN public.pdc_owner_supplied_document_operation_receipts_396 orx ON orx.operation_line_id=ol.operation_line_id
    WHERE orx.receipt_id=v_r.receipt_id FOR UPDATE LOOP
    DELETE FROM public.pdc_owner_supplied_document_review_items_396 WHERE operation_line_id=v_line.operation_line_id;
    GET DIAGNOSTICS v_removed = ROW_COUNT;
    v_review:=v_review+v_removed;
    DELETE FROM public.pdc_owner_supplied_document_operation_receipts_396 WHERE operation_line_id=v_line.operation_line_id;
    DELETE FROM public.pdc_authenticated_email_operation_lines WHERE operation_line_id=v_line.operation_line_id;
    IF v_line.work_item_created AND v_line.work_item_id IS NOT NULL THEN
      DELETE FROM public.vehicle_work_items WHERE id=v_line.work_item_id AND vehicle_id=v_r.vehicle_id AND NOT completed;
      v_work:=v_work+1;
    END IF;
    v_n:=v_n+1;
  END LOOP;
  INSERT INTO public.pdc_owner_supplied_document_undo_receipts_396(receipt_id,actor_id,actor_email,undo_idempotency_key,request_sha256,reason,response)
    VALUES(v_r.receipt_id,v_actor,v_email,p_undo_idempotency_key,v_request,btrim(p_reason),
      jsonb_build_object('receipt_id',v_r.receipt_id,'operation_lines_removed',v_n,'review_items_removed',v_review,
        'work_items_removed',v_work,'booking_created',false,'physical_completion_created',false,'notification_delta',0))
    RETURNING * INTO v_u;
  INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
    VALUES('delete','pdc_owner_supplied_document_undo_receipts_396',v_u.undo_receipt_id,v_r.vehicle_id,v_actor,v_email,v_r.response,v_u.response,
      jsonb_build_object('provenance','owner_supplied_document','undo',true,'receipt_id',v_r.receipt_id,
        'no_booking',true,'no_physical_completion',true,'notification_delta',0));
  v_response:=v_u.response;
  RETURN public.navision_backend_response(true,'owner_document_undone',v_response);
EXCEPTION WHEN unique_violation THEN
  SELECT * INTO v_u FROM public.pdc_owner_supplied_document_undo_receipts_396 WHERE receipt_id=p_receipt_id;
  IF FOUND THEN RETURN public.navision_backend_response(true,'owner_document_undo_replayed',v_u.response||jsonb_build_object('replayed',true)); END IF;
  RETURN public.navision_backend_response(false,'owner_document_undo_replay_conflict');
END $undo$;
REVOKE ALL ON FUNCTION public.undo_pdc_owner_supplied_document_jobcard_396(uuid,text,text) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.undo_pdc_owner_supplied_document_jobcard_396(uuid,text,text) TO authenticated;

-- Keep the canonical import parent as immutable evidence. The final Board
-- snapshot hides only an undone owner projection when no sibling canonical
-- receipt still projects the same vehicle.
ALTER FUNCTION public.get_pdc_email_vehicle_location_snapshot()
  RENAME TO get_pdc_email_vehicle_location_snapshot_pre_396;
REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_location_snapshot_pre_396() FROM public,anon,authenticated,service_role;
CREATE FUNCTION public.get_pdc_email_vehicle_location_snapshot()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public AS $snapshot$
DECLARE v_result jsonb; v_rows jsonb;
BEGIN
  v_result:=public.get_pdc_email_vehicle_location_snapshot_pre_396();
  IF NOT coalesce((v_result->>'ok')::boolean,false) THEN RETURN v_result; END IF;
  SELECT coalesce(jsonb_agg(vehicle ORDER BY ordinal),'[]'::jsonb) INTO v_rows
  FROM jsonb_array_elements(coalesce(v_result#>'{data,vehicles}','[]'::jsonb)) WITH ORDINALITY rows(vehicle,ordinal)
  WHERE NOT EXISTS(
    SELECT 1 FROM public.pdc_owner_supplied_document_receipts_396 r
    JOIN public.pdc_owner_supplied_document_undo_receipts_396 u ON u.receipt_id=r.receipt_id
    WHERE r.vehicle_id=(vehicle->>'id')::uuid
      AND NOT EXISTS(
        SELECT 1 FROM public.pdc_authenticated_email_import_receipts sibling
        WHERE sibling.vehicle_id=r.vehicle_id AND sibling.receipt_id<>r.canonical_import_receipt_id
      )
  );
  RETURN jsonb_set(v_result,'{data,vehicles}',v_rows,true);
END $snapshot$;
REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() TO authenticated,service_role;

DO $post$
BEGIN
  IF has_function_privilege('public','public.process_pdc_owner_supplied_document_jobcard_396(text,text,text,jsonb,jsonb,jsonb)','EXECUTE')
    OR has_function_privilege('anon','public.process_pdc_owner_supplied_document_jobcard_396(text,text,text,jsonb,jsonb,jsonb)','EXECUTE')
    OR has_function_privilege('service_role','public.process_pdc_owner_supplied_document_jobcard_396(text,text,text,jsonb,jsonb,jsonb)','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.process_pdc_owner_supplied_document_jobcard_396(text,text,text,jsonb,jsonb,jsonb)','EXECUTE')
    OR has_function_privilege('public','public.undo_pdc_owner_supplied_document_jobcard_396(uuid,text,text)','EXECUTE')
    OR has_function_privilege('anon','public.undo_pdc_owner_supplied_document_jobcard_396(uuid,text,text)','EXECUTE')
    OR has_function_privilege('service_role','public.undo_pdc_owner_supplied_document_jobcard_396(uuid,text,text)','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.undo_pdc_owner_supplied_document_jobcard_396(uuid,text,text)','EXECUTE')
    OR has_function_privilege('public','public.get_pdc_email_vehicle_location_snapshot()','EXECUTE')
    OR has_function_privilege('anon','public.get_pdc_email_vehicle_location_snapshot()','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.get_pdc_email_vehicle_location_snapshot()','EXECUTE')
    OR NOT has_function_privilege('service_role','public.get_pdc_email_vehicle_location_snapshot()','EXECUTE')
    OR (SELECT count(*) FROM public.vehicle_notifications)<>1 THEN
    RAISE EXCEPTION 'PDC_396_ACL_OR_NOTIFICATION_POSTCONDITION' USING errcode='55000';
  END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826120000','396_owner_supplied_document_jobcard_intake',ARRAY[
  'Exact owner_supplied_document provenance for Craig task t_3ff7139c and Stock 13080553 / JC J139125519',
  'Immutable PDF hash/byte metadata, exact current Navision identity and canonical Board operation evidence',
  'Explicit zero hours remain numeric zero; unknown hours remain NULL with durable review rows',
  'Narrow approved Craig Importer plus temporary activation writer; no provider/email/mailbox attestation path',
  'Immutable receipt/audit/idempotency/undo contract with no booking, movement, completion or notification authority',
  'Authenticated-only staging RPCs with public/anon/service_role denied'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
