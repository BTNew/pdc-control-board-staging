/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
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
  importedPartsStatus: v => v.pdcPartsFlags && ['orange', 'red', 'green', 'grey', 'review'].includes(v.pdcPartsFlags.colour) ? v.pdcPartsFlags : null,
  importedPartsTitle: v => (v.pdcPartsFlags && v.pdcPartsFlags.label) || '',
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
const completeTitle = /title="Parts Jita complete\. Navision JITA number ([^"]+)\."/;
for (const parts of [
  {}, { pdcRequiresParts: true }, { pdcRequiresParts: true, pdcPartsOrdered: true },
  { pdcRequiresParts: true, pdcCompleteParts: true },
]) {
  const withNumber = render('JITA-123', parts), without = render('', parts);
  assert.match(withNumber, /pdc-station-parts parts-jita-split is-complete has-jita/);
  assert.match(withNumber, completeTitle);
  assert.equal(withNumber.match(completeTitle)[1], 'JITA-123');
  assert.equal(withNumber.match(/parts-jita-parts-marker[^>]*>(.*?)<\/span>/)[1], '✓');
  assert.equal(withNumber.match(/parts-jita-marker[^>]*>(.*?)<\/span>/)[1], '✓');
  assert.match(without, /parts-jita-split no-jita/);
  assert.doesNotMatch(without, /Parts Jita complete/);
}
const stopped = render('JITA-123', { pdcRequiresParts: true, pdcPartsStoppage: true });
assert.match(stopped, /has-jita/);
assert.doesNotMatch(stopped, /Parts Jita complete/, 'a parts stoppage stays a stoppage');
assert.match(stopped, /is-blocked/);
for (const missing of ['', '0', '0.00', 'Yes']) {
  assert.match(render(missing), /parts-jita-split no-jita/);
  assert.doesNotMatch(render(missing), /Parts Jita complete/);
}
assert.match(render('JITA-123', {}, false), /parts-jita-split no-jita/, 'unverified stock cannot produce a green tick');
assert.doesNotMatch(render('JITA-123', {}, false), /Parts Jita complete/);
assert.match(render('JITA-123"><img src=x>'), /JITA-123&quot;&gt;|JITA-123&quot;&lt;img|JITA-123&quot;>&lt;img/, 'source number is escaped');
const etaOnly = render('', { jitaEta: '29/10/2026', plannedDeliveryDate: '2026-10-29' });
assert.match(etaOnly, /no-jita/);
assert.doesNotMatch(etaOnly, /Parts Jita complete/, 'a JITA ETA date does not tick Parts Jita');
const glyphs = { green: '✓', orange: '!', red: '●', grey: '—', review: '?' };
for (const colour of ['orange', 'red', 'review', 'grey']) {
  const html = render('JSO122691', { pdcRequiresParts: true, pdcPartsFlags: { colour, label: 'Outstanding ' + colour } });
  assert.match(html, new RegExp(`imported-parts-${colour} has-jita`), colour);
  assert.doesNotMatch(html, /Parts Jita complete/, colour);
  assert.equal(html.match(/parts-jita-parts-marker[^>]*>(.*?)<\/span>/)[1], glyphs[colour], colour);
  assert.equal(html.match(/parts-jita-marker[^>]*>(.*?)<\/span>/)[1], '✓', colour);
}
const greenImport = render('JSO118332', { pdcRequiresParts: true, pdcPartsFlags: { colour: 'green', label: 'All active jobs parts-ready' } });
assert.match(greenImport, /pdc-station-parts parts-jita-split is-complete has-jita/);
assert.doesNotMatch(greenImport, /imported-parts-green/, 'a green import with a JITA number is the full green tick');
assert.equal(greenImport.match(completeTitle)[1], 'JSO118332');
const stoppedImport = render('JITA-123', { pdcRequiresParts: true, pdcPartsStoppage: true, pdcPartsFlags: { colour: 'orange', label: 'Outstanding' } });
assert.match(stoppedImport, /imported-parts-orange has-jita/);
assert.doesNotMatch(stoppedImport, /Parts Jita complete/, 'a parts stoppage is not painted complete by a JITA number');
const importedOnly = render('', { pdcRequiresParts: true, pdcPartsFlags: { colour: 'red', label: 'Outstanding' } });
assert.match(importedOnly, /imported-parts-red no-jita/);
assert.doesNotMatch(importedOnly, /Parts Jita complete/);
const boardCss = fs.readFileSync('styles.css', 'utf8');
assert.match(boardCss, /\.incoming-work-check\.imported-parts-orange \{ background: #dbeafe !important; color: #1d4ed8 !important; border-color: #2563eb !important; \}/);
assert.match(boardCss, /#parts \[data-parts-feed\] \.parts-status-pill\.parts-status-ordered \{ background: #dbeafe !important; color: #1d4ed8 !important; border-color: #2563eb !important; \}/);
assert.doesNotMatch(boardCss, /#fff1dc|#d98200|#a15b00/);
assert.match(fs.readFileSync('karratha/styles.css', 'utf8'), /background: #fff1dc !important; color: #a15b00 !important; border-color: #d98200 !important;/);
assert.match(fs.readFileSync('index.html', 'utf8'), /styles\.css\?[^"]*&amp;r526=2026\.10\.24\.r526&amp;r562=2026\.10\.27\.r562&amp;r563=2026\.10\.27\.r563&amp;r574=2026\.10\.27\.r574"/); // r562 key badge, r563 arrival age, r574 department bay booking
assert.doesNotMatch(fs.readFileSync('karratha/index.html', 'utf8'), /r526=2026\.10\.24\.r526/);
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
