-- STAGING ONLY 770: deterministic Navision candidate preflight and parity-safe
-- source projection refresh. Invalid or ambiguous rows are classified before the
-- canonical atomic apply path; no browser-local authority is introduced.
BEGIN;
SET LOCAL lock_timeout='30s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-768-navision-import-preflight',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE
  v_preview_sha text;
  v_apply_sha text;
  v_preholding_sha text;
BEGIN
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_preview_sha
    FROM pg_proc p WHERE p.oid='public.preview_navision_backend_import(jsonb,text,text,text,timestamptz)'::regprocedure;
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_apply_sha
    FROM pg_proc p WHERE p.oid='public.apply_navision_backend_import(text,jsonb,text,text,text,timestamptz,text,text,bigint)'::regprocedure;
  SELECT encode(extensions.digest(convert_to(p.prosrc,'UTF8'),'sha256'),'hex') INTO v_preholding_sha
    FROM pg_proc p WHERE p.oid='public.apply_navision_backend_import_preholding_055(text,jsonb,text,text,text,timestamptz,text,text,bigint)'::regprocedure;
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT max(version) FILTER (WHERE version~'^[0-9]{14}$') FROM supabase_migrations.schema_migrations)<>'20260830071000'
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260830071000' AND name='769_monitor_compatibility_after_768')<>1
     OR to_regprocedure('public.preview_navision_backend_import_pre768(jsonb,text,text,text,timestamptz)') IS NOT NULL
     OR to_regprocedure('public.apply_navision_backend_import_pre768(text,jsonb,text,text,text,timestamptz,text,text,bigint)') IS NOT NULL
     OR to_regprocedure('public.navision_import_candidate_preflight_770(jsonb,text,text)') IS NOT NULL
     OR v_preview_sha<>'c39548506e0048174ff62e3e85a6da1dd5fd01f3061b6fe0ae7e9192db5b36fc'
     OR v_apply_sha<>'50d4df130d1db123a57b817f9703a7a7b677ec96e232a2d2bbbb064bd88f7c1d'
     OR v_preholding_sha<>'af7b57adeb3c2d623ab774713e4d8cdc49d6c78a631ad16cbb1c906faa1acda6'
  THEN RAISE EXCEPTION 'PDC_768_NAVISION_PREFLIGHT_PREDECESSOR_GUARD_FAILED' USING errcode='55000'; END IF;
END
$guard$;

CREATE OR REPLACE FUNCTION public.navision_import_date_is_valid_770(p_value text)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE
SET search_path=pg_catalog
AS $date_check$
DECLARE
  v_value text:=btrim(coalesce(p_value,''));
  v_date date;
BEGIN
  IF v_value='' THEN RETURN true; END IF;
  BEGIN
    IF v_value~'^\d{4}-\d{2}-\d{2}$' THEN
      v_date:=to_date(v_value,'YYYY-MM-DD');
      RETURN to_char(v_date,'YYYY-MM-DD')=v_value;
    END IF;
    IF v_value~'^\d{1,2}/\d{1,2}/\d{4}$' THEN
      v_date:=to_date(v_value,'DD/MM/YYYY');
      RETURN to_char(v_date,'DD/MM/YYYY')=lpad(split_part(v_value,'/',1),2,'0')||'/'||lpad(split_part(v_value,'/',2),2,'0')||'/'||split_part(v_value,'/',3);
    END IF;
  EXCEPTION WHEN others THEN
    RETURN false;
  END;
  RETURN false;
END
$date_check$;
REVOKE ALL ON FUNCTION public.navision_import_date_is_valid_770(text) FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.navision_import_candidate_preflight_770(
  p_rows jsonb, p_source_system text, p_dealer_code text
)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,extensions
AS $preflight$
DECLARE
  v_issues jsonb;
