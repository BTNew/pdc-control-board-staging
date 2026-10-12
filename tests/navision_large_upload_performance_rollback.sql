-- Match the reported Pilbara volume: 1,063 dealer rows plus 83 head-office
-- rows, 8 new stockless orders, 1,138 changed rows and 196 missing rows.
-- Synthetic orders and every real-source update are transaction-local.
BEGIN;
SET LOCAL statement_timeout='120s';
DO $verify$
DECLARE actor uuid; email text; rows jsonb; p jsonb; result jsonb; replay jsonb;
 started timestamptz; preview_ms numeric; apply_ms numeric; constraints_ms numeric;
 nonce text:=gen_random_uuid()::text; stamp text:=clock_timestamp()::text; i integer; report jsonb;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'Staging required'; END IF;
 SELECT u.auth_user_id,u.email INTO actor,email FROM public.pdc_user_roles u
 WHERE u.email='craig.watson@broometoyota.com.au' AND u.active AND u.account_status='approved' AND u.role::text='administrator';
 IF actor IS NULL THEN RAISE EXCEPTION 'Approved test actor missing'; END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor,'email',email,'role','authenticated')::text,true);
 SELECT jsonb_agg(jsonb_set(b.raw_evidence,'{importedAt}',to_jsonb(stamp),true) ORDER BY b.id) INTO rows FROM (
  (SELECT id,raw_evidence FROM public.navision_backend_records WHERE source_system='microsoft_navision' AND is_current AND record_status='current' AND dealer_code='14450' ORDER BY id LIMIT 1055)
  UNION ALL
  (SELECT id,raw_evidence FROM public.navision_backend_records WHERE source_system='microsoft_navision' AND is_current AND record_status='current' AND dealer_code IN('001234','002345'))
 ) b;
 FOR i IN 1..8 LOOP
  rows:=rows||jsonb_build_array(jsonb_build_object('id','TOYOTA-ORDER-PERFORMANCE-'||nonce||'-'||i,'order','PERFORMANCE-'||nonce||'-'||i,
   'stock','','batch','','cosi','Yes','consultant','BG','client','Fictional performance verification',
   'importedAt',stamp,'navisionRawEvidence',jsonb_build_object('columns',jsonb_build_array(
    jsonb_build_object('header','Dealer','value','014450'),jsonb_build_object('header','Order','value','PERFORMANCE-'||nonce||'-'||i),
    jsonb_build_object('header','COSI','value','Yes')))));
 END LOOP;
 IF jsonb_array_length(rows)<>1146 THEN RAISE EXCEPTION 'Expected 1146 source rows, found %',jsonb_array_length(rows); END IF;
 BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  started:=clock_timestamp();p:=public.preview_navision_upload_profile('pilbara',rows,'large-upload-rollback.tsv',NULL);
  IF p->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Preview failed: %',p->>'code'; END IF;
  IF p#>>'{data,safety,reason}'='suspicious_partial_snapshot' THEN
   result:=public.review_navision_complete_snapshot('pilbara',rows,'large-upload-rollback.tsv',NULL,
    p#>>'{data,source_hash}',p#>>'{data,preview_hash}',(p#>>'{data,base_revision}')::bigint);
   IF result->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Rollback snapshot review failed: %',result->>'code'; END IF;
   p:=public.preview_navision_upload_profile('pilbara',rows,'large-upload-rollback.tsv',NULL);
  END IF;
  IF p#>>'{data,blocking}' IS DISTINCT FROM 'false' THEN RAISE EXCEPTION 'Preview blocked: %',p#>'{data,safety}'; END IF;
  IF p#>>'{data,counts,new}'<>'8' OR p#>>'{data,counts,changed}'<>'1138' THEN RAISE EXCEPTION 'Changed-row stress case did not match: %',p#>'{data,counts}'; END IF;
  preview_ms:=round(extract(epoch FROM(clock_timestamp()-started))*1000,1);
  started:=clock_timestamp(); result:=public.apply_navision_upload_profile('pilbara','large-upload-test-'||nonce,rows,'large-upload-rollback.tsv',NULL,
   p#>>'{data,source_hash}',p#>>'{data,preview_hash}',(p#>>'{data,base_revision}')::bigint);
  apply_ms:=round(extract(epoch FROM(clock_timestamp()-started))*1000,1);
  IF result->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Large apply failed: %',result->>'code'; END IF;
  started:=clock_timestamp();SET CONSTRAINTS ALL IMMEDIATE;
  constraints_ms:=round(extract(epoch FROM(clock_timestamp()-started))*1000,1);
  replay:=public.apply_navision_upload_profile('pilbara','large-upload-test-'||nonce,rows,'large-upload-rollback.tsv',NULL,
   p#>>'{data,source_hash}',p#>>'{data,preview_hash}',(p#>>'{data,base_revision}')::bigint);
  IF replay IS DISTINCT FROM result THEN RAISE EXCEPTION 'Large upload replay changed'; END IF;
  IF apply_ms+constraints_ms>=60000 THEN RAISE EXCEPTION 'Large upload performance regressed: % ms',apply_ms+constraints_ms; END IF;
  report:=jsonb_build_object('source_rows',jsonb_array_length(rows),'counts',p#>'{data,counts}',
   'preview_ms',preview_ms,'apply_ms',apply_ms,'constraints_ms',constraints_ms,'same_request_replay',true,'rolled_back',true);
  RAISE EXCEPTION 'verified rollback' USING errcode='ZX001';
 EXCEPTION WHEN SQLSTATE 'ZX001' THEN EXECUTE 'RESET ROLE'; END;
 IF EXISTS(SELECT 1 FROM public.navision_backend_records WHERE raw_evidence->>'client'='Fictional performance verification'
   AND raw_evidence->>'order' LIKE 'PERFORMANCE-'||nonce||'%')
  OR EXISTS(SELECT 1 FROM pdc_navision_combined_private.receipts WHERE idempotency_key='large-upload-test-'||nonce) THEN
  RAISE EXCEPTION 'Performance fixture escaped rollback';
 END IF;
 PERFORM set_config('pdc.navision_large_upload_verification',report::text,true);
END $verify$;
SELECT current_setting('pdc.navision_large_upload_verification')::jsonb AS verification;
ROLLBACK;
