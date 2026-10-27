/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r499 (F112) performance guard (pattern: test_sublet_board_perf_494c.js). The Sales PMB STATUS icons must cost ONE batched
// read per Sales refresh, nothing per vehicle while the table draws, and no extra table redraw. Made-up vehicles only.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { performance } = require('node:perf_hooks');

const U = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const KEYS = ['tint', 'bus4x4', 'hoist', 'fitting', 'fabrication', 'electrical', 'tyre', 'sublet'];
const entry = i => ({ vehicle_id: U(i), has_stock: true, pmb_stage: i % 3 ? 'FITTING' : 'TINT', pmb_stoppage: i % 17 === 0, pmb_stoppage_reason: i % 17 ? '' : 'Made-up reason',
  work: Object.fromEntries(KEYS.map((k, j) => [k, { required: (i + j) % 3 === 0, completed: (i + j) % 6 === 0 }])),
  parts: { parts_required: true, parts_ordered: i % 2 === 0, parts_received: i % 5 === 0 },
  bookings: i % 4 ? [{ stage_code: 'FITTING', status: i % 8 ? 'planned' : 'stoppage', stoppage_reason: 'Made-up' }] : [],
  parts_flags: i % 3 ? { colour: ['green', 'orange', 'red'][i % 3], label: 'Flag', meaning: 'Made-up', last_successful_import_at: '2026-10-22T01:30:00Z' } : null,
  sublet_active_bookings: i % 7 === 0 ? 1 : 0, sublet_without_po: i % 9 === 0 ? 1 : 0,
  sublet_po: i % 11 === 0 ? { state: 'ordered', total: 2, ticked: 1, with_po: 2 } : null, jita_number: i % 10 === 0 ? '1234567' : null });
const row = i => ({ cosi: 'Yes', salesperson_code: 'BG', tracking_id: 't' + i, stock: 'S' + String(i).padStart(6, '0'), order: '', client: 'Example ' + i,
  vehicle: 'Made-up 4x4', kewdale_eta: '2026-10-23', navision_notes: '', pmb_stage: 'Fitting', pmb_location: 'Yard',
  canonical_vehicle_id: i % 10 === 0 ? null : U(i) });

function harness() {
  const elements = new Map();
  const el = id => { if (!elements.has(id)) elements.set(id, { innerHTML: '', textContent: '', hidden: false, disabled: false, value: '', dataset: {}, classList: { toggle() {} },
    setAttribute() {}, removeAttribute() {}, addEventListener() {}, close() {}, showModal() {}, scrollIntoView() {}, focus() {} }); return elements.get(id); };
  const stored = new Map();
  const calls = [];
  const window = { localStorage: { get length() { return stored.size; }, key: i => [...stored.keys()][i], getItem: k => stored.get(k) ?? null, setItem: (k, v) => stored.set(k, String(v)), removeItem: k => stored.delete(k) },
    document: { hidden: false, getElementById: el, querySelectorAll: () => [], addEventListener() {} }, console: { warn: (...a) => calls.push({ name: 'warn', a }) },
    BROOME_ZEBRA_LABELS: require('./sales/zebra-labels.js'), PDC_AUTH_CONTEXT: { role: 'administrator', userId: 'A' },
    PDC_WORKSHOP_ELIGIBILITY: require('./workshop-eligibility.js'),
    PDC_SUPABASE: { rpc(name, args) { return new Promise(resolve => calls.push({ name, args, resolve })); } }, addEventListener() {}, setInterval() {} };
  const sandbox = { window, globalThis: window, module: undefined, Set, Map, Date, console, Intl, fetch: () => { throw new Error('no fetch on Sales render'); } };
  vm.createContext(sandbox);
  for (const f of ['vehicle-requirements-guard.js', 'sales/pmb-stations.js', 'sales/dashboard-tools.js', 'sales/sales.js']) vm.runInContext(fs.readFileSync(f, 'utf8'), sandbox);
  return { window, calls, el };
}
const tick = async () => { for (let i = 0; i < 10; i++) await new Promise(r => setImmediate(r)); };

for (const N of [200, 400]) {
  test(`${N} vehicles: one batched station read, no per-vehicle work while drawing, no extra redraw`, async () => {
    const h = harness();
    const rows = Array.from({ length: N }, (_, i) => row(i + 1));
    let renders = 0;
    const table = h.el('vehicle-table'); let tableHtml = '';
    Object.defineProperty(table, 'innerHTML', { get: () => tableHtml, set: v => { renders++; tableHtml = v; } });
    const snapshot = h.calls.find(c => /snapshot/.test(c.name));
    assert.ok(snapshot, 'sales refresh started');
    snapshot.resolve({ data: { context: { role: 'administrator' }, items: rows } });
    await tick();
    const stationCalls = h.calls.filter(c => c.name === 'get_broome_sales_pmb_stations');
    assert.equal(stationCalls.length, 1, 'ONE batched read');
    const linked = rows.filter(r => r.canonical_vehicle_id).length;
    assert.equal(stationCalls[0].args.p_vehicle_ids.length, linked, 'every linked vehicle in the one call, no unlinked ones');
    const rendersBefore = renders;
    const t0 = performance.now();
    stationCalls[0].resolve({ data: { ok: true, vehicles: stationCalls[0].args.p_vehicle_ids.map((id, i) => entry(Number(id.slice(-12)))) } });
    // Let every other refresh read settle (each resolves empty), then the existing final render runs once.
    for (let round = 0; round < 10; round++) { await tick(); for (const c of h.calls.filter(c => c.resolve && !c.done && c.name !== 'get_broome_sales_pmb_stations' && !/snapshot/.test(c.name))) { c.done = true; c.resolve({ data: null, error: null }); } }
    const elapsed = performance.now() - t0;
    assert.equal(h.calls.filter(c => c.name === 'get_broome_sales_pmb_stations').length, 1, 'no further station reads');
    assert.ok(renders - rendersBefore <= 1, `at most the existing final render (got ${renders - rendersBefore})`);
    const strips = (tableHtml.match(/class="sales-pmb-stations"/g) || []).length;
    assert.equal(strips, linked, 'icons on linked rows only');
    // Redraw (filter / sort / search) repeatedly: cache reads only, still no calls.
    const api = h.window.BROOME_SALES_PMB_STATIONS;
    const t1 = performance.now();
    for (let k = 0; k < 5; k++) for (const r of rows) api.html(r);
    const lookups = performance.now() - t1;
    assert.equal(h.calls.filter(c => c.name === 'get_broome_sales_pmb_stations').length, 1);
    // Build cost of the strips for N vehicles (once per answer).
    const t2 = performance.now();
    api.api.indexAnswer({ ok: true, vehicles: rows.map((_, i) => entry(i + 1)) });
    const build = performance.now() - t2;
    process.stdout.write(`# r499 perf N=${N}: answer->final render ${elapsed.toFixed(1)} ms; build ${N} strips ${build.toFixed(1)} ms; 5x${N} cached lookups ${lookups.toFixed(2)} ms\n`);
    assert.ok(build < 400, `building ${N} strips took ${build.toFixed(1)} ms`);
    assert.ok(lookups < 50, `cache lookups took ${lookups.toFixed(1)} ms`);
  });
}

