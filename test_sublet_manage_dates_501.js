'use strict';
// r501 (F114, Craig 23 Oct 07:55): Due out / Due back in Manage sublets (also on 'PO to raise' lines) save through the
// Sublet booking service, so the Sublet calendar shows them; the Sublet page and calendar no longer create bookings.
// Fictional data only; every RPC is mocked.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const vs = require('./pdc-vehicle-sublets.js');

const U = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const VID = U(500);
const KEY = 'vehicle-key-1';
const jobLines = [
  { line_identity: `source:${U(1)}`, operation_no: '1', description: 'Seat covers front and rear', work_category: 'SUBLET', category_version: 1, department: '139' },
  { line_identity: `source:${U(2)}`, operation_no: '2', description: 'Canopy signage', work_category: 'SUBLET', category_version: 1, department: '139' },
  { line_identity: `source:${U(3)}`, operation_no: '3', description: 'Tow bar fit', work_category: 'FITTING', category_version: 0, department: '139' },
];
// Line 1: no GP PO yet ('PO to raise') and not booked: the Sublet list's pending 'Sublet To Book' row.
const pendingRow = { __subletVehicleKey: KEY, __subletOperationKey: `op:${U(1)}`, __subletOperationIdentity: `source:${U(1)}`, pmbSubletNotes: 'JC 1 · Seat covers front and rear' };
// Line 2: already booked (active) with a fictional supplier.
const activeRow = { __subletVehicleKey: KEY, __subletBookingId: 'b-2', __subletBookingStatus: 'active', __subletBookingVersion: 3, __subletOperationIdentity: `source:${U(2)}`,
  __subletProviderId: 'p-1', pmbSubletProvider: 'Example Trim Co', pmbSubletBookingDate: '2026-10-27', pmbSubletExpectedReturnDate: '2026-10-29' };
const cancelledRow = { __subletVehicleKey: KEY, __subletBookingId: 'b-0', __subletBookingStatus: 'cancelled', __subletOperationIdentity: `source:${U(1)}`, pmbSubletProvider: 'Old Co' };
const providers = [{ id: 'p-1', name: 'Example Trim Co', email: 'trim@example.invalid', active: true }, { id: 'p-2', name: 'Example Signs', email: 'signs@example.invalid', active: true }];
const model = () => vs.buildModel({ jobLines, poLines: [], bookings: [pendingRow, activeRow, cancelledRow] });

function mockService(log, overrides = {}) {
  return {
    createSubletBooking: async (...args) => { log.push(['create', ...args]); return overrides.create || { ok: true, data: { booking: { id: 'b-new', version: 1 } } }; },
    updateSubletBooking: async (...args) => { log.push(['dates', ...args]); return overrides.dates || { ok: true, data: { booking: { version: 5 } } }; },
    updateSubletBookingProvider: async (...args) => { log.push(['provider', ...args]); return overrides.provider || { ok: true, data: { booking: { version: 4 } } }; },
  };
}

test('validation: both dates needed, Due back on or after Due out; supplier needed for a new booking', () => {
  assert.equal(vs.datesError('', '2026-10-30'), 'Enter both Due out and Due back.');
  assert.equal(vs.datesError('2026-10-30', ''), 'Enter both Due out and Due back.');
  assert.equal(vs.datesError('2026-10-30', '2026-10-29'), 'Due back must be on or after Due out.');
  assert.equal(vs.datesError('2026-10-30', '2026-10-30'), '');
  const m = model();
  const line1 = m.whole.find(r => r.operationNo === '1');
  assert.equal(vs.planSave(line1, { providerId: 'p-1', out: '2026-11-02', back: '2026-11-01' }).error, 'Due back must be on or after Due out.');
  assert.equal(vs.planSave(line1, { out: '2026-11-02', back: '2026-11-04' }).error, 'Choose the supplier first.');
  const line2 = m.whole.find(r => r.operationNo === '2');
  const same = vs.planSave(line2, { providerId: 'p-1', out: '2026-10-27', back: '2026-10-29' });
  assert.equal(same.unchanged, true);
  assert.equal(vs.planSave({ bookings: [] }, { providerId: 'p-1', out: '2026-11-02', back: '2026-11-04' }).error, 'This line is not on the Sublet list yet. Refresh the board, then try again.');
});

