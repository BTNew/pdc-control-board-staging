'use strict';
const assert = require('assert');
const fs = require('fs');
const sqlPath = 'supabase/staging_only/20260827101000_700_authoritative_pdc_lifecycle.sql';
const sql = fs.existsSync(sqlPath) ? fs.readFileSync(sqlPath, 'utf8') : '';
const app = fs.readFileSync('app.js', 'utf8');
const service = fs.readFileSync('pdc-email-vehicle-location-service.js', 'utf8');
const html = fs.readFileSync('index.html', 'utf8');

assert.ok(sql, 'final lifecycle successor migration exists');
for (const marker of [
  'pdc_final_pdc_lifecycle_receipts_700',
  'finalize_pdc_qc_to_rft_700',
  'book_rft_transport_700',
  'collect_rft_transport_700',
  'reconcile_navision_delivery_700',
  "current_location='Collected'",
  "lifecycle_state='completed'",
  'Delivered - At Dealer',
  'dealer_transit_started_at',
  'dealer_transit_duration_seconds',
  'pdc_qc_salesperson_update_outbox_399',
]) assert.ok(sql.includes(marker), `migration marker: ${marker}`);
assert.match(service, /finalizeQcToRft700/);
assert.match(service, /bookRftTransport700/);
assert.match(service, /collectRftTransport700/);
assert.match(service, /reconcileNavisionDelivery700/);
assert.match(service, /pdc_final_pdc_lifecycle_receipts_700/);
assert.match(app, /vehicleInCollectedState/);
assert.match(app, /renderCollectedVehicles/);
assert.match(app, /Delivered - At Dealer/);
assert.match(html, /data-view="collected"/);
assert.match(html, /id="collected-vehicles-content"/);
console.log('final authoritative PDC lifecycle 700 contract passed');
