-- STAGING ONLY: actor-first ordering for the successor hostile-action gate.
BEGIN;
SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-email-ai-successor-actor-first-gate-20260831380000',0));
DO $guard$
BEGIN
 IF current_setting('app.environment',true)='production' OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
 OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
 OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260831370000' AND name='pdc_email_ai_successor_hostile_action_gate')<>1
 OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260831380000')
 THEN RAISE EXCEPTION 'PDC_EMAIL_AI_SUCCESSOR_3800_STAGING_PRECONDITION_FAILED' USING errcode='55000'; END IF;
END $guard$;
CREATE OR REPLACE FUNCTION public.apply_pdc_email_ai_transaction_successor(p_plan jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,auth,extensions
AS $gate$
DECLARE v_actor uuid:=auth.uid();v_email text:=lower(btrim(coalesce(auth.jwt()->>'email','')));
BEGIN
 IF auth.role()<>'authenticated' OR v_actor IS NULL OR v_email='' THEN RETURN jsonb_build_object('ok',false,'code','runtime_identity_required','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb); END IF;
 IF NOT EXISTS(SELECT 1 FROM public.pdc_email_ai_successor_runtime_identities WHERE auth_user_id=v_actor AND normalized_email=v_email AND environment='staging' AND identity_purpose='pdc_email_ai_transaction_successor' AND active AND revoked_at IS NULL)
    OR EXISTS(SELECT 1 FROM public.pdc_user_roles WHERE auth_user_id=v_actor AND active AND account_status='approved' AND role::text='administrator')
 THEN RETURN jsonb_build_object('ok',false,'code','successor_runtime_identity_denied','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb); END IF;
 IF jsonb_typeof(p_plan)='object' AND jsonb_typeof(p_plan->'instructions')='array' AND EXISTS(SELECT 1 FROM jsonb_array_elements(p_plan->'instructions') x WHERE x->>'action_type' NOT IN('activate_from_navision','location_set','workgroup_requirement_set','operation_upsert','parts_eta_set','parts_ordered','parts_complete','notes_append','job_card_upsert','sublet_booking_upsert','rft_transfer','rft_collect'))
 THEN RETURN jsonb_build_object('ok',false,'code','typed_instruction_invalid','disposition','FAILED_QUEUED_RETRY','actions','[]'::jsonb); END IF;
 RETURN public.apply_pdc_email_ai_transaction_successor__pre_hostile_gate(p_plan);
END $gate$;
REVOKE ALL ON FUNCTION public.apply_pdc_email_ai_transaction_successor(jsonb) FROM public,anon,service_role; GRANT EXECUTE ON FUNCTION public.apply_pdc_email_ai_transaction_successor(jsonb) TO authenticated;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260831380000','pdc_email_ai_successor_actor_first_gate',ARRAY['Authenticated successor identity and Administrator denial occur before plan/action inspection','Unknown action types fail closed after actor binding and before source lookup or canonical dispatch','Production sentinel and service-role runtime execution remain denied']);
NOTIFY pgrst,'reload schema'; COMMIT;
