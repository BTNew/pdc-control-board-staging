'use strict';
// r696 (F306): the vehicle panel has To PMB for In Transit / Yard Hold vehicles that are already here.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const js = fs.readFileSync('pdc-vehicle-slideout.js', 'utf8');
test('panel header shows To PMB only when the vehicle can go to PMB', () => {
  assert.match(js, /vso-head-actions">\$\{toPmbHtml\(vehicle\)\}/);
  assert.match(js, /root\.canTransferVehicleToPmb\(vehicle\)/);
  assert.match(js, /sharedVehicleLocationMutationUnavailable\('transfer to PMB', vehicle, \{ silent: true \}\)/);
});
test('To PMB opens the same Send to PMB box (key number starts the timer)', () => {
  assert.match(js, /root\.transferYhVehicleToPmb\(button\.dataset\.vsoToPmb\)/);
  assert.match(fs.readFileSync('canonical-entry.js', 'utf8'), /pdc-vehicle-slideout\.js\?[^']*&r696=2026\.10\.29\.r696(&r699=2026\.10\.29\.r699)?(&r705=2026\.10\.29\.r705)?(&r721=2026\.10\.29\.r721)?(&r738=2026\.10\.30\.r738)?(&r797=2026\.11\.01\.r797)?'/);
});
test('r705 (F315): after To PMB the panel closes and says sent, with the key', () => {
  assert.match(js, /sent = await root\.transferYhVehicleToPmb\(button\.dataset\.vsoToPmb\) === true/);
  assert.match(js, /if \(sent\) \{[\s\S]{0,200}close\(\);[\s\S]{0,200}sent to PMB\$\{keyNo \? `, key \$\{keyNo\}` : ''\}\. The PMB timer has started\./);
});