BEGIN
  IF lower(btrim(coalesce(p_source_system,'')))<>'microsoft_navision'
     OR btrim(coalesce(p_dealer_code,'')) NOT IN ('14450','37047')
     OR jsonb_typeof(p_rows) IS DISTINCT FROM 'array' THEN
    RETURN jsonb_build_object('contract_version',1,'blocking',true,'issue_count',1,'issues',jsonb_build_array(jsonb_build_object(
      'row_index',null,'classification','invalid','reason','invalid_scope_or_rows','field','scope','stock_number',null
    )));
  END IF;

  WITH source_rows AS MATERIALIZED (
    SELECT e.ordinality::integer AS row_index,e.value AS raw_row,
      public.navision_backend_source_record_id(e.value) AS source_record_id,
      NULLIF(public.normalize_vehicle_stock_number(coalesce(e.value->>'stock',e.value->>'stock_number',e.value->>'batch')),'') AS stock_number,
      NULLIF(public.normalize_vehicle_vin(coalesce(e.value->>'vin',e.value->>'fullVin',e.value->>'frameVin')),'') AS vin,
      NULLIF(public.normalize_vehicle_source_identifier(coalesce(e.value->>'order',e.value->>'toyota_order_number')),'') AS order_number,
      public.navision_backend_candidate_vehicle_ids(e.value) AS candidate_vehicle_ids,
      public.navision_row_declared_dealer_code(e.value) AS declared_dealer_code,
      NULLIF(btrim(coalesce(e.value->>'pdcLocation',e.value->>'pdc_location',e.value->>'locationCode',e.value->>'location_code')),'') AS location_code,
      NULLIF(btrim(coalesce(e.value->>'pdcStatus',e.value->>'pdc_status',e.value->>'workflowStatus',e.value->>'workflow_status',e.value->>'statusCode',e.value->>'status_code')),'') AS status_code,
      NULLIF(btrim(coalesce(e.value->>'pdcEtaDate',e.value->>'pdc_eta_date',e.value->>'locationDate',e.value->>'location_date')),'') AS explicit_date
    FROM jsonb_array_elements(p_rows) WITH ORDINALITY e(value,ordinality)
  ), enriched AS MATERIALIZED (
    SELECT s.*,
      count(*) OVER (PARTITION BY s.source_record_id) AS source_id_count,
      count(*) FILTER (WHERE s.stock_number IS NOT NULL) OVER (PARTITION BY s.stock_number) AS stock_count,
      count(*) FILTER (WHERE s.vin IS NOT NULL) OVER (PARTITION BY s.vin) AS vin_count,
      count(*) FILTER (WHERE s.order_number IS NOT NULL) OVER (PARTITION BY s.order_number) AS order_count,
      coalesce((SELECT count(*) FROM public.navision_backend_records b
        WHERE b.source_system='microsoft_navision' AND b.dealer_code=s.declared_dealer_code
          AND b.is_current AND b.record_status='current' AND s.stock_number IS NOT NULL
          AND public.normalize_vehicle_stock_number(b.normalized_data->>'batch')=s.stock_number),0)::integer AS existing_stock_count,
      coalesce((SELECT count(*) FROM public.navision_backend_records b
        WHERE b.source_system='microsoft_navision' AND b.dealer_code IN (btrim(p_dealer_code),'LEGACY_UNSCOPED')
          AND b.is_current AND b.record_status='current' AND b.source_record_id_normalized=s.source_record_id),0)::integer AS existing_source_count,
      coalesce((SELECT b.canonical_vehicle_id FROM public.navision_backend_records b
        WHERE b.source_system='microsoft_navision' AND b.dealer_code IN (btrim(p_dealer_code),'LEGACY_UNSCOPED')
          AND b.is_current AND b.record_status='current' AND b.source_record_id_normalized=s.source_record_id
        ORDER BY CASE WHEN b.dealer_code=btrim(p_dealer_code) THEN 0 ELSE 1 END LIMIT 1),NULL) AS existing_canonical_vehicle_id
    FROM source_rows s
  ), issue_rows AS (
    SELECT e.*,
      CASE
        WHEN jsonb_typeof(e.raw_row)<>'object' THEN 'row_not_object'
        WHEN e.source_record_id IS NULL THEN 'missing_source_record_id'
        WHEN e.declared_dealer_code IS NOT NULL AND e.declared_dealer_code<>btrim(p_dealer_code) THEN 'wrong_dealer_scope'
        WHEN e.source_id_count>1 THEN 'duplicate_source_record_id'
        WHEN e.stock_count>1 THEN 'duplicate_stock_number'
        WHEN e.vin_count>1 THEN 'duplicate_vin'
        WHEN e.order_count>1 THEN 'duplicate_toyota_order'
        WHEN e.status_code IS NOT NULL AND lower(regexp_replace(e.status_code,'[^a-z0-9]+','','g')) NOT IN ('new','current','active','inactive','planned','pending','review','reviewonly','yardhold','yh','pmb','rft','completed','other') THEN 'invalid_status_code'
        WHEN e.location_code IS NOT NULL AND upper(regexp_replace(e.location_code,'[^A-Z0-9]+','','g')) NOT IN ('YH','PMB','RFT') THEN 'invalid_location_code'
        WHEN e.explicit_date IS NOT NULL AND NOT public.navision_import_date_is_valid_770(e.explicit_date) THEN 'invalid_date'
        WHEN cardinality(e.candidate_vehicle_ids)>1 THEN 'ambiguous_canonical_identity'
        WHEN e.existing_stock_count>1 THEN 'duplicate_existing_stock_number'
        WHEN e.existing_source_count=1 AND e.existing_canonical_vehicle_id IS NOT NULL AND e.stock_number IS NOT NULL
             AND cardinality(e.candidate_vehicle_ids)=1 AND e.candidate_vehicle_ids[1]<>e.existing_canonical_vehicle_id THEN 'canonical_identity_mismatch'
        WHEN e.existing_stock_count=1 AND e.existing_source_count=0 THEN 'duplicate_existing_stock_number'
        ELSE NULL
      END AS reason,
      CASE
        WHEN jsonb_typeof(e.raw_row)<>'object' OR e.source_record_id IS NULL THEN 'source_record_id'
        WHEN e.declared_dealer_code IS NOT NULL AND e.declared_dealer_code<>btrim(p_dealer_code) THEN 'dealer_code'
        WHEN e.source_id_count>1 THEN 'source_record_id'
        WHEN e.stock_count>1 OR e.existing_stock_count>1 THEN 'stock'
        WHEN e.vin_count>1 THEN 'vin'
        WHEN e.order_count>1 THEN 'toyota_order_number'
        WHEN e.status_code IS NOT NULL AND lower(regexp_replace(e.status_code,'[^a-z0-9]+','','g')) NOT IN ('new','current','active','inactive','planned','pending','review','reviewonly','yardhold','yh','pmb','rft','completed','other') THEN 'status_code'
        WHEN e.location_code IS NOT NULL AND upper(regexp_replace(e.location_code,'[^A-Z0-9]+','','g')) NOT IN ('YH','PMB','RFT') THEN 'location_code'
        WHEN e.explicit_date IS NOT NULL THEN 'date'
        WHEN cardinality(e.candidate_vehicle_ids)>1 OR e.existing_canonical_vehicle_id IS NOT NULL THEN 'canonical_identity'
        ELSE NULL
      END AS issue_field
    FROM enriched e
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'row_index',row_index,'classification','conflict','reason',reason,'field',issue_field,
    'stock_number',stock_number,'source_record_id',source_record_id,
    'candidate_vehicle_ids',to_jsonb(candidate_vehicle_ids),
    'existing_canonical_vehicle_id',existing_canonical_vehicle_id
  ) ORDER BY row_index) FILTER (WHERE reason IS NOT NULL),'[]'::jsonb)
  INTO v_issues FROM issue_rows;

  RETURN jsonb_build_object('contract_version',1,'blocking',jsonb_array_length(v_issues)>0,
    'issue_count',jsonb_array_length(v_issues),'issues',v_issues,
    'authority','shared_navision_backend_only','atomic_apply',true);
