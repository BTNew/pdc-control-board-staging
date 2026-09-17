'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { createWorkshopReferenceDataService, createWorkshopReferenceSupabaseClient } = require('./workshop-reference-data-service');
const tick = () => new Promise(resolve => setImmediate(resolve));
const deferred = () => { let resolve; const promise = new Promise(done => { resolve = done; }); return { promise, resolve }; };
const bay = (version = 1, technician = null) => ({ id: 'bay-one', code: 'FITTING-BAY-01', version, default_technician_id: technician });
const response = body => ({ ok: true, status: 200, body });

function fixture() {
  let token = 'session-one', scopeCurrent = true, row = bay(), timerId = 0;
  let read = async () => response([{ ...row }]);
  let write = async params => { assert.equal(params.p_expected_version, row.version); row = bay(row.version + 1, params.p_technician_id); return response({ ok: true }); };
  const calls = [], timers = new Map();
  const service = createWorkshopReferenceDataService({ getAccessToken: () => token,
    scheduleTimeout: (fn, ms) => { const id = ++timerId; timers.set(id, { fn, ms }); return id; }, clearScheduledTimeout: id => timers.delete(id),
    client: { rpc: async (accessToken, name, params, options) => {
      calls.push({ accessToken, name, params, options });
      return name === 'list_workshop_bays' ? read() : write(params);
    } },
  });
  return { service, calls, timers, row: () => row, setRow: value => { row = value; }, setRead: fn => { read = fn; }, setWrite: fn => { write = fn; },
    setToken: value => { token = value; }, supersede: () => { scopeCurrent = false; },
    warm: () => service.listWorkshopBays(true),
    assign: (value = 'new-technician', expected = 1, context = {}) => service.setBayDefaultTechnician('bay-one', expected, value, { isCurrent: () => scopeCurrent, ...context }),
    writes: () => calls.filter(call => call.name === 'set_bay_default_technician'),
    fire: () => { const timer = [...timers][0]; assert.ok(timer); timers.delete(timer[0]); timer[1].fn(); },
  };
}

test('stale cached version is replaced by a fresh authoritative version before assignment', async () => {
  const h = fixture(); await h.warm(); h.setRow(bay(9));
  assert.equal((await h.assign()).ok, true);
  assert.equal(h.writes()[0].params.p_expected_version, 9);
  assert.equal(h.service.getCachedWorkshopBays().rows[0].version, 10);
  assert.equal(h.service.getCachedWorkshopBays().rows[0].default_technician_id, 'new-technician');
  assert.equal(h.timers.size, 0);
});

test('cleared bay can be reassigned despite cached former technician', async () => {
  const h = fixture(); h.setRow(bay(3, 'former-technician')); await h.warm(); h.setRow(bay(4, null));
  assert.equal((await h.assign('replacement', 3)).ok, true);
  assert.equal(h.writes()[0].params.p_expected_version, 4); assert.equal(h.row().default_technician_id, 'replacement');
});

test('a fresh different technician is never overwritten by a stale selection', async () => {
  const h = fixture(); await h.warm(); h.setRow(bay(2, 'concurrent-technician'));
  assert.equal((await h.assign()).error, 'bay_assignment_changed'); assert.equal(h.writes().length, 0);
  assert.equal(h.service.getCachedWorkshopBays().rows[0].default_technician_id, 'concurrent-technician');
});

test('explicit observed technician protects the original selection even after cache refresh', async () => {
  const h = fixture(); h.setRow(bay(2, 'concurrent-technician')); await h.warm();
  assert.equal((await h.assign('new-technician', 1, { observedTechnicianId: null })).error, 'bay_assignment_changed');
  assert.equal(h.writes().length, 0);
});

test('unchanged existing technician can be deliberately reassigned or cleared', async () => {
  for (const desired of ['replacement', null]) {
    const h = fixture(); h.setRow(bay(2, 'old-technician')); await h.warm(); h.setRow(bay(3, 'old-technician'));
    assert.equal((await h.assign(desired, 2)).ok, true); assert.equal(h.row().default_technician_id, desired);
    assert.equal(h.writes().length, 1);
  }
});

test('already selected technician merges without any mutation', async () => {
  const h = fixture(); await h.warm(); h.setRow(bay(3, 'new-technician'));
  const result = await h.assign(); assert.equal(result.ok, true); assert.equal(result.alreadyApplied, true);
  assert.equal(h.writes().length, 0);
});

test('missing original bay cache does not authorize overwriting a newer non-null assignment', async () => {
  const h = fixture(); h.setRow(bay(5, 'concurrent-technician'));
  assert.equal((await h.assign('replacement', 1)).error, 'bay_assignment_changed'); assert.equal(h.writes().length, 0);
});

