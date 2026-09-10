-- STAGING ONLY. Extend existing dynamic importer; immutable old receipts remain valid.
DO $$ BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE
 OR NOT EXISTS(SELECT 1 FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')
 OR current_setting('app.environment',true)='production'
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'STAGING only'; END IF;
END $$;

-- Abort deployment if another release changed the inspected importer/projection definitions.
DO $$ BEGIN
 IF md5(pg_get_functiondef('public.pdc_pilbara_service_apply_v1(uuid,text,text)'::regprocedure))<>'0b85da8b753a70720eb39413367e9c2d'
 OR md5(pg_get_functiondef('public.pdc_pilbara_service_preview_v1(jsonb,text,text)'::regprocedure))<>'8e48af922bb54aa0583358af4d2fa20d'
 OR md5(pg_get_functiondef('public.pdc_qc_operation_lines_379(uuid)'::regprocedure))<>'5557bf31ef3d54f61b3005ee55a83159'
 OR md5(pg_get_functiondef('public.pdc_pilbara_service_classification_apply_v2(uuid,text)'::regprocedure))<>'5a4e1e96cdf36f93bc4bde7ac9c93075'
 OR md5(pg_get_functiondef('public.pdc_pilbara_service_classification_preview_v2(uuid,jsonb,text)'::regprocedure))<>'0840a9d5e5a870770df05db4f02522a1'
 OR md5(pg_get_functiondef('public.pdc_pilbara_service_classification_source_v2(uuid)'::regprocedure))<>'ef97bece01cebdc51a2185497972c38a'
 THEN RAISE EXCEPTION 'Inspected STAGING definitions changed; rebase required'; END IF;
END $$;

ALTER TABLE public.pdc_pilbara_service_import_batches ADD COLUMN contract_revision text NOT NULL DEFAULT 'dynamic_v2';
ALTER TABLE public.pdc_pilbara_service_import_batches ADD COLUMN source_link jsonb NOT NULL DEFAULT '{}';
ALTER TABLE public.pdc_pilbara_service_import_batches DROP CONSTRAINT pdc_pilbara_service_import_ba_importer_version_source_hash__key;
ALTER TABLE public.pdc_pilbara_service_import_batches ADD UNIQUE(importer_version,source_hash,batch_kind,contract_revision);
ALTER TABLE public.pdc_pilbara_service_operations ADD COLUMN department text CHECK(department IN('138','139'));
ALTER TABLE public.pdc_pilbara_service_operations ADD COLUMN operation_code text;
ALTER TABLE public.pdc_pilbara_service_operations ADD COLUMN proposed_station text CHECK(proposed_station IN('BUS_4X4','FITTING','ELECTRICAL','TYRE','TINT','HOIST','FABRICATION','SUBLET','REVIEW'));

CREATE FUNCTION public.pdc_pilbara_service_operation_identity_hash_v3(p_department text,p_stock text,p_ro text,p_line integer,p_description text)
RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE SET search_path=pg_catalog,public,extensions AS $$
 SELECT CASE WHEN p_department IS NULL THEN public.pdc_pilbara_service_operation_identity_hash_v2(p_stock,p_ro,p_line,p_description)
 ELSE encode(extensions.digest(convert_to(jsonb_build_array(btrim(p_department),btrim(p_stock),upper(btrim(p_ro)),p_line,
 lower(regexp_replace(btrim(p_description),'[[:space:]]+',' ','g')))::text,'UTF8'),'sha256'),'hex') END
$$;
REVOKE ALL ON FUNCTION public.pdc_pilbara_service_operation_identity_hash_v3(text,text,text,integer,text) FROM PUBLIC,anon,authenticated;
DROP INDEX public.pdc_pilbara_service_operation_semantic_identity_key;
CREATE UNIQUE INDEX pdc_pilbara_service_operation_semantic_identity_key ON public.pdc_pilbara_service_operations
 (importer_version,public.pdc_pilbara_service_operation_identity_hash_v3(department,stock_number,repair_order_number,original_line_number,operation_description));

-- Internal resolver: no writes, no exposed EXECUTE permission. Include historical identities.
CREATE FUNCTION public.pdc_pmg_stock_candidate_v3(p_stock text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE ids uuid[]; vid uuid; v public.vehicles%rowtype; n integer; bid uuid; linked uuid;
BEGIN
 IF nullif(btrim(p_stock),'') IS NULL OR length(p_stock)>80 OR NOT public.is_real_vehicle_stock_number(p_stock)
 THEN RETURN jsonb_build_object('ok',false,'code','invalid_stock'); END IF;
 SELECT array_agg(DISTINCT id) INTO ids FROM (
  SELECT id FROM public.vehicles WHERE stock_number_normalized=public.normalize_vehicle_stock_number(p_stock)
  UNION SELECT vehicle_id FROM public.vehicle_aliases WHERE alias_type_normalized IN('stock','stock_number') AND normalized_alias_value=public.normalize_vehicle_stock_number(p_stock)
  UNION SELECT vehicle_id FROM public.pdc_vehicle_tombstones WHERE normalized_stock=public.normalize_vehicle_stock_number(p_stock)
 ) q;
 IF coalesce(cardinality(ids),0)>1 THEN RETURN jsonb_build_object('ok',false,'code','competing_canonical_identities'); END IF;
 SELECT count(*),min(id::text)::uuid INTO n,bid FROM public.navision_backend_records
 WHERE source_system='microsoft_navision' AND dealer_code='37047' AND is_current AND record_status='current'
 AND public.normalize_vehicle_stock_number(coalesce(normalized_data->>'batch',normalized_data->>'stock'))=public.normalize_vehicle_stock_number(p_stock);
 IF n>1 THEN RETURN jsonb_build_object('ok',false,'code','ambiguous_current_navision_identity'); END IF;
 vid:=ids[1];
 IF n=1 THEN
  SELECT canonical_vehicle_id INTO linked FROM public.navision_backend_records WHERE id=bid;
  IF linked IS NULL THEN RETURN jsonb_build_object('ok',false,'code','navision_vehicle_not_activated'); END IF;
  IF vid IS DISTINCT FROM linked THEN RETURN jsonb_build_object('ok',false,'code','navision_canonical_identity_conflict'); END IF;
 END IF;
 IF vid IS NOT NULL THEN
  SELECT * INTO v FROM public.vehicles WHERE id=vid;
  IF NOT FOUND OR v.deleted_at IS NOT NULL OR v.lifecycle_state::text<>'active' OR v.board_purged_at IS NOT NULL
  THEN RETURN jsonb_build_object('ok',false,'code','historical_identity_requires_restore'); END IF;
  IF btrim(v.stock_number) IS DISTINCT FROM btrim(p_stock) THEN RETURN jsonb_build_object('ok',false,'code','exact_stock_conflict'); END IF;
  IF v.visible_on_board OR EXISTS(SELECT 1 FROM public.pdc_new_vehicle_reviews WHERE vehicle_id=vid AND status<>'pending')
  THEN RETURN jsonb_build_object('ok',false,'code','existing_operational_vehicle_requires_review'); END IF;
 END IF;
 RETURN jsonb_build_object('ok',true,'vehicle_id',vid,'backend_record_id',bid,'create_vehicle',vid IS NULL);
END $$;
REVOKE ALL ON FUNCTION public.pdc_pmg_stock_candidate_v3(text) FROM PUBLIC,anon,authenticated;

-- Unbound queue deliberately has no vehicle column or relationship.
CREATE TABLE public.pdc_unidentified_tune_review(
 review_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 workbook_sha256 text NOT NULL CHECK(workbook_sha256 ~ '^[a-f0-9]{64}$'),
 repair_order_number text NOT NULL, department text NOT NULL CHECK(department IN('138','139')),
 original_line_number integer NOT NULL CHECK(original_line_number>0), operation_description text NOT NULL,
 operation_identity_hash text NOT NULL, source_estimated_hours numeric NOT NULL CHECK(source_estimated_hours BETWEEN 0 AND 999.99),
 operation_code text, proposed_station text NOT NULL CHECK(proposed_station IN('BUS_4X4','FITTING','ELECTRICAL','TYRE','TINT','HOIST','FABRICATION','SUBLET','REVIEW')), raw_row jsonb NOT NULL,
 source_hash text NOT NULL, source_batch_id uuid NOT NULL REFERENCES public.pdc_pilbara_service_import_batches(batch_id),
 status text NOT NULL DEFAULT 'unidentified' CHECK(status='unidentified'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(), UNIQUE(workbook_sha256,operation_identity_hash)
);
ALTER TABLE public.pdc_unidentified_tune_review ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pdc_unidentified_tune_review FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.pdc_unidentified_tune_review FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER pdc_unidentified_tune_review_immutable BEFORE UPDATE OR DELETE ON public.pdc_unidentified_tune_review
FOR EACH ROW EXECUTE FUNCTION public.pdc_pilbara_service_reject_evidence_mutation();

CREATE OR REPLACE FUNCTION public.pdc_pilbara_service_preview_v1(p_rows jsonb, p_source_hash text, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
 SET lock_timeout TO '5s'
 SET statement_timeout TO '60s'
AS $function$
DECLARE
  v_revision text:='dynamic_v2'; v_tune boolean:=false; v_dept text; v_station text; v_code text; v_parent text; v_candidate jsonb;
  v_actor uuid:=auth.uid();v_actor_label text:=lower(btrim(coalesce(auth.jwt()->>'email','')))||':viewer:'||coalesce(auth.uid()::text,'missing');
  v_source_hash text:=lower(btrim(coalesce(p_source_hash,'')));v_idem text:=btrim(coalesce(p_idempotency_key,''));v_request_hash text;
  v_prior public.pdc_pilbara_service_import_batches%rowtype;v_batch_id uuid:=gen_random_uuid();v_item record;v_row jsonb;v_raw jsonb;
  v_stock text;v_ro text;v_descr text;v_parts_raw text;v_parts_sem text;v_provenance text;v_identity_hash text;v_semantic_hash text;v_prior_semantic text;
  v_source_hours numeric;v_effective_hours numeric;v_line_no integer;v_source_order integer;v_backend_count integer;v_backend_id uuid;v_vehicle_id uuid;v_vehicle_count integer;
  v_decision text;v_reason text;v_seen jsonb:='{}'::jsonb;v_outcomes jsonb:='[]'::jsonb;v_response jsonb;
  v_source_count integer:=0;v_accepted_count integer:=0;v_insert_count integer:=0;v_unchanged_count integer:=0;v_duplicate_count integer:=0;
  v_quarantine_count integer:=0;v_conflict_count integer:=0;v_matched_stocks text[]:='{}'::text[];v_unmatched_stocks text[]:='{}'::text[];v_ambiguous_stocks text[]:='{}'::text[];
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'code','wrong_environment');END IF;
  IF NOT public.pdc_email_ai_runtime_authorized_v1() THEN RETURN jsonb_build_object('ok',false,'code','not_authorized');END IF;
  IF jsonb_typeof(p_rows) IS DISTINCT FROM 'array' OR jsonb_array_length(p_rows) NOT BETWEEN 1 AND 1000000
     OR v_source_hash !~ '^[a-f0-9]{64}$' OR length(v_idem) NOT BETWEEN 12 AND 160 THEN RETURN jsonb_build_object('ok',false,'code','invalid_source_contract');END IF;
  v_tune:=EXISTS(SELECT 1 FROM jsonb_array_elements(p_rows) x WHERE x ? 'department' OR (x->'raw_row') ? 'Dept');
  IF v_tune THEN
    v_revision:='pmg_stock_v3';
    SELECT min(coalesce(x->>'workbook_sha256',x->'raw_row'->>'parent_attachment_sha256')) INTO v_parent FROM jsonb_array_elements(p_rows) x;
    IF v_parent IS NULL OR v_parent !~ '^[a-f0-9]{64}$' OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_rows) x
      WHERE coalesce(x->>'workbook_sha256',x->'raw_row'->>'parent_attachment_sha256','')<>v_parent
      OR coalesce(x->>'department',x->'raw_row'->>'Dept','') NOT IN('138','139'))
    THEN RETURN jsonb_build_object('ok',false,'code','invalid_tune_source_link'); END IF;
    IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_rows) x GROUP BY upper(btrim(x->>'repair_order_number'))
      HAVING count(DISTINCT coalesce(x->>'department',x->'raw_row'->>'Dept'))<>1
      OR count(DISTINCT nullif(btrim(x->>'stock_number'),''))>1)
    THEN RETURN jsonb_build_object('ok',false,'code','conflicting_job_card_identity'); END IF;
  END IF;
  v_request_hash:=encode(extensions.digest(convert_to(p_rows::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pilbara_service_open_jobcards_v1:source:'||v_source_hash||':'||v_revision,0));
  PERFORM pg_advisory_xact_lock(hashtextextended('pilbara_service_open_jobcards_v1:preview:'||v_idem,0));
  SELECT * INTO v_prior FROM public.pdc_pilbara_service_import_batches b WHERE b.importer_version='pilbara_service_open_jobcards_v1' AND b.idempotency_key=v_idem;
  IF FOUND THEN IF v_prior.request_hash<>v_request_hash OR v_prior.source_hash<>v_source_hash OR v_prior.contract_revision<>v_revision THEN RETURN jsonb_build_object('ok',false,'code','idempotency_conflict');END IF;
    RETURN v_prior.response||jsonb_build_object('code','preview_replay','replay',true);END IF;
  SELECT * INTO v_prior FROM public.pdc_pilbara_service_import_batches b WHERE b.importer_version='pilbara_service_open_jobcards_v1' AND b.source_hash=v_source_hash AND b.batch_kind='preview' AND b.contract_revision=v_revision;
  IF FOUND THEN IF v_prior.request_hash<>v_request_hash THEN RETURN jsonb_build_object('ok',false,'code','source_hash_payload_conflict');END IF;
    RETURN v_prior.response||jsonb_build_object('code','preview_replay','replay',true);END IF;
  FOR v_item IN SELECT value AS row_value,ordinality::integer AS ordinality FROM jsonb_array_elements(p_rows) WITH ORDINALITY LOOP
    v_source_count:=v_source_count+1;v_row:=v_item.row_value;
    v_raw:=CASE WHEN jsonb_typeof(v_row->'raw_row')='object' THEN v_row->'raw_row' WHEN jsonb_typeof(v_row)='object' THEN v_row ELSE jsonb_build_object('raw_value',v_row) END;
    v_dept:=CASE WHEN v_tune THEN coalesce(v_row->>'department',v_raw->>'Dept') END;
    v_station:=CASE WHEN v_dept='138' THEN 'BUS_4X4' ELSE upper(coalesce(v_row->>'proposed_station',v_raw->>'proposed_station','REVIEW')) END;
    v_code:=nullif(btrim(coalesce(v_row->>'operation_code',v_raw->>'operation_code')),'');
    IF v_tune AND (nullif(v_row->>'department','') IS NOT NULL AND nullif(v_raw->>'Dept','') IS NOT NULL AND v_row->>'department'<>v_raw->>'Dept')
    THEN RETURN jsonb_build_object('ok',false,'code','conflicting_department_evidence'); END IF;
    IF v_tune AND v_station NOT IN('BUS_4X4','FITTING','ELECTRICAL','TYRE','TINT','HOIST','FABRICATION','SUBLET','REVIEW')
    THEN RETURN jsonb_build_object('ok',false,'code','invalid_proposed_station'); END IF;
    v_source_order:=v_item.ordinality;v_stock:=btrim(coalesce(v_row->>'stock_number',''));v_ro:=upper(btrim(coalesce(v_row->>'repair_order_number','')));
    v_descr:=regexp_replace(btrim(coalesce(v_row->>'operation_description','')),'\s+',' ','g');v_parts_raw:=btrim(coalesce(v_row->>'parts_on_backorder_raw',''));
    v_line_no:=NULL;v_source_hours:=NULL;v_effective_hours:=NULL;v_provenance:='';v_parts_sem:='';v_identity_hash:=NULL;v_semantic_hash:=NULL;v_prior_semantic:=NULL;
    v_backend_id:=NULL;v_vehicle_id:=NULL;v_backend_count:=0;v_vehicle_count:=0;v_decision:='quarantine';v_reason:='invalid_row';
    IF jsonb_typeof(v_row) IS DISTINCT FROM 'object' OR (v_stock='' AND NOT v_tune) OR length(v_stock)>80 OR v_ro='' OR length(v_ro)>80 OR v_descr='' OR length(v_descr)>1000
       OR coalesce(v_row->>'original_line_number','') !~ '^[0-9]+$' THEN v_reason:='invalid_natural_identity';v_quarantine_count:=v_quarantine_count+1;
    ELSE
      IF v_tune AND v_stock='' THEN
        SELECT coalesce(min(nullif(btrim(x->>'stock_number'),'')),'') INTO v_stock FROM jsonb_array_elements(p_rows) x WHERE upper(btrim(x->>'repair_order_number'))=v_ro;
      END IF;
      v_line_no:=(v_row->>'original_line_number')::integer;
      IF v_line_no<1 THEN v_reason:='invalid_line_number';v_quarantine_count:=v_quarantine_count+1;
      ELSIF v_tune AND nullif(btrim(v_row->>'source_estimated_hours'),'') IS NULL THEN v_reason:='missing_hours';v_quarantine_count:=v_quarantine_count+1;
      ELSIF v_row ? 'source_estimated_hours' AND v_row->'source_estimated_hours' IS NOT NULL AND btrim(coalesce(v_row->>'source_estimated_hours',''))<>'' THEN
        IF btrim(v_row->>'source_estimated_hours') !~ '^[0-9]+([.][0-9]{1,2})?$' OR (v_row->>'source_estimated_hours')::numeric NOT BETWEEN 0 AND 999.99
        THEN v_reason:='invalid_source_hours';v_quarantine_count:=v_quarantine_count+1;
        ELSE v_source_hours:=(v_row->>'source_estimated_hours')::numeric;v_effective_hours:=v_source_hours;v_provenance:='source_explicit';END IF;
      ELSE
        IF lower(regexp_replace(v_descr,'[^a-z0-9]+','','g')) IN('predelivery','predeliverycommercial','vehiclepredelivery')
        THEN v_effective_hours:=1.0;v_provenance:='pre_delivery_default_1_0';
        ELSIF coalesce(v_row->>'hours_provenance','')='ai_estimated' AND btrim(coalesce(v_row->>'effective_estimated_hours','')) ~ '^[0-9]+([.][0-9]{1,2})?$'
          AND (v_row->>'effective_estimated_hours')::numeric BETWEEN 0 AND 999.99
        THEN v_effective_hours:=(v_row->>'effective_estimated_hours')::numeric;v_provenance:='ai_estimated';
        ELSE v_provenance:='source_blank';v_reason:='missing_hours';v_quarantine_count:=v_quarantine_count+1;END IF;
      END IF;
      IF v_effective_hours IS NOT NULL THEN
        IF v_tune THEN v_source_hours:=trim_scale(v_source_hours);v_effective_hours:=trim_scale(v_effective_hours); END IF;
        v_parts_sem:=CASE lower(v_parts_raw) WHEN 'yes' THEN 'explicitly_backordered' WHEN 'no' THEN 'not_backordered' ELSE 'review' END;
        v_identity_hash:=public.pdc_pilbara_service_operation_identity_hash_v3(v_dept,v_stock,v_ro,v_line_no,v_descr);
        v_semantic_hash:=encode(extensions.digest(convert_to(concat_ws(chr(31),v_identity_hash,coalesce(v_source_hours::text,''),v_effective_hours::text,v_provenance,v_parts_raw,v_parts_sem,'Review'),'UTF8'),'sha256'),'hex');
        IF v_seen ? v_identity_hash THEN
          IF v_seen->>v_identity_hash=(v_semantic_hash||CASE WHEN v_tune THEN chr(31)||coalesce(v_code,'')||chr(31)||v_station ELSE '' END) THEN v_decision:='duplicate';v_reason:='exact_duplicate_row_ignored';v_duplicate_count:=v_duplicate_count+1;
          ELSE v_decision:='conflict';v_reason:='duplicate_operation_identity_conflict';v_conflict_count:=v_conflict_count+1;END IF;
        ELSE
          v_seen:=v_seen||jsonb_build_object(v_identity_hash,v_semantic_hash||CASE WHEN v_tune THEN chr(31)||coalesce(v_code,'')||chr(31)||v_station ELSE '' END);
          IF v_tune THEN
            IF v_stock='' THEN
              IF nullif(btrim(coalesce(v_row->>'vin',v_raw->>'VIN')),'') IS NOT NULL THEN v_decision:='conflict';v_reason:='vin_identity_requires_review';v_conflict_count:=v_conflict_count+1;
              ELSIF EXISTS(SELECT 1 FROM public.pdc_unidentified_tune_review u WHERE u.workbook_sha256=v_parent AND u.operation_identity_hash=v_identity_hash
                AND (u.source_estimated_hours IS DISTINCT FROM v_source_hours OR u.proposed_station IS DISTINCT FROM v_station OR u.operation_code IS DISTINCT FROM v_code OR u.raw_row IS DISTINCT FROM v_raw))
              THEN v_decision:='conflict';v_reason:='unidentified_source_changed';v_conflict_count:=v_conflict_count+1;
              ELSE v_decision:='quarantine';v_reason:='unidentified_tune_review';v_quarantine_count:=v_quarantine_count+1; END IF;
            ELSIF nullif(btrim(coalesce(v_row->>'vin',v_raw->>'VIN')),'') IS NOT NULL THEN v_decision:='conflict';v_reason:='vin_identity_requires_review';v_conflict_count:=v_conflict_count+1;
            ELSIF EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.stock_number=v_stock AND o.repair_order_number=v_ro AND o.department IS NOT NULL AND o.department<>v_dept)
            THEN v_decision:='conflict';v_reason:='conflicting_job_card_department';v_conflict_count:=v_conflict_count+1;
            ELSE
              v_candidate:=public.pdc_pmg_stock_candidate_v3(v_stock);
              IF (v_candidate->>'ok')::boolean IS NOT TRUE THEN
                v_decision:='conflict';v_reason:=v_candidate->>'code';v_conflict_count:=v_conflict_count+1;
              ELSE
                v_vehicle_id:=(v_candidate->>'vehicle_id')::uuid;v_backend_id:=(v_candidate->>'backend_record_id')::uuid;
                IF NOT v_stock=ANY(v_matched_stocks) THEN v_matched_stocks:=array_append(v_matched_stocks,v_stock); END IF;
                IF v_code IS NOT NULL AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o JOIN public.pdc_pilbara_service_operation_history h USING(operation_id)
                  WHERE public.pdc_pilbara_service_operation_identity_hash_v3(o.department,o.stock_number,o.repair_order_number,o.original_line_number,o.operation_description)=v_identity_hash
                  AND nullif(h.immutable_snapshot->>'operation_code','') IS NOT NULL AND h.immutable_snapshot->>'operation_code'<>v_code)
                THEN RETURN jsonb_build_object('ok',false,'code','operation_code_conflict'); END IF;
                SELECT o.semantic_hash INTO v_prior_semantic FROM public.pdc_pilbara_service_operations o WHERE o.importer_version='pilbara_service_open_jobcards_v1'
                AND public.pdc_pilbara_service_operation_identity_hash_v3(o.department,o.stock_number,o.repair_order_number,o.original_line_number,o.operation_description)=v_identity_hash;
                IF NOT FOUND THEN v_decision:='insert';v_reason:='new_operation';v_insert_count:=v_insert_count+1;v_accepted_count:=v_accepted_count+1;
                ELSIF v_prior_semantic=v_semantic_hash THEN v_decision:='unchanged';v_reason:='same_semantic_hash';v_unchanged_count:=v_unchanged_count+1;v_accepted_count:=v_accepted_count+1;
                ELSE v_decision:='conflict';v_reason:='semantic_identity_changed_requires_review';v_conflict_count:=v_conflict_count+1;END IF;
              END IF;
            END IF;
          ELSE
          SELECT count(*),min(b.id::text)::uuid INTO v_backend_count,v_backend_id FROM public.navision_backend_records b
          WHERE b.source_system='microsoft_navision' AND b.dealer_code='37047' AND b.is_current AND b.record_status='current'
            AND btrim(coalesce(b.normalized_data->>'batch',b.normalized_data->>'stock',''))=v_stock;
          IF v_backend_count=0 THEN v_decision:='quarantine';v_reason:='no_exact_current_navision_record';v_quarantine_count:=v_quarantine_count+1;
            IF NOT v_stock=ANY(v_unmatched_stocks) THEN v_unmatched_stocks:=array_append(v_unmatched_stocks,v_stock);END IF;
          ELSIF v_backend_count<>1 THEN v_decision:='conflict';v_reason:='ambiguous_current_navision_identity';v_conflict_count:=v_conflict_count+1;
            IF NOT v_stock=ANY(v_ambiguous_stocks) THEN v_ambiguous_stocks:=array_append(v_ambiguous_stocks,v_stock);END IF;
          ELSE
            SELECT b.canonical_vehicle_id INTO v_vehicle_id FROM public.navision_backend_records b WHERE b.id=v_backend_id;
            IF v_vehicle_id IS NULL THEN v_decision:='quarantine';v_reason:='navision_vehicle_not_activated';v_quarantine_count:=v_quarantine_count+1;
              IF NOT v_stock=ANY(v_unmatched_stocks) THEN v_unmatched_stocks:=array_append(v_unmatched_stocks,v_stock);END IF;
            ELSE
              SELECT count(*) INTO v_vehicle_count FROM public.vehicles v WHERE v.id=v_vehicle_id AND v.deleted_at IS NULL AND v.lifecycle_state::text='active' AND v.stock_number_normalized=v_stock;
              IF v_vehicle_count<>1 THEN v_decision:='quarantine';v_reason:='canonical_vehicle_not_active_for_import';v_quarantine_count:=v_quarantine_count+1;
                IF NOT v_stock=ANY(v_unmatched_stocks) THEN v_unmatched_stocks:=array_append(v_unmatched_stocks,v_stock);END IF;
              ELSE
                IF NOT v_stock=ANY(v_matched_stocks) THEN v_matched_stocks:=array_append(v_matched_stocks,v_stock);END IF;
                SELECT o.semantic_hash INTO v_prior_semantic FROM public.pdc_pilbara_service_operations o WHERE o.importer_version='pilbara_service_open_jobcards_v1'
                  AND o.department IS NULL AND public.pdc_pilbara_service_operation_identity_hash_v2(o.stock_number,o.repair_order_number,o.original_line_number,o.operation_description)=v_identity_hash;
                IF NOT FOUND THEN v_decision:='insert';v_reason:='new_operation';v_insert_count:=v_insert_count+1;v_accepted_count:=v_accepted_count+1;
                ELSIF v_prior_semantic=v_semantic_hash THEN v_decision:='unchanged';v_reason:='same_semantic_hash';v_unchanged_count:=v_unchanged_count+1;v_accepted_count:=v_accepted_count+1;
                ELSE v_decision:='conflict';v_reason:='semantic_identity_changed_requires_review';v_conflict_count:=v_conflict_count+1;END IF;
              END IF;
            END IF;
          END IF;
          END IF;
        END IF;
      END IF;
    END IF;
    v_outcomes:=v_outcomes||jsonb_build_array(jsonb_build_object('source_order',v_source_order,'stock_number',nullif(v_stock,''),'repair_order_number',nullif(v_ro,''),
      'original_line_number',v_line_no,'backend_record_id',v_backend_id,'vehicle_id',v_vehicle_id,'operation_identity_hash',v_identity_hash,'semantic_hash',v_semantic_hash,
      'normalized_payload',CASE WHEN v_identity_hash IS NULL THEN NULL ELSE jsonb_build_object('importer_version','pilbara_service_open_jobcards_v1','stock_number',v_stock,
        'repair_order_number',v_ro,'original_line_number',v_line_no,'source_order',v_source_order,'operation_description',v_descr,'source_estimated_hours',v_source_hours,
        'effective_estimated_hours',v_effective_hours,'hours_provenance',v_provenance,'parts_on_backorder_raw',v_parts_raw,'parts_semantics',v_parts_sem,'classification','Review',
        'operation_identity_hash',v_identity_hash,'semantic_hash',v_semantic_hash,'department',v_dept,'operation_code',v_code,'proposed_station',CASE WHEN v_tune THEN v_station END,'workbook_sha256',v_parent) END,'raw_row',v_raw,'decision',v_decision,'reason',v_reason));
  END LOOP;
  v_response:=jsonb_build_object('ok',true,'code','preview_created','preview_batch_id',v_batch_id,'importer_version','pilbara_service_open_jobcards_v1','source_hash',v_source_hash,
    'source_rows',v_source_count,'accepted_lines',v_accepted_count,'matched',jsonb_build_object('stocks',cardinality(v_matched_stocks),'matched_stock_numbers',to_jsonb(v_matched_stocks)),
    'unmatched',jsonb_build_object('stocks',cardinality(v_unmatched_stocks),'unmatched_stock_numbers',to_jsonb(v_unmatched_stocks)),
    'ambiguous',jsonb_build_object('stocks',cardinality(v_ambiguous_stocks),'ambiguous_stock_numbers',to_jsonb(v_ambiguous_stocks)),
    'operations',jsonb_build_object('insert',v_insert_count,'update',0,'unchanged',v_unchanged_count,'duplicate_ignored',v_duplicate_count,'quarantine',v_quarantine_count,'conflict',v_conflict_count),
    'apply_allowed',(v_accepted_count>0 OR (v_tune AND EXISTS(SELECT 1 FROM jsonb_array_elements(v_outcomes) x WHERE x->>'reason'='unidentified_tune_review'))) AND v_conflict_count=0,'contract_revision',v_revision,'workbook_sha256',v_parent,'partial_batch_policy',CASE WHEN v_tune THEN 'apply_valid_exact_stocks_and_persist_unidentified_separately' ELSE 'apply_exact_active_canonical_matches_and_hold_only_unresolved_rows' END);
  INSERT INTO public.pdc_pilbara_service_import_batches(contract_revision,source_link,batch_id,importer_version,source_hash,request_hash,idempotency_key,batch_kind,source_row_count,accepted_line_count,
    quarantined_line_count,matched_stock_count,unmatched_stock_count,ambiguous_stock_count,insert_count,update_count,unchanged_count,conflict_count,response,created_by,created_actor)
  VALUES(v_revision,CASE WHEN v_tune THEN jsonb_build_object('workbook_sha256',v_parent,'partition_sha256',v_source_hash) ELSE '{}'::jsonb END,v_batch_id,'pilbara_service_open_jobcards_v1',v_source_hash,v_request_hash,v_idem,'preview',v_source_count,v_accepted_count,v_quarantine_count,cardinality(v_matched_stocks),
    cardinality(v_unmatched_stocks),cardinality(v_ambiguous_stocks),v_insert_count,0,v_unchanged_count,v_conflict_count,v_response,v_actor,v_actor_label);
  FOR v_item IN SELECT value AS row_value FROM jsonb_array_elements(v_outcomes) LOOP v_row:=v_item.row_value;
    INSERT INTO public.pdc_pilbara_service_import_rows(batch_id,importer_version,source_order,stock_number,repair_order_number,original_line_number,backend_record_id,semantic_hash,
      normalized_payload,raw_row,decision,reason,vehicle_id)
    VALUES(v_batch_id,'pilbara_service_open_jobcards_v1',(v_row->>'source_order')::integer,v_row->>'stock_number',v_row->>'repair_order_number',
      CASE WHEN v_row->>'original_line_number' IS NULL THEN NULL ELSE (v_row->>'original_line_number')::integer END,
      CASE WHEN v_row->>'backend_record_id' IS NULL THEN NULL ELSE (v_row->>'backend_record_id')::uuid END,v_row->>'semantic_hash',v_row->'normalized_payload',
      coalesce(v_row->'raw_row','{}'::jsonb),v_row->>'decision',v_row->>'reason',CASE WHEN v_row->>'vehicle_id' IS NULL THEN NULL ELSE (v_row->>'vehicle_id')::uuid END);
  END LOOP;
  INSERT INTO public.pdc_pilbara_service_import_receipts(batch_id,importer_version,source_hash,receipt_kind,outcome,created_by,created_actor)
  VALUES(v_batch_id,'pilbara_service_open_jobcards_v1',v_source_hash,CASE WHEN (v_response->>'apply_allowed')::boolean THEN 'preview' ELSE 'blocked' END,v_response,v_actor,v_actor_label);
  RETURN v_response;
END
$function$;
CREATE OR REPLACE FUNCTION public.pdc_pilbara_service_apply_v1(p_preview_batch_id uuid, p_source_hash text, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
 SET lock_timeout TO '5s'
 SET statement_timeout TO '60s'
AS $function$
DECLARE
  v_candidate jsonb; v_stock text; v_tune boolean; v_code text;
  v_actor uuid:=auth.uid();v_actor_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));v_actor_label text:=v_actor_email||':viewer:'||coalesce(v_actor::text,'missing');
  v_source_hash text:=lower(btrim(coalesce(p_source_hash,'')));v_idem text:=btrim(coalesce(p_idempotency_key,''));v_request_hash text;
  v_preview public.pdc_pilbara_service_import_batches%rowtype;v_prior public.pdc_pilbara_service_import_batches%rowtype;v_apply_batch uuid:=gen_random_uuid();
  v_row public.pdc_pilbara_service_import_rows%rowtype;v_op public.pdc_pilbara_service_operations%rowtype;v_vehicle_id uuid;v_first_ro text;v_operation_id uuid;v_identity_hash text;v_response jsonb;
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE OR current_setting('app.environment',true)='production' OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
  THEN RETURN jsonb_build_object('ok',false,'code','wrong_environment');END IF;
  IF NOT public.pdc_email_ai_runtime_authorized_v1() THEN RETURN jsonb_build_object('ok',false,'code','not_authorized');END IF;
  IF p_preview_batch_id IS NULL OR v_source_hash !~ '^[a-f0-9]{64}$' OR length(v_idem) NOT BETWEEN 12 AND 160 THEN RETURN jsonb_build_object('ok',false,'code','invalid_apply_request');END IF;
  SELECT * INTO v_preview FROM public.pdc_pilbara_service_import_batches b WHERE b.batch_id=p_preview_batch_id AND b.importer_version='pilbara_service_open_jobcards_v1' AND b.batch_kind='preview' FOR SHARE;
  IF NOT FOUND OR v_preview.source_hash<>v_source_hash OR NOT coalesce((v_preview.response->>'apply_allowed')::boolean,false) THEN RETURN jsonb_build_object('ok',false,'code','apply_not_eligible');END IF;
  v_tune:=v_preview.contract_revision='pmg_stock_v3';
  v_request_hash:=encode(extensions.digest(convert_to(jsonb_build_object('contract','pdc_pilbara_service_apply_v1_dynamic_20260910','preview_batch_id',p_preview_batch_id,'source_hash',v_source_hash)::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pilbara_service_open_jobcards_v1:apply:'||v_source_hash,0));
  SELECT * INTO v_prior FROM public.pdc_pilbara_service_import_batches b WHERE b.importer_version='pilbara_service_open_jobcards_v1' AND b.source_hash=v_source_hash AND b.batch_kind='apply' AND b.contract_revision=v_preview.contract_revision;
  IF FOUND THEN IF v_prior.request_hash<>v_request_hash THEN RETURN jsonb_build_object('ok',false,'code','source_apply_conflict');END IF;
    INSERT INTO public.pdc_pilbara_service_import_receipts(batch_id,importer_version,source_hash,receipt_kind,outcome,created_by,created_actor)
    VALUES(v_prior.batch_id,'pilbara_service_open_jobcards_v1',v_source_hash,'replay',v_prior.response||jsonb_build_object('code','apply_replay','replay',true),v_actor,v_actor_label);
    RETURN v_prior.response||jsonb_build_object('code','apply_replay','replay',true);END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:top-level-mutation',0));
  IF NOT v_tune AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows r0 LEFT JOIN public.navision_backend_records b ON b.id=r0.backend_record_id LEFT JOIN public.vehicles v ON v.id=r0.vehicle_id
    WHERE r0.batch_id=v_preview.batch_id AND r0.decision IN('insert','unchanged') AND (b.id IS NULL OR NOT b.is_current OR b.record_status<>'current' OR b.source_system<>'microsoft_navision'
      OR b.dealer_code<>'37047' OR b.canonical_vehicle_id IS DISTINCT FROM r0.vehicle_id
      OR btrim(coalesce(b.normalized_data->>'batch',b.normalized_data->>'stock','')) IS DISTINCT FROM btrim(r0.stock_number)
      OR v.id IS NULL OR v.deleted_at IS NOT NULL OR v.lifecycle_state::text<>'active' OR v.stock_number_normalized IS DISTINCT FROM btrim(r0.stock_number)
      OR (SELECT count(*) FROM public.navision_backend_records x WHERE x.source_system='microsoft_navision' AND x.dealer_code='37047' AND x.is_current AND x.record_status='current'
        AND btrim(coalesce(x.normalized_data->>'batch',x.normalized_data->>'stock',''))=btrim(r0.stock_number))<>1))
  THEN RETURN jsonb_build_object('ok',false,'code','apply_cardinality_changed');END IF;
  IF EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows r0 WHERE r0.batch_id=v_preview.batch_id AND r0.decision='insert'
      AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.importer_version='pilbara_service_open_jobcards_v1'
        AND public.pdc_pilbara_service_operation_identity_hash_v3(o.department,o.stock_number,o.repair_order_number,o.original_line_number,o.operation_description)=r0.normalized_payload->>'operation_identity_hash'))
     OR EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows r0 WHERE r0.batch_id=v_preview.batch_id AND r0.decision='unchanged'
      AND NOT EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operations o WHERE o.importer_version='pilbara_service_open_jobcards_v1'
        AND public.pdc_pilbara_service_operation_identity_hash_v3(o.department,o.stock_number,o.repair_order_number,o.original_line_number,o.operation_description)=r0.normalized_payload->>'operation_identity_hash'
        AND o.semantic_hash=r0.semantic_hash))
  THEN RETURN jsonb_build_object('ok',false,'code','operation_state_changed_after_preview');END IF;
  IF v_tune THEN
    -- Serialize Stock creation with all canonical writers and validate every candidate before any write.
    LOCK TABLE public.vehicles IN SHARE ROW EXCLUSIVE MODE;
    FOR v_row IN SELECT * FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged') ORDER BY stock_number LOOP
      v_candidate:=public.pdc_pmg_stock_candidate_v3(v_row.stock_number);
      IF (v_candidate->>'ok')::boolean IS NOT TRUE
        OR (v_row.vehicle_id IS NOT NULL AND v_row.vehicle_id IS DISTINCT FROM (v_candidate->>'vehicle_id')::uuid)
        OR v_row.backend_record_id IS DISTINCT FROM (v_candidate->>'backend_record_id')::uuid
      THEN RETURN jsonb_build_object('ok',false,'code','apply_cardinality_changed','stock_number',v_row.stock_number); END IF;
    END LOOP;
  END IF;
  IF v_tune AND EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows r JOIN public.pdc_unidentified_tune_review u ON u.workbook_sha256=r.normalized_payload->>'workbook_sha256' AND u.operation_identity_hash=r.normalized_payload->>'operation_identity_hash'
    WHERE r.batch_id=v_preview.batch_id AND r.reason='unidentified_tune_review' AND (u.source_estimated_hours IS DISTINCT FROM (r.normalized_payload->>'source_estimated_hours')::numeric OR u.raw_row IS DISTINCT FROM r.raw_row))
  THEN RETURN jsonb_build_object('ok',false,'code','unidentified_source_changed'); END IF;
  v_response:=jsonb_build_object('ok',true,'code','applied','replay',false,'apply_batch_id',v_apply_batch,'source_hash',v_source_hash,'source_link',v_preview.source_link,'unidentified_rows',(SELECT count(*) FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND reason='unidentified_tune_review'),'approvals_created',0,'insert',v_preview.insert_count,'update',0,
    'unchanged',v_preview.unchanged_count,'duplicate_ignored',coalesce((v_preview.response->'operations'->>'duplicate_ignored')::integer,0),'bookings_created',0,'completions_created',0,'atomic',true);
  INSERT INTO public.pdc_pilbara_service_import_batches(contract_revision,source_link,batch_id,importer_version,source_hash,request_hash,idempotency_key,batch_kind,source_row_count,accepted_line_count,quarantined_line_count,
    matched_stock_count,unmatched_stock_count,ambiguous_stock_count,insert_count,update_count,unchanged_count,conflict_count,response,created_by,created_actor)
  VALUES(v_preview.contract_revision,v_preview.source_link,v_apply_batch,'pilbara_service_open_jobcards_v1',v_source_hash,v_request_hash,v_idem,'apply',v_preview.source_row_count,v_preview.accepted_line_count,v_preview.quarantined_line_count,
    v_preview.matched_stock_count,v_preview.unmatched_stock_count,v_preview.ambiguous_stock_count,v_preview.insert_count,0,v_preview.unchanged_count,v_preview.conflict_count,v_response,v_actor,v_actor_label);
  IF v_tune THEN
    FOR v_stock IN SELECT DISTINCT stock_number FROM public.pdc_pilbara_service_import_rows WHERE batch_id=v_preview.batch_id AND decision IN('insert','unchanged') ORDER BY stock_number LOOP
      v_candidate:=public.pdc_pmg_stock_candidate_v3(v_stock);
      IF (v_candidate->>'create_vehicle')::boolean THEN
        INSERT INTO public.vehicles(permanent_vehicle_id,stock_number,vin,source_system,source_record_id,current_location,visible_on_board,lifecycle_state,created_by,updated_by,source_payload)
        VALUES('TUNE/PMG:'||v_stock,v_stock,NULL,'tune_pmg',v_stock,'Yard Hold',false,'active',v_actor,v_actor,v_preview.source_link);
      END IF;
    END LOOP;
    INSERT INTO public.pdc_unidentified_tune_review(workbook_sha256,repair_order_number,department,original_line_number,operation_description,operation_identity_hash,source_estimated_hours,operation_code,proposed_station,raw_row,source_hash,source_batch_id)
    SELECT r.normalized_payload->>'workbook_sha256',r.repair_order_number,r.normalized_payload->>'department',r.original_line_number,r.normalized_payload->>'operation_description',r.normalized_payload->>'operation_identity_hash',
      (r.normalized_payload->>'source_estimated_hours')::numeric,r.normalized_payload->>'operation_code',r.normalized_payload->>'proposed_station',r.raw_row,v_source_hash,v_apply_batch
    FROM public.pdc_pilbara_service_import_rows r WHERE r.batch_id=v_preview.batch_id AND r.reason='unidentified_tune_review'
    ON CONFLICT(workbook_sha256,operation_identity_hash) DO NOTHING;
  END IF;
  FOR v_row IN SELECT * FROM public.pdc_pilbara_service_import_rows r WHERE r.batch_id=v_preview.batch_id AND r.decision IN('insert','unchanged') ORDER BY r.source_order LOOP
    IF v_tune THEN SELECT id INTO STRICT v_row.vehicle_id FROM public.vehicles WHERE stock_number_normalized=public.normalize_vehicle_stock_number(v_row.stock_number) AND deleted_at IS NULL; END IF;
    v_identity_hash:=v_row.normalized_payload->>'operation_identity_hash';
    SELECT * INTO v_op FROM public.pdc_pilbara_service_operations x WHERE x.importer_version='pilbara_service_open_jobcards_v1'
      AND public.pdc_pilbara_service_operation_identity_hash_v3(x.department,x.stock_number,x.repair_order_number,x.original_line_number,x.operation_description)=v_identity_hash FOR SHARE;
    IF v_row.decision='insert' THEN
      IF FOUND THEN RAISE EXCEPTION 'operation state changed after preview' USING ERRCODE='40001';END IF;
      INSERT INTO public.pdc_pilbara_service_operations(department,operation_code,proposed_station,importer_version,stock_number,repair_order_number,original_line_number,source_order,vehicle_id,operation_description,
        source_estimated_hours,effective_estimated_hours,hours_provenance,parts_on_backorder_raw,parts_semantics,classification,semantic_hash,raw_evidence_id)
      VALUES(v_row.normalized_payload->>'department',v_row.normalized_payload->>'operation_code',v_row.normalized_payload->>'proposed_station','pilbara_service_open_jobcards_v1',v_row.stock_number,v_row.repair_order_number,v_row.original_line_number,v_row.source_order,v_row.vehicle_id,v_row.normalized_payload->>'operation_description',
        CASE WHEN v_row.normalized_payload->>'source_estimated_hours' IS NULL THEN NULL ELSE (v_row.normalized_payload->>'source_estimated_hours')::numeric END,
        (v_row.normalized_payload->>'effective_estimated_hours')::numeric,v_row.normalized_payload->>'hours_provenance',coalesce(v_row.normalized_payload->>'parts_on_backorder_raw',''),
        v_row.normalized_payload->>'parts_semantics','Review',v_row.semantic_hash,v_row.evidence_id) RETURNING operation_id INTO v_operation_id;
      INSERT INTO public.pdc_pilbara_service_operation_history(operation_id,batch_id,event_kind,prior_semantic_hash,resulting_semantic_hash,immutable_snapshot)
      VALUES(v_operation_id,v_apply_batch,'insert',NULL,v_row.semantic_hash,v_row.normalized_payload);
    ELSE
      IF NOT FOUND OR v_op.semantic_hash<>v_row.semantic_hash THEN RAISE EXCEPTION 'operation state changed after preview' USING ERRCODE='40001';END IF;
      v_operation_id:=v_op.operation_id;
      INSERT INTO public.pdc_pilbara_service_operation_history(operation_id,batch_id,event_kind,prior_semantic_hash,resulting_semantic_hash,immutable_snapshot)
      VALUES(v_operation_id,v_apply_batch,'unchanged',v_op.semantic_hash,v_op.semantic_hash,v_row.normalized_payload);
    END IF;
  END LOOP;
  FOR v_vehicle_id IN SELECT DISTINCT o.vehicle_id FROM public.pdc_pilbara_service_operation_history h JOIN public.pdc_pilbara_service_operations o USING(operation_id) WHERE h.batch_id=v_apply_batch LOOP
    FOR v_op IN SELECT old.* FROM public.pdc_pilbara_service_operations old WHERE old.vehicle_id=v_vehicle_id
      AND NOT EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows cur WHERE cur.batch_id=v_preview.batch_id AND (cur.vehicle_id=v_vehicle_id OR (v_tune AND cur.stock_number=(SELECT stock_number FROM public.vehicles WHERE id=v_vehicle_id))) AND cur.decision IN('insert','unchanged')
        AND cur.normalized_payload->>'operation_identity_hash'=public.pdc_pilbara_service_operation_identity_hash_v3(old.department,old.stock_number,old.repair_order_number,old.original_line_number,old.operation_description)) LOOP
      INSERT INTO public.vehicle_workshop_line_adjustments(vehicle_id,line_key,source_kind,stage_code,description,estimated_hours,active,version,manual_assignment_locked,created_by,updated_by)
      VALUES(v_vehicle_id,'source:'||v_op.operation_id::text,'source','UNALLOCATED_MAPPING_REVIEW',left(btrim(v_op.operation_description),180),v_op.effective_estimated_hours,false,1,false,v_actor,v_actor)
      ON CONFLICT(vehicle_id,line_key) DO UPDATE SET active=false,version=public.vehicle_workshop_line_adjustments.version+1,updated_by=v_actor,updated_at=clock_timestamp();
    END LOOP;
    SELECT CASE WHEN count(DISTINCT r0.repair_order_number)=1 THEN min(r0.repair_order_number) ELSE NULL END INTO v_first_ro FROM public.pdc_pilbara_service_import_rows r0
    WHERE r0.batch_id=v_preview.batch_id AND (r0.vehicle_id=v_vehicle_id OR (v_tune AND r0.stock_number=(SELECT stock_number FROM public.vehicles WHERE id=v_vehicle_id))) AND r0.decision IN('insert','unchanged');
    IF EXISTS(SELECT 1 FROM public.vehicles v WHERE v.id=v_vehicle_id AND NOT v.visible_on_board) THEN
      INSERT INTO public.pdc_new_vehicle_reviews(vehicle_id,status,source_kind,first_job_card,received_at,approved_at,approved_by,approval_key,approval_hash,approval_receipt)
      VALUES(v_vehicle_id,'pending',CASE WHEN v_tune THEN 'tune_pmg' ELSE 'revolution_report' END,v_first_ro,clock_timestamp(),NULL,NULL,NULL,NULL,NULL)
      ON CONFLICT(vehicle_id) DO UPDATE SET status='pending',source_kind=excluded.source_kind,first_job_card=excluded.first_job_card,received_at=clock_timestamp(),
        approved_at=NULL,approved_by=NULL,approval_key=NULL,approval_hash=NULL,approval_receipt=NULL;
      UPDATE public.vehicles SET job_card_number=v_first_ro,version=version+1,updated_by=v_actor,updated_at=clock_timestamp() WHERE id=v_vehicle_id AND visible_on_board=false;
    END IF;
  END LOOP;
  INSERT INTO public.pdc_pilbara_service_import_receipts(batch_id,importer_version,source_hash,receipt_kind,outcome,created_by,created_actor)
  VALUES(v_apply_batch,'pilbara_service_open_jobcards_v1',v_source_hash,'apply',v_response,v_actor,v_actor_label);
  UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;
  UPDATE public.navision_backend_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;
  PERFORM public.workshop_bump_revision();
  RETURN v_response;
