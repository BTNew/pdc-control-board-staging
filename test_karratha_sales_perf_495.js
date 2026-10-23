/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
// r495 (F108) performance guard: the Karratha branch adds no per-vehicle work and no extra query. One snapshot RPC per
// refresh, and the branch lookups (current / roster) run a fixed number of times whatever the number of vehicles.
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
  const api = window.BROOME_SALES_BRANCH, counts = { current: 0, roster: 0 };
  window.BROOME_SALES_BRANCH = { ...api, current: (...a) => (counts.current++, api.current(...a)), roster: (...a) => (counts.roster++, api.roster(...a)) };
  vm.runInContext(fs.readFileSync('sales/sales.js', 'utf8'), ctx);
  return { el, calls, counts };
}
async function load(h, dealer, division, items) {
  const snap = h.calls.find(c => c.name === 'get_broome_sales_snapshot');
  snap.resolve({ data: { context: { role: 'administrator', display_name: 'Example', dealer_code: dealer, division }, items,
    navision_updated_at: '2026-10-23T01:00:00Z', checked_at: '2026-10-23T01:00:00Z' } });
  for (let i = 0; i < 5; i++) await tick();
}

const rows = (n, codes) => Array.from({ length: n }, (_, i) => ({ tracking_id: 't' + i, navision_record_id: 'n' + i, cosi: true, source_current: true,
  salesperson_code: codes[i % codes.length], order: '0099' + String(i).padStart(4, '0'), stock: 'TEST' + String(i).padStart(4, '0'), client: 'Sample ' + i, vehicle: 'Sample HiLux' }));

test('Karratha: one snapshot RPC per refresh; branch lookups do not scale with 200 vs 400 vehicles', async () => {
  const seen = {};
  for (const n of [200, 400]) {
    const h = harness('?branch=karratha');
    await load(h, '14450', 'Karratha Toyota', rows(n, ['QK', 'QL']));
    assert.equal(h.calls.filter(c => c.name === 'get_broome_sales_snapshot').length, 1, String(n));
    assert.equal(h.counts.roster, 1, 'roster once per refresh');
    seen[n] = { ...h.counts };
    assert.equal((h.el('vehicle-table').innerHTML.match(/data-tracking-id="t\d+"|TEST\d{4}/g) || []).length > 0, true);
  }
  assert.deepEqual(seen[400], seen[200]);
  assert.ok(seen[400].current < 50, 'branch current() is not called per vehicle: ' + seen[400].current);
});
