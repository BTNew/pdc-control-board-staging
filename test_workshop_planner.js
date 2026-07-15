'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const planner = require('./workshop-planner.js');

const root = __dirname;
const app = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const source = fs.readFileSync(path.join(root, 'workshop-planner.js'), 'utf8');
const css = fs.readFileSync(path.join(root, 'workshop-planner.css'), 'utf8');
const globalCss = fs.readFileSync(path.join(root, 'styles.css'), 'utf8');
const htmlFiles = ['index.html', 'no-vehicles.html', 'test-50.html', 'test-75.html', 'test-100.html'];

assert.strictEqual(planner.WORKSHOP_START_HOUR, 8, 'Workshop must start at 8:00am');
assert.strictEqual(planner.WORKSHOP_END_HOUR, 16, 'Workshop must finish at 4:00pm');
assert.strictEqual(planner.WORKSHOP_DAY_MINUTES, 480, 'Workshop day should contain eight hours');
assert.strictEqual(planner.WORKSHOP_DEFAULT_HOURS, 3, 'New planner bookings should default to three hours');
assert.deepStrictEqual(
  planner.WORKSHOP_STAGE_SEQUENCE,
  ['BUS_4X4', 'TINT', 'HOIST', 'FITTING', 'FABRICATION', 'ELECTRICAL', 'TYRE', 'PIT_INSPECTION', 'SUBLET'],
  'The physical station order must be preserved while Sublet remains a provider row',
);

const friday = new Date(2026, 6, 17, 8, 0, 0, 0);
const monday = planner.workshopShiftWorkday(friday, 1);
assert.strictEqual(monday.getDay(), 1, 'Next after Friday must be Monday');
assert.strictEqual(monday.getDate(), 20, 'Friday navigation should skip the weekend');
const previousFriday = planner.workshopShiftWorkday(monday, -1);
assert.strictEqual(previousFriday.getDay(), 5, 'Previous before Monday must be Friday');
assert.strictEqual(previousFriday.getDate(), 17, 'Monday navigation should skip the weekend');
const weekStart = planner.workshopWeekStart(new Date(2026, 6, 16, 13, 0));
assert.strictEqual(weekStart.getDay(), 1, 'Weekly view must begin on Monday');
assert.deepStrictEqual(planner.workshopWeekDates(weekStart).map(date => date.getDay()), [1, 2, 3, 4, 5], 'Weekly view must contain Monday to Friday only');

assert.strictEqual(planner.workshopSnapMinutes(22), 15, 'Times should snap to 15-minute intervals');
assert.strictEqual(planner.workshopSnapMinutes(23), 30, 'Times should snap to the nearest 15 minutes');
assert.strictEqual(planner.workshopClampStartMinutes(500), 465, 'Latest start must be 3:45pm');
assert.strictEqual(planner.workshopClampLineHours(0.5), 0.5, 'Imported job lines may retain sub-three-hour estimates');
assert.strictEqual(planner.workshopClampDurationHours(0.5), 0.5, 'A reviewed category booking must retain its confirmed labour hours');
assert.strictEqual(planner.workshopClampDurationHours(20), 20, 'Workshop jobs must not have a maximum-hour limit');
const longJobEnd = planner.workshopAddWorkMinutes(new Date(2026, 6, 17, 14, 0, 0, 0), 12 * 60);
assert.strictEqual(longJobEnd.getDay(), 2, 'A 12-hour Friday job should carry through Monday into Tuesday');
assert.strictEqual(longJobEnd.getDate(), 21, 'A 12-hour Friday job should finish on Tuesday 21 July');
assert.strictEqual(longJobEnd.getHours(), 10, 'Carried work should finish at 10:00am Tuesday');
assert.ok(planner.workshopIntervalsOverlap(60, 120, 90, 150), 'Overlapping bay slots should be detected');
assert.ok(!planner.workshopIntervalsOverlap(60, 120, 120, 180), 'Back-to-back bay slots should be allowed');

