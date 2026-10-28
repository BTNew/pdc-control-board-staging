'use strict';
// r661 (F271): a station icon is orange ! only when the job sits in a bay. Queued (no bay) stays a red dot.
const test = require('node:test');
const assert = require('node:assert');
const { projectWorkState } = require('./vehicle-requirements-guard.js');

const base = { workKey: 'fitting', required: true, completed: false };
test('queued with no bay is a red dot, not booked', () => {
  const s = projectWorkState({ ...base, bookings: [{ stage_code: 'FITTING', status: 'queued', bay_id: null }] });
  assert.equal(s.state, 'required'); assert.equal(s.marker, '•');
});
test('planned in a bay is orange booked', () => {
  const s = projectWorkState({ ...base, bookings: [{ stage_code: 'FITTING', status: 'planned', bay_id: 'b1' }] });
  assert.equal(s.state, 'booked'); assert.equal(s.marker, '!');
});
test('started in a bay is orange booked', () => {
  assert.equal(projectWorkState({ ...base, bookings: [{ stage_code: 'FITTING', status: 'started', bay_number: 2 }] }).state, 'booked');
});
test('a booking for another station does not count', () => {
  assert.equal(projectWorkState({ ...base, bookings: [{ stage_code: 'HOIST', status: 'planned', bay_id: 'b1' }] }).state, 'required');
});
test('stoppage and completed are unchanged', () => {
  assert.equal(projectWorkState({ ...base, bookings: [{ stage_code: 'FITTING', status: 'stoppage', bay_id: null }] }).state, 'stoppage');
  assert.equal(projectWorkState({ ...base, completed: true, bookings: [] }).state, 'completed');
});
