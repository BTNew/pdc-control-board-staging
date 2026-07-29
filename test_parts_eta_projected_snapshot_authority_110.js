'use strict';
const fs = require('fs');
function assert(value, message) { if (!value) throw new Error(message); }
const path = 'supabase/staging_only/110_restore_parts_eta_snapshot_authority.sql';
assert(fs.existsSync(path), 'Migration 110 must restore shared Parts ETA snapshot authority after migration 109 replaced the snapshot');
const sql = fs.readFileSync(path, 'utf8');
for (const token of [
  'create or replace function public.get_pdc_email_vehicle_location_snapshot()',
  "'operation_line_id',ol.operation_line_id",
  "'estimated_hours',ol.estimated_hours",
  "'estimated_hours_source',ol.estimated_hours_source",
  "'parts_update',coalesce",
  "'worst_eta',pu.worst_eta",
  "'previous_worst_eta'",
  "'sublet_booking',coalesce",
  "'provider_names'",
]) assert(sql.includes(token), `Migration 110 is missing ${token}`);
assert(sql.includes("where v.deleted_at is null and v.lifecycle_state='active' and v.visible_on_board"), 'Snapshot must retain active visible lifecycle scope');
assert(sql.includes("exists(select 1 from public.pdc_authenticated_email_import_receipts"), 'Snapshot must retain authenticated-email source scope');
const service = fs.readFileSync('pdc-email-vehicle-location-service.js', 'utf8');
assert(service.includes('mapped.pdcPartsPreviousWorstEta = partsUpdate.previous_worst_eta ||'), 'Projected rows must map the previous authoritative Parts ETA for countdown/email continuity');
const app = fs.readFileSync('app.js', 'utf8');
assert(app.includes("vehicle.__emailVehicleServerAuthoritative === true") && app.includes('service.updatePartsEta(vehicle.__emailVehicleId, vehicle.__emailVehicleVersion, eta)'), 'Projected Parts ETA writes must stay canonical-ID and version bound');
assert(!/vehicle\.__emailVehicleServerAuthoritative[\s\S]{0,900}saveVehicleEdits\(key/.test(app.slice(app.indexOf('async function updateVehiclePartsWorstEta'), app.indexOf('function draftPartsEtaSalesEmail'))), 'Projected Parts ETA writes must not fall back to browser-local persistence');
console.log('Projected Parts ETA snapshot persistence/countdown authority migration 110 regression checks passed');
