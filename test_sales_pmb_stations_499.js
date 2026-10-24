/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r499 (F112): the Sales PMB STATUS station icons are the Control Board's strip. The board's own functions are taken from
// app.js (not edited) and run on the same mapped vehicles; Sublet is decorated by pdc-sublet-po.js's own decorateStrip.
// Made-up vehicles only (no stock numbers, names or ids from the live data).
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const stations = require('./sales/pmb-stations.js');
const guard = require('./vehicle-requirements-guard.js');
const eligibility = require('./workshop-eligibility.js');
const subletPo = require('./pdc-sublet-po.js');

const APP = fs.readFileSync('app.js', 'utf8');
function source(name) {
  const lines = APP.split('\n');
  const start = lines.findIndex(l => new RegExp(`^(?:async )?function ${name}\\(|^const ${name} = `).test(l));
  assert.ok(start >= 0, `app.js still defines ${name}`);
  if (/;\s*$/.test(lines[start]) && !/[[{(]\s*$/.test(lines[start])) return lines[start];
  for (let i = start + 1; i < lines.length; i++) if (/^[}\])]/.test(lines[i])) return lines.slice(start, i + 1).join('\n');
  throw new Error('unterminated ' + name);
}
const NAMES = ['NAVISION_JITA_NUMBER_AUTHORITY', 'PRODUCTION_FLOW_DEFS', 'PDC_JOB_DEFS', 'PDC_JOB_BY_KEY', 'PMB_STAGE_TO_JOB_KEY', 'PDC_GRID_JOB_LABELS',
  'pmbStageForPdcJob', 'normalizePmbStage', 'inferredPmbStage', 'isPdcBlocked', 'pdcBlockReason', 'pdcJobRequired', 'pdcJobComplete', 'pdcJobTriState',
  'pdcJobCompletionTitle', 'pdcJobDefsPartsFirst', 'pdcGridJobLabel', 'parseIsoTimestamp', 'isBlankStock', 'vehicleHasBatchNumber', 'vehicleNavisionJitaNumber',
  'cleanNavisionText', 'escapeHtml', 'canonicalVehicleWorkState', 'canonicalActiveSubletBooking', 'partsJobDef', 'partsStateComplete',
  'isActivePartsStoppage', 'partsOrdered', 'importedPartsStatus', 'importedPartsTitle', 'incomingWorkChecklistHtml'];
