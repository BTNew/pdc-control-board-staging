'use strict';

const assert = require('assert');
const fs = require('fs');
const guard = require('./vehicle-requirements-guard.js');

const BOOKABLE = ['bus4x4', 'tint', 'hoist', 'fitting', 'fabrication', 'electrical', 'tyre', 'pitInspection'];
for (const workKey of BOOKABLE) {
  const stageCode = workKey === 'bus4x4' ? 'BUS_4X4' : workKey === 'pitInspection' ? 'PIT_INSPECTION' : workKey.toUpperCase();
  const booking = { stage_code: stageCode, status: 'planned' };
  assert.strictEqual(guard.projectWorkState({ workKey, required: true }).state, 'required', `${workKey} starts red/required`);
  assert.strictEqual(guard.projectWorkState({ workKey, required: true, bookings: [booking] }).state, 'booked', `${workKey} books orange`);
  assert.strictEqual(guard.projectWorkState({ workKey, required: true, completed: true, bookings: [booking] }).state, 'completed', `${workKey} completes green`);
}

assert.deepStrictEqual(
  guard.projectWorkState({
    workKey: 'fitting',
    required: true,
    bookings: [{ stage_code: 'FITTING', status: 'stoppage', stoppage_reason: 'Awaiting bracket' }],
  }),
  { state: 'stoppage', marker: '!', label: 'STOPPAGE', reason: 'Awaiting bracket' },
  'Workshop STOPPAGE is an explicit canonical state, never ordinary booked work',
);
assert.deepStrictEqual(
  guard.projectWorkState({ workKey: 'parts', required: true, partsOrdered: true, partsStoppage: true, stoppageReason: 'Back order' }),
  { state: 'stoppage', marker: '!', label: 'STOPPAGE', reason: 'Back order' },
  'Parts STOPPAGE uses the same canonical state',
);
assert.strictEqual(
  guard.projectWorkState({ workKey: 'sublet', required: true, subletBookings: [{ status: 'active' }] }).state,
  'booked',
  'Sublet remains canonically booked',
);

const appSource = fs.readFileSync('app.js', 'utf8');
const plannerSource = fs.readFileSync('workshop-planner.js', 'utf8');
assert.match(appSource, /function canonicalVehicleWorkState[\s\S]*projectWorkState/, 'app exposes one canonical adapter around the shared projector');
assert.match(plannerSource, /canonicalVehicleWorkState\(/, 'Workshop Planner consumes the shared canonical projection');
assert.match(appSource, /function partsDepartmentStatus[\s\S]{0,800}canonicalVehicleWorkState\(/, 'Parts consumes the shared canonical projection');
assert.match(appSource, /function pdcJobTriStateControl[\s\S]{0,1200}canonicalVehicleWorkState\(/, 'Vehicle Detail consumes the shared canonical projection');
assert.match(appSource, /function incomingWorkChecklistHtml[\s\S]{0,2400}canonicalVehicleWorkState\(/, 'Workflow Board consumes the shared canonical projection');

console.log('PDC-14 canonical work-state successor: PASS');
