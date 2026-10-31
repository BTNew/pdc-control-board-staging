-- Undo r774 (F376): restore archive_569 to its r772 body (pdc_backup_r763_20261031.function_sources sig '...@r772'); remove check 489.
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';
DO $undo774$
DECLARE r record; v_def text; v_sig text := 'pdc_codex_intake_private.service_whole_archive_569(uuid,uuid)';
BEGIN
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running', 'loading')) THEN RAISE EXCEPTION 'r774 undo: an import job is running'; END IF;
  SELECT * INTO r FROM pdc_backup_r763_20261031.function_sources WHERE sig = v_sig || '@r772';
  IF NOT FOUND THEN RAISE EXCEPTION 'r774 undo: no r772 backup'; END IF;
  v_def := regexp_replace(pg_get_functiondef(v_sig::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || r.prosrc || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF md5((SELECT prosrc FROM pg_proc WHERE oid = v_sig::regprocedure)) <> r.md5 THEN RAISE EXCEPTION 'r774 undo: would not return to the r772 md5'; END IF;
END $undo774$;
DELETE FROM pdc_ops.regression_checks WHERE added_in = 'r774';
