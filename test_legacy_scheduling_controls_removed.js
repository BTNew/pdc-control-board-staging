'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const app = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8');
const planner = fs.readFileSync(path.join(__dirname, 'workshop-planner.js'), 'utf8');
const checklistStart = app.indexOf('function incomingWorkChecklistHtml');
const checklistEnd = app.indexOf('function workStatusLegendHtml', checklistStart);
const checklist = app.slice(checklistStart, checklistEnd);
assert(checklistStart >= 0 && checklistEnd > checklistStart, 'Vehicle Locations work-status renderer must exist');
assert(!checklist.includes('<select'), 'Vehicle Locations work-status strip must be status-only');
assert(!app.includes('data-pmb-work-transfer-key'), 'Legacy department scheduling dropdowns must be removed');
assert(!app.includes('bindPmbWorkTransferSelects'), 'Legacy department scheduling listeners must be removed');
assert(planner.includes('data-workshop-schedule-vehicle'), 'Workshop Planner must remain the scheduling authority');
assert(planner.includes('scheduleWorkshopVehicle'), 'Workshop Planner scheduling path must remain available');
console.log('Legacy scheduling controls removal: PASS');