global.parseIsoTimestamp = value => {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
};
global.nowIsoString = () => new Date(2026, 6, 14, 10, 0, 0, 0).toISOString();
global.vehicleKey = vehicle => vehicle.id;
global.pmbBayNumber = vehicle => vehicle.bay || '';
global.cleanNavisionText = value => String(value || '').trim();
global.app = { data: [{ id: 'active', bay: 1 }, { id: 'next', bay: '' }] };
global.selectedVehicle = key => {
  const matches = global.app.data.filter(vehicle => vehicle.id === key);
  return matches.length === 1 ? matches[0] : null;
};
const activeStart = new Date(2026, 6, 14, 8, 0, 0, 0);
const nextStart = new Date(2026, 6, 14, 9, 30, 0, 0);
const collisionRows = [
  { id: 'FABRICATION::active', vehicleKey: 'active', stage: 'FABRICATION', bay: 1, startAt: activeStart.toISOString(), hours: 3, status: 'started' },
  { id: 'FABRICATION::next', vehicleKey: 'next', stage: 'FABRICATION', bay: 1, startAt: nextStart.toISOString(), hours: 3, status: 'planned' },
];
assert.strictEqual(planner.workshopHasConflict(collisionRows[1], collisionRows), collisionRows[0], 'An overlapping booking in the same bay must be detected');
const unchanged = planner.workshopCascadePlans(collisionRows, new Date(2026, 6, 14, 12, 0, 0, 0));
assert.ok(!unchanged.changed, 'Hard-block policy must not silently cascade existing bookings');
assert.strictEqual(unchanged.rows.find(row => row.vehicleKey === 'next').startAt, nextStart.toISOString(), 'A conflicting booking must never be moved automatically');
assert.strictEqual(unchanged.rows.find(row => row.vehicleKey === 'next').hours, 3, 'Collision handling must retain the three-hour minimum estimate');
const backToBack = { id: 'FABRICATION::back-to-back', vehicleKey: 'next', stage: 'FABRICATION', bay: 1, startAt: new Date(2026, 6, 14, 11, 0).toISOString(), hours: 3, status: 'planned' };
assert.strictEqual(planner.workshopHasConflict(backToBack, [{ ...collisionRows[0], status: 'planned' }]), null, 'Back-to-back same-bay bookings must remain allowed');

global.selectedVehicle = key => ({ id: key });
global.pmbBayNumber = () => 1;
const overtimeNow = new Date(2026, 6, 14, 12, 0);
const overtimeLiveRow = {
  id: 'FABRICATION::overtime',
  vehicleKey: 'overtime',
  stage: 'FABRICATION',
  bay: 1,
  startAt: new Date(2026, 6, 14, 8, 0).toISOString(),
  hours: 3,
  status: 'started',
};
const overtimeCandidate = {
  id: 'FABRICATION::after-overtime',
  vehicleKey: 'after-overtime',
  stage: 'FABRICATION',
  bay: 1,
  startAt: new Date(2026, 6, 14, 11, 0).toISOString(),
  hours: 3,
  status: 'planned',
};
assert.strictEqual(
  planner.workshopHasConflict(overtimeCandidate, [overtimeLiveRow], overtimeNow),
  overtimeLiveRow,
  'An overtime live job must keep its physical bay blocked beyond its planned end',
);
const mechanicClashRows = [
  { id: 'FABRICATION::one', vehicleKey: 'one', stage: 'FABRICATION', bay: 1, startAt: new Date(2026, 6, 14, 8, 0).toISOString(), hours: 2, status: 'planned', assignee: 'Alex' },
  { id: 'FABRICATION::two', vehicleKey: 'two', stage: 'FABRICATION', bay: 2, startAt: new Date(2026, 6, 14, 9, 0).toISOString(), hours: 1, status: 'planned', assignee: 'Alex' },
];
assert.ok(planner.workshopEntryHasAssigneeConflict(mechanicClashRows[0], mechanicClashRows), 'A mechanic double-booked across bays should be flagged');
const sameBayCascadeRows = mechanicClashRows.map(row => ({ ...row, stage: 'FABRICATION', bay: 1 }));
assert.ok(!planner.workshopEntryHasAssigneeConflict(sameBayCascadeRows[0], sameBayCascadeRows), 'Same-bay work should rely on the bay collision rule instead of a duplicate mechanic warning');

