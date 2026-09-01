-- STAGING ONLY 20260901090000: strict timestamp validation and least-authority ACL closure.
-- Appends to 0800. No production objects, generic DML, service-role authority,
-- mailbox access, or operational writes are introduced by this migration.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260901090000-typed-action-timestamp-acl',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260901080000' AND name='pdc_email_ai_typed_action_identity_contract_20260901')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260901090000')
     OR to_regprocedure('public.pdc_email_ai_successor_validate_v2_plan_20260901(jsonb)') IS NULL
     OR to_regprocedure('public.pdc_email_ai_successor_validate_v2_instruction_20260901(jsonb)') IS NULL
  THEN RAISE EXCEPTION 'PDC_20260901090000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;

-- These helpers use a strict lexical ISO shape, a typed PostgreSQL cast inside
-- an exception boundary, and a date round-trip. Invalid values therefore fail
-- before any executor can reach a canonical ::date/::timestamptz cast.
CREATE OR REPLACE FUNCTION public.pdc_email_ai_successor_iso_date_20260901(p_value text)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $iso_date$
DECLARE parsed date;
BEGIN
  -- timestamp_date_invalid is fail-closed at this typed helper boundary.
  IF p_value IS NULL OR p_value !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN RETURN false; END IF;
  parsed:=p_value::date;
  RETURN to_char(parsed,'YYYY-MM-DD')=p_value;
EXCEPTION WHEN others THEN RETURN false;
END $iso_date$;

