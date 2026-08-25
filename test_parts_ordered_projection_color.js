'use strict';
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

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
const finalRequiredRule = css.lastIndexOf('.incoming-work-check.is-required {');
const finalOrderedRule = css.lastIndexOf('.incoming-work-check.is-required.is-ordered,');
const finalCompleteRule = css.lastIndexOf('.incoming-work-check.is-complete {');
assert.ok(finalRequiredRule >= 0 && finalOrderedRule > finalRequiredRule && finalCompleteRule > finalOrderedRule,
  'final CSS cascade places ordered after required and before complete');
const finalOrderedCss = css.slice(finalOrderedRule, finalCompleteRule);
assert.match(finalOrderedCss, /border-color:\s*#fdba74 !important;/);
assert.match(finalOrderedCss, /background:\s*#fff7ed !important;/);
assert.match(finalOrderedCss, /color:\s*#9a3412 !important;/);
assert.match(css, /\.pdc-work-state-ordered\s*\{[^}]*background:\s*#fff7ed !important;[^}]*color:\s*#9a3412 !important;/s);
assert.match(desktopCss, /\.work-status-key\.status-ordered[^\n]*background:\s*#fff7ed;/);
assert.match(app, /status-ordered"><b>●<\/b> Parts ordered/);
assert.match(app, /orange = Parts ordered/);
console.log('Parts ordered orange projection: PASS');
