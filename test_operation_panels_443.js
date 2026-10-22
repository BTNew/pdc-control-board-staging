/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
// r443 (F56, change request): the operations summary in the vehicle drop-down as packed category panels in two columns
// (largest-first balance), Sublet full width underneath, then Review and other boxes. Layout only.
const test = require('node:test'), assert = require('node:assert/strict'), fs = require('node:fs'), vm = require('node:vm');
const panels = require('./pdc-operation-panels.js');
const po = require('./pdc-sublet-po.js');
const appSource = fs.readFileSync('app.js', 'utf8');
function summary(lines, extra = {}) {
  const context = vm.createContext({ app: { vehicleWorkshopDetailCache: new Map([['synthetic', { status: 'ready', detail: { vehicle_version: 2, job_card_lines: lines } }]]) },
    cleanNavisionText: x => String(x ?? '').trim(), vehicleWorkshopDetailCanonicalId: () => 'synthetic', vehicleKey: () => 'synthetic',
    escapeHtml: x => String(x ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;'),
    vehicleWorkshopLineIdentity: (_s, l) => `source:${l.operation_line_id}`, vehicleWorkshopStageCode: s => String(s).toUpperCase(), ...extra });
  vm.runInContext(appSource.slice(appSource.indexOf('function authenticatedOperationLineValid('), appSource.indexOf('function refreshAuthenticatedOperationSummaryRow(')), context);
  return context;
}
const V1 = '11111111-2222-4333-8444-555555555555';
const S = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const jc = (n, cat, desc, hours = 0.5, stage = cat) => ({ line_identity: `source:${S(n)}`, source_line_id: S(n), operation_no: `PD${String(n).padStart(3, '0')}-ABCDEF01`,
  description: desc, source_kind: 'authenticated', department: '139', active: true, work_category: cat, stage_code: stage, estimated_hours: hours });
const many = (from, count, cat) => Array.from({ length: count }, (_, i) => jc(from + i, cat, `${cat} sample ${i + 1}`));
// Shaped like the board screenshot: Tint 1, Hoist 1, Fitting 12, Fabrication 2, Electrical 12, Tyres 1, Sublet 4, Review 1.
const shot = [jc(31, 'TINT', 'Darkest Legal Window Tint', 1), jc(20, 'HOIST', 'Sample GVM upgrade', 7.5), ...many(1, 12, 'FITTING'), ...many(26, 2, 'FABRICATION'),
  ...many(40, 12, 'ELECTRICAL'), jc(30, 'TYRE', 'Sample tyre package', 0.3), ...many(60, 4, 'SUBLET'), jc(70, 'UNALLOCATED_MAPPING_REVIEW', 'Unmapped sample accessory', null, 'REVIEW')];
const payload = { ok: true, can_tick: true, vehicle_id: V1, lines: [
  { line_key: 'jc:J139000001:31', line_identity: `source:${S(31)}`, operation_no: 'PD031-ABCDEF01', line_no: 31, po_numbers: ['GP13900031'], ticked: false, version: 0, tickable: true },
  { line_key: 'jc:J139000001:60', line_identity: `source:${S(60)}`, operation_no: 'PD060-ABCDEF01', line_no: 60, po_numbers: ['GP13900060'], ticked: true, version: 1, tickable: true },
  { line_key: 'jc:J139000001:41', line_identity: `source:${S(41)}`, operation_no: 'PD041-ABCDEF01', line_no: 41, po_numbers: ['GP13900041'], ticked: false, version: 0, tickable: true } ] };
const order = html => [...html.matchAll(/data-operation-panel="([^"]*)"/g)].map(m => m[1]);
const column = (html, side) => {
  const m = html.match(new RegExp(`<div class="pdc-op-col is-${side}" data-pdc-op-column="${side}">([\\s\\S]*?)</div>(?=<div class="pdc-op-col|<section class="authenticated-operation-station pdc-op-panel[^"]*is-full)`));
  return m ? order(m[1]) : null;
};
const W = ids => ids.map(([id, weight]) => ({ id, weight }));

test('balancing rule: largest first into the lighter column, ties left, each column in the standard order', () => {
  // Screenshot mix: weights Tint 2, Bus 1, Hoist 2, Fitting 13, Fabrication 3, Electrical 13, Tyres 2.
  const a = panels.balance(W([['tint', 2], ['bus4x4', 1], ['hoist', 2], ['fitting', 13], ['fabrication', 3], ['electrical', 13], ['tyre', 2]]));
  assert.deepEqual(a, { left: ['fitting', 'fabrication', 'tyre'], right: ['tint', 'bus4x4', 'hoist', 'electrical'], weights: { left: 18, right: 18 } });
  // Alternative mix: Tint 6, Fitting 3, Electrical 15, the rest empty.
  const b = panels.balance(W([['tint', 7], ['bus4x4', 1], ['hoist', 1], ['fitting', 4], ['fabrication', 1], ['electrical', 16], ['tyre', 1]]));
  assert.deepEqual(b, { left: ['electrical'], right: ['tint', 'bus4x4', 'hoist', 'fitting', 'fabrication', 'tyre'], weights: { left: 16, right: 15 } });
  // All empty: equal weights keep the standard order and alternate, starting left.
  const c = panels.balance(panels.PANELS.map(p => ({ id: p.id, weight: 1 })));
  assert.deepEqual(c.left, ['tint', 'hoist', 'fabrication', 'tyre']); assert.deepEqual(c.right, ['bus4x4', 'fitting', 'electrical']);
  // Deterministic and independent of input object identity.
  assert.deepEqual(panels.balance(W([['tint', 2], ['bus4x4', 1], ['hoist', 2], ['fitting', 13], ['fabrication', 3], ['electrical', 13], ['tyre', 2]])), a);
  assert.deepEqual(panels.PANELS.map(p => p.id), ['tint', 'bus4x4', 'hoist', 'fitting', 'fabrication', 'electrical', 'tyre']);
});

test('real summary: panels with lines in two balanced columns, Sublet full width underneath, then Review; empty categories hidden (r444)', () => {
  const base = summary(shot).authenticatedEmailOperationLinesHtml({});
  const html = panels.arrange(base);
  assert.deepEqual(column(html, 'left'), ['fitting', 'fabrication', 'tyre']);
  assert.deepEqual(column(html, 'right'), ['tint', 'hoist', 'electrical']);
  assert.deepEqual(order(html), ['fitting', 'fabrication', 'tyre', 'tint', 'hoist', 'electrical', 'sublet']);
  assert.match(html, /<section class="authenticated-operation-station pdc-op-panel is-full" data-operation-panel="sublet"/);
  const sublet = html.indexOf('data-operation-panel="sublet"'), review = html.indexOf('data-operation-station="REVIEW"');
  assert.ok(sublet > 0 && review > sublet, 'Review after Sublet');
  assert.match(html, /<div class="authenticated-operation-station-grid pdc-op-below"><section class="authenticated-operation-station" data-operation-station="REVIEW"/);
  assert.doesNotMatch(html, /data-operation-panel="bus4x4"|pdc-op-empty|No jobs/, 'r444: a category with no lines is not shown');
  assert.match(html, /data-operation-panel="fitting"[^>]*><header><strong>Fitting<\/strong><small>12 jobs · 6\.00 h<\/small><\/header>/);
  // Every line is still there, once, with its original markup.
  for (const m of base.matchAll(/<li data-operation-source-id="[^"]*"[\s\S]*?<\/li>/g)) assert.equal(html.split(m[0]).length, 2, m[0].slice(0, 60));
  assert.equal((html.match(/<li /g) || []).length, (base.match(/<li /g) || []).length);
  // Original sections keep their exact class attribute (PO decoration and Review bind to it); markers are data attributes.
  assert.match(html, /<section class="authenticated-operation-station" data-operation-station="FITTING" data-operation-category="fitting" style="[^"]*" data-pdc-op-sub data-pdc-op-sole>/);
  assert.equal(panels.arrange(html), html, 'idempotent');
  assert.equal(panels.arrange(''), ''); assert.equal(panels.arrange('<div>other</div>'), '<div>other</div>');
});

test('Bus 4x4 gathers its sub-categories in one panel and sums stated hours', () => {
  const html = panels.arrange(summary([jc(1, 'BUS_MECHANICAL', 'Bus mech', 1, 'BUS_4X4'), jc(2, 'BUS_ELECTRICAL', 'Bus elec', 0.25, 'BUS_4X4'), jc(3, 'TINT', 'Tint', 1)]).authenticatedEmailOperationLinesHtml({}));
  assert.match(html, /data-operation-panel="bus4x4"[^>]*><header><strong>Bus 4x4<\/strong><small>2 jobs · 1\.25 h<\/small><\/header><div class="pdc-op-panel-body"><section class="authenticated-operation-station" data-operation-station="BUS_4X4" data-operation-category="bus_mechanical"[^>]*data-pdc-op-sub>/);
  assert.doesNotMatch(html, /data-operation-category="bus_mechanical"[^>]*data-pdc-op-sole/, 'sub-category headings stay visible');
});

test('hours: lines with no PD-stated hours read "Hours not stated" as today; a non-numeric value never shows NaN', () => {
  const lines = [jc(1, 'FITTING', 'Blank hours', null), jc(2, 'FITTING', 'Text hours', 'abc'), jc(3, 'TINT', 'Only blank', null), jc(4, 'ELECTRICAL', 'Normal', 1.5)];
  const base = summary(lines).authenticatedEmailOperationLinesHtml({});
  assert.match(base, /<em>Hours not stated<\/em>/, 'today: blank hours');
  assert.match(base, /<em>NaN h<\/em>/, 'the frozen app.js prints NaN h for a non-numeric value; the module guards it');
  const html = panels.arrange(base);
  assert.doesNotMatch(html, /NaN|Infinity/);
  assert.equal((html.match(/<em>Hours not stated<\/em>/g) || []).length, 3);
  assert.match(html, /data-operation-panel="tint"[^>]*><header><strong>Tint<\/strong><small>1 job · Unknown hours<\/small>/);
  assert.match(html, /<em>1\.50 h<\/em>/);
  assert.equal(panels.guardHours('<em class="is-ai-estimate" title="x">NaN h<span class="ai-estimate-label">AI estimate</span></em>'),
    '<em class="is-ai-estimate" title="x">Hours not stated<span class="ai-estimate-label">AI estimate</span></em>');
});

test('PO decoration (loaded first, as canonical-entry.js loads it) then panels: every tick in the Sublet box, PO references on operation lines; reverse order keeps every line and tick', () => {
  const base = summary(shot).authenticatedEmailOperationLinesHtml({});
  const state = { vehicleId: V1, payload };
  const loaded = panels.arrange(po.decorateOperations(base, state));
  const reverse = po.decorateOperations(panels.arrange(base), state);
  for (const h of [loaded, reverse]) assert.equal((h.match(/class="pdc-sublet-po-tick"/g) || []).length, 3);
  assert.equal((loaded.match(/>PO to raise</g) || []).length, 3, 'Sublet lines without a PO (r494: PO to raise)');
  assert.match(loaded, new RegExp(`<li data-operation-source-id="${S(31)}"><strong>PD line 31</strong><span>Darkest Legal Window Tint</span><em>1\\.00 h</em> <span class="pdc-sublet-po-ref is-ordered"[^>]*>GP13900031<span aria-hidden="true"> ↓</span></span></li>`));
  const sublet = loaded.slice(loaded.indexOf('data-operation-panel="sublet"'));
  assert.match(sublet, /pdc-sublet-po-inline is-done[^>]*><span class="pdc-sublet-po-chip">GP13900060<\/span><input[^>]*checked>/);
  assert.match(sublet, /data-line-key="jc:J139000001:31"><strong>PD line 31<\/strong>/);
  assert.match(loaded, /data-operation-panel="sublet"[^>]*><header><strong>Sublet<\/strong><small>6 sublets <span class="pdc-op-sublet-state is-ordered">1 of 6 sublets done<\/span><\/small><\/header>/);
  assert.equal(po.decorateOperations(loaded, state), loaded, 'decorating again changes nothing');
});
test('browser: wraps the summary after the PO module; re-renders (refresh, tick, edit) re-arrange; tick clicks stay isolated; Edit button kept', async () => {
  let lines = shot.slice();
  const listeners = {}, capture = {}, styles = [], refreshed = [];
  const ctx = summary(lines, { vehicleWorkshopCanEditLines: () => true });
  ctx.app.vehicleWorkshopDetailCache.get('synthetic').detail.job_card_lines = lines;
  const board = { ok: true, vehicles: [{ vehicle_id: V1, stock_number: 'S1', state: 'ordered', total: 3, ticked: 1, with_po: 3 }] };
  Object.assign(ctx, { window: { PDC_SUPABASE_CONFIG: { projectRef: 'cdsmnqxtyyoeoznmbidd', url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co', publishableKey: 'k' }, __pdcCachedAccessToken: 't',
    addEventListener: (n, f) => { listeners['window:' + n] = f; }, requestAnimationFrame: f => f() },
    document: { visibilityState: 'visible', documentElement: { clientWidth: 1366 }, createElement: () => ({}), head: { appendChild: el => styles.push(el.textContent || '') },
      querySelectorAll: sel => sel === '[data-incoming-row][open]' ? [{ id: 'row' }] : [], addEventListener: (n, f, c) => { (c ? capture : listeners)[n] = f; } },
    setInterval: () => 0, clearInterval: () => {}, setTimeout: () => 0, renderAll: () => {}, incomingWorkChecklistHtml: () => '',
    refreshAuthenticatedOperationSummaryRow: row => { refreshed.push(row.id); },
    fetch: async url => ({ ok: true, text: async () => JSON.stringify(/sublet_lines/.test(url) ? payload : board) }) });
  vm.runInContext(fs.readFileSync('pdc-sublet-po.js', 'utf8'), ctx);
  vm.runInContext(fs.readFileSync('pdc-operation-panels.js', 'utf8'), ctx);
  assert.equal(ctx.window.PDC_OPERATION_PANELS_VERSION, '2026.10.21.r444');
  assert.deepEqual(refreshed, ['row'], 'rows already open switch to the panels');
  assert.ok(styles.some(s => s.includes('.pdc-op-panels{display:grid')), 'CSS injected by the module');
  for (let i = 0; i < 8; i++) await new Promise(r => setImmediate(r));
  const first = ctx.authenticatedEmailOperationLinesHtml({ id: V1 });
  assert.match(first, /data-pdc-panels="2026\.10\.21\.r444"/);
  assert.equal((first.match(/<button type="button" class="small-button" data-auth-operation-work="synthetic">Edit jobs &amp; hours<\/button>/g) || []).length, 1, 'Edit jobs & hours untouched');
  for (let i = 0; i < 8; i++) await new Promise(r => setImmediate(r));
  const decorated = ctx.authenticatedEmailOperationLinesHtml({ id: V1 });
  assert.equal((decorated.match(/class="pdc-sublet-po-tick"/g) || []).length, 3, 'PO chips/ticks inside the panels');
  assert.deepEqual(column(decorated, 'left'), ['fitting', 'fabrication', 'tyre']);
  // An edit or realtime refresh changes the lines: the next render re-balances.
  lines.splice(0, lines.length, ...many(1, 15, 'ELECTRICAL'), ...many(31, 6, 'TINT'), ...many(50, 3, 'FITTING'));
  const after = ctx.authenticatedEmailOperationLinesHtml({ id: V1 });
  assert.deepEqual(column(after, 'left'), ['electrical']);
  assert.deepEqual(column(after, 'right'), ['tint', 'fitting']);
  assert.equal((after.match(/data-pdc-panels=/g) || []).length, 1);
  let stopped = 0;
  capture.click({ target: { closest: sel => sel === '.pdc-sublet-po-inline' ? {} : null }, stopPropagation: () => { stopped += 1; } });
  assert.equal(stopped, 1, 'a click on the tick never reaches the line (edit/booking)');
  // A second load of the file does nothing.
  vm.runInContext(fs.readFileSync('pdc-operation-panels.js', 'utf8'), ctx);
  assert.equal((ctx.authenticatedEmailOperationLinesHtml({ id: V1 }).match(/data-pdc-panels=/g) || []).length, 1);
  assert.equal(typeof listeners['window:resize'], 'function');
});

test('loader: after pdc-sublet-po.js (onload and onerror), cache-busted; Pages ships it; styles.css and Karratha untouched', () => {
  const entry = fs.readFileSync('canonical-entry.js', 'utf8');
  assert.match(entry, /operationPanels\.src = 'pdc-operation-panels\.js\?operation-panels=2026\.10\.21\.r444';/);
  // r445: pdc-sublet-po-attach.js now sits between the PO module and the panels (panels still load when it fails).
  assert.match(entry, /subletPo\.onload = loadSubletPoAttach;\s*subletPo\.onerror = loadSubletPoAttach;\s*document\.head\.appendChild\(subletPo\);/);
  assert.match(entry, /subletPoAttach\.onload = loadOperationPanels;\s*subletPoAttach\.onerror = loadOperationPanels;/);
  assert.equal((entry.match(/pdc-operation-panels\.js/g) || []).length, 1);
  assert.match(fs.readFileSync('index.html', 'utf8'), /canonical-entry\.js\?[^"]*&amp;operation-panels=2026\.10\.21\.r444(&amp;sublet-po-attach=2026\.10\.21\.r445)?"/);
  assert.match(fs.readFileSync('scripts/build_pages_runtime.js', 'utf8'), /'pdc-sublet-po\.js', ('pdc-sublet-po-attach\.js', )?'pdc-operation-panels\.js'/);
  assert.doesNotMatch(fs.readFileSync('styles.css', 'utf8'), /pdc-op-/);
  for (const f of fs.readdirSync('karratha')) if (/\.(js|html|css)$/.test(f)) assert.doesNotMatch(fs.readFileSync(`karratha/${f}`, 'utf8'), /pdc-operation-panels|pdc-op-panel/, f);
  assert.equal(panels.VERSION, '2026.10.21.r444');
  assert.match(panels.CSS, /max-width:calc\(100vw - 110px\)/);
});
