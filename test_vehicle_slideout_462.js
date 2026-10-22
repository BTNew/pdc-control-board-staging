'use strict';
// r462 (F75): Vehicle Locations Table view: slide-out panel with drag between bays through the planner's own
// moveWorkshopDroppedPlan (Option A, fallback to the planner = Option B), the Parts loc column, resizable columns,
// and the panel's operations layout. Synthetic data only.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const table = require('./pdc-vehicle-locations-table.js');
const slideout = require('./pdc-vehicle-slideout.js');
const departments = require('./pdc-workshop-departments.js');
const { createFixture } = require('./qa/dashboard-render-fixture.cjs');
const { syntheticVehicles, syntheticPlans } = require('./qa/vehicle-locations-table-461-fixture.cjs');

const memoryStorage = () => {
  const store = new Map();
  return { store, getItem: k => (store.has(k) ? store.get(k) : null), setItem: (k, v) => store.set(k, String(v)), removeItem: k => store.delete(k) };
};
const COASTER = { vehicle: 'Coaster', toyotaVehicle: 'COASTER BUS 4X4 SYNTHETIC' };
const HILUX = { vehicle: 'HiLux', toyotaVehicle: 'HILUX SR5 SYNTHETIC' };
const busBooking = (category, bay, status = 'planned') => ({ id: `syn-${category}-${bay}-${status}`, version: 3, stage: 'BUS_4X4', bay, status, category, start: '2026-10-23T02:30:00Z' });

// ---------------- Parts loc column ----------------
test('Parts loc: the card\'s own parts-location span moves to its own cell; "—" when there is none', () => {
  const span = '<span class="tune-parts-location" title="Parts location: 05E2A" aria-label="Parts location: 05E2A">05E2A</span>';
  const unit = `<span class="incoming-card-main"><strong>Coaster</strong>${span}</span>`;
  const card = `<details class="incoming-vehicle-card" data-incoming-row="SYN-0001"><summary><span class="incoming-card-select"></span>${unit}<span class="incoming-card-work-wrap"><div class="pdc-station-strip"></div></span></summary></details>`;
  const split = table.extractPartsLocation(unit);
  assert.equal(split.span, span, 'verbatim span (same title, aria-label and text the card shows)');
  assert.equal(split.text, '05E2A');
  assert.equal(split.unit, '<span class="incoming-card-main"><strong>Coaster</strong></span>');
  const row = table.tableRowHtml(card, 'pmb', { key: 'SYN-0001' });
  assert.match(row, new RegExp(`<td class="c-ploc">${span.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}</td>`));
  assert.match(row, /<td class="c-unit"><span class="incoming-card-main"><strong>Coaster<\/strong><\/span><\/td>/, 'not shown twice');
  assert.match(row, /data-vlt-parts-loc="05E2A"/);
  assert.doesNotMatch(row, /c-loc|vlt-pill/, 'the old Loc column is gone');
  const none = table.tableRowHtml(card.replace(span, ''), 'pmb', { key: 'SYN-0001' });
  assert.match(none, /<td class="c-ploc"><span class="vlt-subtle-dash" title="No parts location">—<\/span><\/td>/);
  assert.equal(table.extractPartsLocation('<span class="tune-parts-location" title="x">A &amp; B</span>').text, 'A & B');
});

test('Parts loc sorts naturally with missing values last in both directions', () => {
  const values = ['12B1', '', '05E2A', '5A', '05E10', ''];
  const asc = [...values].sort((a, b) => table.comparePartsLocation(a, b, 'asc'));
  const desc = [...values].sort((a, b) => table.comparePartsLocation(a, b, 'desc'));
  assert.deepEqual(asc, ['5A', '05E2A', '05E10', '12B1', '', ''], 'numbers compare as numbers (05E2A before 05E10)');
  assert.deepEqual(desc, ['12B1', '05E10', '05E2A', '5A', '', '']);
});

