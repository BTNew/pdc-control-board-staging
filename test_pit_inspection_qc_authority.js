'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = __dirname;
const read = name => fs.readFileSync(path.join(root, name), 'utf8');
const eligibility = require('./workshop-eligibility.js');
const app = read('app.js');
const migration = read('supabase/staging_only/069_pit_inspection_planner_removal_qc_rft_gate.sql');
const shells = ['index.html', 'staging.html', 'no-vehicles.html', 'test-50.html', 'test-75.html', 'test-100.html'];

const pit = eligibility.workshopStageDefinition('Pit Inspection');
assert(pit && pit.code === 'PIT_INSPECTION', 'Pit Inspection must remain a canonical tracked requirement');
assert.strictEqual(pit.statusVisible, true, 'Pit status/tick history must remain visible');
assert.strictEqual(pit.plannerEnabled, false, 'Pit Inspection must not be a Workshop Planner station');
assert.strictEqual(pit.route, '');
assert.strictEqual(pit.path, '');
assert(!eligibility.workshopPlannerStageCodes().includes('PIT_INSPECTION'));
assert.throws(() => eligibility.assertWorkshopPlannerTarget('PIT_INSPECTION'), /not a schedulable planner station/i);

assert(!app.includes("'planner-pit', 'workshop/pit', true"), 'VM fallback must not restore the Pit planner');
assert(!app.includes("'dept-pit-inspection': 'PIT_INSPECTION'"), 'Pit must not retain a production department/planner view');
assert(app.includes(".filter(def => def.code !== 'PIT_INSPECTION')"), 'Pit must not be a PMB bay/staging bucket');
assert(app.includes("job.key !== 'pitInspection'"), 'QC and RFT gates must intentionally exclude Pit Inspection');
assert(app.includes("currentStage === 'PIT_INSPECTION'"), 'Legacy Pit stage markers must not block QC');
assert(app.includes('Pit Inspection is tracked separately and may be completed before or after QC.'), 'Operator guidance must explain the separate Pit timing');

for (const shell of shells) {
  const html = read(shell);
  assert(!html.includes('<option value="PIT_INSPECTION">Pit</option>'), `${shell} must not offer Pit as a production schedule department`);
  assert(html.includes('Department of Transport') && html.includes('has no workshop planner'), `${shell} must explain the external Pit Inspection workflow`);
  assert(html.includes('Pit Inspection remains separately tracked before registration and may be completed before or after QC.'), `${shell} must explain QC/RFT timing`);
}

for (const contract of [
  "set planner_enabled=false",
  "where code='PIT_INSPECTION'",
  'PDC_MIGRATION_069_ACTIVE_PIT_BOOKINGS',
  "b.status::text not in ('completed','deleted','cancelled')",
  'workshop_require_planner_assignment_mutation',
  'pdc_qc_gate_issues',
  "is distinct from 'PIT_INSPECTION'",
  'QC sign-off and RFT transfer must be separate audited transitions',
  'QC sign-off must be completed before RFT transfer',
  'RFT vehicles must retain a prior QC sign-off',
  'vehicles_enforce_qc_then_rft',
]) assert(migration.includes(contract), `migration 069 missing authority contract: ${contract}`);

assert(!/delete\s+from\s+public\.workshop_bookings/i.test(migration), 'Pit planner removal must preserve booking history');
assert(!/update\s+public\.vehicle_work_items[\s\S]{0,120}PIT_INSPECTION/i.test(migration), 'Pit planner removal must not erase or auto-complete the underlying requirement');

console.log('Pit Inspection planner removal and QC/RFT authority contracts passed');
