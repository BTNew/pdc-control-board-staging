'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const migrationPath = path.join(__dirname, 'supabase', 'staging_only', '20260822090000_316_repair_orphan_workshop_bookings.sql');
const sql = fs.readFileSync(migrationPath, 'utf8');

assert.ok(sql.includes("to_regclass('public.pdc_production_environment_sentinel') is not null"), 'Production sentinel must fail closed');
assert.ok(sql.includes('public.pdc_monitor_staging_guard()'), 'Staging guard is required');
assert.ok(sql.includes("v_project is distinct from 'cdsmnqxtyyoeoznmbidd'"), 'Exact staging project binding is required');
assert.ok(sql.includes("lower(email) = 'craig.watson@broometoyota.com.au'"), 'Owner-authorized administrator attribution is required');
assert.ok(sql.includes("b.status in ('queued','planned','started','stoppage')"), 'Only active booking states may be repaired');
assert.ok(sql.includes("v.deleted_at is not null or v.lifecycle_state <> 'active'"), 'Only deleted/inactive parent vehicles may be targeted');
assert.ok(sql.includes('if v_target_count <> 230'), 'Exact observed scope must fail closed on drift');
assert.ok(sql.includes("deleted_reason = 'Parent vehicle archived: legacy orphan repair 316'"), 'Repair must archive, not erase, bookings');
assert.ok(sql.includes('insert into public.workshop_booking_history'), 'Every repaired booking needs retained history');
assert.ok(sql.includes("'vehicle_archived'"), 'History must use the canonical archive event');
assert.ok(sql.includes('perform public.workshop_bump_revision()'), 'Planner clients need a revision bump');
assert.ok(sql.includes('if v_remaining <> 0'), 'Postcondition must require zero active orphans');
assert.ok(sql.includes("'20260822090000'"), 'Migration must have a durable version record');
assert.ok(sql.trim().endsWith('commit;'), 'Migration must commit only after all assertions');

console.log('orphan_workshop_booking_repair: PASS');
