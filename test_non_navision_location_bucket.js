'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const emailVehicles = require('./pdc-email-vehicle-location-service.js');
const source = fs.readFileSync(__dirname + '/app.js', 'utf8');
const vehicleId = '11111111-1111-4111-8111-111111111111';

function extractFunction(name) {
  const start = source.indexOf(`function ${name}(`);
  assert.ok(start >= 0, `${name} exists`);
  const open = source.indexOf(') {', start) + 2;
  assert.ok(open > start, `${name} has a body`);
  let depth = 0;
  for (let i = open; i < source.length; i++) {
    if (source[i] === '{') depth++;
    if (source[i] === '}' && --depth === 0) return source.slice(start, i + 1);
  }
  throw Error(`Unterminated function ${name}`);
}

function vehicle(overrides = {}) {
  return emailVehicles.mapServerVehicle({
    id: vehicleId, version: 3, stock_number: '12657478', customer_name: 'External fleet customer',
    source_system: 'authenticated_email', current_location: 'YH', lifecycle_state: 'active',
    visible_on_board: true, vehicle_description: 'Used vehicle supplied by customer',
    ...overrides,
  });
}

function setup(options = {}) {
  const definitions = source.match(/const VEHICLE_LOCATION_BUCKET_DEFS = Object\.freeze\(\[[\s\S]*?\]\);/);
  assert.ok(definitions, 'bucket definitions exist');
  const ctx = {
    app: { quickFilter: '', selectedRows: new Set() },
    window: {},
    canonicalToyotaStatus: value => value,
    vehicleLooksToyota: () => true,
    navisionLocationSourceText: row => row.navisionLocationStatus || row.toyotaStatus || '',
    kewdaleEtaValue: row => row.navisionKewdaleEta || row.etaAtDealer || '',
    parseDateAU: value => value && !Number.isNaN(Date.parse(value)) ? new Date(value) : null,
    vehicleLifecycleSharedModeActive: () => options.shared !== false,
    sharedNavisionLocationAuthorityReady: () => options.authorityReady !== false,
    sharedVehicleLocationMutationUnavailable: (_action, row) => row?.__emailVehicleServerAuthoritative !== true,
    vehicleKey: row => row.stock || row.id || '',
    displayStockNumber: row => row.stock || '',
    displayVehicle: row => row.vehicle || '',
    consultantName: () => 'AW', vehicleKeyNumber: () => '',
    locationAgeLabel: () => 'SOURCE_ETA_SENTINEL', pmbAgeLabel: () => 'HISTORY_AGE_SENTINEL',
    vehicleWorkshopBookingProjection: () => ({ available: true, bookings: [] }),
    incomingWorkChecklistHtml: () => '<span data-work-checklist>Required work</span>',
    inferredPmbStage: () => '', pmbBaySubletProvider: () => '',
    vehicleReadyForQualityControl: () => false, vehicleCanEnterPit: () => false,
    vehicleWorkshopActivityLabel: () => 'Booked in workshop',
    rftHomeStatus: () => 'ready', rftHomeStatusLabel: () => 'Ready for transport',
    rftTransportControlsHtml: () => '<span data-rft-controls>Transport</span>',
    vehicleIdentityStackHtml: row => `<span data-identity>${row.stock}</span>`,
    partsEtaRisk: () => false, onSiteDaysClass: () => '',
    partsRiskBadge: () => '', vehicleDepartmentBadge: () => '', statusCategoryLabel: () => '',
    escapeHtml: value => String(value ?? '').replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]),
  };
  vm.createContext(ctx);
  const helpers = [
    'cleanNavisionText', 'normalizeToyotaStatus', 'normalizePdcLocation', 'isBlankStock',
    'vehicleHasBatchNumber', 'navisionStatusText', 'vehiclePdcLocation',
    'vehicleCollectedFromRft', 'vehicleInCollectedState', 'navisionImportedToyotaTransitCategory',
    'statusCategory', 'vehicleHasNavisionSource', 'incomingBucketForVehicle',
    'incomingBucketLabel', 'incomingGridStatusLabel', 'canTransferVehicleToPmb',
    'incomingVehicleAge', 'incomingVehicleDetailRow', 'vehicleLocationsScreenRows',
  ];
  vm.runInContext(definitions[0] + '\nthis.bucketDefinitions = VEHICLE_LOCATION_BUCKET_DEFS;\n' + helpers.map(extractFunction).join('\n'), ctx);
  return ctx;
}

