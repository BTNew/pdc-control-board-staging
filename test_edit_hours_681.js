'use strict';
// r681 (F291): Edit hours saves for vehicles with no job card on the vehicle row; description box on hover only; tidy hours.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const app = fs.readFileSync('app.js', 'utf8');
function jobCardFn() {
  const start = app.indexOf('function vehicleWorkshopHoursBatchJobCard');
  const end = app.indexOf('\nasync function saveVehicleWorkshopLineHoursBatch', start);
  const ctx = { vehicleJobcardNumber: v => v.jc || '' };
  vm.runInNewContext(app.slice(start, end), ctx);
  return ctx.vehicleWorkshopHoursBatchJobCard;
}
test('a vehicle with no job card uses one from its lines; a matching vehicle job card is kept', () => {
  const pick = jobCardFn();
  const detail = { job_card_lines: [{ job_card_number: 'J1' }, { lines: [{ job_card_number: 'J2' }] }] };
  assert.equal(pick({}, detail), 'J1');
  assert.equal(pick({ jc: 'J2' }, detail), 'J2');
  assert.equal(pick({ jc: 'J9 · J2' }, detail), 'J2');
  assert.equal(pick({ jc: 'J9' }, {}), 'J9');
  assert.match(app, /jobCardNumber: vehicleWorkshopHoursBatchJobCard\(vehicle, detail\)/);
});
test('the full description shows only on description hover, not while typing hours', () => {
  const css = fs.readFileSync('pdc-vehicle-slideout.css', 'utf8');
  assert.match(css, /li\[data-vso-full\]:has\(> span:hover\)::after/);
  assert.doesNotMatch(css, /li\[data-vso-full\]:focus-within::after|li\[data-vso-full\]:hover::after/);
  assert.match(css, /input\[data-vehicle-workshop-hours-batch-input\] \{/);
  assert.match(fs.readFileSync('pdc-vehicle-slideout.js', 'utf8'), /pdc-vehicle-slideout\.css\?vehicle-slideout=\$\{VERSION\}&r681=2026\.10\.29\.r681/);
});
test('r682 migration: controller completion ticks the station except Later items', () => {
  const sql = fs.readFileSync('supabase/migrations/20261029020000_r682_booking_complete_ticks.sql', 'utf8');
  assert.match(sql, /NOT IN \('operator', 'administrator'\) THEN RETURN NULL/);
  assert.match(sql, /pdc_line_later_627/);
  assert.match(sql, /EXCEPTION WHEN OTHERS THEN NULL; -- a tick never blocks the completion/);
});
