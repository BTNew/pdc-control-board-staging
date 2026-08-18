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
  },
});

assert.strictEqual(mapped.pdcRequiresParts, true, 'Parts remains required');
assert.strictEqual(mapped.pdcCompleteParts, true, 'Parts received projection remains complete after snapshot refresh');
console.log('Parts snapshot completion projection passed.');
