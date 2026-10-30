'use strict';
// r751 (F356, Craig 30 Oct 10:12): the Sublet box is two groups. Standard sublets (Malaga Motor Trimmers / MMT seat
// covers, Perth Signcraft, Full tank of fuel, Pit and weigh) first, Other sublets after; a Pit and weigh line without a
// GP PO is still listed under Standard. Synthetic data only.
const test = require('node:test'), assert = require('node:assert/strict'), fs = require('node:fs'), vm = require('node:vm');
const panels = require('./pdc-operation-panels.js');
const po = require('./pdc-sublet-po.js');
const appSource = fs.readFileSync('app.js', 'utf8');
function summary(lines) {
  const context = vm.createContext({ app: { vehicleWorkshopDetailCache: new Map([['synthetic', { status: 'ready', detail: { vehicle_version: 2, job_card_lines: lines } }]]) },
    cleanNavisionText: x => String(x ?? '').trim(), vehicleWorkshopDetailCanonicalId: () => 'synthetic', vehicleKey: () => 'synthetic',
    escapeHtml: x => String(x ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;'),
    vehicleWorkshopLineIdentity: (_s, l) => `source:${l.operation_line_id}`, vehicleWorkshopStageCode: s => String(s).toUpperCase() });
  vm.runInContext(appSource.slice(appSource.indexOf('function authenticatedOperationLineValid('), appSource.indexOf('function refreshAuthenticatedOperationSummaryRow(')), context);
  return context;
}
const V = '11111111-2222-4333-8444-555555555555';
const S = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const jc = (n, cat, desc, h = 0.5) => ({ line_identity: `source:${S(n)}`, source_line_id: S(n), operation_no: `PD${String(n).padStart(3, '0')}-ABCDEF01`,
  description: desc, source_kind: 'authenticated', department: '138', active: true, work_category: cat, stage_code: cat, estimated_hours: h });
const L = (n, pos, ticked, descs) => ({ line_key: `jc:J138000001:${n}`, line_identity: `source:${S(n)}`, operation_no: `PD${String(n).padStart(3, '0')}-ABCDEF01`, line_no: n,
  po_numbers: pos, po_details: pos.map((p, i) => ({ po_number: p, description: descs[i] })), ticked, version: ticked ? 1 : 0, tickable: true });
// Shape of the screenshot: tyres PO on a Tyres line, Total Tools and Silverstone as own Sublet lines, MMT seat covers own
// line, Pit Inspection PO on a Fitting line, a Full tank of fuel own line, and a Pit and weigh Fitting line with no PO.
const lines = [jc(1, 'SUBLET', 'Total Tools - Quote number 191658', 0), jc(9, 'TYRE', '5 x BFG KO3 A/T Tyres Tyrepower west perth changeover', 0.5),
  jc(16, 'SUBLET', 'SUB - MMT 2 Row Canvas Seat Covers', 0), jc(18, 'FITTING', 'PIT AND WEIGH', 0.25), jc(25, 'SUBLET', 'Silverstone Signage - Vision Group', 0),
  jc(27, 'SUBLET', 'Full tank of fuel', 0), jc(30, 'FITTING', 'Pit and weigh after GVM', 0.25)];
const payload = { ok: true, can_tick: true, vehicle_id: V, lines: [L(1, ['GP13963285'], false, ['Total Tools']), L(9, ['GP13962800'], false, ['Tyrepower west perth changeover']),
  L(16, ['GP13962785'], true, ['MMT 2 ROWS SEAT COVERS CANVAS']), L(18, ['GP13962417'], false, ['Pit Inspection']), L(25, ['GP13962805'], false, ['Silverstone Signage']), L(27, ['GP13962900'], true, ['Full tank'])] };
const render = () => panels.arrange(po.decorateOperations(summary(lines).authenticatedEmailOperationLinesHtml({}), { vehicleId: V, payload }));
const box = html => html.slice(html.indexOf('data-operation-panel="sublet"'));
const order = html => [...box(html).matchAll(/<li[^>]*?(?:class="pdc-sublet-group" data-pdc-sublet-group="(\w+)"|data-line-key="jc:J138000001:(\d+)"|data-operation-source-id="0{8}-0000-4000-8000-0*(\d+)"|data-pdc-sublet-row="standard-line"><strong>PD line (\d+))/g)]
  .map(m => m[1] || Number(m[2] || m[3] || m[4]));

test('two groups: Standard first (MMT, Pit, Fuel), Other after (Total Tools, Tyrepower, Silverstone); PD order inside each; headings carry their own done count', () => {
  const html = render();
  assert.deepEqual(order(html), ['standard', 16, 18, 27, 30, 'other', 1, 9, 25]);
  const b = box(html);
  assert.match(b, /<li class="pdc-sublet-group" data-pdc-sublet-group="standard"><strong>Standard sublets<\/strong><span>Malaga Motor Trimmers · Perth Signcraft · Full tank of fuel · Pit and weigh<\/span><em class="pdc-sublet-group-state is-ordered">2 of 3 done<\/em><\/li>/);
  assert.match(b, /<li class="pdc-sublet-group" data-pdc-sublet-group="other"><strong>Other sublets<\/strong><span>Sublets attached to a line or a one-off provider<\/span><em class="pdc-sublet-group-state is-ordered">0 of 3 done<\/em><\/li>/);
  // The Pit and weigh Fitting line with no PO is listed under Standard, without a tick, and does not count.
  assert.match(b, /data-pdc-sublet-row="standard-line"><strong>PD line 30<\/strong><span><b class="pdc-sublet-desc">Pit and weigh after GVM<\/b><small class="pdc-sublet-on">On operation line: Pit and weigh after GVM · Fitting<\/small><\/span><em class="pdc-sublet-kind">No PO<\/em><\/li>/);
  assert.equal((b.match(/class="pdc-sublet-po-tick"/g) || []).length, 6, 'one tick per PO line, none for the no-PO pit line');
  // Box header: 7 sublets (the no-PO pit line counts as a sublet, group headings do not); the done state stays PO based: 2 of 6.
  assert.match(html, /<strong>Sublet<\/strong><small>7 sublets <span class="pdc-op-sublet-state is-ordered">2 of 6 sublets done<\/span>/);
  assert.match(html, /data-pdc-sublet-state="ordered" data-pdc-sublet-count="2\/6"/);
});

test('matching: provider names and pit/weigh, not loose words', () => {
  const hit = t => (po.standardSublet(t) || {}).id || null;
  assert.equal(hit('SUB - MMT 2 Row Canvas Seat Covers'), 'mmt');
  assert.equal(hit('Malaga Motor Trimmers canopy lining'), 'mmt');
  assert.equal(hit('Perth Signcraft decals'), 'signcraft');
  assert.equal(hit('PERTH SIGN CRAFT'), 'signcraft');
  assert.equal(hit('Full tank of fuel'), 'fuel');
  assert.equal(hit('FULL TANK'), 'fuel');
  assert.equal(hit('PIT AND WEIGH'), 'pit');
  assert.equal(hit('Pit Inspection'), 'pit');
  assert.equal(hit('Weigh bridge certificate'), 'pit');
  assert.equal(hit('Silverstone Signage - Vision Group'), null);
  assert.equal(hit('Tyrepower west perth changeover'), null);
  assert.equal(hit('Fuel filter replace'), null, '"fuel" alone is not the full tank');
  assert.equal(hit('Weight distribution hitch'), null, '"weight" is not "weigh"');
  assert.equal(hit('Pitch adjust'), null);
  assert.equal(po.STANDARD_SUBLETS.map(s => s.name).join(', '), 'Malaga Motor Trimmers, Perth Signcraft, Full tank of fuel, Pit and weigh');
});

test('a group with nothing in it is not shown; no sublet PO lines at all leaves the box as before', () => {
  const only = po.groupRowsHtml(['<li data-line-key="x"><strong>PD line 3</strong><span>Silverstone</span><span class="pdc-sublet-po-inline is-done"></span></li>']);
  assert.doesNotMatch(only, /data-pdc-sublet-group="standard"/);
  assert.match(only, /data-pdc-sublet-group="other"[^>]*><strong>Other sublets<\/strong><span>[^<]*<\/span><em class="pdc-sublet-group-state is-done">1 of 1 done<\/em>/);
  assert.equal(po.groupRowsHtml([]), '');
  assert.match(fs.readFileSync('canonical-entry.js', 'utf8'), /pdc-sublet-po\.js\?[^']*&r751=2026\.10\.30\.r751'/);
  assert.match(fs.readFileSync('pdc-operation-panels.js', 'utf8'), /<li\\b\(\?!\[\^>\]\*pdc-sublet-group\)/, 'the panel header count skips the group headings');
});
