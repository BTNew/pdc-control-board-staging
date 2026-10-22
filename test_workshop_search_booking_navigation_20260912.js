/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, 'workshop-planner.js'), 'utf8');
function extract(name) {
  const match = new RegExp('(?:async )?function ' + name + '\\(').exec(source);
  assert.ok(match, name);
  const tail = source.slice(match.index);
  const next = /\n(?:async )?function \w+\(/.exec(tail);
  return next ? tail.slice(0, next.index) : tail;
}
const names = ['workshopBayText', 'workshopMapSnapshotBookingToLegacyRow', 'workshopSortBookingsClosest', 'workshopPlanVehicleIdentity', 'workshopResolveBookingSelection', 'workshopSearchMatches', 'workshopCurrentSearchLookup', 'workshopMapSearchBookings', 'workshopLookupSearchVehicle', 'workshopLoadSearchBookings', 'workshopBookingSearchStatus', 'workshopBookingSearchMeta', 'workshopSearchResultsHtml', 'workshopSelectSearchBooking', 'workshopSelectUnbookedSearchVehicle', 'workshopRefreshDedicatedDate'];
const vehicleId = '11111111-1111-4111-8111-111111111111';
const vehicle = { id: vehicleId, sharedVehicleId: vehicleId, vehicleKey: '88001038', stockNumber: '88001038', jobcard: 'TEST-JC-1038', customerName: 'Example Workshop Customer', model: 'Example Vehicle' };
function row(id, stage, date, bay = 1, status = 'planned') {
  return { booking_id: id, booking_version: 1, stage_code: stage, bay_number: bay, status, scheduled_start_at: date, scheduled_end_at: new Date(new Date(date).getTime() + 3600000).toISOString(), default_duration_minutes: 60 };
}
const bookedRows = [row('fitting', 'FITTING', '2026-09-12T08:31:00+08:00', 1, 'started'), row('hoist', 'HOIST', '2026-09-16T07:00:00+08:00'), row('fab', 'FABRICATION', '2026-09-17T07:00:00+08:00', 2), row('elec', 'ELECTRICAL', '2026-09-17T13:00:00+08:00'), row('tyre', 'TYRE', '2026-09-21T07:00:00+08:00')];
let snapshot = { revision: 10, vehicles: [vehicle], work_items: [], bookings: [], outstanding_candidates: [{ vehicle_id: vehicleId, stage_code: 'ELECTRICAL', schedule_enabled: true, existing_booking: true }] };
const state = { search: '88001038', stage: 'ELECTRICAL', date: '2026-09-12' };
let response = { ok: true, vehicleId, bookings: bookedRows };
let calls = 0;
let route = '';
let scope = null;
let rendered = 0;
const service = { getTrustedSnapshot: () => snapshot, lookupVehicleBookings: async (id, dealer) => { assert.equal(id, vehicleId); assert.equal(dealer, 'PMG'); calls++; return response; }, setScope: value => { scope = value; } };
const context = {
  app: { data: [vehicle], workshopEligibilitySnapshot: { candidates: [] } },
  window: { __workshopDataService: service, __activeWorkshopPlannerStage: 'ELECTRICAL', PDC_SUPABASE_CONFIG: {}, clearTimeout() {} },
  document: { querySelector: () => null },
  WORKSHOP_STAGE_SEQUENCE: ['BUS4X4', 'FITTING', 'ELECTRICAL', 'FABRICATION', 'HOIST', 'TINT', 'TYRE'],
  workshopState: () => state,
  cleanNavisionText: value => String(value || '').trim(),
  normalizePmbStage: value => String(value || '').trim().toUpperCase(),
  workshopSnapshotVehicleToPlannerRow: value => value,
  workshopVehicleSearchText: value => [value.stockNumber, value.jobcard, value.customerName, value.model].join(' ').toLowerCase(),
  workshopSharedModeActive: () => true,
  workshopSharedVehicleRef: ({ sharedVehicleId }) => ({ vehicleId: sharedVehicleId }),
  vehicleKey: value => value.vehicleKey,
  displayStockNumber: value => value.stockNumber,
  vehicleKeyNumber: () => '',
  vehicleJobcardNumber: value => value.jobcard,
  vehicleCustomerName: value => value.customerName,
  displayVehicle: value => value.model,
  workshopSearchRank: () => 0,
  statusCategory: () => 'pmb',
  vehicleWorkshopDetailRequestDealerCode: () => 'PMG',
  workshopExactDurationHours: value => value,
  workshopDefaultBookingHours: () => 1,
  parseIsoTimestamp: value => { const date = new Date(value); return Number.isFinite(date.getTime()) ? date : null; },
  workshopEntryDate: value => new Intl.DateTimeFormat('en-CA', { timeZone: 'Australia/Perth', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date(value.startAt)),
  workshopEntryEnd: value => new Date(value.endAt),
  workshopLoadPlans: () => [],
  workshopSaveView: () => {},
  renderWorkshopPlanner: () => { rendered++; },
  openWorkshopPlannerForStage: stage => { route = stage; },
  escapeHtml: value => String(value ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;'),
  pmbStageLabel: value => value,
  workshopRefreshSearchResults: () => {},
};
names.push('workshopSearchMatchRows', 'workshopReturnedQueuePlans');
vm.createContext(context);
vm.runInContext(names.map(extract).join('\n'), context);
async function main() {
  assert.match(context.workshopSearchResultsHtml('88001038'), /Finding bookings/);
  assert.doesNotMatch(context.workshopSearchResultsHtml('88001038'), /Select unbooked vehicle/);
  await context.workshopLoadSearchBookings('88001038');
  const matches = context.workshopSearchMatches('88001038');
  assert.equal(matches.length, 1);
  assert.equal(matches[0].bookings.length, 1, 'only selected station booking found across dates despite empty selected-day snapshot');
  assert.equal(matches[0].candidateAvailable, false, 'already-booked station never falsely offered in unallocated lane');
  const html = context.workshopSearchResultsHtml('88001038');
  for (const row of bookedRows) assert.equal(html.includes('data-workshop-search-booking-id="' + row.booking_id + '"'),row.stage_code===state.stage);
  assert.equal(await context.workshopSelectSearchBooking('hoist','shared:'+vehicleId),false,'stale other-station selection cannot navigate away');
  assert.doesNotMatch(html, /Select unbooked vehicle/);
  assert.equal(snapshot.bookings.length, 0, 'lookup never mutates scoped board snapshot');
  const before = calls;
  await context.workshopSelectSearchBooking('elec', 'shared:' + vehicleId);
  assert.equal(calls, before + 1, 'selection rechecks latest authorized booking position');
  assert.equal(route, '');
  assert.equal(state.date, '2026-09-17');
  assert.equal(state.detailManualOpen, false);
  assert.equal(state.detailCollapsedForSelection, true);
  assert.equal(context.app.pendingWorkshopBookingLink.bookingId, 'elec');
  assert.equal(context.app.pendingWorkshopBookingLink.vehicleId, vehicleId);
  assert.equal(context.app.pendingWorkshopBookingLink.search, true);
  context.window.__activeWorkshopPlannerStage = 'ELECTRICAL';
  route = '';
  await context.workshopSelectSearchBooking('elec', 'shared:' + vehicleId);
  assert.equal(route, '');
  assert.equal(scope.stageCode, 'ELECTRICAL');
  assert.equal(scope.dateFrom, '2026-09-17');
  assert.ok(rendered > 0);

  response = { ok: true, vehicleId, bookings: [row('elec', 'ELECTRICAL', '2026-09-22T09:00:00+08:00', 3)] };
  await context.workshopSelectSearchBooking('elec', 'shared:' + vehicleId);
  assert.equal(state.date, '2026-09-22', 'moved booking navigates to newly verified date');
  response = { ok: false, error: 'permission_denied' };
  state.bookingSearchLookup = null;
  await context.workshopLoadSearchBookings('88001038');
  assert.match(context.workshopSearchResultsHtml('88001038'), /Bookings could not be checked/);
  assert.doesNotMatch(context.workshopSearchResultsHtml('88001038'), /Select unbooked vehicle/);
  await context.workshopSelectSearchBooking('elec', 'shared:' + vehicleId);
  assert.match(state.bookingNavigationError, /could not be checked/);

  response = { ok: true, vehicleId, bookings: [row('unallocated', 'FITTING', '2026-09-12T08:00:00+08:00', null, 'queued'), row('completed-unallocated','FITTING','2026-09-01T08:00:00+08:00',null,'completed'), ...bookedRows] };
  assert.equal(context.workshopMapSearchBookings(response, vehicle).length, 5, 'unallocated record cannot mask actual bookings or become Bay 0 choice');
  snapshot = { ...snapshot, revision: 11 };
  assert.equal(context.workshopCurrentSearchLookup('88001038'), null, 'snapshot refresh invalidates cached search');
  let resolve;
  service.lookupVehicleBookings = () => new Promise(done => { resolve = done; });
  const pending = context.workshopLoadSearchBookings('88001038');
  state.search = 'changed query';
  resolve(response);
  await pending;
  assert.notEqual(context.workshopCurrentSearchLookup(state.search)?.status, 'ready', 'late previous query never becomes current results');
  service.lookupVehicleBookings = async () => response;
  state.search = '88001038'; state.bookingSearchLookup = null;
  await context.workshopLoadSearchBookings('88001038');
  context.window.__workshopDataService = { ...service };
  assert.equal(context.workshopCurrentSearchLookup('88001038'), null, 'route/service replacement invalidates cached authority');

  context.window.__workshopDataService = service;
  const savedSnapshot = snapshot;
  snapshot = null;
  const nullCalls = calls;
  state.bookingSearchLookup = { query: '88001038', service, snapshot: null, status: 'ready', matches: new Map() };
  assert.equal(context.workshopCurrentSearchLookup('88001038'), null, 'null snapshot cannot authorize cached results');
  await context.workshopLoadSearchBookings('88001038');
  assert.equal(calls, nullCalls, 'no lookup starts without trusted snapshot');
  assert.match(context.workshopSearchResultsHtml('88001038'), /temporarily unavailable/);
  snapshot = savedSnapshot;
  state.bookingSearchLookup = null;
  await context.workshopLoadSearchBookings('88001038');
  service.getLastSnapshot = () => snapshot;
  const trustedSnapshot = service.getTrustedSnapshot;
  service.getTrustedSnapshot = () => null;
  const duringRefresh = context.workshopSearchResultsHtml('88001038');
  assert.doesNotMatch(duringRefresh, /temporarily unavailable/);
  assert.match(duringRefresh, /data-workshop-search-booking-id="elec"/);
  const refreshCalls = calls;
  await context.workshopLoadSearchBookings('88001038');
  assert.equal(calls, refreshCalls, 'a post-drop refresh keeps the last search and does not start another lookup');
  service.getTrustedSnapshot = trustedSnapshot;
  delete service.getLastSnapshot;
  const resolutions = [];
  response = { ok: true, vehicleId, bookings: [...bookedRows,row('elec-next','ELECTRICAL','2026-09-21T07:00:00+08:00')] };
  service.lookupVehicleBookings = () => new Promise(done => resolutions.push(done));
  const earlierSelection = context.workshopSelectSearchBooking('elec', 'shared:' + vehicleId);
  const latestSelection = context.workshopSelectSearchBooking('elec-next', 'shared:' + vehicleId);
  resolutions[1](response);
  assert.equal(await latestSelection, true);
  resolutions[0](response);
  assert.equal(await earlierSelection, false, 'older click cannot override latest selected job');
  assert.equal(route, '');
  assert.equal(state.date, '2026-09-21');

  const pendingCode = source.slice(source.indexOf("if (pendingBookingLink && normalizePmbStage"), source.indexOf('  if (state.focusedBookingMode && state.focusedBookingId)'));
  assert.match(pendingCode, /pendingBookingLink\.vehicleId/);
  assert.match(pendingCode, /state\.detailManualOpen = false/);
  assert.match(pendingCode, /scope\?\.dateFrom === pendingBookingLink\.date/);
  assert.match(source, /stage && searchNavigationReady/);
  assert.match(extract('workshopScrollToHighlightedVehicle'), /pendingWorkshopBookingLink\?\.search === true\) return/);
  assert.match(extract('workshopScrollToHighlightedVehicle'), /const target = planId \? bookingTarget : vehicleTarget/);
  service.lookupVehicleBookings = async () => ({ok:true,vehicleId,bookings:bookedRows});
  snapshot = {revision:20,vehicles:[],work_items:[],bookings:[],outstanding_candidates:[]};
  context.app.data = [{...vehicle,__emailVehicleServerAuthoritative:true,__emailVehicleId:vehicleId}];
  context.workshopSharedVehicleRef = () => null;
  state.search='88001038'; state.bookingSearchLookup=null;
  const originalMatcher=context.workshopSearchMatches;
  context.workshopSearchMatches=(query,plans)=>originalMatcher(query,plans);
  await context.workshopLoadSearchBookings(state.search);
  assert.equal(context.workshopSearchMatches(state.search)[0].bookings.length,1,
    'authenticated Board-only identity resolves outside station snapshot even with two-argument presentation wrapper');
  assert.equal(snapshot.bookings.length,0);
  assert.equal(context.workshopSearchMatches(state.search)[0].candidateAvailable,false,
    'read-only Board identity does not create scheduling candidate authority');
  context.app.data = [{...vehicle,__emailVehicleId:vehicleId}];
  state.bookingSearchLookup=null;
  let unauthorizedReads=0;
  service.lookupVehicleBookings=async()=>{unauthorizedReads++;throw Error('Untrusted projection may not authorize a lookup');};
  await context.workshopLoadSearchBookings(state.search);
  assert.equal(unauthorizedReads,0,'untrusted UUID/stock alias cannot authorize the read');
  assert.match(context.workshopSearchResultsHtml(state.search),/Bookings could not be checked/);
  snapshot = {revision:21,vehicles:[vehicle],work_items:[],bookings:[],outstanding_candidates:[]};
  context.app.data=[vehicle];
  context.workshopSharedVehicleRef=({sharedVehicleId})=>({vehicleId:sharedVehicleId});
  state.stage='ELECTRICAL';
  state.bookingSearchLookup={query:state.search,service,snapshot,status:'ready',matches:new Map([[`shared:${vehicleId}`,{ok:true,bookings:[]}]])};
  context.workshopLoadPlans=()=>[{id:'returned-existing',sharedVehicleId:vehicleId,vehicleKey:vehicle.vehicleKey,stage:'ELECTRICAL',sharedStatus:'queued',sharedBayId:'',bay:0,hours:88.31666666666666,status:'planned'}];
  const returnedHtml=context.workshopSearchResultsHtml(state.search);
  assert.match(returnedHtml,/data-workshop-select-returned-plan="returned-existing"/,
    'returned canonical reservation stays selectable when read-only booking search omits queued work');
  assert.doesNotMatch(returnedHtml,/Scheduling unavailable|data-workshop-search-unbooked-identity/,
    'reuse existing reservation rather than offering duplicate scheduling');
  const savedStage = state.stage;
  const savedSearch = state.search;
  const savedData = context.app.data;
  const savedPlans = context.workshopLoadPlans;
  const savedTrusted = service.getTrustedSnapshot;
  const fittingVehicle = { ...vehicle, vehicleKey: '13091177', stockNumber: '13091177' };
  const fittingSnapshot = {
    revision: 30,
    vehicles: [fittingVehicle],
    work_items: [],
    bookings: [],
    outstanding_candidates: [{ vehicle_id: vehicleId, stage_code: 'FITTING', schedule_enabled: true, existing_booking: false }],
  };
  state.stage = 'FITTING';
  state.search = '13091177';
  context.app.data = [fittingVehicle];
  context.workshopLoadPlans = () => [];
  service.getLastSnapshot = () => fittingSnapshot;
  service.getTrustedSnapshot = () => null;
  state.bookingSearchLookup = {
    query: '13091177',
    service,
    snapshot: fittingSnapshot,
    status: 'ready',
    matches: new Map([['shared:' + vehicleId, { ok: true, bookings: [] }]]),
  };
  const duringDrop = context.workshopSearchResultsHtml('13091177');
  assert.doesNotMatch(duringDrop, /No booking found/);
  assert.match(duringDrop, /data-workshop-search-drag-vehicle="shared:/);
  state.bookingSearchLookup = { query: '13091177', service, snapshot: { revision: 29 }, status: 'ready', matches: new Map() };
  const finding = context.workshopSearchResultsHtml('13091177');
  assert.match(finding, /Finding bookings/);
  assert.doesNotMatch(finding, /No booking found/);
  state.stage = savedStage;
  state.search = savedSearch;
  context.app.data = savedData;
  context.workshopLoadPlans = savedPlans;
  delete service.getLastSnapshot;
  service.getTrustedSnapshot = savedTrusted;
  state.bookingSearchLookup = null;
  console.log('Workshop search navigation and returned reservation selection: PASS.');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
