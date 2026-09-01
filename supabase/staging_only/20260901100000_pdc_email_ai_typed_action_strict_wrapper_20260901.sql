-- STAGING ONLY 20260901100000: bind the authenticated v2 entrypoint to
-- the complete server-side plan validator before any source lookup or dispatch.
-- Appends to 0900; no receipt, rule or operational history is rewritten.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-20260901100000-v2-strict-wrapper',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $guard$
BEGIN
  IF current_user<>'postgres' OR session_user<>'postgres'
     OR current_setting('app.environment',true)='production'
     OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
     OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
     OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260901090000' AND name='pdc_email_ai_typed_action_timestamp_acl_20260901')<>1
     OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260901100000')
     OR to_regprocedure('public.pdc_email_ai_successor_validate_v2_plan_20260901(jsonb)') IS NULL
     OR to_regprocedure('public.pdc_email_ai_successor_validate_v2_instruction_20260901(jsonb)') IS NULL
     OR to_regprocedure('public.apply_pdc_email_ai_operation_update_transaction_20260901(jsonb)') IS NULL
     OR to_regprocedure('public.apply_pdc_email_ai_typed_action_surface_20260901(jsonb)') IS NULL
  THEN RAISE EXCEPTION 'PDC_20260901100000_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;

-- This is the single least-authority v2 boundary. The complete plan validator
-- owns top-level schema, digest/version/provenance, identity, evidence and
-- per-action checks. It must run before any source lookup or canonical call.
CREATE OR REPLACE FUNCTION public.apply_pdc_email_ai_typed_action_surface_20260901_strict(p_plan jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,auth,extensions AS $strict$
DECLARE actor uuid:=auth.uid(); email text:=lower(btrim(coalesce(auth.jwt()->>'email',''))); identity_ok boolean; item jsonb; normalized jsonb; normalized_items jsonb;
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

  -- Full v2 plan validator is called before source lookup or canonical dispatch.
  IF NOT public.pdc_email_ai_successor_validate_v2_plan_20260901(p_plan) THEN
    RETURN jsonb_build_object('ok',false,'code','typed_v2_plan_invalid','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb);
  END IF;

  IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_plan->'instructions') x WHERE x->>'action_type'='operation_update') THEN
    IF (SELECT count(*) FROM jsonb_array_elements(p_plan->'instructions'))<>1 THEN
      RETURN jsonb_build_object('ok',false,'code','operation_update_mixed_plan_requires_replan','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb);
    END IF;
    RETURN public.apply_pdc_email_ai_operation_update_transaction_20260901(p_plan);
  END IF;

  -- Adapt only after the complete strict v2 preflight; the retained 0200
  -- executor receives only a server-built compatibility projection.
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'instruction_id',x->>'instruction_id',
    'vehicle_id',x->>'vehicle_id',
    'identity',jsonb_build_object(
      'stock_number',x->'identity'->'stock_number',
      'vin',x->'identity'->'vin',
      'backend_record_id',x->'identity'->'backend_record_id'
    ),
    'expected_vehicle_version',(x->'expected_state'->>'vehicle_version')::integer,
    'action_type',x->>'action_type',
    'payload',x->'payload',
    'evidence_refs',coalesce((SELECT jsonb_agg(r->>'ref') FROM jsonb_array_elements(x->'evidence_refs') r),'[]'::jsonb)
  ) ORDER BY x->>'instruction_id'),'[]'::jsonb)
  INTO normalized_items
  FROM jsonb_array_elements(p_plan->'instructions') q(x);
  normalized:=jsonb_build_object(
    'schema_version','pdc-email-ai-plan-v1',
    'source',jsonb_build_object(
      'receipt_id',p_plan->>'source_receipt_id',
      'source_digest',p_plan->>'source_digest',
      'evidence_digest',p_plan->>'evidence_digest',
      'thread_id',p_plan->>'source_thread_id',
      'message_id',p_plan->>'source_message_id',
      'attachment_digests',p_plan->'attachment_digests'
    ),
    'versions',jsonb_build_object('action_contract','pdc-email-ai-actions-v2','taxonomy',p_plan->'versions'->>'taxonomy_version'),
    'instructions',normalized_items
  );
  RETURN public.apply_pdc_email_ai_typed_action_surface_20260901(normalized);
END $strict$;

-- The strict wrapper is the only callable v2 action boundary. Retained low-
-- level/compatibility functions remain unavailable to all runtime roles.
REVOKE ALL ON FUNCTION public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb) TO authenticated;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260901100000','pdc_email_ai_typed_action_strict_wrapper_20260901',ARRAY[
 'Full pdc_email_ai_successor_validate_v2_plan_20260901 is called by the strict authenticated entrypoint before source lookup or canonical dispatch',
 'Strict wrapper source is replay-guarded to the 20260901090000 predecessor and records the exact append-only migration identity',
 'Legacy low-level typed apply and compatibility alias remain denied; only the strict v2 entrypoint is authenticated-callable',
 'Production sentinel, mailbox/outbound paths and operational receipt state remain untouched by migration installation'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
