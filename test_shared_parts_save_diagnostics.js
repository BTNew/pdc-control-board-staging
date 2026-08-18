'use strict';

const assert = require('assert');
const fs = require('fs');
const app = fs.readFileSync('app.js', 'utf8');
const service = fs.readFileSync('pdc-email-vehicle-location-service.js', 'utf8');

assert.ok(app.includes('const backendBody = Array.isArray(result.body) ? result.body[0] : result.body;'), 'RPC error body is inspected');
assert.ok(app.includes('HTTP ${result.status}'), 'RPC status is surfaced');
assert.ok(app.includes('String(backendMessage).slice(0, 240)'), 'backend diagnostic is bounded');
assert.ok(service.includes('row.parts_received === true'), 'top-level Parts received projection is accepted');
assert.ok(service.includes('partsUpdate.parts_received === true'), 'nested Parts received projection is accepted');
console.log('Shared Parts save diagnostics contract passed.');
