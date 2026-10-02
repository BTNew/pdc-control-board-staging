-- AUDIT COPY: current, latest applied backend snapshot is authoritative. Source/runtime unchanged.
-- Staging-only fictional fixtures; all writes rolled back.
BEGIN ISOLATION LEVEL REPEATABLE READ;

CREATE FUNCTION pg_temp.emails_public_fingerprint() RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE t record; value_hash text; accum text:='';
BEGIN
 FOR t IN SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN ('r','p') ORDER BY c.relname LOOP
 EXECUTE format('SELECT md5(count(*)::text||'':''||coalesce(string_agg(row_hash,'''' ORDER BY row_hash),'''')) FROM (SELECT md5(to_jsonb(x)::text) row_hash FROM public.%I x) rows',t.relname) INTO value_hash;
 accum:=accum||t.relname||':'||value_hash||';';
 END LOOP;
 RETURN md5(accum);
END $fn$;

DO $test$
DECLARE actor public.pdc_user_roles; viewer public.pdc_user_roles; person public.salespeople;
 global_before text; private_before text; ops_before text; global_after text; private_after text; ops_after text; accum text; value_hash text; t record; payload jsonb; other_payload jsonb; result jsonb;
 batch uuid; own_id uuid; other_id uuid; built_id uuid; eta_id uuid; other_draft uuid; before_count integer; denied boolean; rec record;
