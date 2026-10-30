-- r743 rollback: remove the three second pause between import parts. Staging cdsmnqxtyyoeoznmbidd only.
DO $down743$
DECLARE v_old text; v_new text; v_def text;
  c_new text := E'    COMMIT;\n    -- r743: let the board''s own writes through between parts; the lock above is per part, this is the gap.\n    IF EXISTS (SELECT 1 FROM pdc_import_620.jobs WHERE status IN (''queued'', ''running'')) THEN PERFORM pg_catalog.pg_sleep(3); END IF;\n  END LOOP;';
  c_old text := E'    COMMIT;\n  END LOOP;';
BEGIN
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = 'pdc_import_620.run_jobs()'::regprocedure;
  IF (length(v_old) - length(replace(v_old, c_new, ''))) / length(c_new) <> 1 THEN RAISE EXCEPTION 'r743 down: anchor not found once'; END IF;
  v_new := replace(v_old, c_new, c_old);
  v_def := regexp_replace(pg_get_functiondef('pdc_import_620.run_jobs()'::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  IF md5((SELECT prosrc FROM pg_proc WHERE oid = 'pdc_import_620.run_jobs()'::regprocedure)) <> 'f05db04600dc405e1d1c269ad26ee5d5' THEN RAISE EXCEPTION 'r743 down: body is not the r620 body'; END IF;
END $down743$;
