// r436 (F47): parts ETA chip beside the parts location on board rows; RPC contract present in the migration.
const test = require('node:test'), assert = require('node:assert/strict'), fs = require('node:fs'), vm = require('node:vm'), path = require('node:path');
const eta = require('./pdc-parts-eta.js');
const board = { today: '2026-10-21', vehicles: [
  { vehicle_id: '11111111-2222-4333-8444-555555555555', stock_number: 'S1', latest_eta: '2026-10-28', count: 2, overdue_count: 0,
    parts: [{ part: 'Driveshaft uni joint', eta_date: '2026-10-28', bay: 'P-12', line_no: 3, ro: 'J1' }, { part: 'Bolt <kit>', eta_date: '2026-10-22', bay: null, line_no: null, ro: 'J1' }] },
  { vehicle_id: '66666666-2222-4333-8444-555555555555', stock_number: 's2', latest_eta: '2026-10-25', count: 2, overdue_count: 1,
    parts: [{ part: 'Mirror', eta_date: '2026-10-25' }, { part: 'Clip', eta_date: '2026-10-19' }] },
  { vehicle_id: '77777777-2222-4333-8444-555555555555', stock_number: 'S3', latest_eta: '2026-10-21', count: 1, parts: [{ part: 'Seal', eta_date: '2026-10-21' }] } ] };