END
$function$;
CREATE OR REPLACE FUNCTION public.pdc_qc_operation_lines_379(p_vehicle_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
 WITH source_lines AS(
  SELECT 'source:'||ol.operation_line_id::text line_identity,'authenticated' source_kind,ol.operation_line_id source_line_id,
   ol.operation_no,ol.description,
   coalesce(nullif(btrim(ol.job_card_number),''),nullif(btrim(v.job_card_number),'')) job_card_number,
   coalesce(a.estimated_hours,ol.estimated_hours) estimated_hours,
   CASE
    WHEN coalesce(a.stage_code,public.workshop_stage_code_for_work_key(ol.work_key)) IN
      ('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET')
    THEN coalesce(a.stage_code,public.workshop_stage_code_for_work_key(ol.work_key))
    ELSE 'UNALLOCATED_MAPPING_REVIEW'
   END stage_code,
   coalesce(a.active,true) active
  FROM public.pdc_authenticated_email_operation_lines ol
  JOIN public.vehicles v ON v.id=ol.vehicle_id
  LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=ol.vehicle_id AND a.line_key='source:'||ol.operation_line_id::text
  WHERE ol.vehicle_id=p_vehicle_id
 ), manual_lines AS(
  SELECT 'manual:'||a.adjustment_id::text,'manual',a.adjustment_id,'MANUAL',a.description,
   coalesce(nullif(btrim(a.job_card_number),''),nullif(btrim(v.job_card_number),'')),a.estimated_hours,
   CASE WHEN a.stage_code IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET') THEN a.stage_code ELSE 'UNALLOCATED_MAPPING_REVIEW' END,
   a.active
  FROM public.vehicle_workshop_line_adjustments a
  JOIN public.vehicles v ON v.id=a.vehicle_id
  WHERE a.vehicle_id=p_vehicle_id AND a.source_kind='manual'
 ), pilbara_lines AS(
  SELECT 'source:'||o.operation_id::text,'authenticated',o.operation_id,
   'PD'||lpad(o.original_line_number::text,3,'0')||'-'||upper(substr(o.semantic_hash,1,8)),
   o.operation_description,o.repair_order_number,
   CASE WHEN a.adjustment_id IS NOT NULL THEN a.estimated_hours ELSE o.effective_estimated_hours END,
   CASE WHEN CASE WHEN o.department='138' THEN 'BUS_4X4' ELSE coalesce(a.stage_code,h.category,o.proposed_station) END IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET')
        THEN CASE WHEN o.department='138' THEN 'BUS_4X4' ELSE coalesce(a.stage_code,h.category,o.proposed_station) END ELSE 'UNALLOCATED_MAPPING_REVIEW' END,
   coalesce(a.active,true)
  FROM public.pdc_pilbara_service_operations o
  JOIN public.vehicles v ON v.id=o.vehicle_id AND v.stock_number=o.stock_number
  LEFT JOIN public.pdc_pilbara_service_classification_current cc USING(operation_id)
  LEFT JOIN public.pdc_pilbara_service_classification_history h USING(classification_id)
  LEFT JOIN public.vehicle_workshop_line_adjustments a ON a.vehicle_id=o.vehicle_id AND a.line_key='source:'||o.operation_id::text
  WHERE o.vehicle_id=p_vehicle_id
 ), all_lines AS(SELECT * FROM source_lines UNION ALL SELECT * FROM manual_lines UNION ALL SELECT * FROM pilbara_lines)
 SELECT coalesce(jsonb_agg(jsonb_build_object('line_identity',l.line_identity,'source_kind',l.source_kind,'source_line_id',l.source_line_id,
  'operation_no',l.operation_no,'description',l.description,'job_card_number',l.job_card_number,'estimated_hours',l.estimated_hours,
  'stage_code',l.stage_code,'active',l.active,'completed',coalesce(c.completed,false),'completed_by',c.completed_by,'completed_at',c.completed_at,
  'line_version',coalesce(c.version,0),'rejected',coalesce(r.active,false),'rejection_reason',case when r.active then r.reason else null end,
  'rejected_by',case when r.active then r.rejected_by else null end,'rejected_at',case when r.active then r.rejected_at else null end,
  'rework_booking_id',case when r.active then r.rejection_id else null end)
  || CASE WHEN ps.operation_id IS NOT NULL THEN jsonb_build_object('source_contract','pilbara_service_open_jobcards_v1','source_evidence_id',ps.raw_evidence_id,'department',ps.department,'original_line_number',ps.original_line_number,'operation_code',coalesce((SELECT h.immutable_snapshot->>'operation_code' FROM public.pdc_pilbara_service_operation_history h WHERE h.operation_id=ps.operation_id AND nullif(h.immutable_snapshot->>'operation_code','') IS NOT NULL ORDER BY h.created_at DESC LIMIT 1),ps.operation_code),'proposed_station',ps.proposed_station) ELSE '{}'::jsonb END
  ORDER BY CASE WHEN l.stage_code='UNALLOCATED_MAPPING_REVIEW' THEN 2 WHEN l.stage_code='SUBLET' THEN 1 ELSE 0 END,l.stage_code,substring(l.operation_no from '[0-9]+')::integer NULLS LAST,l.operation_no,l.line_identity),'[]'::jsonb)
 FROM all_lines l
 LEFT JOIN public.pdc_pilbara_service_operations ps ON ps.vehicle_id=p_vehicle_id AND ps.operation_id=l.source_line_id AND l.source_kind='authenticated'
 LEFT JOIN public.pdc_qc_operation_completions_379 c ON c.vehicle_id=p_vehicle_id AND c.line_identity=l.line_identity
 LEFT JOIN public.pdc_qc_operation_rejections_381 r ON r.vehicle_id=p_vehicle_id AND r.line_identity=l.line_identity
$function$;
CREATE OR REPLACE FUNCTION public.pdc_pilbara_service_classification_preview_v2(p_source_batch_id uuid, p_classifications jsonb, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
 SET lock_timeout TO '5s'
 SET statement_timeout TO '60s'
AS $function$
DECLARE
  b public.pdc_pilbara_service_import_batches%rowtype;
  prior public.pdc_pilbara_service_classification_batches%rowtype;
  rowj jsonb; o public.pdc_pilbara_service_operations%rowtype;
  v_batch_id uuid:=gen_random_uuid(); idem text:=btrim(coalesce(p_idempotency_key,''));
  state_hash text; manifest jsonb; manifest_hash text; response jsonb;
  op_count integer; insert_count integer:=0; update_count integer:=0; unchanged_count integer:=0; review_count integer:=0;
  category text; method text; confidence numeric; current_h public.pdc_pilbara_service_classification_history%rowtype;
  actor_label text:=lower(btrim(coalesce(auth.jwt()->>'email','')))||':viewer:'||coalesce(auth.uid()::text,'missing');
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'code','wrong_environment'); END IF;
  IF NOT public.pdc_email_ai_runtime_authorized_v1() THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
  IF p_source_batch_id IS NULL OR jsonb_typeof(p_classifications) IS DISTINCT FROM 'array'
     OR length(idem) NOT BETWEEN 12 AND 160 THEN RETURN jsonb_build_object('ok',false,'code','invalid_classification_request'); END IF;
  SELECT * INTO b FROM public.pdc_pilbara_service_import_batches WHERE batch_id=p_source_batch_id AND batch_kind='apply' AND importer_version='pilbara_service_open_jobcards_v1' FOR SHARE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','source_apply_batch_not_found'); END IF;
  SELECT count(DISTINCT oh.operation_id) INTO op_count FROM public.pdc_pilbara_service_operation_history oh WHERE oh.batch_id=b.batch_id;
  IF op_count<1 OR jsonb_array_length(p_classifications)<>op_count
     OR (SELECT count(DISTINCT value->>'operation_id') FROM jsonb_array_elements(p_classifications))<>op_count THEN
    RETURN jsonb_build_object('ok',false,'code','all_operations_require_one_classification','expected',op_count,'received',jsonb_array_length(p_classifications));
  END IF;
  manifest:=jsonb_build_object('contract','pilbara_service_operation_classifier_v2','classifier_version','pdc-email-ai-station-classifier-v2',
    'source_batch_id',b.batch_id,'source_hash',b.source_hash,'classifications',p_classifications);
  manifest_hash:=encode(extensions.digest(convert_to(manifest::text,'UTF8'),'sha256'),'hex');
  PERFORM pg_advisory_xact_lock(hashtextextended('pilbara_service_operation_classifier_v2:preview:'||idem,0));
  SELECT * INTO prior FROM public.pdc_pilbara_service_classification_batches WHERE batch_kind='preview' AND idempotency_key=idem;
  IF FOUND THEN
    IF prior.manifest_hash<>manifest_hash THEN RETURN jsonb_build_object('ok',false,'code','idempotency_conflict'); END IF;
    RETURN prior.response||jsonb_build_object('code','preview_replay','replay',true);
  END IF;
  FOR rowj IN SELECT value FROM jsonb_array_elements(p_classifications) LOOP
    BEGIN
      category:=upper(btrim(coalesce(rowj->>'category',''))); method:=lower(btrim(coalesce(rowj->>'method',''))); confidence:=(rowj->>'confidence')::numeric;
    EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
      RETURN jsonb_build_object('ok',false,'code','classification_schema_failed');
    END;
    IF jsonb_typeof(rowj) IS DISTINCT FROM 'object' OR coalesce(rowj->>'operation_id','') !~ '^[0-9a-fA-F-]{36}$'
       OR category NOT IN('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET','REVIEW')
       OR method NOT IN('deterministic_rule','ai_semantic','review') OR confidence NOT BETWEEN 0 AND 1
       OR length(btrim(coalesce(rowj->>'rationale',''))) NOT BETWEEN 3 AND 240
       OR coalesce(rowj->>'source_semantic_hash','') !~ '^[a-f0-9]{64}$'
       OR coalesce(rowj->>'source_description_hash','') !~ '^[a-f0-9]{64}$'
       OR (category='REVIEW' AND (method<>'review' OR confidence>=0.80))
       OR (category<>'REVIEW' AND confidence<0.80)
       OR (method='deterministic_rule' AND (nullif(btrim(coalesce(rowj->>'rule_id','')),'') IS NULL OR nullif(btrim(coalesce(rowj->>'ruleset_version','')),'') IS NULL
            OR nullif(btrim(coalesce(rowj->>'provider','')),'') IS NOT NULL OR nullif(btrim(coalesce(rowj->>'model','')),'') IS NOT NULL OR nullif(btrim(coalesce(rowj->>'run_id','')),'') IS NOT NULL))
       OR (method IN('ai_semantic','review') AND (nullif(btrim(coalesce(rowj->>'rule_id','')),'') IS NOT NULL OR nullif(btrim(coalesce(rowj->>'ruleset_version','')),'') IS NOT NULL
            OR nullif(btrim(coalesce(rowj->>'provider','')),'') IS NULL OR nullif(btrim(coalesce(rowj->>'model','')),'') IS NULL OR nullif(btrim(coalesce(rowj->>'run_id','')),'') IS NULL)) THEN
      RETURN jsonb_build_object('ok',false,'code','classification_contract_failed','operation_id',rowj->>'operation_id');
    END IF;
    SELECT op.* INTO o FROM public.pdc_pilbara_service_operations op
      JOIN public.pdc_pilbara_service_operation_history oh ON oh.operation_id=op.operation_id AND oh.batch_id=b.batch_id
      WHERE op.operation_id=(rowj->>'operation_id')::uuid;
    IF NOT FOUND OR o.semantic_hash IS DISTINCT FROM rowj->>'source_semantic_hash'
       OR encode(extensions.digest(convert_to(o.operation_description,'UTF8'),'sha256'),'hex') IS DISTINCT FROM rowj->>'source_description_hash' THEN
      RETURN jsonb_build_object('ok',false,'code','source_binding_conflict','operation_id',rowj->>'operation_id');
    END IF;
    IF o.department='138' AND category<>'BUS_4X4' THEN RETURN jsonb_build_object('ok',false,'code','department_138_override'); END IF;
    SELECT h.* INTO current_h FROM public.pdc_pilbara_service_classification_current cc JOIN public.pdc_pilbara_service_classification_history h USING(classification_id) WHERE cc.operation_id=o.operation_id;
    IF NOT FOUND THEN insert_count:=insert_count+1;
    ELSIF current_h.category=category AND current_h.method=method AND current_h.confidence=confidence AND current_h.rationale=rowj->>'rationale'
      AND coalesce(current_h.rule_id,'')=coalesce(rowj->>'rule_id','') AND coalesce(current_h.ruleset_version,'')=coalesce(rowj->>'ruleset_version','')
      AND coalesce(current_h.provider,'')=coalesce(rowj->>'provider','') AND coalesce(current_h.model,'')=coalesce(rowj->>'model','')
      AND coalesce(current_h.model_run_id,'')=coalesce(rowj->>'run_id','') AND current_h.source_semantic_hash=o.semantic_hash
      THEN unchanged_count:=unchanged_count+1;
    ELSE update_count:=update_count+1; END IF;
    IF category='REVIEW' THEN review_count:=review_count+1; END IF;
  END LOOP;
  state_hash:=public.pdc_pilbara_service_classification_source_state_hash_v2(b.batch_id);
  response:=jsonb_build_object('ok',true,'code','preview_created','preview_batch_id',v_batch_id,'source_batch_id',b.batch_id,'source_hash',b.source_hash,
    'operation_count',op_count,'insert',insert_count,'update',update_count,'unchanged',unchanged_count,'review',review_count,'assigned',op_count-review_count,
    'category_totals',(SELECT jsonb_object_agg(q.category,q.total) FROM (SELECT upper(value->>'category') category,count(*) total FROM jsonb_array_elements(p_classifications) GROUP BY 1 ORDER BY 1) q),
    'apply_allowed',true,'booking_changes',0,'completion_changes',0);
  INSERT INTO public.pdc_pilbara_service_classification_batches(batch_id,contract,batch_kind,source_importer_version,source_batch_id,classifier_version,
    manifest_hash,idempotency_key,current_state_hash,manifest,response,created_actor)
  VALUES(v_batch_id,'pilbara_service_operation_classifier_v2','preview','pilbara_service_open_jobcards_v1',b.batch_id,'pdc-email-ai-station-classifier-v2',
    manifest_hash,idem,state_hash,manifest,response,actor_label);
  RETURN response;
END
$function$;
CREATE OR REPLACE FUNCTION public.pdc_pilbara_service_classification_apply_v2(p_preview_batch_id uuid, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
 SET lock_timeout TO '5s'
 SET statement_timeout TO '60s'
AS $function$
DECLARE
  preview public.pdc_pilbara_service_classification_batches%rowtype;
  prior public.pdc_pilbara_service_classification_batches%rowtype;
  rowj jsonb; o public.pdc_pilbara_service_operations%rowtype; current_h public.pdc_pilbara_service_classification_history%rowtype;
  new_id uuid; version_no integer; v_batch_id uuid:=gen_random_uuid(); idem text:=btrim(coalesce(p_idempotency_key,''));
  state_hash text; v_response jsonb; inserted integer:=0; updated integer:=0; unchanged integer:=0;
  actor_label text:=lower(btrim(coalesce(auth.jwt()->>'email','')))||':viewer:'||coalesce(auth.uid()::text,'missing');
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'code','wrong_environment'); END IF;
  IF NOT public.pdc_email_ai_runtime_authorized_v1() THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
  IF p_preview_batch_id IS NULL OR length(idem) NOT BETWEEN 12 AND 160 THEN RETURN jsonb_build_object('ok',false,'code','invalid_apply_request'); END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('pilbara_service_operation_classifier_v2:apply:'||idem,0));
  SELECT * INTO preview FROM public.pdc_pilbara_service_classification_batches WHERE batch_id=p_preview_batch_id AND batch_kind='preview' AND contract='pilbara_service_operation_classifier_v2' FOR SHARE;
  IF NOT FOUND OR coalesce((preview.response->>'apply_allowed')::boolean,false) IS NOT TRUE THEN RETURN jsonb_build_object('ok',false,'code','preview_not_eligible'); END IF;
  SELECT * INTO prior FROM public.pdc_pilbara_service_classification_batches WHERE batch_kind='apply' AND idempotency_key=idem;
  IF FOUND THEN
    IF prior.preview_of_batch_id IS DISTINCT FROM preview.batch_id OR prior.manifest_hash<>preview.manifest_hash THEN RETURN jsonb_build_object('ok',false,'code','idempotency_conflict'); END IF;
    RETURN prior.response||jsonb_build_object('code','apply_replay','replay',true);
  END IF;
  state_hash:=public.pdc_pilbara_service_classification_source_state_hash_v2(preview.source_batch_id);
  IF state_hash<>preview.current_state_hash THEN RETURN jsonb_build_object('ok',false,'code','current_state_changed'); END IF;
  FOR rowj IN SELECT value FROM jsonb_array_elements(preview.manifest->'classifications') LOOP
    SELECT op.* INTO o FROM public.pdc_pilbara_service_operations op
      JOIN public.pdc_pilbara_service_operation_history oh ON oh.operation_id=op.operation_id AND oh.batch_id=preview.source_batch_id
      WHERE op.operation_id=(rowj->>'operation_id')::uuid;
    IF o.department='138' AND upper(rowj->>'category')<>'BUS_4X4' THEN RETURN jsonb_build_object('ok',false,'code','department_138_override'); END IF;
    IF NOT FOUND OR o.semantic_hash IS DISTINCT FROM rowj->>'source_semantic_hash'
       OR encode(extensions.digest(convert_to(o.operation_description,'UTF8'),'sha256'),'hex') IS DISTINCT FROM rowj->>'source_description_hash' THEN
      RETURN jsonb_build_object('ok',false,'code','source_binding_conflict','operation_id',rowj->>'operation_id');
    END IF;
  END LOOP;
  v_response:=jsonb_build_object('ok',true,'code','applied','apply_batch_id',v_batch_id,'source_batch_id',preview.source_batch_id,
    'operation_count',preview.response->'operation_count','assigned',preview.response->'assigned','review',preview.response->'review','category_totals',preview.response->'category_totals',
    'booking_changes',0,'completion_changes',0,'work_item_changes',0,'atomic',true,'replay',false);
  INSERT INTO public.pdc_pilbara_service_classification_batches(batch_id,contract,batch_kind,source_importer_version,source_batch_id,classifier_version,
    manifest_hash,idempotency_key,current_state_hash,manifest,response,preview_of_batch_id,created_actor)
  VALUES(v_batch_id,'pilbara_service_operation_classifier_v2','apply',preview.source_importer_version,preview.source_batch_id,preview.classifier_version,
    preview.manifest_hash,idem,preview.current_state_hash,preview.manifest,'{}'::jsonb,preview.batch_id,actor_label);
  FOR rowj IN SELECT value FROM jsonb_array_elements(preview.manifest->'classifications') LOOP
    SELECT * INTO o FROM public.pdc_pilbara_service_operations WHERE operation_id=(rowj->>'operation_id')::uuid FOR SHARE;
    SELECT h.* INTO current_h FROM public.pdc_pilbara_service_classification_current cc JOIN public.pdc_pilbara_service_classification_history h USING(classification_id) WHERE cc.operation_id=o.operation_id FOR SHARE OF h;
    IF FOUND AND current_h.category=upper(rowj->>'category') AND current_h.method=lower(rowj->>'method') AND current_h.confidence=(rowj->>'confidence')::numeric
       AND current_h.rationale=rowj->>'rationale' AND coalesce(current_h.rule_id,'')=coalesce(rowj->>'rule_id','')
       AND coalesce(current_h.ruleset_version,'')=coalesce(rowj->>'ruleset_version','') AND coalesce(current_h.provider,'')=coalesce(rowj->>'provider','')
       AND coalesce(current_h.model,'')=coalesce(rowj->>'model','') AND coalesce(current_h.model_run_id,'')=coalesce(rowj->>'run_id','')
       AND current_h.source_semantic_hash=o.semantic_hash THEN unchanged:=unchanged+1; CONTINUE; END IF;
    SELECT coalesce(max(classification_version),0)+1 INTO version_no FROM public.pdc_pilbara_service_classification_history WHERE operation_id=o.operation_id;
    INSERT INTO public.pdc_pilbara_service_classification_history(operation_id,batch_id,classification_version,category,method,confidence,rationale,
      rule_id,ruleset_version,provider,model,model_run_id,source_description_hash,source_semantic_hash,classifier_version,supersedes_classification_id)
    VALUES(o.operation_id,v_batch_id,version_no,upper(rowj->>'category'),lower(rowj->>'method'),(rowj->>'confidence')::numeric,rowj->>'rationale',
      nullif(rowj->>'rule_id',''),nullif(rowj->>'ruleset_version',''),nullif(rowj->>'provider',''),nullif(rowj->>'model',''),nullif(rowj->>'run_id',''),
      rowj->>'source_description_hash',rowj->>'source_semantic_hash',preview.classifier_version,current_h.classification_id)
    RETURNING classification_id INTO new_id;
    INSERT INTO public.pdc_pilbara_service_classification_current(operation_id,classification_id) VALUES(o.operation_id,new_id)
      ON CONFLICT(operation_id) DO UPDATE SET classification_id=excluded.classification_id,updated_at=clock_timestamp();
    IF current_h.classification_id IS NULL THEN inserted:=inserted+1; ELSE updated:=updated+1; END IF;
  END LOOP;
  v_response:=v_response||jsonb_build_object('insert',inserted,'update',updated,'unchanged',unchanged);
  UPDATE public.pdc_pilbara_service_classification_batches SET response=v_response WHERE pdc_pilbara_service_classification_batches.batch_id=v_batch_id;
  UPDATE public.pdc_email_vehicle_revision SET revision=revision+1,updated_at=clock_timestamp() WHERE singleton;
  RETURN v_response;