test('render path never reads: pmb-stations.js has one rpc call (in refresh) and no fetch; sales.js calls refresh once', () => {
  const src = fs.readFileSync('sales/pmb-stations.js', 'utf8');
  assert.equal((src.match(/\.rpc\(/g) || []).length, 2);
  assert.doesNotMatch(src, /\bfetch\(|XMLHttpRequest|setInterval|setTimeout/);
  const html = src.slice(src.indexOf('html(row) {'), src.indexOf('clear() {'));
  assert.doesNotMatch(html, /rpc|refresh|entryHtml|await/);
  const sales = fs.readFileSync('sales/sales.js', 'utf8');
  assert.equal((sales.match(/BROOME_SALES_PMB_STATIONS\?\.refresh/g) || []).length, 1);
  assert.equal((sales.match(/get_broome_sales_pmb_stations/g) || []).length, 0);
  const refresh = sales.slice(sales.indexOf('async function refresh() {'), sales.indexOf('function applyConfirmedVisibility'));
  assert.equal((refresh.match(/\brender\(\)/g) || []).length, 2, 'no extra render added to refresh');
});

test('a failed icon read still shows the station icons', async () => {
  const stations = require('./sales/pmb-stations.js');
  const host = { PDC_SUPABASE: { rpc: async name => name === 'list_station_icon_completion_578'
    ? { data: null, error: new Error('icon read failed') }
    : { data: { ok: true, vehicles: [entry(1)] } } } };
  const s = stations.create(host);
  assert.equal(await s.refresh([U(1)]), 1);
  assert.match(s.html({ canonical_vehicle_id: U(1) }), /sales-pmb-stations/);
  assert.doesNotMatch(s.html({ canonical_vehicle_id: U(1) }), /every line ticked/);
});

test('a failed or missing read shows no icons, logs once and never breaks the Sales table', async () => {
  const stations = require('./sales/pmb-stations.js');
  const warns = [];
  let fail = true;
  const host = { console: { warn: (...a) => warns.push(a) }, PDC_SUPABASE: { rpc: async () => (fail ? { data: null, error: new Error('function does not exist') } : { data: { ok: true, vehicles: [entry(1)] } }) } };
  const s = stations.create(host);
  assert.equal(await s.refresh([U(1)]), 0); assert.equal(await s.refresh([U(1)]), 0);
  assert.equal(warns.length, 1);
  assert.equal(s.html({ canonical_vehicle_id: U(1) }), '');
  fail = false; assert.equal(await s.refresh([U(1), U(1).toUpperCase(), 'not-a-uuid', null]), 1);
  assert.match(s.html({ canonical_vehicle_id: U(1).toUpperCase() }), /sales-pmb-stations/);
  assert.equal(s.html({ canonical_vehicle_id: null }), '');
  s.clear(); assert.equal(s.size(), 0);
  const capped = []; await stations.create({ PDC_SUPABASE: { rpc: async (n, a) => { capped.push(a.p_vehicle_ids.length); return { data: { ok: true, vehicles: [] } }; } } })
    .refresh(Array.from({ length: 1500 }, (_, i) => U(i + 1)));
  assert.deepEqual(capped, [1000, 1000], 'capped at the server limit, station read then icon read');
});

test('the shared guard file loads beside every Sales page script with no global name clash', () => {
  const index = fs.readFileSync('sales/index.html', 'utf8');
  const files = [...index.matchAll(/<script src="([^"?]+)/g)].map(m => require('node:path').posix.join('sales', m[1]));
  const ctx = vm.createContext({ setTimeout() {}, setInterval() {}, clearTimeout() {}, clearInterval() {}, addEventListener() {}, console: { log() {}, warn() {}, error() {}, info() {} } });
  ctx.window = ctx; ctx.self = ctx;
  for (const f of files) {
    try { vm.runInContext(fs.readFileSync(f, 'utf8'), ctx, { filename: f }); } catch (e) {
      assert.doesNotMatch(String(e && e.message), /already been declared/, f);
    }
  }
  assert.ok(files.includes('vehicle-requirements-guard.js') && files.includes('sales/pmb-stations.js'));
});
