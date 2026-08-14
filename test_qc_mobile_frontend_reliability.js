'use strict';

const assert = require('assert');
const fs = require('fs');

const app = fs.readFileSync('app.js', 'utf8');
const styles = fs.readFileSync('styles.css', 'utf8');

const mobileStart = styles.indexOf('/* QC mobile reliability: task cards without desktop-grid panning. */');
assert.ok(mobileStart >= 0, 'QC mobile reliability override must be present at the end of the cascade');
const mobile = styles.slice(mobileStart);

for (const contract of [
  '@media (max-width: 1100px)',
  '.incoming-bucket-list.incoming-vertical-list',
  'overflow-x: hidden !important',
  '.incoming-production-grid-header',
  'display: none !important',
  '.incoming-bucket-list.incoming-vertical-list > .incoming-vehicle-card',
  'min-width: 0 !important',
  '.incoming-vehicle-summary',
  'grid-template-areas:',
  '.incoming-card-stock',
  '.incoming-card-work-wrap',
  '.incoming-card-action',
  'min-height: 44px !important',
  '.incoming-work-checks',
  'grid-template-columns: repeat(3, minmax(0, 1fr)) !important',
  '.incoming-work-label',
  'display: inline !important',
  '.incoming-vehicle-detail-grid',
]) assert.ok(mobile.includes(contract), `QC mobile CSS contract missing: ${contract}`);

const bindStart = app.indexOf('const vehicleLifecycleActionsInFlight = new Set();');
assert.ok(bindStart >= 0, 'QC lifecycle buttons need one stable browser-side in-flight guard');
const bindEnd = app.indexOf('function updateInlineSelectionBars(', bindStart);
const bind = app.slice(bindStart, bindEnd);
for (const contract of [
  'const vehicleLifecycleActionsInFlight = new Set()',
  'function vehicleLifecycleButtonActionKey(',
  "return `ready-for-qc:${readyForQc}`",
  "return qcSignoffRft ? `qc-signoff-rft:${qcSignoffRft}` : ''",
  'vehicleLifecycleActionsInFlight.has(actionKey)',
  'vehicleLifecycleActionsInFlight.add(actionKey)',
  'button.disabled',
  "button.setAttribute('aria-busy', 'true')",
  'button.disabled = true',
  'await action()',
  'vehicleLifecycleActionsInFlight.delete(actionKey)',
  "button.removeAttribute('aria-busy')",
]) assert.ok(bind.includes(contract), `QC rapid-action guard missing: ${contract}`);
assert.ok(app.includes('runVehicleLifecycleButtonAction(button, () => markVehicleReadyForQualityControl'), 'Ready for QC must use the rapid-action guard');
assert.ok(app.includes('runVehicleLifecycleButtonAction(button, () => completeVehicleQualityControl'), 'QC sign-off must use the rapid-action guard');

assert.ok(app.includes("aria-label=\"Required work stations for ${escapeHtml(stock)}"), 'station status needs a vehicle-specific accessible name');
assert.ok(app.includes('await printQualityControlSignoffLabel'), 'QC must await the label-print result before completing its UI flow');
assert.ok(app.includes('return { ok: true, printerName, message };'), 'successful raw printing must return a structured result');
assert.ok(app.includes("return { ok: false, error: message };"), 'failed raw printing must return a structured result');
assert.ok(app.includes('QC was saved and the vehicle is RFT, but the windscreen label did not print.'), 'print failure copy must accurately separate saved QC from printer failure');

console.log('QC mobile layout, accessible station naming, rapid-action and print-failure contracts passed');
