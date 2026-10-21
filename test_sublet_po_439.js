// r439 (F50): sublet POs. No line changes category, bay or booking. Each line with a GP PO shows its PO and a 'sublet done'
// tick; the Sublet box is orange while a GP PO exists and not all those lines are ticked, green when all are, neutral without.
const test = require('node:test'), assert = require('node:assert/strict'), fs = require('node:fs'), vm = require('node:vm'), path = require('node:path');
const po = require('./pdc-sublet-po.js');
const V1 = '11111111-2222-4333-8444-555555555555', V2 = '66666666-2222-4333-8444-555555555555';
const board = { ok: true, vehicles: [
  { vehicle_id: V1, stock_number: 'S1', state: 'ordered', total: 3, ticked: 1, with_po: 3 },
  { vehicle_id: V2, stock_number: 's2', state: 'done', total: 2, ticked: 2, with_po: 2 } ] };
const idx = po.indexBoard(board);
const strip = (cls = 'is-required', marker = '●', tag = 'span') => `<div class="incoming-work-checks pdc-station-strip"><span class="incoming-work-check pdc-station-parts is-required" title="Parts" aria-label="Parts required"><span class="incoming-work-box" aria-hidden="true">●</span><span class="incoming-work-label">Parts</span></span><${tag} class="incoming-work-check pdc-station-sublet ${cls}" title="Sublet required" aria-label="Sublet required">
      <span class="incoming-work-box" aria-hidden="true">${marker}</span>
      <span class="incoming-work-label">Sublet</span>
    </${tag}></div>`;
