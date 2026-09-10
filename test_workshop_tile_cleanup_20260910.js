'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const cleanup = require('./pdc-workshop-tile-cleanup.js');

test('single-click planner selection hides the duplicate top detail panel', () => {
  assert.equal(cleanup.shouldHideSelectionPanel({ id: 'booking-1' }, false), true);
  assert.equal(cleanup.shouldHideSelectionPanel({ id: 'booking-1' }, undefined), true);
});

test('explicit focused-booking mode retains detailed booking controls', () => {
  assert.equal(cleanup.shouldHideSelectionPanel({ id: 'booking-1' }, true), false);
  assert.equal(cleanup.shouldHideSelectionPanel(null, false), false);
});

test('canonical bootstrap loads current planner cleanup asset', () => {
  const source = fs.readFileSync('canonical-entry.js', 'utf8');
  assert.match(source, /pdc-workshop-tile-cleanup\.js\?v=2026\.09\.10\.03/);
});

test('planner search collapses duplicate frontend rows that resolve to one canonical vehicle', () => {
  const booking = { id: '91c7b519', stage: 'FITTING', bay: 2, startAt: '2026-09-10T07:27:00+08:00' };
  const rows = cleanup.dedupeSearchMatches([
    {
      vehicleIdentity: 'shared:a0609eff-4e4a-5292-af93-6e0b5b975c15',
      vehicleKey: 'legacy-rich', rank: 0, archived: false,
      vehicle: { stock: '13056890', jobCardNumber: 'JC14124638', vehicle: 'Prado 2.8L 48V Dsl Wgn 8AT', client: 'BOAB HEALTH AND COMMUNITY SERVICES' },
      bookings: [booking], candidateInLane: true, candidateAvailable: true,
    },
    {
      vehicleIdentity: 'shared:a0609eff-4e4a-5292-af93-6e0b5b975c15',
      vehicleKey: 'shared-row', rank: 0, archived: false,
      vehicle: { sharedVehicleId: 'a0609eff-4e4a-5292-af93-6e0b5b975c15', stock: '13056890', jobCardNumber: '', vehicle: '', client: 'BOAB HEALTH AND COMMUNITY SERVICES' },
      bookings: [{ ...booking }], candidateInLane: false, candidateAvailable: false,
    },
  ]);
  assert.equal(rows.length, 1);
  assert.equal(rows[0].vehicleIdentity, 'shared:a0609eff-4e4a-5292-af93-6e0b5b975c15');
  assert.equal(rows[0].bookings.length, 1);
  assert.equal(rows[0].vehicle.jobCardNumber, 'JC14124638');
  assert.equal(rows[0].candidateAvailable, true);
});

test('QC rejected vehicle fallback row collapses into its one canonical shared vehicle', () => {
  const rows = cleanup.dedupeSearchMatches([
    {
      vehicleIdentity: 'legacy:13015144-rich', vehicleKey: '13015144-rich', rank: 0,
      vehicle: { stock: '13015144', jobCardNumber: 'JC14124710', vehicle: 'HiAce', client: 'OAKES' },
      bookings: [], candidateInLane: true, candidateAvailable: true,
    },
    {
      vehicleIdentity: 'shared:05962953-af16-5427-9f50-3d66a15fb8a2', vehicleKey: 'candidate-fallback', rank: 0,
      vehicle: { sharedVehicleId: '05962953-af16-5427-9f50-3d66a15fb8a2', stock: '13015144', jobCardNumber: '', vehicle: 'Vehicle description unavailable', client: 'OAKES' },
      bookings: [], candidateInLane: true, candidateAvailable: true,
    },
  ]);
  assert.equal(rows.length, 1);
  assert.equal(rows[0].vehicleIdentity, 'shared:05962953-af16-5427-9f50-3d66a15fb8a2');
  assert.equal(rows[0].vehicle.jobCardNumber, 'JC14124710');
  assert.equal(rows[0].vehicle.vehicle, 'HiAce');
  assert.equal(rows[0].candidateAvailable, true);
});

test('same Stock text never collapses genuinely different shared vehicle identities', () => {
  const rows = cleanup.dedupeSearchMatches([
    { vehicleIdentity: 'shared:vehicle-a', vehicle: { stock: '13056890' }, bookings: [] },
    { vehicleIdentity: 'shared:vehicle-b', vehicle: { stock: '13056890' }, bookings: [] },
  ]);
  assert.equal(rows.length, 2);
});

test('weak fallback does not collapse when strong identity conflicts with canonical vehicle', () => {
  const rows = cleanup.dedupeSearchMatches([
    { vehicleIdentity: 'shared:vehicle-a', vehicle: { sharedVehicleId: 'vehicle-a', stock: '13015144', vin: 'VIN-A' }, bookings: [] },
    { vehicleIdentity: 'legacy:fallback', vehicle: { stock: '13015144', vin: 'VIN-B', jobCardNumber: 'JC14124710' }, bookings: [] },
  ]);
  assert.equal(rows.length, 2);
  assert.equal(cleanup.strongIdentityConflicts(rows[0].vehicle, rows[1].vehicle), true);
});

test('two unresolved legacy rows with same Stock are not guessed into one vehicle', () => {
  const rows = cleanup.dedupeSearchMatches([
    { vehicleIdentity: 'legacy:a', vehicle: { stock: '13015144' }, bookings: [] },
    { vehicleIdentity: 'legacy:b', vehicle: { stock: '13015144' }, bookings: [] },
  ]);
  assert.equal(rows.length, 2);
});

test('one vehicle with multiple distinct bookings stays one vehicle and keeps both bookings', () => {
  const rows = cleanup.dedupeSearchMatches([
    { vehicleIdentity: 'shared:vehicle-a', vehicle: { sharedVehicleId: 'vehicle-a', stock: '13056890' }, bookings: [{ id: 'booking-1' }] },
    { vehicleIdentity: 'legacy:rich', vehicle: { stock: '13056890', jobCardNumber: 'JC1' }, bookings: [{ id: 'booking-2' }] },
  ]);
  assert.equal(rows.length, 1);
  assert.deepEqual(rows[0].bookings.map(row => row.id), ['booking-1', 'booking-2']);
});

test('planner tiles retain their own lifecycle and drag controls', () => {
  const planner = fs.readFileSync('workshop-planner.js', 'utf8');
  assert.match(planner, /data-workshop-start-plan=/);
  assert.match(planner, /data-workshop-stop-plan=/);
  assert.match(planner, /data-workshop-complete-plan=/);
  assert.match(planner, /data-workshop-resize-plan=/);
  assert.match(planner, /draggable="true"/);
});
