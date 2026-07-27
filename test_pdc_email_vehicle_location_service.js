'use strict';
const fs = require('fs');
const {
  PDC_EMAIL_VEHICLE_STAGING_PROJECT_REF, PDC_EMAIL_VEHICLE_REVISION_TABLE,
  canonicalWorkKey, mapServerVehicle, reconcileVehicleRows, createPdcEmailVehicleLocationService,
} = require('./pdc-email-vehicle-location-service.js');
function assert(value, message) { if (!value) throw new Error(message); }

(async () => {
  assert(canonicalWorkKey('Pit Inspection') === 'pitinspection' && canonicalWorkKey('PIT_INSPECTION') === 'pitinspection', 'Pit aliases must canonicalize');
  const server = { id: 's1', permanent_vehicle_id: 'p1', version: 12, stock_number: 'S-100', vin: 'VIN100', customer_name: 'Server customer', vehicle_description: 'Server vehicle', current_location: 'Other', visible_on_board: true, work_items: [{ work_key: 'tint', required: true, completed: false }, { work_key: 'sublet', required: true, completed: false }, { work_key: 'pit_inspection', required: true, completed: true, completed_at: '2026-07-25T01:00:00Z', completed_by: 'staff' }], parts_required: true, parts_completed: false, parts_update: { parts_ordered: true, parts_stoppage: false, worst_eta: '2026-08-12', updated_at: '2026-07-27T01:00:00Z' }, sublet_booking: { provider: 'Provider A', booking_date: '2026-08-04', email_sent: false, version: 3 } };
  const mapped = mapServerVehicle(server);
  assert(mapped.pdcLocation === 'Other' && mapped.pdcSheetVisible === true, 'Other server row must remain board-visible');
  assert(mapped.pdcRequiresTint === true && mapped.pdcCompleteTint === false, 'Required incomplete work must map to a to-be-completed tick');
  assert(mapped.pdcRequiresPitInspection === true && mapped.pdcCompletePitInspection === true, 'Canonical completed work must map');
  assert(mapped.pdcRequiresParts === true && mapped.pdcCompleteParts === false, 'Parts summary flags must be authoritative');
  assert(mapped.__emailVehicleVersion === 12 && mapped.pdcPartsOrdered === true && mapped.pdcPartsWorstEta === '2026-08-12', 'Vehicle version and shared Parts ETA state must map for authoritative updates and countdowns');
  assert(mapped.pdcRequiresSublet === true && mapped.pmbSubletProvider === 'Provider A' && mapped.pmbSubletBookingDate === '2026-08-04' && mapped.__subletBookingVersion === 3, 'Shared Sublet requirement and booking fields must map together');
  assert(mapped.__emailVehicleReadOnly === true, 'Email-imported server rows must remain fail-closed for browser-local location mutations');
  assert(mapped.__locationIdentityReadOnly !== true, 'A unique email-imported server row must not be mislabeled as an identity conflict');

  const merged = reconcileVehicleRows([{ stock: 'S100', vin: 'VIN100', client: 'Browser edit', pdcRequiresTint: false }], [server]).rows;
  assert(merged.length === 1 && merged[0].client === 'Server customer' && merged[0].pdcRequiresTint === true, 'Server row must override matching browser/static data');
  assert(merged[0].__emailVehicleReadOnly === true && merged[0].__locationIdentityReadOnly !== true, 'A unique stock/VIN match must remain safely read-only without claiming an identity conflict');
  const restored = reconcileVehicleRows([], [server]).rows;
  assert(restored.length === 1 && restored[0].__emailVehicleServerAuthoritative === true, 'Browser deletion must not hide a server row');
  const conflict = reconcileVehicleRows([{ stock: 'S100', vin: 'A' }, { stock: 'S200', vin: 'VIN100' }], [server]);
  assert(conflict.rows.length === 2 && conflict.conflictCount === 2 && conflict.rows.every(row => row.__emailVehicleIdentityConflict && row.__locationIdentityReadOnly === true), 'Cross-identity conflicts must remain read-only and fail closed without inserting the server row');

  let blocked = false;
  try { createPdcEmailVehicleLocationService({ config: { url: 'https://production.supabase.co', publishableKey: 'x' }, fetchImpl: async () => null }); } catch (_error) { blocked = true; }
  assert(blocked, 'Non-staging project must be refused');
  let request = null; let subscription = null;
  const service = createPdcEmailVehicleLocationService({
    config: { url: `https://${PDC_EMAIL_VEHICLE_STAGING_PROJECT_REF}.supabase.co`, publishableKey: 'key' },
    getAccessToken: () => 'approved-token',
    fetchImpl: async (url, options) => { request = { url, options }; return { ok: true, status: 200, async json() { return { ok: true, code: 'ok', data: { revision: 7, vehicles: [server] } }; } }; },
    subscribeRealtime(table, callback) { subscription = { table, callback }; return { unsubscribe() {} }; },
  });
  const snapshot = await service.snapshot();
  assert(snapshot.ok && snapshot.data.revision === 7 && /get_pdc_email_vehicle_location_snapshot$/.test(request.url), 'Exact authenticated snapshot RPC must be used');
  assert(request.options.headers.Authorization === 'Bearer approved-token' && request.options.body === '{}', 'Snapshot must use current auth and no browser-supplied authority parameters');
  const updated = await service.updateSublet('s1', 3, 'booking_date', '2026-08-05');
  const updateBody = JSON.parse(request.options.body);
  assert(updated.ok && /update_pdc_sublet_booking_field$/.test(request.url), 'Sublet edits must use the protected shared RPC');
  assert(updateBody.p_vehicle_id === 's1' && updateBody.p_expected_version === 3 && updateBody.p_field === 'booking_date' && updateBody.p_value === '2026-08-05', 'Sublet updates must bind the canonical vehicle, version, field and value');
  const partsEtaUpdated = await service.updatePartsEta('s1', 12, '2026-08-12');
  const partsEtaBody = JSON.parse(request.options.body);
  assert(partsEtaUpdated.ok && /update_pdc_parts_eta$/.test(request.url), 'Parts ETA edits must use the protected shared RPC');
  assert(partsEtaBody.p_vehicle_id === 's1' && partsEtaBody.p_expected_version === 12 && partsEtaBody.p_worst_eta === '2026-08-12', 'Parts ETA updates must bind canonical vehicle identity, vehicle version and date');
  let revision = null; service.subscribe(value => { revision = value; });
  subscription.callback({ new: { revision: 8 } });
  assert(subscription.table === PDC_EMAIL_VEHICLE_REVISION_TABLE && revision === 8, 'Exact realtime revision table must trigger refresh');

  const staging = fs.readFileSync('staging.html', 'utf8');
  const production = fs.readFileSync('index.html', 'utf8');
  const app = fs.readFileSync('app.js', 'utf8');
  assert(staging.includes('pdc-email-vehicle-location-service.js') && !production.includes('pdc-email-vehicle-location-service.js'), 'Service must load only from staging.html');
  assert(app.includes("const emailReadOnly = vehicle.__emailVehicleReadOnly === true;") && app.includes("emailReadOnly ? 'Email import · Read only'"), 'Email-imported rows must show an accurate read-only badge instead of a false identity conflict');
  assert(staging.includes('Identity conflicts fail closed') && staging.includes('Authenticated email vehicle imports'), 'Staging-only safety copy must be present');
  assert(app.includes('pdc-auth-ready') && app.includes('initEmailVehicleLocationsIfAvailable') && app.includes('pdc-auth-locked'), 'App must bind service lifecycle to approved auth');
  assert(app.includes('reconcileVehicleRows(localRows, app.emailVehicleLocationRows)'), 'Vehicle Location cards must consume authoritative rows');
  assert(staging.indexOf('pdc-email-vehicle-location-service.js') < staging.indexOf('app.js'), 'Email vehicle service must load before app initialization/auth events');
  assert(app.includes('vehicle.__emailVehicleServerAuthoritative === true'), 'An authoritative email row must consume its matching activated Navision row rather than render a duplicate');
  console.log('Authenticated email vehicle Location service, authority merge, mapping, realtime and staging containment checks passed');
})().catch(error => { console.error(error); process.exit(1); });