test('cancelled bookings are history: the line is bookable again and they are not listed as vehicle bookings', () => {
  const m = model();
  const line1 = m.whole.find(r => r.operationNo === '1');
  assert.deepEqual(line1.bookings.map(b => b.__subletBookingId || b.__subletOperationKey), [`op:${U(1)}`]);
  assert.equal(m.loose.length, 0);
});

test('save on a PO to raise line creates the booking through the Sublet booking service (the calendar data path)', async () => {
  const line1 = model().whole.find(r => r.operationNo === '1');
  const plan = vs.planSave(line1, { providerId: 'p-2', out: '2026-11-02', back: '2026-11-05' });
  assert.equal(plan.kind, 'create');
  const log = [];
  const result = await vs.performSave(plan, { service: mockService(log), vehicle: { id: VID, version: 7 }, providerEmail: 'signs@example.invalid' });
  assert.deepEqual(result, { ok: true, created: true });
  assert.deepEqual(log, [['create', VID, 7, 'p-2', '2026-11-02', '2026-11-05', 'signs@example.invalid', 'JC 1 · Seat covers front and rear', `source:${U(1)}`]]);
});

test('save on a booked line changes the supplier then the dates, chaining the booking version', async () => {
  const line2 = model().whole.find(r => r.operationNo === '2');
  const plan = vs.planSave(line2, { providerId: 'p-2', out: '2026-10-28', back: '2026-10-31' });
  assert.deepEqual(plan.steps, ['provider', 'dates']);
  const log = [];
  const result = await vs.performSave(plan, { service: mockService(log), vehicle: { id: VID, version: 7 }, providerEmail: 'signs@example.invalid', idempotencyKey: 'k-1' });
  assert.equal(result.ok, true);
  assert.deepEqual(log, [['provider', 'b-2', 3, 'p-2', 'signs@example.invalid', 'k-1'], ['dates', 'b-2', 4, '2026-10-28', '2026-10-31', null]]);
  // dates only
  const log2 = [];
  await vs.performSave(vs.planSave(line2, { providerId: 'p-1', out: '2026-10-27', back: '2026-10-30' }), { service: mockService(log2), vehicle: { id: VID, version: 7 } });
  assert.deepEqual(log2, [['dates', 'b-2', 3, '2026-10-27', '2026-10-30', null]]);
  // a refused save shows plain text and stops
  const log3 = [];
  const refused = await vs.performSave(plan, { service: mockService(log3, { provider: { ok: false, code: 'version_conflict' } }), vehicle: { id: VID, version: 7 } });
  assert.equal(refused.ok, false); assert.equal(refused.message, vs.SAVE_ERRORS.version_conflict); assert.equal(log3.length, 1);
});

test('clear cancels the active booking (history kept) with the expected version; nothing to cancel is a no-op', async () => {
  const calls = [];
  const cancel = async (...args) => { calls.push(args); return { ok: true }; };
  assert.deepEqual(await vs.performClear(activeRow, { cancel }), { ok: true });
  assert.deepEqual(calls, [['b-2', 3, 'Dates cleared in Manage sublets']]);
  assert.deepEqual(await vs.performClear(null, { cancel }), { ok: true, nothing: true });
  assert.equal(calls.length, 1);
});

