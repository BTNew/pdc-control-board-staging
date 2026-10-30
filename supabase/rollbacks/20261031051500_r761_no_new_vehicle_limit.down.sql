-- Rollback r761 (F367): restore the 15 new board vehicle hold in pdc_import_620.submit_finish; drop check 481.
SET LOCAL lock_timeout = '6s';
SET LOCAL statement_timeout = '120s';
DO $r761d$
DECLARE v_old text; v_new text; v_def text;
  sig regprocedure := 'pdc_import_620.submit_finish(uuid)'::regprocedure;
  b1 text := E'  -- r761 (F367): no limit on new board vehicles per upload; the leaving-the-board gate stays in apply_part.\n';
  a1 text := E'  IF v_job.mode = ''apply'' AND v_new > 15 THEN v_status := ''held''; v_note := format(''sanity gate: %s new board vehicles (more than 15)'', v_new); END IF;\n';
BEGIN
  SELECT prosrc INTO v_old FROM pg_proc WHERE oid = sig;
  v_new := replace(v_old, b1, a1);
  IF md5(v_new) <> '1b2efb3460607fd58d3eb491f05387bf' THEN RAISE EXCEPTION 'r761 down: body would not return to the pre-r761 md5'; END IF;
  v_def := regexp_replace(pg_get_functiondef(sig), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  DELETE FROM pdc_ops.regression_checks WHERE check_name = 'no_new_vehicle_limit_761';
END $r761d$;