global.displayStockNumber = vehicle => vehicle.id || '';
global.vehicleJobcardNumber = vehicle => vehicle.jobcard || '';
global.pmbStageLabel = stage => stage === 'FABRICATION' ? 'Fab' : stage;
const conflictAlerts = [];
global.window = { alert: message => conflictAlerts.push(String(message)) };
global.window.PDC_AUTH_CONTEXT = { displayName: 'Craig Watson', email: 'craig.watson@broometoyota.com.au', role: 'administrator' };
assert.deepStrictEqual(
  planner.workshopRequireOperatorProfile(),
  { name: 'Craig Watson', role: 'administrator' },
  'Authenticated users must be able to move planner vehicles without a separate local operator profile',
);
const nextThursday = planner.workshopNextWorkdayDate(new Date(2026, 6, 15, 10, 0));
assert.strictEqual(planner.workshopDateKey(nextThursday), '2026-07-16', 'Next-day warnings should use the following workday');
const nextMonday = planner.workshopNextWorkdayDate(new Date(2026, 6, 17, 10, 0));
assert.strictEqual(planner.workshopDateKey(nextMonday), '2026-07-20', 'Next-day warnings should skip weekends');
const warningVehicles = {
  'parts-open': { id: 'parts-open', jobcard: 'JC-100', stock: 'S-100', client: 'Customer A', vehicle: 'Hilux', partsStatus: 'notordered' },
  'parts-confirmed': { id: 'parts-confirmed', jobcard: 'JC-200', stock: 'S-200', partsStatus: 'issued' },
  'parts-on-order': { id: 'parts-on-order', jobcard: 'JC-250', stock: 'S-250', partsStatus: 'onorder' },
  'invalid-bay': { id: 'invalid-bay', jobcard: 'JC-275', stock: 'S-275', partsStatus: 'notordered' },
  'wrong-stage': { id: 'wrong-stage', jobcard: 'JC-300', stock: 'S-300', partsStatus: 'notordered' },
};
global.normalizePmbStage = value => String(value || '').toUpperCase();
global.pmbStageBayCount = stage => global.normalizePmbStage(stage) === 'FITTING' ? 5 : 13;
global.partsDepartmentStatus = vehicle => vehicle.partsStatus;
global.partsDepartmentStatusLabel = status => ({ onorder: 'On Order', issued: 'Issued', notordered: 'Not Ordered' }[status] || status);
global.partsWorstEtaLabel = () => '';
global.vehicleCustomerName = vehicle => vehicle.client || '';
global.selectedVehicle = key => warningVehicles[key] || null;
const firstLaterSlot = planner.workshopFirstAvailableStartMinutes('FITTING', 1, '2026-07-16', 3, [
  { id: 'FITTING::occupied', vehicleKey: 'occupied', stage: 'FITTING', bay: 1, startAt: new Date(2026, 6, 16, 8, 0).toISOString(), hours: 3, status: 'planned' },
]);
assert.strictEqual(firstLaterSlot, 180, 'The direct scheduler should suggest 11:00am after an 8:00am–11:00am booking in the same bay');
const nextDayRows = [
  { id: 'FITTING::parts-open', vehicleKey: 'parts-open', stage: 'FITTING', bay: 1, startAt: new Date(2026, 6, 16, 8, 0).toISOString(), hours: 3, status: 'planned' },
  { id: 'FITTING::parts-confirmed', vehicleKey: 'parts-confirmed', stage: 'FITTING', bay: 2, startAt: new Date(2026, 6, 16, 9, 0).toISOString(), hours: 3, status: 'planned' },
  { id: 'FITTING::parts-on-order', vehicleKey: 'parts-on-order', stage: 'FITTING', bay: 1, startAt: new Date(2026, 6, 16, 10, 0).toISOString(), hours: 3, status: 'planned' },
  { id: 'FITTING::invalid-bay', vehicleKey: 'invalid-bay', stage: 'FITTING', bay: 99, startAt: new Date(2026, 6, 16, 8, 0).toISOString(), hours: 3, status: 'planned' },
  { id: 'HOIST::wrong-stage', vehicleKey: 'wrong-stage', stage: 'HOIST', bay: 1, startAt: new Date(2026, 6, 16, 8, 0).toISOString(), hours: 3, status: 'planned' },
];
const warningResult = planner.workshopNextDayFittingPartsWarnings(new Date(2026, 6, 15, 10, 0), nextDayRows);
assert.deepStrictEqual(warningResult.warnings.map(item => item.entry.vehicleKey), ['parts-open'], 'Only next-day Fitting bookings without confirmed parts should be warned');
assert.match(planner.workshopNextDayFittingWarningEmailBody(warningResult), /JC JC-100 · Stock parts-open/, 'The warning email must identify the affected fitting vehicle');
assert.match(planner.workshopNextDayFittingWarningEmailBody(warningResult), /Affected vehicles: 1/, 'The warning email must include the affected count');
assert.ok(!planner.workshopNextDayFittingWarningEmailBody(warningResult).includes('S-250'), 'Parts already On Order must count as confirmed');
global.selectedVehicle = key => ({ id: key });
assert.strictEqual(
  planner.workshopRequireNoBayConflict(collisionRows[1], collisionRows),
  false,
  'The same-bay hard-block helper must reject an overlapping booking',
);
assert.match(
  conflictAlerts.at(-1) || '',
  /Fab Bay 1 already has active booked during that time\. Overlapping workshop bookings are blocked; choose another bay or time\./,
  'The operator must receive a clear bay, vehicle and resolution message',
);