test('screen: whole line rows (PO to raise too) get Supplier, Due out, Due back, Save and Clear for operators and administrators only', () => {
  const m = model();
  const html = vs.screenHtml(m, { vehicleId: VID, title: 'Fictional', perms: { canBook: true, canEmail: true, providers, drafts: {}, messages: {} } });
  assert.match(html, /<th>Due out<\/th>/);
  assert.match(html, /class="pvs-nopo"[^>]*>PO to raise</);
  for (const id of [U(1), U(2)]) {
    assert.match(html, new RegExp(`data-pvs-f="out" data-pvs-row="${id}"`));
    assert.match(html, new RegExp(`data-pvs-f="back" data-pvs-row="${id}"`));
    assert.match(html, new RegExp(`data-pvs-save="${id}"`));
    assert.match(html, new RegExp(`data-pvs-clear="${id}"`));
  }
  assert.match(html, new RegExp(`data-pvs-f="out" data-pvs-row="${U(2)}" value="2026-10-27"`));
  assert.match(html, /value="2026-10-29" min="2026-10-27"/, 'Due back cannot be before Due out');
  assert.match(html, /<option value="p-1" selected>Example Trim Co<\/option>/);
  assert.match(html, /Due out and Due back save to the Sublet calendar\./);
  assert.doesNotMatch(html, /book it on the Sublet page/);
  const ro = vs.screenHtml(m, { vehicleId: VID, title: 'Fictional', perms: { canBook: false, canEmail: true } });
  assert.doesNotMatch(ro, /data-pvs-save|data-pvs-f=/);
  assert.match(ro, /Sublet To Book/, 'viewers see the pending row read only');
  const roEmpty = vs.screenHtml(vs.buildModel({ jobLines, poLines: [], bookings: [] }), { vehicleId: VID, perms: { canBook: false } });
  assert.match(roEmpty, /No supplier booked yet: operators and administrators book it here/);
  const busy = vs.screenHtml(m, { vehicleId: VID, perms: { canBook: true, providers, busy: U(1), messages: { [U(2)]: { ok: false, text: 'Due back must be on or after Due out.' } } } });
  assert.match(busy, /Saving…/);
  assert.match(busy, /class="pvs-msg is-err" role="status">Due back must be on or after Due out\.</);
});

