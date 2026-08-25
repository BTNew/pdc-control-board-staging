'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

global.parseIsoTimestamp = value => {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
};
global.cleanNavisionText = value => String(value == null ? '' : value).trim();
global.window = {
  addEventListener() {},
  __workshopReferenceDataService: {
    getCachedWorkshopConfiguration() {
      const row = value => ({ value });
      return {
        state: 'connected_editable',
        rows: {
          day_start_time: row('07:00'),
          day_end_time: row('17:00'),
          scheduling_increment_minutes: row(15),
          default_booking_duration_minutes: row(60),
          working_week: row(['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday']),
          closures: row([]), break_windows: row([]), overtime_windows: row([]), technician_leave: row([]),
        },
      };
    },
  },
};
const planner = require('./workshop-planner.js');

for (const minutes of [20, 47, 59, 61, 918]) {
  assert.strictEqual(
    Math.round(planner.workshopExactDurationHours(minutes / 60) * 60),
    minutes,
    `${minutes} canonical minutes must remain exact`,
  );
}
const lateStart = new Date(2026, 7, 30, 16, 50, 0, 0); // Sunday
const lateEnd = planner.workshopEntryEnd({ startAt: lateStart.toISOString(), hours: 20 / 60, status: 'planned' });
assert.strictEqual(lateEnd.getDay(), 1, 'a late Sunday job must continue on Monday');
assert.strictEqual(lateEnd.getHours(), 7);
assert.strictEqual(lateEnd.getMinutes(), 10);

const app = fs.readFileSync('app.js', 'utf8');
const service = fs.readFileSync('pdc-email-vehicle-location-service.js', 'utf8');
const css = fs.readFileSync('styles.css', 'utf8');
const migrationPath = path.join('supabase', 'staging_only', '20260825120000_375_acceptance_closure_intake.sql');
assert.ok(fs.existsSync(migrationPath), 'additive acceptance intake migration must exist');
const migration = fs.readFileSync(migrationPath, 'utf8');

const qcStart = app.indexOf('async function completeVehicleQualityControl');
const qcEnd = app.indexOf('\nfunction vehicleCanEnterPit', qcStart);
const qcBody = app.slice(qcStart, qcEnd);
assert.ok(qcBody.includes('.qcCompleteVehicle({'), 'named QC sign-off must use the QC-only RPC');
assert.ok(!qcBody.includes('.qcSignoffToRft({'), 'named QC sign-off must not transfer to RFT');
assert.ok(qcBody.includes('.acceptanceQcComplete({'), 'synthetic QC must use zero-notification guarded lifecycle RPC');
assert.ok(app.includes('Transfer signed-off vehicle to RFT'), 'QC UI must expose a separate RFT transfer control after sign-off');
assert.ok(app.includes('This records your named QC sign-off while the vehicle remains in QC.'), 'confirmation copy must describe separated QC semantics');

const addStart = app.indexOf('async function addCustomerFromForm');
assert.ok(addStart >= 0, 'Add vehicle submit handler must await authoritative acceptance creation');
const addEnd = app.indexOf('\nfunction normalizePurchaseOrderText', addStart);
const addBody = app.slice(addStart, addEnd);
assert.ok(addBody.includes('createAcceptanceVehicle('), 'reserved HERMES acceptance stocks must use the protected creation RPC');
assert.ok(addBody.indexOf('createAcceptanceVehicle(') < addBody.indexOf('saveAddedVehicles(added)'), 'authoritative branch must run before browser-local fallback');
assert.ok(service.includes("const PDC_ACCEPTANCE_VEHICLE_CREATE_RPC = 'create_pdc_acceptance_vehicle_375';"));
assert.ok(service.includes('data.protected_state?.rows !== 1498'), 'client receipt validation must match the witnessed protected-state rebaseline');
assert.ok(service.includes('async function createAcceptanceVehicle('));
assert.ok(service.includes('createAcceptanceVehicle,'));
const lifecycleActions = fs.readFileSync('vehicle-lifecycle-actions.js', 'utf8');
assert.ok(lifecycleActions.includes("rpc('pdc_acceptance_lifecycle_375'"));
assert.ok(app.includes('.acceptanceRftTransfer({'));
assert.ok(app.includes("!isAcceptanceClosureVehicle(selected[0])"), 'synthetic RFT must not open notification flow');

assert.match(css, /@media\s*\(pointer:\s*coarse\)[\s\S]*min-height:\s*44px/);
assert.match(css, /@media\s*\(pointer:\s*coarse\)[\s\S]*min-width:\s*44px/);

for (const marker of [
  "project_ref='cdsmnqxtyyoeoznmbidd'",
  "375_acceptance_closure_intake",
  'pdc_acceptance_vehicle_registry_375',
  'pdc_acceptance_vehicle_bindings_375',
  'pdc_acceptance_vehicle_create_receipts_375',
  'pdc_acceptance_lifecycle_receipts_375',
  'create_pdc_acceptance_vehicle_375',
  'pdc_acceptance_lifecycle_375',
  "'HERMES-TEST-ACCEPTANCE-20260825'",
  'pdc_acceptance_protected_digest_375',
  'UNIQUE(actor_id,idempotency_key)',
  'PDC_375_IDEMPOTENCY_PAYLOAD_MISMATCH',
  'vehicle_notifications',
  'pdc_monitor_staging_guard()',
  'GRANT EXECUTE ON FUNCTION public.create_pdc_acceptance_vehicle_375',
]) assert.ok(migration.includes(marker), `migration missing ${marker}`);
assert.doesNotMatch(migration, /GRANT\s+(?:INSERT|UPDATE|DELETE|ALL)\s+ON/i);
assert.doesNotMatch(migration, /queue_vehicle_notification\s*\(/i);
assert.doesNotMatch(migration, /\bTRUNCATE\b|\bCASCADE\b/i);

console.log('acceptance_closure_contract: PASS');
