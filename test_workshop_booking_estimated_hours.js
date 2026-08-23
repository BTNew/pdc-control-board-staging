'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = __dirname;
const migration = fs.readFileSync(path.join(root, 'supabase', 'staging_only', '20260822093000_317_enforce_workshop_booking_estimated_hours.sql'), 'utf8');
const planner = fs.readFileSync(path.join(root, 'workshop-planner.js'), 'utf8');
const app = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const index = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const staging = fs.readFileSync(path.join(root, 'staging.html'), 'utf8');

assert.ok(migration.includes('PDC_317_PRODUCTION_SENTINEL_PRESENT'), 'Production sentinel must fail closed');
assert.ok(migration.includes("v_project is distinct from 'cdsmnqxtyyoeoznmbidd'"), 'Exact staging project binding is required');
assert.ok(migration.includes('if v_active<>4 or v_mismatch<>2 or v_missing<>1'), 'Observed repair scope must fail closed on drift');
assert.ok(migration.includes("then 'estimated_duration_missing'"), 'Eligibility must expose missing estimates');
assert.ok(migration.includes('workshop_require_positive_estimate_for_planned_booking_317'), 'Backend must block planned bookings without estimates');
assert.ok(migration.includes('pdc_operation_line_booking_duration_317'), 'Operation-line reconciliation trigger must exist');
assert.ok(migration.includes('pdc_adjustment_booking_duration_317'), 'Adjustment reconciliation trigger must exist');
assert.ok(migration.includes('public.cancel_workshop_booking'), 'Existing invalid bookings must use audited cancellation');
assert.ok(migration.includes("v.stock_number='IS60252030'"), 'Zero-hour source case must be handled explicitly');
assert.ok(migration.includes("v.stock_number='13033243'"), 'Stale Other-location seeded bookings must be handled explicitly');
assert.ok(migration.includes('PDC_317_BAY_DURATION_POSTCONDITION'), 'Every occupied bay must match its estimate after repair');
assert.ok(migration.trim().endsWith('commit;'), 'Migration must commit only after all postconditions');
assert.ok(planner.includes("estimated_duration_missing: 'Estimated hours are required before this vehicle can be scheduled into a bay'"), 'UI must explain the fail-closed reason');
const appVersion = app.match(/const APP_VERSION = '([^']+)'/)?.[1];
assert.ok(appVersion, 'App version must be declared');
assert.ok(index.includes(`app.js?v=${appVersion}`), 'Index must load the current app asset');
assert.match(staging, /http-equiv=["']refresh["'][^>]+content=["']0;\s*url=\.\/["']/i, 'Legacy staging entry must redirect to the canonical root');

console.log('workshop_booking_estimated_hours: PASS');
