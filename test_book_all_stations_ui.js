'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const eligibility = require('./workshop-eligibility.js');
const emailVehicles = require('./pdc-email-vehicle-location-service.js');
const source = fs.readFileSync(__dirname + '/pdc-book-all-stations.js', 'utf8');
const id = 'a1234567-1234-4123-8123-123456789012';
const secondId = 'b1234567-1234-4123-8123-123456789012';
const flush = () => new Promise(resolve => setImmediate(resolve));
const deferred = () => { let resolve, reject; const promise = new Promise((a, b) => { resolve = a; reject = b; }); return { promise, resolve, reject }; };
const booked = () => ({ ok: true, bookings: [{ stage: 'HOIST', bay: 2, start_at: '2026-09-14T00:00:00Z', end_at: '2026-09-14T02:00:00Z' }], skipped: [{ stage: 'FITTING', reason: 'Already booked' }] });
const response = result => ({ ok: true, json: async () => result });

function setup(options = {}) {
  const elements = new Map(), listeners = {}, authListeners = {}, timers = new Map();
  const state = { refreshes: 0, plannerLoads: 0, renders: 0, token: 'fixture-token', nextTimer: 0 };
  const element = name => {
    if (!elements.has(name)) {
      let text = '', html = '';
      const handlers = {};
      elements.set(name, {
        get textContent() { return text; }, set textContent(value) { text = value; html = ''; },
        get innerHTML() { return html; }, set innerHTML(value) { html = value; text = ''; },
        disabled: false, open: false, setAttribute() {}, focus() {},
        addEventListener(event, handler) { handlers[event] = handler; },
        click() { if (!this.disabled) handlers.click?.({}); },
        showModal() { this.open = true; }, close() { this.open = false; },
        querySelector: element, insertAdjacentHTML(_position, value) { html += value; },
      });
    }
    return elements.get(name);
  };
  const serverVehicle = { id, permanent_vehicle_id: 'different-permanent-id', version: 3, current_location: 'PMB', stock_number: '12657478', lifecycle_state: 'active', visible_on_board: true, ...options.serverVehicle };
  const vehicle = { ...emailVehicles.mapServerVehicle(serverVehicle), ...options.vehicle };
  const calls = [];
  const context = {
    window: {
      PDC_SUPABASE_CONFIG: { projectRef: 'cdsmnqxtyyoeoznmbidd', url: 'https://staging.example', publishableKey: 'fixture' },
      PDC_AUTH_CONTEXT: { userId: 'fixture-operator', role: options.role || 'operator' },
      PDC_WORKSHOP_ELIGIBILITY: eligibility,
      addEventListener(event, handler) { authListeners[event] = handler; },
      __workshopDataService: { loadSnapshot(reason) { state.plannerLoads++; return options.plannerImpl ? options.plannerImpl(reason) : Promise.resolve(true); } },
    },
    document: { createElement: element, body: { appendChild() {} }, addEventListener(event, handler) { listeners[event] = handler; } },
    // Raw snapshot and mapped board DTOs deliberately retain different identities.
    app: { emailVehicleLocationService: {}, emailVehicleLocationRows: options.snapshotRows || [serverVehicle], data: options.mappedRows || [vehicle] },
    sharedNavisionLocationAuthorityReady: () => options.authorityReady !== false,
    renderIncomingDashboardBoard() { state.renders++; },
    displayStockNumber: row => row.stock,
    vehicleCustomerName: () => 'Fixture customer',
    getPdcSupabaseAccessToken: () => state.token,
    setTimeout(callback, milliseconds) { const timer = ++state.nextTimer; timers.set(timer, { callback, milliseconds }); return timer; },
    clearTimeout(timer) { timers.delete(timer); },
    refreshEmailVehicleLocations: async () => {
      state.refreshes++;
      if (options.refreshImpl) return options.refreshImpl(context, state.refreshes);
      if (options.refresh === false) return false;
      const refreshed = { ...serverVehicle, version: 7, ...options.freshServerVehicle };
      context.app.emailVehicleLocationRows = options.freshSnapshotRows || [refreshed];
      context.app.data = options.freshMappedRows || [{ ...emailVehicles.mapServerVehicle(refreshed), ...options.freshMappedVehicle }];
      return true;
    },
    fetch: async (url, request) => {
      calls.push({ url, request });
      if (options.fetchImpl) return options.fetchImpl(url, request, calls.length);
      if (options.throwFetch) throw Error('network');
      return response(options.result || booked());
    },
  };
  vm.runInNewContext(source, context);
  let prevented = 0, stopped = 0;
  const click = (targetId = id) => listeners.click({ target: { closest: () => ({ dataset: { bookAllStations: targetId }, disabled: false }) }, preventDefault() { prevented++; }, stopPropagation() { stopped++; } });
  const expire = milliseconds => {
    const matches = [...timers].filter(([, timer]) => timer.milliseconds === milliseconds);
    assert.ok(matches.length, `Expected an active ${milliseconds} ms timeout`);
    for (const [key, timer] of matches) { timers.delete(key); timer.callback(); }
  };
  return { context, state, api: context.window.PDC_BOOK_ALL_STATIONS, vehicle, serverVehicle, calls, click, elements, timers, expire,
    auth: event => authListeners[event](), propagation: () => ({ prevented, stopped }),
    get html() { return element('[data-book-all-result]').innerHTML; },
    get closeButton() { return element('[data-book-all-close]'); }, get dialog() { return element('dialog'); },
  };
}

