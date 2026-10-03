-- Synthetic staging-only fixtures. Root rehearses after candidate definitions.
-- Repeatable-read protects full-row fingerprints from concurrent background work.
-- For connector deadlines, run core, identity and visibility independently by
-- SET LOCAL app.sales_builds_test_part='<part>' immediately after BEGIN.
-- Each part creates and rolls back its own synthetic setup; 'all' is optional
-- for a runner without the connector's 120-second deadline.
BEGIN ISOLATION LEVEL REPEATABLE READ;
CREATE FUNCTION pg_temp.builds_fingerprint(p_exclude_builds boolean)
RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE t record; h text; combined text:='';
BEGIN
 FOR t IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE c.relkind IN ('r','p') AND (
  n.nspname='pdc_sales_private'
  OR (n.nspname='auth' AND c.relname='users')
  OR (n.nspname='public' AND c.relname IN ('vehicles','navision_backend_records','workshop_bookings','vehicle_parts_updates','navision_import_batches','pdc_user_roles','salespeople'))
 )
 AND NOT(p_exclude_builds AND n.nspname='pdc_sales_private' AND c.relname IN ('sales_build_orders','sales_build_import_batches')) ORDER BY 1,2 LOOP
  EXECUTE format('SELECT md5(count(*)::text||'':''||coalesce(string_agg(h,'''' ORDER BY h),'''')) FROM (SELECT md5(to_jsonb(x)::text) h FROM %I.%I x) rows',t.nspname,t.relname) INTO h;
  combined:=combined||t.nspname||'.'||t.relname||':'||h||';';
 END LOOP;
 RETURN md5(combined);
END $fn$;
DO $test$
DECLARE admin_id uuid:=gen_random_uuid(); own_user uuid:=gen_random_uuid(); other_user uuid:=gen_random_uuid(); pending_user uuid:=gen_random_uuid();
 admin_email text; own_email text; other_email text; pending_email text;
 own_role uuid; other_role uuid; bg_person uuid; pm_person uuid; extra_person uuid:=gen_random_uuid();
 source_own uuid:=gen_random_uuid(); source_other uuid:=gen_random_uuid(); source_extra uuid:=gen_random_uuid();
 source_duplicate uuid:=gen_random_uuid(); source_conflict uuid:=gen_random_uuid(); source_conflict2 uuid:=gen_random_uuid(); source_missing uuid:=gen_random_uuid(); source_replacement uuid:=gen_random_uuid();
 own_order text; other_order text; conflict_order text; own_stock text:='009983001'; other_stock text:='9983002'; duplicate_stock text:='99883004';
 latest_batch uuid; snap jsonb; own_item jsonb; other_item jsonb; row_own jsonb; row_other jsonb; unmatched jsonb; payload jsonb; result jsonb; displayed jsonb;
