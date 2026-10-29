'use strict';
// r714 (F324): page overlay while something the user did is saving or loading.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { createDocument } = require('./qa/mini-dom-496.cjs');
const CODE = fs.readFileSync('pdc-busy-overlay.js', 'utf8');
const busy = require('./pdc-busy-overlay.js');

test('labels: saves, uploads and reads', () => {
  assert.equal(busy.classify('https://x.supabase.co/rest/v1/rpc/set_vehicle_work_category', 'POST'), 'Saving…');
  assert.equal(busy.classify('https://x.supabase.co/rest/v1/rpc/get_vehicle_workshop_detail_scoped', 'POST'), 'Loading…');
  assert.equal(busy.classify('https://x.supabase.co/storage/v1/object/b/p.jpg', 'POST'), 'Uploading…');
  assert.equal(busy.isBoardRequest('https://abc.supabase.co/rest/v1/rpc/x', 'https://abc.supabase.co'), true);
  assert.equal(busy.isBoardRequest('https://pmgpdc.au/version.json', 'https://abc.supabase.co'), false);
});

function page() {
  const doc = createDocument();
  let t = 0; const timers = []; const listeners = {};
  doc.addEventListener = (type, fn) => { (listeners[type] = listeners[type] || []).push(fn); };
  const fire = type => (listeners[type] || []).forEach(fn => fn({ type, key: 'Enter' }));
  const resolvers = [];
  const win = {
    document: doc, performance: { now: () => t },
    PDC_SUPABASE_CONFIG: { url: 'https://abc.supabase.co' },
    fetch: () => new Promise(resolve => resolvers.push(resolve)),
    setTimeout: (fn, ms) => { const id = timers.length; timers.push({ at: t + ms, fn, done: false }); return id; },
    clearTimeout: id => { if (timers[id]) timers[id].done = true; },
  };
  win.window = win;
  const advance = async ms => { t += ms; for (const timer of timers) if (!timer.done && timer.at <= t) { timer.done = true; timer.fn(); } await new Promise(r => setImmediate(r)); };
  vm.runInNewContext(CODE, { window: win, setTimeout: win.setTimeout, clearTimeout: win.clearTimeout, Promise, Date, String, Math, Object });
  const overlay = () => doc.getElementById('pdc-busy');
  return { win, fire, advance, resolvers, overlay, settle: async () => { resolvers.splice(0).forEach(r => r({ ok: true })); for (let i = 0; i < 4; i += 1) await new Promise(r => setImmediate(r)); } };
}

test('a slow save after a drop shows the overlay after 400 ms and clears when done', async () => {
  const p = page();
  p.fire('drop');
  const request = p.win.fetch('https://abc.supabase.co/rest/v1/rpc/administrator_move_workshop_booking', { method: 'POST' });
  await p.advance(300);
  assert.ok(!p.overlay() || !p.overlay().classList.contains('is-on'), 'nothing before 400 ms');
  await p.advance(200);
  assert.equal(p.overlay().classList.contains('is-on'), true);
  assert.equal(p.overlay().querySelector('.pdc-busy-text').textContent, 'Saving…');
  await p.settle(); await request;
  await p.advance(200);
  assert.equal(p.overlay().classList.contains('is-on'), false);
});

test('background requests with no user action never show it; a fast save shows nothing', async () => {
  const p = page();
  p.win.fetch('https://abc.supabase.co/rest/v1/rpc/get_pdc_email_vehicle_board_snapshot', { method: 'POST' });
  await p.advance(1000);
  assert.equal(p.overlay(), null, 'background read: no overlay');
  await p.settle();
  p.fire('click');
  p.win.fetch('https://abc.supabase.co/rest/v1/rpc/set_panel_line_completion_565', { method: 'POST' });
  await p.advance(100); await p.settle(); await p.advance(500);
  assert.equal(p.overlay(), null, 'fast save: no flicker');
});

test('after 25 seconds it steps aside and stops blocking the page', async () => {
  const p = page();
  p.fire('click');
  p.win.fetch('https://abc.supabase.co/rest/v1/rpc/finalize_pdc_qc_to_rft_399', { method: 'POST' });
  await p.advance(500);
  assert.equal(p.overlay().classList.contains('is-on'), true);
  await p.advance(25000);
  assert.equal(p.overlay().classList.contains('is-aside'), true);
  assert.equal(p.overlay().querySelector('.pdc-busy-text').textContent, 'Still working…');
});

test('loads first after pdc-auto-reload.js and ships in the runtime', () => {
  const html = fs.readFileSync('index.html', 'utf8');
  assert.ok(html.indexOf('pdc-auto-reload.js') < html.indexOf('pdc-busy-overlay.js?v=2026.10.29.r714'));
  assert.ok(html.indexOf('pdc-busy-overlay.js') < html.indexOf('pdc-deferred-script-order.js'));
  assert.ok(require('./scripts/build_pages_runtime.js').RUNTIME_FILES.includes('pdc-busy-overlay.js'));
});

test('r726 (F336): background calls and the Stock take page never raise the overlay', () => {
  const o = require('./pdc-busy-overlay.js');
  const u = 'https://x.supabase.co/rest/v1/rpc/';
  assert.equal(o.quiet(u + 'record_pdc_usage_20260914', 'dashboard'), true);
  assert.equal(o.quiet(u + 'record_pdc_login', 'dashboard'), true);
  assert.equal(o.quiet(u + 'get_pdc_stock_take_rev_720', 'dashboard'), true);
  assert.equal(o.quiet(u + 'set_panel_line_completion_565', 'stock-take'), true);
  assert.equal(o.quiet(u + 'set_panel_line_completion_565', 'dashboard'), false, 'a real save elsewhere still shows it');
});
