'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const eligibility = require('./workshop-eligibility.js');
const emailVehicles = require('./pdc-email-vehicle-location-service.js');
const source = fs.readFileSync(__dirname + '/pdc-book-all-stations.js', 'utf8');
const id = 'a1234567-1234-4123-8123-123456789012';

function setup(options = {}) {
  const elements = new Map();
  const listeners = {};
  const element = name => {
    if (!elements.has(name)) elements.set(name, {
      textContent: '', innerHTML: '', disabled: false,
      setAttribute() {}, addEventListener() {}, focus() {}, showModal() {}, close() {},
      querySelector: element, insertAdjacentHTML(_position, html) { this.innerHTML += html; },
    });
    return elements.get(name);
  };
  const serverVehicle = { id, permanent_vehicle_id: 'different-permanent-id', version: 3, current_location: 'PMB', stock_number: '12657478', lifecycle_state: 'active', ...options.serverVehicle };
  const vehicle = { ...emailVehicles.mapServerVehicle(serverVehicle), ...options.vehicle };
  const calls = [];
  const context = {
    window: { PDC_SUPABASE_CONFIG: { projectRef: 'cdsmnqxtyyoeoznmbidd', url: 'https://staging.example', publishableKey: 'fixture' }, PDC_AUTH_CONTEXT: { role: options.role || 'operator' }, PDC_WORKSHOP_ELIGIBILITY: eligibility },
    document: { createElement: element, body: { appendChild() {} }, addEventListener(name, handler) { listeners[name] = handler; } },
    // Production retains raw snake_case snapshot rows and reconciles mapped
    // authoritative DTOs into app.data. These must remain separate objects.
    app: { emailVehicleLocationRows: [serverVehicle], data: [vehicle] },
    sharedNavisionLocationAuthorityReady: () => true,
    renderIncomingDashboardBoard() {},
    displayStockNumber: row => row.stock,
    vehicleCustomerName: () => 'Fixture customer',
    getPdcSupabaseAccessToken: () => 'fixture-token',
    refreshEmailVehicleLocations: async () => {
      if (options.refresh === false) return false;
      const refreshed = { ...serverVehicle, version: 7, ...options.freshServerVehicle };
      context.app.emailVehicleLocationRows = options.freshSnapshotRows || [refreshed];
      context.app.data = options.freshMappedRows || [{ ...emailVehicles.mapServerVehicle(refreshed), ...options.freshMappedVehicle }];
      return true;
    },
    fetch: async (url, request) => {
      calls.push({ url, request });
      if (options.throwFetch) throw Error('network');
      return { ok: true, json: async () => options.result || { ok: true, bookings: [{ stage: 'HOIST', bay: 2, start_at: '2026-09-14T00:00:00Z', end_at: '2026-09-14T02:00:00Z' }], skipped: [{ stage: 'FITTING', reason: 'Already booked' }] } };
    },
  };
  vm.runInNewContext(source, context);
  let prevented = 0, stopped = 0;
  const click = () => listeners.click({ target: { closest: () => ({ dataset: { bookAllStations: id }, disabled: false }) }, preventDefault() { prevented++; }, stopPropagation() { stopped++; } });
  return { context, api: context.window.PDC_BOOK_ALL_STATIONS, vehicle, serverVehicle, calls, click, elements, propagation: () => ({ prevented, stopped }) };
}
const flush = () => new Promise(resolve => setImmediate(resolve));

test('only authoritative writable PMB, Yard Hold and valid ETA transit rows offer booking', () => {
  const s = setup();
  assert.equal(s.api.eligible(s.vehicle), true);
  assert.equal(s.api.eligible(emailVehicles.mapServerVehicle({ ...s.serverVehicle, current_location: 'YH' })), true);
  assert.equal(s.api.eligible(emailVehicles.mapServerVehicle({ ...s.serverVehicle, current_location: 'IT', eta_to_kewdale: '2026-09-14' })), true);
  for (const change of [{ current_location: 'IT' }, { current_location: 'QC' }, { current_location: 'QC', location_override: 'PMB' }]) {
    assert.equal(s.api.eligible(emailVehicles.mapServerVehicle({ ...s.serverVehicle, ...change })), false, JSON.stringify(change));
  }
  for (const change of [{ __emailVehicleId: 'wrong' }, { __locationIdentityReadOnly: true }, { deleted_at: '2026-09-11' }]) {
    assert.equal(s.api.eligible({ ...s.vehicle, ...change }), false, JSON.stringify(change));
  }
  assert.equal(setup({ role: 'viewer' }).api.eligible(s.vehicle), false);
});

test('new action replaces source text while preserving lifecycle controls and column structure', () => {
  const s = setup();
  const html = s.api.actionHtml(s.vehicle, '<span class="badge neutral">Imported by email · Read only</span><button data-yh-transfer-pmb="key">To PMB</button>');
  assert.match(html, /Book all stations/);
  assert.doesNotMatch(html, /<small>/);
  assert.ok(html.indexOf('data-yh-transfer-pmb') < html.indexOf('data-book-all-stations'));
  assert.match(html, /data-yh-transfer-pmb/);
  assert.doesNotMatch(html, /Read only/);
  assert.doesNotMatch(html, /grid-template|incoming-card-action/);
  assert.equal(s.api.actionHtml(emailVehicles.mapServerVehicle({ ...s.serverVehicle, current_location: 'QC' }), 'Keep QC'), 'Keep QC');
});

