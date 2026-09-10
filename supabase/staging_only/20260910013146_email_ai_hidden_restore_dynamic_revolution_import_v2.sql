-- STAGING ONLY: dynamic Revolution/Pilbara service intake + hidden New Vehicles restore.
-- Reuses existing evidence/import tables and New Vehicles review queue.
-- Historical service operation/evidence rows remain append-only.

DO $guard$
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE
     OR current_setting('app.environment', true) = 'production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'STAGING only';
  END IF;
END
$guard$;

CREATE OR REPLACE FUNCTION public.pdc_email_ai_runtime_authorized_v1()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $$
  SELECT auth.role() = 'authenticated'
    AND auth.uid() IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.pdc_user_roles r
      WHERE r.auth_user_id = auth.uid()
        AND lower(btrim(r.email)) = lower(btrim(coalesce(auth.jwt()->>'email','')))
        AND r.active
        AND r.account_status = 'approved'
        AND r.role = 'viewer'
    )
    AND EXISTS (
      SELECT 1
      FROM public.pdc_email_ai_successor_runtime_identities i
      WHERE i.auth_user_id = auth.uid()
        AND i.normalized_email = lower(btrim(coalesce(auth.jwt()->>'email','')))
        AND i.environment = 'staging'
        AND i.identity_purpose = 'pdc_email_ai_transaction_successor'
        AND i.active
        AND i.revoked_at IS NULL
    );
