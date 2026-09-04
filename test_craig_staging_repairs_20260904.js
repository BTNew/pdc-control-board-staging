'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const read = name => fs.readFileSync(path.join(__dirname, name), 'utf8');
const planner = read('workshop-planner.js');
const sharedActions = read('workshop-shared-actions.js');
const app = read('app.js');
const migrationPath = 'supabase/staging_only/20260904010000_craig_workshop_and_jobcard_repairs.sql';
assert.ok(fs.existsSync(path.join(__dirname, migrationPath)), 'append-only staging repair migration must exist');
const migration = read(migrationPath);
const readModelMigrationPath = 'supabase/staging_only/20260904010100_craig_hours_provenance_read_model.sql';
assert.ok(fs.existsSync(path.join(__dirname, readModelMigrationPath)), 'hours provenance must be exposed by the authoritative detail read model');
const readModelMigration = read(readModelMigrationPath);

// Selected bay/station work is intentionally not a duplicate Vehicle Detail page.
assert.ok(planner.includes('function workshopStationSelectionHtml('), 'compact station-only selected work renderer');
assert.ok(planner.includes('workshopStationSelectionHtml(selected)'), 'planner uses compact station selection');
assert.ok(!planner.includes('workshopDetailPanelHtml(selected, focusedPlans'), 'duplicate general Job details panel is not rendered for a bay selection');
const stationSelectionBody = planner.split('function workshopStationSelectionHtml(', 2)[1].split('function workshopDetailHtml(', 1)[0];
assert.ok(!/data-workshop-open-(?:job|vehicle)/.test(stationSelectionBody), 'station selection has no full-detail launcher');
assert.ok(planner.includes('workshopRequiredJobsForStageHtml(vehicle, entry.stage'), 'selected station work remains visible');
for (const control of ['data-workshop-start-plan', 'data-workshop-stop-plan', 'data-workshop-complete-plan']) {
  assert.ok(planner.includes(control), `${control} remains available`);
}

// Labels are editable through one typed server mutation and visible in daily/weekly HTML.
assert.ok(sharedActions.includes('renameAdminBlock({ blockId, expectedVersion, label, metadata })'));
assert.ok(sharedActions.includes("mutate('rename_workshop_admin_block_20260904'"));
assert.ok(planner.includes('data-workshop-admin-block-rename'));
assert.ok(planner.includes('data-workshop-week-admin-block-rename'));

// Atomic block mutations carry distinct labels/history and PIT deletion performs real cancellation.
for (const marker of [
  'rename_workshop_admin_block_20260904',
  "'renamed'",
  "'label'",
  "'admin_block_rename_cascaded'",
  "'admin_block_delete_cancelled'",
  "'PIT_INSPECTION'",
  'deleted_at',
]) assert.ok(migration.includes(marker), `missing migration contract marker ${marker}`);

// Newest Craig authority: every PD is 1.5, including explicit zero and missing hours;
// non-PD explicit zero is immutable source truth. Provenance must state the override.
for (const marker of [
  'pdc_apply_craig_pd_hours_rule_20260904',
  'craig_standard_pd_1_5',
  'source_estimated_hours',
  'source_estimated_hours_source',
  "'Pre-Delivery (Commercial)'",
  "'OP1'",
  "'OP15'",
  "'job_card'",
]) assert.ok(migration.includes(marker), `missing Craig/job-card marker ${marker}`);
assert.ok(/estimated_hours\s*:?=\s*1\.5|estimated_hours[^\n]*1\.50/i.test(migration), 'PD canonical hours are 1.5');
assert.ok(/non[-_ ]pd[^\n]*(?:0\.0|zero)/i.test(migration), 'negative non-PD zero regression is documented');
assert.ok(/explicit[^\n]*0\.0[^\n]*pre[- ]delivery/i.test(migration), 'explicit-zero PD regression is documented');
assert.ok(/missing[^\n]*pre[- ]delivery/i.test(migration), 'missing-hour PD regression is documented');

// Controlled fixture identity and all authoritative fields are exact.
for (const value of ['13048501', 'J139125583', 'SHIRE OF EAST PILBARA', 'Stephen Peck', '069', '1324.5', '17.00']) {
  assert.ok(migration.includes(value), `fixture authority ${value}`);
}
assert.ok(migration.includes('pdc_jobcard_hours_corrections_20260904'), 'append-only correction receipts preserve immutable source evidence');
assert.ok(migration.includes('vehicle_workshop_line_adjustments'), 'effective UI/read-model overlay is repaired without source mutation');
assert.ok(app.includes('Craig standard override · scheduling authority'), 'PD hours UI must expose Craig-standard provenance');
assert.ok(app.includes("label: 'Craig standard hours'"), 'PD override must never be labelled unknown hours');
assert.ok(app.includes("correction_origin === 'job_card_source_correction' ? 'job_card'"), 'adjusted work lines must render OP15 as Job Card evidence');
for (const field of ['correction_origin', 'manual_assignment_locked']) assert.ok(readModelMigration.includes(field), `detail read model must expose ${field}`);

console.log('Craig staging repairs regression: PASS');
