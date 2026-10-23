'use strict';
// r494 (F107): Manage sublets per vehicle: whole line sublets vs sublet items on operation lines (fictional data only).
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vs = require('./pdc-vehicle-sublets.js');

const U = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const jobLines = [
  { line_identity: `source:${U(1)}`, operation_no: '1', description: 'Suspension kit fit', work_category: 'BUS_MECHANICAL', category_version: 2, department: '138' },
  { line_identity: `source:${U(2)}`, operation_no: '2', description: 'Seat covers front and rear', work_category: 'SUBLET', category_version: 1, department: '138' },
  { line_identity: `source:${U(3)}`, operation_no: '3', description: 'Dual battery wiring', work_category: 'BUS_ELECTRICAL', category_version: 0, department: '138' },
  { line_identity: `source:${U(4)}`, operation_no: '4', description: 'Canopy signage', work_category: 'SUBLET', category_version: 3, department: '138' },
  { line_identity: `source:${U(5)}`, operation_no: '5', description: 'Old note', work_category: 'JOB_CARD_NOTES', department: '138' },
];
const poLines = [
  { line_key: 'RO1|1', line_identity: `source:${U(1)}`, operation_no: '1', category: 'BUS_MECHANICAL', po_numbers: ['GP900001'], po_details: [{ po_number: 'GP900001', description: 'Supply leaf springs' }], has_po: true, ticked: false, version: 1 },
  { line_key: 'RO1|2', line_identity: `source:${U(2)}`, operation_no: '2', category: 'SUBLET', po_numbers: ['GP900002'], po_details: [], has_po: true, ticked: true, version: 4 },
];
const bookings = [
  { __subletOperationIdentity: `source:${U(2)}`, __subletBookingId: 'b-1', pmbSubletProvider: 'Example Trim Co', pmbSubletBookingDate: '2026-10-20', pmbSubletExpectedReturnDate: '2026-10-24', pmbSubletActualReturnDate: '' },
  { __subletOperationIdentity: '', __subletBookingId: 'b-2', pmbSubletProvider: 'Example Glass', pmbSubletBookingDate: '2026-10-21' },
];

test('whole line = SUBLET category (user choice); sublet item = GP PO on a line that keeps its category', () => {
  const m = vs.buildModel({ jobLines, poLines, bookings });
  assert.deepEqual(m.whole.map(r => r.description), ['Seat covers front and rear', 'Canopy signage']);
  assert.deepEqual(m.items.map(r => [r.description, r.category, r.pos[0].po, r.pos[0].description]), [['Suspension kit fit', 'BUS_MECHANICAL', 'GP900001', 'Supply leaf springs']]);
  assert.equal(m.whole[0].bookings[0].pmbSubletProvider, 'Example Trim Co');
  assert.equal(m.loose.length, 1, 'a booking that names no line is listed for the vehicle');
  // Electrical and Mechanical lines can be made whole line sublets; notes are never offered.
  assert.deepEqual(m.others.map(r => r.operationNo), ['1', '3']);
});

test('box colour: open while any sublet of either kind is open (a whole line with no PO stays open); done when all ticked', () => {
  const m = vs.buildModel({ jobLines, poLines, bookings });
  assert.equal(m.total, 3); assert.equal(m.done, 1); assert.equal(m.state, 'open'); assert.equal(m.noPoWhole, 1);
  const ticked = poLines.map(l => ({ ...l, ticked: true }));
  const two = vs.buildModel({ jobLines: jobLines.filter(l => l.operation_no !== '4'), poLines: ticked });
  assert.equal(two.state, 'done');
  assert.equal(vs.buildModel({ jobLines: [jobLines[0]] }).state, 'none');
});

test('without the Workshop detail, the GP PO line category decides the kind', () => {
  const m = vs.buildModel({ poLines });
  assert.deepEqual(m.whole.map(r => r.operationNo), ['2']);
  assert.deepEqual(m.items.map(r => r.operationNo), ['1']);
});

