'use strict';

const assert = require('assert');
const { createWorkshopReferenceDataService } = require('./workshop-reference-data-service.js');

function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((res, rej) => { resolve = res; reject = rej; });
  return { promise, resolve, reject };
}

function tick() {
  return new Promise(resolve => setTimeout(resolve, 0));
}

const mutationCases = [
  ['addTechnician', ['Alice', 'technician', 'AL', ['Fitting']], 'add_technician'],
  ['editTechnician', ['tech-1', 1, { name: 'Alice B' }], 'edit_technician'],
  ['setTechnicianActive', ['tech-1', 1, false], 'set_technician_active'],
  ['addSalesperson', ['Sam', 'sam@example.invalid', 'SM'], 'add_salesperson'],
  ['editSalesperson', ['sales-1', 1, { name: 'Sam B' }], 'edit_salesperson'],
  ['setSalespersonActive', ['sales-1', 1, false], 'set_salesperson_active'],
  ['addSubletProvider', ['Tint Co', 'tint@example.invalid', '0400000000'], 'add_sublet_provider'],
  ['editSubletProvider', ['provider-1', 1, { name: 'Tint Co B' }], 'edit_sublet_provider'],
  ['setSubletProviderActive', ['provider-1', 1, false], 'set_sublet_provider_active'],
  ['setWorkshopBayActive', ['bay-1', 1, false], 'set_workshop_bay_active'],
  ['setBayDefaultTechnician', ['bay-1', 1, 'tech-1'], 'set_bay_default_technician'],
  ['updateWorkshopConfiguration', ['day_start_time', 1, '07:30'], 'update_workshop_configuration'],
];

