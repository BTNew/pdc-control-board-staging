'use strict';
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const app = fs.readFileSync('app.js', 'utf8');
const css = fs.readFileSync('styles.css', 'utf8');
const service = fs.readFileSync('pdc-email-vehicle-location-service.js', 'utf8');

assert.match(app, /function qcPageIsMobile\(\)[\s\S]*matchMedia\?\.\('\(max-width: 900px\)'\)\.matches/);
assert.match(app, /qcSelectedVehicleKey = mobile \? '' : qcPageVehicleKey\(vehicles\[0\] \|\| \{\}\)/,
  'mobile does not auto-select the first vehicle');
assert.match(app, /is-mobile-detail[\s\S]*is-mobile-list/);
assert.match(app, /data-qc-back-to-list/);
assert.match(css, /\.qc-page-layout\.is-mobile-list \.qc-detail-host,[\s\S]*\.qc-page-layout\.is-mobile-detail \.qc-queue \{ display: none; \}/);
assert.match(css, /\.qc-mobile-back \{ display: inline-flex; \}/);

assert.match(app, /const qcPageOperationPending = new Map\(\)/);
assert.match(app, /let qcPageOperationMutationChain = Promise\.resolve\(\)/);
assert.match(app, /qcPageOperationMutationChain = qcPageOperationMutationChain\s*\.then\(\(\) => qcPageSetOperationState/,
  'rapid taps are serialized through the latest authoritative versions');
assert.match(app, /aria-busy="true"/);
assert.match(app, /role="status" aria-live="polite"/);
assert.doesNotMatch(app.slice(app.indexOf('async function qcPageSetOperationState'), app.indexOf('async function qcPageSignoff')), /window\.alert/,
  'ordinary QC save/readback errors are inline and non-blocking');
assert.match(app, /result\.data\?\.line\?\.completed !== checked/);
assert.match(service, /data\.line\?\.completed !== \(completed === true\)/);
assert.match(service, /Number\(data\.vehicle_version_after \|\| 0\) < 1/);
assert.match(service, /\^\[a-f0-9\]\{64\}\$/);

const start = app.indexOf('function qcPageReceiptLineApply');
const end = app.indexOf('async function qcPageAwaitOperationSnapshot', start);
assert.ok(start >= 0 && end > start);
const context = { qcPageOperationLines: vehicle => vehicle.lines };
vm.createContext(context);
vm.runInContext(`${app.slice(start, end)} this.applyReceipt = qcPageReceiptLineApply;`, context);
const vehicle = { __emailVehicleVersion: 3, lines: [{ lineIdentity: 'source:11111111-1111-1111-1111-111111111111', completed: false, lineVersion: 0 }] };
const result = { data: { vehicle_version_after: 4, line: { line_identity: vehicle.lines[0].lineIdentity, completed: true, completed_by: 'actor', completed_at: '2026-08-25T01:00:00Z', version: 1 } } };
assert.strictEqual(context.applyReceipt(vehicle, vehicle.lines[0].lineIdentity, result), true);
assert.strictEqual(vehicle.lines[0].completed, true, 'validated authoritative receipt is applied immediately');
assert.strictEqual(vehicle.lines[0].lineVersion, 1);
assert.strictEqual(vehicle.__emailVehicleVersion, 4, 'next queued tap uses receipt vehicle version');

console.log('QC mobile drill-in and queued receipt-backed saves: PASS');
