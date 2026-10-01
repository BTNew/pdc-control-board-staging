-- Synthetic intake fixtures exist only inside a rollback subtransaction.
BEGIN;
DO $test$
DECLARE actor public.pdc_user_roles; viewer public.pdc_user_roles; person public.salespeople;
 snap jsonb; result jsonb; payload jsonb; source_row public.navision_backend_records;
 target_id uuid; bay_vehicle_id uuid; registry_before text; op_before text; op_after text; denied boolean;
BEGIN
 SELECT * INTO actor FROM public.pdc_user_roles WHERE active AND account_status='approved' AND role='administrator' AND auth_user_id IS NOT NULL LIMIT 1;
 SELECT * INTO viewer FROM public.pdc_user_roles WHERE active AND account_status='approved' AND role='viewer' AND auth_user_id IS NOT NULL LIMIT 1;
 SELECT * INTO person FROM public.salespeople WHERE code='BG' AND active;
 SELECT * INTO source_row FROM public.navision_backend_records WHERE dealer_code='37047' AND canonical_vehicle_id IS NULL AND is_current LIMIT 1;
 IF actor.id IS NULL OR viewer.id IS NULL OR person.id IS NULL OR source_row.id IS NULL THEN RAISE EXCEPTION 'Missing rollback fixtures'; END IF;
 SELECT md5(jsonb_build_array(
  (SELECT jsonb_agg(to_jsonb(v) ORDER BY id) FROM public.vehicles v),
  (SELECT jsonb_agg(to_jsonb(n) ORDER BY id) FROM public.navision_backend_records n),
  (SELECT jsonb_agg(to_jsonb(b) ORDER BY id) FROM public.workshop_bookings b))::text) INTO op_before;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(o) ORDER BY id),'[]'::jsonb)::text) INTO registry_before FROM pdc_sales_private.tracked_orders o;
 BEGIN
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor.auth_user_id,'email',actor.email,'role','authenticated')::text,true);
  payload:=jsonb_build_array(jsonb_build_object('dealer_code','37047','order','000-SALES-TEST','batch','','cosi','Yes','consultant','BG','client','Example only','vehicle','Example vehicle'),
   jsonb_build_object('dealer_code','37047','order','UNSOLD-SALES-TEST','batch','','cosi','No','consultant','BG'));
  result:=public.import_broome_sales_orders(payload,false);
  IF result->>'accepted'<>'1' OR result->>'without_stock'<>'1' OR result->>'skipped_unsold'<>'1' THEN RAISE EXCEPTION 'COSI intake rule failed'; END IF;
  IF EXISTS(SELECT 1 FROM pdc_sales_private.tracked_orders WHERE order_key='000-SALES-TEST') THEN RAISE EXCEPTION 'Preview wrote records'; END IF;
  result:=public.import_broome_sales_orders(payload,true);
  SELECT id INTO target_id FROM pdc_sales_private.tracked_orders WHERE order_key='000-SALES-TEST';
  IF target_id IS NULL THEN RAISE EXCEPTION 'Order-only import failed'; END IF;
  result:=public.import_broome_sales_orders(payload,true);
  IF result->>'changed'<>'0' THEN RAISE EXCEPTION 'Replay changed order'; END IF;
  -- Real public rows must remain exactly unchanged after sales-only imports.
  SELECT md5(jsonb_build_array((SELECT jsonb_agg(to_jsonb(v) ORDER BY id) FROM public.vehicles v),(SELECT jsonb_agg(to_jsonb(n) ORDER BY id) FROM public.navision_backend_records n),(SELECT jsonb_agg(to_jsonb(b) ORDER BY id) FROM public.workshop_bookings b))::text) INTO op_after;
  IF op_after<>op_before THEN RAISE EXCEPTION 'Sales import changed PDC records'; END IF;
  snap:=public.get_broome_sales_snapshot();
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(snap->'items') e WHERE e->>'tracking_id'=target_id::text AND e->>'stock'='' AND e->>'order'='000-SALES-TEST') THEN RAISE EXCEPTION 'Early order not visible'; END IF;
  -- Simulate a later Navision stock allocation; source UUID differs, sales UUID stays.
  UPDATE public.navision_backend_records SET normalized_data=jsonb_build_object('batch','TEST-STOCK','order','000-SALES-TEST','consultant','BG'),updated_at=now()+interval '1 second' WHERE id=source_row.id;
  snap:=public.get_broome_sales_snapshot();
  IF (SELECT count(*) FROM jsonb_array_elements(snap->'items') e WHERE e->>'tracking_id'=target_id::text)<>1 OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(snap->'items') e WHERE e->>'tracking_id'=target_id::text AND e->>'stock'='TEST-STOCK') THEN RAISE EXCEPTION 'Order-to-stock identity split'; END IF;
  UPDATE public.navision_backend_records SET is_current=false,record_status='not_in_latest_batch',missing_since_batch_id=last_seen_batch_id WHERE id=source_row.id;
  snap:=public.get_broome_sales_snapshot();
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(snap->'items') e WHERE e->>'tracking_id'=target_id::text AND e->>'source_current'='false') THEN RAISE EXCEPTION 'Missing source removed order'; END IF;
  SELECT v.id INTO bay_vehicle_id FROM public.vehicles v WHERE v.deleted_at IS NULL AND EXISTS(SELECT 1 FROM public.workshop_bookings w WHERE w.vehicle_id=v.id AND w.deleted_at IS NULL AND NOT w.legacy_ambiguity_quarantined) LIMIT 1;
  IF bay_vehicle_id IS NOT NULL THEN
   UPDATE public.vehicles SET salesperson_manual_override=false WHERE id=bay_vehicle_id;
   UPDATE public.navision_backend_records SET canonical_vehicle_id=bay_vehicle_id WHERE id=source_row.id;
   snap:=public.get_broome_sales_snapshot();
   IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(snap->'items') e WHERE e->>'tracking_id'=target_id::text AND e->>'canonical_vehicle_id'=bay_vehicle_id::text AND jsonb_array_length(e->'bay_bookings')=(SELECT count(*) FROM public.workshop_bookings w WHERE w.vehicle_id=bay_vehicle_id AND w.deleted_at IS NULL AND NOT w.legacy_ambiguity_quarantined)) THEN RAISE EXCEPTION 'Bay projection diverged from exact canonical vehicle'; END IF;
   IF EXISTS(SELECT 1 FROM jsonb_array_elements(snap->'items') e CROSS JOIN LATERAL jsonb_array_elements(e->'bay_bookings') b WHERE b ? 'metadata' OR b ? 'technician_id' OR b ? 'source') THEN RAISE EXCEPTION 'Booking private fields leaked'; END IF;
  END IF;
  denied:=false;BEGIN PERFORM public.import_broome_sales_orders(jsonb_build_array(payload->0,payload->0),true);EXCEPTION WHEN OTHERS THEN denied:=true;END;
  IF NOT denied THEN RAISE EXCEPTION 'Duplicate order accepted'; END IF;
  denied:=false;BEGIN PERFORM public.import_broome_sales_orders(jsonb_build_array((payload->0)||jsonb_build_object('dealer_code','14450')),true);EXCEPTION WHEN OTHERS THEN denied:=true;END;
  IF NOT denied THEN RAISE EXCEPTION 'Cross dealer accepted'; END IF;
  UPDATE public.pdc_user_roles SET role=NULL,active=false,account_status='pending' WHERE id=viewer.id;
  PERFORM public.assign_broome_sales_access(viewer.id,person.id);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',viewer.auth_user_id,'email',viewer.email,'role','authenticated')::text,true);
  snap:=public.get_broome_sales_snapshot();
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(snap->'items') e WHERE e->>'tracking_id'=target_id::text) THEN RAISE EXCEPTION 'Own early order unavailable'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(snap->'items') e WHERE e->>'salesperson_code'<>'BG') THEN RAISE EXCEPTION 'Other salesperson exposed'; END IF;
  denied:=false;BEGIN PERFORM public.import_broome_sales_orders(payload,true);EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
  IF NOT denied THEN RAISE EXCEPTION 'Salesperson can import'; END IF;
  IF public.is_pdc_role('operator') OR public.is_pdc_role('viewer') THEN RAISE EXCEPTION 'Sales role gained PDC access'; END IF;
  IF has_function_privilege('anon','public.import_broome_sales_orders(jsonb,boolean)','EXECUTE') OR has_table_privilege('authenticated','pdc_sales_private.tracked_orders','SELECT') THEN RAISE EXCEPTION 'Unsafe intake grants'; END IF;
  RAISE EXCEPTION 'Roll back successful fixtures' USING errcode='ZX001';
 EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL;
 END;
 SELECT md5(jsonb_build_array((SELECT jsonb_agg(to_jsonb(v) ORDER BY id) FROM public.vehicles v),(SELECT jsonb_agg(to_jsonb(n) ORDER BY id) FROM public.navision_backend_records n),(SELECT jsonb_agg(to_jsonb(b) ORDER BY id) FROM public.workshop_bookings b))::text) INTO op_after;
 IF op_after<>op_before THEN RAISE EXCEPTION 'Rollback did not preserve operational rows'; END IF;
 IF registry_before<>(SELECT md5(coalesce(jsonb_agg(to_jsonb(o) ORDER BY id),'[]'::jsonb)::text) FROM pdc_sales_private.tracked_orders o) THEN RAISE EXCEPTION 'Rollback did not preserve registry'; END IF;
END $test$;
SELECT 'COSI, order continuity, retention, administrator-only import and PDC non-mutation checks passed; fixtures rolled back' AS verification;
ROLLBACK;
