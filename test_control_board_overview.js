'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { performance } = require('node:perf_hooks');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const overview = require('./control-board-overview.js');
const { buildModel, render } = overview;
const fixture = require('./qa/control-board-fixtures.js');
const allItems = model => [...model.waiting, ...model.columns.flatMap(column => column.items)];

test('missing authoritative bay or booking arrays fail closed', () => {
  for (const snapshot of [null, {}, { board: {} }, { board: { bays: [] } }, { board: { bookings: [] } }]) assert.equal(buildModel(snapshot), null);
});

test('empty snapshot preserves all 43 physical bay rows and their order', () => {
  const model = buildModel(fixture.emptySnapshot());
  assert.equal(model.totalBays, 43);
  assert.deepEqual(model.stages, fixture.stages.map(([stage]) => stage));
  assert.equal(model.totalBookings, 0);
  assert.equal(model.totalWaiting, 0);
  assert.equal((render(model).match(/data-control-board-bay=/g) || []).length, 43);
  assert.doesNotMatch(render(model), /<(details|summary)\b/);
});

test('booking appears only in its canonical bay, even when vehicle location points elsewhere', () => {
  const snapshot = fixture.emptySnapshot();
  const bay = snapshot.board.bays[3];
  snapshot.board.bookings.push(fixture.booking(1, bay, fixture.vehicle(1, { pmb_stage: 'TYRE', pmb_bay_number: 2 })));
  const model = buildModel(snapshot);
  assert.equal(model.columns.find(column => column.bay.bay_id === bay.bay_id).items.length, 1);
  assert.equal(model.columns.filter(column => column.items.length).length, 1);
  assert.equal(model.waiting.length, 0);
});

test('same vehicle can have distinct bookings in different station bays', () => {
  const snapshot = fixture.emptySnapshot();
  const person = fixture.vehicle(1);
  const other = snapshot.board.bays.find(bay => bay.stage_code === 'HOIST');
  snapshot.board.bookings.push(fixture.booking(1, snapshot.board.bays[0], person), fixture.booking(2, other, person));
  const model = buildModel(snapshot);
  assert.equal(model.totalBookings, 2);
  assert.equal(allItems(model).filter(item => item.vehicle.id === person.id).length, 2);
});

test('duplicate booking UUID is rendered once without deduplicating different jobs by stock', () => {
  const snapshot = fixture.emptySnapshot();
  const first = fixture.booking(1, snapshot.board.bays[0]);
  const second = fixture.booking(2, snapshot.board.bays[1], fixture.vehicle(2, { stock_number: first.vehicle.stock_number }));
  snapshot.board.bookings.push(first, { ...first }, second);
  const model = buildModel(snapshot);
  assert.equal(model.totalBookings, 2);
  assert.equal(allItems(model).length, 2);
});

test('completed, deleted and cancelled bookings never enter the active board', () => {
  const snapshot = fixture.emptySnapshot();
  snapshot.board.bookings.push(...['completed', 'deleted', 'cancelled'].map((status, index) => fixture.booking(index + 1, snapshot.board.bays[0], undefined, { status })));
  snapshot.board.bookings.push(fixture.booking(4, snapshot.board.bays[0], undefined, { deleted_at: '2026-09-14T01:00:00Z' }));
  assert.equal(allItems(buildModel(snapshot)).length, 0);
});

test('hidden, deleted and inactive canonical vehicles are not shown', () => {
  const snapshot = fixture.emptySnapshot();
  [{ visible_on_board: false }, { deleted_at: '2026-09-14T01:00:00Z' }, { lifecycle_state: 'completed' }].forEach((flags, index) => {
    const person = fixture.vehicle(index + 1, flags);
    snapshot.board.bookings.push(fixture.booking(index + 1, snapshot.board.bays[0], person));
    snapshot.candidates.push({ stage_code: 'HOIST', vehicle: person });
  });
  assert.equal(allItems(buildModel(snapshot)).length, 0);
});

