/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r799 (F409, Craig 1 Nov 2026 08:16): Vehicle Locations station columns follow the Department filter.
// All departments: today's 9 columns. 139: no Bus 4x4. 138: Mechanical, Accessories, Electrical, QA, Pit instead of Bus 4x4.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const guard = require('./vehicle-requirements-guard.js');
const eligibility = require('./workshop-eligibility.js');
const table = require('./pdc-vehicle-locations-table.js');

function source(name) {
  const lines = fs.readFileSync('app.js', 'utf8').split('\n');
  const start = lines.findIndex(line => new RegExp(`^(?:async )?function ${name}\\(|^const ${name} = `).test(line));
  assert.ok(start >= 0, name);
  if (/;\s*$/.test(lines[start]) && !/[[{(]\s*$/.test(lines[start])) return lines[start];
  for (let i = start + 1; i < lines.length; i += 1) if (/^[}\])]/.test(lines[i])) return lines.slice(start, i + 1).join('\n');
  throw new Error('unterminated ' + name);
}
function board(department = '') {
  const names = ['NAVISION_JITA_NUMBER_AUTHORITY', 'PDC_JOB_DEFS', 'PDC_JOB_BY_KEY', 'PMB_STAGE_TO_JOB_KEY', 'PDC_GRID_JOB_LABELS', 'PRODUCTION_FLOW_DEFS',
    'PDC_BUS_CATEGORY_DEFS', 'PDC_BUS_CATEGORY_BY_KEY', 'pdcJobDefsForDepartment', 'pdcVehicleLocationsStationDefs', 'busCategoryState', 'busCategoryCheckHtml',
    'pmbStageForPdcJob', 'normalizePmbStage', 'inferredPmbStage', 'isPdcBlocked', 'pdcBlockReason', 'pdcJobRequired', 'pdcJobComplete',
    'pdcJobTriState', 'pdcJobCompletionTitle', 'pdcJobDefsPartsFirst', 'pdcGridJobLabel', 'parseIsoTimestamp', 'isBlankStock',
    'vehicleHasBatchNumber', 'vehicleNavisionJitaNumber', 'cleanNavisionText', 'escapeHtml', 'canonicalVehicleWorkState',
    'canonicalActiveSubletBooking', 'partsJobDef', 'partsStateComplete', 'isActivePartsStoppage', 'partsOrdered', 'importedPartsStatus',
    'importedPartsTitle', 'pdcStationLinesMakeComplete', 'pdcStationLinesOverrideBy', 'incomingWorkChecklistHtml', 'productionGridHeaderHtml',
    'stationIconCompletionSignature', 'storeStationIconCompletion'];
  const ctx = {
    window: { VehicleRequirementsGuard: guard, PDC_WORKSHOP_ELIGIBILITY: eligibility },
    WORKSHOP_ELIGIBILITY: eligibility,
    WORKSHOP_CANONICAL_STATION_DEFS: eligibility.stationDefinitions,
    vehicleKey: () => 'sample',
    pmbArrivalVehicleId: vehicle => String(vehicle.id || ''),
    pdcJobFallbackRequired: () => false,
    incomingDepartmentFilterValue: () => department,
    app: { stationIconCompletion: new Map() },
  };
  vm.runInNewContext(`${names.map(source).join('\n')}\nthis.api = { incomingWorkChecklistHtml, productionGridHeaderHtml, pdcJobDefsForDepartment, pdcVehicleLocationsStationDefs, pdcJobRequired, pdcJobComplete, busCategoryState, storeStationIconCompletion, PDC_JOB_BY_KEY, PDC_BUS_CATEGORY_BY_KEY, app };`, ctx);
  return ctx;
}
const keysOf = html => Array.from(html.match(/pdc-station-(?!strip\b)\w+/g) || [], k => k.slice('pdc-station-'.length));
const ID = '00000000-0000-4000-8000-000000000138';
const busCar = () => ({ id: ID, pdcRequiresBus4x4: true, pdcQcOperationLines: [
  { lineIdentity: 'a', department: '138', stageCode: 'BUS_4X4', workCategory: 'BUS_MECHANICAL', active: true },
  { lineIdentity: 'b', department: '138', stageCode: 'BUS_4X4', workCategory: 'BUS_ELECTRICAL', active: true },
  { lineIdentity: 'c', department: '138', stageCode: 'BUS_4X4', workCategory: 'BUS_ELECTRICAL', active: false },
] });

