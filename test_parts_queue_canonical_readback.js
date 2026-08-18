'use strict';

const assert = require('assert');
const fs = require('fs');
const app = fs.readFileSync('app.js', 'utf8');

for (const name of ['markVehiclePartsOrdered', 'markVehiclePartsComplete', 'updateVehiclePartsWorstEta']) {
  const start = app.indexOf(`async function ${name}`);
  const end = app.indexOf('\nasync function ', start + 10);
  const body = app.slice(start, end > start ? end : start + 5000);
  assert.ok(body.includes('await refreshSharedVehicleWorkState(sharedVehicle);'), `${name} reads the canonical Parts row after every shared result`);
  assert.ok(body.includes('renderPartsHome();'), `${name} rerenders the Parts queue after canonical readback`);
}
assert.ok(app.includes('function partsDepartmentSourceRows()'), 'Parts queue has a single source-row helper');
assert.ok(app.includes('return vehicleLocationsScreenRows().filter(partsQueueVisibleVehicle);'), 'Parts queue remains on the shared Vehicle Locations row set');
console.log('Parts queue canonical readback contract passed.');