test('writable canonical locations, persisted overrides, ETA and lifecycle determine eligibility', () => {
  const s = setup();
  for (const change of [{}, { current_location: 'YH' }, { current_location: 'IT', eta_to_kewdale: '2026-09-14' }, { current_location: 'QC', location_override: 'PMB' }]) {
    assert.equal(s.api.eligible(emailVehicles.mapServerVehicle({ ...s.serverVehicle, ...change })), true, JSON.stringify(change));
  }
  for (const change of [{ current_location: 'IT' }, { current_location: 'QC' }, { location_override: 'IT', eta_to_kewdale: null }]) {
    assert.equal(s.api.eligible(emailVehicles.mapServerVehicle({ ...s.serverVehicle, ...change })), false, JSON.stringify(change));
  }
  for (const change of [{ __emailVehicleId: 'wrong' }, { __locationIdentityReadOnly: true }, { deleted_at: '2026-09-11' }, { pdcSheetVisible: false }, { lifecycleState: 'collected' }]) {
    assert.equal(s.api.eligible({ ...s.vehicle, ...change }), false, JSON.stringify(change));
  }
  assert.equal(setup({ role: 'viewer' }).api.eligible(s.vehicle), false);
  assert.equal(setup({ authorityReady: false }).api.eligible(s.vehicle), false);
});

test('action replaces source text while preserving lifecycle controls and column structure', () => {
  const s = setup();
  const html = s.api.actionHtml(s.vehicle, '<span class="badge neutral">Imported by email · Read only</span><button data-yh-transfer-pmb="key">To PMB</button>');
  assert.match(html, /Book all stations/);
  assert.ok(html.indexOf('data-yh-transfer-pmb') < html.indexOf('data-book-all-stations'));
  assert.doesNotMatch(html, /Read only|<small>|grid-template|incoming-card-action/);
  assert.equal(s.api.actionHtml(emailVehicles.mapServerVehicle({ ...s.serverVehicle, current_location: 'QC' }), 'Keep QC'), 'Keep QC');
});

test('matching cache dispatches version 3 immediately without refresh and ignores double-click', async () => {
  const gate = deferred(), s = setup({ fetchImpl: () => gate.promise });
  assert.equal(s.context.app.emailVehicleLocationRows[0].__emailVehicleId, undefined);
  assert.notEqual(s.vehicle.id, id);
  s.click(); s.click();
  assert.equal(s.calls.length, 1);
  assert.equal(s.state.refreshes, 0);
  assert.equal(s.state.plannerLoads, 0);
  assert.match(s.calls[0].url, /\/rpc\/book_all_vehicle_stations$/);
  assert.deepEqual(JSON.parse(s.calls[0].request.body), { p_vehicle_id: id, p_expected_version: 3 });
  assert.deepEqual(s.propagation(), { prevented: 2, stopped: 2 });
  assert.equal(s.closeButton.disabled, true);
  gate.resolve(response(booked())); await flush();
  for (const text of [/1 station booked/, /Bay 2/, /Already booked/, /Sublet is excluded/, /1-hour gap/]) assert.match(s.html, text);
  assert.equal(s.timers.size, 0);
});

