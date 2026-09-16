-- One atomic upload for Pilbara (014450), 001234 and 002345. Existing
-- per-dealer validation, initial-scope approval and retention remain authoritative.
CREATE SCHEMA IF NOT EXISTS pdc_navision_combined_private;
REVOKE ALL ON SCHEMA pdc_navision_combined_private FROM PUBLIC,anon,authenticated;
CREATE TABLE pdc_navision_combined_private.receipts (
 actor_id uuid NOT NULL, idempotency_key text NOT NULL, request_hash text NOT NULL,
 source_name text NOT NULL, response jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(actor_id,idempotency_key)
);
ALTER TABLE pdc_navision_combined_private.receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_navision_combined_private.receipts FROM PUBLIC,anon,authenticated;

CREATE FUNCTION pdc_navision_combined_private.split_rows(p_rows jsonb) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path='pg_catalog','public' AS $fn$
DECLARE r jsonb; n bigint; code text; groups jsonb:='{}'; excluded jsonb:='[]'; codes integer;
BEGIN
 IF jsonb_typeof(p_rows) IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Rows must be an array' USING errcode='22023'; END IF;
 IF jsonb_array_length(p_rows)<1 OR jsonb_array_length(p_rows)>10000 THEN RAISE EXCEPTION 'Upload must contain 1 to 10000 rows' USING errcode='22023'; END IF;
 FOR r,n IN SELECT value,ordinality FROM jsonb_array_elements(p_rows) WITH ORDINALITY LOOP
  IF jsonb_typeof(r) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'Invalid row %',n USING errcode='22023'; END IF;
  -- Require the original Dealer column. Do not infer scope from a filename,
  -- customer text or a client-assigned dealer property.
  SELECT count(DISTINCT public.navision_canonical_dealer_code(coalesce(nullif(c->>'value',''),c->>'rawValue','')))
  INTO codes FROM jsonb_array_elements(CASE WHEN jsonb_typeof(r#>'{navisionRawEvidence,columns}')='array'
   THEN r#>'{navisionRawEvidence,columns}' ELSE '[]'::jsonb END) c
  WHERE regexp_replace(lower(coalesce(c->>'header','')),'[^a-z0-9]','','g') IN('dealer','dealercode','dealerno','dealernumber');
  code:=public.navision_row_declared_dealer_code(r);
  IF codes<>1 OR code IS NULL OR code !~ '^[0-9]{1,6}$' THEN
   RAISE EXCEPTION 'Row % needs one unambiguous Dealer column',n USING errcode='22023';
  END IF;
  IF code IN('14450','001234','002345') THEN
   groups:=jsonb_set(groups,ARRAY[code],coalesce(groups->code,'[]'::jsonb)||jsonb_build_array(jsonb_build_object('row',r,'index',n)));
  ELSE
   excluded:=excluded||jsonb_build_array(jsonb_build_object('row_index',n,'dealer_code',lpad(code,6,'0'),
    'stock_number',coalesce(r->>'stock',r->>'batch'),'source_record_id',public.navision_backend_source_record_id(r)));
  END IF;
 END LOOP;
 IF groups='{}'::jsonb THEN RAISE EXCEPTION 'No rows for 014450, 001234 or 002345' USING errcode='22023'; END IF;
 RETURN jsonb_build_object('groups',groups,'excluded_rows',excluded);
END $fn$;

CREATE FUNCTION public.preview_navision_combined_import(p_rows jsonb,p_source_name text,p_source_timestamp timestamptz DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='pg_catalog','public','extensions' AS $fn$
DECLARE split jsonb; g record; rows jsonb; result jsonb; d jsonb; item jsonb; items jsonb:='[]'; groups jsonb:='[]';
 counts jsonb:='{"total":0,"new":0,"changed":0,"unchanged":0,"missing":0,"invalid":0,"conflict":0}';
 k text; revision bigint; source_hash text; preview_hash text; safety_reason text; blocking boolean:=false; duplicates jsonb;
BEGIN
 IF auth.uid() IS NULL OR NOT coalesce(public.current_pdc_user_role()::text IN('importer','administrator'),false)
  THEN RETURN public.navision_backend_response(false,'unauthorized'); END IF;
 IF NOT public.pdc_monitor_staging_guard() THEN RETURN public.navision_backend_response(false,'wrong_environment'); END IF;
 split:=pdc_navision_combined_private.split_rows(p_rows);
 SELECT r.revision INTO revision FROM public.navision_backend_revision r WHERE singleton;
 FOR g IN SELECT key,value FROM jsonb_each(split->'groups') ORDER BY key LOOP
  SELECT jsonb_agg(e->'row' ORDER BY (e->>'index')::int) INTO rows FROM jsonb_array_elements(g.value) e;
  result:=public.preview_navision_backend_import(rows,'microsoft_navision',g.key,'Combined Navision dealer '||g.key,p_source_timestamp);
  IF result->>'ok' IS DISTINCT FROM 'true' THEN RETURN result; END IF;
  d:=result->'data';
  IF (d->>'base_revision')::bigint<>revision THEN RETURN public.navision_backend_response(false,'stale_revision'); END IF;
  groups:=groups||jsonb_build_array(jsonb_build_object('dealer_code',g.key,'counts',d->'counts','safety',d->'safety','blocking',d->'blocking'));
  FOREACH k IN ARRAY ARRAY['total','new','changed','unchanged','missing','invalid','conflict'] LOOP
   counts:=jsonb_set(counts,ARRAY[k],to_jsonb(coalesce((counts->>k)::int,0)+coalesce((d#>>ARRAY['counts',k])::int,0)));
  END LOOP;
  FOR item IN SELECT value FROM jsonb_array_elements(coalesce(d->'items','[]'::jsonb)) LOOP
   items:=items||jsonb_build_array(item||jsonb_build_object('dealer_code',g.key,'row_index',g.value->((item->>'row_index')::int-1)->'index'));
  END LOOP;
  blocking:=blocking OR coalesce((d->>'blocking')::boolean,true);
  IF d#>>'{safety,blocking}'='true' AND (safety_reason IS NULL OR safety_reason='unproven_empty_dealer_scope') THEN safety_reason:=d#>>'{safety,reason}'; END IF;
 END LOOP;
 -- Detect identities repeated across dealer partitions before any dealer writes.
 WITH selected AS (
  SELECT (e->>'index')::int idx,e->'row' r FROM jsonb_each(split->'groups') g CROSS JOIN LATERAL jsonb_array_elements(g.value) e
 ), identities AS (
  SELECT idx,public.navision_backend_source_record_id(r) sid,
   nullif(public.normalize_vehicle_stock_number(coalesce(r->>'stock',r->>'stock_number',r->>'batch')),'') stock,
   public.pdc_navision_complete_vin_20260907(r) vin,
   nullif(public.normalize_vehicle_source_identifier(coalesce(r->>'order',r->>'toyota_order_number')),'') ord FROM selected
 ), expanded AS (
  SELECT i.idx,v.kind,v.val FROM identities i CROSS JOIN LATERAL (VALUES('duplicate_source_record_id',sid),('duplicate_stock_number',stock),('duplicate_vin',vin),('duplicate_toyota_order',ord)) v(kind,val) WHERE v.val IS NOT NULL
 ), repeated AS (SELECT *,count(*) OVER(PARTITION BY kind,val) n FROM expanded)
 SELECT coalesce(jsonb_agg(jsonb_build_object('row_index',idx,'reason',kind) ORDER BY idx,kind),'[]'::jsonb) INTO duplicates FROM repeated WHERE n>1;
 IF jsonb_array_length(duplicates)>0 THEN
  SELECT jsonb_agg(CASE WHEN issue.reason IS NULL THEN e.value ELSE e.value||jsonb_build_object('classification','conflict','reason',issue.reason) END ORDER BY (e.value->>'row_index')::int)
  INTO items FROM jsonb_array_elements(items) e LEFT JOIN LATERAL
   (SELECT x->>'reason' reason FROM jsonb_array_elements(duplicates) x WHERE x->>'row_index'=e.value->>'row_index' LIMIT 1) issue ON true;
  FOREACH k IN ARRAY ARRAY['new','changed','unchanged','invalid','conflict'] LOOP
   counts:=jsonb_set(counts,ARRAY[k],to_jsonb((SELECT count(*)::int FROM jsonb_array_elements(items) e WHERE e->>'classification'=k)));
  END LOOP;
  blocking:=true;
 END IF;
 source_hash:=encode(extensions.digest(convert_to(p_rows::text,'UTF8'),'sha256'),'hex');
 d:=jsonb_build_object('counts',counts,'items',items,'dealer_groups',groups,'excluded_rows',split->'excluded_rows',
  'source_row_count',jsonb_array_length(p_rows),'source_hash',source_hash,'base_revision',revision,'blocking',blocking,
  'safety',jsonb_build_object('blocking',safety_reason IS NOT NULL,'reason',safety_reason),
  'authority','shared_navision_backend_only','operational_mutations',0,'atomic_apply',true);
 preview_hash:=encode(extensions.digest(convert_to(jsonb_build_object('data',d,'source_name',coalesce(p_source_name,''),'source_timestamp',p_source_timestamp)::text,'UTF8'),'sha256'),'hex');
 RETURN public.navision_backend_response(true,'preview',d||jsonb_build_object('preview_hash',preview_hash));
END $fn$;

CREATE FUNCTION public.approve_navision_combined_initial_scopes(p_rows jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='pg_catalog','public','extensions' AS $fn$
DECLARE split jsonb; g record; rows jsonb; r jsonb; approved jsonb:='[]';
BEGIN
 IF auth.uid() IS NULL OR public.current_pdc_user_role() IS DISTINCT FROM 'administrator'::public.pdc_role
  THEN RETURN public.navision_backend_response(false,'administrator_required'); END IF;
 IF NOT public.pdc_monitor_staging_guard() THEN RETURN public.navision_backend_response(false,'wrong_environment'); END IF;
 split:=pdc_navision_combined_private.split_rows(p_rows);
 FOR g IN SELECT key,value FROM jsonb_each(split->'groups') ORDER BY key LOOP
  IF NOT EXISTS(SELECT 1 FROM public.navision_backend_records WHERE dealer_code=g.key AND source_system='microsoft_navision' AND is_current AND record_status='current') THEN
   SELECT jsonb_agg(e->'row' ORDER BY (e->>'index')::int) INTO rows FROM jsonb_array_elements(g.value) e;
   r:=public.approve_navision_initial_scope(rows,'microsoft_navision',g.key);
   IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Initial scope approval failed: %',r->>'code' USING errcode='22023'; END IF;
   approved:=approved||jsonb_build_array(g.key);
  END IF;
 END LOOP;
 RETURN public.navision_backend_response(true,'initial_scope_approved',jsonb_build_object('dealers',approved));
END $fn$;

CREATE FUNCTION public.apply_navision_combined_import(p_idempotency_key text,p_rows jsonb,p_source_name text,p_source_timestamp timestamptz,
 p_source_hash text,p_preview_hash text,p_expected_revision bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='pg_catalog','public','extensions' AS $fn$
DECLARE request_hash text; prior pdc_navision_combined_private.receipts%rowtype; preview jsonb; split jsonb; g record; rows jsonb;
 child jsonb; applied jsonb; receipts jsonb:='[]'; result jsonb; revision bigint;
BEGIN
 IF auth.uid() IS NULL OR NOT coalesce(public.current_pdc_user_role()::text IN('importer','administrator'),false)
  THEN RETURN public.navision_backend_response(false,'unauthorized'); END IF;
 IF NOT public.pdc_monitor_staging_guard() THEN RETURN public.navision_backend_response(false,'wrong_environment'); END IF;
 IF nullif(btrim(p_idempotency_key),'') IS NULL OR length(p_idempotency_key)>200 OR p_expected_revision IS NULL
  THEN RETURN public.navision_backend_response(false,'invalid_input'); END IF;
 request_hash:=encode(extensions.digest(convert_to(jsonb_build_object('rows',p_rows,'source_name',p_source_name,'source_timestamp',p_source_timestamp,
  'source_hash',p_source_hash,'preview_hash',p_preview_hash,'expected_revision',p_expected_revision)::text,'UTF8'),'sha256'),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended('navision-combined:'||auth.uid()::text||':'||p_idempotency_key,0));
 SELECT * INTO prior FROM pdc_navision_combined_private.receipts WHERE actor_id=auth.uid() AND idempotency_key=p_idempotency_key;
 IF FOUND THEN
  IF prior.request_hash<>request_hash THEN RETURN public.navision_backend_response(false,'idempotency_conflict'); END IF;
  RETURN prior.response;
 END IF;
 -- Serialize with existing single-dealer imports and bind the whole snapshot.
 PERFORM pg_advisory_xact_lock(hashtextextended('navision-backend-store',0));
 SELECT r.revision INTO revision FROM public.navision_backend_revision r WHERE singleton FOR UPDATE;
 IF revision<>p_expected_revision THEN RETURN public.navision_backend_response(false,'stale_revision'); END IF;
 preview:=public.preview_navision_combined_import(p_rows,p_source_name,p_source_timestamp);
 IF preview->>'ok' IS DISTINCT FROM 'true' THEN RETURN preview; END IF;
 IF p_source_hash IS DISTINCT FROM preview#>>'{data,source_hash}' THEN RETURN public.navision_backend_response(false,'source_changed'); END IF;
 IF p_preview_hash IS DISTINCT FROM preview#>>'{data,preview_hash}' THEN RETURN public.navision_backend_response(false,'preview_changed'); END IF;
 IF preview#>>'{data,blocking}' IS DISTINCT FROM 'false' THEN RETURN public.navision_backend_response(false,'blocking_reconciliation',preview->'data'); END IF;
 split:=pdc_navision_combined_private.split_rows(p_rows);
 FOR g IN SELECT key,value FROM jsonb_each(split->'groups') ORDER BY key LOOP
  SELECT jsonb_agg(e->'row' ORDER BY (e->>'index')::int) INTO rows FROM jsonb_array_elements(g.value) e;
  -- Each successful child advances the shared revision. Recompute its exact
  -- preview under our lock; any later rejection raises and rolls back all children.
  child:=public.preview_navision_backend_import(rows,'microsoft_navision',g.key,'Combined Navision dealer '||g.key,p_source_timestamp);
  applied:=public.apply_navision_backend_import('combined:'||auth.uid()::text||':'||encode(extensions.digest(p_idempotency_key,'sha256'),'hex')||':'||g.key,
   rows,'microsoft_navision',g.key,'Combined Navision dealer '||g.key,p_source_timestamp,
   child#>>'{data,source_hash}',child#>>'{data,preview_hash}',(child#>>'{data,base_revision}')::bigint);
  IF applied->>'ok' IS DISTINCT FROM 'true' THEN
   RAISE EXCEPTION 'Combined Navision upload rolled back; dealer %: %',g.key,applied->>'code' USING errcode='P0001';
  END IF;
  receipts:=receipts||jsonb_build_array(jsonb_build_object('dealer_code',g.key,'result',applied));
 END LOOP;
 SELECT r.revision INTO revision FROM public.navision_backend_revision r WHERE singleton;
 result:=public.navision_backend_response(true,'applied',(preview->'data')||jsonb_build_object('dealer_receipts',receipts,'result_revision',revision,'idempotency_key',p_idempotency_key));
 INSERT INTO pdc_navision_combined_private.receipts(actor_id,idempotency_key,request_hash,source_name,response)
 VALUES(auth.uid(),p_idempotency_key,request_hash,coalesce(p_source_name,''),result);
 RETURN result;
END $fn$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA pdc_navision_combined_private FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.preview_navision_combined_import(jsonb,text,timestamptz) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.approve_navision_combined_initial_scopes(jsonb) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.apply_navision_combined_import(text,jsonb,text,timestamptz,text,text,bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.preview_navision_combined_import(jsonb,text,timestamptz),
 public.approve_navision_combined_initial_scopes(jsonb),public.apply_navision_combined_import(text,jsonb,text,timestamptz,text,text,bigint) TO authenticated;
NOTIFY pgrst,'reload schema';