test('unallocated booking replaces its matching requirement, never the other station requirement', () => {
  const snapshot = fixture.emptySnapshot();
  const person = fixture.vehicle(1);
  snapshot.board.bookings.push(fixture.booking(1, snapshot.board.bays[0], person, { status: 'queued', bay_id: null, bay_number: null }));
  snapshot.candidates.push({ stage_code: 'BUS_4X4', vehicle: person }, { stage_code: 'HOIST', vehicle: person });
  const model = buildModel(snapshot);
  assert.equal(model.waiting.length, 2);
  assert.equal(model.waiting.filter(item => item.kind === 'booking').length, 1);
  assert.equal(model.waiting.find(item => item.kind === 'candidate').stage, 'HOIST');
});

test('existing_booking boolean alone never hides an unallocated requirement', () => {
  const snapshot = fixture.emptySnapshot();
  const candidate = { stage_code: 'FITTING', vehicle: fixture.vehicle(1), existing_booking: true };
  snapshot.candidates.push(candidate, { ...candidate });
  assert.equal(buildModel(snapshot).waiting.length, 1);
});

test('an allocated booking suppresses only the same canonical vehicle and station candidate', () => {
  const snapshot = fixture.emptySnapshot();
  const person = fixture.vehicle(1);
  snapshot.board.bookings.push(fixture.booking(1, snapshot.board.bays[0], person));
  snapshot.candidates.push({ stage_code: 'BUS_4X4', vehicle: person }, { stage_code: 'HOIST', vehicle: person }, { stage_code: 'BUS_4X4', vehicle: fixture.vehicle(2, { stock_number: person.stock_number }) });
  const model = buildModel(snapshot);
  assert.equal(model.totalBookings, 1);
  assert.equal(model.waiting.length, 2);
});

test('unknown or mismatched bay UUID never places a booking in another physical bay', () => {
  const snapshot = fixture.emptySnapshot();
  snapshot.board.bookings.push(fixture.booking(1, snapshot.board.bays[0], undefined, { bay_id: fixture.uuid(999) }), fixture.booking(2, snapshot.board.bays[0], undefined, { stage_code: 'TYRE' }));
  const model = buildModel(snapshot);
  assert.equal(model.columns.reduce((count, column) => count + column.items.length, 0), 0);
  assert.equal(model.waiting.length, 2);
  assert.ok(model.waiting.every(item => item.unassignedBay));
  assert.match(render(model), /Check bay allocation/);
});

test('inactive physical bay and its existing booking stay visible', () => {
  const snapshot = fixture.emptySnapshot();
  snapshot.board.bays[0].is_active = false;
  snapshot.board.bookings.push(fixture.booking(1, snapshot.board.bays[0]));
  const model = buildModel(snapshot);
  assert.equal(model.totalBays, 43);
  assert.equal(model.columns[0].items.length, 1);
  assert.match(render(model), /Inactive · existing bookings only/);
});

test('Sublet never becomes a numbered physical bay or waiting workshop requirement', () => {
  const snapshot = fixture.emptySnapshot();
  const sublet = { bay_id: fixture.uuid(999), stage_code: 'SUBLET', bay_number: 1 };
  snapshot.board.bays.push(sublet);
  snapshot.board.bookings.push(fixture.booking(1, sublet));
  snapshot.candidates.push({ stage_code: 'SUBLET', vehicle: fixture.vehicle(2) });
  const model = buildModel(snapshot);
  assert.equal(model.totalBays, 43);
  assert.equal(allItems(model).length, 0);
});

test('live and stoppage work precede the scheduled queue, which sorts by time', () => {
  const snapshot = fixture.emptySnapshot();
  const bay = snapshot.board.bays[0];
  snapshot.board.bookings.push(fixture.booking(1, bay, undefined, { scheduled_start_at: '2026-09-17T01:00:00Z' }), fixture.booking(2, bay, undefined, { scheduled_start_at: '2026-09-16T01:00:00Z' }), fixture.booking(3, bay, undefined, { status: 'started', scheduled_start_at: '2026-09-18T01:00:00Z' }));
  assert.deepEqual(buildModel(snapshot).columns[0].items.map(item => item.id), [fixture.uuid(20003), fixture.uuid(20002), fixture.uuid(20001)]);
});

