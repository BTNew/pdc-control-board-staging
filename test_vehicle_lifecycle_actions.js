'use strict';

// Real (non-mocked) tests for vehicle-lifecycle-actions.js: proves each
// bridge function emits the exact RPC name + parameter shape defined by
// migration 016, using a fake client transport (not a mock of the module
// under test itself).

const assert = require('assert');
const {
  vehicleLifecycleSharedModeEnabled,
  buildVehicleLifecycleIdentityInput,
  buildVehicleLifecycleSharedActions,
  describeVehicleLifecycleActionError,
} = require('./vehicle-lifecycle-actions.js');

// 1. Opt-in gating: false unless config.vehicleLifecycle.sharedData === true.
{
  assert.strictEqual(vehicleLifecycleSharedModeEnabled(null), false, '1a null config is disabled');
  assert.strictEqual(vehicleLifecycleSharedModeEnabled({}), false, '1b empty config is disabled');
  assert.strictEqual(vehicleLifecycleSharedModeEnabled({ vehicleLifecycle: {} }), false, '1c missing sharedData flag is disabled');
  assert.strictEqual(vehicleLifecycleSharedModeEnabled({ vehicleLifecycle: { sharedData: false } }), false, '1d explicit false is disabled');
  assert.strictEqual(vehicleLifecycleSharedModeEnabled({ vehicleLifecycle: { sharedData: true } }), true, '1e explicit true is enabled');
  console.log('PASS 1: vehicleLifecycleSharedModeEnabled requires explicit opt-in');
}

{
  const projectedId = 'f34f1184-063f-5e72-891e-19de319d88d4';
  const input = buildVehicleLifecycleIdentityInput({ __emailVehicleId: projectedId, stock: '13016934' });
  assert.strictEqual(input.p_vehicle_id, projectedId, 'Projected authenticated vehicle UUID must be used as canonical lifecycle identity');
  assert.strictEqual(input.p_stock_number, '13016934');
  console.log('PASS identity: authenticated projected vehicle UUID reaches lifecycle resolver');
}

function fakeClient(responder) {
  const calls = [];
  return {
    calls,
    rpc: async (token, name, params) => {
      calls.push({ token, name, params });
      return responder(name, params);
    },
  };
}

// Vehicle Detail deletion maps to the established protected lifecycle RPC and
// normalises its legacy row return into the shared-action result contract.
{
  const deletedRow = { id: 'v-delete', lifecycle_state: 'deleted', version: 8 };
  const client = fakeClient(() => ({ status: 200, ok: true, body: deletedRow }));
  const bridge = buildVehicleLifecycleSharedActions(client, () => 'tok-delete');
  bridge.markVehicleDeleted({ vehicleId: 'v-delete', expectedVersion: 7, reason: 'Duplicate import' }).then(result => {
    assert.strictEqual(client.calls[0].name, 'mark_vehicle_deleted');
    assert.deepStrictEqual(client.calls[0].params, {
      p_vehicle_id: 'v-delete',
      p_expected_version: 7,
      p_reason: 'Duplicate import',
    });
    assert.deepStrictEqual(result, { ok: true, vehicle: deletedRow });
    console.log('PASS delete: markVehicleDeleted maps and normalises the protected deletion RPC');
  });
}

// 2. qcCompleteVehicle maps to qc_complete_vehicle with the exact parameter
// names/defaults used by migration 016.
{
  const client = fakeClient(() => ({ status: 200, ok: true, body: { ok: true, notification_id: 'n1' } }));
  const bridge = buildVehicleLifecycleSharedActions(client, () => 'tok-abc');
  bridge.qcCompleteVehicle({ vehicleId: 'v1', expectedVersion: 3, workItemKey: 'QC', completedSummary: 'done' })
    .then(result => {
      assert.strictEqual(client.calls.length, 1, '2a exactly one RPC call');
      assert.strictEqual(client.calls[0].name, 'qc_complete_vehicle', '2b correct RPC name');
      assert.deepStrictEqual(client.calls[0].params, {
        p_vehicle_id: 'v1',
        p_expected_version: 3,
        p_work_item_key: 'QC',
        p_completed_summary: 'done',
      }, '2c correct parameter shape');
      assert.strictEqual(client.calls[0].token, 'tok-abc', '2d access token passed through');
      assert.deepStrictEqual(result, { ok: true, notification_id: 'n1' }, '2e resolves with the RPC body');
      console.log('PASS 2: qcCompleteVehicle maps to qc_complete_vehicle with the correct parameter shape');
    });
}

