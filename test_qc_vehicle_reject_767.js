'use strict';

const assert = require('assert');
const fs = require('fs');

const app = fs.readFileSync('app.js', 'utf8');
const service = fs.readFileSync('pdc-email-vehicle-location-service.js', 'utf8');
const migrationPath = 'supabase/staging_only/20260830060000_767_qc_vehicle_reject_to_pmb_stoppage.sql';
const migration = fs.existsSync(migrationPath) ? fs.readFileSync(migrationPath, 'utf8') : '';
const queueStart = app.indexOf('function qcPageVehicleIsEligible');
const queueEnd = app.indexOf('\nfunction renderActiveView', queueStart);
assert.ok(queueStart >= 0 && queueEnd > queueStart, 'QC renderer exists');
const queue = app.slice(queueStart, queueEnd);

assert.ok(migration, 'append-only 767 QC reject migration exists');
assert.match(migration, /reject_pdc_qc_vehicle_to_pmb_stoppage_767/);
assert.match(migration, /p_vehicle_id uuid[\s\S]*p_stock_number text[\s\S]*p_expected_vehicle_version integer[\s\S]*p_reason text[\s\S]*p_idempotency_key uuid/);
assert.match(migration, /pdc_qc_vehicle_rejection_receipts_767/);
assert.match(migration, /PDC_767_UNAUTHORIZED|PDC_767_INVALID_INPUT/);
assert.match(migration, /PDC_767_STOCK_MISMATCH|PDC_767_VEHICLE_VERSION_CONFLICT/);
assert.match(migration, /current_location='PMB'/);
assert.match(migration, /workshop_status='stoppage'/);
assert.match(migration, /pmb_stoppage_reason/);
assert.match(migration, /Pending QC fixes/);
assert.match(migration, /audit_pdc_event/);
assert.match(migration, /production_environment_sentinel/);
assert.match(migration, /NOTIFY pgrst/);

assert.doesNotMatch(queue, /QUALITY CONTROL/);
assert.doesNotMatch(queue, /Only vehicles with all required workshop work complete/);
assert.doesNotMatch(queue, /Vehicle Locations/);
assert.match(queue, /qcPageVehicleIsEligible/);
assert.match(queue, /customerName|customer_name|vehicleCustomerName/);
assert.match(queue, /data-qc-reject/);
assert.match(queue, /qcPageRejectVehicle/);
assert.match(queue, /window\.prompt/);
assert.match(queue, /window\.confirm/);
assert.match(queue, /Pending QC fixes/);
assert.match(service, /rejectQcVehicleToPmb/);
assert.match(service, /reject_pdc_qc_vehicle_to_pmb_stoppage_767/);

console.log('QC vehicle reject 767 contract passed');
