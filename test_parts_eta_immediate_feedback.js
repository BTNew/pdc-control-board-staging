'use strict';
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const app = fs.readFileSync('app.js', 'utf8');
const start = app.indexOf('async function updateVehiclePartsWorstEta');
const end = app.indexOf('\nfunction draftPartsEtaSalesEmail', start);
assert.ok(start > 0 && end > start);
let renderCount = 0;
let refreshCount = 0;
const sharedVehicle = { __emailVehicleId: 'HERMES-TEST-PARTS-ETA', __emailVehicleVersion: 4, pdcPartsWorstEta: '' };
const never = new Promise(() => {});
const context = {
  cleanNavisionText: value => String(value || '').trim(),
  selectedVehicle: () => sharedVehicle,
  partsWorstEtaValue: vehicle => vehicle.pdcPartsWorstEta || '',
  getCurrentOperatorName: () => 'Hermes Test',
  authenticatedPartsTarget: async () => ({
    service: { updatePartsEta: async () => ({ ok: true, data: { vehicle_id: sharedVehicle.__emailVehicleId } }) },
    vehicle: sharedVehicle,
    vehicleId: sharedVehicle.__emailVehicleId,
    expectedVersion: 4,
  }),
  refreshEmailVehicleLocations: () => { refreshCount += 1; return never; },
  refreshSharedVehicleWorkState: () => { refreshCount += 1; return never; },
  renderPartsHome: () => { renderCount += 1; },
  recordVehicleAudit: () => {},
  saveVehicleEdits: () => {},
  nowIsoString: () => '2026-08-25T00:00:00Z',
  partsWorstEtaLabel: () => '',
  offerSalespersonChangeEmail: () => {},
  Promise,
  window: { alert: () => { throw new Error('unexpected alert'); } },
};
vm.createContext(context);
vm.runInContext(`${app.slice(start, end)}\nupdateResult = updateVehiclePartsWorstEta('HERMES-TEST-PARTS-ETA', '2026-08-30');`, context);
(async () => {
  await context.updateResult;
  assert.strictEqual(sharedVehicle.pdcPartsWorstEta, '2026-08-30');
  assert.strictEqual(renderCount, 1, 'accepted ETA renders immediately without awaiting broad snapshots');
  assert.strictEqual(refreshCount, 2, 'both authoritative reconciliations start in parallel');
  const orderedStart = app.indexOf('async function markVehiclePartsOrdered');
  const orderedEnd = app.indexOf('\nasync function markVehiclePartsComplete', orderedStart);
  const ordered = app.slice(orderedStart, orderedEnd);
  assert.match(ordered, /Set Parts as required and save that authoritative work state/);
  assert.match(ordered, /Operator access is required to mark Parts ordered/);
  assert.match(ordered, /did not return a valid authoritative receipt/);
  assert.doesNotMatch(ordered, /Parts could not be marked ordered on the shared vehicle record\. No change was made\./);
  console.log('Immediate Parts ETA feedback and specific ordered errors: PASS');
})().catch(error => { console.error(error); process.exit(1); });