function board() {
  const ctx = { window: { VehicleRequirementsGuard: guard, PDC_WORKSHOP_ELIGIBILITY: eligibility }, WORKSHOP_ELIGIBILITY: eligibility,
    WORKSHOP_CANONICAL_STATION_DEFS: eligibility.stationDefinitions, vehicleKey: () => '', pdcJobFallbackRequired: () => { throw new Error('free-text fallback used'); } };
  vm.runInNewContext(NAMES.map(source).join('\n') + '\nthis.__board = { incomingWorkChecklistHtml, PDC_GRID_JOB_LABELS, PMB_STAGE_TO_JOB_KEY };', ctx);
  return ctx.__board;
}
const B = board();
const boardHtml = entry => {
  const v = stations.toBoardVehicle(entry);
  const html = B.incomingWorkChecklistHtml(v, { bookingProjection: { bookingRequired: false, activeBookings: v.salesWorkshopBookings } });
  return subletPo.decorateStrip(html, entry.sublet_po || null, Number(entry.sublet_without_po) || 0);
};
const salesHtml = entry => stations.decorateStrip(stations.stripHtml(stations.toBoardVehicle(entry)), entry.sublet_po || null, Number(entry.sublet_without_po) || 0);
// r499b adds is-started and says "started" where the board still says "booked" (the board folds status started into booked).
const asBoard = html => html.replace(/ is-started/g, '').replace(/\b(Parts|Tint|Bus 4x4|Hoist|Fitting|Fab|Elec|Tyre|Sublet) started"/g, '$1 booked"');

const U = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const W = (req = [], done = []) => Object.fromEntries([...new Set([...req, ...done])].map(k => [k, { required: req.includes(k), completed: done.includes(k) }]));
const F = n => FIX.find(e => e.vehicle_id === U(n));
const FIX = [
  { vehicle_id: U(1), has_stock: true },
  { vehicle_id: U(2), has_stock: false, parts: {} },
  { vehicle_id: U(3), has_stock: true, work: W(['tint', 'bus4x4', 'hoist', 'fitting', 'fabrication', 'electrical', 'tyre', 'sublet']), parts: { parts_required: true } },
  { vehicle_id: U(4), has_stock: true, work: W(['tint', 'hoist'], ['tint', 'hoist', 'parts']), parts: { parts_required: true, parts_received: true } },
  { vehicle_id: U(5), has_stock: true, parts: { parts_required: true, parts_ordered: true } },
  { vehicle_id: U(6), has_stock: true, parts: { parts_required: true, parts_stoppage: true, parts_stoppage_reason: 'Back order <ETA>' } },
  { vehicle_id: U(7), has_stock: true, parts: { parts_required: false } },
  ...['green', 'orange', 'red', 'grey', 'review'].map((colour, i) => ({ vehicle_id: U(10 + i), has_stock: true, parts: { parts_required: true },
    parts_flags: { colour, label: `Flag ${colour}`, meaning: 'Made-up meaning', last_successful_import_at: i % 2 ? null : '2026-10-22T01:30:00Z' }, jita_number: i === 0 ? '1234567' : null })),
  { vehicle_id: U(20), has_stock: true, jita_number: '7654321', parts: { parts_required: true } },
  { vehicle_id: U(21), has_stock: true, jita_number: '000', parts: { parts_required: true } },
  { vehicle_id: U(22), has_stock: true, pmb_stage: 'TINT', pmb_stoppage: true, pmb_stoppage_reason: 'Waiting on film', work: W(['tint', 'hoist']) },
  { vehicle_id: U(23), has_stock: true, pmb_stage: 'Express Hoist', work: W(['hoist', 'fitting']), bookings: [{ stage_code: 'HOIST', status: 'stoppage', stoppage_reason: 'Ram fault' }, { stage_code: 'FITTING', status: 'planned', stoppage_reason: '' }] },
  { vehicle_id: U(24), has_stock: true, pmb_stage: 'ELECTRICAL', work: W(['electrical', 'tyre']), bookings: [{ stage_code: 'ELECTRICAL', status: 'started' }, { stage_code: 'TYRE', status: 'queued' }, { stage_code: 'TINT', status: 'completed' }] },
  { vehicle_id: U(25), has_stock: true, sublet_active_bookings: 1 },
  { vehicle_id: U(26), has_stock: true, sublet_active_bookings: 2 },
  { vehicle_id: U(27), has_stock: true, sublet_returned_bookings: 1 },
  { vehicle_id: U(28), has_stock: true, qc_open_stage_codes: ['BUS_QA', 'TINT', 'JOB_CARD_NOTES', 'SUBLET', 'PIT_INSPECTION'] },
  { vehicle_id: U(29), has_stock: true, qc_open_stage_codes: ['SUBLET'], sublet_open_lines: 2, sublet_without_po: 2 },
  { vehicle_id: U(30), has_stock: true, qc_open_stage_codes: ['SUBLET'], sublet_open_lines: 2, sublet_without_po: 1, sublet_po: { state: 'ordered', total: 1, ticked: 0, with_po: 1 } },
  { vehicle_id: U(31), has_stock: true, work: W(['sublet']), sublet_po: { state: 'ordered', total: 3, ticked: 1, with_po: 3 } },
  { vehicle_id: U(32), has_stock: true, work: W(['sublet']), sublet_po: { state: 'done', total: 2, ticked: 2, with_po: 2 } },
  { vehicle_id: U(33), has_stock: true, work: W(['sublet'], ['sublet']), sublet_without_po: 1 },
  { vehicle_id: U(34), has_stock: true, pmb_stage: 'SUBLET', pmb_stoppage: true, pmb_stoppage_reason: '', work: W(['sublet']) },
  { vehicle_id: U(35), has_stock: true, pmb_stage: 'BUS_4X4', work: W(['bus4x4'], ['bus4x4']), bookings: [{ stage_code: 'BUS_4X4', status: 'stoppage', stoppage_reason: '"quoted" & <b>' }] },
  { vehicle_id: U(36), has_stock: true, work: { Tyres: { required: true, completed: false }, parts: { required: true, completed: true } }, parts: {} },
  { vehicle_id: U(37), has_stock: true, work: W(['fitting'], ['fitting']), bookings: [{ stage_code: 'FITTING', status: 'started' }] },
  { vehicle_id: U(38), has_stock: true, pmb_stage: 'SUBLET', work: W(['sublet']), bookings: [{ stage_code: 'SUBLET', status: 'started' }] },
  { vehicle_id: U(39), has_stock: true, parts: { parts_required: true },
    parts_flags: { colour: 'orange', label: 'Parts outstanding — see job cards', meaning: 'Made-up meaning', last_successful_import_at: '2026-10-23T23:36:00Z' },
    jita_number: 'JSO121708' },
];

test('every fixture renders exactly the Control Board strip (app.js incomingWorkChecklistHtml + pdc-sublet-po.js decorateStrip)', () => {
  for (const entry of FIX) assert.equal(asBoard(salesHtml(entry)), boardHtml(entry), `vehicle ${entry.vehicle_id}`);
});

test('a started booking flashes that station only (is-started); queued, planned, stoppage and complete do not', () => {
  const started = salesHtml(F(24));
  assert.match(started, /pdc-station-electrical is-required is-booked is-started is-current-stage" title="Elec started"/);
  assert.match(started, /aria-label="Elec started"/);
  assert.match(started, /pdc-station-tyre is-required is-booked" title="Tyre booked"/);
  assert.doesNotMatch(started, /pdc-station-tyre[^"]*is-started/);
  assert.doesNotMatch(salesHtml(F(23)), /is-started/, 'planned and stoppage do not flash');
  assert.doesNotMatch(salesHtml(F(37)), /is-started/, 'a completed station does not flash');
  assert.doesNotMatch(salesHtml(F(38)), /is-started/, 'Sublet has no board stage, so a SUBLET booking is not a started icon');
  assert.equal((started.match(/is-started/g) || []).length, 1);
});

test('the icons follow the board order and legend', () => {
  const html = salesHtml(F(3));
  const order = [...html.matchAll(/incoming-work-check pdc-station-(\w+)/g)].map(m => m[1]);
  assert.deepEqual(order, ['parts', 'tint', 'bus4x4', 'hoist', 'fitting', 'fabrication', 'electrical', 'tyre', 'sublet']);
  const markers = h => [...h.matchAll(/<span class="incoming-work-box[^"]*" aria-hidden="true">([^<]*)<\/span>/g)].map(m => m[1]);
  assert.deepEqual(markers(salesHtml(F(1))), ['•', '–', '–', '–', '–', '–', '–', '–', '–'], 'not required = grey dash; stocked Parts required');
  assert.deepEqual(markers(salesHtml(F(4))).slice(0, 4), ['✓', '✓', '–', '✓'], 'complete = tick');
  assert.equal(markers(salesHtml(F(5)))[0], '!', 'parts ordered = !');
  assert.match(salesHtml(F(6)), /pdc-station-parts[^"]*is-blocked/);
  assert.match(salesHtml(F(22)), /pdc-station-tint[^"]*is-blocked[^"]*is-current-stage" title="TINT required - not signed off yet"/);
  assert.match(salesHtml(F(23)), /pdc-station-hoist[^"]*is-blocked[^"]*" title="Hoist STOPPAGE: Ram fault"/);
  assert.match(salesHtml(F(23)), /pdc-station-fitting is-required is-booked" title="Fitting booked"/);
  assert.match(salesHtml(F(29)), /is-po-to-raise[\s\S]*PO to raise<\/b>/);
  assert.match(salesHtml(F(29)), /title="Sublet: PO to raise: 2 whole line sublets have no GP PO yet"/);
  assert.match(salesHtml(F(32)), /pdc-station-sublet pdc-sublet-po-box is-complete"/);
  assert.doesNotMatch(salesHtml(F(35)), /<b>/, 'reasons are escaped');
});

test('mapping: work items, open QC lines, sublet bookings and parts as the board maps them', () => {
  const v = stations.toBoardVehicle(F(28));
  assert.equal(v.pdcRequiresBus4x4, true); assert.equal(v.pdcRequiresTint, true); assert.equal(v.pdcRequiresSublet, true);
  assert.equal(v.pdcRequiresPitInspection, true);
  assert.equal(stations.toBoardVehicle(F(27)).pdcCompleteSublet, true, 'only returned sublets = complete');
  assert.equal(stations.toBoardVehicle(F(25)).pdcCompleteSublet, false);
  assert.match(salesHtml(F(25)), /pdc-station-sublet is-required is-ordered is-booked" title="Sublet booked"/, 'one active sublet = booked');
  assert.doesNotMatch(salesHtml(F(26)), /pdc-station-sublet[^"]*is-booked/, 'two active sublets = required, as on the board');
  assert.equal(stations.toBoardVehicle(F(2)).pdcRequiresParts, false, 'no stock and no parts update = Parts not required');
  assert.equal(stations.toBoardVehicle(F(36)).pdcRequiresTyre, true);
  assert.equal(stations.toBoardVehicle(F(36)).pdcCompleteParts, true);
  assert.match(salesHtml(F(10)), /pdc-station-parts parts-jita-split is-complete has-jita" role="img" title="Parts Jita complete\. Navision JITA number 1234567\."/);
  assert.doesNotMatch(salesHtml(F(10)), /imported-parts-/, 'a green import with a verified JITA number is the full green tick');
  assert.match(salesHtml(F(11)), /imported-parts-orange no-jita/);
  assert.match(salesHtml(F(39)), /imported-parts-orange has-jita/);
  assert.match(salesHtml(F(39)), /parts-jita-marker" aria-hidden="true">✓/);
  assert.doesNotMatch(salesHtml(F(39)), /Parts Jita complete/, 'orange import keeps its colour; the JITA tick is the corner mark');
  assert.match(salesHtml(F(20)), /Parts Jita complete\. Navision JITA number 7654321/);
  assert.match(salesHtml(F(21)), /no-jita/, 'zero JITA is not a JITA');
  assert.doesNotMatch(salesHtml(F(21)), /Parts Jita complete/);
  for (const entry of FIX) for (const key of Object.keys(stations.toBoardVehicle(entry)))
    assert.doesNotMatch(key, /name|customer|client|by$|At$/i, 'no people or times in the mapped vehicle');
});

test('read only: no buttons, links, inputs or handlers; hover titles on every icon; wrapped for the Sales cell', () => {
  for (const entry of FIX) {
    const html = stations.entryHtml(entry);
    assert.match(html, /^<div class="sales-pmb-stations" role="group" aria-label="PMB stations \(read only\)">/);
    assert.doesNotMatch(html, /<(button|a|input|select)\b|data-open|onclick|tabindex|href=/i);
    assert.equal((html.match(/class="incoming-work-check /g) || []).length, 9);
    assert.equal((html.match(/<span class="incoming-work-check [^>]*\btitle="[^"]+"/g) || []).length, 9);
  }
  assert.equal(stations.entryHtml(null), '');
});

test('Sales wiring: linked rows only, short status text under the icons, mobile too, styles and scripts loaded with cache bust', () => {
  const sales = fs.readFileSync('sales/sales.js', 'utf8');
  assert.match(sales, /function pmbStationsHtml\(row\)\{return row&&row\.canonical_vehicle_id\?\(root\.BROOME_SALES_PMB_STATIONS\?\.html\?\.\(row\)\|\|''\):'';\}/);
  assert.match(sales, /\+icons\+'<span class="pmb-line"><strong>'/);
  assert.match(sales, /pmbStationsHtml\(row\)\+'<p class="mobile-pmb'/);
  const index = fs.readFileSync('sales/index.html', 'utf8');
  assert.match(index, /<link rel="stylesheet" href="pmb-stations\.css\?v=2026\.10\.23\.r499b">/);
  const order = ['../workshop-eligibility.js?', '../vehicle-requirements-guard.js?', 'pmb-stations.js?v=2026.10.23.r499b&amp;r518=2026.10.23.r518&amp;r524=2026.10.24.r524', 'sales.js?v='].map(s => index.indexOf('src="' + s));
  assert.ok(order.every(i => i > 0) && order.every((v, i) => !i || v > order[i - 1]), 'scripts load before sales.js');
  assert.match(index, /src="sales\.js\?v=2026\.10\.06\.01&amp;r499b=2026\.10\.23\.r499b&amp;[^"]*no-yard-flag=2026\.10\.22\.r486"/, 'sales.js keeps v= (manifest) and adds r499b');
  const build = fs.readFileSync('scripts/build_pages_runtime.js', 'utf8');
  assert.match(build, /'sales\/pmb-stations\.css', 'sales\/pmb-stations\.js'/);
  const css = fs.readFileSync('sales/pmb-stations.css', 'utf8');
  for (const rule of ['is-not-required', 'is-required', 'is-ordered', 'is-booked', 'is-complete', 'is-blocked', 'parts-jita-split', 'imported-parts-orange', 'pdc-sublet-po-raise'])
    assert.ok(css.includes('.sales-pmb-stations ') && css.includes(rule), rule);
  assert.doesNotMatch(css, /cursor:pointer/);
  // The board's colours, copied: required red, ordered/booked amber, complete green, stoppage red.
  for (const colour of ['#fff0f3', '#a3133b', '#fff7ed', '#9a3412', '#edf9f1', '#146c3b', '#ffe8e8', '#9f1111', '#c2410c']) assert.ok(css.includes(colour), colour);
  const pulse = name => {
    const block = fs.readFileSync(name, 'utf8').match(/@keyframes workshop-started-blue-pulse \{[\s\S]*?\n\}/);
    assert.ok(block, name);
    return block[0];
  };
  assert.equal(pulse('sales/pmb-stations.css'), pulse('workshop-planner.css'), 'started flash is the planner pulse, not a Sales-only animation');
  assert.match(css, /\.sales-pmb-stations \.incoming-work-check\.is-started\{[^}]*border-color:#2563eb;[^}]*background:#dbeafe;[^}]*animation:workshop-started-blue-pulse 1\.25s ease-in-out infinite\}/);
  assert.match(css, /@media \(prefers-reduced-motion: reduce\) \{\s*\.sales-pmb-stations \.incoming-work-check\.is-started \{ animation: none; \}/);
  assert.doesNotMatch(css, /@keyframes sales-/);
  assert.match(fs.readFileSync('sales/sales.js', 'utf8'), /pmbStationsHtml\(row\)\+'<p class="pmb-current'/);
});

test('migration and rollback ship LF only and are not referenced by any applied list', () => {
  for (const f of ['supabase/migrations/20261023040000_r499_sales_pmb_stations.sql', 'supabase/rollbacks/20261023040000_r499_sales_pmb_stations.down.sql']) {
    const text = fs.readFileSync(f, 'utf8');
    assert.doesNotMatch(text, /\r/); assert.match(text, /get_broome_sales_pmb_stations|pmb_stations_499/);
  }
  const up = fs.readFileSync('supabase/migrations/20261023040000_r499_sales_pmb_stations.sql', 'utf8');
  assert.match(up, /GRANT EXECUTE ON FUNCTION [^;]*public\.get_broome_sales_pmb_stations\(uuid\[\]\) TO authenticated;/i);
  assert.doesNotMatch(up, /TO anon\b/i);
  assert.doesNotMatch(up, /customer_name|client_name|first_name|last_name|email|phone/i, 'no personal fields');
});
