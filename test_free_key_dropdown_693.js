'use strict';
// r693 (F303): spare key tags follow the yard bay ranges (Ron), lowest first; out-of-service and WPC excluded.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const app = fs.readFileSync('app.js', 'utf8');
function freeFn() {
  const src = app.slice(app.indexOf('const PMB_KEY_RANGES'), app.indexOf('// r692 (F302): Send to PMB box.'));
  const ctx = { boardKeyToken: v => String(v || '').replace(/\s+/g, '').toUpperCase(), vehicleKeyNumber: v => v.key };
  vm.runInNewContext(src + '\nthis.f = pmbFreeKeyNumbers;', ctx);
  return ctx.f;
}
test('spare keys: yard ranges only, lowest first, used and out-of-service skipped', () => {
  const free = freeFn()([{ key: '1' }, { key: '3' }, { key: ' 2 ' }, { key: 'WPC' }, { key: '' }, { key: '650' }]);
  assert.equal(free[0], '4');
  for (const k of ['1', '2', '3', '41', '100', '153', '335', '336', '337', '433', '443', '650', '0']) assert.ok(!free.includes(k), k);
  for (const k of ['40', '101', '334', '338', '432', '444', '520', '649']) assert.ok(free.includes(k), k);
  assert.equal(free.length, 40 + 52 + 82 + 70 + 62 + 20 + 50 - 14 - 4);
});
test('the box offers the spare keys (current key first) and Other key; Vehicle Locations lists spare keys', () => {
  const box = app.slice(app.indexOf('function pmbSendToPmbDialog'), app.indexOf('async function transferYhVehicleToPmb'));
  assert.match(box, /id="pmb-send-key-pick"/);
  assert.match(box, /Other key…/);
  assert.match(box, /\(current key\)/);
  assert.match(app, /freeKeys: typeof pmbFreeKeyNumbers === 'function' \? pmbFreeKeyNumbers\(\) : \[\]/);
  const table = fs.readFileSync('pdc-vehicle-locations-table.js', 'utf8');
  assert.match(table, /Spare key numbers/);
  assert.match(table, /if \(k === 'WPC'\) continue;/);
});
test('WPC is not missing or duplicate in the PMB key alert', () => {
  const { pmbKeyAlert } = require('./pdc-vehicle-locations-table.js');
  assert.equal(pmbKeyAlert([{ key: 'WPC', stock: 'A' }, { key: 'wpc', stock: 'B' }, { key: '5', stock: 'C' }]).alert, false);
});
