-- Unticked Coaster and HiAce imports still stop, on the old gate and on the new one.
DO $before$
DECLARE state_before jsonb; state_after jsonb; loc text; receipts integer;
BEGIN
 SELECT to_jsonb(s) INTO state_before FROM pdc_fitter_private.conversion_state s
  WHERE vehicle_id = pg_temp.vid('coaster-before');
 PERFORM pg_temp.assert_blocked('80', 'coaster-before');
 PERFORM pg_temp.assert_blocked('99', 'coaster-before');
 PERFORM pg_temp.assert_blocked('80', 'hiace-before');
 PERFORM pg_temp.assert_blocked('99', 'hiace-before');
 IF EXISTS (SELECT 1 FROM public.vehicle_work_items WHERE vehicle_id = pg_temp.vid('coaster-before') AND completed) THEN
  RAISE EXCEPTION 'unticked import completed a work item';
 END IF;
 IF EXISTS (SELECT 1 FROM pdc_fitter_private.operation_progress p WHERE p.booking_id = pg_temp.bid('coaster-before')) THEN
  RAISE EXCEPTION 'unticked import wrote operation progress';
 END IF;
 SELECT current_location INTO loc FROM public.vehicles WHERE id = pg_temp.vid('coaster-before');
 IF loc IS DISTINCT FROM 'PMB' THEN RAISE EXCEPTION 'unticked import moved the vehicle to %', loc; END IF;
 SELECT count(*) INTO receipts FROM pdc_codex_intake_private.tune_pmb_complete_receipts
  WHERE vehicle_id IN (pg_temp.vid('coaster-before'), pg_temp.vid('hiace-before'));
 IF receipts <> 0 THEN RAISE EXCEPTION 'unticked import stored a Sub Status 80 receipt'; END IF;
 SELECT count(*) INTO receipts FROM pdc_codex_intake_private.tune_checkout_receipts
  WHERE vehicle_id IN (pg_temp.vid('coaster-before'), pg_temp.vid('hiace-before'));
 IF receipts <> 0 THEN RAISE EXCEPTION 'unticked import stored a Sub Status 99 receipt'; END IF;
 SELECT status INTO loc FROM public.workshop_bookings WHERE id = pg_temp.bid('coaster-before');
 IF loc IS DISTINCT FROM 'started' THEN RAISE EXCEPTION 'unticked import completed the booking'; END IF;
 IF (SELECT default_duration_minutes FROM public.workshop_bookings WHERE id = pg_temp.bid('coaster-before')) <> 3600 THEN
  RAISE EXCEPTION 'unticked import changed booking hours';
 END IF;
 SELECT to_jsonb(s) INTO state_after FROM pdc_fitter_private.conversion_state s
  WHERE vehicle_id = pg_temp.vid('coaster-before');
 IF state_before IS DISTINCT FROM state_after THEN RAISE EXCEPTION 'unticked import rewrote section history'; END IF;
 IF (SELECT count(*) FROM pdc_fitter_private.conversion_audit) <> 0 THEN
  RAISE EXCEPTION 'unticked import wrote conversion audit';
 END IF;
 IF pg_temp.import80('already-qc') IS DISTINCT FROM 'skipped' THEN
  RAISE EXCEPTION 'Sub Status 80 did not skip a vehicle already in QC';
 END IF;
 IF EXISTS (SELECT 1 FROM public.vehicle_work_items WHERE vehicle_id = pg_temp.vid('already-qc') AND completed) THEN
  RAISE EXCEPTION 'QC vehicle work was completed';
 END IF;
 IF EXISTS (SELECT 1 FROM pdc_codex_intake_private.tune_pmb_complete_receipts WHERE vehicle_id = pg_temp.vid('already-qc')) THEN
  RAISE EXCEPTION 'QC vehicle received a completion receipt';
 END IF;
END $before$;
