'use strict';

const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const source = fs.readFileSync('app.js', 'utf8');
const indexSource = fs.readFileSync('index.html', 'utf8');
const migrationPath = 'supabase/staging_only/20260904010300_defer_pit_from_physical_qc_gate.sql';
assert.ok(indexSource.includes('Pit Inspection is retained as a deferred future QC step, not a Workshop station.'), 'deployed guidance describes deferred PIT accurately');
assert.ok(!indexSource.includes('Pit Inspection is a required workshop station'), 'deployed guidance must not call PIT a required Workshop station');
assert.ok(!indexSource.includes('Pit Inspection is a required workshop station with one physical bay'), 'deployed guidance must not claim a physical PIT bay');
assert.ok(!indexSource.includes('including Pit Inspection'), 'RFT guidance must not include deferred PIT in required station jobs');
assert.ok(indexSource.includes('all required physical Workshop station jobs and Parts are complete'), 'RFT guidance names only the active physical gate');

function extract(startMarker, endMarker) {
  const start = source.indexOf(startMarker);
  const end = source.indexOf(endMarker, start);
  assert.ok(start >= 0 && end > start, `${startMarker} must be extractable`);
  return source.slice(start, end);
}

const gateContext = {
  pdcRequirementDefinitions: vehicle => vehicle.requirements || [],
  vehiclePdcLocation: vehicle => vehicle.location,
  isPdcBlocked: () => false,
  isActivePartsStoppage: () => false,
  pdcJobComplete: (_vehicle, job) => job.complete === true,
  normalizePmbStage: value => value || '',
  inferredPmbStage: vehicle => vehicle.stage || '',
};
vm.createContext(gateContext);
vm.runInContext(
  `${extract('function pdcQualityControlRequirementDefinitions(', '\nfunction vehicleRftGateIssues')}\n`
  + `${extract('function vehicleReadyForQualityControl(', '\nfunction vehicleInQualityControlGate')}`,
  gateContext,
);
const deferredPitVehicle = {
  location: 'PMB',
  stage: '',
  requirements: [
    { key: 'fitting', label: 'Fitting', complete: true },
    { key: 'pitInspection', label: 'PIT', complete: false },
    { key: 'parts', label: 'Parts', complete: false },
  ],
};
assert.deepStrictEqual(
  Array.from(gateContext.pdcQualityControlRequirementDefinitions(deferredPitVehicle), job => job.key),
  ['fitting'],
  'deferred PIT and Parts are not physical workshop QC gate requirements',
);
assert.strictEqual(gateContext.vehicleReadyForQualityControl(deferredPitVehicle), true, 'deferred PIT alone cannot block Ready for QC');
assert.strictEqual(gateContext.vehicleReadyForQualityControl({ ...deferredPitVehicle, stage: 'PIT_INSPECTION' }), true, 'obsolete deferred PIT stage cannot block Ready for QC');
assert.strictEqual(
  gateContext.vehicleReadyForQualityControl({ ...deferredPitVehicle, requirements: [{ key: 'fitting', label: 'Fitting', complete: false }] }),
  false,
  'an incomplete non-PIT physical workshop item still blocks Ready for QC',
);

