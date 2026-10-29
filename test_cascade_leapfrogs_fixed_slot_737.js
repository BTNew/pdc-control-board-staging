'use strict';
// r737 (F343): the clock cascade aborted every bay because a planned job was pushed behind another car's queued slot
// and the order test read that as a reorder. The test now ignores that pair; same-car stage order is still enforced.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const up = fs.readFileSync('supabase/migrations/20261030063000_r737_cascade_leapfrogs_fixed_slot.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261030063000_r737_cascade_leapfrogs_fixed_slot.down.sql', 'utf8');

test('the exemption is only for another car and only for a fixed slot', () => {
  assert.match(up, /AND NOT \(a\.vehicle_id<>b\.vehicle_id AND \(b\.status IN\(''started'',''stoppage'',''queued''\) OR b\.actual_start_at IS NOT NULL\)\)/);
  assert.match(up, /r737: anchor not found once/);
  assert.match(up, /r737: readback differs/);
});

test('pin and md5 checks follow; the check is added; the rollback restores the strict test', () => {
  assert.match(up, /UPDATE pdc_ops\.expected_function_md5 SET prosrc_md5 = md5\(v_new\) WHERE prosrc_md5 = v_md5;/);
  assert.match(up, /r737: md5 check not moved/);
  assert.match(up, /'cascade_leapfrogs_fixed_slot_737', 'F343'/);
  assert.match(up, /regression_checks_self_test/);
  assert.match(down, /r737 down: anchor not found once/);
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks WHERE check_name = 'cascade_leapfrogs_fixed_slot_737';/);
});
