DO $guard$ BEGIN IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'Staging only';END IF;END $guard$;
CREATE OR REPLACE FUNCTION pdc_navision_upload_private.split_profile(p_rows jsonb,p_profile text)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path='pg_catalog','public','pdc_sales_private' AS $fn$
DECLARE row_data jsonb; groups jsonb:='{}'; excluded jsonb:='[]'; idx integer:=0; code text; codes integer; allowed text[]; ord text; stock text; matches integer; existing_sid text; normalized jsonb; sold boolean; lookup jsonb; existing_order text;
BEGIN
 IF p_profile='broome' THEN allowed:=ARRAY['37047','001234','002345']; ELSIF p_profile='pilbara' THEN allowed:=ARRAY['14450','001234','002345']; ELSE RAISE EXCEPTION 'Choose Broome Upload or Pilbara Upload' USING errcode='22023'; END IF;
 IF jsonb_typeof(p_rows) IS DISTINCT FROM 'array' OR jsonb_array_length(p_rows) NOT BETWEEN 1 AND 10000 OR octet_length(p_rows::text)>8000000 THEN RAISE EXCEPTION 'Provide 1 to 10000 Navision rows under 8 MB' USING errcode='22023'; END IF;
 WITH backend AS MATERIALIZED (
  SELECT n.source_record_id sid,n.dealer_code dealer,upper(btrim(coalesce(nullif(n.normalized_data->>'order',''),public.navision_original_column_value(n.normalized_data,'Order'),''))) order_key,nullif(public.normalize_vehicle_stock_number(n.normalized_data->>'batch'),'') stock_key
  FROM public.navision_backend_records n WHERE n.source_system='microsoft_navision' AND n.dealer_code=ANY(allowed) AND n.is_current AND n.record_status='current'
 ), keys AS (
  SELECT dealer||'|order|'||order_key k,jsonb_build_object('sid',sid,'order',order_key) v FROM backend WHERE order_key<>''
  UNION ALL SELECT dealer||'|stock|'||stock_key,jsonb_build_object('sid',sid,'order',order_key) FROM backend WHERE stock_key IS NOT NULL
 ), collected AS (SELECT k,jsonb_agg(v) vals FROM keys GROUP BY k)
 SELECT coalesce(jsonb_object_agg(k,vals),'{}'::jsonb) INTO lookup FROM collected;
 FOR row_data IN SELECT value FROM jsonb_array_elements(p_rows) LOOP
  idx:=idx+1;
  IF jsonb_typeof(row_data) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'Invalid row %',idx USING errcode='22023'; END IF;
  code:=public.navision_row_declared_dealer_code(row_data);
  SELECT count(DISTINCT public.navision_canonical_dealer_code(coalesce(nullif(c->>'value',''),c->>'rawValue',''))) INTO codes
   FROM jsonb_array_elements(CASE WHEN jsonb_typeof(row_data#>'{navisionRawEvidence,columns}')='array' THEN row_data#>'{navisionRawEvidence,columns}' ELSE '[]'::jsonb END) c
   WHERE regexp_replace(lower(coalesce(c->>'header','')),'[^a-z0-9]','','g') IN('dealer','dealercode','dealerno','dealernumber');
  IF codes<>1 OR code IS NULL OR code !~ '^[0-9]{1,6}$' THEN RAISE EXCEPTION 'Row % needs one unambiguous original Dealer column',idx USING errcode='22023'; END IF;
  IF NOT(code=ANY(allowed)) THEN excluded:=excluded||jsonb_build_array(jsonb_build_object('row_index',idx,'dealer_code',lpad(code,6,'0'),'reason','outside_selected_upload'));CONTINUE;END IF;
  IF row_data ? 'dealer_code' AND public.navision_canonical_dealer_code(row_data->>'dealer_code') IS DISTINCT FROM code THEN RAISE EXCEPTION 'Row % has conflicting Dealer values',idx USING errcode='22023';END IF;
  ord:=upper(btrim(coalesce(nullif(row_data->>'order',''),public.navision_original_column_value(row_data,'Order'),'')));
  stock:=nullif(public.normalize_vehicle_stock_number(coalesce(row_data->>'stock',row_data->>'batch')),'');
  IF stock IN('0','TBA') THEN stock:=NULL;END IF;
  sold:=lower(btrim(coalesce(row_data->>'cosi',public.navision_original_column_value(row_data,'COSI'),''))) IN('yes','true','1');
  WITH matched AS (
   SELECT value FROM jsonb_array_elements(coalesce(lookup->(code||'|order|'||ord),'[]'::jsonb))
   UNION SELECT value FROM jsonb_array_elements(coalesce(lookup->(code||'|stock|'||coalesce(stock,'')),'[]'::jsonb))
  ) SELECT count(*),min(value->>'sid'),min(nullif(value->>'order','')) INTO matches,existing_sid,existing_order FROM matched;
  IF matches>1 THEN RAISE EXCEPTION 'Row % matches more than one backend vehicle; review Order and Stock',idx USING errcode='23514';END IF;
  IF matches=1 AND ord<>'' AND existing_order IS NOT NULL AND existing_order<>ord THEN RAISE EXCEPTION 'Row % changes an existing Toyota Order identity',idx USING errcode='23514';END IF;
  IF stock IS NULL AND NOT sold AND matches=0 AND NOT EXISTS(SELECT 1 FROM pdc_sales_private.tracked_orders o WHERE o.dealer_code=code AND o.order_key=ord) THEN excluded:=excluded||jsonb_build_array(jsonb_build_object('row_index',idx,'dealer_code',lpad(code,6,'0'),'reason','unsold_without_stock'));CONTINUE;END IF;
  IF stock IS NULL AND (length(ord) NOT BETWEEN 1 AND 80) THEN RAISE EXCEPTION 'Row % without Batch needs a Toyota Order number',idx USING errcode='22023';END IF;
  normalized:=row_data||jsonb_build_object('id',coalesce(existing_sid,stock,'TOYOTA-ORDER-'||ord),'dealer_code',code,'order',ord,'stock',coalesce(stock,''),'batch',coalesce(stock,''));
  groups:=jsonb_set(groups,ARRAY[code],coalesce(groups->code,'[]'::jsonb)||jsonb_build_array(jsonb_build_object('row',normalized,'index',idx)),true);
 END LOOP;
 IF groups='{}'::jsonb THEN RAISE EXCEPTION 'No eligible rows for the selected upload' USING errcode='22023';END IF;
 RETURN jsonb_build_object('groups',groups,'excluded_rows',excluded);
END $fn$;

NOTIFY pgrst,'reload schema';
