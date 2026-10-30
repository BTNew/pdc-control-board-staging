'use strict';
// r490 (F103): page-load trims that keep behaviour. The four side modules
// (sublet PO board, parts ETA, sublet PO attach pilot, key number role) each
// read once at load and again 4 s later. The 4 s retry exists for a page that
// had no session yet; it is now skipped once the first read has succeeded.
// The attach pilot and key-number polls also stop while the tab is hidden;
// coming back to the tab reloads straight away (as before).
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const PROJECT = 'cdsmnqxtyyoeoznmbidd';
const MODULES = [
  { file: 'pdc-sublet-po.js', rpc: 'get_pdc_sublet_po_board_439', body: { vehicles: [] } },
  { file: 'pdc-parts-eta.js', rpc: 'get_pdc_parts_eta_board_v2', body: { vehicles: [], today: '2026-10-23' } },
  { file: 'pdc-sublet-po-attach.js', rpc: 'get_pdc_sublet_po_attach_pilot_445', body: { vehicle_ids: [], can_attach: false } },
  { file: 'pdc-key-number.js', rpc: 'get_pdc_vehicle_key_number_460', body: { ok: true, can_edit: false } },
];
const tick = async (n = 6) => { for (let i = 0; i < n; i++) await new Promise(r => setImmediate(r)); };

function load(mod, { token = 't', fail = false } = {}) {
  const calls = [], timeouts = [], intervals = [], listeners = {};
  const ctx = {
    console, crypto: { randomUUID: () => 'u' },
    setTimeout: (fn, ms) => { timeouts.push({ fn, ms }); return timeouts.length; },
    setInterval: (fn, ms) => { intervals.push({ fn, ms }); return intervals.length; },
    clearInterval: () => {}, clearTimeout: () => {},
    document: { visibilityState: 'visible', head: { appendChild() {} }, createElement: () => ({}), querySelectorAll: () => [], querySelector: () => null,
      addEventListener: (t, f) => { (listeners[t] ||= []).push(f); } },
    fetch: async url => { calls.push(String(url)); if (fail) throw new Error('offline'); return { ok: true, status: 200, text: async () => JSON.stringify(mod.body) }; },
    refreshAllViews() {}, renderAll() {},
  };
  ctx.window = ctx;
  ctx.PDC_SUPABASE_CONFIG = { projectRef: PROJECT, url: `https://${PROJECT}.supabase.co`, publishableKey: 'k' };
  if (token) ctx.__pdcCachedAccessToken = token;
  vm.createContext(ctx);
  vm.runInContext('var app={data:[]};', ctx);
  vm.runInContext(fs.readFileSync(mod.file, 'utf8'), ctx);
  const rpcCalls = () => calls.filter(u => u.endsWith('/rpc/' + mod.rpc)).length;
  const retry = () => timeouts.find(t => t.ms === 4000);
  const poll = () => intervals.find(t => t.ms >= 2 * 60 * 1000);
  return { ctx, calls, rpcCalls, retry, poll, listeners };
}

for (const mod of MODULES) {
  test(`${mod.file}: the 4 s retry does not read again after a successful first read`, async () => {
    const m = load(mod);
    await tick();
    assert.equal(m.rpcCalls(), 1, 'one read at load');
    assert.ok(m.retry(), 'the 4 s retry is still scheduled');
    m.retry().fn();
    await tick();
    assert.equal(m.rpcCalls(), 1, 'no second read 4 s later');
  });

  test(`${mod.file}: with no session at load, the 4 s retry still reads`, async () => {
    const m = load(mod, { token: null });
    await tick();
    assert.equal(m.rpcCalls(), 0, 'no request without a session');
    m.ctx.__pdcCachedAccessToken = 't';
    m.retry().fn();
    await tick();
    assert.equal(m.rpcCalls(), 1, 'the retry picks up the session');
  });

  test(`${mod.file}: a failed first read is retried at 4 s`, async () => {
    const m = load(mod, { fail: true });
    await tick();
    const first = m.rpcCalls();
    assert.ok(first >= 1);
    m.retry().fn();
    await tick();
    assert.ok(m.rpcCalls() > first, 'the retry reads again after a failure');
  });

  test(`${mod.file}: the background poll reads while visible and not while hidden; coming back reads`, async () => {
    const m = load(mod);
    await tick();
    const base = m.rpcCalls();
    m.poll().fn();
    await tick();
    assert.equal(m.rpcCalls(), base + 1, 'visible poll reads');
    m.ctx.document.visibilityState = 'hidden';
    m.poll().fn();
    await tick();
    assert.equal(m.rpcCalls(), base + 1, 'hidden tab: no poll read');
    m.ctx.document.visibilityState = 'visible';
    for (const f of m.listeners.visibilitychange || []) f();
    await tick();
    assert.equal(m.rpcCalls(), base + 2, 'coming back to the tab reads straight away');
  });
}