// ---- runtime: a minimal fake DOM, the Sublet booking service mocked ----
function runtime({ role = 'operator' } = {}) {
  const counts = { refresh: 0, renderSublet: 0, draws: 0, listProviders: 0, fetch: 0 };
  const timers = [];
  const log = [];
  let rows = [pendingRow, activeRow];
  const listeners = {};
  const dialog = { _html: '', set innerHTML(v) { counts.draws += 1; this._html = v; }, get innerHTML() { return this._html; }, querySelector: () => null };
  const shell = { id: 'pvs-shell', classList: { add() {}, remove() {} }, innerHTML: '', querySelector: sel => (sel === '.pvs-dialog' ? dialog : null), querySelectorAll: () => [],
    addEventListener: (type, fn) => { listeners[type] = fn; } };
  let mounted = false;
  const vehicle = { key: KEY, stock: 'FAKE01', __emailVehicleServerAuthoritative: true, __emailVehicleId: VID, __emailVehicleVersion: 7 };
  const ctx = {
    document: { getElementById: id => (id === 'pvs-shell' && mounted ? shell : null), createElement: () => shell, body: { appendChild: () => { mounted = true; }, classList: { add() {}, remove() {} } }, addEventListener() {} },
    setTimeout: (f, ms) => { timers.push(f); return timers.length; },
    PDC_AUTH_CONTEXT: { role },
    vehicleLocationsScreenRows: () => [vehicle], vehicleKey: row => row.key, vehicleWorkshopDetailCanonicalId: v => v.__emailVehicleId,
    subletRows: () => rows,
    loadSubletProviderRecords: () => providers,
    initWorkshopReferenceDataServiceIfAvailable: () => ({ listSubletProviders: async () => { counts.listProviders += 1; } }),
    refreshEmailVehicleLocations: async () => { counts.refresh += 1; rows = [pendingRow, activeRow]; return true; },
    renderSubletHome: () => { counts.renderSublet += 1; },
    pdcNotify: () => {}, confirm: () => true,
    fetch: async () => { counts.fetch += 1; return { ok: true, json: async () => ({ ok: true }) }; },
    PDC_SUPABASE_CONFIG: { url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co', publishableKey: 'k' }, getPdcSupabaseAccessToken: () => 't',
  };
  ctx.app = { currentView: 'sublet', vehicleWorkshopDetailCache: new Map([[VID, { detail: { job_card_lines: jobLines } }]]), emailVehicleLocationService: mockService(log) };
  ctx.window = ctx;
  vm.createContext(ctx);
  vm.runInContext(fs.readFileSync(require.resolve('./pdc-vehicle-sublets.js'), 'utf8'), ctx);
  const runTimers = () => { const due = timers.splice(0); due.forEach(f => f()); return due.length; };
  const flush = async () => { for (let i = 0; i < 20; i++) await new Promise(r => setImmediate(r)); };
  const type = (rowId, field, value) => listeners.input({ target: { closest: () => ({ dataset: { pvsRow: rowId, pvsF: field }, value, closest: () => null }) } });
  const click = attrs => listeners.click({ target: { closest: sel => {
    const m = sel.match(/^\[data-(pvs-[a-z-]+)\]$/); if (!m || !(m[1] in attrs)) return null;
    const camel = m[1].replace(/-([a-z])/g, (_, c) => c.toUpperCase()); return { dataset: { [camel]: attrs[m[1]] } }; } } });
  return { ctx, counts, log, dialog, runTimers, flush, type, click, api: ctx.PDC_VEHICLE_SUBLETS };
}

test('runtime: Save on a PO to raise line books it, then exactly one snapshot refresh, one Sublet render and one debounced redraw', async () => {
  const h = runtime();
  h.api.open(KEY);
  await h.flush(); h.runTimers();
  assert.equal(h.counts.listProviders, 0, 'providers already cached: no list call');
  assert.match(h.dialog.innerHTML, new RegExp(`data-pvs-save="${U(1)}"`));
  h.type(U(1), 'providerId', 'p-2'); h.type(U(1), 'out', '2026-11-02'); h.type(U(1), 'back', '2026-11-05');
  const drawsBefore = h.counts.draws;
  h.click({ 'pvs-save': U(1) });
  await h.flush();
  assert.deepEqual(h.log, [['create', VID, 7, 'p-2', '2026-11-02', '2026-11-05', 'signs@example.invalid', 'JC 1 · Seat covers front and rear', `source:${U(1)}`]]);
  assert.equal(h.counts.refresh, 1, 'one snapshot refresh (the same one the Sublet page uses)');
  assert.equal(h.counts.renderSublet, 1, 'the Sublet page/calendar re-renders once when it is the current view');
  assert.equal(h.runTimers(), 1, 'one debounced redraw'); assert.equal(h.runTimers(), 0);
  assert.ok(h.counts.draws - drawsBefore <= 3, 'busy draw, then the redraw: no per-answer full redraws');
  assert.match(h.dialog.innerHTML, /Saved: Due out/);
  assert.equal(h.counts.fetch, 0);
});

test('runtime: invalid dates are refused before any RPC; viewers get no editor', async () => {
  const h = runtime();
  h.api.open(KEY); h.runTimers();
  h.type(U(1), 'providerId', 'p-2'); h.type(U(1), 'out', '2026-11-05'); h.type(U(1), 'back', '2026-11-02');
  h.click({ 'pvs-save': U(1) }); await h.flush();
  assert.equal(h.log.length, 0); assert.equal(h.counts.refresh, 0);
  assert.match(h.dialog.innerHTML, /Due back must be on or after Due out\./);
  const viewer = runtime({ role: 'viewer' });
  viewer.api.open(KEY); viewer.runTimers();
  assert.doesNotMatch(viewer.dialog.innerHTML, /data-pvs-save/);
});

test('runtime: Clear on a booked line cancels it with the existing cancel RPC once, then one refresh', async () => {
  const h = runtime();
  const urls = [];
  h.ctx.fetch = async (url, init) => { urls.push([url, JSON.parse(init.body)]); return { ok: true, json: async () => ({ ok: true }) }; };
  h.api.open(KEY); h.runTimers();
  h.click({ 'pvs-clear': U(2) }); await h.flush();
  assert.deepEqual(urls, [['https://cdsmnqxtyyoeoznmbidd.supabase.co/rest/v1/rpc/cancel_pdc_sublet_booking', { p_booking_id: 'b-2', p_expected_version: 3, p_reason: 'Dates cleared in Manage sublets' }]]);
  assert.equal(h.counts.refresh, 1);
});

test('perf guard: rendering 200 vehicles\' Manage sublets HTML makes no calls; loading the module makes no RPC or timer', () => {
  const h = runtime();
  assert.equal(h.counts.fetch + h.counts.refresh + h.counts.listProviders + h.counts.draws, 0, 'nothing runs per vehicle until Manage sublets is opened');
  const t0 = process.hrtime.bigint();
  for (let i = 0; i < 200; i++) vs.screenHtml(model(), { vehicleId: VID, perms: { canBook: true, providers } });
  const ms = Number(process.hrtime.bigint() - t0) / 1e6;
  assert.ok(ms < 1000, `200 screens in ${ms.toFixed(1)} ms`);
  const src = fs.readFileSync('pdc-vehicle-sublets.js', 'utf8');
  const pure = src.slice(0, src.indexOf("if (!root || !root.document || root.PDC_VEHICLE_SUBLETS) return;"));
  assert.doesNotMatch(pure.slice(pure.indexOf('function editorCells')), /fetch\(|refreshEmailVehicleLocations|renderAll|setTimeout/);
});

// ---- the Sublet page: create controls hidden, calendar view only ----
function intake({ view = 'list' } = {}) {
  const made = [];
  const el = (props = {}) => ({ hidden: false, style: {}, dataset: {}, attrs: {}, children: [], listeners: {}, tabIndex: 0,
    setAttribute(k, v) { this.attrs[k] = v; }, getAttribute(k) { return this.attrs[k]; }, addEventListener(t, f) { this.listeners[t] = f; },
    insertAdjacentHTML(_w, html) { this.after = (this.after || '') + html; }, appendChild(c) { this.children.push(c); }, querySelector: () => null, querySelectorAll: () => [], ...props });
  const createButton = el({ id: 'sublet-create-open' });
  let noteMade = false;
  const providerSelect = el({ disabled: false }), outInput = el({ disabled: false }), backInput = el({ disabled: false });
  const actions = el({ querySelector: () => null });
  const listRow = el({ lastElementChild: actions,
    querySelector: sel => (sel === '[data-sublet-toggle]' ? { dataset: { subletToggle: `op:${U(1)}` } } : sel === '.sublet-work-required' ? { insertAdjacentHTML() {} } : sel === '.sublet-status-pill.is-to-book' ? {} : null),
    querySelectorAll: sel => (sel.includes('pmbSubletProvider') ? [providerSelect, outInput, backInput] : []) });
  const openBtn = el({ className: 'sublet-calendar-event-open', dataset: { openStock: KEY } });
  openBtn.attrs['aria-label'] = 'Open FAKE01. Drag the card to move this date, or use the date field in List View.';
  const card = el({ draggable: true, querySelector: sel => (sel === '.sublet-calendar-event-open' ? openBtn : null) });
  const content = el({ id: 'sublet-home-content', querySelectorAll: sel => (sel === '[data-sublet-calendar-event]' ? [card] : sel === '[data-sublet-row]' || sel.includes('sublet') ? [listRow] : []) });
  const notes = [], opened = [], dialogOpens = [];
  const ctx = {
    PDC_SUPABASE_CONFIG: { projectRef: 'cdsmnqxtyyoeoznmbidd' }, PDC_AUTH_CONTEXT: { role: 'operator' },
    renderSubletHome: () => 'rendered', openSubletCreateDialog: () => { dialogOpens.push(1); }, closeSubletCreateDialog: () => {}, chooseSubletCreateVehicle: () => true,
    subletRows: () => [{ ...pendingRow, id: 'v1', __emailVehicleServerAuthoritative: true }], vehicleKey: v => v.__subletVehicleKey, pdcNotify: text => notes.push(text),
    PDC_VEHICLE_SUBLETS: { open: key => opened.push(key) },
    app: { currentView: 'other', subletViewMode: view },
    document: { getElementById: id => (id === 'sublet-create-open' ? createButton : id === 'sublet-home-content' ? content : id === 'pdc-sublet-book-note' ? (noteMade ? {} : null) : null),
      createElement: () => { const b = el(); made.push(b); return b; } },
  };
  createButton.insertAdjacentHTML = (_w, html) => { noteMade = true; createButton.after = html; };
  ctx.window = ctx;
  vm.createContext(ctx);
  vm.runInContext(fs.readFileSync(require.resolve('./pdc-sublet-intake.js'), 'utf8'), ctx);
  return { ctx, createButton, content, card, openBtn, actions, made, notes, opened, dialogOpens, providerSelect, outInput, backInput };
}

const NOTE = 'Book sublets from the vehicle: Vehicle Locations, open the vehicle, then Manage sublets';

test('Sublet page: Create Sublet is hidden (kept in the page) with the note; the create dialog no longer opens', () => {
  const h = intake();
  assert.equal(h.createButton.hidden, true); assert.equal(h.createButton.style.display, 'none'); assert.equal(h.createButton.tabIndex, -1);
  assert.ok(h.createButton.after.includes(NOTE));
  assert.equal(h.ctx.openSubletCreateDialog(), false);
  assert.deepEqual(h.dialogOpens, [], 'the old create dialog is not opened');
  assert.deepEqual(h.notes, [NOTE]);
  const html = fs.readFileSync('index.html', 'utf8');
  assert.match(html, /id="sublet-create-open"/, 'the button is hidden, not deleted');
});

test('Sublet list: no Book Sublet; supplier and dates read only; a Manage sublets button opens the vehicle', () => {
  const h = intake();
  assert.equal(h.ctx.renderSubletHome(), 'rendered');
  assert.equal(h.made.some(b => b.textContent === 'Book Sublet'), false);
  assert.ok([h.providerSelect, h.outInput, h.backInput].every(i => i.disabled === true));
  const manage = h.actions.children.find(b => b.textContent === 'Manage sublets');
  assert.ok(manage); manage.listeners.click({ stopPropagation() {} });
  assert.deepEqual(h.opened, [KEY]);
});

test('Sublet calendar: bookings still show but are view only (no drag); each card has Manage sublets', () => {
  const h = intake({ view: 'calendar' });
  h.ctx.renderSubletHome();
  assert.equal(h.card.draggable, false);
  assert.match(h.openBtn.attrs['aria-label'], /Change dates in Manage sublets\./);
  const manage = h.card.children.find(b => b.textContent === 'Manage sublets');
  assert.ok(manage); manage.listeners.click({ stopPropagation() {} });
  assert.deepEqual(h.opened, [KEY]);
  let prevented = false;
  h.content.listeners.dragstart({ target: { closest: () => ({}) }, preventDefault() { prevented = true; }, stopImmediatePropagation() {} });
  assert.equal(prevented, true, 'a drag on a calendar card is blocked');
});

test('source: the old create path stays behind CREATE_ON_SUBLET_PAGE=false (hidden, not deleted)', () => {
  const src = fs.readFileSync('pdc-sublet-intake.js', 'utf8');
  assert.match(src, /const CREATE_ON_SUBLET_PAGE=false;/);
  assert.match(src, /button\.textContent='Book Sublet'/);
  assert.match(fs.readFileSync('app.js', 'utf8'), /function openSubletCreateDialog\(\)/);
});