test('both reported PMB stocks dispatch using cached canonical identity and version', async () => {
  for (const stock_number of ['12238276', '12657478']) {
    const s = setup({ serverVehicle: { stock_number } });
    s.click(); await flush();
    assert.equal(s.calls.length, 1, stock_number);
    assert.deepEqual(JSON.parse(s.calls[0].request.body), { p_vehicle_id: id, p_expected_version: 3 });
  }
});

test('Busselton Yard Hold imports book without ETA or Navision vehicle details', async () => {
  for (const current_location of ['Yard Hold', 'YH', ' yard hold ']) {
    const s = setup({ serverVehicle: { stock_number: '12728609', customer_name: 'BUSSELTON TOYOTA', current_location,
      eta_to_kewdale: null, vehicle_description: null, model: null, navision_record_id: null } });
    assert.equal(s.api.eligible(s.vehicle), true, current_location);
    s.click(); await flush();
    assert.equal(s.calls.length, 1, current_location);
    assert.equal(JSON.parse(s.calls[0].request.body).p_expected_version, 3);
    assert.match(s.html, /1 station booked/);
    assert.equal(s.context.app.emailVehicleLocationRows[0].eta_to_kewdale, null);
    assert.equal(s.context.app.emailVehicleLocationRows[0].vehicle_description, null);
  }
});

test('persisted Yard Hold override is authoritative but a mapped-only override cannot authorize QC', async () => {
  const persisted = setup({ serverVehicle: { current_location: 'QC', location_override: 'Yard Hold' } });
  persisted.click(); await flush(); assert.equal(persisted.calls.length, 1);
  const displayOnly = setup({ serverVehicle: { current_location: 'QC' }, vehicle: { pdcLocationOverride: 'Yard Hold' } });
  assert.equal(displayOnly.api.eligible(displayOnly.vehicle), true);
  displayOnly.click(); await flush();
  assert.equal(displayOnly.calls.length, 0);
  assert.match(displayOnly.html, /no longer eligible/);
});

test('raw eligibility rejects stale mapped PMB overlays without refresh or dispatch', async () => {
  for (const rawChange of [{ current_location: 'QC' }, { current_location: 'IT', eta_to_kewdale: null },
    { current_location: 'IT', eta_to_kewdale: 'not-a-date' }, { visible_on_board: false },
    { deleted_at: '2026-09-14' }, { lifecycle_state: 'collected' }, { location_override: 'IT', eta_to_kewdale: null }]) {
    const s = setup(); Object.assign(s.context.app.emailVehicleLocationRows[0], rawChange);
    s.click(); await flush();
    assert.equal(s.calls.length, 0, JSON.stringify(rawChange));
    assert.equal(s.state.refreshes, 0);
    assert.match(s.html, /no longer eligible/);
  }
});

test('missing or mismatched cache refreshes once before dispatching reconciled version 7', async () => {
  for (const mismatch of [false, true]) {
    const gate = deferred(), s = setup({ fetchImpl: () => gate.promise });
    if (mismatch) s.context.app.emailVehicleLocationRows[0].version = 4;
    else s.context.app.emailVehicleLocationRows = [];
    s.click(); assert.equal(s.calls.length, 0); await flush();
    assert.equal(s.state.refreshes, 1);
    assert.equal(s.state.plannerLoads, 0);
    assert.equal(s.calls.length, 1);
    assert.equal(JSON.parse(s.calls[0].request.body).p_expected_version, 7);
    gate.resolve(response(booked())); await flush();
  }
});

