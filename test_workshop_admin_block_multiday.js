'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

global.escapeHtml = value => String(value == null ? '' : value);
global.cleanNavisionText = value => String(value == null ? '' : value).trim();
global.parseIsoTimestamp = value => {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
};
const planner = require('./workshop-planner.js');
const root = __dirname;
const sql170 = fs.readFileSync(path.join(root, 'supabase', 'staging_only', '170_authoritative_workshop_admin_blocks.sql'), 'utf8');
const sql171 = fs.readFileSync(path.join(root, 'supabase', 'staging_only', '171_release_safety_corrections.sql'), 'utf8');
const sql392 = fs.readFileSync(path.join(root, 'supabase', 'staging_only', '20260826090000_392_workshop_admin_block_atomic_cascade.sql'), 'utf8');
const sql771 = fs.readFileSync(path.join(root, 'supabase', 'staging_only', '20260830100000_771_workshop_admin_block_audit_projection_successor.sql'), 'utf8');
const dataService = fs.readFileSync(path.join(root, 'workshop-data-service.js'), 'utf8');
const source = fs.readFileSync(path.join(root, 'workshop-planner.js'), 'utf8');
const css = fs.readFileSync(path.join(root, 'workshop-planner.css'), 'utf8');

function calendar(overrides = {}) {
  return {
    day_start_time: { value: '07:00' },
    day_end_time: { value: '16:00' },
    scheduling_increment_minutes: { value: 15 },
    default_booking_duration_minutes: { value: 60 },
    working_week: { value: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'] },
    closures: { value: [] },
    break_windows: { value: [] },
    overtime_windows: { value: [] },
    technician_leave: { value: [] },
    ...overrides,
  };
}

function applyConfig(rows) {
  global.window = {
    PDC_AUTH_CONTEXT: { role: 'administrator' },
    __workshopReferenceDataService: {
      getCachedWorkshopConfiguration: () => ({ state: 'connected_editable', rows }),
    },
  };
  planner.workshopSyncConfigFromSharedSettings();
}

function localDate(year, month, day, hour, minute) {
  return new Date(year, month - 1, day, hour, minute, 0, 0);
}

function block(start, durationMinutes) {
  return {
    id: 'admin-15-hours',
    type: 'admin',
    label: 'Admin downtime',
    startAt: start.toISOString(),
    endAt: planner.workshopAddWorkMinutes(start, durationMinutes).toISOString(),
    durationMinutes,
  };
}

applyConfig(calendar());
const longStart = localDate(2026, 8, 29, 10, 15);
const longBlock = block(longStart, 15 * 60);
const longEnd = new Date(longBlock.endAt);
assert.deepStrictEqual([planner.workshopDateKey(longEnd), longEnd.getHours(), longEnd.getMinutes()], ['2026-09-01', 7, 15]);
assert.strictEqual(planner.workshopWorkMinutesBetween(longStart, longEnd), 15 * 60);
const saturday = planner.workshopAdminBlockSegments(longBlock, '2026-08-29');
const monday = planner.workshopAdminBlockSegments(longBlock, '2026-08-31');
const tuesday = planner.workshopAdminBlockSegments(longBlock, '2026-09-01');
assert.strictEqual(saturday.length, 1);
assert.strictEqual(saturday[0].start, 195);
assert.strictEqual(saturday[0].end, 540);
assert.strictEqual(monday.length, 1);
assert.strictEqual(monday[0].continuesFromPrevious, true);
assert.strictEqual(tuesday.length, 1);
assert.strictEqual(tuesday[0].end - tuesday[0].start, 15);
assert.strictEqual([saturday, monday, tuesday].flat().reduce((sum, item) => sum + item.end - item.start, 0), 900);
assert.strictEqual(planner.workshopAdminBlockSegments(longBlock, '2026-08-30').length, 0);
const dailyHtml = planner.workshopAdminBlockHtml(longBlock, '2026-08-31');
assert.ok(dailyHtml.includes('15h total') && dailyHtml.includes('CONTINUED') && dailyHtml.includes('continues next valid work interval'));
const weeklyHtml = planner.workshopWeeklyAdminBlockHtml(longBlock, '2026-09-01');
assert.ok(weeklyHtml.includes('workshop-week-admin-block') && weeklyHtml.includes('CONTINUED') && weeklyHtml.includes('15h total'));

applyConfig(calendar({
  working_week: { value: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'] },
  break_windows: { value: [{ start: '12:00', end: '13:00', scope: 'global' }] },
}));
const breakBlock = block(localDate(2026, 8, 27, 11, 0), 4 * 60);
const breakSegments = planner.workshopAdminBlockSegments(breakBlock, '2026-08-27');
assert.strictEqual(breakSegments.length, 2);
assert.strictEqual(breakSegments[0].end - breakSegments[0].start, 60);
assert.strictEqual(breakSegments[1].end - breakSegments[1].start, 180);
assert.strictEqual(breakSegments.reduce((sum, item) => sum + item.end - item.start, 0), 240);

const lateFriday = block(localDate(2026, 8, 28, 15, 0), 2 * 60);
assert.strictEqual(planner.workshopAdminBlockSegments(lateFriday, '2026-08-29').length, 0);
assert.strictEqual(planner.workshopAdminBlockSegments(lateFriday, '2026-08-31').length, 1);
assert.strictEqual(planner.workshopAdminBlockSegments(lateFriday, '2026-08-31')[0].continuesFromPrevious, true);

const smallBlock = block(localDate(2026, 8, 27, 9, 0), 60);
const smallSegments = planner.workshopAdminBlockSegments(smallBlock, '2026-08-27');
assert.strictEqual(smallSegments.length, 1);
assert.strictEqual(smallSegments[0].end - smallSegments[0].start, 60);

const success = planner.workshopAdminBlockSuccessMessage({
  admin_block: { bay_number: 2, scheduled_start_at: longStart.toISOString(), duration_minutes: 900 },
  repack: { shifted_count: 1 },
});
assert.ok(success.includes('Bay 2') && success.includes('15 h total') && success.includes('cascaded 1 planned row.'));
assert.ok(sql170.includes('workshop_add_operational_minutes(p_start,p_duration)'));
assert.ok(sql170.includes('workshop_operational_minutes_between(p_start,v_end)<>p_duration'));
assert.ok(sql171.includes("b.status='planned'") && sql171.includes("b.status in('queued','planned','started','stoppage')"));
assert.ok(sql392.includes('idempotency_key') && sql392.includes('request_hash') && sql392.includes('shifted_count'));
assert.ok(sql771.includes("PDC_771_OPERATOR_OR_ADMINISTRATOR_REQUIRED") && sql771.includes("'contract','get_workshop_admin_block_audit_771_successor'") && sql771.includes("'continuation_windows',v_windows"));
assert.ok(sql771.includes("pdc_auditor_actor_scope()") && sql771.includes("pdc_auditor_vehicle_dealer") && sql771.includes("'dealer_code',v_dealer_code"));
assert.ok(sql771.includes("GRANT EXECUTE ON FUNCTION public.get_workshop_admin_block_audit_771_successor") && !sql771.includes('GRANT SELECT ON TABLE'));
assert.ok(dataService.includes('get_workshop_admin_block_audit_771_successor') && dataService.includes('readAdminBlockAudit'));
assert.ok(source.includes('workshopWeeklyAdminBlockHtml') && source.includes('adminBlocks.map(block => workshopWeeklyAdminBlockHtml'));
assert.ok(css.includes('flex-wrap: wrap') && css.includes('overflow-wrap: anywhere'));

console.log('Workshop Admin multi-day calendar/projection regression checks passed.');
