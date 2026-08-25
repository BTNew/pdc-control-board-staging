'use strict';

const assert = require('assert');
const fs = require('fs');
global.parseIsoTimestamp = value => {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
};
global.cleanNavisionText = value => String(value == null ? '' : value).trim();
const planner = require('./workshop-planner.js');

// Reproduces the live rejection: 15.3 operation hours is exactly 918 minutes.
assert.strictEqual(planner.workshopExactDurationHours(15.3), 15.3);
assert.strictEqual(Math.round(planner.workshopExactDurationHours(15.3) * 60), 918);
assert.strictEqual(planner.workshopClampDurationHours(15.3), 15.25, 'The start-time grid snap must not be used for canonical operation duration');
const start = new Date(2026, 7, 24, 8, 0, 0, 0); // Monday at Workshop open.
const exactBooking = { startAt: start.toISOString(), hours: 15.3, status: 'planned' };
assert.strictEqual(planner.workshopNewBookingValidation(exactBooking).ok, true);
const exactEnd = planner.workshopEntryEnd(exactBooking);
assert.strictEqual(exactEnd.getDay(), 2, '918 work minutes should carry into Tuesday');
assert.strictEqual(exactEnd.getHours(), 14);
assert.strictEqual(exactEnd.getMinutes(), 18, 'The final three minutes must not be lost to 15-minute snapping');

const source = fs.readFileSync('workshop-planner.js', 'utf8');
assert.ok(source.includes('const canonicalSharedHours = workshopSharedModeActive()'));
assert.ok(source.includes('workshopExactDurationHours(workshopCalculatedStageHours(vehicle, normalizedStage)) || workshopExactDurationHours(existing?.hours)'),
  'shared scheduling derives exact duration from the complete authenticated operation-line projection');
assert.ok(source.includes('const duration = workshopExactDurationHours(hours) || workshopClampDurationHours(hours);'));
assert.ok(source.includes('readonly title="Uses the canonical operation-line estimate"'));
assert.ok(source.includes('Configured hours ${workshopTimeLabelFromMinutes(0)}–${workshopTimeLabelFromMinutes(WORKSHOP_PLANNER_CONFIG.dayLengthMinutes)}'), 'planner header renders authoritative configured hours');
assert.ok(!source.includes('Monday–Friday, 8:00am–4:00pm.'), 'planner must not display stale hard-coded hours');

const app = fs.readFileSync('app.js', 'utf8');
const index = fs.readFileSync('index.html', 'utf8');
const staging = fs.readFileSync('staging.html', 'utf8');
const version = app.match(/const APP_VERSION = '([^']+)'/)?.[1];
assert.strictEqual(version, '2026.08.25.10-qc-operation-projection');
assert.ok(index.includes(`app.js?v=${version}`));
assert.match(staging, /http-equiv=["']refresh["'][^>]+content=["']0;\s*url=\.\/["']/i);

console.log('workshop_exact_operation_minutes: PASS');