-- STAGING ONLY 372: preserve the 60-minute floor except for exact registry-bound estimates.
BEGIN;
SET LOCAL lock_timeout='10s'; SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-372-exact-synthetic-booking-constraint',0));
LOCK TABLE public.pdc_email_monitor_pilot IN SHARE MODE;
LOCK TABLE public.pdc_email_monitor_status IN SHARE MODE;
LOCK TABLE public.monitored_mailboxes IN SHARE MODE;
LOCK TABLE public.pdc_monitor_stage_activation_writers IN SHARE MODE;
LOCK TABLE public.vehicle_notifications IN SHARE MODE;
LOCK TABLE public.pdc_overnight_synthetic_fleet_registry_363 IN SHARE MODE;
LOCK TABLE public.pdc_overnight_synthetic_estimates_369 IN SHARE MODE;
LOCK TABLE public.vehicles IN SHARE MODE;
LOCK TABLE public.workshop_stages IN SHARE MODE;
LOCK TABLE public.workshop_bookings IN SHARE ROW EXCLUSIVE MODE;

DO $guard$
BEGIN
 IF NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260825080000' AND name='371_overnight_exact_synthetic_booking_validation')
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version>'20260825080000' AND version~'^[0-9]{14}$')
   OR NOT public.pdc_hermes_test_dependency_guard_365() OR NOT public.pdc_hermes_test_registry_guard_365()
   OR (SELECT count(*) FROM public.pdc_email_monitor_pilot WHERE singleton AND NOT enabled AND NOT outbound_email_enabled
        AND NOT automatic_rule_application AND NOT automatic_authenticated_jobcards)<>1
   OR (SELECT count(*) FROM public.pdc_email_monitor_status WHERE singleton AND running_status='stopped' AND gateway_instance_id IS NULL)<>1
   OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
   OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL)
   OR (SELECT count(*) FROM public.vehicle_notifications)<>0
   OR (SELECT count(*) FROM pg_constraint c WHERE c.conrelid='public.workshop_bookings'::regclass
        AND c.conname='workshop_bookings_minimum_duration_60' AND c.contype='c' AND c.convalidated
        AND encode(extensions.digest(convert_to(pg_get_constraintdef(c.oid,true),'UTF8'),'sha256'),'hex')='8f9c20ceaee6e0adf011d73eeac6818c1e61d8a512a17c9aad235bf037ee746f')<>1 THEN
  RAISE EXCEPTION 'PDC_372_TARGET_HEAD_CONTAINMENT_OR_CONSTRAINT_MISMATCH' USING errcode='55000'; END IF;
END $guard$;

CREATE FUNCTION public.workshop_booking_minimum_duration_guard_372()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $guard$
BEGIN
 IF NEW.default_duration_minutes IS NULL OR NEW.default_duration_minutes<=0 THEN
  RAISE EXCEPTION 'PDC_372_POSITIVE_DURATION_REQUIRED' USING errcode='23514';
 END IF;
 IF NEW.default_duration_minutes<60 AND NOT EXISTS(
  SELECT 1 FROM public.pdc_overnight_synthetic_estimates_369 e
  JOIN public.pdc_overnight_synthetic_fleet_registry_363 r ON r.run_id=e.run_id AND r.vehicle_id=e.vehicle_id AND r.scenario_no=e.scenario_no
  JOIN public.vehicles v ON v.id=e.vehicle_id AND v.stock_number=r.stock_number AND v.customer_name=r.customer_name
   AND v.job_card_number=r.job_card_number AND v.vehicle_description=r.vehicle_description
   AND v.source_system='hermes_overnight_synthetic' AND v.source_batch_id=e.run_id AND v.source_record_id=r.stock_number
   AND v.source_payload->>'contract'='pdc-overnight-synthetic-fleet-363/render_only'
  JOIN public.workshop_stages s ON s.id=NEW.stage_id AND s.code=e.stage_code
  WHERE e.run_id='HERMES-TEST-RUN-20260824' AND e.vehicle_id=NEW.vehicle_id
    AND e.estimated_minutes=NEW.default_duration_minutes AND e.estimated_minutes BETWEEN 1 AND 59
    AND e.estimated_minutes=round(e.estimated_hours*60)::integer
    AND public.workshop_vehicle_stage_estimated_duration_minutes(NEW.vehicle_id,NEW.stage_id)=e.estimated_minutes
 ) THEN
  RAISE EXCEPTION 'PDC_372_MINIMUM_DURATION_60' USING errcode='23514';
 END IF;
 RETURN NEW;
