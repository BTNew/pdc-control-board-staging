-- r737 rollback: puts the strict order test back (the whole linked group aborts again when a planned job lands behind
-- another car's queued slot), moves the pin and md5 checks back, removes the check. Staging cdsmnqxtyyoeoznmbidd only.
DO $down737$
DECLARE v_old text; v_new text; v_def text; v_md5 text;
  c_new text := E'     AND a.status<>''stoppage''\n     AND b.status<>''stoppage''\n     -- r737 (F343): a planned job pushed behind another car''s fixed slot (started or queued in the bay) keeps no order with it;\n     -- the obstacle loop already keeps them apart. Same-car stage order is still enforced.\n     AND NOT (a.vehicle_id<>b.vehicle_id AND (b.status IN(''started'',''stoppage'',''queued'') OR b.actual_start_at IS NOT NULL))\n     AND a.final_end+CASE';
  c_old text := E'     AND a.status<>''stoppage''\n     AND b.status<>''stoppage''\n     AND a.final_end+CASE';
BEGIN
  SELECT prosrc, md5(prosrc) INTO v_old, v_md5 FROM pg_proc WHERE oid = 'public.workshop_clock_tick(boolean,timestamptz)'::regprocedure;
  IF (length(v_old) - length(replace(v_old, c_new, ''))) / length(c_new) <> 1 THEN RAISE EXCEPTION 'r737 down: anchor not found once'; END IF;
  v_new := replace(v_old, c_new, c_old);
  v_def := regexp_replace(pg_get_functiondef('public.workshop_clock_tick(boolean,timestamptz)'::regprocedure), '(AS \$[a-zA-Z_]*\$).*$', '\1', 's');
  EXECUTE v_def || v_new || substring(v_def from '\$[a-zA-Z_]*\$$');
  UPDATE pdc_ops.expected_function_md5 SET prosrc_md5 = md5(v_new) WHERE prosrc_md5 = v_md5;
  UPDATE pdc_ops.regression_checks SET check_sql = replace(check_sql, v_md5, md5(v_new)) WHERE strpos(check_sql, v_md5) > 0;
  DELETE FROM pdc_ops.regression_checks WHERE check_name = 'cascade_leapfrogs_fixed_slot_737';
END $down737$;