// 3. qcCompleteVehicle defaults workItemKey to 'QC' and completedSummary to
// null when omitted (never undefined, which Postgres/PostgREST would
// reject differently than an explicit null default).
{
  const client = fakeClient(() => ({ status: 200, ok: true, body: { ok: true } }));
  const bridge = buildVehicleLifecycleSharedActions(client, () => null);
  bridge.qcCompleteVehicle({ vehicleId: 'v2', expectedVersion: 1 }).then(() => {
    assert.deepStrictEqual(client.calls[0].params, {
      p_vehicle_id: 'v2',
      p_expected_version: 1,
      p_work_item_key: 'QC',
      p_completed_summary: null,
    }, '3a omitted optional params use the documented defaults, not undefined');
    console.log('PASS 3: qcCompleteVehicle defaults omitted optional parameters correctly');
  });
}

// 4. rftTransferVehicle / rftCollectVehicle map correctly.
{
  const client = fakeClient(() => ({ status: 200, ok: true, body: { ok: true } }));
  const bridge = buildVehicleLifecycleSharedActions(client, () => 'tok');
  Promise.all([
    bridge.rftTransferVehicle({ vehicleId: 'v3', expectedVersion: 2 }),
    bridge.rftCollectVehicle({ vehicleId: 'v3', expectedVersion: 3 }),
  ]).then(() => {
    assert.strictEqual(client.calls[0].name, 'rft_transfer_vehicle', '4a rftTransferVehicle RPC name');
    assert.deepStrictEqual(client.calls[0].params, { p_vehicle_id: 'v3', p_expected_version: 2 }, '4b rftTransferVehicle params');
    assert.strictEqual(client.calls[1].name, 'rft_collect_vehicle', '4c rftCollectVehicle RPC name');
    assert.deepStrictEqual(client.calls[1].params, { p_vehicle_id: 'v3', p_expected_version: 3 }, '4d rftCollectVehicle params');
    console.log('PASS 4: rftTransferVehicle/rftCollectVehicle map correctly');
  });
}

// 4b. New Vehicle Locations actions map to the atomic QC sign-off and PIT
// movement RPCs introduced by staging-only migration 070.
{
  const client = fakeClient(() => ({ status: 200, ok: true, body: { ok: true } }));
  const bridge = buildVehicleLifecycleSharedActions(client, () => 'tok');
  Promise.all([
    bridge.markReadyForQc({ vehicleId: 'v3', expectedVersion: 7 }),
    bridge.qcSignoffToRft({ vehicleId: 'v4', expectedVersion: 8, workItemKey: 'QC', completedSummary: 'all jobs' }),
    bridge.pitTransferVehicle({ vehicleId: 'v5', expectedVersion: 4, direction: 'to_pit' }),
  ]).then(() => {
    assert.strictEqual(client.calls[0].name, 'mark_vehicle_ready_for_qc');
    assert.deepStrictEqual(client.calls[0].params, { p_vehicle_id: 'v3', p_expected_version: 7 });
    assert.strictEqual(client.calls[1].name, 'qc_signoff_to_rft');
    assert.deepStrictEqual(client.calls[1].params, {
      p_vehicle_id: 'v4', p_expected_version: 8, p_work_item_key: 'QC', p_completed_summary: 'all jobs',
    });
    assert.strictEqual(client.calls[2].name, 'pit_transfer_vehicle');
    assert.deepStrictEqual(client.calls[2].params, {
      p_vehicle_id: 'v5', p_expected_version: 4, p_direction: 'to_pit',
    });
    console.log('PASS 4b: markReadyForQc/qcSignoffToRft/pitTransferVehicle map correctly');
  });
}