test('moving a booking between refreshed snapshots moves one card and preserves UUID', () => {
  const snapshot = fixture.emptySnapshot();
  const booking = fixture.booking(1, snapshot.board.bays[0]);
  snapshot.board.bookings.push(booking);
  assert.equal(buildModel(snapshot).columns[0].items.length, 1);
  booking.bay_id = snapshot.board.bays[1].bay_id;
  booking.bay_number = 2;
  const model = buildModel(snapshot);
  assert.equal(model.columns[0].items.length, 0);
  assert.equal(model.columns[1].items[0].id, booking.booking_id);
  assert.equal(allItems(model).length, 1);
});

test('stock, key, job card, customer and full vehicle description all remain searchable', () => {
  const snapshot = fixture.emptySnapshot();
  snapshot.board.bookings.push(fixture.booking(1, snapshot.board.bays[0], fixture.vehicle(1, { key_number: 'UNIQUE-KEY', job_card_number: 'UNIQUE-JOB', customer_name: 'Distinct customer name', vehicle_description: 'Distinctive long wheelbase vehicle' })));
  for (const search of ['demo-0001', 'unique-key', 'unique-job', 'distinct customer', 'long wheelbase']) {
    const model = buildModel(snapshot, { search });
    assert.equal(model.matchingItems, 1, search);
    assert.equal(model.totalBays, 43);
    assert.equal(model.totalBookings, 1);
  }
});

test('no-match search hides all bay rows with accurate totals and an explicit no-results state', () => {
  const snapshot = fixture.populatedSnapshot();
  const full = buildModel(snapshot);
  const model = buildModel(snapshot, { search: 'NO-SUCH-DEMONSTRATION' });
  assert.equal(model.totalBays, 43);
  assert.equal(model.totalBookings, full.totalBookings);
  assert.equal(model.matchingItems, 0);
  assert.equal(model.columns.length, 0);
  assert.equal(model.stages.length, 0);
  assert.doesNotMatch(render(model), /data-control-board-bay=/);
  assert.match(render(model), /No matching jobs/);
});

test('vehicle search keeps only its booked bays and restores all bays when cleared', () => {
  const snapshot = fixture.populatedSnapshot();
  const original = structuredClone(snapshot);
  const model = buildModel(snapshot, {search:'DEMO-0001'});
  assert.equal(model.columns.length,2);
  assert.deepEqual(model.stages,['BUS_4X4','TYRE']);
  assert.equal(allItems(model).length,2);
  assert.ok(allItems(model).every(item => item.vehicle.stock_number === 'DEMO-0001'));
  assert.equal((render(model).match(/data-control-board-bay=/g)||[]).length,2);
  assert.match(render(model), /2 bays · 2 bookings · 0 unallocated/);
  const range = overview.searchDateRange(model,{now:new Date('2026-09-15T01:00:00Z')});
  assert.deepEqual(range,{startDate:'2026-09-15',dayCount:3});
  const timeline = overview.buildTimeline(model, {...range,now:new Date('2026-09-15T01:00:00Z')});
  assert.equal(timeline.outside.length,0);
  assert.equal(new Set(timeline.rows.flatMap(row=>row.segments.map(segment=>segment.item.id))).size,2);
  assert.equal(buildModel(snapshot,{search:''}).columns.length,43);
  assert.deepEqual(snapshot,original,'search never changes source bookings');
});

test('unallocated-only matches remain visible without empty bay rows', () => {
  const model = buildModel(fixture.populatedSnapshot(),{search:'DEMO-1000'});
  assert.equal(model.columns.length,0);
  assert.equal(model.waiting.length,1);
  assert.match(render(model), /Unallocated · 1/);
  assert.doesNotMatch(render(model), /No matching jobs/);
  assert.equal(overview.searchDateRange(model),null);
});

