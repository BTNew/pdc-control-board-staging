'use strict';
// r698 (F308): To PMB reads the vehicle version from the key save's data so the move does not conflict.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
test('key save version comes from data.vehicle_version_after', () => {
  const app = fs.readFileSync('app.js', 'utf8');
  assert.match(app, /Number\(savedBody\.data\?\.vehicle_version_after \?\? savedBody\.vehicle_version_after\)/);
  assert.doesNotMatch(app, /if \(savedBody\.vehicle_version_after\) vehicle\.__emailVehicleVersion/);
  assert.match(fs.readFileSync('index.html', 'utf8'), /&amp;r698=2026\.10\.29\.r698/);
});
