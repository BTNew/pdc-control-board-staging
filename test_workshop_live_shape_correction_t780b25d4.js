'use strict';

const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const service = require('./pdc-email-vehicle-location-service.js');
const identity = require('./vehicle-modal-identity.js');

const appSource = fs.readFileSync('app.js', 'utf8');
const start = appSource.indexOf('function vehicleModalIdentityStock');
const end = appSource.indexOf('\nfunction selectedVehicle', start);
assert.ok(start > 0 && end > start, 'modal identity binding must be extractable');

const canonicalId = 'a1b2ea79-1933-5453-81e3-b0b1945c94bf';
const rawSnapshotRow = {
  id: canonicalId,
  permanent_vehicle_id: 'PDC-PMB-LIVE-SHAPE',
  stock_number: '12705177',
  version: 6,
  current_location: 'IT',
  work_items: [],
  workshop_bookings: [],
};
const context = {
  app: {
    vehicleModalIdentity: { canonicalId, stockBaseline: '12705177', dealerCode: '37047' },
    emailVehicleLocationRows: [rawSnapshotRow],
    data: [],
  },
  window: { PDC_EMAIL_VEHICLE_LOCATION_SERVICE: service, PDC_VEHICLE_MODAL_IDENTITY: identity },
  cleanNavisionText: value => String(value == null ? '' : value).trim(),
  displayStockNumber: vehicle => String(vehicle?.stock || '').trim(),
  vehicleWorkshopDetailCanonicalId: vehicle => String(vehicle?.__emailVehicleId || vehicle?.id || '').trim(),
  applySharedWorkStateCache: rows => rows,
};
vm.createContext(context);
vm.runInContext(appSource.slice(start, end), context);
const bound = context.vehicleModalBoundVehicle();
assert.ok(bound, 'the exact UUID+Stock authoritative row must bind');
assert.strictEqual(bound.__sharedNavisionDealerCode, '37047',
  'modal authoritative rebinding must preserve the exact Board dealer overlay instead of falling back to global 14450');
assert.strictEqual(context.vehicleModalDealerIdentity({}), '', 'missing row-level dealer identity must fail closed');
assert.strictEqual(context.vehicleModalDealerIdentity({ dealerCode: '99999' }), '', 'unsupported row-level dealer identity must fail closed');
assert.strictEqual(context.vehicleModalApplyDealerIdentity({ dealerCode: '14450' }, { dealerCode: '37047' }), null,
  'a contradictory mapped dealer must fail closed');

const openStart = appSource.indexOf('function openVehicleModal');
const openEnd = appSource.indexOf('\nfunction openAuthenticatedOperationWorkshop', openStart);
const openBody = appSource.slice(openStart, openEnd);
assert.match(openBody, /dealerCode:\s*vehicleModalDealerIdentity\(vehicle\)/,
  'the modal identity must capture the rendered Board row dealer before raw snapshot rebinding');

const migrationPath = 'supabase/staging_only/20260909120000_workshop_live_shape_authority.sql';
assert.ok(fs.existsSync(migrationPath), 'a reviewed STAGING migration must repair the live snapshot producer');
const sql = fs.readFileSync(migrationPath, 'utf8');
assert.match(sql, /workshop_overlay_authoritative_candidate_hours_175/,
  'the live get_station_workshop_snapshot wrapper must overlay authoritative stage hours');
assert.match(sql, /workshop_vehicle_stage_estimated_hours\(\(candidate->>'vehicle_id'\)::uuid,v_stage\)/,
  'each real outstanding candidate must resolve its authoritative duration');
assert.match(sql, /'estimated_duration_missing'/,
  'a candidate without authoritative duration must be fail-closed truthfully');
assert.match(sql, /'12705177'[\s\S]*2\.25/,
  'migration postconditions must assert the binding 135-minute stock');
assert.match(sql, /'13007660'[\s\S]*1\.5/,
  'migration postconditions must assert the stock-agnostic 90-minute fixture');
assert.match(sql, /v_wrapper:=pg_get_functiondef\('public\.get_station_workshop_snapshot/,
  'postconditions must verify the public live snapshot wrapper installs the overlay');
assert.match(sql, /v_probe:=public\.workshop_overlay_authoritative_candidate_hours_175/,
  'postconditions must execute the final candidate overlay against both binding stock IDs');

console.log('run175 deployed-real-shape modal and Workshop authority regression: PASS');
