-- STAGING ONLY 371: admit exact sub-hour duration only for migration-369 registry estimates.
BEGIN;
SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-371-exact-synthetic-booking-validation',0));
LOCK TABLE public.pdc_email_monitor_pilot IN SHARE MODE;
LOCK TABLE public.pdc_email_monitor_status IN SHARE MODE;
LOCK TABLE public.monitored_mailboxes IN SHARE MODE;
LOCK TABLE public.pdc_monitor_stage_activation_writers IN SHARE MODE;
LOCK TABLE public.vehicle_notifications IN SHARE MODE;
LOCK TABLE public.pdc_overnight_synthetic_fleet_registry_363 IN SHARE MODE;
LOCK TABLE public.pdc_overnight_synthetic_estimates_369 IN SHARE MODE;
LOCK TABLE public.vehicles IN SHARE MODE;
LOCK TABLE public.workshop_stages IN SHARE MODE;
LOCK TABLE public.workshop_bays IN SHARE MODE;
LOCK TABLE public.workshop_bookings IN SHARE MODE;

DO $guard$
DECLARE v_acl text[];
BEGIN
 IF NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR (SELECT count(*) FROM supabase_migrations.schema_migrations WHERE version='20260825070000' AND name='370_overnight_exact_synthetic_minutes'
       AND statements=ARRAY[
        'Exact migration-369 staging head, ledger statements, installed definitions, ACLs and containment',
        'Exact positive rounded minutes below 60 only for registry-bound migration-369 synthetic estimates',
        'Byte-identical established 60-minute floor and null behavior for every protected/non-test vehicle',
        'Booking-duration reconciliation delegates to the canonical registry-aware minute function',
        'Rebound dependency guard, exact route inventory, migration-317 positive-estimate trigger and zero notifications']::text[])<>1
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version>'20260825070000' AND version~'^[0-9]{14}$')
   OR NOT public.pdc_hermes_test_dependency_guard_365() OR NOT public.pdc_hermes_test_registry_guard_365()
   OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND NOT enabled AND NOT outbound_email_enabled
        AND NOT automatic_rule_application AND NOT automatic_authenticated_jobcards)<>1
   OR (SELECT count(*) FROM public.pdc_email_monitor_status WHERE singleton AND running_status='stopped' AND gateway_instance_id IS NULL)<>1
   OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
   OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)
   OR (SELECT count(*) FROM public.vehicle_notifications)<>0
   OR encode(extensions.digest(convert_to(pg_get_functiondef('public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)'::regprocedure),'UTF8'),'sha256'),'hex')<>'456502dbfe5bafd64193830020023117779194ebb1e79e9caba0b4da4da513ca'
   OR encode(extensions.digest(convert_to(pg_get_functiondef('public.workshop_vehicle_stage_estimated_duration_minutes(uuid,uuid)'::regprocedure),'UTF8'),'sha256'),'hex')<>'6cf33245713fe9481976f4fa47fe5f8a4b1cf8e47d5d8568eb4cb8a602e5ceee' THEN
  RAISE EXCEPTION 'PDC_371_TARGET_HEAD_CONTAINMENT_OR_DEPENDENCY_MISMATCH' USING errcode='55000';
 END IF;
 SELECT array_agg(coalesce(r.rolname,'public')||':'||x.privilege_type ORDER BY coalesce(r.rolname,'public'),x.privilege_type)
 INTO v_acl FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) x LEFT JOIN pg_roles r ON r.oid=x.grantee
 WHERE p.oid='public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)'::regprocedure;
 IF v_acl IS DISTINCT FROM ARRAY['postgres:EXECUTE','service_role:EXECUTE']::text[] OR NOT EXISTS(SELECT 1 FROM pg_proc p
    WHERE p.oid='public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)'::regprocedure
      AND p.prosecdef AND p.provolatile='s' AND pg_get_userbyid(p.proowner)='postgres'
      AND p.proconfig=ARRAY['search_path=pg_catalog, public, extensions']::text[]) THEN
  RAISE EXCEPTION 'PDC_371_VALIDATOR_OWNER_ACL_MISMATCH' USING errcode='55000';
 END IF;
END $guard$;

CREATE TEMP TABLE pdc_371_protected_validation ON COMMIT DROP AS
SELECT b.id booking_id,public.workshop_validate_booking(b.id,b.vehicle_id,b.stage_id,b.bay_id,b.scheduled_start_at,b.scheduled_end_at,
 b.default_duration_minutes,b.status,NULL,true) result
FROM public.workshop_bookings b
WHERE NOT EXISTS(SELECT 1 FROM public.pdc_overnight_synthetic_fleet_registry_363 r WHERE r.vehicle_id=b.vehicle_id);

