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
