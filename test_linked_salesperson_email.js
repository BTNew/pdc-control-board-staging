'use strict';

const assert = require('assert');
const fs = require('fs');
const app = fs.readFileSync('app.js', 'utf8');

assert.ok(app.includes('function salespersonDirectoryRecords()'), 'salesperson directory fallback is available');
const forVehicleStart = app.indexOf('function salespersonForVehicle(');
const forVehicleEnd = app.indexOf('\nfunction salespersonOptionsHtml', forVehicleStart);
const forVehicle = app.slice(forVehicleStart, forVehicleEnd);
assert.ok(forVehicle.includes('const record = salespersonRecord(consultant);'), 'salesperson code is resolved through the directory');
assert.ok(forVehicle.indexOf('if (record) return record;') < forVehicle.indexOf('if (directEmail) {'), 'linked salesperson record has priority over imported email');
const modalStart = app.indexOf('function offerSalespersonChangeEmail(');
const modalEnd = app.indexOf('\nfunction vehicleStatusUpdateEmailBody', modalStart);
const modal = app.slice(modalStart, modalEnd);
assert.ok(modal.includes('data-sales-email-recipient autocomplete="email" readonly'), 'recipient field is linked/read-only');
assert.ok(modal.includes('email address is linked to the selected salesperson directory record'), 'modal explains the linked recipient');
console.log('Linked salesperson email recipient contract passed.');
