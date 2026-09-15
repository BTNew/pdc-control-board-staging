-- Staging only. All probe users, approvals, imports and history are rolled back.
BEGIN;
SET LOCAL statement_timeout='100s';
SET LOCAL lock_timeout='10s';
CREATE TEMP TABLE navision_dealer_test_results(step text,result jsonb) ON COMMIT DROP;
DO $test$
DECLARE
 actor_id uuid:=gen_random_uuid(); actor_email text;
 dealer text; rows jsonb; row_a jsonb; row_b jsonb; result jsonb; preview jsonb; applied jsonb; replay jsonb;
 old_scopes_before text; old_scopes_after text; bookings_before text; bookings_after text;
 serial integer:=0; source_id text; initial_result jsonb;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'Staging only'; END IF;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(b) ORDER BY b.id),'[]'::jsonb)::text) INTO old_scopes_before
 FROM public.navision_backend_records b WHERE dealer_code NOT IN ('002345','001234');
 SELECT md5(coalesce(jsonb_agg(to_jsonb(b) ORDER BY b.id),'[]'::jsonb)::text) INTO bookings_before FROM public.workshop_bookings b;
 actor_email:='dealer-rollback-'||actor_id||'@example.invalid';
 INSERT INTO auth.users(id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 VALUES(actor_id,'authenticated','authenticated',actor_email,clock_timestamp(),
 '{"provider":"email","providers":["email"]}','{"full_name":"Temporary rollback Navision dealer probe"}',clock_timestamp(),clock_timestamp());
 UPDATE public.pdc_user_roles SET role='administrator',active=true,account_status='approved',approved_at=clock_timestamp()
 WHERE auth_user_id=actor_id AND email=actor_email;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor_id,'email',actor_email,'role','authenticated')::text,true);
 FOREACH dealer IN ARRAY ARRAY['002345','001234'] LOOP
  IF EXISTS(SELECT 1 FROM public.navision_backend_records WHERE dealer_code=dealer AND is_current) THEN
   RAISE EXCEPTION 'Fresh-scope test requires no existing rows for %',dealer;
  END IF;
  serial:=serial+1;
  source_id:=CASE WHEN dealer='002345' THEN '99002345' ELSE '99001234' END;
  IF EXISTS(SELECT 1 FROM public.navision_backend_records WHERE source_record_id_normalized IN(source_id,(source_id::bigint+1)::text))
    THEN RAISE EXCEPTION 'Probe identity already exists'; END IF;
  row_a:=jsonb_build_object('id',source_id,'stock',source_id,'batch',source_id,'model','Rollback test vehicle',
    'navisionRawEvidence',jsonb_build_object('columns',jsonb_build_array(jsonb_build_object('header','Dealer','value',dealer))));
  row_b:=jsonb_build_object('id',(source_id::bigint+1)::text,'stock',(source_id::bigint+1)::text,'batch',(source_id::bigint+1)::text,
    'navisionRawEvidence',jsonb_build_object('columns',jsonb_build_array(jsonb_build_object('header','Dealer Code','value',dealer::integer))));
  rows:=jsonb_build_array(row_a,row_b);
  IF public.navision_row_declared_dealer_code(row_a)<>dealer OR public.navision_row_declared_dealer_code(row_b)<>dealer
    THEN RAISE EXCEPTION 'Leading zero normalization failed'; END IF;
  preview:=public.preview_navision_backend_import(rows,'microsoft_navision',dealer,'Pasted text',NULL);
  IF preview#>>'{data,safety,reason}' IS DISTINCT FROM 'unproven_empty_dealer_scope'
    THEN RAISE EXCEPTION 'Initial scope protection failed: %',preview; END IF;
  initial_result:=public.approve_navision_initial_scope(rows,'microsoft_navision',dealer);
  IF initial_result->>'ok'<>'true' THEN RAISE EXCEPTION 'Initial scope approval failed: %',initial_result; END IF;
  preview:=public.preview_navision_backend_import(rows,'microsoft_navision',dealer,'Pasted text',NULL);
  IF preview->>'ok'<>'true' OR preview#>>'{data,blocking}'='true' OR (preview#>>'{data,counts,new}')::integer<>2
    THEN RAISE EXCEPTION 'Preview failed: %',preview; END IF;
  applied:=public.apply_navision_backend_import('dealer-probe-'||actor_id||'-'||dealer,rows,'microsoft_navision',dealer,'Pasted text',NULL,
    preview#>>'{data,source_hash}',preview#>>'{data,preview_hash}',(preview#>>'{data,base_revision}')::bigint);
  IF applied->>'ok'<>'true' THEN RAISE EXCEPTION 'Apply failed: %',applied; END IF;
  SET CONSTRAINTS ALL IMMEDIATE;
  IF (SELECT count(*) FROM public.navision_backend_records WHERE dealer_code=dealer AND is_current)<>2
    OR EXISTS(SELECT 1 FROM public.navision_backend_records WHERE dealer_code=dealer AND canonical_vehicle_id IS NOT NULL)
    THEN RAISE EXCEPTION 'Scope or backend-only storage failed'; END IF;
  replay:=public.apply_navision_backend_import('dealer-probe-'||actor_id||'-'||dealer,rows,'microsoft_navision',dealer,'Pasted text',NULL,
    preview#>>'{data,source_hash}',preview#>>'{data,preview_hash}',(preview#>>'{data,base_revision}')::bigint);
  IF replay->>'ok'<>'true' OR replay#>>'{data,batch_id}' IS DISTINCT FROM applied#>>'{data,batch_id}'
    THEN RAISE EXCEPTION 'Idempotent replay failed: %',replay; END IF;
  result:=public.get_navision_backend_snapshot('microsoft_navision',dealer,NULL,NULL,200,NULL);
  IF result->>'ok'<>'true' OR jsonb_array_length(result#>'{data,items}')<>2 THEN RAISE EXCEPTION 'Readback failed: %',result; END IF;
  result:=public.get_navision_visible_snapshot('microsoft_navision',dealer,NULL,200,NULL);
  IF result->>'ok'<>'true' THEN RAISE EXCEPTION 'Visible snapshot failed: %',result; END IF;
  -- Reimport the full scope with a changed detail; keep both identities.
  rows:=jsonb_build_array(row_a||'{"model":"Updated rollback test vehicle"}'::jsonb,row_b);
  preview:=public.preview_navision_backend_import(rows,'microsoft_navision',dealer,'Pasted text',NULL);
  IF preview->>'ok'<>'true' OR preview#>>'{data,blocking}'='true' THEN RAISE EXCEPTION 'Update preview failed: %',preview; END IF;
  applied:=public.apply_navision_backend_import('dealer-update-'||actor_id||'-'||dealer,rows,'microsoft_navision',dealer,'Pasted text',NULL,
    preview#>>'{data,source_hash}',preview#>>'{data,preview_hash}',(preview#>>'{data,base_revision}')::bigint);
  IF applied->>'ok'<>'true' THEN RAISE EXCEPTION 'Update apply failed: %',applied; END IF;
  SET CONSTRAINTS ALL IMMEDIATE;
  IF NOT EXISTS(SELECT 1 FROM public.navision_backend_records WHERE dealer_code=dealer AND source_record_id_normalized=source_id
    AND raw_evidence->>'model'='Updated rollback test vehicle') THEN RAISE EXCEPTION 'Changed details were not retained'; END IF;
  result:=public.navision_import_candidate_preflight_770(rows,'microsoft_navision',CASE WHEN dealer='002345' THEN '001234' ELSE '002345' END);
  IF result->>'blocking'<>'true' OR result#>>'{issues,0,reason}'<>'wrong_dealer_scope' THEN RAISE EXCEPTION 'Wrong dealer guard failed'; END IF;
  result:=public.navision_import_candidate_preflight_770(jsonb_build_array(row_a,row_a),'microsoft_navision',dealer);
  IF result->>'blocking'<>'true' THEN RAISE EXCEPTION 'Duplicate guard failed'; END IF;
  result:=public.preview_navision_backend_import('[]'::jsonb,'microsoft_navision',dealer,'Pasted text',NULL);
  IF result#>>'{data,blocking}' IS DISTINCT FROM 'true' AND result->>'ok'='true' THEN RAISE EXCEPTION 'Empty import guard failed'; END IF;
  result:=public.navision_import_safety_assessment_pre072(rows,'microsoft_navision',dealer,'navision-14450.csv',preview->'data');
  IF result->>'reason'<>'source_name_dealer_scope_mismatch' THEN RAISE EXCEPTION 'Filename scope guard failed'; END IF;
  INSERT INTO navision_dealer_test_results VALUES(dealer,jsonb_build_object('preview_apply_update_replay_readback',true,
    'leading_zeros_preserved',true,'wrong_scope_duplicate_empty_filename_checks',true));
 END LOOP;
 FOREACH dealer IN ARRAY ARRAY['14450','37047'] LOOP
  result:=public.get_navision_backend_snapshot('microsoft_navision',dealer,NULL,NULL,1,NULL);
  IF result->>'ok'<>'true' THEN RAISE EXCEPTION 'Existing dealer read failed'; END IF;
 END LOOP;
 result:=public.preview_navision_backend_import(rows,'microsoft_navision','999999','Pasted text',NULL);
 IF result->>'ok'='true' AND result#>>'{data,blocking}' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Unknown scope accepted'; END IF;
 PERFORM set_config('request.jwt.claims','{}',true);
 result:=public.preview_navision_backend_import(rows,'microsoft_navision','001234','Pasted text',NULL);
 IF result->>'ok'='true' THEN RAISE EXCEPTION 'Anonymous preview accepted'; END IF;
 SELECT md5(coalesce(jsonb_agg(to_jsonb(b) ORDER BY b.id),'[]'::jsonb)::text) INTO old_scopes_after
 FROM public.navision_backend_records b WHERE dealer_code NOT IN ('002345','001234');
 SELECT md5(coalesce(jsonb_agg(to_jsonb(b) ORDER BY b.id),'[]'::jsonb)::text) INTO bookings_after FROM public.workshop_bookings b;
 IF old_scopes_before IS DISTINCT FROM old_scopes_after OR bookings_before IS DISTINCT FROM bookings_after
 THEN RAISE EXCEPTION 'Other dealers or bookings changed'; END IF;
 INSERT INTO navision_dealer_test_results VALUES('preservation',jsonb_build_object('existing_dealers_unchanged',true,'bookings_unchanged',true,'anonymous_rejected',true,'unknown_dealer_rejected',true));
END $test$;
SELECT * FROM navision_dealer_test_results;
ROLLBACK;

