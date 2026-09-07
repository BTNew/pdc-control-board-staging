-- STAGING ONLY: dedicated Pilbara Service open-job-card import contract v1.
BEGIN;
SET LOCAL lock_timeout='30s';
SET LOCAL statement_timeout='300s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-pilbara-service-open-jobcards-v1',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres'
     OR session_user<>'postgres'
     OR current_setting('app.environment',true)='production'
     OR NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel
         WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT (version,name)::text FROM supabase_migrations.schema_migrations
         WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1)
        IS DISTINCT FROM '(20260907090000,navision_complete_vin_gate)'
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260907100000')
     OR to_regprocedure('public.reconcile_navision_delivery_734(uuid,uuid,text)') IS NULL
  THEN
    RAISE EXCEPTION 'PDC_20260907100000_STAGING_PREDECESSOR_OR_SCOPE_GUARD_FAILED' USING ERRCODE='55000';
  END IF;
END
$guard$;

CREATE TABLE public.pdc_pilbara_service_import_batches(
  batch_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  importer_version text NOT NULL CHECK(importer_version='pilbara_service_open_jobcards_v1'),
  source_hash text NOT NULL CHECK(source_hash~'^[a-f0-9]{64}$'),
  request_hash text NOT NULL CHECK(request_hash~'^[a-f0-9]{64}$'),
  idempotency_key text NOT NULL CHECK(length(btrim(idempotency_key)) BETWEEN 12 AND 160),
  batch_kind text NOT NULL CHECK(batch_kind IN('preview','apply')),
  source_row_count integer NOT NULL CHECK(source_row_count=162),
  accepted_line_count integer NOT NULL CHECK(accepted_line_count BETWEEN 0 AND 161),
  quarantined_line_count integer NOT NULL CHECK(quarantined_line_count BETWEEN 1 AND 162),
  matched_stock_count integer NOT NULL CHECK(matched_stock_count BETWEEN 0 AND 37),
  unmatched_stock_count integer NOT NULL CHECK(unmatched_stock_count BETWEEN 0 AND 37),
  ambiguous_stock_count integer NOT NULL CHECK(ambiguous_stock_count BETWEEN 0 AND 37),
  insert_count integer NOT NULL DEFAULT 0 CHECK(insert_count>=0),
  update_count integer NOT NULL DEFAULT 0 CHECK(update_count>=0),
  unchanged_count integer NOT NULL DEFAULT 0 CHECK(unchanged_count>=0),
  conflict_count integer NOT NULL DEFAULT 0 CHECK(conflict_count>=0),
  response jsonb NOT NULL CHECK(jsonb_typeof(response)='object'),
  created_by uuid,
  created_actor text NOT NULL CHECK(length(btrim(created_actor)) BETWEEN 3 AND 320),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(importer_version,idempotency_key),
  UNIQUE(importer_version,source_hash,batch_kind)
);

CREATE TABLE public.pdc_pilbara_service_import_rows(
  evidence_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id uuid NOT NULL REFERENCES public.pdc_pilbara_service_import_batches(batch_id) ON DELETE RESTRICT,
  importer_version text NOT NULL CHECK(importer_version='pilbara_service_open_jobcards_v1'),
  source_order integer NOT NULL CHECK(source_order BETWEEN 1 AND 162),
  stock_number text,
  repair_order_number text,
  original_line_number integer,
  backend_record_id uuid REFERENCES public.navision_backend_records(id) ON DELETE RESTRICT,
  semantic_hash text CHECK(semantic_hash IS NULL OR semantic_hash~'^[a-f0-9]{64}$'),
  normalized_payload jsonb CHECK(normalized_payload IS NULL OR jsonb_typeof(normalized_payload)='object'),
  raw_row jsonb NOT NULL CHECK(jsonb_typeof(raw_row)='object'),
  decision text NOT NULL CHECK(decision IN('insert','unchanged','quarantine','conflict')),
  reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 3 AND 160),
  vehicle_id uuid REFERENCES public.vehicles(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(batch_id,source_order)
);

