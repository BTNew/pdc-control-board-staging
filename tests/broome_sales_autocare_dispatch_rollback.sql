-- Fictional vehicles/accounts only. Dispatch, source-status changes and all fixtures roll back.
BEGIN;
DO $test$
DECLARE user_id uuid:=gen_random_uuid(); admin_id uuid:=gen_random_uuid(); person_id uuid:=gen_random_uuid(); role_id uuid;
 a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); foreign_id uuid:=gen_random_uuid(); batch uuid;
 response jsonb; item jsonb; denied boolean; before_hash text; after_hash text; duplicate_version integer;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'Staging only'; END IF;
 SELECT id INTO batch FROM public.navision_import_batches WHERE dealer_code='37047' AND source_system='microsoft_navision'
 AND status='applied' AND rolled_back_at IS NULL ORDER BY result_revision DESC,applied_at DESC,id DESC LIMIT 1;
 INSERT INTO auth.users(id,email) VALUES(user_id,'autocare-fixture@example.invalid'),(admin_id,'autocare-admin@example.invalid');
 UPDATE public.pdc_user_roles SET active=true,account_status='approved',role='salesperson' WHERE email='autocare-fixture@example.invalid' RETURNING id INTO role_id;
 UPDATE public.pdc_user_roles SET active=true,account_status='approved',role='administrator' WHERE email='autocare-admin@example.invalid';
 INSERT INTO public.salespeople(id,name,code,active) VALUES(person_id,'Autocare fixture','ACQA',true);
 INSERT INTO pdc_sales_private.account_scopes(user_role_id,salesperson_id,assigned_by) VALUES(role_id,person_id,admin_id);
 INSERT INTO public.navision_backend_records(id,source_record_id,row_hash,normalized_data,raw_evidence,first_seen_batch_id,last_seen_batch_id,source_system,dealer_code,record_status,is_current)
 VALUES(a,'AC-QA-A',repeat('a',64),'{"order":"AC-QA-A","batch":"AC-A","cosi":true,"salesperson":"ACQA","navisionTransportLoadNo":"001234","navisionSubLocationDescription":"Despatched - From TWA"}','{}',batch,batch,'microsoft_navision','37047','current',true),
 (b,'AC-QA-B',repeat('b',64),'{"order":"AC-QA-B","batch":"AC-B","cosi":true,"salesperson":"ACQA","navisionTransportLoadNo":"001234"}','{}',batch,batch,'microsoft_navision','37047','current',true),
 (foreign_id,'AC-QA-FOREIGN',repeat('c',64),'{"order":"AC-QA-FOREIGN","cosi":true,"salesperson":"BG"}','{}',batch,batch,'microsoft_navision','37047','current',true);
 SELECT md5(coalesce((SELECT string_agg(md5(to_jsonb(v)::text),'' ORDER BY id) FROM public.vehicles v),'')||
 coalesce((SELECT string_agg(md5(to_jsonb(w)::text),'' ORDER BY id) FROM public.workshop_bookings w),'')||
 coalesce((SELECT string_agg(md5(to_jsonb(f)::text),'' ORDER BY id) FROM pdc_sales_private.finance_applications f),'')||
 coalesce((SELECT string_agg(md5(to_jsonb(e)::text),'' ORDER BY id) FROM pdc_sales_private.customer_email_drafts e),'')) INTO before_hash;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',user_id,'email','autocare-fixture@example.invalid','role','authenticated')::text,true);
 SELECT e INTO item FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') e WHERE e->>'tracking_id'=a::text;
 IF item->>'transport_number'<>'001234' OR item->>'autocare_dispatch_version'<>'0' THEN RAISE EXCEPTION 'Transport source or default state missing'; END IF;
 -- Every selected vehicle must pass access checks; there is no partial batch update.
 denied:=false;BEGIN PERFORM public.set_broome_sales_autocare_dispatch(jsonb_build_array(jsonb_build_object('tracking_id',a,'expected_version',0),jsonb_build_object('tracking_id',foreign_id,'expected_version',0)),true);EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 IF NOT denied OR EXISTS(SELECT 1 FROM pdc_sales_private.autocare_dispatches WHERE order_key='AC-QA-A') THEN RAISE EXCEPTION 'Cross-scope batch partially saved'; END IF;
 response:=public.set_broome_sales_autocare_dispatch(jsonb_build_array(jsonb_build_object('tracking_id',a,'expected_version',0),jsonb_build_object('tracking_id',b,'expected_version',0)),true);
 IF jsonb_array_length(response->'items')<>2 THEN RAISE EXCEPTION 'Batch dispatch did not save both'; END IF;
 response:=public.set_broome_sales_autocare_dispatch(jsonb_build_array(jsonb_build_object('tracking_id',a,'expected_version',0)),true);
 IF response->'items'->0->>'autocare_dispatch_version'<>'1' OR (SELECT count(*) FROM pdc_sales_private.crm_audit WHERE record_id=a AND kind='autocare_dispatch')<>1 THEN RAISE EXCEPTION 'Lost-response retry duplicated audit'; END IF;
 SELECT e INTO item FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') e WHERE e->>'tracking_id'=a::text;
 IF item->>'autocare_dispatched'<>'true' OR item->>'toyota_status'<>'Despatched - From TWA' THEN RAISE EXCEPTION 'Manual dispatch missing or overwrote Toyota status'; END IF;
 response:=public.set_broome_sales_autocare_dispatch(jsonb_build_array(jsonb_build_object('tracking_id',a,'expected_version',1)),false);
 denied:=false;BEGIN PERFORM public.set_broome_sales_autocare_dispatch(jsonb_build_array(jsonb_build_object('tracking_id',a,'expected_version',0)),true);EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 IF NOT denied THEN RAISE EXCEPTION 'Stale edit overwrote dispatch'; END IF;
 response:=public.set_broome_sales_autocare_dispatch(jsonb_build_array(jsonb_build_object('tracking_id',a,'expected_version',2)),true);
 UPDATE public.navision_backend_records SET normalized_data=jsonb_set(normalized_data,'{navisionSubLocationDescription}','"Delivered - At Dealer"') WHERE id=a;
 SELECT e INTO item FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') e WHERE e->>'tracking_id'=a::text;
 IF item->>'autocare_dispatched'<>'false' OR item->>'toyota_status'<>'Delivered - At Dealer' THEN RAISE EXCEPTION 'Dealer delivery did not override dispatch'; END IF;
 denied:=false;BEGIN PERFORM public.set_broome_sales_autocare_dispatch(jsonb_build_array(jsonb_build_object('tracking_id',a,'expected_version',3)),true);EXCEPTION WHEN raise_exception THEN denied:=true;END;
 IF NOT denied THEN RAISE EXCEPTION 'Dealer vehicle accepted dispatch'; END IF;
 PERFORM public.set_broome_sales_vehicle_visibility(b,true,0);
 denied:=false;BEGIN PERFORM public.set_broome_sales_autocare_dispatch(jsonb_build_array(jsonb_build_object('tracking_id',b,'expected_version',1)),false);EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 IF NOT denied THEN RAISE EXCEPTION 'Hidden vehicle accepted dispatch'; END IF;
 UPDATE public.navision_backend_records SET is_current=false,record_status='not_in_latest_batch',missing_since_batch_id=batch WHERE id=b;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') e WHERE e->>'tracking_id'=b::text) THEN RAISE EXCEPTION 'Missing-source order resurrected by dispatch'; END IF;
 UPDATE public.pdc_user_roles SET active=false,account_status='disabled' WHERE id=role_id;
 denied:=false;BEGIN PERFORM public.set_broome_sales_autocare_dispatch(jsonb_build_array(jsonb_build_object('tracking_id',a,'expected_version',3)),false);EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 IF NOT denied THEN RAISE EXCEPTION 'Disabled user accepted'; END IF;
 PERFORM set_config('request.jwt.claims','{}',true);
 denied:=false;BEGIN PERFORM public.get_broome_sales_snapshot();EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 IF NOT denied OR has_function_privilege('anon','public.set_broome_sales_autocare_dispatch(jsonb,boolean)','EXECUTE')
 OR has_table_privilege('authenticated','pdc_sales_private.autocare_dispatches','SELECT') THEN RAISE EXCEPTION 'Public/private access boundary failure'; END IF;
 SELECT md5(coalesce((SELECT string_agg(md5(to_jsonb(v)::text),'' ORDER BY id) FROM public.vehicles v),'')||
 coalesce((SELECT string_agg(md5(to_jsonb(w)::text),'' ORDER BY id) FROM public.workshop_bookings w),'')||
 coalesce((SELECT string_agg(md5(to_jsonb(f)::text),'' ORDER BY id) FROM pdc_sales_private.finance_applications f),'')||
 coalesce((SELECT string_agg(md5(to_jsonb(e)::text),'' ORDER BY id) FROM pdc_sales_private.customer_email_drafts e),'')) INTO after_hash;
 IF before_hash<>after_hash THEN RAISE EXCEPTION 'Dispatch changed operational, Finance or email records'; END IF;
END $test$;
SELECT 'Autocare batch, exact transport, retries, stale versions, dealer precedence, current/hidden/salesperson/disabled/anonymous access and PDC/Finance/email nonmutation passed; all fixtures rolled back' verification;
ROLLBACK;