test('Non-Navision Vehicles is a separate section between Yard Hold and IT', () => {
  const ctx = setup();
  const keys = Array.from(ctx.bucketDefinitions, item => item.key);
  assert.equal(keys.indexOf('nonnavision'), keys.indexOf('yardhold') + 1);
  assert.equal(keys.indexOf('transit'), keys.indexOf('nonnavision') + 1);
  assert.equal(ctx.incomingBucketLabel('nonnavision'), 'NON-NAVISION VEHICLES');
});

test('Navision source requires an explicit source tag or verified shared record, never descriptive guesses', () => {
  const ctx = setup();
  for (const field of ['source', 'sourceSystem', 'source_system']) {
    for (const value of ['microsoft_navision', 'navision', 'shared navision', '  Microsoft_Navision  ']) {
      assert.equal(ctx.vehicleHasNavisionSource({ [field]: value }), true, `${field}: ${value}`);
    }
  }
  assert.equal(ctx.vehicleHasNavisionSource({ source: 'authenticated_email', __sharedNavisionRecordId: 'record-1' }), true);
  for (const row of [
    {}, { stock: '12657478', dealerCode: 'PMB' }, { vehicle: 'Toyota Navision Hilux', customer: 'Navision dealer' },
    { source: 'non_navision' }, { source: 'Tune import - unmatched Navision' }, { source: 'external' },
    { __sharedNavisionRecordId: '   ' }, { __sharedNavisionReadOnly: true },
    { __sharedNavisionRecordId: 'record-1', __locationIdentityReadOnly: true },
    { navisionLocationStatus: 'Yard Hold', navisionKewdaleEta: '2026-09-15', navisionDealerCode: 'PMB' },
  ]) assert.equal(ctx.vehicleHasNavisionSource(row), false, JSON.stringify(row));
});

test('unmatched external and Tune rows start in the new section with or without descriptions or source statuses', () => {
  const ctx = setup();
  for (const source_system of ['authenticated_email', 'Tune', 'used_vehicle', 'external', '']) {
    for (const vehicle_description of [null, 'Customer supplied Hilux']) {
      for (const current_location of ['YH', 'Other', 'IT']) {
        const row = vehicle({ source_system, vehicle_description, current_location, source_location_status: 'Vehicle In Yard Hold' });
        assert.equal(ctx.incomingBucketForVehicle(row), 'nonnavision', JSON.stringify({ source_system, vehicle_description, current_location }));
      }
    }
  }
});

test('actual Navision rows retain Yard Hold, IT and Other classification', () => {
  const ctx = setup();
  assert.equal(ctx.incomingBucketForVehicle(vehicle({ source_system: 'microsoft_navision', current_location: 'YH' })), 'yardhold');
  assert.equal(ctx.incomingBucketForVehicle(vehicle({ source_system: 'microsoft_navision', current_location: 'IT', source_location_status: 'In Transit', eta_to_kewdale: '2026-09-22' })), 'transit');
  assert.equal(ctx.incomingBucketForVehicle(vehicle({ source_system: 'microsoft_navision', current_location: 'Other' })), 'overseas');
  const unmatched = vehicle({ vehicle_description: null });
  assert.equal(ctx.incomingBucketForVehicle(unmatched), 'nonnavision');
  assert.equal(ctx.incomingBucketForVehicle({ ...unmatched, __sharedNavisionRecordId: 'newly-linked-record' }), 'yardhold', 'later unique Navision reconciliation updates grouping');
  assert.equal(ctx.incomingBucketForVehicle({ ...unmatched, source: 'microsoft_navision' }), 'yardhold', 'later canonical source linkage updates grouping');
  assert.equal(ctx.incomingBucketForVehicle(unmatched), 'nonnavision', 'classifying a merged snapshot never mutates the prior snapshot');
});

test('verified snapshot detail source and record survive mapping and establish the Navision link', () => {
  const ctx = setup();
  const linked = vehicle({ details_source: '  MICROSOFT_NAVISION  ', details_backend_record_id: '  backend-record-42  ' });
  assert.equal(linked.source, 'authenticated_email', 'the original importer source is retained');
  assert.equal(linked.__navisionDetailsSource, 'microsoft_navision');
  assert.equal(linked.__navisionDetailsBackendRecordId, 'backend-record-42');
  assert.equal(linked.__navisionDetailsIdentityConflict, false);
  assert.equal(ctx.vehicleHasNavisionSource(linked), true);
  assert.equal(ctx.incomingBucketForVehicle(linked), 'yardhold');
  for (const partial of [
    { details_source: 'microsoft_navision' },
    { details_source: 'microsoft_navision', details_backend_record_id: '   ' },
    { details_backend_record_id: 'backend-record-42' },
    { details_source: 'tune', details_backend_record_id: 'backend-record-42' },
  ]) {
    const row = vehicle(partial);
    assert.equal(ctx.vehicleHasNavisionSource(row), false, JSON.stringify(partial));
    assert.equal(ctx.incomingBucketForVehicle(row), 'nonnavision');
  }
});

