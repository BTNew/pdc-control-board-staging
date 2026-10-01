-- Example sales-only COSI transitions and latest-source precedence. All fixtures are rolled back.
BEGIN;
DO $test$
DECLARE actor public.pdc_user_roles; viewer public.pdc_user_roles; person public.salespeople;
 source_row public.navision_backend_records; snap jsonb; result jsonb; payload jsonb;
 target_id uuid; no_id uuid; denied boolean; op_before text; op_after text; sales_before text;
BEGIN
 SELECT * INTO actor FROM public.pdc_user_roles WHERE active AND account_status='approved' AND role='administrator' AND auth_user_id IS NOT NULL LIMIT 1;
 SELECT * INTO viewer FROM public.pdc_user_roles WHERE active AND account_status='approved' AND role='viewer' AND auth_user_id IS NOT NULL LIMIT 1;
 SELECT * INTO person FROM public.salespeople WHERE code='BG' AND active;
 SELECT * INTO source_row FROM public.navision_backend_records WHERE dealer_code='37047' AND canonical_vehicle_id IS NULL AND is_current LIMIT 1;
 IF actor.id IS NULL OR viewer.id IS NULL OR person.id IS NULL OR source_row.id IS NULL THEN RAISE EXCEPTION 'Missing rollback fixtures'; END IF;
 SELECT md5(jsonb_build_array(
  (SELECT jsonb_agg(to_jsonb(v) ORDER BY id) FROM public.vehicles v),
  (SELECT jsonb_agg(to_jsonb(n) ORDER BY id) FROM public.navision_backend_records n),
  (SELECT jsonb_agg(to_jsonb(b) ORDER BY id) FROM public.workshop_bookings b),
  (SELECT jsonb_agg(to_jsonb(b) ORDER BY id) FROM public.vehicle_parts_updates b),
  (SELECT jsonb_agg(to_jsonb(b) ORDER BY id) FROM public.navision_import_batches b))::text) INTO op_before;
 SELECT md5(jsonb_build_array(
  (SELECT jsonb_agg(to_jsonb(o) ORDER BY id) FROM pdc_sales_private.tracked_orders o),
  (SELECT jsonb_agg(to_jsonb(p) ORDER BY tracking_id) FROM pdc_sales_private.ordering_progress p),
  (SELECT jsonb_agg(to_jsonb(p) ORDER BY id) FROM public.pdc_user_roles p))::text) INTO sales_before;
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
  IF result->>'accepted'<>'5' OR result->>'without_stock'<>'1' OR result->>'skipped_unsold'<>'1' THEN RAISE EXCEPTION 'Initial eligibility preview failed'; END IF;
  IF EXISTS(SELECT 1 FROM pdc_sales_private.tracked_orders WHERE order_key LIKE 'COSI-SCOPE-%') THEN RAISE EXCEPTION 'Preview changed records or fixture already exists'; END IF;
  result:=public.import_broome_sales_orders(payload,true);
  SELECT id INTO target_id FROM pdc_sales_private.tracked_orders WHERE order_key='COSI-SCOPE-EARLY';
  SELECT id INTO no_id FROM pdc_sales_private.tracked_orders WHERE order_key='COSI-SCOPE-NO';
  snap:=public.get_broome_sales_snapshot();
  IF (SELECT count(*) FROM jsonb_array_elements(snap->'items') e WHERE e->>'order' LIKE 'COSI-SCOPE-%')<>3
   OR EXISTS(SELECT 1 FROM jsonb_array_elements(snap->'items') e WHERE e->>'cosi' IS DISTINCT FROM 'true')
   OR EXISTS(SELECT 1 FROM pdc_sales_private.tracked_orders WHERE order_key='COSI-SCOPE-NEW-UNSOLD') THEN RAISE EXCEPTION 'COSI-only snapshot failed'; END IF;
  result:=public.set_broome_sales_ordering_flag(target_id,'tint',true,0);
  result:=public.import_broome_sales_orders(jsonb_build_array((payload->0)||jsonb_build_object('cosi','No')),false);
  IF result->>'visibility_updates'<>'1' OR result->>'accepted'<>'0' OR result->>'changed'<>'0' THEN RAISE EXCEPTION 'Cancellation preview failed'; END IF;
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') e WHERE e->>'tracking_id'=target_id::text) THEN RAISE EXCEPTION 'Cancellation preview hid order'; END IF;
  result:=public.import_broome_sales_orders(jsonb_build_array((payload->0)||jsonb_build_object('cosi','No','consultant','')),true);
  IF result->>'visibility_updates'<>'1' OR result->>'changed'<>'1' OR EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') e WHERE e->>'tracking_id'=target_id::text) THEN RAISE EXCEPTION 'Stockless cancellation remained visible'; END IF;
  denied:=false;BEGIN PERFORM public.set_broome_sales_ordering_flag(target_id,'build_po',true,1);EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
  IF NOT denied THEN RAISE EXCEPTION 'Hidden order remained editable'; END IF;
  result:=public.import_broome_sales_orders(jsonb_build_array(payload->0),true);
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') e WHERE e->>'tracking_id'=target_id::text AND e->>'tint'='true' AND e->>'ordering_version'='1') THEN RAISE EXCEPTION 'Restored COSI order lost UUID/checklist'; END IF;
  result:=public.import_broome_sales_orders(jsonb_build_array((payload->0)||jsonb_build_object('cosi','')),true);
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') e WHERE e->>'tracking_id'=target_id::text) THEN RAISE EXCEPTION 'Unknown COSI remained visible'; END IF;
  result:=public.import_broome_sales_orders(jsonb_build_array((payload->0)||jsonb_build_object('cosi',true)),true);
  result:=public.import_broome_sales_orders(jsonb_build_array((payload->2)||jsonb_build_object('cosi','Yes')),true);
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') e WHERE e->>'tracking_id'=no_id::text) THEN RAISE EXCEPTION 'Stocked No to Yes did not retain identity'; END IF;
  SELECT md5(jsonb_build_array((SELECT jsonb_agg(to_jsonb(v) ORDER BY id) FROM public.vehicles v),(SELECT jsonb_agg(to_jsonb(n) ORDER BY id) FROM public.navision_backend_records n),(SELECT jsonb_agg(to_jsonb(b) ORDER BY id) FROM public.workshop_bookings b),(SELECT jsonb_agg(to_jsonb(b) ORDER BY id) FROM public.vehicle_parts_updates b),(SELECT jsonb_agg(to_jsonb(b) ORDER BY id) FROM public.navision_import_batches b))::text) INTO op_after;
  IF op_after<>op_before THEN RAISE EXCEPTION 'Sales changes wrote PDC/source/bookings/parts/import records'; END IF;
  -- Simulate newer shared source evidence without applying a real PDC import.
  UPDATE public.navision_backend_records SET normalized_data=jsonb_build_object('order','COSI-SCOPE-EARLY','batch','EXAMPLE-RAW','consultant','BG','navisionRawEvidence',jsonb_build_object('columns',jsonb_build_array(jsonb_build_object('header','COSI','value','Yes')))),updated_at=now()+interval '1 second' WHERE id=source_row.id;
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') e WHERE e->>'tracking_id'=target_id::text AND e->>'stock'='EXAMPLE-RAW') THEN RAISE EXCEPTION 'Raw original COSI not projected'; END IF;
  UPDATE public.navision_backend_records SET normalized_data=jsonb_set(normalized_data,'{navisionRawEvidence,columns,0,value}','"No"') WHERE id=source_row.id;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') e WHERE e->>'tracking_id'=target_id::text) THEN RAISE EXCEPTION 'Newer source No lost precedence'; END IF;
  UPDATE public.navision_backend_records SET normalized_data=jsonb_set(normalized_data,'{navisionRawEvidence,columns,0,value}','"Yes"')||jsonb_build_object('cosi','') WHERE id=source_row.id;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') e WHERE e->>'tracking_id'=target_id::text) THEN RAISE EXCEPTION 'Explicit blank used stale raw Yes'; END IF;
  UPDATE public.navision_backend_records SET normalized_data=normalized_data-'cosi',updated_at=now()-interval '1 second' WHERE id=source_row.id;
  result:=public.import_broome_sales_orders(jsonb_build_array((payload->0)||jsonb_build_object('cosi','No')),true);
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') e WHERE e->>'tracking_id'=target_id::text) THEN RAISE EXCEPTION 'Newer private No used older source Yes'; END IF;
  -- A fresh identical No export must supersede a newer shared Yes observation.
  UPDATE pdc_sales_private.tracked_orders SET imported_at=now()-interval '2 seconds' WHERE id=target_id;
  UPDATE public.navision_backend_records SET updated_at=now()-interval '1 second' WHERE id=source_row.id;
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') e WHERE e->>'tracking_id'=target_id::text) THEN RAISE EXCEPTION 'Newer shared Yes not used'; END IF;
  result:=public.import_broome_sales_orders(jsonb_build_array((payload->0)||jsonb_build_object('cosi','No')),true);
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') e WHERE e->>'tracking_id'=target_id::text) THEN RAISE EXCEPTION 'Identical fresh No lost source precedence'; END IF;
  result:=public.import_broome_sales_orders(jsonb_build_array(payload->0),true);
  UPDATE public.navision_backend_records SET is_current=false,record_status='not_in_latest_batch',missing_since_batch_id=last_seen_batch_id WHERE id=source_row.id;
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') e WHERE e->>'tracking_id'=target_id::text AND e->>'source_current'='false') THEN RAISE EXCEPTION 'Source absence removed COSI order'; END IF;
  UPDATE public.pdc_user_roles SET role=NULL,active=false,account_status='pending' WHERE id=viewer.id;
  PERFORM public.assign_broome_sales_access(viewer.id,person.id);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',viewer.auth_user_id,'email',viewer.email,'role','authenticated')::text,true);
  snap:=public.get_broome_sales_snapshot();
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(snap->'items') e WHERE e->>'salesperson_code' IS DISTINCT FROM 'BG' OR e->>'cosi' IS DISTINCT FROM 'true') THEN RAISE EXCEPTION 'Salesperson scope leaked'; END IF;
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(snap->'items') e WHERE e->>'tracking_id'=target_id::text) THEN RAISE EXCEPTION 'Own sold order missing'; END IF;
  IF has_function_privilege('anon','public.get_broome_sales_snapshot()','EXECUTE') OR has_table_privilege('authenticated','pdc_sales_private.tracked_orders','SELECT') THEN RAISE EXCEPTION 'Unexpected permission expansion'; END IF;
  RAISE EXCEPTION 'Rollback successful fixtures' USING errcode='ZX001';
 EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL;
 END;
 SELECT md5(jsonb_build_array((SELECT jsonb_agg(to_jsonb(v) ORDER BY id) FROM public.vehicles v),(SELECT jsonb_agg(to_jsonb(n) ORDER BY id) FROM public.navision_backend_records n),(SELECT jsonb_agg(to_jsonb(b) ORDER BY id) FROM public.workshop_bookings b),(SELECT jsonb_agg(to_jsonb(b) ORDER BY id) FROM public.vehicle_parts_updates b),(SELECT jsonb_agg(to_jsonb(b) ORDER BY id) FROM public.navision_import_batches b))::text) INTO op_after;
 IF op_after<>op_before THEN RAISE EXCEPTION 'PDC fixture rollback failed'; END IF;
 IF sales_before<>(SELECT md5(jsonb_build_array((SELECT jsonb_agg(to_jsonb(o) ORDER BY id) FROM pdc_sales_private.tracked_orders o),(SELECT jsonb_agg(to_jsonb(p) ORDER BY tracking_id) FROM pdc_sales_private.ordering_progress p),(SELECT jsonb_agg(to_jsonb(p) ORDER BY id) FROM public.pdc_user_roles p))::text)) THEN RAISE EXCEPTION 'Sales/account fixture rollback failed'; END IF;
END $test$;
SELECT 'COSI visibility, cancellation/restore, source precedence, stable checklist, salesperson scope and unchanged PDC fingerprints passed; fixtures rolled back' AS verification;
ROLLBACK;
