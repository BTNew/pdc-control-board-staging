/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r482 (F95): Craig, 22 Oct: "when we're booking into bays, give a notification that the booking date is before an ETA
// date for parts ... still let you book it in". Every booking path asks "Book anyway" / "Cancel" when a booking starts
// (Perth date) before the vehicle's active parts ETA; Cancel sends nothing; Book anyway sends the same command. No ETA, or
// an ETA on or before the booking date, asks nothing and changes nothing. Synthetic fixtures only (no stock numbers).
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const eta = require('./pdc-parts-eta.js');
const { createSlotRuntime } = require('./tests/helpers/workshop-slot-runtime.cjs');

const VEHICLE = 'a1234567-1234-4123-8123-123456789012';
const OTHER = 'b1234567-1234-4123-8123-123456789012';
const BOOKING = 'c1234567-1234-4123-8123-123456789012';
const entry = (latest = '2026-10-29', extra = {}) => ({ vehicle_id: VEHICLE, stock_number: 'SYN-1', latest_eta: latest, count: 1, parts: [{ part: 'Synthetic bar', eta_date: latest }], ...extra });
const flush = () => new Promise(resolve => setImmediate(resolve));

test('r482: a booking that starts on a Perth date before the latest parts ETA is listed; on or after it is not', () => {
  const e = entry('2026-10-29');
  const w = eta.bookingWarning(e, [
    { station: 'Fitting', bay: 1, start: '2026-10-22T05:15:00Z' }, // Thu 22 Oct 1:15 pm Perth
    { station: 'Electrical', bay: 2, start: '2026-10-28T15:59:00Z' }, // Wed 28 Oct 11:59 pm Perth
    { station: 'Tyre', bay: 3, start: '2026-10-28T16:00:00Z' }, // Thu 29 Oct 12:00 am Perth: on the ETA date
  ], 'Stock SYN-1');
  assert.equal(w.eta, '2026-10-29');
  assert.equal(w.etaLabel, 'Thu 29/10/26');
  assert.deepEqual(w.before.map(b => b.station), ['Fitting', 'Electrical']);
  assert.deepEqual(w.before.map(b => b.date), ['2026-10-22', '2026-10-28']);
  assert.equal(eta.bookingWarning(e, [{ station: 'Tyre', start: '2026-10-29T01:00:00Z' }]), null, 'ETA day: no warning');
  assert.equal(eta.bookingWarning(e, [{ station: 'Tyre', start: '2026-11-02T01:00:00Z' }]), null, 'after the ETA: no warning');
  assert.equal(eta.bookingWarning(null, [{ start: '2026-10-22T01:00:00Z' }]), null, 'no ETA: no warning');
  assert.equal(eta.bookingWarning({ vehicle_id: VEHICLE, latest_eta: null }, [{ start: '2026-10-22T01:00:00Z' }]), null);
  // Several parts: the latest ETA decides (the job needs every part).
  const two = eta.bookingWarning(entry('2026-10-29', { count: 2, parts: [{ part: 'A', eta_date: '2026-10-29' }, { part: 'B', eta_date: '2026-10-20' }] }), [{ station: 'Fitting', bay: 1, start: '2026-10-23T01:00:00Z' }]);
  assert.equal(two.count, 2);
  assert.deepEqual(two.parts.map(p => p.part), ['A']);
});