const workshopContext = {
  WORKSHOP_PLANNER_ROUTE_BY_STAGE: { FITTING: 'planner-fitting' },
  VEHICLE_WORKSHOP_STATION_PRESENTATION: { FITTING: { label: 'Fitting' }, PIT_INSPECTION: { label: 'Pit inspection' } },
  vehicleWorkshopLocalRequirements: () => [],
  vehicleWorkshopBookingsForStage: () => [],
  vehiclePdcJobLines: () => [],
  authenticatedOperationLineValid: value => /^OP\d+$/.test(String(value || '')),
  authenticatedOperationLineSortValue: value => [Number(String(value).replace(/\D/g, '')) || 0, 0, String(value)],
  vehicleWorkshopStageCode: value => ({ fitting: 'FITTING', pitInspection: 'PIT_INSPECTION', pitinspection: 'PIT_INSPECTION', FITTING: 'FITTING', PIT_INSPECTION: 'PIT_INSPECTION' }[String(value)] || ''),
  cleanNavisionText: value => String(value == null ? '' : value).trim(),
  vehicleWorkshopLineDescription: (line, fallback = '') => String(line?.description || fallback),
  pdcJobLineStage: line => line?.stage || '',
  authenticatedOperationLineLabel: value => String(value || ''),
  vehicleWorkshopLineIdentity: (_stage, line) => line.operation_line_id ? `source:${line.operation_line_id}` : `display:${_stage}:${line.description}`,
  vehicleWorkshopAdjustedSourceHours: value => value == null || value === '' ? null : Number(value),
  vehicleWorkshopAdjustedSourceDescription: (line, adjustment) => String(adjustment?.description || line?.description || ''),
  vehicleWorkshopStationPresentation: stage => ({ label: stage }),
};
vm.createContext(workshopContext);
vm.runInContext(extract('function vehicleWorkshopGroups(', '\nfunction vehicleWorkshopJobCardValue'), workshopContext);
const groups = workshopContext.vehicleWorkshopGroups({
  pdcEmailOperationLines: [
    { operation_line_id: '11111111-1111-4111-8111-111111111111', operation_no: 'OP8', work_key: 'fitting', description: 'Physical fitment', estimated_hours: 1 },
    { operation_line_id: '99999999-9999-4999-8999-999999999999', operation_no: 'OP9', work_key: 'pitInspection', description: 'PIT AND WEIGH', estimated_hours: 0 },
  ],
}, {
  requirements: [
    { required: true, completed: false, work_key: 'fitting', stage_code: 'FITTING' },
    { required: true, completed: false, work_key: 'pitInspection', stage_code: 'PIT_INSPECTION' },
  ],
  bookings: [],
  job_card_lines: [],
  line_adjustments: [],
});
assert.ok(groups.some(group => group.stage === 'FITTING'), 'physical workshop job card remains visible');
assert.ok(!groups.some(group => group.stage === 'PIT_INSPECTION'), 'deferred PIT does not render as a PMB workshop job/bay card');

assert.ok(fs.existsSync(migrationPath), 'append-only deferred PIT QC successor must exist');
const migration = fs.readFileSync(migrationPath, 'utf8');
for (const marker of [
  'PITINSPECTION',
  'pdc_qc_gate_issues',
  'mark_vehicle_ready_for_qc',
  "stock_number_normalized='13048501'",
  "operation_no='OP9'",
  "work_key='pitInspection'",
  'completed=false',
  'vehicle_version_conflict',
]) assert.ok(migration.includes(marker), `migration must preserve ${marker}`);
assert.doesNotMatch(migration, /UPDATE\s+public\.vehicle_work_items[\s\S]{0,200}completed\s*=\s*true/i, 'migration must not fake PIT completion');
assert.doesNotMatch(migration, /DELETE\s+FROM\s+public\.pdc_authenticated_email_operation_lines/i, 'migration must not delete OP9 source evidence');

const rpcSuccessorPath = 'supabase/staging_only/20260904010400_deferred_pit_stage_rpc_successor.sql';
assert.ok(fs.existsSync(rpcSuccessorPath), 'reviewed PIT stage/RPC successor must exist');
const rpcSuccessor = fs.readFileSync(rpcSuccessorPath, 'utf8');
for (const marker of [
  "s.code<>'PIT_INSPECTION'",
  "'PITINSPECTION'",
  'mark_vehicle_ready_for_qc',
  "pmb_stage=NULL",
  "pmb_bay_stage=NULL",
  "pmb_bay_number=NULL",
  "require_pdc_role('operator')",
  'vehicle_version_conflict',
]) assert.ok(rpcSuccessor.includes(marker), `RPC successor must preserve ${marker}`);

console.log('Deferred PIT QC gate regression: PASS');
