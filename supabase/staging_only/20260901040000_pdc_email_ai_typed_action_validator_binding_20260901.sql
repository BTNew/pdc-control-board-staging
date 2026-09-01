-- STAGING ONLY 20260901040000: correct the strict validator binding.
-- Append-only repair for 0300; no receipts or operational rows are rewritten.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260901040000-typed-action-validator-binding',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260901030000' AND name='pdc_email_ai_typed_action_boundary_repair_20260901')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260901040000')
     OR to_regprocedure('public.pdc_email_ai_successor_validate_instruction_20260901(jsonb)') IS NULL
  THEN RAISE EXCEPTION 'PDC_20260901040000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;
CREATE OR REPLACE FUNCTION public.apply_pdc_email_ai_typed_action_surface_20260901_strict(p_plan jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,auth,extensions AS $strict$
DECLARE actor uuid:=auth.uid(); email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); identity_ok boolean; item jsonb;
BEGIN
  -- Identity is checked before any plan/action inspection.
  IF current_setting('app.environment',true)='production' OR NOT public.pdc_monitor_staging_guard() OR auth.role()<>'authenticated' OR actor IS NULL OR email='' THEN RETURN jsonb_build_object('ok',false,'code','runtime_identity_required','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb); END IF;
  SELECT EXISTS(SELECT 1 FROM public.pdc_email_ai_successor_runtime_identities WHERE auth_user_id=actor AND normalized_email=email AND environment='staging' AND identity_purpose='pdc_email_ai_transaction_successor' AND active AND revoked_at IS NULL) AND NOT EXISTS(SELECT 1 FROM public.pdc_user_roles WHERE auth_user_id=actor AND active AND account_status='approved' AND role::text='administrator') INTO identity_ok;
  IF NOT identity_ok THEN RETURN jsonb_build_object('ok',false,'code','successor_runtime_identity_denied','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb); END IF;
  IF jsonb_typeof(p_plan)<>'object' OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p_plan) k) IS DISTINCT FROM ARRAY['instructions','schema_version','source','versions']::text[] OR (p_plan->'versions'->>'action_contract')<>'pdc-email-ai-actions-v2' OR jsonb_typeof(p_plan->'instructions')<>'array' OR NOT (SELECT bool_and(public.pdc_email_ai_successor_validate_instruction_20260901(value)) FROM jsonb_array_elements(p_plan->'instructions')) THEN
    RETURN jsonb_build_object('ok',false,'code','typed_instruction_invalid','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb);
  END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_plan->'instructions') x WHERE x->>'action_type'='operation_update') THEN
    IF (SELECT count(*) FROM jsonb_array_elements(p_plan->'instructions'))<>1 THEN RETURN jsonb_build_object('ok',false,'code','operation_update_mixed_plan_requires_replan','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb); END IF;
    RETURN public.apply_pdc_email_ai_operation_update_transaction_20260901(p_plan);
  END IF;
  RETURN public.apply_pdc_email_ai_typed_action_surface_20260901(p_plan);
END $strict$;
REVOKE ALL ON FUNCTION public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb) FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb) TO authenticated;
CREATE OR REPLACE FUNCTION public.apply_pdc_email_ai_transaction_successor_v2(p_plan jsonb)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public,auth,extensions AS $$ SELECT public.apply_pdc_email_ai_typed_action_surface_20260901_strict(p_plan) $$;
REVOKE ALL ON FUNCTION public.apply_pdc_email_ai_transaction_successor_v2(jsonb) FROM public,anon,service_role;
GRANT EXECUTE ON FUNCTION public.apply_pdc_email_ai_transaction_successor_v2(jsonb) TO authenticated;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260901040000','pdc_email_ai_typed_action_validator_binding_20260901',ARRAY[
 'Correct the strict wrapper to call the exact suffixed PostgreSQL-owned validator before source lookup, canonical dispatch or receipt writes',
 'Retain actor-first staging/non-Administrator identity checks, v2 action-contract requirement and single-action operation-update routing',
 'Preserve 0200/0300 receipts and rollback implementations without rewriting or deleting operational history; action RPC remains uninvoked by deployment verification'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
