'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const {
  resolveExactAuthoritativeVehicleRow,
  saveWithOneExactRebindRetry,
} = require('./vehicle-modal-identity.js');
const emailService = require('./pdc-email-vehicle-location-service.js');
const { createVehicleLocationsRefreshCoordinator } = require('./vehicle-locations-refresh.js');

const root = __dirname;
const appSource = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const indexSource = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const stylesSource = fs.readFileSync(path.join(root, 'styles.css'), 'utf8');
const canonicalId = '7fe33693-f519-5152-bbe0-9cc799c4ae33';
const raw = {
  id: canonicalId,
  permanent_vehicle_id: 'PDC-AI-812C2291FE80A143E8FE8A55',
  stock_number: '13017855',
  version: 7,
  current_location: 'PMB',
  customer_name: 'FORTESCUE LTD',
  vehicle_description: 'HiLux 4x4 2.8L Dsl D/C/C 6AT WorkMate 2U2231007/2026',
  job_card_number: 'J139125422',
  visible_on_board: true,
  work_items: [{ work_key: 'fitting', required: true, completed: false }],
};

async function testExactOneRowIsMappedAndSaveRebindsOnce() {
  const exact = resolveExactAuthoritativeVehicleRow([raw], { canonicalId, stock: '13017855' });
  assert.strictEqual(exact.ok, true);
  assert.strictEqual(exact.code, 'exact_match');
  assert.strictEqual(exact.row, raw);
  const mapped = emailService.mapServerVehicle(exact.row);
  assert.strictEqual(mapped.__emailVehicleServerAuthoritative, true);
  assert.strictEqual(mapped.__emailVehicleId, canonicalId);
  assert.strictEqual(mapped.stock, '13017855');

  const calls = [];
  const result = await saveWithOneExactRebindRetry({
    vehicle: { __emailVehicleId: canonicalId, __emailVehicleVersion: 6, stock: '13017855' },
    changes: { client_name: 'FORTESCUE LTD' },
    save: async vehicle => {
      calls.push(vehicle);
      return calls.length === 1 ? { ok: false, code: 'version_conflict' } : { ok: true, data: { vehicle_version_after: vehicle.__emailVehicleVersion + 1 } };
    },
    refreshAndRebind: async () => ({ ok: true, vehicle: { ...mapped, __emailVehicleVersion: 7 } }),
  });
  assert.strictEqual(result.ok, true);
  assert.strictEqual(calls.length, 2);
  assert.strictEqual(calls[1].__emailVehicleId, canonicalId);
  assert.strictEqual(calls[1].__emailVehicleVersion, 7);
}

async function testIdentityConflictsAndContradictionsNeverRetry() {
  for (const rows of [
    [raw, { ...raw }],
    [raw, { ...raw, stock_number: '13017856' }],
  ]) {
    const exact = resolveExactAuthoritativeVehicleRow(rows, { canonicalId, stock: '13017855' });
    assert.strictEqual(exact.ok, false);
    assert(['duplicate_identity', 'conflicting_stock'].includes(exact.code));
  }
  assert.strictEqual(resolveExactAuthoritativeVehicleRow([raw], { canonicalId, stock: '13017856' }).code, 'stock_mismatch');
  assert.strictEqual(resolveExactAuthoritativeVehicleRow([], { canonicalId, stock: '13017855' }).code, 'not_found');

  let calls = 0;
  const noRetry = async code => saveWithOneExactRebindRetry({
    vehicle: { __emailVehicleId: canonicalId, __emailVehicleVersion: 7, stock: '13017855' },
    changes: {},
    save: async () => { calls += 1; return { ok: false, code }; },
    refreshAndRebind: async () => { calls += 100; return { ok: false, code: 'duplicate_identity' }; },
  });
  await noRetry('vehicle_detail_readback_contradictory');
  await noRetry('permission_denied');
  assert.strictEqual(calls, 2);
}

async function testBroadRefreshGenerationSupersedesModalCallbacks() {
  let run = 0;
  const first = new Promise(resolve => { setTimeout(() => resolve({ ok: true, revision: 1 }), 15); });
  const second = Promise.resolve({ ok: true, revision: 2 });
  const coordinator = createVehicleLocationsRefreshCoordinator({
    loaders: { snapshot: () => (++run === 1 ? first : second) },
  });
  const oldRun = coordinator.refresh();
  const newRun = coordinator.refresh({ supersede: true });
  assert.strictEqual((await newRun).ok, true);
  assert.strictEqual((await oldRun).stale, true);
}

function testIntegrationAndSlimRefreshContracts() {
  for (const marker of [
    'resolveExactAuthoritativeVehicleRow',
    'saveWithOneExactRebindRetry',
    'mapServerVehicle',
    'vehicleModalIdentityRecoveryInFlight',
    'vehicleModalIdentityRecoveryAttempted',
    'vehicleModalSaveInFlight',
    'refreshGeneration !== app.vehicleLocationsRefreshGeneration',
    'version_conflict',
    'vehicle_detail_readback_contradictory',
  ]) assert(appSource.includes(marker), `missing save/rebind marker: ${marker}`);
  assert(appSource.includes("refreshEmailVehicleLocations({ refreshGeneration: generation })"));
  assert(appSource.includes('Previous authoritative Vehicle Locations data is stale'));
  assert(indexSource.includes('vehicle-locations-refresh=2026.08.29.746-vehicle-modal-save-rebind'));
  assert(stylesSource.includes('width: fit-content'));
  assert(stylesSource.includes('min-width: 0'));
  assert(stylesSource.includes('min-height: 42px'));
  assert(stylesSource.includes('grid-template-columns: minmax(0, 1fr) auto minmax(0, 1fr)'));
  assert(stylesSource.includes('.vehicle-locations-refresh-button'));
  assert(!/\.vehicle-locations-refresh-button[^}]*width:\s*100%/.test(stylesSource), 'refresh button remains slimline rather than a full-width bar');
  assert(!appSource.match(/location\.reload\s*\(/));
}

(async () => {
  await testExactOneRowIsMappedAndSaveRebindsOnce();
  await testIdentityConflictsAndContradictionsNeverRetry();
  await testBroadRefreshGenerationSupersedesModalCallbacks();
  testIntegrationAndSlimRefreshContracts();
  console.log('Vehicle modal exact Stock 13017855 save-rebind regression passed.');
})().catch(error => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
