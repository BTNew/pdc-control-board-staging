'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const planner = require('./workshop-planner.js');

const incrementalRows = Array.from({ length: 105 }, (_, index) => ({ id: index + 1 }));
const firstBatch = planner.workshopIncrementalRenderRows(incrementalRows);
assert.strictEqual(firstBatch.visible.length, 12, 'Planner must incrementally render only the first 12 waiting/completed rows');
assert.strictEqual(firstBatch.remaining, 93, 'Planner must report remaining rows without losing data');
const thirdBatch = planner.workshopIncrementalRenderRows(incrementalRows, 120);
assert.strictEqual(thirdBatch.visible.length, 105, 'Incremental expansion must eventually expose every row');
assert.strictEqual(thirdBatch.remaining, 0, 'Expanded rendering must retain no hidden remainder');

const root = __dirname;
const app = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const source = fs.readFileSync(path.join(root, 'workshop-planner.js'), 'utf8');
const css = fs.readFileSync(path.join(root, 'workshop-planner.css'), 'utf8');
const globalCss = fs.readFileSync(path.join(root, 'styles.css'), 'utf8');
const htmlFiles = ['index.html', 'no-vehicles.html', 'test-50.html', 'test-75.html', 'test-100.html'];
const workshopPlannerNavViews = ['planner-bus-4x4', 'planner-tint', 'planner-hoist', 'planner-fitting', 'planner-fab', 'planner-elec', 'planner-tyre'];
const appVersion = (app.match(/const APP_VERSION = '([^']+)'/) || [])[1];
assert.ok(appVersion, 'app.js must define APP_VERSION');

assert.strictEqual(planner.WORKSHOP_CONFIG.dayStartMinutes, 480, 'Workshop boot config must start at integer minute 480');
assert.strictEqual(planner.WORKSHOP_CONFIG.dayEndMinutes, 960, 'Workshop boot config must finish at integer minute 960');
assert.strictEqual(planner.WORKSHOP_CONFIG.dayLengthMinutes, 480, 'Workshop day should contain 480 integer minutes');
assert.strictEqual(planner.WORKSHOP_CONFIG.defaultBookingDurationMinutes, 180, 'New planner bookings should default to 180 integer minutes');
assert.deepStrictEqual(
  planner.WORKSHOP_STAGE_SEQUENCE,
  ['BUS_4X4', 'TINT', 'HOIST', 'FITTING', 'FABRICATION', 'ELECTRICAL', 'TYRE'],
  'Only the seven schedulable Workshop bay stations must be preserved; Pit and Sublet have no Planner',
);
assert.ok(source.includes('const WORKSHOP_VISIBLE_STAGE_SEQUENCE = WORKSHOP_STAGE_SEQUENCE;'), 'Workshop planner tabs must use the canonical planner-enabled station set');
assert.ok(source.includes("const stageTabs = dedicatedStage ? '' : WORKSHOP_VISIBLE_STAGE_SEQUENCE.map("), 'Combined planner should retain physical station tabs while dedicated planners render no unrelated tabs');
assert.ok(source.includes("new Set(['moveBooking', 'cascadeMoveBooking', 'scheduleVehicleWork', 'cascadeSchedule'])"), 'Cross-bay planned moves must retain the standard future-Parts planning-only retry');

const friday = new Date(2026, 6, 17, 8, 0, 0, 0);
const monday = planner.workshopShiftWorkday(friday, 1);
assert.strictEqual(monday.getDay(), 1, 'Next after Friday must be Monday');
assert.strictEqual(monday.getDate(), 20, 'Friday navigation should skip the weekend');
const previousFriday = planner.workshopShiftWorkday(monday, -1);
assert.strictEqual(previousFriday.getDay(), 5, 'Previous before Monday must be Friday');
assert.strictEqual(previousFriday.getDate(), 17, 'Monday navigation should skip the weekend');
assert.strictEqual(planner.workshopDefaultOpenDateKey(new Date(2026, 6, 20, 14, 0)), '2026-07-20', 'Opening a planner station on a workday must default to today');
assert.strictEqual(planner.workshopDefaultOpenDateKey(new Date(2026, 6, 18, 14, 0)), '2026-07-20', 'Opening a planner station on a weekend must use the next operational day');
const weekStart = planner.workshopWeekStart(new Date(2026, 6, 16, 13, 0));
assert.strictEqual(weekStart.getDay(), 1, 'Weekly view must begin on Monday');
assert.deepStrictEqual(planner.workshopWeekDates(weekStart).map(date => date.getDay()), [1, 2, 3, 4, 5], 'Weekly view must contain Monday to Friday only');

