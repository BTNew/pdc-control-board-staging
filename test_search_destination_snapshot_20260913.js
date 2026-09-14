'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, 'workshop-planner.js'), 'utf8');
const start = source.indexOf('  const navigationScope = window.__workshopDataService?.getScope?.();');
const end = source.indexOf('  if (state.focusedBookingMode && state.focusedBookingId)', start);
assert(start > 0 && end > start);
const renderer = source.slice(start, end);
const vehicleId = '11111111-1111-4111-8111-111111111111';
const otherId = '22222222-2222-4222-8222-222222222222';
const bookingId = '33333333-3333-4333-8333-333333333333';
const intent = { bookingId, vehicleId, stage: 'HOIST', date: '2026-09-22', search: true, focused: false };
const exact = { id: bookingId, sharedVehicleId: vehicleId, vehicleKey: 'canonical-12238276', stage: 'HOIST', status: 'planned', vehicle: { stock: '12238276' } };
function render({trusted = true, scope = {stageCode:'HOIST',dateFrom:'2026-09-22',dateTo:'2026-09-22'}, plans = [exact]} = {}) {
  const state = {selectedPlanId:'', detailManualOpen:true, searchOpen:true};
  const app = {pendingWorkshopBookingLink:{...intent}};
  const context = {state, app, pendingBookingLink:app.pendingWorkshopBookingLink, plans, stage:'HOIST',
    window:{__workshopDataService:{getScope:()=>scope,getTrustedSnapshot:()=>trusted?{bookings:plans}:null}},
    normalizePmbStage:v=>v, workshopSaveView:()=>{}, workshopResolveFocusedBooking:()=>{throw Error('Search must not open focused detail');}};
  vm.runInNewContext(renderer,context);
  return context;
}
for (const options of [{trusted:false},{scope:{stageCode:'FITTING',dateFrom:'2026-09-22',dateTo:'2026-09-22'}},{scope:{stageCode:'HOIST',dateFrom:'2026-09-21',dateTo:'2026-09-21'}}]) {
  const result=render(options);
  assert(result.app.pendingWorkshopBookingLink, 'search waits for the fresh destination snapshot');
  assert.equal(result.state.selectedPlanId, '');
}
for (const plans of [[{...exact,sharedVehicleId:otherId}],[],[{...exact,status:'completed'}]]) {
  const result=render({plans});
  assert.equal(result.app.pendingWorkshopBookingLink, null);
  assert.equal(result.state.selectedPlanId, '');
  assert.equal(result.state.highlightVehicleKey, '');
  assert.match(result.state.bookingNavigationError, /changed or is no longer active/);
}
const result=render();
assert.equal(result.app.pendingWorkshopBookingLink,null);
assert.equal(result.state.selectedPlanId,bookingId);
assert.equal(result.state.highlightVehicleKey,exact.vehicleKey);
assert.equal(result.state.searchHighlightPlanId,bookingId);
assert.equal(result.state.detailManualOpen,false);
assert.equal(result.state.detailCollapsedForSelection,true);
assert.equal(result.state.searchOpen,false);
console.log('Search destination snapshot: PASS (waits for trusted exact scope; rejects changed vehicle, removed/completed booking; highlights exact canonical booking without detail expansion).');

// Reproduce a vehicle-card link arriving while the destination response is
// delayed. Use the real service, including the interval where onSnapshot has
// received rows but getTrustedSnapshot still withholds an in-flight request.
const { createWorkshopDataService } = require('./workshop-data-service.js');
const focusedStart = source.indexOf('function workshopResolveFocusedBooking(');
const focusedEnd = source.indexOf('\nfunction workshopResetFocusedBooking', focusedStart);
assert(focusedStart > 0 && focusedEnd > focusedStart);
const focusedResolver = source.slice(focusedStart, focusedEnd);