test('search date span is bounded and keeps long-range bookings accessible', () => {
  const snapshot=fixture.emptySnapshot();
  snapshot.board.bookings.push(fixture.booking(1,snapshot.board.bays[0],undefined,{scheduled_end_at:'2027-09-15T04:00:00Z'}));
  const model=buildModel(snapshot,{search:'DEMO-0001'});
  assert.equal(overview.searchDateRange(model).dayCount,56);
});

test('admin blocks occupy only their canonical bay and do not inflate vehicle booking totals', () => {
  const snapshot = fixture.emptySnapshot();
  const block = { block_id: fixture.uuid(30000), bay_id: snapshot.board.bays[0].bay_id, label: 'Workshop maintenance' };
  snapshot.board.admin_blocks.push(block, { ...block }, { ...block, block_id: fixture.uuid(30001), deleted_at: '2026-09-14' });
  const model = buildModel(snapshot);
  assert.equal(model.columns[0].items.length, 1);
  assert.equal(model.totalBookings, 0);
  assert.match(render(model), /Workshop maintenance/);
});

test('untrusted identity and admin text is escaped in visible HTML and attributes', () => {
  const snapshot = fixture.emptySnapshot();
  snapshot.board.bookings.push(fixture.booking(1, snapshot.board.bays[0], fixture.vehicle(1, { customer_name: '<script>alert(1)</script>', vehicle_description: '" onfocus="alert(2)' })));
  snapshot.board.admin_blocks.push({ block_id: fixture.uuid(30000), bay_id: snapshot.board.bays[0].bay_id, label: '<img src=x onerror=alert(3)>' });
  const html = render(buildModel(snapshot));
  assert.doesNotMatch(html, /<script|<img|\s+onfocus="alert/);
  assert.match(html, /&lt;script&gt;/);
  assert.match(html, /data-control-board-id="00004e21-0000-4000-8000-000000000001"/);
});

test('building and rendering 43 bays with 1000 synthetic bookings is bounded', t => {
  const snapshot = fixture.emptySnapshot();
  snapshot.board.bookings = Array.from({ length: 1000 }, (_, index) => fixture.booking(index + 1, snapshot.board.bays[index % 43]));
  const started = performance.now();
  const model = buildModel(snapshot);
  const html = render(model);
  const elapsed = performance.now() - started;
  assert.equal(model.totalBookings, 1000);
  assert.equal((html.match(/data-control-board-item="booking"/g) || []).length, 1000);
  assert.ok(elapsed < 2000, `1000-job render took ${elapsed.toFixed(1)}ms`);
  t.diagnostic(`43 bays / 1000 jobs: ${elapsed.toFixed(2)}ms for model plus HTML`);
});

const appSource = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8');
function extracted(startName, endName) {
  const start = appSource.indexOf(`function ${startName}(`);
  const end = appSource.indexOf(`\nfunction ${endName}(`, start);
  assert.ok(start >= 0 && end > start, `Actual app function ${startName} is extractable`);
  return appSource.slice(start, end);
}
function integrationRuntime(overrides = {}) {
  const calls = { exact: [], details: [], planner: [], load: [], scroll: [], scrollTo: [], jump: [], focus: [], removedClass: [] };
  const scroller = { scrollLeft: 2700, scrollTop: 91, clientWidth: 1100, scrollBy: options => calls.scroll.push(options), scrollTo: options => { calls.scrollTo.push(options); scroller.scrollLeft = options.left; scroller.scrollTop = options.top; } };
  const match = { tagName: 'BUTTON', scrollIntoView: options => calls.jump.push(options), focus: options => calls.focus.push(options) };
  const columns = [{ dataset: { controlBoardStage: 'TYRE' }, offsetTop: 2400, scrollIntoView: options => calls.jump.push(options) }];
  let html = '';
  const host = {
    get innerHTML() { return html; }, set innerHTML(value) { html = value; }, onclick: null,
    querySelector: selector => {
      if (selector === '.control-board-bays-scroll') return scroller;
      if (selector === '[data-control-board-match]') return html.includes('data-control-board-match') ? match : null;
      if (selector === '[data-control-board-start]') {
        const value = /data-control-board-start value="([^"]+)"/.exec(html)?.[1];
        return value ? { value } : null;
      }
      return null;
    },
    querySelectorAll: () => columns,
    contains: node => node.inside !== false,
  };
  const search = { value: '' }, floating = { hidden: false };
  const context = {
    app: { data: [], workflowSearch: '', workshopEligibilityState: 'connected', workshopEligibilitySnapshot: fixture.populatedSnapshot(), ...overrides },
    // Keep live carry-over projections on the same clock as the fixture and app VM.
    window: { ControlBoardOverview: {...overview,searchDateRange:(model,options={})=>overview.searchDateRange(model,{now:new Date('2026-09-15T01:00:00Z'),...options})} },
    document: { body: { classList: { remove: name => calls.removedClass.push(name) } } },
    $: selector => ({ '#workflow-board': host, '#workflow-search': search, '#workflow-floating-column-header': floating }[selector] || null),
    workshopEligibilitySharedAuthorityEnabled: () => true,
    loadWorkshopEligibilitySnapshot: reason => calls.load.push(reason),
    escapeHtml: value => String(value || ''),
    WORKSHOP_CONTROL_BOARD_STATIONS: fixture.stages.map(([stage]) => stage),
    openVehicleWorkshopBooking: (...args) => { calls.exact.push(args); return true; },
    openVehicleWorkBookingsFromTile: tile => { calls.details.push(tile); return true; },
    openWorkshopPlannerForStage: stage => { calls.planner.push(stage); return true; },
    vehicleKey: vehicle => vehicle.stock || vehicle.id,
    Date: class extends Date { constructor(...args) { super(...(args.length ? args : ['2026-09-15T01:00:00Z'])); } static now() { return Date.parse('2026-09-15T01:00:00Z'); } }, Intl, console,
  };
  vm.createContext(context);
  vm.runInContext(extracted('vehicleWorkshopPerthDateKey', 'vehicleWorkshopBookingTimeLabel'), context);
  vm.runInContext(extracted('renderWorkflowBoard', 'vehicleHasNavisionSource'), context);
  const click = dataset => host.onclick({ target: { closest: () => ({ dataset, hasAttribute: name => Object.hasOwn(dataset, name.slice(5).replace(/-([a-z])/g, (_, letter) => letter.toUpperCase())) }) } });
  return { context, calls, host, scroller, search, floating, match, click };
}

