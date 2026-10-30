-- Undo r763 (F369, F371). Restores the three function bodies from pdc_backup_r763_20261031.function_sources, drops the
-- snapshot RPC and removes checks 482/483. Snapshots recorded through the RPC stay (evidence; append-only by r479).
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';
DO $undo763$
DECLARE r record; v_def text;
BEGIN
  IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN ('queued', 'running', 'loading')) THEN RAISE EXCEPTION 'r763 undo: an import job is running'; END IF;
  FOR r IN SELECT sig, prosrc, md5 FROM pdc_backup_r763_20261031.function_sources LOOP
    v_def := regexp_replace(pg_get_functiondef(r.sig::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
    EXECUTE v_def || r.prosrc || substring(v_def from '\$[a-zA-Z_]*\$$');
    IF md5((SELECT prosrc FROM pg_proc WHERE oid = r.sig::regprocedure)) <> r.md5 THEN RAISE EXCEPTION 'r763 undo: % would not return to the pre-r763 md5', r.sig; END IF;
  END LOOP;
END $undo763$;
DROP FUNCTION IF EXISTS public.revolution_upload_snapshot_763(uuid, jsonb, jsonb);
DELETE FROM pdc_ops.regression_checks WHERE added_in = 'r763';
