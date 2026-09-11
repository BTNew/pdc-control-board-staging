'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const eligibility = require('./workshop-eligibility.js');
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
  const vehicle = { __emailVehicleId: id, __emailVehicleVersion: 3, pdcLocation: 'PMB', stock: '12657478', ...options.vehicle };
  const calls = [];
  const context = {
    window: { PDC_SUPABASE_CONFIG: { projectRef: 'cdsmnqxtyyoeoznmbidd', url: 'https://staging.example', publishableKey: 'fixture' }, PDC_AUTH_CONTEXT: { role: options.role || 'operator' }, PDC_WORKSHOP_ELIGIBILITY: eligibility },
    document: { createElement: element, body: { appendChild() {} }, addEventListener(name, handler) { listeners[name] = handler; } },
    app: { emailVehicleLocationRows: [vehicle], data: [vehicle] },
    sharedNavisionLocationAuthorityReady: () => true,
    renderIncomingDashboardBoard() {},
    displayStockNumber: row => row.stock,
    vehicleCustomerName: () => 'Fixture customer',
    getPdcSupabaseAccessToken: () => 'fixture-token',
    refreshEmailVehicleLocations: async () => { vehicle.__emailVehicleVersion = 7; return options.refresh !== false; },
    fetch: async (url, request) => {
      calls.push({ url, request });
      if (options.throwFetch) throw Error('network');
      return { ok: true, json: async () => options.result || { ok: true, bookings: [{ stage: 'HOIST', bay: 2, start_at: '2026-09-14T00:00:00Z', end_at: '2026-09-14T02:00:00Z' }], skipped: [{ stage: 'FITTING', reason: 'Already booked' }] } };
    },
  };
  vm.runInNewContext(source, context);
  let prevented = 0, stopped = 0;
  const click = () => listeners.click({ target: { closest: () => ({ dataset: { bookAllStations: id }, disabled: false }) }, preventDefault() { prevented++; }, stopPropagation() { stopped++; } });
  return { context, api: context.window.PDC_BOOK_ALL_STATIONS, vehicle, calls, click, elements, propagation: () => ({ prevented, stopped }) };
}
const flush = () => new Promise(resolve => setImmediate(resolve));

test('only authoritative writable PMB, Yard Hold and valid ETA transit rows offer booking', () => {
  const s = setup();
  assert.equal(s.api.eligible(s.vehicle), true);
  assert.equal(s.api.eligible({ ...s.vehicle, pdcLocation: 'YH' }), true);
  assert.equal(s.api.eligible({ ...s.vehicle, pdcLocation: 'IT', navisionKewdaleEta: '2026-09-14' }), true);
  for (const change of [{ pdcLocation: 'IT' }, { pdcLocation: 'QC' }, { __emailVehicleId: 'wrong' }, { __locationIdentityReadOnly: true }, { deleted_at: '2026-09-11' }, { pdcLocation: 'PMB', pdcAutomaticLocation: 'QC' }]) {
    assert.equal(s.api.eligible({ ...s.vehicle, ...change }), false, JSON.stringify(change));
  }
  assert.equal(setup({ role: 'viewer' }).api.eligible(s.vehicle), false);
});

test('new action replaces source text while preserving lifecycle controls and column structure', () => {
  const s = setup();
  const html = s.api.actionHtml(s.vehicle, '<span class="badge neutral">Imported by email · Read only</span><button data-yh-transfer-pmb="key">To PMB</button>');
  assert.match(html, /Book all stations/);
  assert.match(html, /Next available bookings/);
  assert.match(html, /data-yh-transfer-pmb/);
  assert.doesNotMatch(html, /Read only/);
  assert.doesNotMatch(html, /grid-template|incoming-card-action/);
  assert.equal(s.api.actionHtml({ ...s.vehicle, pdcLocation: 'QC' }, 'Keep QC'), 'Keep QC');
});

test('one click sends one atomic request with refreshed version and does not expand the vehicle', async () => {
  const s = setup();
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