assert.strictEqual(planner.workshopSnapMinutes(22), 15, 'Times should snap to 15-minute intervals');
assert.strictEqual(planner.workshopSnapMinutes(23), 30, 'Times should snap to the nearest 15 minutes');
assert.strictEqual(planner.workshopClampStartMinutes(500), 465, 'Latest start must be 3:45pm');
assert.strictEqual(planner.workshopClampLineHours(0.5), 0.5, 'Imported job lines may retain sub-three-hour estimates');
assert.strictEqual(planner.workshopClampDurationHours(0.5), 1, 'Planner bookings must enforce the approved one-hour minimum');
assert.strictEqual(planner.workshopClampDurationHours(20), 20, 'Workshop jobs must not have a maximum-hour limit');
assert.deepStrictEqual(planner.workshopManualDurationAllocation(25, 0), { total: 25, additional: 25 }, 'A manually entered 25-hour estimate must be saved as the bay total when there are no imported lines');
assert.deepStrictEqual(planner.workshopManualDurationAllocation(25, 3), { total: 25, additional: 22 }, 'A manual total must subtract imported hours rather than add 25 hours on top');
assert.strictEqual(planner.workshopManualDurationAllocation(2, 3), null, 'A manual total below allocated imported hours must fail closed');
const sharedDurationPayload = planner.workshopManualDurationSharedPayload({ id: 'local-id', sharedBookingId: 'booking-id', sharedVersion: 7, stage: 'TINT', bay: 2, startAt: '2026-07-24T01:00:00.000Z', hours: 3 }, 25);
assert.strictEqual(sharedDurationPayload.targetId, 'booking-id', 'Shared manual-time changes must target the authoritative booking id');
assert.strictEqual(sharedDurationPayload.targetExpectedVersion, 7, 'Shared manual-time changes must preserve optimistic concurrency');
assert.strictEqual(sharedDurationPayload.durationMinutes, 1500, 'A 25-hour estimate must be sent as 1500 minutes');
assert.strictEqual(sharedDurationPayload.shiftMinutes, 1320, 'Extending 3 hours to 25 must cascade later queued work by 22 hours');
assert.deepStrictEqual(sharedDurationPayload.metadata, { source: 'manual_estimated_time' });
assert.match(source, /name="estimated_hours" min="1" step="0\.25"/, 'The job modal must expose an editable total estimated-hours field');
assert.match(source, /data-workshop-estimated-hours-total/, 'The visible planned-time total must update with manual input');
assert.match(source, /metadata: \{ source: 'manual_estimated_time' \}/, 'Shared manual-time edits must use the authoritative booking cascade action');
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
const cascaded = planner.workshopCascadePlans(collisionRows, new Date(2026, 6, 14, 12, 0, 0, 0));
assert.ok(cascaded.changed, 'A later planned booking must cascade after earlier work overruns');
assert.strictEqual(cascaded.rows.find(row => row.vehicleKey === 'next').startAt, new Date(2026, 6, 14, 10, 45).toISOString(), 'The later booking must move by the live overrun while preserving its queue position');
assert.strictEqual(cascaded.rows.find(row => row.vehicleKey === 'next').hours, 3, 'Cascade must preserve booking duration');
const backToBack = { id: 'FABRICATION::back-to-back', vehicleKey: 'next', stage: 'FABRICATION', bay: 1, startAt: new Date(2026, 6, 14, 11, 0).toISOString(), hours: 3, status: 'planned' };
assert.strictEqual(planner.workshopHasConflict(backToBack, [{ ...collisionRows[0], status: 'planned' }]), null, 'Back-to-back same-bay bookings must remain allowed');
const differentStageSameBay = { id: 'HOIST::same-bay-number', vehicleKey: 'same-bay-number', stage: 'HOIST', bay: 1, startAt: nextStart.toISOString(), hours: 3, status: 'planned' };
assert.strictEqual(planner.workshopHasConflict(differentStageSameBay, collisionRows), null, 'Bay numbers must be isolated by stage so Hoist Bay 1 does not collide with Fab Bay 1');

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
const queueDropBackToBackSlot = planner.workshopFirstAvailableStartSlot('TINT', 2, '2026-06-17', 3, [
  { id: 'TINT::12544489', vehicleKey: '12544489', stage: 'TINT', bay: 2, startAt: new Date(2026, 5, 17, 9, 30).toISOString(), hours: 3, status: 'planned' },
]);
assert.deepStrictEqual(queueDropBackToBackSlot, { dateKey: '2026-06-17', startMinutes: 270 }, 'A new queue card should start at 12:30pm directly after the existing 9:30am–12:30pm booking');
const nextWorkdaySequenceSlot = planner.workshopFirstAvailableStartSlot('TINT', 2, '2026-06-17', 3, [
  { id: 'TINT::full-day', vehicleKey: 'full-day', stage: 'TINT', bay: 2, startAt: new Date(2026, 5, 17, 8, 0).toISOString(), hours: 8, status: 'planned' },
]);
assert.deepStrictEqual(nextWorkdaySequenceSlot, { dateKey: '2026-06-18', startMinutes: 0 }, 'A full bay day should advance the next vehicle to 8:00am on the following workday');
const bestFabSlot = planner.workshopBestStageSlot('FABRICATION', '2026-07-16', 3, [
  { id: 'FABRICATION::bay-1', vehicleKey: 'bay-1', stage: 'FABRICATION', bay: 1, startAt: new Date(2026, 6, 16, 8, 0).toISOString(), hours: 3, status: 'planned' },
  { id: 'FABRICATION::bay-2', vehicleKey: 'bay-2', stage: 'FABRICATION', bay: 2, startAt: new Date(2026, 6, 16, 11, 0).toISOString(), hours: 3, status: 'planned' },
]);
assert.deepStrictEqual(bestFabSlot, { stage: 'FABRICATION', bay: 2, dateKey: '2026-07-16', startMinutes: 0 }, 'Best-slot suggestions should choose the earliest open bay across the stage, not only the current bay');
assert.match(planner.workshopSlotSummary('FABRICATION', 2, '2026-07-16', 0), /Fab · Bay 02 · Thu,? 16\/07,?.*8:00 am/i, 'Slot summaries should show the stage, bay and suggested work time clearly');
let horizonDate = new Date(2026, 5, 17, 8, 0, 0, 0);
const longHorizonRows = [];
for (let index = 0; index < 25; index += 1) {
  longHorizonRows.push({ id: `HOIST::full-day-${index}`, vehicleKey: `full-day-${index}`, stage: 'HOIST', bay: 1, startAt: horizonDate.toISOString(), hours: 8, status: 'planned' });
  horizonDate = planner.workshopNextWorkdayDate(horizonDate);
}
assert.deepStrictEqual(
  planner.workshopFirstAvailableStartSlot('HOIST', 1, '2026-06-17', 3, longHorizonRows),
  { dateKey: planner.workshopDateKey(horizonDate), startMinutes: 0 },
  'Automatic scheduling must search beyond one month so vehicles can be planned many months ahead',
);
assert.ok(source.includes("hoursValue: Number.isFinite(dragHours) && dragHours > 0 ? dragHours : null, preferRequestedTime: true"), 'Queue-card lane drops must preserve the Vehicle-detail estimate, requested drop time and cascade authority');
assert.ok(source.includes("moveWorkshopDroppedPlan(planId, stage, bay, dateKey, startMinutes, { preferRequestedTime: true })"), 'Dragged planned bookings must keep the requested drop time and route through queue shifting');
assert.ok(source.includes("preferRequestedTime && movingBetweenBays ? 'cascadeMoveBooking' : 'moveBooking'"), 'Shared booked-chip drops between bays must atomically push overlapping and later planned jobs');
assert.ok(source.includes("const previewMinutes = Number(lane.dataset.workshopRequestedStartMinutes);"), 'Daily lane drops must reuse the live preview time so drop coordinates stay exact');
assert.ok(source.includes("lane.dataset.workshopRequestedStartMinutes = String(safeMinutes);"), 'Lane previews must persist the last hovered planner time for reliable dropping');
assert.ok(source.includes('function workshopHideLanePreview(lane)'), 'Daily lane drags should hide the preview without losing the last hovered drop time');
assert.ok(source.includes('function workshopCurrentDropTarget()'), 'Planner drag/drop should keep a global last-hovered drop target for flaky browser drag event order');
assert.ok(source.includes('workshopSetDropTarget({ stage, bay, dateKey, startMinutes: safeMinutes });'), 'Lane preview updates must remember the full hovered stage/bay/date target');
assert.ok(source.includes('setTimeout(() => workshopClearLanePreviews(root), 0);'), 'Daily dragend should defer preview cleanup until the drop event has a chance to read the remembered target');
assert.ok(source.includes('function workshopUpdateLanePreview('), 'Daily and weekly planner lanes should expose a live drag preview helper');
assert.ok(source.includes('workshopDropPreviewHtml({ vertical: true })'), 'Weekly planner lanes should render a vertical ghost preview for drag insertion');
assert.ok(source.includes('setTimeout(() => workshopClearLanePreviews(overlay), 0);'), 'Weekly dragend should also defer preview cleanup until drop completes');
assert.ok(source.includes('workshopFirstAvailableStartSlot(normalizedStage, Number(form.elements.bay.value), safeDate'), 'The direct Schedule form must also suggest a future workday when the selected day is full');
assert.ok(source.includes('maxWorkdays = 260'), 'Automatic scheduling must keep a roughly one-year workday horizon');
assert.ok(source.includes("querySelector('[name=\"hours\"]')?.addEventListener('change', suggestAvailableTime)"), 'Changing planned hours in the Schedule form must recalculate the first available start');
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
let confirmPrompt = '';
global.window.confirm = message => { confirmPrompt = String(message); return true; };
const resolvedConflict = planner.workshopResolveConflictByNextSlot(collisionRows[1], [{ ...collisionRows[0], status: 'planned' }]);
assert.ok(resolvedConflict, 'A planned move into an occupied bay should offer the next open bay slot instead of dead-ending');
assert.strictEqual(
  resolvedConflict.startAt,
  new Date(2026, 6, 14, 11, 0).toISOString(),
  'The conflict resolver should keep the existing booking fixed and move the dragged plan to the next back-to-back opening',
);
assert.match(confirmPrompt, /Move this booking to the next open slot in this bay instead\?/, 'Conflict resolution should ask before moving a plan to the next opening');

