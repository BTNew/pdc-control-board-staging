-- Synthetic-only PostgreSQL integration test. Never run against a working database.
-- Requires a newly created empty database on a loopback PostgreSQL instance.
\set ON_ERROR_STOP on
DO $local$ BEGIN
 IF inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet OR current_database() NOT LIKE 'pdc_synthetic_%' THEN
  RAISE EXCEPTION 'synthetic test requires owned loopback database';
 END IF;
 IF to_regclass('public.vehicles') IS NOT NULL OR to_regclass('public.workshop_bookings') IS NOT NULL THEN
  RAISE EXCEPTION 'synthetic test refuses a restored or working database';
 END IF;
END $local$;
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN;
CREATE SCHEMA auth;
CREATE SCHEMA pdc_ops;
CREATE TABLE public.pdc_staging_environment_sentinel(singleton boolean,project_ref text);
INSERT INTO public.pdc_staging_environment_sentinel VALUES(true,'cdsmnqxtyyoeoznmbidd');
CREATE FUNCTION public.pdc_monitor_staging_guard() RETURNS boolean LANGUAGE sql AS $$SELECT true$$;
CREATE TABLE pdc_ops.expected_function_md5(signature text PRIMARY KEY,prosrc_md5 text);
CREATE TABLE public.pdc_email_vehicle_revision(singleton boolean PRIMARY KEY,revision bigint);
INSERT INTO public.pdc_email_vehicle_revision VALUES(true,7);
CREATE TABLE public.pdc_user_roles(email text PRIMARY KEY,role text,active boolean);
INSERT INTO public.pdc_user_roles VALUES
 ('viewer@synthetic.invalid','viewer',true),('operator@synthetic.invalid','operator',true),
 ('importer@synthetic.invalid','importer',true),('administrator@synthetic.invalid','administrator',true),
 ('inactive@synthetic.invalid','operator',false),('unsupported@synthetic.invalid','customer',true);
CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $$SELECT coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
CREATE FUNCTION public.current_pdc_user_role() RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO public AS $$
 SELECT role FROM public.pdc_user_roles WHERE email=lower(coalesce(auth.jwt()->>'email','')) AND active=true LIMIT 1;
$$;
CREATE FUNCTION public.navision_backend_response(p_ok boolean,p_code text) RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$SELECT jsonb_build_object('ok',p_ok,'code',p_code,'data','{}'::jsonb)$$;
CREATE TABLE pdc_ops.vehicle_board_snapshot_cache_545(singleton boolean PRIMARY KEY,email_revision bigint,snapshot jsonb,computed_at timestamptz);
ALTER TABLE pdc_ops.vehicle_board_snapshot_cache_545 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pdc_ops.vehicle_board_snapshot_cache_545 FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION public.get_pdc_email_vehicle_location_snapshot() RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER AS $$
BEGIN
 IF coalesce(public.current_pdc_user_role() IN ('viewer','operator','importer','administrator'),false) IS NOT TRUE THEN
  RETURN public.navision_backend_response(false,'unauthorized');
 END IF;
 RETURN '{"ok":true,"code":"synthetic","data":{"revision":7,"vehicles":[{"id":"synthetic-vehicle","operation_lines":[{"description":"Synthetic job","estimated_hours":1}],"parts_flags":{"summary":"unchanged","operations":{"removed":"duplicate"}},"pilbara_service_operations":[{"removed":"duplicate"}]}]}}'::jsonb;
END $$;
CREATE FUNCTION public.get_pdc_email_vehicle_board_snapshot() RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog,public AS $function$
DECLARE
  v_base jsonb;
  v_rows jsonb;
  v_rev bigint;
  v_cached jsonb;
  v_lock boolean;
BEGIN
  -- r545 (F159): one shared Vehicle Locations board for 15 seconds.
  -- The payload does not depend on who is signed in. Parallel refreshes were
  -- each rebuilding it and timing the workshop out.
  SELECT r.revision INTO v_rev
  FROM public.pdc_email_vehicle_revision r
  WHERE r.singleton;
  v_rev := coalesce(v_rev, 0);

  SELECT c.snapshot INTO v_cached
  FROM pdc_ops.vehicle_board_snapshot_cache_545 c
  WHERE c.singleton
    AND c.email_revision = v_rev
    AND c.computed_at > clock_timestamp() - interval '15 seconds';
  IF v_cached IS NOT NULL THEN
    RETURN v_cached;
  END IF;

  v_lock := pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtextextended('pdc-r545-vehicle-board', 0));
  IF NOT v_lock THEN
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('pdc-r545-vehicle-board', 0));
    SELECT r.revision INTO v_rev
    FROM public.pdc_email_vehicle_revision r
    WHERE r.singleton;
    v_rev := coalesce(v_rev, 0);
    SELECT c.snapshot INTO v_cached
    FROM pdc_ops.vehicle_board_snapshot_cache_545 c
    WHERE c.singleton
      AND c.email_revision = v_rev
      AND c.computed_at > clock_timestamp() - interval '15 seconds';
    IF v_cached IS NOT NULL THEN
      RETURN v_cached;
    END IF;
  END IF;

  v_base := public.get_pdc_email_vehicle_location_snapshot();
  IF NOT coalesce((v_base->>'ok')::boolean, false)
     OR jsonb_typeof(v_base#>'{data,vehicles}') IS DISTINCT FROM 'array' THEN
    RETURN v_base;
  END IF;
  SELECT coalesce(jsonb_agg(
    CASE WHEN jsonb_typeof(row_value) = 'object' THEN
      CASE WHEN jsonb_typeof(row_value->'parts_flags') = 'object'
        THEN (row_value - 'pilbara_service_operations') #- '{parts_flags,operations}'
        ELSE row_value - 'pilbara_service_operations'
      END
    ELSE row_value END ORDER BY ordinal), '[]'::jsonb)
  INTO v_rows
  FROM jsonb_array_elements(v_base#>'{data,vehicles}') WITH ORDINALITY AS x(row_value, ordinal);
  v_base := jsonb_set(v_base, '{data,vehicles}', v_rows, false);
  INSERT INTO pdc_ops.vehicle_board_snapshot_cache_545 (singleton, email_revision, snapshot, computed_at)
  VALUES (true, v_rev, v_base, clock_timestamp())
  ON CONFLICT (singleton) DO UPDATE
    SET email_revision = EXCLUDED.email_revision,
        snapshot = EXCLUDED.snapshot,
        computed_at = EXCLUDED.computed_at
    WHERE vehicle_board_snapshot_cache_545.singleton;
  RETURN v_base;
END
$function$;
REVOKE ALL ON FUNCTION public.get_pdc_email_vehicle_board_snapshot() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_pdc_email_vehicle_board_snapshot() TO authenticated,service_role;
INSERT INTO pdc_ops.vehicle_board_snapshot_cache_545 VALUES(true,7,
 '{"ok":true,"code":"synthetic","data":{"revision":7,"vehicles":[{"id":"synthetic-vehicle","operation_lines":[{"description":"Synthetic job","estimated_hours":1}],"parts_flags":{"summary":"unchanged"}}]}}',clock_timestamp());
DO $before$ BEGIN
 IF public.current_pdc_user_role() IS NOT NULL THEN RAISE EXCEPTION 'fixture unexpectedly authorized'; END IF;
 IF (public.get_pdc_email_vehicle_board_snapshot()->>'ok')::boolean IS DISTINCT FROM true THEN
  RAISE EXCEPTION 'old fresh-cache authorization gap not reproduced';
 END IF;
END $before$;
SELECT 'PASS: original fresh-cache gap reproduced with synthetic data only' AS result;
