'use strict';

const assert = require('assert');
const fs = require('fs');

const app = fs.readFileSync('app.js', 'utf8');
const html = fs.readFileSync('index.html', 'utf8');

assert.ok(html.includes('id="vehicle-modal" hidden role="dialog" aria-modal="true" aria-labelledby="vehicle-modal-title"'), 'vehicle overlay remains a named modal dialog');
for (const contract of [
  'let vehicleModalReturnFocus = null;',
  'let vehicleModalAppShellWasInert = null;',
  'function vehicleModalFocusableElements(',
  'element.getClientRects().length > 0',
  'function trapVehicleModalFocus(',
  'function syncVehicleModalFocusLifecycle(',
  'function suspendVehicleModalBackgroundForDrag(',
  'function restoreVehicleModalBackgroundAfterDrag(',
  "on($('#vehicle-modal'), 'focusin', syncVehicleModalFocusLifecycle)",
  "event.key !== 'Tab'",
  'event.shiftKey',
  "setAttribute('inert', '')",
  "removeAttribute('inert')",
  "shell?.getAttribute('aria-hidden') !== 'true'",
  'vehicleModalReturnFocus?.focus()',
  'openVehicleModal(key, trigger)',
]) assert.ok(app.includes(contract), `vehicle modal accessibility contract missing: ${contract}`);

const closeStart = app.indexOf('function closeVehicleModal()');
const closeEnd = app.indexOf('async function removeVehicle(', closeStart);
const close = app.slice(closeStart, closeEnd);
assert.ok(close.includes('if (!modal || modal.hidden) return;'), 'closing an already hidden dialog must not steal focus');
assert.ok(close.indexOf('if (!modal || modal.hidden) return;') < close.indexOf('app.vehicleWorkshopDetailRequestGeneration += 1'), 'closing an already hidden dialog must not mutate dialog request state');
assert.ok(close.indexOf('modal.hidden = true') < close.indexOf('vehicleModalReturnFocus?.focus()'), 'focus returns only after the dialog closes');

console.log('Vehicle modal focus trap, background inertness and focus-return contracts passed');
