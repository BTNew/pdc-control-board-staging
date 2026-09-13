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
const names = ['workshopMapSnapshotBookingToLegacyRow', 'workshopSortBookingsClosest', 'workshopPlanVehicleIdentity', 'workshopResolveBookingSelection', 'workshopSearchMatches', 'workshopCurrentSearchLookup', 'workshopMapSearchBookings', 'workshopLookupSearchVehicle', 'workshopLoadSearchBookings', 'workshopBookingSearchStatus', 'workshopBookingSearchMeta', 'workshopSearchResultsHtml', 'workshopSelectSearchBooking', 'workshopSelectUnbookedSearchVehicle', 'workshopRefreshDedicatedDate'];
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
names.push('workshopSearchMatchRows');
vm.createContext(context);
vm.runInContext(names.map(extract).join('\n'), context);
async function main() {
  assert.match(context.workshopSearchResultsHtml('88001038'), /Finding bookings/);
  assert.doesNotMatch(context.workshopSearchResultsHtml('88001038'), /Select unbooked vehicle/);
  await context.workshopLoadSearchBookings('88001038');
  const matches = context.workshopSearchMatches('88001038');
  assert.equal(matches.length, 1);
  assert.equal(matches[0].bookings.length, 5, 'all five station/date bookings found despite empty selected-day snapshot');
  assert.equal(matches[0].candidateAvailable, false, 'already-booked station never falsely offered in unallocated lane');
  const html = context.workshopSearchResultsHtml('88001038');
  for (const row of bookedRows) assert.ok(html.includes('data-workshop-search-booking-id="' + row.booking_id + '"'));
  assert.doesNotMatch(html, /Select unbooked vehicle/);
  assert.equal(snapshot.bookings.length, 0, 'lookup never mutates scoped board snapshot');
  const before = calls;
  await context.workshopSelectSearchBooking('hoist', 'shared:' + vehicleId);
  assert.equal(calls, before + 1, 'selection rechecks latest authorized booking position');
  assert.equal(route, 'HOIST');
  assert.equal(state.date, '2026-09-16');
  assert.equal(state.detailManualOpen, false);
  assert.equal(state.detailCollapsedForSelection, true);
  assert.equal(context.app.pendingWorkshopBookingLink.bookingId, 'hoist');
  assert.equal(context.app.pendingWorkshopBookingLink.vehicleId, vehicleId);
  assert.equal(context.app.pendingWorkshopBookingLink.search, true);
  context.window.__activeWorkshopPlannerStage = 'HOIST';
  route = '';
  await context.workshopSelectSearchBooking('hoist', 'shared:' + vehicleId);
  assert.equal(route, '');
  assert.equal(scope.stageCode, 'HOIST');
  assert.equal(scope.dateFrom, '2026-09-16');
  assert.ok(rendered > 0);

  response = { ok: true, vehicleId, bookings: [row('hoist', 'HOIST', '2026-09-22T09:00:00+08:00', 3)] };
  await context.workshopSelectSearchBooking('hoist', 'shared:' + vehicleId);
  assert.equal(state.date, '2026-09-22', 'moved booking navigates to newly verified date');
  response = { ok: false, error: 'permission_denied' };
  state.bookingSearchLookup = null;
  await context.workshopLoadSearchBookings('88001038');
  assert.match(context.workshopSearchResultsHtml('88001038'), /Bookings could not be checked/);
  assert.doesNotMatch(context.workshopSearchResultsHtml('88001038'), /Select unbooked vehicle/);
  await context.workshopSelectSearchBooking('hoist', 'shared:' + vehicleId);
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
  const resolutions = [];
  response = { ok: true, vehicleId, bookings: bookedRows };
  service.lookupVehicleBookings = () => new Promise(done => resolutions.push(done));
  const earlierSelection = context.workshopSelectSearchBooking('hoist', 'shared:' + vehicleId);
  const latestSelection = context.workshopSelectSearchBooking('tyre', 'shared:' + vehicleId);
  resolutions[1](response);
  assert.equal(await latestSelection, true);
  resolutions[0](response);
  assert.equal(await earlierSelection, false, 'older click cannot override latest selected job');
  assert.equal(route, 'TYRE');
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
  assert.equal(context.workshopSearchMatches(state.search)[0].bookings.length,5,
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
  console.log('Workshop search navigation: PASS (cross-date/station, moved booking, exact identity, read failures, stale requests, no detail expansion).');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
