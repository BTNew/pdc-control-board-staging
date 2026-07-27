'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = __dirname;
const read = name => fs.readFileSync(path.join(root, name), 'utf8');
const eligibility = require('./workshop-eligibility.js');
const app = read('app.js');
const migration069 = read('supabase/staging_only/069_pit_inspection_planner_removal_qc_rft_gate.sql');
const migration070 = read('supabase/staging_only/070_vehicle_locations_pit_qc_signoff_rft.sql');
const shells = ['index.html', 'staging.html', 'no-vehicles.html', 'test-50.html', 'test-75.html', 'test-100.html'];

// The canonical code remains only for legacy/history compatibility and has no planner capability.
const pit = eligibility.workshopStageDefinition('Pit Inspection');
assert(pit && pit.code === 'PIT_INSPECTION');
assert.strictEqual(pit.plannerEnabled, false);
assert.strictEqual(pit.route, '');
assert.strictEqual(pit.path, '');
assert(!eligibility.workshopPlannerStageCodes().includes('PIT_INSPECTION'));
assert.throws(() => eligibility.assertWorkshopPlannerTarget('PIT_INSPECTION'), /not a schedulable planner station/i);

assert(!app.includes("'planner-pit', 'workshop/pit', true"));
assert(!app.includes("'dept-pit-inspection': 'PIT_INSPECTION'"));
const jobs = app.slice(app.indexOf('const PDC_JOB_DEFS = ['), app.indexOf('const PDC_IMPORT_CONTROL_COLUMNS_TEXT'));
assert(!jobs.includes('pitInspection'), 'PIT must not be a workshop job/checklist item');
assert(app.includes("{ key: 'pit', label: 'PIT'"), 'PIT must be a Vehicle Locations bucket');
assert(app.includes("if (manualPdcLocation === 'PIT') return 'pit'"));
assert(app.includes("data-pit-return-pmb"));
assert(app.includes("data-qc-signoff-rft"));

for (const shell of shells) {
  const html = read(shell);
  assert(!html.includes('<option value="PIT_INSPECTION">Pit</option>'), `${shell} must not offer PIT as a workshop schedule department`);
  assert(!html.includes('name="incoming-work-filter" value="pitinspection"'), `${shell} must not offer PIT as a workshop work filter`);
  assert(html.includes('<option value="pit">PIT</option>'), `${shell} must offer the PIT location bucket`);
  assert(html.includes('<option value="qc">QC</option>'), `${shell} must offer the QC location bucket`);
  assert(html.includes('PIT is a separate vehicle location, not a workshop job.'), `${shell} must explain PIT authority`);
  assert(html.includes('A named QC sign-off immediately marks the vehicle RFT.'), `${shell} must explain QC-to-RFT authority`);
}

for (const contract of [
  'set planner_enabled=false',
  "where code='PIT_INSPECTION'",
  'PDC_MIGRATION_069_ACTIVE_PIT_BOOKINGS',
  "b.status::text not in ('completed','deleted','cancelled')",
  'workshop_require_planner_assignment_mutation',
  'pdc_qc_gate_issues',
  "is distinct from 'PIT_INSPECTION'",
  'QC sign-off must be completed before RFT transfer',
  'RFT vehicles must retain a prior QC sign-off',
  'vehicles_enforce_qc_then_rft',
]) assert(migration069.includes(contract), `migration 069 missing authority contract: ${contract}`);

for (const contract of [
  'create or replace function public.pit_transfer_vehicle',
  'create or replace function public.qc_signoff_to_rft',
  'PDC_QC_SIGNOFF_TO_RFT_ATOMIC_FAILED',
  "v_target := 'PIT'",
  "v_target := 'PMB'",
]) assert(migration070.includes(contract), `migration 070 missing authority contract: ${contract}`);

assert(!/delete\s+from\s+public\.workshop_bookings/i.test(migration069), 'PIT planner removal must preserve booking history');
console.log('PIT location removal from Workshop Planning and QC sign-off to RFT contracts passed');
