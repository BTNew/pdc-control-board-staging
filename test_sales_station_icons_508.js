/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r508 (F112): Sales PMB Status uses the PMB board station icons. A station flashes blue only while it is being worked.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const sales = require('./sales/sales.js');
const ID = '20261023113000_r508_sales_station_icons';
const up = fs.readFileSync(`supabase/migrations/${ID}.sql`, 'utf8');
const down = fs.readFileSync(`supabase/rollbacks/${ID}.down.sql`, 'utf8');
const log = fs.readFileSync('docs/FAULT_LOG.md', 'utf8');
const css = fs.readFileSync('sales/sales.css', 'utf8');
const js = fs.readFileSync('sales/sales.js', 'utf8');
const index = fs.readFileSync('sales/index.html', 'utf8');
const ORDER = ['parts', 'tint', 'bus4x4', 'hoist', 'fitting', 'fabrication', 'electrical', 'tyre', 'sublet'];
const LABELS = ['Parts / JITA', 'Tint', 'Bus 4x4', 'Hoist', 'Fitting', 'Fab', 'Elec', 'Tyre', 'Sublet'];

function row(extra = {}) {
  return { tracking_id: 't1', canonical_vehicle_id: 'v1', stock: 'S1', pmb_location: 'PMB', bay_bookings: [], ...extra };
}
function booking(status, stage, extra = {}) {
  return { status, stage, bay: 'Bay 01', ...extra };
}
function cell(states, key) {
  return states.find(station => station.key === key);
}
function htmlOf(record) {
  return sales.salesStationStrip(record);
}

