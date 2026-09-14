-- Staging regression only. Every source change is rolled back.
-- Selects an already completed vehicle with an existing delivered receipt;
-- never creates a booking, completion, QC sign-off, or delivery event.
BEGIN;
SET LOCAL statement_timeout = '45s';
DO $verify$
DECLARE
  v_id uuid; b_id uuid; b_batch uuid; baseline jsonb; after_value jsonb;
  receipts_before jsonb; stats_before jsonb; history_before jsonb; result jsonb;
  checks jsonb := '[]'::jsonb;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() THEN RAISE EXCEPTION 'Staging required'; END IF;
  SELECT v.id,b.id,b.last_seen_batch_id INTO v_id,b_id,b_batch
  FROM public.vehicles v JOIN public.navision_backend_records b ON b.canonical_vehicle_id=v.id
  WHERE v.lifecycle_state='completed' AND v.dealer_transit_closed_at IS NOT NULL
    AND b.is_current AND b.record_status='current'
    AND EXISTS(SELECT 1 FROM public.pdc_rft_transport_lifecycle_receipts_734 r WHERE r.vehicle_id=v.id AND r.action='delivered')
  ORDER BY v.dealer_transit_closed_at DESC LIMIT 1;
  IF v_id IS NULL OR b_batch IS NULL THEN RAISE EXCEPTION 'No completed receipt-backed verification row'; END IF;
  SELECT jsonb_build_object('stock',stock_number,'lifecycle',lifecycle_state,'location',current_location,
    'pmb',date_to_pmb,'rft',date_to_rft,'rft_transfer',rft_transferred_at,'confirmed',rft_confirmed_at,
    'collected',rft_collected_at,'transit_start',dealer_transit_started_at,'od_recorded',dealer_transit_closed_at,
    'transit_seconds',dealer_transit_duration_seconds,'delivery_date',delivered_to_dealer_date)
    INTO baseline FROM public.vehicles WHERE id=v_id;
  SELECT jsonb_agg(to_jsonb(r) ORDER BY receipt_id) INTO receipts_before FROM public.pdc_rft_transport_lifecycle_receipts_734 r WHERE vehicle_id=v_id;
  SELECT jsonb_agg(to_jsonb(s) ORDER BY statistic_id) INTO stats_before FROM public.pdc_rft_dealer_transit_statistics_734 s WHERE vehicle_id=v_id;
  SELECT public.pdc_lifecycle_history_payload_82000(v_id) INTO history_before;

  result:=public.reconcile_navision_delivery_734(b_id,NULL,NULL);
  IF result->>'ok'<>'true' OR result->>'replay'<>'true' THEN RAISE EXCEPTION 'OD replay failed: %',result; END IF;
  checks:=checks||jsonb_build_array('Repeated OD import returns the original delivery receipt');

  UPDATE public.navision_backend_records SET normalized_data=normalized_data||jsonb_build_object(
    'toyotaStatus','Delivered - At Bodybuilder','navisionSubLocationDescription','Delivered - At Bodybuilder','navisionLocationStatus','OB') WHERE id=b_id;
  result:=public.reconcile_navision_operational_record(b_id,NULL,NULL);
  IF result->>'code'<>'protected_completed_lifecycle' THEN RAISE EXCEPTION 'Later non-OD import not protected: %',result; END IF;
  checks:=checks||jsonb_build_array('Later non-OD import cannot reopen completed lifecycle');

  UPDATE public.navision_backend_records SET is_current=false,record_status='not_in_latest_batch',missing_since_batch_id=b_batch WHERE id=b_id;
  result:=public.reconcile_navision_delivery_734(b_id,NULL,NULL);
  IF result->>'code'<>'delivery_record_not_current' THEN RAISE EXCEPTION 'Missing source handling failed: %',result; END IF;
  checks:=checks||jsonb_build_array('Source absent from a later import leaves canonical history retained');

  SELECT jsonb_build_object('stock',stock_number,'lifecycle',lifecycle_state,'location',current_location,
    'pmb',date_to_pmb,'rft',date_to_rft,'rft_transfer',rft_transferred_at,'confirmed',rft_confirmed_at,
    'collected',rft_collected_at,'transit_start',dealer_transit_started_at,'od_recorded',dealer_transit_closed_at,
    'transit_seconds',dealer_transit_duration_seconds,'delivery_date',delivered_to_dealer_date)
    INTO after_value FROM public.vehicles WHERE id=v_id;
  IF baseline IS DISTINCT FROM after_value THEN RAISE EXCEPTION 'Completed milestones changed'; END IF;
  checks:=checks||jsonb_build_array('Stock number and every retained lifecycle milestone are unchanged');
  IF receipts_before IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(r) ORDER BY receipt_id) FROM public.pdc_rft_transport_lifecycle_receipts_734 r WHERE vehicle_id=v_id)
    THEN RAISE EXCEPTION 'Completion receipts changed'; END IF;
  checks:=checks||jsonb_build_array('Immutable completion receipts are unchanged');
  IF stats_before IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(s) ORDER BY statistic_id) FROM public.pdc_rft_dealer_transit_statistics_734 s WHERE vehicle_id=v_id)
    THEN RAISE EXCEPTION 'Transit statistics changed'; END IF;
  checks:=checks||jsonb_build_array('Recorded transit statistic is unchanged');
  IF history_before IS DISTINCT FROM public.pdc_lifecycle_history_payload_82000(v_id) THEN RAISE EXCEPTION 'Lifecycle history changed'; END IF;
  checks:=checks||jsonb_build_array('PMB and RFT lifecycle history is unchanged');
  PERFORM set_config('pdc.completed_retention_verification',jsonb_build_object('passed',jsonb_array_length(checks),'checks',checks)::text,true);
END $verify$;
SELECT current_setting('pdc.completed_retention_verification')::jsonb AS verification;
ROLLBACK;
