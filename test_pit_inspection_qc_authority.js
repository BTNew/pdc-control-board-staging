'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = __dirname;
const read = name => fs.readFileSync(path.join(root, name), 'utf8');
const eligibility = require('./workshop-eligibility.js');
const app = read('app.js');
const removal069 = read('supabase/staging_only/069_pit_inspection_planner_removal_qc_rft_gate.sql');
const restoration103 = read('supabase/staging_only/103_restore_pit_inspection_workshop_planner.sql');
const migration070 = read('supabase/staging_only/070_vehicle_locations_pit_qc_signoff_rft.sql');
const shells = ['index.html', 'staging.html', 'no-vehicles.html', 'test-50.html', 'test-75.html', 'test-100.html'];

// Effective source restores Pit as the eighth physical station. The separate PIT
// current_location continues to represent Department of Transport movement.
const pit = eligibility.workshopStageDefinition('Pit Inspection');
assert(pit && pit.code === 'PIT_INSPECTION');
assert.strictEqual(pit.plannerEnabled, false);
assert.strictEqual(pit.route, '');
assert.strictEqual(pit.path, '');
assert(!eligibility.workshopPlannerStageCodes().includes('PIT_INSPECTION'));
assert.throws(() => eligibility.assertWorkshopPlannerTarget('PIT_INSPECTION'));

assert(app.includes("['PIT_INSPECTION', 'Pit', 'pitInspection', '', '', false]"));
assert(app.includes("'dept-pit-inspection': 'PIT_INSPECTION'"));
const jobs = app.slice(app.indexOf('const PDC_JOB_DEFS = ['), app.indexOf('const PDC_IMPORT_CONTROL_COLUMNS_TEXT'));
assert(jobs.includes('pitInspection'), 'Pit must be a workshop job/checklist item');
assert(app.includes("{ key: 'pit', label: 'PIT'"), 'external PIT must remain a Vehicle Locations bucket');
assert(app.includes("if (manualPdcLocation === 'PIT') return 'pit'"));
assert(app.includes("data-pit-return-pmb"));
assert(app.includes("data-qc-signoff-rft"));

for (const shell of shells) {
  const html = read(shell);
  if (html.includes('name="incoming-work-filter"') || html.includes('id="incoming-work-filter"')) {
    assert(html.includes('value="pitInspection"'), `${shell} must offer Pit as a workshop work filter`);
  }
  if (shell === 'staging.html') {
    assert(!html.includes('id="incoming-bucket-filter"'), 'staging Vehicle Locations must be search-only');
  } else {
    assert(html.includes('<option value="pit">PIT</option>'), `${shell} must offer the external PIT location bucket`);
  }
  assert(html.includes('Pit Inspection is a required workshop station'), `${shell} must explain Pit workshop authority`);
  assert(html.includes('Department of Transport PIT remains a separate vehicle location'), `${shell} must distinguish external PIT location authority`);
}

assert(removal069.includes('set planner_enabled=false'), 'historical removal migration must remain immutable evidence');
for (const contract of [
  'set planner_enabled=true',
  "where code='PIT_INSPECTION'",
  'PDC_MIGRATION_103_ACTIVE_PIT_BOOKING_CONTRADICTION',
  'pdc_qc_gate_issues',
  "coalesce((select stage from vehicle),'')<>''",
  "values('PIT_INSPECTION',1,clock_timestamp())",
]) assert(restoration103.includes(contract), `migration 103 missing effective authority contract: ${contract}`);
assert(!restoration103.includes("stage_code_for_work_key(wi.work_key) is distinct from 'PIT_INSPECTION'"), 'Pit must gate QC/RFT again');

for (const contract of [
  'create or replace function public.pit_transfer_vehicle',
  'create or replace function public.qc_signoff_to_rft',
  'PDC_QC_SIGNOFF_TO_RFT_ATOMIC_FAILED',
  "v_target := 'PIT'",
  "v_target := 'PMB'",
]) assert(migration070.includes(contract), `migration 070 missing external location contract: ${contract}`);

assert(!/delete\s+from\s+public\.workshop_bookings/i.test(restoration103), 'Pit restoration must preserve booking history');
console.log('Pit workshop planner restoration and separate external location contracts passed');