// Queue-shift behavior: starting/extending a job over queued PLANNED work offers to push the queue later.
// Future dates keep the check deterministic: overtime extension only applies to live jobs already past their planned end.
const shiftBase = { id: 'FABRICATION::live-now', vehicleKey: 'live-now', stage: 'FABRICATION', bay: 1, startAt: new Date(2030, 6, 15, 8, 0).toISOString(), hours: 4, status: 'started' };
const queuedPlanned = { id: 'FABRICATION::queued', vehicleKey: 'queued', stage: 'FABRICATION', bay: 1, startAt: new Date(2030, 6, 15, 11, 0).toISOString(), hours: 3, status: 'planned' };
global.window.confirm = message => { confirmPrompt = String(message); return true; };
const shiftResult = planner.workshopShiftTrailingPlannedRows(shiftBase, [queuedPlanned]);
assert.ok(shiftResult, 'A start over a queued planned booking must offer to push the queue instead of dead-ending');
assert.strictEqual(shiftResult.moved.length, 1, 'Exactly the queued planned booking should be moved');
assert.strictEqual(shiftResult.moved[0].startAt, new Date(2030, 6, 15, 12, 0).toISOString(), 'The queued booking should shift back-to-back after the live job');
assert.match(confirmPrompt, /Move the queued booking to the next open slot\?/, 'Queue shifting must be confirmed by the operator');
const liveBlocker = { id: 'FABRICATION::other-live', vehicleKey: 'other-live', stage: 'FABRICATION', bay: 1, startAt: new Date(2030, 6, 15, 9, 0).toISOString(), hours: 3, status: 'started' };
assert.strictEqual(planner.workshopShiftTrailingPlannedRows(shiftBase, [liveBlocker]), null, 'Live jobs must never be moved by queue shifting');
global.window.confirm = () => { throw new Error('No confirmation should be requested when nothing needs to move'); };
const noShift = planner.workshopShiftTrailingPlannedRows(shiftBase, [{ ...queuedPlanned, startAt: new Date(2030, 6, 15, 12, 0).toISOString() }]);
assert.ok(noShift && noShift.moved.length === 0, 'Back-to-back queued bookings must remain untouched without prompting');
global.window.confirm = message => { confirmPrompt = String(message); return true; };

