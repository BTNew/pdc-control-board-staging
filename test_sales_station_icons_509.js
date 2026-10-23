/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r509 (F112): Sales PMB Status uses the Control Board station icons.
// is-started flashes with the planner pulse only while an open booking for that stage has status started.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const sales = require('./sales/sales.js');
const ID = '20261023140000_r509_sales_station_icons';
const up = fs.readFileSync(`supabase/migrations/${ID}.sql`, 'utf8');
const down = fs.readFileSync(`supabase/rollbacks/${ID}.down.sql`, 'utf8');
const log = fs.readFileSync('docs/FAULT_LOG.md', 'utf8');
const css = fs.readFileSync('sales/sales.css', 'utf8');
const stations = fs.readFileSync('sales/pmb-stations.css', 'utf8');
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

test('board order and glyphs; started flashes only for an open started booking', () => {
  const required = sales.salesStationStates(row({ pmb_work: [{ work_key: 'tint', required: true, completed: false }] }));
  assert.deepEqual(required.map(station => station.key), ORDER);
  assert.deepEqual(required.map(station => station.label), LABELS);
  assert.equal(cell(required, 'tint').state, 'required');
  assert.equal(cell(required, 'tint').marker, '•');
  assert.equal(cell(required, 'tint').started, false);
  const requiredHtml = htmlOf(row({ pmb_work: [{ work_key: 'tint', required: true, completed: false }] }));
  assert.match(requiredHtml, /pdc-station-tint[^"]*is-required/);
  assert.doesNotMatch(requiredHtml, /is-started/);
  assert.doesNotMatch(requiredHtml, /pdc-station-tint[^"]*is-booked/);

  const planned = sales.salesStationStates(row({
    bay_bookings: [booking('planned', 'Fitting')],
    pmb_work: [{ work_key: 'fitting', required: true, completed: false }],
  }));
  assert.equal(cell(planned, 'fitting').marker, '!');
  assert.equal(cell(planned, 'fitting').state, 'booked');
  assert.equal(cell(planned, 'fitting').started, false);
  assert.match(htmlOf(row({
    bay_bookings: [booking('planned', 'Fitting')],
    pmb_work: [{ work_key: 'fitting', required: true, completed: false }],
  })), /pdc-station-fitting[^"]*is-booked/);
  assert.doesNotMatch(htmlOf(row({
    bay_bookings: [booking('planned', 'Fitting')],
    pmb_work: [{ work_key: 'fitting', required: true, completed: false }],
  })), /is-started/);

  const started = sales.salesStationStates(row({ bay_bookings: [booking('started', 'Fitting', { stage_code: 'FITTING' })] }));
  assert.equal(cell(started, 'fitting').marker, '!');
  assert.equal(cell(started, 'fitting').state, 'booked');
  assert.equal(cell(started, 'fitting').started, true);
  const startedHtml = htmlOf(row({ bay_bookings: [booking('started', 'Bus 4x4')] }));
  assert.match(startedHtml, /pdc-station-bus4x4[^"]*is-booked[^"]*is-started/);
  assert.match(startedHtml, /pdc-station-bus4x4[\s\S]*?<span class="incoming-work-box" aria-hidden="true">!<\/span>/);

  const queued = sales.salesStationStates(row({ bay_bookings: [booking('queued', 'Hoist')] }));
  assert.equal(cell(queued, 'hoist').started, false);
  assert.equal(cell(queued, 'hoist').state, 'booked');

  const done = sales.salesStationStates(row({
    bay_bookings: [booking('started', 'Fitting')],
    pmb_work: [{ work_key: 'fitting', required: true, completed: true }],
  }));
  assert.equal(cell(done, 'fitting').marker, '✓');
  assert.equal(cell(done, 'fitting').state, 'completed');
  assert.equal(cell(done, 'fitting').started, false);
  const doneHtml = htmlOf(row({
    bay_bookings: [booking('started', 'Fitting')],
    pmb_work: [{ work_key: 'fitting', required: true, completed: true }],
  }));
  assert.match(doneHtml, /pdc-station-fitting[^"]*is-complete/);
  assert.doesNotMatch(doneHtml, /is-started/);

  const stopped = sales.salesStationStates(row({
    bay_bookings: [booking('stoppage', 'Fab'), booking('started', 'Fab')],
    pmb_work: [{ work_key: 'fabrication', required: true, completed: false }],
  }));
  assert.equal(cell(stopped, 'fabrication').marker, '!');
  assert.equal(cell(stopped, 'fabrication').state, 'stoppage');
  assert.equal(cell(stopped, 'fabrication').started, false);
  const blockedHtml = htmlOf(row({ bay_bookings: [booking('stoppage', 'Elec'), booking('started', 'Elec')] }));
  assert.match(blockedHtml, /pdc-station-electrical[^"]*is-blocked/);
  assert.doesNotMatch(blockedHtml, /is-started/);

  const notRequired = sales.salesStationStates(row({
    bay_bookings: [booking('started', 'Tyre')],
    pmb_work: [{ work_key: 'tyre', required: false, completed: false }],
  }));
  assert.equal(cell(notRequired, 'tyre').state, 'none');
  assert.equal(cell(notRequired, 'tyre').marker, '–');
  assert.equal(cell(notRequired, 'tyre').started, false);
  assert.doesNotMatch(htmlOf(row({
    bay_bookings: [booking('started', 'Tyre')],
    pmb_work: [{ work_key: 'tyre', required: false, completed: false }],
  })), /is-started/);

  const deleted = sales.salesStationStates(row({
    bay_bookings: [booking('started', 'Fitting', { deleted_at: '2026-10-23T00:00:00Z' })],
    pmb_work: [{ work_key: 'fitting', required: true, completed: false }],
  }));
  assert.equal(cell(deleted, 'fitting').state, 'required');
  assert.equal(cell(deleted, 'fitting').started, false);
});

test('Parts / JITA split stays orange; only a started SUBLET booking flashes', () => {
  const ordered = htmlOf(row({
    parts: { ordered: true, required: true },
    jita: 'J1',
    pmb_work: [{ work_key: 'parts', required: true, completed: false }],
  }));
  assert.match(ordered, /pdc-station-parts[^"]*parts-jita-split has-jita/);
  assert.match(ordered, /parts-jita-parts-marker" aria-hidden="true">!<\/span><span class="parts-jita-marker" aria-hidden="true">✓/);
  assert.doesNotMatch(ordered, /is-started/);
  const empty = htmlOf(row({ jita: '' }));
  assert.match(empty, /pdc-station-parts[^"]*no-jita/);
  assert.match(empty, /parts-jita-marker" aria-hidden="true">●/);
  const open = sales.salesStationStates(row({
    pmb_sublet: 'open',
    pmb_work: [{ work_key: 'sublet', required: true, completed: false }],
  }));
  assert.equal(cell(open, 'sublet').state, 'booked');
  assert.equal(cell(open, 'sublet').marker, '!');
  assert.equal(cell(open, 'sublet').started, false);
  assert.doesNotMatch(htmlOf(row({
    pmb_sublet: 'open',
    pmb_work: [{ work_key: 'sublet', required: true, completed: false }],
  })), /is-started/);
  const future = sales.salesStationStates(row({
    pmb_sublet: 'booked',
    pmb_work: [{ work_key: 'sublet', required: true, completed: false }],
  }));
  assert.equal(cell(future, 'sublet').started, false);
  assert.equal(cell(future, 'sublet').state, 'booked');
  const subletStarted = sales.salesStationStates(row({
    bay_bookings: [booking('started', 'Sublet', { stage_code: 'SUBLET' })],
    pmb_sublet: 'open',
    pmb_work: [{ work_key: 'sublet', required: true, completed: false }],
  }));
  assert.equal(cell(subletStarted, 'sublet').started, true);
  assert.match(htmlOf(row({
    bay_bookings: [booking('started', 'Sublet')],
    pmb_work: [{ work_key: 'sublet', required: true, completed: false }],
  })), /pdc-station-sublet[^"]*is-started/);
});

test('unlinked and completed rows have no strip; a server array does not flash complete or blocked', () => {
  assert.equal(sales.salesStationStrip(row({ canonical_vehicle_id: null, bay_bookings: [booking('started', 'Fitting')] })), '');
  assert.equal(sales.salesStationStrip(row({ lifecycle_state: 'completed', bay_bookings: [booking('started', 'Fitting')] })), '');
  assert.equal(sales.salesStationStrip(row({ pmb_location: ' Completed ', bay_bookings: [booking('started', 'Fitting')] })), '');
  const custom = [{ key: 'parts', label: 'Parts / JITA', state: 'none', marker: 'Z', started: false, jita: false }];
  while (custom.length < 9) custom.push({ key: ORDER[custom.length], label: LABELS[custom.length], state: 'none', marker: '–', started: false, jita: null });
  custom[4] = { key: 'fitting', label: 'Fitting', state: 'booked', marker: '!', started: true, jita: null };
  custom[5] = { key: 'fabrication', label: 'Fab', state: 'completed', marker: '✓', started: true, jita: null };
  custom[6] = { key: 'electrical', label: 'Elec', state: 'stoppage', marker: '!', started: true, jita: null };
  const html = sales.salesStationStrip(row({ pmb_stations: custom, bay_bookings: [booking('started', 'Tint')] }));
  assert.match(html, /aria-hidden="true">Z<\/span>/);
  assert.match(html, /pdc-station-fitting[^"]*is-started/);
  assert.match(html, /pdc-station-fabrication[^"]*is-complete/);
  assert.doesNotMatch(html, /pdc-station-fabrication[^"]*is-started/);
  assert.match(html, /pdc-station-electrical[^"]*is-blocked/);
  assert.doesNotMatch(html, /pdc-station-electrical[^"]*is-started/);
  assert.doesNotMatch(html, /pdc-station-tint[^"]*is-started/);
});

test('the strip is linked from Sales and uses the planner pulse; the r434 wash stays', () => {
  assert.match(js, /salesStationStrip\(row\)/);
  assert.match(js, /class="mobile-pmb'\+\(pmbStatusTone\(pmbSummary\(row\)\)\?' pmb-running':''\)/);
  assert.match(js, /class="pmb-current'\+\(pmbStatusTone\(summary\)\?' pmb-running':''\)/);
  assert.match(index, /sales\.js\?[^"]*pmb-running=2026\.10\.21\.06/);
  assert.match(index, /sales\.css\?[^"]*pmb-running=2026\.10\.21\.06/);
  assert.match(index, /sales\.js\?[^"]*&amp;r509=2026\.10\.23\.r509/);
  assert.match(index, /pmb-stations\.css\?v=2026\.10\.23\.r509/);
  assert.doesNotMatch(index, /r508=/);
  assert.match(css, /#vehicle-table td\.pmb-status-cell\.pmb-running,\.data-table td\.pmb-status-cell\.pmb-running\{background:#dbeafe;box-shadow:inset 3px 0 0 #2563eb;color:#1e3a8a\}/);
  assert.doesNotMatch(css, /is-started|sales-station-working|workshop-started-blue-pulse/);
  assert.doesNotMatch(stations.replace(/\/\*[\s\S]*?\*\//g, ''), /!important/);
  assert.match(stations, /\.sales-station-strip \.incoming-work-check\.is-required\{border-color:#ee9caf;background:#fff0f3;color:#a3133b\}/);
  assert.match(stations, /\.sales-station-strip \.incoming-work-check\.is-booked\{border-color:#fdba74;background:#fff7ed;color:#9a3412\}/);
  assert.match(stations, /\.sales-station-strip \.incoming-work-check\.is-complete\{border-color:#75c795;background:#edf9f1;color:#146c3b\}/);
  assert.match(stations, /\.sales-station-strip \.incoming-work-check\.is-blocked\{border-color:#d93434;background:#ffe8e8;color:#9f1111/);
  assert.ok(stations.indexOf('.is-booked{') < stations.indexOf('.is-started:not(.is-complete):not(.is-blocked)'));
  assert.ok(stations.indexOf('.is-started:not(.is-complete):not(.is-blocked)') < stations.indexOf('.is-complete{'));
  assert.match(stations, /@keyframes workshop-started-blue-pulse \{\n  0%, 100% \{ background: #dbeafe; box-shadow: 0 0 0 1px rgba\(37,99,235,\.2\), 0 2px 5px rgba\(15,23,42,\.12\); \}\n  50% \{ background: #93c5fd; box-shadow: 0 0 0 4px rgba\(37,99,235,\.32\), 0 5px 12px rgba\(30,64,175,\.22\); \}\n\}/);
  assert.match(stations, /animation:workshop-started-blue-pulse 1\.25s ease-in-out infinite/);
  assert.match(stations, /prefers-reduced-motion: reduce\) \{\n  \.sales-station-strip \.incoming-work-check\.is-started:not\(\.is-complete\):not\(\.is-blocked\)\{animation:none;background:#dbeafe\}/);
  assert.match(stations, /grid-template-columns:repeat\(9,52px\)/);
  assert.match(stations, /parts-jita-split/);
});

test('migration is guarded, LF, pins 212 to 216, and does not collide with merged r508', () => {
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
  assert.match(up, /working := started;/);
  assert.doesNotMatch(up, /working := started OR/);
  assert.match(up, /'started', working/);
  assert.match(up, /sublet IN \('open', 'booked'\)/);
  assert.match(up, /sales_snapshot_509/);
  assert.match(up, /sales_board_snapshot_509/);
  assert.match(down, /snapshot_with_autocare\(\)/);
  assert.match(down, /board_snapshot_with_autocare\(\)/);
  assert.match(up, /sales_station_icons_509', 'F112'/);
  assert.match(up, /true, 294, 'r509'\)/);
  assert.match(up, /outlook_sales_receipt_message_id_508' AND added_in='r508' AND sort_order=293 AND fault_id='F121'/);
  assert.doesNotMatch(up, /added_in='r508' OR/);
  assert.doesNotMatch(up, /sort_order=293 OR/);
  assert.doesNotMatch(down, /DELETE FROM pdc_ops\.regression_checks WHERE[^;]*added_in='r508'/);
  assert.doesNotMatch(down, /DELETE FROM pdc_ops\.expected_function_md5 WHERE release='r508'/);
  assert.match(up, /SELECT count\(\*\) = 1 FROM keys WHERE/);
  assert.match(up, /count\(\*\) = 14 FROM ev/);
  assert.doesNotMatch(up, /count\(\*\)=1 AND [a-z]+ LIKE/);
  assert.doesNotMatch(up.replace(/--[^\n]*/g, ''), /app\.js|pdc-qc-rework\.js|karratha/);
  assert.doesNotMatch(fs.readdirSync('supabase/migrations').join('\n'), /r508_sales_station_icons/);
  assert.match(log, /\| F112 \|/);
  assert.ok(log.indexOf('| F111 |') < log.indexOf('| F112 |'));
  assert.ok(log.indexOf('| F112 |') < log.indexOf('| F113 |'));
  assert.ok(log.indexOf('| F120 |') < log.indexOf('| F121 |'));
  const f112 = log.split('\n').find(line => line.startsWith('| F112 |'));
  assert.equal(f112.split('|').length, 10);
});
