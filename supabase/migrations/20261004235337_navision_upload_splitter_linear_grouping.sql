-- Staging only. Protected PMB, Karratha, Sales and shared source rows are fenced in this transaction.
-- One existing private STABLE INVOKER splitter changes; no RPC, ACL, role,
-- timeout, source rows, operational rows, or atomic apply function changes.
DO $install$
DECLARE target_oid oid; metadata_before jsonb; metadata_after jsonb;
 definition_before text; definition_after text; protected_before text; protected_after text;
 fence_table record; fence_value jsonb; fence_snapshot jsonb:='{}'; rows_before jsonb;
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' OR NOT public.pdc_monitor_staging_guard() THEN
  RAISE EXCEPTION 'Staging manager required for splitter repair' USING errcode='42501';
 END IF;
 target_oid:=to_regprocedure('pdc_navision_upload_private.split_profile(jsonb,text)');
 IF target_oid IS NULL THEN RAISE EXCEPTION 'Frozen splitter is missing'; END IF;
 SELECT jsonb_build_object('oid',p.oid,'schema_name',n.nspname,'proname',p.proname,'owner',p.proowner::regrole::text,'acl',p.proacl::text,'prosecdef',p.prosecdef,'provolatile',p.provolatile,'proparallel',p.proparallel,'proisstrict',p.proisstrict,'proleakproof',p.proleakproof,'procost',p.procost,'prorows',p.prorows,'proconfig',p.proconfig,'identity_arguments',pg_get_function_identity_arguments(p.oid),'returns',pg_get_function_result(p.oid)),encode(extensions.digest(pg_get_functiondef(p.oid),'sha256'),'hex')
 INTO metadata_before,definition_before FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE p.oid=target_oid;
 IF definition_before<>'ed56db7ed2741cea5c6d4efeb52ca212b7f9783a06700707c4dc17edfd5df440' OR metadata_before IS DISTINCT FROM $metadata${"oid":"3532960","schema_name":"pdc_navision_upload_private","proname":"split_profile","owner":"postgres","acl":"{postgres=X/postgres}","prosecdef":false,"provolatile":"s","proparallel":"u","proisstrict":false,"proleakproof":false,"procost":100,"prorows":0,"proconfig":["search_path=pg_catalog, public, pdc_sales_private"],"identity_arguments":"p_rows jsonb, p_profile text","returns":"jsonb"}$metadata$::jsonb THEN
  RAISE EXCEPTION 'Frozen splitter definition or permissions changed';
 END IF;
 SELECT md5(string_agg(md5(p.oid::text||':'||to_jsonb(p)::text||':'||pg_get_functiondef(p.oid)),'' ORDER BY p.oid)) FROM pg_proc p WHERE p.prokind IN('f','p') AND p.oid<>target_oid INTO protected_before;

 FOR fence_table IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relkind='r' AND ((n.nspname='public' AND (c.relname IN ('vehicles','pdc_new_vehicle_reviews','pdc_user_roles','salespeople') OR c.relname ~ '^(vehicle_|workshop_|navision_)')) OR n.nspname IN ('pdc_parts_private','pdc_bus_private','pdc_fitter_private','pdc_sales_private','karratha_pdc') OR (n.nspname LIKE 'karratha135_%' AND n.nspname<>'karratha135_usage')) ORDER BY n.nspname,c.relname LOOP
 EXECUTE format('SELECT jsonb_build_object(''count'',count(*),''hash'',md5(coalesce(string_agg(md5(to_jsonb(t)::text),'''' ORDER BY md5(to_jsonb(t)::text)),''''))) FROM %I.%I t',fence_table.nspname,fence_table.relname) INTO fence_value;
 fence_snapshot:=fence_snapshot||jsonb_build_object(fence_table.nspname||'.'||fence_table.relname,fence_value);
 END LOOP;
 rows_before:=fence_snapshot;
 EXECUTE $replacement$CREATE OR REPLACE FUNCTION pdc_navision_upload_private.split_profile(p_rows jsonb, p_profile text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public', 'pdc_sales_private'
AS $function$
DECLARE row_data jsonb; groups jsonb:='{}'; excluded jsonb:='[]'; idx integer:=0; code text; codes integer; allowed text[]; ord text; stock text; matches integer; existing_sid text; normalized jsonb; sold boolean; lookup jsonb; existing_order text; accepted_rows jsonb[]:=ARRAY[]::jsonb[]; excluded_items jsonb[]:=ARRAY[]::jsonb[];
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
  IF NOT(code=ANY(allowed)) THEN excluded_items:=array_append(excluded_items,jsonb_build_object('row_index',idx,'dealer_code',lpad(code,6,'0'),'reason','outside_selected_upload'));CONTINUE;END IF;
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
  IF stock IS NULL AND NOT sold AND matches=0 AND NOT EXISTS(SELECT 1 FROM pdc_sales_private.tracked_orders o WHERE o.dealer_code=code AND o.order_key=ord) THEN excluded_items:=array_append(excluded_items,jsonb_build_object('row_index',idx,'dealer_code',lpad(code,6,'0'),'reason','unsold_without_stock'));CONTINUE;END IF;
  IF stock IS NULL AND (length(ord) NOT BETWEEN 1 AND 80) THEN RAISE EXCEPTION 'Row % without Batch needs a Toyota Order number',idx USING errcode='22023';END IF;
  normalized:=row_data||jsonb_build_object('id',coalesce(existing_sid,stock,'TOYOTA-ORDER-'||ord),'dealer_code',code,'order',ord,'stock',coalesce(stock,''),'batch',coalesce(stock,''));
  accepted_rows:=array_append(accepted_rows,jsonb_build_object('row',normalized,'index',idx));
 END LOOP;
 WITH grouped AS (
  SELECT a.value#>>'{row,dealer_code}' dealer_code,jsonb_agg(a.value ORDER BY (a.value->>'index')::integer) rows
  FROM unnest(accepted_rows) AS a(value) GROUP BY a.value#>>'{row,dealer_code}'
 ) SELECT coalesce(jsonb_object_agg(g.dealer_code,g.rows),'{}'::jsonb) INTO groups FROM grouped g;
 SELECT coalesce(jsonb_agg(e.value ORDER BY e.ordinality),'[]'::jsonb) INTO excluded FROM unnest(excluded_items) WITH ORDINALITY AS e(value,ordinality);
 IF groups='{}'::jsonb THEN RAISE EXCEPTION 'No eligible rows for the selected upload' USING errcode='22023';END IF;
 RETURN jsonb_build_object('groups',groups,'excluded_rows',excluded);
END $function$
;$replacement$;
 SELECT jsonb_build_object('oid',p.oid,'schema_name',n.nspname,'proname',p.proname,'owner',p.proowner::regrole::text,'acl',p.proacl::text,'prosecdef',p.prosecdef,'provolatile',p.provolatile,'proparallel',p.proparallel,'proisstrict',p.proisstrict,'proleakproof',p.proleakproof,'procost',p.procost,'prorows',p.prorows,'proconfig',p.proconfig,'identity_arguments',pg_get_function_identity_arguments(p.oid),'returns',pg_get_function_result(p.oid)),encode(extensions.digest(pg_get_functiondef(p.oid),'sha256'),'hex')
 INTO metadata_after,definition_after FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE p.oid=target_oid;
 IF metadata_after IS DISTINCT FROM metadata_before OR definition_after<>'2ce8683e055c98f2b50000341a159bb94d4a0cab5405ccd58e1a5bb710c5dba6' THEN
  RAISE EXCEPTION 'Splitter metadata or candidate definition mismatch';
 END IF;
 SELECT md5(string_agg(md5(p.oid::text||':'||to_jsonb(p)::text||':'||pg_get_functiondef(p.oid)),'' ORDER BY p.oid)) FROM pg_proc p WHERE p.prokind IN('f','p') AND p.oid<>target_oid INTO protected_after;
 IF protected_after IS DISTINCT FROM protected_before THEN RAISE EXCEPTION 'Another function changed during splitter repair'; END IF;
 fence_snapshot:='{}'::jsonb;

 FOR fence_table IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relkind='r' AND ((n.nspname='public' AND (c.relname IN ('vehicles','pdc_new_vehicle_reviews','pdc_user_roles','salespeople') OR c.relname ~ '^(vehicle_|workshop_|navision_)')) OR n.nspname IN ('pdc_parts_private','pdc_bus_private','pdc_fitter_private','pdc_sales_private','karratha_pdc') OR (n.nspname LIKE 'karratha135_%' AND n.nspname<>'karratha135_usage')) ORDER BY n.nspname,c.relname LOOP
 EXECUTE format('SELECT jsonb_build_object(''count'',count(*),''hash'',md5(coalesce(string_agg(md5(to_jsonb(t)::text),'''' ORDER BY md5(to_jsonb(t)::text)),''''))) FROM %I.%I t',fence_table.nspname,fence_table.relname) INTO fence_value;
 fence_snapshot:=fence_snapshot||jsonb_build_object(fence_table.nspname||'.'||fence_table.relname,fence_value);
 END LOOP;
 IF fence_snapshot IS DISTINCT FROM rows_before THEN RAISE EXCEPTION 'Protected operational or shared source rows changed during splitter repair'; END IF;
END $install$;

