'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const service = require('./pdc-email-vehicle-location-service.js');
const resolver = require('./vehicle-modal-identity.js');
const source = fs.readFileSync(require('node:path').join(__dirname, 'app.js'), 'utf8');
const helper = source.slice(source.indexOf('function vehicleModalCanOpenWithoutDealer('), source.indexOf('function vehicleModalApplyDealerIdentity('));
const gate = source.slice(source.indexOf('function openVehicleModal('), source.indexOf("  app.vehicleDetailPage = 'details';", source.indexOf('function openVehicleModal('))) + '\n return true;\n}';
const id = '11111111-1111-4111-8111-111111111111';
const raw = { id, stock_number: '70000001', source_system: 'tune_pmg', visible_on_board: true, version: 4 };
function opens(rows, patch = {}) {
  const vehicle = { ...service.mapServerVehicle(raw), ...patch };
  const context = {
    app: {}, selectedVehicle: () => vehicle, vehicleLocationActionAllowed: () => true,
    $: () => ({}), rememberModalReturnFocus() {}, vehicleKey: v => v.stock,
    vehicleWorkshopDetailCanonicalId: v => v.__emailVehicleId,
    vehicleModalIdentityStock: v => v.stock,
    vehicleModalDealerIdentity: v => ['14450', '37047'].includes(v.dealer_code) ? v.dealer_code : '',
    cleanNavisionText: v => String(v || '').trim(), window: { alert() {} },
    exactAuthoritativeVehicleSnapshotRow: identity => resolver.resolveExactAuthoritativeVehicleRow(rows, identity),
  };
  vm.createContext(context);
  vm.runInContext(helper + '\n' + gate, context);
  return context.openVehicleModal('70000001');
}
assert.equal(opens([raw]), true, 'verified external Tune vehicle can open without Navision');
assert.equal(opens([]), false, 'missing authoritative snapshot stays blocked');
assert.equal(opens([raw, raw]), false, 'duplicate canonical identity stays blocked');
assert.equal(opens([{ ...raw, stock_number: 'other' }]), false, 'wrong stock stays blocked');
assert.equal(opens([{ ...raw, id: 'another-id' }]), false, 'wrong UUID stays blocked');
assert.equal(opens([{ ...raw, source_system: 'microsoft_navision' }]), false, 'Navision still requires dealer');
assert.equal(opens([raw], { __emailVehicleServerAuthoritative: false }), false, 'local rows stay blocked');
assert.equal(opens([raw], { __emailVehicleIdentityConflict: true }), false, 'conflicts stay blocked');
assert.equal(opens([raw], { dealer_code: 'unrecognised' }), false, 'unknown dealer is not ignored');
assert.equal(opens([raw], { dealer_code: '14450' }), true, 'existing dealer-scoped path remains');
console.log('External Tune modal Open identity regression passed.');
