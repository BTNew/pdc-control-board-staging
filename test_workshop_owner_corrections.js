const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = __dirname;
const sql = fs.readFileSync(path.join(root, 'supabase', 'staging_only', '20260826093000_393_future_only_workshop_recovery.sql'), 'utf8').toLowerCase();
const adminSql = fs.readFileSync(path.join(root, 'supabase', 'staging_only', '20260826100000_394_admin_compaction_and_duration_bounds.sql'), 'utf8').toLowerCase();
const planner = fs.readFileSync(path.join(root, 'workshop-planner.js'), 'utf8');
const app = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const service = fs.readFileSync(path.join(root, 'workshop-data-service.js'), 'utf8');

for (const marker of [
  "version='20260826090000'",
  'future_only_schedule_enforcement',
  'workshop_reject_overdue_planned_booking',
  'recover_overdue_planned_workshop_bookings',
  'scheduled_start_at < date_trunc',
  'workshop_admin_repack_planned',
  'recover_overdue',
  'workshop_schedule_recovery_receipts',
  'notification_delta',
  'no_partial_save',
]) assert.ok(sql.includes(marker), `migration contains ${marker}`);
assert.match(service, /recover_overdue_planned_workshop_bookings/);
assert.match(service, /snapshot-recovery-/);
assert.match(planner, /workshopQueueVehicleDescription/);
assert.match(planner, /workshopQueueEstimatedLabel/);
assert.match(planner, /Estimated:/);
assert.doesNotMatch(planner, /workshop-requirements-line.*Requirements:/);
assert.match(planner, /authenticatedOperationSummaryLines/);
assert.match(planner, /workshopSharedModeActive\(\) \? \{\} : workshopJobLineAssignments/);
assert.match(app, /data-pdc-block-reason-baseline/);
assert.match(app, /Error: lifecycle or stoppage fields use their dedicated shared action/);
assert.match(app, /parts_update \|\| vehicle\.partsUpdate/);
assert.match(app, /saveAuthoritativeVehicleChanges\(v, consultant, detailChanges\)/);
assert.doesNotMatch(app, /pdcBlockReasonValue !== \(pdcBlockReason\(v\) \|\| ''\)/,
  'salesperson save does not compare against derived block/stoppage text');
for (const marker of [
  "version='20260826093000'",
  'workshop_admin_next_operational_minute',
  'compact_released',
  'delete_workshop_admin_block',
  'notification_delta',
]) assert.ok(adminSql.includes(marker), `admin correction migration contains ${marker}`);
assert.match(planner, /data-workshop-admin-palette-unit/);
assert.match(planner, /working_days/);
assert.doesNotMatch(planner, /data-workshop-admin-palette-duration[^>]*max="8"/);
console.log('Future-only and owner correction contract passed.');