END
$preflight$;
REVOKE ALL ON FUNCTION public.navision_import_candidate_preflight_770(jsonb,text,text) FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.navision_refresh_linked_vehicle_projection_770(p_backend_record_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions
AS $projection$
DECLARE
  b public.navision_backend_records%rowtype;
  v public.vehicles%rowtype;
  before_data jsonb;
  after_data jsonb;
  next_payload jsonb;
BEGIN
  SELECT * INTO b FROM public.navision_backend_records WHERE id=p_backend_record_id AND is_current AND record_status='current';
  IF NOT FOUND OR b.canonical_vehicle_id IS NULL THEN RETURN public.navision_backend_response(true,'projection_not_required'); END IF;
  SELECT * INTO v FROM public.vehicles WHERE id=b.canonical_vehicle_id AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN RETURN public.navision_backend_response(false,'canonical_vehicle_not_found'); END IF;
  next_payload:=coalesce(v.source_payload,'{}'::jsonb)||jsonb_build_object(
    'navision_version',b.version,
    'navision_status',coalesce(b.normalized_data->>'toyotaStatus',''),
    'navision_updated_at',b.updated_at
  );
  IF v.source_payload IS NOT DISTINCT FROM next_payload THEN RETURN public.navision_backend_response(true,'projection_current'); END IF;
  before_data:=to_jsonb(v);
  UPDATE public.vehicles SET source_payload=next_payload,version=version+1,updated_at=clock_timestamp(),updated_by=auth.uid()
    WHERE id=v.id RETURNING * INTO v;
  after_data:=to_jsonb(v);
  INSERT INTO public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata)
  VALUES('update','vehicles',v.id,v.id,auth.uid(),public.current_actor_email(),before_data,after_data,
    jsonb_build_object('contract','navision_import_projection_768','backend_record_id',b.id,'operational_mutations',0));
  RETURN public.navision_backend_response(true,'projection_refreshed',jsonb_build_object('vehicle_id',v.id,'backend_record_id',b.id,'operational_mutations',0));
