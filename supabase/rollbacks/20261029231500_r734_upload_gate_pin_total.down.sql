-- r734 rollback: puts the pin-total lock back into the r591 gate (it will report pins_ok=false while pins <> 241)
-- and restores the check description. Staging cdsmnqxtyyoeoznmbidd only.
DO $down734$
DECLARE v_oid oid; v_src text; v_def text;
  c_new text := $n$    'pins_ok',
      (SELECT md5(p.prosrc)$n$;
  c_old text := $o$    'pins_ok',
      (SELECT count(*) FROM pdc_ops.expected_function_md5) = 241
      AND (SELECT md5(p.prosrc)$o$;
BEGIN
  v_oid := to_regprocedure('public.pdc_revolution_upload_gate_591(integer,integer,boolean,text)');
  SELECT prosrc INTO v_src FROM pg_proc WHERE oid = v_oid;
  SELECT pg_get_functiondef(v_oid) INTO v_def;
  EXECUTE replace(v_def, v_src, replace(v_src, c_new, c_old));
END $down734$;
UPDATE pdc_ops.regression_checks
SET description = 'Revolution upload stays a dry run. Kajel rows and apply stay pinned. Status 99 is skipped, sales boards 37047 and 14450 stay out of the PMB archive rule, and an open job card is not archived.'
WHERE check_name = 'revolution_upload_591';
