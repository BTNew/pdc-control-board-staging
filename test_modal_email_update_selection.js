'use strict';

const assert = require('assert');
const fs = require('fs');
const app = fs.readFileSync('app.js', 'utf8');
const start = app.indexOf('function draftSelectedVehicleStatusEmail(');
const end = app.indexOf('\nfunction draftRftSalespersonNotificationEmail', start);
const body = app.slice(start, end);
assert.ok(body.includes('const activeDetail = app.activeVehicleDetail;'), 'EMAIL UPDATE reads the active modal vehicle');
assert.ok(body.includes('const resolvedVehicle = modalVehicle || (cleanKey ? selectedVehicle(cleanKey) : null);'), 'EMAIL UPDATE resolves the modal/canonical vehicle');
assert.ok(!body.includes('app.data.filter(vehicle => [vehicleKey(vehicle), vehicle.stock, vehicle.id]'), 'EMAIL UPDATE does not depend on the local app.data-only lookup');
assert.ok(app.includes('app.activeVehicleDetail = v;'), 'vehicle detail stores the open vehicle for modal actions');
console.log('Modal EMAIL UPDATE selection contract passed.');
