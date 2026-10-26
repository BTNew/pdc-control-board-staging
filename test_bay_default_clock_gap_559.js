/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const up = fs.readFileSync('supabase/migrations/20261027090000_r559_bay_default_clock_gap.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261027090000_r559_bay_default_clock_gap.down.sql', 'utf8');

test('r559 keeps a gap and does not refuse a bay when only the bay default is busy', () => {
  assert.match(up, /r559 \(F173\)/);
  assert.match(up, /predecessor\.final_end > item\.original_start OR/);
  assert.match(up, /v_bay_default_only/);
  assert.match(up, /fa17068b106bbb9488c257e61d32e483/);
  assert.match(up, /e72b96d1c9b3bf105ae975075f9b4434/);
  assert.match(up, /sort_order=334 OR fault_id='F173'/);
  assert.match(up, /bay_default_clock_gap_559/);
  assert.match(up, /pin count is not 241/);
  assert.match(up, /pin count changed/);
  assert.match(up, /cdsmnqxtyyoeoznmbidd/);
  assert.match(up, /1d85ee5c-d1a7-4d63-8be9-c6b8b9bcbec7/);
  assert.match(up, /26030b23-7d53-402c-9cdc-46abe5e89832/);
  assert.match(up, /12710966/);
  assert.doesNotMatch(up, /INSERT INTO pdc_ops\.expected_function_md5/);
  assert.doesNotMatch(up, /karratha135/);
  assert.doesNotMatch(up, /UPDATE public\.workshop_bookings/);
  assert.doesNotMatch(up, /DELETE FROM public\.workshop_bookings/);
  assert.match(down, /fa17068b106bbb9488c257e61d32e483/);
  assert.match(down, /e72b96d1c9b3bf105ae975075f9b4434/);
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks WHERE check_name='bay_default_clock_gap_559'/);
  assert.match(down, /release='r552'/);
  assert.doesNotMatch(down, /karratha135/);
  assert.equal(fs.readFileSync('karratha/pdc-planner-capacity.js', 'utf8').includes('r559'), false);
});