test('snapshot identity-review blocks source classification and PMB action even with other Navision tags', () => {
  const ctx = setup();
  for (const source_system of ['authenticated_email', 'microsoft_navision']) {
    const row = vehicle({ source_system, details_source: '  IDENTITY_REVIEW  ', details_backend_record_id: 'ambiguous-record' });
    row.__sharedNavisionRecordId = 'previous-shared-record';
    assert.equal(row.__navisionDetailsSource, 'identity_review');
    assert.equal(row.__navisionDetailsBackendRecordId, 'ambiguous-record');
    assert.equal(row.__navisionDetailsIdentityConflict, true);
    assert.equal(ctx.vehicleHasNavisionSource(row), false, source_system);
    assert.equal(ctx.incomingBucketForVehicle(row), 'nonnavision');
    assert.equal(ctx.canTransferVehicleToPmb(row), false);
    const html = ctx.incomingVehicleDetailRow(row, 'nonnavision');
    assert.match(html, /Identity conflict/);
    assert.doesNotMatch(html, /data-yh-transfer-pmb=/);
    assert.equal(ctx.incomingBucketForVehicle({ ...row, pdcLocation: 'PMB' }), 'pmb', 'identity review must not move already operational vehicles');
  }
});

test('operational PMB, PIT, QC and RFT take precedence regardless of source and preserve booking and lifecycle data', () => {
  const ctx = setup();
  for (const source_system of ['authenticated_email', 'microsoft_navision']) {
    for (const [current_location, expected] of [['PMB', 'pmb'], ['PIT', 'pit'], ['QC', 'qc'], ['RFT', 'rft']]) {
      const row = vehicle({ source_system, current_location, source_location_status: 'Vehicle In Yard Hold',
        date_to_pmb: '2026-09-11', lifecycle_history: { first_entered_pmb_at: '2026-09-11T00:00:00Z' },
        workshop_bookings: [{ booking_id: 'booking-1', stage_code: 'FITTING', status: 'planned', scheduled_start_at: '2026-09-16T00:00:00Z' }],
      });
      const before = JSON.stringify(row);
      assert.equal(ctx.incomingBucketForVehicle(row), expected);
      assert.equal(ctx.canTransferVehicleToPmb(row), false, `${current_location} cannot be reset to PMB from stale source text`);
      assert.equal(JSON.stringify(row), before, 'grouping and transfer eligibility do not rewrite any booking or lifecycle fields');
    }
  }
  assert.equal(ctx.incomingBucketForVehicle(vehicle({ current_location: 'PMB', qc_completed_at: '2026-09-15T00:00:00Z' })), 'qc');
  const completed = vehicle({ current_location: 'Completed', lifecycle_state: 'completed' });
  const collected = vehicle({ current_location: 'Collected', lifecycle_state: 'collected' });
  assert.equal(ctx.incomingBucketForVehicle(completed), 'completed');
  assert.equal(ctx.vehicleLocationsScreenRows([completed, collected]).length, 0, 'finished vehicles do not reappear in the new active section');
});

test('active canonical non-Navision rows can transfer; protected, conflicted and noncanonical rows cannot', () => {
  const ctx = setup();
  for (const current_location of ['Other', 'YH', 'IT']) {
    assert.equal(ctx.canTransferVehicleToPmb(vehicle({ current_location })), true, current_location);
  }
  for (const change of [
    { __emailVehicleServerAuthoritative: false }, { __locationIdentityReadOnly: true },
    { __emailVehicleId: '' }, { pdcSheetVisible: false }, { deleted_at: '2026-09-15' },
    { lifecycleState: 'collected', pdcLifecycleState: 'collected' },
    { lifecycleState: 'completed', pdcLifecycleState: 'completed' },
  ]) assert.equal(ctx.canTransferVehicleToPmb({ ...vehicle({ current_location: 'Other' }), ...change }), false, JSON.stringify(change));
});

