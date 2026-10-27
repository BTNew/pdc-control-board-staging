-- Undo r563 (F177). Staging only. Drops the arrival-age table and its triggers.
-- Restores nothing in r562: the key gate, the key table, and the key triggers stay.
-- Does not change vehicles.current_location and does not delete arrival rows.

SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r563 undo: run between :02 and :45'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR pg_catalog.to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r563 undo: staging only'; END IF;
 IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_name='pmb_arrival_age_563' AND fault_id='F177' AND sort_order=336 AND added_in='r563')<>1 THEN RAISE EXCEPTION 'r563 undo: F177 check is not the r563 row'; END IF;
END $g$;

DROP TRIGGER IF EXISTS zz_pdc_arrival_age_563_key ON public.pdc_vehicle_key_assigned_562;
DROP TRIGGER IF EXISTS zz_pdc_arrival_age_563_pmb ON pdc_codex_intake_private.tune_pmb_complete_receipts;
DROP TRIGGER IF EXISTS zz_pdc_arrival_age_563_out ON pdc_codex_intake_private.tune_checkout_receipts;
DROP TRIGGER IF EXISTS zz_pdc_arrival_age_563_evidence ON public.pdc_tune_intake_evidence_v5;
DROP TRIGGER IF EXISTS zz_pdc_arrival_age_563_veh ON public.vehicles;
DROP TRIGGER IF EXISTS zz_pdc_arrival_age_563_veh_upd ON public.vehicles;
DROP FUNCTION IF EXISTS public.list_pmb_arrival_age_563();
DROP FUNCTION IF EXISTS pdc_pmb_ack_private.capture_arrival_age_563();
DROP FUNCTION IF EXISTS pdc_pmb_ack_private.refresh_arrival_age_563(uuid);
DROP TABLE IF EXISTS public.pdc_vehicle_pmb_arrival_age_563;

DELETE FROM pdc_ops.regression_checks
WHERE check_name='pmb_arrival_age_563' AND fault_id='F177' AND sort_order=336 AND added_in='r563';

DO $post$ BEGIN
 IF EXISTS (SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='pmb_arrival_age_563' OR fault_id='F177' OR added_in='r563' OR sort_order=336) THEN RAISE EXCEPTION 'r563 undo: check remains'; END IF;
 IF pg_catalog.to_regclass('public.pdc_vehicle_pmb_arrival_age_563') IS NOT NULL THEN RAISE EXCEPTION 'r563 undo: age table remains'; END IF;
 IF pg_catalog.to_regclass('public.pdc_vehicle_key_assigned_562') IS NULL THEN RAISE EXCEPTION 'r563 undo: key table was removed'; END IF;
 IF (SELECT count(*) FROM pdc_ops.expected_function_md5)<>241 THEN RAISE EXCEPTION 'r563 undo: pin count changed'; END IF;
 IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE release='r563') THEN RAISE EXCEPTION 'r563 undo: a pin remains'; END IF;
END $post$;
