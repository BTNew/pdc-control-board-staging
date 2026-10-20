-- Undo r407 (F21): restore the SQL approved-source helper and the previous operation_station,
-- remove the r407 pins and the approved_source_lookup_once check. Staging cdsmnqxtyyoeoznmbidd only.
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r407 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r407 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r407 undo: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r407 undo: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_tune_approved_operation_source_20260912(uuid)'::regprocedure)<>'867bb1b1c0afebfb62f45c08ad6b3154' THEN RAISE EXCEPTION 'r407 undo: approved-source helper is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_bus_private.operation_station(uuid)'::regprocedure)<>'a63c9309fd6ae046d37709cfb3666019' THEN RAISE EXCEPTION 'r407 undo: operation_station is not the expected version'; END IF;
 IF (SELECT md5(check_sql) FROM pdc_ops.regression_checks WHERE check_name='approved_source_lookup_once' AND added_in='r407') IS DISTINCT FROM '3065f403b5945c40cc864958ecc5dfe2' THEN RAISE EXCEPTION 'r407 undo: check missing or changed'; END IF;
END $g$;

CREATE OR REPLACE FUNCTION public.pdc_tune_approved_operation_source_20260912(oid uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'public'
AS $function$
 SELECT proposed_source FROM public.pdc_tune_operation_change_reviews
 WHERE source_operation_id=oid AND status='approved' ORDER BY approved_at DESC,change_id DESC LIMIT 1
$function$;

-- The previous body has CRLF line endings; it is restored byte-exact from base64 (md5 asserted below).
DO $restore_os$ BEGIN
 EXECUTE convert_from(decode('Q1JFQVRFIE9SIFJFUExBQ0UgRlVOQ1RJT04gcGRjX2J1c19wcml2YXRlLm9wZXJhdGlvbl9zdGF0aW9uKHBfb3BlcmF0aW9uX2lkIHV1aWQpCiBSRVRVUk5TIHRleHQKIExBTkdVQUdFIHNxbAogU1RBQkxFIFNFQ1VSSVRZIERFRklORVIKIFNFVCBzZWFyY2hfcGF0aCBUTyAncGdfY2F0YWxvZycKQVMgJGZ1bmN0aW9uJA0KIFNFTEVDVCBjb2FsZXNjZShoLnN0YWdlX2NvZGUscGRjX3dvcmtfY2F0ZWdvcmllc19wcml2YXRlLnN0YWdlKHIuY2F0ZWdvcnkpLA0KICBwdWJsaWMucGRjX2RlcGFydG1lbnQxMzhfc3RhdGlvbl8yMDI2MDkxNyhjb2FsZXNjZShwdWJsaWMucGRjX3R1bmVfYXBwcm92ZWRfb3BlcmF0aW9uX3NvdXJjZV8yMDI2MDkxMihvLm9wZXJhdGlvbl9pZCktPj4nb3BlcmF0aW9uX2Rlc2NyaXB0aW9uJyxvLm9wZXJhdGlvbl9kZXNjcmlwdGlvbikpKQ0KIEZST00gcHVibGljLnBkY19waWxiYXJhX3NlcnZpY2Vfb3BlcmF0aW9ucyBvDQogTEVGVCBKT0lOIHBkY19idXNfcHJpdmF0ZS5vcGVyYXRpb25fcm91dGluZ19oaXN0b3J5XzIwMjYxMDE1IGggVVNJTkcob3BlcmF0aW9uX2lkKQ0KIExFRlQgSk9JTiBwZGNfb3BlcmF0aW9uX3VwZGF0ZXNfcHJpdmF0ZS5haV9yb3V0aW5nXzIwMjYxMDE5IHIgT04gci5kZXBhcnRtZW50PWJ0cmltKG8uZGVwYXJ0bWVudCkNCiAgQU5EIHIuZGVzY3JpcHRpb25faGFzaD1wZGNfd29ya19jYXRlZ29yaWVzX3ByaXZhdGUuaW1wb3J0X2Rlc2NyaXB0aW9uX2hhc2hfMjAyNjEwMTcoDQogICBjb2FsZXNjZShwdWJsaWMucGRjX3R1bmVfYXBwcm92ZWRfb3BlcmF0aW9uX3NvdXJjZV8yMDI2MDkxMihvLm9wZXJhdGlvbl9pZCktPj4nb3BlcmF0aW9uX2Rlc2NyaXB0aW9uJyxvLm9wZXJhdGlvbl9kZXNjcmlwdGlvbikpDQogV0hFUkUgby5vcGVyYXRpb25faWQ9cF9vcGVyYXRpb25faWQ7DQokZnVuY3Rpb24k','base64'),'UTF8');
END $restore_os$;

DELETE FROM pdc_ops.expected_function_md5 WHERE release='r407' AND signature IN ('public.pdc_tune_approved_operation_source_20260912(uuid)','pdc_bus_private.operation_station(uuid)');
DELETE FROM pdc_ops.regression_checks WHERE check_name='approved_source_lookup_once' AND added_in='r407';

DO $p$ BEGIN
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r407 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_ops.fault_regression_check()'::regprocedure)<>'fa4651cce7bb0fdb8985857779b62d93' THEN RAISE EXCEPTION 'r407 undo: fault_regression_check changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r407 undo: clock tick changed'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.pdc_tune_approved_operation_source_20260912(uuid)'::regprocedure)<>'157311e04f989c5c8a47c8894bd3a278' THEN RAISE EXCEPTION 'r407 undo: approved-source helper is not the expected version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='pdc_bus_private.operation_station(uuid)'::regprocedure)<>'415c4a6993e8693f155c1c3fa4824d5e' THEN RAISE EXCEPTION 'r407 undo: operation_station is not the expected version'; END IF;
 IF (SELECT proacl::text FROM pg_proc WHERE oid='public.pdc_tune_approved_operation_source_20260912(uuid)'::regprocedure)<>'{postgres=X/postgres,service_role=X/postgres}'
    OR (SELECT proacl::text||prosecdef::text||proowner::regrole::text FROM pg_proc WHERE oid='pdc_bus_private.operation_station(uuid)'::regprocedure)<>'{postgres=X/postgres}truepostgres' THEN RAISE EXCEPTION 'r407 undo: grants changed'; END IF;
 IF EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE added_in='r407') OR EXISTS(SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r407') THEN RAISE EXCEPTION 'r407 undo: r407 rows left'; END IF;
END $p$;