// 4c. Explicit Yard Hold/In Transit to PMB movement uses the protected,
// version-checked shared RPC rather than browser-local edits.
{
  const client = fakeClient(() => ({ status: 200, ok: true, body: { ok: true } }));
  const bridge = buildVehicleLifecycleSharedActions(client, () => 'tok');
  bridge.pmbTransferVehicle({ vehicleId: 'v6', expectedVersion: 11 }).then(() => {
    assert.strictEqual(client.calls[0].name, 'pmb_transfer_vehicle');
    assert.deepStrictEqual(client.calls[0].params, {
      p_vehicle_id: 'v6', p_expected_version: 11,
    });
    console.log('PASS 4c: pmbTransferVehicle maps to the protected shared RPC');
  });
}

// 5. retryVehicleNotification maps correctly, including the optional
// recipient email override.
{
  const client = fakeClient(() => ({ status: 200, ok: true, body: { ok: true } }));
  const bridge = buildVehicleLifecycleSharedActions(client, () => 'tok');
  bridge.retryVehicleNotification({ notificationId: 'n1', recipientEmail: 'fixed@example.com' }).then(() => {
    assert.strictEqual(client.calls[0].name, 'retry_vehicle_notification', '5a correct RPC name');
    assert.deepStrictEqual(client.calls[0].params, { p_notification_id: 'n1', p_recipient_email: 'fixed@example.com' }, '5b correct params');
    console.log('PASS 5: retryVehicleNotification maps correctly with recipient override');
  });
}

// 6. A failed HTTP-level request (not a 200 with ok:false body) is
// surfaced as a structured { ok: false, error: 'request_failed', ... }
// rather than throwing or returning the raw fetch result.
{
  const client = fakeClient(() => ({ status: 500, ok: false, body: { message: 'boom' } }));
  const bridge = buildVehicleLifecycleSharedActions(client, () => 'tok');
  bridge.qcCompleteVehicle({ vehicleId: 'v4', expectedVersion: 1 }).then(result => {
    assert.strictEqual(result.ok, false, '6a failed request reports ok:false');
    assert.strictEqual(result.error, 'request_failed', '6b failed request uses the request_failed error code');
    assert.strictEqual(result.status, 500, '6c failed request status is preserved for diagnostics');
    console.log('PASS 6: HTTP-level failures are surfaced as a structured, non-throwing result');
  });
}

// 7. describeVehicleLifecycleActionError: every documented backend error
// code maps to a clear, non-technical message; unknown codes get a safe
// generic fallback rather than leaking a raw code to staff.
{
  const documented = [
    'vehicle_version_conflict', 'already_qc_complete', 'already_collected',
    'qc_not_complete', 'qc_gate_blocked', 'pit_requires_pmb_unallocated',
    'not_in_pit', 'invalid_pit_direction', 'not_in_active_lifecycle', 'not_in_rft',
    'request_failed', 'missing_expected_version', 'pmb_transfer_requires_yh_or_it', 'invalid_vehicle',
  ];
  documented.forEach(code => {
    const message = describeVehicleLifecycleActionError(code);
    assert.strictEqual(typeof message, 'string', `7a ${code} maps to a string message`);
    assert.ok(message.length > 10, `7b ${code} message is not trivially empty`);
    assert.ok(!/^[a-z_]+$/.test(message), `7c ${code} message is not just the raw error code`);
  });
  const fallback = describeVehicleLifecycleActionError('some_unmapped_future_code');
  assert.ok(fallback && fallback.length > 10, '7d unknown codes get a safe generic fallback message');
  console.log('PASS 7: every documented error code and the unmapped fallback produce clear, non-technical messages');
}
