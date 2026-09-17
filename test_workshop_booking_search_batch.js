'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { createWorkshopDataService } = require('./workshop-data-service.js');
const id = number => `11111111-1111-4111-8111-${String(number).padStart(12, '0')}`;
const request = number => ({ vehicleId: id(number), dealerCode: number % 2 ? '14450' : '37047' });
const booking = (number, stage = 'FITTING') => ({ booking_id: id(number + 100), booking_version: 7,
  stage_code: stage, bay_number: 2, status: 'planned', default_duration_minutes: 120,
  scheduled_start_at: '2026-09-18T08:00:00Z', scheduled_end_at: '2026-09-21T00:00:00Z' });
const result = (number, bookings = [booking(number)]) => ({ ok: true, vehicle_id: id(number), dealer_code: request(number).dealerCode, bookings });
const reply = results => ({ ok: true, body: { ok: true, results } });
const missing = { ok: false, status: 404, body: { code: 'PGRST202' } };
function setup(respond, options = {}) {
  const calls = []; let token = 'session'; let role = 'operator';
  const service = createWorkshopDataService({ config: { workshop: { sharedData: true } },
    getAccessToken: () => token, getRole: () => role, ...options,
    client: { rpc: async (auth, name, params, settings) => { calls.push({ auth, name, params, settings }); return respond(name, params, settings); } } });
  return { service, calls, setToken: value => { token = value; }, setRole: value => { role = value; } };
}

test('25 exact mixed-dealer identities take one metadata request and preserve every date/station', async () => {
  const requests = Array.from({ length: 25 }, (_, i) => request(i + 1));
  const { service, calls } = setup(() => reply(requests.map((_, i) => result(i + 1,
    [booking(i + 1, i % 2 ? 'HOIST' : 'ELECTRICAL')]))));
  const response = await service.lookupVehicleBookingsBatch(requests);
  assert.equal(response.ok, true); assert.equal(response.results.length, 25); assert.equal(calls.length, 1);
  assert.equal(calls[0].name, 'get_workshop_booking_search_scoped');
  assert.deepEqual(calls[0].params, { p_vehicles: requests.map(r => ({ vehicle_id: r.vehicleId, dealer_code: r.dealerCode })) });
  assert.equal(response.results[0].bookings[0].stage_code, 'ELECTRICAL');
  assert.equal(response.results[1].bookings[0].stage_code, 'HOIST');
  assert.equal(response.results[0].bookings[0].scheduled_end_at, '2026-09-21T00:00:00Z');
  assert.equal(response.results[0].bookings[0].booking_version, 7);
  assert.equal(service.getLastSnapshot(), null); assert.equal(service.getTrustedSnapshot(), null);
});

test('individual dealer denial is distinct from authorized empty bookings', async () => {
  const { service } = setup(() => reply([{ ...result(1), ok: false, error: 'dealer_scope_denied', bookings: undefined }, result(2, [])]));
  const response = await service.lookupVehicleBookingsBatch([request(1), request(2)]);
  assert.equal(response.ok, true); assert.equal(response.results[0].ok, false);
  assert.equal(response.results[0].bookings, undefined); assert.deepEqual(response.results[1].bookings, []);
});

test('batch identity, completeness, exact dealers and booking versions fail closed', async () => {
  const responses = [
    [result(1)], [result(1), result(1)], [result(1), result(3)],
    [result(1), { ...result(2), dealer_code: '14450' }],
    [result(1), result(2, [{ ...booking(2), booking_version: null }])],
    [result(1), result(2, [booking(1)])],
  ];
  for (const results of responses) {
    const { service } = setup(() => reply(results));
    assert.equal((await service.lookupVehicleBookingsBatch([request(1), request(2)])).error, 'invalid_response');
  }
  const { service, calls } = setup(() => { throw Error('invalid requests must not issue reads'); });
  for (const requests of [[], [request(1), request(1)], [request(1), { vehicleId: 'stock-123', dealerCode: '14450' }],
    Array.from({ length: 26 }, (_, i) => request(i + 1))]) {
    assert.equal((await service.lookupVehicleBookingsBatch(requests)).error, 'invalid_identity');
  }
  assert.equal(calls.length, 0);
});

test('only the missing-RPC response permits a fallback, capped at four vehicle details', async () => {
  const f = setup((name, params) => name === 'get_workshop_booking_search_scoped' ? missing
    : { ok: true, body: { vehicle_id: params.p_vehicle_id, bookings: [] } });
  assert.equal((await f.service.lookupVehicleBookingsBatch([1, 2, 3, 4].map(request))).ok, true);
  assert.equal(f.calls.length, 5);
  const broad = setup(() => missing);
  assert.equal((await broad.service.lookupVehicleBookingsBatch([1, 2, 3, 4, 5].map(request))).error, 'booking_search_upgrade_required');
  assert.equal(broad.calls.length, 1);
  for (const response of [{ ok: false, status: 403 }, { ok: false, status: 500 }, { ok: false, status: 404 },
    { ok: true, body: { ok: false, error: 'dealer_scope_denied' } }]) {
    const { service, calls } = setup(() => response);
    assert.equal((await service.lookupVehicleBookingsBatch([request(1)])).ok, false);
    assert.equal(calls.length, 1);
  }
});

