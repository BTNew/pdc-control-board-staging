'use strict';
const assert = require('assert');
const fs = require('fs');

const sql = fs.readFileSync('supabase/staging_only/107_authenticated_operation_line_identity.sql', 'utf8').toLowerCase();
for (const required of [
  "project_ref='cdsmnqxtyyoeoznmbidd'",
  "'operation_line_id',ol.operation_line_id",
  "'source:'||u.operation_line_id::text",
  "having count(*)=1",
  "a.line_key='operation:'||upper(btrim(u.operation_no))",
  'not exists (',
  "'authenticated_operation_line_identity_107'",
  "'bookings_changed',false",
  "'parts_changed',false",
  "'completion_changed',false",
  'create or replace function public.get_pdc_email_vehicle_location_snapshot()',
  'grant execute on function public.get_pdc_email_vehicle_location_snapshot() to authenticated',
]) assert(sql.includes(required), `Migration 107 is missing ${required}`);
assert(!sql.includes('update public.workshop_bookings'), 'Identity repair must not mutate bookings');
assert(!sql.includes('update public.vehicle_work_items'), 'Identity repair must not mutate work completion');
assert(!sql.includes('update public.vehicle_parts_updates'), 'Identity repair must not mutate Parts');

const service = fs.readFileSync('pdc-email-vehicle-location-service.js', 'utf8');
assert(service.includes("operation_line_id: String(item?.operation_line_id || '').trim().toLowerCase()"), 'Snapshot mapper must preserve durable operation-line UUIDs');
const app = fs.readFileSync('app.js', 'utf8');
assert(app.indexOf("const operationLineId = cleanNavisionText(line.operation_line_id || '')") < app.indexOf("const operationNo = cleanNavisionText(line.operation_no || '').toUpperCase()"), 'Durable UUID identity must take precedence over document-local OP number');

console.log('Authenticated operation-line durable identity migration contract passed');
