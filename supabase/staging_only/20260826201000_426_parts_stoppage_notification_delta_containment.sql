-- STAGING ONLY 426: Parts STOPPAGE containment permits pre-existing immutable notification evidence.
BEGIN; SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='120s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-426-parts-notification-delta',0));
DO $repair$ DECLARE d text; h text; repaired text; BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
  OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL OR NOT public.pdc_monitor_staging_guard()
  OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260826200000' AND name='425_hidden_acceptance_actor_email_qualification')
  OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' AND version>'20260826200000') THEN RAISE EXCEPTION 'PDC_426_STAGING_HEAD_MISMATCH' USING errcode='55000'; END IF;
 SELECT pg_get_functiondef('public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text)'::regprocedure),encode(extensions.digest(convert_to(pg_get_functiondef('public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text)'::regprocedure),'UTF8'),'sha256'),'hex') INTO d,h;
 IF h<>'bf9b4fac69363cb1121d65023dd0b6151ea361b048c73c9c5f08f755e1f0df3c' THEN RAISE EXCEPTION 'PDC_426_EXACT_FUNCTION_MISMATCH' USING errcode='55000'; END IF;
 repaired:=replace(d,' OR (SELECT count(*) FROM public.vehicle_notifications)<>0','');
 repaired:=replace(repaired,'v_notifications_before<>0 OR v_notifications_after<>0','v_notifications_after<>v_notifications_before');
 repaired:=replace(repaired,'''current_notification_count'',0','''current_notification_count'',(SELECT count(*) FROM public.vehicle_notifications)');
 IF repaired=d OR position('v_notifications_before<>0 OR v_notifications_after<>0' in repaired)>0 OR position('(SELECT count(*) FROM public.vehicle_notifications)<>0' in repaired)>0 THEN RAISE EXCEPTION 'PDC_426_REPAIR_NOT_EXACT' USING errcode='55000'; END IF;
 EXECUTE repaired;
END $repair$;
DO $post$ DECLARE d text; BEGIN
 SELECT pg_get_functiondef('public.set_pdc_parts_stoppage_376(uuid,integer,uuid,text,text)'::regprocedure) INTO d;
 IF position('v_notifications_after<>v_notifications_before' in d)=0 OR position('v_notifications_before<>0 OR v_notifications_after<>0' in d)>0 OR position('(SELECT count(*) FROM public.vehicle_notifications)<>0' in d)>0 THEN RAISE EXCEPTION 'PDC_426_POSTCONDITION' USING errcode='55000'; END IF;
END $post$;
INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260826201000','426_parts_stoppage_notification_delta_containment',ARRAY[
 'Exact-SHA Parts STOPPAGE repair accepts pre-existing immutable notification evidence while still forbidding any notification-count delta',
 'Monitor guard, inactive writers/mailboxes, vehicle/version checks, receipts, replay state and Production isolation remain enforced'
]);
NOTIFY pgrst,'reload schema'; COMMIT;
