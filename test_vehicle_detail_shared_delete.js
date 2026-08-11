'use strict';
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const app = fs.readFileSync('app.js', 'utf8');
const actions = fs.readFileSync('vehicle-lifecycle-actions.js', 'utf8');
const source = app.slice(
  app.indexOf('function vehicleRequiresCanonicalSharedDelete('),
  app.indexOf('function renderDetail('),
);
assert(source.includes('vehicleRequiresCanonicalSharedDelete(vehicle)'), 'all shared/Navision projections use the canonical-delete predicate');
assert(source.includes("window.prompt('Reason for deleting this vehicle (required):'"), 'shared deletion requires an audited reason');
assert(source.includes('const ref = await vehicleLifecycleSharedRef(vehicle)'), 'canonical identity and version are freshly resolved at click time');
assert(source.includes('expectedVersion: ref.version'), 'protected delete uses the freshly resolved version');
assert(source.includes('await refreshEmailVehicleLocations()'), 'success and mutation rejection refresh authoritative projections');
assert(actions.includes("rpc('mark_vehicle_deleted'"), 'lifecycle bridge calls mark_vehicle_deleted');
for (const key of ['p_vehicle_id: vehicleId', 'p_expected_version: expectedVersion', 'p_reason: reason ?? null']) {
  assert(actions.includes(key), `shared deletion payload missing ${key}`);
}

async function runScenario({ vehicle, resolution, sharedActive = true, mutation = { ok: true } }) {
  const calls = { confirm: 0, prompt: 0, resolve: 0, mark: [], refresh: 0, local: 0, close: 0, render: 0, alerts: [] };
  const context = {
    window: {
      confirm: () => { calls.confirm += 1; return true; },
      prompt: () => { calls.prompt += 1; return 'Duplicate vehicle'; },
      alert: message => calls.alerts.push(message),
      __vehicleLifecycleActions: {
        markVehicleDeleted: async payload => { calls.mark.push(payload); return mutation; },
      },
    },
    selectedVehicle: () => vehicle,
    vehicleLocationActionAllowed: () => true,
    vehicleIdentityTitle: () => 'S-1',
    vehicleCustomerName: () => 'Customer',
    cleanNavisionText: value => String(value || '').trim(),
    vehicleLifecycleSharedModeActive: () => sharedActive,
    vehicleLifecycleSharedRef: async () => { calls.resolve += 1; return resolution; },
    describeVehicleLifecycleResolutionOutcome: result => `resolution:${result?.outcome}`,
    describeVehicleLifecycleActionError: error => `action:${error}`,
    refreshEmailVehicleLocations: async () => { calls.refresh += 1; },
    removeVehiclesFromTracker: () => { calls.local += 1; },
    refreshAfterVehicleRemoval: () => {},
    closeVehicleModal: () => { calls.close += 1; },
    renderAll: () => { calls.render += 1; },
  };
  vm.runInNewContext(`${source}\nthis.removeVehicleUnderTest=removeVehicle;`, context);
  const returned = await context.removeVehicleUnderTest('S-1');
  return { returned, calls };
}

(async () => {
  const sharedVehicle = { __sharedNavisionReadOnly: true };
  const success = await runScenario({
    vehicle: sharedVehicle,
    resolution: { outcome: 'resolved', vehicleId: 'canonical-id', version: 17, isArchived: false },
  });
  assert.strictEqual(success.returned, true);
  assert.deepStrictEqual(JSON.parse(JSON.stringify(success.calls.mark)), [{ vehicleId: 'canonical-id', expectedVersion: 17, reason: 'Duplicate vehicle' }]);
  assert.strictEqual(success.calls.refresh, 1);
  assert.strictEqual(success.calls.local, 0, 'shared success never touches browser-local deletion');

  const ambiguous = await runScenario({ vehicle: sharedVehicle, resolution: { outcome: 'ambiguous' } });
  assert.strictEqual(ambiguous.returned, false);
  assert.strictEqual(ambiguous.calls.mark.length, 0);
  assert.strictEqual(ambiguous.calls.local, 0, 'ambiguous resolution fails closed without local fallback');

  const stale = await runScenario({
    vehicle: sharedVehicle,
    resolution: { outcome: 'resolved', vehicleId: 'canonical-id', version: 18, isArchived: false },
    mutation: { ok: false, error: 'vehicle_version_conflict' },
  });
  assert.strictEqual(stale.returned, false);
  assert.strictEqual(stale.calls.refresh, 1, 'version rejection performs authoritative refresh');
  assert.strictEqual(stale.calls.local, 0);

  const unavailable = await runScenario({ vehicle: sharedVehicle, resolution: null, sharedActive: false });
  assert.strictEqual(unavailable.returned, false);
  assert.strictEqual(unavailable.calls.resolve, 0);
  assert.strictEqual(unavailable.calls.local, 0, 'unavailable shared authority cannot fall back locally');

  const local = await runScenario({ vehicle: {}, resolution: null, sharedActive: false });
  assert.strictEqual(local.returned, true);
  assert.strictEqual(local.calls.local, 1, 'genuinely local rows retain the local archive path');

  console.log('Canonical shared Vehicle Detail deletion source and behavior passed');
})().catch(error => { console.error(error); process.exitCode = 1; });
