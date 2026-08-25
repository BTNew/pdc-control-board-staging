'use strict';

const assert = require('assert');
const fs = require('fs');
const app = fs.readFileSync('app.js', 'utf8');
const service = fs.readFileSync('pdc-email-vehicle-location-service.js', 'utf8');
const migration = fs.readFileSync('supabase/staging_only/20260826140000_399_qc_finalization_photo_rft_salesperson_outbox.sql', 'utf8');

assert.ok(migration.includes('update_pdc_sublet_booking_provider_399'), 'staging migration adds a bounded canonical provider RPC');
assert.ok(migration.includes('pdc_sublet_provider_update_receipts_399'), 'provider reassignment has immutable receipts');
assert.ok(migration.includes('p_booking_id') && migration.includes('p_expected_version'), 'provider reassignment is booking UUID/version bound');
assert.ok(service.includes('PDC_SUBLET_PROVIDER_UPDATE_RPC') && service.includes('updateSubletBookingProvider'), 'browser service exposes canonical provider reassignment');
assert.ok(app.includes('subletProviderRecordByName') && app.includes('updateSubletBookingProvider'), 'provider UI resolves active provider reference and uses canonical RPC');
assert.ok(app.includes('No active canonical Sublet booking exists') && app.includes('Multiple active Sublet bookings exist'), 'zero and multiple canonical booking states fail closed precisely');
assert.ok(app.includes('row.__subletBookingId') && app.includes('bookings.length !== 1'), 'summary provider mutation requires exact booking identity');
assert.ok(!/vehicleId, current\.__subletBookingVersion, SUBLET_SERVER_FIELD_MAP\[field\], cleanValue/.test(app), 'authoritative Sublet provider/date flow no longer calls vehicle-scoped legacy writer');

console.log('Canonical Sublet provider mutation contract passed.');
