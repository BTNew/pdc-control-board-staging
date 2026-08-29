'use strict';

const assert = require('assert');
const { mapServerVehicle } = require('./pdc-email-vehicle-location-service');

function row(status = 'active') {
  return {
    id: 'b3c293fb-0453-56da-86a6-9c3511cc2fe7',
    permanent_vehicle_id: 'PDC-NAV-B3C293FB045356DA86A6',
    stock_number: '13080534',
    job_card_number: 'J139125425',
    customer_name: 'MGM BULK PTY LTD',
    vehicle_description: 'Prado 2.8L 48V Dsl Wgn 8AT',
    current_location: 'Other',
    version: 11,
    work_items: [{ work_key: 'sublet', required: false, completed: false }],
    sublet_booking: {},
    sublet_active_count: status === 'active' ? 1 : 0,
    sublet_bookings: [{
      booking_id: '475efd0a-1cb9-4f3a-bf02-483afe6ff5ac',
      vehicle_id: 'b3c293fb-0453-56da-86a6-9c3511cc2fe7',
      vehicle_version: 10,
      provider_id: '4cbd486c-78c2-42ce-987a-99d45d1eeaf4',
      provider_name: 'Customer Sublet',
      provider_email: 'tbc',
      out_date: '2026-09-05',
      expected_return_date: '2026-09-12',
      status,
      version: 1,
      updated_at: '2026-08-29T01:48:15.396963+00:00',
    }],
  };
}

const active = mapServerVehicle(row('active'));
assert.strictEqual(active.__emailVehicleId, 'b3c293fb-0453-56da-86a6-9c3511cc2fe7');
assert.strictEqual(active.__emailVehicleVersion, 11);
assert.strictEqual(active.pdcRequiresSublet, true);
assert.strictEqual(active.pdcCompleteSublet, false);
assert.strictEqual(active.pdcSubletBookings.length, 1);
assert.strictEqual(active.pmbSubletProvider, 'Customer Sublet');
assert.strictEqual(active.pmbSubletBookingDate, '2026-09-05');
assert.strictEqual(active.pmbSubletExpectedReturnDate, '2026-09-12');

const returned = mapServerVehicle(row('returned'));
assert.strictEqual(returned.pdcRequiresSublet, true);
assert.strictEqual(returned.pdcCompleteSublet, true);

const cancelled = mapServerVehicle({ ...row('cancelled'), sublet_active_count: 0 });
assert.strictEqual(cancelled.pdcRequiresSublet, false);
assert.strictEqual(cancelled.pdcCompleteSublet, false);

console.log('Sublet canonical booking requirement projection tests passed');
