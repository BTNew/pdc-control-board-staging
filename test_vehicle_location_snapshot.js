/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const forward = fs.readFileSync('supabase/migrations/20261019142000_vehicle_location_snapshot_helpers.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261019142000_vehicle_location_snapshot_helpers.down.sql', 'utf8');

function body(sql) {
  const start = sql.indexOf('AS $function$\n');
  const end = sql.indexOf('\n$function$;');
  assert.ok(start > 0 && end > start);
  return sql.slice(start + 'AS $function$\n'.length, end);
}
function count(text, needle) {
  return text.split(needle).length - 1;
}

test('the location snapshot calls each station helper once and can be restored exactly', () => {
  const next = body(forward);
  const previous = body(down);
  assert.equal(count(next, 'pdc_bus_private.operation_station('), 2);
  assert.equal(count(next, 'pdc_tune_approved_operation_source_20260912('), 1);
  assert.equal(count(next, 'pdc_is_pre_delivery_20260910('), 1);
  assert.equal(count(next, 'pdc_department138_station_20260917('), 1);
  assert.equal(count(previous, 'pdc_bus_private.operation_station('), 5);
  assert.equal(count(previous, 'pdc_tune_approved_operation_source_20260912('), 4);
  assert.match(forward, /b10abea382e64c014e7e8577832712d7/);
  assert.match(forward, /09f6a5c2b02dbf9ae993b80d05c69c98/);
  assert.match(down, /09f6a5c2b02dbf9ae993b80d05c69c98/);
  assert.match(down, /b10abea382e64c014e7e8577832712d7/);
  assert.match(next, /row_value\|\|/);
  assert.equal(next.includes('workshop_bookings'), false);
  assert.equal(forward.includes('vjdtsswhroyguxyfjdkt'), false);
  assert.equal(down.includes('supabase/migrations'), false);
  assert.equal(fs.existsSync('supabase/migrations/20261019142000_vehicle_location_snapshot_helpers.down.sql'), false);
  assert.match(forward, /navision_backend_records_vehicle_idx/);
});
