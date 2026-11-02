'use strict';
// r820 (F458): the slide-out hours editor sends the saved adjustment id/version and shows saved hours.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { mergeLineAdjustments } = require('./pdc-vehicle-slideout.js');
const src = fs.readFileSync('pdc-vehicle-slideout.js', 'utf8');

test('a line with a saved adjustment carries its id, version and saved hours (13109751)', () => {
  const map = new Map([
    ['a9a046b4-7bfd-4fba-bdf7-294582305f4a', { lineKey:'source:a9a046b4-7bfd-4fba-bdf7-294582305f4a', hours:1, stage:'FITTING', adjustmentId:'', adjustmentVersion:0 }],
    ['5de5d3d4-926f-4e88-8cf2-c43d97a661d0', { lineKey:'source:5de5d3d4-926f-4e88-8cf2-c43d97a661d0', hours:1, stage:'FITTING', adjustmentId:'', adjustmentVersion:0 }],
    ['11111111-1111-4111-8111-111111111111', { lineKey:'source:11111111-1111-4111-8111-111111111111', hours:2, stage:'TINT', adjustmentId:'', adjustmentVersion:0 }],
  ]);
  mergeLineAdjustments(map, [
    { line_key:'source:a9a046b4-7bfd-4fba-bdf7-294582305f4a', stage_code:'FABRICATION', adjustment_id:'a414c8a1-085c-464d-bfb5-e635af665486', version:1, estimated_hours:1, source_kind:'source' },
    { line_key:'source:5de5d3d4-926f-4e88-8cf2-c43d97a661d0', stage_code:'FITTING', adjustment_id:'a8bcd81f-a6f3-471e-b7b3-b6c4cd5886a2', version:2, estimated_hours:'4.00', source_kind:'source' },
    { line_key:'manual:22222222-2222-4222-8222-222222222222', adjustment_id:'x', version:1, estimated_hours:3, source_kind:'manual' },
  ]);
  const wheel = map.get('a9a046b4-7bfd-4fba-bdf7-294582305f4a');
  assert.equal(wheel.adjustmentId, 'a414c8a1-085c-464d-bfb5-e635af665486');
  assert.equal(wheel.adjustmentVersion, 1);
  assert.equal(wheel.stage, 'FITTING', 'the line keeps its own station');
  const bullbar = map.get('5de5d3d4-926f-4e88-8cf2-c43d97a661d0');
  assert.equal(bullbar.hours, 4, 'saved hours shown, not job card hours');
  assert.equal(bullbar.adjustmentVersion, 2);
  const tint = map.get('11111111-1111-4111-8111-111111111111');
  assert.equal(tint.adjustmentId, '', 'a line with no adjustment is unchanged');
  assert.equal(tint.hours, 2);
});

test('lineRecords merges detail.line_adjustments', () => {
  assert.match(src, /mergeLineAdjustments\(map, detail\?\.line_adjustments\); \/\/ r820 \(F458\)/);
});