async function focusedDestinationRegression() {
  const focusedIntent = { ...intent, search: false, focused: true };
  const focusedBooking = { ...exact, sharedBookingId: bookingId, startAt: '2026-09-22T07:00:00+08:00' };
  const destination = { stageCode: 'HOIST', dateFrom: '2026-09-22', dateTo: '2026-09-22' };
  const previous = { stageCode: 'FITTING', dateFrom: '2026-09-14', dateTo: '2026-09-14' };
  const focusedState = { selectedPlanId: '', focusedBookingMode: false, focusedBookingError: '' };
  const focusedApp = { pendingWorkshopBookingLink: { ...focusedIntent } };
  let resolveDestination;
  let callbackRenders = 0;
  let rpcCount = 0;
  let service;
  function renderFocused() {
    if (!focusedApp.pendingWorkshopBookingLink) return;
    const trusted = service.getTrustedSnapshot();
    const context = {
      state: focusedState, app: focusedApp, pendingBookingLink: focusedApp.pendingWorkshopBookingLink,
      plans: trusted?.bookings || [], stage: 'HOIST',
      window: { __workshopDataService: service }, normalizePmbStage: value => value,
      workshopSaveView() {}, workshopEntryDate: entry => entry.startAt.slice(0, 10),
      workshopVehicle: key => trusted?.vehicles?.find(vehicle => vehicle.key === key),
      workshopStageJobLines: vehicle => vehicle.operationLines,
    };
    vm.runInNewContext(focusedResolver + '\n' + renderer, context);
  }
  service = createWorkshopDataService({
    config: { workshop: { sharedData: true } }, scope: previous,
    getAccessToken: () => 'fixture-token', getRole: () => 'operator',
    onSnapshot: () => { callbackRenders += 1; renderFocused(); },
    client: { rpc: async (_token, name, params) => {
      assert.equal(name, 'get_station_workshop_snapshot');
      rpcCount += 1;
      if (rpcCount === 1) return { ok: true, body: { revision: 1, vehicles: [], bookings: [] } };
      assert.equal(params.p_stage_code, destination.stageCode);
      assert.equal(params.p_date_from, destination.dateFrom);
      return new Promise(resolve => { resolveDestination = resolve; });
    } },
  });
  await service.loadSnapshot('previous_station');
  renderFocused();
  assert(focusedApp.pendingWorkshopBookingLink, 'trusted previous station must not consume the vehicle-card link');
  assert.equal(focusedState.focusedBookingError, '');

  const loading = service.setScope(destination);
  assert.deepEqual(service.getScope(), destination, 'requested scope changes before destination rows arrive');
  assert.equal(service.getTrustedSnapshot(), null);
  renderFocused();
  assert(focusedApp.pendingWorkshopBookingLink, 'focused intent survives the delayed destination snapshot');
  assert.equal(focusedState.focusedBookingMode, false);
  assert.equal(focusedState.focusedBookingError, '');
  resolveDestination({ ok: true, body: {
    revision: 2, bookings: [focusedBooking],
    vehicles: [{ key: exact.vehicleKey, operationLines: [{ source: 'authenticated-operation-line', hours: 1 }] }],
  } });
  await loading;
  assert.equal(callbackRenders, 2);
  assert(focusedApp.pendingWorkshopBookingLink, 'onSnapshot must not consume intent before in-flight authority settles');
  assert.equal(focusedState.focusedBookingError, '');
  renderFocused();
  assert.equal(focusedApp.pendingWorkshopBookingLink, null);
  assert.equal(focusedState.focusedBookingMode, true);
  assert.equal(focusedState.focusedBookingError, '');
  assert.equal(focusedState.focusedBookingId, bookingId);
  assert.equal(focusedState.selectedPlanId, bookingId);

  // A same-scope refresh retains the old rows for display. They must not be
  // mistaken for current destination authority by a newly clicked card link.
  focusedApp.pendingWorkshopBookingLink = { ...focusedIntent };
  const refreshing = service.loadSnapshot('reconnect');
  assert(service.getLastSnapshot(), 'display snapshot retained during refresh');
  assert.equal(service.getTrustedSnapshot(), null);
  renderFocused();
  assert(focusedApp.pendingWorkshopBookingLink, 'retained stale rows must not consume a focused link');
  assert.equal(focusedState.focusedBookingError, '');
  resolveDestination({ ok: true, body: { revision: 3, vehicles: [], bookings: [] } });
  await refreshing;
  renderFocused();
  assert.equal(focusedApp.pendingWorkshopBookingLink, null);
  assert.equal(focusedState.selectedPlanId, '');
  assert.match(focusedState.focusedBookingError, /booking_not_in_scoped_snapshot/,
    'a booking truly missing from the settled destination still fails safely');
  service.destroy();
  console.log('Focused destination snapshot: PASS (delayed scope, retained refresh rows, callback authority, exact booking and settled missing booking).');
}
focusedDestinationRegression().catch(error => { console.error(error); process.exitCode = 1; });
