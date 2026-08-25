const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = __dirname;
const migrationPath = path.join(root, 'supabase', 'staging_only', '20260826090000_392_workshop_admin_block_atomic_cascade.sql');
assert.ok(fs.existsSync(migrationPath), 'atomic Admin cascade migration exists');
const sql = fs.readFileSync(migrationPath, 'utf8');
const lower = sql.toLowerCase();
const planner = fs.readFileSync(path.join(root, 'workshop-planner.js'), 'utf8');
const actions = fs.readFileSync(path.join(root, 'workshop-shared-actions.js'), 'utf8');

for (const marker of [
  "project_ref='cdsmnqxtyyoeoznmbidd'",
  "to_regclass('public.pdc_production_environment_sentinel')",
  "version='20260825235000'",
  'idempotency_key',
  'request_hash',
  'workshop_admin_nearest_available_slot',
  'nearest_available_slot',
  "'fixed_booking_conflict'",
  "'blocker'",
  "status='planned'",
  'union all',
  'workshop_admin_blocks',
  'workshop_add_operational_minutes',
  'workshop_operational_minutes_between',
  'for update',
  'workshop_bump_revision',
  "'notification_delta',0",
  'no partial save',
]) {
  assert.ok(lower.includes(marker.toLowerCase()), `migration contains ${marker}`);
}
assert.ok(!/raise exception[^;]*fixed_booking_conflict/i.test(sql), 'fixed conflicts return a structured slot instead of raising a generic exception');
assert.match(planner, /workshopAdminBlockFeedback/);
assert.match(planner, /pending/i);
assert.match(planner, /suppressFailureAlert:\s*true/);
assert.match(planner, /cascade/i);
assert.match(planner, /nearest/i);
assert.match(actions, /requestId/);
assert.match(actions, /request_id/);
console.log('Admin block atomic cascade contract passed.');