test('r799: columns per department; every other screen keeps the 9 standard columns', () => {
  const ctx = board('');
  const keys = list => Array.from(list, def => def.key);
  assert.deepEqual(keys(ctx.api.pdcJobDefsForDepartment('')), ['parts', 'tint', 'bus4x4', 'hoist', 'fitting', 'fabrication', 'electrical', 'tyre', 'sublet']);
  assert.deepEqual(keys(ctx.api.pdcJobDefsForDepartment('139')), ['parts', 'tint', 'hoist', 'fitting', 'fabrication', 'electrical', 'tyre', 'sublet']);
  assert.deepEqual(keys(ctx.api.pdcJobDefsForDepartment('138')), ['parts', 'busMechanical', 'busAccessories', 'busElectrical', 'busQa', 'busPit', 'tint', 'tyre', 'sublet']);
  assert.deepEqual(keys(ctx.api.pdcVehicleLocationsStationDefs()), keys(ctx.api.pdcJobDefsForDepartment('')));
  assert.deepEqual(keys(board('138').api.pdcVehicleLocationsStationDefs()), keys(ctx.api.pdcJobDefsForDepartment('138')));
  // No stationDefs option: the strip and header are exactly today's.
  assert.deepEqual(keysOf(ctx.api.incomingWorkChecklistHtml(busCar(), { bookingProjection: { bookingRequired: false, activeBookings: [] } })), keys(ctx.api.pdcJobDefsForDepartment('')));
  assert.deepEqual(Array.from(ctx.api.productionGridHeaderHtml('x', {}).match(/pdc-grid-station-(?!heading\b)\w+/g) || [], k => k.slice(17)), keys(ctx.api.pdcJobDefsForDepartment('')));
});

