'use strict';

const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const source = fs.readFileSync('app.js', 'utf8');
const start = source.indexOf('    if (authoritativeLocationChanged) {');
const end = source.indexOf('\n    if (serverAuthoritative && (pdcBlocked', start);
assert.ok(start >= 0 && end > start, 'authoritative location-save branch is extractable');
const locationSaveBranch = source.slice(start, end);

const calls = {
  lifecycle: [],
  requestKeys: [],
  renderAll: 0,
  renderDetail: 0,
};
const projection = { boardLocation: '', detailLocation: '' };
const authoritativeVehicle = {
  __emailVehicleId: '11111111-1111-4111-8111-111111111111',
  __emailVehicleServerAuthoritative: true,
  pdcLocation: 'PMB',
  version: 18,
};
const saveButton = {
  disabled: false,
  attributes: new Map(),
  setAttribute(name, value) { this.attributes.set(name, value); },
  removeAttribute(name) { this.attributes.delete(name); },
};
const saveMessage = { textContent: '' };
const context = {
  authoritativeLocationChanged: true,
  salespersonChanged: false,
  detailChanges: {},
  workStateChangedByUser: false,
  pdcBlocked: false,
  previouslyPdcBlocked: false,
  pdcBlockReasonValue: '',
  v: { pdcBlockReason: '' },
  form: { dataset: { pdcBlockedBaseline: 'false' } },
  previousPdcLocation: 'YH',
  pdcLocation: 'PMB',
  authoritativeSaveVehicle: { version: 17 },
  saveButton,
  saveMessage,
  window: {
    alert() { assert.fail('valid authoritative location save must not alert'); },
    __vehicleLifecycleActions: {
      async setPdcLocation(payload) {
        calls.lifecycle.push(payload);
        return { ok: true };
      },
    },
  },
  cleanNavisionText: value => String(value || '').trim(),
  pdcLocationManualTransitionAllowed: () => true,
  vehicleLifecycleSharedRef: async () => ({
    outcome: 'resolved',
    vehicleId: authoritativeVehicle.__emailVehicleId,
    version: 17,
  }),
  pdcLocationRequestKey(vehicleId, expectedVersion, location) {
    calls.requestKeys.push({ vehicleId, expectedVersion, location });
    return 'pdc-location:11111111:17:PMB';
  },
  refreshVehicleLifecycleLocationsAndRender: async () => {},
  vehicleLifecycleActionErrorMessage: () => 'unexpected error',
  refreshVehicleModalExactIdentity: async () => ({ ok: true, vehicle: authoritativeVehicle }),
  renderAll() {
    calls.renderAll += 1;
    projection.boardLocation = context.authoritativeSaveVehicle.pdcLocation;
  },
  renderDetail() {
    calls.renderDetail += 1;
    projection.detailLocation = context.authoritativeSaveVehicle.pdcLocation;
  },
};

vm.createContext(context);
vm.runInContext(`async function runLocationSave() {\n${locationSaveBranch}\n}\nthis.runLocationSave = runLocationSave;`, context);

(async () => {
  await context.runLocationSave();

  assert.deepStrictEqual(JSON.parse(JSON.stringify(calls.lifecycle)), [{
    vehicleId: authoritativeVehicle.__emailVehicleId,
    expectedVersion: 17,
    location: 'PMB',
    requestKey: 'pdc-location:11111111:17:PMB',
  }], 'successful save keeps the four-argument request-key lifecycle contract');
  assert.deepStrictEqual(calls.requestKeys, [{
    vehicleId: authoritativeVehicle.__emailVehicleId,
    expectedVersion: 17,
    location: 'PMB',
  }], 'request key is derived from the exact logical mutation');
  assert.strictEqual(context.authoritativeSaveVehicle, authoritativeVehicle, 'authoritative read-back becomes the active save vehicle');
  assert.strictEqual(calls.renderAll, 1, 'Board rerenders once from authoritative state');
  assert.strictEqual(calls.renderDetail, 1, 'Vehicle Detail rerenders once from authoritative state');
  assert.deepStrictEqual(projection, { boardLocation: 'PMB', detailLocation: 'PMB' }, 'Board and Vehicle Detail reconcile to the authoritative location');
  assert.strictEqual(saveMessage.textContent, 'PDC Location saved');
  assert.strictEqual(saveButton.disabled, true, 'the replaced Vehicle Detail owns the post-save control state');
  assert.strictEqual(saveButton.attributes.get('aria-busy'), 'true');
  console.log('PDC-14 location detail reconciliation regression: PASS');
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
