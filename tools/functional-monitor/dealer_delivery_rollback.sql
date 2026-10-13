-- Disposable LOCAL COPY only. The runner validates its connection before this
-- scenario. A generated synthetic order replaces the retired historical stock.
BEGIN;
SET LOCAL statement_timeout='30s';
DO $test$
DECLARE actor uuid; email text; v uuid:=gen_random_uuid(); backend uuid:=gen_random_uuid();
 batch uuid; data jsonb; result jsonb;
BEGIN
 IF inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet THEN RAISE EXCEPTION 'Local copy required';END IF;
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'Staging backup required';END IF;
 SELECT auth_user_id,u.email INTO STRICT actor,email FROM public.pdc_user_roles u
 WHERE u.active AND u.account_status='approved' AND u.role::text='administrator'
 AND u.auth_user_id IS NOT NULL ORDER BY u.id LIMIT 1;
 SELECT id INTO STRICT batch FROM public.navision_import_batches WHERE dealer_code='37047' AND status='applied' ORDER BY id LIMIT 1;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor,'email',email,'role','authenticated')::text,true);
 INSERT INTO public.vehicles(id,permanent_vehicle_id,stock_number,customer_name,
 vehicle_description,current_location,visible_on_board,source_system,source_record_id,source_batch_id,created_by,updated_by)
 VALUES(v,'functional-delivery-'||v,'TEST-DELIVERY','TEST VEHICLE','TEST VEHICLE delivery scenario',
 'PMB',true,'functional_monitor_isolated',v::text,'37047',actor,actor);
 data:=jsonb_build_object('batch','TEST-DELIVERY','order','TEST-ORDER-'||v,
  'stockNumber','TEST-DELIVERY','toyotaOrderNumber','TEST-ORDER-'||v,
  'toyotaStatus','Delivered - At Dealer','navisionSubLocationDescription','Delivered - At Dealer',
  'dealerCode','37047','customerName','TEST VEHICLE');
 INSERT INTO public.navision_backend_records(id,source_record_id,row_hash,normalized_data,raw_evidence,
 first_seen_batch_id,last_seen_batch_id,source_system,dealer_code,record_status,is_current,canonical_vehicle_id)
 VALUES(backend,'TEST-DELIVERY-'||v,repeat('d',64),data,data,batch,batch,'microsoft_navision','37047','current',true,v);
 result:=public.reconcile_navision_delivery_734(backend,NULL,NULL);
 IF result->>'ok' IS DISTINCT FROM 'true' OR NOT EXISTS(SELECT 1 FROM public.vehicles
 WHERE id=v AND lifecycle_state='completed' AND current_location='Completed' AND NOT visible_on_board
 AND active_workshop_booking_id IS NULL) THEN RAISE EXCEPTION 'Synthetic dealer completion failed';END IF;
END $test$;
ROLLBACK;
SELECT 'PASS: TEST VEHICLE dealer completion in isolated copy; all changes rolled back' AS result;