protected_before text; function_before text; imports_before integer; order_version integer; denied boolean; bad jsonb;
 file_one text:=repeat('a',64); file_two text:=repeat('b',64); t record;
 test_part text:=coalesce(nullif(current_setting('app.sales_builds_test_part',true),''),'all');
 getter_started timestamptz; getter_elapsed_ms numeric;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'Staging only'; END IF;
 IF test_part NOT IN ('core','identity','visibility','all') THEN RAISE EXCEPTION 'Unknown build test part'; END IF;
 -- Full protected hashes immediately before/after new RPC operations prove the
 -- isolation requirement. Rehashing the unchanged large import evidence twice
 -- again for subtransaction rollback would exceed the connector time limit.
 SELECT md5(coalesce(jsonb_agg(jsonb_build_array(p.oid,pg_get_functiondef(p.oid),p.proacl) ORDER BY p.oid),'[]'::jsonb)::text) INTO function_before
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('public','pdc_sales_private') AND p.prokind='f';
 IF has_function_privilege('anon','public.get_broome_sales_builds()','EXECUTE') OR has_function_privilege('anon','public.import_broome_sales_builds(text,text,jsonb)','EXECUTE')
 OR has_function_privilege('service_role','public.import_broome_sales_builds(text,text,jsonb)','EXECUTE')
 OR has_function_privilege('authenticated','pdc_sales_private.build_stock_match_count(text)','EXECUTE')
 OR has_function_privilege('authenticated','pdc_sales_private.build_stock_counts()','EXECUTE')
 OR has_function_privilege('authenticated','pdc_sales_private.build_payload(jsonb)','EXECUTE') THEN RAISE EXCEPTION 'Unsafe build function grants'; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname IN ('get_broome_sales_builds','import_broome_sales_builds') AND p.prosecdef) THEN RAISE EXCEPTION 'Public build wrapper must be invoker'; END IF;
 FOR t IN SELECT c.relname,c.relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='pdc_sales_private' AND c.relname IN ('sales_build_orders','sales_build_import_batches') LOOP
  IF NOT t.relrowsecurity OR has_table_privilege('authenticated','pdc_sales_private.'||t.relname,'SELECT,INSERT,UPDATE,DELETE') OR has_table_privilege('anon','pdc_sales_private.'||t.relname,'SELECT,INSERT,UPDATE,DELETE') THEN RAISE EXCEPTION 'Unsafe build table: %',t.relname; END IF;
 END LOOP;
 BEGIN
  admin_email:='build-admin-'||left(admin_id::text,8)||'@example.invalid'; own_email:='build-person-'||left(own_user::text,8)||'@example.invalid';
  other_email:='build-other-'||left(other_user::text,8)||'@example.invalid'; pending_email:='build-pending-'||left(pending_user::text,8)||'@example.invalid';
  own_order:='000-BUILD-QA-'||replace(source_own::text,'-',''); other_order:='BUILD-OTHER-QA-'||replace(source_other::text,'-',''); conflict_order:='BUILD-CONFLICT-QA-'||replace(source_conflict::text,'-','');
  SELECT id INTO bg_person FROM public.salespeople WHERE active AND code='BG'; SELECT id INTO pm_person FROM public.salespeople WHERE active AND code='PM';
  IF bg_person IS NULL OR pm_person IS NULL THEN RAISE EXCEPTION 'Need active existing Broome roster'; END IF;
  INSERT INTO auth.users(id,email) VALUES(admin_id,admin_email),(own_user,own_email),(other_user,other_email),(pending_user,pending_email);
  UPDATE public.pdc_user_roles SET role='administrator',active=true,account_status='approved' WHERE email=admin_email;
  UPDATE public.pdc_user_roles SET role='salesperson',active=true,account_status='approved' WHERE email=own_email RETURNING id INTO own_role;
  UPDATE public.pdc_user_roles SET role='salesperson',active=true,account_status='approved' WHERE email=other_email RETURNING id INTO other_role;
  IF own_role IS NULL OR other_role IS NULL THEN RAISE EXCEPTION 'Registration trigger did not create fixture roles'; END IF;
  INSERT INTO pdc_sales_private.account_scopes(user_role_id,salesperson_id,assigned_by) VALUES(own_role,bg_person,admin_id),(other_role,pm_person,admin_id);
  INSERT INTO public.salespeople(id,name,code,active) VALUES(extra_person,'Fictional build outside roster','BUILDQAEXTRA',true);
  SELECT id INTO latest_batch FROM public.navision_import_batches WHERE source_system='microsoft_navision' AND dealer_code='37047' AND status='applied' AND rolled_back_at IS NULL ORDER BY result_revision DESC,applied_at DESC,id DESC LIMIT 1;
  IF latest_batch IS NULL THEN RAISE EXCEPTION 'Need latest successful staging Broome source reference'; END IF;
  IF EXISTS(SELECT 1 FROM public.navision_backend_records WHERE dealer_code='37047' AND is_current AND normalized_data->>'batch' IN (own_stock,other_stock,duplicate_stock,'99883005','99883006')) THEN RAISE EXCEPTION 'Synthetic stock collision; choose different fictional test stocks'; END IF;
  INSERT INTO public.navision_backend_records(id,source_system,dealer_code,source_record_id,row_hash,normalized_data,raw_evidence,first_seen_batch_id,last_seen_batch_id,record_status,is_current)
  VALUES
   (source_own,'microsoft_navision','37047',own_order,repeat('1',64),jsonb_build_object('order',own_order,'batch',own_stock,'cosi',true,'salesperson','BG','client','Fictional build customer'),'{}',latest_batch,latest_batch,'current',true),
   (source_other,'microsoft_navision','37047',other_order,repeat('2',64),jsonb_build_object('order',other_order,'batch',other_stock,'cosi',true,'salesperson','PM','client','Other fictional build customer'),'{}',latest_batch,latest_batch,'current',true),
   (source_extra,'microsoft_navision','37047','BUILD-EXTRA-'||source_extra::text,repeat('3',64),jsonb_build_object('order','BUILD-EXTRA-'||source_extra::text,'batch',duplicate_stock,'cosi',true,'salesperson','BUILDQAEXTRA'),'{}',latest_batch,latest_batch,'current',true),
   (source_duplicate,'microsoft_navision','37047','BUILD-DUP-'||source_duplicate::text,repeat('4',64),jsonb_build_object('order','BUILD-DUP-'||source_duplicate::text,'batch',duplicate_stock,'cosi',true,'salesperson','BG'),'{}',latest_batch,latest_batch,'current',true),
   (source_conflict,'microsoft_navision','37047',conflict_order,repeat('5',64),jsonb_build_object('order',conflict_order,'batch','99883005','cosi',true,'salesperson','BG'),'{}',latest_batch,latest_batch,'current',true),
   (source_conflict2,'microsoft_navision','37047',conflict_order||'-SECOND-RECORD',repeat('6',64),jsonb_build_object('order',conflict_order,'batch','99883006','cosi',true,'salesperson','BG'),'{}',latest_batch,latest_batch,'current',true),
   (source_missing,'microsoft_navision','37047','BUILD-MISSING-'||source_missing::text,repeat('7',64),jsonb_build_object('order','','batch','99883007','cosi',true,'salesperson','BG'),'{}',latest_batch,latest_batch,'current',true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'email',admin_email,'role','authenticated')::text,true);
  snap:=pdc_sales_private.visibility_source_snapshot(false);
  SELECT e INTO own_item FROM jsonb_array_elements(snap->'items') e WHERE e->>'navision_record_id'=source_own::text;
  SELECT e INTO other_item FROM jsonb_array_elements(snap->'items') e WHERE e->>'navision_record_id'=source_other::text;
  IF own_item IS NULL OR other_item IS NULL THEN RAISE EXCEPTION 'Current source fixtures not visible'; END IF;
  row_own:=jsonb_build_object('stock',own_stock,'dealer_code','037047','expected_tracking_id',own_item->>'tracking_id','expected_navision_record_id',own_item->>'navision_record_id','expected_order',own_item->>'order','expected_navision_updated_at',own_item->>'navision_updated_at',
   'items',jsonb_build_array(jsonb_build_object('description','Example canopy at body builder','source_rows',jsonb_build_array(5,6),'quote_number','QUOTE-EXAMPLE')),
   'notes',jsonb_build_array(jsonb_build_object('text',E'Example build note\nPreserve this second line','source_rows',jsonb_build_array(5))),
   'other_lines',jsonb_build_array(jsonb_build_object('description','Example transport line','reason','Transport quote item','source_rows',jsonb_build_array(7))), 'source_rows',jsonb_build_array(5,6,7));
  row_other:=jsonb_build_object('stock',other_stock,'expected_tracking_id',other_item->>'tracking_id','expected_navision_record_id',other_item->>'navision_record_id','expected_order',other_item->>'order','expected_navision_updated_at',other_item->>'navision_updated_at',
   'items',jsonb_build_array(jsonb_build_object('description','Example dealer-fitted accessory','source_rows',jsonb_build_array(8),'quote_number',12345)),
   'notes','[]'::jsonb,'other_lines','[]'::jsonb,'source_rows',jsonb_build_array(8));
  unmatched:=jsonb_build_object('stock','BUILD-NOT-ON-WEBSITE','items','[]'::jsonb,'notes','[]'::jsonb,'other_lines','[]'::jsonb,'source_rows',jsonb_build_array(9));
  payload:=jsonb_build_array(row_own,row_other,unmatched,
   unmatched||jsonb_build_object('stock',duplicate_stock), unmatched||jsonb_build_object('stock','99883005'), unmatched||jsonb_build_object('stock','99883007'), unmatched||jsonb_build_object('stock',''));
  IF test_part IN ('core','all') THEN protected_before:=pg_temp.builds_fingerprint(true); END IF;
  result:=public.import_broome_sales_builds('example-build.xlsx',file_one,payload);
  IF result->>'imported'<>'2' OR result->>'skipped'<>'5' OR result->>'unchanged'<>'0' THEN RAISE EXCEPTION 'Initial exact-match counts incorrect: %',result; END IF;
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(result->'skipped_details') e WHERE e->>'reason'='duplicate_current_stock')
   OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(result->'skipped_details') e WHERE e->>'reason'='identity_conflict')
   OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(result->'skipped_details') e WHERE e->>'stock'='99883007' AND e->>'reason' IN ('missing_current_order','identity_conflict')) THEN RAISE EXCEPTION 'Missing duplicate/order-conflict/blank-order guards'; END IF;
  IF test_part IN ('core','all') THEN
  SELECT count(*) INTO imports_before FROM pdc_sales_private.sales_build_import_batches;
  result:=public.import_broome_sales_builds('example-build.xlsx',file_one,payload);
  IF result->>'replayed'<>'true' OR result->>'imported'<>'0' OR result->>'unchanged'<>'2' OR (SELECT count(*) FROM pdc_sales_private.sales_build_import_batches)<>imports_before THEN RAISE EXCEPTION 'Exact file replay wrote records'; END IF;
  getter_started:=clock_timestamp(); displayed:=public.get_broome_sales_builds(); getter_elapsed_ms:=round(extract(epoch FROM clock_timestamp()-getter_started)*1000,2);
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(displayed->'items') e WHERE e->>'stock'=own_stock AND e->>'order'=own_order AND e->>'navision_record_id'=source_own::text AND e#>>'{items,0,description}'='Example canopy at body builder' AND e#>>'{notes,0,text}'=E'Example build note\nPreserve this second line') THEN RAISE EXCEPTION 'Leading-zero identity/whole-build/note linebreak display failed'; END IF;
  bad:=jsonb_set(payload,'{0,notes,0,text}','"Different source contents"');
  denied:=false; BEGIN PERFORM public.import_broome_sales_builds('example-build.xlsx',file_one,bad); EXCEPTION WHEN OTHERS THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'Same file checksum reused with altered source payload'; END IF;
  SELECT version INTO order_version FROM pdc_sales_private.sales_build_orders WHERE order_key=upper(own_order);
  IF order_version IS NULL THEN RAISE EXCEPTION 'Imported stable order key missing'; END IF;
  result:=public.import_broome_sales_builds('unchanged-build.xlsx',file_two,jsonb_build_array(row_own,row_other));
  IF result->>'unchanged'<>'2' OR (SELECT version FROM pdc_sales_private.sales_build_orders WHERE order_key=upper(own_order)) IS DISTINCT FROM order_version THEN RAISE EXCEPTION 'Identical newer file rewrote unchanged order'; END IF;
  result:=public.import_broome_sales_builds('changed-build.xlsx',repeat('c',64),jsonb_build_array(jsonb_set(row_own,'{notes,0,text}','"Updated imported note only"')));
  IF result->>'imported'<>'1' OR NOT EXISTS(SELECT 1 FROM pdc_sales_private.sales_build_orders WHERE order_key=upper(other_order)) THEN RAISE EXCEPTION 'Changed file failed or removed omitted order: %',result; END IF;
  result:=public.import_broome_sales_builds('stale-preview.xlsx',repeat('d',64),jsonb_build_array(row_own||jsonb_build_object('expected_order','Different order')));
  IF result->>'imported'<>'0' OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(result->'skipped_details') e WHERE e->>'reason'='stale_preview_identity') THEN RAISE EXCEPTION 'Stale expected order accepted'; END IF;
  result:=public.import_broome_sales_builds('stale-time.xlsx',repeat('e',64),jsonb_build_array(row_own||jsonb_build_object('expected_navision_updated_at','2000-01-01T00:00:00Z')));
  IF result->>'imported'<>'0' OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(result->'skipped_details') e WHERE e->>'reason'='stale_preview_identity') THEN RAISE EXCEPTION 'Stale Navision timestamp accepted'; END IF;
  result:=public.import_broome_sales_builds('duplicate-input.xlsx',repeat('f',64),jsonb_build_array(row_own,row_own));
  IF result->>'imported'<>'0' OR result->>'skipped'<>'2' THEN RAISE EXCEPTION 'Duplicate input stock selected arbitrarily'; END IF;
  bad:=jsonb_set(row_own,'{items,0,completed}','true'); denied:=false;
  BEGIN PERFORM public.import_broome_sales_builds('status-injection.xlsx',repeat('1',64),jsonb_build_array(bad)); EXCEPTION WHEN OTHERS THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'Imported source inferred/wrote completion status'; END IF;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',own_user,'email',own_email,'role','authenticated')::text,true);
  displayed:=public.get_broome_sales_builds();
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(displayed->'items') e WHERE e->>'order'=own_order) OR EXISTS(SELECT 1 FROM jsonb_array_elements(displayed->'items') e WHERE e->>'order'=other_order) THEN RAISE EXCEPTION 'Salesperson own read scope failed'; END IF;
  denied:=false; BEGIN PERFORM public.import_broome_sales_builds('salesperson-import.xlsx',repeat('2',64),jsonb_build_array(row_own)); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'Salesperson can import builds'; END IF;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',pending_user,'email',pending_email,'role','authenticated')::text,true);
  denied:=false; BEGIN PERFORM public.get_broome_sales_builds(); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'Unapproved account can read builds'; END IF;
  denied:=false; BEGIN PERFORM public.import_broome_sales_builds('pending-import.xlsx',repeat('3',64),jsonb_build_array(row_own)); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'Unapproved account can import builds'; END IF;
  PERFORM set_config('request.jwt.claims','{}',true); denied:=false;
  BEGIN PERFORM public.get_broome_sales_builds(); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'Signed-out caller can read builds'; END IF;
  IF pg_temp.builds_fingerprint(true)<>protected_before THEN RAISE EXCEPTION 'Build import/read/replay wrote protected PDC vehicles/bookings/parts/imports/roles/people, sales private or Auth users data'; END IF;
  ELSE
   result:=public.import_broome_sales_builds('changed-build.xlsx',repeat('c',64),jsonb_build_array(jsonb_set(row_own,'{notes,0,text}','"Updated imported note only"')));
   IF result->>'imported'<>'1' THEN RAISE EXCEPTION 'Lifecycle fixture note setup failed'; END IF;
  END IF;
  -- Explicit fixture-only source changes verify the getter follows exact dealer/order
  -- across stock allocation, and hides hidden/missing/ambiguous current sources.
  IF test_part IN ('identity','visibility','all') THEN
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'email',admin_email,'role','authenticated')::text,true);
  UPDATE public.navision_backend_records SET normalized_data=normalized_data||jsonb_build_object('batch','009983099'),updated_at=clock_timestamp() WHERE id=source_own;
  IF test_part IN ('identity','all') THEN
  displayed:=public.get_broome_sales_builds();
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(displayed->'items') e WHERE e->>'order'=own_order AND e->>'stock'='009983099' AND e->>'source_stock'=own_stock AND e#>>'{notes,0,text}'='Updated imported note only') THEN RAISE EXCEPTION 'Exact order build lost after stock reallocation'; END IF;
  -- A new source UUID reusing an order number must not inherit old build details.
  -- A fresh explicit preview/import may attach the source payload to that record.
  BEGIN
   UPDATE public.navision_backend_records SET is_current=false,record_status='not_in_latest_batch',missing_since_batch_id=latest_batch WHERE id=source_own;
   INSERT INTO public.navision_backend_records(id,source_system,dealer_code,source_record_id,row_hash,normalized_data,raw_evidence,first_seen_batch_id,last_seen_batch_id,record_status,is_current)
   VALUES(source_replacement,'microsoft_navision','37047',own_order||'-REPLACEMENT',repeat('8',64),jsonb_build_object('order',own_order,'batch','009983099','cosi',true,'salesperson','BG','client','Replacement fictional build customer'),'{}',latest_batch,latest_batch,'current',true);
   displayed:=public.get_broome_sales_builds();
   IF EXISTS(SELECT 1 FROM jsonb_array_elements(displayed->'items') e WHERE e->>'order'=own_order) THEN RAISE EXCEPTION 'Replacement source inherited old build requirements'; END IF;
   snap:=pdc_sales_private.visibility_source_snapshot(false);
   SELECT e INTO bad FROM jsonb_array_elements(snap->'items') e WHERE e->>'navision_record_id'=source_replacement::text;
   IF bad IS NULL THEN RAISE EXCEPTION 'Replacement fixture not visible in current source'; END IF;
   result:=public.import_broome_sales_builds('reviewed-replacement.xlsx',repeat('5',64),jsonb_build_array(row_own||jsonb_build_object('stock','009983099','expected_tracking_id',bad->>'tracking_id','expected_navision_record_id',bad->>'navision_record_id','expected_order',bad->>'order','expected_navision_updated_at',bad->>'navision_updated_at')));
   IF result->>'imported'<>'1' THEN RAISE EXCEPTION 'Explicit replacement preview/import failed'; END IF;
   displayed:=public.get_broome_sales_builds();
   IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(displayed->'items') e WHERE e->>'order'=own_order AND e->>'navision_record_id'=source_replacement::text) THEN RAISE EXCEPTION 'Reviewed replacement source build did not display'; END IF;
   RAISE EXCEPTION 'Rollback replacement source fixtures' USING errcode='ZX002';
  EXCEPTION WHEN SQLSTATE 'ZX002' THEN NULL;
  END;
  END IF;
  IF test_part IN ('visibility','all') THEN
  PERFORM public.set_broome_sales_vehicle_visibility((own_item->>'tracking_id')::uuid,true,0);
  displayed:=public.get_broome_sales_builds();
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(displayed->'items') e WHERE e->>'order'=own_order) THEN RAISE EXCEPTION 'Hidden source build remained visible'; END IF;
  result:=public.import_broome_sales_builds('hidden-source.xlsx',repeat('4',64),jsonb_build_array(row_own||jsonb_build_object('stock','009983099')));
  IF result->>'imported'<>'0' THEN RAISE EXCEPTION 'Hidden source imported'; END IF;
  PERFORM public.set_broome_sales_vehicle_visibility((own_item->>'tracking_id')::uuid,false,1);
  UPDATE public.navision_backend_records SET is_current=false,record_status='not_in_latest_batch',missing_since_batch_id=latest_batch WHERE id=source_own;
  displayed:=public.get_broome_sales_builds();
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(displayed->'items') e WHERE e->>'order'=own_order) THEN RAISE EXCEPTION 'Missing source retained build through private fallback'; END IF;
  UPDATE public.navision_backend_records SET is_current=true,record_status='current',missing_since_batch_id=NULL WHERE id=source_own;
  UPDATE public.navision_backend_records SET normalized_data=normalized_data||jsonb_build_object('batch','009983099') WHERE id=source_extra;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',own_user,'email',own_email,'role','authenticated')::text,true);
  displayed:=public.get_broome_sales_builds();
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(displayed->'items') e WHERE e->>'order'=own_order) THEN RAISE EXCEPTION 'Cross-roster duplicate stock leaked through own getter scope'; END IF;
  UPDATE public.pdc_user_roles SET active=false,account_status='disabled' WHERE id=own_role;
  denied:=false; BEGIN PERFORM public.get_broome_sales_builds(); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'Disabled salesperson can read builds'; END IF;
  END IF;
  END IF;
  IF function_before<>(SELECT md5(coalesce(jsonb_agg(jsonb_build_array(p.oid,pg_get_functiondef(p.oid),p.proacl) ORDER BY p.oid),'[]'::jsonb)::text) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN ('public','pdc_sales_private') AND p.prokind='f') THEN RAISE EXCEPTION 'Build operations altered existing functions/permissions'; END IF;
  RAISE EXCEPTION 'Rollback successful build fixtures' USING errcode='ZX001';
 EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL;
 END;
 IF EXISTS(SELECT 1 FROM auth.users WHERE id IN (admin_id,own_user,other_user,pending_user))
 OR EXISTS(SELECT 1 FROM public.pdc_user_roles WHERE email IN (admin_email,own_email,other_email,pending_email))
 OR EXISTS(SELECT 1 FROM pdc_sales_private.account_scopes WHERE user_role_id IN (own_role,other_role))
 OR EXISTS(SELECT 1 FROM public.salespeople WHERE id=extra_person)
 OR EXISTS(SELECT 1 FROM public.navision_backend_records WHERE id IN (source_own,source_other,source_extra,source_duplicate,source_conflict,source_conflict2,source_missing,source_replacement))
 OR EXISTS(SELECT 1 FROM pdc_sales_private.sales_build_orders WHERE order_key IN (upper(own_order),upper(other_order)))
 OR EXISTS(SELECT 1 FROM pdc_sales_private.sales_build_import_batches WHERE imported_by=admin_id)
 OR EXISTS(SELECT 1 FROM pdc_sales_private.vehicle_visibility WHERE tracking_id=(own_item->>'tracking_id')::uuid)
 THEN RAISE EXCEPTION 'Synthetic build fixtures remained after subtransaction rollback'; END IF;
 PERFORM set_config('app.sales_builds_test_getter_ms',coalesce(getter_elapsed_ms::text,''),true);
END $test$;
SELECT coalesce(nullif(current_setting('app.sales_builds_test_part',true),''),'all') AS test_part,
 nullif(current_setting('app.sales_builds_test_getter_ms',true),'')::numeric AS getter_elapsed_ms,
 'Selected exact-match/role/isolation or source lifecycle assertions passed; function permissions unchanged and synthetic fixtures rolled back' AS verification;
ROLLBACK;
