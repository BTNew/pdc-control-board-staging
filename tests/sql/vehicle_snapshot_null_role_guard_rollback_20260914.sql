-- STAGING ONLY, after vehicle_snapshot_null_role_guard migration.
-- Read-only: no DDL or synthetic business records. Claims and fixture settings roll back.
BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL statement_timeout = '60s';

DO $verify$
DECLARE
  original_role text := current_user;
  source_body text;
  guard_body text;
  guard_end integer;
  fixture record;
  original_result jsonb;
  compact_result jsonb;
  role_result text;
  passed integer := 0;
  unknown_id uuid := gen_random_uuid();
  actor_claims text;
  guard_marker text := '  SELECT revision INTO v_revision FROM public.pdc_email_vehicle_revision WHERE singleton;';
BEGIN
  IF (SELECT count(*) FROM public.pdc_staging_environment_sentinel
      WHERE singleton AND project_ref = 'cdsmnqxtyyoeoznmbidd') <> 1
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN
    RAISE EXCEPTION 'Wrong environment: NULL-role verification is STAGING only';
  END IF;
  SELECT prosrc INTO STRICT source_body FROM pg_proc
    WHERE oid = 'public.get_pdc_email_vehicle_location_snapshot_pre168()'::regprocedure;
  IF position('IF v_role IS NULL OR v_role NOT IN (''viewer'',''operator'',''importer'',''administrator'') THEN' IN source_body) = 0 THEN
    RAISE EXCEPTION 'The reviewed NULL-role guard has not been installed';
  END IF;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.jwt.claim.email', '', true);

  FOR fixture IN SELECT * FROM (VALUES
    ('missing claims', '{}'::jsonb),
    ('identity without an approved application role', jsonb_build_object(
      'sub', unknown_id, 'email', 'unregistered-snapshot-role-' || unknown_id || '@example.invalid', 'role', 'authenticated'))
  ) cases(label, claims)
  LOOP
    PERFORM set_config('request.jwt.claims', fixture.claims::text, true);
    PERFORM set_config('role', 'authenticated', true);
    IF public.current_pdc_user_role() IS NOT NULL THEN
      RAISE EXCEPTION 'Denied fixture unexpectedly resolves an application role';
    END IF;
    original_result := public.get_pdc_email_vehicle_location_snapshot();
    compact_result := public.get_pdc_email_vehicle_board_snapshot();
    PERFORM set_config('role', original_role, true);
    IF original_result->>'ok' IS DISTINCT FROM 'false'
       OR original_result->>'code' IS DISTINCT FROM 'unauthorized'
       OR compact_result IS DISTINCT FROM original_result
       OR coalesce(jsonb_array_length(original_result#>'{data,vehicles}'), 0) <> 0 THEN
      RAISE EXCEPTION 'Denied fixture leaked a snapshot or changed response: %', fixture.label;
    END IF;
    passed := passed + 1;
  END LOOP;

  -- Run the exact deployed guard prefix with each role value. Stop at the first
  -- data read so this checks every allowed role without fabricating accounts.
  -- The permitted-role list and the query below the guard are never reimplemented.
  guard_end := position(guard_marker IN source_body);
  IF guard_end = 0 THEN RAISE EXCEPTION 'Role-guard fixture boundary changed'; END IF;
  guard_body := left(source_body, guard_end - 1);
  IF position('v_role:=public.current_pdc_user_role()::text;' IN guard_body) = 0
     OR position('RETURN public.navision_backend_response(false,''unauthorized'');' IN guard_body) = 0 THEN
    RAISE EXCEPTION 'Role-guard fixture seams changed';
  END IF;
  guard_body := replace(guard_body, 'v_role:=public.current_pdc_user_role()::text;',
    'v_role:=nullif(current_setting(''snapshot_role_guard.fixture_role''), '''');');
  guard_body := replace(guard_body, 'RETURN public.navision_backend_response(false,''unauthorized'');',
    'PERFORM set_config(''snapshot_role_guard.fixture_result'', ''denied'', true); RETURN;');
  guard_body := guard_body || 'PERFORM set_config(''snapshot_role_guard.fixture_result'', ''allowed'', true); END;';
  FOR fixture IN SELECT * FROM (VALUES
    (NULL::text, 'denied'), ('unapproved', 'denied'),
    ('viewer', 'allowed'), ('operator', 'allowed'), ('importer', 'allowed'), ('administrator', 'allowed')
  ) cases(role_value, expected)
  LOOP
    PERFORM set_config('snapshot_role_guard.fixture_role', coalesce(fixture.role_value, ''), true);
    PERFORM set_config('snapshot_role_guard.fixture_result', 'unset', true);
    EXECUTE 'DO ' || quote_literal(guard_body);
    role_result := current_setting('snapshot_role_guard.fixture_result');
    IF role_result IS DISTINCT FROM fixture.expected THEN
      RAISE EXCEPTION 'Role policy changed for %', coalesce(fixture.role_value, '<NULL>');
    END IF;
    passed := passed + 1;
  END LOOP;

  SELECT jsonb_build_object('sub', r.auth_user_id, 'email', r.email, 'role', 'authenticated')::text
    INTO STRICT actor_claims FROM public.pdc_user_roles r
    JOIN auth.users u ON u.id = r.auth_user_id AND lower(u.email) = lower(r.email)
    WHERE lower(r.email) = 'craig.watson@broometoyota.com.au'
      AND r.active AND r.account_status = 'approved';
  PERFORM set_config('request.jwt.claims', actor_claims, true);
  PERFORM set_config('role', 'authenticated', true);
  original_result := public.get_pdc_email_vehicle_location_snapshot();
  compact_result := public.get_pdc_email_vehicle_board_snapshot();
  PERFORM set_config('role', original_role, true);
  IF original_result->>'ok' IS DISTINCT FROM 'true'
     OR compact_result->>'ok' IS DISTINCT FROM 'true'
     OR jsonb_array_length(original_result#>'{data,vehicles}') <> jsonb_array_length(compact_result#>'{data,vehicles}')
     OR (original_result #- '{data,vehicles}') IS DISTINCT FROM (compact_result #- '{data,vehicles}') THEN
    RAISE EXCEPTION 'Existing approved account lost access or response envelope changed';
  END IF;
  passed := passed + 1;
  PERFORM set_config('snapshot_role_guard.report', jsonb_build_object(
    'result', 'PASS', 'cases', passed, 'missing_claims', 'denied', 'unregistered_application_role', 'denied',
    'allowed_roles', jsonb_build_array('viewer', 'operator', 'importer', 'administrator'),
    'approved_account_access', 'PASS', 'vehicle_count', jsonb_array_length(original_result#>'{data,vehicles}'),
    'read_only', true
  )::text, true);
END $verify$;

SELECT current_setting('snapshot_role_guard.report')::jsonb AS snapshot_role_guard_verification;
ROLLBACK;
