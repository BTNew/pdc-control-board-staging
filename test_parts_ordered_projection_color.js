'use strict';
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const { mapServerVehicle, reconcileVehicleRows } = require('./pdc-email-vehicle-location-service.js');

const app = fs.readFileSync('app.js', 'utf8');
const css = fs.readFileSync('styles.css', 'utf8');
const desktopCss = fs.readFileSync('desktop-operations.css', 'utf8');

function section(startNeedle, endNeedle) {
  const start = app.indexOf(startNeedle);
  const end = app.indexOf(endNeedle, start);
  assert.ok(start >= 0 && end > start, `${startNeedle} section exists`);
  return app.slice(start, end);
}

const controlContext = {
  pdcJobTriState: vehicle => vehicle.state,
  partsOrdered: vehicle => vehicle.ordered === true,
  isActivePartsStoppage: vehicle => vehicle.stoppage === true,
  escapeHtml: value => String(value),
};
vm.createContext(controlContext);
vm.runInContext(`${section('function pdcJobTriStateControl', 'const PDC_JOB_BY_REQUIRE_KEY')} this.renderControl = pdcJobTriStateControl;`, controlContext);
const partsDef = {key: 'parts', label: 'PARTS', short: 'P', requireKey: 'requires', completeKey: 'complete'};
const orderedControl = controlContext.renderControl({state: 'required', ordered: true}, partsDef, false);
assert.match(orderedControl, /pdc-work-state-ordered/);
assert.match(orderedControl, /data-state="required"/);
assert.match(orderedControl, /PARTS - Ordered/);
assert.doesNotMatch(controlContext.renderControl({state: 'required', ordered: false}, partsDef, false), /pdc-work-state-ordered/);
assert.match(controlContext.renderControl({state: 'complete', ordered: true}, partsDef, false), /pdc-work-state-complete/);

function renderIncoming({ordered = false, blocked = false, complete = false} = {}) {
  const context = {
    vehicleKey: () => 'TEST-STOCK', normalizePmbStage: value => value || '', inferredPmbStage: () => '',
    vehicleWorkshopBookingProjection: () => ({bookingRequired: false, activeBookings: []}),
    pdcJobDefsPartsFirst: () => [partsDef], pdcJobRequired: () => true, pdcJobComplete: () => complete,
    pmbStageForPdcJob: () => '', PMB_STAGE_TO_JOB_KEY: {}, isActivePartsStoppage: () => blocked,
    isPdcBlocked: () => false, partsOrdered: () => ordered, pdcGridJobLabel: () => 'Parts',
    pdcJobCompletionTitle: () => 'Parts required', escapeHtml: value => String(value),
  };
  vm.createContext(context);
  vm.runInContext(`${section('function incomingWorkChecklistHtml', 'function workStatusLegendHtml')} this.renderIncoming = incomingWorkChecklistHtml;`, context);
  return context.renderIncoming({}, {});
}
const orderedCard = renderIncoming({ordered: true});
assert.match(orderedCard, /incoming-work-check pdc-station-parts is-required is-ordered/);
assert.match(orderedCard, /aria-label="Parts ordered"/);
assert.match(orderedCard, /title="Parts ordered"/);
assert.doesNotMatch(renderIncoming({ordered: true, blocked: true}), /is-ordered/);
assert.match(renderIncoming({ordered: true, complete: true}), /is-complete/);

assert.match(css, /\.incoming-work-check\.is-ordered\s*\{[^}]*background:\s*#fff7ed;[^}]*color:\s*#9a3412;/s);
assert.match(css, /\.pdc-work-state-ordered\s*\{[^}]*background:\s*#fff7ed !important;[^}]*color:\s*#9a3412 !important;/s);
assert.match(desktopCss, /\.work-status-key\.status-ordered[^\n]*background:\s*#fff7ed;/);
assert.match(app, /status-ordered"><b>●<\/b> Parts ordered/);
assert.match(app, /orange = Parts ordered/);

const authoritative = {
  id: '00000000-0000-4000-8000-000000000941',
  stock_number: 'HERMES-SANITIZED-ORDERED-941',
  version: 7,
  work_items: [{ work_key: 'parts', required: true, completed: false }],
  operation_lines: [],
  parts_update: { parts_required: true, parts_ordered: true, parts_received: false, worst_eta: '2026-08-30' },
};
const mapped = mapServerVehicle(authoritative);
assert.strictEqual(mapped.pdcRequiresParts, true);
assert.strictEqual(mapped.pdcPartsOrdered, true);
assert.strictEqual(mapped.pdcPartsWorstEta, '2026-08-30');
const firstSession = reconcileVehicleRows([{ stock: authoritative.stock_number }], [authoritative]).rows[0];
const secondSession = reconcileVehicleRows([{ ...firstSession }], [authoritative]).rows[0];
assert.strictEqual(firstSession.pdcPartsOrdered, true, 'refresh keeps authoritative ordered projection');
assert.strictEqual(secondSession.pdcPartsOrdered, true, 'realtime/two-session reconciliation keeps authoritative ordered projection');
const runtimeContext = {
  vehicleKey: vehicle => vehicle.stock, normalizePmbStage: value => value || '', inferredPmbStage: () => '',
  vehicleWorkshopBookingProjection: () => ({bookingRequired: false, activeBookings: []}),
  pdcJobDefsPartsFirst: () => [{ ...partsDef, requireKey: 'pdcRequiresParts', completeKey: 'pdcCompleteParts' }],
  pdcJobRequired: (vehicle, def) => vehicle[def.requireKey] === true, pdcJobComplete: (vehicle, def) => vehicle[def.completeKey] === true,
  pmbStageForPdcJob: () => '', PMB_STAGE_TO_JOB_KEY: {}, isActivePartsStoppage: vehicle => vehicle.pdcPartsStoppage === true,
  isPdcBlocked: () => false, partsOrdered: vehicle => vehicle.pdcPartsOrdered === true, pdcGridJobLabel: () => 'Parts',
  pdcJobCompletionTitle: () => 'Parts required', escapeHtml: value => String(value),
};
vm.createContext(runtimeContext);
vm.runInContext(`${section('function incomingWorkChecklistHtml', 'function workStatusLegendHtml')} this.renderIncoming = incomingWorkChecklistHtml;`, runtimeContext);
assert.match(runtimeContext.renderIncoming(secondSession, {}), /incoming-work-check pdc-station-parts is-required is-ordered/);
assert.doesNotMatch(section('function applySharedWorkStateCache', 'async function saveSharedVehicleWorkStates'), /pdcPartsOrdered\s*=/,
  'pending work-state overlays must not erase authoritative Parts ordered state');
console.log('Parts ordered orange projection: PASS');
