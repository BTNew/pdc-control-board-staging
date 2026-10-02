-- Fictional bulk import matching the reported shape: 260 sold, 98 without stock.
-- No schema change. Every write is rolled back; all public tables are fingerprinted.
BEGIN ISOLATION LEVEL REPEATABLE READ;
DO $test$
DECLARE actor public.pdc_user_roles; payload jsonb; result jsonb; ids_before jsonb;
 public_before text:=''; public_after text:=''; private_before text:=''; private_after text:='';
 t record; value_hash text; denied boolean;
BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1 THEN RAISE EXCEPTION 'Staging required'; END IF;
 SELECT * INTO actor FROM public.pdc_user_roles WHERE active AND account_status='approved' AND role::text='administrator' AND auth_user_id IS NOT NULL LIMIT 1;
 IF actor.id IS NULL THEN RAISE EXCEPTION 'Approved test administrator missing'; END IF;
 FOR t IN SELECT c.relname,n.nspname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','pdc_sales_private') AND c.relkind IN ('r','p') ORDER BY n.nspname,c.relname LOOP
  EXECUTE format('SELECT md5(count(*)::text||'':''||coalesce(string_agg(row_hash,'''' ORDER BY row_hash),'''')) FROM (SELECT md5(to_jsonb(x)::text) row_hash FROM %I.%I x) rows',t.nspname,t.relname) INTO value_hash;
  IF t.nspname='public' THEN public_before:=public_before||t.relname||':'||value_hash||';'; ELSE private_before:=private_before||t.relname||':'||value_hash||';'; END IF;
 END LOOP;
 BEGIN
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor.auth_user_id,'email',actor.email,'role','authenticated')::text,true);
  SELECT jsonb_agg(jsonb_build_object('dealer_code','37047','order','UPLOAD-ROUTE-TEST-'||i,'batch',CASE WHEN i<=98 THEN '' ELSE 'EXAMPLE-STOCK-'||i END,'cosi','Yes','consultant','BG','client','Fictional customer','vehicle','Example Hilux','prodMth','202611','navisionKewdaleEta','2026-11-15') ORDER BY i) INTO payload FROM generate_series(1,260) i;
  IF EXISTS(SELECT 1 FROM pdc_sales_private.tracked_orders WHERE order_key LIKE 'UPLOAD-ROUTE-TEST-%') THEN RAISE EXCEPTION 'Test fixture collision'; END IF;
  result:=public.import_broome_sales_orders(payload,false);
  IF result->>'accepted'<>'260' OR result->>'without_stock'<>'98' OR result->>'applied'<>'false' THEN RAISE EXCEPTION 'Bulk preview count mismatch: %',result; END IF;
  IF EXISTS(SELECT 1 FROM pdc_sales_private.tracked_orders WHERE order_key LIKE 'UPLOAD-ROUTE-TEST-%') THEN RAISE EXCEPTION 'Preview wrote orders'; END IF;
  result:=public.import_broome_sales_orders(payload,true);
  IF result->>'accepted'<>'260' OR result->>'without_stock'<>'98' OR result->>'changed'<>'260' OR result->>'applied'<>'true' THEN RAISE EXCEPTION 'Bulk apply failed: %',result; END IF;
  SELECT jsonb_object_agg(order_key,id) INTO ids_before FROM pdc_sales_private.tracked_orders WHERE order_key LIKE 'UPLOAD-ROUTE-TEST-%';
  result:=public.import_broome_sales_orders(payload,true);
  IF result->>'changed'<>'0' THEN RAISE EXCEPTION 'Repeated upload was not idempotent'; END IF;
  payload:=jsonb_set(payload,'{0,batch}','"EXAMPLE-LATER-STOCK"'::jsonb);
  result:=public.import_broome_sales_orders(payload,true);
  IF result->>'changed'<>'1' OR result->>'without_stock'<>'97' THEN RAISE EXCEPTION 'Later stock allocation incorrect'; END IF;
  IF ids_before IS DISTINCT FROM (SELECT jsonb_object_agg(order_key,id) FROM pdc_sales_private.tracked_orders WHERE order_key LIKE 'UPLOAD-ROUTE-TEST-%') THEN RAISE EXCEPTION 'Order UUID changed when stock allocated'; END IF;
  denied:=false;
  BEGIN PERFORM public.import_broome_sales_orders(jsonb_build_array((payload->0)||jsonb_build_object('order','')),true); EXCEPTION WHEN OTHERS THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'Missing Toyota Order accepted'; END IF;
  denied:=false;
  BEGIN PERFORM public.import_broome_sales_orders(jsonb_build_array(payload->0,payload->0),true); EXCEPTION WHEN OTHERS THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'Duplicate Toyota Order accepted'; END IF;
  denied:=false;
  BEGIN PERFORM public.import_broome_sales_orders(jsonb_build_array(jsonb_build_object('dealer_code','37047','order','UPLOAD-ROUTE-UNSOLD','batch','','cosi','No','consultant','BG')),true); EXCEPTION WHEN OTHERS THEN denied:=true; END;
  IF NOT denied OR EXISTS(SELECT 1 FROM pdc_sales_private.tracked_orders WHERE order_key='UPLOAD-ROUTE-UNSOLD') THEN RAISE EXCEPTION 'Unsold stockless vehicle added'; END IF;
  FOR t IN SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN ('r','p') ORDER BY c.relname LOOP
   EXECUTE format('SELECT md5(count(*)::text||'':''||coalesce(string_agg(row_hash,'''' ORDER BY row_hash),'''')) FROM (SELECT md5(to_jsonb(x)::text) row_hash FROM public.%I x) rows',t.relname) INTO value_hash;
   public_after:=public_after||t.relname||':'||value_hash||';';
  END LOOP;
  IF public_before<>public_after THEN RAISE EXCEPTION 'Sales import changed a public PDC table'; END IF;
  RAISE EXCEPTION 'Successful fixtures rolled back' USING errcode='ZX001';
 EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL;
 END;
 public_after:='';
 FOR t IN SELECT c.relname,n.nspname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','pdc_sales_private') AND c.relkind IN ('r','p') ORDER BY n.nspname,c.relname LOOP
  EXECUTE format('SELECT md5(count(*)::text||'':''||coalesce(string_agg(row_hash,'''' ORDER BY row_hash),'''')) FROM (SELECT md5(to_jsonb(x)::text) row_hash FROM %I.%I x) rows',t.nspname,t.relname) INTO value_hash;
  IF t.nspname='public' THEN public_after:=public_after||t.relname||':'||value_hash||';'; ELSE private_after:=private_after||t.relname||':'||value_hash||';'; END IF;
 END LOOP;
 IF public_before<>public_after OR private_before<>private_after THEN RAISE EXCEPTION 'Fixture rollback changed stored data'; END IF;
END $test$;
SELECT 'PASS: 260 sold orders; 98 blank batches; repeat upload unchanged; later stock keeps UUID; all public PDC tables unchanged; all fixtures rolled back' AS result;
ROLLBACK;
