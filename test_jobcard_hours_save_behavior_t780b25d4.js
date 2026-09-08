'use strict';
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const source = fs.readFileSync('app.js', 'utf8');
const start = source.indexOf('function vehicleWorkshopHoursBatchDraftValue');
const end = source.indexOf('\nfunction resetVehicleWorkshopLineHoursBatch', start);
assert.ok(start >= 0 && end > start);

const vehicleId = '11111111-1111-4111-8111-111111111111';
const input = (operationLineId, value, stage = 'FITTING', workKey = 'fitting') => ({
  value,
  dataset: {
    operationLineId,
    adjustmentId: '',
    adjustmentVersion: '0',
    lineKey: `source:${operationLineId}`,
    stage,
    workKey,
    originalHours: '0',
  },
});
const inputs = [
  input('22222222-2222-4222-8222-222222222222', '1'),
  input('33333333-3333-4333-8333-333333333333', '1.5'),
  input('44444444-4444-4444-8444-444444444444', '0.75'),
];
const reset = { disabled: false, setAttribute() { this.disabled = true; }, isConnected: true };
const page = {
  querySelectorAll(selector) { return selector === '[data-vehicle-workshop-hours-batch-input]' ? inputs : []; },
  querySelector(selector) { return selector === '[data-vehicle-workshop-hours-batch-reset]' ? reset : null; },
};
const button = { disabled: false, isConnected: true, closest: () => page };
let calls = 0;
let reloads = 0;
let release;
const serviceResult = new Promise(resolve => { release = resolve; });
const app = {
  vehicleWorkshopHoursBatchDrafts: new Map(),
  vehicleWorkshopHoursBatchSaving: false,
  vehicleWorkshopHoursBatchMessage: '',
  vehicleWorkshopDetailCache: new Map([[vehicleId, { detail: { vehicle_version: 7 } }]]),
  emailVehicleLocationService: {
    saveVehicleWorkshopLineHoursBatch: async request => {
      calls += 1;
      assert.deepStrictEqual(JSON.parse(JSON.stringify(request.rows.map(row => row.estimatedHours))), [1, 1.5, 0.75]);
      return serviceResult;
    },
  },
};
const context = {
  app,
  selectedVehicle: () => ({ stock: 'STOCK-FIXTURE', jobcard: 'JC-FIXTURE' }),
  vehicleWorkshopDetailCanonicalId: () => vehicleId,
  displayStockNumber: () => 'STOCK-FIXTURE',
  vehicleJobcardNumber: () => 'JC-FIXTURE',
  loadVehicleWorkshopDetail: async () => { reloads += 1; return null; },
  renderDetail: () => {},
  window: { alert: message => { throw new Error(`unexpected alert: ${message}`); } },
  crypto: { randomUUID: () => '55555555-5555-4555-8555-555555555555' },
  console,
};
vm.createContext(context);
vm.runInContext(source.slice(start, end), context);

(async () => {
  const first = context.saveVehicleWorkshopLineHoursBatch(button);
  const duplicate = await context.saveVehicleWorkshopLineHoursBatch(button);
  assert.strictEqual(duplicate, false, 'double click is deduplicated while save is in flight');
  assert.strictEqual(calls, 1, 'one in-flight save makes exactly one RPC call');
  release({ ok: false, code: 'line_version_conflict', data: null });
  assert.strictEqual(await first, false, 'server rejection is surfaced as a failed save');
  assert.strictEqual(reloads, 1, 'server rejection reloads authoritative state exactly once');
  assert.deepStrictEqual(
    JSON.parse(JSON.stringify([...app.vehicleWorkshopHoursBatchDrafts.get(vehicleId).entries()])),
    inputs.map(item => [item.dataset.operationLineId, item.value]),
    'all editor draft values survive a server rejection',
  );
  assert.match(app.vehicleWorkshopHoursBatchMessage, /draft is kept/i, 'conflict message states that the draft is kept');
  assert.strictEqual(reset.disabled, false, 'reset control is restored after rejection');
  console.log('Job Card save dedupe and draft-preservation behavior passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
