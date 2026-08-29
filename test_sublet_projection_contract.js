'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = __dirname;
const app = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const service = fs.readFileSync(path.join(root, 'pdc-email-vehicle-location-service.js'), 'utf8');
const styles = fs.readFileSync(path.join(root, 'styles.css'), 'utf8');
const migration = fs.readFileSync(path.join(root, 'supabase/staging_only/20260830090000_sublet_auditor_read_ledger.sql'), 'utf8');

assert(app.includes('canonicalSubletBooking'), 'Vehicle Locations must consume canonical Sublet bookings');
assert(app.includes('incoming-card-sublet'), 'Vehicle Locations card must render the Sublet pill');
assert(app.includes('incoming-sublet-booking-detail'), 'Vehicle Locations card must render canonical Sublet detail');
assert(styles.includes('.incoming-card-sublet'), 'Vehicle Locations Sublet pill must have compact card styling');
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

console.log('Sublet projection/read contract tests passed');
