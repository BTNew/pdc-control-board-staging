'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = process.env.PDC_LOCATION_MERGE_TEST_ROOT || process.cwd();
const source = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const emailModule = require(path.join(root, 'pdc-email-vehicle-location-service.js'));
const id = '10000000-0000-4000-8000-000000000001';

function sourceFunction(name) {
  const start = source.search(new RegExp(`(?:async )?function ${name}\\(`));
  assert.ok(start >= 0, `${name} exists`);
  const next = source.slice(start + 1).search(/\n(?:async )?function /);
  assert.ok(next >= 0, `${name} has a following function`);
  return source.slice(start, start + next + 1);
}
function snapshot(patch = {}) {
  return { id, permanent_vehicle_id: 'MERGE-QC-FIXTURE', stock_number: 'MERGE-QC-FIXTURE',
    version: 12, current_location: 'QC', lifecycle_state: 'active', visible_on_board: true,
    qc_completed_at: null, rft_transferred_at: null, source_system: 'tune_pmg',
    ...patch };
}
function navision(patch = {}) {
  return { id: 'navision-fixture', canonical_vehicle_id: id, stock_number: 'MERGE-QC-FIXTURE',
    is_current: true, board_activated: true, dealer_code: '37047',
    current_location: 'RFT', lifecycle_state: 'rft', vehicle_status: 'Source status',
    eta_to_kewdale: '2026-09-17', ...patch };
}
function harness(serverRows = [snapshot()], localRows = [], sharedRows = [navision()]) {
  const ctx = {
    app: { emailVehicleLocationRows: serverRows, sharedNavisionVisibleRows: sharedRows },
    window: { PDC_EMAIL_VEHICLE_LOCATION_SERVICE: emailModule },
    pdcSheetVehicles: () => localRows,
    applyPendingSharedWorkStateOverlays: rows => rows,
    applySharedWorkStateCache: rows => rows,
    vehicleKey: row => row.stock || row.id,
    isBlankStock: stock => !String(stock || '').trim(),
    currentPdcLocationFromNavision: () => 'YH',
    Map, Set,
  };
  vm.createContext(ctx);
  ['normalizePdcLocation', 'vehiclePdcLocation', 'vehicleCollectedFromRft', 'vehicleInCollectedState',
    'vehicleHasBatchNumber', 'statusCategory', 'vehicleHasNavisionSource', 'incomingBucketForVehicle',
    'vehicleLocationsScreenRows', 'cleanNavisionText', 'sharedNavisionIdentityToken',
    'sharedNavisionItemIdentityKeys', 'vehicleSharedNavisionIdentityKeys', 'sharedNavisionLocationVehicle',
    'sharedNavisionIdentityPartsFromItem', 'sharedNavisionIdentityPartsFromVehicle',
    'localLocationIdentitySignature', 'deduplicateLocalLocationRows', 'activeSharedNavisionRows',
    'vehicleLocationBoardRows'].forEach(name => vm.runInContext(sourceFunction(name), ctx));
  return ctx;
}

test('fresh canonical QC wins over a stale Navision RFT projection without losing source metadata', () => {
  const h = harness(), rows = h.vehicleLocationBoardRows();
  assert.equal(rows.length, 1);
  assert.equal(rows[0].pdcLocation, 'QC');
  assert.equal(rows[0].__sharedNavisionCanonicalLocation, 'QC');
  assert.equal(rows[0].pdcQcComplete, false);
  assert.equal(rows[0].rftTransferredAt, '');
  assert.equal(rows[0].toyotaStatus, 'Source status');
  assert.equal(rows[0].etaAtDealer, '2026-09-17');
  assert.equal(h.incomingBucketForVehicle(rows[0]), 'qc');
  assert.equal(h.vehicleLocationsScreenRows().length, 1);
});

test('QC rejection and subsequent station work stay in canonical PMB despite stale QC/RFT', () => {
  for (const oldLocation of ['QC', 'RFT']) {
    const h = harness([snapshot({ current_location: 'PMB', pmb_stage: 'FITTING',
      workshop_status: 'stoppage', pmb_stoppage_started_at: '2026-09-15T06:30:00Z' })], [],
    [navision({ current_location: oldLocation })]);
    const row = h.vehicleLocationBoardRows()[0];
    assert.equal(row.pdcLocation, 'PMB');
    assert.equal(row.__sharedNavisionCanonicalLocation, 'PMB');
    assert.equal(row.pmbStage, 'FITTING');
    assert.equal(row.workshopStatus, 'stoppage');
    assert.equal(h.incomingBucketForVehicle(row), 'pmb');
  }
});

