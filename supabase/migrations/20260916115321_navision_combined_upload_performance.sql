-- Build dealer partitions once, instead of copying the growing full file for every row.
-- Validation, original row positions and excluded-row evidence are unchanged.
CREATE OR REPLACE FUNCTION pdc_navision_combined_private.split_rows(p_rows jsonb) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path='pg_catalog','public' AS $fn$
DECLARE groups jsonb; excluded jsonb; invalid_row bigint; invalid_dealer bigint;
BEGIN
 IF jsonb_typeof(p_rows) IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Rows must be an array' USING errcode='22023'; END IF;
 IF jsonb_array_length(p_rows)<1 OR jsonb_array_length(p_rows)>10000 THEN RAISE EXCEPTION 'Upload must contain 1 to 10000 rows' USING errcode='22023'; END IF;
 WITH source_rows AS MATERIALIZED (
  SELECT e.value r,e.ordinality n,public.navision_row_declared_dealer_code(e.value) code,
   (SELECT count(DISTINCT public.navision_canonical_dealer_code(coalesce(nullif(c->>'value',''),c->>'rawValue','')))
    FROM jsonb_array_elements(CASE WHEN jsonb_typeof(e.value#>'{navisionRawEvidence,columns}')='array'
      THEN e.value#>'{navisionRawEvidence,columns}' ELSE '[]'::jsonb END) c
    WHERE regexp_replace(lower(coalesce(c->>'header','')),'[^a-z0-9]','','g') IN('dealer','dealercode','dealerno','dealernumber')) codes
  FROM jsonb_array_elements(p_rows) WITH ORDINALITY e(value,ordinality)
 ), dealer_groups AS (
  SELECT code,jsonb_agg(jsonb_build_object('row',r,'index',n) ORDER BY n) rows
  FROM source_rows WHERE code IN('14450','001234','002345') GROUP BY code
 )
 SELECT (SELECT coalesce(jsonb_object_agg(code,rows),'{}'::jsonb) FROM dealer_groups),
  coalesce(jsonb_agg(jsonb_build_object('row_index',n,'dealer_code',lpad(code,6,'0'),
    'stock_number',coalesce(r->>'stock',r->>'batch'),'source_record_id',public.navision_backend_source_record_id(r)) ORDER BY n)
    FILTER(WHERE code NOT IN('14450','001234','002345')),'[]'::jsonb),
  min(n) FILTER(WHERE jsonb_typeof(r) IS DISTINCT FROM 'object'),
  min(n) FILTER(WHERE codes<>1 OR code IS NULL OR code !~ '^[0-9]{1,6}$')
 INTO groups,excluded,invalid_row,invalid_dealer FROM source_rows;
 IF invalid_row IS NOT NULL THEN RAISE EXCEPTION 'Invalid row %',invalid_row USING errcode='22023'; END IF;
 IF invalid_dealer IS NOT NULL THEN RAISE EXCEPTION 'Row % needs one unambiguous Dealer column',invalid_dealer USING errcode='22023'; END IF;
 IF groups='{}'::jsonb THEN RAISE EXCEPTION 'No rows for 014450, 001234 or 002345' USING errcode='22023'; END IF;
 RETURN jsonb_build_object('groups',groups,'excluded_rows',excluded);
END $fn$;
REVOKE ALL ON FUNCTION pdc_navision_combined_private.split_rows(jsonb) FROM PUBLIC,anon,authenticated;
