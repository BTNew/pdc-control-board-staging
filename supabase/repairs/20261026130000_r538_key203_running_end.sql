-- GO-LIVE ONLY. Do not apply with the r538 preview. Staging cdsmnqxtyyoeoznmbidd only.
-- Run as its own step after 20261026130000_r538_running_booking_end.sql is on the ledger.
-- Key 203, stock IS60070112, job J139125575. Fitting booking 9e523fc4-c539-4ef0-961b-b21d774ffc26.
-- Read on 26 Oct 2026: started Mon 26 Oct 07:39, stored finish 07:40 (1 minute), Chelsea Rees # 2, PMB Bay 06.
-- Effective planner length 436 minutes from that same start, which is Mon 26 Oct 14:55.
-- This calls the r538 function. The start and actual start are not updated.
-- The r538 undo does not put this finish back.

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r538 repair: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r538 repair: staging only'; END IF;
 IF to_regprocedure('public.workshop_extend_running_booking_538(uuid,text,integer)') IS NULL THEN RAISE EXCEPTION 'r538 repair: extender is not installed'; END IF;
 IF NOT EXISTS (
  SELECT 1 FROM public.workshop_bookings b
  JOIN public.vehicles v ON v.id=b.vehicle_id
  WHERE b.id='9e523fc4-c539-4ef0-961b-b21d774ffc26'
   AND v.stock_number='IS60070112' AND v.job_card_number='J139125575' AND v.key_number::text='203'
   AND b.status='started' AND b.deleted_at IS NULL
   AND b.scheduled_start_at='2026-10-25 23:39:00+00' AND b.actual_start_at='2026-10-25 23:39:00+00') THEN
  RAISE EXCEPTION 'r538 repair: Key 203 fitting booking is not the 07:39 started row';
 END IF;
END $g$;

SELECT public.workshop_extend_running_booking_538('9e523fc4-c539-4ef0-961b-b21d774ffc26'::uuid, 'key203_repair_538', NULL);
