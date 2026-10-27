/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r576 (F190) / sort 347. A Fitting drop that overlaps the same vehicle in another
// station asks, names that booking, and can push it. The bay's own later jobs
// still move back. Go-live is r576 / F190 / sort 347. The filename keeps r567.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { workshopPushLaterQuestion } = require('./workshop-shared-actions.js');

const root = __dirname;
const read = name => fs.readFileSync(path.join(root, name), 'utf8');
const up = read('supabase/migrations/20261027210000_r567_cross_station_drop.sql');
const down = read('supabase/rollbacks/20261027210000_r567_cross_station_drop.down.sql');
const planner = read('workshop-planner.js');
const shared = read('workshop-shared-actions.js');
const app = read('app.js');

test('r576 migration is a staging preview: pins stay 241, department 135 stays frozen, sort 347 is the free one', () => {
  for (const src of [up, down]) {
    assert.match(src, /SET LOCAL lock_timeout = '2s'/);
    assert.match(src, /NOT BETWEEN 2 AND 45/);
    assert.match(src, /cdsmnqxtyyoeoznmbidd/);
    assert.match(src, /pdc_production_environment_sentinel/);
    assert.match(src, /staging only/);
    assert.match(src, /<>241/);
    assert.match(src, /4eb5baf999b849d174880a1e261fcbf2/);
  }
  assert.match(up, /79f284b178ca2170bf8972c9cd83ce29/);
  assert.match(up, /pmb_arrival_age_563/);
  assert.match(up, /sort_order=336 AND added_in='r563'/);
  assert.match(up, /panel_line_completion_565/);
  assert.match(up, /sort_order=337 AND added_in='r565'/);
  assert.match(up, /pmb_dept_ack_book_574/);
  assert.match(up, /sort_order=345 AND added_in='r574'/);
  assert.match(up, /active_key_unique_575/);
  assert.match(up, /sort_order=346 AND added_in='r575'/);
  assert.match(up, /sort_order=347 OR fault_id='F190'/);
  assert.match(up, /'cross_station_drop_576','F190'/);
  assert.match(up, /, 347, 'r576'/);
  assert.match(up, /if not coalesce\(p_cascade,false\) then/);
  assert.match(up, /cross-station push not confirmed/);
  assert.match(up, /r576 \(F190\)/);
  assert.match(up, /SECURITY DEFINER SET search_path TO ''pg_catalog'', ''public''/);
  assert.doesNotMatch(up, /INSERT INTO pdc_ops\.expected_function_md5/);
  assert.match(up, /Production vjdtsswhroyguxyfjdkt is not a target/);
  assert.doesNotMatch(up, /project_ref='vjdtsswhroyguxyfjdkt'/);
  assert.match(down, /79f284b178ca2170bf8972c9cd83ce29/);
  assert.match(down, /release='r552'/);
  assert.match(down, /a clock version bump with the same bay window does not reject a drag \(was 1c11423631f21d520b9c2d457df8bfe1, r424\)/);
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks/);
  assert.match(down, /sort_order=347 AND added_in='r576'/);
  assert.match(down, /if not coalesce\(p_cascade,false\) then/);
});

test('the question names stock, station and bay when the server sends them, and the old Key 516 line still fits', () => {
  const named = workshopPushLaterQuestion({
    message: 'This drop would book this vehicle in two places at once. Push the other station back so an hour stays clear, and later jobs in this bay move back too.',
    bay_push_count: 1,
    pushes: [{
      key_number: '214', stock_number: '13047384', customer_name: 'MAIN ROADS', stage_name: 'Tint', bay_display_name: 'Tint Bay 01',
      from_start: '2026-10-27T03:30:00Z', to_start: '2026-10-28T06:15:00Z',
    }, {
      key_number: '214', stock_number: '13047384', customer_name: 'MAIN ROADS', stage_name: 'Hoist', bay_display_name: 'Unallocated',
      from_start: '2026-10-27T05:00:00Z', to_start: '2026-10-28T08:15:00Z',
    }],
  });
  assert.match(named, /Key 214 · stock 13047384 · MAIN ROADS · Tint · Tint Bay 01/);
  assert.match(named, /Key 214 · stock 13047384 · MAIN ROADS · Hoist · Unallocated/);
  assert.match(named, /Later jobs in this bay move back too/);
  assert.match(named, /push them back/);
  assert.match(named, /Cancel to leave everything as it is/);
  const legacy = workshopPushLaterQuestion({
    message: "This job would run into Key 516's next booking. Push 2 bookings back so nothing overlaps?",
    pushes: [{ key_number: '516', work_category: 'BUS_ELECTRICAL', bay_number: 8, from_start: '2026-11-02T03:54:00Z', to_start: '2026-11-06T05:07:00Z' }],
  });
  assert.match(legacy, /Key 516 · electrical · Bay 8/);
  assert.doesNotMatch(legacy, /Later jobs in this bay/);
});

test('the planner dialog is blue, names the station, and a started booking says it was not pushed', () => {
  const dialog = planner.slice(planner.indexOf('function workshopPushLaterDialog('), planner.indexOf('function workshopResequencePreviewHtml('));
  assert.match(dialog, /Push the other station back\?/);
  assert.match(dialog, /#1d4ed8/);
  assert.match(dialog, /workshop-push-go/);
  assert.doesNotMatch(dialog, /#f97316|#ea580c|#c2410c|orange/i);
  assert.match(planner, /That booking is already \$\{held\}, so it was not pushed back/);
  assert.match(app, /r576=2026\.10\.27\.r576/g);
  assert.equal(app.split('r576=2026.10.27.r576').length - 1, 4);
  assert.equal(planner.split('workshop-planner.js?').length - 1, 0);
  for (const file of ['karratha/workshop-planner.js', 'karratha/workshop-shared-actions.js', 'karratha/app.js']) {
    assert.equal(read(file).includes('r576'), false, file);
  }
});