test('r482: the question lists the parts ETA date and each station / bay booked before it', () => {
  const w = eta.bookingWarning(entry(), [{ station: 'Fitting', bay: 1, start: '2026-10-22T05:15:00Z' }, { station: 'Tyre', bay: 2, start: '2026-10-23T00:00:00Z' }], 'Stock SYN-1');
  const text = eta.warningText([w]);
  assert.match(text, /Stock SYN-1: Parts ETA Thu 29\/10\/26\./);
  assert.match(text, /• Fitting · Bay 1 · Thu 22 Oct, 1:15 pm/);
  assert.match(text, /• Tyre · Bay 2 · Fri 23 Oct, 8:00 am/);
  assert.match(text, /You can still book it\. Book anyway/);
  assert.deepEqual(eta.acknowledgement([w]), { acknowledged: true, eta_date: '2026-10-29', bookings_before_eta: 2, release: 'r482' });
  // Book all stations (no dry run on the server): asked when the ETA is after today, not on or before it.
  assert.equal(eta.bookAllWarning(entry('2026-10-29'), '2026-10-22').bookAll, true);
  assert.match(eta.warningText([eta.bookAllWarning(entry('2026-10-29'), '2026-10-22', 'Stock SYN-1')]), /earliest start is today \(Thu 22\/10\/26\), before the parts are due/);
  assert.equal(eta.bookAllWarning(entry('2026-10-22'), '2026-10-22'), null);
  assert.equal(eta.bookAllWarning(entry('2026-10-20'), '2026-10-22'), null);
  assert.equal(eta.bookAllWarning(null, '2026-10-22'), null);
});

