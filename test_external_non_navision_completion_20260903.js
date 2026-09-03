'use strict';
const assert = require('assert');
const fs = require('fs');

const migrationPath = 'supabase/staging_only/20260903130000_external_non_navision_completion_20260903.sql';
const sql = fs.existsSync(migrationPath) ? fs.readFileSync(migrationPath, 'utf8') : '';

assert.ok(sql, 'external/non-Navision completion migration exists');
for (const marker of [
  'cdsmnqxtyyoeoznmbidd',
  '20260903125000',
  'pdc_external_completion_receipts_20260903',
  'complete_external_rft_collection_20260903',
  'p_operator_approved boolean',
  "p_completion_type text",
  "external_non_navision_final_collection",
  "lifecycle_state='completed'",
  "current_location='Completed'",
  'cancel_workshop_booking',
  'started_booking_must_be_completed_before_external_completion',
  'idempotency_payload_mismatch',
  'external_completion_already_recorded',
  'external_completion',
  'get_pdc_email_vehicle_location_snapshot_pre_ext1300',
  'ENABLE ROW LEVEL SECURITY',
  'FORCE ROW LEVEL SECURITY',
  'PDC_EXTERNAL_COMPLETION_APPEND_ONLY',
]) assert.ok(sql.includes(marker), `migration marker: ${marker}`);

assert.ok(!sql.includes('vjdtsswhroyguxyfjdkt'), 'Production project ref is absent');
assert.ok(!/CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.reconcile_navision_delivery_/i.test(sql), 'Navision delivery functions are unchanged');
assert.ok(!/UPDATE\s+public\.navision_backend_records/i.test(sql), 'Navision backend records are not mutated');
assert.ok(!/UPDATE\s+public\.navision_board_activations/i.test(sql), 'Navision activations are not mutated');
assert.ok(!/INSERT\s+INTO\s+public\.[a-z0-9_]*(?:outbox|notification)/i.test(sql), 'No outbound queue is written');
assert.match(sql, /has_function_privilege\('authenticated','public\.complete_external_rft_collection_20260903\(uuid,integer,text,boolean,text,uuid\)','execute'\)/i);
assert.match(sql, /has_function_privilege\('anon','public\.complete_external_rft_collection_20260903\(uuid,integer,text,boolean,text,uuid\)','execute'\)/i);
assert.match(sql, /has_table_privilege\('authenticated','public\.pdc_external_completion_receipts_20260903','SELECT,INSERT,UPDATE,DELETE,TRUNCATE'\)/i);
assert.match(sql, /OR EXISTS\s*\(SELECT 1 FROM public\.navision_backend_records/i);
assert.match(sql, /v\.rft_collected_at IS NULL/i);
assert.match(sql, /action='collected'/i);
assert.match(sql, /v\.dealer_transit_closed_at IS NOT NULL/i);
assert.match(sql, /v\.delivered_to_dealer_date IS NOT NULL/i);
assert.match(sql, /visible_on_board=false/i);
assert.match(sql, /active_workshop_booking_id=NULL/i);

console.log('external/non-Navision completion 20260903 contract passed');
