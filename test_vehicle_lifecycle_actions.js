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

// 6. HTTP failures preserve the exact backend body, message and code.
{
  const response = { status: 409, ok: false, body: { code: 'stock_confirmation_mismatch', message: 'Stock confirmation must exactly match 13016934.' } };
  const client = fakeClient(() => response);
  const bridge = buildVehicleLifecycleSharedActions(client, () => 'tok');
  bridge.qcCompleteVehicle({ vehicleId: 'v4', expectedVersion: 1 }).then(result => {
    assert.strictEqual(result.ok, false, '6a failed request reports ok:false');
    assert.strictEqual(result.error, 'stock_confirmation_mismatch', '6b exact backend code is preserved');
    assert.strictEqual(result.code, 'stock_confirmation_mismatch', '6c code has a dedicated field');
    assert.strictEqual(result.message, 'Stock confirmation must exactly match 13016934.', '6d exact backend message is preserved');
    assert.strictEqual(result.status, 409, '6e failed request status is preserved');
    assert.strictEqual(result.body, response.body, '6f exact response body is preserved');
    assert.strictEqual(result.response, response, '6g complete transport response is preserved');
    assert.strictEqual(describeVehicleLifecycleActionError(result), 'Stock confirmation must exactly match 13016934. (stock_confirmation_mismatch)', '6h formatter displays exact server message and code');
    console.log('PASS 6: HTTP-level failures preserve exact backend response/message/body/code');
  });
}

// 6b. Migration 205 Administrator lifecycle RPCs use exact parameter shapes.
{
  const client = fakeClient(() => ({ status: 200, ok: true, body: { ok: true } }));
  const bridge = buildVehicleLifecycleSharedActions(client, () => 'admin-token');
  Promise.all([
    bridge.adminArchiveVehicle({ vehicleId: 'v205', expectedVersion: 12, stockConfirmation: '13016934', reason: 'Duplicate test', resetTest: true }),
    bridge.adminRestoreVehicle({ tombstoneId: 't205', stockConfirmation: '13016934', reason: 'Validated restore' }),
    bridge.adminAllowOneVehicleRecreation({ tombstoneId: 't205', stockConfirmation: '13016934', reason: 'Corrected source retry', sourceHash: 'a'.repeat(64), evidenceHash: 'b'.repeat(64), sourceUid: 'gmail-uid-205' }),
    bridge.adminDeletedVehicleSnapshot(),
  ]).then(() => {
    assert.deepStrictEqual(client.calls.map(call => ({ name: call.name, params: call.params })), [
      { name: 'pdc_admin_reset_staging_test_vehicle', params: { p_vehicle_id: 'v205', p_expected_version: 12, p_confirmation_stock: '13016934', p_reason: 'Duplicate test' } },
      { name: 'pdc_admin_restore_vehicle', params: { p_tombstone_id: 't205', p_confirmation_stock: '13016934', p_reason: 'Validated restore' } },
      { name: 'pdc_admin_allow_vehicle_recreation_once', params: { p_tombstone_id: 't205', p_confirmation_stock: '13016934', p_reason: 'Corrected source retry', p_source_hash: 'a'.repeat(64), p_evidence_hash: 'b'.repeat(64), p_source_uid: 'gmail-uid-205', p_ttl_minutes: 30 } },
      { name: 'pdc_admin_archived_vehicle_snapshot', params: { p_tombstone_id: null, p_limit: 100 } },
    ]);
    assert(client.calls.every(call => call.token === 'admin-token'));
    console.log('PASS 6b: migration 205 Administrator lifecycle RPC parameter shapes are exact');
  });
}

// 6c. A destructive dialog may bind dispatch to the authority owner that
// rendered the intent. Replacement authority must be rejected before transport.
{
  let token = 'token-a';
  let authority = { userId: 'admin-a', role: 'administrator' };
  const client = fakeClient(() => ({ status: 200, ok: true, body: { ok: true } }));
  const bridge = buildVehicleLifecycleSharedActions(client, () => token, () => authority);
  const owner = { token: 'token-a', identity: JSON.stringify(['admin-a', 'administrator']) };
  token = 'token-b';
  authority = { userId: 'admin-b', role: 'administrator' };
  bridge.adminArchiveVehicle({
    vehicleId: 'v-owner', expectedVersion: 1, stockConfirmation: 'S1', reason: 'stale intent',
  }, owner).then(result => {
    assert.strictEqual(result.error, 'stale_authority');
    assert.strictEqual(client.calls.length, 0, 'owner mismatch is rejected before transport');
    console.log('PASS 6c: destructive lifecycle dispatch is bound to its pre-dialog authority owner');
  });
}

