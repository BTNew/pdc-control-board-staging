-- Undo r776 (F379): restore archive_569 to its r774 body (pdc_backup_r763_20261031.function_sources sig '...@r774'); remove check 491.
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';
DO $undo776$
DECLARE r record; v_def text; v_sig text := 'pdc_codex_intake_private.service_whole_archive_569(uuid,uuid)';
BEGIN
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running', 'loading')) THEN RAISE EXCEPTION 'r776 undo: an import job is running'; END IF;
  SELECT * INTO r FROM pdc_backup_r763_20261031.function_sources WHERE sig = v_sig || '@r774';
  IF NOT FOUND THEN RAISE EXCEPTION 'r776 undo: no r774 backup'; END IF;
  v_def := regexp_replace(pg_get_functiondef(v_sig::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || r.prosrc || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF md5((SELECT prosrc FROM pg_proc WHERE oid = v_sig::regprocedure)) <> r.md5 THEN RAISE EXCEPTION 'r776 undo: would not return to the r774 md5'; END IF;
END $undo776$;
DELETE FROM pdc_ops.regression_checks WHERE added_in = 'r776';