test('Sublet box: orange with a GP PO and not all ticked; green when all ticked; neutral (unchanged) without a GP PO', () => {
  const ordered = po.decorateStrip(strip('is-not-required', '—'), po.entryFor(idx, { id: V1 }));
  assert.match(ordered, /class="incoming-work-check pdc-station-sublet pdc-sublet-po-box is-required is-ordered"/);
  assert.match(ordered, /<span class="incoming-work-box" aria-hidden="true">!<\/span>/);
  assert.match(ordered, /Sublet <small class="pdc-sublet-po-count">1\/3<\/small>/);
  assert.match(ordered, /title="Sublet: 3 lines with a GP PO, 1 of 3 ticked sublet done"/);
  assert.match(ordered, /pdc-station-parts is-required/, 'other boxes untouched');
  assert.equal(po.decorateStrip(ordered, po.entryFor(idx, { id: V1 })), ordered, 'idempotent');
  const done = po.decorateStrip(strip('is-ordered', '!'), po.entryFor(idx, { stock: 'S2' }));
  assert.match(done, /pdc-station-sublet pdc-sublet-po-box is-complete"/); assert.doesNotMatch(done, /pdc-station-sublet[^"]*is-ordered/);
  assert.match(done, /aria-hidden="true">✓<\/span>/); assert.match(done, /2\/2/);
  for (const cls of ['is-required', 'is-not-required', 'is-booked']) assert.equal(po.decorateStrip(strip(cls), po.entryFor(idx, { stock: 'NOPE' })), strip(cls), 'no GP PO: neutral');
  assert.equal(po.boxState({ state: 'none', total: 0 }), null);
  const already = po.decorateStrip(strip('is-complete', '✓'), po.entryFor(idx, { id: V1 }));
  assert.match(already, /pdc-station-sublet is-complete pdc-sublet-po-box"/, 'a Sublet already complete on the board stays green');
  const button = po.decorateStrip(strip('is-required', '●', 'button'), po.entryFor(idx, { id: V1 }));
  assert.match(button, /<button class="incoming-work-check pdc-station-sublet pdc-sublet-po-box is-required is-ordered"[^>]*>[\s\S]*<\/button>/);
});
test('drop-down: GP PO lines in any category with PO chip, status and sublet done tick; read only without can_tick; escaped', () => {
  const lines = [
    { line_key: 'jc:J139000001:3', job_card_number: 'J139000001', line_no: 3, description: 'Tint <front>', category: 'TINT', po_numbers: ['GP13900001'], ticked: false, version: 0, tickable: true },
    { line_key: 'jc:J139000001:4', job_card_number: 'J139000001', line_no: 4, description: 'Canopy', category: 'FITTING', po_numbers: ['GP13900002'], ticked: true, ticked_by_email: 'a@example.invalid', ticked_at: '2026-10-21T06:00:00Z', version: 1, tickable: true },
    { line_key: 'jc:J139000001:5', job_card_number: 'J139000001', line_no: 5, description: 'Wrap', category: 'SUBLET', po_numbers: ['GP13900003'], ticked: false, completed: true, version: 0, tickable: true } ];
  const html = po.linesHtml({ ok: true, can_tick: true, total: 3, ticked: 1, lines });
  assert.match(html, /<b>Sublet POs<\/b><small>1 of 3 ticked sublet done<\/small>/); assert.doesNotMatch(html, /read only/);
  assert.match(html, /<th>Category<\/th>/); assert.match(html, /<td>TINT<\/td>/); assert.match(html, /<td>FITTING<\/td>/);
  assert.match(html, /<span class="pdc-sublet-po-chip">GP13900001<\/span>/); assert.match(html, /Tint &lt;front&gt;/); assert.doesNotMatch(html, /Tint <front>/);
  assert.match(html, /is-ordered" data-line-key="jc:J139000001:3" data-version="0"[\s\S]*?>Ordered<\/span>/);
  assert.match(html, /is-done" data-line-key="jc:J139000001:4" data-version="1"[\s\S]*?Sublet done<\/span>[\s\S]*?checked[\s\S]*?21\/10, 14:00/);
  assert.match(html, /Ordered · line completed/);
  assert.doesNotMatch(html, /disabled|No PO|booking/);
  const ro = po.linesHtml({ ok: true, can_tick: false, total: 3, ticked: 1, lines });
  assert.equal((ro.match(/ disabled/g) || []).length, 3); assert.match(ro, /read only/);
  assert.match(po.linesHtml({ ok: true, lines: [] }), /No GP PO lines/); assert.match(po.linesHtml(null), /could not be loaded/);
});
test('drop-down section only for vehicles with a GP PO line', () => {
  const row = '<details class="incoming-vehicle-card"><div class="incoming-vehicle-detail-grid"></div></details>';
  const withPo = po.decorateDetail(row, V1, po.entryFor(idx, { id: V1 }));
  assert.match(withPo, new RegExp(`data-pdc-sublet-vehicle="${V1}"`));
  assert.equal(po.decorateDetail(withPo, V1, {}), withPo, 'idempotent');
  assert.equal(po.decorateDetail(row + strip(), V2, null), row + strip(), 'Sublet required but no GP PO: unchanged');
  assert.equal(po.decorateDetail(row, 'not-a-uuid', {}), row);
});
test('browser wrapper: no request without a session; board RPC then decorated strip and drop-down', async () => {
  const calls = [];
  const mk = token => {
    const listeners = {};
    const ctx = { window: { PDC_SUPABASE_CONFIG: { projectRef: 'cdsmnqxtyyoeoznmbidd', url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co', publishableKey: 'k' }, __pdcCachedAccessToken: token },
      document: { visibilityState: 'visible', createElement: () => ({}), head: { appendChild: () => {} }, addEventListener: (n, f) => { listeners[n] = f; } },
      setInterval: () => 0, clearInterval: () => {}, setTimeout: () => 0, renderAll: () => { ctx.rendered = (ctx.rendered || 0) + 1; },
      fetch: async (url, init) => { calls.push({ url, init }); return { ok: true, text: async () => JSON.stringify(board) }; },
      incomingWorkChecklistHtml: () => strip(),
      incomingVehicleDetailRow: () => '<details class="incoming-vehicle-card"><div class="incoming-vehicle-detail-grid"></div></details>' };
    ctx.window.document = ctx.document; ctx.__pdcCachedAccessToken = token; ctx.listeners = listeners;
    return ctx;
  };
  const a = mk(undefined);
  vm.runInNewContext(fs.readFileSync(require.resolve('./pdc-sublet-po.js'), 'utf8'), a);
  await new Promise(r => setImmediate(r));
  assert.equal(calls.length, 0);
  const b = mk('t');
  vm.runInNewContext(fs.readFileSync(require.resolve('./pdc-sublet-po.js'), 'utf8'), b);
  for (let i = 0; i < 5; i++) await new Promise(r => setImmediate(r));
  assert.equal(calls.length, 1); assert.match(calls[0].url, /\/rest\/v1\/rpc\/get_pdc_sublet_po_board_439$/); assert.equal(calls[0].init.headers.Authorization, 'Bearer t');
  assert.equal(b.rendered, 1);
  assert.match(b.incomingWorkChecklistHtml({ id: V1 }), /is-ordered/);
  assert.match(b.incomingVehicleDetailRow({ id: V1 }), /pdc-sublet-po-detail/);
  assert.equal(typeof b.listeners.toggle, 'function'); assert.equal(typeof b.listeners.change, 'function');
});
test('loader, cache bust and Pages build include the sublet PO script', () => {
  assert.match(fs.readFileSync('canonical-entry.js', 'utf8'), /pdc-sublet-po\.js\?sublet-po=2026\.10\.21\.r439/);
  assert.match(fs.readFileSync('index.html', 'utf8'), /canonical-entry\.js\?[^"]*sublet-po=2026\.10\.21\.r439/);
  assert.match(fs.readFileSync('scripts/build_pages_runtime.js', 'utf8'), /'pdc-parts-eta\.js', 'pdc-sublet-po\.js'/);
});
test('migration: PO refs only, no category/bay/booking change; tick needs a GP PO; audited PO-only import; undo', () => {
  const dir = 'supabase/migrations', name = fs.readdirSync(dir).find(f => /_r439_sublet_po_refs_and_ticks\.sql$/.test(f));
  assert.ok(name, 'r439 migration present');
  assert.ok(!fs.readdirSync(dir).some(f => /r439_sublet_po_category_and_ticks/.test(f)), 'the withdrawn category-move version is not in the repo');
  const sql = fs.readFileSync(path.join(dir, name), 'utf8');
  assert.doesNotMatch(sql, /FUNCTION public\.pdc_qc_operation_lines_379_uncached|FUNCTION pdc_work_categories_private\.sublet_po_override_439|category_before_sublet_po/, 'QC lines untouched');
  assert.match(sql, /CREATE FUNCTION public\.import_sublet_pos_439\(p_rows jsonb, p_source_file_sha256 text, p_dry_run boolean DEFAULT true\) RETURNS jsonb/);
  assert.match(sql, /IF v_role IN \('importer','operator','administrator'\) THEN/);
  assert.match(sql, /GRANT EXECUTE ON FUNCTION [^;]*public\.import_sublet_pos_439\(jsonb,text,boolean\) TO authenticated, service_role;/);
  for (const k of ['skipped_owner_hold', 'skipped_job_closed', 'skipped_vehicle_rft', 'skipped_vehicle_completed', 'skipped_line_completed', 'attached', 'already_attached']) assert.ok(sql.includes(`'${k}'`), k);
  for (const k of ['created_vehicles', 'created_jobs', 'created_lines', 'category_changes', 'booking_changes']) assert.ok(sql.includes(`'${k}',0`), k);
  assert.match(sql, /PDC_439_LINE_HAS_NO_GP_PO/);
  assert.match(sql, /po_number ~ '\^GP\[0-9\]\{8\}\$'/);
  assert.match(sql, /r\.role::text IN \('operator','administrator','fitter'\)/);
  for (const c of ['Company', 'Description of sublet', 'Division', 'Document Line', 'Job #', 'PO #', 'Sublet Line']) assert.ok(sql.includes(`"${c}"`) || sql.includes(`'${c}'`), c);
  assert.match(sql, /revolution_service_headers_439\(p_provenance->'source_headers','\["Type","Dept","Stock #"/);
  assert.match(sql, /REVOKE ALL ON public\.pdc_service_line_po_refs_439, public\.pdc_sublet_line_ticks_439, public\.pdc_sublet_line_tick_history_439,\s+public\.pdc_sublet_po_import_receipts_439 FROM PUBLIC, anon, authenticated;/);
  assert.doesNotMatch(sql, /CREATE POLICY/);
  assert.match(sql, /'sublet_po_category_and_ticks','F50'/); assert.match(sql, /,true,239,'r439'\)/);
  assert.match(sql, /PERFORM public\.audit_pdc_event\('update','pdc_sublet_line_ticks_439'/);
  assert.match(sql, /audit_pdc_event\('update','pdc_service_line_po_refs_439'/);
  assert.doesNotMatch(sql, /CREATE OR REPLACE FUNCTION public\.workshop_clock_tick|workshop_clock_next_minute|workshop_clock_plan/);
  assert.doesNotMatch(sql, /\b1[23]\d{6}\b(?![0-9a-f-])/, 'no live stock numbers');
  const down = fs.readFileSync(path.join('supabase/rollbacks', name.replace(/\.sql$/, '.down.sql')), 'utf8');
  assert.match(down, /DROP TABLE public\.pdc_service_line_po_refs_439;/); assert.match(down, /release='r439'/);
});