test('explicit operational locations remain protected for canonical vehicles without a stock number', () => {
  const ctx = setup();
  for (const current_location of ['PMB', 'PIT', 'QC', 'RFT']) {
    const row = vehicle({ stock_number: null, current_location, source_location_status: 'Vehicle In Yard Hold' });
    assert.equal(row.stock, '');
    assert.equal(ctx.incomingBucketForVehicle(row), current_location.toLowerCase(), current_location);
    assert.equal(ctx.canTransferVehicleToPmb(row), false, current_location);
  }
  assert.equal(ctx.incomingBucketForVehicle(vehicle({ stock_number: null, current_location: 'PMB', qc_completed_at: '2026-09-15T00:00:00Z' })), 'qc');
});

test('new section rows show Location unconfirmed and existing To PMB/Open controls without ETA or age guesses', () => {
  const ctx = setup();
  const row = vehicle({ current_location: 'Other', vehicle_description: null });
  assert.equal(ctx.incomingGridStatusLabel(row, 'nonnavision'), 'Location unconfirmed');
  const html = ctx.incomingVehicleDetailRow(row, 'nonnavision');
  const summary = html.slice(html.indexOf('<summary'), html.indexOf('</summary>'));
  assert.match(html, /incoming-nonnavision-row/);
  assert.match(summary, /Location unconfirmed/);
  assert.match(summary, /data-yh-transfer-pmb="12657478"[^>]*>To PMB<\/button>/);
  assert.match(summary, /data-open-stock="12657478"[^>]*>Open<\/button>/);
  assert.match(summary, /data-work-checklist/);
  assert.doesNotMatch(summary, /SOURCE_ETA_SENTINEL|HISTORY_AGE_SENTINEL|<b>ETA<\/b>|<b>YH<\/b>/);
  assert.match(summary, /incoming-card-age/);
  assert.match(summary, /incoming-card-status/);
  assert.match(summary, /incoming-card-action/);
});

test('new section does not display a PMB transfer action while identity or shared authority is unavailable', () => {
  for (const [options, row] of [
    [{ authorityReady: false }, vehicle()],
    [{}, { ...vehicle(), __locationIdentityReadOnly: true }],
    [{}, { ...vehicle(), __emailVehicleServerAuthoritative: false }],
  ]) {
    const ctx = setup(options);
    const html = ctx.incomingVehicleDetailRow(row, 'nonnavision');
    assert.doesNotMatch(html, /data-yh-transfer-pmb=/);
  }
});

test('the existing transfer action sends canonical ID/version and regroups only after server success', async () => {
  for (const succeeds of [true, false]) {
    const ctx = setup();
    const row = vehicle({ current_location: 'Other', workshop_bookings: [{ booking_id: 'existing-booking', status: 'planned', stage_code: 'FITTING' }] });
    const bookingsBefore = JSON.stringify(row.salesWorkshopBookings);
    const calls = [], alerts = [];
    let refreshes = 0;
    Object.assign(ctx, {
      selectedVehicle: () => row,
      vehicleLocationActionAllowed: () => true,
      vehicleCustomerName: item => item.client,
      reconcileVehicleLifecycleServerResult: (item, result) => Object.assign(item, result.vehicle),
      refreshEmailVehicleLocations: async () => { refreshes++; },
      renderAll: () => {},
    });
    ctx.window.confirm = () => true;
    ctx.window.alert = message => alerts.push(message);
    ctx.window.__vehicleLifecycleActions = { pmbTransferVehicle: async payload => {
      calls.push(JSON.parse(JSON.stringify(payload)));
      assert.equal(ctx.incomingBucketForVehicle(row), 'nonnavision', 'there is no optimistic move before the server responds');
      return succeeds ? { ok: true, vehicle: { ...row, pdcLocation: 'PMB', __emailVehicleVersion: 4 } } : { ok: false, error: 'vehicle_version_conflict' };
    } };
    vm.runInContext('async ' + extractFunction('transferYhVehicleToPmb'), ctx);
    const result = await ctx.transferYhVehicleToPmb(row.stock);
    assert.equal(result, succeeds);
    assert.deepEqual(calls, [{ vehicleId, expectedVersion: 3 }]);
    assert.equal(ctx.incomingBucketForVehicle(row), succeeds ? 'pmb' : 'nonnavision');
    assert.equal(alerts.length, succeeds ? 0 : 1);
    assert.equal(refreshes, 1);
    assert.equal(JSON.stringify(row.salesWorkshopBookings), bookingsBefore, 'the presentation transfer route does not rewrite bookings');
  }
});

