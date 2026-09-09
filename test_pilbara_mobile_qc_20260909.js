'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { mapServerVehicle } = require('./pdc-email-vehicle-location-service.js');
const appSource = fs.readFileSync('app.js', 'utf8');

function sourceFunction(name) {
  const start = appSource.indexOf(`function ${name}(`);
  assert.ok(start >= 0, `${name} exists`);
  const next = appSource.slice(start + 1).search(/\n(?:async )?function /);
  assert.ok(next >= 0, `${name} has a following function`);
  return appSource.slice(start, start + 1 + next);
}
function fixture(withQc = true) {
  // Source shape and hours reproduce the reported Pilbara-only vehicle;
  // synthetic IDs prevent these fixtures from being operational identities.
  const hours = [0, 1.5, 0.5, 0.13, 1.5, 1.75, 0.75];
  const descriptions = ['Fuel / charge', 'Pre-Delivery', 'Front seat covers', 'Cargo mat', 'LED Lightbar', 'Nudge Bar', 'Rear seat covers'];
  const operations = hours.map((h, i) => ({
    operation_line_id: `00000000-0000-4000-8000-${String(i + 1).padStart(12, '0')}`,
    operation_no: `PD${String(i + 1).padStart(3, '0')}-ABCDEF01`,
    description: descriptions[i], work_key: i === 4 ? 'electrical' : 'fitting',
    job_card_number: 'JC14124971', estimated_hours: h,
    source_uid: `pilbara_service_open_jobcards_v1:13064619:JC14124971:${i + 1}`,
  }));
  return {
    id: '00000000-0000-4000-8000-000000000100', permanent_vehicle_id: 'QC-REGRESSION-FIXTURE',
    stock_number: '13064619', customer_name: 'QC regression fixture', vehicle_description: 'RAV4 AWD',
    version: 7, current_location: 'QC', lifecycle_state: 'active', visible_on_board: true,
    qc_completed_at: null, operation_lines: operations,
    qc_operation_lines: withQc ? operations.map(o => ({
      line_identity: `source:${o.operation_line_id}`, source_kind: 'authenticated',
      source_line_id: o.operation_line_id, source_contract: 'pilbara_service_open_jobcards_v1',
      operation_no: o.operation_no, description: o.description, job_card_number: o.job_card_number,
      estimated_hours: o.estimated_hours, stage_code: o.work_key.toUpperCase(),
      active: true, completed: false, line_version: 0,
    })) : [],
  };
}
function harness(rows, mobile = true) {
  const host = { innerHTML: '' };
  const ctx = {
    window: { matchMedia: () => ({ matches: mobile }) },
    $: selector => selector === '#qc-page-host' ? host : null, $$: () => [],
    pdcSheetVehicles: () => rows, vehiclePdcLocation: v => v.pdcLocation,
    vehicleKey: v => v.stock || v.id, displayStockNumber: v => v.stock,
    displayVehicle: v => v.vehicle, consultantName: () => '',
    vehicleCustomerName: v => v.client, vehicleKeyNumber: v => v.keyNumber,
    pmbStageLabel: value => value,
    escapeHtml: value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])),
    groupBy: (items, key) => items.reduce((groups, item) => { (groups[key(item)] ||= []).push(item); return groups; }, {}),
    qcPageOperationPending: new Map(), qcPageNotice: '', qcSelectedVehicleKey: '',
  };
  vm.createContext(ctx);
  ['vehicleInQualityControlGate', 'qcPageIsMobile', 'qcPagePendingKey', 'qcPageVehicleIsEligible',
    'qcPageVehicles', 'qcPageVehicleKey', 'qcPageOperationLineIsDeferredPit', 'qcPageOperationLines',
    'qcPageAllOperationLinesComplete', 'qcPageOperationHoursLabel', 'qcPageStageLabel',
    'qcPageWorkItemsHtml', 'qcPageVehicleCardHtml', 'renderQualityControlPage'].forEach(name => vm.runInContext(sourceFunction(name), ctx));
  return { ctx, host };
}

test('Pilbara source lines alone reproduce the previously hidden QC vehicle', () => {
  const mapped = mapServerVehicle(fixture(false));
  assert.equal(mapped.pdcEmailOperationLines.length, 7);
  const { ctx } = harness([mapped]);
  assert.equal(ctx.qcPageVehicles().length, 0);
});
test('canonical Pilbara QC projection makes the vehicle eligible on mobile and desktop', () => {
  const mapped = mapServerVehicle(fixture());
  for (const mobile of [true, false]) {
    const { ctx } = harness([mapped], mobile);
    assert.equal(ctx.qcPageVehicles().length, 1);
    assert.equal(ctx.qcPageVehicles()[0].stock, '13064619');
    assert.equal(ctx.qcPageOperationLines(mapped).length, 7);
    assert.equal(mapped.jobCardNumber, 'JC14124971');
    assert.equal(ctx.qcPageAllOperationLinesComplete(mapped), false);
  }
});
test('actual mobile list and checklist render the stock and seven unchecked source operations', () => {
  const mapped = mapServerVehicle(fixture());
  const { ctx, host } = harness([mapped]);
  ctx.renderQualityControlPage();
  assert.match(host.innerHTML, /is-mobile-list/);
  assert.match(host.innerHTML, /13064619/);
  assert.match(host.innerHTML, /1 awaiting QC sign-off/);
  const checklist = ctx.qcPageWorkItemsHtml(mapped);
  assert.equal((checklist.match(/type="checkbox"/g) || []).length, 7);
  assert.equal((checklist.match(/ checked/g) || []).length, 0);
  assert.match(checklist, /JC JC14124971/);
  assert.equal(mapped.pdcQcOperationLines[0].estimatedHours, 0);
  assert.equal(mapped.pdcQcComplete, false);
});
test('unknown hours and mapping remain blocked; non-QC and signed-off vehicles stay excluded', () => {
  const raw = fixture();
  raw.qc_operation_lines[0].estimated_hours = null;
  raw.qc_operation_lines[1].stage_code = 'UNALLOCATED_MAPPING_REVIEW';
  const mapped = mapServerVehicle(raw);
  const { ctx } = harness([mapped]);
  assert.equal(ctx.qcPageVehicles().length, 1);
  const checklist = ctx.qcPageWorkItemsHtml(mapped);
  assert.match(checklist, /Unknown operation hours require review/);
  assert.match(checklist, /Station mapping review is required/);
  assert.equal(ctx.qcPageAllOperationLinesComplete(mapped), false);
  assert.equal(ctx.qcPageVehicleIsEligible({ ...mapped, pdcLocation: 'RFT' }), false);
  assert.equal(ctx.qcPageVehicleIsEligible({ ...mapped, pdcQcComplete: true }), false);
});