test('screen: ticks use the r439 tick markup; moves only for operators/admins; read-only text otherwise', () => {
  const m = vs.buildModel({ jobLines, poLines, bookings });
  const rw = vs.screenHtml(m, { vehicleId: U(99), title: 'Fictional', perms: { canTick: true, canMove: true, canEmail: true, choices: ['BUS_MECHANICAL', 'BUS_ELECTRICAL', 'SUBLET'] } });
  assert.match(rw, /class="pdc-sublet-po-inline pvs-tick is-done" data-pdc-sublet-vehicle="00000000-0000-4000-8000-000000000099" data-line-key="RO1\|2" data-version="4"/);
  assert.match(rw, /Whole line sublets/); assert.match(rw, /Sublet items on operation lines/);
  assert.match(rw, /the line stays in Bus 4×4 · Mechanical/);
  assert.match(rw, /class="pvs-nopo"[^>]*>PO to raise</); // Craig 22 Oct 18:41
  assert.match(rw, /<th>Supplier<\/th>/); assert.doesNotMatch(rw, /<th>Provider<\/th>/);
  assert.match(rw, /data-pvs-whole="00000000-0000-4000-8000-000000000003"/);
  assert.match(rw, /data-pvs-move="00000000-0000-4000-8000-000000000002" data-category-version="1"/);
  assert.doesNotMatch(rw, /<option value="SUBLET">/, 'move back never offers Sublet');
  assert.match(rw, /data-pvs-email="b-1"/);
  assert.match(rw, /20\/10\/26/);
  assert.match(rw, /! 2 open · 1\/3 done/);
  const ro = vs.screenHtml(m, { vehicleId: U(99), perms: { canTick: false, canMove: false } });
  assert.doesNotMatch(ro, /data-pvs-whole|data-pvs-move=/);
  assert.match(ro, /Read only: controllers, administrators and fitters tick sublet done/);
  assert.match(ro, /<input type="checkbox" class="pdc-sublet-po-tick"[^>]* disabled>/);
});

