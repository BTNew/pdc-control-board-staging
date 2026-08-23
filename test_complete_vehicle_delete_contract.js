'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = __dirname;
const migration = path.join(root, 'supabase', 'staging_only', '20260823170000_323_admin_complete_vehicle_delete.sql');
assert.ok(fs.existsSync(migration), 'complete-delete staging migration exists');
const sql = fs.readFileSync(migration, 'utf8');
const lower = sql.toLowerCase();

for (const marker of [
  'begin;',
  'pdc_monitor_staging_guard()',
  'pdc_staging_environment_sentinel',
  'pdc_production_environment_sentinel',
  'security definer',
  'pdc_admin_complete_vehicle_delete',
  'p_vehicle_id uuid',
  'p_confirmation_stock text',
  'p_reason text',
  'p_idempotency_key text',
  'pg_try_advisory_xact_lock',
  'idempotency_conflict',
  'pdc_vehicle_reset_receipts_323',
  'replay fence',
]) assert.ok(lower.includes(marker.toLowerCase()), `migration contains ${marker}`);

assert.ok(!/\bon delete\s+cascade\b/i.test(sql), 'migration does not add or use CASCADE');
assert.ok(!/disable\s+trigger/i.test(sql), 'migration never disables triggers');
assert.ok(!/before_data|after_data|vehicle_snapshot/i.test(sql), 'reset receipt does not retain old operational payload');
assert.ok(lower.includes('unknown_vehicle_dependency') || lower.includes('unknown_fk_dependency'), 'unknown dependency drift fails closed');
assert.ok(lower.includes('pdc_email_source_claims'), 'email source replay claims are preserved');
assert.ok(lower.includes('pdc_email_replay_fences'), 'email replay fences are preserved');
assert.ok(lower.includes('pdc_auditor_telegram_instructions_225'), 'Telegram replay instructions are preserved');
assert.ok(lower.includes('atomic'), 'migration documents atomic rollback semantics');

console.log('Complete vehicle delete SQL contract passed.');
