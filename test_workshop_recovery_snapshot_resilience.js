'use strict';
const assert = require('assert');
const { createWorkshopDataService, WORKSHOP_CONNECTION_STATE } = require('./workshop-data-service.js');

const scope = { stageCode: 'FITTING', dateFrom: '2026-08-26', dateTo: '2026-08-26' };
const snapshot = {
  revision: 7840,
  bookings: [],
  vehicles: [],
  work_items: [],
  bays: [],
  stages: [],
  admin_blocks: [],
  recovery: { ok: true, code: 'overdue_planned_recovered_with_conflicts', skipped_bay_count: 1 },
};

function serviceFor({ role = 'operator', rpc, token = 'token' }) {
  return createWorkshopDataService({
    config: { workshop: { sharedData: true } },
    scope,
    getAccessToken: () => token,
    getRole: () => role,
    client: { rpc },
  });
}

async function testSnapshotIsSingleNetworkAuthorityForApprovedRoles() {
  for (const role of ['operator', 'administrator']) {
    const calls = [];
    const service = serviceFor({
      role,
      rpc: async (_token, name) => {
        calls.push(name);
        if (name === 'get_station_workshop_snapshot') return { ok: true, status: 200, body: snapshot };
        throw new Error(`redundant browser RPC: ${name}`);
      },
    });
    const result = await service.loadSnapshot(`${role}-refresh`);
    assert.strictEqual(result, snapshot, `${role} retains the valid transactional snapshot despite a recovery conflict`);
    assert.deepStrictEqual(calls, ['get_station_workshop_snapshot'], `${role} uses one browser network authority`);
    assert.strictEqual(service.getState(), WORKSHOP_CONNECTION_STATE.CONNECTED_EDITABLE);
    assert.strictEqual(service.getTrustedSnapshot(), snapshot);
  }
}

async function testDuplicateRefreshesCoalesceWithoutDirectRecovery() {
  const calls = [];
  let releaseFirst;
  const firstResponse = new Promise(resolve => { releaseFirst = resolve; });
  const service = serviceFor({
    rpc: async (_token, name) => {
      calls.push(name);
      assert.strictEqual(name, 'get_station_workshop_snapshot');
      if (calls.length === 1) return firstResponse;
      return { ok: true, status: 200, body: snapshot };
    },
  });
  const first = service.loadSnapshot('same-minute-1');
  const duplicate = await service.loadSnapshot('same-minute-2');
  assert.strictEqual(duplicate, null, 'an in-flight duplicate never fabricates a successful snapshot');
  releaseFirst({ ok: true, status: 200, body: snapshot });
  assert.strictEqual(await first, snapshot);
  assert.deepStrictEqual(calls, ['get_station_workshop_snapshot', 'get_station_workshop_snapshot']);
  assert.strictEqual(service.getTrustedSnapshot(), snapshot, 'the trailing authoritative refresh settles trusted');
}

async function testAuthorizationAndServerFailuresRemainVisible() {
  const denied = serviceFor({
    role: 'viewer',
    rpc: async () => ({ ok: false, status: 403, body: { code: '42501', message: 'Operator or administrator role required' } }),
  });
  assert.strictEqual(await denied.loadSnapshot('viewer-denied'), null);
  assert.strictEqual(denied.getState(), WORKSHOP_CONNECTION_STATE.PERMISSION_DENIED);
  assert.strictEqual(denied.getTrustedSnapshot(), null);

  let fail = false;
  const resilient = serviceFor({
    rpc: async () => fail
      ? { ok: false, status: 500, body: { code: 'XX000', message: 'recovery failed' } }
      : { ok: true, status: 200, body: snapshot },
  });
  assert.strictEqual(await resilient.loadSnapshot('initial'), snapshot);
  fail = true;
  assert.strictEqual(await resilient.loadSnapshot('server-failure'), snapshot, 'visual continuity retains the last valid snapshot');
  assert.strictEqual(resilient.getState(), WORKSHOP_CONNECTION_STATE.OFFLINE_READ_ONLY);
  assert.strictEqual(resilient.getTrustedSnapshot(), null, 'a server failure is never represented as successful maintenance');
}

(async () => {
  await testSnapshotIsSingleNetworkAuthorityForApprovedRoles();
  await testDuplicateRefreshesCoalesceWithoutDirectRecovery();
  await testAuthorizationAndServerFailuresRemainVisible();
  console.log('Workshop transactional recovery snapshot resilience: PASS');
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
