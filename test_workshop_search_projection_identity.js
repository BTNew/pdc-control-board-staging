/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('workshop-planner.js', 'utf8');
function extract(name) {
  const match = new RegExp('(?:async )?function ' + name + '\\(').exec(source);
  const tail = source.slice(match.index), next = /\n(?:async )?function \w+\(/.exec(tail);
  return next ? tail.slice(0, next.index) : tail;
}
const id = '11111111-1111-4111-8111-111111111111';
function fixture({ eligible = true, station = false } = {}) {
  const vehicle = { id, sharedVehicleId: id, vehicleKey: 'TEST', stock: 'TEST' };
  const snapshot = { vehicles: station ? [vehicle] : [], outstanding_candidates: [] };
  const state = { stage: 'HOIST', search: 'TEST' }, calls = [];
  const service = { getTrustedSnapshot: () => snapshot, lookupVehicleBookings: async () => {},
    lookupVehicleBookingsBatch: async requests => {
      calls.push(requests);
      return { ok: true, results: requests.map(r => ({ ...r, ok: true, bookings: [] })) };
    } };
  const c = { app: { data: [vehicle], workshopEligibilitySnapshot: { candidates: eligible ? [{ vehicle, stage_code: 'HOIST', disabled_reason: 'estimated_duration_missing' }] : [] } },
    window: { __workshopDataService: service, PDC_SUPABASE_CONFIG: { dealerCode: '14450' } },
    workshopState: () => state, workshopLoadPlans: () => [], workshopSharedModeActive: () => true,
    cleanNavisionText: String, workshopSnapshotVehicleToPlannerRow: v => ({ ...v, __workshopStationSnapshotAuthoritative: true }),
    workshopVehicleSearchText: v => v.stock.toLowerCase(), vehicleKey: v => v.vehicleKey,
    workshopSharedVehicleRef: () => station ? { vehicleId: id } : { ok: false, error: 'vehicle_identity_not_found' },
    workshopSortBookingsClosest: rows => rows, normalizePmbStage: v => v,
    workshopReturnedQueuePlans: () => [], workshopSearchRank: () => 0,
    statusCategory: () => 'pmb', displayStockNumber: v => v.stock,
    vehicleWorkshopDetailRequestDealerCode: () => '14450', workshopMapSearchBookings: r => r.bookings };
  vm.createContext(c);
  vm.runInContext(['workshopCurrentSearchLookup', 'workshopSearchMatchRows', 'workshopLoadSearchBookings'].map(extract).join('\n'), c);
  return { c, calls, state };
}
test('eligibility projection outside the station retains its canonical identity for the scoped read', async () => {
  const f = fixture();
  await f.c.workshopLoadSearchBookings('TEST');
  assert.equal(f.calls.length, 1);
  assert.equal(f.calls[0][0].vehicleId, id);
  assert.equal(f.state.bookingSearchLookup.matches.get('shared:' + id).ok, true);
  assert.equal(f.c.workshopSearchMatchRows('TEST', [], { includeUnmatched: true })[0].candidateAvailable, false,
    'Read identity alone cannot grant scheduling authority');
  const result = f.c.workshopSearchMatchRows('TEST', [])[0];
  assert.equal(result.candidateDisabledReason, 'estimated_duration_missing');
  assert.equal(result.candidateHasWork, true, 'Known work remains visible with its real missing-hours reason');
});
test('an arbitrary legacy UUID does not become authoritative through the search pool', async () => {
  const f = fixture({ eligible: false });
  await f.c.workshopLoadSearchBookings('TEST');
  assert.equal(f.calls.length, 0);
  assert.equal(f.state.bookingSearchLookup.matches.get('legacy:TEST').ok, false);
});
test('a later eligibility projection of the same vehicle does not lose station identity', async () => {
  const f = fixture({ station: true });
  await f.c.workshopLoadSearchBookings('TEST');
  assert.equal(f.calls.length, 1);
  assert.equal(f.calls[0][0].vehicleId, id);
});
test('canonical station projection wins over a legacy duplicate resolved to the same vehicle', async () => {
  const f = fixture({ station: true, eligible: false });
  f.c.app.data = [{ id: 'old-local-row', vehicleKey: 'TEST', stock: 'TEST', dealer_code: 'CUSTOMER_ACCOUNT' }];
  f.c.vehicleWorkshopDetailRequestDealerCode = v => v.dealer_code === 'CUSTOMER_ACCOUNT' ? '' : '14450';
  await f.c.workshopLoadSearchBookings('TEST');
  assert.equal(f.calls.length, 1, 'Legacy display fields cannot suppress the canonical scoped request');
  assert.equal(f.calls[0][0].vehicleId, id);
  assert.equal(f.state.bookingSearchLookup.matches.get('shared:' + id).ok, true);
});