const fridayCascadeBase = { id: 'HOIST::inserted', vehicleKey: 'inserted', stage: 'HOIST', bay: 1, startAt: new Date(2030, 6, 19, 14, 0).toISOString(), hours: 1, status: 'planned' };
const fridayLater = [
  { id: 'HOIST::later-1', vehicleKey: 'later-1', stage: 'HOIST', bay: 1, startAt: new Date(2030, 6, 19, 15, 30).toISOString(), hours: 2, status: 'planned' },
  { id: 'HOIST::later-2', vehicleKey: 'later-2', stage: 'HOIST', bay: 1, startAt: new Date(2030, 6, 22, 10, 0).toISOString(), hours: 3, status: 'planned' },
];
const everyLater = planner.workshopShiftEveryLaterPlannedRow(fridayCascadeBase, fridayLater, 60);
assert.deepStrictEqual(everyLater.moved.map(row => row.id), ['HOIST::later-1', 'HOIST::later-2'], 'Every later booking in the same bay must move in original order');
assert.strictEqual(everyLater.moved[0].startAt, new Date(2030, 6, 22, 8, 30).toISOString(), 'Cascade must skip the weekend and continue on the next operational day');
assert.strictEqual(everyLater.moved[1].startAt, new Date(2030, 6, 22, 11, 0).toISOString(), 'The same operational delay must apply to all later bookings');
assert.deepStrictEqual(everyLater.moved.map(row => row.hours), [2, 3], 'Cascade must preserve every later duration');

