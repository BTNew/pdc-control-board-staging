'use strict';

const assert = require('assert');
const fs = require('fs');

const app = fs.readFileSync('app.js', 'utf8');
const lifecycle = fs.readFileSync('vehicle-lifecycle-actions.js', 'utf8');
const service = fs.readFileSync('pdc-email-vehicle-location-service.js', 'utf8');
const { buildVehicleLifecycleIdentityInput } = require('./vehicle-lifecycle-actions.js');

const sharedNavisionStart = app.indexOf('function sharedNavisionLocationVehicle(item = {})');
const sharedNavisionEnd = app.indexOf('\nfunction sharedNavisionIdentityPartsFromItem', sharedNavisionStart);
assert.ok(sharedNavisionStart >= 0 && sharedNavisionEnd > sharedNavisionStart, 'shared Navision mapper exists');
const sharedNavision = app.slice(sharedNavisionStart, sharedNavisionEnd);
assert.ok(sharedNavision.includes('canonicalVehicleId: item.canonical_vehicle_id ||'), 'Navision rows retain the canonical vehicle UUID for Parts mutations');
assert.ok(sharedNavision.includes('sharedVehicleId: item.canonical_vehicle_id ||'), 'Navision rows expose the canonical UUID to shared identity resolution');

const identityStart = lifecycle.indexOf('function buildVehicleLifecycleIdentityInput(vehicle = {})');
const identityEnd = lifecycle.indexOf('\nfunction lifecycleIdentityCacheKey', identityStart);
assert.ok(identityStart >= 0 && identityEnd > identityStart, 'shared identity input builder exists');
const identityBuilder = lifecycle.slice(identityStart, identityEnd);
assert.ok(identityBuilder.includes('vehicle.__sharedNavisionCanonicalVehicleId'), 'identity resolver accepts the shared Navision canonical UUID');
const resolvedInput = buildVehicleLifecycleIdentityInput({
  stock: '13017855',
  __sharedNavisionCanonicalVehicleId: '7fe33693-f519-5152-bbe0-9cc799c4ae33',
  __sharedNavisionRecordId: 'e39eb741-cf03-44f2-8a75-54362ecc8a26',
  sourceSystem: 'microsoft_navision',
});
assert.strictEqual(resolvedInput.p_vehicle_id, '7fe33693-f519-5152-bbe0-9cc799c4ae33', 'Navision Parts target resolves by canonical UUID');
assert.strictEqual(resolvedInput.p_stock_number, '13017855', 'Navision Parts target retains stock as a secondary identity');

for (const name of ['markVehiclePartsOrdered', 'markVehiclePartsComplete', 'updateVehiclePartsWorstEta']) {
  const start = app.indexOf(`async function ${name}`);
  const end = app.indexOf('\nasync function ', start + 10);
  const body = app.slice(start, end > start ? end : start + 5000);
  assert.ok(start >= 0 && body.includes('authenticatedPartsTarget(key, vehicle)'), `${name} uses the shared canonical target resolver`);
}
assert.ok(service.includes("const PDC_PARTS_COMPLETE_RPC = 'mark_pdc_parts_received_auditor';"), 'Parts Received uses the staging Auditor RPC');
assert.ok(service.includes('p_idempotency_key: String(idempotencyKey || crypto.randomUUID())'), 'Parts Received binds one-time idempotency');
console.log('Shared canonical/Navision/email Parts Received identity contract passed.');
