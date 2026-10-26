-- Run after setup and the up proposal, in the same owned synthetic database.
\set ON_ERROR_STOP on
DO $local$ BEGIN
 IF inet_server_addr() IS DISTINCT FROM '127.0.0.1'::inet OR current_database() NOT LIKE 'pdc_synthetic_%' THEN RAISE EXCEPTION 'synthetic only'; END IF;
END $local$;
DO $matrix$
DECLARE actor text; age interval; before_cache jsonb; after_cache jsonb; result jsonb; old_time timestamptz; cases integer:=0;
BEGIN
 FOR actor IN SELECT unnest(ARRAY['','unknown','inactive','unsupported','viewer','operator','importer','administrator']) LOOP
  FOREACH age IN ARRAY ARRAY[interval '0 seconds',interval '30 seconds'] LOOP
   PERFORM set_config('request.jwt.claims',jsonb_build_object('email',actor||'@synthetic.invalid')::text,true);
   UPDATE pdc_ops.vehicle_board_snapshot_cache_545 SET computed_at=clock_timestamp()-age;
   SELECT snapshot,computed_at INTO before_cache,old_time FROM pdc_ops.vehicle_board_snapshot_cache_545 WHERE singleton;
   result:=public.get_pdc_email_vehicle_board_snapshot();
   SELECT snapshot INTO after_cache FROM pdc_ops.vehicle_board_snapshot_cache_545 WHERE singleton;
   IF actor IN ('viewer','operator','importer','administrator') THEN
    IF result IS DISTINCT FROM before_cache OR after_cache IS DISTINCT FROM before_cache THEN
     RAISE EXCEPTION 'allowed role response/cache changed: %, %',actor,age;
    END IF;
   ELSE
    IF result IS DISTINCT FROM public.navision_backend_response(false,'unauthorized') THEN
     RAISE EXCEPTION 'unauthorized actor not denied: %, %',actor,age;
    END IF;
    IF (SELECT computed_at FROM pdc_ops.vehicle_board_snapshot_cache_545 WHERE singleton) IS DISTINCT FROM old_time THEN
     RAISE EXCEPTION 'unauthorized actor modified cache: %, %',actor,age;
    END IF;
   END IF;
   cases:=cases+1;
  END LOOP;
 END LOOP;
 IF has_function_privilege('anon','public.get_pdc_email_vehicle_board_snapshot()','EXECUTE')
 OR NOT has_function_privilege('authenticated','public.get_pdc_email_vehicle_board_snapshot()','EXECUTE')
 OR NOT has_function_privilege('service_role','public.get_pdc_email_vehicle_board_snapshot()','EXECUTE')
 OR has_table_privilege('authenticated','pdc_ops.vehicle_board_snapshot_cache_545','SELECT') THEN
  RAISE EXCEPTION 'ACL changed';
 END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 0 THEN RAISE EXCEPTION 'pins changed'; END IF;
 RAISE NOTICE 'PASS: % role/cache cases; payload parity, denied-no-write, ACL and pin checks',cases;
END $matrix$;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"email":"inactive@synthetic.invalid"}',true);
DO $role$ BEGIN
 IF public.get_pdc_email_vehicle_board_snapshot()->>'code' IS DISTINCT FROM 'unauthorized' THEN RAISE EXCEPTION 'authenticated inactive actor not denied'; END IF;
END $role$;
ROLLBACK;
SELECT 'PASS: actual authenticated database role denied for inactive synthetic actor' AS result;