DO $replace$
DECLARE v_def text:=pg_get_functiondef('public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)'::regprocedure);
 v_old text:=E'  if p_duration_minutes is null or p_duration_minutes<60 then\n    return jsonb_build_object(\'ok\',false,\'error\',\'minimum_duration\',\'minimum_minutes\',60);\n  end if;';
 v_new text:=E'  if p_duration_minutes is null or (p_duration_minutes<60 and not exists(\n    select 1 from public.pdc_overnight_synthetic_estimates_369 e\n    join public.pdc_overnight_synthetic_fleet_registry_363 r on r.run_id=e.run_id and r.vehicle_id=e.vehicle_id and r.scenario_no=e.scenario_no\n    join public.vehicles x on x.id=e.vehicle_id and x.stock_number=r.stock_number and x.customer_name=r.customer_name\n      and x.job_card_number=r.job_card_number and x.vehicle_description=r.vehicle_description\n      and x.source_system=\'hermes_overnight_synthetic\' and x.source_batch_id=e.run_id and x.source_record_id=r.stock_number\n      and x.source_payload->>\'contract\'=\'pdc-overnight-synthetic-fleet-363/render_only\'\n    join public.workshop_stages es on es.id=p_stage_id and es.code=e.stage_code\n    where e.run_id=\'HERMES-TEST-RUN-20260824\' and e.vehicle_id=p_vehicle_id\n      and e.estimated_minutes=p_duration_minutes and e.estimated_minutes between 1 and 59\n      and e.estimated_minutes=round(e.estimated_hours*60)::integer\n      and public.workshop_vehicle_stage_estimated_duration_minutes(p_vehicle_id,p_stage_id)=e.estimated_minutes\n  )) then\n    return jsonb_build_object(\'ok\',false,\'error\',\'minimum_duration\',\'minimum_minutes\',60);\n  end if;';
BEGIN
 IF length(v_def)-length(replace(v_def,v_old,''))<>length(v_old) THEN
  RAISE EXCEPTION 'PDC_371_EXACT_VALIDATOR_FRAGMENT_MISMATCH' USING errcode='55000'; END IF;
 EXECUTE replace(v_def,v_old,v_new);
END $replace$;
REVOKE ALL ON FUNCTION public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean) FROM public,anon,authenticated;

DO $post$
DECLARE v7 uuid;v_stage uuid;v_bay uuid;v_start timestamptz:='2026-08-26T02:23:00+00:00';v_ok jsonb;v_bad jsonb;v_acl text[];
BEGIN
 IF EXISTS(SELECT 1 FROM pdc_371_protected_validation p JOIN public.workshop_bookings b ON b.id=p.booking_id
      WHERE public.workshop_validate_booking(b.id,b.vehicle_id,b.stage_id,b.bay_id,b.scheduled_start_at,b.scheduled_end_at,
       b.default_duration_minutes,b.status,NULL,true) IS DISTINCT FROM p.result) THEN
  RAISE EXCEPTION 'PDC_371_PROTECTED_VALIDATION_BEHAVIOR_DRIFT' USING errcode='55000'; END IF;
 SELECT r.vehicle_id INTO v7 FROM public.pdc_overnight_synthetic_fleet_registry_363 r WHERE r.run_id='HERMES-TEST-RUN-20260824' AND r.scenario_no=7;
 SELECT s.id,b.id INTO v_stage,v_bay FROM public.workshop_stages s JOIN public.workshop_bays b ON b.stage_id=s.id
 WHERE s.code='FITTING' AND b.bay_number=4 AND b.is_active;
 v_ok:=public.workshop_validate_booking(NULL,v7,v_stage,v_bay,v_start,public.workshop_add_operational_minutes(v_start,47),47,'planned',NULL,false);
 v_bad:=public.workshop_validate_booking(NULL,v7,v_stage,v_bay,v_start,public.workshop_add_operational_minutes(v_start,46),46,'planned',NULL,false);
 IF coalesce((v_ok->>'ok')::boolean,false) IS NOT TRUE OR v_bad->>'error'<>'minimum_duration'
   OR NOT public.pdc_hermes_test_dependency_guard_365() OR NOT public.pdc_hermes_test_registry_guard_365()
   OR (SELECT count(*) FROM public.vehicle_notifications)<>0 THEN
  RAISE EXCEPTION 'PDC_371_EXACT_SYNTHETIC_OR_CONTAINMENT_POSTCONDITION ok=% bad=%',v_ok,v_bad USING errcode='55000'; END IF;
 SELECT array_agg(coalesce(r.rolname,'public')||':'||x.privilege_type ORDER BY coalesce(r.rolname,'public'),x.privilege_type)
 INTO v_acl FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) x LEFT JOIN pg_roles r ON r.oid=x.grantee
 WHERE p.oid='public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)'::regprocedure;
 IF v_acl IS DISTINCT FROM ARRAY['postgres:EXECUTE','service_role:EXECUTE']::text[] OR NOT EXISTS(SELECT 1 FROM pg_proc p
    WHERE p.oid='public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)'::regprocedure
      AND p.prosecdef AND p.provolatile='s' AND pg_get_userbyid(p.proowner)='postgres'
      AND p.proconfig=ARRAY['search_path=pg_catalog, public, extensions']::text[])
   OR position('e.estimated_minutes between 1 and 59' in lower(pg_get_functiondef('public.workshop_validate_booking(uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,public.workshop_booking_status,uuid,boolean)'::regprocedure)))=0 THEN
  RAISE EXCEPTION 'PDC_371_VALIDATOR_IDENTITY_OR_DEFINITION_POSTCONDITION' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260825080000','371_overnight_exact_synthetic_booking_validation',ARRAY[
 'Exact migration-370 staging head, validator predecessor hash, owner, ACL and containment',
 'Replace one exact minimum-duration fragment while preserving every established validator branch',
 'Sub-hour duration admitted only for exact registry-bound migration-369 estimate identity and canonical minutes',
 'Protected booking validation snapshot parity and 47-minute positive/46-minute negative executable checks',
 'No generic DML grants, notifications, mailbox, writer, Production or non-test authority'
]);
COMMIT;
