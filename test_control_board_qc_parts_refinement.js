'use strict';
const fs = require('fs');
function assert(value, message) { if (!value) throw new Error(message); }

const app = fs.readFileSync('app.js', 'utf8');
const planner = fs.readFileSync('workshop-planner.js', 'utf8');
const styles = fs.readFileSync('styles.css', 'utf8');
const lifecycle = fs.readFileSync('vehicle-lifecycle-actions.js', 'utf8');
const staging = fs.readFileSync('staging.html', 'utf8');
const migration = fs.readFileSync('supabase/staging_only/073_qc_gate_parts_eta_control_board.sql', 'utf8');

const workflowRender = app.slice(app.indexOf('function renderWorkflowBoard()'), app.indexOf('function incomingBucketForVehicle'));
assert(!workflowRender.includes('control-board-qc-row') && !workflowRender.includes('<span>QC</span>'), 'Control Board must not render QC as a station row');
assert(!staging.includes('PMB only'), 'Control Board header must not render the redundant PMB only badge');
assert(workflowRender.includes('control-board-station-list">${stationHtml}</div>'), 'Control Board list must contain canonical workshop stations only');
assert(planner.includes("workshopDateKey(selectedDate) === workshopDateKey(now)"), 'Moving red time line must be visible only when the selected planner day is today');

assert(app.includes('data-ready-for-qc=') && app.includes('move it to the QC Gate in Vehicle Locations'), 'All-green PMB row must offer a confirmed Ready for QC transition');
assert(lifecycle.includes("rpc('mark_vehicle_ready_for_qc'"), 'Ready for QC must use the protected shared RPC');
assert(migration.includes("set current_location='QC',version=version+1") && migration.includes("'mark_vehicle_ready_for_qc'"), 'Ready for QC must be versioned and audited server-side');
assert(migration.includes("coalesce(new.lifecycle_state::text,'')") && migration.includes("coalesce(old.lifecycle_state::text,'')"), 'QC/RFT trigger must compare lifecycle enums safely as text');
assert(app.includes('Sign off & print label') && app.includes('QC SIGNED OFF') && app.includes('PDC - PLACE ON WINDSCREEN'), 'QC Gate action must sign off and print a dedicated windscreen label');
assert(app.includes('vehicleInQualityControlGate(vehicle)') && app.includes('qcSignoffToRft'), 'QC sign-off must require the explicit QC Gate and retain authoritative RFT transition');

assert(!app.includes('<th>Outstanding station work</th>'), 'Parts table must not show Outstanding station work');
const partsRow = app.slice(app.indexOf('function partsQueueRowHtml'), app.indexOf('function partsIssuedStoppagePickerHtml'));
assert(!partsRow.includes('partsOutstandingStationWork') && !partsRow.includes('parts-outstanding-work'), 'Parts rows must not render the removed station-work cell');
assert(styles.includes('#parts { --pdc-row-height: 46px; }') && styles.includes('#parts .parts-queue-row > td { height: var(--pdc-row-height);'), 'Parts row height must equal the default Vehicle Locations 46px row height');
assert(app.includes('service.updatePartsEta(vehicle.__emailVehicleId, vehicle.__emailVehicleVersion, eta)'), 'Parts ETA must save through shared authority with optimistic concurrency');
assert(/setupPartsEtaCounterClock\((?:sourceRows)?\)/.test(app) && app.includes('window.setInterval(refreshPartsEtaCounters, 60000)') && app.includes('data-parts-eta-counter='), 'Parts ETA countdown must refresh while the board remains open');
assert(migration.includes('create or replace function public.update_pdc_parts_eta') && migration.includes("'parts_update'"), 'Shared Parts ETA RPC and snapshot data must be defined');

console.log('Control Board today-line, QC Gate, QC label and Parts table refinement checks passed');