test('r799: Department 138 strip: lines make a category required, server rows make it complete / booked / stoppage', () => {
  const ctx = board('138');
  const defs = ctx.api.pdcJobDefsForDepartment('138');
  const strip = () => ctx.api.incomingWorkChecklistHtml(busCar(), { stationDefs: defs, bookingProjection: { bookingRequired: false, activeBookings: [] } });
  let html = strip();
  assert.deepEqual(keysOf(html), Array.from(defs, def => def.key));
  assert.match(html, /pdc-station-busMechanical is-required"/);
  assert.match(html, /pdc-station-busElectrical is-required"/);
  assert.match(html, /pdc-station-busAccessories is-not-required"/);
  assert.doesNotMatch(html, /pdc-station-bus4x4\b/);
  ctx.api.storeStationIconCompletion([ID], [
    { vehicle_id: ID, work_key: 'bus4x4', complete: true, override: false },
    { vehicle_id: ID, work_key: 'bus4x4:BUS_MECHANICAL', category: 'BUS_MECHANICAL', total: 1, done: 1, complete: true, booked: false, stoppage: false },
    { vehicle_id: ID, work_key: 'bus4x4:BUS_ELECTRICAL', category: 'BUS_ELECTRICAL', total: 1, done: 0, complete: false, booked: true, stoppage: false },
    { vehicle_id: ID, work_key: 'bus4x4:BUS_QA', category: 'BUS_QA', total: 2, done: 0, complete: false, booked: false, stoppage: true, stoppage_reason: 'parts' },
  ], 1);
  assert.equal(ctx.api.app.stationIconCompletion.get(ID).bus4x4.complete, true, 'the r578 row still lands in the station map');
  assert.equal(ctx.api.app.stationIconCompletion.get(ID)['bus4x4:BUS_MECHANICAL'], undefined, 'category rows never enter the station map');
  html = strip();
  assert.match(html, /pdc-station-busMechanical is-required is-complete" title="Mechanical complete · 1 of 1 lines ticked"/);
  assert.match(html, /pdc-station-busElectrical is-required is-booked" title="Electrical booked · 0 of 1 lines ticked"/);
  assert.match(html, /pdc-station-busQa is-required is-blocked" title="QA STOPPAGE: parts · 0 of 2 lines ticked"/);
  assert.match(html, /pdc-station-busPit is-not-required"/);
  const mech = ctx.api.PDC_BUS_CATEGORY_BY_KEY.get('busMechanical');
  assert.equal(ctx.api.pdcJobRequired(busCar(), mech), true);
  assert.equal(ctx.api.pdcJobComplete(busCar(), mech), true);
  assert.equal(ctx.api.pdcJobComplete(busCar(), ctx.api.PDC_BUS_CATEGORY_BY_KEY.get('busElectrical')), false);
  // Heading filters (r792/r795) work on category columns through the same functions.
  const deps = { pdcVehicleLocationsStationDefs: () => defs, pdcJobRequired: ctx.api.pdcJobRequired, pdcJobComplete: ctx.api.pdcJobComplete, pdcGridJobLabel: def => def.gridLabel || def.label };
  assert.equal(table.stationNeeds(busCar(), 'busElectrical', deps), true);
  assert.equal(table.stationNeeds(busCar(), 'busMechanical', deps), false);
  assert.equal(table.stationDone(busCar(), 'busMechanical', deps), true);
  assert.equal(table.stationLabel('busMechanical', deps), 'Mechanical');
  assert.match(ctx.api.productionGridHeaderHtml('x', { stationDefs: defs }), /pdc-grid-station-busQa" title="QA"/);
});

test('r799: wiring, cache tags, migration and docs', () => {
  const tbl = fs.readFileSync('pdc-vehicle-locations-table.js', 'utf8');
  assert.match(tbl, /const columns = stationDefs\(\);/);
  assert.match(tbl, /stationDefs: columns \}\)/);
  assert.match(tbl, /incomingSort: sort, stationDefs: columns \}\)/);
  assert.match(tbl, /if \(def\.busCategory\) return false;/);
  assert.match(fs.readFileSync('pdc-vehicle-locations-table.css', 'utf8'), /grid-auto-flow: column; grid-auto-columns: 27px;/);
  assert.match(fs.readFileSync('app.js', 'utf8'), /stationDefs: options\.stationDefs, stationTransfer/);
  assert.match(fs.readFileSync('canonical-entry.js', 'utf8'), /pdc-vehicle-locations-table\.js\?[^']*&r799=2026\.11\.01\.r799'/);
  const mig = fs.readFileSync('supabase/migrations/20261101084500_r799_bus_category_columns.sql', 'utf8');
  assert.match(mig, /CREATE FUNCTION pdc_work_categories_private\.bus_category_completion_799/);
  assert.match(mig, /REVOKE ALL ON FUNCTION pdc_work_categories_private\.bus_category_completion_799\(uuid\[\]\) FROM PUBLIC, anon, authenticated/);
  assert.doesNotMatch(mig, /CREATE OR REPLACE FUNCTION pdc_work_categories_private\.station_icon_completion_578/, 'the r578 function is untouched');
  assert.match(fs.readFileSync('supabase/rollbacks/20261101084500_r799_bus_category_columns.down.sql', 'utf8'), /DROP FUNCTION IF EXISTS pdc_work_categories_private\.bus_category_completion_799/);
  assert.match(fs.readFileSync('docs/FAULT_LOG.md', 'utf8'), /\| F409 \|/);
});