test('actual app booking click uses canonical IDs and Perth date, including UTC previous day', () => {
  const runtime = integrationRuntime();
  const snapshot = fixture.emptySnapshot();
  const source = fixture.booking(1, snapshot.board.bays[0], undefined, { scheduled_start_at: '2026-09-14T23:00:00Z' });
  runtime.context.openControlBoardOverviewItem({ kind: 'booking', stage: source.stage_code, vehicle: source.vehicle, source });
  assert.deepEqual(runtime.calls.exact[0].slice(0,6), [source.booking_id, 'BUS_4X4', '2026-09-15', source.vehicle_id, source.vehicle.stock_number, 1]);
  assert.equal(runtime.calls.exact[0][6].showSurrounding, true);
  assert.equal(runtime.calls.details.length, 0);
});

test('actual app queued click opens canonical vehicle Work & bookings without inventing a bay', () => {
  const runtime = integrationRuntime();
  const person = fixture.vehicle(1);
  runtime.context.app.data = [{ id: fixture.uuid(55), stock: person.stock_number }, { id: person.id, stock: 'CANONICAL-MATCH' }];
  runtime.context.openControlBoardOverviewItem({ kind: 'booking', stage: 'FITTING', vehicle: person, source: { status: 'queued', scheduled_start_at: '2026-09-14T23:00:00Z', bay_id: null } });
  assert.equal(runtime.calls.exact.length, 0);
  assert.equal(runtime.calls.details[0].dataset.openWorkBookings, 'CANONICAL-MATCH');
  assert.equal(runtime.calls.details[0].dataset.workStation, 'FITTING');
  assert.equal(runtime.calls.details[0].dataset.workBay, '');
});