test('one click sends one atomic request with refreshed version and does not expand the vehicle', async () => {
  const s = setup();
  assert.equal(s.context.app.emailVehicleLocationRows[0].__emailVehicleId, undefined);
  assert.equal(s.context.app.emailVehicleLocationRows[0].version, 3);
  assert.notEqual(s.vehicle.id, id);
  s.click(); s.click();
  await flush();
  assert.equal(s.calls.length, 1);
  assert.match(s.calls[0].url, /\/rpc\/book_all_vehicle_stations$/);
  assert.deepEqual(JSON.parse(s.calls[0].request.body), { p_vehicle_id: id, p_expected_version: 7 });
  assert.deepEqual(s.propagation(), { prevented: 2, stopped: 2 });
  const summary = s.elements.get('[data-book-all-result]').innerHTML;
  assert.match(summary, /1 station booked/);
  assert.match(summary, /Bay 2/);
  assert.match(summary, /Already booked/);
  assert.match(summary, /Sublet is excluded/);
  assert.match(summary, /5-hour gap/);
});

test('both reported PMB stocks book using raw snapshot identity and refreshed version', async () => {
  for (const stock_number of ['12238276', '12657478']) {
    const s = setup({ serverVehicle: { stock_number } });
    s.click(); await flush();
    assert.equal(s.calls.length, 1, stock_number);
    assert.deepEqual(JSON.parse(s.calls[0].request.body), { p_vehicle_id: id, p_expected_version: 7 });
  }
});

test('Busselton Yard Hold imports book without an ETA or Navision vehicle details', async () => {
  for (const current_location of ['Yard Hold', 'YH', ' yard hold ']) {
    const s = setup({ serverVehicle: {
      stock_number: '12728609', customer_name: 'BUSSELTON TOYOTA', current_location,
      eta_to_kewdale: null, vehicle_description: null, model: null,
      source_system: 'Authenticated email auto-import', navision_record_id: null,
    } });
    assert.equal(s.api.eligible(s.vehicle), true, current_location);
    s.click(); await flush();
    assert.equal(s.calls.length, 1, current_location);
    assert.deepEqual(JSON.parse(s.calls[0].request.body), { p_vehicle_id: id, p_expected_version: 7 });
    assert.match(s.elements.get('[data-book-all-result]').innerHTML, /1 station booked/);
    assert.equal(s.context.app.emailVehicleLocationRows[0].current_location, current_location);
    assert.equal(s.context.app.emailVehicleLocationRows[0].eta_to_kewdale, null);
    assert.equal(s.context.app.emailVehicleLocationRows[0].vehicle_description, null);
  }
});

test('Yard Hold display override cannot authorize a QC vehicle and IT still needs its ETA', async () => {
  for (const serverVehicle of [
    { current_location: 'QC', location_override: 'Yard Hold', eta_to_kewdale: null },
    { current_location: 'IT', eta_to_kewdale: null },
  ]) {
    const s = setup({ serverVehicle });
    assert.equal(s.api.eligible(s.vehicle), false, JSON.stringify(serverVehicle));
    s.click(); await flush();
    assert.equal(s.calls.length, 0, JSON.stringify(serverVehicle));
  }
});

test('a missing fresh canonical row cannot fall back to an eligible stale mapped row', async () => {
  const s = setup({ freshSnapshotRows: [] });
  s.click(); await flush();
  assert.equal(s.calls.length, 0);
  assert.match(s.elements.get('[data-book-all-result]').innerHTML, /no longer eligible|identity|refreshed/i);
});

test('duplicate raw canonical rows stop booking rather than choosing a version', async () => {
  const row = { id, version: 7, stock_number: '12657478', current_location: 'PMB' };
  const s = setup({ freshSnapshotRows: [row, { ...row, version: 8 }] });
  s.click(); await flush();
  assert.equal(s.calls.length, 0);
});

test('a mapped version that disagrees with the fresh snapshot cannot be booked', async () => {
  const s = setup({ freshMappedVehicle: { __emailVehicleVersion: 3 } });
  s.click(); await flush();
  assert.equal(s.calls.length, 0);
});

test('duplicate mapped canonical rows stop booking rather than choosing a projection', async () => {
  const row = emailVehicles.mapServerVehicle({ id, version: 7, stock_number: '12657478', current_location: 'PMB' });
  const s = setup({ freshMappedRows: [row, { ...row }] });
  s.click(); await flush();
  assert.equal(s.calls.length, 0);
});

test('fresh location and identity restrictions are rechecked before a booking request', async () => {
  for (const options of [
    { freshServerVehicle: { current_location: 'QC' } },
    { freshMappedVehicle: { __locationIdentityReadOnly: true, __emailVehicleIdentityConflict: true } },
  ]) {
    const s = setup(options);
    s.click(); await flush();
    assert.equal(s.calls.length, 0, JSON.stringify(options));
  }
});

test('fresh vehicle check fails closed before any booking request', async () => {
  const s = setup({ refresh: false }); s.click(); await flush();
  assert.equal(s.calls.length, 0);
  assert.match(s.elements.get('[data-book-all-result]').innerHTML, /No booking request was sent/);
});

test('server rejection keeps the concrete reason visible and escaped', async () => {
  const s = setup({ result: { ok: false, error: 'missing_hours', message: 'Fitting <line 4> needs hours.' } });
  s.click(); await flush();
  assert.match(s.elements.get('[data-book-all-result]').innerHTML, /Fitting &lt;line 4&gt; needs hours/);
  assert.equal(s.elements.get('[data-book-all-close]').disabled, false);
});

test('uncertain network result is not reported as a successful booking or rollback', async () => {
  const s = setup({ throwFetch: true }); s.click(); await flush();
  assert.match(s.elements.get('[data-book-all-result]').innerHTML, /could not be confirmed/);
  assert.doesNotMatch(s.elements.get('[data-book-all-result]').innerHTML, /station booked|No booking request/);
});
