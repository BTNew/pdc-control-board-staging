'use strict';
const assert = require('assert');
const fs = require('fs');
const sql = fs.readFileSync('supabase/staging_only/20260830093000_pdc_lifecycle_history.sql', 'utf8');
const repairSql = fs.readFileSync('supabase/staging_only/20260830094000_pdc_lifecycle_history_rpc_repair.sql', 'utf8');
const yardHoldSql = fs.readFileSync('supabase/staging_only/20260830095000_pdc_lifecycle_history_yard_hold_transition.sql', 'utf8');
const syntheticScopeSql = fs.readFileSync('supabase/staging_only/20260830101000_pdc_lifecycle_history_synthetic_scope_repair.sql', 'utf8');
const app = fs.readFileSync('app.js', 'utf8');
const service = require('./pdc-email-vehicle-location-service.js');

for (const marker of [
  "20260830093000",
  "pdc_lifecycle_history",
  "20260830094000",
  "pdc_lifecycle_history_rpc_repair",
  'pdc_vehicle_lifecycle_history_events_82000',
  'first_reached_yard_hold_at_utc',
  'first_entered_pmb_at_utc',
  'first_became_rft_at_utc',
  'elapsed_yard_hold_to_pmb_seconds',
  'elapsed_pmb_to_rft_seconds',
  'elapsed_yard_hold_to_rft_seconds',
  "Australia/Perth",
  'pdc_lifecycle_history_append_only_82000',
  'pdc_capture_vehicle_lifecycle_transition_82000',
  'pdc_vehicle_lifecycle_history_one_latch_82000',
  'get_pdc_vehicle_lifecycle_history_82000',
  'correct_pdc_vehicle_lifecycle_history_82000',
  'disable_pdc_vehicle_lifecycle_history_82000',
  'FORCE ROW LEVEL SECURITY',
  'Production sentinel/data/remotes are excluded',
]) assert((sql + repairSql + yardHoldSql + syntheticScopeSql).includes(marker), `migration contains ${marker}`);

const backfill = sql.slice(sql.indexOf('-- Backfill only immutable'), sql.indexOf('CREATE OR REPLACE FUNCTION public.pdc_capture_vehicle'));
assert(!/date_to_pmb|date_to_rft|delivered_to_dealer_date|eta_to_kewdale|current_location\s+IN/i.test(backfill), 'backfill does not infer from mutable dates, ETA or current location');
assert(backfill.includes('vehicle_movements') && backfill.includes('audit_events') && backfill.includes('pdc_final_pdc_lifecycle_receipts_700'));
assert(sql.includes("upper(coalesce(OLD.current_location,''))<>'RFT'") && sql.includes("NEW.lifecycle_state::text='rft'") && sql.includes('NEW.qc_completed_at IS NOT NULL'), 'RFT latch is QC-to-RFT only');
assert(sql.includes("upper(coalesce(OLD.current_location,'')) IN('YH','IT')") && sql.includes("upper(coalesce(NEW.current_location,''))='PMB'"), 'PMB latch is canonical YH/IT to PMB only');
assert(sql.includes("event_kind='latch'") && sql.includes('ON CONFLICT DO NOTHING'), 'latches are one-time and replay-safe');
assert(sql.includes('p_dealer_code') && sql.includes('dealer_scope_denied') && sql.includes('pdc_auditor_user_dealer_scopes'), 'read RPC has dealer scope checks');
assert(repairSql.includes('v_actor_email') && repairSql.includes('PDC_940_EXACT_STAGING_930_PREDECESSOR_REQUIRED'), 'RPC repair is bound to the exact applied predecessor');
assert(yardHoldSql.includes('PDC_950_EXACT_STAGING_940_PREDECESSOR_REQUIRED') && yardHoldSql.includes('mark_vehicle_yard_hold_82000'), 'canonical Yard Hold API is bound to the exact applied predecessor');
assert(syntheticScopeSql.includes('PDC_1010_EXACT_STAGING_1000_PREDECESSOR_REQUIRED') && syntheticScopeSql.includes('synthetic'), 'synthetic acceptance scope is explicit and bound to its predecessor');
assert(!/GRANT\s+(SELECT|ALL).*pdc_vehicle_lifecycle_history_events_82000/i.test(sql), 'history table has no direct table grant');

const mapped = service.mapServerVehicle({
  id: '11111111-1111-4111-8111-111111111111', stock_number: 'STK-82000', job_card_number: 'JC-82000',
  lifecycle_history: {
    vehicle_id: '11111111-1111-4111-8111-111111111111',
    first_reached_yard_hold_at: '2026-08-01T00:00:00.123456Z',
    first_entered_pmb_at: '2026-08-03T12:00:00.654321Z',
    first_became_rft_at: '2026-08-05T00:00:00.000001Z',
    elapsed_yard_hold_to_pmb_days: 2.499999,
    elapsed_pmb_to_rft_days: 1.5,
    elapsed_yard_hold_to_rft_days: 3.999999,
    evidence_state: 'complete', missing_evidence: [],
  },
});
assert.strictEqual(mapped.firstReachedYardHoldAt, '2026-08-01T00:00:00.123456Z');
assert.strictEqual(mapped.firstEnteredPmbAt, '2026-08-03T12:00:00.654321Z');
assert.strictEqual(mapped.firstBecameRftAt, '2026-08-05T00:00:00.000001Z');
assert.strictEqual(mapped.lifecycleHistory.evidence_state, 'complete');
assert.strictEqual(mapped.lifecycleHistory.elapsed_pmb_to_rft_days, 1.5);

assert(app.includes('lifecycleHistoryHtml') && app.includes('Yard Hold → PMB') && app.includes('PMB → RFT') && app.includes('Yard Hold → RFT'));
assert(!app.includes('return parseDateAU(kewdaleEtaValue(vehicle));'), 'completed PMB history never falls back to Kewdale ETA');
assert(app.includes('Partial / Unknown') && app.includes('Australia/Perth'));
console.log('Lifecycle history 82000 contract passed');