test('fallback never chooses a missing, duplicate or version-mismatched canonical row', async () => {
  const row = { id, version: 7, stock_number: '12657478', current_location: 'PMB' };
  for (const options of [{ freshSnapshotRows: [] }, { freshSnapshotRows: [row, { ...row, version: 8 }] },
    { freshMappedVehicle: { __emailVehicleVersion: 3 } },
    { freshMappedRows: [emailVehicles.mapServerVehicle(row), emailVehicles.mapServerVehicle(row)] }]) {
    const s = setup({ snapshotRows: [], ...options }); s.click(); await flush();
    assert.equal(s.calls.length, 0, JSON.stringify(options));
    assert.equal(s.state.refreshes, 1);
    assert.match(s.html, /could not be matched safely/);
  }
});

test('duplicate initial mapped identities cannot authorize a refresh or booking', async () => {
  const s = setup(); s.context.app.data.push({ ...s.vehicle }); s.click(); await flush();
  assert.equal(s.calls.length, 0); assert.equal(s.state.refreshes, 0);
});

test('duplicate initial raw identities require reconciliation before dispatch', async () => {
  const gate = deferred(), s = setup({ fetchImpl: () => gate.promise });
  s.context.app.emailVehicleLocationRows.push({ ...s.serverVehicle, version: 4 });
  s.click(); assert.equal(s.calls.length, 0); await flush();
  assert.equal(s.state.refreshes, 1); assert.equal(s.calls.length, 1);
  assert.equal(JSON.parse(s.calls[0].request.body).p_expected_version, 7);
  gate.resolve(response(booked())); await flush();
});

test('fallback rechecks fresh location and identity restrictions before dispatch', async () => {
  for (const options of [{ freshServerVehicle: { current_location: 'QC' } },
    { freshMappedVehicle: { __locationIdentityReadOnly: true, __emailVehicleIdentityConflict: true } }]) {
    const s = setup({ snapshotRows: [], ...options }); s.click(); await flush();
    assert.equal(s.calls.length, 0); assert.match(s.html, /no longer eligible/);
  }
});

test('failed fallback sends no booking request and permits closing', async () => {
  const s = setup({ snapshotRows: [], refresh: false }); s.click(); await flush();
  assert.equal(s.calls.length, 0); assert.match(s.html, /No booking request was sent/);
  assert.equal(s.closeButton.disabled, false);
});

test('saved summary and Close are available while board and planner refresh in parallel', async () => {
  const board = deferred(), planner = deferred();
  const s = setup({ refreshImpl: () => board.promise, plannerImpl: () => planner.promise });
  s.click(); await flush();
  assert.equal(s.state.refreshes, 1); assert.equal(s.state.plannerLoads, 1);
  assert.match(s.html, /1 station booked/); assert.equal(s.closeButton.disabled, false);
  assert.match(s.api.actionHtml(s.vehicle), /Updating board/);
  s.click(); assert.equal(s.calls.length, 1);
  s.closeButton.click(); assert.equal(s.dialog.open, false);
  board.resolve(true); planner.resolve(true); await flush();
  assert.equal(s.calls.length, 1); assert.doesNotMatch(s.api.actionHtml(s.vehicle), /disabled/);
});

test('explicit version conflict is shown immediately with parallel refresh and no automatic retry', async () => {
  const board = deferred(), planner = deferred();
  const s = setup({ result: { ok: false, error: 'vehicle_version_conflict' }, refreshImpl: () => board.promise, plannerImpl: () => planner.promise });
  s.click(); await flush();
  assert.match(s.html, /changed since the board loaded/); assert.match(s.html, /No new bookings were saved/);
  assert.equal(s.closeButton.disabled, false); assert.equal(s.state.refreshes, 1); assert.equal(s.state.plannerLoads, 1);
  board.resolve(true); planner.resolve(true); await flush(); assert.equal(s.calls.length, 1);
});

