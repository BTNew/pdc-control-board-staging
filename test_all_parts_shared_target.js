'use strict';

const assert = require('assert');
const fs = require('fs');
const app = fs.readFileSync('app.js', 'utf8');

assert.ok(app.includes('function authenticatedEmailPartsTarget('), 'Parts actions have a shared authenticated target resolver');
for (const name of ['markVehiclePartsOrdered', 'markVehiclePartsComplete', 'updateVehiclePartsWorstEta']) {
  const start = app.indexOf(`async function ${name}`);
  const end = app.indexOf('\nasync function ', start + 10);
  const body = app.slice(start, end > start ? end : start + 5000);
  assert.ok(start >= 0 && body.includes('authenticatedEmailPartsTarget(key, vehicle)'), `${name} resolves the authenticated email vehicle target`);
  assert.ok(body.includes('vehicleId') && body.includes('expectedVersion'), `${name} sends canonical vehicle ID/version`);
}
console.log('All Parts actions shared target contract passed.');
