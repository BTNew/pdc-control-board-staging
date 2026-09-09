-- Run only through the approved STAGING development database connection.
-- Uses transaction-local test claims, not new credentials or changed user roles.
-- Real email/runtime OAuth and rendered browser verification remain separate checks.
-- Every synthetic change is rolled back even if an assertion fails.
BEGIN;
SET LOCAL statement_timeout = '30s';

DO $test$
DECLARE
 original_claims text:=current_setting('request.jwt.claims',true);
 r record; result jsonb; result2 jsonb; report jsonb:='[]'::jsonb;
 key text:='vehicleTrackingCoreNotes:audit-'||gen_random_uuid()::text;
 idkey text:='pdc-online-'||replace(gen_random_uuid()::text,'-','');
 manual_id text:='manual-audit-'||gen_random_uuid()::text;
 expected bigint;
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE THEN RAISE EXCEPTION 'STAGING only'; END IF;
 BEGIN
  PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',gen_random_uuid(),'email','audit-unassigned@example.invalid')::text,true);
  result:=public.save_pdc_online_state(key,'{}',0,idkey);
  IF result->>'error' IS DISTINCT FROM 'unauthorized' THEN RAISE EXCEPTION 'Missing role was not rejected'; END IF;
  result:=public.save_pdc_online_state_batch('[]','pdc-batch-'||replace(gen_random_uuid()::text,'-',''));
  IF result->>'error' IS DISTINCT FROM 'unauthorized' THEN RAISE EXCEPTION 'Missing role batch was not rejected'; END IF;
  report:=report||jsonb_build_array('missing role: direct and batch denied');
  FOR r IN SELECT auth_user_id,email,role,active,account_status FROM public.pdc_user_roles WHERE auth_user_id IS NOT NULL AND (active IS NOT TRUE OR account_status::text<>'approved' OR role::text='viewer') LOOP
   PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',r.auth_user_id,'email',r.email)::text,true);
   result:=public.save_pdc_online_state(key,'{}',0,idkey);
   IF result->>'error' IS DISTINCT FROM 'unauthorized' THEN RAISE EXCEPTION 'Non-writer role was not rejected'; END IF;
  END LOOP;
  report:=report||jsonb_build_array('pending/disabled/viewer identities denied');
  SELECT auth_user_id,email INTO r FROM public.pdc_user_roles WHERE active AND account_status::text='approved' AND role::text='administrator' AND auth_user_id IS NOT NULL LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'Approved test identity unavailable'; END IF;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',gen_random_uuid(),'email',r.email)::text,true);
  result:=public.save_pdc_online_state(key,'{}',0,idkey);
  IF result->>'error' IS DISTINCT FROM 'unauthorized' THEN RAISE EXCEPTION 'Mismatched subject/email was not rejected'; END IF;
  report:=report||jsonb_build_array('mismatched subject/email denied');
  PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',r.auth_user_id,'email',r.email)::text,true);
  result:=public.save_pdc_online_state(key,jsonb_build_object('synthetic',true),0,idkey);
  IF result->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'Approved writer denied: %',result->>'error'; END IF;
  result2:=public.save_pdc_online_state(key,jsonb_build_object('synthetic',true),0,idkey);
  IF result2 IS DISTINCT FROM result THEN RAISE EXCEPTION 'Replay result changed'; END IF;
  report:=report||jsonb_build_array('approved writer and exact replay pass');
  SELECT coalesce((SELECT version FROM public.pdc_online_operational_state WHERE state_key='vehicleTrackingCoreNavisionOnlyVehicles:v1'),0) INTO expected;
  result:=public.save_pdc_online_state('vehicleTrackingCoreNavisionOnlyVehicles:v1',jsonb_build_array(jsonb_build_object('id',manual_id,'client','ROLLBACK-ONLY AUDIT','vehicle','Synthetic test','pdcLocation','YH'),'null'::jsonb),expected,'pdc-online-'||replace(gen_random_uuid()::text,'-',''));
  IF result->>'error' IS DISTINCT FROM 'invalid_vehicle_row' THEN RAISE EXCEPTION 'Unexpected atomicity result: %',result->>'error'; END IF;
  IF EXISTS(SELECT 1 FROM public.vehicles WHERE permanent_vehicle_id='ONLINE:'||manual_id) THEN RAISE EXCEPTION 'Partial vehicle mutation survived failed save'; END IF;
  report:=report||jsonb_build_array('valid first vehicle plus invalid second row: full rollback');
  result:=public.save_pdc_online_state_batch('null'::jsonb,'pdc-batch-'||replace(gen_random_uuid()::text,'-',''));
  IF result->>'error' IS DISTINCT FROM 'invalid_batch_items' THEN RAISE EXCEPTION 'JSON null batch accepted'; END IF;
  report:=report||jsonb_build_array('JSON null batch rejected');
  RAISE EXCEPTION USING ERRCODE='PDT00',MESSAGE='rollback all synthetic test effects';
 EXCEPTION WHEN SQLSTATE 'PDT00' THEN NULL;
 END;
 PERFORM set_config('request.jwt.claims',coalesce(original_claims,''),true);
 IF EXISTS(SELECT 1 FROM public.vehicles WHERE permanent_vehicle_id='ONLINE:'||manual_id) OR EXISTS(SELECT 1 FROM public.pdc_online_operational_state WHERE state_key=key) THEN RAISE EXCEPTION 'Synthetic state survived rollback'; END IF;
 PERFORM set_config('pdc.audit_priority_test_results',jsonb_build_object('checks',report,'synthetic_effects_rolled_back',true)::text,true);
