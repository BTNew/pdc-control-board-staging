-- STAGING-only Pilbara Service operation classification overlay v1.
BEGIN;
SET LOCAL lock_timeout='30s';
SET LOCAL statement_timeout='300s';
SELECT pg_advisory_xact_lock(hashtextextended('pilbara_service_operation_classifier_v1',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE v_head jsonb;
BEGIN
  SELECT jsonb_build_array(version,name) INTO v_head
  FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$'
  ORDER BY version::bigint DESC LIMIT 1;
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR v_head IS DISTINCT FROM '["20260907109000","pilbara_service_snapshot_scope_and_apply_head_repair"]'::jsonb
     OR (SELECT count(*) FROM public.pdc_pilbara_service_operations)<>122
     OR (SELECT count(*) FROM public.pdc_pilbara_service_operations WHERE importer_version='pilbara_service_open_jobcards_v1')<>122
     OR (SELECT count(*) FROM public.pdc_pilbara_service_import_rows WHERE decision='quarantine')<>40
  THEN RAISE EXCEPTION 'PDC_PILBARA_CLASSIFIER_STAGING_HEAD_OR_DATA_GUARD_FAILED' USING ERRCODE='55000';
  END IF;
END
$guard$;

CREATE TABLE public.pdc_pilbara_service_classification_batches(
  batch_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contract text NOT NULL CHECK(contract='pilbara_service_operation_classifier_v1'),
  batch_kind text NOT NULL CHECK(batch_kind IN('preview','apply','rollback')),
  source_importer_version text NOT NULL CHECK(source_importer_version='pilbara_service_open_jobcards_v1'),
  source_batch_id uuid NOT NULL REFERENCES public.pdc_pilbara_service_import_batches(batch_id) ON DELETE RESTRICT,
  classifier_version text NOT NULL CHECK(length(btrim(classifier_version)) BETWEEN 8 AND 120),
  manifest_hash text NOT NULL CHECK(manifest_hash~'^[a-f0-9]{64}$'),
  idempotency_key text NOT NULL CHECK(length(btrim(idempotency_key)) BETWEEN 12 AND 160),
  current_state_hash text NOT NULL CHECK(current_state_hash~'^[a-f0-9]{64}$'),
  manifest jsonb NOT NULL CHECK(jsonb_typeof(manifest)='object'),
  response jsonb NOT NULL CHECK(jsonb_typeof(response)='object'),
  preview_of_batch_id uuid REFERENCES public.pdc_pilbara_service_classification_batches(batch_id) ON DELETE RESTRICT,
  rollback_of_batch_id uuid REFERENCES public.pdc_pilbara_service_classification_batches(batch_id) ON DELETE RESTRICT,
  created_actor text NOT NULL CHECK(length(btrim(created_actor)) BETWEEN 3 AND 320),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(batch_kind,idempotency_key),
  CHECK((batch_kind='apply')=(preview_of_batch_id IS NOT NULL))
);
CREATE TABLE public.pdc_pilbara_service_classification_history(
  classification_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  operation_id uuid NOT NULL REFERENCES public.pdc_pilbara_service_operations(operation_id) ON DELETE RESTRICT,
  batch_id uuid NOT NULL REFERENCES public.pdc_pilbara_service_classification_batches(batch_id) ON DELETE RESTRICT,
  classification_version integer NOT NULL CHECK(classification_version>0),
  category text NOT NULL CHECK(category IN('PARTS','TINT','BUS_4X4','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET','REVIEW')),
  method text NOT NULL CHECK(method IN('deterministic_rule','ai_semantic','review')),
  confidence numeric(5,4) NOT NULL CHECK(confidence BETWEEN 0 AND 1),
  rationale text NOT NULL CHECK(length(btrim(rationale)) BETWEEN 3 AND 240),
  rule_id text,
  ruleset_version text,
  provider text,
  model text,
  model_run_id text,
  source_description_hash text NOT NULL CHECK(source_description_hash~'^[a-f0-9]{64}$'),
  source_semantic_hash text NOT NULL CHECK(source_semantic_hash~'^[a-f0-9]{64}$'),
  classifier_version text NOT NULL,
  supersedes_classification_id uuid REFERENCES public.pdc_pilbara_service_classification_history(classification_id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(operation_id,classification_version),
  UNIQUE(batch_id,operation_id)
);
CREATE TABLE public.pdc_pilbara_service_classification_current(
  operation_id uuid PRIMARY KEY REFERENCES public.pdc_pilbara_service_operations(operation_id) ON DELETE RESTRICT,
  classification_id uuid NOT NULL UNIQUE REFERENCES public.pdc_pilbara_service_classification_history(classification_id) ON DELETE RESTRICT,
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE public.pdc_pilbara_service_classification_work_controls(
  vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
  category text NOT NULL CHECK(category IN('PARTS','TINT','BUS_4X4','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET')),
  work_item_id uuid NOT NULL UNIQUE REFERENCES public.vehicle_work_items(id) ON DELETE RESTRICT,
  created_batch_id uuid NOT NULL REFERENCES public.pdc_pilbara_service_classification_batches(batch_id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(vehicle_id,category)
);

ALTER TABLE public.pdc_pilbara_service_classification_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_pilbara_service_classification_batches FORCE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_pilbara_service_classification_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_pilbara_service_classification_history FORCE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_pilbara_service_classification_current ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_pilbara_service_classification_current FORCE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_pilbara_service_classification_work_controls ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_pilbara_service_classification_work_controls FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.pdc_pilbara_service_classification_batches,
  public.pdc_pilbara_service_classification_history,
  public.pdc_pilbara_service_classification_current,
  public.pdc_pilbara_service_classification_work_controls FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.pdc_pilbara_service_classification_reject_batch_mutation_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,public AS $body$
BEGIN
  IF TG_OP='UPDATE' AND OLD.response='{}'::jsonb AND NEW.response<>'{}'::jsonb
     AND to_jsonb(NEW)-'response'=to_jsonb(OLD)-'response' THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'PDC_PILBARA_CLASSIFICATION_IMMUTABLE_BATCH' USING ERRCODE='55000';
END
$body$;
CREATE TRIGGER pdc_pilbara_service_classification_batches_immutable
BEFORE UPDATE OR DELETE ON public.pdc_pilbara_service_classification_batches
FOR EACH ROW EXECUTE FUNCTION public.pdc_pilbara_service_classification_reject_batch_mutation_v1();
REVOKE ALL ON FUNCTION public.pdc_pilbara_service_classification_reject_batch_mutation_v1() FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.pdc_pilbara_service_classification_reject_history_mutation_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,public AS $body$
BEGIN RAISE EXCEPTION 'PDC_PILBARA_CLASSIFICATION_APPEND_ONLY_HISTORY' USING ERRCODE='55000'; END
$body$;
CREATE TRIGGER pdc_pilbara_service_classification_history_append_only
BEFORE UPDATE OR DELETE ON public.pdc_pilbara_service_classification_history
FOR EACH ROW EXECUTE FUNCTION public.pdc_pilbara_service_classification_reject_history_mutation_v1();
REVOKE ALL ON FUNCTION public.pdc_pilbara_service_classification_reject_history_mutation_v1() FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.pdc_pilbara_service_classification_state_hash_v1()
RETURNS text LANGUAGE sql STABLE SET search_path=pg_catalog,public,extensions AS $body$
  SELECT encode(extensions.digest(convert_to(jsonb_build_object(
    'source',coalesce((SELECT jsonb_agg(to_jsonb(o) ORDER BY o.operation_id)
      FROM public.pdc_pilbara_service_operations o),'[]'::jsonb),
    'current',coalesce((SELECT jsonb_agg(jsonb_build_array(o.operation_id,c.classification_id) ORDER BY o.operation_id)
      FROM public.pdc_pilbara_service_operations o LEFT JOIN public.pdc_pilbara_service_classification_current c USING(operation_id)),'[]'::jsonb),
    'work',coalesce((SELECT jsonb_agg(jsonb_build_array(w.id,w.vehicle_id,w.work_key,w.required,w.completed,w.completed_by,w.completed_at,w.notes,w.updated_at) ORDER BY w.vehicle_id,w.work_key)
      FROM public.vehicle_work_items w WHERE EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.vehicle_id=w.vehicle_id)),'[]'::jsonb)
  )::text,'UTF8'),'sha256'),'hex')
$body$;
REVOKE ALL ON FUNCTION public.pdc_pilbara_service_classification_state_hash_v1() FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.pdc_pilbara_service_classification_preview_v1(p_manifest jsonb,p_manifest_hash text,p_idempotency_key text)
RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog,public,extensions AS $body$
DECLARE
  v_row jsonb; v_operation public.pdc_pilbara_service_operations%rowtype; v_current public.pdc_pilbara_service_classification_history%rowtype;
  v_batch uuid:=gen_random_uuid(); v_state text; v_actual_hash text; v_insert integer:=0; v_update integer:=0; v_unchanged integer:=0;
  v_review integer:=0; v_conflict integer:=0; v_owned_conflict integer:=0; v_response jsonb; v_existing public.pdc_pilbara_service_classification_batches%rowtype;
  v_category text; v_method text; v_confidence numeric; v_identity jsonb;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RETURN jsonb_build_object('ok',false,'code','wrong_environment');
  END IF;
  IF jsonb_typeof(p_manifest) IS DISTINCT FROM 'object' THEN
    RETURN jsonb_build_object('ok',false,'code','invalid_manifest_contract');
  END IF;
  IF (SELECT count(*) FROM jsonb_object_keys(p_manifest))<>7
     OR NOT (p_manifest ?& ARRAY['contract','classifier_version','source_importer_version','source_batch_id','source_hash','generated_by','classifications'])
     OR p_manifest->>'contract'<>'pilbara_service_operation_classifier_v1'
     OR p_manifest->>'classifier_version'<>'pilbara-service-classifier-2026-09-07.1'
     OR p_manifest->>'source_importer_version'<>'pilbara_service_open_jobcards_v1'
     OR p_manifest->>'source_batch_id'<>'ab7483a0-9b6c-4777-a7f9-9481e16023ff'
     OR p_manifest->>'source_hash'<>'9803905a50abcacef851a823f5d7bb708e9890a0aa4c49273e91566ea4ebf69e'
     OR p_manifest->'generated_by' IS DISTINCT FROM '{"model":"gpt-5.6-sol","run_id":"141","provider":"openai-codex"}'::jsonb
     OR jsonb_typeof(p_manifest->'classifications') IS DISTINCT FROM 'array'
     OR jsonb_array_length(p_manifest->'classifications')<>122
     OR (SELECT count(*) FROM public.pdc_pilbara_service_operations)<>122
     OR (SELECT count(*) FROM public.pdc_pilbara_service_operations WHERE importer_version='pilbara_service_open_jobcards_v1')<>122
     OR lower(btrim(coalesce(p_manifest_hash,'')))<>'15ddb6eecbe30d2c6d372e81c549983a4fa97d3b1e32e51f20ed53a07aebfe66'
     OR length(btrim(coalesce(p_idempotency_key,''))) NOT BETWEEN 12 AND 160 THEN
    RETURN jsonb_build_object('ok',false,'code','invalid_manifest_contract');
  END IF;
  v_actual_hash:=encode(extensions.digest(convert_to(p_manifest::text,'UTF8'),'sha256'),'hex');
  IF v_actual_hash<>lower(btrim(coalesce(p_manifest_hash,''))) THEN RETURN jsonb_build_object('ok',false,'code','manifest_hash_mismatch'); END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pilbara_service_operation_classifier_v1:preview:'||btrim(p_idempotency_key),0));
  SELECT * INTO v_existing FROM public.pdc_pilbara_service_classification_batches
   WHERE batch_kind='preview' AND idempotency_key=btrim(p_idempotency_key);
  IF FOUND THEN
    IF v_existing.manifest_hash<>v_actual_hash THEN RETURN jsonb_build_object('ok',false,'code','idempotency_conflict'); END IF;
    RETURN v_existing.response||jsonb_build_object('code','preview_replay');
  END IF;
  IF (SELECT count(DISTINCT value->'natural_identity') FROM jsonb_array_elements(p_manifest->'classifications'))<>122 THEN
    RETURN jsonb_build_object('ok',false,'code','duplicate_natural_identity');
  END IF;
  FOR v_row IN SELECT value FROM jsonb_array_elements(p_manifest->'classifications') LOOP
    IF jsonb_typeof(v_row) IS DISTINCT FROM 'object' OR (SELECT count(*) FROM jsonb_object_keys(v_row))<>12
       OR NOT v_row ?& ARRAY['natural_identity','source_semantic_hash','source_description_hash','category','method','confidence','rationale','rule_id','ruleset_version','provider','model','run_id'] THEN
      RETURN jsonb_build_object('ok',false,'code','strict_schema_failed');
    END IF;
    v_identity:=v_row->'natural_identity'; v_category:=upper(v_row->>'category'); v_method:=v_row->>'method'; v_confidence:=(v_row->>'confidence')::numeric;
    IF jsonb_typeof(v_identity) IS DISTINCT FROM 'array' OR jsonb_array_length(v_identity)<>4 OR v_identity->>0<>'pilbara_service_open_jobcards_v1'
       OR v_category NOT IN('PARTS','TINT','BUS_4X4','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET','REVIEW')
       OR v_method NOT IN('deterministic_rule','ai_semantic','review') OR v_confidence NOT BETWEEN 0 AND 1
       OR length(btrim(coalesce(v_row->>'rationale',''))) NOT BETWEEN 3 AND 240
       OR (v_category='REVIEW' AND (v_method<>'review' OR v_confidence>=0.80))
       OR (v_category<>'REVIEW' AND v_confidence<0.80)
       OR (v_method='deterministic_rule' AND (nullif(v_row->>'rule_id','') IS NULL OR nullif(v_row->>'ruleset_version','') IS NULL OR v_row->>'provider' IS NOT NULL OR v_row->>'model' IS NOT NULL OR v_row->>'run_id' IS NOT NULL))
       OR (v_method<>'deterministic_rule' AND (v_row->>'rule_id' IS NOT NULL OR v_row->>'ruleset_version' IS NOT NULL OR v_row->>'provider'<>'openai-codex' OR v_row->>'model'<>'gpt-5.6-sol' OR v_row->>'run_id'<>'141')) THEN
      RETURN jsonb_build_object('ok',false,'code','classification_contract_failed');
    END IF;
    SELECT * INTO v_operation FROM public.pdc_pilbara_service_operations o
     WHERE o.importer_version=v_identity->>0 AND o.stock_number=v_identity->>1 AND o.repair_order_number=v_identity->>2
       AND o.original_line_number=(v_identity->>3)::integer;
    IF NOT FOUND OR v_operation.semantic_hash<>v_row->>'source_semantic_hash'
       OR encode(extensions.digest(convert_to(v_operation.operation_description,'UTF8'),'sha256'),'hex')<>v_row->>'source_description_hash' THEN
      RETURN jsonb_build_object('ok',false,'code','source_binding_conflict');
    END IF;
    SELECT h.* INTO v_current FROM public.pdc_pilbara_service_classification_current c
      JOIN public.pdc_pilbara_service_classification_history h USING(classification_id) WHERE c.operation_id=v_operation.operation_id;
    IF NOT FOUND THEN v_insert:=v_insert+1;
    ELSIF v_current.category=v_category AND v_current.method=v_method AND v_current.confidence=v_confidence
      AND v_current.rationale=v_row->>'rationale' AND v_current.source_description_hash=v_row->>'source_description_hash'
      AND v_current.source_semantic_hash=v_row->>'source_semantic_hash' AND coalesce(v_current.rule_id,'')=coalesce(v_row->>'rule_id','')
      AND coalesce(v_current.ruleset_version,'')=coalesce(v_row->>'ruleset_version','') AND coalesce(v_current.provider,'')=coalesce(v_row->>'provider','')
      AND coalesce(v_current.model,'')=coalesce(v_row->>'model','') AND coalesce(v_current.model_run_id,'')=coalesce(v_row->>'run_id','')
      AND v_current.classifier_version=p_manifest->>'classifier_version'
      THEN v_unchanged:=v_unchanged+1;
    ELSE v_update:=v_update+1;
    END IF;
    IF v_category='REVIEW' THEN v_review:=v_review+1; END IF;
  END LOOP;
  SELECT count(*) INTO v_conflict FROM (
    SELECT DISTINCT o.vehicle_id,
      CASE upper(x.value->>'category') WHEN 'BUS_4X4' THEN 'bus4x4' ELSE lower(x.value->>'category') END work_key
    FROM jsonb_array_elements(p_manifest->'classifications') x(value)
    JOIN public.pdc_pilbara_service_operations o ON o.importer_version=x.value->'natural_identity'->>0
      AND o.stock_number=x.value->'natural_identity'->>1 AND o.repair_order_number=x.value->'natural_identity'->>2
      AND o.original_line_number=(x.value->'natural_identity'->>3)::integer
    WHERE upper(x.value->>'category')<>'REVIEW'
  ) required
  JOIN public.vehicle_work_items w ON w.vehicle_id=required.vehicle_id AND lower(w.work_key)=required.work_key
  LEFT JOIN public.pdc_pilbara_service_classification_work_controls c ON c.work_item_id=w.id
  WHERE c.work_item_id IS NULL;
  SELECT count(*) INTO v_owned_conflict
  FROM public.pdc_pilbara_service_classification_work_controls c
  JOIN public.vehicle_work_items w ON w.id=c.work_item_id
  WHERE w.vehicle_id IS DISTINCT FROM c.vehicle_id
    OR lower(w.work_key) IS DISTINCT FROM CASE c.category WHEN 'BUS_4X4' THEN 'bus4x4' ELSE lower(c.category) END
    OR w.required IS NOT TRUE OR w.completed IS NOT FALSE OR w.completed_by IS NOT NULL OR w.completed_at IS NOT NULL
    OR w.notes IS DISTINCT FROM 'Pilbara Service classifier managed control';
  v_conflict:=v_conflict+v_owned_conflict;
  v_state:=public.pdc_pilbara_service_classification_state_hash_v1();
  v_response:=jsonb_build_object('ok',true,'code','preview_created','preview_batch_id',v_batch,'manifest_hash',v_actual_hash,
    'current_state_hash',v_state,'insert',v_insert,'update',v_update,'unchanged',v_unchanged,'review',v_review,
    'conflict',v_conflict,'classification_conflict',v_conflict>0,'quarantine_count',40,'apply_allowed',v_conflict=0,
    'category_totals',(SELECT jsonb_object_agg(category,total) FROM (SELECT upper(value->>'category') category,count(*) total FROM jsonb_array_elements(p_manifest->'classifications') GROUP BY 1 ORDER BY 1) q),
    'method_totals',(SELECT jsonb_object_agg(method,total) FROM (SELECT value->>'method' method,count(*) total FROM jsonb_array_elements(p_manifest->'classifications') GROUP BY 1 ORDER BY 1) q),
    'confidence_totals',(SELECT jsonb_build_object('assigned_gte_0_80',count(*) FILTER(WHERE upper(value->>'category')<>'REVIEW'),'review_lt_0_80',count(*) FILTER(WHERE upper(value->>'category')='REVIEW')) FROM jsonb_array_elements(p_manifest->'classifications')));
  INSERT INTO public.pdc_pilbara_service_classification_batches(batch_id,contract,batch_kind,source_importer_version,source_batch_id,
    classifier_version,manifest_hash,idempotency_key,current_state_hash,manifest,response,created_actor)
  VALUES(v_batch,'pilbara_service_operation_classifier_v1','preview','pilbara_service_open_jobcards_v1',
    'ab7483a0-9b6c-4777-a7f9-9481e16023ff',p_manifest->>'classifier_version',v_actual_hash,btrim(p_idempotency_key),v_state,p_manifest,v_response,'postgres:staging-management');
  RETURN v_response;
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
  RETURN jsonb_build_object('ok',false,'code','strict_schema_failed');
END
$body$;
REVOKE ALL ON FUNCTION public.pdc_pilbara_service_classification_preview_v1(jsonb,text,text) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.pdc_pilbara_service_reconcile_work_controls_v1(p_batch_id uuid)
RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog,public AS $body$
DECLARE v_pair record; v_item public.vehicle_work_items%rowtype; v_created integer:=0; v_removed integer:=0;
BEGIN
  FOR v_pair IN
    SELECT c.*,w.vehicle_id work_vehicle_id,w.work_key,w.required,w.completed,w.completed_by,w.completed_at,w.notes
    FROM public.pdc_pilbara_service_classification_work_controls c
    JOIN public.vehicle_work_items w ON w.id=c.work_item_id
    ORDER BY c.vehicle_id,c.category FOR UPDATE OF w,c
  LOOP
    IF v_pair.work_vehicle_id IS DISTINCT FROM v_pair.vehicle_id
       OR lower(v_pair.work_key) IS DISTINCT FROM (CASE v_pair.category WHEN 'BUS_4X4' THEN 'bus4x4' ELSE lower(v_pair.category) END)
       OR v_pair.required IS NOT TRUE OR v_pair.completed IS NOT FALSE OR v_pair.completed_by IS NOT NULL
       OR v_pair.completed_at IS NOT NULL OR v_pair.notes IS DISTINCT FROM 'Pilbara Service classifier managed control' THEN
      RAISE EXCEPTION 'classifier_work_control_conflict:%:%',v_pair.vehicle_id,v_pair.category USING ERRCODE='55000';
    END IF;
  END LOOP;
  FOR v_pair IN
    SELECT DISTINCT o.vehicle_id,h.category,
      CASE h.category WHEN 'BUS_4X4' THEN 'bus4x4' ELSE lower(h.category) END work_key
    FROM public.pdc_pilbara_service_classification_current c
    JOIN public.pdc_pilbara_service_classification_history h USING(classification_id)
    JOIN public.pdc_pilbara_service_operations o USING(operation_id)
    WHERE h.category<>'REVIEW' ORDER BY o.vehicle_id,h.category
  LOOP
    IF NOT EXISTS(SELECT 1 FROM public.pdc_pilbara_service_classification_work_controls c WHERE c.vehicle_id=v_pair.vehicle_id AND c.category=v_pair.category) THEN
      SELECT * INTO v_item FROM public.vehicle_work_items w WHERE w.vehicle_id=v_pair.vehicle_id AND lower(w.work_key)=v_pair.work_key FOR UPDATE;
      IF FOUND THEN RAISE EXCEPTION 'manual_or_completed_work_item:%:%',v_pair.vehicle_id,v_pair.category USING ERRCODE='55000'; END IF;
      INSERT INTO public.vehicle_work_items(vehicle_id,work_key,required,completed,completed_by,completed_at,notes)
      VALUES(v_pair.vehicle_id,v_pair.work_key,true,false,null,null,'Pilbara Service classifier managed control') RETURNING * INTO v_item;
      INSERT INTO public.pdc_pilbara_service_classification_work_controls(vehicle_id,category,work_item_id,created_batch_id)
      VALUES(v_pair.vehicle_id,v_pair.category,v_item.id,p_batch_id);
      v_created:=v_created+1;
    END IF;
  END LOOP;
  FOR v_pair IN SELECT c.*,w.required,w.completed,w.completed_by,w.completed_at,w.notes
    FROM public.pdc_pilbara_service_classification_work_controls c JOIN public.vehicle_work_items w ON w.id=c.work_item_id
    WHERE NOT EXISTS(
      SELECT 1 FROM public.pdc_pilbara_service_classification_current x
      JOIN public.pdc_pilbara_service_classification_history h USING(classification_id)
      JOIN public.pdc_pilbara_service_operations o USING(operation_id)
      WHERE o.vehicle_id=c.vehicle_id AND h.category=c.category)
    FOR UPDATE OF w,c
  LOOP
    DELETE FROM public.pdc_pilbara_service_classification_work_controls WHERE vehicle_id=v_pair.vehicle_id AND category=v_pair.category;
    DELETE FROM public.vehicle_work_items WHERE id=v_pair.work_item_id;
    v_removed:=v_removed+1;
  END LOOP;
  RETURN jsonb_build_object('created',v_created,'removed',v_removed);
END
$body$;
REVOKE ALL ON FUNCTION public.pdc_pilbara_service_reconcile_work_controls_v1(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.pdc_pilbara_service_classification_apply_v1(p_preview_batch_id uuid,p_idempotency_key text)
RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog,public,extensions AS $body$
DECLARE v_preview public.pdc_pilbara_service_classification_batches%rowtype; v_existing public.pdc_pilbara_service_classification_batches%rowtype;
  v_source_operation public.pdc_pilbara_service_operations%rowtype;
  v_batch uuid:=gen_random_uuid(); v_row jsonb; v_operation uuid; v_prior uuid; v_new uuid; v_version integer; v_head jsonb;
  v_work jsonb; v_response jsonb; v_source_semantic_hash text; v_source_description_hash text; v_pointer_rows integer;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('pilbara_service_operation_classifier_v1:mutation',0));
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RETURN jsonb_build_object('ok',false,'code','wrong_environment');
  END IF;
  LOCK TABLE supabase_migrations.schema_migrations IN SHARE MODE;
  LOCK TABLE public.pdc_pilbara_service_operations IN SHARE MODE;
  LOCK TABLE public.pdc_pilbara_service_classification_current,
    public.pdc_pilbara_service_classification_work_controls,
    public.vehicle_work_items IN SHARE ROW EXCLUSIVE MODE;
  PERFORM c.operation_id FROM public.pdc_pilbara_service_classification_current c FOR UPDATE;
  PERFORM c.work_item_id FROM public.pdc_pilbara_service_classification_work_controls c
    JOIN public.vehicle_work_items w ON w.id=c.work_item_id FOR UPDATE OF c,w;
  SELECT jsonb_build_array(version,name) INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1;
  IF v_head IS DISTINCT FROM '["20260907110000","pilbara_service_operation_classifier_v1"]'::jsonb THEN RETURN jsonb_build_object('ok',false,'code','schema_head_changed'); END IF;
  SELECT * INTO v_preview FROM public.pdc_pilbara_service_classification_batches WHERE batch_id=p_preview_batch_id AND batch_kind='preview' FOR SHARE;
  IF NOT FOUND OR coalesce((v_preview.response->>'apply_allowed')::boolean,false) IS NOT TRUE THEN RETURN jsonb_build_object('ok',false,'code','preview_not_eligible'); END IF;
  SELECT * INTO v_existing FROM public.pdc_pilbara_service_classification_batches WHERE batch_kind='apply' AND idempotency_key=btrim(p_idempotency_key);
  IF FOUND THEN
    IF v_existing.preview_of_batch_id IS DISTINCT FROM p_preview_batch_id
       OR v_existing.manifest_hash<>v_preview.manifest_hash THEN
      RETURN jsonb_build_object('ok',false,'code','idempotency_conflict');
    END IF;
    RETURN v_existing.response||jsonb_build_object('code','apply_replay');
  END IF;
  IF public.pdc_pilbara_service_classification_state_hash_v1()<>v_preview.current_state_hash THEN RETURN jsonb_build_object('ok',false,'code','current_state_changed'); END IF;
  FOR v_row IN SELECT value FROM jsonb_array_elements(v_preview.manifest->'classifications') LOOP
    SELECT * INTO v_source_operation FROM public.pdc_pilbara_service_operations o
     WHERE o.importer_version=v_row->'natural_identity'->>0 AND o.stock_number=v_row->'natural_identity'->>1
       AND o.repair_order_number=v_row->'natural_identity'->>2 AND o.original_line_number=(v_row->'natural_identity'->>3)::integer;
    IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','source_binding_conflict'); END IF;
    v_source_semantic_hash:=v_source_operation.semantic_hash;
    v_source_description_hash:=encode(extensions.digest(convert_to(v_source_operation.operation_description,'UTF8'),'sha256'),'hex');
    IF v_source_semantic_hash IS DISTINCT FROM v_row->>'source_semantic_hash'
       OR v_source_description_hash IS DISTINCT FROM v_row->>'source_description_hash' THEN
      RETURN jsonb_build_object('ok',false,'code','source_binding_conflict');
    END IF;
  END LOOP;
  INSERT INTO public.pdc_pilbara_service_classification_batches(batch_id,contract,batch_kind,source_importer_version,source_batch_id,classifier_version,
    manifest_hash,idempotency_key,current_state_hash,manifest,response,preview_of_batch_id,created_actor)
  VALUES(v_batch,v_preview.contract,'apply',v_preview.source_importer_version,v_preview.source_batch_id,v_preview.classifier_version,
    v_preview.manifest_hash,btrim(p_idempotency_key),v_preview.current_state_hash,v_preview.manifest,'{}',v_preview.batch_id,'postgres:staging-management');
  FOR v_row IN SELECT value FROM jsonb_array_elements(v_preview.manifest->'classifications') LOOP
    SELECT o.operation_id INTO STRICT v_operation FROM public.pdc_pilbara_service_operations o
     WHERE o.importer_version=v_row->'natural_identity'->>0 AND o.stock_number=v_row->'natural_identity'->>1
       AND o.repair_order_number=v_row->'natural_identity'->>2 AND o.original_line_number=(v_row->'natural_identity'->>3)::integer;
    SELECT c.classification_id INTO v_prior FROM public.pdc_pilbara_service_classification_current c WHERE c.operation_id=v_operation FOR UPDATE;
    IF FOUND AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_classification_history h WHERE h.classification_id=v_prior
      AND h.category=upper(v_row->>'category') AND h.method=v_row->>'method' AND h.confidence=(v_row->>'confidence')::numeric
      AND h.rationale=v_row->>'rationale' AND h.source_description_hash=v_row->>'source_description_hash'
      AND h.source_semantic_hash=v_row->>'source_semantic_hash' AND coalesce(h.rule_id,'')=coalesce(v_row->>'rule_id','')
      AND coalesce(h.ruleset_version,'')=coalesce(v_row->>'ruleset_version','') AND coalesce(h.provider,'')=coalesce(v_row->>'provider','')
      AND coalesce(h.model,'')=coalesce(v_row->>'model','') AND coalesce(h.model_run_id,'')=coalesce(v_row->>'run_id','')
      AND h.classifier_version=v_preview.classifier_version) THEN CONTINUE; END IF;
    SELECT coalesce(max(classification_version),0)+1 INTO v_version FROM public.pdc_pilbara_service_classification_history WHERE operation_id=v_operation;
    INSERT INTO public.pdc_pilbara_service_classification_history(operation_id,batch_id,classification_version,category,method,confidence,rationale,
      rule_id,ruleset_version,provider,model,model_run_id,source_description_hash,source_semantic_hash,classifier_version,supersedes_classification_id)
    VALUES(v_operation,v_batch,v_version,upper(v_row->>'category'),v_row->>'method',(v_row->>'confidence')::numeric,v_row->>'rationale',
      v_row->>'rule_id',v_row->>'ruleset_version',v_row->>'provider',v_row->>'model',v_row->>'run_id',v_row->>'source_description_hash',
      v_row->>'source_semantic_hash',v_preview.classifier_version,v_prior) RETURNING classification_id INTO v_new;
    INSERT INTO public.pdc_pilbara_service_classification_current(operation_id,classification_id)
    VALUES(v_operation,v_new) ON CONFLICT(operation_id) DO UPDATE SET classification_id=excluded.classification_id,updated_at=clock_timestamp();
    GET DIAGNOSTICS v_pointer_rows = ROW_COUNT;
    IF v_pointer_rows<>1 THEN RAISE EXCEPTION 'classification_pointer_update_conflict:%',v_operation USING ERRCODE='55000'; END IF;
  END LOOP;
  v_work:=public.pdc_pilbara_service_reconcile_work_controls_v1(v_batch);
  UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;
  v_response:=v_preview.response||jsonb_build_object('ok',true,'code','applied','apply_batch_id',v_batch,'atomic',true,
    'history_inserted',(SELECT count(*) FROM public.pdc_pilbara_service_classification_history WHERE batch_id=v_batch),
    'work_controls',v_work,'operation_completion_changes',0,'booking_changes',0,'forbidden_vehicle_changes',0);
  UPDATE public.pdc_pilbara_service_classification_batches SET response=v_response WHERE batch_id=v_batch;
  RETURN v_response;
END
$body$;
REVOKE ALL ON FUNCTION public.pdc_pilbara_service_classification_apply_v1(uuid,text) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION public.pdc_pilbara_service_classification_rollback_v1(p_apply_batch_id uuid,p_idempotency_key text)
RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog,public,extensions AS $body$
DECLARE v_apply public.pdc_pilbara_service_classification_batches%rowtype; v_existing public.pdc_pilbara_service_classification_batches%rowtype;
  v_batch uuid:=gen_random_uuid(); v_row record; v_state text; v_work jsonb; v_response jsonb; v_head jsonb; v_pointer_rows integer;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('pilbara_service_operation_classifier_v1:mutation',0));
  IF NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RETURN jsonb_build_object('ok',false,'code','wrong_environment');
  END IF;
  LOCK TABLE supabase_migrations.schema_migrations IN SHARE MODE;
  LOCK TABLE public.pdc_pilbara_service_classification_current,
    public.pdc_pilbara_service_classification_work_controls,
    public.vehicle_work_items IN SHARE ROW EXCLUSIVE MODE;
  PERFORM c.operation_id FROM public.pdc_pilbara_service_classification_current c FOR UPDATE;
  PERFORM c.work_item_id FROM public.pdc_pilbara_service_classification_work_controls c
    JOIN public.vehicle_work_items w ON w.id=c.work_item_id FOR UPDATE OF c,w;
  SELECT jsonb_build_array(version,name) INTO v_head FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1;
  IF v_head IS DISTINCT FROM '["20260907110000","pilbara_service_operation_classifier_v1"]'::jsonb THEN RETURN jsonb_build_object('ok',false,'code','schema_head_changed'); END IF;
  SELECT * INTO v_apply FROM public.pdc_pilbara_service_classification_batches WHERE batch_id=p_apply_batch_id AND batch_kind='apply' FOR SHARE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','apply_batch_not_found'); END IF;
  SELECT * INTO v_existing FROM public.pdc_pilbara_service_classification_batches WHERE batch_kind='rollback' AND idempotency_key=btrim(p_idempotency_key);
  IF FOUND THEN
    IF v_existing.rollback_of_batch_id IS DISTINCT FROM p_apply_batch_id OR v_existing.manifest_hash<>v_apply.manifest_hash THEN
      RETURN jsonb_build_object('ok',false,'code','idempotency_conflict');
    END IF;
    RETURN v_existing.response||jsonb_build_object('code','rollback_replay');
  END IF;
  IF EXISTS(SELECT 1 FROM public.pdc_pilbara_service_classification_history h
    LEFT JOIN public.pdc_pilbara_service_classification_current c ON c.operation_id=h.operation_id
    WHERE h.batch_id=v_apply.batch_id AND c.classification_id IS DISTINCT FROM h.classification_id) THEN
    RETURN jsonb_build_object('ok',false,'code','rollback_conflict');
  END IF;
  v_state:=public.pdc_pilbara_service_classification_state_hash_v1();
  INSERT INTO public.pdc_pilbara_service_classification_batches(batch_id,contract,batch_kind,source_importer_version,source_batch_id,classifier_version,
    manifest_hash,idempotency_key,current_state_hash,manifest,response,rollback_of_batch_id,created_actor)
  VALUES(v_batch,v_apply.contract,'rollback',v_apply.source_importer_version,v_apply.source_batch_id,v_apply.classifier_version,
    v_apply.manifest_hash,btrim(p_idempotency_key),v_state,v_apply.manifest,'{}',v_apply.batch_id,'postgres:staging-management');
  FOR v_row IN SELECT * FROM public.pdc_pilbara_service_classification_history WHERE batch_id=v_apply.batch_id ORDER BY operation_id LOOP
    IF v_row.supersedes_classification_id IS NULL THEN
      DELETE FROM public.pdc_pilbara_service_classification_current WHERE operation_id=v_row.operation_id AND classification_id=v_row.classification_id;
      GET DIAGNOSTICS v_pointer_rows = ROW_COUNT;
    ELSE
      UPDATE public.pdc_pilbara_service_classification_current SET classification_id=v_row.supersedes_classification_id,updated_at=clock_timestamp()
       WHERE operation_id=v_row.operation_id AND classification_id=v_row.classification_id;
      GET DIAGNOSTICS v_pointer_rows = ROW_COUNT;
    END IF;
    IF v_pointer_rows<>1 THEN RAISE EXCEPTION 'rollback_pointer_conflict:%',v_row.operation_id USING ERRCODE='55000'; END IF;
  END LOOP;
  v_work:=public.pdc_pilbara_service_reconcile_work_controls_v1(v_batch);
  UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;
  v_response:=jsonb_build_object('ok',true,'code','rolled_back','rollback_batch_id',v_batch,'rollback_of_batch_id',v_apply.batch_id,
    'restored_current_pointers',(SELECT count(*) FROM public.pdc_pilbara_service_classification_history WHERE batch_id=v_apply.batch_id),
    'work_controls',v_work,'history_deleted',0,'atomic',true);
  UPDATE public.pdc_pilbara_service_classification_batches SET response=v_response WHERE batch_id=v_batch;
  RETURN v_response;
END
$body$;
REVOKE ALL ON FUNCTION public.pdc_pilbara_service_classification_rollback_v1(uuid,text) FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.get_pdc_email_vehicle_location_snapshot()
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
      'work_key',CASE coalesce(h.category,'REVIEW') WHEN 'BUS_4X4' THEN 'bus4x4' ELSE lower(coalesce(h.category,'REVIEW')) END,
      'job_card_number',o.repair_order_number,'description',o.operation_description,
      'estimated_hours',o.effective_estimated_hours,
      'estimated_hours_source',CASE o.hours_provenance WHEN 'pre_delivery_default_1_5' THEN 'business_rule_default' WHEN 'source_explicit' THEN 'job_card' ELSE 'owner_supplied_document_unknown' END,
      'source_estimated_hours',o.source_estimated_hours,'effective_estimated_hours',o.effective_estimated_hours,
      'hours_provenance',o.hours_provenance,'parts_on_backorder_raw',o.parts_on_backorder_raw,'parts_semantics',o.parts_semantics,
      'classification',coalesce(h.category,'REVIEW'),'classification_method',coalesce(h.method,'review'),
      'classification_confidence',coalesce(h.confidence,0),'classification_rationale',coalesce(h.rationale,'No current classification; retained for Review.'),
      'source_description_hash',h.source_description_hash,'classifier_version',h.classifier_version,
      'source_uid','pilbara_service_open_jobcards_v1:'||o.stock_number||':'||o.repair_order_number||':'||o.original_line_number
    ) ORDER BY o.source_order),'[]'::jsonb) service_lines
    FROM public.pdc_pilbara_service_operations o
    LEFT JOIN public.pdc_pilbara_service_classification_current c USING(operation_id)
    LEFT JOIN public.pdc_pilbara_service_classification_history h USING(classification_id)
    WHERE o.vehicle_id=(row_value->>'id')::uuid
  ) projected;
  RETURN jsonb_set(v_base,'{data,vehicles}',v_rows,true);
END
$snapshot$;
REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_pdc_email_vehicle_location_snapshot() TO authenticated,service_role;

REVOKE ALL ON FUNCTION public.pdc_pilbara_service_classification_preview_v1(jsonb,text,text),
  public.pdc_pilbara_service_classification_apply_v1(uuid,text),
  public.pdc_pilbara_service_classification_rollback_v1(uuid,text) FROM PUBLIC,anon,authenticated,service_role;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
  '20260907110000','pilbara_service_operation_classifier_v1',ARRAY[
    'Add append-only, hash-bound classification history with a controlled mutable current pointer.',
    'Provide private preview/apply/rollback functions guarded by exact source, manifest, state and migration head.',
    'Materialise only classifier-owned outstanding work controls and conflict on manual or completed work.',
    'Project controlled categories and evidence through the authenticated snapshot without altering raw Service rows.'
  ]);
NOTIFY pgrst,'reload schema';
COMMIT;
