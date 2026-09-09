'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { STATIONS, reviewLines, controlHtml, movePayload, verifyMove } = require('./pdc-review-stations');
function fixture(hours = 0) {
  const id = '00000000-0000-4000-8000-000000000101';
  const line = { sourceLineId: id, lineIdentity: `source:${id}`, sourceKind: 'authenticated',
    stageCode: 'UNALLOCATED_MAPPING_REVIEW', active: true, completed: false, lineVersion: 0,
    description: 'Snake Bite Kit', estimatedHours: hours };
  return { __emailVehicleId: '00000000-0000-4000-8000-000000000100',
    __emailVehicleVersion: 21, __emailVehicleServerAuthoritative: true,
    pdcQcOperationLinesProjectionPresent: true, pdcLocation: 'QC', pdcQcComplete: false,
    pdcQcOperationLines: [line] };
}
function result(v, stage = 'FITTING') {
  const l = v.pdcQcOperationLines[0];
  return { ok: true, data: { vehicle_id: v.__emailVehicleId, vehicle_version_after: 22,
    line_key: l.lineIdentity, stage_code: stage,
    qc_line: { line_identity: l.lineIdentity, source_line_id: l.sourceLineId, stage_code: stage,
      estimated_hours: l.estimatedHours, description: l.description, active: true, completed: false } } };
}
test('Review controls require canonical source identity and never include already completed work', () => {
  const v = fixture(); assert.equal(reviewLines(v).length, 1);
  for (const change of [{ __emailVehicleServerAuthoritative: false }, { pdcQcOperationLinesProjectionPresent: false }, { pdcQcComplete: true }, { pdcLocation: 'RFT' }, { pdcLocation: 'Collected' }]) assert.equal(reviewLines({ ...v, ...change }).length, 0);
  for (const change of [{ completed: true }, { active: false }, { sourceKind: 'manual' }, { sourceLineId: 'other' }, { stageCode: 'FITTING' }]) assert.equal(reviewLines({ ...v, pdcQcOperationLines: [{ ...v.pdcQcOperationLines[0], ...change }] }).length, 0);
});
test('All eight permitted workshop stations are available; Review and Parts are not QC bypass choices', () => {
  const v = fixture(); const html = controlHtml(v, v.pdcQcOperationLines[0]);
  assert.equal(STATIONS.length, 8);
  for (const [code] of STATIONS) assert.ok(html.includes(`value="${code}"`));
  assert.doesNotMatch(html, /value="(?:PARTS|PIT_INSPECTION|REVIEW)"/);
  assert.match(html, /Save station/); assert.match(html, /data-review-station-save disabled/);
  assert.match(html, /0 h · hours unchanged/);
});
test('Read-only roles and busy operations cannot change the station', () => {
  const v = fixture(), line = v.pdcQcOperationLines[0];
  assert.doesNotMatch(controlHtml(v, line, { writable: false }), /<select|<button/);
  assert.match(controlHtml(v, line, { busy: true, value: 'FITTING' }), /Saving…/);
  assert.match(controlHtml(v, line, { busy: true, value: 'FITTING' }), /data-review-station-save disabled/);
});
test('Source descriptions and feedback are escaped; unknown hours are not converted to zero', () => {
  const v = fixture(null), l = { ...v.pdcQcOperationLines[0], description: '<img src=x onerror=alert(1)>' };
  const html = controlHtml(v, l, { message: '<script>bad</script>' });
  assert.match(html, /Hours still need review/); assert.doesNotMatch(html, /<img|<script/);
});
test('Move uses the existing versioned RPC shape and never submits replacement hours or completion', () => {
  const v = fixture(); const p = movePayload(v, v.pdcQcOperationLines[0], 'FITTING', { vehicle_id: v.__emailVehicleId, line_adjustments: [] });
  assert.deepEqual(p, { p_vehicle_id: v.__emailVehicleId, p_adjustment_id: null, p_expected_version: 0, p_line_key: v.pdcQcOperationLines[0].lineIdentity, p_stage_code: 'FITTING' });
  assert.equal(Object.keys(p).length, 5);
});
test('Cross-vehicle details, ambiguous adjustments and later assignments fail before dispatch', () => {
  const v = fixture(), l = v.pdcQcOperationLines[0], a = { line_key: l.lineIdentity, stage_code: 'REVIEW', adjustment_id: l.sourceLineId, version: 3 };
  assert.throws(() => movePayload(v, l, 'FITTING', { vehicle_id: 'different', line_adjustments: [] }));
  assert.throws(() => movePayload(v, l, 'FITTING', { vehicle_id: v.__emailVehicleId, line_adjustments: [a, a] }));
  assert.throws(() => movePayload(v, l, 'FITTING', { vehicle_id: v.__emailVehicleId, line_adjustments: [{ ...a, stage_code: 'TINT' }] }));
  assert.equal(movePayload(v, l, 'FITTING', { vehicle_id: v.__emailVehicleId, line_adjustments: [a] }).p_expected_version, 3);
});
test('Actual response verification preserves zero and null hours and exact identities', () => {
  for (const hours of [0, null, 0.07, 1.67]) {
    const v = fixture(hours); assert.equal(verifyMove(result(v), v, v.pdcQcOperationLines[0], 'FITTING'), true);
  }
});
test('No success for wrong vehicle, wrong station, altered hours, stale version or automatic QC completion', () => {
  const v = fixture(), l = v.pdcQcOperationLines[0];
  for (const change of [{ vehicle_id: 'wrong' }, { stage_code: 'TINT' }, { vehicle_version_after: 21 }]) {
    const r = result(v); Object.assign(r.data, change); assert.equal(verifyMove(r, v, l, 'FITTING'), false);
  }
  for (const change of [{ completed: true }, { estimated_hours: 1 }, { description: 'Different item' }, { source_line_id: 'wrong' }]) {
    const r = result(v); Object.assign(r.data.qc_line, change); assert.equal(verifyMove(r, v, l, 'FITTING'), false);
  }
});
test('Module compiles and only calls the existing station action, not QC completion or RFT', () => {
  const source = fs.readFileSync('pdc-review-stations.js', 'utf8'); new vm.Script(source);
  assert.match(source, /rpc\/move_vehicle_workshop_source_line_stage/);
  assert.doesNotMatch(source, /rpc\/(?:set_pdc_qc_operation|finalize_pdc_qc|collect_rft)/);
  assert.match(source, /qcPageOperationPending\.set/); assert.match(source, /qcPageOperationPending\.delete/);
});
