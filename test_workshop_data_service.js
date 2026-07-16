'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const service = require('./workshop-data-service.js');

const source = fs.readFileSync(path.join(__dirname, 'workshop-data-service.js'), 'utf8');
const assignment = service._test.chooseAssignment([
  { technician_id: 'released-primary', assignment_type: 'primary', assigned_at: '2026-07-16T09:00:00Z', released_at: '2026-07-16T10:00:00Z' },
  { technician_id: 'active-secondary', assignment_type: 'secondary', assigned_at: '2026-07-16T11:00:00Z', released_at: null },
  { technician_id: 'active-primary', assignment_type: 'primary', assigned_at: '2026-07-16T08:00:00Z', released_at: null },
]);
assert.strictEqual(assignment.technician_id, 'active-primary', 'Active primary assignment must win over released or secondary assignments');

const indexes = {
  stages: new Map([['stage-1', { id: 'stage-1', code: 'FITTING' }]]),
  bays: new Map([['bay-1', { id: 'bay-1', bay_number: 3 }]]),
  technicians: new Map([['tech-1', { id: 'tech-1', name: 'Alex Mechanic' }]]),
  vehicles: new Map([['vehicle-1', {
    id: 'vehicle-1',
    permanent_vehicle_id: 'vehicle-key-1',
    stock_number: 'S100',
    job_card_number: 'JC100',
    customer_name: 'Example Customer',
    model: 'Hilux',
  }]]),
  assignments: new Map([['booking-1', [{
    booking_id: 'booking-1', technician_id: 'tech-1', assignment_type: 'primary', assigned_at: '2026-07-16T08:00:00Z', released_at: null,
  }]]]),
};
const mapped = service._test.mapBookingRow({
  id: 'booking-1', vehicle_id: 'vehicle-1', stage_id: 'stage-1', bay_id: 'bay-1',
  status: 'planned', scheduled_start_at: '2026-07-17T00:00:00Z', scheduled_end_at: '2026-07-17T03:00:00Z',
  default_duration_minutes: 180, version: 7, created_at: '2026-07-16T00:00:00Z', updated_at: '2026-07-16T01:00:00Z',
}, indexes);
assert.strictEqual(mapped.vehicleKey, 'vehicle-key-1', 'Shared booking must map to the permanent vehicle key used by the planner');
assert.strictEqual(mapped.stage, 'FITTING');
assert.strictEqual(mapped.bay, 3);
assert.strictEqual(mapped.hours, 3);
assert.strictEqual(mapped.assignee, 'Alex Mechanic');
assert.strictEqual(mapped.version, 7);


const adaptedVehicle = service._test.plannerVehicleFromRow({
  id: 'db-vehicle-1',
  permanent_vehicle_id: 'ORDER-1',
  stock_number: 'S300',
  job_card_number: 'JC300',
  customer_name: 'Shared Customer',
  make: 'Toyota',
  model: 'HiLux',
  current_location: 'PMB',
  pmb_stage: 'FITTING',
  pmb_bay_number: '2',
  visible_on_board: true,
  lifecycle_state: 'active',
  source_payload: { pdcRequiresFitting: true, consultant: 'BG' },
  version: 4,
  updated_at: '2026-07-16T02:00:00Z',
});
assert.strictEqual(adaptedVehicle.stock, 'S300');
assert.strictEqual(adaptedVehicle.customer, 'Shared Customer');
assert.strictEqual(adaptedVehicle.pdcLocation, 'PMB');
assert.strictEqual(adaptedVehicle.pdcRequiresFitting, true, 'Shared vehicle adapter must retain operational source payload fields used by the planner queue');
assert.strictEqual(adaptedVehicle.databaseVehicleId, 'db-vehicle-1');

const bayError = service._test.mutationError({
  error: 'bay_overlap',
  conflict: { existing_booking: { vehicle: { stock_number: 'S200' }, stage: { display_name: 'Fitting' }, bay: { display_name: 'Bay 2' }, scheduled_start_at: '2026-07-17T01:00:00Z' } },
});
assert.strictEqual(bayError.code, 'bay_overlap');
assert.match(bayError.message, /already booked for S200/);

for (const table of ['workshop_bookings', 'workshop_booking_assignments', 'workshop_booking_history', 'workshop_bays', 'workshop_technicians', 'workshop_settings', 'vehicles']) {
  assert.ok(source.includes(`'${table}'`), `Realtime subscription list is missing ${table}`);
}
for (const rpc of ['workshop_create_booking', 'workshop_update_booking', 'workshop_start_booking', 'workshop_record_stoppage', 'workshop_resume_booking', 'workshop_complete_booking', 'workshop_return_booking_to_queue', 'workshop_delete_booking']) {
  assert.ok(source.includes(`'${rpc}'`), `Shared service is missing RPC ${rpc}`);
}
assert.ok(source.includes("getPlannerVehicles"), 'Shared service must expose Supabase-backed planner vehicles');
assert.ok(source.includes("Number(settings.frontend_contract_version) < 1"), 'Shared mode must fail closed when migration 009 has not been applied');
assert.ok(source.includes('sharedData: workshop.sharedData === true'), 'Shared mode must require an explicit post-migration cutover flag');
assert.ok(source.includes("state.plans = mappedBookings.filter(row => !['queued', 'deleted'].includes(row.status));"), 'Queued rows must stay in the shared cache without rendering as booked timeline plans');
assert.ok(source.includes("root.dispatchEvent(new root.CustomEvent('pdc-workshop-data-changed'"), 'Shared data changes must notify the planner UI');

console.log('Workshop shared data service checks passed');
