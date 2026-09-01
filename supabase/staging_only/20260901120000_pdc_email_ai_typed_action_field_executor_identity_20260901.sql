-- STAGING ONLY 20260901120000: bind planned actions to the field-level
-- affected-row executor and preserve unbound review identity evidence.
-- No low-level compatibility projection is reachable from the strict boundary.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260901120000-typed-action-field-executor-identity',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260901110000' AND name='pdc_email_ai_typed_action_review_receipts_20260901')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260901120000')
     OR to_regprocedure('public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)') IS NULL
     OR to_regprocedure('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)') IS NULL
     OR to_regprocedure('public.pdc_email_ai_successor_validate_v2_instruction_20260901(jsonb)') IS NULL
     OR to_regprocedure('public.pdc_email_ai_successor_validate_v2_plan_20260901(jsonb)') IS NULL
     OR to_regprocedure('public.pdc_email_ai_successor_record_non_dispatch_v2_20260901(jsonb)') IS NULL
     OR to_regprocedure('public.apply_pdc_email_ai_operation_update_transaction_20260901(jsonb)') IS NULL
  THEN RAISE EXCEPTION 'PDC_20260901120000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;

-- The preceding 0800 identity contract already defines the canonical validator.
-- Rebind its durable source definition so vehicle_id NULL is accepted only for
-- unbound review note evidence, while all authoritative-bound plans still use
-- exact UUID/Stock/VIN/Navision checks.
DO $validator_rebind$
DECLARE definition text;
BEGIN
  SELECT pg_get_functiondef('public.pdc_email_ai_successor_validate_v2_instruction_20260901(jsonb)'::regprocedure) INTO definition;
  IF definition IS NULL OR position('p_item->>''vehicle_id'' !~ ''^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$''' in definition)=0
     OR position('p_item->''identity''->>''vehicle_id''<>p_item->>''vehicle_id''' in definition)=0
  THEN RAISE EXCEPTION 'PDC_20260901120000_VALIDATOR_SOURCE_GUARD_FAILED' USING errcode='55000'; END IF;
  definition:=replace(definition,
    'p_item->>''vehicle_id'' !~ ''^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$''',
    'NOT (p_item->>''vehicle_id'' ~ ''^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'' OR (p_item->>''vehicle_id'' IS NULL AND p_item->>''decision_disposition''=''review'' AND p_item->>''action_type''=''note_append''))');
  definition:=replace(definition,
    'p_item->''identity''->>''vehicle_id''<>p_item->>''vehicle_id''',
    'NOT ((p_item->''identity''->>''vehicle_id'' IS NULL AND p_item->>''vehicle_id'' IS NULL) OR p_item->''identity''->>''vehicle_id''=p_item->>''vehicle_id'')');
  EXECUTE definition;
END $validator_rebind$;

DO $plan_rebind$
DECLARE definition text;
BEGIN
  SELECT pg_get_functiondef('public.pdc_email_ai_successor_validate_v2_plan_20260901(jsonb)'::regprocedure) INTO definition;
  IF definition IS NULL OR position('unresolved:=identity->>''stock_number'' IS NULL AND identity->>''vin'' IS NULL AND identity->>''backend_record_id'' IS NULL' in definition)=0
  THEN RAISE EXCEPTION 'PDC_20260901120000_PLAN_VALIDATOR_SOURCE_GUARD_FAILED' USING errcode='55000'; END IF;
  definition:=replace(definition,
    'unresolved:=identity->>''stock_number'' IS NULL AND identity->>''vin'' IS NULL AND identity->>''backend_record_id'' IS NULL',
    'unresolved:=item->>''vehicle_id'' IS NULL OR (identity->>''stock_number'' IS NULL AND identity->>''vin'' IS NULL AND identity->>''backend_record_id'' IS NULL)');
  EXECUTE definition;
END $plan_rebind$;

-- The strict v2 boundary validates first, preserves review/unsupported/conflict
-- as non-dispatch receipts, retains the dedicated operation-update path, and
-- sends every remaining planned action directly to the field-level affected-row
-- executor. This avoids identifier-only compatibility readback.
CREATE OR REPLACE FUNCTION public.apply_pdc_email_ai_typed_action_surface_20260901_strict(p_plan jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,auth,extensions AS $strict$
DECLARE actor uuid:=auth.uid(); email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); identity_ok boolean;
BEGIN
  IF current_setting('app.environment',true)='production' OR NOT public.pdc_monitor_staging_guard() OR auth.role()<>'authenticated' OR actor IS NULL OR email='' THEN
    RETURN jsonb_build_object('ok',false,'code','runtime_identity_required','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb);
  END IF;
  SELECT EXISTS(
    SELECT 1 FROM public.pdc_email_ai_successor_runtime_identities
    WHERE auth_user_id=actor AND normalized_email=email AND environment='staging'
      AND identity_purpose='pdc_email_ai_transaction_successor' AND active AND revoked_at IS NULL
  ) AND NOT EXISTS(
    SELECT 1 FROM public.pdc_user_roles
    WHERE auth_user_id=actor AND active AND account_status='approved' AND role::text='administrator'
  ) INTO identity_ok;
  IF NOT identity_ok THEN
    RETURN jsonb_build_object('ok',false,'code','successor_runtime_identity_denied','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb);
  END IF;
  IF NOT public.pdc_email_ai_successor_validate_v2_plan_20260901(p_plan) THEN
    RETURN jsonb_build_object('ok',false,'code','typed_v2_plan_invalid','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb);
  END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_plan->'instructions') x WHERE x->>'decision_disposition'<>'planned') THEN
    RETURN public.pdc_email_ai_successor_record_non_dispatch_v2_20260901(p_plan);
  END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_plan->'instructions') x WHERE x->>'action_type'='operation_update') THEN
    IF (SELECT count(*) FROM jsonb_array_elements(p_plan->'instructions'))<>1 THEN
      RETURN jsonb_build_object('ok',false,'code','operation_update_mixed_plan_requires_replan','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb);
    END IF;
    RETURN public.apply_pdc_email_ai_operation_update_transaction_20260901(p_plan);
  END IF;
  RETURN public.pdc_email_ai_successor_execute_v2_20260901(p_plan);
END $strict$;
REVOKE ALL ON FUNCTION public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb) FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb) TO authenticated;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260901120000','pdc_email_ai_typed_action_field_executor_identity_20260901',ARRAY[
 'Strict all-planned actions route to the field-level affected-row executor with booking, work-complete and note timeline parity',
 'Unbound review identity evidence keeps nullable vehicle_id and cannot dispatch or invent a vehicle binding',
 'Unknown identity and duplicate VIN plans remain typed review evidence; no last-context fallback is permitted',
 'Operation update retains its dedicated optimistic-concurrency transaction path',
 'Strict authenticated-only staging ACL, append-only receipts, Production and mailbox boundaries remain unchanged'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
