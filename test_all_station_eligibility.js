'use strict';

const assert = require('assert');
const eligibility = require('./workshop-eligibility.js');

const STATIONS = ['BUS_4X4', 'TINT', 'HOIST', 'FITTING', 'FABRICATION', 'ELECTRICAL', 'TYRE', 'PIT_INSPECTION'];
const ALIASES = {
  BUS_4X4: ['Bus4x4', 'Bus 4x4', 'BUS4X4', 'BUS_4X4', 'Department 138'],
  TINT: ['Tint', 'TINTING'],
  HOIST: ['Hoist', 'Pit Hoist', 'Pits Hoist'],
  FITTING: ['Fitting', 'Fitment'],
  FABRICATION: ['Fabrication', 'Fab'],
  ELECTRICAL: ['Electrical', 'Elec'],
  TYRE: ['Tyre Bay', 'Tyre', 'Tire'],
  PIT_INSPECTION: ['Pit Inspection', 'Pit', 'Pits'],
};

assert.deepStrictEqual(eligibility.workshopPlannerStageCodes(), STATIONS);
assert.strictEqual(eligibility.workshopStageDefinition('SUBLET').plannerEnabled, false);
assert.strictEqual(eligibility.workshopStageDefinition('SUBLET').route, '');
assert.strictEqual(eligibility.workshopIsPlannerStage('SUBLET'), false);
for (const stage of STATIONS) {
  for (const alias of ALIASES[stage]) assert.strictEqual(eligibility.canonicalWorkshopStage(alias), stage, `${alias} -> ${stage}`);
  const def = eligibility.workshopStageDefinition(stage);
  assert.strictEqual(eligibility.canonicalWorkshopStage(def.workKey), stage, `${def.workKey} work key -> ${stage}`);
}

function vehicle(id, location, eta = '') {
  return { id, lifecycle_state: 'active', deleted_at: null, current_location: location, eta_to_kewdale: eta };
}
function item(vehicleId, key, completed = false) {
  return { vehicle_id: vehicleId, work_key: key, required: true, completed };
}
function booking(vehicleId, stage, status = 'planned') {
  return { id: `B-${vehicleId}-${status}`, vehicle_id: vehicleId, stage_code: stage, status };
}

let assertions = 0;
for (const stage of STATIONS) {
  const def = eligibility.workshopStageDefinition(stage);
  const other = STATIONS.find(value => value !== stage);
  const vehicles = [
    vehicle(`${stage}-PMB`, 'PMB'),
    vehicle(`${stage}-YH`, 'YH'),
    vehicle(`${stage}-IT-VALID`, 'IT', '2026-07-24'),
    vehicle(`${stage}-IT-MISSING`, 'IT', ''),
    vehicle(`${stage}-BOOKED`, 'PMB'),
    vehicle(`${stage}-COMPLETED`, 'PMB'),
    vehicle(`${stage}-NONE`, 'PMB'),
    vehicle(`${stage}-ALIAS`, 'YH'),
    vehicle(`${stage}-WRONG-LOCATION`, 'RFT'),
    vehicle(`${stage}-BOOKED-WRONG-LOCATION`, 'RFT'),
    vehicle(`${other}-LEAK`, 'PMB'),
  ];
  const workItems = [
    item(`${stage}-PMB`, def.workKey),
    item(`${stage}-YH`, def.workKey),
    item(`${stage}-IT-VALID`, def.workKey),
    item(`${stage}-IT-MISSING`, def.workKey),
    item(`${stage}-BOOKED`, def.workKey),
    item(`${stage}-COMPLETED`, def.workKey, true),
    item(`${stage}-ALIAS`, ALIASES[stage][0]),
    item(`${stage}-ALIAS`, def.workKey),
    item(`${stage}-WRONG-LOCATION`, def.workKey),
    item(`${stage}-BOOKED-WRONG-LOCATION`, def.workKey),
    item(`${other}-LEAK`, eligibility.workshopStageDefinition(other).workKey),
  ];
  const bookings = [
    booking(`${stage}-BOOKED`, stage),
    booking(`${stage}-BOOKED-WRONG-LOCATION`, stage),
    booking(`${stage}-COMPLETED`, stage, 'completed'),
  ];
  const result = eligibility.workshopCanonicalEligibility({ stage, vehicles, workItems, bookings });
  const ids = result.candidates.map(row => row.vehicle.id).sort();
  assert.deepStrictEqual(ids, [
    `${stage}-ALIAS`, `${stage}-BOOKED`, `${stage}-IT-MISSING`, `${stage}-IT-VALID`, `${stage}-PMB`, `${stage}-YH`,
  ].sort(), `${stage} canonical candidates`);
  assert.strictEqual(new Set(ids).size, ids.length, `${stage} duplicate aliases deduplicated`);
  assert.strictEqual(result.availableCount, ids.length, `${stage} count equals candidates`);
  assert.strictEqual(result.candidates.find(row => row.vehicle.id === `${stage}-PMB`).schedule.enabled, true);
  assert.strictEqual(result.candidates.find(row => row.vehicle.id === `${stage}-YH`).schedule.enabled, true);
  assert.strictEqual(result.candidates.find(row => row.vehicle.id === `${stage}-IT-VALID`).schedule.enabled, true);
  assert.strictEqual(result.candidates.find(row => row.vehicle.id === `${stage}-IT-VALID`).schedule.earliestDateKey, '2026-07-24');
  assert.strictEqual(result.candidates.find(row => row.vehicle.id === `${stage}-IT-MISSING`).schedule.enabled, false);
  assert.strictEqual(result.candidates.find(row => row.vehicle.id === `${stage}-IT-MISSING`).schedule.reason, 'ETA to Kewdale is missing');
  assert.strictEqual(result.candidates.find(row => row.vehicle.id === `${stage}-BOOKED`).existingBooking, true);
  assert.strictEqual(result.excluded.some(row => row.vehicle.id === `${stage}-WRONG-LOCATION` && row.reason === 'location'), true);
  assert.strictEqual(result.excluded.some(row => row.vehicle.id === `${stage}-BOOKED-WRONG-LOCATION` && row.reason === 'location'), true);
  assert.strictEqual(result.excluded.some(row => row.vehicle.id === `${stage}-COMPLETED` && row.reason === 'completed'), true);
  assert.strictEqual(result.excluded.some(row => row.vehicle.id === `${other}-LEAK`), true);
  assert.deepStrictEqual(
    eligibility.workshopCanonicalEligibility({ stage, vehicles, workItems, bookings }).candidates.map(row => row.vehicle.id),
    result.candidates.map(row => row.vehicle.id),
    `${stage} refresh is deterministic`
  );
  const realtimeRequirementChange = eligibility.workshopCanonicalEligibility({
    stage,
    vehicles,
    workItems: workItems.filter(row => row.vehicle_id !== `${stage}-PMB`),
    bookings,
  });
  assert.strictEqual(realtimeRequirementChange.candidates.some(row => row.vehicle.id === `${stage}-PMB`), false, `${stage} requirement change refreshes eligibility`);
  const realtimeLocationChange = eligibility.workshopCanonicalEligibility({
    stage,
    vehicles: vehicles.map(row => row.id === `${stage}-YH` ? { ...row, current_location: 'RFT' } : row),
    workItems,
    bookings,
  });
  assert.strictEqual(realtimeLocationChange.candidates.some(row => row.vehicle.id === `${stage}-YH`), false, `${stage} location change refreshes eligibility`);
  assertions += 16;
}

