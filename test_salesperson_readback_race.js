'use strict';

const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const source = fs.readFileSync('app.js', 'utf8');
const start = source.indexOf('function authoritativeSalespersonCode');
const end = source.indexOf('\nfunction resetEmailVehicleLocations', start);
assert.ok(start >= 0 && end > start, 'receipt-first helpers must remain locally testable');

const vehicleId = '11111111-1111-4111-8111-111111111111';
const baseVehicle = {
  __emailVehicleId: vehicleId,
  __emailVehicleVersion: 16,
  stock: '12664962',
  salespersonCode: 'BG',
  salespersonName: 'Bryce Guthrie',
  salespersonEmail: 'bg@example.test',
  consultant: 'BG',
  client: 'Original client',
  keyNumber: 'K-16',
  jobcard: 'JC-16',
};
const acceptedReceipt = {
  ok: true,
  code: 'salesperson_assigned',
  data: {
    receipt_id: 'dfa ad2e1-0265-5716-aca4-5250dbaceac5'.replaceAll(' ', ''),
    vehicle_id: vehicleId,
    vehicle_version_before: 16,
    vehicle_version_after: 17,
    effective_salesperson: {
      salesperson_code: 'CW', salesperson_name: 'Craig Watson', salesperson_email: 'cw@example.test',
      salesperson_manual_override: true,
    },
  },
};

const context = {
  app: { data: [structuredClone(baseVehicle)], emailVehicleLocationRows: [], emailVehicleReceiptOverlays: new Map() },
  window: { crypto: { randomUUID: () => '00000000-0000-4000-8000-000000000000' } },
  crypto: { randomUUID: () => '00000000-0000-4000-8000-000000000000' },
  setTimeout,
  Promise,
};
vm.createContext(context);
vm.runInContext(`${source.slice(start, end)}\nthis.receiptHelpers = { applyAuthoritativeVehicleReceipt, authoritativeVehicleReadbackStatus };`, context);

