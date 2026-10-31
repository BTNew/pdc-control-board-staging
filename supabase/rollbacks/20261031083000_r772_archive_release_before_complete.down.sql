-- Undo r772 (F373). Restores archive_569 and begin_728 to their r763 bodies from pdc_backup_r763_20261031.function_sources (*@r763), removes check 487,
-- and puts check 482 back to the r763 wording.
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';
DO $undo772$
DECLARE r record; v_def text; v_sig text;
BEGIN
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running', 'loading')) THEN RAISE EXCEPTION 'r772 undo: an import job is running'; END IF;
  FOR r IN SELECT sig, prosrc, md5 FROM pdc_backup_r763_20261031.function_sources WHERE sig LIKE '%@r763' LOOP
    v_sig := replace(r.sig, '@r763', '');
    v_def := regexp_replace(pg_get_functiondef(v_sig::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
    EXECUTE v_def || r.prosrc || substring(v_def from '\$[a-zA-Z_]*\$$');
    IF md5((SELECT prosrc FROM pg_proc WHERE oid = v_sig::regprocedure)) <> r.md5 THEN RAISE EXCEPTION 'r772 undo: % would not return to the r763 md5', v_sig; END IF;
  END LOOP;
END $undo772$;
UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, $$p->'apply'->>'ok' IS DISTINCT FROM 'true'$$, $$p->'apply'->>'ok' = 'true'$$) WHERE check_name = 'website_snapshot_recorded_763';
DELETE FROM pdc_ops.regression_checks WHERE added_in = 'r772';
