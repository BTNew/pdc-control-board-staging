'use strict';
// r732 (F342): a cross-bay cascade onto a packed bay took 84 s (API limit 30 s). A transaction memo of QC lines,
// stamped with the cache epoch generations, brings p_apply to 7 s. r733 and r734 clear the pin-total locks that
// would have gone red when r732 added a pin.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const up = fs.readFileSync('supabase/migrations/20261029230000_r732_qc_lines_transaction_memo.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261029230000_r732_qc_lines_transaction_memo.down.sql', 'utf8');
const r733 = fs.readFileSync('supabase/migrations/20261029224500_r733_pin_total_locks_part_two.sql', 'utf8');
const r734 = fs.readFileSync('supabase/migrations/20261029231500_r734_upload_gate_pin_total.sql', 'utf8');

test('the memo is transaction scoped, owner checked, and valid only while both epoch generations match', () => {
  assert.match(up, /CREATE TEMP TABLE IF NOT EXISTS pdc_qc_lines_memo_732\(vehicle_id uuid PRIMARY KEY, vgen bigint NOT NULL, ggen bigint NOT NULL, lines jsonb NOT NULL\) ON COMMIT DROP;/);
  assert.match(up, /c\.relowner = \(SELECT proowner FROM pg_proc WHERE oid = 'pdc_work_categories_private\.qc_lines_memo_fill_732\(uuid\)'::regprocedure\)/);
  assert.match(up, /AND m\.vgen = coalesce\(\(SELECT e\.gen FROM pdc_work_categories_private\.qc_operation_lines_cache_epoch e WHERE e\.vehicle_id = p_vehicle_id\), 0\)/);
  assert.match(up, /AND m\.ggen = coalesce\(\(SELECT e\.gen FROM pdc_work_categories_private\.qc_operation_lines_cache_epoch e WHERE e\.vehicle_id = '00000000-0000-0000-0000-000000000000'::uuid\), 0\)/);
  // memo, then the persistent cache, then compute
  assert.ok(up.indexOf('pg_temp.pdc_qc_lines_memo_732 m') < up.indexOf('FROM pdc_work_categories_private.qc_operation_lines_cache c WHERE c.vehicle_id = p_vehicle_id'));
  assert.match(up, /RETURN public\.pdc_qc_operation_lines_379_uncached\(p_vehicle_id\);/);
});

test('only the cascade writes the memo: private fill function, called before the scans and after each placement', () => {
  assert.match(up, /REVOKE ALL ON FUNCTION pdc_work_categories_private\.qc_lines_memo_fill_732\(uuid\) FROM PUBLIC, anon, authenticated;/);
  assert.match(up, /c_fill text := \$a\$ PERFORM pdc_work_categories_private\.qc_lines_memo_fill_732\(r\.vehicle_id\);\$a\$;/);
  assert.match(up, /v_new := replace\(v_src, c_place1, c_place1 \|\| c_fill\);/);
  assert.match(up, /v_new := replace\(v_new, c_place2, c_place2 \|\| c_fill\);/);
  assert.match(up, /qc_lines_memo_fill_732\(z\.vehicle_id\) FROM \(SELECT DISTINCT vehicle_id FROM pg_temp\.r424_p WHERE changed\) z;/);
  assert.match(up, /r732: anchor place 1/);
  assert.match(up, /r732: p_apply readback differs/);
});

test('pins and the three frozen reader md5s follow; the rollback restores both bodies by md5', () => {
  assert.match(up, /IS DISTINCT FROM 'b7f90bff12643229ff80f8ca552663a2' THEN RAISE EXCEPTION 'r732: reader body is not the baseline body'/);
  assert.match(up, /IS DISTINCT FROM 'd6eb557f2d80ed074658a9b525b8578a' THEN RAISE EXCEPTION 'r732: p_apply body is not the r424 body'/);
  assert.match(up, /WHERE check_name IN \('station_icon_completion_578','board_qc_nesting_587','qc_signoff_override_590'\);/);
  assert.match(up, /expected_function_md5\) <> 242 THEN RAISE EXCEPTION 'r732: pin count is not 242'/);
  assert.match(up, /'qc_lines_memo_732', 454, 'F342', 'r732'/);
  assert.match(down, /IF md5\(v_new\) <> 'd6eb557f2d80ed074658a9b525b8578a' THEN RAISE EXCEPTION 'r732 down: p_apply is not the r424 body/);
  assert.match(down, /<> 'b7f90bff12643229ff80f8ca552663a2' THEN RAISE EXCEPTION 'r732 down: reader is not the baseline body'/);
  assert.match(down, /DROP FUNCTION IF EXISTS pdc_work_categories_private\.qc_lines_memo_fill_732\(uuid\);/);
});

test('r733 strips every aliased pin-total lock, teaches the self test the alias forms, and runs the whole suite after', () => {
  assert.match(r733, /<> 24 THEN/);
  assert.match(r733, /\$re7\$\(\\mpins\\\.\(n\|pin_count\)\|/);
  assert.match(r733, /r733: a lock survived/);
  assert.match(r733, /FOR r IN SELECT \* FROM pdc_ops\.fault_regression_check\(\) x LOOP/);
  assert.match(r733, /IF v_n < 180 THEN RAISE EXCEPTION 'r733: only % checks ran'/);
});

test('r734 takes the pin-total lock out of the r591 upload gate without touching what it reports', () => {
  assert.match(r734, /\(SELECT count\(\*\) FROM pdc_ops\.expected_function_md5\) = 241\n      AND \(SELECT md5\(p\.prosrc\)\$o\$;/);
  assert.match(r734, /r734: anchor not found once; nothing changed/);
  assert.match(r734, /->>'pins_ok'\) IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'r734: pins_ok still false'/);
  assert.match(r734, /since r728 the website applies Service as a Whole through its own RPCs, not this gate/);
});
