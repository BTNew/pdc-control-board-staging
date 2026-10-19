'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('app.js', 'utf8');
const fn = source.slice(source.indexOf('function vehicleWorkshopDetailRequestDealerCode('), source.indexOf('\nfunction vehicleWorkshopDetailResponse('));
const context = { cleanNavisionText: value => String(value || '').trim() };
vm.runInNewContext(fn, context);
test('accepted PMG board records with customer-account codes use the configured read scope', () => {
  assert.equal(context.vehicleWorkshopDetailRequestDealerCode({ dealer_code: '001234', __emailVehicleServerAuthoritative: true }, { dealerCode: '14450' }), '14450');
});
test('authenticated Navision projections use their canonical read identity despite a customer-account code', () => {
  const row = { __sharedNavisionDealerCode: 'CUSTOMER_ACCOUNT', __sharedNavisionReadOnly: true,
    __sharedNavisionCanonicalVehicleId: '11111111-1111-4111-8111-111111111111' };
  assert.equal(context.vehicleWorkshopDetailRequestDealerCode(row, { dealerCode: '14450' }), '14450');
  assert.equal(context.vehicleWorkshopDetailRequestDealerCode({ ...row, __sharedNavisionCanonicalVehicleId: '' }, { dealerCode: '14450' }), '');
  assert.equal(context.vehicleWorkshopDetailRequestDealerCode({ ...row, __sharedNavisionReadOnly: false }, { dealerCode: '14450' }), '');
  assert.equal(context.vehicleWorkshopDetailRequestDealerCode(row, { dealerCode: '37047' }), '');
});
test('read-scope fallback cannot confer cross-dealer authority or accept an untrusted record', () => {
  for (const vehicle of [{ dealer_code: '001234' }, { dealer_code: '001234', __emailVehicleServerAuthoritative: false }]) {
    assert.equal(context.vehicleWorkshopDetailRequestDealerCode(vehicle, { dealerCode: '14450' }), '');
  }
  assert.equal(context.vehicleWorkshopDetailRequestDealerCode({ dealer_code: '001234', __emailVehicleServerAuthoritative: true }, { dealerCode: '37047' }), '');
  assert.equal(context.vehicleWorkshopDetailRequestDealerCode({ dealer_code: '37047', __emailVehicleServerAuthoritative: true }, { dealerCode: '14450' }), '37047');
});
