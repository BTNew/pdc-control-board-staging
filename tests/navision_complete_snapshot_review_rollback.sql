-- Fictional additions only; the transaction rolls back every change.
BEGIN;
SET LOCAL statement_timeout='180s';
DO $test$
DECLARE actor uuid:=gen_random_uuid(); fixture_email text; uid text:=gen_random_uuid()::text; rows jsonb:='[]'; original_rows jsonb;
 p jsonb; r jsonb; q jsonb; changed jsonb; dealer text; profile text; fixture jsonb; normalized jsonb;
 base_batch uuid; i int; before_work text; before_bookings text; before_ordering text; before_locations text; before_rev bigint;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'Staging only';END IF;
 fixture_email:='snapshot-review-'||actor||'@example.invalid';
 INSERT INTO auth.users(id,aud,role,email,email_confirmed_at,created_at,updated_at) VALUES(actor,'authenticated','authenticated',fixture_email,now(),now(),now());
 INSERT INTO public.pdc_user_roles(email,auth_user_id,role,active,account_status) VALUES(fixture_email,actor,'administrator',true,'approved') ON CONFLICT(email) DO UPDATE SET role='administrator',active=true,account_status='approved',auth_user_id=actor;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor,'email',fixture_email,'role','authenticated')::text,true);
 SELECT md5(coalesce(jsonb_agg(to_jsonb(v) ORDER BY id),'[]'::jsonb)::text) INTO before_work FROM public.vehicle_work_items v;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(v) ORDER BY id),'[]'::jsonb)::text) INTO before_bookings FROM public.workshop_bookings v;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(v) ORDER BY tracking_id),'[]'::jsonb)::text) INTO before_ordering FROM pdc_sales_private.ordering_progress v;
 SELECT md5(coalesce(jsonb_agg(jsonb_build_object('id',v.id,'location',v.current_location,'stage',v.pmb_stage,'status',v.workshop_status,'date',v.date_to_pmb,'qc',v.qc_completed_at) ORDER BY id),'[]'::jsonb)::text) INTO before_locations FROM public.vehicles v;
 -- Include all existing real records unchanged. Only synthetic records are omitted.
 FOREACH dealer IN ARRAY ARRAY['37047','001234'] LOOP
  SELECT rows||coalesce(jsonb_agg(n.raw_evidence ORDER BY n.id),'[]'::jsonb) INTO rows
   FROM public.navision_backend_records n WHERE n.is_current AND n.record_status='current' AND n.source_system='microsoft_navision' AND n.dealer_code=dealer;
  SELECT first_seen_batch_id INTO base_batch FROM public.navision_backend_records WHERE dealer_code=dealer AND is_current LIMIT 1;
  FOR i IN 1..200 LOOP
   fixture:=jsonb_build_object('id','OMIT-'||uid||'-'||dealer||'-'||i,'order','OMIT-'||uid||'-'||dealer||'-'||i,'stock','','batch','','cosi','Yes','consultant','BG','client','Fictional omitted vehicle','navisionRawEvidence',jsonb_build_object('columns',jsonb_build_array(jsonb_build_object('header','Dealer','value',lpad(dealer,6,'0')),jsonb_build_object('header','Order','value','OMIT-'||uid||'-'||dealer||'-'||i),jsonb_build_object('header','COSI','value','Yes'))));
   normalized:=public.navision_backend_normalize_row(fixture);
   INSERT INTO public.navision_backend_records(source_record_id,row_hash,normalized_data,raw_evidence,first_seen_batch_id,last_seen_batch_id,source_system,dealer_code,record_status)
   VALUES(public.navision_backend_source_record_id(fixture),public.navision_backend_row_hash(fixture),normalized,fixture,base_batch,base_batch,'microsoft_navision',dealer,'current');
  END LOOP;
  FOR i IN 1..40 LOOP
   rows:=rows||jsonb_build_array(jsonb_build_object('id','NEW-'||uid||'-'||dealer||'-'||i,'order','NEW-'||uid||'-'||dealer||'-'||i,'stock','','batch','','cosi','Yes','consultant','BG','client','Fictional new vehicle','navisionRawEvidence',jsonb_build_object('columns',jsonb_build_array(jsonb_build_object('header','Dealer','value',lpad(dealer,6,'0')),jsonb_build_object('header','Order','value','NEW-'||uid||'-'||dealer||'-'||i),jsonb_build_object('header','COSI','value','Yes')))));
  END LOOP;
 END LOOP;
 original_rows:=rows;
 p:=public.preview_navision_upload_profile('broome',rows,'fictional-full-export.tsv',NULL);
 IF p#>>'{data,safety,reason}' IS DISTINCT FROM 'suspicious_partial_snapshot' OR (p#>>'{data,counts,missing}')::int<>400 THEN RAISE EXCEPTION 'Omission reproduction failed: %',p#>'{data,counts}'; END IF;
 before_rev:=(p#>>'{data,base_revision}')::bigint;
 r:=public.review_navision_complete_snapshot('broome',rows,'fictional-full-export.tsv',NULL,p#>>'{data,source_hash}','wrong',before_rev);
 IF r->>'code'<>'preview_changed' THEN RAISE EXCEPTION 'Changed preview accepted'; END IF;
 r:=public.review_navision_complete_snapshot('broome',rows,'fictional-full-export.tsv',NULL,p#>>'{data,source_hash}',p#>>'{data,preview_hash}',before_rev-1);
 IF r->>'code'<>'stale_revision' THEN RAISE EXCEPTION 'Stale review accepted'; END IF;
 UPDATE public.pdc_user_roles SET role='importer' WHERE auth_user_id=actor;
 r:=public.review_navision_complete_snapshot('broome',rows,'fictional-full-export.tsv',NULL,p#>>'{data,source_hash}',p#>>'{data,preview_hash}',before_rev);
 IF r->>'code'<>'administrator_required' THEN RAISE EXCEPTION 'Importer review accepted'; END IF;
 UPDATE public.pdc_user_roles SET role='administrator' WHERE auth_user_id=actor;
 r:=public.review_navision_complete_snapshot('broome',rows,'fictional-full-export.tsv',NULL,p#>>'{data,source_hash}',p#>>'{data,preview_hash}',before_rev);
 IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Exact review rejected: %',r; END IF;
 q:=public.preview_navision_upload_profile('broome',rows,'fictional-full-export.tsv',NULL);
 IF q#>>'{data,blocking}' IS DISTINCT FROM 'false' THEN RAISE EXCEPTION 'Reviewed full export still blocked: %',q#>'{data,safety}'; END IF;
 changed:=jsonb_set(rows,ARRAY[(jsonb_array_length(rows)-1)::text,'client'],'"Changed fictional name"'::jsonb);
 r:=public.preview_navision_upload_profile('broome',changed,'fictional-full-export.tsv',NULL);
 IF r#>>'{data,blocking}' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Approval accepted changed file'; END IF;
 -- Review cannot be reused for another actor or changed dealer baseline.
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',gen_random_uuid(),'email','other@example.invalid','role','authenticated')::text,true);
 r:=public.navision_import_safety_assessment((SELECT jsonb_agg(e->'row' ORDER BY (e->>'index')::int) FROM jsonb_array_elements(pdc_navision_upload_private.split_profile(rows,'broome')#>'{groups,37047}') e),'microsoft_navision','37047','broome Navision dealer 37047',jsonb_build_object('counts',jsonb_build_object('total',317,'missing',200,'invalid',0,'conflict',0)));
 IF r->>'blocking'<>'true' THEN RAISE EXCEPTION 'Approval accepted another actor'; END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor,'email',fixture_email,'role','authenticated')::text,true);
 UPDATE public.navision_backend_records SET version=version+1 WHERE source_record_id='OMIT-'||upper(uid)||'-37047-1';
 r:=public.preview_navision_upload_profile('broome',rows,'fictional-full-export.tsv',NULL);
 IF r#>>'{data,blocking}' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Approval accepted changed baseline'; END IF;
 p:=r;
 r:=public.review_navision_complete_snapshot('broome',rows,'fictional-full-export.tsv',NULL,p#>>'{data,source_hash}',p#>>'{data,preview_hash}',(p#>>'{data,base_revision}')::bigint);
 IF r->>'ok'<>'true' THEN RAISE EXCEPTION 'Fresh review failed'; END IF;
 UPDATE pdc_navision_upload_private.complete_snapshot_reviews SET expires_at=clock_timestamp()-interval '1 second' WHERE actor_id=actor;
 p:=public.preview_navision_upload_profile('broome',rows,'fictional-full-export.tsv',NULL);
 IF p#>>'{data,blocking}' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Expired approval accepted'; END IF;
 r:=public.review_navision_complete_snapshot('broome',rows,'fictional-full-export.tsv',NULL,p#>>'{data,source_hash}',p#>>'{data,preview_hash}',(p#>>'{data,base_revision}')::bigint);
 q:=public.preview_navision_upload_profile('broome',rows,'fictional-full-export.tsv',NULL);
 r:=public.apply_navision_upload_profile('broome','review-fixture-'||uid,rows,'fictional-full-export.tsv',NULL,q#>>'{data,source_hash}',q#>>'{data,preview_hash}',(q#>>'{data,base_revision}')::bigint);
 IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Reviewed multi-dealer apply failed: %',r; END IF;
 IF (SELECT count(*) FROM public.navision_backend_records WHERE normalized_data->>'order' LIKE upper('NEW-'||uid)||'%' AND is_current)<>80 THEN RAISE EXCEPTION 'Stockless new orders not imported'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(pdc_sales_private.visibility_source_snapshot(NULL)->'items') x WHERE x->>'order' LIKE upper('OMIT-'||uid)||'%') THEN RAISE EXCEPTION 'Omitted synthetic orders still visible in sales'; END IF;
 IF (SELECT count(*) FROM jsonb_array_elements(pdc_sales_private.visibility_source_snapshot(NULL)->'items') x WHERE x->>'order' LIKE upper('NEW-'||uid)||'-37047-%')<>40 THEN RAISE EXCEPTION 'New stockless orders missing from sales'; END IF;
 IF (SELECT count(*) FROM public.navision_backend_records WHERE source_record_id LIKE upper('OMIT-'||uid)||'%')<>400 THEN RAISE EXCEPTION 'History was deleted'; END IF;
 p:=public.apply_navision_upload_profile('broome','review-fixture-'||uid,rows,'fictional-full-export.tsv',NULL,q#>>'{data,source_hash}',q#>>'{data,preview_hash}',(q#>>'{data,base_revision}')::bigint);
 IF p IS DISTINCT FROM r THEN RAISE EXCEPTION 'Replay changed receipt'; END IF;
 IF before_work IS DISTINCT FROM (SELECT md5(coalesce(jsonb_agg(to_jsonb(v) ORDER BY id),'[]'::jsonb)::text) FROM public.vehicle_work_items v)
  OR before_bookings IS DISTINCT FROM (SELECT md5(coalesce(jsonb_agg(to_jsonb(v) ORDER BY id),'[]'::jsonb)::text) FROM public.workshop_bookings v)
  OR before_ordering IS DISTINCT FROM (SELECT md5(coalesce(jsonb_agg(to_jsonb(v) ORDER BY tracking_id),'[]'::jsonb)::text) FROM pdc_sales_private.ordering_progress v)
  OR before_locations IS DISTINCT FROM (SELECT md5(coalesce(jsonb_agg(jsonb_build_object('id',v.id,'location',v.current_location,'stage',v.pmb_stage,'status',v.workshop_status,'date',v.date_to_pmb,'qc',v.qc_completed_at) ORDER BY id),'[]'::jsonb)::text) FROM public.vehicles v)
 THEN RAISE EXCEPTION 'Upload changed workshop, locations or sales ordering'; END IF;
 IF has_table_privilege('authenticated','pdc_navision_upload_private.complete_snapshot_reviews','SELECT')
  OR has_function_privilege('anon','public.review_navision_complete_snapshot(text,jsonb,text,timestamptz,text,text,bigint)','EXECUTE')
  OR has_function_privilege('authenticated','pdc_navision_upload_private.current_scope_hash(text)','EXECUTE')
 THEN RAISE EXCEPTION 'Private approval or helper exposed'; END IF;
END $test$;
ROLLBACK;
SELECT 'PASS exact full-export review, expiry, actor/content/baseline binding, stale and importer rejection, two-dealer atomic apply, stockless orders, omitted history retention, replay and unchanged operational progress; rolled back' result;