CREATE OR REPLACE FUNCTION public.pdc_email_ai_successor_iso_timestamptz_20260901(p_value text)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog,public AS $iso_timestamp$
DECLARE parsed timestamptz;
BEGIN
  -- timestamp_timestamptz_invalid is fail-closed at this typed helper boundary.
  IF p_value IS NULL OR p_value !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([.][0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$'
     OR NOT public.pdc_email_ai_successor_iso_date_20260901(substr(p_value,1,10)) THEN RETURN false; END IF;
  parsed:=p_value::timestamptz;
  RETURN parsed IS NOT NULL
     AND to_char(parsed AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS') IS NOT NULL;
EXCEPTION WHEN others THEN RETURN false;
END $iso_timestamp$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_successor_iso_date_20260901(text) FROM public,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.pdc_email_ai_successor_iso_timestamptz_20260901(text) FROM public,anon,authenticated,service_role;

-- Rebind the instruction validator with typed date/timestamp checks. The
-- action key set and all other exact contracts remain unchanged from 0800.
CREATE OR REPLACE FUNCTION public.pdc_email_ai_successor_validate_v2_instruction_20260901(p_item jsonb)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog,public AS $validate$
DECLARE p jsonb; expected_taxonomy text; unresolved boolean;
BEGIN
  IF jsonb_typeof(p_item)<>'object'
     OR (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p_item) x) IS DISTINCT FROM ARRAY['action_type','audit_event_ref','decision_disposition','evidence_refs','expected_state','identity','instruction_id','payload','provenance','reason','required_evidence','vehicle_id']::text[]
     OR p_item->>'action_type' NOT IN('activate_vehicle','operation_add','operation_update','parts_eta_set','parts_complete','booking_set','booking_move','booking_cancel','required_work_set','work_complete','note_append','location_set','rft_transfer','rft_collect')
     OR p_item->>'decision_disposition' NOT IN('planned','review','unsupported','conflict')
     OR p_item->>'vehicle_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
     OR nullif(btrim(p_item->>'instruction_id'),'') IS NULL
     OR jsonb_typeof(p_item->'payload')<>'object'
     OR jsonb_typeof(p_item->'evidence_refs')<>'array' OR jsonb_array_length(p_item->'evidence_refs') NOT BETWEEN 1 AND 20
     OR jsonb_typeof(p_item->'identity')<>'object'
     OR (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p_item->'identity') x) IS DISTINCT FROM ARRAY['backend_record_id','stock_number','vehicle_id','vin']::text[]
     OR p_item->'identity'->>'vehicle_id'<>p_item->>'vehicle_id'
     OR jsonb_typeof(p_item->'identity'->'stock_number') NOT IN('null','string')
     OR jsonb_typeof(p_item->'identity'->'vin') NOT IN('null','string')
     OR jsonb_typeof(p_item->'identity'->'backend_record_id') NOT IN('null','string')
     OR jsonb_typeof(p_item->'expected_state')<>'object'
     OR (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p_item->'expected_state') x) IS DISTINCT FROM ARRAY['backend_revision','vehicle_version']::text[]
     OR p_item->'expected_state'->>'vehicle_version' !~ '^[1-9][0-9]*$'
     OR p_item->'expected_state'->>'backend_revision' !~ '^[0-9]+$'
     OR jsonb_typeof(p_item->'provenance')<>'object'
     OR jsonb_typeof(p_item->'required_evidence')<>'array'
     OR nullif(btrim(p_item->>'audit_event_ref'),'') IS NULL
     OR nullif(btrim(p_item->>'reason'),'') IS NULL
  THEN RETURN false; END IF;
  unresolved:=p_item->'identity'->>'stock_number' IS NULL AND p_item->'identity'->>'vin' IS NULL AND p_item->'identity'->>'backend_record_id' IS NULL;
  IF unresolved THEN
    IF p_item->>'decision_disposition'<>'review' OR p_item->>'action_type'<>'note_append' THEN RETURN false; END IF;
  ELSIF (p_item->'identity'->>'stock_number' IS NOT NULL AND p_item->'identity'->>'stock_number' !~ '^[A-Z0-9][A-Z0-9-]{3,79}$')
     OR (p_item->'identity'->>'vin' IS NOT NULL AND p_item->'identity'->>'vin' !~ '^[A-HJ-NPR-Z0-9]{17}$')
     OR (p_item->'identity'->>'backend_record_id' IS NOT NULL AND p_item->'identity'->>'backend_record_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$') THEN RETURN false;
  END IF;
  p:=p_item->'payload';
  IF p_item->>'action_type' IN('operation_add','operation_update') THEN
    expected_taxonomy:=public.pdc_email_ai_successor_taxonomy_disposition_20260901(p->>'taxonomy_version',p->>'description',p->>'work_key');
    IF (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p) x) IS DISTINCT FROM ARRAY['description','estimated_hours','operation_no','source_row_no','source_uid','taxonomy_disposition','taxonomy_version','work_key']::text[]
       OR p->>'operation_no' !~ '^OP[1-9][0-9]{0,2}$' OR p->>'source_row_no' !~ '^[1-9][0-9]*$'
       OR p->>'taxonomy_version'<>'pdc-operation-taxonomy-proposed/v1' OR p->>'taxonomy_disposition' NOT IN('classified','review','unsupported','conflict')
       OR p->>'taxonomy_disposition'<>expected_taxonomy OR nullif(btrim(p->>'source_uid'),'') IS NULL
       OR length(p->>'description') NOT BETWEEN 1 AND 500 OR p->>'description'<>btrim(p->>'description')
       OR NOT ((jsonb_typeof(p->'estimated_hours')='number' AND (p->>'estimated_hours')::numeric BETWEEN 0 AND 999.99) OR (p_item->>'decision_disposition'<>'planned' AND jsonb_typeof(p->'estimated_hours')='null'))
    THEN RETURN false; END IF;
  ELSIF p_item->>'action_type'='activate_vehicle' THEN
    IF (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p) x) IS DISTINCT FROM ARRAY['backend_record_id','job_card_number','stock_number','vin']::text[] OR p->>'backend_record_id' !~ '^[0-9a-f-]{36}$' OR p->>'stock_number' !~ '^[A-Z0-9][A-Z0-9-]{3,79}$' THEN RETURN false; END IF;
  ELSIF p_item->>'action_type'='parts_eta_set' THEN
    IF (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p) x) IS DISTINCT FROM ARRAY['eta']::text[] OR (jsonb_typeof(p->'eta')<>'null' AND NOT public.pdc_email_ai_successor_iso_date_20260901(p->>'eta')) THEN RETURN false; END IF;
  ELSIF p_item->>'action_type' IN('parts_complete','rft_transfer','rft_collect') THEN
    IF (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p) x) IS DISTINCT FROM ARRAY['confirmed']::text[] OR jsonb_typeof(p->'confirmed')<>'boolean' OR p->>'confirmed'<>'true' THEN RETURN false; END IF;
  ELSIF p_item->>'action_type'='booking_set' THEN
    IF (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p) x) IS DISTINCT FROM ARRAY['bay_number','duration_minutes','scheduled_start_at','stage_code','technician_id']::text[] OR p->>'bay_number' !~ '^[1-9][0-9]*$' OR p->>'duration_minutes' !~ '^[1-9][0-9]*$' OR (p->>'duration_minutes')::integer<60 OR nullif(btrim(p->>'stage_code'),'') IS NULL OR NOT public.pdc_email_ai_successor_iso_timestamptz_20260901(p->>'scheduled_start_at') THEN RETURN false; END IF;
  ELSIF p_item->>'action_type'='booking_move' THEN
    IF (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p) x) IS DISTINCT FROM ARRAY['booking_id','bay_number','duration_minutes','expected_booking_version','override_reason','scheduled_start_at','stage_code']::text[] OR p->>'booking_id' !~ '^[0-9a-f-]{36}$' OR p->>'expected_booking_version' !~ '^[1-9][0-9]*$' OR p->>'bay_number' !~ '^[1-9][0-9]*$' OR p->>'duration_minutes' !~ '^[1-9][0-9]*$' OR (p->>'duration_minutes')::integer<60 OR nullif(btrim(p->>'stage_code'),'') IS NULL OR NOT public.pdc_email_ai_successor_iso_timestamptz_20260901(p->>'scheduled_start_at') THEN RETURN false; END IF;
  ELSIF p_item->>'action_type'='booking_cancel' THEN
    IF (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p) x) IS DISTINCT FROM ARRAY['booking_id','expected_booking_version','reason']::text[] OR p->>'booking_id' !~ '^[0-9a-f-]{36}$' OR p->>'expected_booking_version' !~ '^[1-9][0-9]*$' OR nullif(btrim(p->>'reason'),'') IS NULL THEN RETURN false; END IF;
  ELSIF p_item->>'action_type'='required_work_set' THEN
    IF (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p) x) IS DISTINCT FROM ARRAY['required','work_key']::text[] OR upper(p->>'work_key') NOT IN('PARTS','TINT','HOIST','FITTING','BUS_4X4','FABRICATION','ELECTRICAL','TYRE','PIT_INSPECTION','SUBLET') OR jsonb_typeof(p->'required')<>'boolean' THEN RETURN false; END IF;
  ELSIF p_item->>'action_type'='work_complete' THEN
    IF (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p) x) IS DISTINCT FROM ARRAY['booking_id','completed_at','expected_booking_version','work_key']::text[] OR p->>'booking_id' !~ '^[0-9a-f-]{36}$' OR p->>'expected_booking_version' !~ '^[1-9][0-9]*$' OR upper(p->>'work_key') NOT IN('PARTS','TINT','HOIST','FITTING','BUS_4X4','FABRICATION','ELECTRICAL','TYRE','PIT_INSPECTION','SUBLET') OR NOT public.pdc_email_ai_successor_iso_timestamptz_20260901(p->>'completed_at') THEN RETURN false; END IF;
  ELSIF p_item->>'action_type'='note_append' THEN
    IF (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p) x) IS DISTINCT FROM ARRAY['event_at','text']::text[] OR nullif(btrim(p->>'text'),'') IS NULL OR NOT public.pdc_email_ai_successor_iso_timestamptz_20260901(p->>'event_at') THEN RETURN false; END IF;
  ELSIF p_item->>'action_type'='location_set' THEN
    IF (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p) x) IS DISTINCT FROM ARRAY['location','reason']::text[] OR upper(p->>'location') NOT IN('YH','PMB','QC','RFT','OTHER','IT') OR nullif(btrim(p->>'reason'),'') IS NULL THEN RETURN false; END IF;
  ELSE RETURN false;
  END IF;
  RETURN true;