test('authoritative location override retains precedence over both canonical automatic and Navision location', () => {
  const h = harness([snapshot({ current_location: 'YH', location_override: 'PMB' })]);
  assert.equal(h.vehicleLocationBoardRows()[0].pdcLocation, 'PMB');
});

test('legitimate RFT stays visible and completed or collected vehicles remain outside active locations', () => {
  const rft = harness([snapshot({ current_location: 'RFT', lifecycle_state: 'rft',
    qc_completed_at: '2026-09-15T06:00:00Z', rft_transferred_at: '2026-09-15T06:01:00Z' })], [],
  [navision({ current_location: 'QC', lifecycle_state: 'active' })]);
  assert.equal(rft.incomingBucketForVehicle(rft.vehicleLocationBoardRows()[0]), 'rft');
  assert.equal(rft.vehicleLocationsScreenRows().length, 1);
  for (const [location, lifecycle] of [['Completed', 'completed'], ['Collected', 'collected']]) {
    const h = harness([snapshot({ current_location: location, lifecycle_state: lifecycle })]);
    assert.equal(h.vehicleLocationBoardRows()[0].pdcLocation, location);
    assert.equal(h.vehicleLocationsScreenRows().length, 0);
  }
});

test('stale Navision completion cannot hide an active canonical QC vehicle', () => {
  const h = harness([snapshot()], [], [navision({ current_location: 'Completed', lifecycle_state: 'completed' })]);
  const row = h.vehicleLocationBoardRows()[0];
  assert.equal(row.completedVehicle, false);
  assert.equal(h.incomingBucketForVehicle(row), 'qc');
  assert.equal(h.vehicleLocationsScreenRows().length, 1);
});

test('legacy and work-cache-only identities still use the Navision operating location', () => {
  for (const flags of [{}, { __emailVehicleServerAuthoritative: true, __emailVehicleId: id, __emailVehicleVersion: 12 }]) {
    const h = harness([], [{ stock: 'MERGE-QC-FIXTURE', pdcLocation: 'QC', ...flags }]);
    assert.equal(h.vehicleLocationBoardRows()[0].pdcLocation, 'RFT');
  }
  const sharedOnly = harness([], [], [navision({ current_location: 'YH', lifecycle_state: 'active' })]);
  const row = sharedOnly.vehicleLocationBoardRows()[0];
  assert.equal(row.pdcLocation, 'YH');
  assert.equal(row.__sharedNavisionReadOnly, true);
});

test('invalid or incomplete snapshots cannot establish operational location authority', () => {
  for (const patch of [{ id: '' }, { id: 'not-a-canonical-id' }, { version: 0 }, { version: 1.5 },
    { current_location: '' }, { current_location: 'unrecognized' }, { location_override: 'unrecognized' }]) {
    const raw = snapshot(patch);
    assert.equal(emailModule.mapServerVehicle(raw).__emailVehicleLocationAuthoritative, false);
    assert.equal(harness([raw]).vehicleLocationBoardRows()[0].pdcLocation, 'RFT');
  }
});

test('duplicate Navision matches and dealer conflicts remain read-only rather than bypassing identity checks', () => {
  const duplicate = harness([snapshot()], [], [navision(), navision({ id: 'second-record', vehicle_status: 'Different status' })]);
  const row = duplicate.vehicleLocationBoardRows().find(row => row.__emailVehicleId === id);
  assert.equal(row.__locationIdentityReadOnly, true);
  assert.equal(row.__sharedNavisionRecordId, undefined);
  const conflict = harness([snapshot()], [{ stock: 'MERGE-QC-FIXTURE', dealer_code: '14450' }]);
  const conflictRow = conflict.vehicleLocationBoardRows().find(row => row.__emailVehicleId === id);
  assert.equal(conflictRow.__locationIdentityReadOnly, true);
});
