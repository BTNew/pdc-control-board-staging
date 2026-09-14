-- psql entry point. Everything, including the function replacement, rolls back.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='45s';
CREATE TEMP TABLE tune_owner_before ON COMMIT DROP AS
 SELECT public.pdc_tune_source_fields_v5(jsonb_build_object('raw_row',r.raw_row)) fields,r.evidence_id
 FROM public.pdc_pilbara_service_import_rows r
 WHERE r.batch_id='9684eefc-cc95-4258-809b-6570be1ca31f' AND r.stock_number='13073094';
CREATE TEMP TABLE tune_owner_function_before ON COMMIT DROP AS
 SELECT proacl,prosecdef,provolatile FROM pg_proc WHERE oid='public.pdc_tune_source_fields_v5(jsonb)'::regprocedure;
\ir ../../supabase/migrations/20260914054015_tune_owner_name_alias.sql
DO $normalizer_test$
DECLARE result jsonb; fixture jsonb; expected text; n integer;
BEGIN
 FOR fixture,expected IN SELECT * FROM (VALUES
  ('{"Owner Name":"HERTZ AUSTRALIA PTY LTD **"}'::jsonb,'HERTZ AUSTRALIA PTY LTD **'),
  ('{"raw_row":{"Owner Name":"  Example Pty Ltd  "}}'::jsonb,'Example Pty Ltd'),
  ('{"owner_name":"Example Pty Ltd"}'::jsonb,'Example Pty Ltd'),
  ('{"OWNER NAME":"Example Pty Ltd"}'::jsonb,'Example Pty Ltd'),
  ('{"customer_name":"Existing customer","Owner Name":"Report owner"}'::jsonb,'Existing customer'),
  ('{"client":"Existing client","Owner Name":"Report owner"}'::jsonb,'Existing client'),
  ('{"customer_name":null,"raw_row":{"Owner Name":"Report owner"}}'::jsonb,'Report owner'),
  ('{"Owner Name":"  "}'::jsonb,NULL::text),
  ('{}'::jsonb,NULL::text)) x(fixture,expected)
 LOOP
  result:=public.pdc_tune_source_fields_v5(fixture);
  IF result->>'customer_name' IS DISTINCT FROM expected THEN RAISE EXCEPTION 'customer_alias_case_failed %',fixture; END IF;
 END LOOP;
 SELECT count(*) INTO n FROM public.pdc_pilbara_service_import_rows r
 JOIN tune_owner_before b USING(evidence_id)
 WHERE public.pdc_tune_source_fields_v5(jsonb_build_object('raw_row',r.raw_row))->>'customer_name'='HERTZ AUSTRALIA PTY LTD **'
  AND (public.pdc_tune_source_fields_v5(jsonb_build_object('raw_row',r.raw_row))-'customer_name')=(b.fields-'customer_name');
 IF n<>18 THEN RAISE EXCEPTION 'retained_row_mapping_or_unrelated_fields_failed: %',n; END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p CROSS JOIN tune_owner_function_before b
  WHERE p.oid='public.pdc_tune_source_fields_v5(jsonb)'::regprocedure
   AND (p.proacl IS DISTINCT FROM b.proacl OR p.prosecdef IS DISTINCT FROM b.prosecdef OR p.provolatile IS DISTINCT FROM b.provolatile))
  THEN RAISE EXCEPTION 'function_privileges_or_volatility_changed'; END IF;
END $normalizer_test$;
\ir restore_stock13073094_customer.sql
CREATE TEMP TABLE tune_owner_after_first ON COMMIT DROP AS
 SELECT to_jsonb(v) vehicle,
  (SELECT count(*) FROM public.pdc_pilbara_service_import_receipts WHERE batch_id='baffafc5-1402-4dd3-a5c8-2a630fc1e16c') receipts
 FROM public.vehicles v WHERE id='d0d1ffef-93b6-4a67-bace-fece1bbfe893';
\ir restore_stock13073094_customer.sql
DO $replay_test$
BEGIN
 IF EXISTS(SELECT 1 FROM public.vehicles v CROSS JOIN tune_owner_after_first x
  WHERE v.id='d0d1ffef-93b6-4a67-bace-fece1bbfe893'
   AND (to_jsonb(v) IS DISTINCT FROM x.vehicle OR x.receipts<>(SELECT count(*)
    FROM public.pdc_pilbara_service_import_receipts WHERE batch_id='baffafc5-1402-4dd3-a5c8-2a630fc1e16c')))
 THEN RAISE EXCEPTION 'repair_replay_changed_state'; END IF;
END $replay_test$;
SET CONSTRAINTS ALL IMMEDIATE;
SELECT jsonb_build_object('ok',true,'rollback',true,'customer',v.customer_name,
 'projection',public.pdc_tune_vehicle_details_v5(v.id),
 'location',v.current_location,'vehicle_description',v.vehicle_description,'vin',v.vin,
 'operation_count',(SELECT count(*) FROM public.pdc_pilbara_service_operations WHERE vehicle_id=v.id),
 'operation_hours',(SELECT sum(effective_estimated_hours) FROM public.pdc_pilbara_service_operations WHERE vehicle_id=v.id),
 'booking_count',(SELECT count(*) FROM public.workshop_bookings WHERE vehicle_id=v.id),
 'immutable_evidence_customer',(SELECT customer_name FROM public.pdc_tune_intake_evidence_v5 WHERE evidence_id='e8436f7f-e0ad-4bab-adb5-f44e852d710f'),
 'checks','9 alias fixtures; 18 actual retained rows; other normalized fields; unchanged function permissions; vehicle state whitelist; 10 operational tables; immutable evidence and rows; current evidence pointer; idempotent repair replay; deferred constraints') result
FROM public.vehicles v WHERE v.id='d0d1ffef-93b6-4a67-bace-fece1bbfe893';
ROLLBACK;
