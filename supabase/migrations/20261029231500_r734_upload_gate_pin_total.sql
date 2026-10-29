-- r734 (F339, part three): the r591 upload gate pdc_revolution_upload_gate_591 computed pins_ok with the pin table
-- total locked to 241 inside the function body, so the moment r732 added a pin the regression check
-- revolution_upload_591 went red. The r728 website upload only uses this gate for duplicate-file detection, so
-- uploads were never affected. pins_ok now checks the three bodies it cares about and nothing else. The check's
-- description is brought up to date: since r728 Apply is live for Service as a Whole through its own RPCs; this
-- old gate still answers apply_enabled=false because nothing applies through it.
-- Staging cdsmnqxtyyoeoznmbidd only. Production never touched.
-- Rollback: supabase/rollbacks/20261029231500_r734_upload_gate_pin_total.down.sql

DO $r734$
DECLARE v_oid oid; v_src text; v_new text; v_def text;
  c_old text := $o$    'pins_ok',
      (SELECT count(*) FROM pdc_ops.expected_function_md5) = 241
      AND (SELECT md5(p.prosrc)$o$;
  c_new text := $n$    'pins_ok',
      (SELECT md5(p.prosrc)$n$;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r734: staging only'; END IF;
  v_oid := to_regprocedure('public.pdc_revolution_upload_gate_591(integer,integer,boolean,text)');
  IF v_oid IS NULL THEN RAISE EXCEPTION 'r734: gate missing'; END IF;
  IF EXISTS (SELECT 1 FROM pdc_ops.expected_function_md5 WHERE signature LIKE '%revolution_upload_gate_591%') THEN RAISE EXCEPTION 'r734: the gate is pinned, this file does not expect that'; END IF;
  SELECT prosrc INTO v_src FROM pg_proc WHERE oid = v_oid;
  IF (length(v_src) - length(replace(v_src, c_old, ''))) / length(c_old) <> 1 THEN RAISE EXCEPTION 'r734: anchor not found once; nothing changed'; END IF;
  v_new := replace(v_src, c_old, c_new);
  SELECT pg_get_functiondef(v_oid) INTO v_def;
  EXECUTE replace(v_def, v_src, v_new);
  SELECT prosrc INTO v_src FROM pg_proc WHERE oid = v_oid;
  IF v_src <> v_new THEN RAISE EXCEPTION 'r734: readback differs'; END IF;
  IF (public.pdc_revolution_upload_gate_591(0, 0, false, 'abc')->>'pins_ok') IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'r734: pins_ok still false'; END IF;
END $r734$;

UPDATE pdc_ops.regression_checks
SET description = 'The r591 upload gate still answers apply_enabled=false (since r728 the website applies Service as a Whole through its own RPCs, not this gate), reports duplicate files, and its pins_ok follows the Kajel rows, apply and Department 135 bodies (no pin-total lock since r734). Status 99 is skipped, sales boards 37047 and 14450 stay out of the PMB archive rule, and an open job card is not archived.'
WHERE check_name = 'revolution_upload_591';

DO $post734$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM pdc_ops.fault_regression_check() x WHERE x.check_name IN ('revolution_upload_591','regression_checks_self_test','protected_function_md5s') LOOP
    IF NOT r.ok THEN RAISE EXCEPTION 'r734: % red after apply: %', r.check_name, left(r.detail, 160); END IF;
  END LOOP;
END $post734$;
