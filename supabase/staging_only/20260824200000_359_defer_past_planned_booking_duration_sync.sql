-- STAGING ONLY 359: do not rewrite already-started queued/planned booking windows
-- during automatic operation-estimate reconciliation. Preserve the booking and
-- record a deferred audit event so exact operation-area corrections can proceed.
BEGIN;
SET LOCAL lock_timeout='10s';
SET LOCAL statement_timeout='180s';
SELECT pg_advisory_xact_lock(hashtextextended('pdc-staging-359-past-booking-duration-defer',0));
DO $guard$
DECLARE h text;
BEGIN
 IF NOT public.pdc_monitor_staging_guard()
   OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
   OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL
   OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version='20260824190000' AND name='358_craig_owner_jobcard_area_rules')
   OR EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations WHERE version>'20260824190000' AND version~'^[0-9]{14}$')
   OR EXISTS(SELECT 1 FROM public.monitored_mailboxes WHERE active)
   OR EXISTS(SELECT 1 FROM public.pdc_monitor_stage_activation_writers WHERE active AND revoked_at IS NULL) THEN
  RAISE EXCEPTION 'PDC_359_STAGING_TARGET_HEAD_OR_CONTAINMENT_MISMATCH';
 END IF;
 SELECT encode(extensions.digest(convert_to(pg_get_functiondef('public.workshop_sync_vehicle_stage_booking_duration(uuid,text,text)'::regprocedure),'UTF8'),'sha256'),'hex') INTO h;
 IF h<>'cea8497d2a1b6636d433f267f9ae826d94e6b1a298d55ebdb28d5ba3775d100b' THEN RAISE EXCEPTION 'PDC_359_PREDECESSOR_FUNCTION_DRIFT %',h; END IF;
END $guard$;

CREATE OR REPLACE FUNCTION public.workshop_sync_vehicle_stage_booking_duration(p_vehicle_id uuid,p_stage_code text,p_reason text)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,extensions AS $function$
DECLARE
 v_stage text:=public.workshop_canonical_stage_code(p_stage_code);v_booking public.workshop_bookings%rowtype;
 v_minutes integer;v_end timestamptz;v_before jsonb;v_after jsonb;v_count integer:=0;
 v_original_claims text:=current_setting('request.jwt.claims',true);v_initiator_uid uuid:=auth.uid();v_initiator_email text:=public.current_actor_email();
 v_system_actor uuid;v_system_email text;
