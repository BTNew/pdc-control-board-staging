'use strict';
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const app = fs.readFileSync('app.js', 'utf8');
const index = fs.readFileSync('index.html', 'utf8');
const start = app.indexOf('function clearLegacyLocalSalespersonAssignments');
const end = app.indexOf('\n// Salesperson assignment is operational data.', start);
assert.ok(start > 0 && end > start);
let saved = null;
const edits = {
  vehicleA: { consultant: 'Local Person', salespersonCode: 'LP', pdcLocation: 'PMB' },
  vehicleB: { owner: 'Local Owner', salespersonReference: { code: 'XX' }, client: 'Customer' },
};
const context = {
  loadVehicleEdits: () => edits,
  saveJson: (_key, value) => { saved = JSON.parse(JSON.stringify(value)); },
  EDITS_KEY: 'vehicleEdits',
};
vm.createContext(context);
vm.runInContext(`${app.slice(start, end)}\nresult = clearLegacyLocalSalespersonAssignments();`, context);
assert.strictEqual(context.result, true);
assert.strictEqual(saved.vehicleA.consultant, undefined);
assert.strictEqual(saved.vehicleA.salespersonCode, undefined);
assert.strictEqual(saved.vehicleA.pdcLocation, 'PMB', 'targeted cleanup retains unrelated fields pending full migration');
assert.strictEqual(saved.vehicleB.owner, undefined);
assert.strictEqual(saved.vehicleB.salespersonReference, undefined);
assert.strictEqual(saved.vehicleB.client, 'Customer');
assert.ok(app.indexOf('clearLegacyLocalSalespersonAssignments();') < app.indexOf('const app = {'), 'legacy local salesperson is removed before data is built');

const submitStart = app.indexOf("$('[data-vehicle-edit-form]', panel).addEventListener('submit'");
const submitEnd = app.indexOf('\n  });', submitStart);
const submit = app.slice(submitStart, submitEnd);
assert.match(submit, /serverAuthoritative && \(salespersonChanged \|\| Object\.keys\(detailChanges\)\.length\)/);
assert.match(submit, /saveAuthoritativeVehicleChanges\(v, consultant, detailChanges\)/);
assert.match(submit, /serverAuthoritative \? true : saveVehicleEdits\(key, updates\)/);
assert.match(app, /discardLegacyAuthoritativeSalespersonEdits/);
assert.match(index, /authoritative-detail=386-388-391/);
console.log('Server-only salesperson/detail fail-closed safeguard: PASS');