END
$function$;
CREATE OR REPLACE FUNCTION public.pdc_pilbara_service_classification_source_v2(p_source_batch_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
 SET statement_timeout TO '30s'
AS $function$
DECLARE
  b public.pdc_pilbara_service_import_batches%rowtype;
  n integer;
BEGIN
  IF public.pdc_monitor_staging_guard() IS NOT TRUE
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RETURN jsonb_build_object('ok',false,'code','wrong_environment');
  END IF;
  IF NOT public.pdc_email_ai_runtime_authorized_v1() THEN
    RETURN jsonb_build_object('ok',false,'code','not_authorized');
  END IF;
  SELECT * INTO b FROM public.pdc_pilbara_service_import_batches
   WHERE batch_id=p_source_batch_id AND batch_kind='apply'
     AND importer_version='pilbara_service_open_jobcards_v1';
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','source_apply_batch_not_found'); END IF;
  SELECT count(DISTINCT oh.operation_id) INTO n
  FROM public.pdc_pilbara_service_operation_history oh WHERE oh.batch_id=b.batch_id;
  IF n<1 THEN RETURN jsonb_build_object('ok',false,'code','source_apply_batch_has_no_operations'); END IF;
  RETURN jsonb_build_object(
    'ok',true,'code','classification_source_ready','source_batch_id',b.batch_id,'source_hash',b.source_hash,
    'operation_count',n,
    'operations',(SELECT jsonb_agg(jsonb_build_object(
      'operation_id',o.operation_id,'department',o.department,'operation_code',o.operation_code,'proposed_station',o.proposed_station,'proposal_provenance',(SELECT r.raw_row->'classification' FROM public.pdc_pilbara_service_import_rows r WHERE r.evidence_id=o.raw_evidence_id),'vehicle_id',o.vehicle_id,'stock_number',o.stock_number,
      'repair_order_number',o.repair_order_number,'original_line_number',o.original_line_number,
      'operation_description',o.operation_description,'estimated_hours',o.effective_estimated_hours,
      'source_semantic_hash',o.semantic_hash,
      'source_description_hash',encode(extensions.digest(convert_to(o.operation_description,'UTF8'),'sha256'),'hex'),
      'current_category',h.category,'current_method',h.method,'current_confidence',h.confidence,
      'prior_exact_description_hint',(SELECT jsonb_build_object('category',ph.category,'method',ph.method,'confidence',ph.confidence,'rationale',ph.rationale)
        FROM public.pdc_pilbara_service_operations po
        JOIN public.pdc_pilbara_service_classification_current pc ON pc.operation_id=po.operation_id
        JOIN public.pdc_pilbara_service_classification_history ph ON ph.classification_id=pc.classification_id
        WHERE po.operation_id<>o.operation_id
          AND lower(regexp_replace(btrim(po.operation_description),'[^a-z0-9]+','','g'))=lower(regexp_replace(btrim(o.operation_description),'[^a-z0-9]+','','g'))
        ORDER BY ph.confidence DESC,ph.created_at DESC LIMIT 1)
    ) ORDER BY o.stock_number,o.repair_order_number,o.source_order,o.operation_id)
    FROM public.pdc_pilbara_service_operation_history oh
    JOIN public.pdc_pilbara_service_operations o ON o.operation_id=oh.operation_id
    LEFT JOIN public.pdc_pilbara_service_classification_current cc ON cc.operation_id=o.operation_id
    LEFT JOIN public.pdc_pilbara_service_classification_history h ON h.classification_id=cc.classification_id
    WHERE oh.batch_id=b.batch_id),
    'allowed_stations',jsonb_build_array('BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','SUBLET','REVIEW'),
    'confidence_rule','assign station at >=0.80; use REVIEW below 0.80',
    'booking_changes',0,'completion_changes',0
  );
END
$function$;
CREATE FUNCTION public.pdc_pmg_intake_readback_v3(p_apply_batch_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE b public.pdc_pilbara_service_import_batches%rowtype; vehicles_json jsonb; unbound jsonb;
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR NOT public.pdc_email_ai_runtime_authorized_v1()
 THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
 SELECT * INTO b FROM public.pdc_pilbara_service_import_batches WHERE batch_id=p_apply_batch_id AND batch_kind='apply' AND contract_revision='pmg_stock_v3';
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','batch_not_found'); END IF;
 SELECT coalesce(jsonb_agg(public.pdc_new_vehicle_review_row(v.id)||jsonb_build_object('visible_on_board',v.visible_on_board,'lifecycle_state',v.lifecycle_state,'source_system',v.source_system,'backend_record_id',
   (SELECT min(n.id::text) FROM public.navision_backend_records n WHERE n.canonical_vehicle_id=v.id AND n.is_current AND n.record_status='current')) ORDER BY v.stock_number),'[]') INTO vehicles_json
 FROM public.vehicles v WHERE EXISTS(SELECT 1 FROM public.pdc_pilbara_service_operation_history h JOIN public.pdc_pilbara_service_operations o USING(operation_id) WHERE h.batch_id=b.batch_id AND o.vehicle_id=v.id);
 SELECT coalesce(jsonb_agg(to_jsonb(u) ORDER BY repair_order_number,original_line_number),'[]') INTO unbound FROM public.pdc_unidentified_tune_review u
 WHERE u.source_batch_id=b.batch_id OR EXISTS(SELECT 1 FROM public.pdc_pilbara_service_import_rows r JOIN public.pdc_pilbara_service_import_batches p ON p.batch_id=r.batch_id
  WHERE p.source_hash=b.source_hash AND p.contract_revision=b.contract_revision AND p.batch_kind='preview' AND r.reason='unidentified_tune_review' AND r.normalized_payload->>'operation_identity_hash'=u.operation_identity_hash AND u.workbook_sha256=b.source_link->>'workbook_sha256');
 RETURN jsonb_build_object('ok',true,'code','pmg_intake_readback','apply_batch_id',b.batch_id,'source_link',b.source_link,'receipt',b.response,
 'vehicles',vehicles_json,'unidentified_rows',unbound,'vehicle_count',jsonb_array_length(vehicles_json),'unidentified_row_count',jsonb_array_length(unbound));
END $$;
REVOKE ALL ON FUNCTION public.pdc_pmg_intake_readback_v3(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.pdc_pmg_intake_readback_v3(uuid) TO authenticated;

CREATE FUNCTION public.list_pdc_unidentified_tune_reviews(p_offset integer DEFAULT 0,p_limit integer DEFAULT 50) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
DECLARE items jsonb; total integer;
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE OR auth.uid() IS NULL OR NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r
 WHERE r.auth_user_id=auth.uid() AND r.active AND r.account_status='approved' AND r.role IN('viewer','operator','importer','administrator')
 AND lower(btrim(r.email))=lower(btrim(coalesce(auth.jwt()->>'email',''))))
 THEN RETURN jsonb_build_object('ok',false,'code','not_authorized'); END IF;
 IF p_offset IS NULL OR p_offset<0 OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN RETURN jsonb_build_object('ok',false,'code','invalid_page'); END IF;
 SELECT count(*) INTO total FROM (SELECT DISTINCT workbook_sha256,repair_order_number FROM public.pdc_unidentified_tune_review) x;
 SELECT coalesce(jsonb_agg(to_jsonb(q)),'[]') INTO items FROM (
  SELECT workbook_sha256,repair_order_number,department,count(*) operation_count,sum(source_estimated_hours) hours,
   jsonb_agg(jsonb_build_object('description',operation_description,'line',original_line_number,'hours',source_estimated_hours,'station',proposed_station,'operation_code',operation_code) ORDER BY original_line_number,operation_identity_hash) operations
  FROM public.pdc_unidentified_tune_review GROUP BY workbook_sha256,repair_order_number,department
  ORDER BY workbook_sha256,repair_order_number LIMIT p_limit OFFSET p_offset) q;
 RETURN jsonb_build_object('ok',true,'code','unidentified_tune_reviews','data',jsonb_build_object('items',items,'total',total));
END $$;
REVOKE ALL ON FUNCTION public.list_pdc_unidentified_tune_reviews(integer,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.list_pdc_unidentified_tune_reviews(integer,integer) TO authenticated;
