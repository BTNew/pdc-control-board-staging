'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const identity = require('./vehicle-modal-identity.js');
const emailService = require('./pdc-email-vehicle-location-service.js');

const root = __dirname;
const app = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const index = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const css = fs.readFileSync(path.join(root, 'styles.css'), 'utf8');
const exactId = '7fe33693-f519-5152-bbe0-9cc799c4ae33';
const raw13017855 = { id: exactId, stock_number: '13017855', version: 7, customer_name: 'FORTESCUE LTD' };

function testRetryableAndTerminalIdentityFailures() {
  assert.strictEqual(identity.isRetryableVehicleModalIdentityFailure('snapshot_unavailable'), true);
  assert.strictEqual(identity.isRetryableVehicleModalIdentityFailure('identity_refresh_unavailable'), true);
  assert.strictEqual(identity.isRetryableVehicleModalIdentityFailure('not_found'), false);
  assert.strictEqual(identity.isRetryableVehicleModalIdentityFailure('duplicate_identity'), false);
  assert.strictEqual(identity.isRetryableVehicleModalIdentityFailure('conflicting_stock'), false);
  assert.strictEqual(identity.isRetryableVehicleModalIdentityFailure('stock_mismatch'), false);
  assert.strictEqual(identity.isRetryableVehicleModalIdentityFailure('permission_denied'), false);
}

function test13017855RawSnapshotMapping() {
  const exact = identity.resolveExactAuthoritativeVehicleRow([raw13017855], { canonicalId: exactId, stock: '13017855' });
  assert.strictEqual(exact.ok, true);
  const mapped = emailService.mapServerVehicle(exact.row);
  assert.strictEqual(mapped.__emailVehicleServerAuthoritative, true);
  assert.strictEqual(mapped.__emailVehicleId, exactId);
  assert.strictEqual(mapped.stock, '13017855');
}

function testRecoveryAndRetryIntegrationContracts() {
  for (const marker of [
    'vehicleModalIdentityLastError',
    'data-modal-retry-authoritative-details',
    'retryAuthoritativeVehicleDetails',
    'isRetryableVehicleModalIdentityFailure',
    'if (cachedReady && isRetryableVehicleModalIdentityFailure(backgroundError)',
    'app.vehicleModalIdentityReady = true',
  ]) assert(app.includes(marker), `missing modal recovery marker: ${marker}`);
  assert(index.includes('vehicle-modal-identity.js?v=2026.08.29.750-vehicle-modal-recovery'));
  assert(index.includes('vehicle-locations-refresh=2026.08.29.750-vehicle-modal-recovery'));
  assert(css.includes('.vehicle-identity-refresh-notice'));
  assert(css.includes('.vehicle-modal-retry-details'));
  assert(!/location\.reload\s*\(/.test(app));
}

testRetryableAndTerminalIdentityFailures();
test13017855RawSnapshotMapping();
testRecoveryAndRetryIntegrationContracts();
console.log('Vehicle modal authenticated identity recovery regression passed.');
