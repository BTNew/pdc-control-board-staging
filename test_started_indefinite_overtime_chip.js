'use strict';

const assert = require('assert');
const fs = require('fs');
const planner = fs.readFileSync('workshop-planner.js', 'utf8');
const css = fs.readFileSync('workshop-planner.css', 'utf8');

assert.ok(planner.includes("if (entry.status === 'started')"), 'started jobs have a dedicated live-end rule');
assert.ok(planner.includes('const liveMoment = workshopLatestWorkMoment(now);'), 'started jobs extend through the current operational moment');
assert.ok(planner.includes('return liveMoment > plannedEnd ? liveMoment : plannedEnd;'), 'started chips do not stop at estimate plus one increment');
assert.ok(planner.includes("overtime ? ' · OVERTIME' : ''"), 'overdue started chips identify OVERTIME');
assert.ok(planner.includes('window.setInterval(() => {') && planner.includes('}, 60000);'), 'Workshop Planner rerenders live timing every minute');
assert.ok(css.includes('@keyframes workshop-overtime-flash'), 'overtime animation exists');
assert.ok(css.includes('.workshop-plan-chip.is-overtime') && css.includes('animation: workshop-overtime-flash'), 'overdue chips flash red');
console.log('Started indefinite-duration and overtime chip contract passed.');