test('Control Board links request surrounding bookings while vehicle-detail links keep their focused mode', () => {
  const context = {
    app: {}, window: { VehicleRequirementsGuard: { exactBookingNavigationTarget: target => target.bookingId ? target : null } },
    vehicleWorkshopStageCode: value => value, WORKSHOP_PLANNER_ROUTE_BY_STAGE: { FABRICATION: 'fab' },
    closeVehicleModal() {}, openWorkshopPlannerForStage() {},
  };
  vm.createContext(context);
  const start = appSource.indexOf('function openVehicleWorkshopBooking(');
  const end = appSource.indexOf('\nasync function ', start);
  vm.runInContext(appSource.slice(start,end),context);
  assert.equal(context.openVehicleWorkshopBooking('booking-id','FABRICATION','2026-09-17','vehicle-id','stock',5,{showSurrounding:true}),true);
  assert.equal(context.app.pendingWorkshopBookingLink.focused,false);
  assert.equal(context.app.pendingWorkshopBookingLink.search,true);
  assert.equal(context.app.pendingWorkshopBookingLink.date,'2026-09-17');
  assert.equal(context.app.pendingWorkshopBookingLink.vehicleId,'vehicle-id');
  assert.equal(context.openVehicleWorkshopBooking('booking-id','FABRICATION','2026-09-17','vehicle-id','stock',5),true);
  assert.equal(context.app.pendingWorkshopBookingLink.focused,true);
  assert.equal(context.app.pendingWorkshopBookingLink.search,undefined);
  const pending = context.app.pendingWorkshopBookingLink;
  assert.equal(context.openVehicleWorkshopBooking('','FABRICATION'),false);
  assert.equal(context.app.pendingWorkshopBookingLink,pending,'invalid identity never replaces a valid navigation intent');
});

test('actual app missing local vehicle and unresolved bay fall back safely to its planner', () => {
  const runtime = integrationRuntime();
  runtime.context.openControlBoardOverviewItem({ kind: 'booking', stage: 'HOIST', vehicle: fixture.vehicle(1), unassignedBay: true, source: { bay_id: fixture.uuid(999), scheduled_start_at: '2026-09-15T02:00:00Z' } });
  assert.equal(runtime.calls.exact.length, 0);
  assert.deepEqual(runtime.calls.planner, ['HOIST']);
});

test('actual app rendering hides retained snapshots during loading, reconnect, permission or network failure', () => {
  for (const state of ['idle', 'loading', 'reconnecting', 'offline_error', 'permission_denied']) {
    const runtime = integrationRuntime({ workshopEligibilityState: state });
    runtime.context.renderWorkflowBoard();
    assert.doesNotMatch(runtime.host.innerHTML, /data-control-board-bay=|DEMO-0001/, state);
    assert.match(runtime.host.innerHTML, /Workshop overview unavailable|Loading workshop overview/, state);
    assert.equal(runtime.calls.load.length, state === 'idle' ? 1 : 0);
  }
});

test('actual app rejects incomplete connected snapshots instead of showing old board data', () => {
  const runtime = integrationRuntime({ workshopEligibilitySnapshot: { board: { bays: [] } } });
  runtime.host.innerHTML = 'OLD RETAINED BOARD';
  runtime.context.renderWorkflowBoard();
  assert.match(runtime.host.innerHTML, /full bay list could not be loaded/);
  assert.doesNotMatch(runtime.host.innerHTML, /OLD RETAINED BOARD/);
});

