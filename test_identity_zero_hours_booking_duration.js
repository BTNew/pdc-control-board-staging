'use strict';

const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const emailService = require('./pdc-email-vehicle-location-service.js');
const modalIdentity = require('./vehicle-modal-identity.js');

const appSource = fs.readFileSync('app.js', 'utf8');
assert.match(appSource, /vehicleModalIdentity/, 'modal must retain a stable identity binding');
assert.match(appSource, /identity.*stock|stock.*identity/, 'modal binding must retain the displayed stock baseline');
assert.match(appSource, /No mutation was made|No vehicle was changed/, 'unresolved identity must fail closed');
const plannerSource = fs.readFileSync('workshop-planner.js', 'utf8');
assert.match(plannerSource, /const authoritativeStageHours = workshopCalculatedStageHours/, 'shared booking duration must be derived from authoritative projection');

const start = appSource.indexOf('function vehicleWorkshopGroups(');
const end = appSource.indexOf('\nfunction vehicleWorkshopJobCardValue', start);
assert.ok(start >= 0 && end > start, 'vehicleWorkshopGroups must be extractable');

const stages = ['BUS_4X4', 'TINT', 'HOIST', 'FITTING', 'FABRICATION', 'ELECTRICAL', 'TYRE', 'PIT_INSPECTION', 'PARTS'];
const context = {
  WORKSHOP_PLANNER_ROUTE_BY_STAGE: Object.fromEntries(stages.filter(stage => !['PIT_INSPECTION', 'PARTS'].includes(stage)).map(stage => [stage, `planner-${stage}`])),
  vehicleWorkshopLocalRequirements: () => [],
  vehicleWorkshopBookingsForStage: () => [],
  vehiclePdcJobLines: () => [],
  authenticatedOperationLineValid: value => /^OP\d+$/.test(String(value || '')),
  authenticatedOperationLineSortValue: value => [Number(String(value).replace(/\D/g, '')) || 0, 0, String(value)],
  vehicleWorkshopStageCode: value => String(value || '').trim().toUpperCase().replace(/[^A-Z0-9]+/g, '_'),
  cleanNavisionText: value => String(value == null ? '' : value).trim(),
  vehicleWorkshopLineDescription: (line, fallback = '') => String(line?.description || fallback),
  pdcJobLineStage: line => line?.stage_code || line?.stage || '',
  authenticatedOperationLineLabel: value => String(value || ''),
  vehicleWorkshopLineIdentity: (_stage, line) => line.operation_line_id ? `source:${line.operation_line_id}` : `display:${_stage}:${line.description}`,
  vehicleWorkshopAdjustedSourceHours: value => value == null || value === '' ? null : Number(value),
  vehicleWorkshopAdjustedSourceDescription: (line, adjustment) => String(adjustment?.description || line?.description || ''),
  vehicleWorkshopStationPresentation: stage => ({ label: String(stage || '').replace(/_/g, ' ') }),
};
vm.createContext(context);
vm.runInContext(appSource.slice(start, end), context);

const lines = Array.from({ length: 18 }, (_, index) => ({
  operation_line_id: `00000000-0000-4000-8000-${String(index + 1).padStart(12, '0')}`,
  operation_no: `OP${index + 1}`,
  description: `Synthetic owner line ${index + 1}`,
  estimated_hours: index === 0 ? 8.1 : 0,
  stage_code: stages[index % stages.length],
  job_card_number: 'SYNTHETIC-JC-18',
}));
const vehicle = { pdcEmailOperationLines: [] };
const detail = { requirements: [], bookings: [], job_card_lines: lines, line_adjustments: [] };
const groups = context.vehicleWorkshopGroups(vehicle, detail);
const projected = groups.flatMap(group => group.lines);
assert.strictEqual(projected.length, 16, 'all non-PIT genuine owner lines, including zero-hour lines, remain visible');
assert.strictEqual(projected.filter(line => Number(line.estimatedHours) === 0).length, 15, 'non-PIT explicit zero hours are preserved as visible evidence');
assert.ok(lines.some(line => line.operation_no === 'OP17'), 'deferred PIT source evidence remains in the immutable input');
assert.ok(!projected.some(line => line.operation_no === 'OP17'), 'deferred PIT source evidence is not rendered as PMB workshop work');
assert.ok(groups.some(group => group.stage === 'PARTS'), 'Parts evidence has a visible station');
assert.ok(!groups.some(group => group.stage === 'PIT_INSPECTION'), 'deferred Pit evidence is not a visible PMB workshop station');
assert.ok(!projected.some(line => line.fallback === true), 'generic station fallback never replaces genuine lines');
const relocatedLine = lines[2];
const relocatedGroups = context.vehicleWorkshopGroups(vehicle, {
  requirements: [], bookings: [], job_card_lines: [relocatedLine],
  line_adjustments: [{ source_kind: 'source', line_key: `source:${relocatedLine.operation_line_id}`, stage_code: 'FITTING', estimated_hours: 0.5 }],
});
assert.ok(relocatedGroups.find(group => group.stage === 'FITTING')?.lines.some(line => line.operation_no === relocatedLine.operation_no), 'adjusted lines move into their authoritative station');
assert.ok(!relocatedGroups.find(group => group.stage === 'HOIST')?.lines.some(line => line.operation_no === relocatedLine.operation_no), 'adjusted source station no longer duplicates the line');

