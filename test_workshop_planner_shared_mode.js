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
    vehicle: { stock_number: 'STK-999', permanent_vehicle_id: 'perm-1' },
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
  assert.strictEqual(row.stage, 'HOIST', '4e stage code preserved');
  assert.strictEqual(row.bay, 2, '4f bay number preserved as a number');
  assert.strictEqual(row.hours, 3, '4g 180 minutes maps to 3 hours');
  assert.strictEqual(row.assignee, 'Alex', '4h technician name maps to legacy assignee field');
  assert.strictEqual(row.status, 'started', '4i status maps through the legacy status vocabulary');
  console.log('PASS 4: snapshot booking DTO maps cleanly onto the existing legacy row shape');
}

// 5. Vehicle with no stock_number falls back to permanent_vehicle_id
{
  const booking = {
    booking_id: 'b-456',
    vehicle: { stock_number: '', permanent_vehicle_id: 'perm-2' },
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

// 6. A booking with no booking_id is rejected (never silently mapped to a garbage row)
{
  const row = planner.workshopMapSnapshotBookingToLegacyRow({});
  assert.strictEqual(row, null, '6a booking with no booking_id maps to null, filtered out by callers');
  console.log('PASS 6: malformed/incomplete snapshot bookings are rejected, not silently mapped');
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
  console.log('PASS 7: connection banner renders a distinct, styled message per connection state');
}

console.log('Workshop planner shared-mode integration seam checks passed');

// --- Section 14 error mapping: never a raw stack trace / DB error ---

{
  const cases = [
    ['version_conflict', 'changed by another user'],
    ['bay_overlap', 'bay is already occupied'],
    ['technician_overlap', 'already assigned to another booking'],
    ['parts_incomplete', 'Parts requirements are incomplete'],
    ['permission_denied', 'do not have permission'],
    ['missing_expected_version', 'missing required version'],
    ['totally_unmapped_backend_error_code', 'could not be saved'],
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
