'use strict';
// r739 (F345): a fitter resume recomputed one car's QC lines hundreds of times in one transaction (over 2 minutes,
// API limit 30 s). The reader now memoises a cache miss for the transaction in a transaction-local setting.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const up = fs.readFileSync('supabase/migrations/20261030074000_r739_qc_lines_memo_for_every_caller.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261030074000_r739_qc_lines_memo_for_every_caller.down.sql', 'utf8');

test('the memo is stamped with both generations and its setting name is a valid identifier', () => {
  // a custom setting name must be identifiers separated by dots; a uuid hex can start with a digit, so it is prefixed
  assert.match(up, /key := 'pdc\.qcl\.v' \|\| replace\(p_vehicle_id::text, '-', ''\);/);
  assert.match(up, /IF memo IS NOT NULL AND \(memo->>'v'\)::bigint = vgen AND \(memo->>'g'\)::bigint = ggen THEN RETURN memo->'l'; END IF;/);
  assert.match(up, /PERFORM set_config\(key, jsonb_build_object\('v', vgen, 'g', ggen, 'l', v\)::text, true\);/);
  assert.match(up, /STABLE SECURITY DEFINER/);
  // the r732 lookup text stays exactly as the r732 check expects it
  assert.match(up, /AND m\.vgen = coalesce\(\(SELECT e\.gen FROM pdc_work_categories_private\.qc_operation_lines_cache_epoch e WHERE e\.vehicle_id = p_vehicle_id\), 0\)/);
});

test('pin and the three md5 checks follow; the rollback restores the r735 body', () => {
  assert.match(up, /IS DISTINCT FROM 'b67e9ee98000a647d14c6cbf0506ee48'/);
  assert.match(up, /IF v_n <> 3 THEN RAISE EXCEPTION 'r739: expected 3 checks to follow the reader md5/);
  assert.match(up, /'qc_lines_memo_every_caller_739', 'F345'/);
  assert.match(down, /IF v_new <> 'b67e9ee98000a647d14c6cbf0506ee48' THEN RAISE EXCEPTION 'r739 down: restored body is not the r735 body'/);
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks WHERE check_name = 'qc_lines_memo_every_caller_739';/);
});
