'use strict';
// r494c (F107b, Craig 22 Oct: 'now the website is extremely slow'): the board's 'PO to raise' must not call
// get_pdc_sublet_lines_439 per vehicle or redraw the whole board per answer. Fictional data only.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const N = 200;
const U = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
// Every vehicle has two open whole line sublets; even vehicles also have a GP PO (a board entry), odd ones none.
const vehicles = Array.from({ length: N }, (_, i) => ({ id: U(i + 1), stock: `T${String(i + 1).padStart(4, '0')}`,
  pdcQcOperationLinesProjectionPresent: true,
  pdcQcOperationLines: [
    { lineIdentity: `source:${U(10000 + i * 2)}`, stageCode: 'SUBLET', active: true, completed: false },
    { lineIdentity: `source:${U(10001 + i * 2)}`, stageCode: 'SUBLET', active: true, completed: false },
    { lineIdentity: `source:${U(90000 + i)}`, stageCode: 'FITTING', active: true, completed: false }] }));
const board = { ok: true, vehicles: vehicles.filter((_, i) => i % 2 === 0)
  .map(v => ({ vehicle_id: v.id, stock_number: v.stock, state: 'ordered', total: 1, ticked: 0, with_po: 1 })) };
const lines = vid => ({ ok: true, can_tick: true, vehicle_id: vid, lines: [{ line_key: 'jc:J1:1', line_identity: `source:${U(10000)}`, operation_no: '1', category: 'SUBLET', po_numbers: ['GP900001'], has_po: true, ticked: false, version: 0 }] });
const strip = '<span class="incoming-work-check pdc-station-sublet is-required" title="Sublet" aria-label="Sublet"><span class="incoming-work-box">○</span><span class="incoming-work-label">SUB</span></span>';

function harness() {
  const calls = [], timers = [];
  const ctx = {
    window: { PDC_SUPABASE_CONFIG: { projectRef: 'cdsmnqxtyyoeoznmbidd', url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co', publishableKey: 'k' }, __pdcCachedAccessToken: 't' },
    document: { visibilityState: 'visible', createElement: () => ({}), head: { appendChild: () => {} }, querySelectorAll: () => [], addEventListener: () => {} },
    setInterval: () => 0, clearInterval: () => {}, setTimeout: (f, ms) => { timers.push({ f, ms }); return timers.length; }, rendered: 0,
    fetch: async (url, init) => { calls.push(url); const vid = JSON.parse(init.body || '{}').p_vehicle_id; return { ok: true, text: async () => JSON.stringify(/sublet_lines/.test(url) ? lines(vid) : board) }; },
    incomingWorkChecklistHtml: () => strip,
  };
  ctx.renderAll = () => { ctx.rendered += 1; for (const v of vehicles) ctx.incomingWorkChecklistHtml(v); };
  ctx.window.document = ctx.document;
  vm.runInNewContext(fs.readFileSync(require.resolve('./pdc-sublet-po.js'), 'utf8'), ctx);
  const flush = async () => { for (let i = 0; i < 20; i++) await new Promise(r => setImmediate(r)); };
  const runTimers = () => { const due = timers.splice(0).filter(t => t.ms < 4000); due.forEach(t => t.f()); return due.length; };
  return { ctx, calls, timers, flush, runTimers, lineCalls: () => calls.filter(u => /get_pdc_sublet_lines_439$/.test(u)).length };
}

test(`board render with ${N} vehicles with Sublet jobs: zero get_pdc_sublet_lines_439 calls and at most one board redraw`, async () => {
  const h = harness();
  await h.flush();
  assert.equal(h.calls.length, 1, 'only the one board call'); assert.match(h.calls[0], /get_pdc_sublet_po_board_439$/);
  assert.equal(h.ctx.rendered, 1, 'one redraw for the board answer');
  for (let pass = 0; pass < 3; pass++) {
    const html = vehicles.map(v => h.ctx.incomingWorkChecklistHtml(v));
    await h.flush(); h.runTimers(); await h.flush();
    assert.equal(h.lineCalls(), 0, 'no per-vehicle GP PO line calls while the board renders');
    assert.equal(h.ctx.rendered, 1, 'no extra board redraws');
    // odd vehicles have no GP PO at all: both Sublet lines need one; even ones: 2 Sublet lines, 1 GP PO line -> at least 1
    assert.equal(html.filter(s => /is-po-to-raise/.test(s)).length, N, 'every vehicle shows PO to raise');
    assert.match(html[1], /PO to raise: 2 whole line sublets have no GP PO yet/);
    assert.match(html[0], /PO to raise: 1 whole line sublet has no GP PO yet/);
  }
});

test('lazy: lines load only when a vehicle is opened; one debounced redraw only if its count changes, and no loop', async () => {
  const h = harness();
  await h.flush();
  vehicles.forEach(v => h.ctx.incomingWorkChecklistHtml(v));
  const api = h.ctx.window.PDC_SUBLET_PO;
  // Opening vehicle 1 (index 0): its lines show line 1 has the PO, so 1 to raise = same as the board's lower bound.
  await api.fetch(vehicles[0].id); await h.flush();
  assert.equal(h.lineCalls(), 1);
  assert.equal(h.runTimers(), 0, 'count unchanged: no redraw');
  // Opening vehicle 3 (index 2) with a payload saying no Sublet line has a PO: count 1 -> 2, one redraw, then stable.
  const before = h.ctx.rendered;
  await api.fetch(vehicles[2].id); await api.fetch(vehicles[4].id); await h.flush();
  assert.equal(h.lineCalls(), 3);
  assert.equal(h.runTimers(), 1, 'two answers, one debounced redraw');
  await h.flush();
  assert.equal(h.ctx.rendered, before + 1);
  assert.match(h.ctx.incomingWorkChecklistHtml(vehicles[2]), /PO to raise: 2 whole line sublets/);
  assert.equal(h.runTimers(), 0, 'the redraw does not schedule another');
  assert.equal(h.lineCalls(), 3, 'the redraw makes no calls');
});

test('source: no fetch from the board strip, debounced single redraw', () => {
  const src = fs.readFileSync('pdc-sublet-po.js', 'utf8');
  const raise = src.slice(src.indexOf('const raiseFor = '), src.indexOf('let redrawTimer'));
  assert.doesNotMatch(raise, /fetchLines|rpc\(|rerender/);
  assert.match(src, /redrawTimer = setTimeout\(\(\) => \{ redrawTimer = 0; rerender\(\); \}, 250\);/);
});
