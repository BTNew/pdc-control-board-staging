'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = __dirname;
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');
const eligibility = require('./workshop-eligibility.js');
const app = read('app.js');
const migration = read('supabase/staging_only/103_restore_pit_inspection_workshop_planner.sql');
const runner = read('scripts/apply_migration_103_staging.py');

const expectedStations = ['BUS_4X4', 'TINT', 'HOIST', 'FITTING', 'FABRICATION', 'ELECTRICAL', 'TYRE', 'PIT_INSPECTION'];
assert.deepStrictEqual(eligibility.workshopPlannerStageCodes(), expectedStations, 'all eight physical stations must be planner-enabled');
const pit = eligibility.assertWorkshopPlannerTarget('PIT_INSPECTION');
assert.strictEqual(pit.route, 'planner-pit');
assert.strictEqual(pit.path, 'workshop/pit');

const fallback = app.slice(app.indexOf('function workshopEligibilityHarnessFallback'), app.indexOf('const WORKSHOP_ELIGIBILITY'));
assert(fallback.includes("['PIT_INSPECTION', 'Pit', 'pitInspection', 'planner-pit', 'workshop/pit', true]"));
assert(!app.includes(".filter(def => def.code !== 'PIT_INSPECTION')"), 'Pit must not be filtered from PMB stage options');
assert(app.includes("PIT_INSPECTION: 1"), 'Pit must retain one physical bay on every capacity surface');
assert(app.includes("{ key: 'PIT_INSPECTION', label: 'Pit'"), 'Pit must be present in the production flow');
const jobs = app.slice(app.indexOf('const PDC_JOB_DEFS = ['), app.indexOf('const PDC_IMPORT_CONTROL_COLUMNS_TEXT'));
assert(jobs.includes("key: 'pitInspection'"), 'Pit must be a required/completed work item');
assert(!/legacyPitStage[\s\S]{0,300}return 'PIT'/.test(app), 'a PMB Pit work assignment must not masquerade as the external PIT location');

for (const marker of [
  "project_ref='cdsmnqxtyyoeoznmbidd'",
  "version='102'",
  "set planner_enabled=true",
  "where code='PIT_INSPECTION'",
  'PDC_MIGRATION_103_ACTIVE_PIT_BOOKING_CONTRADICTION',
  'create or replace function public.pdc_qc_gate_issues',
  "coalesce((select stage from vehicle),'')<>''",
  "values('PIT_INSPECTION',1,clock_timestamp())",
]) assert(migration.includes(marker), `migration 103 missing contract: ${marker}`);
assert(!migration.includes("stage_code_for_work_key(wi.work_key) is distinct from 'PIT_INSPECTION'"), 'effective QC gate must include outstanding Pit work');
assert.match(migration, /raise exception 'PDC_STAGING_SENTINEL_MISMATCH'/);

assert.match(runner, /EXPECTED_REF\s*=\s*['"]cdsmnqxtyyoeoznmbidd['"]/);
assert.match(runner, /PRODUCTION_REF\s*=\s*['"]vjdtsswhroyguxyfjdkt['"]/);
assert.match(runner, /EXPECTED_BRANCH\s*=\s*['"]qa\/workshop-bulletproof-20260728['"]/);
assert.match(runner, /ROLLBACK_ONLY/);
assert.match(runner, /head!='102'/);
assert.match(runner, /operationalSignaturesUnchanged/);

console.log('PASS guarded Pit Inspection planner scope closure 103 contract');