assert.ok(app.includes("case 'workshop':"), 'Main renderer is missing the Workshop Planner view');
assert.ok(app.includes("workshop: 'Workshop Planner'"), 'Workshop Planner page title is missing');
assert.ok(app.includes('const PMB_SCHEDULE_WORK_START_HOUR = 8;'), 'Legacy PMB schedule start should match the workshop day');
assert.ok(app.includes('const PMB_SCHEDULE_WORK_END_HOUR = 16;'), 'Legacy PMB schedule finish should match the workshop day');
assert.ok(app.includes("{ value: 'BUS_4X4', label: 'Bus 4x4' }"), 'Bus 4x4 location option is missing');
assert.ok(app.includes("['BUS_4X4', 'TINT', 'HOIST', 'FITTING', 'FABRICATION'"), 'Bus 4x4 must remain the first physical PMB station');

assert.ok(source.includes("vehicleTrackingCoreWorkshopPlan:v1"), 'Planner persistence key is missing');
assert.ok(source.includes('CRM_BACKUP_STORAGE_KEYS.push(WORKSHOP_PLAN_STORAGE_KEY)'), 'Planner data must be included in CRM backups');
assert.ok(source.includes('CRM_BACKUP_STORAGE_KEYS.push(WORKSHOP_BAY_SETUP_STORAGE_KEY)'), 'Bay mechanic setup must be included in CRM backups');
assert.ok(source.includes('function workshopHasConflict('), 'Bay collision protection is missing');
assert.ok(source.includes("typeof selectedVehicle === 'function' ? selectedVehicle(cleanKey) : null"), 'Planner vehicle lookup must use the fail-closed shared resolver');
assert.ok(source.includes('requiredAndIncomplete'), 'Future required work must remain schedulable before the vehicle reaches that station');
assert.ok(source.includes("typeof pmbVehiclesNeedingStationWork === 'function'"), 'Planner awaiting lists must share the Control Board station-work eligibility');
assert.ok(source.includes("const requestedStage = normalizePmbStage(app.pendingWorkshopStage || '')"), 'Open Bays must be able to open the requested Workshop Planner station');
assert.ok(app.includes('function openWorkshopPlannerForStage('), 'Control Board Open Bays navigation helper is missing');
assert.ok(source.includes('function workshopPersistPlanAction('), 'Planner mutations must use transactional persistence and audit logging');
assert.ok(source.includes("window.addEventListener('storage'"), 'Planner must reload changes saved in another browser tab');
assert.ok(source.includes('function workshopRequireNoBayConflict('), 'Hard-block bay collision protection is missing');
assert.ok(source.includes('Overlapping workshop bookings are blocked'), 'Collision rejection must explain that overlapping bookings are blocked');
assert.ok(source.includes('function workshopEntryIsOvertime('), 'Overtime detection is missing');
assert.ok(source.includes('actualHours:'), 'Actual workshop time recording is missing');
assert.ok(source.includes('function startWorkshopPlan('), 'Physical bay start action is missing');
assert.ok(source.includes('function completeWorkshopPlan('), 'Workshop completion action is missing');
assert.ok(source.includes('function stopWorkshopPlan('), 'Workshop stoppage action is missing');
assert.ok(source.includes('function openWorkshopVehicleJob('), 'Double-click vehicle job editor is missing');
assert.ok(source.includes('function openWorkshopWeeklyView('), 'Per-bay weekly schedule is missing');
assert.ok(source.includes('data-workshop-weekly-stage'), 'Per-bay Week button is missing');
assert.ok(source.includes('function workshopRevealSearchMatch('), 'Planner search reveal is missing');
assert.ok(source.includes('workshopJobLineAssignments'), 'Imported job-line work-area allocation is missing');
assert.ok(source.includes('workshopAdditionalHoursByStage'), 'Manual per-area additional hours are missing');
assert.ok(source.includes('function workshopReturnChoiceModal('), 'Live-job return choice is missing');
assert.ok(source.includes('function workshopStoppageReasonModal('), 'In-app stoppage reason capture is missing');
assert.ok(source.includes('function workshopRequireOperatorProfile('), 'Planner mutations must require an authenticated or saved operator profile before transactions begin');
assert.ok(source.includes('window.PDC_AUTH_CONTEXT?.displayName'), 'Authenticated staff identity must satisfy planner audit gating');
assert.ok(!source.includes('data-workshop-manage-mechanics'), 'Manage Mechanics must be removed from the Workshop Planner header');
assert.ok(source.includes('data-workshop-weekly-view'), 'The Workshop Planner header is missing the Weekly view button');
assert.ok(source.includes('data-workshop-parts-warning'), 'The next-day fitting parts warning button is missing');
const nextButtonIndex = source.indexOf('data-workshop-date-shift="1"');
const todayButtonIndex = source.indexOf('data-workshop-today');
assert.ok(nextButtonIndex >= 0 && todayButtonIndex > nextButtonIndex, 'Today must appear to the right of Next in the planner controls');
assert.ok(!source.includes('window.prompt('), 'Workshop actions must not use browser prompt dialogs');
assert.ok(source.includes('value="move" checked'), 'Just move return option is missing');
assert.ok(source.includes('value="stoppage"'), 'Stoppage return option is missing');
assert.ok(source.includes('Parts completion remains an RFT gate, not an entry gate for Tint, Tyre or Sublet.'), 'Parts should remain an RFT gate without blocking workshop entry');
assert.ok(!source.includes('function removeWorkshopPlan('), 'Direct Remove Plan action must not exist');
assert.ok(!source.includes('max="8"'), 'Workshop hours must not be capped at eight');
assert.ok(!source.includes('Scheduled other days'), 'The Scheduled other days box should be removed');
assert.ok(!source.includes('A started, stopped or completed job cannot be removed from the planner'), 'Live jobs should be returnable through the protected choice flow');
assert.ok(source.includes('data-workshop-resize-plan'), 'Duration resize control is missing');
assert.ok(source.includes('data-workshop-schedule-vehicle'), 'Awaiting vehicles need a direct Schedule button as a reliable alternative to drag/drop');
assert.ok(source.includes('data-workshop-schedule-form'), 'The direct booking modal is missing');
assert.ok(source.includes('data-workshop-extend-plan'), 'Quick +15m/+30m/+1h controls are missing');
assert.ok(source.includes('name="hours" type="number" min="0.25"'), 'Reviewed sub-three-hour bookings must remain valid and extendable');
assert.ok(source.includes('Back-to-back bookings are allowed; overlapping times are blocked.'), 'The scheduling modal must explain later same-bay booking behavior');

