'use strict';
const assert = require('assert');
const fs = require('fs');

global.cleanNavisionText = value => String(value == null ? '' : value).trim();
global.normalizePmbStage = value => String(value || '').trim().toUpperCase();
global.vehicleWorkshopStageCode = value => String(value || '').trim().toUpperCase();
global.vehicleJobcardNumber = vehicle => vehicle.jobCardNumber || '';
global.vehiclePdcJobLines = () => [];
global.inferredPmbStage = () => '';
global.window = {
  PDC_SUPABASE_CONFIG: {},
  workshopSharedModeEnabled: () => true,
  __workshopDataService: { isEnabled: () => true },
  addEventListener: () => {},
};

const canonicalId = '11111111-1111-4111-8111-111111111111';
function line(id, operationNo, description, hours) {
  return { operation_line_id: id, operation_no: operationNo, description, estimated_hours: hours, stage_code: 'FITTING', job_card_number: 'J139124136' };
}
const allLines = [
  line('00000000-0000-4000-8000-000000000003', 'OP3', 'Tow Bar', 1.6),
  line('00000000-0000-4000-8000-000000000004', 'OP4', 'Fire Extinguisher', 0.5),
  line('00000000-0000-4000-8000-000000000007', 'OP7', 'Safari Snorkel', 2),
  line('00000000-0000-4000-8000-000000000008', 'OP8', 'ARB Summit Bar', 4.5),
];
global.pdcSheetVehicles = () => [{
  __emailVehicleServerAuthoritative: true,
  __emailVehicleIdentityConflict: false,
  __emailVehicleId: canonicalId,
  pdcEmailOperationLines: allLines,
}];

const planner = require('./workshop-planner.js');
const scopedVehicle = {
  id: canonicalId,
  vehicle_id: canonicalId,
  jobCardNumber: 'J139124136',
  operation_lines: allLines.slice(2),
  workshopEstimatedHoursByStage: { FITTING: 8.5 },
  workshopAdditionalHoursByStage: {},
};
const imported = planner.workshopImportedJobLines(scopedVehicle);
assert.strictEqual(imported.length, 4, 'exact canonical Board lines supplement incomplete station snapshot lines');
assert.deepStrictEqual(imported.map(row => row.operationNo), ['OP3', 'OP4', 'OP7', 'OP8']);
const resolved = planner.workshopResolvedJobLines(scopedVehicle);
assert.deepStrictEqual(resolved.map(row => row.hours), [1.6, 0.5, 2, 4.5], 'authenticated decimal hours remain exact and are never quarter-hour snapped');
assert.strictEqual(planner.workshopCalculatedStageHours(scopedVehicle, 'FITTING'), 8.6,
  'four authenticated Fitting lines total exactly 8.6h and override stale saved 8.5h');
const increase = planner.workshopManualDurationSharedPayload({id: 'b', sharedBookingId: 'b', sharedVersion: 3, stage: 'FITTING', bay: 1, startAt: '2026-08-25T00:00:00Z', hours: 8.5}, 8.6);
assert.strictEqual(increase.durationMinutes, 516);
assert.strictEqual(increase.shiftMinutes, 6);
assert.strictEqual(increase.operation, 'extend');
const decrease = planner.workshopManualDurationSharedPayload({id: 'b', sharedVersion: 3, stage: 'FITTING', bay: 1, startAt: '2026-08-25T00:00:00Z', hours: 8.6}, 8.5);
assert.strictEqual(decrease.operation, 'resize');
assert.strictEqual(decrease.shiftMinutes, 0);

const source = fs.readFileSync('workshop-planner.js', 'utf8');
assert.match(source, /Existing booking .* h; save to align/);
assert.match(source, /step="any"/);
assert.match(source, /exact operation hours/);
console.log('Workshop complete operation projection and exact stage total: PASS');
