'use strict';

const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const source = fs.readFileSync('app.js', 'utf8');
const start = source.indexOf('function incomingWorkChecklistHtml(');
const end = source.indexOf('\nfunction workStatusLegendHtml(', start);
assert.ok(start > 0 && end > start, 'incoming checklist renderer is discoverable');

const defs = [
  ['parts', 'Parts'], ['tint', 'Tint'], ['bus4x4', 'Bus 4x4'], ['hoist', 'Hoist/GVM'], ['fitting', 'Fitting'],
  ['fabrication', 'Fabrication'], ['electrical', 'Electrical'], ['tyre', 'Tyres'], ['pitInspection', 'PIT'], ['sublet', 'Sublet'],
].map(([key, label]) => ({ key, label }));
const context = {
  pdcJobDefsPartsFirst: () => defs,
  vehicleNavisionJitaNumber: () => '', vehicleKey: vehicle => vehicle.stock,
  normalizePmbStage: value => value || '',
  inferredPmbStage: () => '',
  vehicleWorkshopBookingProjection: () => ({ bookingRequired: false, activeBookings: [] }),
  pdcJobRequired: (_vehicle, def) => def.key === 'parts',
  pdcJobComplete: () => false,
  partsOrdered: () => true,
  canonicalActiveSubletBooking: () => null,
  pdcBlockReason: () => '',
  pdcJobCompletionTitle: (_vehicle, def) => `${def.label} required`,
  pmbStageForPdcJob: def => def.key.toUpperCase(),
  PMB_STAGE_TO_JOB_KEY: {},
  isActivePartsStoppage: () => false,
  isPdcBlocked: () => false,
  canonicalVehicleWorkState: () => ({ state: 'required', label: 'To be completed' }),
  pdcGridJobLabel: def => def.label,
  escapeHtml: value => String(value),
};
vm.createContext(context);
vm.runInContext(`${source.slice(start, end)}\nthis.renderChecklist = incomingWorkChecklistHtml;`, context);

const html = context.renderChecklist({
  stock: '13056889',
  required: true,
  pilbaraServiceOperations: [
    { classification: 'FITTING' },
    { classification: 'ELECTRICAL' },
    { classification: 'TYRE' },
  ],
});
const controls = [...html.matchAll(/class="incoming-work-check\b/g)].length;
assert.strictEqual(controls, defs.length, 'Parts through Sublet render exactly one aligned category control each');
assert.strictEqual((html.match(/pdc-station-parts/g) || []).length, 1, 'Parts has one intentional state/warning control');
assert.match(html, /pdc-station-parts[^"\n]*is-required[^"\n]*is-ordered/, 'the sole Parts control retains its explicit ordered/backorder warning presentation');
assert.doesNotMatch(html, /pdc-station-review|Service Review/, 'expanded operation cards carry Review presentation without a stray top-row pseudo-control');
console.log('Pilbara Service main category-row alignment: PASS');
