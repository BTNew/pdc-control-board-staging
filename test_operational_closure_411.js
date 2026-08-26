'use strict';
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const app = fs.readFileSync('app.js', 'utf8');
const index = fs.readFileSync('index.html', 'utf8');
const planner = fs.readFileSync('workshop-planner.js', 'utf8');
const migration = fs.readFileSync('supabase/staging_only/20260826170000_411_yh_workshop_eligibility_hide_test_fleet.sql', 'utf8');

assert.match(app, /const APP_VERSION = '2026\.08\.27\.06-manual-authority-closure'/);
assert.match(index, /app\.js\?v=2026\.08\.27\.06-manual-authority-closure/);
assert.match(app, /photoReceiptId: result\.data\.photo_receipt_id/);
assert.match(app, /const hasSalesperson = Boolean/);
assert.match(app, /Assign an active salesperson with an email address before final sign-off/);
assert.match(app, /salesperson_email_required:/);
assert.match(app, /Boolean\(photo\?\.photoReceiptId\)/);
assert.match(app, /completeVehicleQualityControl\(cleanKey, photo\)/);
assert.match(app, /app\.vehicleModalLoadingIdentity = !cachedReady/);
assert.match(app, /Loading authoritative vehicle details/);
assert.match(app, /await refreshEmailVehicleLocations\(\)/);
assert.match(app, /refreshed = vehicleModalBoundVehicle\(\)/);
assert.match(app, /void Promise\.allSettled\(\[/);
assert.match(app, /app\.vehicleModalLoadingIdentity = false/);
assert.match(app, /No blank or TBA email draft was opened/);
assert.match(app, /vehicle\.__emailVehicleServerAuthoritative !== true/);
assert.match(app, /Current outstanding work and booking times:/);
assert.match(planner, /alreadyBookedOutstanding/);
assert.match(planner, /unallocated · \$\{alreadyBookedOutstanding\} already booked in bays/);
assert.match(app, /const outstanding = vehicleOutstandingWorkEmailLines\(vehicle\)/);

const start = app.indexOf('function vehicleOutstandingWorkEmailLines');
const end = app.indexOf('\nfunction vehicleStatusUpdateEmailBody', start);
assert.ok(start >= 0 && end > start);
const context = {
  Set, String,
  parseIsoTimestamp: value => value ? new Date(value) : null,
  normalizePmbStage: value => ({ hoist: 'HOIST', fitting: 'FITTING', parts: 'PARTS' }[String(value).toLowerCase()] || String(value).toUpperCase()),
  pdcRequirementDefinitions: () => [
    { key: 'hoist', label: 'HOIST' },
    { key: 'fitting', label: 'FITTING' },
    { key: 'parts', label: 'PARTS' },
  ],
  pdcJobComplete: () => false,
};
vm.createContext(context);
vm.runInContext(app.slice(start, end), context);
const lines = context.vehicleOutstandingWorkEmailLines({ salesWorkshopBookings: [
  { stageCode: 'HOIST', status: 'planned', scheduledStartAt: '2026-08-26T00:00:00Z', scheduledEndAt: '2026-08-26T01:36:00Z', bayName: 'Hoist Bay 01' },
  { stageCode: 'FITTING', status: 'started', actualStartAt: '2026-08-25T07:09:00Z', scheduledEndAt: '2026-08-25T08:45:00Z', bayName: 'Fitting Bay 01' },
] });
assert.strictEqual(lines.length, 3);
assert.match(lines[0], /^- HOIST · PLANNED · .* to .* · Hoist Bay 01$/);
assert.match(lines[1], /^- FITTING · STARTED · .* to .* · Fitting Bay 01$/);
assert.strictEqual(lines[2], '- PARTS · Not booked');

for (const token of [
  'PDC_411_STAGING_HEAD_OR_CONTAINMENT_MISMATCH',
  "v_head IS DISTINCT FROM '20260826164500'",
  "IN('PMB','YH','IT')",
  'v.visible_on_board',
  "stock_number LIKE 'HERMES-TEST-%'",
  'hide_hermes_test_vehicle_from_staging_website_411',
  "records_deleted',false",
  "history_preserved',true",
  "VALUES('20260826170000','411_yh_workshop_eligibility_hide_test_fleet'",
]) assert.ok(migration.includes(token), token);
assert.match(migration, /UPDATE public\.vehicles SET visible_on_board=false,version=version\+1/);
assert.doesNotMatch(migration, /DELETE FROM public\.vehicles/i);
assert.doesNotMatch(migration, /SET deleted_at=/i);
assert.match(migration, /REVOKE ALL ON FUNCTION public\.workshop_station_eligibility\(text\) FROM public,anon,authenticated,service_role/);
assert.match(migration, /GRANT EXECUTE ON FUNCTION public\.workshop_station_eligibility\(text\) TO authenticated/);

console.log('Operational closure 411 contract passed.');
