-- Synthetic Sales lifecycle fixtures only. All inserts/updates roll back.
BEGIN ISOLATION LEVEL REPEATABLE READ;
DO $test$
DECLARE admin_id uuid:=gen_random_uuid(); user_id uuid:=gen_random_uuid(); role_id uuid; person_id uuid:=gen_random_uuid();
 other_person uuid:=gen_random_uuid(); old_id uuid:=gen_random_uuid(); current_id uuid:=gen_random_uuid();
 other_id uuid:=gen_random_uuid(); stockless_id uuid:=gen_random_uuid(); twin_id uuid:=gen_random_uuid();
 tracked_id uuid:=gen_random_uuid(); unsold_id uuid:=gen_random_uuid(); flag_id uuid:=gen_random_uuid();
 batch_id uuid; previous_id uuid; snap jsonb; item jsonb; denied boolean;
 before_hash text:=''; after_hash text:=''; t record; val text;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'Staging only'; END IF;
 SELECT id INTO batch_id FROM public.navision_import_batches WHERE source_system='microsoft_navision' AND dealer_code='37047'
 AND status='applied' AND rolled_back_at IS NULL ORDER BY result_revision DESC,applied_at DESC,id DESC LIMIT 1;
 SELECT id INTO previous_id FROM public.navision_import_batches WHERE source_system='microsoft_navision' AND dealer_code='37047'
 AND status='applied' AND rolled_back_at IS NULL AND id<>batch_id ORDER BY result_revision DESC,applied_at DESC,id DESC LIMIT 1;
 IF previous_id IS NULL THEN RAISE EXCEPTION 'Need two successful staging batches'; END IF;
 INSERT INTO auth.users(id,email) VALUES(admin_id,'sales-completed-admin@example.invalid'),(user_id,'sales-completed-own@example.invalid');
 UPDATE public.pdc_user_roles SET role='administrator',active=true,account_status='approved' WHERE email='sales-completed-admin@example.invalid';
 UPDATE public.pdc_user_roles SET role='salesperson',active=true,account_status='approved' WHERE email='sales-completed-own@example.invalid' RETURNING id INTO role_id;
 INSERT INTO public.salespeople(id,name,code,active) VALUES(person_id,'Completed fixture','CMPQA',true),(other_person,'Other completed fixture','CMPQB',true);
 INSERT INTO pdc_sales_private.account_scopes(user_role_id,salesperson_id,assigned_by) VALUES(role_id,person_id,admin_id);
 INSERT INTO public.navision_backend_records(id,source_record_id,row_hash,normalized_data,raw_evidence,first_seen_batch_id,last_seen_batch_id,source_system,dealer_code,record_status,is_current,missing_since_batch_id)
 VALUES
 (old_id,'SALES-CMP-OLD',repeat('0',64),'{"order":"SALES-CMP-OLD","batch":"CMP-OLD","cosi":true,"salesperson":"CMPQA","client":"Old fictional order"}','{}',previous_id,previous_id,'microsoft_navision','37047','not_in_latest_batch',false,batch_id),
 (current_id,'SALES-CMP-CURRENT',repeat('1',64),'{"order":"SALES-CMP-CURRENT","batch":"CMP-CURRENT","cosi":true,"salesperson":"CMPQA","navisionSubLocationDescription":"Delivered - At Dealer"}','{}',batch_id,batch_id,'microsoft_navision','37047','current',true,NULL),
 (other_id,'SALES-CMP-OTHER',repeat('2',64),'{"order":"SALES-CMP-OTHER","cosi":true,"salesperson":"CMPQB","client":"Other fictional order"}','{}',previous_id,previous_id,'microsoft_navision','37047','not_in_latest_batch',false,batch_id),
 (stockless_id,'SALES-CMP-STOCKLESS',repeat('3',64),'{"order":"SALES-CMP-STOCKLESS","batch":"","cosi":"Yes","salesperson":"CMPQA","client":"No batch fictional order"}','{}',previous_id,previous_id,'microsoft_navision','37047','not_in_latest_batch',false,batch_id),
 (twin_id,'SALES-CMP-TWIN',repeat('4',64),'{"order":"SALES-CMP-CURRENT","batch":"OLDER-STOCK","cosi":true,"salesperson":"CMPQA"}','{}',previous_id,previous_id,'microsoft_navision','37047','not_in_latest_batch',false,batch_id),
 (unsold_id,'SALES-CMP-UNSOLD',repeat('5',64),'{"order":"SALES-CMP-UNSOLD","cosi":"No","salesperson":"CMPQA"}','{}',previous_id,previous_id,'microsoft_navision','37047','not_in_latest_batch',false,batch_id),
 (flag_id,'SALES-CMP-FLAG',repeat('6',64),'{"order":"SALES-CMP-FLAG","cosi":true,"salesperson":"CMPQA"}','{}',previous_id,previous_id,'microsoft_navision','37047','current',true,NULL);
 INSERT INTO pdc_sales_private.tracked_orders(id,order_key,data,imported_at) VALUES(tracked_id,'SALES-CMP-OLD','{}',now());
 INSERT INTO pdc_sales_private.vehicle_notes(tracking_id,notes,custom_information,created_by,updated_by)
 VALUES(tracked_id,'Retained staff note','Retained custom information',admin_id,admin_id);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',user_id,'email','sales-completed-own@example.invalid','role','authenticated')::text,true);
 FOR t IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE c.relkind IN('r','p') AND (n.nspname='public' OR n.nspname='pdc_sales_private') ORDER BY 1,2 LOOP
  EXECUTE format('SELECT md5(count(*)::text||coalesce(string_agg(h,'''' ORDER BY h),'''')) FROM (SELECT md5(to_jsonb(x)::text) h FROM %I.%I x) z',t.nspname,t.relname) INTO val;
  before_hash:=before_hash||t.nspname||'.'||t.relname||':'||val||';';
 END LOOP;
 snap:=public.get_broome_completed_sales_vehicles();
 SELECT value INTO item FROM jsonb_array_elements(snap->'items') WHERE value->>'tracking_id'=tracked_id::text;
 IF item IS NULL OR item->>'notes'<>'Retained staff note' OR item->>'custom_information'<>'Retained custom information'
 OR item->>'source_current'<>'false' OR item->>'completion_reason'<>'absent_from_navision'
 OR item->>'customer_delivery_confirmed'<>'false' OR item->>'completed_at' IS NULL THEN RAISE EXCEPTION 'Missing archive identity, notes or omission evidence'; END IF;
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(snap->'items') WHERE value->>'tracking_id'=stockless_id::text AND value->>'order'='SALES-CMP-STOCKLESS' AND value->>'stock'='') THEN RAISE EXCEPTION 'Stockless Toyota order absent'; END IF;
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(snap->'items') WHERE value->>'tracking_id'=flag_id::text) THEN RAISE EXCEPTION 'Stale global current flag resurrected old vehicle'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(snap->'items') WHERE value->>'tracking_id' IN(other_id::text,current_id::text,twin_id::text,unsold_id::text)) THEN RAISE EXCEPTION 'Cross-scope, current, duplicate order or unsold archived'; END IF;
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') WHERE value->>'tracking_id'=current_id::text) THEN RAISE EXCEPTION 'Dealer delivery removed current upload order'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') WHERE value->>'tracking_id' IN(old_id::text,tracked_id::text,stockless_id::text,flag_id::text)) THEN RAISE EXCEPTION 'Old order on active board'; END IF;
 FOR t IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE c.relkind IN('r','p') AND (n.nspname='public' OR n.nspname='pdc_sales_private') ORDER BY 1,2 LOOP
  EXECUTE format('SELECT md5(count(*)::text||coalesce(string_agg(h,'''' ORDER BY h),'''')) FROM (SELECT md5(to_jsonb(x)::text) h FROM %I.%I x) z',t.nspname,t.relname) INTO val;
  after_hash:=after_hash||t.nspname||'.'||t.relname||':'||val||';';
 END LOOP;
 IF before_hash<>after_hash THEN RAISE EXCEPTION 'Read-only archive changed existing records'; END IF;
 -- Return to a later upload: automatically leaves Completed, keeps notes and identity.
 UPDATE public.navision_backend_records SET last_seen_batch_id=batch_id,is_current=true,record_status='current',missing_since_batch_id=NULL WHERE id=old_id;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_completed_sales_vehicles()->'items') WHERE value->>'tracking_id'=tracked_id::text) THEN RAISE EXCEPTION 'Reappearing order stayed completed'; END IF;
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') WHERE value->>'tracking_id'=tracked_id::text) THEN RAISE EXCEPTION 'Reappearing order missing from active'; END IF;
 -- Hidden current vehicle must not turn into a completed record.
 PERFORM public.set_broome_sales_vehicle_visibility(current_id,true,0);
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_completed_sales_vehicles()->'items') WHERE value->>'tracking_id' IN(current_id::text,twin_id::text)) THEN RAISE EXCEPTION 'Hidden order archived'; END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'email','sales-completed-admin@example.invalid','role','authenticated')::text,true);
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_completed_sales_vehicles()->'items') WHERE value->>'tracking_id'=other_id::text) THEN RAISE EXCEPTION 'Admin cannot see completed fleet'; END IF;
 UPDATE public.pdc_user_roles SET active=false,account_status='disabled' WHERE id=role_id;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',user_id,'email','sales-completed-own@example.invalid','role','authenticated')::text,true);
 denied:=false;BEGIN PERFORM public.get_broome_completed_sales_vehicles();EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 IF NOT denied THEN RAISE EXCEPTION 'Disabled access accepted'; END IF;
 PERFORM set_config('request.jwt.claims','{}',true);
 denied:=false;BEGIN PERFORM public.get_broome_completed_sales_vehicles();EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 IF NOT denied OR has_function_privilege('anon','public.get_broome_completed_sales_vehicles()','EXECUTE') THEN RAISE EXCEPTION 'Anonymous archive access'; END IF;
END $test$;
SELECT 'Completed omission, stale flags, stocked/stockless references, notes retention, reappearance, hidden/current/unsold exclusion, approved scope and full PDC/Sales nonmutation passed; fixtures rolled back' AS verification;
ROLLBACK;