test('concrete server rejection is escaped and does not refresh or retry', async () => {
  const s = setup({ result: { ok: false, error: 'missing_hours', message: 'Fitting <line 4> needs hours.' } });
  s.click(); await flush(); assert.match(s.html, /Fitting &lt;line 4&gt; needs hours/);
  assert.equal(s.closeButton.disabled, false); assert.equal(s.calls.length, 1); assert.equal(s.state.refreshes, 0);
});

test('network and malformed response failures remain uncertain without retry or false rollback', async () => {
  for (const options of [{ throwFetch: true }, { fetchImpl: async () => ({ ok: true, json: async () => { throw Error('bad JSON'); } }) }]) {
    const s = setup(options); s.click(); await flush();
    assert.match(s.html, /could not be confirmed/); assert.doesNotMatch(s.html, /station booked|No booking request|No new bookings/);
    assert.equal(s.calls.length, 1); assert.equal(s.state.refreshes, 0); assert.equal(s.closeButton.disabled, false);
  }
});

test('bounded write timeout releases Close and ignores eventual write completion', async () => {
  const gate = deferred(), s = setup({ fetchImpl: () => gate.promise });
  s.click(); await flush(); s.expire(90000); await flush();
  assert.match(s.html, /could not be confirmed/); assert.equal(s.closeButton.disabled, false);
  const uncertain = s.html; gate.resolve(response(booked())); await flush();
  assert.equal(s.html, uncertain); assert.equal(s.calls.length, 1); assert.equal(s.state.refreshes, 0);
});

test('write deadline also bounds a response body that never finishes decoding', async () => {
  const body = deferred(), s = setup({ fetchImpl: async () => ({ ok: true, json: () => body.promise }) });
  s.click(); await flush(); s.expire(90000); await flush();
  assert.match(s.html, /could not be confirmed/); assert.equal(s.closeButton.disabled, false);
  const uncertain = s.html; body.resolve(booked()); await flush();
  assert.equal(s.html, uncertain); assert.equal(s.calls.length, 1); assert.equal(s.state.refreshes, 0);
});

test('bounded fallback timeout sends no request even after the old refresh later completes', async () => {
  const gate = deferred(), s = setup({ snapshotRows: [], refreshImpl: () => gate.promise });
  s.click(); await flush(); s.expire(60000); await flush();
  assert.match(s.html, /No booking request was sent/); assert.equal(s.closeButton.disabled, false);
  gate.resolve(true); await flush(); assert.equal(s.calls.length, 0);
});

test('failed or timed-out post-save refresh retains success with an honest warning', async () => {
  for (const failure of ['false', 'reject', 'timeout']) {
    const gate = deferred();
    const s = setup({ refreshImpl: () => failure === 'false' ? false : failure === 'reject' ? Promise.reject(Error('offline')) : gate.promise });
    s.click(); await flush();
    if (failure === 'timeout') { assert.equal(s.closeButton.disabled, false); s.expire(60000); await flush(); }
    assert.match(s.html, /1 station booked/); assert.match(s.html, /bookings were saved/); assert.match(s.html, /Refresh the board/);
    assert.equal(s.calls.length, 1); assert.equal(s.closeButton.disabled, false);
    gate.resolve(true); await flush();
  }
});

test('planner resolved failures preserve booking success and warn, while connected snapshots do not', async () => {
  const retained = { revision: 10, bookings: [] };
  for (const [connection, snapshot, warn] of [
    ['offline_read_only', retained, true], ['offline_read_only', null, true],
    ['permission_denied', retained, true], ['permission_denied', null, true],
    ['connected_editable', null, true], ['connected_editable', false, true],
    ['connected_editable', retained, false], ['connected_read_only', retained, false],
  ]) {
    const planner = deferred(), s = setup({ plannerImpl: () => planner.promise });
    s.context.window.__workshopDataService.getState = () => connection;
    s.click(); await flush();
    assert.match(s.html, /1 station booked/);
    assert.equal(s.closeButton.disabled, false);
    planner.resolve(snapshot); await flush();
    const scenario = `${connection}: ${JSON.stringify(snapshot)}`;
    assert.match(s.html, /1 station booked/, scenario);
    assert.equal(/The bookings were saved\. Refresh the board/.test(s.html), warn, scenario);
    assert.doesNotMatch(s.html, /No new bookings were saved/, scenario);
    assert.equal(s.calls.length, 1); assert.equal(s.state.refreshes, 1); assert.equal(s.state.plannerLoads, 1);
  }
});

