-- Undo r641 (F256): drop chunked loading. Staging only. The r620 functions are restored by re-running the r620 file's
-- CREATE FUNCTION bodies as CREATE OR REPLACE (preview_part, apply_part, run_jobs, job_receipt, submit_service_whole, hold_stocks).
SET LOCAL lock_timeout = '4s';
DELETE FROM pdc_ops.regression_checks WHERE check_name = 'one_step_import_chunks_641' AND added_in = 'r641';
DROP FUNCTION IF EXISTS pdc_import_620.submit_begin(text, jsonb, text);
DROP FUNCTION IF EXISTS pdc_import_620.add_rows(uuid, jsonb);
DROP FUNCTION IF EXISTS pdc_import_620.submit_finish(uuid);
DROP TABLE IF EXISTS pdc_import_620.job_rows;
