-- STAGING ONLY. Run after 20260914053929_compact_vehicle_board_snapshot.sql.
-- Execute this complete file in one connection, as the project SQL administrator.
-- No DDL or business-data writes: all checks use a read-only, repeatable snapshot.
-- The existing approved Craig account supplies the same scope used in browser QA.
-- Claims, role changes and result settings are transaction-local and roll back.
BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL statement_timeout = '60s';
SET LOCAL lock_timeout = '5s';

DO $guard$
DECLARE
  wrapper regprocedure := to_regprocedure('public.get_pdc_email_vehicle_board_snapshot()');
  original regprocedure := to_regprocedure('public.get_pdc_email_vehicle_location_snapshot()');
  actor_claims text;
  wrapper_definition record;
BEGIN
  IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel
      WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'Wrong environment: compact snapshot verification is STAGING only';
  END IF;
  IF wrapper IS NULL OR original IS NULL THEN
    RAISE EXCEPTION 'Install the compact snapshot migration before running this test';
  END IF;

  SELECT p.prosecdef, p.provolatile, p.prorettype, p.proconfig
    INTO STRICT wrapper_definition FROM pg_proc p WHERE p.oid = wrapper;
  IF wrapper_definition.prosecdef
     OR wrapper_definition.provolatile <> 's'
     OR wrapper_definition.prorettype <> 'jsonb'::regtype
     OR ('search_path=pg_catalog, public' = ANY(wrapper_definition.proconfig)) IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Wrapper must be stable, invoker, JSONB, with the reviewed search path';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_proc p,
      LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
    WHERE p.oid = wrapper AND a.grantee = 0 AND a.privilege_type = 'EXECUTE'
  ) OR has_function_privilege('anon', wrapper, 'EXECUTE')
    OR NOT has_function_privilege('authenticated', wrapper, 'EXECUTE')
    OR NOT has_function_privilege('service_role', wrapper, 'EXECUTE') THEN
    RAISE EXCEPTION 'Wrapper execution grants differ from the reviewed access policy';
  END IF;
  IF NOT has_function_privilege('authenticated', original, 'EXECUTE') THEN
    RAISE EXCEPTION 'Original endpoint must remain callable by authenticated clients';
  END IF;

  SELECT jsonb_build_object('sub', r.auth_user_id, 'email', r.email, 'role', 'authenticated')::text
    INTO STRICT actor_claims
    FROM public.pdc_user_roles r
    JOIN auth.users u ON u.id = r.auth_user_id AND lower(u.email) = lower(r.email)
    WHERE lower(r.email) = 'craig.watson@broometoyota.com.au'
      AND r.active AND r.account_status = 'approved';
  PERFORM set_config('compact_review.actor_claims', actor_claims, true);
  PERFORM set_config('compact_review.original_role', current_user, true);
  PERFORM set_config('compact_review.original_fingerprint', (
    SELECT md5(pg_get_functiondef(p.oid) || coalesce(p.proacl::text, '<default>'))
    FROM pg_proc p WHERE p.oid = original
  ), true);
  PERFORM set_config('compact_review.report', jsonb_build_object(
    'environment', 'staging', 'read_only', true,
    'wrapper_catalog_and_privileges', 'PASS'
  )::text, true);
END $guard$;

DO $authentication$
DECLARE
  original_response jsonb;
  compact_response jsonb;
  original_error text;
  compact_error text;
  original_message text;
  compact_message text;
  denied boolean := false;
