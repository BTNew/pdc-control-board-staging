'use strict';

// Real (non-mocked) tests for the shared-data integration seam added to
// workshop-planner.js: workshopSharedModeActive(), snapshot-row mapping,
// and the connection banner. These prove the planner (a) stays inert by
// default (no window.__workshopDataService => local behaviour unchanged)
// and (b) correctly maps get_workshop_snapshot() bookings into the same
// legacy row shape the rest of the file already renders/interacts with,
// without needing any changes to that rendering/interaction code.

const assert = require('assert');

// workshop-planner.js expects several app.js globals to exist (it is a
// non-module script loaded alongside app.js in the browser). Stub the
// minimum set needed for the functions under test, matching the pattern
// already used by test_workshop_planner.js.
global.normalizePmbStage = value => String(value || '').toUpperCase();
global.escapeHtml = value => String(value == null ? '' : value)
  .replace(/&/g, '&amp;')
  .replace(/</g, '&lt;')
  .replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;');
global.parseIsoTimestamp = value => {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
};
global.nowIsoString = () => new Date(2026, 6, 14, 10, 0, 0, 0).toISOString();
global.pmbStageLabel = value => String(value || '');
global.cleanNavisionText = value => String(value == null ? '' : value).trim();

const planner = require('./workshop-planner.js');

function withGlobals(overrides, fn) {
  const originalWindow = global.window;
  global.window = Object.assign({}, originalWindow, overrides);
  try {
    fn();
  } finally {
    global.window = originalWindow;
  }
}