test('actual app rerender preserves both board scroll positions and hides legacy floating headers', () => {
  const runtime = integrationRuntime();
  runtime.context.renderWorkflowBoard();
  assert.equal(runtime.scroller.scrollLeft, 2700);
  assert.equal(runtime.scroller.scrollTop, 91);
  assert.equal(runtime.context.app.controlBoardScroll.left, 2700);
  assert.equal(runtime.floating.hidden, true);
  assert.match(runtime.host.innerHTML, /data-control-board-bay=/);
});

test('actual app delegated navigation finds exact cards and horizontal scroll controls', () => {
  const runtime = integrationRuntime();
  runtime.context.renderWorkflowBoard();
  const booking = runtime.context.app.workshopEligibilitySnapshot.board.bookings[0];
  const click = runtime.click;
  click({ controlBoardItem: 'booking', controlBoardId: booking.booking_id });
  assert.equal(runtime.calls.exact[0][0], booking.booking_id);
  click({ controlBoardItem: 'booking', controlBoardId: booking.booking_id, controlBoardDate: '2026-09-17' });
  assert.equal(runtime.calls.exact[1][2], '2026-09-17', 'continuation segment opens the clicked day');
  assert.equal(runtime.calls.exact[1][6].showSurrounding, true);
  click({ controlBoardPlanner: 'TYRE' });
  assert.deepEqual(runtime.calls.planner, ['TYRE']);
  click({ controlBoardJump: 'TYRE' });
  assert.equal(runtime.calls.jump[0].block, 'start');
  assert.equal(runtime.calls.jump[0].inline, 'nearest');
  assert.equal(runtime.scroller.scrollLeft, 2700);
  click({ controlBoardScroll: '1' });
  assert.equal(runtime.calls.scroll[0].left, 1020);
  click({ controlBoardScroll: '-1' });
  assert.equal(runtime.calls.scroll[1].left, -1020);
});

test('actual Find command renders normalized search then reveals and focuses the matching job', () => {
  const runtime = integrationRuntime();
  runtime.search.value = ' DEMO-0001 ';
  runtime.context.findControlBoardOverviewMatch();
  assert.equal(runtime.context.app.workflowSearch, 'demo-0001');
  assert.equal(runtime.calls.jump[0].inline, 'center');
  assert.equal(runtime.calls.jump[0].block, 'nearest');
  assert.equal(runtime.calls.focus[0].preventScroll, true);
  assert.match(runtime.host.innerHTML, /matching jobs/);
});

test('search fits booking dates once and clearing restores the previous full-board range', () => {
  const runtime=integrationRuntime({controlBoardTimelineStart:'2026-10-01',controlBoardTimelineDays:28});
  runtime.search.value='DEMO-0001';
  runtime.context.renderWorkflowBoard();
  assert.equal(runtime.context.app.controlBoardTimelineStart,'2026-09-15');
  assert.equal(runtime.context.app.controlBoardTimelineDays,3);
  assert.equal(runtime.scroller.scrollLeft,0);
  runtime.click({controlBoardShift:'3'});
  assert.equal(runtime.context.app.controlBoardTimelineStart,'2026-09-18','manual date navigation is retained during a search');
  runtime.search.value=''; runtime.context.app.workflowSearch='';
  runtime.context.renderWorkflowBoard();
  assert.equal(runtime.context.app.controlBoardTimelineStart,'2026-10-01');
  assert.equal(runtime.context.app.controlBoardTimelineDays,28);
  assert.equal(runtime.scroller.scrollLeft,2700);
  assert.equal((runtime.host.innerHTML.match(/data-control-board-bay=/g)||[]).length,43);
});

