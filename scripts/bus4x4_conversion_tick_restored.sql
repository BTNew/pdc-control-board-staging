-- The previous gate is back: an unticked import is blocked, and a stored tick is not reopened.
DO $restored$
DECLARE result jsonb; still boolean;
BEGIN
 result := pg_temp.tick('coaster-before', true);
 IF result->>'error' IS DISTINCT FROM 'conversion_sections_required' THEN
  RAISE EXCEPTION 'restored command accepted a tick %', result;
 END IF;
 PERFORM pg_temp.assert_blocked('80', 'coaster-before');
 PERFORM pg_temp.assert_blocked('99', 'hiace-before');
 SELECT completed INTO still FROM pdc_fitter_private.operation_progress WHERE booking_id = pg_temp.bid('coaster-after');
 IF still IS NOT TRUE THEN RAISE EXCEPTION 'rollback cleared the ticked conversion'; END IF;
 IF pg_temp.import80('coaster-after') IS DISTINCT FROM 'skipped' THEN
  RAISE EXCEPTION 'rollback applied a second Sub Status 80';
 END IF;
 IF (SELECT count(*) FROM pdc_codex_intake_private.tune_pmb_complete_receipts WHERE vehicle_id = pg_temp.vid('coaster-after')) <> 1 THEN
  RAISE EXCEPTION 'rollback duplicated the Sub Status 80 receipt';
 END IF;
 IF (SELECT completed FROM public.vehicle_work_items WHERE vehicle_id = pg_temp.vid('hiace-99') AND work_key = 'qc') THEN
  RAISE EXCEPTION 'rollback completed QC';
 END IF;
END $restored$;