test('sublet PO attach: coming back to the tab also refreshes the open PO documents', () => {
  const src = fs.readFileSync('pdc-sublet-po-attach.js', 'utf8');
  assert.match(src, /const refreshAll = \(\) => \{ loadPilot\(\); for \(const vid of cache\.keys\(\)\) fetchDocs\(vid\); \};/);
  assert.match(src, /setInterval\(\(\) => \{ if \(document\.visibilityState !== 'hidden'\) refreshAll\(\); \}, 2 \* 60 \* 1000\);/);
  assert.match(src, /addEventListener\('visibilitychange', \(\) => \{ if \(document\.visibilityState === 'visible'\) refreshAll\(\); \}\);/);
});

test('app.js: the 2-minute reference-data safety net skips while hidden and runs once on return', () => {
  const src = fs.readFileSync('app.js', 'utf8');
  const start = src.indexOf('function startWorkshopReferenceDataReconciliationTimer()');
  const end = src.indexOf('const DEFAULT_SUBLET_PROVIDERS');
  assert.ok(start > 0 && end > start);
  const reads = [], listeners = {}; let tick = null;
  const doc = { visibilityState: 'visible', addEventListener: (t, f) => { (listeners[t] ||= []).push(f); } };
  const service = {}; for (const m of ['listTechnicians', 'listSalespeople', 'listSubletProviders', 'listWorkshopBays']) service[m] = () => { reads.push(m); return Promise.resolve(); };
  service.getWorkshopConfiguration = () => { reads.push('config'); return Promise.resolve(); };
  service.unsubscribeAll = () => {};
  const win = { PDC_AUTH_CONTEXT: { role: 'operator' }, __workshopReferenceDataService: service, setInterval: (fn, ms) => { assert.equal(ms, 120000); tick = fn; return 7; }, clearInterval: () => { tick = null; } };
  const ctx = vm.createContext({ window: win, document: doc, workshopReferenceDataRoleCanRead: () => true });
  vm.runInContext(src.slice(start, end), ctx);
  ctx.startWorkshopReferenceDataReconciliationTimer();
  ctx.startWorkshopReferenceDataReconciliationTimer();
  assert.equal((listeners.visibilitychange || []).length, 1, 'one visibility hook');
  tick(); assert.equal(reads.length, 5, 'visible: one full safety-net read');
  doc.visibilityState = 'hidden'; tick(); tick();
  assert.equal(reads.length, 5, 'hidden: no reads');
  listeners.visibilitychange[0](); assert.equal(reads.length, 5, 'still hidden: nothing');
  doc.visibilityState = 'visible'; listeners.visibilitychange[0]();
  assert.equal(reads.length, 10, 'back to visible: one catch-up read');
  listeners.visibilitychange[0](); assert.equal(reads.length, 10, 'no second catch-up');
  doc.visibilityState = 'hidden'; listeners.visibilitychange[0](); doc.visibilityState = 'visible'; listeners.visibilitychange[0]();
  assert.equal(reads.length, 10, 'a short hide with no skipped tick reads nothing extra');
  ctx.stopWorkshopReferenceDataReconciliationTimer();
  assert.equal(win.__workshopReferenceDataReconcileTimer, null);
});

test('cache bust: r490 on the four module srcs and on canonical-entry.js; FAULT_LOG F103', () => {
  const entry = fs.readFileSync('canonical-entry.js', 'utf8');
  for (const file of ['pdc-sublet-po.js', 'pdc-parts-eta.js', 'pdc-sublet-po-attach.js', 'pdc-key-number.js']) {
    assert.match(entry, new RegExp(`'${file.replace(/[.]/g, '\\.')}\\?[^']*&r490=2026\\.10\\.23\\.r490(&r494=2026\\.10\\.23\\.r494[bc]?)?(&r575=2026\\.10\\.27\\.r575)?(&r616=2026\\.10\\.28\\.r616)?(&r747=2026\\.10\\.30\\.r747)?(&r751=2026\\.10\\.30\\.r751)?'`), file); // r494 (F107) appends its own token to pdc-sublet-po.js; r575 (F189) appends its tag to pdc-key-number.js
  }
  assert.match(fs.readFileSync('index.html', 'utf8'), /canonical-entry\.js\?[^"]*&amp;r490=2026\.10\.23\.r490&amp;/);
  assert.match(fs.readFileSync('index.html', 'utf8'), /<script src="app\.js\?[^"]*&amp;r490=2026\.10\.23\.r490&amp;/);
  assert.match(fs.readFileSync('docs/FAULT_LOG.md', 'utf8'), /\n\| F103 \| \d+ Oct [0-9:]+ \|[^\n]*r490/);
});
