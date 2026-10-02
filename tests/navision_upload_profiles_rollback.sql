-- Synthetic records only; all database changes roll back.
BEGIN;
SET LOCAL statement_timeout='120s';
DO $test$
DECLARE a uuid:=gen_random_uuid(); mail text; rows jsonb; r jsonb; p jsonb; replay jsonb; bad jsonb; fixture_id uuid; sid text; before_vehicles text; before_bookings text; before_progress text; profile text; dealer text; uid text:=gen_random_uuid()::text; denied boolean; before_revision bigint;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'Staging only';END IF;
 mail:='upload-rollback-'||a||'@example.invalid';INSERT INTO auth.users(id,aud,role,email,email_confirmed_at,created_at,updated_at) VALUES(a,'authenticated','authenticated',mail,now(),now(),now());
 INSERT INTO public.pdc_user_roles(email,auth_user_id,role,active,account_status) VALUES(mail,a,'administrator',true,'approved') ON CONFLICT(email) DO UPDATE SET role='administrator',active=true,account_status='approved',auth_user_id=a;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',a,'email',mail,'role','authenticated')::text,true);
 SELECT md5(coalesce(jsonb_agg(jsonb_build_object('id',v.id,'location',v.current_location,'pmb_stage',v.pmb_stage,'workshop_status',v.workshop_status,'date_to_pmb',v.date_to_pmb,'qc_completed_at',v.qc_completed_at) ORDER BY v.id),'[]'::jsonb)::text) INTO before_vehicles FROM public.vehicles v;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(v) ORDER BY v.id),'[]'::jsonb)::text) INTO before_bookings FROM public.workshop_bookings v;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(v) ORDER BY tracking_id),'[]'::jsonb)::text) INTO before_progress FROM pdc_sales_private.ordering_progress v;
 FOREACH profile IN ARRAY ARRAY['broome','pilbara'] LOOP
  dealer:=CASE profile WHEN 'broome' THEN '001234' ELSE '002345' END;
  -- Keep all existing rows for the selected dealer scopes; do not simulate an empty snapshot.
  SELECT coalesce(jsonb_agg(n.raw_evidence ORDER BY n.id),'[]'::jsonb) INTO rows FROM public.navision_backend_records n WHERE n.is_current AND n.record_status='current' AND n.source_system='microsoft_navision' AND n.dealer_code=dealer;
  rows:=rows||jsonb_build_array(jsonb_build_object('id','fixture-'||profile||'-'||uid,'order','fixture-'||profile||'-'||uid,'cosi','Yes','consultant','BG','client','Fictional upload test','stock','','batch','','navisionRawEvidence',jsonb_build_object('columns',jsonb_build_array(jsonb_build_object('header','Dealer','value',dealer),jsonb_build_object('header','Order','value','fixture-'||profile||'-'||uid),jsonb_build_object('header','COSI','value','Yes'),jsonb_build_object('header','Salesperson','value','BG')))));
  p:=public.preview_navision_upload_profile(profile,rows,'fictional-test.tsv',NULL);
  IF p#>>'{data,safety,reason}'='unproven_empty_dealer_scope' THEN PERFORM public.approve_navision_upload_profile(profile,rows);p:=public.preview_navision_upload_profile(profile,rows,'fictional-test.tsv',NULL);END IF;
  IF p#>>'{data,blocking}' IS DISTINCT FROM 'false' THEN RAISE EXCEPTION 'Fixture preview blocked: %',p;END IF;
  r:=public.apply_navision_upload_profile(profile,'test-'||profile||'-'||uid,rows,'fictional-test.tsv',NULL,p#>>'{data,source_hash}',p#>>'{data,preview_hash}',(p#>>'{data,base_revision}')::bigint);
  IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Fixture apply failed: %',r;END IF;
  SELECT n.id,n.source_record_id INTO fixture_id,sid FROM public.navision_backend_records n WHERE n.dealer_code=dealer AND n.normalized_data->>'order'=upper('fixture-'||profile||'-'||uid);
  IF fixture_id IS NULL OR EXISTS(SELECT 1 FROM public.navision_backend_records n WHERE n.id=fixture_id AND n.canonical_vehicle_id IS NOT NULL) THEN RAISE EXCEPTION 'Stockless order failed or activated a PDC vehicle';END IF;
  replay:=public.apply_navision_upload_profile(profile,'test-'||profile||'-'||uid,rows,'fictional-test.tsv',NULL,p#>>'{data,source_hash}',p#>>'{data,preview_hash}',(p#>>'{data,base_revision}')::bigint);
  IF replay IS DISTINCT FROM r THEN RAISE EXCEPTION 'Replay created a second receipt';END IF;
  replay:=public.apply_navision_upload_profile(profile,'test-'||profile||'-'||uid,rows,'changed.tsv',NULL,p#>>'{data,source_hash}',p#>>'{data,preview_hash}',(p#>>'{data,base_revision}')::bigint);
  IF replay->>'code'<>'idempotency_conflict' THEN RAISE EXCEPTION 'Changed replay accepted';END IF;
  replay:=public.apply_navision_upload_profile(profile,'test-stale-'||uid,rows,'fictional-test.tsv',NULL,p#>>'{data,source_hash}',p#>>'{data,preview_hash}',(p#>>'{data,base_revision}')::bigint);
  IF replay->>'code'<>'stale_revision' THEN RAISE EXCEPTION 'Stale preview accepted';END IF;
  rows:=jsonb_set(rows,ARRAY[(jsonb_array_length(rows)-1)::text,'stock'],to_jsonb('TEST-STOCK-'||profile||uid));rows:=jsonb_set(rows,ARRAY[(jsonb_array_length(rows)-1)::text,'batch'],to_jsonb('TEST-STOCK-'||profile||uid));
  p:=public.preview_navision_upload_profile(profile,rows,'stock-allocated.tsv',NULL);
  IF p#>>'{data,blocking}' IS DISTINCT FROM 'false' THEN RAISE EXCEPTION 'Stock allocation preview blocked: %',p;END IF;
  r:=public.apply_navision_upload_profile(profile,'test-stock-'||profile||'-'||uid,rows,'stock-allocated.tsv',NULL,p#>>'{data,source_hash}',p#>>'{data,preview_hash}',(p#>>'{data,base_revision}')::bigint);
  IF r->>'ok' IS DISTINCT FROM 'true' OR NOT EXISTS(SELECT 1 FROM public.navision_backend_records n WHERE n.id=fixture_id AND n.source_record_id=sid AND n.normalized_data->>'batch'=public.normalize_vehicle_stock_number('TEST-STOCK-'||profile||uid)) THEN RAISE EXCEPTION 'Stock allocation failed: code %, fixture %',r->>'code',(SELECT jsonb_build_object('id',n.id,'sid',n.source_record_id,'batch',n.normalized_data->>'batch') FROM public.navision_backend_records n WHERE n.id=fixture_id);END IF;
 END LOOP;
 IF before_vehicles IS DISTINCT FROM (SELECT md5(coalesce(jsonb_agg(jsonb_build_object('id',v.id,'location',v.current_location,'pmb_stage',v.pmb_stage,'workshop_status',v.workshop_status,'date_to_pmb',v.date_to_pmb,'qc_completed_at',v.qc_completed_at) ORDER BY v.id),'[]'::jsonb)::text) FROM public.vehicles v) OR before_bookings IS DISTINCT FROM (SELECT md5(coalesce(jsonb_agg(to_jsonb(v) ORDER BY v.id),'[]'::jsonb)::text) FROM public.workshop_bookings v) OR before_progress IS DISTINCT FROM (SELECT md5(coalesce(jsonb_agg(to_jsonb(v) ORDER BY tracking_id),'[]'::jsonb)::text) FROM pdc_sales_private.ordering_progress v) THEN RAISE EXCEPTION 'Synthetic uploads changed PDC work or sales ordering';END IF;

 -- Failure in the second included scope must roll back the first scope too.
 SELECT coalesce(jsonb_agg(n.raw_evidence ORDER BY n.id),'[]'::jsonb) INTO rows FROM public.navision_backend_records n WHERE n.is_current AND n.record_status='current' AND n.source_system='microsoft_navision' AND n.dealer_code IN('001234','002345');
 FOREACH dealer IN ARRAY ARRAY['001234','002345'] LOOP
  rows:=rows||jsonb_build_array(jsonb_build_object('id','atomic-'||dealer||'-'||uid,'order','atomic-'||dealer||'-'||uid,'cosi','Yes','consultant','BG','client','Fictional atomic test','stock','','batch','','navisionRawEvidence',jsonb_build_object('columns',jsonb_build_array(jsonb_build_object('header','Dealer','value',dealer),jsonb_build_object('header','Order','value','atomic-'||dealer||'-'||uid),jsonb_build_object('header','COSI','value','Yes')))));
 END LOOP;
 p:=public.preview_navision_upload_profile('pilbara',rows,'atomic-fixture.tsv',NULL);
 IF p#>>'{data,blocking}' IS DISTINCT FROM 'false' THEN RAISE EXCEPTION 'Atomic fixture blocked';END IF;
 SELECT revision INTO before_revision FROM public.navision_backend_revision WHERE singleton;
 EXECUTE format('CREATE FUNCTION pg_temp.fail_profile_second_scope() RETURNS trigger LANGUAGE plpgsql AS $failure$ BEGIN IF NEW.dealer_code=''002345'' AND NEW.source_record_id=%L THEN RAISE EXCEPTION ''simulated profile scope failure'';END IF;RETURN NEW;END $failure$',upper('TOYOTA-ORDER-atomic-002345-'||uid));
 CREATE TRIGGER upload_profile_test_failure BEFORE INSERT ON public.navision_backend_records FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_profile_second_scope();
 denied:=false;
 BEGIN
  r:=public.apply_navision_upload_profile('pilbara','atomic-'||uid,rows,'atomic-fixture.tsv',NULL,p#>>'{data,source_hash}',p#>>'{data,preview_hash}',(p#>>'{data,base_revision}')::bigint);
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE '%simulated profile scope failure%' THEN RAISE;END IF;denied:=true;
 END;
 DROP TRIGGER upload_profile_test_failure ON public.navision_backend_records;
 IF NOT denied OR EXISTS(SELECT 1 FROM public.navision_backend_records WHERE normalized_data->>'order' IN(upper('atomic-001234-'||uid),upper('atomic-002345-'||uid))) OR EXISTS(SELECT 1 FROM pdc_navision_combined_private.receipts WHERE actor_id=a AND idempotency_key='atomic-'||uid) OR (SELECT revision FROM public.navision_backend_revision WHERE singleton)<>before_revision THEN RAISE EXCEPTION 'Partial profile upload escaped rollback';END IF;
 UPDATE public.pdc_user_roles SET account_status='pending',role=NULL,active=false WHERE auth_user_id=a;
 IF public.preview_navision_upload_profile('broome',rows,'x',NULL)->>'code'<>'unauthorized' THEN RAISE EXCEPTION 'Pending account allowed';END IF;
 UPDATE public.pdc_user_roles SET account_status='approved',role='salesperson',active=true WHERE auth_user_id=a;
 IF public.preview_navision_upload_profile('broome',rows,'x',NULL)->>'code'<>'unauthorized' THEN RAISE EXCEPTION 'Salesperson import allowed';END IF;
 PERFORM set_config('request.jwt.claims','{}',true);
 IF public.preview_navision_upload_profile('broome',rows,'x',NULL)->>'code'<>'unauthorized' THEN RAISE EXCEPTION 'Signed-out import allowed';END IF;
 IF has_function_privilege('anon','public.preview_navision_upload_profile(text,jsonb,text,timestamptz)','EXECUTE') OR has_function_privilege('authenticated','pdc_navision_upload_private.split_profile(jsonb,text)','EXECUTE') THEN RAISE EXCEPTION 'Private helper exposed';END IF;
END $test$;
ROLLBACK;
SELECT 'PASS Broome/Pilbara stockless apply, atomic failure rollback, stable allocation, replay, stale preview, denied actors, PDC and ordering fingerprints; rolled back' result;
