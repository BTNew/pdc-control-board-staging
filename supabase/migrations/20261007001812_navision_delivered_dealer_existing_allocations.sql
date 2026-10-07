-- Reconcile only current, exactly linked dealer-delivered PMB vehicles.
-- Uses the same audited rule as future imports; no generated IDs are embedded.
DO $repair$
DECLARE row record; result jsonb;
BEGIN
 IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'wrong_environment'; END IF;
 FOR row IN SELECT b.id FROM public.navision_backend_records b JOIN public.vehicles v ON v.id=b.canonical_vehicle_id
 WHERE b.is_current AND b.record_status='current' AND v.deleted_at IS NULL
 AND pdc_navision_delivery_private.exact_link(b.id,v.id)
 AND (v.lifecycle_state<>'completed' OR v.current_location IS DISTINCT FROM 'Completed' OR v.visible_on_board
  OR EXISTS(SELECT 1 FROM public.workshop_bookings w WHERE w.vehicle_id=v.id AND w.deleted_at IS NULL
   AND w.status IN('queued','planned','started','stoppage')))
 ORDER BY b.id LOOP
  result:=public.reconcile_navision_delivery_734(row.id,NULL,NULL);
  IF result->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'dealer_delivery_repair_failed: %',result->>'code'; END IF;
 END LOOP;
END $repair$;