END $guard$;
REVOKE ALL ON FUNCTION public.workshop_booking_minimum_duration_guard_372() FROM public,anon,authenticated,service_role;

ALTER TABLE public.workshop_bookings DROP CONSTRAINT workshop_bookings_minimum_duration_60;
ALTER TABLE public.workshop_bookings ADD CONSTRAINT workshop_bookings_positive_duration_372 CHECK(default_duration_minutes>0);
CREATE TRIGGER workshop_booking_044_minimum_duration_372 BEFORE INSERT OR UPDATE OF vehicle_id,stage_id,default_duration_minutes
ON public.workshop_bookings FOR EACH ROW EXECUTE FUNCTION public.workshop_booking_minimum_duration_guard_372();

DO $post$
DECLARE v_def text;v_trigger text;
BEGIN
 v_def:=pg_get_functiondef('public.workshop_booking_minimum_duration_guard_372()'::regprocedure);
 SELECT pg_get_triggerdef(t.oid,true) INTO v_trigger FROM pg_trigger t WHERE t.tgrelid='public.workshop_bookings'::regclass
  AND t.tgname='workshop_booking_044_minimum_duration_372' AND t.tgenabled='O' AND t.tgqual IS NULL AND NOT t.tgisinternal;
 IF (SELECT count(*) FROM pg_constraint c WHERE c.conrelid='public.workshop_bookings'::regclass AND c.conname='workshop_bookings_minimum_duration_60')<>0
   OR (SELECT count(*) FROM pg_constraint c WHERE c.conrelid='public.workshop_bookings'::regclass AND c.conname='workshop_bookings_positive_duration_372'
       AND c.convalidated AND pg_get_constraintdef(c.oid,true)='CHECK (default_duration_minutes > 0)')<>1
   OR position('e.estimated_minutes BETWEEN 1 AND 59' in v_def)=0
   OR position('BEFORE INSERT OR UPDATE OF vehicle_id, stage_id, default_duration_minutes ON workshop_bookings' in v_trigger)=0
   OR NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid='public.workshop_booking_minimum_duration_guard_372()'::regprocedure
       AND p.prosecdef AND pg_get_userbyid(p.proowner)='postgres'
       AND NOT has_function_privilege('public',p.oid,'EXECUTE') AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
       AND NOT has_function_privilege('authenticated',p.oid,'EXECUTE') AND NOT has_function_privilege('service_role',p.oid,'EXECUTE'))
   OR NOT public.pdc_hermes_test_dependency_guard_365() OR NOT public.pdc_hermes_test_registry_guard_365()
   OR (SELECT count(*) FROM public.vehicle_notifications)<>0 THEN
  RAISE EXCEPTION 'PDC_372_CONSTRAINT_TRIGGER_OR_CONTAINMENT_POSTCONDITION' USING errcode='55000'; END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20260825090000','372_overnight_exact_synthetic_booking_constraint',ARRAY[
 'Exact migration-371 head, staging containment and original 60-minute constraint definition',
 'Positive check constraint plus fail-closed trigger preserving 60 minutes for every ordinary booking',
 'Sub-hour booking permitted only for exact registry-bound migration-369 estimate and canonical minutes',
 'Exact trigger timing/columns, postgres owner, no callable grants and zero notifications',
 'No Production, generic DML, mailbox, writer or non-test mutation authority'
]);
COMMIT;
