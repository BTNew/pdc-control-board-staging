const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const planner = fs.readFileSync('workshop-planner.js', 'utf8');
const actions = fs.readFileSync('workshop-shared-actions.js', 'utf8');
const up = fs.readFileSync('supabase/migrations/20261028090000_r597_key460_drag.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261028090000_r597_key460_drag.down.sql', 'utf8');
const karratha = fs.readFileSync('karratha/workshop-planner.js', 'utf8');

test('a station drag uses the unticked hours and does not ask before cascading', () => {
  assert.match(planner, /hours still to do/);
  assert.match(planner, /cascade_notice/);
  assert.match(planner, /workshopNotify\(result\.cascade_notice, 'info'\)/);
  assert.match(actions, /workshopCascadeNotice/);
  assert.equal(actions.includes('confirmFn(workshopPlaceAfterQuestion'), false);
  assert.equal(actions.includes('confirmFn(workshopPushLaterQuestion'), false);
  assert.match(up, /estimated_operation_hours/);
  assert.match(up, /b\.bay_id is not null/);
  assert.match(up, /sort 367/);
  assert.match(up, /F211/);
  assert.match(up, /6a02115d30578e8eb3807a283b1d60ea/);
  assert.equal(up.includes('INSERT INTO pdc_ops.expected_function_md5'), false);
  const check = up.slice(up.indexOf('$chk$'));
  assert.equal(/expected_function_md5\s*\)\s*=\s*241/.test(check), false);
  assert.match(down, /key460_drag_597/);
  assert.equal(karratha.includes('cascade_notice'), false);
});