END $test$;
SELECT current_setting('pdc.audit_priority_test_results')::jsonb AS online_save_results;

-- Requires an existing, eligible future-ETA IT vehicle and an available bay.
-- If unavailable, this intentionally fails rather than creating fictional business evidence.
DO $test$
DECLARE original_claims text:=current_setting('request.jwt.claims',true); actor record; c record; bay record; result jsonb; moved jsonb; booking_id uuid; booking_version integer; start_at timestamptz; before_start timestamptz; attempted_start timestamptz; failure_message text; report jsonb;
BEGIN
 IF public.pdc_monitor_staging_guard() IS NOT TRUE THEN RAISE EXCEPTION 'STAGING only'; END IF;
 SELECT auth_user_id,email INTO actor FROM public.pdc_user_roles WHERE active AND account_status::text='approved' AND role::text='administrator' AND auth_user_id IS NOT NULL LIMIT 1;
 SELECT v.id,v.version,v.eta_to_kewdale,s.id AS stage_id,s.code,public.workshop_vehicle_stage_estimated_duration_minutes(v.id,s.id) AS duration INTO c FROM public.vehicles v JOIN public.vehicle_work_items wi ON wi.vehicle_id=v.id AND wi.required AND NOT wi.completed JOIN public.workshop_stages s ON s.code=public.workshop_stage_code_for_work_key(wi.work_key) AND s.active AND s.planner_enabled WHERE v.current_location='IT' AND v.deleted_at IS NULL AND v.lifecycle_state='active' AND v.eta_to_kewdale>=current_date AND NOT EXISTS(SELECT 1 FROM public.workshop_bookings b WHERE b.vehicle_id=v.id AND b.deleted_at IS NULL AND b.status IN('queued','planned','started','stoppage')) LIMIT 1;
 IF c.id IS NULL OR actor.auth_user_id IS NULL THEN RAISE EXCEPTION 'No suitable existing staging test context'; END IF;
 start_at:=((c.eta_to_kewdale+7)::timestamp+interval '8 hours') AT TIME ZONE 'Australia/Perth';
 attempted_start:=start_at-interval '1 day';
 SELECT b.bay_number INTO bay FROM public.workshop_bays b WHERE b.stage_id=c.stage_id AND b.is_active AND public.workshop_find_bay_conflict(NULL,b.id,start_at,public.workshop_add_operational_minutes(start_at,c.duration)) IS NULL ORDER BY b.bay_number LIMIT 1;
 IF bay.bay_number IS NULL THEN RAISE EXCEPTION 'No available staging bay for rollback-only test'; END IF;
 BEGIN
  PERFORM set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub',actor.auth_user_id,'email',actor.email)::text,true);
  result:=public.schedule_vehicle_work(c.id,c.version,c.code,bay.bay_number,start_at,c.duration,NULL,NULL,jsonb_build_object('source','audit_priority_rollback_only'));
  IF coalesce((result->>'ok')::boolean,false) IS NOT TRUE THEN RAISE EXCEPTION 'Canonical create test blocked: %',result->>'error'; END IF;
  SELECT id,version,scheduled_start_at INTO booking_id,booking_version,before_start FROM public.workshop_bookings WHERE vehicle_id=c.id AND deleted_at IS NULL AND scheduled_start_at=start_at AND status IN('queued','planned') ORDER BY created_at DESC LIMIT 1;
  IF booking_id IS NULL THEN RAISE EXCEPTION 'Canonical create returned no booking'; END IF;
  BEGIN
   moved:=public.move_workshop_booking(booking_id,booking_version,c.code,bay.bay_number,attempted_start,c.duration,'Rollback-only audit of ETA buffer',jsonb_build_object('source','audit_priority_rollback_only'));
  EXCEPTION WHEN SQLSTATE '22023' OR SQLSTATE '23514' THEN failure_message:=SQLERRM;
  END;
  IF coalesce((moved->>'ok')::boolean,false) IS TRUE THEN RAISE EXCEPTION 'Move to ETA+6 incorrectly succeeded'; END IF;
  IF coalesce(failure_message,moved->>'error','') NOT LIKE '%eta_plus_seven%' THEN RAISE EXCEPTION 'Move was not rejected specifically for ETA buffer: %',coalesce(failure_message,moved->>'error'); END IF;
  IF (SELECT scheduled_start_at FROM public.workshop_bookings WHERE id=booking_id) IS DISTINCT FROM before_start THEN RAISE EXCEPTION 'Rejected move changed the booking'; END IF;
  report:=jsonb_build_object('create_at_eta_plus_7','PASS','move_to_eta_plus_6_rejected','PASS','failed_move_unchanged','PASS','all_test_changes_rolled_back',true);
  RAISE EXCEPTION USING ERRCODE='PDT00',MESSAGE='rollback all booking test effects';
 EXCEPTION WHEN SQLSTATE 'PDT00' THEN NULL;
 END;
 PERFORM set_config('request.jwt.claims',coalesce(original_claims,''),true);
 IF EXISTS(SELECT 1 FROM public.workshop_bookings WHERE id=booking_id) THEN RAISE EXCEPTION 'Temporary booking survived rollback'; END IF;
 PERFORM set_config('pdc.audit_eta_test_result',report::text,true);
END $test$;
SELECT current_setting('pdc.audit_eta_test_result')::jsonb AS booking_results;
ROLLBACK;