test('timeline previous and next controls move by the visible date span and reset only horizontal scroll', () => {
  const runtime = integrationRuntime();
  runtime.context.renderWorkflowBoard();
  runtime.click({ controlBoardShift: '14' });
  assert.equal(runtime.context.app.controlBoardTimelineStart, '2026-09-29');
  assert.equal(runtime.scroller.scrollLeft, 0);
  assert.equal(runtime.scroller.scrollTop, 91);
  runtime.click({ controlBoardShift: '-14' });
  assert.equal(runtime.context.app.controlBoardTimelineStart, '2026-09-15');
});

test('timeline date picker changes the visible range and ignores an emptied field', () => {
  const runtime = integrationRuntime();
  runtime.context.renderWorkflowBoard();
  runtime.host.onchange({ target: { matches: selector => selector === '[data-control-board-start]', value: '2026-10-01' } });
  assert.equal(runtime.context.app.controlBoardTimelineStart, '2026-10-01');
  assert.match(runtime.host.innerHTML, /data-control-board-start value="2026-10-01"/);
  runtime.host.onchange({ target: { matches: () => true, value: '' } });
  assert.equal(runtime.context.app.controlBoardTimelineStart, '2026-10-01');
});

test('More days extends the timeline up to 56 days while preserving both scroll positions', () => {
  const runtime = integrationRuntime();
  runtime.context.renderWorkflowBoard();
  runtime.click({ controlBoardMore: '' });
  assert.equal(runtime.context.app.controlBoardTimelineDays, 28);
  assert.equal(runtime.scroller.scrollLeft, 2700);
  assert.equal(runtime.scroller.scrollTop, 91);
  runtime.click({ controlBoardMore: '' });
  runtime.click({ controlBoardMore: '' });
  runtime.click({ controlBoardMore: '' });
  assert.equal(runtime.context.app.controlBoardTimelineDays, 56);
  assert.match(runtime.host.innerHTML, /data-control-board-more disabled/);
});

test('Today returns to the current Perth date without changing the selected range length', () => {
  const runtime = integrationRuntime({ controlBoardTimelineStart: '2026-11-01', controlBoardTimelineDays: 28 });
  runtime.context.renderWorkflowBoard();
  runtime.click({ controlBoardToday: '' });
  assert.equal(runtime.context.app.controlBoardTimelineStart, '2026-09-15');
  assert.equal(runtime.context.app.controlBoardTimelineDays, 28);
});

test('outside-date reveal opens the requested range without modifying any booking record', () => {
  const runtime = integrationRuntime();
  const original = structuredClone(runtime.context.app.workshopEligibilitySnapshot);
  runtime.context.renderWorkflowBoard();
  runtime.click({ controlBoardReveal: '2026-10-19' });
  assert.equal(runtime.context.app.controlBoardTimelineStart, '2026-10-19');
  assert.equal(runtime.scroller.scrollLeft, 0);
  assert.deepEqual(runtime.context.app.workshopEligibilitySnapshot, original);
  assert.equal(runtime.calls.load.length, 0);
});

test('Find automatically reveals and focuses a matching booking beyond the visible date range', () => {
  const snapshot = fixture.emptySnapshot();
  const source = fixture.booking(1, snapshot.board.bays[0], undefined, { scheduled_start_at: '2026-10-18T23:00:00Z', scheduled_end_at: '2026-10-19T00:00:00Z' });
  snapshot.board.bookings.push(source);
  const runtime = integrationRuntime({ workshopEligibilitySnapshot: snapshot });
  runtime.search.value = source.vehicle.stock_number;
  runtime.context.renderWorkflowBoard();
  assert.ok(runtime.host.querySelector('[data-control-board-match]'), 'typing a vehicle search already fits its booking dates');
  runtime.context.findControlBoardOverviewMatch();
  assert.equal(runtime.context.app.controlBoardTimelineStart, '2026-10-19');
  assert.ok(runtime.host.querySelector('[data-control-board-match]'));
  assert.equal(runtime.calls.jump[0].inline, 'center');
  assert.equal(runtime.calls.focus[0].preventScroll, true);
  assert.equal(runtime.calls.load.length, 0);
});