// ---- a small fake DOM, enough for the dialogs ----
function fakeDocument() {
  const made = [];
  const node = tag => {
    const handlers = {}, kids = {};
    const el = {
      tag, className: '', attrs: {}, innerHTML: '', textContent: '', open: false, removed: false, focused: false, dataset: {},
      setAttribute(k, v) { this.attrs[k] = v; }, addEventListener(type, fn) { (handlers[type] ||= []).push(fn); },
      dispatch(type, event = {}) { for (const fn of handlers[type] || []) fn({ preventDefault() {}, ...event }); },
      querySelector(sel) { return kids[sel] ||= node(sel); }, showModal() { this.open = true; }, close() { if (this.open) { this.open = false; this.dispatch('close'); } },
      remove() { this.removed = true; }, focus() { el.focused = true; }, click() { this.dispatch('click'); },
    };
    made.push(el);
    return el;
  };
  return { made, document: { createElement: node, head: { appendChild() {} }, body: { appendChild() {} }, addEventListener() {}, visibilityState: 'visible' } };
}
async function runtimeGuard(board) {
  const dom = fakeDocument();
  const ctx = { window: { PDC_SUPABASE_CONFIG: { projectRef: 'cdsmnqxtyyoeoznmbidd', url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co', publishableKey: 'fixture' }, __pdcCachedAccessToken: 'fixture-token' },
    document: dom.document, setInterval: () => 0, clearInterval() {}, setTimeout: () => 0, Intl, Date,
    fetch: async () => ({ ok: true, status: 200, text: async () => JSON.stringify(board) }) };
  vm.runInNewContext(fs.readFileSync(require.resolve('./pdc-parts-eta.js'), 'utf8'), ctx);
  await flush(); await flush();
  return { guard: ctx.window.PDC_PARTS_ETA, dom };
}
const dialogOf = dom => dom.made.filter(el => el.tag === 'dialog').pop();

test('r482: the dialog shows the ETA and bookings; Cancel answers no, Book anyway answers yes; no ETA asks nothing', async () => {
  const { guard, dom } = await runtimeGuard({ today: '2026-10-22', vehicles: [entry()] });
  const groups = [{ vehicle: { id: VEHICLE, stock: 'SYN-1' }, bookings: [{ station: 'Fitting', bay: 1, start: '2026-10-22T05:15:00Z' }] }];
  let pending = guard.confirmBookings(groups);
  let dialog = dialogOf(dom);
  assert.equal(dialog.open, true);
  assert.equal(dialog.attrs.role, 'alertdialog');
  assert.match(dialog.innerHTML, /Parts not due yet/);
  assert.match(dialog.innerHTML, /Parts ETA <strong>Thu 29\/10\/26<\/strong>/);
  assert.match(dialog.innerHTML, /<li>Fitting · Bay 1 · Thu 22 Oct, 1:15 pm<\/li>/);
  assert.match(dialog.innerHTML, />Cancel<\/button><button type="button" class="primary" data-parts-eta-book>Book anyway<\/button>/);
  assert.equal(dialog.querySelector('[data-parts-eta-cancel]').focused, true, 'Cancel has the focus');
  dialog.querySelector('[data-parts-eta-cancel]').click();
  assert.equal((await pending).ok, false);
  assert.equal(dialog.removed, true);
  pending = guard.confirmBookings(groups);
  dialog = dialogOf(dom);
  dialog.querySelector('[data-parts-eta-book]').click();
  const yes = await pending;
  assert.equal(yes.ok, true);
  assert.equal(yes.warnings[0].eta, '2026-10-29');
  // Escape (the dialog's cancel event) is Cancel.
  pending = guard.confirmBookings(groups); dialogOf(dom).dispatch('cancel');
  assert.equal((await pending).ok, false);
  const count = dom.made.filter(el => el.tag === 'dialog').length;
  const plain = value => JSON.parse(JSON.stringify(value));
  assert.deepEqual(plain(await guard.confirmBookings([{ vehicle: { id: OTHER }, bookings: [{ station: 'Fitting', bay: 1, start: '2026-10-22T05:15:00Z' }] }])), { ok: true, warnings: [] });
  assert.deepEqual(plain(await guard.confirmBookings([{ vehicle: { id: VEHICLE }, bookings: [{ station: 'Fitting', bay: 1, start: '2026-10-29T05:15:00Z' }] }])), { ok: true, warnings: [] });
  assert.equal(dom.made.filter(el => el.tag === 'dialog').length, count, 'no dialog without a warning');
  assert.equal(guard.beforeEta({ id: VEHICLE }, '2026-10-23T01:00:00Z'), '2026-10-29');
  assert.equal(guard.beforeEta({ id: OTHER }, '2026-10-23T01:00:00Z'), '');
  assert.equal(guard.bookAllWarningFor({ id: OTHER }), null);
});

// ---- planner: every booking command passes workshopDispatchSharedAction ----
function plannerSetup({ answer = true, board = [entry()] } = {}) {
  const r = createSlotRuntime();
  const sent = [], asked = [];
  const index = new Map(board.map(e => [e.vehicle_id, e]));
  r.context.window.PDC_AUTH_CONTEXT = { userId: 'fixture-planner', role: 'administrator' };
  r.context.window.PDC_VEHICLE_HANDOVER = null;
  r.context.window.PDC_PARTS_ETA = {
    async confirmBookings(groups) {
      const warnings = groups.map(g => eta.bookingWarning(index.get(g.vehicle.id), g.bookings, g.vehicle.stock ? `Stock ${g.vehicle.stock}` : '')).filter(Boolean);
      if (!warnings.length) return { ok: true, warnings };
      asked.push(eta.warningText(warnings));
      return { ok: typeof answer === 'function' ? answer() : answer, warnings };
    },
    acknowledgement: eta.acknowledgement,
  };
  const ok = name => async payload => { sent.push({ name, payload }); return name === 'resequenceBay' && payload.apply !== true ? { ok: true, plan_hash: 'plan-1', changes: r.changes || [] } : { ok: true }; };
  r.context.window.__workshopSharedActions = Object.fromEntries(['scheduleVehicleWork', 'administratorScheduleVehicle', 'moveBooking', 'cascadeMoveBooking', 'administratorMoveBooking', 'cascadeSchedule', 'changeBookingBay', 'resequenceBay', 'resizeBooking'].map(n => [n, ok(n)]));
  r.context.pmbStageLabel = code => ({ FITTING: 'Fitting', TYRE: 'Tyre' }[code] || code); // app.js provides this on the board
  r.context.workshopSharedModeActive = () => true;
  r.context.workshopEnsureCurrentDeployment = async () => true;
  r.context.workshopNotify = message => { r.notes.push(message); };
  r.notes = [];
  const plan = { id: BOOKING, sharedBookingId: BOOKING, sharedVersion: 3, sharedVehicleId: VEHICLE, vehicleKey: 'SYN-1', stage: 'FITTING', bay: 1, startAt: '2026-10-30T00:00:00.000Z', status: 'planned' };
  r.context.workshopLoadPlans = () => [plan];
  const dispatch = (name, payload) => r.context.workshopDispatchSharedAction(name, payload, () => {});
  return { r, sent, asked, dispatch, plan };
}
const move = (start, extra = {}) => ({ bookingId: BOOKING, expectedVersion: 3, stageCode: 'FITTING', bayNumber: 2, scheduledStartAt: start, durationMinutes: 60, requestId: 'req-1', metadata: { source: 'planner_chip_drop', reason: 'website_drag_drop' }, ...extra });

test('r482: planner drag / move before the parts ETA asks; Cancel sends nothing and says so', async () => {
  for (const name of ['moveBooking', 'cascadeMoveBooking', 'administratorMoveBooking']) {
    const s = plannerSetup({ answer: false });
    const result = await s.dispatch(name, move('2026-10-22T05:15:00.000Z'));
    assert.equal(s.asked.length, 1, name);
    assert.match(s.asked[0], /Stock SYN-1: Parts ETA Thu 29\/10\/26\.\nBooked before the parts ETA:\n• Fitting · Bay 2 · Thu 22 Oct, 1:15 pm/);
    assert.equal(s.sent.length, 0, `${name}: nothing sent on Cancel`);
    assert.equal(result.ok, false); assert.equal(result.error, 'parts_eta_not_confirmed'); assert.equal(result.cancelled, true);
    assert.deepEqual(s.r.notes, ['No booking was made. The parts are not due until after that date.']);
  }
});

test('r482: Book anyway sends the same command, with the acknowledgement in its metadata', async () => {
  const s = plannerSetup({ answer: true });
  const payload = move('2026-10-22T05:15:00.000Z');
  const result = await s.dispatch('administratorMoveBooking', payload);
  assert.equal(result.ok, true);
  assert.equal(s.sent.length, 1);
  const { metadata, ...rest } = s.sent[0].payload;
  const { metadata: original, ...originalRest } = payload;
  assert.deepEqual(JSON.parse(JSON.stringify(rest)), originalRest, 'every other field is unchanged');
  assert.deepEqual(JSON.parse(JSON.stringify(metadata)), { ...original, parts_eta_warning: { acknowledged: true, eta_date: '2026-10-29', bookings_before_eta: 1, release: 'r482' } });
});

test('r482: new bookings (drop from Unallocated / search / Find, Best slot, Schedule) are asked before they are sent', async () => {
  const s = plannerSetup({ answer: false });
  const request = { vehicleId: VEHICLE, vehicleExpectedVersion: 4, stageCode: 'TYRE', bayNumber: 3, scheduledStartAt: '2026-10-23T00:00:00.000Z', durationMinutes: 120, technicianId: null, requestId: 'req-2', cascade: true, metadata: { source: 'admin_unallocated_vehicle_pill' } };
  assert.equal((await s.dispatch('administratorScheduleVehicle', request)).error, 'parts_eta_not_confirmed');
  assert.equal((await s.dispatch('scheduleVehicleWork', { ...request })).error, 'parts_eta_not_confirmed');
  assert.equal((await s.dispatch('cascadeSchedule', { operation: 'schedule', targetId: VEHICLE, targetExpectedVersion: 4, stageCode: 'TYRE', bayNumber: 3, scheduledStartAt: '2026-10-23T00:00:00.000Z', durationMinutes: 60 })).error, 'parts_eta_not_confirmed');
  assert.equal(s.sent.length, 0);
  assert.match(s.asked[0], /• Tyre · Bay 3 · Fri 23 Oct, 8:00 am/);
  // The planner's uncertain-outcome retry replays the same object: asked once, same bytes both times.
  let asks = 0;
  const t = plannerSetup({ answer: () => { asks++; return true; } });
  await t.dispatch('administratorScheduleVehicle', request);
  await t.dispatch('administratorScheduleVehicle', request);
  assert.equal(asks, 1);
  assert.equal(t.sent.length, 2);
  assert.deepEqual(t.sent[0].payload, t.sent[1].payload);
  assert.equal(t.sent[0].payload.metadata.parts_eta_warning.acknowledged, true);
});

test('r482: no ETA, an ETA on or before the start, an unchanged booking, or extend / resize: nothing asked and the payload is untouched', async () => {
  const cases = [
    ['moveBooking', move('2026-10-29T00:00:00.000Z')], // ETA day
    ['moveBooking', move('2026-11-02T00:00:00.000Z')], // after the ETA
    ['moveBooking', move('2026-10-30T00:00:00.000Z', { bayNumber: 1 })], // same start and bay (detail save)
    ['cascadeSchedule', { operation: 'extend', targetId: BOOKING, targetExpectedVersion: 3, stageCode: 'FITTING', bayNumber: 1, scheduledStartAt: '2026-10-22T00:00:00.000Z', durationMinutes: 120, shiftMinutes: 60 }],
    ['resizeBooking', { bookingId: BOOKING, expectedVersion: 3, durationMinutes: 30 }],
  ];
  for (const [name, payload] of cases) {
    const s = plannerSetup({ answer: false });
    const result = await s.dispatch(name, payload);
    assert.equal(s.asked.length, 0, `${name} ${payload.scheduledStartAt}`);
    assert.equal(result.ok, true);
    assert.equal(s.sent[0].payload, payload, 'the very same payload object is sent');
  }
  const none = plannerSetup({ answer: false, board: [] });
  assert.equal((await none.dispatch('administratorMoveBooking', move('2026-10-22T05:15:00.000Z'))).ok, true);
  assert.equal(none.asked.length, 0);
  // Without the parts ETA module (e.g. it failed to load) the planner books exactly as before.
  const bare = plannerSetup();
  delete bare.r.context.window.PDC_PARTS_ETA;
  const payload = move('2026-10-22T05:15:00.000Z');
  await bare.dispatch('moveBooking', payload);
  assert.equal(bare.sent[0].payload, payload);
});

test('r482: bay re-order Apply is asked about the bookings its preview moves before the ETA', async () => {
  const s = plannerSetup({ answer: false });
  s.r.changes = [{ booking_id: BOOKING, vehicle_id: VEHICLE, stage_code: 'FITTING', bay_number: 1, from_start: '2026-10-30T00:00:00Z', to_start: '2026-10-26T00:00:00Z' }];
  const base = { bookingId: BOOKING, expectedVersion: 3, targetBookingId: 'd1234567-1234-4123-8123-123456789012', mode: 'ahead', metadata: { source: 'planner_bay_resequence' } };
  assert.equal((await s.dispatch('resequenceBay', { ...base, apply: false, requestId: 'p' })).ok, true);
  assert.equal(s.asked.length, 0, 'the preview itself books nothing');
  const result = await s.dispatch('resequenceBay', { ...base, apply: true, planHash: 'plan-1', requestId: 'a' });
  assert.equal(result.error, 'parts_eta_not_confirmed');
  assert.match(s.asked[0], /• Fitting · Bay 1 · Mon 26 Oct, 8:00 am/);
  assert.equal(s.sent.filter(x => x.payload.apply === true).length, 0);
});

// ---- Book all stations (Vehicle Locations table and the board share this button) ----
function bookAllSetup(guard) {
  const elements = new Map(), listeners = {};
  const element = name => {
    if (!elements.has(name)) elements.set(name, { textContent: '', innerHTML: '', disabled: false, open: false, setAttribute() {}, focus() {}, addEventListener() {}, showModal() { this.open = true; }, close() { this.open = false; }, querySelector: element, insertAdjacentHTML(_p, v) { this.innerHTML += v; } });
    return elements.get(name);
  };
  const emailVehicles = require('./pdc-email-vehicle-location-service.js');
  const server = { id: VEHICLE, permanent_vehicle_id: 'perm', version: 3, current_location: 'PMB', stock_number: 'SYN-1', lifecycle_state: 'active', visible_on_board: true };
  const calls = [];
  const context = {
    window: { PDC_SUPABASE_CONFIG: { projectRef: 'cdsmnqxtyyoeoznmbidd', url: 'https://staging.example', publishableKey: 'fixture' }, PDC_AUTH_CONTEXT: { userId: 'fixture-operator', role: 'operator' },
      PDC_WORKSHOP_ELIGIBILITY: require('./workshop-eligibility.js'), addEventListener() {}, __workshopDataService: { loadSnapshot: async () => true }, PDC_PARTS_ETA: guard },
    document: { createElement: element, body: { appendChild() {} }, addEventListener(event, handler) { listeners[event] = handler; } },
    app: { emailVehicleLocationService: {}, emailVehicleLocationRows: [server], data: [emailVehicles.mapServerVehicle(server)] },
    sharedNavisionLocationAuthorityReady: () => true, renderIncomingDashboardBoard() {}, displayStockNumber: row => row.stock, vehicleCustomerName: () => 'Fixture customer',
    getPdcSupabaseAccessToken: () => 'fixture-token', setTimeout: () => 0, clearTimeout() {}, refreshEmailVehicleLocations: async () => true,
    fetch: async (url, request) => { calls.push({ url, request }); return { ok: true, json: async () => ({ ok: true, bookings: [{ stage: 'FITTING', bay: 1, start_at: '2026-10-22T05:15:00Z', end_at: '2026-10-22T08:00:00Z' }, { stage: 'TYRE', bay: 2, start_at: '2026-10-30T00:00:00Z', end_at: '2026-10-30T02:00:00Z' }], skipped: [] }) }; },
  };
  vm.runInNewContext(fs.readFileSync(require.resolve('./pdc-book-all-stations.js'), 'utf8'), context);
  const click = () => listeners.click({ target: { closest: () => ({ dataset: { bookAllStations: VEHICLE }, disabled: false }) }, preventDefault() {}, stopPropagation() {} });
  return { calls, click, html: () => element('[data-book-all-result]').innerHTML };
}

test('r482: Book all stations asks first when the parts ETA is after today; Cancel sends no request', async () => {
  const asked = [];
  let answer = false;
  const guard = { bookAllWarningFor: () => eta.bookAllWarning(entry(), '2026-10-22', 'Stock SYN-1'), ask: async w => { asked.push(w); return answer; },
    beforeEta: (_v, start) => (String(start) < '2026-10-28T16:00:00Z' ? '2026-10-29' : ''), etaLabel: eta.etaLabel };
  const s = bookAllSetup(guard);
  s.click(); await flush(); await flush();
  assert.equal(asked.length, 1);
  assert.equal(asked[0][0].bookAll, true);
  assert.equal(s.calls.length, 0, 'Cancel: no booking request');
  answer = true;
  s.click(); await flush(); await flush(); await flush();
  assert.equal(s.calls.length, 1);
  assert.deepEqual(JSON.parse(s.calls[0].request.body), { p_vehicle_id: VEHICLE, p_expected_version: 3 }, 'Book anyway: the same request as before');
  await flush();
  assert.match(s.html(), /Before parts ETA Thu 29\/10\/26/);
  assert.equal((s.html().match(/Before parts ETA/g) || []).length, 1, 'only the booking that starts before the ETA is marked');
});

test('r482: Book all stations without an ETA after today sends at once (no question, same request)', () => {
  const s = bookAllSetup({ bookAllWarningFor: () => null, ask: async () => { throw Error('must not ask'); }, beforeEta: () => '', etaLabel: eta.etaLabel });
  s.click();
  assert.equal(s.calls.length, 1, 'sent synchronously, as before r482');
  assert.deepEqual(JSON.parse(s.calls[0].request.body), { p_vehicle_id: VEHICLE, p_expected_version: 3 });
});

// ---- Prioritise vehicle (its preview is a dry run of the bookings) ----
function emergencySetup(answer) {
  const el = () => ({ disabled: false, hidden: false, textContent: '', innerHTML: '', value: 'SYN-1', handlers: {}, setAttribute() {}, addEventListener(t, f) { this.handlers[t] = f; }, insertAdjacentHTML(_p, v) { this.innerHTML += v; }, click() { return this.handlers.click?.(); } });
  const parts = { input: el(), '[data-emergency-preview]': el(), '[data-emergency-apply]': el(), '[data-emergency-cancel]': el(), '[data-emergency-result]': el() };
  const host = { querySelector: sel => parts[sel], setAttribute() {} };
  const calls = [], asked = [];
  const root = {
    document: { getElementById: id => (id === 'workshop-emergency' ? host : null) }, addEventListener() {},
    PDC_AUTH_CONTEXT: { userId: 'fixture-operator', role: 'operator' }, crypto: { randomUUID: () => 'e1234567-1234-4123-8123-123456789012' },
    PDC_SUPABASE_CONFIG: { projectRef: 'cdsmnqxtyyoeoznmbidd', url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co', publishableKey: 'fixture', workshop: { sharedData: true } },
    PDC_PARTS_ETA: { confirmBookings: async groups => { const w = groups.map(g => eta.bookingWarning(entry(), g.bookings, g.vehicle.stock)).filter(Boolean); asked.push(w); return { ok: w.length ? answer : true, warnings: w }; } },
    fetch: async (_url, request) => { const body = JSON.parse(request.body); calls.push(body); return { ok: true, json: async () => ({ ok: true, can_apply: true, applied: body.p_apply === true, plan_hash: 'h', vehicle_id: VEHICLE, stock_number: 'SYN-1', bookings: [{ stage_code: 'FITTING', bay_number: 1, start_at: '2026-10-22T05:15:00Z', end_at: '2026-10-22T07:00:00Z' }], changes: [] }) }; },
  };
  const context = { window: root, getPdcSupabaseAccessToken: () => 'fixture-token', setTimeout, clearTimeout, Promise, AbortController };
  context.window.window = root;
  const source = fs.readFileSync(require.resolve('./pdc-emergency-priority.js'), 'utf8').replace(/\(typeof window==='undefined'\?globalThis:window\);\s*$/, '(window);');
  vm.runInNewContext(source, context);
  return { parts, calls, asked };
}

test('r482: Prioritise vehicle asks before applying a plan that books before the ETA; Cancel applies nothing', async () => {
  const s = emergencySetup(false);
  await s.parts['[data-emergency-preview]'].click(); await flush();
  assert.deepEqual(s.calls.map(c => c.p_apply), [false]);
  await s.parts['[data-emergency-apply]'].click(); await flush();
  assert.equal(s.asked.length, 1);
  assert.equal(s.asked[0][0].before[0].station, 'Fitting');
  assert.deepEqual(s.calls.map(c => c.p_apply), [false], 'Cancel: not applied');
  assert.match(s.parts['[data-emergency-result]'].innerHTML, /Not prioritised: the parts are not due yet\. No changes saved\./);
  const t = emergencySetup(true);
  await t.parts['[data-emergency-preview]'].click(); await flush();
  await t.parts['[data-emergency-apply]'].click(); await flush();
  assert.deepEqual(t.calls.map(c => c.p_apply), [false, true], 'Book anyway: applied exactly as before');
  assert.equal(t.calls[1].p_plan_hash, 'h');
});

test('r482: cache-bust tags and versions', () => {
  assert.equal(eta.VERSION, '2026.10.22.r482');
  const entrySource = fs.readFileSync('canonical-entry.js', 'utf8');
  assert.match(entrySource, /pdc-parts-eta\.js\?parts-eta=2026\.10\.21\.r436&r475=2026\.10\.22\.r475&r482=2026\.10\.22\.r482'/);
  assert.match(entrySource, /pdc-book-all-stations\.js\?[^']*&r482=2026\.10\.22\.r482'/);
  const html = fs.readFileSync('index.html', 'utf8');
  assert.match(html, /canonical-entry\.js\?[^"]*r482=2026\.10\.22\.r482/);
  assert.match(html, /pdc-emergency-priority\.js\?v=2026\.09\.15\.01&amp;r482=2026\.10\.22\.r482/);
  assert.match(fs.readFileSync('workshop-planner.js', 'utf8'), /parts_eta_not_confirmed: 'No booking was made\./);
});
