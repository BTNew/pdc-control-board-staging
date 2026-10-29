'use strict';
// r692 (F302): To PMB opens one box: confirm, then key number; Enter sends; the key starts the 24-hour New to PMB timer.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const app = fs.readFileSync('app.js', 'utf8');
test('To PMB uses the in-page box (confirm then key), with the old confirm/prompt only as a fallback', () => {
  const fn = app.slice(app.indexOf('async function transferYhVehicleToPmb'), app.indexOf('\nfunction ', app.indexOf('async function transferYhVehicleToPmb') + 20));
  assert.match(fn, /await pmbSendToPmbDialog\(\{ stock, customer, warning: partsWarning, existingKey \}\)/);
  assert.ok(fn.indexOf('pmbSendToPmbDialog') < fn.indexOf('window.confirm'));
  assert.match(fn, /set_pdc_vehicle_key_number_460/);
  const box = app.slice(app.indexOf('function pmbSendToPmbDialog'), app.indexOf('async function transferYhVehicleToPmb'));
  assert.match(box, /Send to PMB\?/);
  assert.match(box, /Yes, send to PMB/);
  assert.match(box, /Key number for/);
  assert.match(box, /event\.key === 'Enter'/);
  assert.match(box, /New to PMB for 24 hours/);
  assert.match(box, /0 is not a key/);
});
test('In transit vehicles that can be transferred show To PMB', () => {
  assert.match(app, /bucketKey === 'transit' && canTransferVehicleToPmb\(vehicle\)/);
});
