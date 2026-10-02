-- Apply candidate migration first. Fictional fixtures, no external send, all rollback.
BEGIN;
SET LOCAL statement_timeout='120s';
DO $test$
DECLARE a uuid:=gen_random_uuid(); s uuid:=gen_random_uuid(); ar uuid; sr uuid; sp uuid; mail text; smail text;
 rows jsonb; payload jsonb; preview jsonb; applied jsonb; bid uuid; own uuid; built uuid; eta uuid; response jsonb;
 uid text:=gen_random_uuid()::text; before_ops text; before_bookings text; before_ordering text; denied boolean;
 baseline_count integer; queue_before integer; v integer; draft_version integer; status_name text; spoof_bid uuid;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'STAGING only'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='broome_customer_email_import_committed' AND tgdeferrable AND tginitdeferred AND tgrelid='public.navision_import_batches'::regclass) THEN RAISE EXCEPTION 'Missing deferred commit trigger'; END IF;
 IF has_function_privilege('authenticated','pdc_sales_private.customer_email_batch_items(uuid)','EXECUTE')
  OR has_function_privilege('authenticated','pdc_sales_private.customer_email_process_import_queue()','EXECUTE')
  OR has_function_privilege('anon','pdc_sales_private.customer_email_navision_committed()','EXECUTE')
  OR has_table_privilege('authenticated','pdc_sales_private.customer_email_import_queue','SELECT,INSERT,UPDATE,DELETE') THEN RAISE EXCEPTION 'Private capture exposed'; END IF;
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='pdc_sales_private.customer_email_import_queue'::regclass) THEN RAISE EXCEPTION 'Queue RLS missing'; END IF;
 FOREACH status_name IN ARRAY ARRAY['Line Off Complete','Final Inspection','Ready for Shipment','In Transit To WA','In Transit To Eastern States','At Overseas Wharf','Despatched - From TWA','Delivered - At Dealer'] LOOP
  IF pdc_sales_private.customer_email_signals(jsonb_build_object('toyota_status',status_name))->>'vehicle_built' IS DISTINCT FROM 'built' THEN RAISE EXCEPTION 'Physical status dropped built confirmation'; END IF;
 END LOOP;
 IF pdc_sales_private.customer_email_signals('{"toyota_status":"Planned for Production","vin":"EXAMPLE","build_status":"completed"}')->>'vehicle_built' IS NOT NULL THEN RAISE EXCEPTION 'Unconfirmed production inferred as built'; END IF;
 -- Deployment baseline must acknowledge current authoritative source without backfill sends.
 SELECT b.id INTO bid FROM public.navision_import_batches b WHERE source_system='microsoft_navision' AND dealer_code='37047'
  AND status='applied' AND rolled_back_at IS NULL AND receipt->>'ok'='true' ORDER BY result_revision DESC,applied_at DESC,id DESC LIMIT 1;
 IF bid IS NOT NULL AND NOT EXISTS(SELECT 1 FROM pdc_sales_private.customer_email_import_queue WHERE batch_id=bid AND status='processed') THEN RAISE EXCEPTION 'Current deployment baseline missing'; END IF;

 mail:='email-importer-'||a||'@example.invalid';smail:='email-sales-'||s||'@example.invalid';
 INSERT INTO auth.users(id,aud,role,email,email_confirmed_at,created_at,updated_at) VALUES(a,'authenticated','authenticated',mail,now(),now(),now()),(s,'authenticated','authenticated',smail,now(),now(),now());
 -- Auth's existing after-insert trigger creates pending account rows. Approve
 -- only these fictional accounts rather than inserting duplicate email rows.
 UPDATE public.pdc_user_roles SET auth_user_id=a,role='importer',active=true,account_status='approved' WHERE email=mail RETURNING id INTO ar;
 UPDATE public.pdc_user_roles SET auth_user_id=s,role='salesperson',active=true,account_status='approved' WHERE email=smail RETURNING id INTO sr;
 IF ar IS NULL OR sr IS NULL THEN RAISE EXCEPTION 'Fictional Auth role rows were not created'; END IF;
 SELECT id INTO sp FROM public.salespeople WHERE active AND code='BG';
 INSERT INTO pdc_sales_private.account_scopes(user_role_id,salesperson_id,dealer_code,assigned_by) VALUES(sr,sp,'37047',a);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',a,'email',mail,'role','authenticated')::text,true);
 denied:=false;BEGIN PERFORM public.get_broome_sales_snapshot();EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 IF NOT denied THEN RAISE EXCEPTION 'Importer unexpectedly has Sales access';END IF;
 SELECT md5(coalesce(jsonb_agg(jsonb_build_object('id',v.id,'location',v.current_location,'pmb_stage',v.pmb_stage,'workshop_status',v.workshop_status,'date_to_pmb',v.date_to_pmb,'qc_completed_at',v.qc_completed_at) ORDER BY v.id),'[]'::jsonb)::text) INTO before_ops FROM public.vehicles v;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(b) ORDER BY b.id),'[]'::jsonb)::text) INTO before_bookings FROM public.workshop_bookings b;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(p) ORDER BY p.tracking_id),'[]'::jsonb)::text) INTO before_ordering FROM pdc_sales_private.ordering_progress p;
 SELECT coalesce(jsonb_agg(n.raw_evidence ORDER BY n.id),'[]'::jsonb) INTO rows FROM public.navision_backend_records n WHERE n.is_current AND n.record_status='current' AND n.source_system='microsoft_navision' AND n.dealer_code='37047';
 payload:=jsonb_build_object('id','email-commit-'||uid,'order','EMAIL-COMMIT-'||uid,'cosi','Yes','consultant','BG','client','Fictional email test','vehicle','Example Hilux','stock','','batch','','prodMth','10/26','navisionSubLocationDescription','Planned for Production',
  'navisionRawEvidence',jsonb_build_object('columns',jsonb_build_array(jsonb_build_object('header','Dealer','value','37047'),jsonb_build_object('header','Order','value','EMAIL-COMMIT-'||uid),jsonb_build_object('header','COSI','value','Yes'),jsonb_build_object('header','Salesperson','value','BG'))));
 -- First newly imported order establishes baseline. No Sales page RPC observes it.
 preview:=public.preview_navision_upload_profile('broome',rows||jsonb_build_array(payload),'email-fixture.tsv',NULL);
 IF preview#>>'{data,blocking}' IS DISTINCT FROM 'false' THEN RAISE EXCEPTION 'Fixture preview blocked: %',preview->>'code'; END IF;
 applied:=public.apply_navision_upload_profile('broome','email-first-'||uid,rows||jsonb_build_array(payload),'email-fixture.tsv',NULL,preview#>>'{data,source_hash}',preview#>>'{data,preview_hash}',(preview#>>'{data,base_revision}')::bigint);
 IF applied->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'First fixture import failed: %',applied->>'code'; END IF;
 SELECT id INTO own FROM public.navision_backend_records WHERE dealer_code='37047' AND normalized_data->>'order'=upper('EMAIL-COMMIT-'||uid);
 IF EXISTS(SELECT 1 FROM pdc_sales_private.customer_email_observations WHERE tracking_id=own) THEN RAISE EXCEPTION 'Observer ran before transaction-end work'; END IF;
 EXECUTE 'SET CONSTRAINTS broome_customer_email_import_committed IMMEDIATE';
 EXECUTE 'SET CONSTRAINTS broome_customer_email_import_committed DEFERRED';
 IF NOT EXISTS(SELECT 1 FROM pdc_sales_private.customer_email_observations WHERE tracking_id=own)
  OR EXISTS(SELECT 1 FROM pdc_sales_private.customer_email_drafts WHERE tracking_id=own AND status<>'baseline') THEN RAISE EXCEPTION 'First observation failed baseline rule'; END IF;

 -- A changed production month and then built confirmation are captured offline.
 FOR v IN 1..3 LOOP
  payload:=payload||CASE v WHEN 1 THEN jsonb_build_object('prodMth','11/26') WHEN 2 THEN jsonb_build_object('navisionSubLocationDescription','Line Off Complete') ELSE jsonb_build_object('navisionSubLocationDescription','In Transit To WA','navisionKewdaleEta','04/11/2026') END;
  preview:=public.preview_navision_upload_profile('broome',rows||jsonb_build_array(payload),'email-step.tsv',NULL);
  applied:=public.apply_navision_upload_profile('broome','email-step-'||v||'-'||uid,rows||jsonb_build_array(payload),'email-step.tsv',NULL,preview#>>'{data,source_hash}',preview#>>'{data,preview_hash}',(preview#>>'{data,base_revision}')::bigint);
  IF applied->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Offline fixture step failed: %',applied->>'code'; END IF;
  -- Keep built and shipping imports deferred together to prove that the hook
  -- captures each immutable batch, rather than only the final backend snapshot.
  IF v<>2 THEN
   EXECUTE 'SET CONSTRAINTS broome_customer_email_import_committed IMMEDIATE';
   EXECUTE 'SET CONSTRAINTS broome_customer_email_import_committed DEFERRED';
  END IF;
  IF v=1 AND (SELECT count(*) FROM pdc_sales_private.customer_email_drafts WHERE tracking_id=own AND template_kind='production_planned' AND status='draft')<>1 THEN RAISE EXCEPTION 'Offline production month change missed'; END IF;
  IF v=2 AND EXISTS(SELECT 1 FROM pdc_sales_private.customer_email_drafts WHERE tracking_id=own AND template_kind='vehicle_built') THEN RAISE EXCEPTION 'Built observer ran before deferred boundary'; END IF;
  IF v=3 AND (SELECT count(*) FROM pdc_sales_private.customer_email_drafts WHERE tracking_id=own AND template_kind='vehicle_built' AND status='draft')<>1 THEN RAISE EXCEPTION 'Built draft lost when shipment confirmed'; END IF;
 END LOOP;
 SELECT id INTO built FROM pdc_sales_private.customer_email_drafts WHERE tracking_id=own AND template_kind='vehicle_built';
 SELECT id INTO eta FROM pdc_sales_private.customer_email_drafts WHERE tracking_id=own AND template_kind='perth_eta' AND event_key='2026-11-04';
 IF eta IS NULL OR EXISTS(SELECT 1 FROM pdc_sales_private.customer_email_drafts WHERE tracking_id=own AND status IN ('prepared','sent')) THEN RAISE EXCEPTION 'Offline ETA draft missing or sent'; END IF;
 baseline_count:=(SELECT count(*) FROM pdc_sales_private.customer_email_drafts WHERE tracking_id=own);
 -- Idempotent replay must not add a job or a duplicate milestone.
 SELECT count(*) INTO queue_before FROM pdc_sales_private.customer_email_import_queue;
 response:=public.apply_navision_upload_profile('broome','email-step-3-'||uid,rows||jsonb_build_array(payload),'email-step.tsv',NULL,preview#>>'{data,source_hash}',preview#>>'{data,preview_hash}',(preview#>>'{data,base_revision}')::bigint);
 EXECUTE 'SET CONSTRAINTS broome_customer_email_import_committed IMMEDIATE';
 EXECUTE 'SET CONSTRAINTS broome_customer_email_import_committed DEFERRED';
 IF response IS DISTINCT FROM applied OR queue_before<>(SELECT count(*) FROM pdc_sales_private.customer_email_import_queue)
  OR baseline_count<>(SELECT count(*) FROM pdc_sales_private.customer_email_drafts WHERE tracking_id=own) THEN RAISE EXCEPTION 'Replay duplicated capture'; END IF;

 -- Fail the observer only. Authoritative import succeeds; retry keeps exact facts.
 EXECUTE format('CREATE FUNCTION pg_temp.email_capture_failure() RETURNS trigger LANGUAGE plpgsql AS $fail$ BEGIN IF NEW.tracking_id=%L::uuid AND NEW.template_kind=''perth_eta'' AND NEW.event_key=''2026-11-05'' THEN RAISE EXCEPTION ''Fictional observer failure''; END IF; RETURN NEW; END $fail$',own);
 CREATE TRIGGER email_capture_test_failure BEFORE INSERT ON pdc_sales_private.customer_email_drafts FOR EACH ROW EXECUTE FUNCTION pg_temp.email_capture_failure();
 payload:=payload||jsonb_build_object('navisionKewdaleEta','05/11/2026');
 preview:=public.preview_navision_upload_profile('broome',rows||jsonb_build_array(payload),'email-failure.tsv',NULL);
 applied:=public.apply_navision_upload_profile('broome','email-failure-'||uid,rows||jsonb_build_array(payload),'email-failure.tsv',NULL,preview#>>'{data,source_hash}',preview#>>'{data,preview_hash}',(preview#>>'{data,base_revision}')::bigint);
 EXECUTE 'SET CONSTRAINTS broome_customer_email_import_committed IMMEDIATE';
 EXECUTE 'SET CONSTRAINTS broome_customer_email_import_committed DEFERRED';
 IF applied->>'ok' IS DISTINCT FROM 'true' OR NOT EXISTS(SELECT 1 FROM public.navision_backend_records WHERE id=own AND normalized_data->>'navisionKewdaleEta'='05/11/2026')
  OR NOT EXISTS(SELECT 1 FROM pdc_sales_private.customer_email_import_queue q WHERE q.status='failed' AND q.items @> jsonb_build_array(jsonb_build_object('tracking_id',own,'kewdale_eta','05/11/2026'))) THEN RAISE EXCEPTION 'Observer failure broke import or lost retry evidence'; END IF;
 -- Opening review and saving another draft cannot leap over the failed ETA job.
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',s,'email',smail,'role','authenticated')::text,true);
 response:=public.get_broome_customer_emails();
 IF coalesce((response->>'capture_pending')::integer,0)<1 THEN RAISE EXCEPTION 'Failed capture not surfaced for review retry'; END IF;
 PERFORM public.save_broome_customer_email(built,'save','{}',1);
 IF (SELECT signals->>'perth_eta' FROM pdc_sales_private.customer_email_observations WHERE tracking_id=own) IS DISTINCT FROM '2026-11-04' THEN RAISE EXCEPTION 'Review/save skipped retained failed milestone'; END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',a,'email',mail,'role','authenticated')::text,true);
 DROP TRIGGER email_capture_test_failure ON pdc_sales_private.customer_email_drafts;
 PERFORM pdc_sales_private.customer_email_process_import_queue();
 IF (SELECT count(*) FROM pdc_sales_private.customer_email_drafts WHERE tracking_id=own AND template_kind='perth_eta' AND event_key='2026-11-05' AND status='draft')<>1
  OR NOT EXISTS(SELECT 1 FROM pdc_sales_private.customer_email_drafts WHERE id=eta AND status='superseded') THEN RAISE EXCEPTION 'Retry/obsolete ETA protection failed'; END IF;

 -- The existing authenticated salesperson review path and optimistic versions apply.
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',s,'email',smail,'role','authenticated')::text,true);
 response:=public.get_broome_customer_emails();
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(response->'drafts') e WHERE e->>'id'=built::text) THEN RAISE EXCEPTION 'Own built draft unavailable for review'; END IF;
 PERFORM pdc_sales_private.customer_email_observe(jsonb_build_array(jsonb_build_object('tracking_id',own,'identity_conflict',true,'toyota_status','Planned for Production','production_month','12/26','kewdale_eta','01/01/2027')));
 IF NOT EXISTS(SELECT 1 FROM pdc_sales_private.customer_email_drafts WHERE id=built AND status='draft')
  OR (SELECT signals->>'perth_eta' FROM pdc_sales_private.customer_email_observations WHERE tracking_id=own) IS DISTINCT FROM '2026-11-05' THEN RAISE EXCEPTION 'Identity conflict changed safe milestones'; END IF;
 SELECT version INTO draft_version FROM pdc_sales_private.customer_email_drafts WHERE id=built;
 response:=public.save_broome_customer_email(built,'save','{"recipient":"customer@example.invalid","subject":"Example vehicle update","body":"Reviewed fictional draft"}',draft_version);
 denied:=false;BEGIN PERFORM public.save_broome_customer_email(built,'prepare','{"recipient":"customer@example.invalid","subject":"Example vehicle update","body":"Reviewed fictional draft"}',draft_version);EXCEPTION WHEN serialization_failure THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Stale version accepted'; END IF;
 denied:=false;BEGIN PERFORM public.save_broome_customer_email(eta,'prepare','{"recipient":"customer@example.invalid","subject":"Old ETA","body":"Reviewed fictional draft"}',1);EXCEPTION WHEN OTHERS THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Obsolete ETA accepted'; END IF;

 -- Reassign the source order; its prior salesperson loses draft read/write scope.
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',a,'email',mail,'role','authenticated')::text,true);
 payload:=payload||jsonb_build_object('consultant','PM');payload:=jsonb_set(payload,'{navisionRawEvidence,columns,3,value}','"PM"');
 preview:=public.preview_navision_upload_profile('broome',rows||jsonb_build_array(payload),'email-reassignment.tsv',NULL);
 applied:=public.apply_navision_upload_profile('broome','email-reassignment-'||uid,rows||jsonb_build_array(payload),'email-reassignment.tsv',NULL,preview#>>'{data,source_hash}',preview#>>'{data,preview_hash}',(preview#>>'{data,base_revision}')::bigint);
 EXECUTE 'SET CONSTRAINTS broome_customer_email_import_committed IMMEDIATE';
 EXECUTE 'SET CONSTRAINTS broome_customer_email_import_committed DEFERRED';
 IF applied->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Fixture reassignment failed'; END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',s,'email',smail,'role','authenticated','user_metadata',jsonb_build_object('role','administrator'))::text,true);
 response:=public.get_broome_customer_emails();
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(response->'drafts') e WHERE e->>'tracking_id'=own::text) THEN RAISE EXCEPTION 'Reassigned draft leaked'; END IF;
 denied:=false;BEGIN PERFORM public.save_broome_customer_email(built,'prepare','{"recipient":"customer@example.invalid","subject":"Example vehicle update","body":"Reviewed fictional draft"}',draft_version+1);EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Reassignment or metadata spoof bypassed scope'; END IF;
 -- Complete-looking receipts still cannot make a salesperson/metadata claim an
 -- authorised importer. Signed-out role claims cannot impersonate the real actor.
 FOR v IN 1..2 LOOP
  spoof_bid:=gen_random_uuid();
  IF v=2 THEN PERFORM set_config('request.jwt.claims','{"role":"administrator","user_metadata":{"role":"administrator"}}',true); END IF;
  INSERT INTO public.navision_import_batches(id,idempotency_key,request_hash,source_name,source_hash,preview_hash,base_revision,result_revision,total_rows,receipt,actor_id,actor_email,source_system,dealer_code)
  VALUES(spoof_bid,'email-spoof-'||v||'-'||uid,repeat('a',64),'email-spoof.tsv',repeat('b',64),repeat('c',64),1,1,0,jsonb_build_object('ok',true,'data',jsonb_build_object('batch_id',spoof_bid)),CASE v WHEN 1 THEN s ELSE a END,CASE v WHEN 1 THEN smail ELSE mail END,'microsoft_navision','37047');
  INSERT INTO public.navision_operation_receipts(operation_kind,idempotency_key,request_hash,batch_id,response,actor_id,actor_email)
  VALUES('apply','email-spoof-'||v||'-'||uid,repeat('a',64),spoof_bid,jsonb_build_object('ok',true),CASE v WHEN 1 THEN s ELSE a END,CASE v WHEN 1 THEN smail ELSE mail END);
  EXECUTE 'SET CONSTRAINTS broome_customer_email_import_committed IMMEDIATE';
  EXECUTE 'SET CONSTRAINTS broome_customer_email_import_committed DEFERRED';
  IF EXISTS(SELECT 1 FROM pdc_sales_private.customer_email_import_queue WHERE batch_id=spoof_bid) THEN RAISE EXCEPTION 'Spoofed role captured untrusted import'; END IF;
 END LOOP;
 PERFORM set_config('request.jwt.claims','{}',true);denied:=false;BEGIN PERFORM public.get_broome_customer_emails();EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Signed-out draft access allowed'; END IF;
 IF before_ops IS DISTINCT FROM (SELECT md5(coalesce(jsonb_agg(jsonb_build_object('id',v.id,'location',v.current_location,'pmb_stage',v.pmb_stage,'workshop_status',v.workshop_status,'date_to_pmb',v.date_to_pmb,'qc_completed_at',v.qc_completed_at) ORDER BY v.id),'[]'::jsonb)::text) FROM public.vehicles v)
  OR before_bookings IS DISTINCT FROM (SELECT md5(coalesce(jsonb_agg(to_jsonb(b) ORDER BY b.id),'[]'::jsonb)::text) FROM public.workshop_bookings b)
  OR before_ordering IS DISTINCT FROM (SELECT md5(coalesce(jsonb_agg(to_jsonb(p) ORDER BY p.tracking_id),'[]'::jsonb)::text) FROM pdc_sales_private.ordering_progress p) THEN RAISE EXCEPTION 'Capture affected PDC or ordering'; END IF;
END $test$;
ROLLBACK;
SELECT 'PASS offline committed imports, baseline, dedup, importer isolation, observer retry, current review/scope/version checks and PDC fingerprints; all rolled back' result;