const workshopFunctionSection = (startName, nextName) => {
  const start = source.indexOf(`function ${startName}`);
  const end = source.indexOf(`function ${nextName}`, start + 1);
  assert.ok(start >= 0 && end > start, `Could not isolate ${startName} for collision-path verification`);
  return source.slice(start, end);
};
for (const [startName, nextName, pathLabel] of [
  ['scheduleWorkshopVehicle', 'saveWorkshopDetailForm', 'daily drag/drop'],
  ['saveWorkshopDetailForm', 'startWorkshopPlan', 'detail edit'],
  ['startWorkshopPlan', 'completeWorkshopPlan', 'start work'],
  ['startWorkshopResize', 'workshopWeeklyCardHtml', 'duration resize'],
  ['moveWorkshopWeeklyPlan', 'openWorkshopWeeklyView', 'weekly move'],
  ['openWorkshopVehicleJob', 'setupWorkshopPlannerClock', 'job-allocation duration'],
]) {
  const section = workshopFunctionSection(startName, nextName);
  assert.ok(section.includes('workshopRequireNoBayConflict('), `${pathLabel} must hard-block same-bay overlaps before persistence`);
  assert.ok(section.includes('workshopRequireAvailableAssignee('), `${pathLabel} must reject overlapping mechanic assignments across bays`);
}
for (const [startName, nextName, pathLabel] of [
  ['saveWorkshopDetailForm', 'startWorkshopPlan', 'detail edit'],
  ['startWorkshopResize', 'workshopWeeklyCardHtml', 'duration resize'],
]) {
  const section = workshopFunctionSection(startName, nextName);
  assert.ok(section.includes('workshopPersistVehiclePlanAction('), `${pathLabel} must commit planner, vehicle estimate and audit atomically`);
  assert.ok(section.includes('if (!persisted)'), `${pathLabel} must stop when operator gating or transactional persistence fails`);
  assert.ok(!section.includes('saveVehicleEdits('), `${pathLabel} must not write vehicle estimates outside the shared transaction`);
}

