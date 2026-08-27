'use strict';
const assert = require('assert');
const fs = require('fs');

const app = fs.readFileSync('app.js', 'utf8');
const service = fs.readFileSync('pdc-email-vehicle-location-service.js', 'utf8');
const css = fs.readFileSync('styles.css', 'utf8');
const sql = fs.readFileSync('supabase/staging_only/20260826173000_412_stoppage_rft_transport_workflow.sql', 'utf8');
const repairs = [
  '20260826174000_413_rft_email_ambiguity_repair.sql',
  '20260826175000_414_collected_workshop_status.sql',
  '20260826180000_415_synthetic_stoppage_actor_qualification.sql',
  '20260826181000_416_synthetic_started_stoppage_setup.sql',
  '20260826182000_417_synthetic_started_snapshot_setup.sql',
  '20260826183000_418_hidden_stoppage_acceptance_fallback.sql',
  '20260826184000_419_hidden_stoppage_deleted_status.sql',
  '20260826185000_420_hidden_stoppage_visible_bridge.sql',
  '20260826190000_421_rft_shared_vehicle_snapshot.sql',
].map(file => fs.readFileSync(`supabase/staging_only/${file}`, 'utf8')).join('\n');

assert.match(sql, /clear_vehicle_stoppage_412/);
assert.match(sql, /return_work_to_queue\(b\.id,b\.version,NULL/);
assert.match(sql, /stoppage_cleared_to_unallocated/);
assert.match(sql, /book_rft_transport_412/);
assert.match(sql, /mandatory-rft-transport-salesperson-email-412/);
assert.match(sql, /'completed_work',after_j->'completed_work'/);
assert.match(sql, /'build_times',after_j->'build_times'/);
assert.match(sql, /'stoppages',after_j->'stoppages'/);
assert.match(sql, /'photo_attachment',after_j->'photo'/);
assert.match(sql, /delivery_status<>'pending'/);
assert.match(sql, /collect_rft_transport_412/);
assert.match(sql, /started_booking_must_be_completed_before_collection/);
assert.match(sql, /cancel_workshop_booking\(b\.id,b\.version,'Vehicle collected from RFT'/);
assert.match(sql, /pmb_stage=NULL,pmb_bay_stage=NULL,pmb_bay_number=NULL,active_workshop_booking_id=NULL/);
assert.match(sql, /transport_booking_required_use_412/);
assert.match(sql, /PDC_412_STAGING_HEAD_OR_DEPENDENCY_MISMATCH/);
assert.match(repairs, /actor_email text:=/);
assert.match(repairs, /workshop_status=''queued''/);
assert.match(repairs, /registry\.actor_email=v_actor_email/);
assert.match(repairs, /public\.stop_workshop_work/);
assert.match(repairs, /public\.workshop_write_history/);
assert.match(repairs, /HERMES-TEST-420-visible-bridge/);
assert.match(repairs, /v\.lifecycle_state IN\(''active'',''rft''\)/);
assert.match(sql, /REVOKE ALL ON TABLE public\.pdc_rft_transport_salesperson_outbox_412 FROM public,anon,authenticated,service_role/);

assert.match(service, /PDC_STOPPAGE_CLEAR_RPC = 'clear_vehicle_stoppage_422'/);
assert.match(service, /PDC_RFT_TRANSPORT_BOOK_RPC = 'book_rft_transport_412'/);
assert.match(service, /PDC_RFT_TRANSPORT_COLLECT_RPC = 'collect_rft_transport_412'/);
assert.match(service, /clearVehicleStoppage, setPmbStoppage, bookRftTransport, collectRftTransport/);
assert.match(service, /mapped\.rftTransportBookedAt = row\.rft_transport_booked_at/);

assert.match(app, /data-clear-priority-stoppage/);
assert.match(app, /Why is this stoppage being cleared\?/);
assert.match(app, /Booked on trucking website/);
assert.match(app, /data-rft-transport-booked-key/);
assert.match(app, /bookRftTransport700\(vehicle\.__emailVehicleId/);
assert.match(app, /creates the mandatory salesperson email with completed work, dates, build times, stoppages and the QC photo/);
assert.match(app, /collectRftTransport700\(vehicle\.__emailVehicleId/);
assert.match(app, /Book the vehicle on the trucking company website first/);
assert.match(app, /\|\| filter === 'open'/);
assert.match(app, /All uncollected transport handovers/);
assert.doesNotMatch(app.slice(app.indexOf('async function markRftVehicleCollected'), app.indexOf('function bindRftCollectedInputs')), /saveVehicleEdits|offerSalespersonChangeEmail|rftCollectVehicle/);
assert.match(css, /\.fix-first-clear/);
assert.match(css, /\.rft-transport-checks/);

console.log('stoppage/RFT transport 412 contract passed');
