'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { projectWorkState } = require('./vehicle-requirements-guard');
const { mapServerVehicle } = require('./pdc-email-vehicle-location-service');
const source = fs.readFileSync('app.js', 'utf8');
const section = (start, end) => source.slice(source.indexOf(start), source.indexOf(end, source.indexOf(start)));
const context = {
  vehicleKey: v => v.stock, normalizePmbStage: () => '', inferredPmbStage: () => '',
  vehicleWorkshopBookingProjection: () => ({ activeBookings: [] }),
  pdcJobDefsPartsFirst: () => [{ key: 'parts' }],
  pdcJobRequired: v => v.pdcRequiresParts, pdcJobComplete: v => v.pdcCompleteParts,
  pmbStageForPdcJob: () => '', PMB_STAGE_TO_JOB_KEY: {},
  isActivePartsStoppage: v => v.pdcPartsStoppage, isPdcBlocked: () => false,
  pdcBlockReason: () => 'Awaiting parts', partsOrdered: v => v.pdcPartsOrdered,
  canonicalVehicleWorkState: v => projectWorkState({ workKey: 'parts', required: v.pdcRequiresParts,
    completed: v.pdcCompleteParts, partsOrdered: v.pdcPartsOrdered, partsStoppage: v.pdcPartsStoppage }),
  pdcGridJobLabel: () => 'Parts', pdcJobCompletionTitle: () => 'Parts status',
  escapeHtml: v => String(v).replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;'),
};
vm.createContext(context);
vm.runInContext(section('const NAVISION_JITA_NUMBER_AUTHORITY', '\nfunction legacyVehicleFlag') +
  section('function importedPartsStatus', 'function partsDepartmentStatus') + section('function incomingWorkChecklistHtml', 'function workStatusLegendHtml'), context);
const mapped = (value, verified = true) => mapServerVehicle({
  id: '00000000-0000-4000-8000-000000000378', stock_number: 'TEST-JITA',
  navision_jita_identity_verified: verified, navision_jita_column_present: true,
  navision_jita_number_authority: 'validated-navision-import-v1', navision_jita_number: value,
});
const render = (number, parts = {}, verified = true) => context.incomingWorkChecklistHtml({ ...mapped(number, verified), ...parts });

for (const [colour,label] of [
 ['orange','Parts on order — outstanding'],
 ['orange','Parts attached; outstanding parts — check PO'],
 ['red','Outstanding parts — PO not confirmed'],
 ['green','Parts attached — no recorded backorders'],
 ['grey','No parts recorded — check whether required'],
 ['review','Unknown / Needs review'],
 ['review','Inconsistent data / Needs review'],
]) {
 const server = {id:'00000000-0000-4000-8000-000000000378',stock_number:'TEST',parts_flags:{colour,label,last_successful_import_at:'2026-09-11T08:00:00Z',meaning:'At least one operation, not all.'}};
 const v = mapServerVehicle(server);
 assert.equal(v.pdcPartsFlags.colour,colour);
 v.pdcCompleteParts=true; // Imported orange must stay orange even with an older completion projection.
 const html=context.incomingWorkChecklistHtml(v);
 assert.ok(html.includes('imported-parts-'+colour));
 assert.ok(html.includes(label));
 assert.ok(html.includes('Last successful import:'));
 assert.ok(html.includes('Perth'));
 assert.ok(!html.includes('Parts received'));
 assert.ok(html.includes('no-jita'));
}
const zero=mapServerVehicle({id:'00000000-0000-4000-8000-000000000378',parts_flags:{colour:'grey',label:'No parts recorded — check whether required',jobs:[{parts_attached:0,backorder:0,backorder_with_po:0}]}});
assert.equal(zero.pdcPartsFlags.jobs[0].parts_attached,0);
console.log('Numeric parts evidence colours, timestamps, zero preservation and independent JITA: PASS');
