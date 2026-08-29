-- STAGING ONLY 785: narrow authenticated dealer-scoped read contracts.
-- No direct table grants; all source access remains behind SECURITY DEFINER
-- functions with server-owned dealer scope and existing role checks.
BEGIN;
SET LOCAL lock_timeout='15s';
SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-785-narrow-authenticated-contracts',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;
DO $guard$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' OR NOT public.pdc_monitor_staging_guard()
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
    OR (SELECT (version,name)::text FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' ORDER BY version::bigint DESC LIMIT 1) IS DISTINCT FROM '(20260830181000,784_stage_a_integrity_projection)'
    OR to_regprocedure('public.get_vehicle_workshop_detail(uuid)') IS NULL
    OR to_regprocedure('public.pdc_auditor_actor_scope()') IS NULL
    OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260830182000')
 THEN RAISE EXCEPTION 'PDC_785_CURRENT_HEAD_GUARD_FAILED' USING errcode='55000'; END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.get_vehicle_workshop_detail_scoped(p_vehicle_id uuid,p_dealer_code text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public
AS $fn$
DECLARE v_scope jsonb; v_dealer text; v_vehicle_dealer text;
BEGIN
 v_scope:=public.pdc_auditor_actor_scope();
 v_dealer:=btrim(coalesce(p_dealer_code,''));
 IF v_dealer NOT IN ('14450','37047') OR v_scope->>'environment' IS DISTINCT FROM 'staging' OR v_scope->>'dealer_code' IS DISTINCT FROM v_dealer THEN
   RETURN jsonb_build_object('ok',false,'code','dealer_scope_denied','data',jsonb_build_object('environment','staging','dealer_code',v_dealer));
 END IF;
 SELECT public.pdc_auditor_vehicle_dealer(v.id) INTO v_vehicle_dealer
 FROM public.vehicles v
 WHERE v.id=p_vehicle_id AND v.deleted_at IS NULL AND v.lifecycle_state='active';
 IF v_vehicle_dealer IS DISTINCT FROM v_dealer THEN
   RETURN jsonb_build_object('ok',false,'code','vehicle_not_in_dealer_scope','data',jsonb_build_object('vehicle_id',p_vehicle_id,'dealer_code',v_dealer));
 END IF;
 RETURN public.get_vehicle_workshop_detail(p_vehicle_id);
END $fn$;
REVOKE ALL ON FUNCTION public.get_vehicle_workshop_detail_scoped(uuid,text) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_vehicle_workshop_detail_scoped(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_pdc_email_intake_status(p_intake_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,public
AS $fn$
DECLARE v_scope jsonb; v_result jsonb;
BEGIN
 v_scope:=public.pdc_auditor_actor_scope();
 SELECT jsonb_build_object(
   'ok',true,'code','pdc_email_intake_status','data',jsonb_build_object(
     'id',i.id,'status',i.status::text,'received_at',i.received_at,'updated_at',i.updated_at,
     'last_attempt_at',i.last_attempt_at,'last_success_at',i.last_success_at,
     'next_attempt_at',i.next_attempt_at,'queue_attempts',i.queue_attempts,
     'permanent_failure',i.permanent_failure,'last_error_code',i.last_error_code,
     'linked_vehicle_id',i.linked_vehicle_id,'dealer_code',v_scope->>'dealer_code'))
 INTO v_result
 FROM public.ai_email_intake i
 JOIN public.vehicles v ON v.id=i.linked_vehicle_id
 WHERE i.id=p_intake_id AND v.deleted_at IS NULL AND v.lifecycle_state='active'
   AND public.pdc_auditor_vehicle_dealer(v.id)=v_scope->>'dealer_code';
 RETURN coalesce(v_result,jsonb_build_object('ok',false,'code','email_intake_not_in_dealer_scope','data',jsonb_build_object('dealer_code',v_scope->>'dealer_code')));
END $fn$;
REVOKE ALL ON FUNCTION public.get_pdc_email_intake_status(uuid) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_pdc_email_intake_status(uuid) TO authenticated;

DO $verify$
DECLARE d text;
BEGIN
 SELECT pg_get_functiondef('public.get_vehicle_workshop_detail_scoped(uuid,text)'::regprocedure) INTO d;
 IF position('pdc_auditor_actor_scope' in d)=0 OR position('pdc_auditor_vehicle_dealer' in d)=0 OR position('get_vehicle_workshop_detail' in d)=0 OR position('dealer_scope_denied' in d)=0
    OR has_function_privilege('anon','public.get_vehicle_workshop_detail_scoped(uuid,text)','execute') OR has_function_privilege('service_role','public.get_vehicle_workshop_detail_scoped(uuid,text)','execute') THEN RAISE EXCEPTION 'PDC_785_PLANNER_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
 SELECT pg_get_functiondef('public.get_pdc_email_intake_status(uuid)'::regprocedure) INTO d;
 IF position('pdc_auditor_actor_scope' in d)=0 OR position('ai_email_intake' in d)=0 OR position('email_intake_not_in_dealer_scope' in d)=0
    OR has_function_privilege('anon','public.get_pdc_email_intake_status(uuid)','execute') OR has_function_privilege('service_role','public.get_pdc_email_intake_status(uuid)','execute')
    OR has_table_privilege('authenticated','public.ai_email_intake','select') OR has_table_privilege('anon','public.ai_email_intake','select') THEN RAISE EXCEPTION 'PDC_785_INTAKE_POSTCONDITION_FAILED' USING errcode='55000'; END IF;
END $verify$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260830182000','785_narrow_authenticated_contracts',ARRAY[
 'Expose planner detail only through a dealer-scoped authenticated RPC bound to the server-owned auditor actor scope',
 'Expose only status metadata for a linked dealer-scoped intake through an authenticated SECURITY DEFINER RPC',
 'Preserve no direct ai_email_intake table access and no anon/service-role execute grants'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