test('role, token, lifecycle and scope changes discard the complete late batch', async () => {
  for (const change of ['role', 'token', 'lost', 'scope', 'destroy']) {
    let release;
    const f = setup(name => name === 'get_workshop_booking_search_scoped' ? new Promise(resolve => { release = resolve; })
      : { ok: true, body: { revision: 1, bookings: [] } });
    const pending = f.service.lookupVehicleBookingsBatch([request(1), request(2)]);
    if (change === 'role') f.setRole('viewer');
    if (change === 'token') f.setToken('other');
    if (change === 'lost') f.service.onAuthorityLost();
    if (change === 'destroy') f.service.destroy();
    if (change === 'scope') await f.service.setScope({ stageCode: 'TYRE', dateFrom: '2026-09-22', dateTo: '2026-09-22' });
    release(reply([result(1), result(2)]));
    assert.equal((await pending).error, 'authority_superseded');
  }
});

test('a timed-out batch is aborted and cannot launch late fallback detail reads', async () => {
  let release; let expire;
  const f = setup(() => new Promise(resolve => { release = resolve; }), {
    scheduleTimeout: fn => { expire = fn; return 1; }, clearScheduledTimeout: () => {},
  });
  const pending = f.service.lookupVehicleBookingsBatch([request(1)]);
  expire(); assert.equal((await pending).ok, false);
  assert.equal(f.calls[0].settings.signal.aborted, true);
  release(missing); await Promise.resolve(); await Promise.resolve();
  assert.equal(f.calls.length, 1);
});

const source = fs.readFileSync(require.resolve('./workshop-planner.js'), 'utf8');
function extract(name) {
  const start = source.indexOf(`async function ${name}(`);
  const tail = source.slice(start); const next = /\n(?:async )?function \w+\(/.exec(tail);
  return next ? tail.slice(0, next.index) : tail;
}
function planner() {
  let snapshot = {}; let release; let batchCalls = 0; let singleCalls = 0;
  const candidates = Array.from({ length: 26 }, (_, i) => ({ vehicleIdentity: `shared:${id(i + 1)}`, vehicle: { dealer: request(i + 1).dealerCode } }));
  const state = { search: 'Example' };
  const service = { getTrustedSnapshot: () => snapshot,
    lookupVehicleBookings: async () => { singleCalls++; throw Error('search must use batch'); },
    lookupVehicleBookingsBatch: requests => { batchCalls++; assert.equal(requests.length, 25); return new Promise(resolve => { release = resolve; }); } };
  const c = vm.createContext({ window: { __workshopDataService: service }, workshopState: () => state,
    workshopSharedModeActive: () => true, cleanNavisionText: value => value.trim(), workshopCurrentSearchLookup: () => null,
    workshopSearchMatchRows: () => candidates, workshopLoadPlans: () => [],
    vehicleWorkshopDetailRequestDealerCode: vehicle => vehicle.dealer,
    workshopMapSearchBookings: result => result.bookings });
  vm.runInContext(extract('workshopLoadSearchBookings'), c);
  return { c, state, service, resolve: () => release({ ok: true, results: Array.from({ length: 25 }, (_, i) => ({ ok: true,
    vehicleId: id(i + 1), dealerCode: request(i + 1).dealerCode, bookings: [booking(i + 1)] })) }),
    replaceSnapshot: () => { snapshot = {}; }, counts: () => ({ batchCalls, singleCalls }) };
}

test('planner search sends all 25 candidates once and retains its result cap', async () => {
  const f = planner(); const pending = f.c.workshopLoadSearchBookings('Example'); f.resolve(); await pending;
  assert.deepEqual(f.counts(), { batchCalls: 1, singleCalls: 0 });
  assert.equal(f.state.bookingSearchLookup.matches.size, 25); assert.equal(f.state.bookingSearchLookup.limited, true);
  assert.equal(f.state.bookingSearchLookup.status, 'ready');
});

test('query or trusted-snapshot changes cannot publish a late batch into current search', async () => {
  for (const change of ['query', 'snapshot', 'service']) {
    const f = planner(); const pending = f.c.workshopLoadSearchBookings('Example');
    if (change === 'query') f.state.search = 'other';
    if (change === 'snapshot') f.replaceSnapshot();
    if (change === 'service') f.c.window.__workshopDataService = {};
    f.resolve(); await pending;
    assert.equal(f.state.bookingSearchLookup.matches.size, 0); assert.notEqual(f.state.bookingSearchLookup.status, 'ready');
  }
});