test('late old background failure cannot repaint a different vehicle result', async () => {
  const old = deferred(), s = setup({ refreshImpl: (_ctx, count) => count === 1 ? old.promise : true });
  const second = { ...s.serverVehicle, id: secondId, stock_number: '13000000' };
  s.context.app.emailVehicleLocationRows.push(second); s.context.app.data.push(emailVehicles.mapServerVehicle(second));
  s.click(); await flush(); s.closeButton.click(); s.click(secondId); await flush();
  assert.match(s.elements.get('[data-book-all-vehicle]').textContent, /13000000/);
  const latest = s.html; old.reject(Error('late failure')); await flush();
  assert.equal(s.html, latest); assert.equal(s.calls.length, 2);
});

test('auth lock or ready invalidates old writes even if the same actor and token sign in again', async () => {
  for (const event of ['pdc-auth-locked', 'pdc-auth-ready']) {
    const old = deferred(), fresh = deferred(), s = setup({ fetchImpl: (_url, _request, count) => count === 1 ? old.promise : fresh.promise });
    s.click(); await flush(); s.auth(event); assert.equal(s.dialog.open, false);
    s.click(); await flush(); assert.equal(s.calls.length, 2); assert.equal(s.closeButton.disabled, true);
    old.resolve(response(booked())); await flush();
    assert.equal(s.closeButton.disabled, true); assert.equal(s.html, ''); assert.equal(s.state.refreshes, 0);
    fresh.resolve(response(booked())); await flush(); assert.match(s.html, /1 station booked/);
  }
});

test('old background failure after same-actor lock and ready cannot alter the new result', async () => {
  const old = deferred(), s = setup({ refreshImpl: (_ctx, count) => count === 1 ? old.promise : true });
  s.click(); await flush(); s.auth('pdc-auth-locked'); s.auth('pdc-auth-ready'); s.click(); await flush();
  const latest = s.html; old.reject(Error('old session offline')); await flush();
  assert.equal(s.html, latest); assert.equal(s.calls.length, 2); assert.doesNotMatch(s.html, /Refresh the board/);
});

test('token, service, config or role changes without an event discard the old result and release its dialog', async () => {
  for (const change of [s => { s.state.token = 'new-token'; }, s => { s.context.app.emailVehicleLocationService = {}; },
    s => { s.context.window.PDC_SUPABASE_CONFIG = { ...s.context.window.PDC_SUPABASE_CONFIG }; },
    s => { s.context.window.PDC_AUTH_CONTEXT.role = 'viewer'; }]) {
    const gate = deferred(), s = setup({ fetchImpl: () => gate.promise });
    s.click(); await flush(); change(s); gate.resolve(response(booked())); await flush();
    assert.equal(s.dialog.open, false); assert.equal(s.closeButton.disabled, false); assert.equal(s.state.refreshes, 0);
    assert.doesNotMatch(s.html, /station booked/);
  }
});

test('auth invalidation while a fallback is pending prevents subsequent dispatch', async () => {
  const gate = deferred(), s = setup({ snapshotRows: [], refreshImpl: () => gate.promise });
  s.click(); await flush(); s.auth('pdc-auth-locked'); gate.resolve(true); await flush();
  assert.equal(s.calls.length, 0); assert.equal(s.dialog.open, false); assert.equal(s.closeButton.disabled, false);
});

test('missing actor or access token sends no request even when the visible role is writable', async () => {
  for (const missing of ['actor', 'token']) {
    const s = setup();
    if (missing === 'actor') s.context.window.PDC_AUTH_CONTEXT.userId = null;
    else s.state.token = '';
    s.click(); await flush();
    assert.equal(s.calls.length, 0); assert.equal(s.state.refreshes, 0); assert.equal(s.dialog.open, false);
  }
});
