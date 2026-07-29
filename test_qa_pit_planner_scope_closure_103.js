'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = __dirname;
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const eligibility = require('./workshop-eligibility.js');
const app = read('app.js');
const restored103 = read('supabase/staging_only/103_restore_pit_inspection_workshop_planner.sql');
const removed108 = read('supabase/staging_only/108_remove_pit_inspection_workshop_planner.sql');
const runner108 = read('scripts/apply_migration_108_staging.py');

const expectedStations = ['BUS_4X4', 'TINT', 'HOIST', 'FITTING', 'FABRICATION', 'ELECTRICAL', 'TYRE'];
assert.deepStrictEqual(eligibility.workshopPlannerStageCodes(), expectedStations, 'Pit inspection must not own a Workshop bay');
const pit = eligibility.workshopStageDefinition('PIT_INSPECTION');
assert(pit && pit.statusVisible === true, 'Pit must remain a visible workflow/status requirement');
assert.strictEqual(pit.plannerEnabled, false);
assert.strictEqual(pit.route, '');
assert.throws(() => eligibility.assertWorkshopPlannerTarget('PIT_INSPECTION'));

const fallback = app.slice(app.indexOf('function workshopEligibilityHarnessFallback'), app.indexOf('const WORKSHOP_ELIGIBILITY'));
assert(fallback.includes("['PIT_INSPECTION', 'Pit', 'pitInspection', '', '', false]"));
assert(app.includes("{ key: 'PIT_INSPECTION', label: 'Pit'"), 'Pit must remain in the production flow');
const jobs = app.slice(app.indexOf('const PDC_JOB_DEFS = ['), app.indexOf('const PDC_IMPORT_CONTROL_COLUMNS_TEXT'));
assert(jobs.includes("key: 'pitInspection'"), 'Pit must remain a required/completed work item');
assert(!/legacyPitStage[\s\S]{0,300}return 'PIT'/.test(app), 'a PMB Pit work assignment must not masquerade as the external PIT location');

assert(restored103.includes("set planner_enabled=true"), 'migration 103 must remain immutable historical ledger source');
for (const marker of [
  "project_ref='cdsmnqxtyyoeoznmbidd'",
  "PDC_MIGRATION_108_ACTIVE_PIT_BOOKINGS_REQUIRE_REVIEW",
  "set planner_enabled=false",
  "where code='PIT_INSPECTION'",
  "set is_active=false",
  'workflow/status-only and has no Workshop bay',
]) assert(removed108.includes(marker), `migration 108 missing contract: ${marker}`);
assert.match(removed108, /raise exception 'PDC_STAGING_SENTINEL_MISMATCH'/);
assert.match(runner108, /EXPECTED_REF='cdsmnqxtyyoeoznmbidd'/);
assert.match(runner108, /PRODUCTION_REF='vjdtsswhroyguxyfjdkt'/);
assert.match(runner108, /ROLLBACK_ONLY/);
assert.match(runner108, /head!='107'/);
assert.match(runner108, /protected operational signatures changed/);

console.log('PASS additive Pit Inspection Workshop-bay removal 108 contract');
