-- STAGING ONLY 440: keep the pre-binding stale rejection non-retryable at the HTTP boundary.
-- The locked authoritative stale check remains SQLSTATE 40001; only the early fast path avoids proxy serialization retries.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-440-acceptance-stale-nonretryable',0));
LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE;

DO $pre$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260826222000' AND name='439_acceptance_stale_before_binding')<>1
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260826222000') THEN
  RAISE EXCEPTION 'PDC_440_STAGING_HEAD_MISMATCH' USING errcode='55000';
 END IF;
END $pre$;

DO $repair$
DECLARE d text; repaired text; needle text; replacement text;
BEGIN
 SELECT pg_get_functiondef('public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)'::regprocedure) INTO d;
 d:=replace(d,chr(13),'');
 needle:= $$IF EXISTS(SELECT 1 FROM public.vehicles v WHERE v.id=p_vehicle_id AND v.version IS DISTINCT FROM p_expected_version) THEN
  RAISE EXCEPTION 'PDC_375_LIFECYCLE_VERSION_CONFLICT' USING errcode='40001'; END IF;$$;
 replacement:= $$IF EXISTS(SELECT 1 FROM public.vehicles v WHERE v.id=p_vehicle_id AND v.version IS DISTINCT FROM p_expected_version) THEN
  RAISE EXCEPTION 'PDC_375_LIFECYCLE_VERSION_CONFLICT' USING errcode='P0001'; END IF;$$;
 needle:=replace(needle,chr(13),''); replacement:=replace(replacement,chr(13),'');
 IF position(needle IN d)=0 THEN RAISE EXCEPTION 'PDC_440_EARLY_STALE_BLOCK_NOT_FOUND' USING errcode='55000'; END IF;
 repaired:=replace(d,needle,replacement);
 IF repaired=d OR position(replacement IN repaired)=0
   OR position('v_notification_state_after<>v_notification_state_before' IN repaired)=0
   OR position('v_outbound_after<>v_outbound_before' IN repaired)=0 THEN
  RAISE EXCEPTION 'PDC_440_STALE_REPAIR_NOT_EXACT' USING errcode='55000';
 END IF;
 EXECUTE repaired;
END $repair$;

REVOKE ALL ON FUNCTION public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text) FROM public,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text) TO authenticated;

DO $post$
DECLARE d text; early_pos integer; binding_pos integer; retry_pos integer;
BEGIN
 SELECT replace(pg_get_functiondef('public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)'::regprocedure),chr(13),'') INTO d;
 early_pos:=position('v.version IS DISTINCT FROM p_expected_version' IN d);
 binding_pos:=position('SELECT b.* INTO v_binding' IN d);
 retry_pos:=position('PDC_375_LIFECYCLE_VERSION_CONFLICT' IN substring(d FROM early_pos FOR 350));
 IF early_pos=0 OR binding_pos=0 OR early_pos>binding_pos OR retry_pos=0
   OR position('P0001' IN substring(d FROM early_pos FOR 350))=0
   OR position('v_notification_state_after<>v_notification_state_before' IN d)=0
   OR position('v_outbound_after<>v_outbound_before' IN d)=0
   OR has_function_privilege('public','public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)','EXECUTE')
   OR has_function_privilege('anon','public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)','EXECUTE')
   OR has_function_privilege('service_role','public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)','EXECUTE')
   OR NOT has_function_privilege('authenticated','public.pdc_acceptance_lifecycle_375(uuid,integer,uuid,text)','EXECUTE')
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR EXISTS(SELECT 1 FROM public.pdc_rft_transport_salesperson_outbox_412 WHERE sent_at IS NOT NULL OR delivered_at IS NOT NULL) THEN
  RAISE EXCEPTION 'PDC_440_STALE_FUNCTION_OR_CONTAINMENT_POSTCONDITION' USING errcode='55000';
 END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826223000','440_acceptance_stale_nonretryable',ARRAY[
 'Append-only repair after current 439 stale-before-binding repair; no applied migration rewritten',
 'The authenticated pre-binding stale rejection keeps the stable lifecycle version-conflict message but uses non-retryable SQLSTATE P0001 to avoid HTTP proxy serialization retries',
 'The locked authoritative stale check remains SQLSTATE 40001 for the normal concurrency path',
 'Normal acceptance writes retain current staging containment and exact protected, notification and outbound before-vs-after postconditions',
 'Authenticated-only lifecycle ACL, registry identity, replay, absent Production-sentinel and zero sent/delivered guards remain enforced'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
