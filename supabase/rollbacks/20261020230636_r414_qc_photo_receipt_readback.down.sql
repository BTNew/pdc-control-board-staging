-- r414 undo: removes get_pdc_qc_photo_receipt_414 and its check. Nothing else was changed by r414.
-- Run between :02 and :45 with lock_timeout 2s. Staging only. Revert the r414 PR too (the page then forgets receipts on refresh again).
SET LOCAL lock_timeout = '2s';
DO $g$ BEGIN
 IF extract(second FROM clock_timestamp()) NOT BETWEEN 2 AND 45 THEN RAISE EXCEPTION 'r414 undo: run between :02 and :45 (release-test window; the clock tick runs at :00)'; END IF;
 IF NOT public.pdc_monitor_staging_guard()
    OR (SELECT count(*) FROM public.pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd')<>1
    OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r414 undo: staging only'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('public.get_pdc_qc_photo_receipt_414(uuid)')) IS DISTINCT FROM '313140d87083899267fff7ea3275ca5b' THEN RAISE EXCEPTION 'r414 undo: get_pdc_qc_photo_receipt_414 is not the r414 version'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.record_pdc_qc_photo_evidence_399(uuid,integer,text,text,text,integer,integer,integer,integer,text,text,uuid)'::regprocedure)<>'aca6f38ffba657e5828aeb81f56d1b7a'
    OR (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.finalize_pdc_qc_to_rft_700(uuid,integer,uuid,uuid)'::regprocedure)<>'e4c7271b2efe49ed45117f600b6fe954'
 THEN RAISE EXCEPTION 'r414 undo: upload or sign-off function changed since r414; check before undoing'; END IF;
END $g$;
DELETE FROM pdc_ops.regression_checks WHERE check_name='qc_photo_receipt_readable' AND added_in='r414';
DROP FUNCTION public.get_pdc_qc_photo_receipt_414(uuid);
DO $a$ BEGIN
 IF to_regprocedure('public.get_pdc_qc_photo_receipt_414(uuid)') IS NOT NULL OR EXISTS(SELECT 1 FROM pdc_ops.regression_checks WHERE check_name='qc_photo_receipt_readable')
 THEN RAISE EXCEPTION 'r414 undo: not fully removed'; END IF;
END $a$;
