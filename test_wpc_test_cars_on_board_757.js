'use strict';
// r757 (F363, Craig 30 Oct 12:52): the ten WPC test cars without job cards are listed by the Vehicle Locations board.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
test('r757: one anchored filter line keyed on source_payload.wpc_test_20261030, check 469, rollback present', () => {
  const up = fs.readFileSync('supabase/migrations/20261030125500_r757_wpc_test_cars_on_board.sql', 'utf8');
  assert.match(up, /OR coalesce\(\(v\.source_payload->>''wpc_test_20261030''\)::boolean,false\)\\n';/);
  assert.match(up, /IF v_md5 <> 'd3b6f69bdf3420336403816fc7c60255' THEN RAISE EXCEPTION/);
  assert.match(up, /'wpc_test_cars_on_board_757', 'F363',/);
  assert.match(up, /IF v_n <> 10 THEN RAISE EXCEPTION 'r757: tagged % cars, expected 10'/);
  assert.doesNotMatch(up, /qc_completed_at IS NOT NULL/, 'no general rule: only the tagged test cars');
  const down = fs.readFileSync('supabase/rollbacks/20261030125500_r757_wpc_test_cars_on_board.down.sql', 'utf8');
  assert.match(down, /wpc_test_20261030/);
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks WHERE check_name = 'wpc_test_cars_on_board_757'/);
});