function completeConfigurationRows(overrides = {}) {
  return {
    day_start_time: { value: '08:00' },
    day_end_time: { value: '16:00' },
    scheduling_increment_minutes: { value: 15 },
    default_booking_duration_minutes: { value: 180 },
    working_week: { value: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'] },
    closures: { value: [] },
    break_windows: { value: [] },
    overtime_windows: { value: [] },
    technician_leave: { value: [] },
    ...overrides,
  };
}

// 1. No window at all (Node test context, no shared globals defined):
//    workshopSharedModeActive() must return a falsy value, never throw.
{
  const originalWindow = global.window;
  delete global.window;
  let result;
  let threw = false;
  try {
    result = planner.workshopSharedModeActive();
  } catch (_err) {
    threw = true;
  }
  global.window = originalWindow;
  assert.strictEqual(threw, false, '1a workshopSharedModeActive must not throw when window is undefined');
  assert.ok(!result, '1b workshopSharedModeActive is falsy with no window/config at all');
  console.log('PASS 1: workshopSharedModeActive is safe and inert with no browser globals');
}

// 2. window present, but PDC_SUPABASE_CONFIG missing / sharedData not true:
//    still inactive regardless of a present data service instance.
{
  withGlobals({
    workshopSharedModeEnabled: (cfg) => !!(cfg && cfg.workshop && cfg.workshop.sharedData === true),
    PDC_SUPABASE_CONFIG: {},
    __workshopDataService: { isEnabled: () => true }
  }, () => {
    assert.strictEqual(planner.workshopSharedModeActive(), false, '2a shared mode inactive without explicit opt-in, even if a service instance exists');
  });
  console.log('PASS 2: shared mode requires explicit config opt-in, not just service presence');
}

// 3. Fully enabled + service reports isEnabled() true => active
{
  withGlobals({
    workshopSharedModeEnabled: (cfg) => !!(cfg && cfg.workshop && cfg.workshop.sharedData === true),
    PDC_SUPABASE_CONFIG: { workshop: { sharedData: true } },
    __workshopDataService: { isEnabled: () => true }
  }, () => {
    assert.strictEqual(planner.workshopSharedModeActive(), true, '3a shared mode active when opted in and service reports enabled');
  });
  console.log('PASS 3: shared mode active only when config opts in AND the service instance itself is enabled');
}

// 4. Snapshot booking -> legacy row mapping preserves every field the
//    existing renderer/interaction code depends on (id, vehicleKey, stage,
//    bay, startAt, hours, assignee, status, stoppage fields).
{
  const booking = {
    booking_id: 'b-123',
    version: 4,
    vehicle: { id: 'veh-123', stock_number: 'STK-999', permanent_vehicle_id: 'perm-1' },
    stage: { code: 'HOIST' },
    bay: { bay_number: 2 },
    status: 'started',
    scheduled_start_at: '2026-07-20T01:00:00.000Z',
    default_duration_minutes: 180,
    assignment: { technician_name: 'Alex' },
    stoppage_reason: null,
    stoppage_started_at: null,
    stoppage_accumulated_minutes: 0,
    actual_duration_minutes: null,
    actual_end_at: null,
    created_at: '2026-07-19T00:00:00.000Z',
    updated_at: '2026-07-20T01:05:00.000Z',
  };
  const row = planner.workshopMapSnapshotBookingToLegacyRow(booking);
  assert.strictEqual(row.id, 'b-123', '4a booking_id becomes the legacy row id');
  assert.strictEqual(row.sharedBookingId, 'b-123', '4b sharedBookingId retained for future write-path use');
  assert.strictEqual(row.sharedVersion, 4, '4c version retained for future optimistic-lock writes');
  assert.strictEqual(row.vehicleKey, 'STK-999', '4d vehicle key resolves from stock_number');
  assert.strictEqual(row.sharedVehicleId, 'veh-123', '4e stable shared vehicle UUID survives the legacy adapter');
  assert.strictEqual(row.stage, 'HOIST', '4e stage code preserved');
  assert.strictEqual(row.bay, 2, '4f bay number preserved as a number');
  assert.strictEqual(row.hours, 3, '4g 180 minutes maps to 3 hours');
  assert.strictEqual(row.assignee, 'Alex', '4h technician name maps to legacy assignee field');
  assert.strictEqual(row.status, 'started', '4i status maps through the legacy status vocabulary');
  const minimal = planner.workshopMapSnapshotBookingToLegacyRow({
    ...booking,
    vehicle_id: 'veh-123',
    vehicle: undefined,
  }, new Map([['veh-123', { id: 'veh-123', stock_number: 'STK-999' }]]));
  assert.strictEqual(minimal.vehicleKey, 'STK-999', '4j migration-044 minimal booking DTO resolves display identity from separately scoped vehicles');
  assert.ok(minimal.id && minimal.vehicleKey && minimal.sharedVehicleId, '4k production-shaped minimal DTO survives planner filtering');
  console.log('PASS 4: snapshot booking DTO maps cleanly onto the existing legacy row shape');
}

// 5. Vehicle with no stock_number falls back to permanent_vehicle_id
{
  const booking = {
    booking_id: 'b-456',
    vehicle: { id: 'veh-456', stock_number: '', permanent_vehicle_id: 'perm-2' },
    stage: { code: 'FITTING' },
    bay: null,
    status: 'queued',
    scheduled_start_at: '2026-07-21T01:00:00.000Z',
    default_duration_minutes: 60,
  };
  const row = planner.workshopMapSnapshotBookingToLegacyRow(booking);
  assert.strictEqual(row.vehicleKey, 'perm-2', '5a falls back to permanent_vehicle_id when stock_number is blank');
  assert.strictEqual(row.bay, 0, '5b missing bay (e.g. Sublet provider row) maps to 0, not null/NaN');
  assert.strictEqual(row.status, 'planned', "5c 'queued' status maps to legacy 'planned'");
  console.log('PASS 5: vehicle-identity fallback and null-bay/queued-status mapping are correct');
}

// 6. A booking with no booking_id or stable vehicle UUID is rejected (never
//    silently mapped to a garbage/unstable row).
{
  const row = planner.workshopMapSnapshotBookingToLegacyRow({});
  assert.strictEqual(row, null, '6a booking with no booking_id maps to null, filtered out by callers');
  const missingVehicleId = planner.workshopMapSnapshotBookingToLegacyRow({
    booking_id: 'b-no-vehicle-uuid',
    vehicle: { stock_number: 'STK-WEAK', permanent_vehicle_id: 'perm-weak' },
    stage: { code: 'HOIST' },
  });
  assert.strictEqual(missingVehicleId, null, '6b shared booking without a stable vehicle UUID is rejected');
  console.log('PASS 6: malformed/incomplete snapshot bookings and missing vehicle UUIDs are rejected');
}

// 7. Connection banner renders distinct, human-readable text per state and
//    escapes any state string safely (no raw HTML injection risk even
//    though state values are backend-controlled constants today).
{
  const states = {
    CONNECTED_EDITABLE: 'connected_editable',
    CONNECTED_READ_ONLY: 'connected_read_only',
    RECONNECTING: 'reconnecting',
    OFFLINE_READ_ONLY: 'offline_read_only',
    INCOMPATIBLE: 'incompatible',
    PERMISSION_DENIED: 'permission_denied',
    CONNECTING: 'connecting',
  };
  withGlobals({
    WORKSHOP_CONNECTION_STATE: states,
    __workshopDataService: { getState: () => states.CONNECTED_READ_ONLY }
  }, () => {
    const html = planner.workshopConnectionBannerHtml();
    assert.ok(html.includes('read-only'), '7a connected_read_only banner mentions read-only');
    assert.ok(html.includes('workshop-connection-warn'), '7b connected_read_only uses the warn style class');
  });
  withGlobals({
    WORKSHOP_CONNECTION_STATE: states,
    __workshopDataService: { getState: () => states.OFFLINE_READ_ONLY }
  }, () => {
    const html = planner.workshopConnectionBannerHtml();
    assert.ok(html.includes('Offline'), '7c offline state banner says Offline');
    assert.ok(html.includes('workshop-connection-error'), '7d offline state uses the error style class');
  });
  withGlobals({
    WORKSHOP_CONNECTION_STATE: states,
    __workshopDataService: { getState: () => states.CONNECTED_EDITABLE }
  }, () => {
    const html = planner.workshopConnectionBannerHtml();
    assert.ok(html.includes('workshop-connection-ok'), '7e editable state uses the ok style class');
  });
  withGlobals({
    WORKSHOP_CONNECTION_STATE: states,
    __workshopDataService: { getState: () => states.PERMISSION_DENIED }
  }, () => {
    const banner = planner.workshopConnectionBannerHtml();
    assert.ok(banner.includes('Access denied'), '7f permission_denied has explicit access-denied copy');
    assert.ok(banner.includes('workshop-connection-error'), '7g permission_denied uses the error style class');
    assert.ok(!banner.includes('status unknown'), '7h permission_denied never falls through to unknown status');
    const emptyState = planner.workshopStationSnapshotEmptyStateHtml('BUS_4X4');
    assert.ok(emptyState.includes('Workshop Planner access unavailable'), '7i denied route renders a terminal unavailable state');
    assert.ok(emptyState.includes('does not have permission'), '7j denied route explains the permission boundary');
    assert.ok(!emptyState.includes('Waiting for the selected station snapshot'), '7k denied route never hangs on loading copy');
    assert.ok(!emptyState.includes('workshop-station-loading'), '7l denied route is not marked as loading');
  });
  console.log('PASS 7: connection banner renders a distinct, styled message per connection state');
}

console.log('Workshop planner shared-mode integration seam checks passed');

// 8. A rendered outstanding candidate must retain the same authoritative
// scheduling decision when the click handler resolves it again by stock.
// Losing this projection made enabled Schedule/Best slot buttons fail with
// the generic "Current shared Workshop authority" alert.
{
  const vehicleId = '11111111-2222-4333-8444-555555555555';
  const snapshot = {
    vehicles: [{ id: vehicleId, stock_number: '12664966', current_location: 'PMB', version: 7 }],
    work_items: [{ vehicle_id: vehicleId, work_key: 'fabrication', required: true, completed: false }],
    outstanding_candidates: [{ vehicle_id: vehicleId, stage_code: 'FABRICATION', existing_booking: false, schedule_enabled: true, disabled_reason: '' }],
  };
  withGlobals({
    workshopSharedModeEnabled: cfg => !!(cfg && cfg.workshop && cfg.workshop.sharedData === true),
    PDC_SUPABASE_CONFIG: { workshop: { sharedData: true } },
    __activeWorkshopPlannerStage: 'FABRICATION',
    __workshopDataService: { isEnabled: () => true, getLastSnapshot: () => snapshot },
  }, () => {
    const row = planner.workshopVehicle('12664966', 'FABRICATION');
    assert.ok(row, '8a authoritative candidate resolves by stock');
    assert.strictEqual(row.id, vehicleId, '8b canonical vehicle UUID is retained');
    assert.deepStrictEqual(row.__workshopOutstanding, {
      existingBooking: false,
      scheduleEnabled: true,
      disabledReason: '',
    }, '8c click-time lookup retains the authoritative scheduling projection');
  });
  console.log('PASS 8: click-time vehicle lookup retains shared scheduling authority');
}

// --- Section 14 error mapping: never a raw stack trace / DB error ---

{
  const cases = [
    ['version_conflict', 'changed by another user'],
    ['bay_overlap', 'bay is already occupied'],
    ['technician_overlap', 'already assigned to another booking'],
    ['vehicle_overlap', 'back-to-back or non-overlapping'],
    ['parts_incomplete', 'Parts requirements are incomplete'],
    ['permission_denied', 'do not have permission'],
    ['authority_superseded', 'session changed'],
    ['destroyed', 'session changed'],
    ['missing_expected_version', 'missing required version'],
    ['minimum_duration', 'at least 60 minutes'],
    ['calendar_unavailable', 'configured Workshop calendar'],
    ['calendar_duration_mismatch', 'configured Workshop operating minutes'],
    ['invalid_schedule_interval', 'configured Workshop operating minutes'],
    ['vehicle_inactive_or_missing', 'vehicle is inactive'],
    ['station_inactive_or_missing', 'station is inactive'],
    ['location_ineligible', 'location is not eligible'],
    ['active_booking_exists', 'active booking already represents'],
    ['vehicle_not_eligible_for_station', 'no longer has an outstanding requirement'],
    ['missing_eta', 'valid ETA to Kewdale'],
    ['it_eta_missing', 'valid ETA to Kewdale'],
    ['it_before_eta', 'before its ETA to Kewdale'],
    ['canonical_requirement_missing_or_completed', 'no incomplete canonical requirement'],
    ['bay_inactive_or_wrong_station', 'active bay'],
    ['technician_inactive_or_missing', 'active Workshop technician'],
    ['technician_leave_conflict', 'technician is on leave'],
    ['totally_unmapped_backend_error_code', 'server rejected this change'],
  ];
  for (const [error, expectedSubstring] of cases) {
    const message = planner.workshopDescribeSharedActionError({ ok: false, error });
    assert.ok(
      message.toLowerCase().includes(expectedSubstring.toLowerCase()),
      `error '${error}' should map to a message containing '${expectedSubstring}', got: '${message}'`
    );
    assert.ok(!/postgres|pg_|relation "|null value in column|constraint/i.test(message), `error '${error}' message must never leak a raw DB error string`);
  }
  console.log('PASS 8: every mapped and unmapped backend error produces a clear, non-technical message');
}

// 9. Note: workshopDispatchSharedAction() itself is not exported directly
// (it's an internal dispatch helper used inside each action function), but
// its gating condition is exactly workshopSharedModeActive(), which IS
// exported and already covered by tests 1-3 above -- when shared mode is
// inactive, every action function's existing legacy code path runs
// completely untouched (proven by the unchanged-behaviour browser smoke
// test recorded in this stage's commit message). The full guarded
// lifecycle (start/stop/resume/complete/return-to-queue, real version
// enforcement, real conflict rejection) is exercised end-to-end against
// live staging RPCs in _staging_test_tools/test_workshop_staging_integration.py
// and the manual staging RPC chain recorded in this session, not re-mocked
// here.

// 10. workshopSharedVehicleRef: resolves a vehicle key to its shared
// Supabase id + version from the last snapshot, using the same
// stock_number-then-permanent_vehicle_id fallback as
// workshopMapSnapshotBookingToLegacyRow. Never fabricates an id -- returns
// null on no match or when shared mode is inactive.
{
  withGlobals({}, () => {
    assert.strictEqual(planner.workshopSharedVehicleRef('STK-1'), null, '10a returns null when shared mode is inactive, never guesses');
  });
  const snapshot = { vehicles: [
    { id: 'veh-a', stock_number: 'STK-1', permanent_vehicle_id: 'perm-1', version: 5 },
    { id: 'veh-b', stock_number: '', permanent_vehicle_id: 'perm-2', version: 9 },
  ] };
  withGlobals({
    workshopSharedModeEnabled: () => true,
    PDC_SUPABASE_CONFIG: { workshop: { sharedData: true } },
    __workshopDataService: { isEnabled: () => true, getLastSnapshot: () => snapshot },
  }, () => {
    assert.deepStrictEqual(planner.workshopSharedVehicleRef('STK-1'), { vehicleId: 'veh-a', version: 5 }, '10b resolves one unique stock_number');
    assert.deepStrictEqual(planner.workshopSharedVehicleRef('perm-2'), { vehicleId: 'veh-b', version: 9 }, '10c resolves one unique permanent_vehicle_id');
    assert.deepStrictEqual(
      planner.workshopSharedVehicleRef('STK-NOT-IN-SNAPSHOT'),
      { ok: false, error: 'vehicle_identity_not_found', requestedVehicleId: '', requestedLegacyKey: 'STK-NOT-IN-SNAPSHOT', candidateVehicleIds: [] },
      '10d missing legacy identity returns a reviewable error, never a fabricated ref'
    );
  });
  console.log('PASS 10: workshopSharedVehicleRef resolves unique snapshot identity and reports missing identity');
}

// 10e-10g. Legacy reverse lookup must inspect every candidate. Duplicate keys
// are ambiguous, and a supplied stable UUID that disagrees with a legacy key
// is a conflict. Neither case may silently choose the first array element.
{
  const snapshot = { vehicles: [
    { id: 'veh-a', stock_number: 'DUP-1', permanent_vehicle_id: 'perm-a', version: 2 },
    { id: 'veh-b', stock_number: 'd up-1', permanent_vehicle_id: 'perm-b', version: 3 },
    { id: 'veh-c', stock_number: 'STK-C', permanent_vehicle_id: 'perm-c', version: 4 },
  ] };
  withGlobals({
    workshopSharedModeEnabled: () => true,
    PDC_SUPABASE_CONFIG: { workshop: { sharedData: true } },
    __workshopDataService: { isEnabled: () => true, getLastSnapshot: () => snapshot },
  }, () => {
    assert.deepStrictEqual(
      planner.workshopSharedVehicleRef('DUP-1'),
      { ok: false, error: 'ambiguous_vehicle_identity', requestedVehicleId: '', requestedLegacyKey: 'DUP-1', candidateVehicleIds: ['veh-a', 'veh-b'] },
      '10e duplicate legacy key is refused with every candidate UUID'
    );
    assert.deepStrictEqual(
      planner.workshopSharedVehicleRef({ sharedVehicleId: 'veh-c', vehicleKey: 'DUP-1' }),
      { ok: false, error: 'conflicting_vehicle_identity', requestedVehicleId: 'veh-c', requestedLegacyKey: 'DUP-1', candidateVehicleIds: ['veh-a', 'veh-b', 'veh-c'] },
      '10f conflicting stable UUID and legacy key is refused for review'
    );
    assert.deepStrictEqual(
      planner.workshopSharedVehicleRef({ sharedVehicleId: 'veh-c', vehicleKey: 'STK-C' }),
      { vehicleId: 'veh-c', version: 4 },
      '10g matching stable UUID and legacy key retains the stable UUID'
    );
    assert.deepStrictEqual(
      planner.workshopSharedVehicleRef({ sharedVehicleId: 'veh-missing', vehicleKey: 'STK-C' }),
      { ok: false, error: 'conflicting_vehicle_identity', requestedVehicleId: 'veh-missing', requestedLegacyKey: 'STK-C', candidateVehicleIds: ['veh-c'] },
      '10h stale/missing UUID that points by legacy key to another vehicle is a conflict, not a fallback match'
    );
  });
  console.log('PASS 10e-h: duplicate, missing and conflicting legacy vehicle identities fail closed');
}

// 11. workshopSharedTechnicianRef: resolves a legacy free-text assignee
// name to a technician id by scanning bookings/assignments already
// present in the snapshot (the snapshot has no standalone technician
// list). Never fabricates an id for an unmatched name.
{
  withGlobals({}, () => {
    assert.strictEqual(planner.workshopSharedTechnicianRef('Alex'), null, '11a returns null when shared mode is inactive');
  });
  const snapshot = {
    bookings: [
      { assignment: { technician_id: 'tech-alex', technician_name: 'Alex' } },
      { assignment: null },
    ],
    active_stoppages: [
      { assignment: { technician_id: 'tech-beta', technician_name: 'Beta' } },
    ],
  };
  withGlobals({
    workshopSharedModeEnabled: () => true,
    PDC_SUPABASE_CONFIG: { workshop: { sharedData: true } },
    __workshopDataService: { isEnabled: () => true, getLastSnapshot: () => snapshot },
  }, () => {
    assert.deepStrictEqual(planner.workshopSharedTechnicianRef('Alex'), { technicianId: 'tech-alex' }, '11b resolves from the bookings list');
    assert.deepStrictEqual(planner.workshopSharedTechnicianRef('Beta'), { technicianId: 'tech-beta' }, '11c resolves from the active_stoppages list too');
    assert.strictEqual(planner.workshopSharedTechnicianRef('Nobody'), null, '11d unmatched name returns null, never fabricated');
    assert.strictEqual(planner.workshopSharedTechnicianRef(''), null, '11e blank name returns null without scanning');
  });
  console.log('PASS 11: workshopSharedTechnicianRef resolves technician identity from booking assignments only, never fabricates');
}

// 12. workshopOtherDepartmentOverlaps / workshopConfirmOtherDepartmentPlans:
// real time-overlap detection, not "any other department booking exists".
// Uses real module execution against workshopEntryStart/End (which apply
// the actual workshop-day normalization), not string matching.
{
  const fitting0800to1100 = { id: 'p1', vehicleKey: 'V1', stage: 'FITTING', bay: 1, startAt: new Date(2026, 6, 17, 8, 0, 0, 0).toISOString(), hours: 3, status: 'planned' };
  const tint1100to1300 = { id: 'p2', vehicleKey: 'V1', stage: 'TINT', bay: 1, startAt: new Date(2026, 6, 17, 11, 0, 0, 0).toISOString(), hours: 2, status: 'planned' };
  const tint1000to1200 = { id: 'p3', vehicleKey: 'V1', stage: 'TINT', bay: 1, startAt: new Date(2026, 6, 17, 10, 0, 0, 0).toISOString(), hours: 2, status: 'planned' };
  const tintTomorrow = { id: 'p4', vehicleKey: 'V1', stage: 'TINT', bay: 1, startAt: new Date(2026, 6, 20, 8, 0, 0, 0).toISOString(), hours: 2, status: 'planned' };
  const sameStage0900 = { id: 'p5', vehicleKey: 'V1', stage: 'FITTING', bay: 2, startAt: new Date(2026, 6, 17, 9, 0, 0, 0).toISOString(), hours: 2, status: 'planned' };
  const otherVehicleOverlap = { id: 'p6', vehicleKey: 'V2', stage: 'TINT', bay: 1, startAt: new Date(2026, 6, 17, 9, 0, 0, 0).toISOString(), hours: 2, status: 'planned' };
  const startedFitting = { ...fitting0800to1100, id: 'p7', status: 'started' };

  // 12a: sequential, back-to-back bookings in different departments must
  // never be flagged as overlapping.
  assert.deepStrictEqual(
    planner.workshopOtherDepartmentOverlaps(fitting0800to1100, [fitting0800to1100, tint1100to1300]),
    [],
    '12a Fitting 8-11 and Tint 11-1 must not be treated as overlapping (back-to-back is valid)',
  );

  // 12b: genuinely overlapping windows in different departments must be
  // detected and returned.
  const overlaps = planner.workshopOtherDepartmentOverlaps(fitting0800to1100, [fitting0800to1100, tint1000to1200]);
  assert.strictEqual(overlaps.length, 1, '12b Fitting 8-11 and Tint 10-12 must be detected as a real overlap');
  assert.strictEqual(overlaps[0].id, 'p3', '12b overlap result must identify the exact conflicting booking');

  // 12c: a booking on a different day must never trigger today's warning.
  assert.deepStrictEqual(
    planner.workshopOtherDepartmentOverlaps(fitting0800to1100, [fitting0800to1100, tintTomorrow]),
    [],
    '12c a booking tomorrow in another department must not warn for today',
  );

  // 12d: the vehicle invariant also applies across two bays in the same stage.
  assert.strictEqual(
    planner.workshopOtherDepartmentOverlaps(fitting0800to1100, [fitting0800to1100, sameStage0900]).length,
    1,
    '12d same-vehicle overlap in another bay of the same stage must be rejected',
  );

  // 12e: a different vehicle's overlapping booking must never be reported
  // against this vehicle's candidate.
  assert.deepStrictEqual(
    planner.workshopOtherDepartmentOverlaps(fitting0800to1100, [fitting0800to1100, otherVehicleOverlap]),
    [],
    '12e another vehicle\'s overlapping booking must not be attributed to this vehicle',
  );

  // 12f: valid sequential work proceeds silently; a real overlap is an
  // authoritative rejection and cannot be confirmed through.
  {
    let alertCalls = 0;
    withGlobals({ alert: () => { alertCalls += 1; } }, () => {
      const ok = planner.workshopConfirmOtherDepartmentPlans(fitting0800to1100, [fitting0800to1100, tint1100to1300]);
      assert.strictEqual(ok, true, '12f sequential departments must be allowed without prompting');
    });
    assert.strictEqual(alertCalls, 0, '12f no rejection alert may fire for a valid sequential booking');
  }
  {
    let alertCalls = 0;
    let lastMessage = '';
    withGlobals({ alert: message => { alertCalls += 1; lastMessage = message; } }, () => {
      const ok = planner.workshopConfirmOtherDepartmentPlans(fitting0800to1100, [fitting0800to1100, tint1000to1200]);
      assert.strictEqual(ok, false, '12f a same-vehicle overlap must be rejected without an override');
    });
    assert.strictEqual(alertCalls, 1, '12f one rejection alert must identify the conflict');
    assert.ok(lastMessage.includes('TINT'), '12f the rejection must name the exact conflicting department');
    assert.ok(lastMessage.includes('Bay 01'), '12f the rejection must name the exact conflicting bay');
  }
  {
    let alertCalls = 0;
    withGlobals({ alert: () => { alertCalls += 1; } }, () => {
      const ok = planner.workshopConfirmOtherDepartmentPlans(startedFitting, [startedFitting, tint1000to1200]);
      assert.strictEqual(ok, false, '12g a live started/stoppage move must reject same-vehicle overlap');
    });
    assert.strictEqual(alertCalls, 1, '12g live overlap rejection must explain the conflict');
  }
  console.log('PASS 12: same-vehicle overlap is rejected across stations/bays and live states while back-to-back and cross-vehicle bookings remain valid');
}

// 13. workshopDateAtOffset: exact drag/drop time-coordinate calculation.
// Dropping at 10:30am (150 minutes after 8:00am) must resolve to exactly
// 10:30, never snap back to the workshop start time.
{
  const dateKey = '2026-07-17';
  const tenThirty = planner.workshopDateAtOffset(dateKey, 150);
  assert.strictEqual(tenThirty.getHours(), 10, '13a dropping at minute-offset 150 must resolve to 10am, not 8am');
  assert.strictEqual(tenThirty.getMinutes(), 30, '13b dropping at minute-offset 150 must resolve to :30, not :00');
  const eightAm = planner.workshopDateAtOffset(dateKey, 0);
  assert.strictEqual(eightAm.getHours(), 8, '13c minute-offset 0 must still resolve to 8am (the actual start, not an accidental default)');
  assert.strictEqual(planner.workshopMinuteOffset(tenThirty), 150, '13d workshopMinuteOffset must round-trip back to the same 150-minute offset');
  console.log('PASS 13: workshopDateAtOffset resolves drag/drop pixel-derived minute offsets to the exact requested time, never snapping to day start');
}

// 14. Stage 2A workshop bay behaviour: shared reference service lookup,
// inactive-bay rejection, default-technician availability, and
// fail-safe behaviour when the service has not loaded.
{
  // 14a. No shared service loaded at all -> fail safe: active, no default.
  withGlobals({ __workshopReferenceDataService: undefined }, () => {
    assert.strictEqual(planner.workshopBayIsActive('FABRICATION', 1), true, '14a with no shared service loaded, a bay must be treated as active (fail safe, never block on missing data)');
    assert.strictEqual(planner.workshopBayDefaultTechnicianName('FABRICATION', 1), '', '14a with no shared service loaded, there is no default technician name');
    assert.strictEqual(planner.workshopSharedBayRef('FABRICATION', 1), null, '14a with no shared service loaded, workshopSharedBayRef must return null');
  });

  const technicianRows = [{ id: 'tech-1', name: 'Real Default Tech', active: true }];
  const bayRows = [
    { id: 'bay-1', code: 'FABRICATION-BAY-01', is_active: true, default_technician_id: 'tech-1' },
    { id: 'bay-2', code: 'FABRICATION-BAY-02', is_active: false, default_technician_id: null },
    { id: 'bay-3', code: 'SUBLET-ROW', is_active: true, default_technician_id: null },
  ];
  const referenceService = {
    getCachedWorkshopBays: () => ({ rows: bayRows }),
    getCachedTechnicians: () => ({ rows: technicianRows }),
  };

  withGlobals({ __workshopReferenceDataService: referenceService }, () => {
    // 14b. Shared service loaded with a real bay row -- active, matched by code.
    assert.strictEqual(planner.workshopBayIsActive('FABRICATION', 1), true, '14b an active bay (FABRICATION-BAY-01) must report active');
    assert.strictEqual(planner.workshopBayDefaultTechnicianName('FABRICATION', 1), 'Real Default Tech', '14b an active bay with a default_technician_id must resolve the real technician name');

    // 14c. Inactive bay -- must report inactive, no default technician leaks through.
    assert.strictEqual(planner.workshopBayIsActive('FABRICATION', 2), false, '14c an inactive bay (FABRICATION-BAY-02) must report inactive');
    assert.strictEqual(planner.workshopBayDefaultTechnicianName('FABRICATION', 2), '', '14c an inactive bay with no default_technician_id must return an empty default');

    // 14d. Historical SUBLET reference rows must not map into the active planner.
    assert.strictEqual(planner.workshopSharedBayRef('SUBLET', 1), null, '14d the historical SUBLET row must not resolve as a planner bay');
    assert.strictEqual(planner.workshopBayAvailabilityStatus('SUBLET', 1), 'unknown', '14d direct Sublet bay identifiers must fail closed for new scheduling');

    // 14e. Unknown bay number for a known stage -- fail safe: active, no default.
    assert.strictEqual(planner.workshopBayIsActive('FABRICATION', 99), true, '14e a bay number with no matching row must fail safe to active');
  });

  console.log('PASS 14: Stage 2A workshop bay behaviour -- shared lookup, inactive detection, defaults, and Sublet planner rejection all behave correctly');
}

// 15. Independent-review remediation (finding 1): workshopSyncConfigFromSharedSettings()
// must actually change the planner's live scheduling constants from
// the shared, database-validated workshop configuration, and must
// leave the current values untouched when the cache is not ready or
// an individual value fails validation (never silently reset to the
// hard-coded boot default after a valid value was already active).
{
  const originalStart = planner.WORKSHOP_CONFIG.dayStartMinutes;
  const originalEnd = planner.WORKSHOP_CONFIG.dayEndMinutes;

  // 15a. Cache not ready (e.g. still loading) -- must return false and
  // change nothing.
  withGlobals({
    __workshopReferenceDataService: {
      getCachedWorkshopConfiguration: () => ({ state: 'loading', rows: null }),
    },
  }, () => {
    const changed = planner.workshopSyncConfigFromSharedSettings();
    assert.strictEqual(changed, false, '15a a not-ready cache must report no change');
  });

  // 15b. Valid configuration -- start/end/increment/default-duration/
  // working-week all update.
  withGlobals({
    __workshopReferenceDataService: {
      getCachedWorkshopConfiguration: () => ({
        state: 'connected_read_only',
        rows: completeConfigurationRows({
          day_start_time: { value: '07:30' },
          day_end_time: { value: '15:30' },
          scheduling_increment_minutes: { value: 30 },
          default_booking_duration_minutes: { value: 240 },
          working_week: { value: ['Monday', 'Tuesday', 'Wednesday'] },
        }),
      }),
    },
  }, () => {
    const changed = planner.workshopSyncConfigFromSharedSettings();
    assert.strictEqual(changed, true, '15b a genuinely different valid configuration must report a change');
    assert.strictEqual(planner.WORKSHOP_CONFIG.dayStartMinutes, 450, '15b day_start_time 07:30 must become dayStartMinutes 450');
    assert.strictEqual(planner.WORKSHOP_CONFIG.dayEndMinutes, 930, '15b day_end_time 15:30 must become dayEndMinutes 930');
    assert.strictEqual(planner.WORKSHOP_CONFIG.schedulingIncrementMinutes, 30, '15b scheduling_increment_minutes 30 must become schedulingIncrementMinutes 30');
    assert.strictEqual(planner.WORKSHOP_CONFIG.defaultBookingDurationMinutes, 240, '15b default_booking_duration_minutes 240 must become defaultBookingDurationMinutes 240');
    assert.deepStrictEqual(planner.WORKSHOP_CONFIG.workingDayIndexes, [1, 2, 3], '15b working_week [Monday,Tuesday,Wednesday] must become workingDayIndexes [1,2,3]');
  });

  // 15b2. A successful administrator write places the same cache in the
  // real service's connected_editable state. That state must be treated as
  // authoritative too; the old fictional 'ready' state is never emitted by
  // workshop-reference-data-service.js.
  withGlobals({
    __workshopReferenceDataService: {
      getCachedWorkshopConfiguration: () => ({
        state: 'connected_editable',
        rows: completeConfigurationRows({
          day_start_time: { value: '08:00' },
          day_end_time: { value: '16:00' },
          scheduling_increment_minutes: { value: 15 },
          default_booking_duration_minutes: { value: 180 },
          working_week: { value: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'] },
        }),
      }),
    },
  }, () => {
    const changed = planner.workshopSyncConfigFromSharedSettings();
    assert.strictEqual(changed, true, '15b2 connected_editable must be accepted as an authoritative cache state');
    assert.strictEqual(planner.WORKSHOP_CONFIG.dayStartMinutes, 480, '15b2 editable state must apply day_start_time');
    assert.strictEqual(planner.WORKSHOP_CONFIG.defaultBookingDurationMinutes, 180, '15b2 editable state must apply default duration');
  });

  // 15c. Malformed/invalid values (start after end, non-string time,
  // negative increment) must be ignored -- current values remain from
  // the previous successful sync, never silently reset.
  withGlobals({
    __workshopReferenceDataService: {
      getCachedWorkshopConfiguration: () => ({
        state: 'connected_editable',
        rows: completeConfigurationRows({
          day_start_time: { value: '20:00' },
          day_end_time: { value: '08:00' }, // end before start -- must be ignored
          scheduling_increment_minutes: { value: -5 }, // negative -- must be ignored
          default_booking_duration_minutes: { value: 'banana' }, // not a number -- must be ignored
          working_week: { value: [] }, // empty -- must be ignored
        }),
      }),
    },
  }, () => {
    const before = { start: planner.WORKSHOP_CONFIG.dayStartMinutes, end: planner.WORKSHOP_CONFIG.dayEndMinutes, snap: planner.WORKSHOP_CONFIG.schedulingIncrementMinutes, hours: planner.WORKSHOP_CONFIG.defaultBookingDurationMinutes, days: [...planner.WORKSHOP_CONFIG.workingDayIndexes] };
    const changed = planner.workshopSyncConfigFromSharedSettings();
    assert.strictEqual(changed, false, '15c an entirely-invalid configuration must report no change');
    assert.strictEqual(planner.WORKSHOP_CONFIG.dayStartMinutes, before.start, '15c invalid start/end (end before start) must not change dayStartMinutes');
    assert.strictEqual(planner.WORKSHOP_CONFIG.dayEndMinutes, before.end, '15c invalid start/end (end before start) must not change dayEndMinutes');
    assert.strictEqual(planner.WORKSHOP_CONFIG.schedulingIncrementMinutes, before.snap, '15c a negative increment must not change schedulingIncrementMinutes');
    assert.strictEqual(planner.WORKSHOP_CONFIG.defaultBookingDurationMinutes, before.hours, '15c a non-numeric duration must not change defaultBookingDurationMinutes');
    assert.deepStrictEqual(planner.WORKSHOP_CONFIG.workingDayIndexes, before.days, '15c an empty working_week must not change workingDayIndexes');
  });

  console.log('PASS 15: workshopSyncConfigFromSharedSettings() applies valid shared integer-minute configuration and fails closed on invalid/not-ready values without reverting to boot defaults');
}

// 16. Independent-review remediation (finding 2 & 3): in shared mode,
// workshopBayMechanic() must read the shared default ONLY (no
// localStorage fallback), and workshopReferenceTechnicianRef() must
// resolve an ACTIVE technician who has never appeared on a booking by
// their stable reference-table ID, never returning null for a valid
// name just because the booking-snapshot scan found nothing.
{
  const technicianRows = [
    { id: 'tech-active-1', name: 'Never Booked Active Tech', active: true },
    { id: 'tech-inactive-1', name: 'Deactivated Tech', active: false },
  ];
  const bayRows = [
    { id: 'bay-shared-1', code: 'FABRICATION-BAY-01', is_active: true, default_technician_id: null, version: 3 },
  ];
  const referenceService = {
    getCachedWorkshopBays: () => ({ rows: bayRows }),
    getCachedTechnicians: () => ({ rows: technicianRows }),
  };

  // 16a. workshopReferenceTechnicianRef resolves an active technician
  // purely from the reference table, even though they appear on no
  // booking anywhere.
  withGlobals({ __workshopReferenceDataService: referenceService }, () => {
    const ref = planner.workshopReferenceTechnicianRef('Never Booked Active Tech');
    assert.deepStrictEqual(ref, { technicianId: 'tech-active-1' }, '16a an active technician never seen on any booking must still resolve by stable reference-table ID');
  });

  // 16b. workshopReferenceTechnicianRef must NEVER resolve an inactive
  // technician for a new assignment.
  withGlobals({ __workshopReferenceDataService: referenceService }, () => {
    const ref = planner.workshopReferenceTechnicianRef('Deactivated Tech');
    assert.strictEqual(ref, null, '16b an inactive technician must never resolve for a new assignment, even if the name matches exactly');
  });

  // 16c. workshopReferenceTechnicianRef with an unknown name returns
  // null (never fabricates a match).
  withGlobals({ __workshopReferenceDataService: referenceService }, () => {
    const ref = planner.workshopReferenceTechnicianRef('Nobody Real');
    assert.strictEqual(ref, null, '16c an unknown name must resolve to null, not a fabricated match');
  });

  // 16d. workshopBayMechanic in shared mode reads the shared default
  // ONLY -- an empty shared default must return '' (no default set is
  // a valid state), never falling through to a browser-local mapping.
  withGlobals({
    workshopSharedModeEnabled: (cfg) => !!(cfg && cfg.workshop && cfg.workshop.sharedData === true),
    PDC_SUPABASE_CONFIG: { workshop: { sharedData: true } },
    __workshopSharedActions: {},
    __workshopDataService: { isEnabled: () => true, getLastSnapshot: () => ({}) },
    __workshopReferenceDataService: referenceService,
  }, () => {
    assert.strictEqual(planner.workshopBayMechanic('FABRICATION', 1), '', '16d in shared mode, an empty shared default must return empty string, never a localStorage fallback value');
  });

  console.log('PASS 16: workshopReferenceTechnicianRef resolves active technicians by stable ID regardless of booking history and rejects inactive/unknown names; workshopBayMechanic in shared mode reads the shared default only with no localStorage fallback');
}

// 17. Independent-review remediation (finding 8): workshopBayAvailabilityStatus()
// must distinguish active/inactive/unavailable/unknown and fail
// CLOSED (never 'active') for anything except a confirmed-active bay.
{
  const bayRows = [
    { id: 'bay-1', code: 'FABRICATION-BAY-01', is_active: true, default_technician_id: null },
    { id: 'bay-2', code: 'FABRICATION-BAY-02', is_active: false, default_technician_id: null },
  ];

  // 17a. No shared service at all (legacy local mode) -- must report
  // 'active' so local-mode scheduling behaviour is unaffected by
  // Stage 2A.
  withGlobals({ __workshopReferenceDataService: undefined }, () => {
    assert.strictEqual(planner.workshopBayAvailabilityStatus('FABRICATION', 1), 'active', '17a with no shared service at all (legacy local mode), availability must report active');
  });

  // 17b. Shared service present but still loading/reconnecting/offline
  // -- must report 'unavailable', NOT 'active'.
  ['connecting', 'reconnecting', 'offline_error', 'permission_denied'].forEach((state) => {
    withGlobals({
      __workshopReferenceDataService: {
        getCachedWorkshopBays: () => ({ rows: [], state }),
      },
    }, () => {
      assert.strictEqual(planner.workshopBayAvailabilityStatus('FABRICATION', 1), 'unavailable', `17b a shared service in state '${state}' must report 'unavailable', never 'active'`);
    });
  });

  const readyService = {
    getCachedWorkshopBays: () => ({ rows: bayRows, state: 'connected_read_only' }),
  };

  // 17c. Confirmed active bay -- reports 'active'.
  withGlobals({ __workshopReferenceDataService: readyService }, () => {
    assert.strictEqual(planner.workshopBayAvailabilityStatus('FABRICATION', 1), 'active', '17c a confirmed active bay must report active');
  });

  // 17d. Confirmed inactive bay -- reports 'inactive', not 'active'.
  withGlobals({ __workshopReferenceDataService: readyService }, () => {
    assert.strictEqual(planner.workshopBayAvailabilityStatus('FABRICATION', 2), 'inactive', '17d a confirmed inactive bay must report inactive');
  });

  // 17e. Unknown bay number with no matching row -- reports 'unknown',
  // NOT 'active' (this is the core fix -- the OLD workshopBayIsActive()
  // failed open here).
  withGlobals({ __workshopReferenceDataService: readyService }, () => {
    assert.strictEqual(planner.workshopBayAvailabilityStatus('FABRICATION', 99), 'unknown', "17e an unmatched bay number must report 'unknown', not 'active' -- this is the fail-closed fix");
  });

  // 17f. workshopBayIsActive() (the older, intentionally lenient
  // boolean used for rendering EXISTING/historical bookings) is left
  // unchanged and must still fail open for backward compatibility.
  withGlobals({ __workshopReferenceDataService: readyService }, () => {
    assert.strictEqual(planner.workshopBayIsActive('FABRICATION', 99), true, '17f workshopBayIsActive() must remain unchanged (fail open) for rendering existing/historical bookings');
  });

  console.log("PASS 17: workshopBayAvailabilityStatus() distinguishes active/inactive/unavailable/unknown and fails closed for new scheduling, while workshopBayIsActive() remains unchanged for existing/historical bookings");
}

// 18. Transport/runtime failures are converted to safe operator UX and never
// leak a rejected promise or raw backend/network text.
(async () => {
  const originalWindow = global.window;
  const alerts = [];
  let renders = 0;
  global.window = {
    workshopSharedModeEnabled: () => true,
    PDC_SUPABASE_CONFIG: { workshop: { sharedData: true } },
    __workshopDataService: { isEnabled: () => true },
    __workshopSharedActions: { moveBooking: async () => { throw new Error('network sentinel must not leak'); } },
    alert: message => alerts.push(String(message)),
  };
  try {
    const result = await planner.workshopDispatchSharedAction('moveBooking', {}, () => { renders += 1; });
    assert.deepStrictEqual(result, { ok: false, error: 'runtime_failure' }, '18a rejected actions become a structured fail-closed result');
    assert.strictEqual(alerts.length, 1, '18b one safe user-facing alert is shown');
    assert.ok(!alerts[0].includes('sentinel'), '18c raw transport errors never leak to the operator');
    assert.strictEqual(renders, 1, '18d planner refresh is still requested after failure');
    console.log('PASS 18: rejected shared actions fail closed with safe UX and refresh');

    const duplicateBookings = ['b1', 'b2'].map((id, index) => ({
      booking_id: id,
      version: 7,
      vehicle: { id: 'veh-legacy', stock_number: 'LEGACY-HOIST' },
      stage: { code: 'HOIST' },
      bay: { bay_number: index + 1 },
      status: 'planned',
      scheduled_start_at: `2026-07-20T0${index + 1}:00:00.000Z`,
      default_duration_minutes: 60,
    }));
    let ambiguityDispatches = 0;
    global.window = {
      workshopSharedModeEnabled: () => true,
      PDC_SUPABASE_CONFIG: { workshop: { sharedData: true } },
      __workshopDataService: {
        isEnabled: () => true,
        getLastSnapshot: () => ({ bookings: duplicateBookings, vehicles: [] }),
      },
      __workshopSharedActions: {
        startWork: async () => { ambiguityDispatches += 1; return { ok: true }; },
        cascadeSchedule: async () => { ambiguityDispatches += 1; return { ok: true }; },
      },
      alert: message => alerts.push(String(message)),
    };
    const blocked = await planner.workshopDispatchSharedAction('startWork', { bookingId: 'b1', expectedVersion: 7 }, () => { renders += 1; });
    assert.strictEqual(blocked.error, 'legacy_ambiguity_blocked', '19a ambiguous legacy booking is rejected centrally');
    assert.strictEqual(ambiguityDispatches, 0, '19b no protected mutation is dispatched for an ambiguous legacy booking');
    assert.ok(alerts.at(-1).includes('Legacy review required'), '19c operator receives a clear legacy-review explanation');
    const blockedResize = await planner.workshopDispatchSharedAction('cascadeSchedule', { targetId: 'b1', expectedVersion: 7, operation: 'extend', durationMinutes: 1500 }, () => { renders += 1; });
    assert.strictEqual(blockedResize.error, 'legacy_ambiguity_blocked', '19d manual estimated-time resize also rejects ambiguous targetId payloads');
    assert.strictEqual(ambiguityDispatches, 0, '19e ambiguous resize never reaches cascadeSchedule');
    console.log('PASS 19: alternate Job details and manual resize paths cannot mutate ambiguous legacy bookings');
  } finally {
    global.window = originalWindow;
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
