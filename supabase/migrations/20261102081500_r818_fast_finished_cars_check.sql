-- r818 (F457): check 602 finished_cars_stay_finished_814 (night review, F452) scanned every Navision record per active car
-- through normalize_vehicle_stock_number and took ~22 s, hitting the statement timeout and stopping the whole check run.
-- It now reads the Navision status the linked refresh already keeps on the car (source_payload.navision_status): 11 ms,
-- same answer (0 finished cars active).
UPDATE pdc_ops.regression_checks SET check_sql = $chk$
SELECT NOT EXISTS (
  SELECT 1 FROM public.vehicles v
  WHERE v.deleted_at IS NULL AND v.lifecycle_state::text = 'active'
    AND (v.source_payload ? 'admin_completed_800' OR v.source_payload->>'navision_status' = 'Delivered - At Dealer'))
 AS ok, 'finished cars stay finished (r818: fast)' AS detail
$chk$
WHERE check_name = 'finished_cars_stay_finished_814';
