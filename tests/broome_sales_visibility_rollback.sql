-- Synthetic fixture only. Everything rolls back, including auth accounts and source rows.
BEGIN ISOLATION LEVEL REPEATABLE READ;
DO $test$
DECLARE a uuid:=gen_random_uuid(); u uuid:=gen_random_uuid(); other_u uuid:=gen_random_uuid();
 role_id uuid:=gen_random_uuid(); person uuid:=gen_random_uuid(); other_person uuid:=gen_random_uuid();
 own_id uuid:=gen_random_uuid(); other_id uuid:=gen_random_uuid(); tracked_id uuid:=gen_random_uuid(); replaced_id uuid:=gen_random_uuid();
 batch uuid; snap jsonb; result jsonb; denied boolean; before_hash text:=''; after_hash text:=''; t record; val text;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'Staging only'; END IF;
 INSERT INTO auth.users(id,email) VALUES(a,'sales-hide-admin@example.invalid'),(u,'sales-hide-person@example.invalid'),(other_u,'sales-hide-other@example.invalid');
 UPDATE public.pdc_user_roles SET role='administrator',active=true,account_status='approved' WHERE email='sales-hide-admin@example.invalid';
 UPDATE public.pdc_user_roles SET role='salesperson',active=true,account_status='approved' WHERE email='sales-hide-person@example.invalid' RETURNING id INTO role_id;
 INSERT INTO public.salespeople(id,name,code,active) VALUES(person,'Visibility fixture','HIDEQA',true),(other_person,'Other visibility fixture','HIDEQB',true);
 INSERT INTO pdc_sales_private.account_scopes(user_role_id,salesperson_id,assigned_by) VALUES(role_id,person,a);
 SELECT id INTO batch FROM public.navision_import_batches ORDER BY id LIMIT 1;
 IF batch IS NULL THEN RAISE EXCEPTION 'Need existing staging batch reference'; END IF;
 INSERT INTO public.navision_backend_records(id,source_record_id,row_hash,normalized_data,raw_evidence,first_seen_batch_id,last_seen_batch_id,source_system,dealer_code,record_status)
 VALUES
 (own_id,'SALES-HIDE-QA-OWN',repeat('0',64),'{"order":"SALES-HIDE-QA-OWN","cosi":true,"salesperson":"HIDEQA","client":"Fictional current customer","batch":""}','{}',batch,batch,'microsoft_navision','37047','current'),
 (other_id,'SALES-HIDE-QA-OTHER',repeat('1',64),'{"order":"SALES-HIDE-QA-OTHER","cosi":true,"salesperson":"HIDEQB","client":"Other fictional customer","batch":""}','{}',batch,batch,'microsoft_navision','37047','current');
 INSERT INTO pdc_sales_private.tracked_orders(id,order_key,data,imported_at) VALUES(tracked_id,'SALES-HIDE-QA-OWN','{"order":"SALES-HIDE-QA-OWN","cosi":true,"salesperson":"HIDEQA","client":"STALE PRIVATE CUSTOMER","navisionKewdaleEta":"2099-01-01"}',now()+interval '1 day');
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u,'email','sales-hide-person@example.invalid','role','authenticated')::text,true);
 snap:=public.get_broome_sales_snapshot();
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(snap->'items') e WHERE e->>'tracking_id'=tracked_id::text AND e->>'client'='Fictional current customer' AND e->>'stock'='') THEN RAISE EXCEPTION 'Backend facts/stable tracked identity/stockless COSI failed'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(snap->'items') e WHERE e->>'tracking_id'=other_id::text) THEN RAISE EXCEPTION 'Cross salesperson read'; END IF;
 FOR t IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE c.relkind IN('r','p') AND (n.nspname='public' OR (n.nspname='pdc_sales_private' AND c.relname<>'vehicle_visibility')) ORDER BY 1,2 LOOP
  EXECUTE format('SELECT md5(count(*)::text||coalesce(string_agg(h,'''' ORDER BY h),'''')) FROM (SELECT md5(to_jsonb(x)::text) h FROM %I.%I x) z',t.nspname,t.relname) INTO val;
  before_hash:=before_hash||t.nspname||'.'||t.relname||':'||val||';';
 END LOOP;
 result:=public.set_broome_sales_vehicle_visibility(tracked_id,true,0);
 IF result->>'sales_hidden'<>'true' OR result->>'sales_visibility_version'<>'1' THEN RAISE EXCEPTION 'Hide response'; END IF;
 snap:=public.get_broome_sales_snapshot();
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(snap->'items') e WHERE e->>'tracking_id'=tracked_id::text) THEN RAISE EXCEPTION 'Hidden active vehicle'; END IF;
 snap:=public.get_broome_hidden_sales_vehicles();
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(snap->'items') e WHERE e->>'tracking_id'=tracked_id::text AND e->>'sales_visibility_version'='1') THEN RAISE EXCEPTION 'Restore list missing'; END IF;
 denied:=false;BEGIN PERFORM public.set_broome_sales_vehicle_visibility(tracked_id,false,0);EXCEPTION WHEN serialization_failure THEN denied:=true;END;
 IF NOT denied THEN RAISE EXCEPTION 'Stale save accepted'; END IF;
 denied:=false;BEGIN PERFORM public.set_broome_sales_vehicle_visibility(other_id,true,0);EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 IF NOT denied THEN RAISE EXCEPTION 'Cross salesperson write accepted'; END IF;
 result:=public.set_broome_sales_vehicle_visibility(tracked_id,false,1);
 IF result->>'sales_visibility_version'<>'2' THEN RAISE EXCEPTION 'Restore version'; END IF;
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') e WHERE e->>'tracking_id'=tracked_id::text) THEN RAISE EXCEPTION 'Restore not visible'; END IF;
 result:=public.set_broome_sales_vehicle_visibility(tracked_id,true,2);
 FOR t IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE c.relkind IN('r','p') AND (n.nspname='public' OR (n.nspname='pdc_sales_private' AND c.relname<>'vehicle_visibility')) ORDER BY 1,2 LOOP
  EXECUTE format('SELECT md5(count(*)::text||coalesce(string_agg(h,'''' ORDER BY h),'''')) FROM (SELECT md5(to_jsonb(x)::text) h FROM %I.%I x) z',t.nspname,t.relname) INTO val;
  after_hash:=after_hash||t.nspname||'.'||t.relname||':'||val||';';
 END LOOP;
 IF before_hash<>after_hash THEN RAISE EXCEPTION 'Hide/restore changed PDC, backend, finance, ordering or another table'; END IF;
 -- Later stock allocation retains hidden state and uses backend facts.
 UPDATE public.navision_backend_records SET normalized_data=normalized_data||'{"batch":"SALES-HIDE-QA-STOCK","navisionKewdaleEta":"2026-12-01"}',updated_at=clock_timestamp() WHERE id=own_id;
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_hidden_sales_vehicles()->'items') e WHERE e->>'tracking_id'=tracked_id::text AND e->>'stock'='SALES-HIDE-QA-STOCK' AND e->>'kewdale_eta'='2026-12-01') THEN RAISE EXCEPTION 'Reimport lost hide or backend details'; END IF;
 -- Only a successfully applied snapshot marks an omitted record non-current.
 UPDATE public.navision_backend_records SET is_current=false,record_status='not_in_latest_batch',missing_since_batch_id=batch WHERE id=own_id;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_hidden_sales_vehicles()->'items') e WHERE e->>'tracking_id'=tracked_id::text) OR
 EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_sales_snapshot()->'items') e WHERE e->>'tracking_id'=tracked_id::text) THEN RAISE EXCEPTION 'Private fallback resurrected missing vehicle'; END IF;
 denied:=false;BEGIN PERFORM public.set_broome_sales_vehicle_visibility(tracked_id,false,3);EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 IF NOT denied THEN RAISE EXCEPTION 'Missing order writable'; END IF;
 -- A replacement backend UUID with the same exact dealer/order retains shared hide.
 DELETE FROM pdc_sales_private.tracked_orders WHERE id=tracked_id;
 INSERT INTO public.navision_backend_records(id,source_record_id,row_hash,normalized_data,raw_evidence,first_seen_batch_id,last_seen_batch_id,source_system,dealer_code,record_status)
 VALUES(replaced_id,'SALES-HIDE-QA-REPLACED',repeat('2',64),'{"order":"SALES-HIDE-QA-OWN","cosi":true,"salesperson":"HIDEQA","client":"Fictional replacement","batch":""}','{}',batch,batch,'microsoft_navision','37047','current');
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_hidden_sales_vehicles()->'items') e WHERE e->>'tracking_id'=replaced_id::text AND e->>'sales_visibility_version'='3') THEN RAISE EXCEPTION 'Exact order replacement lost hide'; END IF;
 result:=public.set_broome_sales_vehicle_visibility(replaced_id,false,3);
 IF result->>'sales_visibility_version'<>'4' OR (SELECT count(*) FROM pdc_sales_private.vehicle_visibility WHERE order_key='SALES-HIDE-QA-OWN')<>1 THEN RAISE EXCEPTION 'Restore replacement created duplicate preference'; END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',a,'email','sales-hide-admin@example.invalid','role','authenticated')::text,true);
 result:=public.set_broome_sales_vehicle_visibility(other_id,true,0);
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.get_broome_hidden_sales_vehicles()->'items') e WHERE e->>'tracking_id'=other_id::text) THEN RAISE EXCEPTION 'Administrator cannot manage hidden fleet'; END IF;
 UPDATE public.pdc_user_roles SET active=false,account_status='disabled' WHERE id=role_id;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u,'email','sales-hide-person@example.invalid','role','authenticated')::text,true);
 denied:=false;BEGIN PERFORM public.get_broome_hidden_sales_vehicles();EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 IF NOT denied THEN RAISE EXCEPTION 'Disabled account read'; END IF;
 PERFORM set_config('request.jwt.claims','{}',true);
 denied:=false;BEGIN PERFORM public.set_broome_sales_vehicle_visibility(replaced_id,true,4);EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 IF NOT denied THEN RAISE EXCEPTION 'Anonymous write'; END IF;
 IF has_table_privilege('authenticated','pdc_sales_private.vehicle_visibility','SELECT') OR
 has_table_privilege('authenticated','pdc_sales_private.vehicle_visibility','UPDATE') OR
 has_function_privilege('anon','public.get_broome_hidden_sales_vehicles()','EXECUTE') OR
 has_function_privilege('anon','public.set_broome_sales_vehicle_visibility(uuid,boolean,integer)','EXECUTE') OR
 has_function_privilege('authenticated','pdc_sales_private.visibility_source_snapshot(boolean)','EXECUTE') OR
 NOT (SELECT relrowsecurity FROM pg_class WHERE oid='pdc_sales_private.vehicle_visibility'::regclass) THEN RAISE EXCEPTION 'Unsafe visibility permissions'; END IF;
END $test$;
SELECT 'Sales hide/restore, stockless COSI, stable identity/reimports, missing source removal, scoped access, concurrency and every public/private non-visibility table unchanged; synthetic fixtures rolled back' AS verification;
ROLLBACK;
