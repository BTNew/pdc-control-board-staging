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
  section('function incomingWorkChecklistHtml', 'function workStatusLegendHtml'), context);
const mapped = (value, verified = true) => mapServerVehicle({
  id: '00000000-0000-4000-8000-000000000378', stock_number: 'TEST-JITA',
  navision_jita_identity_verified: verified, navision_jita_column_present: true,
  navision_jita_number_authority: 'validated-navision-import-v1', navision_jita_number: value,
});
const render = (number, parts = {}, verified = true) => context.incomingWorkChecklistHtml({ ...mapped(number, verified), ...parts });
for (const parts of [
  {}, { pdcRequiresParts: true }, { pdcRequiresParts: true, pdcPartsOrdered: true },
  { pdcRequiresParts: true, pdcCompleteParts: true }, { pdcRequiresParts: true, pdcPartsStoppage: true },
]) {
  const withNumber = render('JITA-123', parts), without = render('', parts);
  assert.match(withNumber, /parts-jita-split has-jita/);
  assert.match(without, /parts-jita-split no-jita/);
  assert.match(withNumber, /JITA pre-order JITA-123/);
  assert.equal(withNumber.match(/parts-jita-parts-marker[^>]*>(.*?)<\/span>/)[1],
    without.match(/parts-jita-parts-marker[^>]*>(.*?)<\/span>/)[1], 'JITA never changes the Parts marker');
  assert.equal(withNumber.match(/pdc-station-parts(.*?)parts-jita-split/)[1],
    without.match(/pdc-station-parts(.*?)parts-jita-split/)[1], 'JITA never changes Parts state colours');
}
for (const missing of ['', '0', '0.00', 'Yes']) assert.match(render(missing), /parts-jita-split no-jita/);
assert.match(render('JITA-123', {}, false), /parts-jita-split no-jita/, 'unverified stock cannot produce a green tick');
assert.match(render('JITA-123"><img src=x>'), /JITA-123&quot;&gt;|JITA-123&quot;>&lt;img/, 'source number is escaped');
if (process.env.PDC_JITA_PREVIEW) {
  const examples = [
    ['Parts received / JITA present', {pdcRequiresParts:true,pdcCompleteParts:true}, 'JITA-123'],
    ['Parts received / JITA missing', {pdcRequiresParts:true,pdcCompleteParts:true}, ''],
    ['Parts ordered / JITA present', {pdcRequiresParts:true,pdcPartsOrdered:true}, 'JITA-123'],
    ['Parts required / JITA missing', {pdcRequiresParts:true}, ''],
    ['Parts STOPPAGE / JITA present', {pdcRequiresParts:true,pdcPartsStoppage:true}, 'JITA-123'],
  ];
  fs.writeFileSync('parts-jita-preview.html', '<!doctype html><meta charset="utf-8"><link rel="stylesheet" href="styles.css"><main style="padding:32px;background:white"><h1>Parts / JITA</h1><p>Top left: Parts · Bottom right: Navision JITA pre-order</p>' + examples.map(([label,parts,number]) => `<div style="display:flex;align-items:center;gap:24px;margin:24px 0"><span style="width:290px">${label}</span>${render(number,parts)}</div>`).join('') + '</main>');
}
console.log('Independent Parts / verified Navision JITA split pill: PASS');