for (const selector of ['.workshop-board-shell', '.workshop-bay-lane', '.workshop-plan-chip', '.workshop-now-line', '.workshop-plan-chip.is-overtime', '.workshop-plan-chip.has-assignee-conflict', '.workshop-plan-chip.is-search-match', '.workshop-unallocated-drop', '.workshop-week-grid', '.workshop-week-card', '.workshop-return-card', '.workshop-job-line-row']) {
  assert.ok(css.includes(selector), `Workshop CSS is missing ${selector}`);
}
assert.ok(globalCss.includes('.pmb-card-move-button {'), 'PMB movement buttons must have a visible default style');

for (const file of htmlFiles) {
  const html = fs.readFileSync(path.join(root, file), 'utf8');
  assert.ok(html.includes('data-view="workshop"'), `${file} is missing the Workshop Planner navigation item`);
  assert.ok(html.includes('id="workshop-planner-root"'), `${file} is missing the Workshop Planner host`);
  assert.ok(html.includes('workshop-planner.css?v=2026.07.15.10-parts-current-location'), `${file} is missing the planner stylesheet`);
  assert.ok(!html.includes('<script src="workshop-planner.js'), `${file} must not eagerly load the planner script`);
}
assert.ok(app.includes("loadExternalScript(`workshop-planner.js?v=${encodeURIComponent(APP_VERSION)}`"), 'app.js must lazy-load the Workshop Planner with the active release version');

console.log('Workshop planner regression checks passed');
