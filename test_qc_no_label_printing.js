'use strict';
const assert = require('assert');
const fs = require('fs');

const app = fs.readFileSync('app.js', 'utf8');
const index = fs.readFileSync('index.html', 'utf8');

assert.doesNotMatch(app, /function qualityControlSignoffLabelZpl|function printQualityControlSignoffLabel/,
  'QC label generation and printing functions are removed');
const qcCompleteStart = app.indexOf('async function completeVehicleQualityControl');
const qcCompleteEnd = app.indexOf('function vehicleCanEnterPit', qcCompleteStart);
assert.ok(qcCompleteStart >= 0 && qcCompleteEnd > qcCompleteStart);
assert.doesNotMatch(app.slice(qcCompleteStart, qcCompleteEnd), /printQualityControlSignoffLabel|printRawZpl|QZ Tray/,
  'named QC sign-off never invokes a printer');
assert.doesNotMatch(app, /Sign off & print label/);
assert.match(app, />Open QC finalization<\/button>/);
assert.match(app, /const labelAction = locationReadOnly \|\| bucketKey === 'qc' \? ''/,
  'Vehicle Locations suppresses Label action in QC');
assert.match(app, /vehiclePdcLocation\(v\) === 'QC' \? '' : `<button class="small-button vehicle-label-button"/,
  'Vehicle detail suppresses Label action for QC vehicles');
assert.match(app, /const APP_VERSION = '2026\.08\.26\.14-workshop-subhour-duration'/);
assert.match(index, /app\.js\?v=2026\.08\.26\.14-workshop-subhour-duration/);

console.log('Mobile QC sign-off has no label printing: PASS');
