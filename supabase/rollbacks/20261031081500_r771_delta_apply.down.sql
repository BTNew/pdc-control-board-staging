-- Undo r771 (F372). Restores run_jobs from pdc_backup_r763_20261031.function_sources, drops the two helper functions, removes check 484.
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';
DO $undo764$
DECLARE r record; v_def text;
BEGIN
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running', 'loading')) THEN RAISE EXCEPTION 'r771 undo: an import job is running'; END IF;
  SELECT * INTO r FROM pdc_backup_r763_20261031.function_sources WHERE sig = 'pdc_import_620.run_jobs()';
  IF NOT FOUND THEN RAISE EXCEPTION 'r771 undo: no backup of run_jobs'; END IF;
  v_def := regexp_replace(pg_get_functiondef(r.sig::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || r.prosrc || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF md5((SELECT prosrc FROM pg_proc WHERE oid = r.sig::regprocedure)) <> r.md5 THEN RAISE EXCEPTION 'r771 undo: run_jobs would not return to the pre-r771 md5'; END IF;
END $undo764$;
DROP FUNCTION IF EXISTS pdc_import_620.part_skip_771(uuid, integer, timestamptz);
DROP FUNCTION IF EXISTS pdc_import_620.row_content_hash_771(jsonb);
DELETE FROM pdc_ops.regression_checks WHERE added_in = 'r771';