test('Parts loc uses the card\'s data source: real pdc-service-locations.js output on a PMB vehicle, parity unchanged', () => {
  const fixture = createFixture({ vehicleCount: 0 });
  fixture.loadHelper('vehicle-requirements-guard.js');
  const c = fixture.context;
  c.PDC_SUPABASE_CONFIG = { projectRef: 'cdsmnqxtyyoeoznmbidd' };
  c.app.data = syntheticVehicles();
  const plans = syntheticPlans(c, c.app.data);
  c.workshopLoadPlans = () => plans;
  c.ensureDashboardWorkshopProjectionReady = () => true;
  const pmb = c.app.data.find(v => v.pdcLocation === 'PMB');
  const yard = c.app.data.find(v => v.pdcLocation === 'YH');
  pmb.tuneServiceLocations = { jobs: [{ ro_number: 'SYN-RO-1', parts_location: '05E2A', vehicle_key_number: '516' }] };
  yard.tuneServiceLocations = { jobs: [{ ro_number: 'SYN-RO-2', parts_location: '09Z9', vehicle_key_number: '17' }] };
  fixture.loadHelper('pdc-service-locations.js');
  const row = vehicle => {
    const bucket = c.incomingBucketForVehicle(vehicle);
    const card = c.incomingVehicleDetailRow(vehicle, bucket, { workshopPlans: plans, workshopProjectionAvailable: true, subletNavigation: true });
    return { card, row: table.tableRowHtml(card, bucket, { key: c.vehicleKey(vehicle) }) };
  };
  const a = row(pmb);
  assert.match(a.card, /Parts location: 05E2A/, 'the card shows it');
  assert.match(a.row, /<td class="c-ploc"><span class="tune-parts-location"[^>]*>05E2A<\/span><\/td>/, 'the table shows the same value in Parts loc');
  const b = row(yard);
  assert.doesNotMatch(b.card, /tune-parts-location/, 'off-site vehicles: the card shows none');
  assert.match(b.row, /<td class="c-ploc"><span class="vlt-subtle-dash"/, 'and the table shows —');
  const cells = html => (html.match(/class="incoming-work-check[^"]*"[^>]*>/g) || []).join('\n');
  assert.equal(cells(a.row), cells(a.card), 'station cells unchanged by the Parts loc move');
});

test('Parts loc: search includes it (table only), sorting is table-only and never changes the drop-down sort', () => {
  const source = fs.readFileSync('pdc-vehicle-locations-table.js', 'utf8');
  assert.match(source, /partsLocationValues\(vehicle\)\.some\(value => value\.toLowerCase\(\)\.includes\(needle\)\) && root\.incomingVehicleMatchesFilters\(vehicle, searchless\)/,
    'a search that matches the parts location shows the vehicle; every other filter still applies');
  assert.match(source, /vehiclePdcLocation\(vehicle\) !== 'PMB'\) return \[\]/, 'same on-site rule as the card');
  assert.match(source, /state\.partsSort \? comparePartsLocation\(a\.partsLoc, b\.partsLoc, state\.partsSort\) : 0/);
  assert.doesNotMatch(source, /incomingDashboardSort = \{ key: 'parts/, 'the shared drop-down sort is never set to the table-only column');
});

// ---------------- Resizable columns ----------------
test('column widths: saved per signed-in user on this device, like the view switch', () => {
  const storage = memoryStorage();
  assert.deepEqual(table.readWidths(storage, 'user-a'), {}, 'nothing saved: default widths');
  assert.equal(table.writeWidths(storage, 'user-a', { cust: 180, unit: 210 }), true);
  assert.deepEqual(table.readWidths(storage, 'user-a'), { cust: 180, unit: 210 });
  assert.deepEqual(table.readWidths(storage, 'user-b'), {}, 'another person on this device keeps their own widths');
  assert.equal(storage.store.get('pdc.vehicle-locations-columns.v1:user-a'), '{"cust":180,"unit":210}');
  assert.equal(table.columnStorageKey(''), 'pdc.vehicle-locations-columns.v1:signed-out');
  storage.setItem('pdc.vehicle-locations-columns.v1:user-c', '{not json');
  assert.deepEqual(table.readWidths(storage, 'user-c'), {}, 'broken value: defaults');
  const broken = { getItem() { throw new Error('blocked'); }, setItem() { throw new Error('blocked'); }, removeItem() { throw new Error('blocked'); } };
  assert.deepEqual(table.readWidths(broken, 'user-a'), {});
  assert.equal(table.writeWidths(broken, 'user-a', { cust: 120 }), false);
});

test('column widths: sensible minimums, a maximum, unknown columns dropped; the station column never shrinks', () => {
  const clean = table.sanitizeWidths({ key: 1, stock: 10, cust: 9999, unit: 'abc', ploc: 50.6, work: 100, status: -5, nope: 300, action: Infinity });
  assert.deepEqual(clean, { key: 30, stock: 56, cust: 520, ploc: 51, work: 282 });
  for (const [key, col] of Object.entries(table.COLUMNS)) {
    assert.ok(col.min >= 30 && col.min <= col.width, `${key}: minimum ${col.min} is at most its default ${col.width}`);
  }
  assert.equal(table.COLUMNS.work.min, table.COLUMNS.work.width, 'station strip keeps its 9 x 27 px cells at any width');
  assert.ok(table.COLUMNS.work.min >= 9 * 27 + 8 * 3 + 8, 'room for 9 cells, 8 gaps and the cell padding');
});

test('column widths: CSS variables keep pinned Key / Stock aligned; defaults equal the r461 widths; reset clears', () => {
  assert.equal(table.widthStyle({}), '', 'no saved widths: no inline style at all (r461 layout exactly)');
  const css = table.widthStyle({ key: 50, cust: 150 });
  assert.match(css, /--vlt-w-key:50px/);
  assert.match(css, /--vlt-w-cust:150px/);
  assert.match(css, /--vlt-left-key:26px/);
  assert.match(css, /--vlt-left-stock:76px/, 'Stock pins right after the wider Key column');
  const total = 26 + 50 + 92 + 150 + 132 + 66 + 282 + 72 + 104 + 176;
  assert.match(css, new RegExp(`--vlt-table-min:${total}px`));
  const sheet = fs.readFileSync('pdc-vehicle-locations-table.css', 'utf8');
  for (const [key, col] of Object.entries(table.COLUMNS)) {
    assert.match(sheet, new RegExp(`col\\.c-${key} \\{ width: var\\(--vlt-w-${key}, ${col.width}px\\); \\}`), `${key} default is the r461 width`);
  }
  assert.match(sheet, /\.c-key \{ left: var\(--vlt-left-key, 26px\); \}/);
  assert.match(sheet, /\.c-stock \{ left: var\(--vlt-left-stock, 64px\);/);
  const storage = memoryStorage();
  table.writeWidths(storage, 'user-a', { cust: 200 });
  assert.equal(table.resetWidths(storage, 'user-a'), true);
  assert.equal(storage.store.has('pdc.vehicle-locations-columns.v1:user-a'), false, 'Reset columns removes the saved widths');
  assert.deepEqual(table.readWidths(storage, 'user-a'), {});
  table.writeWidths(storage, 'user-a', {});
  assert.equal(storage.store.size, 0, 'saving nothing removes the key');
  const source = fs.readFileSync('pdc-vehicle-locations-table.js', 'utf8');
  assert.match(source, /data-vlt-reset-cols/, 'Reset columns button');
  assert.match(source, /role="separator" aria-orientation="vertical" tabindex="0"/, 'header edge grips are keyboard reachable');
  assert.match(source, /ArrowLeft[\s\S]{0,80}ArrowRight/);
});

// ---------------- Slide-out: rules, decisions, the planner call ----------------
test('panel bay targets follow the Dept 138 bay guide (bus_bay_guide_447) and Bay 3 no Coaster', () => {
  const GRID = { BUS_MECHANICAL: [1, 2, 3, 4, 5, 6], BUS_ACCESSORIES: [1, 2, 3, 4, 5, 6, 8, 9, 10], BUS_ELECTRICAL: [5, 6, 8, 9, 10], BUS_QA: [5, 6, 7] };
  for (const [category, free] of Object.entries(GRID)) {
    for (let bay = 1; bay <= 10; bay += 1) {
      const rules = slideout.predictedRules(busBooking(category, 0), HILUX, bay, departments).map(r => r.rule);
      assert.deepEqual(rules, free.includes(bay) ? [] : ['category_bay_mismatch'], `${category} bay ${bay}`);
    }
  }
  assert.deepEqual(slideout.predictedRules(busBooking('BUS_MECHANICAL', 0), COASTER, 3, departments).map(r => r.rule), ['bus_bay_vehicle_incompatible'], 'Coaster into Bay 3 asks to confirm');
  assert.deepEqual(slideout.predictedRules(busBooking('BUS_ELECTRICAL', 0), COASTER, 3, departments).map(r => r.rule), ['category_bay_mismatch', 'bus_bay_vehicle_incompatible']);
  assert.deepEqual(slideout.predictedRules(busBooking('BUS_WHOLE_JOB', 0), HILUX, 9, departments), [], 'whole-job booking (r450): no category rule');
  assert.deepEqual(slideout.predictedRules({ ...busBooking('', 0), stage: 'FITTING' }, COASTER, 3, departments), [], 'Dept 139 / shared bays: no bay rules');
});

test('drag handles: completed, Pit - external and Sublet are fixed; Bus 4x4 waits for its category', () => {
  assert.equal(slideout.movable(busBooking('BUS_MECHANICAL', 2, 'planned')), true);
  assert.equal(slideout.movable(busBooking('BUS_MECHANICAL', 2, 'started')), true);
  assert.equal(slideout.movable(busBooking('BUS_MECHANICAL', 2, 'completed')), false);
  assert.equal(slideout.movable({ ...busBooking('', 0), stage: 'PIT_INSPECTION' }), false);
  assert.equal(slideout.movable({ ...busBooking('', 0), stage: 'SUBLET' }), false);
  assert.equal(slideout.movable(busBooking('', 2)), false, 'no category yet');
  assert.equal(slideout.movable({ ...busBooking('', 4), stage: 'FITTING' }), true);
});

const plannerSpy = ({ entry = { id: 'plan-syn-1', startAt: '2026-10-23T02:30:00Z' }, result = true } = {}) => {
  const calls = { move: [], fallback: [], messages: [], station: 0 };
  return {
    calls,
    deps: {
      departments,
      helpers: { workshopDateKey: d => new Date(new Date(d).getTime() + 8 * 3600000).toISOString().slice(0, 10), workshopMinuteOffset: d => ((new Date(d).getUTCHours() + 8) % 24) * 60 + new Date(d).getUTCMinutes() - 7 * 60 },
      stationEntry: async () => { calls.station += 1; return entry; },
      moveWorkshopDroppedPlan: async (...args) => { calls.move.push(args); return result; },
      openInPlanner: (booking, bay, message) => calls.fallback.push({ booking: booking.id, bay, message }),
      message: (kind, text) => calls.messages.push({ kind, text }),
    },
  };
};

test('a drop calls the planner\'s moveWorkshopDroppedPlan with the station, the dropped bay and the booking\'s own start', async () => {
  const { calls, deps } = plannerSpy();
  const out = await slideout.performDrop(busBooking('BUS_ELECTRICAL', 9), HILUX, 8, deps);
  assert.equal(out.outcome, 'moved');
  assert.deepEqual(calls.move, [['plan-syn-1', 'BUS_4X4', 8, '2026-10-23', 210]], '10:30 Perth = 210 min after the 07:00 day start');
  assert.equal(calls.fallback.length, 0);
  // A rule-breaking drop still goes to the same function: its own warn-and-confirm (and the logged override) decide.
  const warn = plannerSpy({ result: false });
  const out2 = await slideout.performDrop(busBooking('BUS_ELECTRICAL', 9), COASTER, 3, warn.deps);
  assert.equal(out2.outcome, 'not-moved');
  assert.deepEqual(out2.rules.map(r => r.rule), ['category_bay_mismatch', 'bus_bay_vehicle_incompatible']);
  assert.deepEqual(warn.calls.move, [['plan-syn-1', 'BUS_4X4', 3, '2026-10-23', 210]]);
  // Dept 139 / shared station: same call, no rule hint.
  const fit = plannerSpy();
  await slideout.performDrop({ ...busBooking('', 2), stage: 'FITTING' }, HILUX, 4, fit.deps);
  assert.deepEqual(fit.calls.move, [['plan-syn-1', 'FITTING', 4, '2026-10-23', 210]]);
  // Unallocated (no start): now, and the planner finds the slot.
  const queued = plannerSpy({ entry: { id: 'plan-syn-2', startAt: '' } });
  await slideout.performDrop({ ...busBooking('BUS_QA', 0, 'queued'), start: '' }, HILUX, 7, queued.deps);
  assert.equal(queued.calls.move[0][0], 'plan-syn-2');
  assert.equal(queued.calls.move[0][2], 7);
});

test('started / STOPPAGE: a rule-breaking drop is refused in the panel; an allowed one uses the live-move path', async () => {
  for (const status of ['started', 'stoppage']) {
    const { calls, deps } = plannerSpy();
    const out = await slideout.performDrop(busBooking('BUS_MECHANICAL', 2, status), HILUX, 9, deps);
    assert.equal(out.outcome, 'blocked-live');
    assert.equal(calls.move.length, 0, 'nothing is called');
    assert.equal(calls.station, 0, 'station data is not even loaded');
    assert.match(calls.messages[0].text, /can't go to a bay that breaks the bay rule from here\. Use the planner\./);
    const ok = plannerSpy();
    const allowed = await slideout.performDrop(busBooking('BUS_MECHANICAL', 2, status), HILUX, 4, ok.deps);
    assert.equal(allowed.outcome, 'moved');
    assert.deepEqual(ok.calls.move, [['plan-syn-1', 'BUS_4X4', 4, '2026-10-23', 210]], 'moveWorkshopDroppedPlan routes started jobs to its live-move confirm');
  }
  const coaster = plannerSpy();
  assert.equal((await slideout.performDrop(busBooking('BUS_MECHANICAL', 2, 'started'), COASTER, 3, coaster.deps)).outcome, 'blocked-live', 'started Coaster into Bay 3');
});

test('station data not ready: the planner opens on the booking (Option B) and nothing is moved', async () => {
  const { calls, deps } = plannerSpy({ entry: null });
  const out = await slideout.performDrop(busBooking('BUS_ELECTRICAL', 9), HILUX, 8, deps);
  assert.equal(out.outcome, 'fallback-planner');
  assert.equal(calls.move.length, 0);
  assert.deepEqual(calls.fallback.map(f => [f.booking, f.bay]), [['syn-BUS_ELECTRICAL-9-planned', 8]]);
  const throwing = plannerSpy();
  throwing.deps.stationEntry = async () => { throw new Error('offline'); };
  assert.equal((await slideout.performDrop(busBooking('BUS_ELECTRICAL', 9), HILUX, 8, throwing.deps)).outcome, 'fallback-planner');
  const missing = plannerSpy();
  missing.deps.moveWorkshopDroppedPlan = null;
  assert.equal((await slideout.performDrop(busBooking('BUS_ELECTRICAL', 9), HILUX, 8, missing.deps)).outcome, 'fallback-planner');
});

test('the panel reads the planner\'s drop function and date helpers only after the station data has loaded', async () => {
  // The planner modules arrive inside stationEntry(); capturing them before that would always fall back to Option B.
  const src = fs.readFileSync('pdc-vehicle-slideout.js', 'utf8');
  assert.match(src, /get moveWorkshopDroppedPlan\(\) \{ return typeof root\.moveWorkshopDroppedPlan === 'function'/);
  assert.match(src, /workshopDateKey: when => root\.workshopDateKey\(when\), workshopMinuteOffset: when => root\.workshopMinuteOffset\(when\)/);
  let loaded = null; const calls = [];
  const deps = { departments: plannerSpy().deps.departments, message: () => {}, openInPlanner: () => calls.push('planner'),
    helpers: { workshopDateKey: d => loaded.dateKey(d), workshopMinuteOffset: d => loaded.offset(d) },
    stationEntry: async () => { loaded = { dateKey: () => '2026-10-23', offset: () => 270, move: (...a) => { calls.push(a); return true; } };
      return { id: 'plan-syn-9', startAt: '2026-10-23T02:30:00Z' }; },
    get moveWorkshopDroppedPlan() { return loaded ? loaded.move : null; } };
  const out = await slideout.performDrop(busBooking('BUS_MECHANICAL', 1), HILUX, 5, deps);
  assert.equal(out.outcome, 'moved');
  assert.deepEqual(calls, [['plan-syn-9', 'BUS_4X4', 5, '2026-10-23', 270]]);
});

test('same bay, fixed jobs and empty drops call nothing', async () => {
  const { calls, deps } = plannerSpy();
  assert.equal((await slideout.performDrop(busBooking('BUS_ELECTRICAL', 9), HILUX, 9, deps)).outcome, 'same-bay');
  assert.equal((await slideout.performDrop(busBooking('BUS_ELECTRICAL', 9, 'completed'), HILUX, 8, deps)).outcome, 'fixed');
  assert.equal((await slideout.performDrop({ ...busBooking('', 0), stage: 'PIT_INSPECTION' }, HILUX, 1, deps)).outcome, 'fixed');
  assert.equal((await slideout.performDrop({ ...busBooking('', 0), stage: 'SUBLET' }, HILUX, 1, deps)).outcome, 'fixed');
  assert.equal((await slideout.performDrop(busBooking('BUS_ELECTRICAL', 9), HILUX, 0, deps)).outcome, 'none');
  assert.equal(calls.move.length + calls.station + calls.fallback.length, 0);
});

test('bookings come from the vehicle\'s Workshop detail (category, version), else the board', () => {
  const detail = { bookings: [{ booking_id: 'b1', booking_version: 4, work_category: 'BUS_QA', stage_code: 'BUS_4X4', stage_name: 'Bus 4x4', bay_number: 7, status: 'planned', scheduled_start_at: 'x', scheduled_end_at: 'y', default_duration_minutes: 90 }] };
  assert.deepEqual(slideout.bookingsFrom(detail, {}), [{ id: 'b1', version: 4, stage: 'BUS_4X4', stageName: 'Bus 4x4', bay: 7, status: 'planned', start: 'x', end: 'y', category: 'BUS_QA', minutes: 90, source: 'detail' }]);
  const board = slideout.bookingsFrom(null, { salesWorkshopBookings: [{ bookingId: 'b2', stageCode: 'FITTING', bayName: 'Bay 03', status: 'started', scheduledStartAt: 's' }] });
  assert.equal(board[0].bay, 3);
  assert.equal(board[0].category, '');
  assert.equal(board[0].source, 'board');
});

// ---------------- Safety, scope, loader ----------------
test('the panel never calls an RPC or fetch itself and writes nothing to storage', () => {
  const source = fs.readFileSync('pdc-vehicle-slideout.js', 'utf8').replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/.*$/gm, '');
  assert.doesNotMatch(source, /\bfetch\s*\(|\.rpc\s*\(|XMLHttpRequest|sendBeacon|localStorage|sessionStorage|\beval\s*\(|new Function/);
  assert.doesNotMatch(source, /__workshopSharedActions|administratorMoveBooking|moveBooking\(|mutate\(/, 'moves only through moveWorkshopDroppedPlan');
  assert.match(source, /root\.moveWorkshopDroppedPlan\(\.\.\.args\)/);
  assert.doesNotMatch(source, /deleteIncomingVehicleFromMain\(|completeVehicle|markVehicleComplete/, 'never calls delete / complete itself');
  const tableSource = fs.readFileSync('pdc-vehicle-locations-table.js', 'utf8');
  assert.doesNotMatch(tableSource, /\beval\s*\(|new Function|\.rpc\(|fetch\(/);
});

test('panel CSS is scoped to the panel: the Drop-down view card and station cells are untouched', () => {
  const css = fs.readFileSync('pdc-vehicle-slideout.css', 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');
  const rules = [...css.matchAll(/([^{}]+)\{([^{}]*)\}/g)].map(m => [m[1].trim(), m[2]]);
  assert.ok(rules.length > 40);
  for (const [selector, body] of rules) {
    for (const part of selector.split(',').map(s => s.trim())) {
      assert.match(part, /^(#vso-shell\b|\.vso-ghost\b|\.vso-target-bay\b)/, `${part} is scoped to the panel`);
    }
    if (/incoming-work-check|incoming-work-box|parts-jita|pdc-station-strip|pdc-sublet-po|badge/.test(selector)) {
      assert.doesNotMatch(body, /(^|;|\s)(color|background(-color|-image)?|border(-\w+)?-color|opacity|content)\s*:/, `${selector} must not change colours or symbols`);
    }
  }
  // Craig 08:07: operations stacked full width, one row per line, ellipsis + full text on hover and focus.
  assert.match(css, /#vso-shell \.authenticated-email-operations \.pdc-op-panels \{ display: flex !important; flex-direction: column;/);
  assert.match(css, /li > span \{[^}]*white-space: nowrap !important; overflow: hidden !important; text-overflow: ellipsis;/);
  assert.match(css, /li\[data-vso-full\]:hover::after,\s*#vso-shell \.authenticated-email-operations li\[data-vso-full\]:focus::after/);
  assert.match(css, /content: attr\(data-vso-full\)/);
  const js = fs.readFileSync('pdc-vehicle-slideout.js', 'utf8');
  assert.match(js, /if \(!span\.title\) span\.title = full;/, 'title tooltip');
  assert.match(js, /li\.tabIndex = 0/, 'keyboard focus shows it');
  for (const locked of ['styles.css', 'app.js', 'pdc-operation-panels.js']) {
    assert.doesNotMatch(fs.readFileSync(locked, 'utf8'), /vso-|r462/, `${locked} untouched`);
  }
});

test('loading both modules leaves the Drop-down view render byte-for-byte unchanged', () => {
  const fixture = createFixture({ vehicleCount: 0 });
  fixture.loadHelper('vehicle-requirements-guard.js');
  const c = fixture.context;
  c.app.data = syntheticVehicles();
  const plans = syntheticPlans(c, c.app.data);
  c.workshopLoadPlans = () => plans;
  c.ensureDashboardWorkshopProjectionReady = () => true;
  c.renderIncomingDashboardBoard();
  const before = fixture.host.innerHTML;
  fixture.loadHelper('pdc-vehicle-locations-table.js');
  fixture.loadHelper('pdc-vehicle-slideout.js');
  assert.equal(typeof c.PDC_VEHICLE_SLIDEOUT.open, 'function', 'panel installed');
  assert.equal(c.PDC_VEHICLE_LOCATIONS_TABLE.state.view, 'dropdown', 'default stays the Drop-down view');
  fixture.host.innerHTML = '';
  c.renderIncomingDashboardBoard();
  assert.equal(fixture.host.innerHTML, before);
  assert.doesNotMatch(before, /vso-|c-ploc|vlt-col-resize/);
});

test('loader: slide-out loads after the table module; cache-bust tags; runtime files; pdc-auto-reload.js first', () => {
  const entry = fs.readFileSync('canonical-entry.js', 'utf8');
  assert.match(entry, /pdc-vehicle-locations-table\.js\?vehicle-locations-table=2026\.10\.22\.r461&r462=2026\.10\.22\.r462/);
  assert.match(entry, /table\.onload = loadVehicleSlideout;/);
  assert.match(entry, /pdc-vehicle-slideout\.js\?vehicle-slideout=2026\.10\.22\.r462/);
  assert.match(fs.readFileSync('pdc-vehicle-slideout.js', 'utf8'), /pdc-vehicle-slideout\.css\?vehicle-slideout=\$\{VERSION\}/);
  assert.match(fs.readFileSync('pdc-vehicle-slideout.js', 'utf8'), /const VERSION = '2026\.10\.22\.r462'/);
  const html = fs.readFileSync('index.html', 'utf8');
  assert.match(html, /canonical-entry\.js\?[^"]*r462=2026\.10\.22\.r462/);
  const scripts = [...html.matchAll(/<script[^>]*src="([^"]+)"/g)].map(m => m[1]);
  assert.match(scripts[0], /^pdc-auto-reload\.js/);
  assert.match(fs.readFileSync('scripts/build_pages_runtime.js', 'utf8'), /'pdc-vehicle-slideout\.js', 'pdc-vehicle-slideout\.css'/);
});

test('this test and its fixtures carry no real stock numbers, job cards or customer names', () => {
  const text = fs.readFileSync(__filename, 'utf8');
  assert.doesNotMatch(text, /\b1[23]\d{6}\b/);
  assert.doesNotMatch(text, /\bJ13[89]\d{6}\b/);
});
