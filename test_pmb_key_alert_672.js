'use strict';
// r672 (F281): PMB tile flashes red for no key, key 0 or duplicate keys.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const { pmbKeyAlert } = require('./pdc-vehicle-locations-table.js');

test('clean PMB keys do not alert', () => {
  assert.strictEqual(pmbKeyAlert([{ key: '12', stock: 'A' }, { key: '13', stock: 'B' }]).alert, false);
});
test('missing, zero and duplicate keys alert with stocks named', () => {
  const r = pmbKeyAlert([{ key: '', stock: 'A' }, { key: '000', stock: 'B' }, { key: '432', stock: 'C' }, { key: ' 432 ', stock: 'D' }, { key: '7', stock: 'E' }]);
  assert.strictEqual(r.alert, true);
  assert.deepStrictEqual(r.missing, ['A']);
  assert.deepStrictEqual(r.zero, ['B']);
  assert.deepStrictEqual(r.dups, [{ key: '432', stocks: ['C', 'D'] }]);
  assert.strictEqual(r.count, 4);
  assert.match(r.text, /no key: A · key 0: B · key 432 on C, D/);
});
test('PMB tile gets the red class and css exists', () => {
  const js = fs.readFileSync('pdc-vehicle-locations-table.js', 'utf8');
  const css = fs.readFileSync('pdc-vehicle-locations-table.css', 'utf8');
  assert.match(js, /key === 'pmb' && !loading && pmbKeys\.alert \? ' is-key-alert'/);
  assert.match(css, /\[data-vlt-tile="pmb"\]\.is-key-alert/);
});
