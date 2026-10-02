-- AUDIT COPY: approved current backend COSI scope and latest applied batch semantics.
-- Only fictional source rows and temporary account scopes are used. All writes roll back.
BEGIN ISOLATION LEVEL REPEATABLE READ;
CREATE FUNCTION pg_temp.cosi_fingerprint(p_schema text) RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE t record; h text; a text:='';
BEGIN
 FOR t IN SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname=p_schema AND c.relkind IN('r','p') ORDER BY c.relname LOOP
 EXECUTE format('SELECT md5(count(*)::text||coalesce(string_agg(h,'''' ORDER BY h),'''')) FROM (SELECT md5(to_jsonb(x)::text) h FROM %I.%I x) z',p_schema,t.relname) INTO h;
 a:=a||t.relname||':'||h||';';
 END LOOP; RETURN md5(a);
END $fn$;
DO $test$
DECLARE actor public.pdc_user_roles; viewer public.pdc_user_roles; person public.salespeople;
 batch uuid; older_batch uuid; source_id uuid; target_id uuid; no_id uuid; result jsonb; payload jsonb; snap jsonb; denied boolean;
 global_before text; private_before text; operations_before text;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'Staging only'; END IF;
 SELECT * INTO actor FROM public.pdc_user_roles WHERE active AND account_status='approved' AND role='administrator' AND auth_user_id IS NOT NULL LIMIT 1;
 SELECT * INTO viewer FROM public.pdc_user_roles WHERE active AND account_status='approved' AND role='viewer' AND auth_user_id IS NOT NULL LIMIT 1;
 SELECT * INTO person FROM public.salespeople WHERE code='BG' AND active;
 SELECT id INTO batch FROM public.navision_import_batches WHERE source_system='microsoft_navision' AND dealer_code='37047' AND status='applied' AND rolled_back_at IS NULL ORDER BY result_revision DESC,applied_at DESC,id DESC LIMIT 1;
 IF actor.id IS NULL OR viewer.id IS NULL OR person.id IS NULL OR batch IS NULL THEN RAISE EXCEPTION 'Missing staging rollback prerequisites'; END IF;
 IF EXISTS(SELECT 1 FROM public.navision_backend_records WHERE source_record_id LIKE 'COSI-SCOPE-%') OR EXISTS(SELECT 1 FROM pdc_sales_private.tracked_orders WHERE order_key LIKE 'COSI-SCOPE-%') THEN RAISE EXCEPTION 'Fictional fixture identifiers already exist'; END IF;
 global_before:=pg_temp.cosi_fingerprint('public'); private_before:=pg_temp.cosi_fingerprint('pdc_sales_private');
 BEGIN
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor.auth_user_id,'email',actor.email,'role','authenticated')::text,true);
  payload:=jsonb_build_array(
   jsonb_build_object('dealer_code','37047','order','COSI-SCOPE-EARLY','batch','','cosi',' Yes ','consultant','BG'),
   jsonb_build_object('dealer_code','37047','order','COSI-SCOPE-STOCK','batch','EXAMPLE-STOCK','cosi',true,'consultant','BG'),
   jsonb_build_object('dealer_code','37047','order','COSI-SCOPE-NO','batch','EXAMPLE-NO','cosi','No','consultant','BG'),
   jsonb_build_object('dealer_code','37047','order','COSI-SCOPE-UNKNOWN','batch','EXAMPLE-UNKNOWN','cosi',null,'consultant','BG'),
   jsonb_build_object('dealer_code','37047','order','COSI-SCOPE-CW','batch','EXAMPLE-CW','cosi',1,'consultant','CW'),
   jsonb_build_object('dealer_code','37047','order','COSI-SCOPE-NEW-UNSOLD','batch','','cosi','No','consultant','BG'));
  result:=public.import_broome_sales_orders(payload,false);
  IF result->>'accepted'<>'5' OR result->>'without_stock'<>'1' OR result->>'skipped_unsold'<>'1' THEN RAISE EXCEPTION 'Legacy eligibility preview failed'; END IF;
  IF EXISTS(SELECT 1 FROM pdc_sales_private.tracked_orders WHERE order_key LIKE 'COSI-SCOPE-%') THEN RAISE EXCEPTION 'Preview wrote records'; END IF;
  PERFORM public.import_broome_sales_orders(payload,true);
  SELECT id INTO target_id FROM pdc_sales_private.tracked_orders WHERE order_key='COSI-SCOPE-EARLY';
  SELECT id INTO no_id FROM pdc_sales_private.tracked_orders WHERE order_key='COSI-SCOPE-NO';
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') e WHERE e->>'order' LIKE 'COSI-SCOPE-%') THEN RAISE EXCEPTION 'Private-only order bypassed backend authority'; END IF;
  IF pg_temp.cosi_fingerprint('public')<>global_before THEN RAISE EXCEPTION 'Private import changed public operational/source data'; END IF;
  INSERT INTO public.navision_backend_records(source_system,dealer_code,source_record_id,row_hash,normalized_data,raw_evidence,first_seen_batch_id,last_seen_batch_id,record_status,is_current)
  SELECT 'microsoft_navision','37047',e->>'order',repeat('0',64),e,'{}',batch,batch,'current',true FROM jsonb_array_elements(payload) e;
  SELECT id INTO source_id FROM public.navision_backend_records WHERE source_record_id='COSI-SCOPE-EARLY' AND dealer_code='37047';
  operations_before:=pg_temp.cosi_fingerprint('public');
  snap:=public.get_broome_sales_snapshot();
  IF (SELECT count(*) FROM jsonb_array_elements(snap->'items') e WHERE e->>'order' LIKE 'COSI-SCOPE-%')<>3
   OR EXISTS(SELECT 1 FROM jsonb_array_elements(snap->'items') e WHERE e->>'cosi' IS DISTINCT FROM 'true')
   OR EXISTS(SELECT 1 FROM pdc_sales_private.tracked_orders WHERE order_key='COSI-SCOPE-NEW-UNSOLD') THEN RAISE EXCEPTION 'Current COSI-only snapshot failed'; END IF;
  PERFORM public.set_broome_sales_ordering_flag(target_id,'tint',true,0);
  PERFORM public.import_broome_sales_orders(jsonb_build_array((payload->0)||jsonb_build_object('cosi','No','consultant','')),true);
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') e WHERE e->>'tracking_id'=target_id::text AND e->>'tint'='true') THEN RAISE EXCEPTION 'Legacy private cancellation overrode current backend'; END IF;
  IF pg_temp.cosi_fingerprint('public')<>operations_before THEN RAISE EXCEPTION 'Sales checklist/private import changed public data'; END IF;
  -- Only current authoritative backend COSI changes hide the order.
  UPDATE public.navision_backend_records SET normalized_data=normalized_data||jsonb_build_object('cosi','No') WHERE id=source_id;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') e WHERE e->>'tracking_id'=target_id::text) THEN RAISE EXCEPTION 'Backend cancellation remained visible'; END IF;
  denied:=false; BEGIN PERFORM public.set_broome_sales_ordering_flag(target_id,'build_po',true,1); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'Cancelled order remained editable'; END IF;
  UPDATE public.navision_backend_records SET normalized_data=payload->0 WHERE id=source_id;
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') e WHERE e->>'tracking_id'=target_id::text AND e->>'tint'='true' AND e->>'ordering_version'='1' AND e->>'stock'='') THEN RAISE EXCEPTION 'Backend restoration lost stockless identity/checklist'; END IF;
  UPDATE public.navision_backend_records SET normalized_data=normalized_data||jsonb_build_object('cosi','') WHERE id=source_id;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') e WHERE e->>'tracking_id'=target_id::text) THEN RAISE EXCEPTION 'Unknown COSI remained visible'; END IF;
  UPDATE public.navision_backend_records SET normalized_data=(payload->0)-'cosi'||jsonb_build_object('batch','EXAMPLE-RAW','navisionRawEvidence',jsonb_build_object('columns',jsonb_build_array(jsonb_build_object('header','COSI','value','Yes')))),updated_at=now()-interval '1 day' WHERE id=source_id;
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') e WHERE e->>'tracking_id'=target_id::text AND e->>'stock'='EXAMPLE-RAW') THEN RAISE EXCEPTION 'Raw original COSI or backend stock projection failed'; END IF;
  UPDATE public.navision_backend_records SET normalized_data=jsonb_set(normalized_data,'{navisionRawEvidence,columns,0,value}','"No"') WHERE id=source_id;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') e WHERE e->>'tracking_id'=target_id::text) THEN RAISE EXCEPTION 'Raw source No lost precedence'; END IF;
  UPDATE public.navision_backend_records SET normalized_data=jsonb_set(normalized_data,'{navisionRawEvidence,columns,0,value}','"Yes"')||jsonb_build_object('cosi','') WHERE id=source_id;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') e WHERE e->>'tracking_id'=target_id::text) THEN RAISE EXCEPTION 'Explicit blank used stale raw Yes'; END IF;
  UPDATE public.navision_backend_records SET normalized_data=normalized_data-'cosi' WHERE id=source_id;
  -- Newer private timestamps do not change the authoritative source decision.
  PERFORM public.import_broome_sales_orders(jsonb_build_array((payload->0)||jsonb_build_object('cosi','No')),true);
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') e WHERE e->>'tracking_id'=target_id::text) THEN RAISE EXCEPTION 'Private timestamp overrode current backend Yes'; END IF;
  UPDATE public.navision_backend_records SET normalized_data=normalized_data||jsonb_build_object('cosi','Yes') WHERE dealer_code='37047' AND source_record_id='COSI-SCOPE-NO';
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') e WHERE e->>'tracking_id'=no_id::text) THEN RAISE EXCEPTION 'Backend stocked No-to-Yes lost tracked identity'; END IF;
  UPDATE public.navision_backend_records SET is_current=false,record_status='not_in_latest_batch',missing_since_batch_id=batch WHERE id=source_id;
  PERFORM public.import_broome_sales_orders(jsonb_build_array(payload->0),true);
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') e WHERE e->>'tracking_id'=target_id::text) THEN RAISE EXCEPTION 'Private fallback resurrected missing backend vehicle'; END IF;
  denied:=false; BEGIN PERFORM public.set_broome_sales_ordering_flag(target_id,'build_po',true,1); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'Missing order remained editable'; END IF;
  UPDATE public.navision_backend_records SET is_current=true,record_status='current',missing_since_batch_id=NULL WHERE id=source_id;
  SELECT id INTO older_batch FROM public.navision_import_batches WHERE source_system='microsoft_navision' AND dealer_code='37047' AND status='applied' AND rolled_back_at IS NULL AND id<>batch ORDER BY result_revision DESC LIMIT 1;
  IF older_batch IS NOT NULL THEN
   UPDATE public.navision_backend_records SET last_seen_batch_id=older_batch WHERE id=source_id;
   IF EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') e WHERE e->>'tracking_id'=target_id::text) THEN RAISE EXCEPTION 'Older applied batch row leaked into latest snapshot'; END IF;
   UPDATE public.navision_backend_records SET last_seen_batch_id=batch WHERE id=source_id;
  END IF;
  UPDATE public.pdc_user_roles SET role=NULL,active=false,account_status='pending' WHERE id=viewer.id;
  PERFORM public.assign_broome_sales_access(viewer.id,person.id);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',viewer.auth_user_id,'email',viewer.email,'role','authenticated')::text,true);
  snap:=public.get_broome_sales_snapshot();
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(snap->'items') e WHERE e->>'salesperson_code' IS DISTINCT FROM 'BG' OR e->>'cosi' IS DISTINCT FROM 'true') THEN RAISE EXCEPTION 'Salesperson scope leaked'; END IF;
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(snap->'items') e WHERE e->>'tracking_id'=target_id::text AND e->>'tint'='true') THEN RAISE EXCEPTION 'Own backend sold order missing or checklist lost'; END IF;
  IF public.is_pdc_role('operator') OR public.is_pdc_role('viewer') OR has_function_privilege('anon','public.get_broome_sales_snapshot()','EXECUTE') OR has_table_privilege('authenticated','pdc_sales_private.tracked_orders','SELECT') THEN RAISE EXCEPTION 'Sales access expanded PDC/private authority'; END IF;
  RAISE EXCEPTION 'Rollback successful fixtures' USING errcode='ZX001';
 EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL; END;
 IF pg_temp.cosi_fingerprint('public')<>global_before OR pg_temp.cosi_fingerprint('pdc_sales_private')<>private_before THEN RAISE EXCEPTION 'All public/private fixture rollback fingerprints changed'; END IF;
END $test$;
SELECT 'PASS: current backend COSI variants, raw evidence, stockless identity, isolated checklist, missing/latest-batch removal, private fallback denial and complete rollback fingerprints' AS verification;
ROLLBACK;
