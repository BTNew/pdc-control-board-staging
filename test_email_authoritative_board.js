'use strict';

const assert = require('assert');
const fs = require('fs');
const service = require('./pdc-email-vehicle-location-service.js');

const ghost = { stock: '10048728', client: 'Maddington Hire', vehicle: 'Coaster' };
const realLocal = { stock: '13070395', client: 'Old local customer', consultant: 'POISONED-LOCAL-SP' };
const realServer = {
  id: '483fc596-ebe2-5c89-870b-ccf375e076f5',
  permanent_vehicle_id: 'PDC-NAV-483FC596EBE25C89870B',
  version: 5,
  stock_number: '13070395',
  vin: 'MR0NABAV702461906',
  job_card_number: 'J139125512',
  customer_name: 'JOOMBARN-BURU ABORIGINAL CORPORATIO',
  vehicle_description: 'HiLux 4x4 2.8L Dsl D/C/C 6MT',
  visible_on_board: true,
  current_location: 'Other',
  salesperson_code: 'CW',
  salesperson_name: 'Craig Watson',
  salesperson_email: 'craig@example.test',
  work_items: [
    { work_key: 'fitting', required: true, completed: false },
    { work_key: 'pitInspection', required: true, completed: false },
  ],
  operation_lines: [
    { operation_line_id: '9b4d03af-1f4a-4b09-8cdc-d3ea51349cce', operation_no: 'OP1', work_key: 'pitInspection', description: 'Fill with Fuel [ 0.00 ] C1', estimated_hours: 0, estimated_hours_source: 'job_card', source_uid: 'pdc-jc-159:test' },
  ],
};

const legacyMerge = service.reconcileVehicleRows([ghost, realLocal], [realServer]);
assert.strictEqual(legacyMerge.rows.some(row => row.stock === '10048728'), true, 'Legacy mixed views must retain unmatched local rows');

const authoritative = service.reconcileVehicleRows([ghost, realLocal], [realServer], { authoritative: true });
assert.strictEqual(authoritative.rows.length, 1, 'Authoritative Board must contain only shared email vehicles');
assert.strictEqual(authoritative.rows.some(row => row.stock === '10048728'), false, 'Local test Stock must be removed');
const real = authoritative.rows[0];
assert.strictEqual(real.stock, '13070395');
assert.strictEqual(real.jobCardNumber, 'J139125512');
assert.strictEqual(real.client, 'JOOMBARN-BURU ABORIGINAL CORPORATIO');
assert.strictEqual(real.pdcRequiresFitting, true);
assert.strictEqual(real.pdcRequiresPitInspection, true);
assert.strictEqual(real.pdcEmailOperationLines.length, 1);
assert.strictEqual(real.pdcEmailOperationLines[0].estimatedHours, 0, 'Genuine zero hours must remain zero');
assert.strictEqual(real.consultant, 'CW', 'Authoritative snapshot must ignore poisoned local salesperson edits');
assert.strictEqual(real.salespersonEmail, 'craig@example.test');

const conflictingLocal = [
  { stock: '13070395', id: 'local-a' },
  { stock: '13070395', id: 'local-b' },
  ghost,
];
const conflict = service.reconcileVehicleRows(conflictingLocal, [realServer], { authoritative: true });
assert.strictEqual(conflict.conflictCount, 2);
assert.strictEqual(conflict.rows.length, 2, 'Only ambiguous rows may survive authoritative reconciliation');
assert.ok(conflict.rows.every(row => row.__emailVehicleIdentityConflict === true && row.__locationIdentityReadOnly === true));
assert.strictEqual(conflict.rows.some(row => row.stock === '10048728'), false);

const app = fs.readFileSync('app.js', 'utf8');
assert.ok(app.includes("reconcileVehicleRows(app.data, serverRows, { authoritative: true })"));
assert.ok(app.includes("runStorageTransaction('Reconcile authoritative email vehicles', [EDITS_KEY, ADDED_KEY, DELETED_KEY]"));
assert.ok(app.includes('discardLegacyAuthoritativeSalespersonEdits(serverRows)'));
assert.ok(app.indexOf('if (!response.ok) return false;') < app.indexOf("runStorageTransaction('Reconcile authoritative email vehicles'"), 'Local purge must occur only after authenticated snapshot success');

console.log('email_authoritative_board: PASS');
