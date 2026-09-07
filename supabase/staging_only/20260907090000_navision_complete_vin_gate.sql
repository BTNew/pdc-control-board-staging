-- STAGING ONLY 20260907090000: complete-VIN gating for every Navision
-- import/identity/reconciliation path. Raw WMI/VDS/Frame remain untouched in
-- raw_evidence; normalized_data.vin is an identity projection and is nullable.
BEGIN;
SET LOCAL lock_timeout='30s';
SET LOCAL statement_timeout='300s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-navision-complete-vin-20260907090000',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
DECLARE
  v_preholding text;
BEGIN
  v_preholding:=lower(pg_get_functiondef('public.apply_navision_backend_import_preholding_055(text,jsonb,text,text,text,timestamptz,text,text,bigint)'::regprocedure));
  IF current_user<>'postgres'
     OR session_user<>'postgres'
     OR current_setting('app.environment',true)='production'
     OR NOT public.pdc_monitor_staging_guard()
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT (version,name)::text FROM supabase_migrations.schema_migrations
         WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1)
        IS DISTINCT FROM '(20260905010200,archived_snapshot_volatility_repair)'
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260907090000')
     OR to_regprocedure('public.pdc_navision_complete_vin_20260907(jsonb)') IS NOT NULL
     OR position('normalized_data = v_normalized' IN v_preholding)=0
     OR position('raw_evidence = v_row' IN v_preholding)=0
     OR position('v_normalized, v_row' IN v_preholding)=0
  THEN
    RAISE EXCEPTION 'PDC_20260907090000_STAGING_PREDECESSOR_OR_EVIDENCE_GUARD_FAILED' USING errcode='55000';
  END IF;
END
$guard$;

CREATE OR REPLACE FUNCTION public.pdc_navision_complete_vin_20260907(p_data jsonb)
RETURNS text
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
SET search_path=pg_catalog,public
AS $vin$
  WITH source AS (
    SELECT CASE
      WHEN coalesce(p_data,'{}'::jsonb) ?| ARRAY['wmi','vdsNumber','vds','frame']
      THEN coalesce(p_data->>'wmi','')
        ||coalesce(p_data->>'vdsNumber',p_data->>'vds','')
        ||coalesce(p_data->>'frame','')
      ELSE coalesce(p_data->>'vin',p_data->>'fullVin',p_data->>'frameVin','')
    END AS raw_vin
  ), normalized AS (
    SELECT public.normalize_vehicle_vin(raw_vin) AS vin FROM source
  )
  SELECT CASE WHEN length(vin)=17 AND public.is_valid_vehicle_vin(vin) THEN vin ELSE NULL END
  FROM normalized
$vin$;
REVOKE ALL ON FUNCTION public.pdc_navision_complete_vin_20260907(jsonb) FROM public,anon,authenticated,service_role;