for (const shape of ['error', 'code']) {
  test(`one definitive ${shape} version conflict retries only once with fresh unchanged default`, async () => {
    const h = fixture(); await h.warm(); let writes = 0;
    h.setWrite(async params => {
      if (++writes === 1) { h.setRow(bay(2)); return response({ ok: false, [shape]: 'version_conflict' }); }
      assert.equal(params.p_expected_version, 2); h.setRow(bay(3, params.p_technician_id)); return response({ ok: true });
    });
    assert.equal((await h.assign()).ok, true); assert.deepEqual(h.writes().map(call => call.params.p_expected_version), [1,2]);
    assert.equal(h.timers.size, 0);
  });
}

test('repeated version conflicts are bounded to two writes', async () => {
  const h = fixture(); await h.warm();
  h.setWrite(async () => { h.setRow(bay(h.row().version + 1)); return response({ ok: false, error: 'version_conflict' }); });
  assert.equal((await h.assign()).error, 'version_conflict'); assert.equal(h.writes().length, 2);
});

test('a competing non-null default during a conflict prevents retry', async () => {
  const h = fixture(); h.setRow(bay(1, 'original')); await h.warm(); h.setRow(bay(2));
  h.setWrite(async () => { h.setRow(bay(3, 'original')); return response({ ok: false, error: 'version_conflict' }); });
  assert.equal((await h.assign()).error, 'bay_assignment_changed'); assert.equal(h.writes().length, 1);
});

test('another writer applying the same selected technician merges the rejected attempt', async () => {
  const h = fixture(); await h.warm();
  h.setWrite(async () => { h.setRow(bay(2, 'new-technician')); return response({ ok: false, error: 'version_conflict' }); });
  const result = await h.assign(); assert.equal(result.ok, true); assert.equal(result.alreadyApplied, true); assert.equal(h.writes().length, 1);
});

test('failed, missing or malformed fresh bay authority never falls back to cached version', async () => {
  const results = [{ ok: false, status: 503 }, { ok: false, status: 403 }, response([]), response([bay(), bay()]),
    response([{ id: 'bay-one', default_technician_id: null }]), response([{ ...bay(), version: null }]), response([{ ...bay(), version: '2' }]),
    response([{ id: 'bay-one', version: 2 }]), response({ bays: [bay()] })];
  for (const result of results) {
    const h = fixture(); await h.warm(); h.setRead(async () => result);
    assert.equal((await h.assign()).ok, false); assert.equal(h.writes().length, 0); assert.equal(h.timers.size, 0);
    assert.deepEqual(h.service.getCachedWorkshopBays().rows, []);
  }
});

test('preflight transport exception releases assignment busy state', async () => {
  const h = fixture(); await h.warm(); h.setRead(async () => { throw Error('offline'); });
  assert.equal((await h.assign()).error, 'request_failed'); assert.equal(h.writes().length, 0);
  h.setRead(async () => response([h.row()])); assert.equal((await h.assign()).ok, true);
});

test('lost write response is not replayed and fresh matching value can confirm the intended result', async () => {
  for (const committed of [false,true]) {
    const h = fixture(); await h.warm();
    h.setWrite(async () => { if (committed) h.setRow(bay(2, 'new-technician')); throw Error('connection lost'); });
    const result = await h.assign(); assert.equal(result.ok, committed); assert.equal(h.writes().length, 1);
    if (!committed) assert.equal(result.outcomeUnknown, true); else assert.equal(result.alreadyApplied, true);
    assert.equal(h.timers.size, 0);
  }
});

test('truncated or malformed successful HTTP replies preserve write uncertainty without replay', async () => {
  for (const body of [null, {}, 'partial-json']) for (const committed of [false,true]) {
    const h = fixture(); await h.warm();
    h.setWrite(async () => { if (committed) h.setRow(bay(2, 'new-technician')); return response(body); });
    const result = await h.assign(); assert.equal(result.ok, committed); assert.equal(h.writes().length, 1);
    if (committed) assert.equal(result.alreadyApplied, true); else assert.equal(result.outcomeUnknown, true);
    assert.equal(h.timers.size, 0);
  }
});

test('confirmed save survives failed or subsequently changed readback without claiming the displayed assignment is current', async () => {
  for (const readback of [{ ok: false, status: 503 }, response([bay(3, 'another-technician')])]) {
    const h = fixture(); await h.warm(); h.setWrite(async () => { h.setRead(async () => readback); return response({ ok: true }); });
    const result = await h.assign(); assert.equal(result.ok, true); assert.equal(result.refreshRequired, true);
    assert.equal(result.reconciliation, readback.ok ? 'changed_after_save' : 'pending'); assert.equal(h.writes().length, 1);
  }
});

test('permission and other canonical rejections are surfaced without retries', async () => {
  for (const result of [{ ok: false, status: 403, body: { code: '42501' } }, response({ ok: false, code: 'technician_not_found' }),
    response({ ok: false, error: 'bay_inactive' }), { ok: false, status: 500, body: { message: 'unavailable' } }]) {
    const h = fixture(); await h.warm(); h.setWrite(async () => result);
    const rejected = await h.assign(); assert.equal(rejected.ok, false); assert.notEqual(rejected.error, undefined); assert.equal(h.writes().length, 1);
    if (result.status === 403) assert.deepEqual(h.service.getCachedWorkshopBays().rows, []);
    if (result.status === 500) assert.equal(rejected.outcomeUnknown, true);
  }
});