$$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_runtime_authorized_v1() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.pdc_pilbara_service_operation_identity_hash_v2(
  p_stock text,
  p_repair_order text,
  p_line integer,
  p_description text
)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path TO 'pg_catalog','extensions'
AS $$
  SELECT encode(
    extensions.digest(
      convert_to(
        concat_ws(chr(31),
          btrim(coalesce(p_stock,'')),
          upper(btrim(coalesce(p_repair_order,''))),
          coalesce(p_line,0)::text,
          regexp_replace(lower(btrim(coalesce(p_description,''))), '\s+', ' ', 'g')
        ),
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );
$$;
REVOKE ALL ON FUNCTION public.pdc_pilbara_service_operation_identity_hash_v2(text,text,integer,text)
FROM PUBLIC, anon, authenticated;

ALTER TABLE public.pdc_pilbara_service_operations
  DROP CONSTRAINT IF EXISTS pdc_pilbara_service_operation_importer_version_stock_number_key;
DROP INDEX IF EXISTS public.pdc_pilbara_service_operation_importer_version_stock_number_key;
CREATE UNIQUE INDEX IF NOT EXISTS pdc_pilbara_service_operation_semantic_identity_key
ON public.pdc_pilbara_service_operations(
  importer_version,
  (public.pdc_pilbara_service_operation_identity_hash_v2(
    stock_number,repair_order_number,original_line_number,operation_description
  ))
);

ALTER TABLE public.pdc_pilbara_service_operations
  DROP CONSTRAINT IF EXISTS pdc_pilbara_service_operations_source_order_check,
  DROP CONSTRAINT IF EXISTS pdc_pilbara_service_operations_hours_provenance_check;
ALTER TABLE public.pdc_pilbara_service_operations
  ADD CONSTRAINT pdc_pilbara_service_operations_source_order_check
    CHECK (source_order BETWEEN 1 AND 1000000),
  ADD CONSTRAINT pdc_pilbara_service_operations_hours_provenance_check
    CHECK (hours_provenance = ANY(ARRAY[
      'source_explicit','source_blank','pre_delivery_default_1_5',
      'pre_delivery_default_1_0','ai_estimated'
    ]));

ALTER TABLE public.pdc_pilbara_service_import_rows
  DROP CONSTRAINT IF EXISTS pdc_pilbara_service_import_rows_source_order_check,
  DROP CONSTRAINT IF EXISTS pdc_pilbara_service_import_rows_decision_check;
ALTER TABLE public.pdc_pilbara_service_import_rows
  ADD CONSTRAINT pdc_pilbara_service_import_rows_source_order_check
    CHECK (source_order BETWEEN 1 AND 1000000),
  ADD CONSTRAINT pdc_pilbara_service_import_rows_decision_check
    CHECK (decision = ANY(ARRAY['insert','unchanged','duplicate','quarantine','conflict']));

ALTER TABLE public.pdc_pilbara_service_import_batches
  DROP CONSTRAINT IF EXISTS pdc_pilbara_service_import_batches_source_row_count_check,
  DROP CONSTRAINT IF EXISTS pdc_pilbara_service_import_batches_accepted_line_count_check,
  DROP CONSTRAINT IF EXISTS pdc_pilbara_service_import_batches_quarantined_line_count_check,
  DROP CONSTRAINT IF EXISTS pdc_pilbara_service_import_batches_matched_stock_count_check,
  DROP CONSTRAINT IF EXISTS pdc_pilbara_service_import_batches_unmatched_stock_count_check,
  DROP CONSTRAINT IF EXISTS pdc_pilbara_service_import_batches_ambiguous_stock_count_check;
ALTER TABLE public.pdc_pilbara_service_import_batches
  ADD CONSTRAINT pdc_pilbara_service_import_batches_source_row_count_check
    CHECK (source_row_count BETWEEN 1 AND 1000000),
  ADD CONSTRAINT pdc_pilbara_service_import_batches_accepted_line_count_check
    CHECK (accepted_line_count BETWEEN 0 AND source_row_count),
  ADD CONSTRAINT pdc_pilbara_service_import_batches_quarantined_line_count_check
    CHECK (quarantined_line_count BETWEEN 0 AND source_row_count),
  ADD CONSTRAINT pdc_pilbara_service_import_batches_matched_stock_count_check
    CHECK (matched_stock_count >= 0),
  ADD CONSTRAINT pdc_pilbara_service_import_batches_unmatched_stock_count_check
    CHECK (unmatched_stock_count >= 0),
  ADD CONSTRAINT pdc_pilbara_service_import_batches_ambiguous_stock_count_check
    CHECK (ambiguous_stock_count >= 0);

CREATE TABLE IF NOT EXISTS public.pdc_email_ai_new_vehicle_restore_receipts_20260910 (
  receipt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  idempotency_key text NOT NULL UNIQUE CHECK (length(btrim(idempotency_key)) BETWEEN 12 AND 160),
  request_hash text NOT NULL CHECK (request_hash ~ '^[a-f0-9]{64}$'),
  vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
  tombstone_id uuid NOT NULL REFERENCES public.pdc_vehicle_tombstones(tombstone_id) ON DELETE RESTRICT,
  backend_record_id uuid NOT NULL REFERENCES public.navision_backend_records(id) ON DELETE RESTRICT,
  stock_number text NOT NULL CHECK (length(btrim(stock_number)) BETWEEN 1 AND 80),
  before_state jsonb NOT NULL CHECK (jsonb_typeof(before_state)='object'),
  after_state jsonb NOT NULL CHECK (jsonb_typeof(after_state)='object'),
  response jsonb NOT NULL CHECK (jsonb_typeof(response)='object'),
  created_by uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE public.pdc_email_ai_new_vehicle_restore_receipts_20260910 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_email_ai_new_vehicle_restore_receipts_20260910 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_email_ai_new_vehicle_restore_receipts_20260910 FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.pdc_email_ai_restore_receipt_immutable_20260910()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog'
AS $$
BEGIN
  RAISE EXCEPTION 'restore receipts are immutable' USING ERRCODE='42501';
END
$$;
DROP TRIGGER IF EXISTS pdc_email_ai_restore_receipt_immutable_20260910
ON public.pdc_email_ai_new_vehicle_restore_receipts_20260910;
CREATE TRIGGER pdc_email_ai_restore_receipt_immutable_20260910
BEFORE UPDATE OR DELETE ON public.pdc_email_ai_new_vehicle_restore_receipts_20260910
FOR EACH ROW EXECUTE FUNCTION public.pdc_email_ai_restore_receipt_immutable_20260910();

CREATE OR REPLACE FUNCTION public.pdc_email_ai_restore_hidden_new_vehicle_v1(
  p_vehicle_id uuid,
  p_stock_number text,
  p_backend_record_id uuid,
  p_tombstone_id uuid,
  p_idempotency_key text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
SET lock_timeout TO '5s'
SET statement_timeout TO '60s'
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_actor_email text := lower(btrim(coalesce(auth.jwt()->>'email','')));
  v_stock text := btrim(coalesce(p_stock_number,''));
  v_idem text := btrim(coalesce(p_idempotency_key,''));
  v_request_hash text;
  v_prior public.pdc_email_ai_new_vehicle_restore_receipts_20260910%rowtype;
  v_vehicle public.vehicles%rowtype;
  v_after public.vehicles%rowtype;
  v_tombstone public.pdc_vehicle_tombstones%rowtype;
  v_backend public.navision_backend_records%rowtype;
  v_before_state jsonb;
  v_after_state jsonb;
  v_response jsonb;
  v_location text;
  v_eta date;
  v_vin text;
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RETURN jsonb_build_object('ok',false,'code','wrong_environment');
  END IF;
  IF NOT public.pdc_email_ai_runtime_authorized_v1() THEN
    RETURN jsonb_build_object('ok',false,'code','not_authorized');
  END IF;
  IF p_vehicle_id IS NULL OR p_backend_record_id IS NULL OR p_tombstone_id IS NULL
     OR v_stock='' OR length(v_stock)>80 OR length(v_idem) NOT BETWEEN 12 AND 160 THEN
    RETURN jsonb_build_object('ok',false,'code','invalid_restore_request');
  END IF;
  v_request_hash := encode(extensions.digest(convert_to(jsonb_build_object(
    'contract','pdc_email_ai_restore_hidden_new_vehicle_v1','vehicle_id',p_vehicle_id,
    'stock_number',v_stock,'backend_record_id',p_backend_record_id,'tombstone_id',p_tombstone_id
  )::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc:email-ai:hidden-restore:'||v_idem,0));
  SELECT * INTO v_prior FROM public.pdc_email_ai_new_vehicle_restore_receipts_20260910 WHERE idempotency_key=v_idem;
  IF FOUND THEN
    IF v_prior.request_hash<>v_request_hash THEN RETURN jsonb_build_object('ok',false,'code','idempotency_conflict'); END IF;
    RETURN v_prior.response || jsonb_build_object('replay',true);
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc:vehicle-lifecycle:'||p_vehicle_id::text,0));
  SELECT * INTO v_tombstone FROM public.pdc_vehicle_tombstones WHERE tombstone_id=p_tombstone_id FOR SHARE;
  IF NOT FOUND OR v_tombstone.vehicle_id<>p_vehicle_id OR v_tombstone.normalized_stock<>v_stock THEN
    RETURN jsonb_build_object('ok',false,'code','tombstone_identity_mismatch');
  END IF;
  IF EXISTS (SELECT 1 FROM public.pdc_vehicle_lifecycle_events e WHERE e.tombstone_id=v_tombstone.tombstone_id AND e.event_kind='restored') THEN
    RETURN jsonb_build_object('ok',false,'code','tombstone_already_restored');
  END IF;
  SELECT * INTO v_backend FROM public.navision_backend_records WHERE id=p_backend_record_id FOR SHARE;
  IF NOT FOUND OR v_backend.source_system<>'microsoft_navision' OR v_backend.dealer_code<>'37047'
     OR NOT v_backend.is_current OR v_backend.record_status<>'current'
     OR btrim(coalesce(v_backend.normalized_data->>'batch',v_backend.normalized_data->>'stock',''))<>v_stock
     OR v_backend.canonical_vehicle_id<>p_vehicle_id THEN
    RETURN jsonb_build_object('ok',false,'code','backend_identity_mismatch');
  END IF;
  IF (SELECT count(*) FROM public.navision_backend_records x WHERE x.source_system='microsoft_navision'
      AND x.dealer_code=v_backend.dealer_code AND x.is_current AND x.record_status='current'
      AND btrim(coalesce(x.normalized_data->>'batch',x.normalized_data->>'stock',''))=v_stock)<>1 THEN
    RETURN jsonb_build_object('ok',false,'code','backend_identity_ambiguous');
  END IF;
  SELECT * INTO v_vehicle FROM public.vehicles WHERE id=p_vehicle_id FOR UPDATE;
  IF NOT FOUND OR v_vehicle.deleted_at IS NULL OR v_vehicle.lifecycle_state::text<>'deleted' OR v_vehicle.visible_on_board THEN
    RETURN jsonb_build_object('ok',false,'code','vehicle_not_exact_tombstone_state');
  END IF;
  v_vin := upper(btrim(coalesce(v_backend.normalized_data->>'vin',v_tombstone.vehicle_snapshot->>'vin','')));
  IF EXISTS (SELECT 1 FROM public.vehicles x WHERE x.id<>p_vehicle_id AND x.deleted_at IS NULL
      AND (x.stock_number_normalized=v_stock OR (v_vin<>'' AND x.vin_normalized=v_vin))) THEN
    RETURN jsonb_build_object('ok',false,'code','restore_identity_conflict');
  END IF;
  v_location := public.navision_operational_location(v_backend.normalized_data);
  IF v_location='Completed' THEN RETURN jsonb_build_object('ok',false,'code','delivered_vehicle_not_restorable'); END IF;
  v_eta := public.navision_kewdale_eta(v_backend.normalized_data);
  v_before_state := to_jsonb(v_vehicle);
  PERFORM set_config('pdc.vehicle_restore_tombstone',v_tombstone.tombstone_id::text,true);
  UPDATE public.vehicles SET
      stock_number=v_stock,stock_number_normalized=v_stock,
      vin=coalesce(nullif(v_vin,''),v_vehicle.vin),vin_normalized=coalesce(nullif(v_vin,''),v_vehicle.vin_normalized),
      customer_name=coalesce(nullif(btrim(v_backend.normalized_data->>'client'),''),nullif(btrim(v_backend.normalized_data->>'customerSurname'),''),v_vehicle.customer_name),
      vehicle_description=coalesce(nullif(btrim(v_backend.normalized_data->>'modelDescription'),''),nullif(btrim(v_backend.normalized_data->>'vehicle'),''),v_vehicle.vehicle_description),
      source_record_id=v_backend.id::text,source_record_id_normalized=upper(v_backend.id::text),source_batch_id=v_backend.dealer_code,
      source_system='microsoft_navision',source_system_normalized='microsoft_navision',eta_to_kewdale=v_eta,current_location=v_location,
      lifecycle_state='active',visible_on_board=false,job_card_number=NULL,
      pmb_stage=NULL,pmb_bay_stage=NULL,pmb_bay_number=NULL,pmb_key_tag=NULL,date_to_pmb=NULL,date_to_rft=NULL,
      workshop_status='queued',active_workshop_booking_id=NULL,pmb_stoppage_reason=NULL,pmb_stoppage_started_at=NULL,pmb_stoppage_started_by=NULL,
      pmb_stoppage_cleared_at=NULL,pmb_stoppage_cleared_by=NULL,qc_completed_at=NULL,qc_completed_by=NULL,
      rft_transferred_at=NULL,rft_confirmed_at=NULL,rft_confirmed_by=NULL,rft_collected_at=NULL,rft_collected_by=NULL,
      rft_transport_booked_at=NULL,rft_transport_booked_by=NULL,dealer_transit_started_at=NULL,dealer_transit_closed_at=NULL,
      dealer_transit_duration_seconds=NULL,delivered_to_dealer_date=NULL,board_purged_at=NULL,board_purged_by=NULL,board_purge_reason=NULL,
      deleted_at=NULL,deleted_reason=NULL,sales_build_complete=false,sales_build_po_raised=false,sales_tint_raised=false,
      sales_tray_ordered=false,sales_tray_complete=false,
      source_payload=(coalesce(v_vehicle.source_payload,'{}'::jsonb)-'manual_location_authority'-'manual_location_updated_at'-'manual_location_updated_by')
        || jsonb_build_object('authority','pdc_email_ai_hidden_new_vehicle_restore_v1','navision_record_id',v_backend.id,
          'navision_source_data',v_backend.normalized_data,'latest_navision_status',coalesce(v_backend.normalized_data->>'toyotaStatus',v_backend.normalized_data->>'navisionLocationStatus',''),
          'restored_to_new_vehicle_at',clock_timestamp()),
      version=version+1,updated_by=v_actor,updated_at=clock_timestamp()
  WHERE id=p_vehicle_id RETURNING * INTO v_after;
  UPDATE public.vehicle_work_items SET required=false,completed=false,completed_by=NULL,completed_at=NULL,updated_at=clock_timestamp() WHERE vehicle_id=v_after.id;
  INSERT INTO public.pdc_new_vehicle_reviews(vehicle_id,status,source_kind,first_job_card,received_at,approved_at,approved_by,approval_key,approval_hash,approval_receipt)
  VALUES(v_after.id,'pending','revolution_report',NULL,clock_timestamp(),NULL,NULL,NULL,NULL,NULL)
  ON CONFLICT(vehicle_id) DO UPDATE SET status='pending',source_kind='revolution_report',first_job_card=NULL,received_at=clock_timestamp(),
    approved_at=NULL,approved_by=NULL,approval_key=NULL,approval_hash=NULL,approval_receipt=NULL;
  INSERT INTO public.pdc_vehicle_lifecycle_events(tombstone_id,vehicle_id,normalized_stock,event_kind,actor_id,actor_email,evidence)
  VALUES(v_tombstone.tombstone_id,v_after.id,v_stock,'restored',v_actor,v_actor_email,
    jsonb_build_object('reason','Current Revolution Job Card restored to hidden New Vehicles review','restore_mode','hidden_new_vehicle_pending',
      'same_vehicle_uuid',true,'bookings_reactivated',false,'completion_state_reactivated',false,'backend_record_id',v_backend.id));
  v_after_state:=to_jsonb(v_after);
  v_response:=jsonb_build_object('ok',true,'code','hidden_new_vehicle_restored','replay',false,'data',jsonb_build_object(
    'vehicle_id',v_after.id,'stock_number',v_after.stock_number,'vehicle_version',v_after.version,'current_location',v_after.current_location,
    'visible_on_board',v_after.visible_on_board,'new_vehicle_status','pending','backend_record_id',v_backend.id,'tombstone_id',v_tombstone.tombstone_id,
    'bookings_created',0,'completions_created',0));
  INSERT INTO public.pdc_email_ai_new_vehicle_restore_receipts_20260910(idempotency_key,request_hash,vehicle_id,tombstone_id,backend_record_id,stock_number,before_state,after_state,response,created_by)
  VALUES(v_idem,v_request_hash,v_after.id,v_tombstone.tombstone_id,v_backend.id,v_stock,v_before_state,v_after_state,v_response,v_actor);
  INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
  VALUES('restore'::public.audit_action,'vehicles',v_after.id,v_after.id,v_actor,v_actor_email,v_before_state,v_after_state,
    jsonb_build_object('source','pdc_email_ai_hidden_new_vehicle_restore_v1','tombstone_id',v_tombstone.tombstone_id,'backend_record_id',v_backend.id,
      'visible_on_board',false,'new_vehicle_status','pending'));
  UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;
  UPDATE public.navision_backend_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;
  PERFORM public.workshop_bump_revision();
  RETURN v_response;
END
$$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_restore_hidden_new_vehicle_v1(uuid,text,uuid,uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pdc_email_ai_restore_hidden_new_vehicle_v1(uuid,text,uuid,uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.pdc_pilbara_service_preview_v1(
  p_rows jsonb,
  p_source_hash text,
  p_idempotency_key text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
SET lock_timeout TO '5s'
SET statement_timeout TO '60s'
AS $$
DECLARE
  v_actor uuid:=auth.uid();
  v_actor_label text:=lower(btrim(coalesce(auth.jwt()->>'email','')))||':viewer:'||coalesce(auth.uid()::text,'missing');
  v_source_hash text:=lower(btrim(coalesce(p_source_hash,''));
  v_idem text:=btrim(coalesce(p_idempotency_key,''));
  v_request_hash text;
  v_prior public.pdc_pilbara_service_import_batches%rowtype;
  v_batch_id uuid:=gen_random_uuid();
  v_item record;
  v_row jsonb;
  v_raw jsonb;
  v_stock text;
  v_ro text;
  v_descr text;
  v_parts_raw text;
  v_parts_sem text;
  v_provenance text;
  v_identity_hash text;
  v_semantic_hash text;
  v_prior_semantic text;
  v_source_hours numeric;
  v_effective_hours numeric;
  v_line_no integer;
  v_source_order integer;
  v_backend_count integer;
  v_backend_id uuid;
  v_vehicle_id uuid;
  v_vehicle_count integer;
  v_decision text;
  v_reason text;
  v_seen jsonb:='{}'::jsonb;
  v_outcomes jsonb:='[]'::jsonb;
  v_response jsonb;
  v_source_count integer:=0;
  v_accepted_count integer:=0;
  v_insert_count integer:=0;
  v_unchanged_count integer:=0;
  v_duplicate_count integer:=0;
  v_quarantine_count integer:=0;
  v_conflict_count integer:=0;
  v_matched_stocks text[]:='{}'::text[];
  v_unmatched_stocks text[]:='{}'::text[];
  v_ambiguous_stocks text[]:='{}'::text[];
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'code','wrong_environment'); END IF;
  IF NOT public.pdc_email_ai_runtime_authorized_v1() THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
  IF jsonb_typeof(p_rows) IS DISTINCT FROM 'array' OR jsonb_array_length(p_rows) NOT BETWEEN 1 AND 1000000
     OR v_source_hash !~ '^[a-f0-9]{64}$' OR length(v_idem) NOT BETWEEN 12 AND 160 THEN RETURN jsonb_build_object('ok',false,'code','invalid_source_contract'); END IF;
  v_request_hash:=encode(extensions.digest(convert_to(p_rows::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pilbara_service_open_jobcards_v1:preview:'||v_idem,0));
  SELECT * INTO v_prior FROM public.pdc_pilbara_service_import_batches b WHERE b.importer_version='pilbara_service_open_jobcards_v1' AND b.idempotency_key=v_idem;
  IF FOUND THEN IF v_prior.request_hash<>v_request_hash THEN RETURN jsonb_build_object('ok',false,'code','idempotency_conflict'); END IF; RETURN v_prior.response||jsonb_build_object('code','preview_replay','replay',true); END IF;
  SELECT * INTO v_prior FROM public.pdc_pilbara_service_import_batches b WHERE b.importer_version='pilbara_service_open_jobcards_v1' AND b.source_hash=v_source_hash AND b.batch_kind='preview';
  IF FOUND THEN IF v_prior.request_hash<>v_request_hash THEN RETURN jsonb_build_object('ok',false,'code','source_hash_payload_conflict'); END IF; RETURN v_prior.response||jsonb_build_object('code','preview_replay','replay',true); END IF;
  FOR v_item IN SELECT value AS row_value,ordinality::integer AS ordinality FROM jsonb_array_elements(p_rows) WITH ORDINALITY LOOP
    v_source_count:=v_source_count+1;
    v_row:=v_item.row_value;
    v_raw:=CASE WHEN jsonb_typeof(v_row->'raw_row')='object' THEN v_row->'raw_row' WHEN jsonb_typeof(v_row)='object' THEN v_row ELSE jsonb_build_object('raw_value',v_row) END;
    v_source_order:=v_item.ordinality;
    v_stock:=btrim(coalesce(v_row->>'stock_number',''));
    v_ro:=upper(btrim(coalesce(v_row->>'repair_order_number','')));
    v_descr:=regexp_replace(btrim(coalesce(v_row->>'operation_description','')),'\s+',' ','g');
    v_parts_raw:=btrim(coalesce(v_row->>'parts_on_backorder_raw',''));
    v_line_no:=NULL;v_source_hours:=NULL;v_effective_hours:=NULL;v_provenance:='';v_parts_sem:='';v_identity_hash:=NULL;v_semantic_hash:=NULL;v_prior_semantic:=NULL;
    v_backend_id:=NULL;v_vehicle_id:=NULL;v_backend_count:=0;v_vehicle_count:=0;v_decision:='quarantine';v_reason:='invalid_row';
    IF jsonb_typeof(v_row) IS DISTINCT FROM 'object' OR v_stock='' OR length(v_stock)>80 OR v_ro='' OR length(v_ro)>80 OR v_descr='' OR length(v_descr)>1000 OR coalesce(v_row->>'original_line_number','') !~ '^[0-9]+$' THEN
      v_reason:='invalid_natural_identity';v_quarantine_count:=v_quarantine_count+1;
    ELSE
      v_line_no:=(v_row->>'original_line_number')::integer;
      IF v_line_no<1 THEN v_reason:='invalid_line_number';v_quarantine_count:=v_quarantine_count+1;
      ELSIF v_row ? 'source_estimated_hours' AND v_row->'source_estimated_hours' IS NOT NULL AND btrim(coalesce(v_row->>'source_estimated_hours',''))<>'' THEN
        IF btrim(v_row->>'source_estimated_hours') !~ '^[0-9]+([.][0-9]{1,2})?$' OR (v_row->>'source_estimated_hours')::numeric NOT BETWEEN 0 AND 999.99 THEN
          v_reason:='invalid_source_hours';v_quarantine_count:=v_quarantine_count+1;
        ELSE v_source_hours:=(v_row->>'source_estimated_hours')::numeric;v_effective_hours:=v_source_hours;v_provenance:='source_explicit'; END IF;
      ELSE
        IF lower(regexp_replace(v_descr,'[^a-z0-9]+','','g')) IN ('predelivery','predeliverycommercial','vehiclepredelivery') THEN v_effective_hours:=1.0;v_provenance:='pre_delivery_default_1_0';
        ELSIF coalesce(v_row->>'hours_provenance','')='ai_estimated' AND btrim(coalesce(v_row->>'effective_estimated_hours','')) ~ '^[0-9]+([.][0-9]{1,2})?$' AND (v_row->>'effective_estimated_hours')::numeric BETWEEN 0 AND 999.99 THEN
          v_effective_hours:=(v_row->>'effective_estimated_hours')::numeric;v_provenance:='ai_estimated';
        ELSE v_provenance:='source_blank';v_reason:='missing_hours';v_quarantine_count:=v_quarantine_count+1; END IF;
      END IF;
      IF v_effective_hours IS NOT NULL THEN
        v_parts_sem:=CASE lower(v_parts_raw) WHEN 'yes' THEN 'explicitly_backordered' WHEN 'no' THEN 'not_backordered' ELSE 'review' END;
        v_identity_hash:=public.pdc_pilbara_service_operation_identity_hash_v2(v_stock,v_ro,v_line_no,v_descr);
        v_semantic_hash:=encode(extensions.digest(convert_to(concat_ws(chr(31),v_identity_hash,coalesce(v_source_hours::text,''),v_effective_hours::text,v_provenance,v_parts_raw,v_parts_sem,'Review'),'UTF8'),'sha256'),'hex');
        IF v_seen ? v_identity_hash THEN
          IF v_seen->>v_identity_hash=v_semantic_hash THEN v_decision:='duplicate';v_reason:='exact_duplicate_row_ignored';v_duplicate_count:=v_duplicate_count+1;
          ELSE v_decision:='conflict';v_reason:='duplicate_operation_identity_conflict';v_conflict_count:=v_conflict_count+1; END IF;
        ELSE
          v_seen:=v_seen||jsonb_build_object(v_identity_hash,v_semantic_hash);
          SELECT count(*),min(b.id::text)::uuid INTO v_backend_count,v_backend_id FROM public.navision_backend_records b WHERE b.source_system='microsoft_navision' AND b.dealer_code='37047' AND b.is_current AND b.record_status='current' AND btrim(coalesce(b.normalized_data->>'batch',b.normalized_data->>'stock',''))=v_stock;
          IF v_backend_count=0 THEN v_decision:='quarantine';v_reason:='no_exact_current_navision_record';v_quarantine_count:=v_quarantine_count+1;IF NOT v_stock=ANY(v_unmatched_stocks) THEN v_unmatched_stocks:=array_append(v_unmatched_stocks,v_stock);END IF;
          ELSIF v_backend_count<>1 THEN v_decision:='conflict';v_reason:='ambiguous_current_navision_identity';v_conflict_count:=v_conflict_count+1;IF NOT v_stock=ANY(v_ambiguous_stocks) THEN v_ambiguous_stocks:=array_append(v_ambiguous_stocks,v_stock);END IF;
          ELSE
            SELECT b.canonical_vehicle_id INTO v_vehicle_id FROM public.navision_backend_records b WHERE b.id=v_backend_id;
            IF v_vehicle_id IS NULL THEN v_decision:='quarantine';v_reason:='navision_vehicle_not_activated';v_quarantine_count:=v_quarantine_count+1;IF NOT v_stock=ANY(v_unmatched_stocks) THEN v_unmatched_stocks:=array_append(v_unmatched_stocks,v_stock);END IF;
            ELSE
              SELECT count(*) INTO v_vehicle_count FROM public.vehicles v WHERE v.id=v_vehicle_id AND v.deleted_at IS NULL AND v.lifecycle_state::text='active' AND v.stock_number_normalized=v_stock;
              IF v_vehicle_count<>1 THEN v_decision:='quarantine';v_reason:='canonical_vehicle_not_active_for_import';v_quarantine_count:=v_quarantine_count+1;IF NOT v_stock=ANY(v_unmatched_stocks) THEN v_unmatched_stocks:=array_append(v_unmatched_stocks,v_stock);END IF;
              ELSE
                IF NOT v_stock=ANY(v_matched_stocks) THEN v_matched_stocks:=array_append(v_matched_stocks,v_stock);END IF;
                SELECT o.semantic_hash INTO v_prior_semantic FROM public.pdc_pilbara_service_operations o WHERE o.importer_version='pilbara_service_open_jobcards_v1' AND public.pdc_pilbara_service_operation_identity_hash_v2(o.stock_number,o.repair_order_number,o.original_line_number,o.operation_description)=v_identity_hash;
                IF NOT FOUND THEN v_decision:='insert';v_reason:='new_operation';v_insert_count:=v_insert_count+1;v_accepted_count:=v_accepted_count+1;
                ELSIF v_prior_semantic=v_semantic_hash THEN v_decision:='unchanged';v_reason:='same_semantic_hash';v_unchanged_count:=v_unchanged_count+1;v_accepted_count:=v_accepted_count+1;
                ELSE v_decision:='conflict';v_reason:='semantic_identity_changed_requires_review';v_conflict_count:=v_conflict_count+1; END IF;
              END IF;
            END IF;
          END IF;
        END IF;
      END IF;
    END IF;
    v_outcomes:=v_outcomes||jsonb_build_array(jsonb_build_object('source_order',v_source_order,'stock_number',nullif(v_stock,''),'repair_order_number',nullif(v_ro,''),'original_line_number',v_line_no,'backend_record_id',v_backend_id,'vehicle_id',v_vehicle_id,'operation_identity_hash',v_identity_hash,'semantic_hash',v_semantic_hash,'normalized_payload',CASE WHEN v_identity_hash IS NULL THEN NULL ELSE jsonb_build_object('importer_version','pilbara_service_open_jobcards_v1','stock_number',v_stock,'repair_order_number',v_ro,'original_line_number',v_line_no,'source_order',v_source_order,'operation_description',v_descr,'source_estimated_hours',v_source_hours,'effective_estimated_hours',v_effective_hours,'hours_provenance',v_provenance,'parts_on_backorder_raw',v_parts_raw,'parts_semantics',v_parts_sem,'classification','Review','operation_identity_hash',v_identity_hash,'semantic_hash',v_semantic_hash) END,'raw_row',v_raw,'decision',v_decision,'reason',v_reason));
  END LOOP;
  v_response:=jsonb_build_object('ok',true,'code','preview_created','preview_batch_id',v_batch_id,'importer_version','pilbara_service_open_jobcards_v1','source_hash',v_source_hash,'source_rows',v_source_count,'accepted_lines',v_accepted_count,'matched',jsonb_build_object('stocks',cardinality(v_matched_stocks),'matched_stock_numbers',to_jsonb(v_matched_stocks)),'unmatched',jsonb_build_object('stocks',cardinality(v_unmatched_stocks),'unmatched_stock_numbers',to_jsonb(v_unmatched_stocks)),'ambiguous',jsonb_build_object('stocks',cardinality(v_ambiguous_stocks),'ambiguous_stock_numbers',to_jsonb(v_ambiguous_stocks)),'operations',jsonb_build_object('insert',v_insert_count,'update',0,'unchanged',v_unchanged_count,'duplicate_ignored',v_duplicate_count,'quarantine',v_quarantine_count,'conflict',v_conflict_count),'apply_allowed',v_accepted_count>0 AND v_conflict_count=0,'partial_batch_policy','apply_exact_active_canonical_matches_and_hold_only_unresolved_rows');
  INSERT INTO public.pdc_pilbara_service_import_batches(batch_id,importer_version,source_hash,request_hash,idempotency_key,batch_kind,source_row_count,accepted_line_count,quarantined_line_count,matched_stock_count,unmatched_stock_count,ambiguous_stock_count,insert_count,update_count,unchanged_count,conflict_count,response,created_by,created_actor) VALUES(v_batch_id,'pilbara_service_open_jobcards_v1',v_source_hash,v_request_hash,v_idem,'preview',v_source_count,v_accepted_count,v_quarantine_count,cardinality(v_matched_stocks),cardinality(v_unmatched_stocks),cardinality(v_ambiguous_stocks),v_insert_count,0,v_unchanged_count,v_conflict_count,v_response,v_actor,v_actor_label);
  FOR v_item IN SELECT value AS row_value FROM jsonb_array_elements(v_outcomes) LOOP v_row:=v_item.row_value;INSERT INTO public.pdc_pilbara_service_import_rows(batch_id,importer_version,source_order,stock_number,repair_order_number,original_line_number,backend_record_id,semantic_hash,normalized_payload,raw_row,decision,reason,vehicle_id) VALUES(v_batch_id,'pilbara_service_open_jobcards_v1',(v_row->>'source_order')::integer,v_row->>'stock_number',v_row->>'repair_order_number',CASE WHEN v_row->>'original_line_number' IS NULL THEN NULL ELSE (v_row->>'original_line_number')::integer END,CASE WHEN v_row->>'backend_record_id' IS NULL THEN NULL ELSE (v_row->>'backend_record_id')::uuid END,v_row->>'semantic_hash',v_row->'normalized_payload',coalesce(v_row->'raw_row','{}'::jsonb),v_row->>'decision',v_row->>'reason',CASE WHEN v_row->>'vehicle_id' IS NULL THEN NULL ELSE (v_row->>'vehicle_id')::uuid END);END LOOP;
  INSERT INTO public.pdc_pilbara_service_import_receipts(batch_id,importer_version,source_hash,receipt_kind,outcome,created_by,created_actor) VALUES(v_batch_id,'pilbara_service_open_jobcards_v1',v_source_hash,CASE WHEN (v_response->>'apply_allowed')::boolean THEN 'preview' ELSE 'blocked' END,v_response,v_actor,v_actor_label);
  RETURN v_response;
END
$$;
REVOKE ALL ON FUNCTION public.pdc_pilbara_service_preview_v1(jsonb,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pdc_pilbara_service_preview_v1(jsonb,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.pdc_pilbara_service_apply_v1(p_preview_batch_id uuid,p_source_hash text,p_idempotency_key text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions'
SET lock_timeout TO '5s'
SET statement_timeout TO '60s'
AS $$
DECLARE
  v_actor uuid:=auth.uid();v_actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));v_actor_label text:=v_actor_email||':viewer:'||coalesce(v_actor::text,'missing');
  v_source_hash text:=lower(btrim(coalesce(p_source_hash,'')));v_idem text:=btrim(coalesce(p_idempotency_key,''));v_request_hash text;v_preview public.pdc_pilbara_service_import_batches%rowtype;v_prior public.pdc_pilbara_service_import_batches%rowtype;v_apply_batch uuid:=gen_random_uuid();v_row public.pdc_pilbara_service_import_rows%rowtype;v_op public.pdc_pilbara_service_operations%rowtype;v_vehicle_id uuid;v_first_ro text;v_operation_id uuid;v_identity_hash text;v_response jsonb;
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE OR current_setting('app.environment',true)='production' OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'code','wrong_environment');END IF;
  IF NOT public.pdc_email_ai_runtime_authorized_v1() THEN RETURN jsonb_build_object('ok',false,'code','not_authorized');END IF;
  IF p_preview_batch_id IS NULL OR v_source_hash !~ '^[a-f0-9]{64}$' OR length(v_idem) NOT BETWEEN 12 AND 160 THEN RETURN jsonb_build_object('ok',false,'code','invalid_apply_request');END IF;
  SELECT * INTO v_preview FROM public.pdc_pilbara_service_import_batches b WHERE b.batch_id=p_preview_batch_id AND b.importer_version='pilbara_service_open_jobcards_v1' AND b.batch_kind='preview' FOR SHARE;
  IF NOT FOUND OR v_preview.source_hash<>v_source_hash OR NOT coalesce((v_preview.response->>'apply_allowed')::boolean,false) THEN RETURN jsonb_build_object('ok',false,'code','apply_not_eligible');END IF;
  v_request_hash:=encode(extensions.digest(convert_to(jsonb_build_object('contract','pdc_pilbara_service_apply_v1_dynamic_20260910','preview_batch_id',p_preview_batch_id,'source_hash',v_source_hash)::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pilbara_service_open_jobcards_v1:apply:'||v_source_hash,0));
  SELECT * INTO v_prior FROM public.pdc_pilbara_service_import_batches b WHERE b.importer_version='pilbara_service_open_jobcards_v1' AND b.source_hash=v_source_hash AND b.batch_kind='apply';
  IF FOUND THEN IF v_prior.request_hash<>v_request_hash THEN RETURN jsonb_build_object('ok',false,'code','source_apply_conflict');END IF;INSERT INTO public.pdc_pilbara_service_import_receipts(batch_id,importer_version,source_hash,receipt_kind,outcome,created_by,created_actor) VALUES(v_prior.batch_id,'pilbara_service_open_jobcards_v1',v_source_hash,'replay',v_prior.response||jsonb_build_object('code','apply_replay','replay',true),v_actor,v_actor_label);RETURN v_prior.response||jsonb_build_object('code','apply_replay','replay',true);END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
  IF EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows r0 LEFT JOIN public.navision_backend_records b ON b.id=r0.backend_record_id LEFT JOIN public.vehicles v ON v.id=r0.vehicle_id WHERE r0.batch_id=v_preview.batch_id AND r0.decision IN('insert','unchanged') AND (b.id IS NULL OR NOT b.is_current OR b.record_status<>'current' OR b.source_system<>'microsoft_navision' OR b.dealer_code<>'37047' OR b.canonical_vehicle_id IS DISTINCT FROM r0.vehicle_id OR btrim(coalesce(b.normalized_data->>'batch',b.normalized_data->>'stock','')) IS DISTINCT FROM btrim(r0.stock_number) OR v.id IS NULL OR v.deleted_at IS NOT NULL OR v.lifecycle_state::text<>'active' OR v.stock_number_normalized IS DISTINCT FROM btrim(r0.stock_number) OR (SELECT count(*) FROM public.navision_backend_records x WHERE x.source_system='microsoft_navision' AND x.dealer_code='37047' AND x.is_current AND x.record_status='current' AND btrim(coalesce(x.normalized_data->>'batch',x.normalized_data->>'stock',''))=btrim(r0.stock_number))<>1)) THEN RETURN jsonb_build_object('ok',false,'code','apply_cardinality_changed');END IF;
  IF EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows r0 WHERE r0.batch_id=v_preview.batch_id AND r0.decision='insert' AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.importer_version='pilbara_service_open_jobcards_v1' AND public.pdc_pilbara_service_operation_identity_hash_v2(o.stock_number,o.repair_order_number,o.original_line_number,o.operation_description)=r0.normalized_payload->>'operation_identity_hash')) OR EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows r0 WHERE r0.batch_id=v_preview.batch_id AND r0.decision='unchanged' AND NOT EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.importer_version='pilbara_service_open_jobcards_v1' AND public.pdc_pilbara_service_operation_identity_hash_v2(o.stock_number,o.repair_order_number,o.original_line_number,o.operation_description)=r0.normalized_payload->>'operation_identity_hash' AND o.semantic_hash=r0.semantic_hash)) THEN RETURN jsonb_build_object('ok',false,'code','operation_state_changed_after_preview');END IF;
  v_response:=jsonb_build_object('ok',true,'code','applied','replay',false,'apply_batch_id',v_apply_batch,'source_hash',v_source_hash,'insert',v_preview.insert_count,'update',0,'unchanged',v_preview.unchanged_count,'duplicate_ignored',coalesce((v_preview.response->'operations'->>'duplicate_ignored')::integer,0),'bookings_created',0,'completions_created',0,'atomic',true);
  INSERT INTO public.pdc_pilbara_service_import_batches(batch_id,importer_version,source_hash,request_hash,idempotency_key,batch_kind,source_row_count,accepted_line_count,quarantined_line_count,matched_stock_count,unmatched_stock_count,ambiguous_stock_count,insert_count,update_count,unchanged_count,conflict_count,response,created_by,created_actor) VALUES(v_apply_batch,'pilbara_service_open_jobcards_v1',v_source_hash,v_request_hash,v_idem,'apply',v_preview.source_row_count,v_preview.accepted_line_count,v_preview.quarantined_line_count,v_preview.matched_stock_count,v_preview.unmatched_stock_count,v_preview.ambiguous_stock_count,v_preview.insert_count,0,v_preview.unchanged_count,v_preview.conflict_count,v_response,v_actor,v_actor_label);
  FOR v_row IN SELECT * FROM public.pdc_pilbara_service_import_rows r WHERE r.batch_id=v_preview.batch_id AND r.decision IN('insert','unchanged') ORDER BY r.source_order LOOP
    v_identity_hash:=v_row.normalized_payload->>'operation_identity_hash';SELECT * INTO v_op FROM public.pdc_pilbara_service_operations x WHERE x.importer_version='pilbara_service_open_jobcards_v1' AND public.pdc_pilbara_service_operation_identity_hash_v2(x.stock_number,x.repair_order_number,x.original_line_number,x.operation_description)=v_identity_hash FOR SHARE;
    IF v_row.decision='insert' THEN IF FOUND THEN RAISE EXCEPTION 'operation state changed after preview' USING ERRCODE='40001';END IF;INSERT INTO public.pdc_pilbara_service_operations(importer_version,stock_number,repair_order_number,original_line_number,source_order,vehicle_id,operation_description,source_estimated_hours,effective_estimated_hours,hours_provenance,parts_on_backorder_raw,parts_semantics,classification,semantic_hash,raw_evidence_id) VALUES('pilbara_service_open_jobcards_v1',v_row.stock_number,v_row.repair_order_number,v_row.original_line_number,v_row.source_order,v_row.vehicle_id,v_row.normalized_payload->>'operation_description',CASE WHEN v_row.normalized_payload->>'source_estimated_hours' IS NULL THEN NULL ELSE (v_row.normalized_payload->>'source_estimated_hours')::numeric END,(v_row.normalized_payload->>'effective_estimated_hours')::numeric,v_row.normalized_payload->>'hours_provenance',coalesce(v_row.normalized_payload->>'parts_on_backorder_raw',''),v_row.normalized_payload->>'parts_semantics','Review',v_row.semantic_hash,v_row.evidence_id) RETURNING operation_id INTO v_operation_id;INSERT INTO public.pdc_pilbara_service_operation_history(operation_id,batch_id,event_kind,prior_semantic_hash,resulting_semantic_hash,immutable_snapshot) VALUES(v_operation_id,v_apply_batch,'insert',NULL,v_row.semantic_hash,v_row.normalized_payload);
    ELSE IF NOT FOUND OR v_op.semantic_hash<>v_row.semantic_hash THEN RAISE EXCEPTION 'operation state changed after preview' USING ERRCODE='40001';END IF;v_operation_id:=v_op.operation_id;INSERT INTO public.pdc_pilbara_service_operation_history(operation_id,batch_id,event_kind,prior_semantic_hash,resulting_semantic_hash,immutable_snapshot) VALUES(v_operation_id,v_apply_batch,'unchanged',v_op.semantic_hash,v_op.semantic_hash,v_row.normalized_payload);END IF;
  END LOOP;
  FOR v_vehicle_id IN SELECT DISTINCT r0.vehicle_id FROM public.pdc_pilbara_service_import_rows r0 WHERE r0.batch_id=v_preview.batch_id AND r0.decision IN('insert','unchanged') AND r0.vehicle_id IS NOT NULL LOOP
    FOR v_op IN SELECT old.* FROM public.pdc_pilbara_service_operations old WHERE old.vehicle_id=v_vehicle_id AND NOT EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows cur WHERE cur.batch_id=v_preview.batch_id AND cur.vehicle_id=v_vehicle_id AND cur.decision IN('insert','unchanged') AND cur.normalized_payload->>'operation_identity_hash'=public.pdc_pilbara_service_operation_identity_hash_v2(old.stock_number,old.repair_order_number,old.original_line_number,old.operation_description)) LOOP INSERT INTO public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,active,version,manual_assignment_locked,created_by,updated_by) VALUES(v_vehicle_id,'source:'||v_op.operation_id::text,'source','UNALLOCATED_MAPPING_REVIEW',left(btrim(v_op.operation_description),180),v_op.effective_estimated_hours,false,1,false,v_actor,v_actor) ON CONFLICT(vehicle_id,line_key) DO UPDATE SET active=false,version=public.vehicle_workshop_line_adjustments.version+1,updated_by=v_actor,updated_at=clock_timestamp();END LOOP;
    SELECT CASE WHEN count(DISTINCT r0.repair_order_number)=1 THEN min(r0.repair_order_number) ELSE NULL END INTO v_first_ro FROM public.pdc_pilbara_service_import_rows r0 WHERE r0.batch_id=v_preview.batch_id AND r0.vehicle_id=v_vehicle_id AND r0.decision IN('insert','unchanged');
    IF EXISTS(SELECT 1 FROM public.vehicles v WHERE v.id=v_vehicle_id AND NOT v.visible_on_board) THEN INSERT INTO public.pdc_new_vehicle_reviews(vehicle_id,status,source_kind,first_job_card,received_at,approved_at,approved_by,approval_key,approval_hash,approval_receipt) VALUES(v_vehicle_id,'pending','revolution_report',v_first_ro,clock_timestamp(),NULL,NULL,NULL,NULL,NULL) ON CONFLICT(vehicle_id) DO UPDATE SET status='pending',source_kind='revolution_report',first_job_card=excluded.first_job_card,received_at=clock_timestamp(),approved_at=NULL,approved_by=NULL,approval_key=NULL,approval_hash=NULL,approval_receipt=NULL;UPDATE public.vehicles SET job_card_number=v_first_ro,version=version+1,updated_by=v_actor,updated_at=clock_timestamp() WHERE id=v_vehicle_id AND visible_on_board=false;END IF;
  END LOOP;
  INSERT INTO public.pdc_pilbara_service_import_receipts(batch_id,importer_version,source_hash,receipt_kind,outcome,created_by,created_actor) VALUES(v_apply_batch,'pilbara_service_open_jobcards_v1',v_source_hash,'apply',v_response,v_actor,v_actor_label);UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;UPDATE public.navision_backend_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;PERFORM public.workshop_bump_revision();RETURN v_response;
END
$$;
REVOKE ALL ON FUNCTION public.pdc_pilbara_service_apply_v1(uuid,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pdc_pilbara_service_apply_v1(uuid,text,text) TO authenticated;
REVOKE ALL ON TABLE public.pdc_pilbara_service_operations FROM anon, authenticated;
REVOKE ALL ON TABLE public.pdc_pilbara_service_import_rows FROM anon, authenticated;
REVOKE ALL ON TABLE public.pdc_pilbara_service_import_batches FROM anon, authenticated;
REVOKE ALL ON TABLE public.pdc_pilbara_service_import_receipts FROM anon, authenticated;