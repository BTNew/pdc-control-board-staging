// r439 (F50): sublet POs. No line changes category, bay or booking. Each line with a GP PO shows its PO and a 'sublet done'
// tick inline on its own line (r439b); the Sublet box is orange while a GP PO exists and not all those lines are ticked, green when all are, neutral without.
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
// r439b: the PO chip and tick sit inline on each line inside the existing category boxes, rendered by the real app.js summary.
const appSource = fs.readFileSync('app.js', 'utf8');
function summary(lines) {
  const context = vm.createContext({ app: { vehicleWorkshopDetailCache: new Map([['synthetic', { status: 'ready', detail: { vehicle_version: 2, job_card_lines: lines } }]]) },
    cleanNavisionText: x => String(x ?? '').trim(), vehicleWorkshopDetailCanonicalId: () => 'synthetic', vehicleKey: () => 'synthetic',
    escapeHtml: x => String(x ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;'),
    vehicleWorkshopLineIdentity: (_s, l) => `source:${l.operation_line_id}`, vehicleWorkshopStageCode: s => String(s).toUpperCase() });
  vm.runInContext(appSource.slice(appSource.indexOf('function authenticatedOperationLineValid('), appSource.indexOf('function refreshAuthenticatedOperationSummaryRow(')), context);
  return context;
}
const S = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const jc = (n, cat, stage, desc, hours = 0) => ({ line_identity: `source:${S(n)}`, source_line_id: S(n), operation_no: `PD${String(n).padStart(3, '0')}-ABCDEF01`,
  description: desc, source_kind: 'authenticated', department: '139', active: true, work_category: cat, stage_code: stage, estimated_hours: hours });
const jobLines = [jc(12, 'SUBLET', 'SUBLET', 'MMT CLOTH SEAT COVERS 2 ROWS'), jc(13, 'SUBLET', 'SUBLET', 'Wheel alignment <sublet>'),
  jc(3, 'TINT', 'TINT', 'Tint front', 1), jc(4, 'FITTING', 'FITTING', 'Canopy', 2.5), jc(5, 'FITTING', 'FITTING', 'Towbar', 1)];
const poPayload = (canTick = true) => ({ ok: true, can_tick: canTick, vehicle_id: V1, total: 3, ticked: 1, lines: [
  { line_key: 'jc:J139000001:12', line_identity: `source:${S(12)}`, operation_no: 'PD012-ABCDEF01', line_no: 12, description: 'MMT CLOTH SEAT COVERS 2 ROWS', category: 'SUBLET', po_numbers: ['GP13900012'], ticked: false, version: 0, tickable: true },
  { line_key: 'jc:J139000001:3', line_identity: `source:${S(3)}`, operation_no: 'PD003-ABCDEF01', line_no: 3, description: 'Tint front', category: 'TINT', po_numbers: ['GP13900003'], ticked: true, ticked_by_email: 'a@example.invalid', ticked_at: '2026-10-21T06:00:00Z', version: 2, tickable: true },
  { line_key: 'jc:J139000001:4', line_identity: `source:${S(4)}`, operation_no: 'PD004-ABCDEF01', line_no: 4, description: 'Canopy', category: 'FITTING', po_numbers: ['GP13900004'], ticked: false, version: 1, tickable: true } ] });
const liOf = (html, n) => (html.match(new RegExp(`<li data-operation-source-id="${S(n)}"[^>]*>[\\s\\S]*?<\\/li>`)) || [''])[0];
test('inline: PO chip and sublet done tick on each GP PO line in its own category box; "No PO" only in the Sublet box; no separate table', () => {
  const base = summary(jobLines).authenticatedEmailOperationLinesHtml({});
  const html = po.decorateOperations(base, { vehicleId: V1, payload: poPayload() });
  const l12 = liOf(html, 12);
  assert.match(l12, /<strong>PD line 12<\/strong><span>MMT CLOTH SEAT COVERS 2 ROWS<\/span><em>0\.00 h <span class="pdc-sublet-po-inline is-ordered" data-pdc-sublet-vehicle="11111111-2222-4333-8444-555555555555" data-line-key="jc:J139000001:12" data-version="0"><span class="pdc-sublet-po-chip">GP13900012<\/span><input type="checkbox" class="pdc-sublet-po-tick" title="[^"]+" aria-label="PD line 12 sublet done"><\/span><\/em><\/li>/);
  assert.match(html, /data-operation-category="sublet"[\s\S]*PD line 12[\s\S]*<\/section>/);
  assert.match(liOf(html, 13), /<em>0\.00 h <span class="pdc-sublet-po-nopo" title="[^"]+">No PO<\/span><\/em>/, 'Sublet line without a GP PO');
  const tint = liOf(html, 3);
  assert.match(tint, /pdc-sublet-po-inline is-done[^>]*data-version="2"><span class="pdc-sublet-po-chip">GP13900003<\/span><input[^>]*checked>/);
  assert.match(tint, /title="Sublet done \(a@example\.invalid 21\/10, 14:00\)\. Untick if the sublet is not done"/);
  assert.match(liOf(html, 4), /GP13900004/);
  assert.equal(liOf(html, 5), liOf(base, 5), 'non-Sublet line without a PO: nothing extra');
  assert.doesNotMatch(html, /<table|Sublet POs<|pdc-sublet-po-detail|pdc-sublet-po-unplaced/);
  assert.doesNotMatch(html, />\s*Sublet done\s*</, 'no visible caption; the tick carries title and aria-label');
  for (const n of [12, 3, 4]) assert.equal((html.match(new RegExp(S(n), 'g')) || []).length, 1, 'line not duplicated or moved');
  assert.equal(html.replace(/ <span class="pdc-sublet-po-(inline|nopo)[\s\S]*?<\/span>(<\/span>)?(?=<\/em>)/g, ''), base, 'only additions; categories and hours unchanged');
  assert.equal(po.decorateOperations(html, { vehicleId: V1, payload: poPayload() }), html, 'idempotent');
});
test('inline: read only without can_tick; unknown POs show nothing yet; vehicle without POs shows "No PO" on Sublet lines only; unplaced PO lines still listed', () => {
  const base = summary(jobLines).authenticatedEmailOperationLinesHtml({});
  const ro = po.decorateOperations(base, { vehicleId: V1, payload: poPayload(false) });
  assert.equal((ro.match(/class="pdc-sublet-po-tick"[^>]* disabled>/g) || []).length, 3);
  assert.match(ro, /Read only: controllers, administrators and fitters tick sublet done/);
  assert.equal(po.decorateOperations(base, { vehicleId: V1, payload: null }), base, 'POs still loading: unchanged');
  const none = po.decorateOperations(base, { known: true });
  assert.equal((none.match(/No PO/g) || []).length, 2); assert.doesNotMatch(none, /pdc-sublet-po-inline/);
  const extra = poPayload(); extra.lines.push({ line_key: 'jc:J139000001:40', line_identity: `source:${S(40)}`, operation_no: 'PD040-ABCDEF01', line_no: 40, description: 'Hidden <x>', po_numbers: ['GP13900040'], ticked: false, version: 0, tickable: true });
  const un = po.decorateOperations(base, { vehicleId: V1, payload: extra });
  assert.match(un, /<div class="pdc-sublet-po-unplaced"><b>Sublet POs on lines not shown above<\/b><div><strong>PD line 40<\/strong> <span>Hidden &lt;x&gt;<\/span> <span class="pdc-sublet-po-inline[^>]*>[\s\S]*GP13900040/);
  assert.equal(po.decorateOperations('', { known: true }), '');
});
test('browser wrapper: no request without a session; board RPC, decorated strip, inline lines; tick clicks stay off the line', async () => {
  const calls = [];
  const linesBody = poPayload();
  const mk = token => {
    const listeners = {}, capture = {};
    const ctx = { window: { PDC_SUPABASE_CONFIG: { projectRef: 'cdsmnqxtyyoeoznmbidd', url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co', publishableKey: 'k' }, __pdcCachedAccessToken: token },
      document: { visibilityState: 'visible', createElement: () => ({}), head: { appendChild: () => {} }, querySelectorAll: () => [],
        addEventListener: (n, f, c) => { (c ? capture : listeners)[n] = f; } },
      setInterval: () => 0, clearInterval: () => {}, setTimeout: () => 0, renderAll: () => { ctx.rendered = (ctx.rendered || 0) + 1; },
      fetch: async (url, init) => { calls.push({ url, init }); return { ok: true, text: async () => JSON.stringify(/sublet_lines/.test(url) ? linesBody : board) }; },
      incomingWorkChecklistHtml: () => strip(),
      authenticatedEmailOperationLinesHtml: () => summary(jobLines).authenticatedEmailOperationLinesHtml({}) };
    ctx.window.document = ctx.document; ctx.__pdcCachedAccessToken = token; ctx.listeners = listeners; ctx.capture = capture;
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
  assert.doesNotMatch(b.authenticatedEmailOperationLinesHtml({ id: V1 }), /pdc-sublet-po-(inline|nopo)/, 'POs not loaded yet');
  for (let i = 0; i < 5; i++) await new Promise(r => setImmediate(r));
  assert.match(calls[1].url, /get_pdc_sublet_lines_439$/); assert.equal(JSON.parse(calls[1].init.body).p_vehicle_id, V1);
  const html = b.authenticatedEmailOperationLinesHtml({ id: V1 });
  assert.match(html, /GP13900012/); assert.equal(calls.length, 2, 'cached');
  assert.match(b.authenticatedEmailOperationLinesHtml({ id: '99999999-2222-4333-8444-555555555555', stock: 'NONE' }), /No PO/);
  for (const t of ['click', 'dblclick', 'mousedown', 'pointerdown', 'keydown']) assert.equal(typeof b.capture[t], 'function', t);
  let stopped = 0;
  b.capture.click({ target: { closest: sel => sel === '.pdc-sublet-po-inline' ? {} : null }, stopPropagation: () => { stopped += 1; } });
  b.capture.click({ target: { closest: () => null }, stopPropagation: () => { stopped += 10; } });
  assert.equal(stopped, 1, 'only clicks on the tick/chip are kept from the line');
  assert.equal(typeof b.capture.change, 'function');
});
test('loader, cache bust and Pages build include the sublet PO script', () => {
  assert.match(fs.readFileSync('canonical-entry.js', 'utf8'), /pdc-sublet-po\.js\?sublet-po=2026\.10\.21\.r439b'/);
  assert.match(fs.readFileSync('index.html', 'utf8'), /canonical-entry\.js\?[^"]*sublet-po=2026\.10\.21\.r439b"/);
  assert.match(fs.readFileSync('scripts/build_pages_runtime.js', 'utf8'), /'pdc-parts-eta\.js', 'pdc-sublet-po\.js'/);
  assert.equal(po.VERSION, '2026.10.21.r439b');
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
