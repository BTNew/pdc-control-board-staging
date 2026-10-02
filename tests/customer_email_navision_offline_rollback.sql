-- Staging-only fictional fixtures. Run each feature file separately and serially.
-- Existing current dealer rows are retained; real approved preview/apply calls.
BEGIN;
SET LOCAL statement_timeout='60s';

CREATE FUNCTION pg_temp.email_import(p_base_rows jsonb,p_extra jsonb,p_key text,p_flush boolean DEFAULT true)
RETURNS jsonb LANGUAGE plpgsql AS $fixture$
DECLARE preview jsonb; applied jsonb; all_rows jsonb:=p_base_rows||p_extra;
BEGIN
 preview:=public.preview_navision_upload_profile('broome',all_rows,'email-feature.tsv',NULL);
 IF preview->>'ok' IS DISTINCT FROM 'true' OR preview#>>'{data,blocking}' IS DISTINCT FROM 'false' THEN RAISE EXCEPTION 'Fixture preview blocked: %',preview->>'code'; END IF;
 applied:=public.apply_navision_upload_profile('broome',p_key,all_rows,'email-feature.tsv',NULL,preview#>>'{data,source_hash}',preview#>>'{data,preview_hash}',(preview#>>'{data,base_revision}')::bigint);
 IF applied->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Fixture import failed: %',applied->>'code'; END IF;
 IF p_flush THEN
  EXECUTE 'SET CONSTRAINTS broome_customer_email_import_committed IMMEDIATE';
  EXECUTE 'SET CONSTRAINTS broome_customer_email_import_committed DEFERRED';
 END IF;
 RETURN jsonb_build_object('preview',preview,'applied',applied);
END $fixture$;

CREATE FUNCTION pg_temp.email_item(p_id uuid,p_payload jsonb) RETURNS jsonb LANGUAGE sql AS $fixture$
 SELECT jsonb_build_object('tracking_id',p_id,'identity_conflict',false,'vehicle',p_payload->>'vehicle',
  'salesperson_name','Example Staff','production_month',p_payload->>'prodMth',
  'toyota_status',p_payload->>'navisionSubLocationDescription','kewdale_eta',coalesce(p_payload->>'navisionKewdaleEta',''));
$fixture$;

CREATE FUNCTION pg_temp.email_ops() RETURNS jsonb LANGUAGE sql AS $fixture$
 SELECT jsonb_build_object(
 'vehicles',(SELECT md5(coalesce(jsonb_agg(jsonb_build_object('id',v.id,'location',v.current_location,'pmb_stage',v.pmb_stage,'workshop_status',v.workshop_status,'date_to_pmb',v.date_to_pmb,'qc_completed_at',v.qc_completed_at) ORDER BY v.id),'[]'::jsonb)::text) FROM public.vehicles v),
 'bookings',(SELECT md5(coalesce(jsonb_agg(to_jsonb(b) ORDER BY b.id),'[]'::jsonb)::text) FROM public.workshop_bookings b),
 'ordering',(SELECT md5(coalesce(jsonb_agg(to_jsonb(p) ORDER BY p.tracking_id),'[]'::jsonb)::text) FROM pdc_sales_private.ordering_progress p));
$fixture$;

DO $test$
DECLARE a uuid:=gen_random_uuid(); s uuid:=gen_random_uuid(); ar uuid; sr uuid; sp uuid; mail text; smail text;
 rows jsonb; payload jsonb; fresh_payload jsonb; result jsonb; response jsonb; bid uuid; own uuid:=gen_random_uuid(); fresh uuid; built uuid; eta uuid;
 uid text:=gen_random_uuid()::text; before_ops jsonb; denied boolean; total_before integer; jobs_before integer; draft_version integer; v integer; status_name text; spoof_bid uuid;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'STAGING only'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgname='broome_customer_email_import_committed' AND tgdeferrable AND tginitdeferred AND tgrelid='public.navision_import_batches'::regclass) THEN RAISE EXCEPTION 'Missing deferred commit trigger'; END IF;
 IF has_function_privilege('authenticated','pdc_sales_private.customer_email_batch_items(uuid)','EXECUTE')
  OR has_function_privilege('authenticated','pdc_sales_private.customer_email_process_import_queue()','EXECUTE')
  OR has_function_privilege('anon','pdc_sales_private.customer_email_navision_committed()','EXECUTE')
  OR has_table_privilege('authenticated','pdc_sales_private.customer_email_import_queue','SELECT,INSERT,UPDATE,DELETE') THEN RAISE EXCEPTION 'Private capture exposed'; END IF;
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='pdc_sales_private.customer_email_import_queue'::regclass) THEN RAISE EXCEPTION 'Queue RLS missing'; END IF;
 SELECT b.id INTO bid FROM public.navision_import_batches b WHERE source_system='microsoft_navision' AND dealer_code='37047'
  AND status='applied' AND rolled_back_at IS NULL AND receipt->>'ok'='true' ORDER BY result_revision DESC,applied_at DESC,id DESC LIMIT 1;
 IF bid IS NULL OR NOT EXISTS(SELECT 1 FROM pdc_sales_private.customer_email_import_queue WHERE batch_id=bid AND status='processed') THEN RAISE EXCEPTION 'Current authoritative deployment baseline missing'; END IF;
 mail:='email-importer-'||a||'@example.invalid';smail:='email-sales-'||s||'@example.invalid';
 INSERT INTO auth.users(id,aud,role,email,email_confirmed_at,created_at,updated_at) VALUES(a,'authenticated','authenticated',mail,now(),now(),now()),(s,'authenticated','authenticated',smail,now(),now(),now());
 UPDATE public.pdc_user_roles SET auth_user_id=a,role='importer',active=true,account_status='approved' WHERE email=mail RETURNING id INTO ar;
 UPDATE public.pdc_user_roles SET auth_user_id=s,role='salesperson',active=true,account_status='approved' WHERE email=smail RETURNING id INTO sr;
 IF ar IS NULL OR sr IS NULL THEN RAISE EXCEPTION 'Fictional Auth role rows were not created'; END IF;
 SELECT id INTO sp FROM public.salespeople WHERE active AND code='BG';
 INSERT INTO pdc_sales_private.account_scopes(user_role_id,salesperson_id,dealer_code,assigned_by) VALUES(sr,sp,'37047',a);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',a,'email',mail,'role','authenticated')::text,true);
 denied:=false;BEGIN PERFORM public.get_broome_sales_snapshot();EXCEPTION WHEN insufficient_privilege THEN denied:=true;END;
 IF NOT denied THEN RAISE EXCEPTION 'Importer unexpectedly has Sales access';END IF;
 before_ops:=pg_temp.email_ops();
 -- Capture real rows before adding a fictional pre-existing source order.
 SELECT coalesce(jsonb_agg(n.raw_evidence ORDER BY n.id),'[]'::jsonb) INTO rows FROM public.navision_backend_records n WHERE n.is_current AND n.record_status='current' AND n.source_system='microsoft_navision' AND n.dealer_code='37047';
 payload:=jsonb_build_object('id','email-commit-'||uid,'order','EMAIL-COMMIT-'||uid,'dealer_code','37047','cosi','Yes','consultant','BG','client','Fictional email test','vehicle','Example Hilux','stock','','batch','','prodMth','10/26','navisionSubLocationDescription','Planned for Production',
  'navisionRawEvidence',jsonb_build_object('columns',jsonb_build_array(jsonb_build_object('header','Dealer','value','37047'),jsonb_build_object('header','Order','value','EMAIL-COMMIT-'||uid),jsonb_build_object('header','COSI','value','Yes'),jsonb_build_object('header','Salesperson','value','BG'))));
 -- Seed only a fictional previously known order under the current valid receipt.
 -- No role/import guard is changed; all later transitions use real approved imports.
 INSERT INTO public.navision_backend_records(id,source_system,dealer_code,source_record_id,row_hash,normalized_data,raw_evidence,first_seen_batch_id,last_seen_batch_id,record_status,is_current)
 VALUES(own,'microsoft_navision','37047',public.navision_backend_source_record_id(payload),repeat('0',64),payload,payload,bid,bid,'current',true);
 PERFORM pdc_sales_private.customer_email_observe(jsonb_build_array(pg_temp.email_item(own,payload)));
 payload:=payload||jsonb_build_object('navisionSubLocationDescription','Line Off Complete');
 PERFORM pg_temp.email_import(rows,jsonb_build_array(payload),'email-built-'||uid,false);
 IF EXISTS(SELECT 1 FROM pdc_sales_private.customer_email_drafts WHERE tracking_id=own AND template_kind='vehicle_built') THEN RAISE EXCEPTION 'Built observer ran before deferred boundary'; END IF;
 payload:=payload||jsonb_build_object('navisionSubLocationDescription','In Transit To WA','navisionKewdaleEta','04/11/2026');
 result:=pg_temp.email_import(rows,jsonb_build_array(payload),'email-shipping-'||uid,true);
 IF NOT EXISTS(SELECT 1 FROM public.navision_backend_records WHERE id=own AND normalized_data->>'order'=upper('EMAIL-COMMIT-'||uid)) THEN RAISE EXCEPTION 'Seeded order identity changed'; END IF;
 IF (SELECT count(*) FROM pdc_sales_private.customer_email_drafts WHERE tracking_id=own AND template_kind='vehicle_built' AND status='draft')<>1 THEN RAISE EXCEPTION 'Deferred built milestone lost during shipping'; END IF;
 IF (SELECT count(*) FROM pdc_sales_private.customer_email_drafts WHERE tracking_id=own AND template_kind='perth_eta' AND event_key='2026-11-04' AND status='draft')<>1 THEN RAISE EXCEPTION 'Offline Perth ETA draft missing'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_sales_private.customer_email_drafts WHERE tracking_id=own AND status IN ('prepared','sent')) THEN RAISE EXCEPTION 'Import prepared or sent customer mail'; END IF;
 SELECT count(*) INTO total_before FROM pdc_sales_private.customer_email_drafts WHERE tracking_id=own;
 SELECT count(*) INTO jobs_before FROM pdc_sales_private.customer_email_import_queue;
 response:=public.apply_navision_upload_profile('broome','email-shipping-'||uid,rows||jsonb_build_array(payload),'email-feature.tsv',NULL,result#>>'{preview,data,source_hash}',result#>>'{preview,data,preview_hash}',(result#>>'{preview,data,base_revision}')::bigint);
 EXECUTE 'SET CONSTRAINTS broome_customer_email_import_committed IMMEDIATE';
 EXECUTE 'SET CONSTRAINTS broome_customer_email_import_committed DEFERRED';
 IF response IS DISTINCT FROM result->'applied' OR jobs_before<>(SELECT count(*) FROM pdc_sales_private.customer_email_import_queue)
  OR total_before<>(SELECT count(*) FROM pdc_sales_private.customer_email_drafts WHERE tracking_id=own) THEN RAISE EXCEPTION 'Replay duplicated capture'; END IF;

 IF before_ops IS DISTINCT FROM pg_temp.email_ops() THEN RAISE EXCEPTION 'Capture affected PDC operational fields, bookings or ordering'; END IF;
END $test$;
ROLLBACK;
SELECT 'PASS deferred built/shipping/ETA capture, unique-event replay and PDC fingerprints; all fictional writes rolled back' result;