CREATE TABLE public.pdc_pilbara_service_operations(
  operation_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  importer_version text NOT NULL CHECK(importer_version='pilbara_service_open_jobcards_v1'),
  stock_number text NOT NULL,
  repair_order_number text NOT NULL,
  original_line_number integer NOT NULL CHECK(original_line_number>0),
  source_order integer NOT NULL CHECK(source_order BETWEEN 1 AND 161),
  vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
  operation_description text NOT NULL CHECK(length(btrim(operation_description)) BETWEEN 1 AND 1000),
  source_estimated_hours numeric CHECK(source_estimated_hours IS NULL OR source_estimated_hours BETWEEN 0 AND 999.99),
  effective_estimated_hours numeric CHECK(effective_estimated_hours IS NULL OR effective_estimated_hours BETWEEN 0 AND 999.99),
  hours_provenance text NOT NULL CHECK(hours_provenance IN('source_explicit','source_blank','pre_delivery_default_1_5')),
  parts_on_backorder_raw text NOT NULL DEFAULT '',
  parts_semantics text NOT NULL CHECK(parts_semantics IN('explicitly_backordered','not_backordered','review')),
  classification text NOT NULL CHECK(classification='Review'),
  semantic_hash text NOT NULL CHECK(semantic_hash~'^[a-f0-9]{64}$'),
  raw_evidence_id uuid NOT NULL REFERENCES public.pdc_pilbara_service_import_rows(evidence_id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(importer_version,stock_number,repair_order_number,original_line_number)
);

CREATE TABLE public.pdc_pilbara_service_operation_history(
  history_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  operation_id uuid NOT NULL REFERENCES public.pdc_pilbara_service_operations(operation_id) ON DELETE RESTRICT,
  batch_id uuid NOT NULL REFERENCES public.pdc_pilbara_service_import_batches(batch_id) ON DELETE RESTRICT,
  event_kind text NOT NULL CHECK(event_kind IN('insert','unchanged','conflict')),
  prior_semantic_hash text,
  resulting_semantic_hash text NOT NULL CHECK(resulting_semantic_hash~'^[a-f0-9]{64}$'),
  immutable_snapshot jsonb NOT NULL CHECK(jsonb_typeof(immutable_snapshot)='object'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE public.pdc_pilbara_service_import_receipts(
  receipt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id uuid NOT NULL REFERENCES public.pdc_pilbara_service_import_batches(batch_id) ON DELETE RESTRICT,
  importer_version text NOT NULL CHECK(importer_version='pilbara_service_open_jobcards_v1'),
  source_hash text NOT NULL CHECK(source_hash~'^[a-f0-9]{64}$'),
  receipt_kind text NOT NULL CHECK(receipt_kind IN('preview','apply','replay','blocked')),
  outcome jsonb NOT NULL CHECK(jsonb_typeof(outcome)='object'),
  created_by uuid,
  created_actor text NOT NULL CHECK(length(btrim(created_actor)) BETWEEN 3 AND 320),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

ALTER TABLE public.pdc_pilbara_service_import_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_pilbara_service_import_batches FORCE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_pilbara_service_import_rows ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_pilbara_service_import_rows FORCE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_pilbara_service_operations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_pilbara_service_operations FORCE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_pilbara_service_operation_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_pilbara_service_operation_history FORCE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_pilbara_service_import_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_pilbara_service_import_receipts FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_pilbara_service_import_batches,public.pdc_pilbara_service_import_rows,
  public.pdc_pilbara_service_operations,public.pdc_pilbara_service_operation_history,
  public.pdc_pilbara_service_import_receipts FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.pdc_pilbara_service_reject_evidence_mutation()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,public AS $immutable$
BEGIN
  RAISE EXCEPTION 'PDC_PILBARA_SERVICE_APPEND_ONLY_EVIDENCE' USING ERRCODE='55000';
END
$immutable$;
REVOKE ALL ON FUNCTION public.pdc_pilbara_service_reject_evidence_mutation() FROM PUBLIC,anon,authenticated,service_role;

CREATE TRIGGER pdc_pilbara_service_batches_append_only BEFORE UPDATE OR DELETE ON public.pdc_pilbara_service_import_batches
FOR EACH ROW EXECUTE FUNCTION public.pdc_pilbara_service_reject_evidence_mutation();
CREATE TRIGGER pdc_pilbara_service_rows_append_only BEFORE UPDATE OR DELETE ON public.pdc_pilbara_service_import_rows
FOR EACH ROW EXECUTE FUNCTION public.pdc_pilbara_service_reject_evidence_mutation();
CREATE TRIGGER pdc_pilbara_service_operations_append_only BEFORE UPDATE OR DELETE ON public.pdc_pilbara_service_operations
FOR EACH ROW EXECUTE FUNCTION public.pdc_pilbara_service_reject_evidence_mutation();
CREATE TRIGGER pdc_pilbara_service_history_append_only BEFORE UPDATE OR DELETE ON public.pdc_pilbara_service_operation_history
FOR EACH ROW EXECUTE FUNCTION public.pdc_pilbara_service_reject_evidence_mutation();
CREATE TRIGGER pdc_pilbara_service_receipts_append_only BEFORE UPDATE OR DELETE ON public.pdc_pilbara_service_import_receipts
FOR EACH ROW EXECUTE FUNCTION public.pdc_pilbara_service_reject_evidence_mutation();

CREATE FUNCTION public.pdc_pilbara_service_preview_v1(p_rows jsonb,p_source_hash text,p_idempotency_key text)
RETURNS jsonb LANGUAGE plpgsql
SET search_path=pg_catalog,public,extensions AS $preview$
DECLARE
  v_hash text:=lower(btrim(coalesce(p_source_hash,'')));
  v_key text:=btrim(coalesce(p_idempotency_key,''));
  v_request text;
  v_authorized_payload_hash constant text:='284d241601d743123c0d07bd2a85f71cdca833b813c78558a7b77c1ad1f810b8';
  v_existing public.pdc_pilbara_service_import_batches%rowtype;
  v_batch uuid:=gen_random_uuid();
  v_row jsonb;
  v_outcomes jsonb:='[]'::jsonb;
  v_decision text;
  v_reason text;
  v_pair_count integer;
  v_navision_count integer;
  v_vehicle_count integer;
  v_backend uuid;
  v_vehicle uuid;
  v_existing_hash text;
  v_insert integer:=0;
  v_unchanged integer:=0;
  v_conflict integer:=0;
  v_quarantine integer:=0;
  v_matched_lines integer:=0;
  v_unmatched_lines integer:=0;
  v_ambiguous_lines integer:=0;
  v_matched text[]:='{}'::text[];
  v_unmatched text[]:='{}'::text[];
  v_ambiguous text[]:='{}'::text[];
  v_response jsonb;
BEGIN
  IF v_hash<>'9803905a50abcacef851a823f5d7bb708e9890a0aa4c49273e91566ea4ebf69e'
     OR length(v_key) NOT BETWEEN 12 AND 160
     OR jsonb_typeof(p_rows) IS DISTINCT FROM 'array'
     OR jsonb_array_length(p_rows)<>162 THEN
    RETURN jsonb_build_object('ok',false,'code','invalid_source_contract');
  END IF;
  v_request:=encode(extensions.digest(convert_to(p_rows::text,'UTF8'),'sha256'),'hex');
  IF v_request<>v_authorized_payload_hash THEN
    RETURN jsonb_build_object('ok',false,'code','authorized_payload_hash_mismatch');
  END IF;
  IF EXISTS(
    WITH source AS (
      SELECT value row_value,ordinality::integer source_order
      FROM jsonb_array_elements(p_rows) WITH ORDINALITY
    ), valid AS (
      SELECT * FROM source WHERE nullif(btrim(coalesce(row_value->>'stock_number','')),'') IS NOT NULL
        AND nullif(btrim(coalesce(row_value->>'repair_order_number','')),'') IS NOT NULL
        AND row_value->>'original_line_number' IS NOT NULL
    )
    SELECT 1 WHERE
      (SELECT count(*) FROM source WHERE (row_value->>'source_order')::integer=source_order)<>162
      OR (SELECT count(*) FROM valid)<>161
      OR EXISTS(SELECT 1 FROM source WHERE source_order<162 AND (
        nullif(btrim(coalesce(row_value->>'stock_number','')),'') IS NULL
        OR nullif(btrim(coalesce(row_value->>'repair_order_number','')),'') IS NULL
        OR row_value->>'original_line_number' IS NULL))
      OR (SELECT count(DISTINCT row_value->>'stock_number') FROM valid)<>37
      OR (SELECT count(DISTINCT (row_value->>'stock_number',row_value->>'repair_order_number')) FROM valid)<>37
      OR (SELECT count(DISTINCT (row_value->>'stock_number',row_value->>'repair_order_number',(row_value->>'original_line_number')::integer)) FROM valid)<>161
      OR (SELECT count(*) FROM source WHERE source_order=162
            AND coalesce(row_value->>'reason','')='invalid_blank_natural_identity'
            AND nullif(btrim(coalesce(row_value->>'stock_number','')),'') IS NULL
            AND nullif(btrim(coalesce(row_value->>'repair_order_number','')),'') IS NULL
            AND row_value->>'original_line_number' IS NULL
            AND coalesce(row_value->'raw_row'->>'Estimated labour hours','')='1,339.00')<>1
      OR EXISTS(SELECT 1 FROM valid WHERE coalesce(row_value->>'importer_version','')<>'pilbara_service_open_jobcards_v1'
        OR coalesce(row_value->>'classification','')<>'Review'
        OR (row_value-'raw_row') ?| array['Status Desc','status desc','status_desc','status']
        OR coalesce(row_value->>'semantic_hash','') IS DISTINCT FROM encode(extensions.digest(convert_to(concat_ws(chr(31),
          row_value->>'importer_version',row_value->>'stock_number',row_value->>'repair_order_number',row_value->>'original_line_number',
          row_value->>'source_order',row_value->>'operation_description',coalesce(row_value->>'source_estimated_hours',''),
          coalesce(row_value->>'effective_estimated_hours',''),row_value->>'hours_provenance',coalesce(row_value->>'parts_on_backorder_raw',''),
          row_value->>'parts_semantics',row_value->>'classification'),'UTF8'),'sha256'),'hex'))
  ) THEN
    RETURN jsonb_build_object('ok',false,'code','authorized_payload_validation_failed');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('pilbara_service_open_jobcards_v1:'||v_key,0));
  SELECT * INTO v_existing FROM public.pdc_pilbara_service_import_batches
   WHERE importer_version='pilbara_service_open_jobcards_v1' AND idempotency_key=v_key;
  IF FOUND THEN
    IF v_existing.request_hash<>v_request THEN
      RETURN jsonb_build_object('ok',false,'code','idempotency_conflict');
    END IF;
    v_response:=v_existing.response||jsonb_build_object('code','preview_replay');
    INSERT INTO public.pdc_pilbara_service_import_receipts(
      batch_id,importer_version,source_hash,receipt_kind,outcome,created_by,created_actor)
    VALUES(v_existing.batch_id,'pilbara_service_open_jobcards_v1',v_hash,'replay',v_response,NULL,'postgres:staging-management');
    RETURN v_response;
  END IF;
  SELECT * INTO v_existing FROM public.pdc_pilbara_service_import_batches
   WHERE importer_version='pilbara_service_open_jobcards_v1' AND source_hash=v_hash AND batch_kind='preview';
  IF FOUND THEN
    IF v_existing.request_hash<>v_request THEN
      RETURN jsonb_build_object('ok',false,'code','source_hash_payload_conflict');
    END IF;
    v_response:=v_existing.response||jsonb_build_object('code','preview_replay');
    INSERT INTO public.pdc_pilbara_service_import_receipts(
      batch_id,importer_version,source_hash,receipt_kind,outcome,created_by,created_actor)
    VALUES(v_existing.batch_id,'pilbara_service_open_jobcards_v1',v_hash,'replay',v_response,NULL,'postgres:staging-management');
    RETURN v_response;
  END IF;

  FOR v_row IN SELECT value FROM jsonb_array_elements(p_rows) LOOP
    v_backend:=NULL;v_vehicle:=NULL;v_existing_hash:=NULL;
    IF nullif(btrim(coalesce(v_row->>'stock_number','')),'') IS NULL
       OR nullif(btrim(coalesce(v_row->>'repair_order_number','')),'') IS NULL
       OR v_row->>'original_line_number' IS NULL THEN
      v_decision:='quarantine';v_reason:='invalid_blank_natural_identity';v_pair_count:=0;v_quarantine:=v_quarantine+1;
    ELSE
      SELECT count(DISTINCT b.id),min(b.id::text)::uuid
      INTO v_navision_count,v_backend
      FROM public.navision_backend_records b
      WHERE b.source_system='microsoft_navision' AND b.is_current AND b.record_status='current' AND b.dealer_code='37047'
        AND btrim(coalesce(b.normalized_data->>'batch',b.normalized_data->>'stock',''))=btrim(v_row->>'stock_number');
      SELECT count(DISTINCT v.id),min(v.id::text)::uuid
      INTO v_vehicle_count,v_vehicle
      FROM public.vehicles v
      WHERE v.deleted_at IS NULL AND btrim(v.stock_number)=btrim(v_row->>'stock_number');
      SELECT count(*) INTO v_pair_count
      FROM public.navision_backend_records b
      WHERE b.id=v_backend
        AND v_navision_count=1 AND v_vehicle_count<=1
        AND (b.canonical_vehicle_id IS NULL OR b.canonical_vehicle_id=v_vehicle);

      IF v_navision_count=0 THEN
        v_decision:='quarantine';v_reason:='no_exact_current_navision_record';v_quarantine:=v_quarantine+1;v_unmatched_lines:=v_unmatched_lines+1;
        IF NOT (v_row->>'stock_number'=ANY(v_unmatched)) THEN v_unmatched:=array_append(v_unmatched,v_row->>'stock_number');END IF;
      ELSIF v_navision_count<>1 OR v_vehicle_count>1 OR v_pair_count<>1 THEN
        v_decision:='quarantine';v_reason:='ambiguous_or_conflicting_exact_stock_identity';v_quarantine:=v_quarantine+1;v_ambiguous_lines:=v_ambiguous_lines+1;
        IF NOT (v_row->>'stock_number'=ANY(v_ambiguous)) THEN v_ambiguous:=array_append(v_ambiguous,v_row->>'stock_number');END IF;
      ELSE
        v_matched_lines:=v_matched_lines+1;
        IF NOT (v_row->>'stock_number'=ANY(v_matched)) THEN v_matched:=array_append(v_matched,v_row->>'stock_number');END IF;
        SELECT semantic_hash INTO v_existing_hash FROM public.pdc_pilbara_service_operations
         WHERE importer_version='pilbara_service_open_jobcards_v1'
           AND stock_number=v_row->>'stock_number' AND repair_order_number=v_row->>'repair_order_number'
           AND original_line_number=(v_row->>'original_line_number')::integer;
        IF NOT FOUND THEN v_decision:='insert';v_reason:='new_operation';v_insert:=v_insert+1;
        ELSIF v_existing_hash=v_row->>'semantic_hash' THEN v_decision:='unchanged';v_reason:='same_semantic_hash';v_unchanged:=v_unchanged+1;
        ELSE v_decision:='conflict';v_reason:='semantic_identity_conflict';v_conflict:=v_conflict+1;
        END IF;
      END IF;
    END IF;
    v_outcomes:=v_outcomes||jsonb_build_array(jsonb_build_object(
      'source_order',(v_row->>'source_order')::integer,'stock_number',nullif(v_row->>'stock_number',''),
      'repair_order_number',nullif(v_row->>'repair_order_number',''),'original_line_number',nullif(v_row->>'original_line_number','')::integer,
      'backend_record_id',v_backend,'semantic_hash',nullif(v_row->>'semantic_hash',''),'normalized_payload',v_row-'raw_row',
      'raw_row',coalesce(v_row->'raw_row','{}'::jsonb),'decision',v_decision,'reason',v_reason,'vehicle_id',v_vehicle));
  END LOOP;

  v_response:=jsonb_build_object('ok',true,'code','preview_created','preview_batch_id',v_batch,
    'importer_version','pilbara_service_open_jobcards_v1','source_hash',v_hash,'source_rows',162,
    'source_valid_lines',161,'source_invalid_lines',1,
    'matched',jsonb_build_object('stocks',cardinality(v_matched),'groups',cardinality(v_matched),'lines',v_matched_lines,
      'matched_stock_numbers',to_jsonb(v_matched)),
    'unmatched',jsonb_build_object('stocks',cardinality(v_unmatched),'groups',cardinality(v_unmatched),'lines',v_unmatched_lines,
      'unmatched_stock_numbers',to_jsonb(v_unmatched)),
    'ambiguous',jsonb_build_object('stocks',cardinality(v_ambiguous),'groups',cardinality(v_ambiguous),'lines',v_ambiguous_lines,
      'ambiguous_stock_numbers',to_jsonb(v_ambiguous)),
    'operations',jsonb_build_object('insert',v_insert,'update',0,'unchanged',v_unchanged,'conflict',v_conflict,'quarantine',v_quarantine),
    'standalone_vehicles_created',0,
    'apply_allowed',cardinality(v_matched)>0 AND cardinality(v_ambiguous)=0 AND v_conflict=0,
    'partial_batch_policy','apply_exact_current_dealer_matches_and_quarantine_unmatched');
  INSERT INTO public.pdc_pilbara_service_import_batches(batch_id,importer_version,source_hash,request_hash,idempotency_key,batch_kind,
    source_row_count,accepted_line_count,quarantined_line_count,matched_stock_count,unmatched_stock_count,ambiguous_stock_count,
    insert_count,update_count,unchanged_count,conflict_count,response,created_by,created_actor)
  VALUES(v_batch,'pilbara_service_open_jobcards_v1',v_hash,v_request,v_key,'preview',162,161,v_quarantine,
    cardinality(v_matched),cardinality(v_unmatched),cardinality(v_ambiguous),v_insert,0,v_unchanged,v_conflict,v_response,
    NULL,'postgres:staging-management');
  FOR v_row IN SELECT value FROM jsonb_array_elements(v_outcomes) LOOP
    INSERT INTO public.pdc_pilbara_service_import_rows(batch_id,importer_version,source_order,stock_number,repair_order_number,
      original_line_number,backend_record_id,semantic_hash,normalized_payload,raw_row,decision,reason,vehicle_id)
    VALUES(v_batch,'pilbara_service_open_jobcards_v1',(v_row->>'source_order')::integer,v_row->>'stock_number',v_row->>'repair_order_number',
      (v_row->>'original_line_number')::integer,(v_row->>'backend_record_id')::uuid,v_row->>'semantic_hash',v_row->'normalized_payload',
      v_row->'raw_row',v_row->>'decision',v_row->>'reason',(v_row->>'vehicle_id')::uuid);
  END LOOP;
  INSERT INTO public.pdc_pilbara_service_import_receipts(
    batch_id,importer_version,source_hash,receipt_kind,outcome,created_by,created_actor)
  VALUES(v_batch,'pilbara_service_open_jobcards_v1',v_hash,
    CASE WHEN (v_response->>'apply_allowed')::boolean THEN 'preview' ELSE 'blocked' END,v_response,
    NULL,'postgres:staging-management');
  RETURN v_response;
END
$preview$;
REVOKE ALL ON FUNCTION public.pdc_pilbara_service_preview_v1(jsonb,text,text) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.pdc_pilbara_service_apply_v1(p_preview_batch_id uuid,p_source_hash text,p_idempotency_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions AS $apply$
DECLARE
  v_role text:=public.current_pdc_user_role()::text;
  v_actor uuid:=auth.uid();
  v_actor_label text:=lower(btrim(coalesce(auth.jwt()->>'email','')))||':'||coalesce(v_role,'unknown')||':'||coalesce(v_actor::text,'missing');
  v_preview public.pdc_pilbara_service_import_batches%rowtype;
  v_prior public.pdc_pilbara_service_import_batches%rowtype;
  v_batch uuid:=gen_random_uuid();
  v_backend uuid;
  v_activation jsonb;
  v_revision bigint;
  v_vehicle uuid;
  v_row public.pdc_pilbara_service_import_rows%rowtype;
  v_operation uuid;
  v_response jsonb;
  v_request_hash text;
BEGIN
  IF current_setting('app.environment',true)='production'
     OR NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel
         WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RETURN jsonb_build_object('ok',false,'code','wrong_environment');
  END IF;
  IF v_actor IS NULL OR NOT coalesce(v_role='viewer',false)
     OR NOT EXISTS(SELECT 1 FROM public.pdc_email_ai_successor_runtime_identities i
       WHERE i.auth_user_id=v_actor AND i.normalized_email=lower(btrim(coalesce(auth.jwt()->>'email','')))
         AND i.environment='staging' AND i.identity_purpose='pdc_email_ai_transaction_successor'
         AND i.active AND i.revoked_at IS NULL)
     OR NOT EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers w
       WHERE w.user_id=v_actor AND w.active AND w.revoked_at IS NULL) THEN
    RETURN jsonb_build_object('ok',false,'code','unauthorized');
  END IF;
  IF length(btrim(coalesce(p_idempotency_key,''))) NOT BETWEEN 12 AND 160 THEN
    RETURN jsonb_build_object('ok',false,'code','invalid_idempotency_key');
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pilbara_service_open_jobcards_v1:apply:'||lower(btrim(coalesce(p_source_hash,''))),0));
  SELECT * INTO v_preview FROM public.pdc_pilbara_service_import_batches
   WHERE batch_id=p_preview_batch_id AND batch_kind='preview' FOR SHARE;
  IF NOT FOUND OR v_preview.source_hash<>lower(btrim(coalesce(p_source_hash,'')))
     OR NOT coalesce((v_preview.response->>'apply_allowed')::boolean,false)
     OR (v_preview.response->'matched'->>'stocks')::integer<>21
     OR (v_preview.response->'matched'->>'lines')::integer<>122
     OR (v_preview.response->'unmatched'->>'stocks')::integer<>16
     OR (v_preview.response->'unmatched'->>'lines')::integer<>39
     OR (v_preview.response->'ambiguous'->>'stocks')::integer<>0
     OR v_preview.quarantined_line_count<>40
     OR v_preview.conflict_count<>0 THEN
    RETURN jsonb_build_object('ok',false,'code','apply_not_eligible');
  END IF;
  LOCK TABLE public.navision_backend_records IN SHARE ROW EXCLUSIVE MODE;
  LOCK TABLE public.vehicles IN SHARE ROW EXCLUSIVE MODE;
  PERFORM pg_advisory_xact_lock(hashtextextended('navision-backend-store',0));
  PERFORM 1 FROM public.navision_backend_records b
    JOIN (SELECT DISTINCT backend_record_id FROM public.pdc_pilbara_service_import_rows
      WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged')) r ON r.backend_record_id=b.id
    FOR UPDATE OF b;
  PERFORM 1 FROM public.vehicles v
    JOIN (SELECT DISTINCT stock_number FROM public.pdc_pilbara_service_import_rows
      WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged')) r ON btrim(v.stock_number)=btrim(r.stock_number)
    WHERE v.deleted_at IS NULL FOR SHARE OF v;
  v_request_hash:=encode(extensions.digest(convert_to(
    jsonb_build_object('preview_batch_id',p_preview_batch_id,'source_hash',v_preview.source_hash,
      'idempotency_key',btrim(p_idempotency_key),'importer_version','pilbara_service_open_jobcards_v1')::text,'UTF8'),'sha256'),'hex');
  SELECT * INTO v_prior FROM public.pdc_pilbara_service_import_batches
   WHERE importer_version='pilbara_service_open_jobcards_v1' AND batch_kind='apply' AND source_hash=v_preview.source_hash;
  IF FOUND THEN
    IF v_prior.request_hash<>v_request_hash THEN RETURN jsonb_build_object('ok',false,'code','idempotency_conflict'); END IF;
    v_response:=v_prior.response||jsonb_build_object('code','apply_replay');
    INSERT INTO public.pdc_pilbara_service_import_receipts(
      batch_id,importer_version,source_hash,receipt_kind,outcome,created_by,created_actor)
    VALUES(v_prior.batch_id,'pilbara_service_open_jobcards_v1',v_preview.source_hash,'replay',v_response,v_actor,v_actor_label);
    RETURN v_response;
  END IF;
  IF EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows r
    LEFT JOIN public.navision_backend_records b ON b.id=r.backend_record_id
    WHERE r.batch_id=v_preview.batch_id AND r.decision IN('insert','unchanged') AND (
      b.id IS NULL OR NOT b.is_current OR b.record_status<>'current' OR b.source_system<>'microsoft_navision'
      OR b.dealer_code<>'37047'
      OR btrim(coalesce(b.normalized_data->>'batch',b.normalized_data->>'stock',''))<>btrim(r.stock_number)
      OR (SELECT count(*) FROM public.navision_backend_records x WHERE x.source_system='microsoft_navision'
        AND x.is_current AND x.record_status='current' AND x.dealer_code='37047'
        AND btrim(coalesce(x.normalized_data->>'batch',x.normalized_data->>'stock',''))=btrim(r.stock_number))<>1
      OR (SELECT count(*) FROM public.vehicles v WHERE v.deleted_at IS NULL
        AND btrim(v.stock_number)=btrim(r.stock_number))>1
      OR (r.vehicle_id IS NULL AND EXISTS(SELECT 1 FROM public.vehicles v
        WHERE v.deleted_at IS NULL AND btrim(v.stock_number)=btrim(r.stock_number)))
      OR (r.vehicle_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.vehicles v
        WHERE v.deleted_at IS NULL AND v.id=r.vehicle_id AND btrim(v.stock_number)=btrim(r.stock_number)))
      OR EXISTS(SELECT 1 FROM public.vehicles v
        WHERE v.deleted_at IS NULL AND btrim(v.stock_number)=btrim(r.stock_number)
          AND NOT (b.canonical_vehicle_id IS NULL OR b.canonical_vehicle_id=v.id))
    )) THEN
    RETURN jsonb_build_object('ok',false,'code','apply_cardinality_changed');
  END IF;
  IF EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows r JOIN public.pdc_pilbara_service_operations o
    ON o.importer_version=r.importer_version AND o.stock_number=r.stock_number AND o.repair_order_number=r.repair_order_number
      AND o.original_line_number=r.original_line_number
    WHERE r.batch_id=v_preview.batch_id AND o.semantic_hash<>r.semantic_hash) THEN
    RETURN jsonb_build_object('ok',false,'code','semantic_identity_conflict');
  END IF;

  FOR v_backend IN SELECT DISTINCT backend_record_id FROM public.pdc_pilbara_service_import_rows
    WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged') ORDER BY backend_record_id
  LOOP
    SELECT revision INTO v_revision FROM public.navision_backend_revision WHERE singleton;
    v_activation:=public.activate_navision_backend_record(
      'pilbara-service-v1-'||substr(v_preview.source_hash,1,24)||'-'||substr(v_backend::text,1,8),
      v_backend,v_revision,'approved_email_build');
    IF NOT coalesce((v_activation->>'ok')::boolean,false) THEN
      RAISE EXCEPTION 'PDC_PILBARA_CONTROLLED_ACTIVATION_FAILED:%',v_activation USING ERRCODE='55000';
    END IF;
    SELECT canonical_vehicle_id INTO v_vehicle FROM public.navision_backend_records WHERE id=v_backend;
    IF v_vehicle IS NULL OR NOT EXISTS(SELECT 1 FROM public.vehicles v JOIN public.navision_backend_records b ON b.id=v_backend
      WHERE v.id=v_vehicle AND v.deleted_at IS NULL AND b.canonical_vehicle_id=v.id
        AND btrim(v.stock_number)=btrim(coalesce(b.normalized_data->>'batch',b.normalized_data->>'stock',''))) THEN
      RAISE EXCEPTION 'PDC_PILBARA_CONTROLLED_ACTIVATION_DID_NOT_LINK:%',v_backend USING ERRCODE='55000';
    END IF;
  END LOOP;

  v_response:=jsonb_build_object('ok',true,'code','applied','apply_batch_id',v_batch,
    'source_hash',v_preview.source_hash,'insert',v_preview.insert_count,'update',0,
    'unchanged',v_preview.unchanged_count,'quarantine',v_preview.quarantined_line_count,
    'matched_stock_numbers',v_preview.response->'matched'->'matched_stock_numbers',
    'unmatched_stock_numbers',v_preview.response->'unmatched'->'unmatched_stock_numbers',
    'standalone_vehicles_created',0,'identity_authority','exact_current_navision_controlled_activation',
    'activation_source','approved_email_build','atomic',true,'service_forbidden_vehicle_fields_changed',0);
  INSERT INTO public.pdc_pilbara_service_import_batches(batch_id,importer_version,source_hash,request_hash,idempotency_key,batch_kind,
    source_row_count,accepted_line_count,quarantined_line_count,matched_stock_count,unmatched_stock_count,ambiguous_stock_count,
    insert_count,update_count,unchanged_count,conflict_count,response,created_by,created_actor)
  VALUES(v_batch,'pilbara_service_open_jobcards_v1',v_preview.source_hash,v_request_hash,btrim(p_idempotency_key),'apply',162,
    (v_preview.response->'matched'->>'lines')::integer,v_preview.quarantined_line_count,
    (v_preview.response->'matched'->>'stocks')::integer,(v_preview.response->'unmatched'->>'stocks')::integer,
    (v_preview.response->'ambiguous'->>'stocks')::integer,v_preview.insert_count,0,v_preview.unchanged_count,0,v_response,
    v_actor,v_actor_label);
  FOR v_row IN SELECT * FROM public.pdc_pilbara_service_import_rows
    WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged') ORDER BY source_order
  LOOP
    SELECT canonical_vehicle_id INTO v_vehicle FROM public.navision_backend_records WHERE id=v_row.backend_record_id;
    SELECT operation_id INTO v_operation FROM public.pdc_pilbara_service_operations
     WHERE importer_version=v_row.importer_version AND stock_number=v_row.stock_number
       AND repair_order_number=v_row.repair_order_number AND original_line_number=v_row.original_line_number;
    IF NOT FOUND THEN
      INSERT INTO public.pdc_pilbara_service_operations(importer_version,stock_number,repair_order_number,original_line_number,source_order,
        vehicle_id,operation_description,source_estimated_hours,effective_estimated_hours,hours_provenance,parts_on_backorder_raw,
        parts_semantics,classification,semantic_hash,raw_evidence_id)
      VALUES('pilbara_service_open_jobcards_v1',v_row.stock_number,v_row.repair_order_number,v_row.original_line_number,v_row.source_order,
        v_vehicle,v_row.normalized_payload->>'operation_description',(v_row.normalized_payload->>'source_estimated_hours')::numeric,
        (v_row.normalized_payload->>'effective_estimated_hours')::numeric,v_row.normalized_payload->>'hours_provenance',
        coalesce(v_row.normalized_payload->>'parts_on_backorder_raw',''),v_row.normalized_payload->>'parts_semantics','Review',
        v_row.semantic_hash,v_row.evidence_id)
      RETURNING operation_id INTO v_operation;
    END IF;
    INSERT INTO public.pdc_pilbara_service_operation_history(operation_id,batch_id,event_kind,prior_semantic_hash,resulting_semantic_hash,immutable_snapshot)
    VALUES(v_operation,v_batch,v_row.decision,CASE WHEN v_row.decision='unchanged' THEN v_row.semantic_hash END,
      v_row.semantic_hash,v_row.normalized_payload);
  END LOOP;
  UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;
  INSERT INTO public.pdc_pilbara_service_import_receipts(
    batch_id,importer_version,source_hash,receipt_kind,outcome,created_by,created_actor)
  VALUES(v_batch,'pilbara_service_open_jobcards_v1',v_preview.source_hash,'apply',v_response,v_actor,v_actor_label);
  RETURN v_response;
END
$apply$;
REVOKE ALL ON FUNCTION public.pdc_pilbara_service_apply_v1(uuid,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.pdc_pilbara_service_apply_v1(uuid,text,text) TO authenticated;

ALTER FUNCTION public.get_pdc_email_vehicle_location_snapshot() RENAME TO get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1;
REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1() FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.get_pdc_email_vehicle_location_snapshot()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $snapshot$
DECLARE v_base jsonb; v_rows jsonb;
BEGIN
  v_base:=public.get_pdc_email_vehicle_location_snapshot_pre_pilbara_service_v1();
  IF NOT coalesce((v_base->>'ok')::boolean,false) THEN RETURN v_base; END IF;
  SELECT coalesce(jsonb_agg(row_value||jsonb_build_object(
    'pilbara_service_operations',service_lines,
    'operation_lines',coalesce(row_value->'operation_lines','[]'::jsonb)||service_lines
  ) ORDER BY coalesce(row_value->>'stock_number',row_value->>'id')),'[]'::jsonb)
  INTO v_rows
  FROM jsonb_array_elements(coalesce(v_base#>'{data,vehicles}','[]'::jsonb)) row_value
  CROSS JOIN LATERAL (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'operation_line_id',o.operation_id,
      'operation_no','PD'||lpad(o.original_line_number::text,3,'0')||'-'||upper(substr(o.semantic_hash,1,8)),
      'work_key','review','job_card_number',o.repair_order_number,'description',o.operation_description,
      'estimated_hours',o.effective_estimated_hours,
      'estimated_hours_source',CASE o.hours_provenance WHEN 'pre_delivery_default_1_5' THEN 'business_rule_default'
        WHEN 'source_explicit' THEN 'job_card' ELSE 'owner_supplied_document_unknown' END,
      'source_estimated_hours',o.source_estimated_hours,'effective_estimated_hours',o.effective_estimated_hours,
      'hours_provenance',o.hours_provenance,'parts_on_backorder_raw',o.parts_on_backorder_raw,
      'parts_semantics',o.parts_semantics,'classification',o.classification,
      'source_uid','pilbara_service_open_jobcards_v1:'||o.stock_number||':'||o.repair_order_number||':'||o.original_line_number
    ) ORDER BY o.source_order),'[]'::jsonb) service_lines
    FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=(row_value->>'id')::uuid
  ) projected;
  RETURN jsonb_set(v_base,'{data,vehicles}',v_rows,true);
END
$snapshot$;
REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() TO authenticated,service_role;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
  '20260907100000','pilbara_service_open_jobcards_v1',ARRAY[
    'create dedicated preview/apply evidence, operation, history and receipt schema for Pilbara Service open job cards',
    'use exact trimmed Stock only and the controlled activate_navision_backend_record approved_email_build path',
    'retain immutable raw rows while normalized semantics exclude Status Desc and preserve Review, hours and parts provenance',
    'project dedicated Review operations through the authenticated STAGING snapshot without changing physical work state',
    'RLS forced, direct access revoked, apply scoped runtime-viewer-authorized, Production untouched'
  ]);
NOTIFY pgrst,'reload schema';
COMMIT;