BEGIN
  PERFORM set_config('request.jwt.claims', '{}', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.jwt.claim.email', '', true);
  PERFORM set_config('role', 'anon', true);
  BEGIN
    PERFORM public.get_pdc_email_vehicle_board_snapshot();
  EXCEPTION WHEN insufficient_privilege THEN denied := true;
  END;
  PERFORM set_config('role', current_setting('compact_review.original_role'), true);
  IF NOT denied THEN RAISE EXCEPTION 'Anonymous role unexpectedly executed compact endpoint'; END IF;

  PERFORM set_config('role', 'authenticated', true);
  BEGIN
    original_response := public.get_pdc_email_vehicle_location_snapshot();
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS original_error = RETURNED_SQLSTATE, original_message = MESSAGE_TEXT;
  END;
  BEGIN
    compact_response := public.get_pdc_email_vehicle_board_snapshot();
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS compact_error = RETURNED_SQLSTATE, compact_message = MESSAGE_TEXT;
  END;
  PERFORM set_config('role', current_setting('compact_review.original_role'), true);
  IF original_error IS DISTINCT FROM compact_error
     OR original_message IS DISTINCT FROM compact_message
     OR original_response IS DISTINCT FROM compact_response THEN
    RAISE EXCEPTION 'Missing-claims response or exception differs from original endpoint';
  END IF;
  IF original_error IS NOT NULL
     OR original_response->>'ok' IS DISTINCT FROM 'false'
     OR original_response->>'code' IS DISTINCT FROM 'unauthorized' THEN
    RAISE EXCEPTION 'Missing claims must return unauthorized after the NULL-role repair';
  END IF;
  PERFORM set_config('compact_review.report', (
    current_setting('compact_review.report')::jsonb || jsonb_build_object(
      'anon_execution_denied', 'PASS', 'missing_claims_matches_original', 'PASS',
      'missing_claims_denied', 'PASS'
    )
  )::text, true);
END $authentication$;

DO $live_parity$
DECLARE
  original_response jsonb;
  compact_response jsonb;
  started timestamptz;
  original_ms numeric;
  compact_ms numeric;
  mismatches integer;
  original_bytes integer;
  compact_bytes integer;
  vehicle_count integer;
BEGIN
  PERFORM set_config('request.jwt.claims', current_setting('compact_review.actor_claims'), true);
  PERFORM set_config('role', 'authenticated', true);
  started := clock_timestamp();
  original_response := public.get_pdc_email_vehicle_location_snapshot();
  original_ms := extract(epoch FROM clock_timestamp() - started) * 1000;
  started := clock_timestamp();
  compact_response := public.get_pdc_email_vehicle_board_snapshot();
  compact_ms := extract(epoch FROM clock_timestamp() - started) * 1000;
  PERFORM set_config('role', current_setting('compact_review.original_role'), true);

  IF original_response->>'ok' IS DISTINCT FROM 'true'
     OR original_response->>'code' IS DISTINCT FROM 'ok'
     OR jsonb_typeof(original_response#>'{data,vehicles}') IS DISTINCT FROM 'array'
     OR original_response#>'{data,revision}' IS NULL THEN
    RAISE EXCEPTION 'Original endpoint no longer has the observed data.vehicles/revision envelope';
  END IF;
  IF (original_response #- '{data,vehicles}') IS DISTINCT FROM
     (compact_response #- '{data,vehicles}') THEN
    RAISE EXCEPTION 'Response envelope or data revision changed';
  END IF;
  IF jsonb_typeof(compact_response#>'{data,vehicles}') IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'Compact vehicles projection is not an array';
  END IF;
  vehicle_count := jsonb_array_length(original_response#>'{data,vehicles}');
  IF vehicle_count = 0 THEN RAISE EXCEPTION 'No live vehicles available for parity coverage'; END IF;
  IF vehicle_count <> jsonb_array_length(compact_response#>'{data,vehicles}') THEN
    RAISE EXCEPTION 'Vehicle count changed';
  END IF;

  -- Pair by position, never by an id join that could conceal reordering or duplicates.
  -- Compare every unrelated field and each retained parts object in full.
  SELECT count(*) INTO mismatches
  FROM jsonb_array_elements(original_response#>'{data,vehicles}') WITH ORDINALITY a(v, ordinal)
  FULL JOIN jsonb_array_elements(compact_response#>'{data,vehicles}') WITH ORDINALITY b(v, ordinal)
    USING (ordinal)
  WHERE jsonb_typeof(a.v) IS DISTINCT FROM jsonb_typeof(b.v)
    OR CASE WHEN jsonb_typeof(a.v) = 'object' THEN
      (a.v - ARRAY['pilbara_service_operations', 'parts_flags']) IS DISTINCT FROM
      (b.v - ARRAY['pilbara_service_operations', 'parts_flags'])
      OR CASE WHEN jsonb_typeof(a.v->'parts_flags') = 'object'
        THEN (a.v->'parts_flags') - 'operations' ELSE a.v->'parts_flags' END
        IS DISTINCT FROM b.v->'parts_flags'
      OR b.v ? 'pilbara_service_operations'
      OR (jsonb_typeof(b.v->'parts_flags') = 'object' AND (b.v->'parts_flags') ? 'operations')
    ELSE a.v IS DISTINCT FROM b.v END;
  IF mismatches <> 0 THEN
    RAISE EXCEPTION 'Vehicle order, retained fields or removal contract differs in % positions', mismatches;
  END IF;

  original_bytes := octet_length(original_response::text);
  compact_bytes := octet_length(compact_response::text);
  IF compact_bytes >= original_bytes THEN
    RAISE EXCEPTION 'Current live fixture did not exercise a payload reduction';
  END IF;
  PERFORM set_config('compact_review.report', (
    current_setting('compact_review.report')::jsonb || jsonb_build_object(
      'live_envelope_order_and_all_retained_fields', 'PASS', 'vehicle_count', vehicle_count,
      'retained_field_mismatches', mismatches, 'original_bytes', original_bytes,
      'compact_bytes', compact_bytes, 'saved_bytes', original_bytes - compact_bytes,
      'saved_percent', round(100.0 * (original_bytes - compact_bytes) / original_bytes, 2),
      'original_database_ms', original_ms, 'compact_database_ms', compact_ms,
      'timing_note', 'Sequential single samples in a repeatable-read transaction, not a benchmark'
    )
  )::text, true);
END $live_parity$;

DO $field_shapes$
DECLARE
  source_body text;
  harness_body text;
  fixture record;
  actual jsonb;
  tested integer := 0;
BEGIN
  -- Execute the exact deployed transformation as an anonymous block. Only replace
  -- its legacy read and return statements with transaction-local fixture IO.
  -- This seam exercises absent/null/scalar cases without changing either RPC,
  -- creating a helper function, inserting vehicles or duplicating the transform.
  SELECT p.prosrc INTO STRICT source_body FROM pg_proc p
    WHERE p.oid = 'public.get_pdc_email_vehicle_board_snapshot()'::regprocedure;
  IF md5(replace(source_body, chr(13), '')) <> 'a3a635b978cb6b266ea04f03c876672f' THEN
    RAISE EXCEPTION 'Wrapper body changed: independently review it before refreshing fixture hash';
  END IF;
  IF position('v_base := public.get_pdc_email_vehicle_location_snapshot();' IN source_body) = 0
     OR position('RETURN v_base;' IN source_body) = 0
     OR position('RETURN jsonb_set(v_base, ''{data,vehicles}'', v_rows, false);' IN source_body) = 0 THEN
    RAISE EXCEPTION 'Wrapper structure changed: review fixture seams before rerunning';
  END IF;
  harness_body := replace(source_body,
    'v_base := public.get_pdc_email_vehicle_location_snapshot();',
    'v_base := current_setting(''compact_review.fixture_input'')::jsonb;');
  harness_body := replace(harness_body, 'RETURN v_base;',
    'PERFORM set_config(''compact_review.fixture_result'', v_base::text, true); RETURN;');
  harness_body := replace(harness_body,
    'RETURN jsonb_set(v_base, ''{data,vehicles}'', v_rows, false);',
    'PERFORM set_config(''compact_review.fixture_result'', jsonb_set(v_base, ''{data,vehicles}'', v_rows, false)::text, true); RETURN;');

  FOR fixture IN SELECT * FROM (VALUES
    ('failed envelope', '{"ok":false,"code":"not_authorized","data":{"vehicles":[{"pilbara_service_operations":[1],"parts_flags":{"operations":{"x":1}}}]}}'::jsonb, NULL::jsonb),
    ('missing ok', '{"code":"pending","data":{"vehicles":[]}}'::jsonb, NULL::jsonb),
    ('null ok', '{"ok":null,"code":"pending","data":{"vehicles":[]}}'::jsonb, NULL::jsonb),
    ('missing data', '{"ok":true,"code":"ok","extra":1}'::jsonb, NULL::jsonb),
    ('missing vehicles', '{"ok":true,"code":"ok","data":{"revision":9}}'::jsonb, NULL::jsonb),
    ('null vehicles', '{"ok":true,"code":"ok","data":{"vehicles":null,"revision":9}}'::jsonb, NULL::jsonb),
    ('object vehicles', '{"ok":true,"code":"ok","data":{"vehicles":{"keep":1},"revision":9}}'::jsonb, NULL::jsonb),
    ('scalar vehicles', '{"ok":true,"code":"ok","data":{"vehicles":"keep","revision":9}}'::jsonb, NULL::jsonb),
    ('empty array and envelope', '{"ok":true,"code":"ok","unknown":{"keep":true},"data":{"vehicles":[],"revision":0,"extra":false}}'::jsonb, NULL::jsonb),
    ('parts shapes and non-object rows',
      '{"ok":true,"code":"ok","data":{"revision":9,"vehicles":[{"id":"z","pilbara_service_operations":[1]},{"id":"a","parts_flags":null},{"id":"b","parts_flags":[{"operations":"keep"}]},{"id":"c","parts_flags":"keep"},{"id":"d","parts_flags":0},{"id":"e","parts_flags":false},{"id":"f","parts_flags":{}},null,7,"row",["row"]]}}'::jsonb,
      '{"ok":true,"code":"ok","data":{"revision":9,"vehicles":[{"id":"z"},{"id":"a","parts_flags":null},{"id":"b","parts_flags":[{"operations":"keep"}]},{"id":"c","parts_flags":"keep"},{"id":"d","parts_flags":0},{"id":"e","parts_flags":false},{"id":"f","parts_flags":{}},null,7,"row",["row"]]}}'::jsonb),
    ('only named paths removed; authoritative nested evidence retained',
      '{"ok":true,"code":"ok","unknown":[1,2],"data":{"revision":9,"other":0,"vehicles":[{"id":"b","version":8,"pilbara_service_operations":[1],"operation_lines":[{"source_uid":"pilbara_service_open_jobcards_v1:keep","estimated_hours":0}],"qc_operation_lines":[{"line_version":4,"completed":false}],"parts_flags":{"operations":{"x":{}},"colour":"orange","parts_complete":false,"jobs":[{"job_number":"R1","operations":"keep"}],"import_status":{"operations":"keep"}}},{"id":"a","pilbara_service_operations":null,"parts_flags":{"operations":null,"label":"keep"},"other":{"pilbara_service_operations":"keep"}}]}}'::jsonb,
      '{"ok":true,"code":"ok","unknown":[1,2],"data":{"revision":9,"other":0,"vehicles":[{"id":"b","version":8,"operation_lines":[{"source_uid":"pilbara_service_open_jobcards_v1:keep","estimated_hours":0}],"qc_operation_lines":[{"line_version":4,"completed":false}],"parts_flags":{"colour":"orange","parts_complete":false,"jobs":[{"job_number":"R1","operations":"keep"}],"import_status":{"operations":"keep"}}},{"id":"a","parts_flags":{"label":"keep"},"other":{"pilbara_service_operations":"keep"}}]}}'::jsonb)
  ) cases(name, input, expected)
  LOOP
    PERFORM set_config('compact_review.fixture_input', fixture.input::text, true);
    PERFORM set_config('compact_review.fixture_result', 'null', true);
    EXECUTE 'DO ' || quote_literal(harness_body);
    actual := current_setting('compact_review.fixture_result')::jsonb;
    IF actual IS DISTINCT FROM coalesce(fixture.expected, fixture.input) THEN
      RAISE EXCEPTION 'Field-shape fixture failed: %', fixture.name;
    END IF;
    tested := tested + 1;
  END LOOP;
  PERFORM set_config('compact_review.report', (
    current_setting('compact_review.report')::jsonb || jsonb_build_object(
      'exact_deployed_transform_shape_cases', tested, 'shape_cases', 'PASS'
    )
  )::text, true);
END $field_shapes$;

DO $unchanged_original$
BEGIN
  IF current_setting('compact_review.original_fingerprint') IS DISTINCT FROM (
    SELECT md5(pg_get_functiondef(p.oid) || coalesce(p.proacl::text, '<default>'))
    FROM pg_proc p WHERE p.oid = 'public.get_pdc_email_vehicle_location_snapshot()'::regprocedure
  ) THEN RAISE EXCEPTION 'Original endpoint definition or privileges changed'; END IF;
  PERFORM set_config('compact_review.report', (
    current_setting('compact_review.report')::jsonb ||
    '{"original_endpoint_unchanged":"PASS","result":"PASS"}'::jsonb
  )::text, true);
END $unchanged_original$;

SELECT current_setting('compact_review.report')::jsonb AS compact_snapshot_verification;
ROLLBACK;