test('wiring: no new RPC or SQL; category through set_vehicle_work_category; tick saved by pdc-sublet-po.js; slide-out button', () => {
  const src = fs.readFileSync('pdc-vehicle-sublets.js', 'utf8');
  const rpcs = [...src.matchAll(/rpc\/([a-z0-9_]+)/g)].map(m => m[1]);
  // r501 (F114): Clear dates in Manage sublets cancels the booking through the existing cancel_pdc_sublet_booking (staging_only/171).
  assert.deepEqual([...new Set(rpcs)], ['set_vehicle_work_category', 'cancel_pdc_sublet_booking']);
  assert.doesNotMatch(src, /set_pdc_sublet_line_tick_439'\s*,|\.delete\(|DELETE/);
  assert.match(src, /'operator', 'administrator'\]\.includes\(role\(\)\)/);
  assert.match(src, /textContent = 'Manage sublets'/);
  const po = fs.readFileSync('pdc-sublet-po.js', 'utf8');
  assert.match(po, /window\.PDC_SUBLET_PO = Object\.freeze/);
  assert.match(po, /new CustomEvent\('pdc-sublet-lines'/);
  const index = fs.readFileSync('index.html', 'utf8');
  assert.match(index, /pdc-vehicle-sublets\.js\?r494=2026\.10\.23\.r494b&amp;r501=2026\.10\.23\.r501" defer/);
  assert.match(index, /pdc-vehicle-sublets\.css\?r494=2026\.10\.23\.r494b&amp;r501=2026\.10\.23\.r501/);
  assert.match(fs.readFileSync('canonical-entry.js', 'utf8'), /pdc-sublet-po\.js\?sublet-po=2026\.10\.21\.r444&r490=2026\.10\.23\.r490&r494=2026\.10\.23\.r494c'/);
  assert.match(fs.readFileSync('scripts/build_pages_runtime.js', 'utf8'), /'pdc-vehicle-sublets\.css', 'pdc-vehicle-sublets\.js'/);
  assert.equal(vs.VERSION, '2026.10.23.r501');
  assert.equal(fs.readdirSync('supabase/migrations').filter(f => /r494|_494/.test(f)).length, 0, 'no SQL in r494');
});

const po = require('./pdc-sublet-po.js');
const qcVehicle = (lines) => ({ id: U(99), pdcQcOperationLinesProjectionPresent: true, pdcQcOperationLines: lines });
const qc = [
  { lineIdentity: `source:${U(2)}`, stageCode: 'SUBLET', active: true, completed: false, description: 'Seat covers' },
  { lineIdentity: `source:${U(4)}`, stageCode: 'SUBLET', active: true, completed: false, description: 'Canopy signage' },
  { lineIdentity: `source:${U(1)}`, stageCode: 'BUS_4X4', active: true, completed: false, description: 'Suspension' },
  { lineIdentity: `source:${U(6)}`, stageCode: 'SUBLET', active: true, completed: true, description: 'Done earlier' },
];

test('board Sublet box (Craig 22 Oct 18:41): a whole line sublet with no GP PO turns it orange with "PO to raise"', () => {
  const v = qcVehicle(qc);
  // no GP PO on the vehicle at all (no board entry): both open Sublet lines need a PO
  assert.deepEqual(po.poToRaise(v, null, null), { count: 2, known: true });
  const entry = { vehicle_id: U(99), total: 2, ticked: 2, with_po: 2, state: 'done' };
  assert.deepEqual(po.poToRaise(v, entry, null), { count: 0, known: false }, 'lines not loaded: lower bound from the board counts (2 Sublet lines, 2 PO lines)');
  assert.deepEqual(po.poToRaise(v, { ...entry, total: 1, with_po: 1 }, null), { count: 1, known: false }, 'r494c: 2 Sublet lines but only 1 GP PO line: at least 1 to raise');
  assert.deepEqual(po.poToRaise(v, entry, { lines: poLines }), { count: 1, known: true }, 'line 2 has a PO, line 4 not');
  assert.deepEqual(po.poToRaise(qcVehicle(qc.slice(2)), null, null), { count: 0, known: true });
  assert.deepEqual(po.poToRaise({ pdcQcOperationLines: qc }, null, null), { count: 0, known: true }, 'no server projection: unchanged');
  const s = po.boxState(entry, 1);
  assert.equal(s.cls, 'is-ordered'); assert.equal(s.marker, '!'); assert.equal(s.count, 'PO to raise');
  assert.match(s.title, /^Sublet: PO to raise: 1 whole line sublet has no GP PO yet; 2 of 2 GP PO lines ticked sublet done$/);
  assert.equal(po.boxState(entry, 0).cls, 'is-complete', 'all ticked and nothing to raise: green');
  assert.equal(po.boxState(null, 0), null, 'nothing: box unchanged');
  const strip = '<span class="incoming-work-check pdc-station-sublet is-required" title="Sublet" aria-label="Sublet"><span class="incoming-work-box">○</span><span class="incoming-work-label">SUB</span></span>';
  const out = po.decorateStrip(strip, null, 2);
  assert.match(out, /class="incoming-work-check pdc-station-sublet pdc-sublet-po-box is-required is-ordered is-po-to-raise"/);
  assert.match(out, /<span class="incoming-work-box"><b class="pdc-sublet-po-raise">PO to raise<\/b><\/span><span class="incoming-work-label">SUB <small class="pdc-sublet-po-count">PO to raise<\/small><\/span>/);
  assert.match(out, /title="Sublet: PO to raise: 2 whole line sublets have no GP PO yet"/);
  assert.equal(po.decorateStrip(strip, null, 0), strip);
});

test('new GP PO on a line with no sublet (e.g. suspension in Fitting): shows as a sublet item; r494b (Craig 22 Oct 18:55): no "PO raised for this line" note or Got it', () => {
  const line = { line_key: 'RO1|7', line_identity: `source:${U(7)}`, operation_no: '7', category: 'FITTING', po_numbers: ['GP90000107'], po_details: [], has_po: true, ticked: false, version: 0 };
  // The r494 helpers stay (unused by the pages) so nothing that calls them breaks.
  const seen = new Set();
  assert.equal(po.isNewPo(line, U(99), seen), true);
  assert.equal(po.isNewPo(line, U(99), null), false, 'no seen list: no note');
  const m = vs.buildModel({ jobLines: [{ line_identity: `source:${U(7)}`, operation_no: '7', description: 'Suspension fit', work_category: 'FITTING' }], poLines: [line] });
  assert.deepEqual(m.items.map(r => r.category), ['FITTING'], 'shows as a sublet item; the line stays in Fitting');
  assert.equal(m.whole.length, 0); assert.equal(m.state, 'open');
  const html = vs.screenHtml(m, { vehicleId: U(99), perms: { seen: new Set() } });
  assert.match(html, /<span class="pvs-po">GP90000107<\/span>/, 'the GP PO number shows it');
  assert.doesNotMatch(html, /PO raised for this line|Got it|is-new-po|data-pdc-sublet-ack/);
  // The vehicle Sublet box: the page wrapper no longer hands decorateOperations a 'seen' list, so no note or highlight.
  const src = fs.readFileSync('pdc-sublet-po.js', 'utf8');
  assert.match(src, /return decorateOperations\(html, \{ vehicleId: vid, payload: cached\?\.payload \|\| null \}\);/);
  assert.doesNotMatch(src, /payload: cached\?\.payload \|\| null, seen \}/);
});

test('r494b (Craig 22 Oct 18:55): vehicle Sublet box: no "Hours not stated", every right side one same-size chip, one text size', () => {
  assert.equal(po.stripNoHours('<strong>2</strong><span>x</span><em>Hours not stated</em>'), '<strong>2</strong><span>x</span>');
  assert.equal(po.stripNoHours('<em class="is-ai-estimate" title="t">Hours not stated<span class="ai-estimate-label">AI estimate</span></em> y'), ' y');
  assert.equal(po.stripNoHours('<em>NaN h</em>'), '');
  assert.equal(po.stripNoHours('<em>1.50 h</em>'), '<em>1.50 h</em>', 'stated hours stay');
  const box = '<div class="authenticated-email-operations"><section class="authenticated-operation-station" data-operation-station="FITTING"><ul>'
    + `<li data-operation-source-id="${U(1)}"><strong>1</strong><span>Suspension</span><em>Hours not stated</em></li></ul></section>`
    + '<section class="authenticated-operation-station" data-operation-station="SUBLET"><ul>'
    + `<li data-operation-source-id="${U(2)}"><strong>2</strong><span>Seat covers</span><em>Hours not stated</em></li>`
    + `<li data-operation-source-id="${U(4)}"><strong>4</strong><span>Canopy signage</span><em>Hours not stated</em></li>`
    + `<li data-operation-source-id="${U(8)}"><strong>8</strong><span>Stated</span><em>1.50 h</em></li></ul></section></div>`;
  const out = po.decorateOperations(box, { vehicleId: U(99), payload: { ok: true, can_tick: true, lines: poLines } });
  const sublet = out.slice(out.indexOf('data-operation-station="SUBLET"'));
  assert.doesNotMatch(sublet, /Hours not stated/, 'none in the Sublet box');
  assert.match(out.slice(0, out.indexOf('data-operation-station="SUBLET"')), /<em>Hours not stated<\/em>/, 'other boxes unchanged');
  assert.match(sublet, /<em>1\.50 h<\/em>/);
  assert.match(sublet, /<span class="pdc-sublet-po-chip">GP900002<\/span>/);
  assert.equal((sublet.match(/>PO to raise</g) || []).length, 2, 'lines 4 and 8 have no GP PO');
  assert.doesNotMatch(sublet, /PO raised for this line|Got it/);
  const src = fs.readFileSync('pdc-sublet-po.js', 'utf8');
  assert.match(src, /const SUB = OPS \+ '\[data-operation-station="SUBLET"\]';/);
  assert.match(src, /SUB \+ ' li,' \+ SUB \+ ' li :is\(strong,span,small,b,i,em\)\{font-size:12px!important;/, 'one text size');
  assert.match(src, /SUB \+ ' \.pdc-sublet-kind\{display:none\}'/, 'no "Op line PO" caption');
  assert.match(src, /SUB \+ ' \.pdc-sublet-po-chip,' \+ SUB \+ ' \.pdc-sublet-po-nopo\{display:inline-block;box-sizing:border-box;min-width:8\.2em;/, 'same chip size');
  // Manage sublets: 'PO to raise' sits in the GP PO column at the GP PO chip size; one text size in the tables.
  const m = vs.buildModel({ jobLines, poLines, bookings });
  const rw = vs.screenHtml(m, { vehicleId: U(99), perms: { canTick: true } });
  assert.match(rw, /data-pvs-line="00000000-0000-4000-8000-000000000004"><td><b>Op 4<\/b><\/td><td>Canopy signage<\/td><td><span class="pvs-nopo"[^>]*>PO to raise<\/span><\/td><td><span class="pvs-muted"/);
  const css = fs.readFileSync('pdc-vehicle-sublets.css', 'utf8');
  assert.match(css, /\.pvs-po,\.pvs-nopo\{box-sizing:border-box;min-width:8\.2em;/);
  assert.equal(vs.VERSION, '2026.10.23.r501');
});

test('Got it is stored per user in this browser (no SQL); the board strip asks for a vehicle\'s GP PO lines only when it has Sublet lines and a PO', () => {
  const src = fs.readFileSync('pdc-sublet-po.js', 'utf8');
  assert.match(src, /'pdc\.sublet-new-po-seen\.v1:' \+ String\(window\.PDC_AUTH_CONTEXT\?\.userId \|\| ''\)/);
  assert.match(src, /if \(!index \|\| !subletJobs\(vehicle\)\.length\) return 0;/);
  // r494c (F107b): the board strip never fetches a vehicle's GP PO lines while it renders (that made the site slow).
  assert.doesNotMatch(src, /fetchLines\(vid, true\)/);
  assert.match(src, /decorateStrip\(prior\(vehicle, \.\.\.args\), entry, raiseFor\(vehicle, entry\)\)/);
  assert.match(src, /closest\?\.\('\[data-pdc-sublet-ack\]'\)/);
  assert.equal(po.VERSION, '2026.10.21.r444', 'module version string unchanged; cache bust r494 on its src');
});
