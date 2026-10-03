-- Candidate only. Root creates the append-only CLI migration and applies STAGING.
-- Read-only build source; no progress/status inference or PDC/source/CRM writes.
DO $guard$ BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
 OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 OR current_setting('app.environment',true)='production' THEN RAISE EXCEPTION 'Exact staging environment required'; END IF;
END $guard$;

CREATE TABLE pdc_sales_private.sales_build_import_batches (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 dealer_code text NOT NULL DEFAULT '37047' CHECK(dealer_code='37047'),
 file_name text NOT NULL CHECK(length(file_name) BETWEEN 1 AND 255),
 file_sha256 text NOT NULL UNIQUE CHECK(file_sha256~'^[a-f0-9]{64}$'),
 source_payload_sha256 text NOT NULL CHECK(source_payload_sha256~'^[a-f0-9]{64}$'),
 imported_by uuid NOT NULL REFERENCES auth.users(id),
 imported_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 result jsonb NOT NULL DEFAULT '{}'::jsonb CHECK(jsonb_typeof(result)='object')
);
CREATE TABLE pdc_sales_private.sales_build_orders (
 dealer_code text NOT NULL CHECK(dealer_code='37047'),
 order_key text NOT NULL CHECK(order_key=upper(btrim(order_key)) AND length(order_key) BETWEEN 1 AND 80),
 tracking_id uuid NOT NULL,
 source_record_id uuid NOT NULL,
 source_stock text NOT NULL CHECK(length(source_stock) BETWEEN 1 AND 80),
 source_updated_at timestamptz NOT NULL,
 import_batch_id uuid NOT NULL REFERENCES pdc_sales_private.sales_build_import_batches(id),
 data jsonb NOT NULL CHECK(jsonb_typeof(data)='object' AND octet_length(data::text)<=262144),
 version integer NOT NULL DEFAULT 1 CHECK(version>0),
 imported_by uuid NOT NULL REFERENCES auth.users(id),
 imported_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(dealer_code,order_key)
);
CREATE INDEX sales_build_orders_tracking_idx ON pdc_sales_private.sales_build_orders(tracking_id);
CREATE INDEX sales_build_orders_batch_idx ON pdc_sales_private.sales_build_orders(import_batch_id);
CREATE INDEX sales_build_orders_imported_by_idx ON pdc_sales_private.sales_build_orders(imported_by);
CREATE INDEX sales_build_import_batches_imported_by_idx ON pdc_sales_private.sales_build_import_batches(imported_by);
-- Provenance UUIDs deliberately have no FK into PDC/source tables. New sales data
-- must not block an operational source import, canonical deletion or source repair.
ALTER TABLE pdc_sales_private.sales_build_import_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE pdc_sales_private.sales_build_orders ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE pdc_sales_private.sales_build_import_batches,pdc_sales_private.sales_build_orders FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION pdc_sales_private.build_payload(p_row jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SECURITY INVOKER SET search_path=pg_catalog AS $fn$
DECLARE key text; line jsonb; row_num jsonb; v_text text; result jsonb;
BEGIN
 IF jsonb_typeof(p_row) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'Each build row must be an object'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_row) k WHERE k NOT IN ('stock','dealer_code','expected_tracking_id','expected_navision_record_id','expected_order','expected_navision_updated_at','items','notes','other_lines','source_rows')) THEN RAISE EXCEPTION 'Unapproved build import field'; END IF;
 FOREACH key IN ARRAY ARRAY['items','notes','other_lines','source_rows'] LOOP
  IF jsonb_typeof(p_row->key) IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'Build % must be an array',key; END IF;
  IF jsonb_array_length(p_row->key)>(CASE WHEN key='source_rows' THEN 10000 ELSE 1000 END) THEN RAISE EXCEPTION 'Build % exceeds supported size',key; END IF;
 END LOOP;
 FOREACH key IN ARRAY ARRAY['items','notes','other_lines'] LOOP
  FOR line IN SELECT value FROM jsonb_array_elements(p_row->key) LOOP
   IF jsonb_typeof(line) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'Build lines must be objects'; END IF;
   IF EXISTS(SELECT 1 FROM jsonb_object_keys(line) k WHERE NOT k=ANY(CASE key WHEN 'items' THEN ARRAY['description','source_rows','quote_number'] WHEN 'notes' THEN ARRAY['text','source_rows'] ELSE ARRAY['description','source_rows','reason'] END)) THEN RAISE EXCEPTION 'Unapproved build line field'; END IF;
   v_text:=CASE WHEN key='notes' THEN line->>'text' ELSE line->>'description' END;
   IF jsonb_typeof(CASE WHEN key='notes' THEN line->'text' ELSE line->'description' END) IS DISTINCT FROM 'string' OR length(v_text)>6000
   OR (key<>'other_lines' AND coalesce(btrim(v_text),'')='') OR v_text~'[\x00-\x08\x0B\x0C\x0E-\x1F]' THEN RAISE EXCEPTION 'Invalid or oversized build description/note'; END IF;
   -- Preserve exact note line breaks and description text. No quantity or fitted
   -- status is inferred from a quote line, a repeated row or the all-zero Line field.
   IF jsonb_typeof(line->'source_rows') IS DISTINCT FROM 'array' OR jsonb_array_length(line->'source_rows') NOT BETWEEN 1 AND 10000 THEN RAISE EXCEPTION 'Source rows are required for each build line'; END IF;
   FOR row_num IN SELECT value FROM jsonb_array_elements(line->'source_rows') LOOP
    IF jsonb_typeof(row_num) IS DISTINCT FROM 'number' OR row_num::text!~'^[0-9]{1,7}$' OR (row_num::text)::integer NOT BETWEEN 1 AND 1000000 THEN RAISE EXCEPTION 'Invalid source row number'; END IF;
   END LOOP;
   IF key='items' AND line ? 'quote_number' AND line->'quote_number'<>'null'::jsonb THEN
    IF jsonb_typeof(line->'quote_number') NOT IN ('string','number') OR length(line->>'quote_number')>80 OR (line->>'quote_number')~'[\x00-\x1F]' THEN RAISE EXCEPTION 'Invalid source quote number'; END IF;
   END IF;
   IF key='other_lines' AND (jsonb_typeof(line->'reason') IS DISTINCT FROM 'string' OR length(line->>'reason') NOT BETWEEN 1 AND 200) THEN RAISE EXCEPTION 'An explanatory reason is required for other quote lines'; END IF;
  END LOOP;
 END LOOP;
 FOR row_num IN SELECT value FROM jsonb_array_elements(p_row->'source_rows') LOOP
  IF jsonb_typeof(row_num) IS DISTINCT FROM 'number' OR row_num::text!~'^[0-9]{1,7}$' OR (row_num::text)::integer NOT BETWEEN 1 AND 1000000 THEN RAISE EXCEPTION 'Invalid source row number'; END IF;
 END LOOP;
 result:=jsonb_build_object('items',p_row->'items','notes',p_row->'notes','other_lines',p_row->'other_lines','source_rows',p_row->'source_rows');
 IF octet_length(result::text)>262144 THEN RAISE EXCEPTION 'Build order payload exceeds supported size'; END IF;
 RETURN result;
