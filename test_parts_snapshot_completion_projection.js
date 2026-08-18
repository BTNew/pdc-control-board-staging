'use strict';

const assert = require('assert');
const { mapServerVehicle } = require('./pdc-email-vehicle-location-service.js');

const mapped = mapServerVehicle({
  id: 'vehicle-12185553',
  permanent_vehicle_id: 'vehicle-12185553',
  stock_number: '12185553',
  parts_required: true,
  parts_completed: false,
  parts_update: {
    parts_required: true,
    parts_ordered: true,
    parts_received: true,
    worst_eta: '2026-08-25',
  },
});

assert.strictEqual(mapped.pdcRequiresParts, true, 'Parts remains required');
assert.strictEqual(mapped.pdcPartsOrdered, true, 'nested Parts ordered projection remains authoritative');
assert.strictEqual(mapped.pdcPartsWorstEta, '2026-08-25', 'nested Parts ETA projection remains available');
assert.strictEqual(mapped.pdcCompleteParts, true, 'Parts received projection remains complete after snapshot refresh');

const rootProjected = mapServerVehicle({
  id: 'vehicle-root-projection',
  permanent_vehicle_id: 'vehicle-root-projection',
  stock_number: '12185554',
  parts_required: true,
  parts_ordered: true,
  parts_received: false,
  worst_eta: '2026-08-29',
});
assert.strictEqual(rootProjected.pdcRequiresParts, true, 'root Parts required alias is accepted');
assert.strictEqual(rootProjected.pdcPartsOrdered, true, 'root Parts ordered alias is accepted');
assert.strictEqual(rootProjected.pdcPartsWorstEta, '2026-08-29', 'root Parts ETA alias is accepted');
assert.strictEqual(rootProjected.pdcCompleteParts, false, 'root Parts received false remains incomplete');
console.log('Parts snapshot completion/projection passed.');
