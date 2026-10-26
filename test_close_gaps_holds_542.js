/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const up = fs.readFileSync('supabase/migrations/20261026160000_r542_close_gaps_holds.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261026160000_r542_close_gaps_holds.down.sql', 'utf8');

test('r542 stores the hold sentence in v_hold and calls the real plan', () => {
  const body = up.split('$plan542$')[1];
  assert.match(body, /v_hold text/);
  assert.match(body, /hold_reason=v_hold/);
  assert.doesNotMatch(body, /hold_reason=hold_reason/);
  assert.doesNotMatch(body, /hold_reason:=/);
  assert.match(up, /close_gaps_holds_populated/);
  assert.match(up, /true, 320, 'r542'/);
  assert.match(up, /workshop_capacity_plan\(\s*'FITTING'::pg_catalog\.text/);
  assert.doesNotMatch(up.split('$chk542$')[1], /regprocedure/);
  assert.match(up, /pin count is not 241/);
  assert.match(up, /pin count changed/);
  assert.doesNotMatch(up, /INSERT INTO pdc_ops\.expected_function_md5/);
  assert.doesNotMatch(up, /karratha135/);
  assert.match(down, /5b3c6de9fe2ea38fc967c17a8a63437c/);
  assert.match(down, /bc237d9f466c45a086c251ec8c3071a7/);
  assert.match(down, /close_gaps_holds_populated/);
  assert.equal(fs.readFileSync('karratha/pdc-planner-capacity.js', 'utf8').includes('r542'), false);
});
