-- Staging verification, using the user-reported vehicle inside rollback-only
-- subtransactions. No test start, delivery, timer or receipt is committed.
BEGIN;
SET LOCAL statement_timeout='60s';
DO $verify$
DECLARE target uuid; backend uuid; booking uuid; result jsonb; state text; actor uuid; email text;
 baseline_work jsonb; baseline_parts jsonb; baseline_other_bookings jsonb;
 baseline_milestones jsonb; checks jsonb:='[]'; vehicle_after public.vehicles%rowtype;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'Staging required'; END IF;
 SELECT auth_user_id,u.email INTO actor,email FROM public.pdc_user_roles u
 WHERE u.email='craig.watson@broometoyota.com.au' AND u.active AND u.account_status='approved' AND u.role::text='administrator';
 IF actor IS NULL THEN RAISE EXCEPTION 'Approved owner required'; END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor,'email',email,'role','authenticated')::text,true);
 SELECT v.id,b.id,w.id INTO target,backend,booking FROM public.vehicles v
 JOIN public.navision_backend_records b ON b.canonical_vehicle_id=v.id
 JOIN public.workshop_bookings w ON w.vehicle_id=v.id AND w.deleted_at IS NULL AND w.status='planned'
 WHERE v.stock_number='12311009' AND b.is_current AND b.record_status='current' AND v.lifecycle_state='active';
 IF target IS NULL THEN RAISE EXCEPTION 'Reported active verification booking not found'; END IF;
 SELECT jsonb_agg(to_jsonb(w) ORDER BY w.id) INTO baseline_work FROM public.vehicle_work_items w WHERE vehicle_id=target;
 SELECT jsonb_agg(to_jsonb(p) ORDER BY p.id) INTO baseline_parts FROM public.vehicle_parts_updates p WHERE vehicle_id=target;
 SELECT jsonb_agg(jsonb_build_array(w.id,w.vehicle_id,w.status,w.deleted_at,w.actual_start_at,w.actual_end_at) ORDER BY w.id)
 INTO baseline_other_bookings FROM public.workshop_bookings w WHERE vehicle_id<>target;
 SELECT jsonb_build_object('qc',qc_completed_at,'qc_by',qc_completed_by,'collected',rft_collected_at,
  'collected_by',rft_collected_by,'transit_start',dealer_transit_started_at) INTO baseline_milestones FROM public.vehicles WHERE id=target;
 FOREACH state IN ARRAY ARRAY['queued','planned','started','stoppage','linked'] LOOP
  BEGIN
   IF state<>'linked' THEN
   UPDATE public.navision_backend_records SET normalized_data=normalized_data||jsonb_build_object(
    'toyotaStatus','Despatched - From Body Builder','navisionSubLocationDescription','Despatched - From Body Builder') WHERE id=backend;
   END IF;
   IF state='queued' THEN
    PERFORM public.workshop_authorize_transition(booking,'return_to_queue');
    UPDATE public.workshop_bookings SET status='queued',bay_id=NULL,returned_to_queue_at=clock_timestamp(),
     scheduled_end_at=public.workshop_add_operational_minutes(scheduled_start_at,default_duration_minutes) WHERE id=booking;
   END IF;
   IF state IN('started','stoppage') THEN
    UPDATE public.workshop_bookings SET status='started',actual_start_at=clock_timestamp() WHERE id=booking;
   END IF;
   IF state='stoppage' THEN
    UPDATE public.workshop_bookings SET status='stoppage',stoppage_reason='Rollback-only verification',stoppage_started_at=clock_timestamp() WHERE id=booking;
   END IF;
   IF state='linked' THEN
    UPDATE public.navision_backend_records SET canonical_vehicle_id=NULL WHERE id=backend;
    UPDATE public.navision_backend_records SET canonical_vehicle_id=target WHERE id=backend;
   ELSE
    UPDATE public.navision_backend_records SET normalized_data=normalized_data||jsonb_build_object(
     'toyotaStatus','Delivered - At Dealer','navisionSubLocationDescription','Delivered - At Dealer') WHERE id=backend;
   END IF;
   SELECT * INTO vehicle_after FROM public.vehicles WHERE id=target;
   IF vehicle_after.lifecycle_state<>'completed' OR vehicle_after.current_location<>'Completed' OR vehicle_after.visible_on_board
   OR vehicle_after.active_workshop_booking_id IS NOT NULL THEN RAISE EXCEPTION 'Completion failed for %',state; END IF;
   IF EXISTS(SELECT 1 FROM public.workshop_bookings WHERE vehicle_id=target AND deleted_at IS NULL AND status IN('queued','planned','started','stoppage'))
   THEN RAISE EXCEPTION 'Active booking retained for %',state; END IF;
   IF NOT EXISTS(SELECT 1 FROM public.workshop_booking_history WHERE booking_id=booking AND event_type='navision_dealer_delivery_cancelled')
   THEN RAISE EXCEPTION 'Cancellation history missing'; END IF;
   IF EXISTS(SELECT 1 FROM public.workshop_booking_assignments WHERE booking_id=booking AND released_at IS NULL)
   THEN RAISE EXCEPTION 'Technician interval retained'; END IF;
   IF baseline_work IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(w) ORDER BY w.id) FROM public.vehicle_work_items w WHERE vehicle_id=target)
   OR baseline_parts IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(p) ORDER BY p.id) FROM public.vehicle_parts_updates p WHERE vehicle_id=target)
   THEN RAISE EXCEPTION 'Work or Parts altered'; END IF;
   IF baseline_milestones IS DISTINCT FROM (SELECT jsonb_build_object('qc',qc_completed_at,'qc_by',qc_completed_by,
    'collected',rft_collected_at,'collected_by',rft_collected_by,'transit_start',dealer_transit_started_at) FROM public.vehicles WHERE id=target)
   THEN RAISE EXCEPTION 'QC, collection or transport was invented'; END IF;
   IF EXISTS(SELECT 1 FROM public.pdc_rft_dealer_transit_statistics_734 WHERE vehicle_id=target)
   THEN RAISE EXCEPTION 'Transit duration invented'; END IF;
   result:=public.reconcile_navision_delivery_734(backend,NULL,NULL);
   IF result->>'ok'<>'true' OR result->>'replay'<>'true' OR (result#>>'{data,cancelled_bookings}')::int<>0
   THEN RAISE EXCEPTION 'Replay is not idempotent: %',result; END IF;
   BEGIN
    UPDATE public.workshop_bookings SET status='queued',bay_id=NULL,deleted_at=NULL WHERE id=booking;
    RAISE EXCEPTION 'Completed vehicle booking was restored';
   EXCEPTION WHEN SQLSTATE '22023' THEN
    IF SQLERRM<>'dealer_delivered_vehicle_cannot_be_booked' THEN RAISE; END IF;
   END;
   IF baseline_other_bookings IS DISTINCT FROM (SELECT jsonb_agg(jsonb_build_array(w.id,w.vehicle_id,w.status,w.deleted_at,w.actual_start_at,w.actual_end_at) ORDER BY w.id) FROM public.workshop_bookings w WHERE vehicle_id<>target)
   THEN RAISE EXCEPTION 'Another vehicle booking lifecycle changed in %',state; END IF;
   -- Roll back this scenario before testing the next booking state.
   RAISE EXCEPTION 'scenario_passed' USING ERRCODE='P0002';
  EXCEPTION WHEN SQLSTATE 'P0002' THEN
   IF SQLERRM<>'scenario_passed' THEN RAISE; END IF;
   checks:=checks||jsonb_build_array(state||': automatic completion, cancellation, audit, preserved work/Parts/QC, no invented transit, replay and rebooking guard');
  END;
 END LOOP;
 result:=public.reconcile_navision_delivery_734(backend,NULL,NULL);
 IF result->>'ok'<>'true' THEN RAISE EXCEPTION 'Direct backfill failed: %',result; END IF;
 checks:=checks||jsonb_build_array('Direct repair uses the same final-delivery rule');
 PERFORM set_config('pdc.delivery_rule_verification',jsonb_build_object('passed',jsonb_array_length(checks),'checks',checks)::text,true);
END $verify$;
SELECT current_setting('pdc.delivery_rule_verification')::jsonb AS verification;
ROLLBACK;
