'use strict';

const assert = require('assert');
const fs = require('fs');
const planner = fs.readFileSync('workshop-planner.js', 'utf8');
const css = fs.readFileSync('workshop-planner.css', 'utf8');

const { createSlotRuntime, at } = require('./tests/helpers/workshop-slot-runtime.cjs');
const runtime = createSlotRuntime();
runtime.planner.workshopSyncConfigFromSharedSettings();
const running = { status: 'started', startAt: at(16, 7).toISOString(), endAt: at(16, 8).toISOString(), hours: 1 };
assert.equal(+runtime.planner.workshopEntryEffectiveEnd(running, at(16, 14, 26)), +at(16, 14, 26), 'started chips extend through the operational moment, not estimate plus one increment');
assert.ok(planner.includes("overtime ? ' · OVERTIME' : ''"), 'overdue started chips identify OVERTIME');
assert.ok(planner.includes('window.setInterval(() => {') && planner.includes('}, 60000);'), 'Workshop Planner rerenders live timing every minute');
assert.ok(css.includes('@keyframes workshop-overtime-flash'), 'overtime animation exists');
assert.ok(css.includes('.workshop-plan-chip.is-overtime') && css.includes('animation: workshop-overtime-flash'), 'overdue chips flash red');
console.log('Started indefinite-duration and overtime chip contract passed.');
