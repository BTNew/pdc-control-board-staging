/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. */
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');

process.env.TZ = 'Australia/Perth';
global.parseIsoTimestamp = value => {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
};
global.cleanNavisionText = value => String(value ?? '').trim();
global.escapeHtml = value => String(value ?? '').replace(/[&<>"']/g, character => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[character]));
const planner = require('./workshop-planner.js');

const row = value => ({ value, version: 1 });
global.window = {
  __workshopReferenceDataService: {
    getCachedWorkshopConfiguration: () => ({
      state: 'connected_read_only',
      rows: {
        day_start_time: row('07:00'),
        day_end_time: row('17:00'),
        scheduling_increment_minutes: row(15),
        default_booking_duration_minutes: row(60),
        working_week: row(['monday', 'tuesday', 'wednesday', 'thursday', 'friday']),
        closures: row([]),
        break_windows: row([]),
        overtime_windows: row([]),
        technician_leave: row([]),
      },
    }),
  },
};
planner.workshopSyncConfigFromSharedSettings();

const monday = new Date('2026-10-26T00:00:00.000Z'); // 08:00 Perth Monday
const noOverride = planner.workshopAvailabilityWindowsForDate(monday, { stage: 'HOIST', bay: 1 });
const plain = planner.workshopAvailabilityWindowsForDate(monday);
assert.deepEqual(noOverride, plain);
assert.equal(planner.workshopBayHoursOverride({ stage: 'HOIST', bay: 1 }), null);
assert.equal(planner.workshopBayHoursCaption('HOIST', 1, '2026-10-26'), '');

const week = {};
for (const day of ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday']) {
  week[day] = { off: day === 'tuesday' || day === 'saturday' || day === 'sunday', start: '08:00', finish: '15:00', breaks: day === 'monday' ? [{ start: '12:00', finish: '12:30' }] : [] };
}
planner.workshopSetBayHours570({ 'HOIST:1': week });
assert.deepEqual(planner.workshopAvailabilityWindowsForDate(monday), plain);
const hoist = planner.workshopAvailabilityWindowsForDate(monday, { stage: 'HOIST', bay: 1 });
assert.deepEqual(hoist.map(item => [item.startMinutes, item.endMinutes]), [[480, 720], [750, 900]]);
const tuesday = new Date('2026-10-27T00:00:00.000Z');
assert.equal(planner.workshopIsConfiguredWorkingDay(tuesday, { stage: 'HOIST', bay: 1 }), false);
assert.equal(planner.workshopIsConfiguredWorkingDay(tuesday), true);
const added = planner.workshopAddWorkMinutes(monday, 60, { stage: 'HOIST', bay: 1 });
assert.equal(added.toISOString(), new Date('2026-10-26T01:00:00.000Z').toISOString());
// 07:00 Perth is inside the 07:00–17:00 workshop day and before this bay opens at 08:00.
const beforeOpen = new Date('2026-10-25T23:00:00.000Z');
const addedEarly = planner.workshopAddWorkMinutes(beforeOpen, 60, { stage: 'HOIST', bay: 1 });
const plainEarly = planner.workshopAddWorkMinutes(beforeOpen, 60);
assert.equal(addedEarly.toISOString(), '2026-10-26T01:00:00.000Z');
assert.equal(plainEarly.toISOString(), '2026-10-26T00:00:00.000Z');
// Sixty minutes from 11:30 crosses the 12:00–12:30 break only when the override is on.
const beforeBreak = new Date('2026-10-26T03:30:00.000Z');
assert.equal(planner.workshopAddWorkMinutes(beforeBreak, 60, { stage: 'HOIST', bay: 1 }).toISOString(), '2026-10-26T05:00:00.000Z');
assert.equal(planner.workshopAddWorkMinutes(beforeBreak, 60).toISOString(), '2026-10-26T04:30:00.000Z');
const next = planner.workshopNextWorkdayDate(monday, { stage: 'HOIST', bay: 1 });
assert.equal(planner.workshopDateKey(next), '2026-10-28');
assert.equal(planner.workshopBayHoursCaption('HOIST', 1, '2026-10-26'), '08:00–15:00 · break 12:00–12:30');
assert.equal(planner.workshopBayHoursCaption('HOIST', 1, '2026-10-27'), 'Day off');
const closed = planner.workshopUnavailableTimeHtml('2026-10-26', { stage: 'HOIST', bay: 1 });
assert.match(closed, /Closed/);
planner.workshopSetBayHours570(null);
assert.deepEqual(planner.workshopAvailabilityWindowsForDate(monday, { stage: 'HOIST', bay: 1 }), plain);

const html = fs.readFileSync('index.html', 'utf8');
const app = fs.readFileSync('app.js', 'utf8');
const sql = fs.readFileSync('supabase/migrations/20261027233000_r570_bay_manager_hours.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261027233000_r570_bay_manager_hours.down.sql', 'utf8');
assert.match(html, /id="nav-bay-manager" data-view="bay-manager"/);
assert.match(html, /<section id="bay-manager" class="view">/);
assert.match(html, /pdc-bay-manager\.js\?r570=2026\.10\.27\.r570/);
assert.doesNotMatch(app, /requestedView === 'bay-manager' && !userManagementAdministratorActive/);
assert.match(app, /case 'bay-manager':\s*window\.PdcBayManager\?\.open\(\);/);
assert.match(app, /r570=2026\.10\.27\.r570/);
assert.equal((app.match(/workshop-planner\.js\?[^`]*r570=2026\.10\.27\.r570/g) || []).length, 2);
assert.match(fs.readFileSync('pdc-staff-usage.js', 'utf8'), /'bay-manager':'update-history'/);
assert.ok(fs.readFileSync('scripts/build_pages_runtime.js', 'utf8').includes("'pdc-bay-manager.js'"));
assert.match(sql, /sort_order, added_in\)\s*VALUES \('bay_manager_hours_570', 'F184'/);
assert.match(sql, /true, 342, 'r570'/);
assert.match(sql, /workshop_bay_has_hours_570/);
assert.equal(sql.includes('UPDATE public.workshop_bookings SET'), false);
assert.match(sql, /strpos\(setter\.prosrc, 'UPDATE public\.workshop_bookings'\) = 0/);
assert.match(sql, /strpos\(tick\.prosrc, 'workshop_bay_work_hours_570'\) = 0/);
assert.match(down, /83a2c8d5ff85b5a295343e5f3ef66ded/);
assert.equal(fs.readFileSync('karratha/workshop-planner.js', 'utf8').includes('WORKSHOP_BAY_HOURS_570'), false);
assert.equal(fs.readFileSync('karratha/workshop-planner.css', 'utf8').includes('workshop-bay-hours'), false);
assert.doesNotMatch(fs.readFileSync('pdc-bay-manager.css', 'utf8'), /orange|#f97316|#ea580c/i);
assert.match(fs.readFileSync('pdc-bay-manager.js', 'utf8'), /set_workshop_bay_display_name/);
assert.match(fs.readFileSync('pdc-bay-manager.js', 'utf8'), /set_workshop_bay_active/);
assert.match(fs.readFileSync('pdc-bay-manager.js', 'utf8'), /cdsmnqxtyyoeoznmbidd/);
assert.doesNotMatch(fs.readFileSync('pdc-bay-manager.js', 'utf8'), /vjdtsswhroyguxyfjdkt/);

console.log('Bay Manager r570 checks passed.');