async function main() {
  for (const [method, args] of mutationCases) {
    let token = 'token-a';
    let identity = 'principal-a\nadministrator';
    const calls = [];
    let notifications = 0;
    const service = createWorkshopReferenceDataService({
      client: {
        rpc: async (usedToken, name, params) => {
          calls.push({ token: usedToken, name, params });
          return { status: 200, ok: true, body: { ok: true } };
        },
      },
      getAccessToken: () => token,
      getAuthorityIdentity: () => identity,
      onStateChange: () => { notifications += 1; },
    });

    token = 'token-b';
    identity = 'principal-b\nadministrator';
    const result = await service[method](...args);
    assert.deepStrictEqual(result, { ok: false, error: 'stale_authority' }, `${method}: stale authority returns the stable fail-closed result`);
    assert.strictEqual(calls.length, 0, `${method}: stale authority dispatches no RPC`);
    assert.strictEqual(notifications, 0, `${method}: stale authority publishes no state`);
  }

  {
    let token = 'token-a';
    let identity = 'principal-a\nadministrator';
    const mutation = deferred();
    const calls = [];
    let notifications = 0;
    const service = createWorkshopReferenceDataService({
      client: {
        rpc: async (usedToken, name, params) => {
          calls.push({ token: usedToken, name, params });
          if (name === 'add_technician') return mutation.promise;
          if (name === 'list_technicians') return { status: 200, ok: true, body: [] };
          return { status: 404, ok: false, body: {} };
        },
      },
      getAccessToken: () => token,
      getAuthorityIdentity: () => identity,
      onStateChange: () => { notifications += 1; },
    });

    const pending = service.addTechnician('Alice');
    await tick();
    assert.deepStrictEqual(calls, [{ token: 'token-a', name: 'add_technician', params: { p_name: 'Alice', p_role_type: 'technician', p_code: null, p_can_fit_stages: [] } }], 'mutation dispatch is bound to token A');
    token = 'token-b';
    identity = 'principal-b\nadministrator';
    mutation.resolve({ status: 200, ok: true, body: { ok: true } });
    const result = await pending;
    assert.deepStrictEqual(result, { ok: false, error: 'stale_authority' }, 'delayed success after authority replacement fails closed');
    assert.strictEqual(calls.length, 1, 'delayed stale success performs no list reload with token B');
    assert.strictEqual(notifications, 0, 'delayed stale success publishes no state');
  }

  {
    let token = 'token-a';
    const mutation = deferred();
    const calls = [];
    const service = createWorkshopReferenceDataService({
      client: {
        rpc: async (usedToken, name) => {
          calls.push({ token: usedToken, name });
          return mutation.promise;
        },
      },
      getAccessToken: () => token,
      getAuthorityIdentity: () => 'principal-a\nadministrator',
    });

    const pending = service.setTechnicianActive('tech-1', 1, false);
    await tick();
    token = 'token-b';
    mutation.reject(new Error('network failed after replacement'));
    const result = await pending;
    assert.deepStrictEqual(result, { ok: false, error: 'stale_authority' }, 'delayed rejection after token replacement fails closed instead of escaping into replacement authority');
    assert.strictEqual(calls.length, 1, 'delayed stale rejection performs no follow-up RPC');
  }

  {
    let token = 'token-a';
    let identity = 'principal-a\nadministrator';
    const update = deferred();
    const calls = [];
    const service = createWorkshopReferenceDataService({
      client: {
        rpc: async (usedToken, name) => {
          calls.push({ token: usedToken, name });
          if (name === 'update_workshop_configuration') return update.promise;
          if (name === 'get_workshop_configuration') return { status: 200, ok: true, body: {} };
          return { status: 404, ok: false, body: {} };
        },
      },
      getAccessToken: () => token,
      getAuthorityIdentity: () => identity,
    });

    const pending = service.updateWorkshopConfiguration('day_start_time', 1, '07:30');
    await tick();
    token = 'token-b';
    identity = 'principal-b\nadministrator';
    update.resolve({ status: 200, ok: true, body: { ok: true } });
    const result = await pending;
    assert.deepStrictEqual(result, { ok: false, error: 'stale_authority' }, 'stale settings write completion fails closed');
    assert.deepStrictEqual(calls, [{ token: 'token-a', name: 'update_workshop_configuration' }], 'stale settings completion never reloads with token B');
  }

  {
    let identity = 'principal-a\nadministrator';
    let rpcCalls = 0;
    const service = createWorkshopReferenceDataService({
      client: { rpc: async () => { rpcCalls += 1; return { status: 200, ok: true, body: { ok: true } }; } },
      getAccessToken: () => 'shared-token',
      getAuthorityIdentity: () => identity,
    });
    identity = 'principal-b\nadministrator';
    const principalResult = await service.setWorkshopBayActive('bay-1', 1, true);
    assert.strictEqual(principalResult.error, 'stale_authority', 'same-token principal replacement must fail closed');
    assert.strictEqual(rpcCalls, 0, 'same-token principal replacement must not dispatch');
  }

  {
    let identity = 'principal-a\nadministrator';
    let rpcCalls = 0;
    const service = createWorkshopReferenceDataService({
      client: { rpc: async () => { rpcCalls += 1; return { status: 200, ok: true, body: { ok: true } }; } },
      getAccessToken: () => 'shared-token',
      getAuthorityIdentity: () => identity,
    });
    identity = 'principal-a\nviewer';
    const roleResult = await service.updateWorkshopConfiguration('day_start_time', 1, '07:00');
    assert.strictEqual(roleResult.error, 'stale_authority', 'same-token role demotion must fail closed');
    assert.strictEqual(rpcCalls, 0, 'same-token role demotion must not dispatch');
  }

  {
    let onChange;
    let onStatus;
    let token = 'token-a';
    const calls = [];
    let notifications = 0;
    const service = createWorkshopReferenceDataService({
      client: {
        rpc: async (usedToken, name) => {
          calls.push({ token: usedToken, name });
          return { status: 200, ok: true, body: [] };
        },
      },
      getAccessToken: () => token,
      getAuthorityIdentity: () => 'principal-a\nadministrator',
      subscribeRealtime: (_table, handlers) => {
        onChange = handlers.onChange;
        onStatus = handlers.onStatus;
        return { unsubscribe() {} };
      },
      onStateChange: () => { notifications += 1; },
    });

    service.subscribeTechnicians();
    assert.strictEqual(typeof service.destroy, 'function', 'service exposes authority-destroy lifecycle');
    service.destroy();
    token = 'token-b';
    onChange({});
    onStatus('TIMED_OUT');
    await tick();
    assert.strictEqual(calls.length, 0, 'queued realtime callback from destroyed service performs no RPC');
    assert.strictEqual(notifications, 0, 'queued realtime callback from destroyed service publishes no state');
    assert.deepStrictEqual(service.getCachedTechnicians().rows, [], 'destroy clears disposable authority-bound cache');
  }

  {
    let token = 'token-a';
    const calls = [];
    const service = createWorkshopReferenceDataService({
      client: {
        rpc: async (usedToken, name) => {
          calls.push({ token: usedToken, name });
          if (name === 'add_technician') return { status: 200, ok: true, body: { ok: true } };
          if (name === 'list_technicians') return { status: 200, ok: true, body: [{ id: 'tech-1', name: 'Alice', version: 1 }] };
          return { status: 404, ok: false, body: {} };
        },
      },
      getAccessToken: () => token,
      getAuthorityIdentity: () => 'principal-a\nadministrator',
    });

    const result = await service.addTechnician('Alice');
    assert.strictEqual(result.ok, true, 'same-authority mutation still succeeds');
    assert.deepStrictEqual(calls.map(call => [call.token, call.name]), [
      ['token-a', 'add_technician'],
      ['token-a', 'list_technicians'],
    ], 'same-authority mutation and resync use the same captured token');
  }

  console.log('PASS workshop reference service authority ownership');
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
