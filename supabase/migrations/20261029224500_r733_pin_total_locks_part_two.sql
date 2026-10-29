-- r733 (F339, part two): 24 more regression checks lock the pin table total to a literal 241 through an alias
-- (pins.n = 241, pin_count = 241, (SELECT n FROM pins) = 241, (SELECT 241)), which the r529 self test did not see.
-- Every added pin would turn them all red (r732 adds one). The literal compare becomes TRUE in each (the rest of
-- every check is untouched; each was run before and after and gave the same answer), and the self test gains a
-- regex that catches any alias form comparing a pin count to a three-digit literal.
-- Staging cdsmnqxtyyoeoznmbidd only. Production never touched. No vehicle, booking, line or tick changes.
-- Rollback: supabase/rollbacks/20261029224500_r733_pin_total_locks_part_two.down.sql (restores the self test only;
-- the literal locks stay out on purpose, as in r729).

DO $pre733$
DECLARE v_self text; c_anchor text := $old$     OR c.check_sql ~* $re6$[0-9]+\s*(=|<>|!=)\s*\(\s*select\s+count\(\s*\*\s*\)\s+from\s+pdc_ops\.expected_function_md5\s*\)$re6$$old$;
BEGIN
  IF NOT public.pdc_monitor_staging_guard() OR to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL THEN RAISE EXCEPTION 'r733: staging only'; END IF;
  IF (SELECT count(*) FROM pdc_ops.expected_function_md5) <> 241 THEN RAISE EXCEPTION 'r733: pin count is not 241 (run before r732)'; END IF;
  IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_sql ~* '(\mpins\.(n|pin_count)|\(\s*select\s+(n|pin_count)\s+from\s+pins\s*\)|\s+pins\s*\)|\mpin_count)\s*(=|<>|!=)\s*\(?\s*(select\s+)?[0-9]{3,}') <> 24 THEN
    RAISE EXCEPTION 'r733: expected 24 checks with an aliased pin-total lock; nothing changed';
  END IF;
  SELECT check_sql INTO v_self FROM pdc_ops.regression_checks WHERE check_name = 'regression_checks_self_test';
  IF (length(v_self) - length(replace(v_self, c_anchor, ''))) / length(c_anchor) <> 2 THEN
    RAISE EXCEPTION 'r733: self test anchor not found twice; nothing changed';
  END IF;
END $pre733$;

UPDATE pdc_ops.regression_checks
SET check_sql = regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(check_sql,
   '\mpins\.(n|pin_count)\s*=\s*241\M', 'TRUE', 'g'),
   '\(SELECT pins\.n FROM \(SELECT count\(\*\) AS n FROM pdc_ops\.expected_function_md5\) pins\)\s*=\s*241\M', 'TRUE', 'g'),
   '\(SELECT n FROM pins\)\s*=\s*241 AS pins_241', 'TRUE AS pins_241', 'g'),
   '\(SELECT count\(\*\) AS n FROM pdc_ops\.expected_function_md5 pins\)\s*=\s*\(SELECT 241\)', 'TRUE', 'g'),
   '\(SELECT pin_count\s*=\s*241\M', '(SELECT TRUE', 'g')
WHERE check_sql ~* '(\mpins\.(n|pin_count)|\(\s*select\s+(n|pin_count)\s+from\s+pins\s*\)|\s+pins\s*\)|\mpin_count)\s*(=|<>|!=)\s*\(?\s*(select\s+)?[0-9]{3,}';

-- the self test now also catches an aliased pin count compared to a three-digit literal
UPDATE pdc_ops.regression_checks
SET check_sql = replace(check_sql,
  $old$     OR c.check_sql ~* $re6$[0-9]+\s*(=|<>|!=)\s*\(\s*select\s+count\(\s*\*\s*\)\s+from\s+pdc_ops\.expected_function_md5\s*\)$re6$$old$,
  $new$     OR c.check_sql ~* $re6$[0-9]+\s*(=|<>|!=)\s*\(\s*select\s+count\(\s*\*\s*\)\s+from\s+pdc_ops\.expected_function_md5\s*\)$re6$
     OR c.check_sql ~* $re7$(\mpins\.(n|pin_count)|\(\s*select\s+(n|pin_count)\s+from\s+pins\s*\)|\s+pins\s*\)|\mpin_count)\s*(=|<>|!=)\s*\(?\s*(select\s+)?[0-9]{3,}$re7$$new$),
    description = description || ' Since r733 it also catches a pin count compared to a three-digit literal through an alias (pins.n, pin_count).'
WHERE check_name = 'regression_checks_self_test';

DO $post733$
DECLARE r record; v_red text := ''; v_n integer := 0;
BEGIN
  IF (SELECT count(*) FROM pdc_ops.regression_checks WHERE check_sql ~* '(\mpins\.(n|pin_count)|\(\s*select\s+(n|pin_count)\s+from\s+pins\s*\)|\s+pins\s*\)|\mpin_count)\s*(=|<>|!=)\s*\(?\s*(select\s+)?[0-9]{3,}') <> 0 THEN RAISE EXCEPTION 'r733: a lock survived'; END IF;
  IF (SELECT count(*) FROM regexp_matches((SELECT check_sql FROM pdc_ops.regression_checks WHERE check_name = 'regression_checks_self_test'), '\$re7\$', 'g')) <> 4 THEN RAISE EXCEPTION 'r733: self test regex not added twice'; END IF;
  -- the whole suite: nothing new may be red
  FOR r IN SELECT * FROM pdc_ops.fault_regression_check() x LOOP
    v_n := v_n + 1;
    IF NOT r.ok AND r.check_name NOT IN ('clock_ticks_recent','qc_cache_refill_busy_not_error','qc_photo_receipt_readable','pmb_bay_names_483','fabrication_bays_14_509','board_prewarm_729') THEN
      v_red := v_red || r.check_name || ' (' || left(r.detail, 120) || '); ';
    END IF;
  END LOOP;
  IF v_n < 180 THEN RAISE EXCEPTION 'r733: only % checks ran', v_n; END IF;
  IF v_red <> '' THEN RAISE EXCEPTION 'r733: red after apply, rolled back: %', v_red; END IF;
  RAISE NOTICE 'r733: % checks, no new red', v_n;
END $post733$;
