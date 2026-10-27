/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. */
'use strict';
// r579 (F192): the two known bay checks key on id, code and is_active.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const up = fs.readFileSync('supabase/migrations/20261028020000_r579_bay_code_checks.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261028020000_r579_bay_code_checks.down.sql', 'utf8');

test('r579: retargets the two bay checks and adds bay_code_identity_579', () => {
  assert.match(up, /sort 350/);
  assert.match(up, /fault_id='F192'/);
  assert.match(up, /added_in='r579'|true, 350, 'r579'/);
  assert.match(up, /bay_code_identity_579/);
  assert.match(up, /b\.is_active = \(m\.stage_code <> 'ELECTRICAL' OR m\.bay_number <= 7\)/);
  assert.match(up, /2dfbb177-f353-4f4f-9668-6519909d418a/);
  assert.match(up, /ff080124-3632-4a07-944c-e0fb0f45fa1b/);
  assert.match(up, /8b93e7f79791e0af4d3ba60de836275b/);
  assert.match(up, /9f468149645af4563fa18efeed061efc/);
  assert.match(up, /pin count is not 241/);
  assert.match(up, /cdsmnqxtyyoeoznmbidd/);
  assert.doesNotMatch(up, /CREATE OR REPLACE FUNCTION/);
  const stored = up.slice(up.indexOf('$c$'), up.lastIndexOf('$c$'));
  assert.doesNotMatch(stored, /expected_function_md5/);
});

test('r579: down restores the previous check bodies and removes only F192', () => {
  assert.match(down, /8b93e7f79791e0af4d3ba60de836275b/);
  assert.match(down, /9f468149645af4563fa18efeed061efc/);
  assert.match(down, /display_name=m\.new_name/);
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks WHERE check_name='bay_code_identity_579'/);
  assert.match(down, /pin count stays 241|pin count changed/);
  assert.doesNotMatch(down, /DELETE FROM public\.workshop_bays/);
  assert.doesNotMatch(down, /CREATE OR REPLACE FUNCTION/);
});