END $fn$;

-- Sealed helper. Counts visible COSI stocks across the current dealer
-- snapshot before salesperson/roster filtering, without exposing another order.
CREATE FUNCTION pdc_sales_private.build_stock_counts()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,pdc_sales_private AS $fn$
DECLARE ctx jsonb:=pdc_sales_private.context(); result jsonb;
BEGIN
 IF ctx->>'dealer_code'<>'37047' THEN RAISE EXCEPTION 'Broome sales access required' USING errcode='42501'; END IF;
 WITH latest AS MATERIALIZED (
  SELECT b.id FROM public.navision_import_batches b WHERE b.source_system='microsoft_navision' AND b.dealer_code='37047'
  AND b.status='applied' AND b.rolled_back_at IS NULL ORDER BY b.result_revision DESC,b.applied_at DESC,b.id DESC LIMIT 1
 ), source_rows AS (
  SELECT n.*,upper(btrim(coalesce(nullif(n.normalized_data->>'order',''),public.navision_original_column_value(n.normalized_data,'Order')))) order_key
  FROM public.navision_backend_records n JOIN latest b ON b.id=n.last_seen_batch_id
  WHERE n.source_system='microsoft_navision' AND n.dealer_code='37047' AND n.is_current AND n.record_status='current'
 ), counted AS (
  SELECT n.*,count(*) OVER(PARTITION BY dealer_code,order_key) order_matches FROM source_rows n
 ), stocks AS (
 SELECT btrim(coalesce(nullif(n.normalized_data->>'batch',''),n.normalized_data->>'stock',v.stock_number,'')) AS stock FROM counted n
 LEFT JOIN pdc_sales_private.tracked_orders o ON o.dealer_code=n.dealer_code AND o.order_key=n.order_key AND n.order_matches=1
 LEFT JOIN public.vehicles v ON v.id=n.canonical_vehicle_id AND v.deleted_at IS NULL
 LEFT JOIN LATERAL (SELECT h.hidden FROM pdc_sales_private.vehicle_visibility h WHERE h.tracking_id=coalesce(o.id,n.id)
  OR (n.order_matches=1 AND h.dealer_code=n.dealer_code AND h.order_key=n.order_key)
  ORDER BY (h.tracking_id=coalesce(o.id,n.id)) DESC LIMIT 1) visibility ON true
 WHERE lower(btrim(coalesce(CASE WHEN n.normalized_data ? 'cosi' THEN n.normalized_data->>'cosi' ELSE public.navision_original_column_value(n.normalized_data,'COSI') END,''))) IN ('yes','true','1')
 AND (n.canonical_vehicle_id IS NULL OR v.id IS NOT NULL) AND NOT coalesce(visibility.hidden,false)
 )
 SELECT coalesce(jsonb_object_agg(s.stock,s.matches),'{}'::jsonb) INTO result FROM (SELECT stock,count(*) AS matches FROM stocks GROUP BY stock) s;
 RETURN result;