END
$projection$;
REVOKE ALL ON FUNCTION public.navision_refresh_linked_vehicle_projection_770(uuid) FROM public,anon,authenticated,service_role;

ALTER FUNCTION public.preview_navision_backend_import(jsonb,text,text,text,timestamptz) RENAME TO preview_navision_backend_import_pre768;
ALTER FUNCTION public.apply_navision_backend_import(text,jsonb,text,text,text,timestamptz,text,text,bigint) RENAME TO apply_navision_backend_import_pre768;

CREATE OR REPLACE FUNCTION public.preview_navision_backend_import(
  p_rows jsonb,p_source_system text,p_dealer_code text,p_source_name text,p_source_timestamp timestamptz default null
)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,extensions
AS $preview$
DECLARE
  v_preflight jsonb;
  v_result jsonb;
  v_data jsonb;
  v_items jsonb;
  v_issue jsonb;
  v_index integer;
  v_counts jsonb;
BEGIN
  v_preflight:=public.navision_import_candidate_preflight_770(p_rows,p_source_system,p_dealer_code);
  v_result:=public.preview_navision_backend_import_pre768(p_rows,p_source_system,p_dealer_code,p_source_name,p_source_timestamp);
  IF coalesce((v_result->>'ok')::boolean,false) IS NOT TRUE THEN RETURN v_result; END IF;
  v_data:=coalesce(v_result->'data','{}'::jsonb);
  v_items:=coalesce(v_data->'items','[]'::jsonb);
  FOR v_issue IN SELECT value FROM jsonb_array_elements(coalesce(v_preflight->'issues','[]'::jsonb)) LOOP
    v_index:=coalesce((v_issue->>'row_index')::integer,0);
    IF v_index>0 AND v_index<=jsonb_array_length(v_items) THEN
      v_items:=jsonb_set(v_items,ARRAY[(v_index-1)::text],(v_items->(v_index-1))||v_issue,true);
    END IF;
  END LOOP;
  SELECT jsonb_build_object(
    'total',jsonb_array_length(v_items),
    'new',count(*) FILTER (WHERE value->>'classification'='new'),
    'changed',count(*) FILTER (WHERE value->>'classification'='changed'),
    'unchanged',count(*) FILTER (WHERE value->>'classification'='unchanged'),
    'invalid',count(*) FILTER (WHERE value->>'classification'='invalid' OR value->>'reason' IN ('row_not_object','missing_source_record_id','invalid_status_code','invalid_date','invalid_location_code')),
    'conflict',count(*) FILTER (WHERE value->>'classification'='conflict' OR value->>'reason' IN ('duplicate_source_record_id','duplicate_stock_number','duplicate_vin','duplicate_toyota_order','duplicate_existing_stock_number','canonical_identity_mismatch','wrong_dealer_scope','ambiguous_canonical_identity')),
    'missing',coalesce((v_data->'counts'->>'missing')::integer,0),
    'proposed_links',coalesce((v_data->'counts'->>'proposed_links')::integer,0),
    'operational_mutations',0
  ) INTO v_counts FROM jsonb_array_elements(v_items);
  v_data:=v_data||jsonb_build_object('items',v_items,'counts',v_counts,'preflight',v_preflight,
    'blocking',coalesce((v_data->>'blocking')::boolean,false) OR coalesce((v_preflight->>'blocking')::boolean,true));
  RETURN jsonb_set(v_result,'{data}',v_data,true);