// 6d. Shared transport mutation RPCs must reject stale expectedOwner before transport.
{
  let token = 'token-a';
  let authority = { userId: 'admin-a', role: 'administrator' };
  const client = fakeClient(() => ({ status: 200, ok: true, body: { ok: true } }));
  const bridge = buildVehicleLifecycleSharedActions(client, () => token, () => authority);
  const owner = { token: 'token-a', identity: JSON.stringify(['admin-a', 'administrator']) };
  token = 'token-b';
  authority = { userId: 'admin-b', role: 'administrator' };
  Promise.all([
    bridge.rftTransferVehicle({ vehicleId: 'v-owner-rft', expectedVersion: 2 }, owner),
    bridge.pmbTransferVehicle({ vehicleId: 'v-owner-pmb', expectedVersion: 3 }, owner),
  ]).then(results => {
    assert.deepStrictEqual(results, [
      { ok: false, error: 'stale_authority' },
      { ok: false, error: 'stale_authority' },
    ]);
    assert.strictEqual(client.calls.length, 0, 'stale owner for shared transport mutations is rejected before RPC dispatch');
    console.log('PASS 6d: shared transport mutation dispatch is bound to the pre-dialog authority owner');
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

// 8. Delayed RPC completions are bound to the exact access token and
// principal/role authority that dispatched them. A server success after
// sign-out, token replacement, principal replacement, or role demotion must
// be returned as a stale-authority failure rather than published as success.
(async () => {
  function deferred() {
    let resolve;
    let reject;
    const promise = new Promise((done, fail) => { resolve = done; reject = fail; });
    return { promise, resolve, reject };
  }

  let token = 'tok-a';
  let authority = { userId: 'operator-a', role: 'Technician' };
  let response = deferred();
  const calls = [];
  const client = {
    async rpc(capturedToken, name, params) {
      calls.push({ capturedToken, name, params });
      return response.promise;
    },
  };
  const bridge = buildVehicleLifecycleSharedActions(client, () => token, () => authority);

  const signedOut = bridge.markReadyForQc({ vehicleId: 'v-auth-1', expectedVersion: 1 });
  token = null;
  authority = null;
  response.resolve({ status: 200, ok: true, body: { ok: true, vehicle: { id: 'v-auth-1' } } });
  assert.deepStrictEqual(await signedOut, { ok: false, error: 'stale_authority' }, '8a sign-out suppresses delayed success');

  token = 'tok-b';
  authority = { userId: 'operator-a', role: 'Technician' };
  response = deferred();
  const tokenReplacement = bridge.markReadyForQc({ vehicleId: 'v-auth-2', expectedVersion: 2 });
  token = 'tok-c';
  response.resolve({ status: 200, ok: true, body: { ok: true } });
  assert.deepStrictEqual(await tokenReplacement, { ok: false, error: 'stale_authority' }, '8b same-principal token replacement suppresses delayed success');

  response = deferred();
  const principalReplacement = bridge.markReadyForQc({ vehicleId: 'v-auth-3', expectedVersion: 3 });
  authority = { userId: 'operator-b', role: 'Technician' };
  response.resolve({ status: 200, ok: true, body: { ok: true } });
  assert.deepStrictEqual(await principalReplacement, { ok: false, error: 'stale_authority' }, '8c principal replacement suppresses delayed success');

  authority = { userId: 'operator-b', role: 'Administrator' };
  response = deferred();
  const roleDemotion = bridge.adminDeletedVehicleSnapshot();
  authority = { userId: 'operator-b', role: 'Technician' };
  response.resolve({ status: 200, ok: true, body: { ok: true, rows: [] } });
  assert.deepStrictEqual(await roleDemotion, { ok: false, error: 'stale_authority' }, '8d role demotion suppresses delayed administrator success');

  token = 'tok-d';
  authority = { userId: 'operator-b', role: 'Administrator' };
  response = deferred();
  const staleRejection = bridge.adminDeletedVehicleSnapshot();
  token = null;
  authority = null;
  response.reject(new Error('obsolete network failure'));
  assert.deepStrictEqual(await staleRejection, { ok: false, error: 'stale_authority' }, '8e authority loss suppresses delayed transport rejection');

  assert.strictEqual(calls.length, 5, '8f each pre-authorized action dispatches exactly once');
  console.log('PASS 8: delayed lifecycle RPC completion is token/principal/role authority-bound');
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