assert.ok(app.includes("case 'workshop':"), 'Main renderer is missing the Workshop Planner view');
assert.ok(app.includes("workshop: 'Workshop Planner'"), 'Workshop Planner page title is missing');
assert.ok(app.includes('const PMB_SCHEDULE_WORK_START_HOUR = 8;'), 'Legacy PMB schedule start should match the workshop day');
assert.ok(app.includes('const PMB_SCHEDULE_WORK_END_HOUR = 16;'), 'Legacy PMB schedule finish should match the workshop day');
assert.ok(!app.includes(".filter(def => def.code !== 'PIT_INSPECTION')") && app.includes('.map(def => ({ value: def.code, label: def.label }))'), 'Location options must derive from the canonical map and include Pit Inspection as the eighth physical station');
assert.strictEqual(planner.WORKSHOP_STAGE_SEQUENCE[0], 'BUS_4X4', 'Bus 4x4 must remain the first physical workshop station');

assert.ok(source.includes("vehicleTrackingCoreWorkshopPlan:v1"), 'Planner persistence key is missing');
assert.ok(source.includes('CRM_BACKUP_STORAGE_KEYS.push(WORKSHOP_PLAN_STORAGE_KEY)'), 'Planner data must be included in CRM backups');
assert.ok(source.includes('CRM_BACKUP_STORAGE_KEYS.push(WORKSHOP_BAY_SETUP_STORAGE_KEY)'), 'Bay mechanic setup must be included in CRM backups');
assert.ok(source.includes('function workshopHasConflict('), 'Bay collision protection is missing');
assert.ok(source.includes("typeof selectedVehicle === 'function' ? selectedVehicle(cleanKey) : null"), 'Planner vehicle lookup must use the fail-closed shared resolver');
assert.ok(source.includes('requiredAndIncomplete'), 'Future required work must remain schedulable before the vehicle reaches that station');
assert.ok(source.includes("typeof pmbVehiclesNeedingStationWork === 'function'"), 'Planner awaiting lists must share the Control Board station-work eligibility');
assert.ok(source.includes("const requestedStage = dedicatedStage || normalizePmbStage(app.pendingWorkshopStage || '')"), 'Control Board station routes must pin the requested dedicated planner stage');
assert.ok(app.includes('function openWorkshopPlannerForStage('), 'Control Board Open Bays navigation helper is missing');
assert.ok(app.includes('const enteringWorkshopPlanner = nextView === \'workshop\''), 'Planner route entry must detect a fresh station open');
assert.ok(app.includes('app.pendingWorkshopOpenToday = true;'), 'Fresh planner station entry must request today instead of retaining an old viewed date');
assert.ok(source.includes('app.pendingWorkshopOpenToday !== true') && source.includes('app.pendingWorkshopOpenToday = false;'), 'Planner rendering must consume the one-shot today default');
assert.ok(source.includes('function workshopPersistPlanAction('), 'Planner mutations must use transactional persistence and audit logging');
assert.ok(source.includes("window.addEventListener('storage'"), 'Planner must reload changes saved in another browser tab');
assert.ok(source.includes('function workshopRequireNoBayConflict('), 'Hard-block bay collision protection is missing');
assert.ok(source.includes('Overlapping workshop bookings are blocked'), 'Collision rejection must explain that overlapping bookings are blocked');
assert.ok(source.includes('function workshopEntryIsOvertime('), 'Overtime detection is missing');
assert.ok(source.includes('actualHours:'), 'Actual workshop time recording is missing');
assert.ok(source.includes('function startWorkshopPlan('), 'Physical bay start action is missing');
assert.ok(source.includes('function workshopPlanLifecycleActionsHtml('), 'Visible planner-card lifecycle controls are missing');
global.escapeHtml = value => String(value ?? '').replace(/[&<>"']/g, character => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[character]));
assert.match(planner.workshopPlanLifecycleActionsHtml({ id: 'planned', status: 'planned' }), /data-workshop-start-plan="planned"[^>]*>Start job</, 'Planned bay cards must show a direct Start job button');
assert.match(planner.workshopPlanLifecycleActionsHtml({ id: 'started', status: 'started' }), /data-workshop-stop-plan="started"[^>]*>STOPPAGE</, 'Started bay cards must show a direct STOPPAGE button');
assert.match(planner.workshopPlanLifecycleActionsHtml({ id: 'stopped', status: 'stoppage' }), /data-workshop-resume-plan="stopped"[^>]*>Resume job</, 'Stopped bay cards must show a direct Resume job button');
assert.strictEqual(planner.workshopPlanLifecycleActionsHtml({ id: 'done', status: 'completed' }), '', 'Completed bay cards must not show mutable lifecycle controls');
assert.ok(source.includes("querySelectorAll('[data-workshop-start-plan]')"), 'Every rendered Start job button must be bound, not only the first match');
assert.ok(source.includes("querySelectorAll('[data-workshop-stop-plan]')"), 'Every rendered Stop job button must be bound, not only the first match');
assert.ok(source.includes("lifecycleActionsHtml ? 'has-lifecycle-actions'"), 'Cards with lifecycle controls must use the compact non-overlapping content layout');
assert.ok(source.includes('async function moveWorkshopLivePlan('), 'Live workshop jobs need a dedicated safe move path');
assert.ok(source.includes('function moveWorkshopDroppedPlan('), 'Daily drop handling must route planned and live jobs through the correct move path');
assert.ok(source.includes('preferRequestedTime = false'), 'Planner scheduling should distinguish drop-to-time insertion from next-open-slot scheduling');
assert.ok(source.includes('The red current-time line stays visible on the planner and clamps to the workshop edge outside work hours.'), 'Planner guidance should explain the current-time line visibility and edge clamping');
assert.ok(source.includes('const selectedDate = workshopDateFromKey(state.date);'), 'The current-time line should also render when reviewing another workday');
assert.ok(source.includes('const clampedOffset = Math.min(Math.max(offset, 0), WORKSHOP_PLANNER_CONFIG.dayLengthMinutes);'), 'The current-time line should clamp with the authoritative integer-minute planner configuration');
assert.ok(source.includes('function completeWorkshopPlan('), 'Workshop completion action is missing');
assert.ok(source.includes('function stopWorkshopPlan('), 'Workshop stoppage action is missing');
assert.ok(source.includes('function openWorkshopVehicleJob('), 'Double-click vehicle job editor is missing');
assert.ok(source.includes('function openWorkshopWeeklyView('), 'Per-bay weekly schedule is missing');
assert.ok(source.includes('Started and STOPPAGE jobs can also be moved safely, with audit and bay-state updates.'), 'Weekly planner guidance must explain the safe live-move path');
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
assert.ok(source.includes('Parts completion remains an RFT gate, not an entry gate for Tint or Tyre.'), 'Parts should remain an RFT gate without blocking workshop entry');
assert.ok(!source.includes('function removeWorkshopPlan('), 'Direct Remove Plan action must not exist');
assert.ok(!source.includes('max="8"'), 'Workshop hours must not be capped at eight');
assert.ok(!source.includes('Scheduled other days'), 'The Scheduled other days box should be removed');
assert.ok(!source.includes('A started, stopped or completed job cannot be removed from the planner'), 'Live jobs should be returnable through the protected choice flow');
assert.ok(source.includes('data-workshop-resize-plan'), 'Duration resize control is missing');
assert.ok(source.includes('data-workshop-schedule-vehicle'), 'Awaiting vehicles need a direct Schedule button as a reliable alternative to drag/drop');
assert.ok(source.includes('data-workshop-best-slot-vehicle'), 'Awaiting vehicles need a direct Best slot shortcut for the earliest bay suggestion');
assert.ok(source.includes('data-workshop-quick-move-plan'), 'Selected jobs need bay-to-bay quick move controls');
assert.ok(source.includes('data-workshop-best-bay-plan'), 'Selected jobs need a best bay/time shortcut');
assert.ok(source.includes('data-workshop-open-plan-week'), 'Selected jobs need a direct week-view shortcut');
assert.ok(source.includes('data-workshop-schedule-form'), 'The direct booking modal is missing');
assert.ok(source.includes('data-workshop-extend-plan'), 'Quick +15m/+30m/+1h controls are missing');
assert.ok(source.includes('function workshopBestStageSlot('), 'Stage-wide best-slot helper is missing');
assert.ok(source.includes('function workshopSlotSummary('), 'Suggested-slot summary helper is missing');
assert.ok(source.includes('This job is already in the earliest open bay/time for its current stage.'), 'Quick best-bay action must explain when no better move exists');
assert.ok(source.includes('name="hours" type="number" min="1"'), 'Booking inputs must enforce the approved one-hour minimum');
assert.ok(source.includes('Later bookings in this bay move automatically'), 'The scheduling modal must explain the approved cascade behavior');
assert.ok(css.includes('display: block;') && css.includes('overflow: visible;') && css.includes('z-index: 6;'), 'The workshop time axis should stay visibly layered above the planner header');
assert.ok(css.includes('min-width: 760px;') && css.includes('grid-template-columns: 160px minmax(600px, 1fr);'), 'The planner timeline should fit more of the hour labels on standard laptop widths');
assert.ok(source.includes('function workshopConfirmOtherDepartmentPlans('), 'Same-vehicle overlap guard is missing');
assert.ok(source.includes('function workshopOtherDepartmentOverlaps('), 'Same-vehicle overlap detector is missing');
assert.ok(source.includes('This vehicle already has an active booking in the requested time window:'), 'Same-vehicle rejection must identify the conflicting plan');
assert.ok(!source.includes('This vehicle is also planned by another department:'), 'Cross-department warning must not fire merely because another department has any booking - only on real time overlap');
assert.ok(app.includes('function vehicleReadyForQualityControl('), 'The final QC eligibility gate is missing');
assert.ok(app.includes('data-qc-signoff-rft'), 'The Control Board QC sign-off-to-RFT row/action is missing');
assert.ok(app.includes('QC sign-off required'), 'RFT must remain gated until QC is complete');
assert.ok(!app.includes("issues.push('No PMB bucket assigned')"), 'PMB Unallocated must not block RFT');
assert.ok(app.includes('is-in-bay'), 'Control Board work rows must highlight a vehicle that is physically in a numbered bay');

const workshopFunctionSection = (startName, nextName) => {
  const start = source.indexOf(`function ${startName}`);
  const end = source.indexOf(`function ${nextName}`, start + 1);
  assert.ok(start >= 0 && end > start, `Could not isolate ${startName} for collision-path verification`);
  return source.slice(start, end);
};
for (const [startName, nextName, pathLabel] of [
  ['moveWorkshopLivePlan', 'moveWorkshopDroppedPlan', 'live drag/drop'],
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
  ['moveWorkshopLivePlan', 'moveWorkshopDroppedPlan', 'live drag/drop'],
  ['scheduleWorkshopVehicle', 'saveWorkshopDetailForm', 'daily drag/drop'],
  ['saveWorkshopDetailForm', 'startWorkshopPlan', 'detail edit'],
  ['startWorkshopResize', 'workshopWeeklyCardHtml', 'duration resize'],
  ['moveWorkshopWeeklyPlan', 'openWorkshopWeeklyView', 'weekly move'],
]) {
  const section = workshopFunctionSection(startName, nextName);
  assert.ok(section.includes('workshopConfirmOtherDepartmentPlans('), `${pathLabel} must reject an overlapping active booking for the same vehicle before persistence`);
  const firstDispatch = section.search(/workshop(?:DispatchSharedAction|ScheduleSharedNewBooking)\(/);
  if (firstDispatch >= 0) {
    assert.ok(section.indexOf('workshopConfirmOtherDepartmentPlans(') < firstDispatch, `${pathLabel} shared-mode overlap guard must run before dispatch`);
  }
}
{
  const section = workshopFunctionSection('extendWorkshopPlan', 'workshopOtherDepartmentOverlaps');
  assert.ok(section.indexOf('workshopConfirmOtherDepartmentPlans(') >= 0 && section.indexOf('workshopConfirmOtherDepartmentPlans(') < section.indexOf('workshopDispatchSharedAction('), 'shared duration extension must reject same-vehicle overlap before cascade dispatch');
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

for (const selector of ['.workshop-board-shell', '.workshop-bay-lane', '.workshop-plan-chip', '.workshop-now-line', '.workshop-plan-chip.is-overtime', '.workshop-plan-chip.has-assignee-conflict', '.workshop-plan-chip.is-search-match', '.workshop-unallocated-drop', '.workshop-week-grid', '.workshop-week-card', '.workshop-return-card', '.workshop-job-line-row', '.workshop-status-legend', '.workshop-queue-actions', '.workshop-slot-hint', '.workshop-drop-preview', '.workshop-drop-preview-pill']) {
  assert.ok(css.includes(selector), `Workshop CSS is missing ${selector}`);
}
assert.ok(globalCss.includes('.pmb-card-move-button {'), 'PMB movement buttons must have a visible default style');

for (const file of htmlFiles) {
  const html = fs.readFileSync(path.join(root, file), 'utf8');
  for (const view of workshopPlannerNavViews) {
    assert.ok(html.includes(`class="nav-item nav-workshop-item" data-view="${view}"`), `${file} is missing direct Workshop Planner link ${view}`);
  }
  assert.ok(!html.includes('data-view="workshop"'), `${file} must not expose the combined Workshop Planner navigation item`);
  assert.ok(!html.includes('<section id="pipeline"'), `${file} must not expose the obsolete Vehicle Pipeline view`);
  assert.ok(html.includes('id="workshop-planner-root"'), `${file} is missing the Workshop Planner host`);
  assert.ok(html.includes(`workshop-planner.css?v=${appVersion}`), `${file} is missing the planner stylesheet`);
  assert.ok(!html.includes('<script src="workshop-planner.js'), `${file} must not eagerly load the planner script`);
}
assert.ok(app.includes(`const WORKSHOP_PLANNER_SCRIPT_VERSION = '${appVersion}';`), 'Workshop Planner must carry the current canonical eligibility cache-bust version');
assert.ok(app.includes("loadExternalScript(`workshop-planner.js?v=${encodeURIComponent(WORKSHOP_PLANNER_SCRIPT_VERSION)}`"), 'app.js must lazy-load the Workshop Planner with its dedicated cache-bust version');

console.log('Workshop planner regression checks passed');