END
$preview$;

CREATE OR REPLACE FUNCTION public.apply_navision_backend_import(
  p_idempotency_key text,p_rows jsonb,p_source_system text,p_dealer_code text,p_source_name text,
  p_source_timestamp timestamptz,p_source_hash text,p_preview_hash text,p_expected_revision bigint
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public,extensions
AS $apply$
DECLARE
  v_preflight jsonb;
BEGIN
  v_preflight:=public.navision_import_candidate_preflight_770(p_rows,p_source_system,p_dealer_code);
  IF coalesce((v_preflight->>'blocking')::boolean,true) THEN
    RETURN public.navision_backend_response(false,'navision_preflight_blocked',jsonb_build_object(
      'preflight',v_preflight,'message','No Navision records changed. Review each flagged Stock, field and reason before applying the complete file.'
    ));
  END IF;
  RETURN public.apply_navision_backend_import_pre768(p_idempotency_key,p_rows,p_source_system,p_dealer_code,p_source_name,
    p_source_timestamp,p_source_hash,p_preview_hash,p_expected_revision);
END
$apply$;

DO $patch$
DECLARE d text;n text;
BEGIN
  SELECT pg_get_functiondef('public.apply_navision_backend_import_preholding_055(text,jsonb,text,text,text,timestamptz,text,text,bigint)'::regprocedure) INTO d;
  IF position('public.navision_refresh_linked_vehicle_projection_770(v_record.id)' IN d)>0 THEN
    NULL;
  ELSIF position('    v_after := to_jsonb(v_record);'||E'\n\n    insert into public.navision_import_items (' IN d)=0 THEN
    RAISE EXCEPTION 'PDC_768_PREHOLDING_SOURCE_DRIFT' USING errcode='55000';
  ELSE
    n:=replace(d,
      '    v_after := to_jsonb(v_record);'||E'\n\n    insert into public.navision_import_items (',
      '    v_after := to_jsonb(v_record);'||E'\n    perform public.navision_refresh_linked_vehicle_projection_770(v_record.id);'||E'\n\n    insert into public.navision_import_items (');
    EXECUTE n;
  END IF;
END
$patch$;

REVOKE ALL ON FUNCTION public.preview_navision_backend_import(jsonb,text,text,text,timestamptz) FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.preview_navision_backend_import(jsonb,text,text,text,timestamptz) TO authenticated;
REVOKE ALL ON FUNCTION public.apply_navision_backend_import(text,jsonb,text,text,text,timestamptz,text,text,bigint) FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.apply_navision_backend_import(text,jsonb,text,text,text,timestamptz,text,text,bigint) TO authenticated;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
 '20260830072000','navision_import_preflight_contract',ARRAY[
  'Guard exact staging predecessor 20260830071000/769 and exact live preview/apply/preholding sources',
  'Classify every Navision candidate by source identity, dealer scope, duplicate Stock/VIN/order, canonical ambiguity, explicit status/date/location fields before apply',
  'Return Stock, field, reason and candidate identity evidence while preserving atomic whole-file apply and temporary holding semantics',
  'Refresh only the linked vehicle Navision source projection required by the existing parity constraint trigger; operational mutations remain zero and audit history is appended',
  'Preserve staging-only project guard, RLS, grants, canonical RPCs, idempotency/replay protection and no browser-local fallback',
  'Dashboard repair session 20260829_100425_fbe916; Production, email and mailbox paths untouched'
 ]);
NOTIFY pgrst,'reload schema';
COMMIT;
