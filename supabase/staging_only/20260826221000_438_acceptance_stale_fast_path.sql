-- STAGING ONLY 438: reject stale registered acceptance writes before the expensive containment lock path.
-- Normal writes retain exact protected/notification/outbound before-vs-after checks.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-438-acceptance-stale-fast-path',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $pre$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260826220000' AND name='437_registered_replay_containment_repair')<>1
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260826220000') THEN
  RAISE EXCEPTION 'PDC_438_STAGING_HEAD_MISMATCH' USING errcode='55000';
 END IF;
END $pre$;

DO $repair$
DECLARE d text; repaired text; needle text; insertion text;
BEGIN
 SELECT pg_get_functiondef('public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)'::regprocedure) INTO d;
 d:=replace(d,chr(13),'');
 needle:= $$PERFORM pg_advisory_xact_lock(hashtextextended('pdc-375-vehicle:'||p_vehicle_id::text,0));$$;
 insertion:= $$IF EXISTS(SELECT 1 FROM public.vehicles v WHERE v.id=p_vehicle_id AND v.version IS DISTINCT FROM p_expected_version) THEN
  RAISE EXCEPTION 'PDC_375_LIFECYCLE_VERSION_CONFLICT' USING errcode='40001'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc-375-vehicle:'||p_vehicle_id::text,0));$$;
 insertion:=replace(insertion,chr(13),'');
 repaired:=replace(d,needle,insertion);
 IF repaired=d
   OR position('v.version IS DISTINCT FROM p_expected_version' IN repaired)=0
   OR position('v_before.version<>p_expected_version' IN repaired)=0
   OR position('v_notification_state_after<>v_notification_state_before' IN repaired)=0
   OR position('v_outbound_after<>v_outbound_before' IN repaired)=0
   OR position('pdc_hermes_containment_contract_432()' IN repaired)=0
   OR position('pdc_375-lifecycle:' IN repaired)=0
   OR position('PDC_375_LIFECYCLE_VERSION_CONFLICT' IN repaired)=0 THEN
  RAISE EXCEPTION 'PDC_438_LIFECYCLE_REPAIR_NOT_EXACT' USING errcode='55000';
 END IF;
 EXECUTE repaired;
END $repair$;

REVOKE ALL ON FUNCTION public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text) TO authenticated;

DO $post$
DECLARE d text; early text; runtime_lock integer; early_pos integer;
BEGIN
 SELECT pg_get_functiondef('public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)'::regprocedure) INTO d;
 d:=replace(d,chr(13),'');
 early:= $$IF EXISTS(SELECT 1 FROM public.vehicles v WHERE v.id=p_vehicle_id AND v.version IS DISTINCT FROM p_expected_version) THEN
  RAISE EXCEPTION 'PDC_375_LIFECYCLE_VERSION_CONFLICT' USING errcode='40001'; END IF;$$;
 early:=replace(early,chr(13),'');
 early_pos:=position(early IN d);
 runtime_lock:=position('LOCK TABLE public.pdc_email_monitor_pilot' IN d);
 IF early_pos=0 OR runtime_lock=0 OR early_pos>runtime_lock
   OR position('v_notification_state_after<>v_notification_state_before' IN d)=0
   OR position('v_outbound_after<>v_outbound_before' IN d)=0
   OR position('public.pdc_acceptance_protected_digest_375() IS DISTINCT FROM v_receipt.response->''protected_state''' IN d)>0
   OR has_function_privilege('public','public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)','EXECUTE')
   OR has_function_privilege('anon','public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)','EXECUTE')
   OR has_function_privilege('service_role','public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)','EXECUTE')
   OR NOT has_function_privilege('authenticated','public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)','EXECUTE')
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR EXISTS(SELECT 1 FROM public.pdc_rft_transport_salesperson_outbox_412 WHERE sent_at IS NOT NULL OR delivered_at IS NOT NULL) THEN
  RAISE EXCEPTION 'PDC_438_LIFECYCLE_FUNCTION_OR_CONTAINMENT_POSTCONDITION' USING errcode='55000';
 END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826221000','438_acceptance_stale_fast_path',ARRAY[
 'Append-only repair after current 437 registered replay containment repair; no applied migration rewritten',
 'Registered acceptance stale-version rejection occurs before the expensive current containment lock path',
 'Normal acceptance writes retain current staging containment and exact protected, notification and outbound before-vs-after postconditions',
 'Authenticated-only lifecycle ACL, registry identity, replay and absent Production-sentinel guards remain enforced'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