const identityStart = appSource.indexOf('function vehicleModalIdentityStock(');
const identityEnd = appSource.indexOf('\nfunction selectedVehicle(', identityStart);
assert.ok(identityStart >= 0 && identityEnd > identityStart, 'modal identity resolver must be extractable');
const identityContext = {
  app: {
    vehicleModalIdentity: { canonicalId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', stockBaseline: '12704242' },
    emailVehicleLocationRows: [],
    data: [],
  },
  window: { PDC_EMAIL_VEHICLE_LOCATION_SERVICE: emailService, PDC_VEHICLE_MODAL_IDENTITY: modalIdentity },
  cleanNavisionText: value => String(value == null ? '' : value).trim(),
  vehicleWorkshopDetailCanonicalId: vehicle => String(vehicle.__emailVehicleId || vehicle.id || ''),
  displayStockNumber: vehicle => vehicle.stock || '',
  vehicleKey: vehicle => vehicle.stock || vehicle.stock_number || vehicle.id || '',
  applySharedWorkStateCache: rows => rows,
};
vm.createContext(identityContext);
vm.runInContext(appSource.slice(identityStart, identityEnd), identityContext);
const otherVehicle = { __emailVehicleId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', stock: '12657478' };
identityContext.app.emailVehicleLocationRows = [otherVehicle];
identityContext.app.data = [otherVehicle];
assert.strictEqual(identityContext.vehicleModalBoundVehicle(), null, 'missing Stock 12704242 cannot fall back to Stock 12657478');
const exactVehicle = { __emailVehicleId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', stock: '12704242' };
const exactRawSnapshotVehicle = { id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', stock_number: '12704242' };
identityContext.app.emailVehicleLocationRows = [otherVehicle, exactRawSnapshotVehicle];
identityContext.app.data = [exactVehicle, otherVehicle];
assert.strictEqual(identityContext.vehicleModalBoundVehicle().__emailVehicleId, exactVehicle.__emailVehicleId, 'reordered realtime rows retain exact modal UUID and Stock');
identityContext.app.emailVehicleLocationRows = [otherVehicle];
identityContext.app.data = [{ ...exactVehicle, __emailVehicleServerAuthoritative: true }, otherVehicle];
assert.strictEqual(identityContext.vehicleModalBoundVehicle().__emailVehicleId, exactVehicle.__emailVehicleId, 'cached authenticated exact row survives a transient snapshot omission');
identityContext.app.emailVehicleLocationRows = [{ ...exactVehicle, stock: '12657478' }, exactVehicle];
assert.strictEqual(identityContext.vehicleModalBoundVehicle(), null, 'conflicting UUID/Stock projection fails closed');

global.cleanNavisionText = value => String(value == null ? '' : value).trim();
global.normalizePmbStage = value => String(value || '').trim().toUpperCase();
global.vehicleWorkshopStageCode = value => String(value || '').trim().toUpperCase();
global.inferredPmbStage = () => '';
global.vehicleJobcardNumber = vehicle => vehicle.jobCardNumber || '';
global.vehiclePdcJobLines = () => [];
global.window = { workshopSharedModeEnabled: () => true, __workshopDataService: { isEnabled: () => true }, addEventListener: () => {} };
const planner = require('./workshop-planner.js');
const canonicalVehicle = {
  __emailVehicleServerAuthoritative: true,
  __emailVehicleIdentityConflict: false,
  __emailVehicleId: '11111111-1111-4111-8111-111111111111',
  pdcEmailOperationLines: [
    { operation_line_id: '00000000-0000-4000-8000-000000000003', operation_no: 'OP1', description: 'Fitting authority', estimated_hours: 8.1, work_key: 'fitting' },
    { operation_line_id: '00000000-0000-4000-8000-000000000004', operation_no: 'OP3', description: 'Adjusted fire extinguisher', estimated_hours: 0.5, work_key: 'fitting' },
  ],
  workshopEstimatedHoursByStage: { FITTING: 8.5 },
  workshopAdditionalHoursByStage: {},
};
assert.strictEqual(planner.workshopCalculatedStageHours(canonicalVehicle, 'FITTING'), 8.6, 'unscoped Board projection still totals exact authenticated lines');
const fittingMismatchVehicle = {
  ...canonicalVehicle,
  __workshopStationSnapshotAuthoritative: true,
  pdcEmailOperationLines: [
    { operation_line_id: '00000000-0000-4000-8000-000000000005', operation_no: 'OP1', description: 'Tow bar originally classified as fabrication', estimated_hours: 1.6, work_key: 'fabrication' },
    { operation_line_id: '00000000-0000-4000-8000-000000000006', operation_no: 'OP2', description: 'Long range tank moved to Hoist', estimated_hours: 1.9, work_key: 'fitting' },
  ],
  workshopEstimatedHoursByStage: { FITTING: 1.6 },
};
assert.strictEqual(planner.workshopCalculatedStageHours(fittingMismatchVehicle, 'FITTING'), 1.6, 'Stock 12704245-style adjusted Fitting authority overrides stale 1.90h raw line');
assert.strictEqual(Math.round(planner.workshopExactDurationHours(planner.workshopCalculatedStageHours(fittingMismatchVehicle, 'FITTING')) * 60), 96, 'Fitting booking submits the server expected 96 minutes');
assert.strictEqual(Math.round(planner.workshopExactDurationHours(planner.workshopCalculatedStageHours(canonicalVehicle, 'FITTING')) * 60), 516, 'booking uses exact whole minutes');

console.log('identity, zero-hour projection and authoritative booking duration: PASS');
