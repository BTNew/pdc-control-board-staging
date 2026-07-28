'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = __dirname;
const app = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const index = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const styles = fs.readFileSync(path.join(root, 'styles.css'), 'utf8');

for (const transactionLabel of ['Navision import', 'PD Document import', 'Vehicle removal', 'CRM backup restore']) {
  assert.ok(app.includes(`runStorageTransaction('${transactionLabel}'`), `${transactionLabel} is not protected by the storage transaction wrapper`);
}
assert.ok(app.indexOf('recoverInterruptedStorageTransaction();') < app.indexOf('const app = {'), 'Interrupted storage recovery must run before app.data is built');
assert.ok(app.includes('const STORAGE_TRANSACTION_JOURNAL_KEY'), 'Storage recovery journal key is missing');

assert.ok(!index.includes('id="operational-health-summary"'), 'Operational health metadata should not be rendered in the sidebar');
assert.ok(!index.includes('id="report-date"') && !index.includes('id="report-meta"'), 'Source-data metadata should not be rendered in the sidebar');
assert.ok(app.includes('function renderOperationalHealthSummary()'), 'Operational health tracking is missing');
assert.ok(app.includes('OPERATIONAL_HEALTH_KEY'), 'Operational health storage is missing');
for (const healthField of ['lastNavisionImportAt', 'lastWorkImportAt', 'lastBackupAt']) {
  assert.ok(app.includes(healthField), `Operational health is missing ${healthField}`);
}

assert.ok(index.includes('id="incoming-more-filters"'), 'Secondary incoming filters should be grouped under More filters');
const moreFilters = index.slice(index.indexOf('id="incoming-more-filters"'), index.indexOf('id="incoming-filter-summary"'));
assert.ok(moreFilters.includes('id="incoming-rep-filter"'), 'Sales rep should be a secondary filter');
assert.ok(moreFilters.includes('name="incoming-work-filter"'), 'Work-type controls should be secondary filters');

assert.ok(index.includes('id="operational-visibility-grid"'), 'The management visibility statistics view is missing');
assert.ok(app.includes('function operationalVisibilityMetrics('), 'Operational visibility metrics are missing');
for (const metric of ['openThirdParty', 'stagnant', 'capacityAlerts', 'rftGateIssues', 'historyEvents']) {
  assert.ok(app.includes(metric), `Operational visibility is missing the ${metric} metric`);
}

assert.ok(app.includes('function pmbVehicleNeedsStationWork('), 'Control Board should derive rows from outstanding PMB station work');
assert.ok(app.includes('data-open-workshop-stage='), 'Control Board station rows should link directly to Workshop Planner bays');
assert.ok(index.includes('A vehicle can appear in more than one station row'), 'Control Board should explain that multi-station work appears in every applicable row');
assert.ok(styles.includes('.operational-visibility-panel'), 'Operational visibility styling is missing');

console.log('Operational hardening checks passed');