END $validate$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_successor_validate_v2_instruction_20260901(jsonb) FROM public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION public.pdc_email_ai_successor_validate_v2_plan_20260901(p_plan jsonb)
RETURNS boolean LANGUAGE plpgsql STABLE SET search_path=pg_catalog,public,extensions AS $plan_validate$
DECLARE item jsonb; ref jsonb; versions jsonb; identity jsonb; provenance jsonb; vehicle public.vehicles%rowtype; unresolved boolean;
BEGIN
  IF jsonb_typeof(p_plan)<>'object'
     OR (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p_plan) x) IS DISTINCT FROM ARRAY['aggregate_disposition','attachment_digests','created_at','environment','evidence_digest','instructions','plan_id','planner_failure_reason','planner_status','schema_version','source_digest','source_message_id','source_receipt_id','source_thread_id','versions']::text[]
     OR p_plan->>'schema_version'<>'pdc-email-ai-plan-v1' OR p_plan->>'environment'<>'staging'
     OR p_plan->>'plan_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' OR p_plan->>'source_receipt_id' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
     OR p_plan->>'source_digest' !~ '^[a-f0-9]{64}$' OR p_plan->>'evidence_digest' !~ '^[a-f0-9]{64}$'
     OR nullif(btrim(p_plan->>'source_message_id'),'') IS NULL OR nullif(btrim(p_plan->>'source_thread_id'),'') IS NULL
     OR p_plan->>'aggregate_disposition' NOT IN('planned','applied','partial_failure','review','quarantined','no_actions')
     OR p_plan->>'planner_status' NOT IN('available','unavailable','failed')
     OR (p_plan->'planner_failure_reason' IS NOT NULL AND jsonb_typeof(p_plan->'planner_failure_reason') NOT IN('null','string'))
     OR (jsonb_typeof(p_plan->'planner_failure_reason')='string' AND length(p_plan->>'planner_failure_reason')>1000)
     OR NOT public.pdc_email_ai_successor_iso_timestamptz_20260901(p_plan->>'created_at')
     OR jsonb_typeof(p_plan->'attachment_digests')<>'array' OR (jsonb_typeof(p_plan->'attachment_digests')='array' AND jsonb_array_length(p_plan->'attachment_digests')>25)
     OR (jsonb_typeof(p_plan->'attachment_digests')='array' AND EXISTS(SELECT 1 FROM jsonb_array_elements(p_plan->'attachment_digests') d WHERE jsonb_typeof(d)<>'string' OR d #>> '{}' !~ '^[a-f0-9]{64}$'))
     OR (jsonb_typeof(p_plan->'attachment_digests')='array' AND (SELECT count(*) FROM jsonb_array_elements_text(p_plan->'attachment_digests') d)<>(SELECT count(DISTINCT d) FROM jsonb_array_elements_text(p_plan->'attachment_digests') d))
     OR jsonb_typeof(p_plan->'versions')<>'object'
     OR (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(p_plan->'versions') x) IS DISTINCT FROM ARRAY['business_rule_version','evidence_digest','model_version','planner_version','prompt_version','ruleset_version','source_digest','supabase_action_contract_version','taxonomy_version','transport_release_version']::text[]
     OR p_plan->'versions'->>'supabase_action_contract_version'<>'pdc-email-ai-action-request-v1' OR p_plan->'versions'->>'taxonomy_version'<>'pdc-operation-taxonomy-proposed/v1'
     OR p_plan->'versions'->>'source_digest'<>p_plan->>'source_digest' OR p_plan->'versions'->>'evidence_digest'<>p_plan->>'evidence_digest'
     OR EXISTS(SELECT 1 FROM jsonb_each(p_plan->'versions') x WHERE jsonb_typeof(x.value)<>'string' OR nullif(btrim(x.value #>> '{}'),'') IS NULL)
     OR jsonb_typeof(p_plan->'instructions')<>'array' OR jsonb_array_length(p_plan->'instructions')>200
  THEN RETURN false; END IF;
  versions:=p_plan->'versions';
  FOR item IN SELECT value FROM jsonb_array_elements(p_plan->'instructions') LOOP
    IF NOT public.pdc_email_ai_successor_validate_v2_instruction_20260901(item) THEN RETURN false; END IF;
    identity:=item->'identity';
    unresolved:=identity->>'stock_number' IS NULL AND identity->>'vin' IS NULL AND identity->>'backend_record_id' IS NULL;
    IF NOT unresolved THEN
      SELECT * INTO vehicle FROM public.vehicles WHERE id=(item->>'vehicle_id')::uuid;
      IF NOT FOUND THEN RETURN false; END IF;
      IF identity->>'stock_number' IS NOT NULL AND upper(identity->>'stock_number') IS DISTINCT FROM upper(vehicle.stock_number_normalized) THEN RETURN false; END IF;
      IF identity->>'vin' IS NOT NULL AND upper(identity->>'vin') IS DISTINCT FROM upper(vehicle.vin_normalized) THEN RETURN false; END IF;
      IF identity->>'backend_record_id' IS NOT NULL AND vehicle.source_record_id_normalized IS DISTINCT FROM public.normalize_vehicle_source_identifier(identity->>'backend_record_id') THEN RETURN false; END IF;
    END IF;
    provenance:=item->'provenance';
    IF (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(provenance) x) IS DISTINCT FROM ARRAY['business_rule_version','evidence_digest','model_version','planner_version','prompt_version','ruleset_version','source_digest','supabase_action_contract_version','taxonomy_version','transport_release_version']::text[]
       OR EXISTS(SELECT 1 FROM jsonb_each(provenance) x WHERE jsonb_typeof(x.value)<>'string' OR nullif(btrim(x.value #>> '{}'),'') IS NULL)
       OR provenance->>'source_digest'<>p_plan->>'source_digest' OR provenance->>'evidence_digest'<>p_plan->>'evidence_digest' THEN RETURN false; END IF;
    IF provenance->>'business_rule_version'<>versions->>'business_rule_version' OR provenance->>'model_version'<>versions->>'model_version' OR provenance->>'planner_version'<>versions->>'planner_version' OR provenance->>'prompt_version'<>versions->>'prompt_version' OR provenance->>'ruleset_version'<>versions->>'ruleset_version' OR provenance->>'taxonomy_version'<>versions->>'taxonomy_version' OR provenance->>'transport_release_version'<>versions->>'transport_release_version' OR provenance->>'supabase_action_contract_version'<>versions->>'supabase_action_contract_version' THEN RETURN false; END IF;
    FOR ref IN SELECT value FROM jsonb_array_elements(item->'evidence_refs') LOOP
      IF jsonb_typeof(ref)<>'object' OR (SELECT array_agg(x ORDER BY x) FROM jsonb_object_keys(ref) x) IS DISTINCT FROM ARRAY['kind','ref','required_for_action']::text[] OR nullif(btrim(ref->>'kind'),'') IS NULL OR nullif(btrim(ref->>'ref'),'') IS NULL OR jsonb_typeof(ref->'required_for_action')<>'boolean' THEN RETURN false; END IF;
    END LOOP;
  END LOOP;
  RETURN true;
END $plan_validate$;
REVOKE ALL ON FUNCTION public.pdc_email_ai_successor_validate_v2_plan_20260901(jsonb) FROM public,anon,authenticated,service_role;

-- Only the full strict v2 identity boundary is browser-authenticated callable.
-- The original apply function and compatibility alias remain retained as
-- rollback evidence but cannot be invoked by any runtime role.
REVOKE ALL ON FUNCTION public.apply_pdc_email_ai_typed_action_surface_20260901(jsonb) FROM public,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.apply_pdc_email_ai_transaction_successor_v2(jsonb) FROM public,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb) FROM public,anon,service_role;
REVOKE ALL ON FUNCTION public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb) TO authenticated;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260901090000','pdc_email_ai_typed_action_timestamp_acl_20260901',ARRAY[
 'Strict ISO date and timezone-bearing timestamp helpers reject malformed values with typed cast and round-trip checks before canonical dispatch',
 'The v2 PostgreSQL instruction and plan validators use strict date/timestamp helpers for Parts ETA, booking set/move, work complete, note event and created_at',
 'The low-level typed apply RPC and compatibility alias are revoked from public, anon, authenticated and service_role; only the strict v2 entrypoint is authenticated-callable'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