test('token, scope and teardown changes prevent queued writes and late prior-authority readback', async () => {
  for (const phase of ['preflight','write']) for (const change of ['token','scope','teardown']) {
    const h = fixture(); await h.warm(); const pending = deferred();
    if (phase === 'preflight') h.setRead(() => pending.promise); else h.setWrite(() => pending.promise);
    const request = h.assign(); await tick();
    if (change === 'token') h.setToken('session-two');
    if (change === 'scope') h.supersede();
    if (change === 'teardown') h.service.unsubscribeAll();
    const before = h.calls.length; pending.resolve(phase === 'preflight' ? response([bay(99)]) : response({ ok: true }));
    assert.equal((await request).error, 'authority_superseded'); assert.equal(h.calls.length, before);
    assert.equal(h.writes().length, phase === 'write' ? 1 : 0); assert.equal(h.timers.size, 0);
    assert.notEqual(h.service.getCachedWorkshopBays().rows[0]?.version, 99);
  }
});

test('simultaneous selections for one bay do not issue competing writes', async () => {
  const h = fixture(); await h.warm(); const pending = deferred(); h.setRead(() => pending.promise);
  const first = h.assign(); assert.equal((await h.assign('other-technician')).error, 'assignment_in_progress');
  h.setRead(async () => response([h.row()])); pending.resolve(response([h.row()])); assert.equal((await first).ok, true);
  assert.equal(h.writes().length, 1);
});

test('preflight timeout releases busy state; write timeout remains uncertain and never duplicates the write', async () => {
  for (const phase of ['preflight','write']) {
    const h = fixture(); await h.warm(); const pending = deferred();
    if (phase === 'preflight') h.setRead(() => pending.promise); else h.setWrite(() => pending.promise);
    const request = h.assign(); await tick(); h.fire(); await tick();
    const result = await request; assert.equal(result.error, 'request_timeout'); assert.equal(h.writes().length, phase === 'write' ? 1 : 0);
    if (phase === 'write') assert.equal(result.outcomeUnknown, true);
    assert.equal(h.calls.find(call => call.options?.signal?.aborted)?.options.signal.aborted, true);
    pending.resolve(response([bay(99)])); await tick(); assert.notEqual(h.service.getCachedWorkshopBays().rows[0]?.version, 99);
    assert.equal(h.timers.size, 0);
  }
});

test('reference transport forwards abort signal without changing normal request parameters', async () => {
  const controller = new AbortController(), calls = [];
  const client = createWorkshopReferenceSupabaseClient({ url: 'https://fixture.invalid', publishableKey: 'public-test' }, async (url, options) => {
    calls.push({ url, options }); return { ok: true, status: 200, json: async () => [] };
  });
  await client.rpc('session', 'list_workshop_bays', { p_include_inactive: true }, { signal: controller.signal });
  assert.equal(calls[0].options.signal, controller.signal); assert.equal(calls[0].options.headers.Authorization, 'Bearer session');
});

test('late readback from one bay cannot overwrite another bay assignment or newer reference failure state', async () => {
  for (const secondReadFails of [false,true]) {
    const late = deferred(); let reads = 0;
    const rows = [bay(), { ...bay(), id: 'bay-two', code: 'FITTING-BAY-02' }];
    const service = createWorkshopReferenceDataService({ getAccessToken: () => 'session', client: { rpc: async (_token, name, params) => {
      if (name === 'list_workshop_bays') {
        reads++;
        if (reads === 3) return late.promise;
        if (reads === 4 && secondReadFails) return { ok: false, status: 503 };
        return response(rows.map(row => ({ ...row })));
      }
      const target = rows.find(row => row.id === params.p_bay_id);
      assert.equal(params.p_expected_version, target.version);
      target.version++; target.default_technician_id = params.p_technician_id;
      return response({ ok: true });
    } } });
    await service.listWorkshopBays(true);
    const first = service.setBayDefaultTechnician('bay-one', 1, 'technician-one'); await tick();
    const earlierRows = rows.map(row => ({ ...row }));
    const second = await service.setBayDefaultTechnician('bay-two', 1, 'technician-two');
    assert.equal(second.ok, !secondReadFails);
    late.resolve(response(earlierRows)); assert.equal((await first).ok, true);
    const cache = service.getCachedWorkshopBays();
    if (secondReadFails) {
      assert.deepEqual(cache.rows, []); assert.equal(cache.state, 'offline_error', 'older readback must not mark a newer failed cache editable');
    } else {
      assert.equal(cache.rows.find(row => row.id === 'bay-two').default_technician_id, 'technician-two');
      assert.equal(cache.rows.find(row => row.id === 'bay-two').version, 2); assert.equal(cache.state, 'connected_editable');
    }
  }
});
