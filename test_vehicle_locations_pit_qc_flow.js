'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = __dirname;
const read = name => fs.readFileSync(path.join(root, name), 'utf8');
const app = read('app.js');
const lifecycle = read('vehicle-lifecycle-actions.js');
const migration = read('supabase/staging_only/070_vehicle_locations_pit_qc_signoff_rft.sql');
const shells = ['index.html', 'staging.html', 'no-vehicles.html', 'test-50.html', 'test-75.html', 'test-100.html'];

const bucketDefs = app.slice(app.indexOf('const VEHICLE_LOCATION_BUCKET_DEFS'), app.indexOf('const VEHICLE_LOCATION_BUCKET_DEFS') + 1200);
const orderedKeys = [...bucketDefs.matchAll(/key:\s*'([^']+)'/g)].map(match => match[1]);
assert.deepStrictEqual(orderedKeys, ['rft', 'qc', 'pit', 'pmb', 'yardhold', 'transit', 'overseas'], 'Vehicle Locations must render RFT, QC, PIT, PMB, YARD HOLD, IT, OTHER in that order');
for (const label of ['RFT', 'QC', 'PIT', 'PMB', 'YARD HOLD', 'IT', 'OTHER']) {
  assert(bucketDefs.includes(`label: '${label}'`), `Vehicle Locations is missing the ${label} bucket`);
}

const jobDefs = app.slice(app.indexOf('const PDC_JOB_DEFS'), app.indexOf('function currentPdcJobLabelList'));
assert(!jobDefs.includes("key: 'pitInspection'"), 'PIT must not remain a workshop job/tick');
const productionDefs = app.slice(app.indexOf('const PRODUCTION_FLOW_DEFS'), app.indexOf('const PRODUCTION_DEPARTMENT_VIEWS'));
assert(!productionDefs.includes("key: 'PIT_INSPECTION'"), 'PIT must not remain a productive workshop station');
assert(app.includes("{ value: 'PIT', label: 'PIT - Department of Transport inspection' }"), 'PIT must be an explicit vehicle location');
assert(app.includes("if (manualPdcLocation === 'PIT') return 'pit';"), 'PIT location must map to the PIT board bucket');
assert(app.includes("if (manualPdcLocation === 'PMB' && (vehicleOrStatus.pdcQcComplete === true || vehicleReadyForQualityControl(vehicleOrStatus))) return 'qc';"), 'Completed station work must promote a PMB vehicle into the QC bucket');
assert(app.includes("window.__vehicleLifecycleActions.qcSignoffToRft"), 'QC sign-off must use the atomic server transition to RFT');
assert(app.includes("data-qc-signoff-rft"), 'QC bucket rows must provide an explicit sign-off action');
assert(app.includes("data-pit-transfer") && app.includes("data-pit-return-pmb"), 'PMB/PIT rows must provide auditable PIT movement controls');

for (const shell of shells) {
  const html = read(shell);
  assert(!html.includes('name="incoming-work-filter" value="pitinspection"'), `${shell} must not expose PIT as a workshop work filter`);
  const bucketFilter = html.slice(html.indexOf('<select id="incoming-bucket-filter">'), html.indexOf('</select>', html.indexOf('<select id="incoming-bucket-filter">')));
  const options = [...bucketFilter.matchAll(/<option value="([^"]*)">([^<]+)<\/option>/g)].slice(1).map(match => [match[1], match[2]]);
  assert.deepStrictEqual(options, [
    ['rft', 'RFT'], ['qc', 'QC'], ['pit', 'PIT'], ['pmb', 'PMB'], ['yardhold', 'YARD HOLD'], ['transit', 'IT'], ['overseas', 'OTHER'],
  ], `${shell} Vehicle Location bucket filter order is incorrect`);
  assert(!html.includes('id="transfer-selected-to-rft-bar"'), `${shell} must not bypass QC sign-off with a bulk PMB-to-RFT action`);
}

assert(app.includes('function reconcileVehicleLifecycleServerResult('), 'successful shared lifecycle responses must reconcile authoritative vehicle state immediately');
assert((app.match(/reconcileVehicleLifecycleServerResult\(vehicle, result\)/g) || []).length >= 2, 'QC and PIT shared mutations must both reconcile the returned server vehicle');

assert(lifecycle.includes('qcSignoffToRft({ vehicleId, expectedVersion, workItemKey, completedSummary })'), 'Lifecycle bridge must expose QC sign-off to RFT');
assert(lifecycle.includes("rpc('qc_signoff_to_rft'"), 'Lifecycle bridge must call the atomic QC-to-RFT RPC');
assert(lifecycle.includes('pitTransferVehicle({ vehicleId, expectedVersion, direction })'), 'Lifecycle bridge must expose PIT location movement');
assert(lifecycle.includes("rpc('pit_transfer_vehicle'"), 'Lifecycle bridge must call the PIT movement RPC');

for (const contract of [
  'create or replace function public.qc_signoff_to_rft',
  'v_qc := public.qc_complete_vehicle',
  'v_rft := public.rft_transfer_vehicle',
  'create or replace function public.pit_transfer_vehicle',
  "v_direction not in ('to_pit', 'to_pmb')",
  "v_target := 'PIT'",
  "v_target := 'PMB'",
  'public.workshop_bookings',
  'grant execute on function public.qc_signoff_to_rft',
  'grant execute on function public.pit_transfer_vehicle',
]) assert(migration.includes(contract), `migration 070 missing authority contract: ${contract}`);

console.log('Vehicle Locations PIT/QC/sign-off-to-RFT contracts passed');