-- This is the single normalized projection seam used by preview and apply.
-- raw_evidence remains the exact submitted object in the retained writer.
CREATE OR REPLACE FUNCTION public.navision_backend_normalize_row(p_row jsonb)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
SET search_path=pg_catalog,public
AS $normalize$
  WITH base AS (
    SELECT CASE WHEN jsonb_typeof(p_row)='object' THEN coalesce((
      SELECT jsonb_object_agg(key,CASE
        WHEN jsonb_typeof(value)='string' THEN to_jsonb(nullif(btrim(value #>> '{}'),''))
        ELSE value
      END ORDER BY key)
      FROM jsonb_each(p_row)
    ),'{}'::jsonb) ELSE NULL END AS value
  )
  SELECT CASE WHEN value IS NULL THEN NULL ELSE jsonb_set(
    value,'{vin}',coalesce(to_jsonb(public.pdc_navision_complete_vin_20260907(p_row)),'null'::jsonb),true
  ) END
  FROM base
$normalize$;
REVOKE ALL ON FUNCTION public.navision_backend_normalize_row(jsonb) FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.navision_backend_candidate_vehicle_ids(p_row jsonb)
RETURNS uuid[]
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,extensions
AS $candidates$
  WITH input AS (
    SELECT public.pdc_navision_complete_vin_20260907(p_row) AS vin,
      public.normalize_vehicle_stock_number(coalesce(p_row->>'stock',p_row->>'stock_number',p_row->>'batch')) AS stock_number,
      public.is_real_vehicle_stock_number(coalesce(p_row->>'stock',p_row->>'stock_number',p_row->>'batch')) AS stock_valid,
      public.normalize_vehicle_source_identifier(coalesce(p_row->>'order',p_row->>'toyota_order_number')) AS toyota_order_number
  ), candidates AS (
    SELECT v.id FROM input i JOIN public.vehicles v
      ON v.deleted_at IS NULL AND i.vin IS NOT NULL AND v.vin_normalized=i.vin
    UNION SELECT v.id FROM input i JOIN public.vehicles v
      ON v.deleted_at IS NULL AND i.stock_valid AND i.stock_number IS NOT NULL AND v.stock_number_normalized=i.stock_number
    UNION SELECT v.id FROM input i JOIN public.vehicles v
      ON v.deleted_at IS NULL AND i.toyota_order_number IS NOT NULL
      AND public.normalize_vehicle_source_identifier(v.toyota_order_number)=i.toyota_order_number
    UNION SELECT a.vehicle_id FROM input i JOIN public.vehicle_aliases a
      ON i.vin IS NOT NULL AND a.active AND a.alias_type_normalized='vin' AND a.normalized_alias_value=i.vin
      JOIN public.vehicles v ON v.id=a.vehicle_id AND v.deleted_at IS NULL
    UNION SELECT a.vehicle_id FROM input i JOIN public.vehicle_aliases a
      ON i.stock_valid AND i.stock_number IS NOT NULL AND a.active
      AND a.alias_type_normalized='stock_number' AND a.normalized_alias_value=i.stock_number
      JOIN public.vehicles v ON v.id=a.vehicle_id AND v.deleted_at IS NULL
    UNION SELECT a.vehicle_id FROM input i JOIN public.vehicle_aliases a
      ON i.toyota_order_number IS NOT NULL AND a.active
      AND a.alias_type_normalized='toyota_order_number'
      AND a.normalized_alias_value=i.toyota_order_number
      AND a.source_system_normalized IN('navision','microsoft-navision')
      JOIN public.vehicles v ON v.id=a.vehicle_id AND v.deleted_at IS NULL
  )
  SELECT coalesce(array_agg(DISTINCT id ORDER BY id),'{}'::uuid[]) FROM candidates
$candidates$;
REVOKE ALL ON FUNCTION public.navision_backend_candidate_vehicle_ids(jsonb) FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.navision_import_candidate_preflight_770(
  p_rows jsonb,p_source_system text,p_dealer_code text
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path=pg_catalog,public,extensions
AS $preflight$
DECLARE
  v_issues jsonb;
BEGIN
  IF lower(btrim(coalesce(p_source_system,'')))<>'microsoft_navision'
     OR btrim(coalesce(p_dealer_code,'')) NOT IN('14450','37047')
     OR jsonb_typeof(p_rows) IS DISTINCT FROM 'array' THEN
    RETURN jsonb_build_object('contract_version',1,'blocking',true,'issue_count',1,'issues',jsonb_build_array(jsonb_build_object(
      'row_index',null,'classification','invalid','reason','invalid_scope_or_rows','field','scope','stock_number',null
    )));
  END IF;

  WITH source_rows AS MATERIALIZED (
    SELECT e.ordinality::integer AS row_index,e.value AS raw_row,
      public.navision_backend_source_record_id(e.value) AS source_record_id,
      NULLIF(public.normalize_vehicle_stock_number(coalesce(e.value->>'stock',e.value->>'stock_number',e.value->>'batch')),'') AS stock_number,
      public.pdc_navision_complete_vin_20260907(e.value) AS vin,
      NULLIF(public.normalize_vehicle_source_identifier(coalesce(e.value->>'order',e.value->>'toyota_order_number')),'') AS order_number,
      public.navision_backend_candidate_vehicle_ids(e.value) AS candidate_vehicle_ids,
      public.navision_row_declared_dealer_code(e.value) AS declared_dealer_code,
      NULLIF(btrim(coalesce(e.value->>'pdcLocation',e.value->>'pdc_location',e.value->>'locationCode',e.value->>'location_code')),'') AS location_code,
      NULLIF(btrim(coalesce(e.value->>'pdcStatus',e.value->>'pdc_status',e.value->>'workflowStatus',e.value->>'workflow_status',e.value->>'statusCode',e.value->>'status_code')),'') AS status_code,
      NULLIF(btrim(coalesce(e.value->>'pdcEtaDate',e.value->>'pdc_eta_date',e.value->>'locationDate',e.value->>'location_date')),'') AS explicit_date
    FROM jsonb_array_elements(p_rows) WITH ORDINALITY e(value,ordinality)
  ), enriched AS MATERIALIZED (
    SELECT s.*,
      count(*) OVER(PARTITION BY s.source_record_id) AS source_id_count,
      count(*) FILTER(WHERE s.stock_number IS NOT NULL) OVER(PARTITION BY s.stock_number) AS stock_count,
      count(*) FILTER(WHERE s.vin IS NOT NULL) OVER(PARTITION BY s.vin) AS vin_count,
      count(*) FILTER(WHERE s.order_number IS NOT NULL) OVER(PARTITION BY s.order_number) AS order_count,
      coalesce((SELECT count(*) FROM public.navision_backend_records b
        WHERE b.source_system='microsoft_navision' AND b.dealer_code=s.declared_dealer_code
          AND b.is_current AND b.record_status='current' AND s.stock_number IS NOT NULL
          AND public.normalize_vehicle_stock_number(b.normalized_data->>'batch')=s.stock_number),0)::integer AS existing_stock_count,
      coalesce((SELECT count(*) FROM public.navision_backend_records b
        WHERE b.source_system='microsoft_navision' AND b.dealer_code IN(btrim(p_dealer_code),'LEGACY_UNSCOPED')
          AND b.is_current AND b.record_status='current' AND b.source_record_id_normalized=s.source_record_id),0)::integer AS existing_source_count,
      coalesce((SELECT b.canonical_vehicle_id FROM public.navision_backend_records b
        WHERE b.source_system='microsoft_navision' AND b.dealer_code IN(btrim(p_dealer_code),'LEGACY_UNSCOPED')
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
        WHEN e.status_code IS NOT NULL AND lower(regexp_replace(e.status_code,'[^a-z0-9]+','','g')) NOT IN('new','current','active','inactive','planned','pending','review','reviewonly','yardhold','yh','pmb','rft','completed','other') THEN 'invalid_status_code'
        WHEN e.location_code IS NOT NULL AND upper(regexp_replace(e.location_code,'[^A-Z0-9]+','','g')) NOT IN('YH','PMB','RFT') THEN 'invalid_location_code'
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
        WHEN e.status_code IS NOT NULL AND lower(regexp_replace(e.status_code,'[^a-z0-9]+','','g')) NOT IN('new','current','active','inactive','planned','pending','review','reviewonly','yardhold','yh','pmb','rft','completed','other') THEN 'status_code'
        WHEN e.location_code IS NOT NULL AND upper(regexp_replace(e.location_code,'[^A-Z0-9]+','','g')) NOT IN('YH','PMB','RFT') THEN 'location_code'
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
  ) ORDER BY row_index) FILTER(WHERE reason IS NOT NULL),'[]'::jsonb)
  INTO v_issues FROM issue_rows;

  RETURN jsonb_build_object('contract_version',1,'blocking',jsonb_array_length(v_issues)>0,
    'issue_count',jsonb_array_length(v_issues),'issues',v_issues,
    'authority','shared_navision_backend_only','atomic_apply',true);
END
$preflight$;
REVOKE ALL ON FUNCTION public.navision_import_candidate_preflight_770(jsonb,text,text) FROM public,anon,authenticated,service_role;

-- All operational reconciliation callers already route through this function.
CREATE OR REPLACE FUNCTION public.pdc_navision_effective_vin_471(p_data jsonb)
RETURNS text
LANGUAGE sql
IMMUTABLE SECURITY DEFINER
SET search_path=pg_catalog,public
AS $effective$
  SELECT public.pdc_navision_complete_vin_20260907(p_data)
$effective$;
REVOKE ALL ON FUNCTION public.pdc_navision_effective_vin_471(jsonb) FROM public,anon,authenticated,service_role;

DO $contract$
DECLARE
  v_raw jsonb:=jsonb_build_object('wmi','MR','vdsNumber','BA3CD1','frame','00000001','vin','MRBA3CD100000001');
  v_normalized jsonb;
  v_partial jsonb;
  v_duplicate jsonb;
BEGIN
  IF public.pdc_navision_complete_vin_20260907(jsonb_build_object(
       'wmi','MR0','vdsNumber','BA3CD1','frame','00000001','vin','MR0BA3CD100000001'))<>'MR0BA3CD100000001'
  THEN RAISE EXCEPTION 'COMPLETE_VIN_MUST_BE_PRESERVED' USING errcode='55000'; END IF;
  IF public.pdc_navision_complete_vin_20260907(v_raw) IS NOT NULL
  THEN RAISE EXCEPTION 'PARTIAL_WMI_VDS_FRAME_MUST_BE_NULL' USING errcode='55000'; END IF;
  IF public.pdc_navision_complete_vin_20260907(jsonb_build_object('wmi','MR0','vdsNumber','BA3$D1','frame','00000001')) IS NOT NULL
  THEN RAISE EXCEPTION 'INVALID_CHARACTER_VIN_MUST_BE_NULL' USING errcode='55000'; END IF;
  IF public.pdc_navision_complete_vin_20260907(jsonb_build_object('wmi','MR0','vdsNumber','BA3CDI','frame','00000001')) IS NOT NULL
  THEN RAISE EXCEPTION 'PROHIBITED_I_VIN_MUST_BE_NULL' USING errcode='55000'; END IF;
  IF public.pdc_navision_complete_vin_20260907(jsonb_build_object('wmi','MR0','vdsNumber','BA3CDO','frame','00000001')) IS NOT NULL
  THEN RAISE EXCEPTION 'PROHIBITED_O_VIN_MUST_BE_NULL' USING errcode='55000'; END IF;
  IF public.pdc_navision_complete_vin_20260907(jsonb_build_object('wmi','MR0','vdsNumber','BA3CDQ','frame','00000001')) IS NOT NULL
  THEN RAISE EXCEPTION 'PROHIBITED_Q_VIN_MUST_BE_NULL' USING errcode='55000'; END IF;
  IF public.pdc_navision_complete_vin_20260907(jsonb_build_object('vin','REBHV112345678')) IS NOT NULL
  THEN RAISE EXCEPTION 'LEGACY_SHORT_VIN_MUST_BE_NULL' USING errcode='55000'; END IF;

  v_normalized:=public.navision_backend_normalize_row(v_raw);
  IF v_normalized->>'vin' IS NOT NULL
     OR v_normalized->>'wmi' IS DISTINCT FROM 'MR'
     OR v_normalized->>'vdsNumber' IS DISTINCT FROM 'BA3CD1'
     OR v_normalized->>'frame' IS DISTINCT FROM '00000001'
  THEN RAISE EXCEPTION 'RAW_COMPONENT_PRESERVATION_FAILED' USING errcode='55000'; END IF;

  v_partial:=public.navision_import_candidate_preflight_770(jsonb_build_array(
    jsonb_build_object('id','VIN-GATE-PARTIAL-1','stock','13090001','wmi','MR','vdsNumber','BA3CD1','frame','00000001','vin','MRBA3CD100000001'),
    jsonb_build_object('id','VIN-GATE-PARTIAL-2','stock','13090002','wmi','MR','vdsNumber','BA3CD1','frame','00000001','vin','MRBA3CD100000001')
  ),'microsoft_navision','37047');
  IF coalesce((v_partial->>'blocking')::boolean,true)
     OR EXISTS(SELECT 1 FROM jsonb_array_elements(v_partial->'issues') i WHERE i->>'reason'='duplicate_vin')
  THEN RAISE EXCEPTION 'PARTIAL_DUPLICATE_VIN_MUST_NOT_BLOCK' USING errcode='55000'; END IF;

  v_duplicate:=public.navision_import_candidate_preflight_770(jsonb_build_array(
    jsonb_build_object('id','VIN-GATE-COMPLETE-1','stock','13090003','wmi','MR0','vdsNumber','BA3CD1','frame','00000001','vin','MR0BA3CD100000001'),
    jsonb_build_object('id','VIN-GATE-COMPLETE-2','stock','13090004','wmi','MR0','vdsNumber','BA3CD1','frame','00000001','vin','MR0BA3CD100000001')
  ),'microsoft_navision','37047');
  IF NOT coalesce((v_duplicate->>'blocking')::boolean,false)
     OR (SELECT count(*) FROM jsonb_array_elements(v_duplicate->'issues') i WHERE i->>'reason'='duplicate_vin')<>2
  THEN RAISE EXCEPTION 'DUPLICATE_COMPLETE_VIN_MUST_BLOCK' USING errcode='55000'; END IF;
END
$contract$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(
 '20260907090000','navision_complete_vin_gate',ARRAY[
  'Use existing normalize_vehicle_vin/is_valid_vehicle_vin contract to derive effective identity only from a complete valid 17-character WMI+VDS+Frame concatenation',
  'Persist normalized_data.vin as null for partial, invalid, or prohibited-letter values while preserving exact raw_evidence and raw WMI/VDS/Frame',
  'Route Navision preview duplicate protection, canonical candidate matching, apply normalization, and operational reconciliation through one complete-VIN helper',
  'Keep duplicate rejection for complete valid VINs and prevent partial VIN collisions',
  'Preserve existing RLS/grants, audit/replay semantics, dealer scope, and STAGING-only separation; Production untouched'
 ]
);
NOTIFY pgrst,'reload schema';
COMMIT;