END $fn$;

CREATE FUNCTION pdc_sales_private.build_stock_match_count(p_stock text)
RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $fn$
 SELECT coalesce((pdc_sales_private.build_stock_counts()->>p_stock)::integer,0);
$fn$;

CREATE FUNCTION pdc_sales_private.get_builds()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,pdc_sales_private AS $fn$
DECLARE ctx jsonb:=pdc_sales_private.context(); current_items jsonb; stock_counts jsonb; result jsonb;
BEGIN
 SELECT pdc_sales_private.visibility_source_snapshot(false)->'items',pdc_sales_private.build_stock_counts() INTO current_items,stock_counts;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'tracking_id',e->>'tracking_id','navision_record_id',e->>'navision_record_id','stock',e->>'stock','order',e->>'order',
  'items',b.data->'items','notes',b.data->'notes','other_lines',b.data->'other_lines','source_rows',b.data->'source_rows',
  'source_file',f.file_name,'source_file_sha256',f.file_sha256,'imported_at',b.imported_at,
  'source_stock',b.source_stock,'build_version',b.version
 ) ORDER BY e->>'stock',e->>'order'),'[]'::jsonb) INTO result
 FROM jsonb_array_elements(current_items) e
 JOIN pdc_sales_private.sales_build_orders b ON b.dealer_code='37047' AND b.order_key=upper(btrim(e->>'order'))
  AND e->>'navision_record_id'=b.source_record_id::text
 JOIN pdc_sales_private.sales_build_import_batches f ON f.id=b.import_batch_id
 WHERE e->>'salesperson_code' IN ('AW','BG','PM','CW') AND NOT coalesce((e->>'identity_conflict')::boolean,false)
 AND coalesce(btrim(e->>'stock'),'') NOT IN ('','0','TBA') AND e->>'source_current'='true'
 AND coalesce((stock_counts->>btrim(e->>'stock'))::integer,0)=1;
 IF octet_length(result::text)>8000000 THEN RAISE EXCEPTION 'Sales build display exceeds supported size'; END IF;
 RETURN jsonb_build_object('context',ctx,'items',result,'checked_at',now());