test('board order, glyphs and the blue flash follow projectWorkState plus started/open', () => {
  const required = sales.salesStationStates(row({ pmb_work: [{ work_key: 'tint', required: true, completed: false }] }));
  assert.deepEqual(required.map(station => station.key), ORDER);
  assert.deepEqual(required.map(station => station.label), LABELS);
  assert.equal(cell(required, 'tint').state, 'required');
  assert.equal(cell(required, 'tint').marker, '•');
  assert.equal(cell(required, 'tint').working, false);
  const requiredHtml = htmlOf(row({ pmb_work: [{ work_key: 'tint', required: true, completed: false }] }));
  assert.match(requiredHtml, /pdc-station-tint[^"]*is-required/);
  assert.doesNotMatch(requiredHtml, /pdc-station-tint[^"]*is-working/);
  assert.doesNotMatch(requiredHtml, /pdc-station-tint[^"]*is-booked/);

  const planned = sales.salesStationStates(row({
    bay_bookings: [booking('planned', 'Fitting')],
    pmb_work: [{ work_key: 'fitting', required: true, completed: false }],
  }));
  assert.equal(cell(planned, 'fitting').marker, '!');
  assert.equal(cell(planned, 'fitting').state, 'booked');
  assert.equal(cell(planned, 'fitting').working, false);
  assert.match(htmlOf(row({
    bay_bookings: [booking('planned', 'Fitting')],
    pmb_work: [{ work_key: 'fitting', required: true, completed: false }],
  })), /pdc-station-fitting[^"]*is-booked/);
  assert.doesNotMatch(htmlOf(row({
    bay_bookings: [booking('planned', 'Fitting')],
    pmb_work: [{ work_key: 'fitting', required: true, completed: false }],
  })), /pdc-station-fitting[^"]*is-working/);

  const started = sales.salesStationStates(row({ bay_bookings: [booking('started', 'Fitting', { stage_code: 'FITTING' })] }));
  assert.equal(cell(started, 'fitting').marker, '!');
  assert.equal(cell(started, 'fitting').state, 'booked');
  assert.equal(cell(started, 'fitting').working, true);
  const startedHtml = htmlOf(row({ bay_bookings: [booking('started', 'Bus 4x4')] }));
  assert.match(startedHtml, /pdc-station-bus4x4[^"]*is-working/);
  assert.match(startedHtml, /pdc-station-bus4x4[\s\S]*?<span class="incoming-work-box" aria-hidden="true">!<\/span>/);

  const queued = sales.salesStationStates(row({ bay_bookings: [booking('queued', 'Hoist')] }));
  assert.equal(cell(queued, 'hoist').working, false);
  assert.equal(cell(queued, 'hoist').state, 'booked');

  const done = sales.salesStationStates(row({
    bay_bookings: [booking('started', 'Fitting')],
    pmb_work: [{ work_key: 'fitting', required: true, completed: true }],
  }));
  assert.equal(cell(done, 'fitting').marker, '✓');
  assert.equal(cell(done, 'fitting').state, 'completed');
  assert.equal(cell(done, 'fitting').working, false);
  assert.match(htmlOf(row({
    bay_bookings: [booking('started', 'Fitting')],
    pmb_work: [{ work_key: 'fitting', required: true, completed: true }],
  })), /pdc-station-fitting[^"]*is-complete/);
  assert.doesNotMatch(htmlOf(row({
    bay_bookings: [booking('started', 'Fitting')],
    pmb_work: [{ work_key: 'fitting', required: true, completed: true }],
  })), /pdc-station-fitting[^"]*is-working/);

  const stopped = sales.salesStationStates(row({
    bay_bookings: [booking('stoppage', 'Fab'), booking('started', 'Fab')],
    pmb_work: [{ work_key: 'fabrication', required: true, completed: false }],
  }));
  assert.equal(cell(stopped, 'fabrication').marker, '!');
  assert.equal(cell(stopped, 'fabrication').state, 'stoppage');
  assert.equal(cell(stopped, 'fabrication').working, false);
  assert.match(htmlOf(row({ bay_bookings: [booking('stoppage', 'Elec')] })), /pdc-station-electrical[^"]*is-blocked/);
  assert.doesNotMatch(htmlOf(row({ bay_bookings: [booking('stoppage', 'Elec')] })), /pdc-station-electrical[^"]*is-working/);

  const notRequired = sales.salesStationStates(row({
    bay_bookings: [booking('started', 'Tyre')],
    pmb_work: [{ work_key: 'tyre', required: false, completed: false }],
  }));
  assert.equal(cell(notRequired, 'tyre').state, 'none');
  assert.equal(cell(notRequired, 'tyre').marker, '–');
  assert.equal(cell(notRequired, 'tyre').working, false);
});

test('Parts / JITA split and sublet open use the board markers', () => {
  const ordered = htmlOf(row({
    parts: { ordered: true, required: true },
    jita: 'J1',
    pmb_work: [{ work_key: 'parts', required: true, completed: false }],
  }));
  assert.match(ordered, /pdc-station-parts[^"]*parts-jita-split has-jita/);
  assert.match(ordered, /parts-jita-parts-marker" aria-hidden="true">!<\/span><span class="parts-jita-marker" aria-hidden="true">✓/);
  assert.doesNotMatch(ordered, /pdc-station-parts[^"]*is-working/);
  const empty = htmlOf(row({ jita: '' }));
  assert.match(empty, /pdc-station-parts[^"]*no-jita/);
  assert.match(empty, /parts-jita-marker" aria-hidden="true">●/);
  const open = sales.salesStationStates(row({
    pmb_sublet: 'open',
    pmb_work: [{ work_key: 'sublet', required: true, completed: false }],
  }));
  assert.equal(cell(open, 'sublet').state, 'booked');
  assert.equal(cell(open, 'sublet').marker, '!');
  assert.equal(cell(open, 'sublet').working, true);
  const future = sales.salesStationStates(row({
    pmb_sublet: 'booked',
    pmb_work: [{ work_key: 'sublet', required: true, completed: false }],
  }));
  assert.equal(cell(future, 'sublet').working, false);
  assert.equal(cell(future, 'sublet').state, 'booked');
});

test('unlinked and completed rows have no strip; a server array is rendered as given', () => {
  assert.equal(sales.salesStationStrip(row({ canonical_vehicle_id: null, bay_bookings: [booking('started', 'Fitting')] })), '');
  assert.equal(sales.salesStationStrip(row({ lifecycle_state: 'completed', bay_bookings: [booking('started', 'Fitting')] })), '');
  assert.equal(sales.salesStationStrip(row({ pmb_location: ' Completed ', bay_bookings: [booking('started', 'Fitting')] })), '');
  const custom = [{ key: 'parts', label: 'Parts / JITA', state: 'none', marker: 'Z', working: false, jita: false }];
  while (custom.length < 9) custom.push({ key: ORDER[custom.length], label: LABELS[custom.length], state: 'none', marker: '–', working: false, jita: null });
  const html = sales.salesStationStrip(row({ pmb_stations: custom, bay_bookings: [booking('started', 'Fitting')] }));
  assert.match(html, /aria-hidden="true">Z<\/span>/);
  assert.doesNotMatch(html, /is-working/);
});

test('the strip is in the table, mobile card and detail, and the r434 wash stays', () => {
  assert.match(js, /salesStationStrip\(row\)/);
  assert.match(js, /class="mobile-pmb'\+\(pmbStatusTone\(pmbSummary\(row\)\)\?' pmb-running':''\)/);
  assert.match(js, /class="pmb-current'\+\(pmbStatusTone\(summary\)\?' pmb-running':''\)/);
  assert.match(index, /sales\.js\?[^"]*pmb-running=2026\.10\.21\.06/);
  assert.match(index, /sales\.css\?[^"]*pmb-running=2026\.10\.21\.06/);
  assert.match(index, /sales\.js\?[^"]*&amp;r508=2026\.10\.23\.r508/);
  assert.match(index, /sales\.css\?[^"]*&amp;r508=2026\.10\.23\.r508/);
  assert.match(css, /#vehicle-table td\.pmb-status-cell\.pmb-running,\.data-table td\.pmb-status-cell\.pmb-running\{background:#dbeafe;box-shadow:inset 3px 0 0 #2563eb;color:#1e3a8a\}/);
  assert.match(css, /\.sales-station-strip \.incoming-work-check\.is-required\{border-color:#ee9caf;background:#fff0f3;color:#a3133b\}/);
  assert.match(css, /\.sales-station-strip \.incoming-work-check\.is-booked\{border-color:#fdba74;background:#fff7ed;color:#9a3412\}/);
  assert.match(css, /\.sales-station-strip \.incoming-work-check\.is-complete\{border-color:#75c795;background:#edf9f1;color:#146c3b\}/);
  assert.match(css, /\.sales-station-strip \.incoming-work-check\.is-blocked\{border-color:#d93434;background:#ffe8e8;color:#9f1111/);
  assert.match(css, /@keyframes sales-station-working/);
  assert.match(css, /prefers-reduced-motion:reduce/);
  assert.match(css, /grid-template-columns:repeat\(9,52px\)/);
});

test('migration is guarded, LF, pins 212 to 216, and does not rewrite the r420 snapshots', () => {
  assert.doesNotMatch(up, /\r/);
  assert.doesNotMatch(down, /\r/);
  assert.ok(!up.includes('vjdtsswhroyguxyfjdkt') && !down.includes('vjdtsswhroyguxyfjdkt'));
  assert.ok(!up.slice(0, 400).includes('Specialise Pty Ltd'));
  assert.ok(!down.slice(0, 400).includes('Specialise Pty Ltd'));
  assert.match(up, /pdc_monitor_staging_guard\(\)/);
  assert.match(up, /cdsmnqxtyyoeoznmbidd/);
  assert.match(up, /NOT BETWEEN 2 AND 45/);
  assert.match(up, /^SET LOCAL lock_timeout = '2s';$/m);
  assert.match(up, /expected 212 pins at tip/);
  assert.match(up, /expected 216 pins/);
  assert.match(down, /pin count is not 216/);
  assert.match(down, /pin count is not 212/);
  assert.match(up, /e57e0904890225fad39c5e41ee1b14ef/);
  assert.match(up, /37a9d2d92ce5c34e8617a0058cfd3e4f/);
  assert.doesNotMatch(up, /CREATE OR REPLACE FUNCTION pdc_sales_private\.visibility_source_snapshot/);
  assert.doesNotMatch(up, /CREATE OR REPLACE FUNCTION pdc_sales_private\.board_visibility_source_snapshot/);
  assert.doesNotMatch(up, /CREATE (OR REPLACE )?FUNCTION public\.workshop_clock_tick/);
  assert.match(up, /CREATE FUNCTION pdc_sales_private\.station_icons/);
  assert.match(up, /'started'/);
  assert.match(up, /sublet = 'open'/);
  assert.match(up, /sales_snapshot_508/);
  assert.match(up, /sales_board_snapshot_508/);
  assert.match(down, /snapshot_with_autocare\(\)/);
  assert.match(down, /board_snapshot_with_autocare\(\)/);
  assert.match(up, /sales_station_icons_508', 'F112'/);
  assert.match(up, /true, 293, 'r508'\)/);
  assert.match(up, /SELECT count\(\*\) = 1 FROM keys WHERE/);
  assert.doesNotMatch(up, /count\(\*\)=1 AND [a-z]+ LIKE/);
  assert.doesNotMatch(up.replace(/--[^\n]*/g, ''), /app\.js|pdc-qc-rework\.js|karratha/);
  assert.match(log, /\| F112 \|/);
  assert.ok(log.indexOf('| F111 |') < log.indexOf('| F112 |'));
  assert.ok(log.indexOf('| F112 |') < log.indexOf('| F113 |'));
  const f112 = log.split('\n').find(line => line.startsWith('| F112 |'));
  assert.equal(f112.split('|').length, 10);
});