const dtoVehicles = [vehicle('DTO-BOOKING-ONLY', 'PMB'), vehicle('DTO-COMPLETED-ACTIVE', 'PMB'), vehicle('DTO-STOPPAGE', 'RFT'), vehicle('DTO-RECENT-COMPLETED', 'PMB')];
const dtoWorkItems = [item('DTO-COMPLETED-ACTIVE', 'bus4x4', true), item('DTO-RECENT-COMPLETED', 'bus4x4', true)];
const dtoBookings = [
  { vehicle_id: 'DTO-BOOKING-ONLY', stage: { id: 'S1', code: 'BUS_4X4' }, status: 'planned' },
  { vehicle_id: 'DTO-COMPLETED-ACTIVE', stage: { id: 'S1', code: 'BUS_4X4' }, status: 'started' },
  { vehicle_id: 'DTO-STOPPAGE', stage: { id: 'S1', code: 'BUS_4X4' }, status: 'stoppage' },
  { vehicle_id: 'DTO-RECENT-COMPLETED', stage: { id: 'S1', code: 'BUS_4X4' }, status: 'completed' },
];
const dtoResult = eligibility.workshopCanonicalEligibility({ stage: 'BUS_4X4', vehicles: dtoVehicles, workItems: dtoWorkItems, bookings: dtoBookings });
assert.deepStrictEqual(dtoResult.candidates.map(row => row.vehicle.id), []);
assert.strictEqual(dtoResult.excluded.find(row => row.vehicle.id === 'DTO-BOOKING-ONLY').reason, 'requirement');
assert.strictEqual(dtoResult.excluded.find(row => row.vehicle.id === 'DTO-COMPLETED-ACTIVE').reason, 'completed');
assert.strictEqual(dtoResult.excluded.find(row => row.vehicle.id === 'DTO-STOPPAGE').reason, 'requirement');
assert.strictEqual(dtoResult.excluded.find(row => row.vehicle.id === 'DTO-RECENT-COMPLETED').reason, 'completed');

const sublet = eligibility.workshopStageDefinition('Sublet');
assert.strictEqual(sublet.code, 'SUBLET');
assert.strictEqual(sublet.statusVisible, true);
assert.strictEqual(sublet.plannerEnabled, false);
assert.throws(() => eligibility.assertWorkshopPlannerTarget('SUBLET'), /not a schedulable planner station/i);

console.log(`All-station canonical eligibility regression: ${assertions + 40} assertions passed`);
