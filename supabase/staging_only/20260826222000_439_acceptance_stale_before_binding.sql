-- STAGING ONLY 439: reject stale registered acceptance lifecycle requests before binding/idempotency/containment work.
-- Normal acceptance writes retain exact protected/notification/outbound before-vs-after checks.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-439-acceptance-stale-before-binding',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $pre$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260826221000' AND name='438_acceptance_stale_fast_path')<>1
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260826221000') THEN
  RAISE EXCEPTION 'PDC_439_STAGING_HEAD_MISMATCH' USING errcode='55000';
 END IF;
END $pre$;

DO $repair$
DECLARE d text; repaired text; needle text; insertion text;
BEGIN
 SELECT pg_get_functiondef('public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)'::regprocedure) INTO d;
 d:=replace(d,chr(13),'');
 needle:= $$ IF v_actor IS NULL OR v_email='' OR NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=v_actor AND lower(r.email)=v_email
   AND r.role IN('operator','administrator') AND r.active AND r.account_status='approved' FOR SHARE) THEN
  RAISE EXCEPTION 'PDC_375_LIFECYCLE_UNAUTHORIZED' USING errcode='42501'; END IF;
 SELECT b.* INTO v_binding FROM public.pdc_acceptance_vehicle_bindings_375 b WHERE b.vehicle_id=p_vehicle_id FOR SHARE;$$;
 insertion:= $$ IF v_actor IS NULL OR v_email='' OR NOT EXISTS(SELECT 1 FROM public.pdc_user_roles r WHERE r.auth_user_id=v_actor AND lower(r.email)=v_email
   AND r.role IN('operator','administrator') AND r.active AND r.account_status='approved' FOR SHARE) THEN
  RAISE EXCEPTION 'PDC_375_LIFECYCLE_UNAUTHORIZED' USING errcode='42501'; END IF;
 IF EXISTS(SELECT 1 FROM public.vehicles v WHERE v.id=p_vehicle_id AND v.version IS DISTINCT FROM p_expected_version) THEN
  RAISE EXCEPTION 'PDC_375_LIFECYCLE_VERSION_CONFLICT' USING errcode='40001'; END IF;
 SELECT b.* INTO v_binding FROM public.pdc_acceptance_vehicle_bindings_375 b WHERE b.vehicle_id=p_vehicle_id FOR SHARE;$$;
 needle:=replace(needle,chr(13),''); insertion:=replace(insertion,chr(13),'');
 repaired:=replace(d,needle,insertion);
 IF position(needle IN d)=0 OR repaired=d
   OR position('PDC_375_LIFECYCLE_VERSION_CONFLICT' IN substring(repaired FROM 1 FOR position('SELECT b.* INTO v_binding' IN repaired)))=0
   OR position('v.version IS DISTINCT FROM p_expected_version' IN substring(repaired FROM 1 FOR position('SELECT b.* INTO v_binding' IN repaired)))=0
   OR position('v_notification_state_after<>v_notification_state_before' IN repaired)=0
   OR position('v_outbound_after<>v_outbound_before' IN repaired)=0 THEN
  RAISE EXCEPTION 'PDC_439_LIFECYCLE_REPAIR_NOT_EXACT' USING errcode='55000';
 END IF;
 EXECUTE repaired;
END $repair$;

REVOKE ALL ON FUNCTION public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text) TO authenticated;

DO $post$
DECLARE d text; early_pos integer; binding_pos integer; runtime_lock integer;
BEGIN
 SELECT replace(pg_get_functiondef('public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)'::regprocedure),chr(13),'') INTO d;
 early_pos:=position('v.version IS DISTINCT FROM p_expected_version' IN d);
 binding_pos:=position('SELECT b.* INTO v_binding' IN d);
 runtime_lock:=position('LOCK TABLE public.pdc_email_monitor_pilot' IN d);
 IF early_pos=0 OR binding_pos=0 OR early_pos>binding_pos OR runtime_lock=0
   OR position('v_notification_state_after<>v_notification_state_before' IN d)=0
   OR position('v_outbound_after<>v_outbound_before' IN d)=0
   OR position('pdc_hermes_containment_contract_432()' IN d)=0
   OR has_function_privilege('public','public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)','EXECUTE')
   OR has_function_privilege('anon','public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)','EXECUTE')
   OR has_function_privilege('service_role','public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)','EXECUTE')
   OR NOT has_function_privilege('authenticated','public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)','EXECUTE')
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR EXISTS(SELECT 1 FROM public.pdc_rft_transport_salesperson_outbox_412 WHERE sent_at IS NOT NULL OR delivered_at IS NOT NULL) THEN
  RAISE EXCEPTION 'PDC_439_LIFECYCLE_FUNCTION_OR_CONTAINMENT_POSTCONDITION' USING errcode='55000';
 END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826222000','439_acceptance_stale_before_binding',ARRAY[
 'Append-only repair after current 438 stale fast path; no applied migration rewritten',
 'Registered acceptance stale-version rejection occurs immediately after authenticated input validation, before binding, idempotency and containment work',
 'Normal acceptance writes retain current staging containment and exact protected, notification and outbound before-vs-after postconditions',
 'Authenticated-only lifecycle ACL, registry identity, replay, absent Production-sentinel and zero sent/delivered guards remain enforced'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