END $fn$;

CREATE FUNCTION pdc_sales_private.import_builds(p_file_name text,p_file_sha256 text,p_rows jsonb)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,public,pdc_sales_private AS $fn$
DECLARE ctx jsonb:=pdc_sales_private.context(); actor_role uuid; filename text:=btrim(p_file_name); file_hash text:=lower(btrim(p_file_sha256));
 row_data jsonb; payload jsonb; normalized_rows jsonb:='[]'::jsonb; source_hash text; current_items jsonb; stock_counts jsonb; item jsonb;
 batch pdc_sales_private.sales_build_import_batches; existing pdc_sales_private.sales_build_orders;
stock text; v_order_key text; expected_id uuid; expected_source uuid; expected_at timestamptz; reason text; matches integer;
 imported_count integer:=0; unchanged_count integer:=0; skipped_count integer:=0;
imported_details jsonb:='[]'::jsonb; unchanged_details jsonb:='[]'::jsonb; skipped_details jsonb:='[]'::jsonb; v_result jsonb;
BEGIN
 IF ctx->>'role'<>'administrator' OR ctx->>'dealer_code'<>'37047' THEN RAISE EXCEPTION 'Administrator sales import access required' USING errcode='42501'; END IF;
 IF filename IS NULL OR length(filename) NOT BETWEEN 1 AND 255 OR position('/' in filename)>0 OR position(chr(92) in filename)>0 OR filename~'[[:cntrl:]]' OR file_hash IS NULL OR file_hash!~'^[a-f0-9]{64}$' THEN RAISE EXCEPTION 'Provide a source filename and SHA-256'; END IF;
 IF jsonb_typeof(p_rows) IS DISTINCT FROM 'array' OR jsonb_array_length(p_rows) NOT BETWEEN 1 AND 5000 OR octet_length(p_rows::text)>8000000 THEN RAISE EXCEPTION 'Provide 1 to 5000 bounded build order rows'; END IF;
 FOR row_data IN SELECT value FROM jsonb_array_elements(p_rows) LOOP
  IF jsonb_typeof(row_data) IS DISTINCT FROM 'object' OR jsonb_typeof(row_data->'stock') IS DISTINCT FROM 'string' OR length(row_data->>'stock')>80 THEN RAISE EXCEPTION 'Preserve source stocks as text'; END IF;
  IF row_data ? 'dealer_code' AND coalesce(row_data->>'dealer_code','') NOT IN ('37047','037047') THEN RAISE EXCEPTION 'Broome dealer 37047 is required'; END IF;
  payload:=pdc_sales_private.build_payload(row_data);
  normalized_rows:=normalized_rows||jsonb_build_array(jsonb_build_object('stock',btrim(row_data->>'stock'),'data',payload));
 END LOOP;
 -- Expected identity/timestamps are preview guards, not source-file contents.
 SELECT encode(sha256(convert_to(coalesce(jsonb_agg(e ORDER BY e->>'stock',e::text),'[]'::jsonb)::text,'UTF8')),'hex') INTO source_hash FROM jsonb_array_elements(normalized_rows) e;
 SELECT r.id INTO actor_role FROM public.pdc_user_roles r WHERE r.email=lower(coalesce(auth.jwt()->>'email','')) AND r.active AND r.account_status='approved'
 AND (r.auth_user_id=auth.uid() OR r.auth_user_id IS NULL) AND r.role::text='administrator';
 IF actor_role IS NULL THEN RAISE EXCEPTION 'Approved administrator required' USING errcode='42501'; END IF;
 PERFORM 1 FROM public.pdc_user_roles WHERE id=actor_role FOR SHARE;
 PERFORM pg_advisory_xact_lock(hashtextextended('broome-sales-build-import:37047',0));
 ctx:=pdc_sales_private.context();
 IF ctx->>'role'<>'administrator' THEN RAISE EXCEPTION 'Administrator sales import access required' USING errcode='42501'; END IF;
 SELECT * INTO batch FROM pdc_sales_private.sales_build_import_batches WHERE file_sha256=file_hash FOR UPDATE;
 IF batch.id IS NOT NULL THEN
  IF batch.source_payload_sha256<>source_hash THEN RAISE EXCEPTION 'This file checksum was already used with different source contents'; END IF;
  RETURN batch.result||jsonb_build_object('replayed',true,'imported',0,'unchanged',coalesce((batch.result->>'imported')::integer,0)+coalesce((batch.result->>'unchanged')::integer,0),
   'imported_details','[]'::jsonb,'unchanged_details',coalesce(batch.result->'imported_details','[]'::jsonb)||coalesce(batch.result->'unchanged_details','[]'::jsonb));
 END IF;
 -- Read current authoritative scope after acquiring the import lock. Never use
 -- retained private order fallback, finance editor references or client vehicle IDs.
 SELECT pdc_sales_private.visibility_source_snapshot(false)->'items',pdc_sales_private.build_stock_counts() INTO current_items,stock_counts;
 INSERT INTO pdc_sales_private.sales_build_import_batches(file_name,file_sha256,source_payload_sha256,imported_by)
 VALUES(filename,file_hash,source_hash,auth.uid()) RETURNING * INTO batch;
 FOR row_data IN SELECT value FROM jsonb_array_elements(p_rows) LOOP
  stock:=btrim(row_data->>'stock'); reason:=NULL; item:=NULL;
  IF upper(stock) IN ('','0','TBA') THEN reason:='blank_stock';
  ELSIF (SELECT count(*) FROM jsonb_array_elements(p_rows) e WHERE btrim(e->>'stock')=stock)>1 THEN reason:='duplicate_input_stock';
  ELSE
   SELECT count(*) INTO matches FROM jsonb_array_elements(current_items) e WHERE btrim(e->>'stock')=stock;
   IF matches=0 THEN reason:='not_on_current_visible_sales';
   ELSIF matches<>1 OR coalesce((stock_counts->>stock)::integer,0)<>1 THEN reason:='duplicate_current_stock';
   ELSE
    SELECT e INTO item FROM jsonb_array_elements(current_items) e WHERE btrim(e->>'stock')=stock;
    v_order_key:=nullif(upper(btrim(item->>'order')),'');
    IF coalesce((item->>'identity_conflict')::boolean,false) THEN reason:='identity_conflict';
    ELSIF item->>'salesperson_code' NOT IN ('AW','BG','PM','CW') OR item->>'salesperson_code' IS NULL THEN reason:='outside_sales_roster';
    ELSIF v_order_key IS NULL THEN reason:='missing_current_order';
    ELSIF item->>'source_current' IS DISTINCT FROM 'true' THEN reason:='source_not_current';
    ELSE
     IF nullif(btrim(row_data->>'expected_tracking_id'),'') IS NULL OR nullif(btrim(row_data->>'expected_navision_record_id'),'') IS NULL
      OR nullif(btrim(row_data->>'expected_order'),'') IS NULL OR nullif(btrim(row_data->>'expected_navision_updated_at'),'') IS NULL THEN reason:='preview_identity_required';
     ELSE
      BEGIN
       expected_id:=(row_data->>'expected_tracking_id')::uuid; expected_source:=(row_data->>'expected_navision_record_id')::uuid;
       IF length(row_data->>'expected_navision_updated_at')>40 OR (row_data->>'expected_navision_updated_at')!~'^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}' THEN RAISE EXCEPTION 'Invalid preview timestamp'; END IF;
       expected_at:=(row_data->>'expected_navision_updated_at')::timestamptz;
      EXCEPTION WHEN OTHERS THEN reason:='invalid_preview_identity'; END;
      IF reason IS NULL AND (expected_id IS DISTINCT FROM (item->>'tracking_id')::uuid OR expected_source IS DISTINCT FROM (item->>'navision_record_id')::uuid
       OR upper(btrim(row_data->>'expected_order')) IS DISTINCT FROM v_order_key OR expected_at IS DISTINCT FROM (item->>'navision_updated_at')::timestamptz) THEN reason:='stale_preview_identity'; END IF;
     END IF;
    END IF;
   END IF;
  END IF;
  IF reason IS NOT NULL THEN skipped_count:=skipped_count+1; skipped_details:=skipped_details||jsonb_build_array(jsonb_build_object('stock',stock,'reason',reason)); CONTINUE; END IF;
  payload:=pdc_sales_private.build_payload(row_data);
  SELECT * INTO existing FROM pdc_sales_private.sales_build_orders WHERE dealer_code='37047' AND order_key=v_order_key FOR UPDATE;
  -- An identical newer file is logged but does not rewrite unchanged provenance.
  IF existing.order_key IS NOT NULL AND existing.data=payload AND existing.source_stock=stock AND existing.tracking_id=expected_id AND existing.source_record_id=expected_source THEN
   unchanged_count:=unchanged_count+1; unchanged_details:=unchanged_details||jsonb_build_array(jsonb_build_object('stock',stock,'order',item->>'order','tracking_id',item->>'tracking_id')); CONTINUE;
  END IF;
  INSERT INTO pdc_sales_private.sales_build_orders AS current(dealer_code,order_key,tracking_id,source_record_id,source_stock,source_updated_at,import_batch_id,data,imported_by)
  VALUES('37047',v_order_key,expected_id,expected_source,stock,expected_at,batch.id,payload,auth.uid())
  ON CONFLICT(dealer_code,order_key) DO UPDATE SET tracking_id=excluded.tracking_id,source_record_id=excluded.source_record_id,source_stock=excluded.source_stock,
   source_updated_at=excluded.source_updated_at,import_batch_id=excluded.import_batch_id,data=excluded.data,version=current.version+1,imported_by=excluded.imported_by,imported_at=clock_timestamp();
  imported_count:=imported_count+1; imported_details:=imported_details||jsonb_build_array(jsonb_build_object('stock',stock,'order',item->>'order','tracking_id',item->>'tracking_id'));
 END LOOP;
 v_result:=jsonb_build_object('batch_id',batch.id,'file_name',filename,'file_sha256',file_hash,'replayed',false,
  'imported',imported_count,'unchanged',unchanged_count,'skipped',skipped_count,'imported_details',imported_details,'unchanged_details',unchanged_details,'skipped_details',skipped_details);
 UPDATE pdc_sales_private.sales_build_import_batches SET result=v_result WHERE id=batch.id;
 RETURN v_result;
END $fn$;

CREATE FUNCTION public.get_broome_sales_builds()
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog AS $fn$ SELECT pdc_sales_private.get_builds() $fn$;
CREATE FUNCTION public.import_broome_sales_builds(p_file_name text,p_file_sha256 text,p_rows jsonb)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path=pg_catalog AS $fn$ SELECT pdc_sales_private.import_builds(p_file_name,p_file_sha256,p_rows) $fn$;
REVOKE ALL ON FUNCTION pdc_sales_private.build_payload(jsonb),pdc_sales_private.build_stock_counts(),pdc_sales_private.build_stock_match_count(text),pdc_sales_private.get_builds(),pdc_sales_private.import_builds(text,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION pdc_sales_private.get_builds(),pdc_sales_private.import_builds(text,text,jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.get_broome_sales_builds(),public.import_broome_sales_builds(text,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_broome_sales_builds(),public.import_broome_sales_builds(text,text,jsonb) TO authenticated;
-- Backup/restore schema traversal must include BOTH new private tables and their
-- private batch FK. Source ZIPs alone contain no imported build records/notes.
NOTIFY pgrst,'reload schema';
