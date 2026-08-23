'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const actionsSource = fs.readFileSync(path.join(__dirname, 'vehicle-lifecycle-actions.js'), 'utf8');
const appSource = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8');
const stagingSource = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
const legacyShell = fs.readFileSync(path.join(__dirname, 'staging.html'), 'utf8');
const stagingConfig = fs.readFileSync(path.join(__dirname, 'pdc-supabase-config.staging.js'), 'utf8');

assert.ok(actionsSource.includes('adminCompleteVehicleDelete'), 'bridge exposes complete delete action');
assert.ok(actionsSource.includes("pdc_admin_complete_vehicle_delete"), 'bridge calls complete-delete RPC');
assert.ok(actionsSource.includes('p_idempotency_key'), 'bridge sends idempotency key');
assert.ok(appSource.includes('Complete Vehicle Delete'), 'vehicle UI labels complete delete');
assert.ok(appSource.toLowerCase().includes('historical email will not replay'), 'vehicle UI explains historical email replay fence');
assert.ok(appSource.includes('data-complete-vehicle-delete'), 'vehicle UI retains reviewed complete-delete control source');
assert.ok(appSource.includes('completeVehicleDeleteCommissioned()'), 'vehicle UI is gated by commissioned capability');
assert.ok(appSource.includes('completeVehicleDeleteCommissioned === true'), 'commissioning gate requires exact true');
assert.ok(stagingConfig.includes('completeVehicleDeleteCommissioned: false'), 'uncommissioned staging source hides destructive control');
assert.ok(appSource.includes('disabled = true') || appSource.includes('.disabled = true'), 'request path disables the destructive control');
assert.ok(appSource.includes('refreshVehicleLifecycleLocationsAndRender'), 'success path performs authoritative readback');
assert.ok(stagingSource.includes('pdc-supabase-config.staging.js'), 'staging shell loads staging config');
assert.ok(stagingSource.includes('app.js?v=2026.08.23.05-fix-chip-shortening'), 'staging shell points at hidden-control release marker');
assert.ok(legacyShell.includes('url=./'), 'retired staging shell redirects to current entry');

const { buildVehicleLifecycleSharedActions } = require('./vehicle-lifecycle-actions.js');
const calls = [];
const bridge = buildVehicleLifecycleSharedActions({
  rpc: async (_token, name, params) => { calls.push({ name, params }); return { ok: true, body: { ok: true, code: 'vehicle_deleted', data: { receipt_id: 'r' } } }; },
}, () => 'token');
(async () => {
  const result = await bridge.adminCompleteVehicleDelete({
    vehicleId: '11111111-1111-4111-8111-111111111111',
    expectedVersion: 4,
    stockConfirmation: '13047224',
    reason: 'Repeat staging import test',
    idempotencyKey: 'complete-delete-test-1234',
  });
  assert.strictEqual(result.ok, true);
  assert.deepStrictEqual(calls[0], {
    name: 'pdc_admin_complete_vehicle_delete',
    params: {
      p_vehicle_id: '11111111-1111-4111-8111-111111111111',
      p_expected_version: 4,
      p_confirmation_stock: '13047224',
      p_reason: 'Repeat staging import test',
      p_idempotency_key: 'complete-delete-test-1234',
    },
  });
  console.log('Complete vehicle delete UI/service contract passed.');
})().catch(error => { console.error(error); process.exitCode = 1; });
