'use strict';
// r709 (F319, Craig 29 Oct): keys on Craig's key list are never offered as spare keys at To PMB.
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
test('key list keys are not spare even when the vehicle is not on the board', () => {
  const free = freeFn()([{ key: '1' }], new Set(['2', '103', '316']));
  for (const k of ['1', '2', '103', '316']) assert.ok(!free.includes(k), k);
  assert.equal(free[0], '3');
});
test('reserved keys load from the key list table and the script version is bumped', () => {
  assert.match(app, /from\('pdc_key_list_reserved_708'\)\.select\('key_token'\)/);
  assert.match(fs.readFileSync('index.html', 'utf8'), /&amp;r709=2026\.10\.29\.r709"/);
});
