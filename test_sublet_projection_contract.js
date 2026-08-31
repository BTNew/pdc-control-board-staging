'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = __dirname;
const app = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const service = fs.readFileSync(path.join(root, 'pdc-email-vehicle-location-service.js'), 'utf8');
const styles = fs.readFileSync(path.join(root, 'styles.css'), 'utf8');
const migration = fs.readFileSync(path.join(root, 'supabase/staging_only/20260830090000_sublet_auditor_read_ledger.sql'), 'utf8');
const volatilityRepair = fs.readFileSync(path.join(root, 'supabase/staging_only/20260830091000_sublet_auditor_read_ledger_volatility_repair.sql'), 'utf8');
const castRepair = fs.readFileSync(path.join(root, 'supabase/staging_only/20260830092000_sublet_auditor_read_ledger_uuid_text_cast_repair.sql'), 'utf8');
const vehicleRenderer = app.slice(app.indexOf('function incomingVehicleDetailRow'), app.indexOf('const SALES_PREPARATION_FIELDS'));

assert(app.includes('canonicalSubletBooking'), 'Vehicle Locations must consume canonical Sublet bookings');
assert(app.includes('canonicalActiveSubletBooking'), 'Sublet booking state must use the canonical active-booking projection');
assert(app.includes('subletBooked'), 'Vehicle Locations must project active Sublet booking state into the workgroup strip');
assert(!vehicleRenderer.includes('incoming-card-sublet'), 'Vehicle/model column must not render a duplicate Sublet status badge');
assert(app.includes('incoming-sublet-booking-detail'), 'Vehicle Locations card must render canonical Sublet detail');
assert(app.includes("allRows.filter(vehicle => subletBookingState(vehicle) === 'booked')"), 'Sublet summary must exclude cancelled-only rows from booked count');
assert(styles.includes('.incoming-work-check.is-ordered'), 'Sublet booked workgroup must reuse the orange ordered styling');
assert(service.includes("PDC_SUBLET_AUDIT_READ_RPC = 'get_pdc_sublet_audit_ledgers'"), 'service must expose the exact Sublet ledger RPC');
assert(service.includes('readSubletAuditLedgers'), 'service must expose the authenticated ledger read bridge');
for (const fragment of [
  "p_vehicle_id: String(vehicleId || '')",
  "p_stock_number: String(stockNumber || '').trim()",
  "p_job_card_number: String(jobCardNumber || '').trim()",
]) assert(service.includes(fragment), `service request binding missing: ${fragment}`);
for (const fragment of [
  "current_user<>'postgres'",
  "project_ref='cdsmnqxtyyoeoznmbidd'",
  "get_pdc_sublet_audit_ledgers(uuid,text,text)",
  'pdc_sublet_booking_instances',
  'pdc_sublet_booking_instance_history',
  'pdc_sublet_email_update_receipts',
  'pdc_auditor_actor_scope()',
  "r.dealer_code=v_dealer",
  "GRANT EXECUTE ON FUNCTION public.get_pdc_sublet_audit_ledgers(uuid,text,text)",
  "TO authenticated",
  'Direct SELECT on immutable Sublet ledgers remains denied',
]) assert(migration.includes(fragment), `migration contract missing: ${fragment}`);
assert(!/GRANT\s+SELECT\s+ON\s+TABLE\s+public\.pdc_sublet_/i.test(migration), 'migration must not grant direct Sublet table SELECT');
assert(!/CREATE FUNCTION public\.(?:set_pdc_vehicle_work_states|repair_.*sublet)/i.test(migration), 'projection-only closure must not add a repair mutation');
assert(volatilityRepair.includes("ALTER FUNCTION public.get_pdc_sublet_audit_ledgers(uuid,text,text) VOLATILE"), 'FOR SHARE read bridge must be volatile');
assert(volatilityRepair.includes("version='20260830090000'"), 'volatility repair must be append-only after migration 900');
assert(castRepair.includes("version='20260830091000'"), 'UUID/text cast repair must be append-only after migration 901');
assert(castRepair.includes('r.id::text=v_vehicle.source_record_id'), 'dealer binding must use an explicit UUID/text-safe comparison');

console.log('Sublet projection/read contract tests passed');
