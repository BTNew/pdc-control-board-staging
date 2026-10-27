/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. */
'use strict';
// r566 (F180): hide Electrical PMB Bays 20, 21 and 22 (Elec station bays 08-10). Bays 17-19 stay visible.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const layout = require('./pdc-workshop-departments.js');
const overview = require('./control-board-overview.js');
const fixture = require('./qa/control-board-fixtures.js');
const read = file => fs.readFileSync(path.join(__dirname, file), 'utf8');

const HIDDEN = [
  ['ELECTRICAL', 8, 'Electrical · Bay 20'],
  ['ELECTRICAL', 9, 'Electrical · Bay 21'],
  ['ELECTRICAL', 10, 'Electrical · Bay 22'],
];
const VISIBLE = [
  ['ELECTRICAL', 5, 'Electrical · Bay 17'],
  ['ELECTRICAL', 6, 'Electrical · Bay 18'],
  ['ELECTRICAL', 7, 'Electrical · Bay 19'],
];

test('r566: planner counts and labels keep PMB 17-19 and still name 20-22 for history', () => {
  assert.equal(layout.PMB_BAYS_VERSION, 'r566');
  assert.equal(layout.PMB_BAY_COUNTS.ELECTRICAL, 7);
  for (const [stage, bay, label] of VISIBLE) {
    assert.equal(layout.pmbBayLabel(stage, bay), label);
    assert.equal(layout.bayLabel(stage, bay), label);
  }
  for (const [stage, bay, label] of HIDDEN) {
    assert.equal(layout.pmbBayLabel(stage, bay), label, 'label map kept for inactive bays');
  }
  const app = read('app.js');
  for (const name of ['PMB_WIP_LIMITS', 'PMB_STAGE_BAY_COUNTS']) {
    const block = app.match(new RegExp(`const ${name} = \\{([\\s\\S]*?)\\n\\};`))[1];
    assert.match(block, /ELECTRICAL: 7,/);
    assert.doesNotMatch(block, /ELECTRICAL: 10,/);
  }
});

test('r566: control board retires inactive empty Elec bays above the active count', () => {
  const snapshot = fixture.emptySnapshot();
  const elec = snapshot.board.bays.filter(bay => bay.stage_code === 'ELECTRICAL');
  const hidden = elec.filter(bay => bay.bay_number >= 8);
  assert.ok(hidden.length >= 3);
  hidden.forEach(bay => { bay.is_active = false; });
  const model = overview.buildModel(snapshot);
  const html = overview.render(model);
  for (const bay of hidden) assert.doesNotMatch(html, new RegExp(`data-control-board-bay="${bay.bay_id}"`));
  const bay19 = elec.find(bay => bay.bay_number === 7);
  if (bay19) assert.match(html, new RegExp(`data-control-board-bay="${bay19.bay_id}"`));
});

test('r566: migration pins three Elec bay ids and adds electrical_bays_7_566', () => {
  const sql = read('supabase/migrations/20261027160000_r566_hide_electrical_bays_20_22.sql');
  assert.match(sql, /88bfd1d0-5e69-473b-88e3-572135184022/);
  assert.match(sql, /5af51266-df78-4cb0-88e9-bc65af3bf656/);
  assert.match(sql, /3dd68646-b4a7-4c32-98fa-39e068b0b1e9/);
  assert.match(sql, /electrical_bays_7_566/);
  assert.match(sql, /sort_order=348/);
  assert.match(sql, /pin count is not 241/);
  assert.match(sql, /panel_line_completion_565/);
  assert.match(sql, /fault_id='F180'/);
  assert.match(sql, /sort_order=348/);
  assert.match(sql, /NOT b\.is_active OR b\.display_name=m\.new_name/);
  assert.doesNotMatch(sql, /sort_order=338/);
  assert.doesNotMatch(sql, /fault_regression_check\(/);
  assert.doesNotMatch(sql, /CREATE OR REPLACE FUNCTION/);
});

test('r566: cache-bust tag loads the electrical bay count', () => {
  assert.match(read('index.html'), /pdc-workshop-departments\.js\?[^"]*r566=2026\.10\.27\.r566/);
  assert.match(read('index.html'), /app\.js\?[^"]*r566=2026\.10\.27\.r566/);
  assert.match(read('index.html'), /app\.js\?[^"]*r563=2026\.10\.27\.r563/);
});
