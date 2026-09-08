'use strict';

const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const source = fs.readFileSync('app.js', 'utf8');
const vehicleId = '11111111-1111-4111-8111-111111111111';
const bookingId = '22222222-2222-4222-8222-222222222222';

function sourceSlice(startMarker, endMarker) {
  const start = source.indexOf(startMarker);
  const end = source.indexOf(endMarker, start);
  assert.ok(start >= 0 && end > start, `${startMarker} seam must be extractable`);
  return source.slice(start, end);
}

const contractContext = {
  cleanNavisionText: value => String(value ?? '').trim(),
};
vm.createContext(contractContext);
vm.runInContext(sourceSlice('function vehicleWorkshopDetailRequestDealerCode', '\nfunction vehicleWorkshopDisplayLineHours'), contractContext);

const complete = {
  vehicle_id: vehicleId,
  vehicle_version: 7,
  generated_at: '2026-09-08T08:00:00.000Z',
  requirements: [],
  bookings: [],
  line_adjustments: [],
};
assert.strictEqual(contractContext.vehicleWorkshopDetailResponse(complete, vehicleId).ok, true, 'complete shared Workshop DTO is ready');

const unavailable = contractContext.vehicleWorkshopDetailResponse({
  ok: false,
  code: 'vehicle_not_in_dealer_scope',
  data: { vehicle_id: vehicleId, dealer_code: '37047' },
}, vehicleId);
assert.strictEqual(unavailable.ok, false, 'structured unavailable response never becomes ready');
assert.match(unavailable.message, /outside.*scope/i, 'structured unavailable response remains truthful');

assert.strictEqual(
  contractContext.vehicleWorkshopDetailResponse({ ...complete, bookings: undefined }, vehicleId).ok,
  false,
  'top-level partial response is unavailable',
);

const failures = [];
function redExpectation(label, callback) {
  try {
    callback();
  } catch (error) {
    failures.push(`${label}: ${error.message}`);
  }
}

redExpectation('missing vehicle version', () => {
  const { vehicle_version: _missing, ...partial } = complete;
  assert.strictEqual(
    contractContext.vehicleWorkshopDetailResponse(partial, vehicleId).ok,
    false,
    'a response without the concurrency version must not enable authoritative controls',
  );
});

redExpectation('partial booking row', () => {
  const partial = {
    ...complete,
    bookings: [{ booking_id: bookingId }],
  };
  assert.strictEqual(
    contractContext.vehicleWorkshopDetailResponse(partial, vehicleId).ok,
    false,
    'a booking without stage, status, version, and schedule must not be presented as a successful booking',
  );
});

const renderContext = {
  app: {
    vehicleWorkshopDetailCache: new Map([[vehicleId, {
      status: 'error',
      message: 'The shared Workshop response was incomplete.',
      detail: { ...complete, bookings: [{ booking_id: 'STALE-BOOKING' }] },
    }]]),
    vehicleWorkshopHoursBatchMessage: '',
  },
  vehicleWorkshopDetailCanonicalId: () => vehicleId,
  vehicleWorkshopGroups: (_vehicle, detail) => {
    assert.strictEqual(detail, null, 'error state must not reuse stale cached detail');
    return [];
  },
  vehicleWorkshopCanEditLines: () => false,
  vehicleWorkshopStationHtml: () => 'STALE-BOOKING',
  vehicleWorkshopRemovalReceiptHtml: () => '',
  escapeHtml: value => String(value),
};
vm.createContext(renderContext);
vm.runInContext(sourceSlice('function renderVehicleWorkshopWorkPage', '\nasync function loadVehicleWorkshopDetail'), renderContext);
const unavailableHtml = renderContext.renderVehicleWorkshopWorkPage({});
assert.match(unavailableHtml, /Booking data unavailable/, 'error state is visibly unavailable');
assert.doesNotMatch(unavailableHtml, /STALE-BOOKING|Not booked/, 'error state shows neither stale booking data nor fake not-booked success');

if (failures.length) {
  console.error('Shared Workshop response contract regression: RED');
  failures.forEach(failure => console.error(`- ${failure}`));
  process.exitCode = 1;
} else {
  console.log('Shared Workshop response contract regression: PASS');
}