BEGIN
 IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1 THEN RAISE EXCEPTION 'STAGING required'; END IF;
 SELECT * INTO actor FROM public.pdc_user_roles WHERE active AND account_status='approved' AND role::text='administrator' AND auth_user_id IS NOT NULL LIMIT 1;
 SELECT * INTO viewer FROM public.pdc_user_roles WHERE active AND account_status='approved' AND role::text='viewer' AND auth_user_id IS NOT NULL LIMIT 1;
 SELECT * INTO person FROM public.salespeople WHERE code='BG' AND active;
 IF actor.id IS NULL OR viewer.id IS NULL OR person.id IS NULL THEN RAISE EXCEPTION 'Rollback fixtures unavailable'; END IF;
 accum:=''; FOR t IN SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN ('r','p') ORDER BY c.relname LOOP EXECUTE format('SELECT md5(count(*)::text||'':''||coalesce(string_agg(row_hash,'''' ORDER BY row_hash),'''')) FROM (SELECT md5(to_jsonb(x)::text) row_hash FROM public.%I x) rows',t.relname) INTO value_hash; accum:=accum||t.relname||':'||value_hash||';'; END LOOP; global_before:=md5(accum);accum:=''; FOR t IN SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='pdc_sales_private' AND c.relkind IN ('r','p') ORDER BY c.relname LOOP EXECUTE format('SELECT md5(count(*)::text||'':''||coalesce(string_agg(row_hash,'''' ORDER BY row_hash),'''')) FROM (SELECT md5(to_jsonb(x)::text) row_hash FROM pdc_sales_private.%I x) rows',t.relname) INTO value_hash; accum:=accum||t.relname||':'||value_hash||';'; END LOOP; private_before:=md5(accum);
 IF has_function_privilege('anon','public.get_broome_customer_emails()','EXECUTE') OR has_function_privilege('anon','public.save_broome_customer_email(uuid,text,jsonb,integer)','EXECUTE') OR has_function_privilege('authenticated','pdc_sales_private.customer_email_observe(jsonb)','EXECUTE') THEN RAISE EXCEPTION 'Unsafe function access'; END IF;
 FOR rec IN SELECT relname,relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='pdc_sales_private' AND relname IN ('customer_email_observations','customer_email_drafts') LOOP
  IF NOT rec.relrowsecurity OR has_table_privilege('authenticated','pdc_sales_private.'||rec.relname,'SELECT,INSERT,UPDATE,DELETE') THEN RAISE EXCEPTION 'Unsafe customer table permissions'; END IF;
 END LOOP;
 IF pdc_sales_private.customer_email_date('2026-02-30') IS NOT NULL OR pdc_sales_private.customer_email_date('4/11/2026')<>'2026-11-04' THEN RAISE EXCEPTION 'Date validation/canonicalisation failed'; END IF;
 IF pdc_sales_private.customer_email_signals('{"toyota_status":"Production","build_complete":true,"vin":"EXAMPLEVIN"}'::jsonb) ? 'vehicle_built' THEN RAISE EXCEPTION 'Workshop/VIN inferred vehicle built'; END IF;
 BEGIN
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor.auth_user_id,'email',actor.email,'role','authenticated')::text,true);
  payload:=jsonb_build_object('dealer_code','37047','order','EMAIL-ROLLBACK-OWN','batch','','cosi','Yes','consultant','BG','client','Example customer','vehicle','Example Hilux','navisionSubLocationDescription','Production','prodMth','10/26');
  other_payload:=payload||jsonb_build_object('order','EMAIL-ROLLBACK-OTHER','consultant','PM');
  PERFORM public.import_broome_sales_orders(jsonb_build_array(payload,other_payload),true);
  SELECT id INTO batch FROM public.navision_import_batches WHERE source_system='microsoft_navision' AND dealer_code='37047' AND status='applied' AND rolled_back_at IS NULL ORDER BY result_revision DESC,applied_at DESC,id DESC LIMIT 1;
  IF batch IS NULL THEN RAISE EXCEPTION 'Need latest applied Broome batch'; END IF;
  IF EXISTS(SELECT 1 FROM public.navision_backend_records WHERE source_record_id IN ('EMAIL-ROLLBACK-OWN','EMAIL-ROLLBACK-OTHER')) THEN RAISE EXCEPTION 'Fictional source identity exists'; END IF;
  INSERT INTO public.navision_backend_records(source_system,dealer_code,source_record_id,row_hash,normalized_data,raw_evidence,first_seen_batch_id,last_seen_batch_id,record_status,is_current)
  SELECT 'microsoft_navision','37047',e->>'order',repeat('0',64),e,'{}',batch,batch,'current',true FROM jsonb_array_elements(jsonb_build_array(payload,other_payload)) e;

  SELECT id INTO own_id FROM pdc_sales_private.tracked_orders WHERE order_key='EMAIL-ROLLBACK-OWN';
  SELECT id INTO other_id FROM pdc_sales_private.tracked_orders WHERE order_key='EMAIL-ROLLBACK-OTHER';
  UPDATE public.pdc_user_roles SET role=NULL,active=false,account_status='pending' WHERE id=viewer.id;
  PERFORM public.assign_broome_sales_access(viewer.id,person.id);
  accum:=''; FOR t IN SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN ('r','p') ORDER BY c.relname LOOP EXECUTE format('SELECT md5(count(*)::text||'':''||coalesce(string_agg(row_hash,'''' ORDER BY row_hash),'''')) FROM (SELECT md5(to_jsonb(x)::text) row_hash FROM public.%I x) rows',t.relname) INTO value_hash; accum:=accum||t.relname||':'||value_hash||';'; END LOOP; ops_before:=md5(accum);
  result:=public.get_broome_customer_emails();
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(result->'drafts') e WHERE e->>'tracking_id'=own_id::text) THEN RAISE EXCEPTION 'Initial baseline created historical drafts'; END IF;
  PERFORM public.set_broome_sales_ordering_flag(own_id,'build_complete',true,0);
  PERFORM public.get_broome_customer_emails();
  IF EXISTS(SELECT 1 FROM pdc_sales_private.customer_email_drafts WHERE tracking_id=own_id AND template_kind='vehicle_built') THEN RAISE EXCEPTION 'Sales Build Complete triggered customer built email'; END IF;
  payload:=payload||jsonb_build_object('navisionSubLocationDescription','Planned for Production','prodMth','11/26');
  PERFORM public.import_broome_sales_orders(jsonb_build_array(payload),true);
  IF pg_temp.emails_public_fingerprint()<>ops_before THEN RAISE EXCEPTION 'Email/private import changed public data before source fixture update'; END IF;
  UPDATE public.navision_backend_records SET normalized_data=payload
  WHERE source_system='microsoft_navision' AND dealer_code='37047' AND source_record_id=payload->>'order';
  ops_before:=pg_temp.emails_public_fingerprint();
  PERFORM public.get_broome_customer_emails();
  IF (SELECT count(*) FROM pdc_sales_private.customer_email_drafts WHERE tracking_id=own_id AND template_kind='production_planned' AND status='draft')<>1 THEN RAISE EXCEPTION 'Planned production trigger missing'; END IF;
  PERFORM public.get_broome_customer_emails();
  payload:=payload||jsonb_build_object('prodMth','11/2026');PERFORM public.import_broome_sales_orders(jsonb_build_array(payload),true);
  IF pg_temp.emails_public_fingerprint()<>ops_before THEN RAISE EXCEPTION 'Email/private import changed public data before source fixture update'; END IF;
  UPDATE public.navision_backend_records SET normalized_data=payload
  WHERE source_system='microsoft_navision' AND dealer_code='37047' AND source_record_id=payload->>'order';
  ops_before:=pg_temp.emails_public_fingerprint();
  PERFORM public.get_broome_customer_emails();
  IF (SELECT count(*) FROM pdc_sales_private.customer_email_drafts WHERE tracking_id=own_id)<>1 THEN RAISE EXCEPTION 'Equivalent month or repeated check duplicated draft'; END IF;
  payload:=payload||jsonb_build_object('prodMth','12/26');PERFORM public.import_broome_sales_orders(jsonb_build_array(payload),true);
  IF pg_temp.emails_public_fingerprint()<>ops_before THEN RAISE EXCEPTION 'Email/private import changed public data before source fixture update'; END IF;
  UPDATE public.navision_backend_records SET normalized_data=payload
  WHERE source_system='microsoft_navision' AND dealer_code='37047' AND source_record_id=payload->>'order';
  ops_before:=pg_temp.emails_public_fingerprint();
  PERFORM public.get_broome_customer_emails();
  IF (SELECT count(*) FROM pdc_sales_private.customer_email_drafts WHERE tracking_id=own_id AND status='superseded')<>1 THEN RAISE EXCEPTION 'Old production update was not superseded'; END IF;
  payload:=payload||jsonb_build_object('navisionSubLocationDescription','Line Off Complete');PERFORM public.import_broome_sales_orders(jsonb_build_array(payload),true);
  IF pg_temp.emails_public_fingerprint()<>ops_before THEN RAISE EXCEPTION 'Email/private import changed public data before source fixture update'; END IF;
  UPDATE public.navision_backend_records SET normalized_data=payload
  WHERE source_system='microsoft_navision' AND dealer_code='37047' AND source_record_id=payload->>'order';
  ops_before:=pg_temp.emails_public_fingerprint();
  PERFORM public.get_broome_customer_emails();
  SELECT id INTO built_id FROM pdc_sales_private.customer_email_drafts WHERE tracking_id=own_id AND template_kind='vehicle_built';
  IF built_id IS NULL THEN RAISE EXCEPTION 'Toyota built confirmation trigger missing'; END IF;
  payload:=payload||jsonb_build_object('navisionSubLocationDescription','Ready For Shipment');PERFORM public.import_broome_sales_orders(jsonb_build_array(payload),true);
  IF pg_temp.emails_public_fingerprint()<>ops_before THEN RAISE EXCEPTION 'Email/private import changed public data before source fixture update'; END IF;
  UPDATE public.navision_backend_records SET normalized_data=payload
  WHERE source_system='microsoft_navision' AND dealer_code='37047' AND source_record_id=payload->>'order';
  ops_before:=pg_temp.emails_public_fingerprint();
  PERFORM public.get_broome_customer_emails();
  IF (SELECT count(*) FROM pdc_sales_private.customer_email_drafts WHERE tracking_id=own_id AND template_kind='vehicle_built')<>1 THEN RAISE EXCEPTION 'Built status transition duplicated update'; END IF;
  denied:=false;BEGIN PERFORM public.save_broome_customer_email(built_id,'prepare','{"recipient":"example@example.invalid","subject":"Built","body":"Hi {{customer_first_name}}"}',1);EXCEPTION WHEN OTHERS THEN denied:=true;END;
  IF NOT denied THEN RAISE EXCEPTION 'Unresolved customer placeholder accepted'; END IF;
  result:=public.save_broome_customer_email(built_id,'prepare','{"recipient":"example@example.invalid","subject":"Example Hilux built","body":"Hi Example, your Example Hilux has been built. Kind Regards, Example salesperson, 0400 000 000, staff@example.invalid"}',1);
  IF result#>>'{record,status}'<>'prepared' OR result#>'{record,sent_at}'<>'null'::jsonb THEN RAISE EXCEPTION 'Preparation incorrectly recorded sending'; END IF;
  denied:=false;BEGIN PERFORM public.save_broome_customer_email(built_id,'prepare','{}',1);EXCEPTION WHEN serialization_failure THEN denied:=true;END;
  IF NOT denied THEN RAISE EXCEPTION 'Concurrent preparation was not version protected'; END IF;
  denied:=false;BEGIN PERFORM public.save_broome_customer_email(built_id,'prepare','{}',2);EXCEPTION WHEN OTHERS THEN denied:=true;END;
  IF NOT denied THEN RAISE EXCEPTION 'Already prepared draft exported twice'; END IF;
  result:=public.save_broome_customer_email(built_id,'sent','{}',2);
  IF result#>>'{record,status}'<>'sent' OR result#>>'{record,sent_at}' IS NULL THEN RAISE EXCEPTION 'Explicit sent confirmation missing'; END IF;
  PERFORM public.get_broome_customer_emails();
  IF (SELECT count(*) FROM pdc_sales_private.customer_email_drafts WHERE tracking_id=own_id AND template_kind='vehicle_built')<>1 THEN RAISE EXCEPTION 'Sent update regenerated'; END IF;
  payload:=payload||jsonb_build_object('navisionKewdaleEta','4/11/2026');PERFORM public.import_broome_sales_orders(jsonb_build_array(payload),true);
  IF pg_temp.emails_public_fingerprint()<>ops_before THEN RAISE EXCEPTION 'Email/private import changed public data before source fixture update'; END IF;
  UPDATE public.navision_backend_records SET normalized_data=payload
  WHERE source_system='microsoft_navision' AND dealer_code='37047' AND source_record_id=payload->>'order';
  ops_before:=pg_temp.emails_public_fingerprint();
  PERFORM public.get_broome_customer_emails();
  SELECT id INTO eta_id FROM pdc_sales_private.customer_email_drafts WHERE tracking_id=own_id AND template_kind='perth_eta' AND status='draft';
  IF eta_id IS NULL THEN RAISE EXCEPTION 'Perth ETA trigger missing'; END IF;
  payload:=payload||jsonb_build_object('navisionKewdaleEta','2026-11-04');PERFORM public.import_broome_sales_orders(jsonb_build_array(payload),true);
  IF pg_temp.emails_public_fingerprint()<>ops_before THEN RAISE EXCEPTION 'Email/private import changed public data before source fixture update'; END IF;
  UPDATE public.navision_backend_records SET normalized_data=payload
  WHERE source_system='microsoft_navision' AND dealer_code='37047' AND source_record_id=payload->>'order';
  ops_before:=pg_temp.emails_public_fingerprint();
  PERFORM public.get_broome_customer_emails();
  IF (SELECT count(*) FROM pdc_sales_private.customer_email_drafts WHERE tracking_id=own_id AND template_kind='perth_eta')<>1 THEN RAISE EXCEPTION 'Equivalent ETA duplicated draft'; END IF;
  result:=public.save_broome_customer_email(eta_id,'save','{"recipient":"example@example.invalid","subject":"Perth ETA","body":"Reviewed customer update"}',1);
  denied:=false;BEGIN PERFORM public.save_broome_customer_email(eta_id,'save','{"current_location":"PDC EDIT"}',2);EXCEPTION WHEN OTHERS THEN denied:=true;END;
  IF NOT denied THEN RAISE EXCEPTION 'PDC field accepted in email edit'; END IF;
  payload:=payload||jsonb_build_object('navisionKewdaleEta','2026-11-05');PERFORM public.import_broome_sales_orders(jsonb_build_array(payload),true);
  IF pg_temp.emails_public_fingerprint()<>ops_before THEN RAISE EXCEPTION 'Email/private import changed public data before source fixture update'; END IF;
  UPDATE public.navision_backend_records SET normalized_data=payload
  WHERE source_system='microsoft_navision' AND dealer_code='37047' AND source_record_id=payload->>'order';
  ops_before:=pg_temp.emails_public_fingerprint();
  
  denied:=false;BEGIN PERFORM public.save_broome_customer_email(eta_id,'prepare','{}',2);EXCEPTION WHEN serialization_failure THEN denied:=true;END;
  IF NOT denied THEN RAISE EXCEPTION 'Outdated ETA prepared'; END IF;
  PERFORM public.get_broome_customer_emails();
  IF (SELECT status FROM pdc_sales_private.customer_email_drafts WHERE id=eta_id)<>'superseded' THEN RAISE EXCEPTION 'Old ETA remains sendable'; END IF;
  other_payload:=other_payload||jsonb_build_object('navisionSubLocationDescription','Line Off Complete');PERFORM public.import_broome_sales_orders(jsonb_build_array(other_payload),true);
  IF pg_temp.emails_public_fingerprint()<>ops_before THEN RAISE EXCEPTION 'Email/private import changed public data before source fixture update'; END IF;
  UPDATE public.navision_backend_records SET normalized_data=other_payload
  WHERE source_system='microsoft_navision' AND dealer_code='37047' AND source_record_id=other_payload->>'order';
  ops_before:=pg_temp.emails_public_fingerprint();
  PERFORM public.get_broome_customer_emails();
  SELECT id INTO other_draft FROM pdc_sales_private.customer_email_drafts WHERE tracking_id=other_id AND status='draft';
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',viewer.auth_user_id,'email',viewer.email,'role','authenticated')::text,true);
  result:=public.get_broome_customer_emails();
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(result->'drafts') e WHERE e->>'tracking_id'=other_id::text) THEN RAISE EXCEPTION 'Other salesperson emails leaked'; END IF;
  denied:=false;BEGIN PERFORM public.save_broome_customer_email(other_draft,'save','{}',1);EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
  IF NOT denied THEN RAISE EXCEPTION 'Other salesperson draft edit allowed'; END IF;
  denied:=false;BEGIN PERFORM public.save_broome_customer_email(gen_random_uuid(),'save','{}',1);EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
  IF NOT denied THEN RAISE EXCEPTION 'Unknown draft allowed'; END IF;
  PERFORM set_config('request.jwt.claims','{}',true);
  denied:=false;BEGIN PERFORM public.get_broome_customer_emails();EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
  IF NOT denied THEN RAISE EXCEPTION 'Anonymous queue access allowed'; END IF;
  accum:=''; FOR t IN SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN ('r','p') ORDER BY c.relname LOOP EXECUTE format('SELECT md5(count(*)::text||'':''||coalesce(string_agg(row_hash,'''' ORDER BY row_hash),'''')) FROM (SELECT md5(to_jsonb(x)::text) row_hash FROM public.%I x) rows',t.relname) INTO value_hash; accum:=accum||t.relname||':'||value_hash||';'; END LOOP; ops_after:=md5(accum); IF ops_before<>ops_after THEN RAISE EXCEPTION 'Customer draft workflow changed PDC/public data'; END IF;
  RAISE EXCEPTION 'EMAIL_FIXTURE_ROLLBACK' USING errcode='Z0001';
 EXCEPTION WHEN SQLSTATE 'Z0001' THEN NULL;
 END;
 accum:=''; FOR t IN SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN ('r','p') ORDER BY c.relname LOOP EXECUTE format('SELECT md5(count(*)::text||'':''||coalesce(string_agg(row_hash,'''' ORDER BY row_hash),'''')) FROM (SELECT md5(to_jsonb(x)::text) row_hash FROM public.%I x) rows',t.relname) INTO value_hash; accum:=accum||t.relname||':'||value_hash||';'; END LOOP; global_after:=md5(accum);accum:=''; FOR t IN SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='pdc_sales_private' AND c.relkind IN ('r','p') ORDER BY c.relname LOOP EXECUTE format('SELECT md5(count(*)::text||'':''||coalesce(string_agg(row_hash,'''' ORDER BY row_hash),'''')) FROM (SELECT md5(to_jsonb(x)::text) row_hash FROM pdc_sales_private.%I x) rows',t.relname) INTO value_hash; accum:=accum||t.relname||':'||value_hash||';'; END LOOP; private_after:=md5(accum); IF global_before<>global_after OR private_before<>private_after THEN RAISE EXCEPTION 'Test fixtures persisted'; END IF;
END $test$;
SELECT 'PASS: customer triggers, canonical deduplication, versioned preparation, sent confirmation, scoped access, outdated drafts, and all public records unchanged; fictional fixtures rolled back' AS result;
ROLLBACK;