BEGIN
 IF p_vehicle_id IS NULL OR v_stage IS NULL THEN RETURN 0;END IF;
 SELECT r.auth_user_id,r.email INTO v_system_actor,v_system_email FROM public.pdc_user_roles r JOIN auth.users u ON u.id=r.auth_user_id
 WHERE r.active AND r.account_status='approved' AND r.role='administrator' AND r.auth_user_id IS NOT NULL ORDER BY r.created_at,r.id LIMIT 1;
 IF v_system_actor IS NULL THEN RAISE EXCEPTION 'PDC_156_WORKSHOP_SYSTEM_ACTOR_MISSING' USING errcode='55000';END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',v_system_actor,'email',v_system_email,'role','authenticated')::text,true);
 PERFORM pg_advisory_xact_lock(hashtextextended('pdc:workshop:estimate-sync:'||p_vehicle_id::text,0));
 LOCK TABLE public.workshop_bookings,public.workshop_booking_assignments IN EXCLUSIVE MODE;
 FOR v_booking IN SELECT b.* FROM public.workshop_bookings b JOIN public.workshop_stages s ON s.id=b.stage_id
  WHERE b.vehicle_id=p_vehicle_id AND b.deleted_at IS NULL AND b.status::text IN('queued','planned','started','stoppage')
    AND public.workshop_canonical_stage_code(s.code)=v_stage ORDER BY b.scheduled_start_at,b.id FOR UPDATE OF b LOOP
  v_minutes:=coalesce(greatest(60,round(public.workshop_vehicle_stage_estimated_hours(p_vehicle_id,v_stage)*60)::integer),60);
  v_end:=public.workshop_add_operational_minutes(v_booking.scheduled_start_at,v_minutes);
  IF v_booking.default_duration_minutes IS DISTINCT FROM v_minutes OR v_booking.scheduled_end_at IS DISTINCT FROM v_end THEN
   v_before:=public.workshop_booking_snapshot(v_booking.id);
   IF v_booking.status::text IN('queued','planned') AND v_booking.scheduled_start_at<=clock_timestamp() THEN
    INSERT INTO public.workshop_booking_history(booking_id,event_type,before_data,after_data,metadata,actor_user_id,actor_email)
    VALUES(v_booking.id,'operation_estimate_duration_reconcile_deferred',v_before,v_before,
     jsonb_build_object('system_reconciliation',true,'source',coalesce(p_reason,'operation_estimate_change'),'stage_code',v_stage,
      'proposed_duration_minutes',v_minutes,'reason','preserve already-started queued/planned booking window','initiator_auth_uid',v_initiator_uid,'initiator_email',v_initiator_email),v_system_actor,v_system_email);
   ELSE
    UPDATE public.workshop_bookings SET default_duration_minutes=v_minutes,scheduled_end_at=v_end,version=version+1 WHERE id=v_booking.id;
    UPDATE public.workshop_booking_assignments SET scheduled_start_at=v_booking.scheduled_start_at,scheduled_end_at=v_end WHERE booking_id=v_booking.id AND released_at IS NULL;
    v_after:=public.workshop_booking_snapshot(v_booking.id);
    INSERT INTO public.workshop_booking_history(booking_id,event_type,before_data,after_data,metadata,actor_user_id,actor_email)
    VALUES(v_booking.id,'operation_estimate_duration_reconciled',v_before,v_after,
     jsonb_build_object('system_reconciliation',true,'source',coalesce(p_reason,'operation_estimate_change'),'stage_code',v_stage,
      'duration_minutes',v_minutes,'initiator_auth_uid',v_initiator_uid,'initiator_email',v_initiator_email),v_system_actor,v_system_email);
    v_count:=v_count+1;
   END IF;
  END IF;
 END LOOP;
 PERFORM set_config('request.jwt.claims',coalesce(v_original_claims,''),true);RETURN v_count;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('request.jwt.claims',coalesce(v_original_claims,''),true);RAISE;
END $function$;
REVOKE ALL ON FUNCTION public.workshop_sync_vehicle_stage_booking_duration(uuid,text,text) FROM public,anon,authenticated,service_role;

DO $post$
DECLARE d text;
BEGIN
 SELECT pg_get_functiondef('public.workshop_sync_vehicle_stage_booking_duration(uuid,text,text)'::regprocedure) INTO d;
 IF position('operation_estimate_duration_reconcile_deferred' IN d)=0 OR position('preserve already-started queued/planned booking window' IN d)=0
   OR has_function_privilege('authenticated','public.workshop_sync_vehicle_stage_booking_duration(uuid,text,text)','EXECUTE') THEN
  RAISE EXCEPTION 'PDC_359_FUNCTION_POSTCONDITION_FAILED';
 END IF;
END $post$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements)
VALUES('20260824200000','359_defer_past_planned_booking_duration_sync',array[
 'Require exact staging sentinel, migration 358 head, stopped ingestion and exact predecessor function hash',
 'Preserve already-started queued/planned booking windows instead of rewriting them during automatic estimate reconciliation',
 'Append a deferred booking-history event containing the proposed duration and initiator evidence',
 'Continue normal reconciliation for future and active started/stoppage bookings',
 'Grant no direct function execution, generic DML, Monitor, mailbox, writer or Production authority'
]);
NOTIFY pgrst,'reload schema';
COMMIT;
