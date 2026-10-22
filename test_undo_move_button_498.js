/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r498 (F111): after an administrator moves a chip, 'Undo last move' shows straight away
// (the planner draws again once the receipt is kept) and goes away again after Undo.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { createSlotRuntime } = require('./tests/helpers/workshop-slot-runtime.cjs');
const planner = fs.readFileSync(path.join(__dirname, 'workshop-planner.js'), 'utf8');

function setup(role = 'administrator') {
  const r = createSlotRuntime(), c = r.context, calls = [];
  c.window.PDC_AUTH_CONTEXT = { role }; c.window.alert = () => {};
  c.workshopRequireSchedulableCandidate = () => true; c.workshopConfirmOtherDepartmentPlans = () => true;
  c.workshopLoadPlans = () => [{ id: 'booking', sharedBookingId: 'booking', sharedVersion: 3, vehicleKey: 'vehicle', stage: 'FITTING', bay: 1, status: 'planned', hours: 1 }];
  c.workshopVehicle = () => ({}); c.workshopRequireEtaSchedule = () => true; c.workshopSchedulingDuration = () => ({ hours: 1 });
  c.workshopBookingDestinationHours = () => 1; c.workshopBayMechanic = () => ''; c.pmbBayMechanic = () => '';
  c.__redraws = 0; c.scheduleWorkshopPlannerRender = () => { c.__redraws += 1; };
  c.workshopDispatchSharedAction = async (action, payload) => { calls.push({ action, payload }); return { ok: true, receipt_id: 'receipt', booking_id: 'booking', booking_version: 4 }; };
  return { r, c, calls };
}

test('a confirmed administrator move asks the planner to draw again so Undo last move shows', async () => {
  const { c, calls } = setup();
  assert.equal(await c.scheduleWorkshopVehicle({ planId: 'booking', stage: 'FITTING', bay: 2, dateKey: '2026-09-18', startMinutes: 60, preferRequestedTime: true }), true);
  assert.equal(calls[0].action, 'administratorMoveBooking');
  assert.equal(c.__redraws, 1);
});

test('a successful Undo draws again so the button goes away', async () => {
  const { c, calls } = setup();
  await c.scheduleWorkshopVehicle({ planId: 'booking', stage: 'FITTING', bay: 2, dateKey: '2026-09-18', startMinutes: 60, preferRequestedTime: true });
  assert.equal(await c.workshopUndoLastAdministratorMove(), true);
  assert.equal(calls[1].action, 'undoAdministratorBookingMove');
  assert.equal(c.__redraws, 2);
});

test('a refused move or a move without a receipt does not redraw', async () => {
  const { c } = setup();
  c.workshopDispatchSharedAction = async () => ({ ok: false, error: 'version_conflict' });
  await c.scheduleWorkshopVehicle({ planId: 'booking', stage: 'FITTING', bay: 2, dateKey: '2026-09-18', startMinutes: 60, preferRequestedTime: true });
  assert.equal(c.__redraws, 0);
  c.workshopDispatchSharedAction = async () => ({ ok: true });
  await c.scheduleWorkshopVehicle({ planId: 'booking', stage: 'FITTING', bay: 2, dateKey: '2026-09-18', startMinutes: 60, preferRequestedTime: true });
  assert.equal(c.__redraws, 0);
});

test('the redraw goes through the batched planner render and is safe without it', () => {
  assert.match(planner, /function workshopRedrawForUndoMoveButton\(\) \{\n  if \(typeof scheduleWorkshopPlannerRender === 'function'\) scheduleWorkshopPlannerRender\(\);\n\}/);
});

test('cache busts name r498 on both workshop-planner.js loads and on app.js', () => {
  const app = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8');
  assert.equal((app.match(/workshop-planner\.js\?[^`]*r498=2026\.10\.22\.r498/g) || []).length, 2);
  assert.match(fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8'), /app\.js\?[^"]*&amp;r498=2026\.10\.22\.r498/);
});
