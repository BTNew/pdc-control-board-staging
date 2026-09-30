-- Execute BEGIN; migration SQL; this test SQL; ROLLBACK in one connection.
-- Only transaction-local function/configuration/temp-table changes; no application rows written.
CREATE TEMP TABLE pdc_update_history_test_result(result jsonb) ON COMMIT DROP;
DO $test$
DECLARE payload jsonb; admin_id uuid; other_id uuid; started timestamptz;
        cold_ms numeric; warm_ms numeric; checks integer := 0; expected timestamptz;
BEGIN
  IF has_function_privilege('anon','public.get_pdc_update_history()','EXECUTE') THEN
    RAISE EXCEPTION 'Anonymous execute must be denied'; END IF;
  checks:=checks+1;
  IF NOT has_function_privilege('authenticated','public.get_pdc_update_history()','EXECUTE') THEN
    RAISE EXCEPTION 'Authenticated execute grant missing'; END IF;
  checks:=checks+1;
  IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid='public.get_pdc_update_history()'::regprocedure
      AND p.prosecdef AND p.provolatile='s' AND p.proconfig @> ARRAY['search_path=pg_catalog']) THEN
    RAISE EXCEPTION 'Read-only definer contract or fixed search path missing'; END IF;
  checks:=checks+1;
  PERFORM set_config('request.jwt.claim.sub','',true);
  PERFORM set_config('request.jwt.claims','{}',true);
  IF public.get_pdc_update_history() IS DISTINCT FROM '{"ok":false,"code":"permission_denied"}'::jsonb THEN
    RAISE EXCEPTION 'Missing identity was not denied'; END IF;
  checks:=checks+1;
  PERFORM set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
  IF public.get_pdc_update_history()->>'ok' IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'Unknown identity was not denied'; END IF;
  checks:=checks+1;
  SELECT r.auth_user_id INTO other_id FROM public.pdc_user_roles r
    WHERE r.auth_user_id IS NOT NULL AND r.role::text<>'administrator' ORDER BY r.id LIMIT 1;
  IF other_id IS NULL THEN RAISE EXCEPTION 'Missing existing non-admin test identity'; END IF;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',other_id,'role','authenticated')::text,true);
  IF public.get_pdc_update_history()->>'ok' IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'Non-administrator was not denied'; END IF;
  checks:=checks+1;
  SELECT r.auth_user_id INTO admin_id FROM public.pdc_user_roles r
    WHERE r.auth_user_id IS NOT NULL AND r.role::text='administrator'
      AND r.active IS TRUE AND r.account_status='approved' ORDER BY r.id LIMIT 1;
  IF admin_id IS NULL THEN RAISE EXCEPTION 'Missing existing approved administrator test identity'; END IF;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'role','authenticated')::text,true);
  started:=clock_timestamp(); payload:=public.get_pdc_update_history();
  cold_ms:=round(extract(epoch FROM clock_timestamp()-started)*1000,3);
  started:=clock_timestamp(); payload:=public.get_pdc_update_history();
  warm_ms:=round(extract(epoch FROM clock_timestamp()-started)*1000,3);
  IF payload->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Administrator denied'; END IF;
  checks:=checks+1;
  IF jsonb_array_length(payload->'feeds')<>5 THEN RAISE EXCEPTION 'Expected five feeds'; END IF;
  checks:=checks+1;
  IF (SELECT array_agg(e->>'key' ORDER BY e->>'key') FROM jsonb_array_elements(payload->'feeds') e)
     IS DISTINCT FROM ARRAY['broome_navision','other_navision','parts_info','pilbara_navision','service_codes']::text[] THEN
    RAISE EXCEPTION 'Feed keys changed'; END IF;
  checks:=checks+1;
  IF jsonb_array_length(payload->'history')>20 THEN RAISE EXCEPTION 'History exceeds cap'; END IF;
  checks:=checks+1;
  IF payload::text ~ '"(customer_name|stock_number|vin|raw_row|source_file|mailbox|actor_email|batch_id|source_hash)"[ ]*:' THEN
    RAISE EXCEPTION 'Sensitive result key leaked'; END IF;
  checks:=checks+1;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(payload->'history') e
     WHERE e->>'status' NOT IN ('completed','completed_with_warnings') OR e->>'completed_at' IS NULL) THEN
    RAISE EXCEPTION 'History includes an uncompleted event'; END IF;
  checks:=checks+1;
  SELECT max(applied_at) INTO expected FROM public.navision_import_batches
    WHERE dealer_code='37047' AND source_system='microsoft_navision' AND status='applied' AND receipt->>'ok'='true';
  IF (SELECT (e->>'last_success_at')::timestamptz FROM jsonb_array_elements(payload->'feeds') e WHERE e->>'key'='broome_navision')
      IS DISTINCT FROM expected THEN RAISE EXCEPTION 'Broome completion mismatch'; END IF;
  checks:=checks+1;
  SELECT max(imported_at) INTO expected FROM pdc_parts_private.receipts WHERE response->>'ok'='true';
  IF (SELECT (e->>'last_success_at')::timestamptz FROM jsonb_array_elements(payload->'feeds') e WHERE e->>'key'='parts_info')
      IS DISTINCT FROM expected THEN RAISE EXCEPTION 'Parts completion mismatch'; END IF;
  checks:=checks+1;
  SELECT max(r.created_at) INTO expected FROM public.pdc_pilbara_service_import_receipts r
    JOIN public.pdc_pilbara_service_import_batches b USING(batch_id)
    WHERE b.batch_kind='apply' AND r.receipt_kind='apply' AND b.response->>'ok'='true'
      AND b.response->>'code'='applied' AND r.outcome->>'ok'='true' AND r.outcome->>'code'='applied';
  IF (SELECT (e->>'last_success_at')::timestamptz FROM jsonb_array_elements(payload->'feeds') e WHERE e->>'key'='service_codes')
      IS DISTINCT FROM expected THEN RAISE EXCEPTION 'Service completion uses preview or batch start'; END IF;
  checks:=checks+1;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(payload->'feeds') e WHERE
      e->>'last_success_at' IS NOT NULL AND (e->>'last_success_status' NOT IN ('completed','completed_with_warnings')
        OR (e->>'record_count')::bigint<0)) THEN RAISE EXCEPTION 'Latest success contract incorrect'; END IF;
  checks:=checks+1;
  INSERT INTO pdc_update_history_test_result VALUES(jsonb_build_object(
    'assertions_passed',checks,'cold_execution_ms',cold_ms,'warm_execution_ms',warm_ms,
    'application_rows_written',0,'payload',payload));
END;
$test$;
SELECT result FROM pdc_update_history_test_result;