const patched = context.receiptHelpers.applyAuthoritativeVehicleReceipt(baseVehicle, acceptedReceipt, 'CW');
assert.ok(patched, 'accepted receipt should produce an immediate canonical vehicle patch');
assert.strictEqual(patched.__emailVehicleId, vehicleId, 'stable UUID is preserved');
assert.strictEqual(patched.__emailVehicleVersion, 17, 'receipt version is applied immediately');
assert.strictEqual(patched.salespersonCode, 'CW');
assert.strictEqual(patched.consultant, 'CW');
assert.strictEqual(patched.salespersonManualOverride, true);
assert.strictEqual(patched.client, 'Original client', 'poisoned/unrelated local fields are not invented or discarded');
const replayPatched = context.receiptHelpers.applyAuthoritativeVehicleReceipt(baseVehicle, { ...acceptedReceipt, replay: true }, 'CW');
assert.strictEqual(replayPatched.__emailVehicleVersion, 17, 'a valid idempotent replay applies the same canonical receipt state');
assert.doesNotMatch(source.slice(start, source.indexOf('\nfunction discardLegacyAuthoritativeSalespersonEdits', start)), /saveJson\(|localStorage\./, 'receipt reconciliation cannot invent browser-local persistence');

assert.strictEqual(context.receiptHelpers.authoritativeVehicleReadbackStatus(
  { id: vehicleId, version: 16, salesperson_code: 'BG' },
  { vehicleId, vehicleVersionAfter: 17, salespersonCode: 'CW', hasSalespersonProjection: true },
), 'pending', 'a stale projection is retried rather than reported as a failed write');
assert.strictEqual(context.receiptHelpers.authoritativeVehicleReadbackStatus(
  { id: vehicleId, version: 17, salesperson_code: 'CW' },
  { vehicleId, vehicleVersionAfter: 17, salespersonCode: 'CW', hasSalespersonProjection: true },
), 'matching', 'an immediate matching snapshot converges');
assert.strictEqual(context.receiptHelpers.authoritativeVehicleReadbackStatus(
  { id: vehicleId, version: 17, salesperson_code: 'CW' },
  { vehicleId, vehicleVersionAfter: 17, salespersonCode: 'CW', hasSalespersonProjection: true },
), 'matching', 'an eventual snapshot has the same authoritative result');
assert.strictEqual(context.receiptHelpers.authoritativeVehicleReadbackStatus(
  { id: vehicleId, version: 17, salesperson_code: 'BG' },
  { vehicleId, vehicleVersionAfter: 17, salespersonCode: 'CW', hasSalespersonProjection: true },
), 'contradictory', 'a same/newer contradictory authoritative row fails closed');
assert.strictEqual(context.receiptHelpers.authoritativeVehicleReadbackStatus(
  { id: vehicleId, version: 17, salesperson_code: 'BG' },
  { vehicleId, vehicleVersionAfter: 17, salespersonCode: '', hasSalespersonProjection: true },
), 'contradictory', 'a clear receipt cannot accept a stale salesperson projection');

const combined = context.receiptHelpers.applyAuthoritativeVehicleReceipt(baseVehicle, {
  ok: true,
  code: 'vehicle_detail_updated',
  data: { receipt_id: '388-receipt', vehicle_id: vehicleId, vehicle_version_after: 18 },
}, '', { client_name: 'Updated client', key_number: 'K-18', job_card_number: 'JC-18' });
assert.strictEqual(combined.__emailVehicleVersion, 18, 'detail save can consume salesperson receipt version');
assert.strictEqual(combined.client, 'Updated client');
assert.strictEqual(combined.keyNumber, 'K-18');
assert.strictEqual(combined.jobcard, 'JC-18');
assert.strictEqual(combined.salespersonCode, 'BG', 'detail receipt preserves the canonical salesperson');

assert.doesNotMatch(source, /if \(!await refreshEmailVehicleLocations\(\)\) return \{ ok: false, code: 'salesperson_assignment_readback_failed'/,
  'a superseded broad refresh cannot turn an accepted salesperson receipt into an error');

const raceContext = {
  app: {
    data: [structuredClone(baseVehicle)],
    emailVehicleLocationRows: [structuredClone(baseVehicle)],
    emailVehicleReceiptOverlays: new Map(),
    emailVehicleLocationService: null,
  },
  window: {
    crypto: { randomUUID: () => '00000000-0000-4000-8000-000000000000' },
    setTimeout,
    PDC_EMAIL_VEHICLE_LOCATION_SERVICE: require('./pdc-email-vehicle-location-service.js'),
  },
  crypto: { randomUUID: () => '00000000-0000-4000-8000-000000000000' },
  setTimeout,
  Promise,
  refreshEmailVehicleLocations: async () => false,
};
vm.createContext(raceContext);
vm.runInContext(`${source.slice(start, end)}\nthis.saveSalesperson = saveAuthoritativeVehicleSalesperson; this.saveChanges = saveAuthoritativeVehicleChanges;`, raceContext);

let snapshotCalls = 0;
let detailExpectedVersion = null;
raceContext.app.emailVehicleLocationService = {
  updateSalespersonAssignment: async () => acceptedReceipt,
  updateVehicleDetailFields: async (_id, expectedVersion) => {
    detailExpectedVersion = expectedVersion;
    return { ok: true, code: 'vehicle_detail_updated', data: { receipt_id: 'detail-receipt', vehicle_id: vehicleId, vehicle_version_after: 18 } };
  },
  snapshot: async () => {
    snapshotCalls += 1;
    if (snapshotCalls <= 3) return { ok: true, data: { vehicles: [{ id: vehicleId, version: 16, salesperson_code: 'BG' }] } };
    return { ok: true, data: { vehicles: [{ id: vehicleId, version: 18, salesperson_code: 'CW', salesperson_name: 'Craig Watson', salesperson_email: 'cw@example.test', salesperson_manual_override: true, customer_name: 'Updated client', key_number: 'K-18', job_card_number: 'JC-18' }] } };
  },
};
(async () => {
  const salespersonResult = await raceContext.saveSalesperson(raceContext.app.data[0], 'CW');
  assert.strictEqual(salespersonResult.ok, true, 'accepted receipt remains successful when broad refresh loses its generation race');
  assert.strictEqual(salespersonResult.readbackPending, true, 'delayed authoritative readback is reported as pending, not failed');
  assert.strictEqual(salespersonResult.data.authoritativeVehicle.__emailVehicleVersion, 17);
  assert.strictEqual(raceContext.app.data[0].salespersonCode, 'CW', 'receipt patch immediately replaces poisoned local salesperson state');
  const combinedResult = await raceContext.saveChanges(raceContext.app.data[0], 'CW', { client_name: 'Updated client', key_number: 'K-18', job_card_number: 'JC-18' });
  assert.strictEqual(combinedResult.ok, true, 'combined salesperson/detail save remains successful');
  assert.strictEqual(detailExpectedVersion, 17, 'detail RPC uses vehicle_version_after from salesperson receipt');
  assert.strictEqual(combinedResult.data.authoritativeVehicle.__emailVehicleVersion, 18);
  console.log('Salesperson accepted receipt generation-race integration: PASS');
})().catch(error => { console.error(error); process.exitCode = 1; });
console.log('Salesperson receipt-first readback race regression: PASS');
