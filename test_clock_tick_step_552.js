/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const up = fs.readFileSync('supabase/migrations/20261027010000_r552_clock_tick_step.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261027010000_r552_clock_tick_step.down.sql', 'utf8');
const tick = up.split('$tick552$')[1];
const sched = up.split('$sched552$')[1];

test('r552 steps a running end by 15 minutes and keeps a cosmetic clock bump from rejecting a drag', () => {
  assert.match(tick, /workshop_clock_step_552/);
  assert.doesNotMatch(tick, /greatest\(item\.original_end,item\.effective_end,floor_at\)/);
  assert.match(up, /workshop_clock_window_same_552/);
  assert.match(up, /v_move_version:=v_booking\.version/);
  assert.match(up, /true,327,'r552'/);
  assert.match(up, /schedule_stale_version_window_552/);
  assert.match(up, /'F166'/);
  assert.match(up, /fa17068b106bbb9488c257e61d32e483/);
  assert.match(up, /0aaaa15690ca286ed0db87fc72271d5a/);
  assert.match(up, /1c11423631f21d520b9c2d457df8bfe1/);
  assert.match(up, /pin count is not 241/);
  assert.match(up, /pin count changed/);
  assert.match(up, /cdsmnqxtyyoeoznmbidd/);
  assert.doesNotMatch(up, /INSERT INTO pdc_ops\.expected_function_md5/);
  assert.doesNotMatch(up, /karratha135/);
  assert.doesNotMatch(sched, /::regprocedure/);
  assert.match(up, /PERFORM set_config\('search_path','pg_catalog',true\)/);
  assert.match(down, /0aaaa15690ca286ed0db87fc72271d5a/);
  assert.match(down, /1c11423631f21d520b9c2d457df8bfe1/);
  assert.match(down, /DROP FUNCTION public\.workshop_clock_step_552/);
  assert.match(down, /DROP FUNCTION public\.workshop_clock_window_same_552/);
  assert.match(down, /F38: stopped jobs re-plannable, push-back warn-and-confirm, bay re-order\/swap with undo/);
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks WHERE check_name='schedule_stale_version_window_552'/);
  assert.equal(fs.readFileSync('karratha/pdc-planner-capacity.js', 'utf8').includes('r552'), false);
});