const idx = eta.indexBoard(board);
test('latest ETA plus a count, part names on hover, Perth dd/mm', () => {
  const s = eta.summarise(eta.entryFor(idx, { __emailVehicleId: '11111111-2222-4333-8444-555555555555' }), idx.today);
  assert.equal(s.label, 'Parts ETA 28/10 · 7 days · 2 parts'); assert.equal(s.state, 'ok'); // r475 (F88) adds the days countdown
  assert.match(s.title, /Driveshaft uni joint: 28\/10\/26 · line 3 · R\/O J1 · bay P-12/); assert.match(s.title, /Bolt <kit>: 22\/10\/26/);
});
test('overdue (before today, Perth) is red, due today amber, single part has no count', () => {
  const over = eta.summarise(eta.entryFor(idx, { stock: 'S2' }), idx.today);
  assert.equal(over.state, 'overdue'); assert.equal(over.overdue, 1); assert.match(over.title, /Clip: 19\/10\/26 · OVERDUE/);
  const due = eta.summarise(eta.entryFor(idx, { id: '77777777-2222-4333-8444-555555555555' }), idx.today);
  assert.equal(due.state, 'due'); assert.equal(due.label, 'Parts ETA 21/10 · today'); // r475 countdown
  assert.match(eta.chipHtml(over), /class="pdc-parts-eta pdc-parts-eta-overdue"/);
});
test('chip sits beside the parts location, or at the right of the vehicle name without one; escaped; idempotent', () => {
  const s = eta.summarise(eta.entryFor(idx, { stock: 's1' }), idx.today);
  const withLoc = '<span class="incoming-card-main"><strong>Hilux</strong><span class="tune-parts-location" title="x">05C1A</span></span><div class="incoming-vehicle-detail-grid">';
  const out = eta.decorateRow(withLoc, s);
  assert.match(out, /<span class="pdc-parts-eta-wrap"><span class="tune-parts-location" title="x">05C1A<\/span><span class="pdc-parts-eta pdc-parts-eta-ok"/);
  assert.match(out, /Bolt &lt;kit&gt;/); assert.doesNotMatch(out, /Bolt <kit>/);
  assert.equal(eta.decorateRow(out, s), out);
  const noLoc = eta.decorateRow('<span class="incoming-card-main"><strong>Hilux</strong></span>', s);
  assert.match(noLoc, /<strong>Hilux<\/strong><span class="pdc-parts-eta-wrap"><span class="pdc-parts-eta /);
  assert.equal(eta.decorateRow(withLoc, null), withLoc);
  assert.equal(eta.entryFor(idx, { stock: 'NOPE' }), null);
});
test('browser wrapper decorates board rows only after the ETAs load; no request without a session', async () => {
  const calls = []; let refreshed = 0;
  const ctx = { window: { PDC_SUPABASE_CONFIG: { projectRef: 'cdsmnqxtyyoeoznmbidd', url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co', publishableKey: 'k' } },
    document: { visibilityState: 'visible', createElement: () => ({}), head: { appendChild: () => {} }, addEventListener: () => {} },
    setInterval: () => 0, clearInterval: () => {}, setTimeout: () => 0, refreshAllViews: () => { refreshed++; },
    fetch: async (url, init) => { calls.push({ url, init }); return { ok: true, text: async () => JSON.stringify(board) }; },
    incomingVehicleDetailRow: () => '<span class="incoming-card-main"><strong>Hilux</strong></span><div class="incoming-vehicle-detail-grid">' };
  ctx.window.document = ctx.document;
  vm.runInNewContext(fs.readFileSync(require.resolve('./pdc-parts-eta.js'), 'utf8'), ctx);
  await new Promise(r => setImmediate(r));
  assert.equal(calls.length, 0, 'no session token, no request');
  assert.doesNotMatch(ctx.incomingVehicleDetailRow({ stock: 'S1' }), /pdc-parts-eta/);
  ctx.window.__pdcCachedAccessToken = 't';
  ctx.__pdcCachedAccessToken = 't';
  const ctx2 = { ...ctx, window: { ...ctx.window, __pdcCachedAccessToken: 't', PDC_PARTS_ETA_VERSION: undefined } };
  ctx2.incomingVehicleDetailRow = () => '<span class="incoming-card-main"><strong>Hilux</strong></span><div class="incoming-vehicle-detail-grid">';
  vm.runInNewContext(fs.readFileSync(require.resolve('./pdc-parts-eta.js'), 'utf8'), ctx2);
  for (let i = 0; i < 5; i++) await new Promise(r => setImmediate(r));
  assert.equal(calls.length, 1); assert.match(calls[0].url, /\/rest\/v1\/rpc\/get_pdc_parts_eta_board(_v2)?$/); assert.equal(calls[0].init.headers.Authorization, 'Bearer t'); // r475 reads v2 first (falls back to this read)
  assert.equal(refreshed, 1);
  const row = ctx2.incomingVehicleDetailRow({ stock: 'S1' });
  assert.match(row, /Parts ETA <\/span>28\/10 · [^<]+ · 2 parts/); assert.match(row, /pdc-parts-eta-detail/); // r475: label span + countdown
  assert.doesNotMatch(ctx2.incomingVehicleDetailRow({ stock: 'NONE' }), /pdc-parts-eta/);
});
test('loader, cache bust and Pages build include the parts ETA script', () => {
  const entry = fs.readFileSync('canonical-entry.js', 'utf8');
  assert.match(entry, /pdc-parts-eta\.js\?parts-eta=2026\.10\.21\.r436/);
  assert.match(entry, /serviceLocations\.onload = loadPartsEta;/); assert.match(entry, /serviceLocations\.onerror = loadPartsEta;/);
  assert.match(fs.readFileSync('index.html', 'utf8'), /canonical-entry\.js\?[^"]*parts-eta=2026\.10\.21\.r436/);
  assert.match(fs.readFileSync('scripts/build_pages_runtime.js', 'utf8'), /'pdc-service-locations\.js', 'pdc-parts-eta\.js'/);
});
test('migration: importer-gated set_parts_eta contract, allowlist table, RLS read-only, undo present', () => {
  const dir = 'supabase/migrations', name = fs.readdirSync(dir).find(f => /_r436_parts_eta\.sql$/.test(f));
  assert.ok(name, 'r436 migration present');
  const sql = fs.readFileSync(path.join(dir, name), 'utf8');
  assert.match(sql, /CREATE FUNCTION public\.set_parts_eta\(p_stock text, p_ro text, p_line_no integer DEFAULT NULL, p_part text DEFAULT NULL, p_eta_date date DEFAULT NULL,\s+p_bay text DEFAULT NULL, p_notes text DEFAULT NULL, p_source_message_id text DEFAULT NULL, p_sender text DEFAULT NULL,\s+p_dry_run boolean DEFAULT false, p_message_at timestamptz DEFAULT NULL\)/);
  assert.match(sql, /v_role IN \('importer','operator','administrator'\)/);
  for (const s of ['applied', 'replaced', 'stale', 'duplicate', 'unmatched', 'ambiguous', 'rejected_sender', 'invalid']) assert.match(sql, new RegExp(`'${s}'`));
  assert.match(sql, /\('broometoyota\.com\.au',true/); assert.match(sql, /\('pmgwa\.com\.au',true/);
  assert.match(sql, /d\.active AND d\.domain=v_domain/);
  assert.match(sql, /REVOKE ALL ON public\.pdc_parts_eta, public\.pdc_parts_eta_sender_domains, public\.pdc_parts_eta_audit FROM PUBLIC, anon, authenticated;/);
  assert.match(sql, /GRANT SELECT ON public\.pdc_parts_eta, public\.pdc_parts_eta_sender_domains, public\.pdc_parts_eta_audit TO authenticated;/);
  assert.doesNotMatch(sql, /CREATE POLICY[^;]*FOR (INSERT|UPDATE|DELETE|ALL)/);
  assert.match(sql, /'parts_eta_rpc_contract','F47'/);
  assert.doesNotMatch(sql, /CREATE OR REPLACE FUNCTION public\.workshop_clock_tick/);
  assert.ok(fs.existsSync(path.join('supabase/rollbacks', name.replace(/\.sql$/, '.down.sql'))));
});
