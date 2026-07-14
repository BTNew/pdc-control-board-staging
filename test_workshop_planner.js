'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const planner = require('./workshop-planner.js');

const root = __dirname;
const app = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const source = fs.readFileSync(path.join(root, 'workshop-planner.js'), 'utf8');
const css = fs.readFileSync(path.join(root, 'workshop-planner.css'), 'utf8');
const htmlFiles = ['index.html', 'no-vehicles.html', 'test-50.html', 'test-75.html', 'test-100.html'];

assert.strictEqual(planner.WORKSHOP_START_HOUR, 8, 'Workshop must start at 8:00am');
assert.strictEqual(planner.WORKSHOP_END_HOUR, 16, 'Workshop must finish at 4:00pm');
assert.strictEqual(planner.WORKSHOP_DAY_MINUTES, 480, 'Workshop day should contain eight hours');
assert.deepStrictEqual(planner.WORKSHOP_STAGE_SEQUENCE, ['BUS_4X4', 'TINT', 'HOIST', 'FITTING', 'FABRICATION', 'ELECTRICAL', 'TYRE', 'PIT_INSPECTION'], 'Planner must include every current physical workshop station in order');

const friday = new Date(2026, 6, 17, 8, 0, 0, 0);
const monday = planner.workshopShiftWorkday(friday, 1);
assert.strictEqual(monday.getDay(), 1, 'Next after Friday must be Monday');
assert.strictEqual(monday.getDate(), 20, 'Friday navigation should skip the weekend');
const previousFriday = planner.workshopShiftWorkday(monday, -1);
assert.strictEqual(previousFriday.getDay(), 5, 'Previous before Monday must be Friday');
assert.strictEqual(previousFriday.getDate(), 17, 'Monday navigation should skip the weekend');

assert.strictEqual(planner.workshopSnapMinutes(22), 15, 'Times should snap to 15-minute intervals');
assert.strictEqual(planner.workshopSnapMinutes(23), 30, 'Times should snap to the nearest 15 minutes');
assert.strictEqual(planner.workshopClampStartMinutes(500), 465, 'Latest start must be 3:45pm');
assert.strictEqual(planner.workshopClampDurationHours(2, 420), 1, 'A job must not run beyond 4:00pm');
assert.ok(planner.workshopIntervalsOverlap(60, 120, 90, 150), 'Overlapping bay slots should be detected');
assert.ok(!planner.workshopIntervalsOverlap(60, 120, 120, 180), 'Back-to-back bay slots should be allowed');

const plannerStorage = new Map();
const auditEvents = [];
global.loadJson = (key, fallback) => plannerStorage.has(key) ? JSON.parse(plannerStorage.get(key)) : fallback;
global.saveJson = (key, value) => plannerStorage.set(key, JSON.stringify(value));
global.app = { data: [{ stock: '12666620' }] };
global.normalizePmbStage = value => String(value || '').toUpperCase();
global.selectedVehicle = key => key === '12666620' ? global.app.data[0] : null;
global.parseIsoTimestamp = value => { const date = new Date(value); return Number.isNaN(date.getTime()) ? null : date; };
global.cleanNavisionText = value => String(value || '').trim();
global.nowIsoString = () => '2026-07-14T00:00:00.000Z';
global.pmbStageLabel = stage => stage;
global.pmbBayHours = () => '';
global.pmbBayMechanic = () => '';
global.vehicleKey = vehicle => vehicle.stock;
global.displayStockNumber = vehicle => vehicle?.stock || '';
global.recordVehicleAudit = (_vehicle, action, details) => auditEvents.push({ action, details });
global.document = { querySelector: () => null };
global.window = { alert() {} };
planner.scheduleWorkshopVehicle({ vehicleKeyValue: '12666620', stage: 'FABRICATION', bay: 2, dateKey: '2026-07-14', startMinutes: 120 });
const storedPlans = planner.workshopLoadPlans();
assert.strictEqual(storedPlans.length, 1, 'Scheduling must persist one future plan');
assert.strictEqual(storedPlans[0].bay, 2, 'Scheduling must preserve the selected physical bay');
assert.strictEqual(storedPlans[0].hours, 1, 'A new plan should default to one hour');
assert.strictEqual(auditEvents[0]?.action, 'Workshop plan created', 'Scheduling must append an audit event');

assert.ok(app.includes("case 'workshop':"), 'Main renderer is missing the Workshop Planner view');
assert.ok(app.includes("workshop: 'Workshop Planner'"), 'Workshop Planner page title is missing');
assert.ok(app.includes('const PMB_SCHEDULE_WORK_START_HOUR = 8;'), 'Legacy PMB schedule start should match the workshop day');
assert.ok(app.includes('const PMB_SCHEDULE_WORK_END_HOUR = 16;'), 'Legacy PMB schedule finish should match the workshop day');

assert.ok(source.includes("vehicleTrackingCoreWorkshopPlan:v1"), 'Planner persistence key is missing');
assert.ok(source.includes('CRM_BACKUP_STORAGE_KEYS.push(WORKSHOP_PLAN_STORAGE_KEY)'), 'Planner data must be included in CRM backups');
assert.ok(source.includes('function workshopHasConflict('), 'Bay collision protection is missing');
assert.ok(source.includes('function startWorkshopPlan('), 'Physical bay start action is missing');
assert.ok(source.includes('function completeWorkshopPlan('), 'Workshop completion action is missing');
assert.ok(source.includes('data-workshop-resize-plan'), 'Duration resize control is missing');
assert.ok(source.includes("selectedVehicle(cleanKey)"), 'Workshop lookup must use the fail-closed vehicle resolver');
assert.ok(source.includes("'Workshop plan created'"), 'Workshop plan creation must be audited');
assert.ok(!/\b(?:fetch|XMLHttpRequest|WebSocket|EventSource)\b/.test(source), 'Workshop planner must not add network calls');

for (const selector of ['.workshop-board-shell', '.workshop-bay-lane', '.workshop-plan-chip', '.workshop-now-line']) {
  assert.ok(css.includes(selector), `Workshop CSS is missing ${selector}`);
}

for (const file of htmlFiles) {
  const html = fs.readFileSync(path.join(root, file), 'utf8');
  assert.ok(html.includes('data-view="workshop"'), `${file} is missing the Workshop Planner navigation item`);
  assert.ok(html.includes('id="workshop-planner-root"'), `${file} is missing the Workshop Planner host`);
  assert.ok(html.includes('workshop-planner.css?v=2026.07.14.10-workshop-planner-stage2'), `${file} is missing the planner stylesheet`);
  assert.ok(html.includes('workshop-planner.js?v=2026.07.14.10-workshop-planner-stage2'), `${file} is missing the planner script`);
}

console.log('Workshop planner regression checks passed');
