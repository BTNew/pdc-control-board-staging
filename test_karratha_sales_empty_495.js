/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
// r495 (F108): the Karratha Sales page before its first upload says why it is empty; Broome keeps "No vehicles match this view".
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const tick = () => new Promise(resolve => setImmediate(resolve));

function harness(search) {
  const elements = new Map(), calls = [];
  function el(id) {
    if (!elements.has(id)) {
      let markup = '';
      const node = { textContent: '', hidden: false, disabled: false, value: '', dataset: {}, events: {}, classList: { add() {}, remove() {}, toggle() {} },
        setAttribute() {}, removeAttribute() {}, focus() {}, addEventListener(name, fn) { this.events[name] = fn; } };
      Object.defineProperty(node, 'innerHTML', { get() { return markup; }, set(v) { markup = v; } });
      elements.set(id, node);
    }
    return elements.get(id);
  }
  const nav = ['myday', 'dashboard'].map(view => { const e = el('nav-' + view); e.dataset.salesView = view; return e; });
  const document = { hidden: false, title: 'Broome Toyota · Dashboard', body: { dataset: {} }, activeElement: null, getElementById: el,
    querySelectorAll: sel => (/img/.test(sel) ? [] : nav), querySelector() { return null; }, addEventListener() {} };
  const window = { document, location: { search, href: 'http://127.0.0.1/sales/' + search }, history: { state: null, replaceState() {} },
    BROOME_SALES_TOOLS: require('./sales/dashboard-tools.js'), PDC_AUTH_CONTEXT: { role: 'administrator', userId: 'user-A' },
    PDC_SUPABASE: { rpc(name, args) { return new Promise(resolve => calls.push({ name, args, resolve })); } },
    addEventListener() {}, setInterval() {}, clearInterval() {}, setTimeout, clearTimeout };
  const ctx = vm.createContext({ window, module: undefined, URL, URLSearchParams, Date, Set, Map, console });
  vm.runInContext(fs.readFileSync('sales/sales-branch.js', 'utf8'), ctx);
  vm.runInContext(fs.readFileSync('sales/sales.js', 'utf8'), ctx);
  return { el, calls };
}
async function load(h, dealer, division, items) {
  const snap = h.calls.find(c => c.name === 'get_broome_sales_snapshot');
  snap.resolve({ data: { context: { role: 'administrator', display_name: 'Example', dealer_code: dealer, division }, items,
    navision_updated_at: '2026-10-23T01:00:00Z', checked_at: '2026-10-23T01:00:00Z' } });
  for (let i = 0; i < 5; i++) await tick();
}

test('Karratha with no vehicles yet: table and phone list explain the upload', async () => {
  const h = harness('?branch=karratha');
  await load(h, '14450', 'Karratha Toyota', []);
  for (const id of ['vehicle-table', 'sales-mobile-vehicles']) {
    assert.match(h.el(id).innerHTML, /No Karratha Toyota vehicles yet\. This tab stays empty until the first Karratha sales export is imported \(dealer 14450, COSI = Yes\)\. Those files are not loaded into Broome Sales\./);
    assert.doesNotMatch(h.el(id).innerHTML, /No vehicles match this view/);
  }
});

test('Karratha with vehicles but none matching the filters keeps the usual wording', async () => {
  const h = harness('?branch=karratha');
  await load(h, '14450', 'Karratha Toyota', [{ tracking_id: 'k1', cosi: 'Yes', salesperson_code: 'QK', order: '0099001', toyota_status: 'In Transit To WA', source_current: true }]);
  assert.doesNotMatch(h.el('vehicle-table').innerHTML, /No Karratha Toyota vehicles yet/);
});

test('Karratha feed rows with no Karratha salesperson set up: says so instead of "no vehicles yet"', async () => {
  const h = harness('?branch=karratha');
  await load(h, '14450', 'Karratha Toyota', [{ tracking_id: 'k1', cosi: 'Yes', salesperson_code: null, order: '0099001', source_current: true },
    { tracking_id: 'k2', cosi: 'Yes', salesperson_code: null, order: '0099002', source_current: true }]);
  assert.match(h.el('vehicle-table').innerHTML, /2 Karratha Toyota vehicles are on the Navision feed, but none is linked to a Karratha salesperson yet\./);
  assert.doesNotMatch(h.el('vehicle-table').innerHTML, /0099001|0099002/);
});

test('Broome with no vehicles: unchanged "No vehicles match this view"', async () => {
  const h = harness('');
  await load(h, '37047', 'Broome Toyota', []);
  assert.match(h.el('vehicle-table').innerHTML, /No vehicles match this view\./);
  assert.doesNotMatch(h.el('vehicle-table').innerHTML, /Karratha/);
});
