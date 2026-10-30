-- Rollback r759 (F365): restore the r569 archive body from the backup schema and drop check 476.
-- Cars already completed by r759 stay completed (data); restore them by hand from pdc_backup_r759_20261030.vehicles if needed.
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';
DO $r759d$
DECLARE v_def text;
BEGIN
  SELECT def INTO v_def FROM pdc_backup_r759_20261030.function_sources WHERE nspname = 'pdc_codex_intake_private' AND proname = 'service_whole_archive_569' AND prosrc_md5 = '6bd4a75d2b96a187b3e0d5ff99f4d217';
  IF v_def IS NULL THEN RAISE EXCEPTION 'r759 down: backed-up r569 body not found'; END IF;
  EXECUTE v_def;
  IF md5((SELECT prosrc FROM pg_proc WHERE oid = 'pdc_codex_intake_private.service_whole_archive_569(uuid,uuid)'::regprocedure)) <> '6bd4a75d2b96a187b3e0d5ff99f4d217' THEN RAISE EXCEPTION 'r759 down: body did not return to the r569 md5'; END IF;
  DELETE FROM pdc_ops.regression_checks WHERE check_name = 'upload_left_revolution_rules_759';
END $r759d$;
