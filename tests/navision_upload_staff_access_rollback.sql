-- Exercise the actual public RPC as authenticated staff, not as postgres.
-- Each apply and all synthetic evidence are rolled back. No vehicles or
-- bookings are created, started, completed or changed permanently.
BEGIN;
SET LOCAL statement_timeout='180s';
DO $verify$
DECLARE actor uuid; email text; staff_role text; profile text; rows jsonb;
 p jsonb; result jsonb; replay jsonb; checks jsonb:='[]'; nonce text:=gen_random_uuid()::text;
 original_revision bigint;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'Staging required'; END IF;
 SELECT revision INTO original_revision FROM public.navision_backend_revision WHERE singleton;
 FOREACH staff_role IN ARRAY ARRAY['administrator','importer'] LOOP
  SELECT u.auth_user_id,u.email INTO actor,email FROM public.pdc_user_roles u
   WHERE u.active AND u.account_status='approved' AND u.role::text=staff_role AND u.auth_user_id IS NOT NULL
   ORDER BY (u.email='craig.watson@broometoyota.com.au') DESC,u.email LIMIT 1;
  IF actor IS NULL THEN RAISE EXCEPTION 'Approved % test identity missing',staff_role; END IF;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor,'email',email,'role','authenticated')::text,true);
  FOREACH profile IN ARRAY ARRAY['broome','pilbara'] LOOP
   SELECT jsonb_agg(b.raw_evidence ORDER BY b.id) INTO rows FROM public.navision_backend_records b
    WHERE b.is_current AND b.record_status='current' AND b.source_system='microsoft_navision'
    AND b.dealer_code=ANY(CASE profile WHEN 'broome' THEN ARRAY['37047'] ELSE ARRAY['14450','001234','002345'] END);
   EXECUTE 'SET LOCAL ROLE authenticated';
   p:=public.preview_navision_upload_profile(profile,rows,'staff-access-verification.tsv',NULL);
   EXECUTE 'RESET ROLE';
   IF p->>'ok' IS DISTINCT FROM 'true' OR p#>>'{data,blocking}' IS DISTINCT FROM 'false'
    OR p#>>'{data,preview_hash}' IS NULL OR p#>>'{data,source_hash}' IS NULL THEN
    RAISE EXCEPTION '% % preview failed: %',staff_role,profile,p->>'code';
   END IF;
   checks:=checks||jsonb_build_array(jsonb_build_object('check','preview','role',staff_role,'profile',profile,'source_rows',jsonb_array_length(rows)));
   IF (staff_role='administrator' AND profile='broome') OR (staff_role='importer' AND profile='pilbara') THEN
    rows:=rows||jsonb_build_array(jsonb_build_object('id','staff-access-'||profile||'-'||nonce,
     'order','staff-access-'||profile||'-'||nonce,'cosi','Yes','consultant','BG','client','Fictional staff upload test','stock','','batch','',
     'navisionRawEvidence',jsonb_build_object('columns',jsonb_build_array(
      jsonb_build_object('header','Dealer','value',CASE profile WHEN 'broome' THEN '037047' ELSE '002345' END),
      jsonb_build_object('header','Order','value','staff-access-'||profile||'-'||nonce),
      jsonb_build_object('header','COSI','value','Yes'),jsonb_build_object('header','Salesperson','value','BG')))));
    BEGIN
     EXECUTE 'SET LOCAL ROLE authenticated';
     p:=public.preview_navision_upload_profile(profile,rows,'staff-access-verification.tsv',NULL);
     IF p#>>'{data,blocking}' IS DISTINCT FROM 'false' THEN RAISE EXCEPTION 'Apply fixture preview blocked: %',p->>'code'; END IF;
     result:=public.apply_navision_upload_profile(profile,'wrong-hash-'||profile||nonce,rows,'staff-access-verification.tsv',NULL,
      p#>>'{data,source_hash}','wrong-preview',(p#>>'{data,base_revision}')::bigint);
     IF result->>'code'<>'preview_changed' THEN RAISE EXCEPTION 'Changed preview accepted: %',result->>'code'; END IF;
     result:=public.apply_navision_upload_profile(profile,'wrong-source-'||profile||nonce,rows,'staff-access-verification.tsv',NULL,
      'wrong-source',p#>>'{data,preview_hash}',(p#>>'{data,base_revision}')::bigint);
     IF result->>'code'<>'source_changed' THEN RAISE EXCEPTION 'Changed source accepted: %',result->>'code'; END IF;
     result:=public.apply_navision_upload_profile(profile,'stale-'||profile||nonce,rows,'staff-access-verification.tsv',NULL,
      p#>>'{data,source_hash}',p#>>'{data,preview_hash}',(p#>>'{data,base_revision}')::bigint-1);
     IF result->>'code'<>'stale_revision' THEN RAISE EXCEPTION 'Stale preview accepted: %',result->>'code'; END IF;
     result:=public.apply_navision_upload_profile(profile,'staff-apply-'||profile||nonce,rows,'staff-access-verification.tsv',NULL,
      p#>>'{data,source_hash}',p#>>'{data,preview_hash}',(p#>>'{data,base_revision}')::bigint);
     IF result->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION '% % apply failed: %',staff_role,profile,result->>'code'; END IF;
     replay:=public.apply_navision_upload_profile(profile,'staff-apply-'||profile||nonce,rows,'staff-access-verification.tsv',NULL,
      p#>>'{data,source_hash}',p#>>'{data,preview_hash}',(p#>>'{data,base_revision}')::bigint);
     IF replay IS DISTINCT FROM result THEN RAISE EXCEPTION 'Upload replay changed'; END IF;
     SET CONSTRAINTS ALL IMMEDIATE;
     RAISE EXCEPTION 'rollback verified apply' USING errcode='ZX001';
    EXCEPTION WHEN SQLSTATE 'ZX001' THEN
     EXECUTE 'RESET ROLE';
     checks:=checks||jsonb_build_array(jsonb_build_object('check','apply_replay_hash_and_stale_guards','role',staff_role,'profile',profile,'rolled_back',true));
    END;
   END IF;
  END LOOP;
 END LOOP;
 -- Approved non-import staff, disabled staff, signed-out and mismatched claims
 -- must stay denied even though the SQL execute grant is restored.
 FOREACH staff_role IN ARRAY ARRAY['operator','disabled','signed_out','mismatched_email'] LOOP
  SELECT u.auth_user_id,u.email INTO actor,email FROM public.pdc_user_roles u
   WHERE u.auth_user_id IS NOT NULL AND
    CASE WHEN staff_role='operator' THEN u.role::text='operator' AND u.active AND u.account_status='approved'
     WHEN staff_role='disabled' THEN NOT u.active AND u.account_status='disabled'
     ELSE u.role::text='administrator' AND u.active AND u.account_status='approved' END
   ORDER BY u.email LIMIT 1;
  IF actor IS NULL THEN RAISE EXCEPTION 'Denied actor fixture missing: %',staff_role; END IF;
  PERFORM set_config('request.jwt.claims',CASE WHEN staff_role='signed_out' THEN '{}' ELSE
   jsonb_build_object('sub',actor,'email',CASE WHEN staff_role='mismatched_email' THEN 'mismatch@example.invalid' ELSE email END,'role','authenticated')::text END,true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  p:=public.preview_navision_upload_profile('broome','[]'::jsonb,'denied-check',NULL);
  result:=public.apply_navision_upload_profile('broome','denied-'||nonce,'[]'::jsonb,'denied-check',NULL,'wrong','wrong',original_revision);
  EXECUTE 'RESET ROLE';
  IF p->>'code' IS DISTINCT FROM 'unauthorized' OR result->>'code' IS DISTINCT FROM 'unauthorized' THEN RAISE EXCEPTION 'Denied actor accepted: %',staff_role; END IF;
  checks:=checks||jsonb_build_array(jsonb_build_object('check','preview_and_apply_denied','actor_case',staff_role));
 END LOOP;
 IF has_function_privilege('anon','public.preview_navision_upload_profile(text,jsonb,text,timestamptz)','EXECUTE')
  OR has_function_privilege('anon','pdc_navision_upload_private.preview_profile(text,jsonb,text,timestamptz)','EXECUTE')
  OR has_function_privilege('authenticated','pdc_navision_upload_private.split_profile(jsonb,text)','EXECUTE') THEN RAISE EXCEPTION 'Private or anonymous access expanded'; END IF;
 IF EXISTS(SELECT 1 FROM public.navision_backend_records WHERE normalized_data->>'order' IN(
   upper('staff-access-broome-'||nonce),upper('staff-access-pilbara-'||nonce)))
  OR EXISTS(SELECT 1 FROM pdc_navision_combined_private.receipts WHERE idempotency_key IN(
   'staff-apply-broome'||nonce,'staff-apply-pilbara'||nonce))
  OR EXISTS(SELECT 1 FROM pdc_navision_delivery_private.booking_cancellations WHERE transaction_id=txid_current()) THEN
  RAISE EXCEPTION 'Test import or cancellation evidence escaped rollback';
 END IF;
 checks:=checks||jsonb_build_array(jsonb_build_object('check','no_test_imports_receipts_or_cancellations_retained'));
 PERFORM set_config('pdc.upload_staff_access_verification',jsonb_build_object('passed',jsonb_array_length(checks),'checks',checks)::text,true);
END $verify$;
SELECT current_setting('pdc.upload_staff_access_verification')::jsonb AS verification;
ROLLBACK;
